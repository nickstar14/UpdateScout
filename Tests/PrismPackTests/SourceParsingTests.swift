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

    @Test func cargoInstallList() {
        let text = """
        cargo-edit v0.13.0:
            cargo-add
            cargo-rm
        ripgrep v14.1.0:
            rg
        mytool v0.1.0 (/Users/me/src/mytool):
            mytool
        """
        let crates = CargoSource.parseList(text)
        #expect(crates.map(\.name) == ["cargo-edit", "ripgrep"])
        #expect(crates.last?.version == "14.1.0")
    }

    @Test func gemOutdatedSkipsBundledGems() {
        let outdated = GemSource.parseOutdated("rake (13.0.6 < 13.2.1)\njson (2.7.2 < 2.9.1)\n")
        #expect(outdated.map(\.name) == ["rake", "json"])
        #expect(outdated.first?.latest == "13.2.1")
        let bundled = GemSource.defaultOnly("json (default: 2.7.2)\nrake (13.0.6)\nbigdecimal (3.1.8, default: 3.1.6)\n")
        #expect(bundled == ["json"])
    }

    @Test func editorExtensionList() {
        let exts = EditorExtensionsSource.parseList("esbenp.prettier-vscode@12.4.0\nms-python.python@2026.4.0\nnoise\n")
        #expect(exts.map(\.id) == ["esbenp.prettier-vscode", "ms-python.python"])
        #expect(exts.first?.version == "12.4.0")
    }

    @Test func extensionEngineRange() {
        #expect(EditorExtensionsSource.engineAllows("^1.90.0", editor: "1.144.0"))
        #expect(!EditorExtensionsSource.engineAllows("^1.150.0", editor: "1.144.0"))
        #expect(EditorExtensionsSource.engineAllows(">=1.80", editor: "1.80.0"))
        #expect(EditorExtensionsSource.engineAllows("*", editor: "1.0"))
        #expect(EditorExtensionsSource.engineAllows("^1.90.0", editor: nil))
    }
}
