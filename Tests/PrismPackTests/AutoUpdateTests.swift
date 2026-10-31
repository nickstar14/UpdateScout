import Foundation
import Testing
@testable import PrismPack

/// Which updates may install on their own (Phase 8 auto-update rules).
struct AutoUpdateTests {
    private func item(_ source: String = "npm", from: String = "1.5.0", to: String = "1.6.0",
                      token: String = "cowsay", scripted: Bool = true) -> UpdateItem {
        UpdateItem(sourceID: source, name: "cowsay", installedVersion: from, latestVersion: to,
                   installToken: token, scriptedInstall: scripted)
    }

    private func blocker(_ item: UpdateItem, hidden: Bool = false, pinned: Bool = false, admin: Bool = false,
                         open: Bool = false, enabled: Bool = true, rule: AutoUpdate.Rule? = nil) -> String? {
        AutoUpdate.blocker(item, hidden: hidden, pinned: pinned, needsAdmin: admin, appOpen: open,
                           enabled: enabled, rule: rule)
    }

    @Test func plainUpdateInstallsWhenOn() {
        #expect(blocker(item()) == nil)
        #expect(blocker(item(), enabled: false) == "Automatic updates are off")
    }

    @Test func perAppRulesOverrideTheSwitch() {
        #expect(blocker(item(), enabled: false, rule: .always) == nil)
        #expect(blocker(item(), rule: .never) == "Set to never update automatically")
    }

    @Test func neverAutomatic() {
        #expect(blocker(item(), hidden: true) == "Hidden")
        #expect(blocker(item(), pinned: true) == "Pinned")
        #expect(blocker(item(), admin: true) == "Needs your password")
        #expect(blocker(item(), open: true) == "Open right now")
        #expect(blocker(item(to: "1.6.0-beta.2")) == "Beta")
        #expect(blocker(item("sparkle", from: "2.4", to: "3.0", token: "/Applications/X.app")) == "Major upgrade")
        for source in ["macos", "custom", "mas", "components", "caskOracle"] {
            #expect(blocker(item(source)) == "Only updated by hand")
        }
        #expect(blocker(item(scripted: false)) == "Only updated by hand")
        // Always doesn't override the safety rules.
        #expect(blocker(item(), admin: true, rule: .always) == "Needs your password")
    }

    @Test func schedule() {
        let now = Date()
        #expect(AutoUpdate.isDue(now: now, last: nil, schedule: .daily))
        #expect(!AutoUpdate.isDue(now: now, last: now.addingTimeInterval(-3600), schedule: .daily))
        #expect(AutoUpdate.isDue(now: now, last: now.addingTimeInterval(-23.5 * 3600), schedule: .daily))
        #expect(!AutoUpdate.isDue(now: now, last: now.addingTimeInterval(-3 * 86400), schedule: .weekly))
        #expect(AutoUpdate.isDue(now: now, last: now.addingTimeInterval(-7 * 86400), schedule: .weekly))
        #expect(AutoUpdate.isDue(now: now, last: now, schedule: .everyCheck))
    }

    @Test func ruleIsSavedAndCleared() {
        let key = "test|\(UUID().uuidString)"
        AutoUpdate.setRule(.always, for: key)
        #expect(AutoUpdate.rule(for: key) == .always)
        AutoUpdate.setRule(nil, for: key)
        #expect(AutoUpdate.rule(for: key) == nil)
    }
}
