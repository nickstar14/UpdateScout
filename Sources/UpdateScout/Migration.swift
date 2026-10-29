import AppKit

/// One-time steps for the UpdateScout to PrismPack rename (rename plan,
/// section 7). Plan A Part 1: only the display and bundle name changed, so
/// data and preferences are already where they were. What can go stale is the
/// app's own path: Sparkle keeps the old `UpdateScout.app` folder name, and the
/// launch agent stores the executable's full path.
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
        if renameBundleIfNeeded() { return true }
        Task { await LaunchAgent.repairIfNeeded() }
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
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }
}

extension LaunchAgent {
    /// If the agent's plist points at an executable that no longer exists
    /// (the app was renamed or moved), point it at this app and reload it.
    /// Leaves a working agent alone, so a test build never takes it over.
    static func repairIfNeeded() async {
        guard let data = FileManager.default.contents(atPath: plistURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let stored = (plist["ProgramArguments"] as? [String])?.first,
              let exe = Bundle.main.executablePath,
              stored != exe, !FileManager.default.fileExists(atPath: stored)
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
