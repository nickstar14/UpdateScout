import Foundation
import Testing
@testable import PrismPack

/// The 2.0 rename's early migration, on temp folders only (nothing real).
struct RenameMigrationTests {
    @Test func carriesOnlyWhatTheNewDomainLacks() {
        let old: [String: Any] = ["appearance": "dark", "checkIntervalMinutes": 30,
                                  "migrationLevel": 9, "recheckPermissions": true]
        let out = EarlyMigration.carriedPreferences(old: old, existing: ["appearance": "light"])
        #expect(out["appearance"] == nil)                // the new domain's own value wins
        #expect(out["checkIntervalMinutes"] as? Int == 30)
        #expect(out["migrationLevel"] == nil)            // the ledger isn't copied
        #expect(out["recheckPermissions"] == nil)
    }

    @Test func menuBarPositionKeysAreRenamed() {
        let old: [String: Any] = ["NSStatusItem Preferred Position UpdateScoutStatusItem": 1234.0]
        let out = EarlyMigration.carriedPreferences(old: old, existing: [:])
        #expect(out["NSStatusItem Preferred Position PrismPackStatusItem"] as? Double == 1234.0)
        #expect(out.count == 1)
    }

    private func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rename-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func movesTheDataFolder() throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("UpdateScout"), new = root.appendingPathComponent("PrismPack")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try "state".write(to: old.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        #expect(EarlyMigration.moveSupportFolder(from: old, to: new) == .moved)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(try String(contentsOf: new.appendingPathComponent("state.json"), encoding: .utf8) == "state")
    }

    @Test func replacesAnEmptyNewFolderButNeverANonEmptyOne() throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        let old = root.appendingPathComponent("UpdateScout"), new = root.appendingPathComponent("PrismPack")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        try "a".write(to: old.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        #expect(EarlyMigration.moveSupportFolder(from: old, to: new) == .moved)   // new was empty

        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try "b".write(to: old.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        #expect(EarlyMigration.moveSupportFolder(from: old, to: new) == .bothExist)
        #expect(fm.fileExists(atPath: old.appendingPathComponent("state.json").path))   // untouched
        #expect(try String(contentsOf: new.appendingPathComponent("state.json"), encoding: .utf8) == "a")
    }

    @Test func nothingToMoveWhenThereIsNoOldFolder() throws {
        let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(EarlyMigration.moveSupportFolder(from: root.appendingPathComponent("UpdateScout"),
                                                 to: root.appendingPathComponent("PrismPack")) == .nothingToMove)
    }
}

/// The release list behind Settings → Release notes, from text only.
struct ReleaseHistoryTests {
    @Test func parsesAndDropsDrafts() {
        let json = """
        [{"tag_name":"v2.0.0-beta.1","name":"PrismPack 2.0.0-beta.1","body":"## Hi","html_url":"https://x/1","published_at":"2026-11-05T10:00:00Z","draft":false,"prerelease":true},
         {"tag_name":"v9","name":null,"body":null,"html_url":"https://x/9","published_at":null,"draft":true,"prerelease":false},
         {"tag_name":"v1.8.0","name":"UpdateScout 1.8.0","body":null,"html_url":"https://x/2","published_at":"2026-10-01T10:00:00Z","draft":false,"prerelease":false}]
        """
        let entries = ReleaseHistory.parse(Data(json.utf8))
        #expect(entries.map(\.tag) == ["v2.0.0-beta.1", "v1.8.0"])
        #expect(entries[0].version == "2.0.0-beta.1" && entries[0].prerelease)
        #expect(entries[1].body == "" && entries[1].date != nil)
        #expect(ReleaseHistory.visible(entries, includePrereleases: false).map(\.tag) == ["v1.8.0"])
        #expect(ReleaseHistory.parse(Data("nonsense".utf8)).isEmpty)
    }

    @Test func channelChoiceMovesToTheNewBundleID() {
        let old: [String: Any] = [Legacy.bundleID: "beta", "com.other.app": "stable"]
        let out = EarlyMigration.carriedChannelChoices(old, newID: "com.nickszun.prismpack")
        #expect(out?["com.nickszun.prismpack"] as? String == "beta")
        #expect(out?["com.other.app"] as? String == "stable")
        #expect(EarlyMigration.carriedChannelChoices(["com.nickszun.prismpack": "stable", Legacy.bundleID: "beta"],
                                                     newID: "com.nickszun.prismpack") == nil)
        #expect(EarlyMigration.carriedChannelChoices(nil, newID: "x") == nil)
    }
}
