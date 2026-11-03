import Testing
import Foundation
@testable import PrismPack

/// Discover's local search, recently-added bookkeeping and install routing.
struct DiscoverTests {
    private func entry(_ kind: DiscoverEntry.Kind, _ name: String, _ summary: String? = nil, pop: Int = 0) -> DiscoverEntry {
        DiscoverEntry(kind: kind, name: name, title: name, summary: summary, version: "1", popularity: pop)
    }

    @Test func handMadeCategoryBeatsTheGuess() {
        // Its description says "browser" nowhere; the list puts it in Browsers.
        #expect(DiscoverCategories.category(of: entry(.cask, "zen", "Gecko based web browser")) == .browsers)
        #expect(DiscoverCategories.category(of: entry(.cask, "codex", "OpenAI's coding agent that runs in your terminal")) == .developer)
    }

    @Test func guessesFromTheDescription() {
        #expect(DiscoverCategories.guess("Game Boy Advance emulator") == .games)
        #expect(DiscoverCategories.guess("Desktop client that supports multiple LLM providers") == .ai)
        #expect(DiscoverCategories.guess("Dynamic Island for the MacBook notch") == .menuBar)
        #expect(DiscoverCategories.guess("Calendar software focusing on flexibility and reliability") == .productivity)
        #expect(DiscoverCategories.guess("Open-source BitTorrent client") == .cloud)
        #expect(DiscoverCategories.guess("Virtual Audio Driver") == .audio)
    }

    @Test func guessAvoidsKnownMisfits() {
        // Found while checking the rules against every cask.
        #expect(DiscoverCategories.guess("Bluetooth Low Energy browser") != .browsers)
        #expect(DiscoverCategories.guess("Apply and analyze cryptographic algorithms") != .design)
        #expect(DiscoverCategories.guess("Graphically shows disk usage within a file system") != .design)
        #expect(DiscoverCategories.guess("") == nil)
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

    @Test func sortsByPopularityNameAndDates() {
        let day: TimeInterval = 86_400, now = Date()
        var a = entry(.cask, "alpha", pop: 5), b = entry(.cask, "bravo", pop: 50), c = entry(.cask, "charlie", pop: 20)
        a.added = now - 2 * day; b.added = nil; c.added = now - day
        a.updated = now; c.updated = now - 3 * day
        let names = { (sort: DiscoverModel.Sort) in DiscoverModel.sorted([a, b, c], by: sort).map(\.name) }
        #expect(names(.popular) == ["bravo", "charlie", "alpha"])
        #expect(names(.name) == ["alpha", "bravo", "charlie"])
        // Undated ones go last, most popular first.
        #expect(names(.newest) == ["charlie", "alpha", "bravo"])
        #expect(names(.updated) == ["alpha", "charlie", "bravo"])
        // Reversed flips the order; undated ones stay last.
        let back = { (sort: DiscoverModel.Sort) in DiscoverModel.sorted([a, b, c], by: sort, reversed: true).map(\.name) }
        #expect(back(.popular) == ["alpha", "charlie", "bravo"])
        #expect(back(.name) == ["charlie", "bravo", "alpha"])
        #expect(back(.newest) == ["alpha", "charlie", "bravo"])
    }

    @Test func versionChangesAreDatedFromTheSecondLook() {
        let then = Date(timeIntervalSince1970: 1_000), now = Date(timeIntervalSince1970: 2_000)
        let changed = DiscoverCatalog.testTrackVersions(
            old: ["cask:a": "1", "cask:b": "1", "cask:gone": "1"], changed: ["cask:b": then],
            current: [("cask:a", "2"), ("cask:b", "1"), ("cask:new", "1")], now: now)
        #expect(changed == ["cask:a": now, "cask:b": then])
    }

    @Test func registryTextAndVersionsAreTidied() {
        #expect(DiscoverRegistries.plain("[ripgrep](https://github.com/x) in a ![badge](https://b.svg) package")
                == "ripgrep in a package")
        #expect(DiscoverRegistries.plain("  ") == nil)
        var edge = entry(.cask, "microsoft-edge")
        edge.version = "156.0.4314.58,bc665d48-ec9a-4625"
        #expect(edge.shortVersion == "156.0.4314.58")
        #expect(entry(.cask, "zen").shortVersion == "1")
    }

    @Test func installedSortsWithUnmeasuredLast() {
        let a = InstalledPackage(name: "Alpha", version: "1", sourceID: "homebrew")
        let b = InstalledPackage(name: "bravo", version: "1", sourceID: "npm")
        let c = InstalledPackage(name: "Charlie", version: "1", sourceID: "homebrew")
        let sizes: [String: Int64] = [a.id: 10, c.id: 30]
        let names = { (sort: String, reversed: Bool) in
            InstalledMetrics.sorted([a, b, c], by: sort, reversed: reversed, sizes: sizes, dates: [:]).map(\.name)
        }
        #expect(names("name", false) == ["Alpha", "bravo", "Charlie"])
        #expect(names("name", true) == ["Charlie", "bravo", "Alpha"])
        #expect(names("size", false) == ["Charlie", "Alpha", "bravo"])
        #expect(names("size", true) == ["Alpha", "Charlie", "bravo"])
        #expect(names("date", false) == ["Alpha", "bravo", "Charlie"])
    }

    @Test @MainActor func releaseNotesPreviewSkipsHeadingsAndLinks() {
        let notes = """
        ## What's Changed
        * fix(macos): retry stapler validate by @aiongg in https://github.com/x/pull/1116
        * Add [TextureCraft](https://x.com) to the suite
        * Third line
        """
        #expect(UpdateDetailView.preview(notes) == "fix(macos): retry stapler validate by @aiongg\nAdd TextureCraft to the suite")
        #expect(UpdateDetailView.preview("<h2>Changes</h2><ul><li>Faster sync</li></ul>") == "Faster sync")
        #expect(UpdateDetailView.preview("## What's new") == nil)
    }
}

/// Font previews: cask names to Google Fonts families, and the CSS answer.
struct FontPreviewTests {
    @Test func caskTitlesBecomeFamilies() {
        #expect(FontPreviewName.family(forCask: "font-inter", title: "Inter") == "Inter")
        // Google wants the family's own capitals.
        #expect(FontPreviewName.family(forCask: "font-jetbrains-mono", title: "JetBrains Mono") == "JetBrains Mono")
        #expect(FontPreviewName.family(forCask: "font-ibm-plex-sans", title: "IBM Plex Sans (IBM)") == "IBM Plex Sans")
        // No title worth using: the token, word by word.
        #expect(FontPreviewName.family(forCask: "font-open-sans", title: "font-open-sans") == "Open Sans")
    }

    @Test func fontsGoogleLacksShowTheirNameOnly() {
        #expect(FontPreviewName.family(forCask: "font-fira-code-nerd-font", title: "FiraCode Nerd Font (Fira Code)") == nil)
        #expect(FontPreviewName.family(forCask: "font-maple-mono-nf", title: "Maple Mono NF") == nil)
        #expect(FontPreviewName.family(forCask: "firefox", title: "Firefox") == nil)
    }

    @Test func readsTheFontFileFromGoogleCSS() {
        let css = "@font-face { font-family: 'Inter'; src: url(https://fonts.gstatic.com/l/font?kit=abc) format('truetype'); }"
        #expect(FontPreviewName.fontURL(inCSS: css)?.host == "fonts.gstatic.com")
        // Only Google's own file host is followed.
        #expect(FontPreviewName.fontURL(inCSS: "src: url(https://example.com/x.ttf)") == nil)
        #expect(FontPreviewName.fontURL(inCSS: "no url here") == nil)
    }

    @Test func asksForOnlyTheSampleLetters() {
        let url = FontPreviewName.cssURL(family: "Open Sans")
        #expect(url?.host == "fonts.googleapis.com")
        #expect(url?.query?.contains("family=Open%20Sans") == true || url?.query?.contains("family=Open+Sans") == true)
    }
}

/// Install progress: phases from the lines a source reports, and a percentage
/// only where one was really measured.
struct InstallProgressTests {
    private func run(_ lines: [String]) -> InstallProgress {
        var p = InstallProgress()
        lines.forEach { p.take($0) }
        return p
    }

    @Test func downloadBytesGiveARealPercent() {
        let p = run(["§step:download", "§download:300/1200"])
        #expect(p.phase == .download)
        #expect(p.percentText == 25)
        #expect(p.bytesText?.contains(" of ") == true)
    }

    @Test func aCompleteDownloadIsBeingVerified() {
        let p = run(["§step:prepare", "§download:1200/1200"])
        #expect(p.phase == .verify)
        #expect(p.fraction == nil)
        // The watcher keeps reporting; the phase stays put.
        var q = p
        q.take("§download:1200/1200")
        #expect(q.phase == .verify)
    }

    @Test func bytesWithoutATotalGiveNoPercent() {
        let p = run(["§download:5000/0"])
        #expect(p.phase == .download)
        #expect(p.fraction == nil)
        #expect(p.bytesText != nil)
    }

    @Test func brewHeadingsMoveThroughThePhases() {
        #expect(run(["==> Downloading https://example.com/a.dmg"]).phase == .download)
        #expect(run(["==> Downloading x", "==> Installing Cask x"]).phase == .install)
        #expect(run(["==> Installing Cask x", "==> Moving App 'X.app' to '/Applications/X.app'"]).phase == .move)
        #expect(run(["==> Running installer for x"]).phase == .vendor)
        #expect(run(["==> Purging files for version 1 of Cask x"]).phase == .cleanup)
        #expect(run(["Unzipping the archive"]).phase == .unpack)
    }

    @Test func aFormulaInstallsThroughItsOwnHeadings() {
        #expect(run(["==> Fetching downloads for: hello"]).phase == .download)
        #expect(run(["==> Fetching downloads for: hello", "==> Reinstalling hello"]).phase == .install)
        #expect(run(["==> Pouring hello--2.12.3.arm64_golden_gate.bottle.1.tar.gz"]).phase == .install)
        #expect(run(["§step:prepare"]).phase == .prepare)
        #expect(run(["§step:prepare", "§download:10/100"]).phase == .download)
    }

    @Test func noPercentWhereNothingIsMeasured() {
        let p = run(["==> Installing Cask x", "==> Moving App 'X.app' to '/Applications/X.app'"])
        #expect(p.fraction == nil)
    }

    @Test func theMacOSInstallersOwnPercentIsUsed() {
        let p = run(["installer: Percent complete: 45"])
        #expect(p.phase == .vendor)
        #expect(p.percentText == 45)
    }

    @Test func aPhaseChangeDropsTheOldPercent() {
        let p = run(["installer: Percent complete: 90", "==> Purging files for version 1 of Cask x"])
        #expect(p.phase == .cleanup)
        #expect(p.fraction == nil)
    }

    @Test func sparklesDownloadLineCarriesItsPercent() {
        let p = run(["Downloading… 12 MB / 50 MB (24%)"])
        #expect(p.phase == .download)
        #expect(p.percentText == 24)
    }

    @Test func theLineSaysTheTimeOnlyAfterAMinuteWhenUnmeasured() {
        var p = run(["==> Installing Cask x"])
        p.startedAt = Date(timeIntervalSinceNow: -161)
        #expect(p.line(now: .now).contains("2:41"))
        p.startedAt = Date(timeIntervalSinceNow: -20)
        #expect(!p.line(now: .now).contains(":"))
    }
}

/// The font pop-up's style list.
struct FontStyleTests {
    @Test func weightsHaveTheirUsualNames() {
        #expect(FontStyleName.name(weight: 400, italic: false) == "Regular")
        #expect(FontStyleName.name(weight: 400, italic: true) == "Italic")
        #expect(FontStyleName.name(weight: 600, italic: false) == "SemiBold")
        #expect(FontStyleName.name(weight: 700, italic: true) == "Bold Italic")
        #expect(FontStyleName.name(weight: 100, italic: false) == "Thin")
        #expect(FontStyleName.name(weight: 900, italic: false) == "Black")
    }

    @Test func readsTheStylesFromGoogleCSS() {
        let css = """
        @font-face { font-style: italic; font-weight: 700; src: url(https://fonts.gstatic.com/l/font?kit=b) format('truetype'); }
        @font-face { font-style: normal; font-weight: 400; src: url(https://fonts.gstatic.com/l/font?kit=a) format('truetype'); }
        @font-face { font-style: normal; font-weight: 700; src: url(https://fonts.gstatic.com/l/font?kit=c) format('truetype'); }
        """
        let faces = FontStyleName.faces(inCSS: css)
        #expect(faces.map(\.name) == ["Regular", "Bold", "Bold Italic"])
        #expect(FontStyleName.summary(faces) == "3 styles (2 upright, 1 italic)")
    }

    @Test func aFamilyWithoutItalicsSaysJustTheCount() {
        let css = "@font-face { font-style: normal; font-weight: 400; src: url(https://fonts.gstatic.com/l/font?kit=a) format('truetype'); }"
        #expect(FontStyleName.summary(FontStyleName.faces(inCSS: css)) == "1 style")
    }

    @Test func asksForEveryStyleButOnlyTheSampleLetters() {
        let url = FontStyleName.cssURL(family: "Inter", text: "Aa")
        #expect(url?.host == "fonts.googleapis.com")
        #expect(url?.absoluteString.contains("900i") == true)
    }
}
