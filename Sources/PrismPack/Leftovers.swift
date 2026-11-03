import AppKit
import Security

/// What an app leaves in the user's own Library once it's in the Trash
/// (Phase 9). Matches by exact bundle ID only; folders that match just the
/// app's name, and shared group folders, are listed but not ticked. Only
/// ever looks inside `~/Library`, and only ever moves things to the Trash.
enum Leftovers {
    /// Read from the app before it goes to the Trash.
    struct Identity: Hashable, Sendable {
        let appPath: String
        let name: String
        let bundleID: String
        /// Login items, XPC services, plug-ins and helper apps inside the app
        /// whose IDs start with the app's own ID.
        var helperIDs: [String] = []
        /// From the `application-groups` entitlement.
        var appGroups: [String] = []
        /// The folder name and the bundle's own names, for name matches.
        var names: [String] = []

        var ids: [String] { [bundleID] + helperIDs }
    }

    struct Found: Identifiable, Hashable, Sendable {
        enum Match: Sendable { case id, name, group }
        var id: String { path }
        let path: String
        /// The Library folder it sits in, checked again before it moves.
        let folder: String
        let match: Match
        let size: Int64
        /// The launchd label of a LaunchAgent, stopped before it moves.
        var label: String? = nil
        /// Found because the user said it belongs to this app ("Belongs to…").
        var assigned = false

        var tickedByDefault: Bool { match == .id }
        /// Group containers are shown with Show in Finder only. On macOS 27
        /// moving one reported success while the folder stayed put (31 Oct
        /// 2026 test), and a stuck system container can't be emptied from the
        /// Trash (Pearcleaner #616).
        var movable: Bool { match != .group }
    }

    static var userLibrary: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
    }

    // MARK: Before the Trash

    /// The app's IDs, or nil when it has none safe to match on.
    static func identity(ofApp path: String) -> Identity? {
        let url = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, isSafeID(id) else { return nil }
        let folderName = url.deletingPathExtension().lastPathComponent
        var names = [folderName]
        for key in ["CFBundleName", "CFBundleDisplayName"] {
            if let name = bundle.object(forInfoDictionaryKey: key) as? String,
               !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                names.append(name)
            }
        }
        return Identity(appPath: path, name: folderName, bundleID: id,
                        helperIDs: helperIDs(inApp: path, bundleID: id),
                        appGroups: CodeSign.appGroups(path).filter { !$0.lowercased().hasPrefix("com.apple.") },
                        names: names.filter { $0.count >= 3 })
    }

    /// Never Apple's, never one without a dot, never PrismPack's own.
    static func isSafeID(_ id: String) -> Bool {
        let lower = id.lowercased()
        // Apple's own, with or without a prefix: group.com.apple.notes,
        // 243LU875E5.groups.com.apple.podcasts. Moved to the Trash, Apple's
        // protected folders can leave it impossible to empty (Pearcleaner #616).
        let apple = lower.hasPrefix("com.apple.") || lower.contains(".com.apple.") || lower.contains(".apple.")
            || lower.hasPrefix("apple.")
        return lower.contains(".") && !apple && !lower.hasPrefix(".") && !lower.hasSuffix(".")
            && lower != Bundle.main.bundleIdentifier?.lowercased()
    }

    /// Bundles and agents inside an app: login items, XPC services,
    /// plug-ins, helpers, SMAppService agents. With `frameworks`, also the
    /// XPC services inside its frameworks (Sparkle's), for deciding who owns
    /// what, never for what to remove.
    static func nestedBundles(inApp path: String, frameworks: Bool = false) -> [(id: String, path: String)] {
        let contents = URL(fileURLWithPath: path).appendingPathComponent("Contents")
        let fm = FileManager.default
        var dirs = ["Library/LoginItems", "XPCServices", "PlugIns", "Helpers", "Library/LaunchAgents",
                    "Library/LaunchServices", "Library/SystemExtensions"].map { contents.appendingPathComponent($0) }
        if frameworks {
            let fw = contents.appendingPathComponent("Frameworks")
            for entry in (try? fm.contentsOfDirectory(atPath: fw.path)) ?? [] where entry.hasSuffix(".framework") {
                dirs.append(fw.appendingPathComponent(entry).appendingPathComponent("XPCServices"))
                dirs.append(fw.appendingPathComponent(entry).appendingPathComponent("Versions/Current/XPCServices"))
            }
        }
        var found: [(id: String, path: String)] = []
        for dir in dirs {
            for entry in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                let item = dir.appendingPathComponent(entry)
                // SMAppService agents: the label is what launchd and the Library use.
                let id = item.pathExtension == "plist" ? NSDictionary(contentsOf: item)?["Label"] as? String
                                                       : Bundle(url: item)?.bundleIdentifier
                if let id, !found.contains(where: { $0.id == id }) { found.append((id, item.path)) }
            }
        }
        return found
    }

    /// Helpers bundled inside the app (not inside its frameworks), whose IDs
    /// start with the app's own: `com.example.foo.helper`, `com.example.fooLauncher`.
    /// Shared helpers (Sparkle's, a vendor's common updater) don't qualify.
    static func helperIDs(inApp path: String, bundleID: String) -> [String] {
        nestedBundles(inApp: path).map(\.id).filter { id in
            isSafeID(id) && id.lowercased().hasPrefix(bundleID.lowercased()) && id.lowercased() != bundleID.lowercased()
        }
    }

    // MARK: After the Trash

    /// Another installed copy with the same ID still uses these files.
    static func otherCopy(of identity: Identity, among apps: [String] = AppFolders.appPaths()) -> String? {
        let gone = URL(fileURLWithPath: identity.appPath).standardizedFileURL.path
        return apps.first { path in
            URL(fileURLWithPath: path).standardizedFileURL.path != gone
                && Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier?.lowercased() == identity.bundleID.lowercased()
        }
    }

    /// The Library folders searched, with the ID matches first.
    static let idFolders = ["Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers",
                            "Application Scripts", "Saved Application State", "HTTPStorages", "WebKit", "Logs",
                            "LaunchAgents"]

    /// The app ID an item in one of `idFolders` (or Group Containers) is
    /// named for, or nil when it isn't named for one. A container's owner
    /// comes from its own metadata when there is any, so an Apple container
    /// with a harmless-looking name is still recognised as Apple's.
    static func namedID(_ entry: String, in sub: String, at url: URL) -> String? {
        func stem(_ suffix: String) -> String? {
            entry.lowercased().hasSuffix(suffix) ? String(entry.dropLast(suffix.count)) : nil
        }
        switch sub {
        case "Preferences": return stem(".plist")
        case "Preferences/ByHost":
            // <id>.<hardware UUID>.plist
            guard let s = stem(".plist"), let dot = s.lastIndex(of: "."),
                  isHostID(String(s[s.index(after: dot)...])) else { return nil }
            return String(s[..<dot])
        case "Saved Application State": return stem(".savedstate")
        case "HTTPStorages": return stem(".binarycookies") ?? entry
        case "Containers":
            let meta = url.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
            if let owner = NSDictionary(contentsOf: meta)?["MCMMetadataIdentifier"] as? String { return owner }
            return isUUID(entry) ? nil : entry
        case "LaunchAgents":
            guard let s = stem(".plist") else { return nil }
            return (NSDictionary(contentsOf: url)?["Label"] as? String) ?? s
        default: return entry
        }
    }

    /// Everything found, ID matches first.
    static func scan(_ identity: Identity, library: URL = userLibrary, assigned: Set<String> = []) -> [Found] {
        guard !isLink(library) else { return [] }
        let ids = Set(identity.ids.map { $0.lowercased() })
        // What the user said belongs to this app, kept to what's safe to move.
        let assignedIDs = Set(assigned.map { $0.lowercased() }.filter(canAssign))
        var assignedPaths = Set<String>()
        var found: [Found] = []

        func look(_ sub: String, _ match: Found.Match, _ test: (_ entry: String, _ url: URL) -> (Bool, String?)) {
            let folder = library.appendingPathComponent(sub)
            guard !isLink(folder) else { return }
            for entry in ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() {
                let url = folder.appendingPathComponent(entry)
                let (hit, label) = test(entry, url)
                guard hit, !found.contains(where: { $0.path == url.path }) else { continue }
                found.append(Found(path: url.path, folder: folder.path, match: match, size: size(of: url), label: label))
            }
        }

        for sub in idFolders {
            look(sub, .id) { entry, url in
                guard let id = namedID(entry, in: sub, at: url), isSafeID(id) else { return (false, nil) }
                let lower = id.lowercased()
                if sub == "LaunchAgents" {
                    // An agent's label may add to the ID: com.example.foo.agent.
                    if ids.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") }) { return (true, id) }
                    if assignedIDs.contains(where: { lower == $0 || lower.hasPrefix($0 + ".") }) {
                        assignedPaths.insert(url.path)
                        return (true, id)
                    }
                    return (false, nil)
                }
                if ids.contains(lower) { return (true, nil) }
                if assignedIDs.contains(lower) { assignedPaths.insert(url.path); return (true, nil) }
                return (false, nil)
            }
        }

        let groups = Set(identity.appGroups.map { $0.lowercased() })
        look("Group Containers", .group) { entry, _ in
            (groups.contains(entry.lowercased()) && !entry.lowercased().contains("com.apple."), nil)
        }

        let names = Set(identity.names.map { $0.lowercased() })
        for sub in ["Application Support", "Caches", "Logs"] {
            look(sub, .name) { entry, _ in (names.contains(entry.lowercased()), nil) }
        }
        return found.map { item in
            var item = item
            item.assigned = assignedPaths.contains(item.path)
            return item
        }
    }

    // MARK: Orphans

    /// Files named for an app ID that nothing on this Mac owns any more.
    struct Orphan: Identifiable, Hashable, Sendable {
        /// The app ID (or group) they're named for.
        let id: String
        var items: [Found]
        var size: Int64 { items.reduce(0) { $0 + $1.size } }
        var lastChanged: Date?
        /// Another app from the same developer is installed, so these may be
        /// its shared files (shown with a note, never hidden).
        var sameDeveloper = false
        var isGroup: Bool { items.allSatisfy { $0.match == .group } }
    }

    /// The orphan IDs assigned to an app that is installed right now. An
    /// assignment to an app that's gone is ignored, so its files show in the
    /// list again rather than waiting for an owner that isn't there.
    static func activeAssignments(_ assigned: [String: [String]], installed: Set<String>) -> Set<String> {
        let installedLower = Set(installed.map { $0.lowercased() })
        return Set(assigned.filter { installedLower.contains($0.key.lowercased()) }.values.flatMap { $0.map { $0.lowercased() } })
    }

    /// Only an ID that is safe to move, looks like an app ID and isn't an app
    /// group (shared folders are never moved) can be assigned.
    static func canAssign(_ id: String) -> Bool {
        isSafeID(id) && isAppIDShaped(id) && !isGroupID(id)
    }

    /// Looks like an app ID: `com.example.foo`, three parts or more.
    static func isAppIDShaped(_ s: String) -> Bool {
        s.range(of: "^[a-z][a-z0-9-]*(\\.[a-z0-9_-]+){2,}$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// What's installed, for deciding who owns what. Read once per scan.
    struct Owners: Sendable {
        var appIDs: Set<String> = []
        var groups: Set<String> = []
        /// First two parts of each app ID ("com.microsoft"), for groups only.
        var vendors: Set<String> = []

        static func current(apps: [String] = AppFolders.appPaths()) -> Owners {
            var owners = Owners()
            for path in apps {
                guard let id = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier?.lowercased() else { continue }
                owners.appIDs.insert(id)
                owners.vendors.insert(id.split(separator: ".").prefix(2).joined(separator: "."))
                owners.groups.formUnion(CodeSign.appGroups(path).map { $0.lowercased() })
                // What's inside counts too: Excel's Quick Look extension,
                // Office's shared helpers, and the groups they claim.
                for nested in nestedBundles(inApp: path, frameworks: true) {
                    owners.appIDs.insert(nested.id.lowercased())
                    owners.groups.formUnion(CodeSign.appGroups(nested.path).map { $0.lowercased() })
                }
            }
            return owners
        }

        /// Owned when an app has this ID, it starts with an app's ID (a
        /// helper), an app's ID starts with it, or macOS knows an app with
        /// this ID anywhere outside the Trash.
        func owns(_ id: String, knownToMacOS: (String) -> Bool) -> Bool {
            let lower = id.lowercased()
            if appIDs.contains(lower) { return true }
            if appIDs.contains(where: { lower.hasPrefix($0) || $0.hasPrefix(lower + ".") }) { return true }
            return knownToMacOS(id)
        }

        /// Shared folders: owned when any installed app claims the group, or
        /// any app from the same developer is installed.
        func ownsGroup(_ group: String) -> Bool {
            let lower = group.lowercased()
            return groups.contains(lower) || vendors.contains { lower.contains($0 + ".") || lower.hasSuffix($0) }
        }
    }

    /// LaunchServices knows an app with this ID somewhere (not in the Trash).
    static func knownToMacOS(_ id: String) -> Bool {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: id).contains { !$0.path.contains("/.Trash/") }
    }

    /// Everything in the Library that no installed app owns, grouped by ID,
    /// largest first. `kept` are IDs the user chose to keep.
    static func orphans(library: URL = userLibrary, owners: Owners = .current(), kept: Set<String> = [],
                        assigned: [String: [String]] = [:],
                        knownToMacOS: (String) -> Bool = knownToMacOS) -> [Orphan] {
        guard !isLink(library) else { return [] }
        let assignedIDs = activeAssignments(assigned, installed: owners.appIDs)
        var byID: [String: Orphan] = [:]
        var known: [String: Bool] = [:]
        func isKnown(_ id: String) -> Bool {
            if let k = known[id.lowercased()] { return k }
            let k = knownToMacOS(id)
            known[id.lowercased()] = k
            return k
        }
        func add(_ id: String, _ url: URL, _ folder: URL, _ match: Found.Match, label: String? = nil) {
            let key = id.lowercased()
            guard !kept.contains(key), !assignedIDs.contains(key) else { return }
            let item = Found(path: url.path, folder: folder.path, match: match, size: size(of: url), label: label)
            let changed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            var orphan = byID[key] ?? Orphan(id: id, items: [])
            orphan.items.append(item)
            if let changed { orphan.lastChanged = max(orphan.lastChanged ?? changed, changed) }
            byID[key] = orphan
        }

        for sub in idFolders {
            let folder = library.appendingPathComponent(sub)
            guard !isLink(folder) else { continue }
            for entry in ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() {
                let url = folder.appendingPathComponent(entry)
                guard let id = namedID(entry, in: sub, at: url), isSafeID(id), isAppIDShaped(id) else { continue }
                // An app group's folder outside Group Containers (Application
                // Scripts/group.com.example.shared): shared, owned like a group.
                if isGroupID(id) {
                    if !owners.ownsGroup(id) { add(id, url, folder, .group) }
                    continue
                }
                guard !owners.owns(id, knownToMacOS: isKnown) else { continue }
                var label: String?
                if sub == "LaunchAgents" {
                    // An agent whose program still exists belongs to something.
                    let plist = NSDictionary(contentsOf: url)
                    let program = (plist?["Program"] as? String) ?? (plist?["ProgramArguments"] as? [String])?.first
                    if let program, FileManager.default.fileExists(atPath: program) { continue }
                    label = id
                }
                add(id, url, folder, .id, label: label)
            }
        }

        let groups = library.appendingPathComponent("Group Containers")
        if !isLink(groups) {
            for entry in ((try? FileManager.default.contentsOfDirectory(atPath: groups.path)) ?? []).sorted()
            where !entry.lowercased().contains("com.apple.") && entry.contains(".") && !owners.ownsGroup(entry) {
                add(entry, groups.appendingPathComponent(entry), groups, .group)
            }
        }
        // A helper's files go under its app: com.example.foo.agent under com.example.foo.
        for key in byID.keys.sorted(by: { $0.count > $1.count }) {
            guard let parent = byID.keys.filter({ key.hasPrefix($0 + ".") }).min(by: { $0.count < $1.count }),
                  let child = byID.removeValue(forKey: key) else { continue }
            var merged = byID[parent]!
            merged.items += child.items
            if let changed = child.lastChanged { merged.lastChanged = max(merged.lastChanged ?? changed, changed) }
            byID[parent] = merged
        }
        return byID.values.map { orphan in
            var orphan = orphan
            orphan.sameDeveloper = owners.vendors.contains(orphan.id.lowercased().split(separator: ".").prefix(2).joined(separator: "."))
            return orphan
        }
        .sorted { $0.size > $1.size }
    }

    // MARK: Moving

    struct Outcome: Sendable {
        struct Failure: Sendable {
            let item: Found
            let reason: String
            /// macOS refused: only apps with Full Disk Access may remove
            /// another app's container.
            var needsFullDiskAccess = false
        }
        var moved: [Found] = []
        var failed: [Failure] = []
    }

    /// Stops any running agent, then moves each item to the Trash after
    /// checking again that it's still where it was found and nothing on the
    /// way is a link. `trash` is replaceable for tests.
    static func moveToTrash(_ items: [Found], library: URL = userLibrary,
                            trash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) })
        async -> Outcome {
        var outcome = Outcome()
        for item in items {
            guard item.movable else {
                outcome.failed.append(.init(item: item, reason: "Shared app folders aren't moved. Use Show in Finder."))
                continue
            }
            let url = URL(fileURLWithPath: item.path)
            let folder = URL(fileURLWithPath: item.folder)
            guard folder.path.hasPrefix(library.path + "/"), url.deletingLastPathComponent().path == folder.path,
                  !isLink(library), !isLink(folder) else {
                outcome.failed.append(.init(item: item, reason: "It isn't where it was found any more."))
                continue
            }
            // lstat: a link counts as there, and only the link moves.
            guard (try? FileManager.default.attributesOfItem(atPath: item.path)) != nil else {
                outcome.failed.append(.init(item: item, reason: "It's already gone."))
                continue
            }
            if let label = item.label { await stopAgent(label) }
            do {
                try trash(url)
                // Don't trust the success alone: macOS can report a protected
                // folder as moved and leave it where it was.
                if (try? FileManager.default.attributesOfItem(atPath: item.path)) != nil {
                    outcome.failed.append(.init(item: item, reason: "macOS said it moved, but it's still there.",
                                                needsFullDiskAccess: true))
                } else {
                    outcome.moved.append(item)
                }
            } catch let error as CocoaError where error.code == .fileWriteNoPermission || error.code == .fileReadNoPermission {
                outcome.failed.append(.init(item: item, reason: "macOS only lets apps with Full Disk Access remove another app's data.",
                                            needsFullDiskAccess: true))
            } catch {
                outcome.failed.append(.init(item: item, reason: error.localizedDescription))
            }
        }
        return outcome
    }

    /// `launchctl bootout` for a loaded agent, so it doesn't keep running
    /// from the Trash until the next login.
    static func stopAgent(_ label: String) async {
        let target = "gui/\(getuid())/\(label)"
        guard let loaded = try? await Shell.run("/bin/launchctl", ["print", target]), loaded.status == 0 else { return }
        _ = try? await Shell.run("/bin/launchctl", ["bootout", target])
    }

    // MARK: Helpers

    @MainActor static func showInFinder(_ item: Found) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    static func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// `group.com.example.shared` or `ABCDE12345.com.example.shared`.
    static func isGroupID(_ s: String) -> Bool {
        s.lowercased().hasPrefix("group.") || s.range(of: "^[A-Z0-9]{10}\\.", options: .regularExpression) != nil
    }

    static func isUUID(_ s: String) -> Bool {
        s.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
                options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// ByHost files end in the Mac's hardware UUID (older ones: 12 hex digits).
    static func isHostID(_ s: String) -> Bool {
        isUUID(s) || s.range(of: "^[0-9a-f]{12}$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// On-disk size, never following links.
    static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isSymbolicLinkKey]
        if isLink(url) { return 0 }
        var total = Int64((try? url.resourceValues(forKeys: Set(keys)))?.totalFileAllocatedSize ?? 0)
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return total }
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: Set(keys)))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

extension CodeSign {
    /// The `com.apple.security.application-groups` entitlement, if signed with one.
    static func appGroups(_ path: String) -> [String] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
              let code else { return [] }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation),
                                            &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let entitlements = dict[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }
}
