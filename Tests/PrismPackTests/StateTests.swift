import Foundation
import Testing
@testable import PrismPack

/// state.json stays readable both ways: old files load, new fields survive.
struct StateTests {
    @Test func oldFileLoadsWithDefaults() throws {
        let old = #"{"items":[],"dismissed":["a"],"notified":[]}"#
        let state = try JSONDecoder().decode(Store.State.self, from: Data(old.utf8))
        #expect(state.dismissed == ["a"])
        #expect(state.ignoredApps.isEmpty && state.ignoredMajors.isEmpty && state.activity.isEmpty)
    }

    @Test func newFieldsRoundTrip() throws {
        var state = Store.State()
        state.ignoredApps = ["homebrew|formula:z3"]
        state.log(ActivityEntry(kind: .updated, title: "z3 5.3.2 to 5.3.3"))
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(Store.State.self, from: data)
        #expect(back.ignoredApps == ["homebrew|formula:z3"])
        #expect(back.activity.first?.title == "z3 5.3.2 to 5.3.3")
    }

    @Test func activityIsKeptUntilDeleted() {
        var state = Store.State()
        for i in 0..<250 { state.log(ActivityEntry(kind: .checked, title: "\(i)")) }
        #expect(state.activity.count == 250)
        #expect(state.activity.first?.title == "249")
    }
}
