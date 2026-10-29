import Testing
@testable import PrismPack

/// Parsing the text and JSON the new package tools print.
struct SourceParsingTests {
    @Test func uvOutdatedList() {
        let text = """
        ruff v0.5.0 [required: ==0.5.0] [latest: 0.17.3]
        - ruff
        black v24.1.0 [latest: 25.1.0]
        - black
        - blackd
        """
        let tools = PythonSource.parseUVList(text)
        #expect(tools.count == 2)
        #expect(tools[0].name == "ruff" && tools[0].installed == "0.5.0" && tools[0].latest == "0.17.3" && tools[0].pinned)
        #expect(tools[1].name == "black" && !tools[1].pinned)
    }

    @Test func npmOutdatedSkipsNodeOwnedPackages() {
        let json: [String: Any] = [
            "cowsay": ["current": "1.5.0", "wanted": "1.5.0", "latest": "1.6.0"],
            "npm": ["current": "10.9.9", "latest": "11.0.0"],
            "corepack": ["current": "0.36.0", "latest": "0.40.0"],
        ]
        let pkgs = NPMSource.parse(json)
        #expect(pkgs.map(\.name) == ["cowsay"])
        #expect(pkgs.first?.latest == "1.6.0")
    }

    @Test func pinnedItemsStayOutOfBulkUpdates() {
        let pinned = UpdateItem(sourceID: "pip", name: "ruff", installedVersion: "0.5.0", latestVersion: "0.17.3",
                                url: nil, caveat: nil, installToken: "uvpin:ruff", scriptedInstall: true)
        #expect(pinned.isPinned)
    }
}
