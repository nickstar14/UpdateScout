import Foundation
import Testing
@testable import PrismPack

/// Leftover cleanup (Phase 9). Everything runs in a temporary folder that
/// stands in for `~/Library`; nothing touches the real one or the Trash.
struct LeftoverTests {
    let root: URL
    var library: URL { root.appendingPathComponent("Library") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("leftovers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func make(_ path: String, plist: [String: Any]? = nil) throws {
        let url = library.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let plist {
            (plist as NSDictionary).write(to: url, atomically: true)
        } else if url.pathExtension.isEmpty || url.pathExtension == "savedState" {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url.appendingPathComponent("data"))
        } else {
            try Data("x".utf8).write(to: url)
        }
    }

    private func app(_ id: String, helpers: [String: String] = [:]) throws -> String {
        let app = root.appendingPathComponent("Foo.app")
        for (sub, helperID) in [("", id)] + helpers.map({ ($0.key, $0.value) }) {
            let contents = sub.isEmpty ? app.appendingPathComponent("Contents")
                                       : app.appendingPathComponent("Contents/\(sub)/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            (["CFBundleIdentifier": helperID, "CFBundleName": "Foo"] as NSDictionary)
                .write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        }
        return app.path
    }

    private func names(_ found: [Leftovers.Found]) -> [String] {
        found.map { String($0.path.dropFirst(library.path.count + 1)) }
    }

    @Test func idSafety() {
        #expect(Leftovers.isSafeID("com.example.foo"))
        #expect(!Leftovers.isSafeID("com.apple.Safari"))
        #expect(!Leftovers.isSafeID("COM.APPLE.Safari"))
        #expect(!Leftovers.isSafeID("foo"))
        #expect(!Leftovers.isSafeID("com.example."))
        // Apple's group folders, with a prefix (seen on Nick's Mac, 31 Oct 2026).
        #expect(!Leftovers.isSafeID("group.com.apple.notes"))
        #expect(!Leftovers.isSafeID("243LU875E5.groups.com.apple.podcasts"))
        #expect(!Leftovers.isSafeID("group.com.apple.siri.userfeedbacklearning"))
    }

    @Test func helpersMustStartWithTheAppID() throws {
        let path = try app("com.example.foo", helpers: [
            "Library/LoginItems/FooLauncher.app": "com.example.fooLauncher",
            "XPCServices/Helper.xpc": "com.example.foo.helper",
            "XPCServices/Installer.xpc": "org.sparkle-project.InstallerLauncher",
            "PlugIns/Share.appex": "com.example.shared",
            "Frameworks/Bar.framework/XPCServices/X.xpc": "com.example.foo.framework",
        ])
        let ids = Set(Leftovers.helperIDs(inApp: path, bundleID: "com.example.foo"))
        #expect(ids == ["com.example.fooLauncher", "com.example.foo.helper"])
    }

    @Test func findsExactMatchesOnly() throws {
        let uuid = UUID().uuidString
        let host = UUID().uuidString
        try make("Application Support/com.example.foo")
        try make("Application Support/com.example.foobar")          // other app, same start
        try make("Caches/com.example.foo.helper")
        try make("Preferences/com.example.foo.plist")
        try make("Preferences/com.example.foo.other.plist")          // not ours
        try make("Preferences/ByHost/com.example.foo.\(host).plist")
        try make("Preferences/ByHost/com.example.foo.notahost.plist")
        try make("Containers/com.example.foo")
        try make("Containers/\(uuid)")
        try make("Containers/\(uuid)/.com.apple.containermanagerd.metadata.plist",
                 plist: ["MCMMetadataIdentifier": "com.example.foo"])
        try make("Containers/\(UUID().uuidString)/.com.apple.containermanagerd.metadata.plist",
                 plist: ["MCMMetadataIdentifier": "com.other.app"])
        try make("Application Scripts/com.example.foo")
        try make("Saved Application State/com.example.foo.savedState")
        try make("HTTPStorages/com.example.foo.binarycookies")
        try make("WebKit/com.example.foo")
        try make("Logs/com.example.foo")
        try make("LaunchAgents/com.example.foo.agent.plist", plist: ["Label": "com.example.foo.agent"])
        try make("LaunchAgents/misleading.plist", plist: ["Label": "com.example.foobar"])
        try make("Group Containers/ABCDE12345.com.example.group")
        try make("Group Containers/ABCDE12345.com.example.other")
        try make("Application Support/Foo")

        let identity = Leftovers.Identity(appPath: "/gone/Foo.app", name: "Foo", bundleID: "com.example.foo",
                                          helperIDs: ["com.example.foo.helper"],
                                          appGroups: ["ABCDE12345.com.example.group"], names: ["Foo"])
        let found = Leftovers.scan(identity, library: library)
        let byID = Set(names(found.filter { $0.match == .id }))
        #expect(byID == [
            "Application Support/com.example.foo", "Caches/com.example.foo.helper",
            "Preferences/com.example.foo.plist", "Preferences/ByHost/com.example.foo.\(host).plist",
            "Containers/com.example.foo", "Containers/\(uuid)", "Application Scripts/com.example.foo",
            "Saved Application State/com.example.foo.savedState", "HTTPStorages/com.example.foo.binarycookies",
            "WebKit/com.example.foo", "Logs/com.example.foo", "LaunchAgents/com.example.foo.agent.plist",
        ])
        #expect(names(found.filter { $0.match == .group }) == ["Group Containers/ABCDE12345.com.example.group"])
        #expect(names(found.filter { $0.match == .name }) == ["Application Support/Foo"])
        #expect(found.filter(\.tickedByDefault).count == byID.count)
        #expect(found.first { $0.path.hasSuffix("agent.plist") }?.label == "com.example.foo.agent")
        #expect(found.first { $0.path.hasSuffix("Application Support/com.example.foo") }!.size > 0)
    }

    @Test func linkedFolderIsSkippedAndLinksMoveAsLinks() async throws {
        let outside = root.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("com.example.foo"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        // A Library folder that's a link to somewhere else: skipped.
        try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("Caches"), withDestinationURL: outside)
        // A leftover that's a link: found, and only the link moves.
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Logs"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: library.appendingPathComponent("Logs/com.example.foo"),
                                                   withDestinationURL: outside.appendingPathComponent("com.example.foo"))

        let identity = Leftovers.Identity(appPath: "/gone/Foo.app", name: "Foo", bundleID: "com.example.foo")
        let found = Leftovers.scan(identity, library: library)
        #expect(names(found) == ["Logs/com.example.foo"])
        #expect(found[0].size == 0)

        let trash = root.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let outcome = await Leftovers.moveToTrash(found, library: library) { url in
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }
        #expect(outcome.moved.count == 1)
        #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("com.example.foo").path))
        #expect(Leftovers.isLink(trash.appendingPathComponent("com.example.foo")))
    }

    @Test func movedItemsAreCheckedAgain() async throws {
        try make("Logs/com.example.foo")
        let identity = Leftovers.Identity(appPath: "/gone/Foo.app", name: "Foo", bundleID: "com.example.foo")
        var found = Leftovers.scan(identity, library: library)
        try FileManager.default.removeItem(at: library.appendingPathComponent("Logs/com.example.foo"))
        // Outside the Library it was scanned in.
        found.append(Leftovers.Found(path: "/tmp/com.example.foo", folder: "/tmp", match: .id, size: 0))
        let outcome = await Leftovers.moveToTrash(found, library: library) { _ in Issue.record("nothing should move") }
        #expect(outcome.moved.isEmpty)
        #expect(outcome.failed.count == 2)
    }

    @Test func groupContainersAreNeverMoved() async throws {
        try make("Group Containers/ABCDE12345.com.example.group")
        let identity = Leftovers.Identity(appPath: "/gone/Foo.app", name: "Foo", bundleID: "com.example.foo",
                                          appGroups: ["ABCDE12345.com.example.group"])
        let found = Leftovers.scan(identity, library: library)
        #expect(found.count == 1 && !found[0].movable)
        let outcome = await Leftovers.moveToTrash(found, library: library) { _ in Issue.record("nothing should move") }
        #expect(outcome.moved.isEmpty && outcome.failed.count == 1)
    }

    @Test func aMoveThatLeavesTheItemIsAFailure() async throws {
        // macOS 27 reported a protected folder as moved and left it (31 Oct 2026).
        try make("Logs/com.example.foo")
        let identity = Leftovers.Identity(appPath: "/gone/Foo.app", name: "Foo", bundleID: "com.example.foo")
        let found = Leftovers.scan(identity, library: library)
        let outcome = await Leftovers.moveToTrash(found, library: library) { _ in }
        #expect(outcome.moved.isEmpty)
        #expect(outcome.failed.first?.needsFullDiskAccess == true)
    }

    @Test func appleContainerIsNeverMatched() throws {
        // A container whose own metadata says it's Apple's, whatever its name.
        try make("Containers/com.example.foo/.com.apple.containermanagerd.metadata.plist",
                 plist: ["MCMMetadataIdentifier": "com.apple.quicklook.ThumbnailsAgent"])
        let identity = Leftovers.Identity(appPath: "/gone/Foo.app", name: "Foo", bundleID: "com.example.foo")
        #expect(Leftovers.scan(identity, library: library).isEmpty)
    }

    @Test func orphansAreOnlyUnownedAppIDs() throws {
        try make("Application Support/com.example.gone")
        try make("Caches/com.example.gone")
        try make("Preferences/com.example.gone.plist")
        try make("Application Support/com.example.installed")         // owned
        try make("Caches/com.example.installed.helper")               // owned helper
        try make("Caches/com.example.knownelsewhere")                 // macOS knows it
        try make("Caches/com.apple.Safari")                           // Apple
        try make("Application Support/Some Folder")                   // not an ID
        try make("Caches/two.parts")                                  // not ID-shaped
        try make("Caches/com.example.kept")                           // kept
        try make("LaunchAgents/com.example.gone.agent.plist",
                 plist: ["Label": "com.example.gone.agent", "ProgramArguments": ["/nonexistent/agent"]])
        try make("LaunchAgents/com.example.tool.plist",
                 plist: ["Label": "com.example.tool", "Program": "/bin/sleep"])  // program still there
        try make("Group Containers/ABCDE12345.com.example.group")     // same vendor installed
        try make("Group Containers/XYZ9876543.net.other.shared")      // nobody's
        try make("Group Containers/group.com.apple.notes")            // Apple
        try make("Application Scripts/group.net.other.scripts")       // a group outside Group Containers
        try make("Application Scripts/group.com.example.group")       // same vendor installed
        try make("Group Containers/243LU875E5.groups.com.apple.podcasts")
        try make("Containers/\(UUID().uuidString)/.com.apple.containermanagerd.metadata.plist",
                 plist: ["MCMMetadataIdentifier": "group.com.apple.siri.userfeedbacklearning"])

        var owners = Leftovers.Owners()
        owners.appIDs = ["com.example.installed"]
        owners.vendors = ["com.example"]
        let orphans = Leftovers.orphans(library: library, owners: owners, kept: ["com.example.kept"],
                                        knownToMacOS: { $0 == "com.example.knownelsewhere" })
        let ids = Set(orphans.map(\.id))
        #expect(ids == ["com.example.gone", "XYZ9876543.net.other.shared", "group.net.other.scripts"])
        #expect(orphans.first { $0.id == "group.net.other.scripts" }?.items.allSatisfy { !$0.movable } == true)
        let gone = try #require(orphans.first { $0.id == "com.example.gone" })
        #expect(gone.items.count == 4)
        #expect(gone.lastChanged != nil)
        #expect(gone.sameDeveloper)
        #expect(gone.items.contains { $0.label == "com.example.gone.agent" })
        #expect(orphans.first { $0.id.hasPrefix("XYZ") }?.isGroup == true)
    }

    @Test func zapList() throws {
        let json = """
        {"casks":[{"token":"foo","artifacts":[{"app":["Foo.app"]},
          {"zap":[{"trash":["~/Library/Caches/com.example.foo","~/Library/Preferences/com.example.foo.plist"],
                   "rmdir":"~/Library/Foo"}]}]}]}
        """
        let zap = try #require(Zap.parse(Data(json.utf8)))
        #expect(zap.trash.count == 2)
        #expect(zap.delete == ["~/Library/Foo"])
        #expect(!zap.needsPassword)

        let system = """
        {"casks":[{"token":"bar","artifacts":[{"pkg":["Bar.pkg"]},
          {"zap":[{"trash":"/Library/Application Support/Bar","launchctl":"com.example.bar.daemon"}]}]}]}
        """
        let sysZap = try #require(Zap.parse(Data(system.utf8)))
        #expect(sysZap.needsPassword)
        #expect(sysZap.other == ["Stop background job com.example.bar.daemon"])
        #expect(sysZap.summary.contains("To the Trash:"))
    }
}

/// "Belongs to…" (Phase 10 step 9): files the user assigned to an installed
/// app leave the orphan list and are found with that app's own. A temporary
/// folder stands in for `~/Library`; no real data folder or settings.
struct AssignedOrphanTests {
    let root: URL
    var library: URL { root.appendingPathComponent("Library") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("assigned-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for path in ["Application Support/com.example.stray", "Caches/com.example.stray",
                     "Application Support/com.example.other", "Application Support/com.example.owner",
                     "Application Support/com.apple.fake", "Group Containers/group.com.example.shared"] {
            let url = library.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url.appendingPathComponent("data"))
        }
    }

    private func owners(_ ids: [String]) -> Leftovers.Owners {
        var owners = Leftovers.Owners()
        owners.appIDs = Set(ids)
        return owners
    }

    private func identity(_ id: String) -> Leftovers.Identity {
        Leftovers.Identity(appPath: root.appendingPathComponent("Owner.app").path, name: "Owner", bundleID: id)
    }

    @Test func assignedFilesLeaveTheOrphanList() {
        let assigned = ["com.example.owner": ["com.example.stray"]]
        let ids = Set(Leftovers.orphans(library: library, owners: owners(["com.example.owner"]), assigned: assigned,
                                        knownToMacOS: { _ in false }).map(\.id))
        #expect(!ids.contains("com.example.stray"))
        #expect(ids.contains("com.example.other"))
    }

    @Test func anAssignmentToAnAppThatIsGoneIsIgnored() {
        let assigned = ["com.example.owner": ["com.example.stray"]]
        let ids = Set(Leftovers.orphans(library: library, owners: owners(["com.example.somethingelse"]), assigned: assigned,
                                        knownToMacOS: { _ in false }).map(\.id))
        #expect(ids.contains("com.example.stray"))
    }

    @Test func theOwnersScanFindsItsAssignedFilesTicked() {
        let found = Leftovers.scan(identity("com.example.owner"), library: library, assigned: ["com.example.stray"])
        let strays = found.filter { $0.path.contains("com.example.stray") }
        #expect(strays.count == 2)
        #expect(strays.allSatisfy { $0.assigned && $0.tickedByDefault && $0.movable })
        #expect(found.contains { $0.path.hasSuffix("Application Support/com.example.owner") && !$0.assigned })
        #expect(!found.contains { $0.path.contains("com.example.other") })
    }

    @Test func withoutAnAssignmentNothingExtraIsFound() {
        let found = Leftovers.scan(identity("com.example.owner"), library: library)
        #expect(!found.contains { $0.path.contains("com.example.stray") })
    }

    @Test func whatCanNeverBeAssigned() {
        #expect(Leftovers.canAssign("com.example.stray"))
        #expect(!Leftovers.canAssign("com.apple.fake"))
        #expect(!Leftovers.canAssign("group.com.example.shared"))
        #expect(!Leftovers.canAssign("ABCDE12345.com.example.shared"))
        #expect(!Leftovers.canAssign("nodots"))
    }

    @Test func anUnsafeAssignedIDIsNeverScanned() {
        let found = Leftovers.scan(identity("com.example.owner"), library: library,
                                   assigned: ["com.apple.fake", "group.com.example.shared"])
        #expect(!found.contains { $0.path.contains("com.apple.fake") })
        #expect(!found.contains { $0.path.contains("group.com.example.shared") })
    }
}
