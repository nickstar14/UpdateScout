import Foundation
import Testing
@testable import PrismPack

/// Fixes for 2.0.0-beta.2 (25 Nov 2026): the Caskroom repair, the automatic retry limit.
struct Beta2FixTests {
    private let signalError = """
        Error: signal: It seems there is already an App at '/opt/homebrew/Caskroom/signal/8.35.0/Signal.app'.
        """

    @Test func repairRecognisesAPlainVersionFolder() {
        let folder = BrewRepair.staleUpgradeFolder(in: signalError, token: "signal")
        #expect(folder?.path == "/opt/homebrew/Caskroom/signal/8.35.0")
    }

    @Test func repairStillRecognisesTheUpgradingFolder() {
        let out = "Error: x: It seems there is already an App at '/opt/homebrew/Caskroom/x/1.0.upgrading/X.app'."
        #expect(BrewRepair.staleUpgradeFolder(in: out, token: "x")?.lastPathComponent == "1.0.upgrading")
    }

    @Test func repairRefusesAnythingElse() {
        // wrong token, not under Caskroom, /Applications, other error
        #expect(BrewRepair.staleUpgradeFolder(in: signalError, token: "spotify") == nil)
        let apps = "It seems there is already an App at '/Applications/Signal.app'."
        #expect(BrewRepair.staleUpgradeFolder(in: apps, token: "signal") == nil)
        let other = "It seems there is already an App at '/opt/homebrew/Caskroom/signal/Signal.app'."
        #expect(BrewRepair.staleUpgradeFolder(in: other, token: "signal") == nil)
        #expect(BrewRepair.staleUpgradeFolder(in: "Error: no space left", token: "signal") == nil)
    }

    private func item() -> UpdateItem {
        UpdateItem(sourceID: "homebrew", name: "signal", installedVersion: "8.35.0", latestVersion: "8.36.0",
                   installToken: "cask:signal", scriptedInstall: true)
    }

    private func entry(_ kind: ActivityEntry.Kind, for item: UpdateItem) -> ActivityEntry {
        ActivityEntry(kind: kind, title: "signal", itemID: item.id)
    }

    @Test func automaticUpdatesGiveUpAfterTwoFailuresInARow() {
        let it = item()
        #expect(!AutoUpdate.hasGivenUp(it, activity: []))
        #expect(!AutoUpdate.hasGivenUp(it, activity: [entry(.failed, for: it)]))
        #expect(AutoUpdate.hasGivenUp(it, activity: [entry(.failed, for: it), entry(.failed, for: it)]))
        // A success or another app in between resets nothing it shouldn't.
        #expect(!AutoUpdate.hasGivenUp(it, activity: [entry(.failed, for: it), entry(.updated, for: it), entry(.failed, for: it)]))
    }
}

/// The password prompt's words say what it is for and what set it off.
struct PasswordTextTests {
    @Test func listsNamesPlainly() {
        #expect(PasswordText.list([]) == "your apps")
        #expect(PasswordText.list(["Signal"]) == "Signal")
        #expect(PasswordText.list(["Signal", "Spotify"]) == "Signal and Spotify")
        #expect(PasswordText.list(["A", "B", "C"]) == "A, B and C")
        #expect(PasswordText.list(["A", "B", "C", "D", "E"]) == "A, B, C and 2 more")
    }

    @Test func saysWhatSetItOff() {
        #expect(PasswordText.purpose(apps: ["Signal"], cause: .you) == "to update Signal, which you started")
        #expect(PasswordText.purpose(apps: ["Signal", "Spotify"], cause: .you) == "to update 2 apps you started: Signal and Spotify")
        #expect(PasswordText.purpose(apps: ["Signal"], cause: .automatic) == "to update your apps automatically: Signal")
        #expect(PasswordText.purpose(apps: ["Signal"], cause: .repair) == "to repair and update Signal")
        #expect(PasswordText.detail(count: 1).hasSuffix("Cancel leaves it for later."))
        #expect(PasswordText.detail(count: 3).hasSuffix("Cancel leaves them for later."))
    }
}
