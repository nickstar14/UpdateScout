import Foundation

/// Cross-references apps in /Applications against Homebrew's cask database —
/// including apps that were NOT installed via Homebrew (DisplayLink Manager etc.).
/// The cask index (https://formulae.brew.sh/api/cask.json) is cached locally and
/// refreshed at most once a day.
struct CaskOracleSource: UpdateSource {
    let id = "caskOracle"
    let displayName = "Other apps (via Homebrew data)"

    private struct CaskInfo {
        let token: String
        let version: String
        let homepage: String?
        /// .app bundle filenames this cask installs, plus its human-readable names.
        let appNames: [String]
    }

    func detect() async throws -> [UpdateItem] {
        guard let brew = HomebrewSource.brewPath else { return [] }

        let casks = try await loadCaskIndex()

        // Apps already managed as brew casks are HomebrewSource's job; skip them here.
        let installedCasksResult = try? await Shell.run(brew, ["list", "--cask", "-1"])
        let brewManaged = Set((installedCasksResult?.stdout ?? "").split(separator: "\n").map(String.init))

        // Index casks by lowercase app filename and by human name.
        var byName: [String: CaskInfo] = [:]
        for cask in casks {
            for n in cask.appNames { byName[n.lowercased()] = cask }
        }

        var items: [UpdateItem] = []
        let fm = FileManager.default
        for appURL in installedApps() {
            let fileName = appURL.lastPathComponent                       // "DisplayLink Manager.app"
            let bareName = (fileName as NSString).deletingPathExtension   // "DisplayLink Manager"
            guard let cask = byName[fileName.lowercased()] ?? byName[bareName.lowercased()] else { continue }
            guard !brewManaged.contains(cask.token) else { continue }

            let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
            guard let data = fm.contents(atPath: plistURL.path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let installed = (plist["CFBundleShortVersionString"] ?? plist["CFBundleVersion"]) as? String
            else { continue }

            // Skip Mac App Store installs — those belong to the MAS source.
            if fm.fileExists(atPath: appURL.appendingPathComponent("Contents/_MASReceipt").path) { continue }

            if isNewerVersion(cask.version, than: installed) {
                items.append(UpdateItem(sourceID: id, name: bareName,
                                        installedVersion: installed,
                                        latestVersion: cask.version,
                                        url: cask.homepage ?? "https://formulae.brew.sh/cask/\(cask.token)",
                                        caveat: "Installs via Homebrew — this app will become Homebrew-managed (cask \"\(cask.token)\").",
                                        installToken: cask.token))
            }
        }
        return items
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let brew = HomebrewSource.brewPath else {
            throw UpdateScoutError.toolMissing("Homebrew", hint: "Install it from https://brew.sh")
        }
        let args = ["install", "--cask", item.installToken, "--force"]
        let result = try await Shell.run(brew, args, tag: "install", lineHandler: progress)
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed("brew \(args.joined(separator: " "))", output: result.combined)
        }
    }

    // MARK: - App scan

    private func installedApps() -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            guard let entries = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                           includingPropertiesForKeys: nil) else { continue }
            urls += entries.filter { $0.pathExtension == "app" }
        }
        return urls
    }

    // MARK: - Cask index cache

    private func loadCaskIndex() async throws -> [CaskInfo] {
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
                if let stale = fm.contents(atPath: cacheURL.path) { data = stale }
                else { throw UpdateScoutError.parseFailure("cask index download") }
                return try parse(data!)
            }
            try? downloaded.write(to: cacheURL, options: .atomic)
            data = downloaded
        }
        return try parse(data!)
    }

    private func parse(_ data: Data) throws -> [CaskInfo] {
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
