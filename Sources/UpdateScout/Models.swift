import Foundation

/// One available update, as reported by a detector.
struct UpdateItem: Identifiable, Codable, Hashable {
    /// Stable identity: source + name + latest version, so a new version of the
    /// same app counts as a "new" item for notification/dismissal purposes.
    var id: String { "\(sourceID)|\(name)|\(latestVersion)" }

    let sourceID: String
    let name: String
    let installedVersion: String
    let latestVersion: String
    /// Vendor / info page, if known.
    let url: String?
    /// Extra caveat shown in the UI before the user clicks Update
    /// (e.g. "requires restart", "will switch this app to Homebrew management").
    let caveat: String?
    /// Opaque token the detector needs to perform the install
    /// (cask token, mas id, softwareupdate label, shell command, ...).
    let installToken: String
    /// If false, the "Update" button opens `url` instead of running anything.
    let scriptedInstall: Bool

    init(sourceID: String, name: String, installedVersion: String, latestVersion: String,
         url: String? = nil, caveat: String? = nil, installToken: String, scriptedInstall: Bool = true) {
        self.sourceID = sourceID
        self.name = name
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.url = url
        self.caveat = caveat
        self.installToken = installToken
        self.scriptedInstall = scriptedInstall
    }
}

/// A detector for one kind of update source.
protocol UpdateSource: Sendable {
    /// Stable identifier, also used in settings ("enabled sources").
    var id: String { get }
    /// Human name shown as a section header.
    var displayName: String { get }
    /// Return currently available updates. Throwing marks the source as errored
    /// in the UI; returning [] means "everything up to date".
    func detect() async throws -> [UpdateItem]
    /// Perform the update for one item previously returned by detect().
    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws
}

enum UpdateScoutError: LocalizedError {
    case toolMissing(String, hint: String)
    case commandFailed(String, output: String)
    case parseFailure(String)

    var errorDescription: String? {
        switch self {
        case .toolMissing(let tool, let hint): return "\(tool) is not installed. \(hint)"
        case .commandFailed(let cmd, let output):
            let tail = output.split(separator: "\n").suffix(4).joined(separator: "\n")
            return "`\(cmd)` failed:\n\(tail)"
        case .parseFailure(let what): return "Could not parse \(what)"
        }
    }
}

/// Lenient dotted-version comparison ("1.10.2" > "1.9"). Non-numeric parts
/// compare as strings. Returns true if `remote` is newer than `local`.
func isNewerVersion(_ remote: String, than local: String) -> Bool {
    // Homebrew cask versions can carry build metadata after "," or "_" — compare the front part.
    func clean(_ s: String) -> [Substring] {
        let front = s.split(whereSeparator: { $0 == "," || $0 == "_" }).first.map(String.init) ?? s
        return front.split(separator: ".")
    }
    let r = clean(remote), l = clean(local)
    for i in 0..<max(r.count, l.count) {
        let rp = i < r.count ? r[i] : "0"
        let lp = i < l.count ? l[i] : "0"
        if let ri = Int(rp), let li = Int(lp) {
            if ri != li { return ri > li }
        } else if rp != lp {
            return rp.compare(lp, options: .numeric) == .orderedDescending
        }
    }
    return false
}
