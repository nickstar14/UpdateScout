import Testing
@testable import PrismPack

/// Every brew caller shares one lane; other managers get their own.
struct LaneTests {
    @Test func lanes() {
        for id in ["homebrew", "caskOracle", "components", "custom"] {
            #expect(UpdateController.lane(for: id) == "brew")
        }
        #expect(UpdateController.lane(for: "sparkle") == "sparkle")
        #expect(UpdateController.lane(for: "npm") == "npm")
        #expect(UpdateController.lane(for: "pip") == "pip")
        #expect(UpdateController.lane(for: "mas") == "mas")
    }

    @Test func toolsBlockTheirPackages() {
        func formula(_ name: String) -> UpdateItem {
            UpdateItem(sourceID: "homebrew", name: name, installedVersion: "1", latestVersion: "2",
                       url: nil, caveat: nil, installToken: "formula:\(name)", scriptedInstall: true)
        }
        #expect(UpdateController.lanes(for: formula("node@22")) == ["brew", "npm"])
        #expect(UpdateController.lanes(for: formula("pipx")) == ["brew", "pip"])
        #expect(UpdateController.lanes(for: formula("uv")) == ["brew", "pip"])
        #expect(UpdateController.lanes(for: formula("mas")) == ["brew", "mas"])
        #expect(UpdateController.lanes(for: formula("rust")) == ["brew"])
        #expect(UpdateController.lanes(for: formula("z3")) == ["brew"])
        #expect(formula("rust").sectionID == "tools")
        #expect(formula("z3").sectionID == "homebrew")
    }
}
