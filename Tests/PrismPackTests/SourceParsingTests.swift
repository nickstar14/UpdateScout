import Foundation
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

    @Test func softwareUpdateTitleWithComma() {
        let f = SystemUpdateSource.fields(of: "Title: Safari 18.1, for macOS Tahoe, Version: 18.1, Size: 140210KiB, Recommended: YES, Action: restart,")
        #expect(f["Title"] == "Safari 18.1, for macOS Tahoe")
        #expect(f["Version"] == "18.1")
        #expect(f["Action"] == "restart")
        let plain = SystemUpdateSource.fields(of: "Title: macOS Tahoe 27.1, Version: 27.1, Size: 1KiB, Recommended: YES,")
        #expect(plain["Title"] == "macOS Tahoe 27.1" && plain["Action"] == nil)
    }

    @Test func appcastHardwareRequirementsParsedAndMetHere() {
        let feed = """
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>2</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
        <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements></item>
        <item><sparkle:version>1</sparkle:version><sparkle:shortVersionString>1.0</sparkle:shortVersionString></item>
        </channel></rss>
        """
        let latest = AppcastParser.latestVersion(from: Data(feed.utf8), installed: "1.0", installedBuild: "1")
        #expect(latest?.hardwareRequirements == ["arm64"])
        #expect(latest?.displayVersion == "2.0")   // this build is arm64-only
        #expect(AppcastParser.meetsHardwareRequirements(["arm64"]))
    }

    @Test func appScanGoesOneFolderDeep() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("appscan-\(UUID().uuidString)").path
        defer { try? fm.removeItem(atPath: root) }
        for dir in ["Top.app/Contents/Inner.app", "Utilities/Tool.app", "Vendor/Deep/Hidden.app", "Vendor/Suite.app"] {
            try fm.createDirectory(atPath: "\(root)/\(dir)", withIntermediateDirectories: true)
        }
        try fm.createSymbolicLink(atPath: "\(root)/Linked", withDestinationPath: "\(root)/Utilities")
        let found = AppFolders.appPaths(in: [root]).map { String($0.dropFirst(root.count + 1)) }
        // Top level first; one folder down; never inside a bundle, deeper, or through a symlink.
        #expect(found == ["Top.app", "Utilities/Tool.app", "Vendor/Suite.app"])
        #expect(!AppFolders.isNested("\(root)/Top.app", roots: [root]))
        #expect(AppFolders.isNested("\(root)/Utilities/Tool.app", roots: [root]))
    }
}

/// App Store apps matched by their bundle's name among receipted apps.
struct AppStoreMatchTests {
    @Test func matchesTheBundleNameWhenTheFileNameDiffers() {
        let apps: [(path: String, names: [String])] = [
            ("/Applications/Pages Creator Studio.app", ["Pages"]),
            ("/Applications/Keynote Creator Studio.app", ["Keynote Creator Studio", "Keynote"]),
        ]
        #expect(Inventory.masMatch("Pages", among: apps) == "/Applications/Pages Creator Studio.app")
        #expect(Inventory.masMatch("keynote", among: apps) == "/Applications/Keynote Creator Studio.app")
        #expect(Inventory.masMatch("Numbers", among: apps) == nil)
    }

    @Test func twoMatchesCountAsNone() {
        let apps: [(path: String, names: [String])] = [("/Applications/A.app", ["Pages"]), ("/Applications/B.app", ["Pages"])]
        #expect(Inventory.masMatch("Pages", among: apps) == nil)
    }
}

/// Which of two copies is suggested to keep (Nick, 2 Nov 2026).
struct DuplicateChoiceTests {
    private func copy(_ path: String, _ version: String = "1.0", running: Bool = false, opened: Int = 0) -> Duplicates.Candidate {
        .init(path: path, version: version, running: running, opened: opened)
    }

    @Test func theOpenCopyWins() {
        #expect(Duplicates.preferred([copy("/Applications/Flux.app", "2.0", opened: 50),
                                      copy("/Users/x/Applications/Flux.app", running: true)]) == "/Users/x/Applications/Flux.app")
    }

    @Test func thenTheOneOpenedMost() {
        #expect(Duplicates.preferred([copy("/Applications/Flux.app", opened: 6),
                                      copy("/Users/x/Applications/Flux.app", opened: 31)]) == "/Users/x/Applications/Flux.app")
    }

    @Test func thenNewerThenApplications() {
        #expect(Duplicates.preferred([copy("/Applications/A.app", "1.0"), copy("/Applications/B.app", "1.1")]) == "/Applications/B.app")
        #expect(Duplicates.preferred([copy("/Users/x/Applications/A.app"), copy("/Applications/A.app")]) == "/Applications/A.app")
    }
}

struct MacOSAppTests {
    @Test func appleAppsWithoutAReceiptComeWithMacOS() {
        #expect(Inventory.isMacOSApp(bundleID: "com.apple.Safari", hasReceipt: false))
        #expect(!Inventory.isMacOSApp(bundleID: "com.apple.dt.Xcode", hasReceipt: true))
        #expect(!Inventory.isMacOSApp(bundleID: "org.herf.Flux", hasReceipt: false))
        #expect(!Inventory.isMacOSApp(bundleID: nil, hasReceipt: false))
    }
}

/// When "Use Homebrew's copy" is offered (Nick, 2 Nov 2026).
struct HomebrewCopyTests {
    private func copy(_ path: String, brew: Bool = false, store: Bool = false) -> Duplicates.Copy {
        .init(path: path, fromHomebrew: brew, fromAppStore: store)
    }

    @Test func offeredWhenOneCopyIsHomebrews() {
        #expect(Duplicates.homebrewCopy([copy("/Applications/Flux.app", brew: true), copy("/Users/x/Applications/Flux.app")])
                == "/Applications/Flux.app")
    }

    @Test func notOfferedOtherwise() {
        #expect(Duplicates.homebrewCopy([copy("/a/A.app"), copy("/b/A.app")]) == nil)
        #expect(Duplicates.homebrewCopy([copy("/a/A.app", brew: true), copy("/b/A.app", brew: true)]) == nil)
        #expect(Duplicates.homebrewCopy([copy("/a/A.app", brew: true), copy("/b/A.app", store: true)]) == nil)
        #expect(Duplicates.homebrewCopy([copy("/a/A.app", brew: true)]) == nil)
    }
}
