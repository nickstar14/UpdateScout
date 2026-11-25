import AppKit

/// The 1.x names, kept only so the 2.0 migration can find what 1.x left
/// behind. Nothing else should use them.
enum Legacy {
    static let bundleID = "com.nickszun.updatescout"
    static let launchLabel = "com.nickszun.updatescout.check"
    static let supportFolder = "UpdateScout"
    static let statusItemName = "UpdateScoutStatusItem"
}

/// Steps that run first thing in `main`, before anything reads preferences or
/// the data folder. Not main-actor and with every path a parameter, so tests
/// run on temp folders. Numbered (`level`): a later release adds a step and
/// raises `current`, and what already ran never runs again.
///  1. (2.0.0) preferences copied from the 1.x domain, the menu bar item's
///     saved position renamed, the data folder moved to `PrismPack`.
enum EarlyMigration {
    static let levelKey = "migrationLevel"
    /// Set when 2.0 took over from 1.x: macOS starts Full Disk Access and
    /// notifications over for a new bundle ID, so launch re-checks them.
    static let recheckPermissionsKey = "recheckPermissions"
    static let current = 1

    static func run() {
        guard !AppIdentity.isFreshProfile else { return }
        guard Bundle.main.bundleIdentifier != Legacy.bundleID else { return }
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: levelKey) < current else { return }
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]

        var carried = false
        if let keys = CFPreferencesCopyKeyList(Legacy.bundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String],
           let old = CFPreferencesCopyMultiple(keys as CFArray, Legacy.bundleID as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] {
            let existing = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
            for (key, value) in carriedPreferences(old: old, existing: existing) { defaults.set(value, forKey: key) }
            carried = !old.isEmpty
        }
        // PrismPack's own Stable / Beta choice was filed under the old bundle ID.
        if let id = Bundle.main.bundleIdentifier,
           let carried = carriedChannelChoices(defaults.dictionary(forKey: "channelChoices"), newID: id) {
            defaults.set(carried, forKey: "channelChoices")
        }
        let moved = moveSupportFolder(from: support.appendingPathComponent(Legacy.supportFolder, isDirectory: true),
                                      to: support.appendingPathComponent("PrismPack", isDirectory: true), using: fm)
        if moved == .failed { return }   // try again next launch
        if carried || moved == .moved { defaults.set(true, forKey: recheckPermissionsKey) }
        defaults.set(current, forKey: levelKey)
        NSLog("Rename: preferences carried over: %@, data folder: %@", carried ? "yes" : "none", "\(moved)")
    }

    /// What to copy from the old preferences domain: everything the new one
    /// doesn't have yet, with the menu bar item's saved-position keys renamed.
    static func carriedPreferences(old: [String: Any], existing: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in old where key != levelKey && key != recheckPermissionsKey {
            let newKey = key.replacingOccurrences(of: Legacy.statusItemName, with: "PrismPackStatusItem")
            if existing[newKey] == nil { out[newKey] = value }
        }
        return out
    }

    /// The channel choices with the old bundle ID's entry copied to the new one
    /// (nil when there is nothing to copy).
    static func carriedChannelChoices(_ choices: [String: Any]?, newID: String) -> [String: Any]? {
        guard var choices, let old = choices[Legacy.bundleID], choices[newID] == nil else { return nil }
        choices[newID] = old
        return choices
    }

    enum Move: Equatable { case nothingToMove, moved, bothExist, failed }

    /// Moves the 1.x data folder to the new name. Only when the new one is
    /// missing or empty; never deletes anything but an empty folder.
    static func moveSupportFolder(from old: URL, to new: URL, using fm: FileManager = .default) -> Move {
        guard fm.fileExists(atPath: old.path) else { return .nothingToMove }
        if fm.fileExists(atPath: new.path) {
            let inside = (try? fm.contentsOfDirectory(atPath: new.path)) ?? ["?"]
            guard inside.isEmpty else { return .bothExist }
            try? fm.removeItem(at: new)
        }
        do {
            try fm.moveItem(at: old, to: new)
            return .moved
        } catch {
            NSLog("Rename: couldn't move %@ to %@: %@", old.path, new.path, error.localizedDescription)
            return .failed
        }
    }
}

/// One-time steps for the UpdateScout to PrismPack rename (rename plan,
/// section 7), the ones that need the app running. 2.0.0 renamed everything
/// (bundle ID, executable, launch agent, data folder; see `EarlyMigration`
/// and `Legacy`). What can go stale is the app's own path: Sparkle installs
/// 2.0.0 as the old `UpdateScout.app`, and the launch agent stores the
/// executable's full path.
@MainActor
enum Migration {
    /// Set when someone upgrades from UpdateScout; the main window shows the
    /// rename pop-up (RenameWelcome) until it's closed.
    static let noticeKey = "showRenameNotice"
    private static let decidedKey = "renameNoticeDecided"
    /// The "UpdateScout is now PrismPack" banner on the Updates page, shown to
    /// everyone for all of 2.0 (Nick); clicking it replays the pop-up. Nick
    /// turns this off in a later release.
    static let showsRenameBanner = true
    private static let legacyBundleName = "UpdateScout.app"

    /// Decide once whether this is an upgrade (show the notice) or a fresh
    /// install (don't). Call before first-run setup marks `didFirstRunSetup`,
    /// which 1.x already set on every machine it ran on.
    static func prepareNotice() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: decidedKey) else { return }
        defaults.set(true, forKey: decidedKey)
        guard defaults.bool(forKey: "didFirstRunSetup") else { return }
        defaults.set(true, forKey: noticeKey)
        let s = Store.load()
        NSLog("Rename: carried over %d items, %d hidden versions, %d hidden apps, %d hidden majors, %d notified",
              s.items.count, s.dismissed.count, s.ignoredApps.count, s.ignoredMajors.count, s.notified.count)
    }

    /// Runs at every app launch. Returns true if the app is relaunching from a
    /// new path, so the caller can skip the rest of its launch work.
    static func runAtLaunch() -> Bool {
        if AppIdentity.isFreshProfile { return false }
        if renameBundleIfNeeded() { return true }
        Task {
            await LaunchAgent.retireLegacyIfNeeded()
            await LaunchAgent.repairIfNeeded()
        }
        return false
    }

    /// Renames `UpdateScout.app` to `<display name>.app` in the same folder and
    /// relaunches from there (Nick, Phase 5: always, without asking). Skips
    /// quietly when the new name is taken or the folder isn't writable without
    /// a password; the next launch tries again. The relaunched copy repairs
    /// the launch agent, since its stored path no longer exists.
    private static func renameBundleIfNeeded() -> Bool {
        let current = Bundle.main.bundleURL
        guard current.lastPathComponent == legacyBundleName,
              AppIdentity.name + ".app" != legacyBundleName,
              !current.path.contains("/AppTranslocation/") else { return false }
        let fm = FileManager.default
        let target = current.deletingLastPathComponent().appendingPathComponent(AppIdentity.name + ".app")
        guard !fm.fileExists(atPath: target.path),
              fm.isWritableFile(atPath: current.deletingLastPathComponent().path) else { return false }
        do {
            try fm.moveItem(at: current, to: target)
        } catch {
            NSLog("Rename: couldn't rename %@: %@", current.path, error.localizedDescription)
            return false
        }
        NSLog("Rename: moved %@ to %@", current.path, target.path)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = Array(CommandLine.arguments.dropFirst())
        NSWorkspace.shared.openApplication(at: target, configuration: config) { _, error in
            if let error { NSLog("Rename: relaunch failed: %@", error.localizedDescription) }
            DispatchQueue.main.async { AppDelegate.quitWithoutAsking() }
        }
        return true
    }
}

extension LaunchAgent {
    private static var legacyPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Legacy.launchLabel).plist")
    }

    /// 1.x's background agent (old label) is stopped and its plist removed, so
    /// it never runs against the moved data folder. If it was on, the new
    /// agent takes over with the same interval, unless one already exists.
    static func retireLegacyIfNeeded() async {
        guard let data = FileManager.default.contents(atPath: legacyPlistURL.path) else { return }
        let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        let minutes = (plist?["StartInterval"] as? Int).map { $0 / 60 } ?? Prefs.checkIntervalMinutes
        _ = try? await Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(Legacy.launchLabel)"])
        try? FileManager.default.removeItem(at: legacyPlistURL)
        guard !hasPlist else { return }
        do {
            try await install(intervalMinutes: minutes)
            NSLog("Rename: background agent moved to %@", label)
        } catch {
            NSLog("Rename: couldn't start the new background agent: %@", error.localizedDescription)
        }
    }

    /// If the agent's plist points at an executable that no longer exists
    /// (the app was renamed or moved), or at a test build while this is the
    /// installed copy in /Applications, point it at this app and reload it.
    /// Otherwise leaves a working agent alone, so a test build never takes it
    /// over from the installed copy.
    static func repairIfNeeded() async {
        guard let data = FileManager.default.contents(atPath: plistURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let stored = (plist["ProgramArguments"] as? [String])?.first,
              let exe = Bundle.main.executablePath,
              stored != exe,
              !FileManager.default.fileExists(atPath: stored)
                || (exe.hasPrefix("/Applications/") && !stored.hasPrefix("/Applications/"))
        else { return }
        let minutes = (plist["StartInterval"] as? Int).map { $0 / 60 } ?? Prefs.checkIntervalMinutes
        do {
            try await install(intervalMinutes: minutes)
            NSLog("Rename: launch agent repaired, %@ to %@", stored, exe)
        } catch {
            NSLog("Rename: launch agent repair failed: %@", error.localizedDescription)
        }
    }
}
