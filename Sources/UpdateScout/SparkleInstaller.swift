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
///  3. Its Team ID must match the installed app's Team ID — so a validly
///     signed *but different* app can never replace it.
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

        // 1. Download.
        progress("Downloading…")
        let (tempFile, response) = try await URLSession.shared.download(from: plan.enclosureURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateScoutError.commandFailed("download", output: "HTTP error fetching \(plan.enclosureURL.lastPathComponent)")
        }
        let archive = workDir.appendingPathComponent(plan.enclosureURL.lastPathComponent)
        try fm.moveItem(at: tempFile, to: archive)

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
        progress("Checking code signature…")
        let verify = try await Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
        guard verify.status == 0 else {
            throw UpdateScoutError.commandFailed("codesign --verify", output: verify.combined)
        }
        let newTeam = try await teamIdentifier(of: newApp)
        let oldTeam = try await teamIdentifier(of: plan.appURL)
        guard let newTeam, let oldTeam, newTeam == oldTeam else {
            throw UpdateScoutError.commandFailed(
                "identity check",
                output: "The update is signed by a different developer (\(newTeam ?? "unsigned") vs \(oldTeam ?? "unsigned")). Nothing was installed.")
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
        // Move the old bundle aside first so we can roll back on failure.
        let backup = workDir.appendingPathComponent("previous.app")
        try fm.moveItem(at: plan.appURL, to: backup)
        do {
            try fm.moveItem(at: newApp, to: plan.appURL)
        } catch {
            try? fm.moveItem(at: backup, to: plan.appURL)   // roll back
            throw error
        }
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
