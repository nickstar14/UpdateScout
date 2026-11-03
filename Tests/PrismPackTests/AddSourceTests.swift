import Foundation
import Testing
@testable import PrismPack

/// Add a Source: guessing where a page keeps its version, and adding or
/// removing entries in a custom_sources.json (a temp file, never the real one).
struct AddSourceTests {
    private func entry(_ name: String) -> CustomSource.Entry {
        CustomSource.Entry(name: name, remoteURL: "https://example.com/v.json", remoteJSONPath: "version")
    }

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("addsource-\(UUID().uuidString)").appendingPathComponent("custom_sources.json")
    }

    @Test func guessesCommonJSONKeys() {
        #expect(CustomSource.guessRemote(Data(#"{"version":"1.2"}"#.utf8)).jsonPath == "version")
        #expect(CustomSource.guessRemote(Data(#"{"tag_name":"v3"}"#.utf8)).jsonPath == "tag_name")
        #expect(CustomSource.guessRemote(Data(#"{"release":{"version":"2.0"}}"#.utf8)).jsonPath == "release.version")
    }

    @Test func guessesAPatternForText() {
        let guess = CustomSource.guessRemote(Data("Download App 4.12.1 now".utf8))
        #expect(guess.jsonPath == nil)
        var e = entry("x"); e.remoteJSONPath = nil; e.remoteRegex = guess.regex
        #expect(CustomSource.parseRemote(Data("Download App 4.12.1 now".utf8), e) == "4.12.1")
    }

    @Test func addKeepsExistingAndRejectsDuplicates() throws {
        let url = tempFile()
        try CustomSource.add(entry("One"), to: url)
        try CustomSource.add(entry("Two"), to: url)
        #expect(throws: Error.self) { try CustomSource.add(entry("one"), to: url) }
        let names = try JSONDecoder().decode([CustomSource.Entry].self, from: Data(contentsOf: url)).map(\.name)
        #expect(names == ["One", "Two"])
    }

    @Test func removeDeletesOnlyThatEntry() throws {
        let url = tempFile()
        try CustomSource.add(entry("One"), to: url)
        try CustomSource.add(entry("Two"), to: url)
        try CustomSource.remove(named: "One", from: url)
        let names = try JSONDecoder().decode([CustomSource.Entry].self, from: Data(contentsOf: url)).map(\.name)
        #expect(names == ["Two"])
    }
}
