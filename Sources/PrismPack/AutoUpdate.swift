import Foundation
import AppKit
import Network

/// Automatic installs (Phase 8). Off until turned on in Settings. Runs on a
/// schedule after a check: from the background agent when PrismPack's window
/// app isn't running, otherwise from the app's own install queue. Never for
/// anything that needs a password, an open app, macOS, custom sources, betas,
/// major upgrades, or anything hidden or pinned (Nick, 30 Oct 2026).
enum AutoUpdate {
    enum Schedule: String, CaseIterable, Identifiable {
        case daily, weekly, everyCheck
        var id: String { rawValue }
        var title: String {
            switch self {
            case .daily: "Daily"
            case .weekly: "Weekly"
            case .everyCheck: "Every check"
            }
        }
    }

    /// A per-app override of the global switch.
    enum Rule: String, CaseIterable, Identifiable {
        case always, never
        var id: String { rawValue }
    }

    // MARK: Settings

    private static var defaults: UserDefaults { .standard }

    static var enabled: Bool {
        get { defaults.bool(forKey: "autoUpdateEnabled") }
        set { defaults.set(newValue, forKey: "autoUpdateEnabled") }
    }

    static var schedule: Schedule {
        get { defaults.string(forKey: "autoUpdateSchedule").flatMap(Schedule.init) ?? .daily }
        set { defaults.set(newValue.rawValue, forKey: "autoUpdateSchedule") }
    }

    /// Skip runs on a phone hotspot or in Low Data Mode.
    static var unmeteredOnly: Bool {
        get { defaults.bool(forKey: "autoUpdateUnmeteredOnly") }
        set { defaults.set(newValue, forKey: "autoUpdateUnmeteredOnly") }
    }

    static var lastRun: Date? {
        get { defaults.object(forKey: "autoUpdateLastRun") as? Date }
        set { defaults.set(newValue, forKey: "autoUpdateLastRun") }
    }

    /// Per-app rules, keyed like the Hide lists (`UpdateItem.appKey`).
    static func rule(for appKey: String) -> Rule? {
        (defaults.dictionary(forKey: "autoUpdateRules")?[appKey] as? String).flatMap(Rule.init)
    }

    static func setRule(_ rule: Rule?, for appKey: String) {
        var all = defaults.dictionary(forKey: "autoUpdateRules") ?? [:]
        all[appKey] = rule?.rawValue
        defaults.set(all, forKey: "autoUpdateRules")
    }

    /// Apps kept at their installed version: never automatic, not in Update
    /// All; a newer version is still listed.
    static var pinned: Set<String> {
        get { Set(defaults.stringArray(forKey: "pinnedApps") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "pinnedApps") }
    }

    // MARK: Rules

    /// Sources whose installs routinely ask for a password, or that change
    /// more than the app (cask replacement, drivers), or run the user's own
    /// commands. Never automatic.
    static let excludedSources: Set<String> = ["macos", "custom", "mas", "components", "caskOracle"]

    /// Why an update won't install on its own, or nil when it will.
    static func blocker(_ item: UpdateItem, hidden: Bool, pinned: Bool, needsAdmin: Bool, appOpen: Bool,
                        enabled: Bool = AutoUpdate.enabled, rule: Rule? = nil) -> String? {
        if hidden { return "Hidden" }
        if pinned { return "Pinned" }
        if rule == .never { return "Set to never update automatically" }
        if !enabled && rule != .always { return "Automatic updates are off" }
        if !item.scriptedInstall || excludedSources.contains(item.sourceID) { return "Only updated by hand" }
        if item.isMajorUpgrade { return "Major upgrade" }
        if VersionParts(item.latestVersion).track > 0 { return "Beta" }
        if needsAdmin { return "Needs your password" }
        if appOpen { return "Open right now" }
        return nil
    }

    /// A run is due by the schedule. A little slack, so a daily run doesn't
    /// slip a whole check interval each day.
    static func isDue(now: Date = Date(), last: Date? = AutoUpdate.lastRun,
                      schedule: Schedule = AutoUpdate.schedule) -> Bool {
        guard let last else { return true }
        let elapsed = now.timeIntervalSince(last)
        switch schedule {
        case .everyCheck: return true
        case .daily: return elapsed >= 23 * 3600
        case .weekly: return elapsed >= 7 * 24 * 3600 - 3600
        }
    }

    /// On a phone hotspot or in Low Data Mode (macOS's expensive or
    /// constrained network).
    static func onMeteredNetwork() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                monitor.cancel()
                continuation.resume(returning: path.isExpensive || path.isConstrained)
            }
            monitor.start(queue: DispatchQueue(label: "AutoUpdate.network"))
        }
    }

    /// The app is running, so replacing it would mean quitting it.
    static func isOpen(_ item: UpdateItem) -> Bool {
        guard let path = item.appPath else { return false }
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
        }
    }

    // MARK: One run at a time, across the app and the agent

    private static var lockURL: URL { Store.supportDirectory.appendingPathComponent("auto-update.lock") }

    /// An exclusive lock for a run, or nil while another process holds it.
    /// Released when the descriptor is closed (or the process exits).
    static func acquireLock() -> Int32? {
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 { close(fd); return nil }
        return fd
    }

    static func releaseLock(_ fd: Int32) { flock(fd, LOCK_UN); close(fd) }

    /// PrismPack's window app is running (not this headless agent).
    static var appIsRunning: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != me && $0.activationPolicy != .prohibited }
    }

    // MARK: Headless

    /// After a background check: install what's eligible, one at a time, and
    /// log it. Leaves it to the app when the app is running. Returns the
    /// names updated and those that failed (empty when nothing ran).
    static func runHeadless() async -> (updated: [String], failed: [String]) {
        guard isActive, !appIsRunning, isDue() else { return ([], []) }
        if unmeteredOnly, await onMeteredNetwork() { return ([], []) }
        guard let lock = acquireLock() else { return ([], []) }
        defer { releaseLock(lock) }

        let state = Store.load()
        await HomebrewSource.lookUpInstallerCasks(state.items.compactMap(HomebrewSource.caskToken(of:)))
        let items = state.items.filter { item in
            let source = UpdateController.source(for: item.sourceID)
            return blocker(item, hidden: state.isHidden(item), pinned: isPinned(item),
                           needsAdmin: source?.needsAdmin(item) ?? true, appOpen: isOpen(item),
                           rule: rule(for: item.appKey)) == nil
        }
        lastRun = Date()
        var updated: [String] = [], failed: [String] = []
        for item in items {
            guard let source = UpdateController.source(for: item.sourceID) else { continue }
            let started = Date()
            do {
                try await Shell.$noPasswordPrompt.withValue(true) {
                    try await source.install(item) { _ in }
                }
                updated.append(item.name)
                Store.mutate {
                    $0.items.removeAll { $0.id == item.id }
                    $0.log(ActivityEntry(kind: .updated, title: "\(item.name) \(item.installedVersion) to \(item.latestVersion)",
                                         detail: "Automatically · \(UpdateController.sourceName(item.sourceID))",
                                         itemID: item.id, sourceID: item.sourceID,
                                         seconds: Int(Date().timeIntervalSince(started).rounded())))
                }
            } catch {
                failed.append(item.name)
                Store.mutate {
                    $0.log(ActivityEntry(kind: .failed, title: item.logTitle,
                                         detail: "Automatically · \(UpdateController.sourceName(item.sourceID)) · \(error.localizedDescription)",
                                         itemID: item.id, sourceID: item.sourceID))
                }
            }
        }
        return (updated, failed)
    }

    /// Anything could install automatically: the switch is on, or some app
    /// is set to Always.
    static var isActive: Bool {
        enabled || (defaults.dictionary(forKey: "autoUpdateRules") ?? [:]).values.contains { $0 as? String == Rule.always.rawValue }
    }

    static func isPinned(_ item: UpdateItem) -> Bool { item.isPinned || pinned.contains(item.appKey) }
}
