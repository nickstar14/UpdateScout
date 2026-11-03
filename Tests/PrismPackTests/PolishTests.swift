import Foundation
import Testing
@testable import PrismPack

/// Small fixes from the Phase 9 polish list, on temp folders only.
struct PolishTests {
    @Test func appPathKeepsTheNameAsOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("polish-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Itsycal.app"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(AppLocator.realCase(of: dir.path + "/itsycal.app") == dir.path + "/Itsycal.app")
        #expect(AppLocator.realCase(of: dir.path + "/Missing.app") == dir.path + "/Missing.app")
    }
}
