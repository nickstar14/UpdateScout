import Foundation

struct HomebrewSource: UpdateSource {
    let id = "homebrew"
    let displayName = "Homebrew"

    static var brewPath: String? { Shell.which("brew") }

    func detect() async throws -> [UpdateItem] {
        guard let brew = Self.brewPath else {
            throw UpdateScoutError.toolMissing("Homebrew", hint: "Install it from https://brew.sh")
        }
        // Refresh brew's own metadata first so "outdated" is against current
        // data. Background checks can run every few minutes, and brew's
        // formula data changes on the order of hours, so they refresh at most
        // every 30 minutes; a manual Check Now always refreshes.
        let background = CommandLine.arguments.contains("--background-check")
        let last = UserDefaults.standard.object(forKey: "lastBrewUpdate") as? Date ?? .distantPast
        if !background || Date().timeIntervalSince(last) > 30 * 60 {
            _ = try? await Shell.run(brew, ["update", "--quiet"])
            UserDefaults.standard.set(Date(), forKey: "lastBrewUpdate")
        }
        let result = try await Shell.run(brew, ["outdated", "--json=v2"])
        guard result.status == 0, let data = result.stdout.data(using: .utf8) else {
            throw UpdateScoutError.commandFailed("brew outdated", output: result.combined)
        }

        struct Outdated: Decodable {
            struct Formula: Decodable {
                let name: String
                let installed_versions: [String]
                let current_version: String
            }
            struct Cask: Decodable {
                let name: String
                let installed_versions: [String]
                let current_version: String
            }
            let formulae: [Formula]
            let casks: [Cask]
        }
        let outdated = try JSONDecoder().decode(Outdated.self, from: data)

        // Project homepages (one call for everything): a better "info page"
        // than formulae.brew.sh, and lets GitHubNotes find changelogs.
        let info = await info(brew: brew,
                              formulae: outdated.formulae.map(\.name),
                              casks: outdated.casks.map(\.name))

        var items: [UpdateItem] = []
        for f in outdated.formulae {
            items.append(UpdateItem(sourceID: id, name: f.name,
                                    installedVersion: f.installed_versions.last ?? "?",
                                    latestVersion: f.current_version,
                                    url: info[f.name]?.homepage ?? "https://formulae.brew.sh/formula/\(f.name)",
                                    installToken: "formula:\(f.name)"))
        }
        for c in outdated.casks {
            items.append(UpdateItem(sourceID: id, name: c.name,
                                    installedVersion: c.installed_versions.last ?? "?",
                                    latestVersion: c.current_version,
                                    url: info[c.name]?.homepage ?? "https://formulae.brew.sh/cask/\(c.name)",
                                    installToken: "cask:\(c.name)",
                                    appPath: info[c.name]?.appName.flatMap {
                                        AppLocator.find(named: ($0 as NSString).deletingPathExtension)
                                    } ?? info[c.name]?.deletedApp ?? AppLocator.findUnique(prefix: c.name)))
        }
        return items
    }

    private struct Info {
        var homepage: String?
        /// The .app the cask installs (app-artifact casks).
        var appName: String?
        /// For pkg casks: an existing /Applications/*.app named in the
        /// uninstall stanza's delete list, if any.
        var deletedApp: String?
    }

    /// Homepage and installed .app name for each outdated item, from one
    /// `brew info` call per kind.
    private func info(brew: String, formulae: [String], casks: [String]) async -> [String: Info] {
        var map: [String: Info] = [:]
        func collect(_ args: [String], key: String, nameKey: String) async {
            guard let result = try? await Shell.run(brew, args), result.status == 0,
                  let data = result.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json[key] as? [[String: Any]] else { return }
            for e in entries {
                guard let name = e[nameKey] as? String else { continue }
                var appName: String?
                var deletedApp: String?
                for artifact in (e["artifacts"] as? [[String: Any]]) ?? [] {
                    if let apps = artifact["app"] as? [Any], let first = apps.first as? String {
                        appName = first
                    }
                    for stanza in (artifact["uninstall"] as? [[String: Any]]) ?? [] {
                        let paths = (stanza["delete"] as? [String]) ?? (stanza["delete"] as? String).map { [$0] } ?? []
                        if let hit = paths.first(where: {
                            $0.hasPrefix("/Applications/") && $0.hasSuffix(".app")
                                && FileManager.default.fileExists(atPath: $0) }) {
                            deletedApp = hit
                        }
                    }
                }
                map[name] = Info(homepage: e["homepage"] as? String, appName: appName, deletedApp: deletedApp)
            }
        }
        if !formulae.isEmpty {
            await collect(["info", "--json=v2", "--formula"] + formulae, key: "formulae", nameKey: "name")
        }
        if !casks.isEmpty {
            await collect(["info", "--json=v2", "--cask"] + casks, key: "casks", nameKey: "token")
        }
        return map
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let brew = Self.brewPath else {
            throw UpdateScoutError.toolMissing("Homebrew", hint: "Install it from https://brew.sh")
        }
        let parts = item.installToken.split(separator: ":", maxSplits: 1).map(String.init)
        let (kind, name) = (parts.first ?? "", parts.last ?? item.name)
        let args = kind == "cask" ? ["upgrade", "--cask", name] : ["upgrade", name]
        let result = try await Shell.run(brew, args, tag: "install", lineHandler: progress)
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed("brew \(args.joined(separator: " "))", output: result.combined)
        }
    }
}
