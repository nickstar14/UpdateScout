import Testing
@testable import UpdateScout

/// Pure version logic: comparison, release tracks, major upgrades, item ids.
struct VersionTests {
    @Test(arguments: [
        ("1.2.10", "1.2.9"),
        ("v2.0", "1.9.9"),
        ("3.0.0", "3.0.0-beta.4"),
        ("3.0.0-beta.4", "3.0.0-alpha.10"),
        ("3.0.0-rc.1", "3.0.0-beta.9"),
        ("1.0.1", "1.0"),
        ("2.1,1234", "2.0,9999"),
    ])
    func newer(_ remote: String, _ local: String) {
        #expect(isNewerVersion(remote, than: local))
        #expect(!isNewerVersion(local, than: remote))
    }

    @Test func equalVersions() {
        #expect(compareVersions("1.0", "1.0.0") == .orderedSame)
        #expect(compareVersions("v1.2", "1.2") == .orderedSame)
        #expect(compareVersions("1.2,abc", "1.2_def") == .orderedSame)
    }

    @Test func releaseTracks() {
        #expect(VersionParts("2.0.0").track == 0)
        #expect(VersionParts("2.0.0-beta.1").track == 1)
        #expect(VersionParts("2.0.0-rc2").track == 1)
        #expect(VersionParts("2.0.0-alpha.3").track == 2)
        #expect(VersionParts("2.0.0-nightly").track == 2)
    }

    private func item(_ source: String, _ token: String, from old: String, to new: String) -> UpdateItem {
        UpdateItem(sourceID: source, name: "App", installedVersion: old, latestVersion: new,
                   url: nil, caveat: nil, installToken: token, scriptedInstall: true)
    }

    @Test func majorUpgrades() {
        #expect(item("sparkle", "x", from: "6.2", to: "8.0").isMajorUpgrade)
        #expect(item("homebrew", "cask:x", from: "1.9", to: "2.0").isMajorUpgrade)
        #expect(item("sparkle", "x", from: "6.2", to: "8.0").majorUpgradeSummary == "6 → 8")
        #expect(!item("sparkle", "x", from: "6.2", to: "6.3").isMajorUpgrade)
        #expect(!item("homebrew", "formula", from: "1.9", to: "2.0").isMajorUpgrade)
        #expect(!item("macos", "x", from: "26.1", to: "27.0").isMajorUpgrade)
        #expect(!item("sparkle", "x", from: "26106.1", to: "26200.1").isMajorUpgrade)
        #expect(!item("sparkle", "x", from: "0.9", to: "1.0").isMajorUpgrade)
    }

    /// Ignored and notified lists are keyed by this; it must never change.
    @Test func itemIDFormat() {
        #expect(item("homebrew", "cask:docker", from: "1", to: "2").id == "homebrew|cask:docker|App|2")
    }

    /// Betas see the beta channel; releases see only untagged appcast items.
    @Test func selfUpdateChannels() {
        #expect(SelfUpdaterDelegate.channels(forVersion: "2.0.0-beta.1") == ["beta"])
        #expect(SelfUpdaterDelegate.channels(forVersion: "2.0.0-rc.2") == ["beta"])
        #expect(SelfUpdaterDelegate.channels(forVersion: "2.0.0-alpha.1") == ["beta"])
        #expect(SelfUpdaterDelegate.channels(forVersion: "2.0.0").isEmpty)
        #expect(SelfUpdaterDelegate.channels(forVersion: "1.8.0").isEmpty)
    }
}
