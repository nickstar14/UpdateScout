import Testing
@testable import UpdateScout

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
}
