import Foundation

/// Cross-references apps in /Applications against Homebrew's cask database —
/// including apps that were NOT installed via Homebrew (DisplayLink Manager etc.).
/// The cask index (https://formulae.brew.sh/api/cask.json) is cached locally and
/// refreshed at most once a day.
struct CaskOracleSource: UpdateSource {
    let id = "caskOracle"
    let displayName = "Other apps (via Homebrew data)"

    /// Casks that run a pkg installer ask for a password.
    func needsAdmin(_ item: UpdateItem) -> Bool { HomebrewSource.isInstallerCask(item.installToken) }

    func detect() async throws -> [UpdateItem] {
        guard let brew = HomebrewSource.brewPath else { return [] }

        let casks = try await CaskIndex.load()

        // Apps already managed as brew casks are HomebrewSource's job; skip them here.
        // If this fails, stop: treating every cask as unmanaged would offer to
        // reinstall apps Homebrew already manages.
        let listed = try await Shell.run(brew, ["list", "--cask", "-1"])
        guard listed.status == 0 else {
            throw PrismPackError.commandFailed("brew list --cask", output: listed.combined)
        }
        let brewManaged = Set(listed.stdout.split(separator: "\n").map(String.init))

        // Index casks by lowercase app filename and by human name (stable
        // casks only — see CaskIndex.byAppName).
        let byName = CaskIndex.byAppName(casks)

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
                                        caveat: "Installs via Homebrew: your copy goes to the Trash and this app becomes Homebrew-managed (cask \"\(cask.token)\"). Its settings and data stay.",
                                        installToken: cask.token,
                                        appPath: appURL.path))
            }
        }
        return items
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let brew = HomebrewSource.brewPath else {
            throw PrismPackError.toolMissing("Homebrew", hint: "Install it from https://brew.sh")
        }
        // Replace, not `--force` (which deleted the old app outright): the
        // old copy waits in the Trash until Homebrew's is checked (Nick, 30 Oct 2026).
        guard let appPath = item.appPath else {
            throw PrismPackError.parseFailure("app path for \(item.name)")
        }
        _ = brew
        try await Adopter.replace(cask: item.installToken, appPath: appPath, name: item.name, progress: progress)
    }

    // MARK: - App scan

    /// Top-level apps only: Homebrew would install the cask's copy at the
    /// top level, leaving an app one folder down where it was.
    private func installedApps() -> [URL] {
        AppFolders.appPaths().filter { !AppFolders.isNested($0) }.map { URL(fileURLWithPath: $0) }
    }

}
