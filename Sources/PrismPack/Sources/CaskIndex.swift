import Foundation

/// Shared loader for Homebrew's cask database (formulae.brew.sh/api/cask.json),
/// cached locally and refreshed at most once a day. Used by the cask oracle
/// and the drivers/extensions detector.
enum CaskIndex {
    struct CaskInfo {
        let token: String
        let version: String
        let homepage: String?
        /// .app bundle filenames this cask installs, plus its human-readable names.
        let appNames: [String]
        /// Facts adoption checks (Phase 7). Defaults keep other callers simple.
        /// The .app bundle filenames alone, without the human names.
        var apps: [String] = []
        /// Installs by running a pkg (needs the admin password).
        var pkg = false
        /// Marked by Homebrew as updating itself.
        var autoUpdates = false
        /// Bundle ids from the cask's `uninstall quit:` and `pkgutil:` stanzas.
        var quitIDs: [String] = []
        var pkgutilIDs: [String] = []
        /// The download, for the size shown in the adoption sheet.
        var url: String?
        /// `depends_on macos: >= …`, when set.
        var minimumMacOS: String?
        /// `depends_on arch: intel` (can't run natively here).
        var intelOnly = false
        /// The tap it comes from (adoption only trusts homebrew/cask).
        var tap: String?
    }

    static func load() async throws -> [CaskInfo] {
        try await parse(rawData())
    }

    static let cacheURL = Store.supportDirectory.appendingPathComponent("cask-index.json")

    /// The cask JSON, from the cache when it's under a day old, else freshly
    /// downloaded (or the stale cache when offline). Discover reads the same file.
    static func rawData() async throws -> Data {
        let fm = FileManager.default
        let maxAge: TimeInterval = 24 * 3600

        if let attrs = try? fm.attributesOfItem(atPath: cacheURL.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < maxAge,
           let cached = fm.contents(atPath: cacheURL.path) {
            return cached
        }
        // The update check and Discover often ask at the same moment: they
        // share one download instead of fetching 19 MB twice.
        if let downloaded = await Download.shared.data() { return downloaded }
        // Fall back to a stale cache if we're offline.
        if let stale = fm.contents(atPath: cacheURL.path) { return stale }
        throw PrismPackError.parseFailure("cask index download")
    }

    /// One download at a time, shared by everyone waiting on it.
    private actor Download {
        static let shared = Download()
        private var running: Task<Data?, Never>?

        func data() async -> Data? {
            if let running { return await running.value }
            let task = Task<Data?, Never> {
                let url = URL(string: "https://formulae.brew.sh/api/cask.json")!
                guard let (data, response) = try? await Net.fetch(url),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                try? data.write(to: CaskIndex.cacheURL, options: .atomic)
                return data
            }
            running = task
            let result = await task.value
            running = nil
            return result
        }
    }

    private static func parse(_ data: Data) throws -> [CaskInfo] {
        // The cask JSON's `artifacts` array is heterogeneous, so parse leniently.
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PrismPackError.parseFailure("cask index JSON")
        }
        var casks: [CaskInfo] = []
        casks.reserveCapacity(array.count)
        for obj in array {
            guard let token = obj["token"] as? String,
                  let version = obj["version"] as? String,
                  version != "latest",                       // unversioned casks can't be compared
                  obj["deprecated"] as? Bool != true,
                  obj["disabled"] as? Bool != true
            else { continue }

            var apps: [String] = []
            var pkg = false
            var quitIDs: [String] = [], pkgutilIDs: [String] = []
            if let artifacts = obj["artifacts"] as? [[String: Any]] {
                for artifact in artifacts {
                    if let found = artifact["app"] as? [Any] {
                        apps += found.compactMap { $0 as? String }
                    }
                    if artifact["pkg"] != nil { pkg = true }
                    for stanza in artifact["uninstall"] as? [[String: Any]] ?? [] {
                        quitIDs += strings(stanza["quit"])
                        pkgutilIDs += strings(stanza["pkgutil"])
                    }
                }
            }
            let depends = obj["depends_on"] as? [String: Any] ?? [:]
            let macos = (depends["macos"] as? [String: Any])?[">="] as? [String]
            let arch = depends["arch"] as? [[String: Any]] ?? []
            var info = CaskInfo(token: token, version: version,
                                homepage: obj["homepage"] as? String,
                                appNames: (obj["name"] as? [String] ?? []) + apps)
            info.apps = apps
            info.pkg = pkg
            info.autoUpdates = obj["auto_updates"] as? Bool == true
            info.quitIDs = quitIDs
            info.pkgutilIDs = pkgutilIDs
            info.url = obj["url"] as? String
            info.minimumMacOS = macos?.first
            info.intelOnly = !arch.isEmpty && arch.allSatisfy { $0["type"] as? String == "intel" }
            info.tap = obj["tap"] as? String
            casks.append(info)
        }
        return casks
    }

    /// A stanza value that may be one string or a list of them.
    private static func strings(_ value: Any?) -> [String] {
        if let one = value as? String { return [one] }
        return (value as? [Any])?.compactMap { $0 as? String } ?? []
    }
}

extension CaskIndex {
    /// Casks whose token carries an @-suffix track prerelease channels
    /// (cloudflare-warp@beta, firefox@nightly). They share the same app name as
    /// the stable cask, so a naive name index can match them and offer a beta as
    /// an "update" — and Homebrew then refuses the install because the two casks
    /// conflict. Never match against these.
    static func isPrerelease(_ token: String) -> Bool { token.contains("@") }

    /// App name (lowercased) → stable cask.
    static func byAppName(_ casks: [CaskInfo]) -> [String: CaskInfo] {
        var map: [String: CaskInfo] = [:]
        for cask in casks where !isPrerelease(cask.token) {
            for name in cask.appNames { map[name.lowercased()] = cask }
        }
        return map
    }
}
