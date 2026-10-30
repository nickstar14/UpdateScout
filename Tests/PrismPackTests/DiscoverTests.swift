import Testing
import Foundation
@testable import PrismPack

/// Discover's local search, recently-added bookkeeping and install routing.
struct DiscoverTests {
    private func entry(_ kind: DiscoverEntry.Kind, _ name: String, _ summary: String? = nil, pop: Int = 0) -> DiscoverEntry {
        DiscoverEntry(kind: kind, name: name, title: name, summary: summary, version: "1", popularity: pop)
    }

    @Test func searchRanksExactThenPrefixThenContains() {
        let entries = [entry(.formula, "ripmime", pop: 900), entry(.formula, "ripgrep", pop: 50),
                       entry(.formula, "grip", pop: 10), entry(.cask, "searcher", "rip through files"),
                       entry(.formula, "rip", pop: 1)]
        #expect(DiscoverCatalog.search("rip", in: entries).map(\.name) == ["rip", "ripmime", "ripgrep", "grip", "searcher"])
        #expect(DiscoverCatalog.search("  ", in: entries).isEmpty)
    }

    @Test func recentlyAddedComparesWithLastLook() {
        let now = Date()
        // First look: nothing to compare with, so nothing is "new".
        #expect(DiscoverCatalog.testDiff(knownIDs: [], added: [], current: ["cask:a"], now: now).isEmpty)
        // Second look: the new one shows; old entries expire after 30 days.
        let old = now.addingTimeInterval(-31 * 24 * 3600)
        #expect(DiscoverCatalog.testDiff(knownIDs: ["cask:a", "cask:b"], added: [("cask:b", old)],
                                         current: ["cask:a", "cask:b", "formula:c"], now: now) == ["formula:c"])
    }

    @Test func installsUseTheRightLane() {
        #expect(DiscoverInstaller.lane(of: "cask:firefox") == "brew")
        #expect(DiscoverInstaller.lane(of: "formula:ripgrep") == "brew")
        #expect(DiscoverInstaller.lane(of: "pipx:ruff") == "pip")
        #expect(DiscoverInstaller.lane(of: "ext-codium:ms-python.python") == "editors")
        let node = DiscoverInstaller.item(for: entry(.formula, "node"))
        #expect(UpdateController.lanes(for: node) == ["brew", "npm"])
        let crate = DiscoverInstaller.item(for: entry(.crate, "ripgrep"))
        #expect(crate.installToken == "cargo:ripgrep" && UpdateController.lanes(for: crate) == ["cargo"])
    }

    @Test func installedKeysMatchEntries() {
        let cask = InstalledPackage(name: "Firefox", version: "1", sourceID: "homebrew", detail: "cask firefox")
        #expect(cask.discoverKey == entry(.cask, "firefox").installKey)
        let ext = InstalledPackage(name: "ms-python.python (VSCodium)", version: "1", sourceID: "editors")
        #expect(ext.discoverKey == entry(.ext, "MS-Python.python").installKey)
    }

    @Test func iconLinksPreferTouchIconThenLargestSize() {
        let html = """
        <link rel="icon" href="/favicon-16.png" sizes="16x16">
        <LINK REL="shortcut icon" HREF="//cdn.example.com/fav.ico">
        <link rel="icon" sizes="192x192" href="icons/big.png">
        <link rel='apple-touch-icon' href='/touch.png?v=2&amp;x=1'>
        <link rel="stylesheet" href="/site.css">
        """
        let links = DiscoverIcons.iconLinks(in: html, base: URL(string: "https://example.com/app/")!)
        #expect(links.map(\.absoluteString) == [
            "https://example.com/touch.png?v=2&x=1",
            "https://example.com/app/icons/big.png",
            "https://example.com/favicon-16.png",
            "https://cdn.example.com/fav.ico",
        ])
    }

    @Test func removalsMatchWhereThingsCameFrom() {
        func token(_ pkg: InstalledPackage) -> String? { Removal(pkg)?.token }
        #expect(token(InstalledPackage(name: "Itsycal", version: "1", sourceID: "homebrew",
                                       appPath: "/Applications/Itsycal.app", detail: "cask itsycal")) == "cask:itsycal")
        #expect(token(InstalledPackage(name: "cowsay", version: "1", sourceID: "homebrew", detail: "formula")) == "formula:cowsay")
        #expect(token(InstalledPackage(name: "ruff", version: "1", sourceID: "pip", detail: "uv tool")) == "uv:ruff")
        #expect(token(InstalledPackage(name: "black", version: "1", sourceID: "pip", detail: "pipx")) == "pipx:black")
        #expect(token(InstalledPackage(name: "corepack", version: "1", sourceID: "npm", detail: "updated with node")) == nil)
        #expect(token(InstalledPackage(name: "Xcode", version: "1", sourceID: "mas",
                                       appPath: "/Applications/Xcode.app")) == "app:/Applications/Xcode.app")
        #expect(token(InstalledPackage(name: "Self", version: "1", sourceID: "unmanaged",
                                       appPath: Bundle.main.bundlePath)) == nil)
        #expect(Removal(entry(.ext, "oderwat.indent-rainbow")).token == "ext-all:oderwat.indent-rainbow")
        #expect(DiscoverInstaller.lane(of: "uv:ruff") == "pip")
        #expect(DiscoverInstaller.lane(of: "app:/Applications/X.app") == "app")
    }

    @Test func stateSurvivesAnActivityKindItDoesNotKnow() throws {
        let json = """
        {"dismissed": ["a|b|c|1"], "ignoredApps": ["homebrew|x"],
         "activity": [{"id": "6B29FC40-CA47-1067-B31D-00DD010662DA", "date": "2026-10-30T10:00:00Z",
                       "kind": "somethingNew", "title": "From a newer build", "detail": ""},
                      {"id": "6B29FC40-CA47-1067-B31D-00DD010662DB", "date": "2026-10-30T10:00:00Z",
                       "kind": "removed", "title": "Itsycal", "detail": ""}]}
        """
        let state = try Store.decode(Data(json.utf8))
        #expect(state.dismissed == ["a|b|c|1"])
        #expect(state.ignoredApps == ["homebrew|x"])
        #expect(state.activity.map(\.title) == ["Itsycal"])
    }
}
