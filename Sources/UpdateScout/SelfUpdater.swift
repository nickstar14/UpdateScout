import Foundation
import Sparkle

/// UpdateScout keeping *itself* up to date, via Sparkle + GitHub Releases.
/// Feed URL and EdDSA public key live in Info.plist (SUFeedURL / SUPublicEDKey).
@MainActor
enum SelfUpdater {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
