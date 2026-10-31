import Foundation
import Testing
@testable import PrismPack

/// Stable / Beta choices (Phase 8 channels).
struct ChannelTests {
    /// 2.0 stable, 2.1 beta (tagged), 2.2-beta.1 (untagged, marker only).
    private let feed = Data("""
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
    <item><sparkle:version>30</sparkle:version><sparkle:shortVersionString>2.2-beta.1</sparkle:shortVersionString></item>
    <item><sparkle:version>20</sparkle:version><sparkle:shortVersionString>2.1</sparkle:shortVersionString>
    <sparkle:channel>beta</sparkle:channel></item>
    <item><sparkle:version>10</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString></item>
    </channel></rss>
    """.utf8)

    @Test func noChoiceFollowsWhatsInstalled() {
        #expect(AppcastParser.latestVersion(from: feed, installed: "1.9", installedBuild: "9")?.displayVersion == "2.0")
        #expect(AppcastParser.latestVersion(from: feed, installed: "2.1", installedBuild: "20")?.displayVersion == "2.2-beta.1")
    }

    @Test func betaChoiceOnStableSeesBetas() {
        let latest = AppcastParser.latestVersion(from: feed, installed: "2.0", installedBuild: "10", channel: .beta)
        #expect(latest?.displayVersion == "2.2-beta.1")
    }

    @Test func stableChoiceOnBetaSeesStableOnly() {
        let latest = AppcastParser.latestVersion(from: feed, installed: "2.2-beta.1", installedBuild: "30", channel: .stable)
        #expect(latest?.displayVersion == "2.0")
        #expect(!isNewerVersion("2.0", than: "2.2-beta.1"))   // so no update row, only "Go back"
    }

    @Test func goBackTargetOnlyForANewerBeta() {
        #expect(AppcastParser.stableBelow(from: feed, installed: "2.2-beta.1", installedBuild: "30")?.displayVersion == "2.0")
        #expect(AppcastParser.stableBelow(from: feed, installed: "2.1", installedBuild: "20")?.displayVersion == "2.0")
        #expect(AppcastParser.stableBelow(from: feed, installed: "2.0", installedBuild: "10") == nil)
    }

    @Test func betasDetected() {
        #expect(AppcastParser.offersBetas(feed))
        let stableOnly = Data("""
        <rss><channel><item><sparkle:shortVersionString>1.0</sparkle:shortVersionString></item></channel></rss>
        """.utf8)
        #expect(!AppcastParser.offersBetas(stableOnly))
    }

    @Test func trackRules() {
        #expect(Channels.track(installed: 2, choice: .beta) == 2)    // an alpha stays on alphas
        #expect(Channels.track(installed: 0, choice: .beta) == 1)
        #expect(Channels.track(installed: 2, choice: .stable) == 0)
        #expect(Channels.track(installed: 1, choice: nil) == 1)
        #expect(Channels.effective(nil, installedVersion: "3.0-rc.1") == .beta)
        #expect(Channels.effective(nil, installedVersion: "3.0") == .stable)
    }

    @Test func separateBetaCasksFound() {
        let index = Data(#"[{"token":"firefox","full_token":"firefox"},{"token":"firefox@nightly","full_token":"firefox@nightly"},{"token": "firefox@beta"},{"token":"thaw@beta"}]"#.utf8)
        let betas = CaskIndex.separateBetas(in: index)
        #expect(betas["firefox"] == ["firefox@beta", "firefox@nightly"])
        #expect(betas["thaw"] == ["thaw@beta"])
        #expect(betas.count == 2)
    }
}
