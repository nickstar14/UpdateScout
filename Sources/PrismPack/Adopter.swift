import AppKit
import Security

/// Runs adoption work through the update queue, in Homebrew's lane, one at a
/// time like every other `brew` mutation. Tokens are
/// `<action>:<cask>|<app path>`:
/// - `adopt`: `brew install --cask --adopt`, in place, nothing replaced.
/// - `replace`: old app to the Trash, `brew install --cask` (never --force),
///   checked, and rolled back if anything is wrong.
/// - `switch`: an App Store app replaced by Homebrew's copy of it, the
///   same way (Nick, 30 Oct 2026). Same bundle id and developer, so its data stays.
/// - `untrack`: "Stop managing with Homebrew" (and a duplicate's "Stop
///   Homebrew tracking it"): only the cask's Caskroom record goes, after
///   checking it holds no app. Never `brew uninstall`, which deletes the app.
struct Adopter: UpdateSource {
    let id = "adopt"
    let displayName = "Homebrew adoption"

    struct Job: Hashable {
        let action: String
        let cask: String
        let appPath: String

        var token: String { "\(action):\(cask)|\(appPath)" }

        init(action: String, cask: String, appPath: String) {
            self.action = action; self.cask = cask; self.appPath = appPath
        }

        init?(token: String) {
            let head = token.split(separator: ":", maxSplits: 1).map(String.init)
            guard head.count == 2 else { return nil }
            let rest = head[1].split(separator: "|", maxSplits: 1).map(String.init)
            guard rest.count == 2 else { return nil }
            self.init(action: head[0], cask: rest[0], appPath: rest[1])
        }

        /// The queue item. Its name is the app's, for rows and Activity.
        func item(name: String) -> UpdateItem {
            UpdateItem(sourceID: "adopt", name: name, installedVersion: "", latestVersion: "",
                       installToken: token, appPath: appPath)
        }
    }

    /// Cask tokens are passed as arguments, never through a shell, and must
    /// look like one (adoption doc, "Safe with the rest of the app").
    static func validToken(_ token: String) -> Bool {
        token.wholeMatch(of: #/[a-z0-9@+._-]+/#) != nil
    }

    func detect() async throws -> [UpdateItem] { [] }

    /// Replacing with a pkg cask runs its installer, which needs the password.
    func needsAdmin(_ item: UpdateItem) -> Bool {
        guard let job = Job(token: item.installToken) else { return false }
        // Moving an App Store copy always needs admin: it's owned by root.
        return job.action == "switch" || (job.action == "replace"
            && (HomebrewSource.isInstallerCask(job.cask) || Self.isRootOwned(job.appPath)))
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let job = Job(token: item.installToken), Self.validToken(job.cask),
              let brew = HomebrewSource.brewPath else {
            throw PrismPackError.parseFailure("adoption job \(item.installToken)")
        }
        let cask = try await Self.liveCask(job.cask, brew: brew)
        switch job.action {
        case "adopt": try await adopt(job, cask: cask, brew: brew, progress: progress)
        case "replace", "switch": try await replace(job, name: item.name, cask: cask, brew: brew, progress: progress)
        case "untrack": try await untrack(job, progress: progress)
        default: throw PrismPackError.parseFailure("adoption action \(job.action)")
        }
    }

    // MARK: Adopt in place

    private func adopt(_ job: Job, cask: LiveCask, brew: String,
                       progress: @escaping @Sendable (String) -> Void) async throws {
        // Homebrew 7.0.11 adopts an older copy without complaint and records
        // the cask's version (tested 30 Oct 2026), so the version check is ours.
        guard let before = Adoption.facts(at: job.appPath) else { throw gone(job) }
        guard Adoption.sameVersion(before, cask.version) else {
            throw PrismPackError.commandFailed("Adopt",
                output: "\(before.name) is \(before.version) and Homebrew's is \(Adoption.core(cask.version)). Only an identical copy is adopted in place.")
        }
        progress("§step:download")
        try await Self.watchingDownload(cask: job.cask, url: cask.url, brew: brew, progress: progress) {
            try await self.run(brew, ["install", "--cask", "--adopt", job.cask], progress)
        }
        do {
            progress("§step:check")
            try verify(job, bundleID: before.bundleID, version: cask.version)
        } catch {
            // Adopting changed nothing on disk: just drop the new record.
            try? await Self.removeRecord(job.cask)
            throw error
        }
    }

    // MARK: Replace

    /// Replace for callers outside the queue token format: the "Other apps
    /// (via Homebrew data)" updates (Nick, 30 Oct 2026: no more --force).
    static func replace(cask: String, appPath: String, name: String,
                        progress: @escaping @Sendable (String) -> Void) async throws {
        guard validToken(cask), let brew = HomebrewSource.brewPath else {
            throw PrismPackError.toolMissing("Homebrew", hint: "Install it from https://brew.sh")
        }
        let job = Job(action: "replace", cask: cask, appPath: appPath)
        let adopter = Adopter()
        try await adopter.replace(job, name: name, cask: try await liveCask(cask, brew: brew), brew: brew, progress: progress)
    }

    /// Replace, and also "switch": an App Store copy moved to Homebrew's.
    /// Homebrew may already hold a record of the cask (Outlook did), which
    /// would make `install` refuse; only that record goes first.
    private func replace(_ job: Job, name: String, cask: LiveCask, brew: String,
                         progress: @escaping @Sendable (String) -> Void) async throws {
        guard let before = Adoption.facts(at: job.appPath) else { throw gone(job) }
        let team = CodeSign.teamID(job.appPath)
        if NSRunningApplication.runningApplications(withBundleIdentifier: before.bundleID).isEmpty == false {
            throw PrismPackError.commandFailed("Replace", output: "\(name) is open. Quit it, then try again.")
        }
        progress("§step:trash")
        progress("Moving \(name) to the Trash…")
        let trashed: URL
        do {
            trashed = try await Self.trash(job.appPath, name: name)
        } catch {
            throw PrismPackError.commandFailed("Move to Trash",
                output: "macOS didn't let \(AppIdentity.name) move \(name) to the Trash (\(error.localizedDescription)). Nothing was changed.")
        }

        do {
            if job.action == "switch" { try await Self.removeRecord(job.cask) }
            progress("§step:download")
            try await Self.watchingDownload(cask: job.cask, url: cask.url, brew: brew, progress: progress) {
                try await self.run(brew, ["install", "--cask", job.cask], progress)
            }
            progress("§step:check")
            try verify(job, bundleID: before.bundleID, version: cask.version)
            // Same developer, so macOS keeps giving it the same data.
            if let team, CodeSign.teamID(job.appPath) != team {
                throw failed("The new copy is signed by a different developer.")
            }
            progress("§step:launch")
            progress("Checking that \(name) opens…")
            try await checkLaunches(job.appPath, bundleID: before.bundleID, name: name)
        } catch {
            progress("Putting your copy of \(name) back…")
            let restored = await rollBack(job, trashed: trashed, cask: cask)
            throw PrismPackError.commandFailed("Replace", output: error.localizedDescription
                + (restored ? "\n\nYour copy of \(name) is back where it was, and Homebrew's record of it is removed."
                            : "\n\nYour copy of \(name) is still in the Trash: put it back from there."))
        }
    }

    /// Undo a Replace that failed: the new copy out of the way, the old one
    /// back from the Trash, Homebrew's record and any installer receipt
    /// removed. True when the old app is back.
    private func rollBack(_ job: Job, trashed: URL, cask: LiveCask) async -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: job.appPath) {
            // A pkg installs as root, so its app can only move with admin rights.
            if (try? fm.attributesOfItem(atPath: job.appPath)[.ownerAccountID] as? Int) == 0 {
                let dest = NSHomeDirectory() + "/.Trash/" + UUID().uuidString + "-" + (job.appPath as NSString).lastPathComponent
                _ = try? await Shell.runPrivileged("/bin/mv \(Self.quoted(job.appPath)) \(Self.quoted(dest))",
                                                   reason: "\(AppIdentity.name) is putting your previous app back.")
            } else {
                _ = try? await NSWorkspace.shared.recycle([URL(fileURLWithPath: job.appPath)])
            }
        }
        try? await Self.removeRecord(job.cask)
        if cask.pkg {
            for id in cask.pkgutilIDs where id.wholeMatch(of: #/[A-Za-z0-9._-]+/#) != nil {
                _ = try? await Shell.runPrivileged("/usr/sbin/pkgutil --forget \(Self.quoted(id))",
                                                   reason: "\(AppIdentity.name) is removing the installer's record.")
            }
        }
        guard !fm.fileExists(atPath: job.appPath) else { return false }
        return await Self.restore(trashed, to: job.appPath)
    }

    /// App Store apps and pkg installs are owned by root, so moving them
    /// takes admin rights (found 30 Oct 2026: OneNote couldn't be trashed).
    static func isRootOwned(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.ownerAccountID] as? Int) == 0
    }

    /// Moves an app to the user's Trash, with admin rights when it's root's.
    static func trash(_ path: String, name: String) async throws -> URL {
        guard isRootOwned(path) else {
            let moved = try await NSWorkspace.shared.recycle([URL(fileURLWithPath: path)])
            guard let url = moved.values.first else { throw CocoaError(.fileWriteUnknown) }
            return url
        }
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: ".")
        let dest = NSHomeDirectory() + "/.Trash/\((path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")) \(stamp).app"
        let result = try await Shell.runPrivileged("/bin/mv \(quoted(path)) \(quoted(dest))",
                                                   reason: "\(AppIdentity.name) is moving \(name) to the Trash.")
        guard result.status == 0, FileManager.default.fileExists(atPath: dest) else {
            throw PrismPackError.commandFailed("mv", output: result.combined)
        }
        return URL(fileURLWithPath: dest)
    }

    /// Puts a trashed app back, with admin rights when it's root's.
    static func restore(_ trashed: URL, to path: String) async -> Bool {
        if (try? FileManager.default.moveItem(at: trashed, to: URL(fileURLWithPath: path))) != nil { return true }
        let result = try? await Shell.runPrivileged("/bin/mv \(quoted(trashed.path)) \(quoted(path))",
                                                    reason: "\(AppIdentity.name) is putting your app back.")
        return result?.status == 0 && FileManager.default.fileExists(atPath: path)
    }

    /// Opens the new app in the background, waits for it to run, then quits it.
    private func checkLaunches(_ path: String, bundleID: String, name: String) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        let app = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config)
        for _ in 0..<20 where NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            try await Task.sleep(for: .milliseconds(500))
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else {
            throw PrismPackError.commandFailed("Replace", output: "The new copy of \(name) didn't open.")
        }
        // It wasn't open before (Replace refuses then), so close what we opened.
        (app.map { [$0] } ?? running).forEach { $0.terminate() }
    }

    // MARK: Stop managing

    private func untrack(_ job: Job, progress: @escaping @Sendable (String) -> Void) async throws {
        progress("Removing Homebrew's record…")
        try await Self.removeRecord(job.cask)
        if !job.appPath.isEmpty, !FileManager.default.fileExists(atPath: job.appPath) {
            throw PrismPackError.commandFailed("Stop managing", output: "\(job.appPath) is missing.")
        }
    }

    /// Moves `Caskroom/<token>` to the Trash, after checking it holds only
    /// Homebrew's metadata, links to the app and installer files: never an
    /// app bundle itself.
    static func removeRecord(_ token: String) async throws {
        guard validToken(token) else { throw PrismPackError.parseFailure("cask token \(token)") }
        let fm = FileManager.default
        guard let folder = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
            .map({ "\($0)/\(token)" }).first(where: { fm.fileExists(atPath: $0) }) else { return }
        if let bundle = appBundle(inside: folder) {
            throw PrismPackError.commandFailed("Stop managing",
                output: "Homebrew's folder for \(token) holds an app (\(bundle)), so it was left alone.")
        }
        _ = try await NSWorkspace.shared.recycle([URL(fileURLWithPath: folder)])
    }

    /// The first real .app bundle in a Caskroom folder (links don't count).
    static func appBundle(inside folder: String) -> String? {
        guard let walker = FileManager.default.enumerator(at: URL(fileURLWithPath: folder),
                                                           includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return nil }
        for case let url as URL in walker where url.pathExtension == "app" {
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            return url.lastPathComponent
        }
        return nil
    }

    // MARK: Checks

    /// After adopting or replacing: Homebrew lists it, the app is at the
    /// same path with the same bundle id, and it's the cask's version.
    private func verify(_ job: Job, bundleID: String, version: String) throws {
        let fm = FileManager.default
        let recorded = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"].contains { fm.fileExists(atPath: "\($0)/\(job.cask)") }
        guard recorded else { throw failed("Homebrew didn't record \(job.cask).") }
        guard let after = Adoption.facts(at: job.appPath) else { throw failed("The app isn't at \(job.appPath) any more.") }
        guard after.bundleID == bundleID else { throw failed("The app's bundle ID changed (\(after.bundleID)).") }
        guard Adoption.sameVersion(after, version) else {
            throw failed("The app is \(after.version), not Homebrew's \(Adoption.core(version)).")
        }
    }

    private func failed(_ message: String) -> Error { PrismPackError.commandFailed("Check after moving", output: message) }
    private func gone(_ job: Job) -> Error {
        PrismPackError.commandFailed("Adopt", output: "\(job.appPath) isn't there any more. Check again.")
    }

    private func run(_ brew: String, _ args: [String], _ progress: @escaping @Sendable (String) -> Void) async throws {
        let result = try await Shell.run(brew, args, tag: Shell.installTag, lineHandler: progress)
        guard result.status == 0 else {
            throw PrismPackError.commandFailed("brew " + args.joined(separator: " "), output: result.combined)
        }
    }

    static func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    // MARK: The cask, as Homebrew has it now

    struct LiveCask {
        let version: String
        let pkg: Bool
        let pkgutilIDs: [String]
        var url: String? = nil
    }

    /// Runs a brew command while reporting how much of the cask's download is
    /// on disk: Homebrew prints nothing while it downloads when not in a
    /// terminal, so PrismPack watches its download file (`brew --cache`, with
    /// `.incomplete` while it's still arriving) against the size the server gives.
    static func watchingDownload(cask: String, url: String?, brew: String,
                                 progress: @escaping @Sendable (String) -> Void,
                                 _ body: @escaping () async throws -> Void) async throws {
        let cached = (try? await Shell.run(brew, ["--cache", "--cask", cask]))?.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let total = await url.asyncFlatMap { await Adoption.downloadSize($0) } ?? 0
        let watcher = Task {
            guard !cached.isEmpty else { return }
            while !Task.isCancelled {
                let fm = FileManager.default
                let size = [cached + ".incomplete", cached].compactMap {
                    (try? fm.attributesOfItem(atPath: $0)[.size] as? NSNumber)?.int64Value
                }.max() ?? 0
                if size > 0 { progress("§download:\(size)/\(total)") }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { watcher.cancel() }
        try await body()
    }

    /// The cask's current facts from `brew info` (the daily list may be a day old).
    static func liveCask(_ token: String, brew: String) async throws -> LiveCask {
        let result = try await Shell.run(brew, ["info", "--json=v2", "--cask", token])
        guard result.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let cask = (json["casks"] as? [[String: Any]])?.first,
              let version = cask["version"] as? String, version != "latest"
        else { throw PrismPackError.commandFailed("brew info --cask \(token)", output: result.combined) }
        let artifacts = cask["artifacts"] as? [[String: Any]] ?? []
        var ids: [String] = []
        for artifact in artifacts {
            for stanza in artifact["uninstall"] as? [[String: Any]] ?? [] {
                if let one = stanza["pkgutil"] as? String { ids.append(one) }
                ids += (stanza["pkgutil"] as? [String]) ?? []
            }
        }
        return LiveCask(version: version, pkg: artifacts.contains { $0["pkg"] != nil }, pkgutilIDs: ids,
                        url: cask["url"] as? String)
    }
}

/// Reads code signatures.
enum CodeSign {
    /// The developer Team ID an app or package is signed with, if any.
    static func teamID(_ path: String) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// True when the app's signature is intact (`codesign --verify --deep --strict`).
    static func isValid(_ path: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
    }
}

extension Optional {
    /// `flatMap` for an async transform.
    func asyncFlatMap<U>(_ transform: (Wrapped) async -> U?) async -> U? {
        guard let value = self else { return nil }
        return await transform(value)
    }
}
