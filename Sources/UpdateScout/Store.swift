import Foundation
import AppKit
import QuartzCore

/// Local JSON persistence under ~/Library/Application Support/UpdateScout/.
struct Store {
    struct State: Codable {
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

    static func save(_ state: State) {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

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

    static var checkIntervalHours: Int {
        get { max(1, UserDefaults.standard.object(forKey: "checkIntervalHours") as? Int ?? 6) }
        set { UserDefaults.standard.set(newValue, forKey: "checkIntervalHours") }
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

    /// Switch appearance, crossfading each visible window from its old look to
    /// its new one. A `CATransition` fade is captured by Core Animation from
    /// the live layer tree, so it works on glass windows — unlike a bitmap
    /// snapshot, and without the fade-out/fade-in "disappear" of animating the
    /// window's alpha.
    @MainActor static func apply(_ value: Appearance, animated: Bool = false) {
        if animated {
            for window in NSApp.windows where window.isVisible {
                guard let view = window.contentView?.superview ?? window.contentView else { continue }
                view.wantsLayer = true
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.4
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.layer?.add(fade, forKey: "appearanceCrossfade")
            }
        }
        set(value)
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
