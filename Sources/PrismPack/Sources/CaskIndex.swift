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

            var appNames: [String] = obj["name"] as? [String] ?? []
            if let artifacts = obj["artifacts"] as? [[String: Any]] {
                for artifact in artifacts {
                    if let apps = artifact["app"] as? [Any] {
                        appNames += apps.compactMap { $0 as? String }
                    }
                }
            }
            casks.append(CaskInfo(token: token, version: version,
                                  homepage: obj["homepage"] as? String,
                                  appNames: appNames))
        }
        return casks
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
