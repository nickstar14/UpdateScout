import Foundation
import Testing
@testable import PrismPack

/// Adoption's checks and verdicts (docs/2.0.0-adoption.md, "Test cases").
struct AdoptionTests {
    private func cask(_ version: String = "3.7.5", pkg: Bool = false, quit: [String] = ["org.audacity"],
                      autoUpdates: Bool = false, tap: String? = "homebrew/cask") -> CaskIndex.CaskInfo {
        var info = CaskIndex.CaskInfo(token: "audacity", version: version, homepage: nil, appNames: ["Audacity.app"])
        info.apps = ["Audacity.app"]
        info.pkg = pkg
        info.quitIDs = quit
        info.autoUpdates = autoUpdates
        info.tap = tap
        return info
    }

    private func app(_ version: String = "3.7.5", id: String = "org.audacity", mas: Bool = false,
                     updater: String? = nil) -> AppFacts {
        AppFacts(name: "Audacity", path: "/Applications/Audacity.app", bundleID: id, version: version,
                 hasMASReceipt: mas, updater: updater)
    }

    @Test func sameVersionNoUpdaterIsRecommendedInPlace() throws {       // case 1
        let c = try #require(Adoption.evaluate(app: app(), cask: cask(), copies: 1, includeSelfUpdating: false))
        #expect(c.verdict == .recommended && c.method == .inPlace && !c.needsAdmin && c.isSafe)
        #expect(c.checks.contains("Name and bundle ID match") && c.checks.contains("Cask is current"))
    }

    @Test func olderVersionIsReplace() throws {                           // case 2
        let c = try #require(Adoption.evaluate(app: app("3.7.4"), cask: cask(), copies: 1, includeSelfUpdating: false))
        #expect(c.method == .replace && c.verdict == .worthConsidering && !c.isSafe)
    }

    @Test func pkgCaskIsReplaceWithPassword() throws {                    // case 3
        let c = try #require(Adoption.evaluate(app: app(), cask: cask(pkg: true), copies: 1, includeSelfUpdating: false))
        #expect(c.method == .replace && c.needsAdmin && c.verdict == .worthConsidering)
    }

    @Test func neverOffered() {                                           // cases 4, 5, 6
        #expect(Adoption.evaluate(app: app(mas: true), cask: cask(), copies: 1, includeSelfUpdating: true) == nil)
        #expect(Adoption.evaluate(app: app(), cask: cask(), copies: 2, includeSelfUpdating: true) == nil)
        // Same filename, different bundle id and version: name alone never counts.
        #expect(Adoption.evaluate(app: app("2.0", id: "com.other"), cask: cask(), copies: 1, includeSelfUpdating: true) == nil)
        #expect(Adoption.evaluate(app: app(id: "com.apple.audacity"), cask: cask(), copies: 1, includeSelfUpdating: true) == nil)
        #expect(Adoption.evaluate(app: app(), cask: cask(tap: "someone/tap"), copies: 1, includeSelfUpdating: true) == nil)
    }

    @Test func caskBehindVendorIsNotBetter() throws {                     // case 0
        let c = try #require(Adoption.evaluate(app: app(updater: "Sparkle"), cask: cask(), copies: 1,
                                               includeSelfUpdating: true, vendorLatest: "3.8.0"))
        #expect(c.verdict == .notBetter)
        #expect(c.reasons.first?.contains("older than the vendor's release") == true)
    }

    @Test func betaOnStableCaskIsNotBetter() throws {                     // case 0, beta
        let c = try #require(Adoption.evaluate(app: app("3.8.0-beta.2", id: "org.audacity"), cask: cask(), copies: 1,
                                               includeSelfUpdating: false))
        #expect(c.verdict == .notBetter)
    }

    @Test func caskOlderThanInstalledIsNotBetter() throws {
        let c = try #require(Adoption.evaluate(app: app("3.8.0"), cask: cask(), copies: 1, includeSelfUpdating: false))
        #expect(c.verdict == .notBetter)
    }

    @Test func selfUpdatingOnlyWhenIncluded() throws {
        #expect(Adoption.evaluate(app: app(updater: "Sparkle"), cask: cask(), copies: 1, includeSelfUpdating: false) == nil)
        #expect(Adoption.evaluate(app: app(), cask: cask(autoUpdates: true), copies: 1, includeSelfUpdating: false) == nil)
        let c = try #require(Adoption.evaluate(app: app(updater: "Sparkle"), cask: cask(), copies: 1, includeSelfUpdating: true))
        #expect(c.verdict == .worthConsidering && c.updater == "Sparkle")
    }

    @Test func cantRunHereIsHidden() {
        var intel = cask(); intel.intelOnly = true
        var newer = cask(); newer.minimumMacOS = "99"
        #expect(Adoption.evaluate(app: app(), cask: intel, copies: 1, includeSelfUpdating: false) == nil)
        #expect(Adoption.evaluate(app: app(), cask: newer, copies: 1, includeSelfUpdating: false) == nil)
    }

    // Office: the app shows 16.114.1, its build and the cask say 16.114.26102720.
    @Test func caskCountingBuildsMatchesTheBuild() {
        let app = AppFacts(name: "Microsoft OneNote", path: "/Applications/Microsoft OneNote.app",
                           bundleID: "com.microsoft.onenote.mac", version: "16.114.3", build: "16.114.26102720")
        #expect(Adoption.sameVersion(app, "16.114.26102720"))
        #expect(Adoption.comparable(app, to: "16.114.26102720") == "16.114.26102720")
        let older = AppFacts(name: "x", path: "/Applications/x.app", bundleID: "x", version: "16.114.1", build: "16.114.26102031")
        #expect(!Adoption.sameVersion(older, "16.114.26102720"))
        #expect(isNewerVersion("16.114.26102720", than: Adoption.comparable(older, to: "16.114.26102720")))
        // An ordinary app keeps using its own version.
        let plain = AppFacts(name: "y", path: "/Applications/y.app", bundleID: "y", version: "3.7.5", build: "42")
        #expect(Adoption.comparable(plain, to: "3.7.6") == "3.7.5")
    }

    @Test func buildSuffixCountsAsSameVersion() {
        #expect(Adoption.sameVersion("4", "4,2023.07"))
        #expect(!Adoption.sameVersion("4.1", "4,2023.07"))
    }

    // Case 11: at most one digest a week; snoozed and never are hidden.
    @Test func digestOncePerWeekAndHideLists() throws {
        let c = try #require(Adoption.evaluate(app: app(), cask: cask(), copies: 1, includeSelfUpdating: false))
        var s = Store.State()
        let now = Date()
        #expect(Adoption.merge(Adoption.Scan(candidates: [c]), into: &s, now: now).count == 1)
        #expect(Adoption.merge(Adoption.Scan(candidates: [c]), into: &s, now: now.addingTimeInterval(60)).isEmpty)
        s.adoptionSnoozed[c.hideKey] = now.addingTimeInterval(Adoption.snoozeInterval)
        #expect(s.visibleAdoptions.isEmpty)
        s.adoptionSnoozed = [:]
        s.adoptionNever.insert(c.hideKey)
        #expect(s.visibleAdoptions.isEmpty)
    }

    // Case 12 and state safety: candidates live apart from item ids.
    @Test func stateRoundTripKeepsHideListsAndCandidates() throws {
        let c = try #require(Adoption.evaluate(app: app(), cask: cask(), copies: 1, includeSelfUpdating: false))
        var s = Store.State()
        s.ignoredApps = ["homebrew|cask:x"]
        s.adoptionCandidates = [c]
        s.adoptionNever = ["org.other"]
        let back = try JSONDecoder().decode(Store.State.self, from: JSONEncoder().encode(s))
        #expect(back.ignoredApps == ["homebrew|cask:x"] && back.adoptionCandidates == [c] && back.adoptionNever == ["org.other"])
    }

    @Test func jobTokensAreChecked() throws {
        let job = Adopter.Job(action: "replace", cask: "low-profile", appPath: "/Applications/Low Profile.app")
        #expect(Adopter.Job(token: job.token) == job)
        #expect(Adopter.validToken("low-profile") && Adopter.validToken("visual-studio-code@insiders"))
        #expect(!Adopter.validToken("x; rm -rf ~") && !Adopter.validToken("../x") && !Adopter.validToken("a b"))
        // Adoption shares Homebrew's lane, so it never runs beside other brew work (case 10).
        #expect(UpdateController.lane(for: "adopt") == "brew")
    }
}

/// The progress shown during long moves.
struct MoveProgressTests {
    @Test func stepsFollowMarkersAndHomebrewHeadings() throws {
        let job = Adopter.Job(action: "switch", cask: "microsoft-onenote", appPath: "/Applications/Microsoft OneNote.app")
        var p = try #require(MoveProgress.plan(for: job.item(name: "Microsoft OneNote")))
        #expect(p.steps == [.trash, .download, .install, .check, .launch])
        p.take("§step:trash")
        p.take("§step:download")
        p.take("§download:500/1000")
        #expect(p.current == .download && p.done == [.trash] && p.downloadText != nil)
        #expect(abs(p.fraction - 0.3) < 0.001)                 // step 2 of 5, half downloaded
        p.take("==> Running installer for microsoft-onenote with `sudo`")
        #expect(p.current == .install && p.done.contains(.download))
        p.take("installer: The upgrade was successful.")
        #expect(p.detail == "installer: The upgrade was successful.")
    }
}
