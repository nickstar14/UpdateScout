import Foundation

/// Cross-references apps in /Applications against Homebrew's cask database —
/// including apps that were NOT installed via Homebrew (DisplayLink Manager etc.).
/// The cask index (https://formulae.brew.sh/api/cask.json) is cached locally and
/// refreshed at most once a day.
struct CaskOracleSource: UpdateSource {
    let id = "caskOracle"
    let displayName = "Other apps (via Homebrew data)"

    func detect() async throws -> [UpdateItem] {
        guard let brew = HomebrewSource.brewPath else { return [] }

        let casks = try await CaskIndex.load()

        // Apps already managed as brew casks are HomebrewSource's job; skip them here.
        let installedCasksResult = try? await Shell.run(brew, ["list", "--cask", "-1"])
        let brewManaged = Set((installedCasksResult?.stdout ?? "").split(separator: "\n").map(String.init))

        // Index casks by lowercase app filename and by human name.
        var byName: [String: CaskIndex.CaskInfo] = [:]
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

}
