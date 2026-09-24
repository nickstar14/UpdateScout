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
    /// Release notes for the new version, when the source publishes them
    /// (Sparkle appcast description, App Store "What's New"). May be HTML.
    var releaseNotes: String? = nil
    /// A page with the full notes, when the source only links to them.
    var releaseNotesURL: String? = nil
    /// The installed .app bundle, when known — used for the icon.
    var appPath: String? = nil
    /// An iPhone/iPad app running on Apple silicon. Only the App Store can
    /// update these, so the UI says so rather than offering a generic button.
    var isIOSApp: Bool = false

    init(sourceID: String, name: String, installedVersion: String, latestVersion: String,
         url: String? = nil, caveat: String? = nil, installToken: String, scriptedInstall: Bool = true,
         releaseNotes: String? = nil, releaseNotesURL: String? = nil, appPath: String? = nil,
         isIOSApp: Bool = false) {
        self.sourceID = sourceID
        self.name = name
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.url = url
        self.caveat = caveat
        self.installToken = installToken
        self.scriptedInstall = scriptedInstall
        self.releaseNotes = releaseNotes
        self.releaseNotesURL = releaseNotesURL
        self.appPath = appPath
        self.isIOSApp = isIOSApp
    }

    /// What the action button should say.
    var actionLabel: String {
        if scriptedInstall { return "Update" }
        switch sourceID {
        case "mas": return "App Store"
        case "macos": return "Settings"
        default: return "Get…"
        }
    }
    var actionLabelLong: String {
        if scriptedInstall { return "Update" }
        switch sourceID {
        case "mas": return "Open in App Store"
        case "macos": return "Open Software Update"
        default: return "Open download page"
        }
    }
    var actionSymbol: String {
        if scriptedInstall { return "arrow.down.circle" }
        switch sourceID {
        case "mas": return "arrow.up.forward.app"
        case "macos": return "gearshape"
        default: return "safari"
        }
    }
}

/// Finds an installed .app by its display name, in the usual places.
enum AppLocator {
    static func find(named name: String) -> String? {
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        for dir in dirs {
            let path = dir + "/" + name + ".app"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    /// Last resort for pkg-based casks with no app artifact: the one app in
    /// /Applications whose normalised name starts with the cask token
    /// ("displaylink" → "DisplayLink Manager.app"). Requires a *unique* match
    /// so it can't attach the wrong app.
    static func findUnique(prefix token: String) -> String? {
        func norm(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let key = norm(token)
        guard key.count >= 4 else { return nil }
        let fm = FileManager.default
        var hits: [String] = []
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for entry in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where entry.hasSuffix(".app") {
                if norm((entry as NSString).deletingPathExtension).hasPrefix(key) {
                    hits.append(dir + "/" + entry)
                }
            }
        }
        return hits.count == 1 ? hits[0] : nil
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
    /// A cask stuck on a half-finished earlier upgrade — see BrewRepair.
    case staleCaskUpgrade(token: String, folder: URL)

    var errorDescription: String? {
        switch self {
        case .toolMissing(let tool, let hint): return "\(tool) is not installed. \(hint)"
        case .commandFailed(let cmd, let output):
            let tail = output.split(separator: "\n").suffix(4).joined(separator: "\n")
            return "`\(cmd)` failed:\n\(tail)"
        case .parseFailure(let what): return "Could not parse \(what)"
        case .staleCaskUpgrade(let token, _):
            return "Homebrew is stuck on an earlier upgrade of \(token) that never finished. Repair moves its leftover folder to the Trash and reinstalls it cleanly."
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

extension UpdateItem {
    /// True when the major version number increases (6.x → 8.x). For commercial
    /// apps that usually means a separate purchase rather than a free update,
    /// so the UI flags it before the user clicks Update.
    var isMajorUpgrade: Bool {
        // Free/system sources don't have paid major upgrades: Homebrew formulae
        // are open source, and macOS updates come with the OS.
        if sourceID == "macos" { return false }
        if sourceID == "homebrew" && !installToken.hasPrefix("cask:") { return false }

        func major(_ s: String) -> Int? {
            let front = s.split(whereSeparator: { $0 == "," || $0 == "_" }).first.map(String.init) ?? s
            return Int(front.split(separator: ".").first ?? "")
        }
        guard let new = major(latestVersion), let old = major(installedVersion),
              old > 0, new > old,
              // Build-number-style versions (Teams' 26106.x) aren't marketing
              // majors — a jump there says nothing about licensing.
              old < 1000
        else { return false }
        return true
    }

    /// Short "6 → 8" description of the major jump, for the warning text.
    var majorUpgradeSummary: String? {
        guard isMajorUpgrade else { return nil }
        let old = installedVersion.split(separator: ".").first.map(String.init) ?? installedVersion
        let new = latestVersion.split(separator: ".").first.map(String.init) ?? latestVersion
        return "\(old) → \(new)"
    }
}
