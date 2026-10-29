import Foundation

/// Globally installed npm packages. A Mac without npm gets an empty section.
struct NPMSource: UpdateSource {
    let id = "npm"
    let displayName = "npm global"

    /// Owned by Homebrew's node, which updates them along with node itself.
    static let skipped: Set<String> = ["npm", "corepack"]

    func detect() async throws -> [UpdateItem] {
        guard let npm = Shell.which("npm") else { return [] }
        let result = try await Shell.run(npm, ["outdated", "-g", "--json"])
        // npm exits 1 whenever anything is outdated, so valid JSON on stdout
        // is the success signal, not the exit status.
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let json = try? JSONSerialization.jsonObject(with: Data((out.isEmpty ? "{}" : out).utf8)) as? [String: Any] else {
            throw UpdateScoutError.commandFailed("npm outdated -g", output: result.combined)
        }
        return Self.parse(json).map { pkg in
            UpdateItem(sourceID: id, name: pkg.name, installedVersion: pkg.current, latestVersion: pkg.latest,
                       url: "https://www.npmjs.com/package/\(pkg.name)", caveat: nil,
                       installToken: pkg.name, scriptedInstall: true)
        }
    }

    static func parse(_ json: [String: Any]) -> [(name: String, current: String, latest: String)] {
        json.compactMap { name, value in
            guard !skipped.contains(name), let info = value as? [String: Any],
                  let current = info["current"] as? String, let latest = info["latest"] as? String,
                  isNewerVersion(latest, than: current) else { return nil }
            return (name, current, latest)
        }
        .sorted { $0.name < $1.name }
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let npm = Shell.which("npm") else {
            throw UpdateScoutError.toolMissing("npm", hint: "It was removed after the last check.")
        }
        let args = ["install", "-g", "\(item.installToken)@latest"]
        let result = try await Shell.run(npm, args, tag: Shell.installTag, lineHandler: progress)
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed("npm " + args.joined(separator: " "), output: result.combined)
        }
    }
}
