import Foundation
import Sparkle

/// PrismPack keeping *itself* up to date, via Sparkle + GitHub Releases.
/// Feed URL and EdDSA public key live in Info.plist (SUFeedURL / SUPublicEDKey).
/// Sparkle does its own HTTP fetching and honours `Cache-Control`, and
/// raw.githubusercontent.com serves the appcast with `max-age=300`. That makes a
/// just-published release invisible to the updater for minutes ("You're up to
/// date" when you aren't). A changing query parameter sidesteps the cache —
/// GitHub ignores unknown query params and serves the same file.
final class SelfUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        guard let base = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return nil }
        return base + "?t=\(Int(Date().timeIntervalSince1970))"
    }

    /// Items tagged `sparkle:channel` beta are seen when Beta is chosen on
    /// PrismPack's own card, or, with no choice, when the running version is
    /// a beta (any prerelease marker). Otherwise only untagged items.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        switch Channels.choice(for: Bundle.main.bundleIdentifier) {
        case .beta: return ["beta"]
        case .stable: return []
        case nil: return Self.channels(forVersion: version)
        }
    }

    /// Sparkle is about to restart us after "Install and Relaunch": reopen the
    /// window on the way back up, rather than only the menu bar icon.
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        UserDefaults.standard.set(true, forKey: SelfUpdater.reopenWindowKey)
        AppDelegate.skipQuitPrompt = true
    }

    static func channels(forVersion version: String) -> Set<String> {
        VersionParts(version).track > 0 ? ["beta"] : []
    }
}

@MainActor
enum SelfUpdater {
    private static let delegate = SelfUpdaterDelegate()
    /// Set just before Sparkle relaunches the app; cleared on the next launch.
    nonisolated static let reopenWindowKey = "reopenWindowAfterUpdate"

    static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: delegate,
        userDriverDelegate: nil
    )

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// Start Sparkle's scheduled checks at launch. Without this the lazy
    /// `controller` was only created by a manual Check for Updates, so no
    /// automatic check ever ran. Never called from the headless background check.
    static func start() {
        if AppIdentity.isFreshProfile { return }
        _ = controller
    }

    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
