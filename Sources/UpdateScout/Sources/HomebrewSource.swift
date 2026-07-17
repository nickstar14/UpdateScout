import Foundation

struct HomebrewSource: UpdateSource {
    let id = "homebrew"
    let displayName = "Homebrew"

    static var brewPath: String? { Shell.which("brew") }

    func detect() async throws -> [UpdateItem] {
        guard let brew = Self.brewPath else {
            throw UpdateScoutError.toolMissing("Homebrew", hint: "Install it from https://brew.sh")
        }
        // Refresh brew's own metadata first so "outdated" is against current data.
        _ = try? await Shell.run(brew, ["update", "--quiet"])
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

        var items: [UpdateItem] = []
        for f in outdated.formulae {
            items.append(UpdateItem(sourceID: id, name: f.name,
                                    installedVersion: f.installed_versions.last ?? "?",
                                    latestVersion: f.current_version,
                                    url: "https://formulae.brew.sh/formula/\(f.name)",
                                    installToken: "formula:\(f.name)"))
        }
        for c in outdated.casks {
            items.append(UpdateItem(sourceID: id, name: c.name,
                                    installedVersion: c.installed_versions.last ?? "?",
                                    latestVersion: c.current_version,
                                    url: "https://formulae.brew.sh/cask/\(c.name)",
                                    installToken: "cask:\(c.name)"))
        }
        return items
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
