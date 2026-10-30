import Foundation
import Testing
@testable import PrismPack

/// GitHub releases: which download is picked, and the version a tag means.
struct GitHubReleasesTests {
    private func release(_ names: [String], tag: String = "v1.0.2") -> GitHubAPI.Release {
        GitHubAPI.Release(tag: tag, notes: nil, htmlURL: "",
                          assets: names.map { GitHubAPI.Asset(name: $0, url: "https://x/\($0)", size: 1) })
    }

    @Test func tagsLoseTheirV() {
        #expect(release([], tag: "v1.0.2").version == "1.0.2")
        #expect(release([], tag: "2.3").version == "2.3")
    }

    @Test func picksTheMacDownloadForThisMac() {
        #expect(GitHubAPI.pickAsset(release(["ClaudeCounter.dmg"]))?.name == "ClaudeCounter.dmg")
        #expect(GitHubAPI.pickAsset(release(["App-x86_64.dmg", "App-arm64.dmg"]))?.name == "App-arm64.dmg")
        #expect(GitHubAPI.pickAsset(release(["App-universal.zip", "App.pkg"]))?.name == "App-universal.zip")
        #expect(GitHubAPI.pickAsset(release(["App-windows.exe", "App-linux.tar.gz", "App-intel.dmg"])) == nil)
        #expect(GitHubAPI.pickAsset(release(["Source code.tar.gz"])) == nil)
    }
}
