import Foundation

/// Stable or Beta, chosen per app on its card (Phase 8).
enum Channel: String, CaseIterable, Identifiable {
    case stable, beta
    var id: String { rawValue }
    var title: String { self == .stable ? "Stable" : "Beta" }
}

/// Each app's chosen channel, keyed by bundle ID so it survives updates and
/// moves. No choice means "follow what's installed": a beta stays on betas, a
/// release on releases, as in 1.8.0.
enum Channels {
    private static let key = "channelChoices"

    static func choice(for bundleID: String?) -> Channel? {
        guard let bundleID else { return nil }
        return (UserDefaults.standard.dictionary(forKey: key)?[bundleID] as? String).flatMap(Channel.init)
    }

    static func set(_ channel: Channel, for bundleID: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[bundleID] = channel.rawValue
        UserDefaults.standard.set(all, forKey: key)
    }

    /// The release track to offer (0 stable, 1 beta-like, 2 alpha-like).
    /// Beta keeps someone already on an alpha on alphas.
    static func track(installed: Int, choice: Channel?) -> Int {
        switch choice {
        case .stable: 0
        case .beta: max(1, installed)
        case nil: installed
        }
    }

    /// The channel the card shows: the choice, else what's installed.
    static func effective(_ choice: Channel?, installedVersion: String) -> Channel {
        choice ?? (VersionParts(installedVersion).track > 0 ? .beta : .stable)
    }

    static func bundleID(at appPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: appPath + "/Contents/Info.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }
}
