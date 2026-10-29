import Foundation

/// Python command-line tools: pipx apps, uv tools, and `pip --user` packages
/// of the python.org interpreter. Homebrew's and macOS's own Pythons are never
/// touched. A Mac with none of these tools just gets an empty section.
struct PythonSource: UpdateSource {
    let id = "pip"
    let displayName = "Python (pip)"

    /// The one plain-pip interpreter PrismPack looks at (python.org's).
    static let userPython = "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"

    func detect() async throws -> [UpdateItem] {
        async let pipx = pipxOutdated()
        async let uv = uvOutdated()
        async let pip = pipUserOutdated()
        let all = try await pipx + uv + pip
        return all.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        let parts = item.installToken.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw UpdateScoutError.parseFailure("install token \(item.installToken)") }
        let (kind, name) = (parts[0], parts[1])
        let tool: String, args: [String]
        switch kind {
        case "pipx":
            tool = try Self.require("pipx"); args = ["upgrade", name]
        case "uv":
            tool = try Self.require("uv"); args = ["tool", "upgrade", name]
        case "uvpin":
            // Only reached from an explicit click: moves a pinned tool to latest.
            tool = try Self.require("uv"); args = ["tool", "install", "\(name)@latest"]
        case "pip":
            tool = Self.userPython; args = ["-m", "pip", "install", "--user", "--upgrade", name]
        default:
            throw UpdateScoutError.parseFailure("install token \(item.installToken)")
        }
        let result = try await Shell.run(tool, args, tag: Shell.installTag, lineHandler: progress)
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed(([(tool as NSString).lastPathComponent] + args).joined(separator: " "),
                                                 output: result.combined)
        }
    }

    private static func require(_ tool: String) throws -> String {
        guard let path = Shell.which(tool) else {
            throw UpdateScoutError.toolMissing(tool, hint: "It was removed after the last check.")
        }
        return path
    }

    private func item(_ kind: String, _ name: String, _ installed: String, _ latest: String,
                      caveat: String? = nil) -> UpdateItem {
        UpdateItem(sourceID: id, name: name, installedVersion: installed, latestVersion: latest,
                   url: "https://pypi.org/project/\(name)/", caveat: caveat,
                   installToken: "\(kind):\(name)", scriptedInstall: true)
    }

    // MARK: pipx

    /// pipx has no "outdated" command: read installed versions from its JSON
    /// and ask PyPI for the latest. Pinned apps (`pipx pin`) are left alone.
    private func pipxOutdated() async throws -> [UpdateItem] {
        guard let pipx = Shell.which("pipx") else { return [] }
        let result = try await Shell.run(pipx, ["list", "--json"])
        guard result.status == 0 else { throw UpdateScoutError.commandFailed("pipx list --json", output: result.combined) }
        guard let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let venvs = json["venvs"] as? [String: Any]
        else { throw UpdateScoutError.parseFailure("pipx list output") }

        var installed: [(name: String, version: String)] = []
        for case let (name, venv as [String: Any]) in venvs {
            guard let meta = (venv["metadata"] as? [String: Any])?["main_package"] as? [String: Any],
                  meta["pinned"] as? Bool != true,
                  let version = meta["package_version"] as? String else { continue }
            installed.append((name, version))
        }
        return await withTaskGroup(of: UpdateItem?.self) { group in
            for pkg in installed {
                group.addTask {
                    guard let latest = await Self.pypiLatest(pkg.name),
                          isNewerVersion(latest, than: pkg.version) else { return nil }
                    return self.item("pipx", pkg.name, pkg.version, latest)
                }
            }
            var items: [UpdateItem] = []
            for await item in group { if let item { items.append(item) } }
            return items
        }
    }

    /// Best effort: a failed lookup just means "no update known".
    static func pypiLatest(_ name: String) async -> String? {
        guard let url = URL(string: "https://pypi.org/pypi/\(name)/json"),
              let (data, _) = try? await Net.fetch(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (json["info"] as? [String: Any])?["version"] as? String
    }

    // MARK: uv

    /// `uv tool list --outdated` is text only, e.g. `ruff v0.5.0 [latest: 0.17.3]`;
    /// with specifiers shown, a pinned tool also carries `[required: ==0.5.0]`.
    private func uvOutdated() async throws -> [UpdateItem] {
        guard let uv = Shell.which("uv") else { return [] }
        let result = try await Shell.run(uv, ["tool", "list", "--outdated", "--show-version-specifiers"])
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed("uv tool list --outdated", output: result.combined)
        }
        return Self.parseUVList(result.stdout).map { tool in
            tool.pinned
                ? item("uvpin", tool.name, tool.installed, tool.latest,
                       caveat: "Pinned to \(tool.installed). Updating moves it to the latest version.")
                : item("uv", tool.name, tool.installed, tool.latest)
        }
    }

    static func parseUVList(_ text: String) -> [(name: String, installed: String, latest: String, pinned: Bool)] {
        let pattern = #/^(\S+)\s+v(\S+)(.*)$/#
        let latestTag = #/\[latest:\s*([^\]\s]+)\s*\]/#
        let requiredTag = #/\[required:\s*==/#
        var tools: [(String, String, String, Bool)] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("-") {
            guard let m = line.firstMatch(of: pattern),
                  let latest = m.3.firstMatch(of: latestTag)?.1 else { continue }
            tools.append((String(m.1), String(m.2), String(latest), m.3.contains(requiredTag)))
        }
        return tools
    }

    // MARK: pip --user

    /// Only python.org's interpreter, only `--user` packages, and never an
    /// interpreter marked externally managed (PEP 668).
    private func pipUserOutdated() async throws -> [UpdateItem] {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: Self.userPython) else { return [] }
        let lib = (Self.userPython as NSString).deletingLastPathComponent + "/../lib"
        let managed = ((try? fm.contentsOfDirectory(atPath: lib)) ?? [])
            .filter { $0.hasPrefix("python3") }
            .contains { fm.fileExists(atPath: "\(lib)/\($0)/EXTERNALLY-MANAGED") }
        guard !managed else { return [] }

        let result = try await Shell.run(Self.userPython,
                                         ["-m", "pip", "list", "--user", "--outdated", "--format=json",
                                          "--disable-pip-version-check"])
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed("pip list --user --outdated", output: result.combined)
        }
        guard let rows = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [[String: Any]] else {
            throw UpdateScoutError.parseFailure("pip list output")
        }
        return rows.compactMap { row in
            guard let name = row["name"] as? String, let installed = row["version"] as? String,
                  let latest = row["latest_version"] as? String else { return nil }
            return item("pip", name, installed, latest)
        }
    }
}
