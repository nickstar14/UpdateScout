import Foundation
import CryptoKit
import AppKit

/// Installs a Sparkle app update in place, doing the same verification Sparkle
/// itself does before replacing a bundle. Every check below is a hard failure:
/// if we cannot prove the download is the vendor's own signed build, we do not
/// touch the installed app.
///
///  1. The archive's Ed25519 signature (`sparkle:edSignature`) must verify
///     against the installed app's own `SUPublicEDKey`.
///  2. The unpacked bundle must pass `codesign --verify --deep --strict`.
///  3. If the installed app has a Team ID, the update's must match it — so a
///     validly signed *but different* app can never replace it. (Ad-hoc-signed
///     apps have no Team ID; there step 1 is the proof of provenance.)
enum SparkleInstaller {
    struct Plan {
        let appURL: URL
        let enclosureURL: URL
        let edSignature: String
        let publicEDKey: String
    }

    /// Everything needed to install, or nil if this app can't be updated safely
    /// (no public key in the bundle, or no signature in the appcast).
    static func plan(appPath: String, latest: AppcastParser.Latest) -> Plan? {
        let appURL = URL(fileURLWithPath: appPath)
        guard let data = FileManager.default.contents(
                atPath: appURL.appendingPathComponent("Contents/Info.plist").path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let publicKey = plist["SUPublicEDKey"] as? String,
              let signature = latest.edSignature,
              let enclosure = latest.enclosureURL.flatMap(URL.init(string:))
        else { return nil }
        return Plan(appURL: appURL, enclosureURL: enclosure,
                    edSignature: signature, publicEDKey: publicKey)
    }

    static func install(_ plan: Plan, progress: @escaping @Sendable (String) -> Void) async throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("UpdateScout-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        // 1. Download, reporting bytes as they arrive.
        progress("Downloading…")
        let archive = workDir.appendingPathComponent(plan.enclosureURL.lastPathComponent)
        try await ProgressDownloader.download(from: plan.enclosureURL, to: archive) { written, total in
            let done = ByteCountFormatter.string(fromByteCount: written, countStyle: .file)
            if total > 0 {
                let all = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                progress("Downloading… \(done) / \(all) (\(Int(Double(written) / Double(total) * 100))%)")
            } else {
                progress("Downloading… \(done)")
            }
        }

        // 2. Verify the signature before unpacking anything.
        progress("Verifying signature…")
        let archiveData = try Data(contentsOf: archive)
        guard verifyEdDSA(data: archiveData, signatureB64: plan.edSignature, publicKeyB64: plan.publicEDKey) else {
            throw UpdateScoutError.commandFailed(
                "signature check",
                output: "The download's signature does not match this app's public key. Nothing was installed.")
        }

        // 3. Unpack.
        progress("Unpacking…")
        let unpackDir = workDir.appendingPathComponent("unpacked")
        try fm.createDirectory(at: unpackDir, withIntermediateDirectories: true)
        let newApp = try await unpack(archive: archive, into: unpackDir)

        // 4. Validate the new bundle's own code signature and signing identity.
        // Strip extended attributes first: unpacking can leave quarantine flags
        // and AppleDouble/Finder-info detritus, which makes codesign fail with
        // "resource fork, Finder information, or similar detritus not allowed"
        // even though the signature itself is fine. Signatures cover file
        // contents, not xattrs, so clearing them doesn't weaken this check.
        progress("Checking code signature…")
        _ = try? await Shell.run("/usr/bin/xattr", ["-cr", newApp.path])
        let verify = try await Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
        guard verify.status == 0 else {
            throw UpdateScoutError.commandFailed("codesign --verify", output: verify.combined)
        }
        // If the installed app has a Team ID, the update must carry the same one
        // — that stops a validly signed app from a *different* developer (or an
        // unsigned build) taking its place. Ad-hoc/unsigned apps have no Team ID
        // to compare; there the Ed25519 check above is the proof of provenance,
        // which is the same guarantee Sparkle itself relies on.
        let newTeam = try await teamIdentifier(of: newApp)
        let oldTeam = try await teamIdentifier(of: plan.appURL)
        if let oldTeam, newTeam != oldTeam {
            throw UpdateScoutError.commandFailed(
                "identity check",
                output: "The update is signed by a different developer (\(newTeam ?? "unsigned") vs \(oldTeam)). Nothing was installed.")
        }

        // 5. Quit the app if it's running, then swap the bundle.
        let bundleID = try? bundleIdentifier(of: plan.appURL)
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID ?? "")
        let wasRunning = !running.isEmpty
        if wasRunning {
            progress("Quitting \(plan.appURL.lastPathComponent)…")
            running.forEach { $0.terminate() }
            for _ in 0..<50 where NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID ?? "").contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        progress("Installing…")
        try await swap(newApp: newApp, into: plan.appURL, workDir: workDir, progress: progress)
        // Clear the download quarantine flag so the app opens normally; its own
        // signature was already verified above.
        _ = try? await Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", plan.appURL.path])

        if wasRunning {
            progress("Relaunching…")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: plan.appURL, configuration: config)
        }
    }

    /// Replace the installed bundle with the verified new one.
    ///
    /// The plain user-level move covers apps the user owns. Apps installed by a
    /// pkg are often root-owned (AppCleaner, most vendor installers), and macOS
    /// also protects app bundles behind App Management — both surface as
    /// "couldn't be moved because you don't have permission". In that case redo
    /// the swap with admin rights, through the same password dialog the rest of
    /// the app uses, preserving the original owner so the app stays as it was.
    private static func swap(newApp: URL, into target: URL, workDir: URL,
                             progress: @escaping @Sendable (String) -> Void) async throws {
        let fm = FileManager.default
        let backup = workDir.appendingPathComponent("previous.app")
        do {
            try fm.moveItem(at: target, to: backup)
            do {
                try fm.moveItem(at: newApp, to: target)
                return
            } catch {
                try? fm.moveItem(at: backup, to: target)   // roll back
                throw error
            }
        } catch {
            progress("Needs your password to replace this app…")
            let attrs = try? fm.attributesOfItem(atPath: target.path)
            let owner = (attrs?[.ownerAccountName] as? String) ?? NSUserName()
            let group = (attrs?[.groupOwnerAccountName] as? String) ?? "staff"
            func q(_ path: String) -> String {
                "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            }
            // Move aside, move in, restore ownership; roll back on any failure.
            let command = """
            /bin/mv \(q(target.path)) \(q(backup.path)) && \
            { /bin/mv \(q(newApp.path)) \(q(target.path)) && \
              /usr/sbin/chown -R \(owner):\(group) \(q(target.path)); } || \
            { /bin/mv \(q(backup.path)) \(q(target.path)); exit 1; }
            """
            let result = try await Shell.runPrivileged(command, tag: "install")
            guard result.status == 0, fm.fileExists(atPath: target.path) else {
                throw UpdateScoutError.commandFailed(
                    "replace \(target.lastPathComponent)",
                    output: result.combined.isEmpty
                        ? "The app could not be replaced, even with administrator rights. Nothing was changed."
                        : result.combined)
            }
        }
    }

    // MARK: - Helpers

    /// Sparkle signs the archive's raw bytes with Ed25519; SUPublicEDKey is the
    /// matching raw public key, both base64.
    static func verifyEdDSA(data: Data, signatureB64: String, publicKeyB64: String) -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyB64),
              let sigData = Data(base64Encoded: signatureB64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return false }
        return key.isValidSignature(sigData, for: data)
    }

    /// Unpack a .zip (ditto), tarball (bsdtar handles xz/gz/bz2), or .dmg
    /// (hdiutil), and return the .app inside it.
    private static func unpack(archive: URL, into dir: URL) async throws -> URL {
        let name = archive.lastPathComponent.lowercased()
        if name.hasSuffix(".tar.xz") || name.hasSuffix(".tar.gz") || name.hasSuffix(".tar.bz2")
            || name.hasSuffix(".txz") || name.hasSuffix(".tgz") || name.hasSuffix(".tar") {
            let result = try await Shell.run("/usr/bin/tar", ["-xf", archive.path, "-C", dir.path])
            guard result.status == 0 else {
                throw UpdateScoutError.commandFailed("tar -xf", output: result.combined)
            }
            return try findApp(in: dir)
        }
        switch archive.pathExtension.lowercased() {
        case "zip":
            let result = try await Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, dir.path])
            guard result.status == 0 else {
                throw UpdateScoutError.commandFailed("ditto", output: result.combined)
            }
            return try findApp(in: dir)
        case "dmg":
            let mountPoint = dir.appendingPathComponent("mount")
            let attach = try await Shell.run("/usr/bin/hdiutil",
                ["attach", archive.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path])
            guard attach.status == 0 else {
                throw UpdateScoutError.commandFailed("hdiutil attach", output: attach.combined)
            }
            defer { Task { _ = try? await Shell.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"]) } }
            // Copy off the read-only image before detaching.
            let source = try findApp(in: mountPoint)
            let dest = dir.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: dest)
            return dest
        default:
            throw UpdateScoutError.commandFailed(
                "unpack", output: "Unsupported archive type: .\(archive.pathExtension)")
        }
    }

    /// Find the .app at the top level, or one directory down (some archives
    /// wrap it in a folder).
    private static func findApp(in dir: URL) throws -> URL {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        if let app = entries.first(where: { $0.pathExtension == "app" }) { return app }
        for sub in entries where (try? sub.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let nested = (try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil)) ?? []
            if let app = nested.first(where: { $0.pathExtension == "app" }) { return app }
        }
        throw UpdateScoutError.commandFailed("unpack", output: "No .app found in the downloaded archive.")
    }

    private static func teamIdentifier(of app: URL) async throws -> String? {
        let result = try await Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", app.path])
        for line in result.combined.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let value = String(line.dropFirst("TeamIdentifier=".count))
            return value == "not set" ? nil : value
        }
        return nil
    }

    private static func bundleIdentifier(of app: URL) throws -> String? {
        guard let data = FileManager.default.contents(
                atPath: app.appendingPathComponent("Contents/Info.plist").path),
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }
}

/// URLSession download that reports bytes written as it goes, so a row can show
/// "Downloading… 42.3 MB / 84.4 MB (50%)". Throttled to ~4 updates/second.
final class ProgressDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private let destination: URL
    private var lastReport = Date.distantPast

    private init(destination: URL, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    static func download(from url: URL, to destination: URL,
                         onProgress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        let delegate = ProgressDownloader(destination: destination, onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            delegate.continuation = cont
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard Date().timeIntervalSince(lastReport) > 0.25 else { return }
        lastReport = Date()
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is removed as soon as this returns, so move it now.
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw UpdateScoutError.commandFailed("download", output: "HTTP \(http.statusCode)")
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }   // success is handled above
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
