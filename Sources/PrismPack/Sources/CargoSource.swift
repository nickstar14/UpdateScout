import Foundation

/// Rust command-line tools installed with `cargo install`. cargo has no
/// "outdated" command: installed versions come from `cargo install --list`
/// and the latest from crates.io. A Mac without cargo gets an empty section.
struct CargoSource: UpdateSource {
    let id = "cargo"
    let displayName = "Rust (cargo)"

    func detect() async throws -> [UpdateItem] {
        guard let cargo = Shell.which("cargo") else { return [] }
        let result = try await Shell.run(cargo, ["install", "--list"])
        guard result.status == 0 else {
            throw PrismPackError.commandFailed("cargo install --list", output: result.combined)
        }
        let installed = Self.parseList(result.stdout)
        // Four lookups at a time: crates.io asks API users not to burst.
        return await withTaskGroup(of: UpdateItem?.self) { group in
            var pending = installed[...]
            func addNext() {
                guard let crate = pending.popFirst() else { return }
                group.addTask {
                    guard let latest = await Self.latest(crate.name),
                          isNewerVersion(latest, than: crate.version) else { return nil }
                    return UpdateItem(sourceID: id, name: crate.name, installedVersion: crate.version,
                                      latestVersion: latest, url: "https://crates.io/crates/\(crate.name)",
                                      caveat: "Builds from source, which can take a few minutes.",
                                      installToken: crate.name, scriptedInstall: true)
                }
            }
            for _ in 0..<4 { addNext() }
            var items: [UpdateItem] = []
            for await item in group {
                if let item { items.append(item) }
                addNext()
            }
            return items.sorted { $0.name < $1.name }
        }
    }

    /// `ripgrep v14.1.0:` heads each crate; its binaries follow, indented.
    /// Crates installed from a git repo or a path carry it in brackets and
    /// aren't on crates.io, so they're skipped.
    static func parseList(_ text: String) -> [(name: String, version: String)] {
        let pattern = #/^(\S+) v(\S+?):$/#
        return text.split(separator: "\n").compactMap { line in
            guard let m = line.firstMatch(of: pattern) else { return nil }
            return (String(m.1), String(m.2))
        }
    }

    /// The newest stable version on crates.io. Best effort.
    static func latest(_ name: String) async -> String? {
        guard let url = URL(string: "https://crates.io/api/v1/crates/\(name)"),
              let json = try? await Net.json(url) as? [String: Any],
              let crate = json["crate"] as? [String: Any] else { return nil }
        return crate["max_stable_version"] as? String
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        try await Self.cargoInstall(item.installToken, progress: progress)
    }

    /// `cargo install` replaces an installed crate when a newer one exists,
    /// so it both installs (Discover) and updates.
    static func cargoInstall(_ name: String, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let cargo = Shell.which("cargo") else {
            throw PrismPackError.toolMissing("cargo", hint: "Install Rust from Homebrew (the rust formula).")
        }
        let result = try await Shell.run(cargo, ["install", "--locked", name], tag: Shell.installTag,
                                         lineHandler: progress)
        guard result.status == 0 else {
            throw PrismPackError.commandFailed("cargo install \(name)", output: result.combined)
        }
    }
}
