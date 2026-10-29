import Foundation
import Sparkle

/// UpdateScout keeping *itself* up to date, via Sparkle + GitHub Releases.
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

    /// A running beta (any prerelease marker) also sees items tagged
    /// `sparkle:channel` beta; a release sees only untagged items.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Self.channels(forVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }

    static func channels(forVersion version: String) -> Set<String> {
        VersionParts(version).track > 0 ? ["beta"] : []
    }
}

@MainActor
enum SelfUpdater {
    private static let delegate = SelfUpdaterDelegate()

    static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: delegate,
        userDriverDelegate: nil
    )

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
