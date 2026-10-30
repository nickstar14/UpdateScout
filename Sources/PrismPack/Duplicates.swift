import Foundation

/// The same app found twice (Nick, Phase 4 decisions table). Detection only
/// reads; every fix is a click, and anything removed goes to the Trash.
struct DuplicateGroup: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Two copies of one app on disk (same bundle id).
        case twoCopies
        /// An App Store app that a Homebrew cask also claims.
        case twoStores(cask: String)
    }

    let kind: Kind
    let name: String
    /// The copy to keep.
    let keep: String
    /// The copies the user may move to the Trash (twoCopies only).
    let extras: [String]

    var id: String { keep }

    var advice: String {
        switch kind {
        case .twoCopies:
            "Two copies of \(name). Keep the one in \((keep as NSString).deletingLastPathComponent), and move the other to the Trash."
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
            let keep = copies.max { a, b in
                // The newer version wins; on a tie, the one in /Applications.
                switch compareVersions(a.version, b.version) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: return a.path.hasPrefix("/Applications/") && !b.path.hasPrefix("/Applications/") ? false
                    : !a.path.hasPrefix("/Applications/") && b.path.hasPrefix("/Applications/")
                }
            }!
            groups.append(DuplicateGroup(kind: .twoCopies, name: keep.name, keep: keep.path,
                                         extras: copies.map(\.path).filter { $0 != keep.path }))
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
