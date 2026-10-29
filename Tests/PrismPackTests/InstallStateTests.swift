import Testing
@testable import PrismPack

/// How install progress lines map to the states the cards show.
struct InstallStateTests {
    @Test func classifiesLines() {
        #expect(InstallState(progressLine: "Downloading… 3 MB / 10 MB (30%)") == .downloading(percent: 30, line: "Downloading… 3 MB / 10 MB (30%)"))
        #expect(InstallState(progressLine: "==> Downloading https://example.com/a.zip") == .downloading(percent: nil, line: "==> Downloading https://example.com/a.zip"))
        #expect(InstallState(progressLine: "Needs your password to replace this app…") == .needsAdmin)
        #expect(InstallState(progressLine: "==> Upgrading foo") == .installing("==> Upgrading foo"))
    }

    @Test func activeStates() {
        #expect(InstallState.queued.isActive)
        #expect(InstallState.cancelling.isActive)
        #expect(!InstallState.failed("x").isActive)
        #expect(!InstallState.done.isActive)
        #expect(InstallState.failed("boom").errorMessage == "boom")
        #expect(InstallState.queued.errorMessage == nil)
    }
}
