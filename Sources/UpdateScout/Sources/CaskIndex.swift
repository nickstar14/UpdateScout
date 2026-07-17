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
        let cacheURL = Store.supportDirectory.appendingPathComponent("cask-index.json")
        let fm = FileManager.default
        let maxAge: TimeInterval = 24 * 3600

        var data: Data? = nil
        if let attrs = try? fm.attributesOfItem(atPath: cacheURL.path),
           let modified = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < maxAge {
            data = fm.contents(atPath: cacheURL.path)
        }
        if data == nil {
            let url = URL(string: "https://formulae.brew.sh/api/cask.json")!
            let (downloaded, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                // Fall back to a stale cache if we're offline.
                if let stale = fm.contents(atPath: cacheURL.path) { return try parse(stale) }
                throw UpdateScoutError.parseFailure("cask index download")
            }
            try? downloaded.write(to: cacheURL, options: .atomic)
            data = downloaded
        }
        return try parse(data!)
    }

    private static func parse(_ data: Data) throws -> [CaskInfo] {
        // The cask JSON's `artifacts` array is heterogeneous, so parse leniently.
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw UpdateScoutError.parseFailure("cask index JSON")
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
