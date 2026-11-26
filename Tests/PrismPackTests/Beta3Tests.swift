import Foundation
import Testing
@testable import PrismPack

/// Homebrew's same-version false alarm, any app or formula (first seen on a self-updating cask, 26 Nov 2026).
@Suite(.serialized)
struct BrewQuirkTests {
    static let roblox = "0.748.0.7481526,445548190fe44ee2"

    @Test func sameStringsAreTheQuirk() {
        #expect(BrewQuirks.isSameVersion(installed: Self.roblox, latest: Self.roblox))
        #expect(!BrewQuirks.isSameVersion(installed: "0.747.0.7471000,aaaa", latest: Self.roblox))
        #expect(!BrewQuirks.isSameVersion(installed: nil, latest: Self.roblox))
        #expect(!BrewQuirks.isSameVersion(installed: "", latest: ""))
    }

    @Test func recordsOncePerAppAndVersionThenDrains() {
        _ = BrewQuirks.drain()
        BrewQuirks.record(token: "roblox", version: Self.roblox)
        BrewQuirks.record(token: "roblox", version: Self.roblox)
        #expect(BrewQuirks.drain() == [BrewQuirks.Skipped(token: "roblox", version: Self.roblox)])
        #expect(BrewQuirks.drain().isEmpty)
    }

    @Test func formulaeAreCoveredToo() {
        _ = BrewQuirks.drain()
        BrewQuirks.record(token: "wget", version: "1.25.0", kind: "formula")
        let skipped = BrewQuirks.drain()
        #expect(skipped.count == 1)
        #expect(BrewQuirks.entry(for: skipped[0]).itemID == "quirk|formula:wget|1.25.0")
        #expect(!BrewQuirks.explanation(for: skipped[0]).contains("Roblox"))
    }

    @Test func entryIsKeyedAndFlagged() {
        let skipped = BrewQuirks.Skipped(token: "roblox", version: Self.roblox)
        let entry = BrewQuirks.entry(for: skipped)
        #expect(entry.isBrewQuirk)
        #expect(entry.itemID == "quirk|cask:roblox|\(Self.roblox)")
        #expect(entry.kind == .checked)
        #expect(BrewQuirks.report(for: skipped, brewVersion: "Homebrew 7").contains("roblox"))
    }
}

struct ActivityExportTests {
    @Test func homeFolderBecomesTilde() {
        #expect(ActivityExport.scrub("/Users/someone/Library/x", home: "/Users/someone") == "~/Library/x")
    }

    @Test func reportHasDetailsLogAndNoHomePath() {
        let entry = ActivityEntry(kind: .updated, title: "Roblox 1 to 1", detail: "Homebrew",
                                  itemID: "x", sourceID: "homebrew", seconds: 4,
                                  log: "line one\nline two",
                                  fromVersion: "1", toVersion: "1", how: "By you",
                                  command: "brew upgrade --cask roblox",
                                  appPath: NSHomeDirectory() + "/Applications/Roblox.app")
        let text = ActivityExport.text(entries: [entry], updates: [], brewVersion: "Homebrew 7", appVersion: "9.9")
        #expect(text.contains("PrismPack: 9.9"))
        #expect(text.contains("Versions: 1 (the same on both sides)"))
        #expect(text.contains("Command: brew upgrade --cask roblox"))
        #expect(text.contains("    line two"))
        #expect(!text.contains(NSHomeDirectory()))
    }

    @Test func olderHistoryWithoutNewFieldsStillLoads() throws {
        let json = #"{"id":"6F3C2B1A-0000-4000-8000-000000000001","date":0,"kind":"updated","title":"A","detail":"","seconds":1}"#
        let entry = try JSONDecoder().decode(ActivityEntry.self, from: Data(json.utf8))
        #expect(entry.fromVersion == nil)
        #expect(entry.title == "A")
    }
}
