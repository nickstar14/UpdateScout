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

    @MainActor static func apply(_ value: Appearance, animated: Bool = false) {
        guard animated else { return set(value) }
        // AppKit can't crossfade an appearance change, and snapshotting glass
        // windows produces garbage. Fade fully out, switch while invisible
        // (so the instant repaint is never seen), and ease back in.
        let windows = NSApp.windows.filter { $0.isVisible }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            windows.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            set(value)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    windows.forEach { $0.animator().alphaValue = 1 }
                }
            }
        })
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
        case .clear: 0.35
        case .regular: 0.7
        case .tinted: 0.92
        }
    }
    /// Accepts the pre-rename stored values ("middle"/"frosted") too.
    static func from(_ raw: String) -> GlassStyle {
        GlassStyle(rawValue: raw)
            ?? (raw == "middle" ? .regular : raw == "frosted" ? .tinted : .regular)
    }
}
