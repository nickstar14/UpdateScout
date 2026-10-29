import Foundation
import AppKit
import QuartzCore

/// Local JSON persistence under ~/Library/Application Support/UpdateScout/.
struct Store {
    struct State: Codable, Equatable {
        var lastCheck: Date?
        var items: [UpdateItem] = []
        /// Item ids the user dismissed ("ignore this version").
        var dismissed: Set<String> = []
        /// Item ids we've already notified about (notify only on new items).
        var notified: Set<String> = []
        /// Per-source error messages from the last check.
        var sourceErrors: [String: String] = [:]
        /// Third-party kexts on disk that the kernel isn't loading — offered
        /// for removal rather than update.
        var leftoverKexts: [KextBundle] = []
        /// Set by the background agent while its check runs, so the menu bar
        /// app can show the check in progress.
        var checkStartedAt: Date?
        /// "Ignore updates from this app": `sourceID|installToken`, no version,
        /// so it holds across new versions without touching item ids.
        var ignoredApps: Set<String> = []
        /// "Ignore major upgrades only", same key. Minor updates still show.
        var ignoredMajors: Set<String> = []
        /// What happened, newest first, capped at `activityLimit`.
        var activity: [ActivityEntry] = []

        static let activityLimit = 200

        init() {}

        // Hand-rolled so state files written before a field existed still load.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lastCheck = try c.decodeIfPresent(Date.self, forKey: .lastCheck)
            items = try c.decodeIfPresent([UpdateItem].self, forKey: .items) ?? []
            dismissed = try c.decodeIfPresent(Set<String>.self, forKey: .dismissed) ?? []
            notified = try c.decodeIfPresent(Set<String>.self, forKey: .notified) ?? []
            sourceErrors = try c.decodeIfPresent([String: String].self, forKey: .sourceErrors) ?? [:]
            leftoverKexts = try c.decodeIfPresent([KextBundle].self, forKey: .leftoverKexts) ?? []
            checkStartedAt = try c.decodeIfPresent(Date.self, forKey: .checkStartedAt)
            ignoredApps = try c.decodeIfPresent(Set<String>.self, forKey: .ignoredApps) ?? []
            ignoredMajors = try c.decodeIfPresent(Set<String>.self, forKey: .ignoredMajors) ?? []
            activity = try c.decodeIfPresent([ActivityEntry].self, forKey: .activity) ?? []
        }

        mutating func log(_ entry: ActivityEntry) {
            activity.insert(entry, at: 0)
            if activity.count > Self.activityLimit { activity.removeLast(activity.count - Self.activityLimit) }
        }
    }

    static var supportDirectory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UpdateScout", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var stateURL: URL { supportDirectory.appendingPathComponent("state.json") }

    static func load() -> State {
        guard let data = FileManager.default.contents(atPath: stateURL.path),
              let state = try? decoder.decode(State.self, from: data) else { return State() }
        return state
    }

    private static func save(_ state: State) {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    /// The only way to write state. The menu bar app and the background agent
    /// are separate processes that both write this file, so each write
    /// re-reads it under a cross-process lock and applies just its own
    /// change. Saving a whole in-memory copy instead let one process erase the
    /// other's newer results. Returns the state as written.
    @discardableResult
    static func mutate(_ change: (inout State) -> Void) -> State {
        let lockPath = supportDirectory.appendingPathComponent("state.lock").path
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o600)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        var state = load()
        change(&state)
        save(state)
        return state
    }

    /// Where state.json lives, for the app's file watcher.
    static var stateFileURL: URL { stateURL }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
}

/// User preferences (UserDefaults-backed).
enum Prefs {
    static let defaultInterval: TimeInterval = 6 * 3600

    static var disabledSources: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "disabledSources") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "disabledSources") }
    }

    /// Ask for the admin password once per batch instead of once per sudo call.
    static var askPasswordOncePerBatch: Bool {
        get { UserDefaults.standard.object(forKey: "askPasswordOncePerBatch") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "askPasswordOncePerBatch") }
    }

    /// How many installs may run at once ("Update at once", 1 to 8).
    static var updateConcurrency: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: "updateConcurrency")
            return value == 0 ? 4 : min(max(value, 1), 8)
        }
        set { UserDefaults.standard.set(min(max(newValue, 1), 8), forKey: "updateConcurrency") }
    }

    /// Choices for the background check interval, in minutes.
    static let checkIntervalChoices = [5, 15, 30, 45, 60, 180, 360, 720, 1440]

    /// Background check interval in minutes. Falls back to the older
    /// hours-based setting so an existing choice carries over.
    static var checkIntervalMinutes: Int {
        get {
            let d = UserDefaults.standard
            if let minutes = d.object(forKey: "checkIntervalMinutes") as? Int { return max(5, minutes) }
            if let hours = d.object(forKey: "checkIntervalHours") as? Int { return max(1, hours) * 60 }
            return 360
        }
        set { UserDefaults.standard.set(newValue, forKey: "checkIntervalMinutes") }
    }

    static func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }

    static var showDockIcon: Bool {
        get { UserDefaults.standard.bool(forKey: "showDockIcon") }
        set { UserDefaults.standard.set(newValue, forKey: "showDockIcon") }
    }

    /// How much light/dark tint sits under the glass: 0 is untinted Liquid
    /// Glass, 1 fully opaque. Seeded from the old Clear/Regular/Tinted choice.
    static let glassTintKey = "glassTint"
    static func migrateGlassTint() {
        let d = UserDefaults.standard
        guard d.object(forKey: glassTintKey) == nil else { return }
        let old = GlassStyle.from(d.string(forKey: "glassStyle") ?? "regular")
        d.set(old.washOpacity, forKey: glassTintKey)
    }

    static var appearance: Appearance {
        get { Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "appearance") }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    @MainActor private static func set(_ value: Appearance) {
        switch value {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Switch appearance, crossfading each visible window from its old look
    /// to its new one.
    static var fadeDuration: CFTimeInterval = 0.6

    /// Whether macOS itself is in dark mode, whatever the app is set to.
    static var systemIsDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    /// Whether this setting ends up dark.
    var isDark: Bool {
        switch self {
        case .system: Self.systemIsDark
        case .light: false
        case .dark: true
        }
    }

    @MainActor static func apply(_ value: Appearance, animated: Bool = false) {
        // Nothing will look different (Light while the Mac is light, say):
        // just record the choice, with no fade.
        let nowDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard animated, value.isDark != nowDark else { set(value); return }
        // A quick veil in the window's background colour rises over each
        // window, the switch happens under it, and it fades away in the new
        // background colour. Parts of the window redraw a few milliseconds
        // apart, and the glass sidebar can't be faded or snapshotted, so the
        // switch is hidden rather than animated piece by piece.
        let rise = fadeDuration * 0.4, fall = fadeDuration * 0.6
        var veils: [CALayer] = []
        for window in NSApp.windows where window.isVisible {
            guard let frame = window.contentView?.superview else { continue }
            frame.wantsLayer = true
            let veil = CALayer()
            veil.frame = frame.bounds
            veil.zPosition = 10_000
            veil.backgroundColor = background(in: window.effectiveAppearance)
            veil.opacity = 0
            frame.layer?.addSublayer(veil)
            veils.append(veil)
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(rise)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
        CATransaction.setCompletionBlock {
            set(value)
            // A turn of the runloop, so everything has redrawn under the veil.
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setAnimationDuration(fall)
                CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
                CATransaction.setCompletionBlock { veils.forEach { $0.removeFromSuperlayer() } }
                for veil in veils {
                    veil.backgroundColor = background(in: NSApp.effectiveAppearance)
                    veil.opacity = 0
                }
                CATransaction.commit()
            }
        }
        veils.forEach { $0.opacity = 0.85 }
        CATransaction.commit()
    }

    /// The window background colour as it looks in `appearance`.
    @MainActor private static func background(in appearance: NSAppearance) -> CGColor {
        var color = NSColor.windowBackgroundColor.cgColor
        appearance.performAsCurrentDrawingAppearance { color = NSColor.windowBackgroundColor.cgColor }
        return color
    }
}

/// How opaque the window's Liquid Glass reads — Apple's own tier names.
enum GlassStyle: String, CaseIterable, Identifiable {
    case clear, regular, tinted
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Opacity of the window-background wash layered under the glass.
    var washOpacity: Double {
        switch self {
        case .clear: 0.12
        case .regular: 0.35
        case .tinted: 0.65
        }
    }
    /// Accepts the pre-rename stored values ("middle"/"frosted") too.
    static func from(_ raw: String) -> GlassStyle {
        GlassStyle(rawValue: raw)
            ?? (raw == "middle" ? .regular : raw == "frosted" ? .tinted : .regular)
    }
}

/// One line in the Activity tab.
struct ActivityEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case updated, failed, skipped, cancelled, checked }
    var id = UUID()
    var date = Date()
    let kind: Kind
    let title: String
    var detail: String = ""
    /// The update it's about, for Retry while that update is still listed.
    var itemID: String? = nil
    var sourceID: String? = nil
    var seconds: Int? = nil
    /// The last lines of output, for Show log on failures.
    var log: String? = nil
}

extension UpdateItem {
    /// Key for the per-app ignore lists: the app, not the version.
    var appKey: String { "\(sourceID)|\(installToken)" }
}
