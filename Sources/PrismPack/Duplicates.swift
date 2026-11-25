import Foundation
import AppKit
import CoreServices

/// The same app found twice (Nick, Phase 4 decisions table). Detection only
/// reads; every fix is a click, and anything removed goes to the Trash.
struct DuplicateGroup: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Two copies of one app on disk (same bundle id).
        case twoCopies
        /// Different apps that share one bundle id (Serato DJ Lite and DJ Pro,
        /// 25 Nov 2026): probably two editions of one product, so nothing is
        /// suggested and nothing can be moved from here.
        case lookAlikes
        /// An App Store app that a Homebrew cask also claims.
        case twoStores(cask: String)
    }

    let kind: Kind
    let name: String
    /// The copy suggested to keep: the one that's open, else the one opened
    /// most (Nick, 2 Nov 2026). The user chooses; this is only the default.
    let keep: String
    /// The copies the user may move to the Trash (twoCopies only).
    let extras: [String]

    var id: String { keep }

    var advice: String {
        switch kind {
        case .twoCopies:
            "Two copies of \(name). Keep the one in \((keep as NSString).deletingLastPathComponent), and move the other to the Trash."
        case .lookAlikes:
            "These share one bundle ID but have different names, so they may be two editions of one product (like Serato DJ Lite and DJ Pro) rather than copies. Nothing is suggested. If you do want one gone, uninstall it from its own page."
        case .twoStores(let cask):
            "\(name) comes from the App Store, and Homebrew also tracks it (cask \(cask)). The App Store keeps it up to date, so Homebrew can stop tracking it. The app isn't touched."
        }
    }
}

enum Duplicates {
    /// Reads /Applications, ~/Applications and Homebrew's Caskroom records.
    static func scan(records: [CaskRecord]) async -> [DuplicateGroup] {
        let apps = Adoption.installedApps()
        var groups: [DuplicateGroup] = []

        for (_, copies) in Dictionary(grouping: apps, by: \.bundleID) where copies.count > 1 {
            let keep = preferred(copies.map { app in
                let use = usage(app.path)
                return Candidate(path: app.path, version: app.version, running: isRunning(app.path),
                                 opened: use.count)
            })
            let name = copies.first { $0.path == keep }?.name ?? copies[0].name
            // Different names: not plain copies. Show them, suggest nothing.
            if Set(copies.map { $0.name.lowercased() }).count > 1 {
                let paths = copies.map(\.path).sorted()
                groups.append(DuplicateGroup(kind: .lookAlikes, name: copies.map(\.name).sorted().joined(separator: " and "),
                                             keep: paths[0], extras: Array(paths.dropFirst())))
                continue
            }
            groups.append(DuplicateGroup(kind: .twoCopies, name: name, keep: keep,
                                         extras: copies.map(\.path).filter { $0 != keep }))
        }

        let masApps = Dictionary(apps.filter(\.hasMASReceipt).map { ($0.fileName.lowercased(), $0) },
                                 uniquingKeysWith: { a, _ in a })
        for record in records {
            for file in record.apps {
                guard let app = masApps[file.lowercased()] else { continue }
                groups.append(DuplicateGroup(kind: .twoStores(cask: record.token), name: app.name,
                                             keep: app.path, extras: []))
            }
        }
        return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// One copy, for choosing which to suggest keeping.
    struct Candidate {
        let path: String
        let version: String
        let running: Bool
        let opened: Int
    }

    /// The copy that's open; else the one opened most; else the newer one;
    /// else /Applications itself, then a folder in it, then ~/Applications.
    static func preferred(_ copies: [Candidate]) -> String {
        func place(_ path: String) -> Int {
            path.hasPrefix("/Applications/") ? (AppFolders.isNested(path) ? 1 : 2) : 0
        }
        return copies.max { a, b in
            if a.running != b.running { return b.running }
            if a.opened != b.opened { return a.opened < b.opened }
            switch compareVersions(a.version, b.version) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return place(a.path) < place(b.path)
            }
        }!.path
    }

    /// True when this exact copy is open (by its path, not its bundle id:
    /// two copies share one id).
    static func isRunning(_ path: String) -> Bool {
        let key = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
        return NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path.lowercased() == key
        }
    }

    /// How often macOS has seen the app opened, and when last (Spotlight's
    /// own counts; zero and nil when it hasn't recorded any).
    static func usage(_ path: String) -> (count: Int, last: Date?) {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return (0, nil) }
        let count = (MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber)?.intValue ?? 0
        let last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        return (count, last)
    }

    /// Why `path` mustn't go to the Trash now, keeping `kept`; nil when it
    /// may. Checked again at the moment of the move (Nick: airtight).
    /// `allowOpen`: "Use Homebrew's copy" quits the copy itself first.
    static func refusal(moving path: String, keeping kept: String, allowOpen: Bool = false) -> String? {
        let fm = FileManager.default
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        guard path.lowercased() != kept.lowercased() else { return "That's the copy you're keeping." }
        guard let moving = Adoption.facts(at: path) else { return "\(path) isn't there any more." }
        guard let keep = Adoption.facts(at: kept) else {
            return "The other copy (\(kept)) isn't there any more, so this is the last one. Nothing was moved."
        }
        guard keep.bundleID == moving.bundleID else {
            return "The other copy isn't the same app any more. Nothing was moved."
        }
        // The kept copy must still be a whole app: its program is there.
        let exe = (try? fm.contentsOfDirectory(atPath: kept + "/Contents/MacOS")) ?? []
        guard !exe.isEmpty else { return "The other copy looks damaged (no program inside). Nothing was moved." }
        if !allowOpen, isRunning(path) { return "\(name) in \(folder(of: path)) is open. Quit it, then try again." }
        return nil
    }

    /// One copy as "Use Homebrew's copy" sees it.
    struct Copy {
        let path: String
        let fromHomebrew: Bool
        let fromAppStore: Bool
    }

    /// Homebrew's copy, when exactly one copy is Homebrew's, at least one
    /// isn't, and none is from the App Store (those stay with the App
    /// Store). Nil otherwise: then the button isn't offered.
    static func homebrewCopy(_ copies: [Copy]) -> String? {
        let brew = copies.filter(\.fromHomebrew)
        guard brew.count == 1, copies.count > 1, !copies.contains(where: \.fromAppStore) else { return nil }
        return brew[0].path
    }

    /// "~/Applications" rather than the full home path.
    static func folder(of path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        return folder.hasPrefix(NSHomeDirectory()) ? "~" + folder.dropFirst(NSHomeDirectory().count) : folder
    }

    struct CaskRecord {
        let token: String
        /// The app bundles it installs; for a pkg cask, its name plus ".app".
        let apps: [String]
        let autoUpdates: Bool
    }

    /// Installed casks, from one `brew info --installed` call. The cask JSON
    /// Homebrew 7 keeps in each Caskroom record is empty, so the folders
    /// alone can't say what a cask installs. Empty if brew can't answer.
    static func caskRecords() async -> [CaskRecord] {
        guard let brew = HomebrewSource.brewPath,
              let result = try? await Shell.run(brew, ["info", "--json=v2", "--cask", "--installed"]),
              result.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let casks = json["casks"] as? [[String: Any]] else { return [] }
        return casks.compactMap { cask in
            guard let token = cask["token"] as? String else { return nil }
            let artifacts = cask["artifacts"] as? [[String: Any]] ?? []
            var apps = artifacts.flatMap { ($0["app"] as? [Any])?.compactMap { $0 as? String } ?? [] }
            if apps.isEmpty, artifacts.contains(where: { $0["pkg"] != nil }) {
                apps = (cask["name"] as? [String] ?? []).map { $0 + ".app" }
            }
            return CaskRecord(token: token, apps: apps, autoUpdates: cask["auto_updates"] as? Bool == true)
        }
    }
}
