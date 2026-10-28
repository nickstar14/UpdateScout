import Foundation

/// One available update, as reported by a detector.
struct UpdateItem: Identifiable, Codable, Hashable {
    /// Stable identity: source + install token + name + latest version, so a
    /// new version of the same app counts as a "new" item for notification/
    /// dismissal purposes. The token keeps a formula and a cask that share a
    /// name (docker, docker) from collapsing into one id.
    var id: String { "\(sourceID)|\(installToken)|\(name)|\(latestVersion)" }

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
/// compare as strings. A leading "v" is ignored, and a release ranks above its
/// own prereleases ("3.0.0" > "3.0.0-beta.4" > "3.0.0-alpha.10").
/// Returns true if `remote` is newer than `local`.
func isNewerVersion(_ remote: String, than local: String) -> Bool {
    compareVersions(remote, local) == .orderedDescending
}

/// A version split into its dotted core and an optional prerelease stage.
struct VersionParts {
    var core: [String]
    /// nil for a release; otherwise the stage rank (dev < alpha < beta < rc).
    var stage: Int?
    var stageNumber: Int

    /// 0 for a release, 1 for beta-like (beta, preview, rc), 2 for alpha-like
    /// (alpha, dev, nightly). Used to work out which release track an app is on.
    var track: Int {
        guard let stage else { return 0 }
        return stage <= Self.alphaRank ? 2 : 1
    }

    static let alphaRank = 1
    private static let stages: [(String, Int)] = [
        ("nightly", 0), ("dev", 0), ("alpha", 1),
        ("beta", 2), ("preview", 3), ("pre", 3), ("rc", 4),
    ]
    private static let marker = try! NSRegularExpression(
        pattern: "[-.+ ]?(nightly|dev|alpha|beta|preview|pre|rc)[-.]?(\\d*)",
        options: .caseInsensitive)

    init(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if let first = s.first, first == "v" || first == "V", s.dropFirst().first?.isNumber == true {
            s.removeFirst()
        }
        // Homebrew cask versions can carry build metadata after "," or "_".
        s = s.split(whereSeparator: { $0 == "," || $0 == "_" }).first.map(String.init) ?? s
        stage = nil
        stageNumber = 0
        let ns = s as NSString
        if let m = Self.marker.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
           m.range.location > 0 {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            stage = Self.stages.first { $0.0 == name }?.1
            stageNumber = Int(ns.substring(with: m.range(at: 2))) ?? 0
            s = ns.substring(to: m.range.location)
        }
        core = s.split(separator: ".").map(String.init)
    }
}

func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
    let x = VersionParts(a), y = VersionParts(b)
    for i in 0..<max(x.core.count, y.core.count) {
        let xp = i < x.core.count ? x.core[i] : "0"
        let yp = i < y.core.count ? y.core[i] : "0"
        if let xi = Int(xp), let yi = Int(yp) {
            if xi != yi { return xi < yi ? .orderedAscending : .orderedDescending }
        } else if xp != yp {
            let r = xp.compare(yp, options: .numeric)
            if r != .orderedSame { return r }
        }
    }
    switch (x.stage, y.stage) {
    case (nil, nil): return .orderedSame
    case (nil, _): return .orderedDescending   // release beats its prerelease
    case (_, nil): return .orderedAscending
    case let (xs?, ys?):
        if xs != ys { return xs < ys ? .orderedAscending : .orderedDescending }
        if x.stageNumber != y.stageNumber {
            return x.stageNumber < y.stageNumber ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }
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
