import Foundation

/// An app nothing updates that Homebrew could take over (Phase 7,
/// docs/2.0.0-adoption.md). Kept in its own list in state.json, apart from
/// update items, so item ids and the hide lists never change because of it.
struct AdoptionCandidate: Codable, Hashable, Identifiable {
    enum Method: String, Codable {
        /// `brew install --cask --adopt`: the installed app is the cask's version.
        case inPlace
        /// Old app to the Trash, then `brew install --cask`.
        case replace
    }

    enum Verdict: String, Codable, Comparable {
        case recommended, worthConsidering, notBetter
        static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
        private var rank: Int { self == .recommended ? 0 : self == .worthConsidering ? 1 : 2 }

        var title: String {
            switch self {
            case .recommended: "Recommended"
            case .worthConsidering: "Worth considering"
            case .notBetter: "Not better"
            }
        }
    }

    var id: String { appPath }
    let name: String
    let appPath: String
    let bundleID: String
    let installedVersion: String
    let token: String
    let caskVersion: String
    let method: Method
    let verdict: Verdict
    /// Why the verdict isn't Recommended, first line first. Empty for Recommended.
    let reasons: [String]
    /// The checks it passed, shown as ticks in the review sheet.
    let checks: [String]
    /// The cask runs a pkg installer: a password to move it and on every update.
    let needsAdmin: Bool
    /// What updates it today, when something does ("Sparkle", …).
    let updater: String?
    /// The cask's download, for the size shown when the sheet opens.
    let downloadURL: String?
    /// The vendor's own feed lists delta updates (Homebrew always downloads in full).
    var vendorDeltas = false

    /// The key the Not now / Never lists use: the app, not its version.
    var hideKey: String { bundleID }

    /// "Adopt all safe ones" only takes in-place, password-free, Recommended ones.
    var isSafe: Bool { verdict == .recommended && method == .inPlace && !needsAdmin }
}

/// What PrismPack reads from one installed app.
struct AppFacts: Equatable {
    let name: String
    let path: String
    let bundleID: String
    let version: String
    /// CFBundleVersion. Some vendors' casks use it (Office: "16.114.26102031"
    /// where the app shows "16.114.1").
    var build: String? = nil
    var hasMASReceipt = false
    var isIOSApp = false
    /// Sparkle, Squirrel, Microsoft AutoUpdate or Google's updater, if found.
    var updater: String? = nil
    var feedURL: URL? = nil
    var fileName: String { (path as NSString).lastPathComponent }
}

/// Finds adoption candidates. Reads only: nothing here changes anything.
enum Adoption {
    /// Homebrew's version string without its build suffix ("4,2023.07" → "4").
    static func core(_ caskVersion: String) -> String {
        String(caskVersion.split(separator: ",").first ?? Substring(caskVersion))
    }

    static func sameVersion(_ installed: String, _ caskVersion: String) -> Bool {
        installed == caskVersion || installed == core(caskVersion)
    }

    /// The app's own version or its build matches the cask's.
    static func sameVersion(_ app: AppFacts, _ caskVersion: String) -> Bool {
        sameVersion(app.version, caskVersion) || app.build.map { sameVersion($0, caskVersion) } == true
    }

    /// The app's version in the cask's numbering: its build when the cask
    /// counts builds (same number of parts, a long last part), else its version.
    static func comparable(_ app: AppFacts, to caskVersion: String) -> String {
        let cask = core(caskVersion).split(separator: ".")
        guard let build = app.build, let last = cask.last, last.count >= 6 else { return app.version }
        let parts = build.split(separator: ".")
        return parts.count == cask.count && (parts.last?.count ?? 0) >= 6 ? build : app.version
    }

    /// Every check in docs/2.0.0-adoption.md for one app and the cask that
    /// matches it by filename. nil means "never offer": a hard check failed,
    /// or it updates itself and those aren't included. `vendorLatest` is the
    /// app's own feed's newest release, when it has one and it was read.
    static func evaluate(app: AppFacts, cask: CaskIndex.CaskInfo, copies: Int,
                         includeSelfUpdating: Bool, vendorLatest: String? = nil,
                         macOS: String = currentMacOS) -> AdoptionCandidate? {
        // 1. Strong match: filename, plus the bundle id or the exact version.
        guard cask.apps.contains(where: { $0.caseInsensitiveCompare(app.fileName) == .orderedSame }) else { return nil }
        let idMatch = cask.quitIDs.contains(app.bundleID)
        let versionMatch = sameVersion(app, cask.version)
        let installed = comparable(app, to: cask.version)
        guard idMatch || versionMatch else { return nil }
        // 3. Not an App Store, iPhone or iPad app. 4. Not a system app.
        guard !app.hasMASReceipt, !app.isIOSApp, !app.bundleID.hasPrefix("com.apple."),
              !app.path.hasPrefix("/System/") else { return nil }
        // 5. Exactly one copy on disk.
        guard copies == 1 else { return nil }
        // 6. Cask health (deprecated, disabled and `latest` never reach here).
        guard cask.tap == nil || cask.tap == "homebrew/cask" else { return nil }
        // Can it run here at all?
        if cask.intelOnly { return nil }
        if let min = cask.minimumMacOS, isNewerVersion(min, than: macOS) { return nil }
        // 7. Another updater: only when the user asked for those.
        let updater = app.updater ?? (cask.autoUpdates ? "its own updater" : nil)
        if updater != nil, !includeSelfUpdating { return nil }

        var checks = [idMatch ? "Name and bundle ID match" : "Name and version match",
                      "Not an App Store app", "One copy on disk"]
        checks.append(updater == nil ? "No updater found" : "Already updates itself")

        let caskCore = core(cask.version)
        var lags: [String] = []
        if isNewerVersion(installed, than: caskCore) {
            lags.append("Homebrew's version (\(caskCore)) is older than yours (\(installed)).")
        }
        if let vendorLatest, isNewerVersion(vendorLatest, than: caskCore) {
            lags.append("Its cask (\(caskCore)) is older than the vendor's release (\(vendorLatest)).")
        }
        if VersionParts(app.version).track > 0, VersionParts(caskCore).track == 0 {
            lags.append("You're on a beta. Homebrew follows stable releases, so it would offer a downgrade.")
        }
        if lags.isEmpty { checks.append("Cask is current") }
        if cask.pkg { checks.append("Installer needs admin") }

        let method: AdoptionCandidate.Method = !cask.pkg && versionMatch ? .inPlace : .replace
        let verdict: AdoptionCandidate.Verdict
        var reasons = lags
        if !lags.isEmpty {
            verdict = .notBetter
        } else {
            if let updater { reasons.append("It already updates itself through \(updater). Homebrew adds one place to update everything.") }
            if cask.pkg { reasons.append("Homebrew runs an installer, so it needs your password to move it and on every update.") }
            if method == .replace, !cask.pkg {
                reasons.append("Your copy is older than Homebrew's, so it's replaced rather than adopted in place.")
            }
            verdict = reasons.isEmpty ? .recommended : .worthConsidering
        }
        return AdoptionCandidate(name: app.name, appPath: app.path, bundleID: app.bundleID,
                                 installedVersion: app.version, token: cask.token, caskVersion: cask.version,
                                 method: method, verdict: verdict, reasons: reasons, checks: checks,
                                 needsAdmin: cask.pkg, updater: updater, downloadURL: cask.url)
    }

    static var currentMacOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    // MARK: - Scanning

    /// The scan, when "Suggest apps that can move under Homebrew" is on.
    /// nil when it's off, so the stored list is left alone.
    static func scanIfEnabled() async -> Scan? {
        guard Prefs.adoptionEnabled else { return nil }
        return await scan(includeSelfUpdating: Prefs.adoptionIncludeSelfUpdating, adopted: Store.load().adopted)
    }

    struct Scan {
        var candidates: [AdoptionCandidate] = []
        /// Adopted casks behind the vendor's own feed: token → vendor release.
        var behind: [String: String] = [:]
        /// Casks Homebrew manages now; nil when `brew list` couldn't say.
        var managed: Set<String>? = nil
        /// App Store apps a cask also installs: app path → cask token. Never
        /// suggested; their Installed card offers "Move to Homebrew…".
        var storeSwitches: [String: String] = [:]
    }

    static let digestInterval: TimeInterval = 7 * 24 * 3600
    static let snoozeInterval: TimeInterval = 30 * 24 * 3600

    /// Store one scan's results. Returns what goes in a digest notification
    /// now: new, shown, not Not better, and only once a week at most.
    static func merge(_ scan: Scan, into s: inout Store.State, now: Date = Date()) -> [AdoptionCandidate] {
        let candidates = scan.candidates
        s.adoptionCandidates = candidates
        s.adoptedBehind = scan.behind
        s.storeSwitches = scan.storeSwitches
        // An adopted cask that's since been uninstalled is forgotten.
        if let managed = scan.managed { s.adopted = s.adopted.filter { managed.contains($0.key) } }
        s.adoptionSnoozed = s.adoptionSnoozed.filter { $0.value > now }
        let keys = Set(candidates.map(\.hideKey))
        s.adoptionNotified.formIntersection(keys)
        let fresh = s.visibleAdoptions.filter { $0.verdict != .notBetter && !s.adoptionNotified.contains($0.hideKey) }
        guard !fresh.isEmpty else { return [] }
        if let last = s.adoptionDigestAt, now.timeIntervalSince(last) < digestInterval { return [] }
        s.adoptionDigestAt = now
        s.adoptionNotified.formUnion(fresh.map(\.hideKey))
        return fresh
    }

    /// Every candidate on this Mac, best first. Empty (never an error) when
    /// Homebrew is missing, the cask list can't be read, or `brew list`
    /// fails: offering nothing beats offering to reinstall managed apps.
    static func scan(includeSelfUpdating: Bool, adopted: [String: String] = [:]) async -> Scan {
        guard let brew = HomebrewSource.brewPath,
              let casks = try? await CaskIndex.load(),
              let listed = try? await Shell.run(brew, ["list", "--cask", "-1"]), listed.status == 0
        else { return Scan() }
        let managed = Set(listed.stdout.split(separator: "\n").map(String.init))

        var byFile: [String: CaskIndex.CaskInfo] = [:]
        for cask in casks where !CaskIndex.isPrerelease(cask.token) && !managed.contains(cask.token) {
            for app in cask.apps { byFile[app.lowercased()] = cask }
        }

        let apps = installedApps()
        var copies: [String: Int] = [:]
        for app in apps { copies[app.bundleID, default: 0] += 1 }

        // "It can change over time": an app PrismPack adopted whose vendor
        // feed is now ahead of its cask.
        var behind: [String: String] = [:]
        for (token, bundleID) in adopted where managed.contains(token) {
            guard let cask = casks.first(where: { $0.token == token }),
                  let app = apps.first(where: { $0.bundleID == bundleID }), let feed = app.feedURL,
                  let vendor = await vendorRelease(feed, installed: app.version),
                  isNewerVersion(vendor.0, than: core(cask.version)) else { continue }
            behind[token] = vendor.0
        }

        // Read the vendor's feed only for apps that would otherwise be shown
        // and update themselves through Sparkle.
        let pairs = apps.compactMap { app in byFile[app.fileName.lowercased()].map { (app, $0) } }
        let candidates = await withTaskGroup(of: AdoptionCandidate?.self) { group in
            for (app, cask) in pairs {
                group.addTask {
                    var vendor: (String, Bool)? = nil
                    if includeSelfUpdating, let feed = app.feedURL { vendor = await vendorRelease(feed, installed: app.version) }
                    var candidate = evaluate(app: app, cask: cask, copies: copies[app.bundleID] ?? 1,
                                             includeSelfUpdating: includeSelfUpdating, vendorLatest: vendor?.0)
                    candidate?.vendorDeltas = vendor?.1 ?? false
                    return candidate
                }
            }
            var found: [AdoptionCandidate] = []
            for await candidate in group { if let candidate { found.append(candidate) } }
            return found.sorted { ($0.verdict, $0.name.lowercased()) < ($1.verdict, $1.name.lowercased()) }
        }
        // App Store apps Homebrew could install instead, matched by app or
        // cask name. The bundle id and developer are checked after install.
        var byName: [String: String] = [:]
        for cask in casks where !CaskIndex.isPrerelease(cask.token) {
            for name in cask.appNames { byName[name.lowercased().replacingOccurrences(of: ".app", with: "")] = cask.token }
        }
        var switches: [String: String] = [:]
        for app in apps where app.hasMASReceipt {
            if let token = byName[app.name.lowercased()] { switches[app.path] = token }
        }
        return Scan(candidates: candidates, behind: behind, managed: managed, storeSwitches: switches)
    }

    /// The newest release in an app's Sparkle feed, and whether it lists deltas.
    private static func vendorRelease(_ feed: URL, installed: String) async -> (String, Bool)? {
        guard let (data, response) = try? await Net.fetch(feed),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = AppcastParser.latestVersion(from: data, installed: installed, installedBuild: nil)
        else { return nil }
        return (latest.displayVersion, latest.hasDeltas)
    }

    /// Apps directly in /Applications and ~/Applications.
    static func installedApps() -> [AppFacts] {
        let fm = FileManager.default
        var found: [AppFacts] = []
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for entry in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where entry.hasSuffix(".app") {
                if let facts = facts(at: "\(dir)/\(entry)") { found.append(facts) }
            }
        }
        return found
    }

    static func facts(at path: String) -> AppFacts? {
        let fm = FileManager.default
        guard let data = fm.contents(atPath: path + "/Contents/Info.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              let version = (plist["CFBundleShortVersionString"] ?? plist["CFBundleVersion"]) as? String
        else {
            // iPhone and iPad apps keep their Info.plist inside a wrapper.
            return nil
        }
        let frameworks = path + "/Contents/Frameworks/"
        let feed = (plist["SUFeedURL"] as? String).flatMap(URL.init(string:))
        var updater: String?
        if feed != nil || fm.fileExists(atPath: frameworks + "Sparkle.framework") {
            updater = "Sparkle"
        } else if fm.fileExists(atPath: frameworks + "Squirrel.framework") {
            updater = "Squirrel"
        } else if plist["KSProductID"] != nil || plist["KSUpdateURL"] != nil {
            updater = "Google Software Update"
        } else if bundleID.hasPrefix("com.microsoft."),
                  fm.fileExists(atPath: "/Library/Application Support/Microsoft/MAU2.0") {
            updater = "Microsoft AutoUpdate"
        }
        return AppFacts(name: ((path as NSString).lastPathComponent as NSString).deletingPathExtension,
                        path: path, bundleID: bundleID, version: version,
                        build: plist["CFBundleVersion"] as? String,
                        hasMASReceipt: fm.fileExists(atPath: path + "/Contents/_MASReceipt"),
                        isIOSApp: fm.fileExists(atPath: path + "/Wrapper") || fm.fileExists(atPath: path + "/WrappedBundle"),
                        updater: updater, feedURL: feed?.scheme?.hasPrefix("http") == true ? feed : nil)
    }

    // MARK: - Download size (read when the review sheet opens)

    private static let sizeLock = NSLock()
    nonisolated(unsafe) private static var sizes: [String: Int64] = [:]

    /// The download's size from a HEAD request, cached. nil when it can't be read.
    static func downloadSize(_ urlString: String) async -> Int64? {
        if let cached = sizeLock.withLock({ sizes[urlString] }) { return cached }
        guard let url = URL(string: urlString), url.scheme == "https" else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        guard let (_, response) = try? await Net.fetch(request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.expectedContentLength > 0 else { return nil }
        sizeLock.withLock { sizes[urlString] = http.expectedContentLength }
        return http.expectedContentLength
    }
}
