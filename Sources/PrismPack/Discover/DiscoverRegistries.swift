import Foundation

/// Live searches for the registries too big to download: npm, crates.io,
/// RubyGems and the editor extension stores. PyPI has no search, so Python
/// gets exact-name lookup plus a short curated list. Each throws its own
/// error so a failing registry never blocks the others.
enum DiscoverRegistries {
    static func npm(_ text: String) async throws -> [DiscoverEntry] {
        guard let url = query("https://registry.npmjs.org/-/v1/search", ["text": text, "size": "25"]),
              let json = try await Net.json(url) as? [String: Any],
              let objects = json["objects"] as? [[String: Any]] else { throw PrismPackError.parseFailure("npm search") }
        return objects.compactMap { obj in
            guard let pkg = obj["package"] as? [String: Any], let name = pkg["name"] as? String else { return nil }
            let monthly = (obj["downloads"] as? [String: Any])?["monthly"] as? Int ?? 0
            return DiscoverEntry(kind: .npm, name: name, title: name, summary: pkg["description"] as? String,
                                 version: pkg["version"] as? String ?? "",
                                 homepage: ((pkg["links"] as? [String: Any])?["npm"] as? String), popularity: monthly)
        }
    }

    static func crates(_ text: String) async throws -> [DiscoverEntry] {
        guard let url = query("https://crates.io/api/v1/crates", ["q": text, "per_page": "25"]),
              let json = try await Net.json(url) as? [String: Any],
              let crates = json["crates"] as? [[String: Any]] else { throw PrismPackError.parseFailure("crates.io search") }
        return crates.compactMap { c in
            guard let name = c["name"] as? String else { return nil }
            return DiscoverEntry(kind: .crate, name: name, title: name, summary: c["description"] as? String,
                                 version: c["max_stable_version"] as? String ?? c["max_version"] as? String ?? "",
                                 homepage: "https://crates.io/crates/\(name)", popularity: c["downloads"] as? Int ?? 0)
        }
    }

    static func gems(_ text: String) async throws -> [DiscoverEntry] {
        guard let url = query("https://rubygems.org/api/v1/search.json", ["query": text]),
              let gems = try await Net.json(url) as? [[String: Any]] else { throw PrismPackError.parseFailure("RubyGems search") }
        return gems.prefix(25).compactMap { g in
            guard let name = g["name"] as? String else { return nil }
            return DiscoverEntry(kind: .gem, name: name, title: name, summary: g["info"] as? String,
                                 version: g["version"] as? String ?? "",
                                 homepage: g["project_uri"] as? String, popularity: g["downloads"] as? Int ?? 0)
        }
    }

    /// PyPI by exact name. nil when there's no such package.
    static func pypi(_ name: String) async throws -> DiscoverEntry? {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !clean.contains(" "),
              let safe = clean.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])),
              let url = URL(string: "https://pypi.org/pypi/\(safe)/json") else { return nil }
        let (data, response) = try await Net.fetch(url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["info"] as? [String: Any], let real = info["name"] as? String
        else { throw PrismPackError.parseFailure("PyPI lookup") }
        return DiscoverEntry(kind: .pypi, name: real, title: real, summary: info["summary"] as? String,
                             version: info["version"] as? String ?? "",
                             homepage: "https://pypi.org/project/\(real)/")
    }

    /// Command line apps that install well with pipx. PyPI can't be searched,
    /// so these are the starting points; anything else is found by exact name.
    static let curatedPython: [(name: String, summary: String)] = [
        ("ruff", "Very fast Python linter and formatter"),
        ("black", "The uncompromising Python code formatter"),
        ("mypy", "Static type checker for Python"),
        ("poetry", "Python packaging and dependency management"),
        ("pdm", "Modern Python package and dependency manager"),
        ("hatch", "Modern, extensible Python project manager"),
        ("pre-commit", "Framework for managing git pre-commit hooks"),
        ("tox", "Run tests across Python versions"),
        ("nox", "Flexible test automation"),
        ("twine", "Publish Python packages to PyPI"),
        ("cookiecutter", "Create projects from templates"),
        ("copier", "Project templates that can be updated"),
        ("ipython", "A richer interactive Python shell"),
        ("jupyterlab", "Notebooks in the browser"),
        ("httpie", "Human-friendly command line HTTP client"),
        ("yt-dlp", "Download video and audio from many sites"),
        ("datasette", "Explore and publish data"),
        ("sqlite-utils", "Work with SQLite databases from the command line"),
        ("visidata", "Terminal spreadsheet for exploring data"),
        ("csvkit", "Tools for working with CSV files"),
        ("pgcli", "Postgres command line with completion"),
        ("mycli", "MySQL command line with completion"),
        ("litecli", "SQLite command line with completion"),
        ("rich-cli", "Pretty-print files and data in the terminal"),
        ("glances", "System monitor for the terminal"),
        ("asciinema", "Record and share terminal sessions"),
        ("mkdocs", "Project documentation with Markdown"),
        ("pipdeptree", "Show a dependency tree of installed packages"),
        ("tldr", "Simplified, community-driven man pages"),
        ("speedtest-cli", "Test internet bandwidth"),
    ]

    static var curatedPythonEntries: [DiscoverEntry] {
        curatedPython.map {
            DiscoverEntry(kind: .pypi, name: $0.name, title: $0.name, summary: $0.summary, version: "",
                          homepage: "https://pypi.org/project/\($0.name)/")
        }
    }

    /// The VS Code Marketplace when VS Code is installed, else Open VSX (what
    /// VSCodium and Cursor use). If the Marketplace fails, Open VSX answers
    /// instead and `note` says so.
    static func extensions(_ text: String) async throws -> (entries: [DiscoverEntry], note: String?) {
        let editors = EditorExtensionsSource.editors()
        if editors.contains(where: \.usesMarketplace) {
            if let hits = try? await Marketplace.search(text) {
                return (hits.map { ext($0.id, $0.name, $0.summary, $0.version, $0.installs, market: true) }, nil)
            }
            let hits = try await OpenVSX.search(text)
            return (hits.map { ext($0.id, $0.name, $0.summary, $0.version, $0.installs, market: false) },
                    "The VS Code Marketplace didn't answer, so these results come from Open VSX.")
        }
        let hits = try await OpenVSX.search(text)
        return (hits.map { ext($0.id, $0.name, $0.summary, $0.version, $0.installs, market: false) }, nil)
    }

    private static func ext(_ id: String, _ name: String, _ summary: String?, _ version: String,
                            _ installs: Int, market: Bool) -> DiscoverEntry {
        DiscoverEntry(kind: .ext, name: id, title: name, summary: summary, version: version,
                      homepage: market ? "https://marketplace.visualstudio.com/items?itemName=\(id)"
                                       : "https://open-vsx.org/extension/\(OpenVSX.path(of: id))",
                      popularity: installs)
    }

    private static func query(_ base: String, _ items: [String: String]) -> URL? {
        var parts = URLComponents(string: base)
        parts?.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts?.url
    }
}

/// Runs Discover installs through the update queue, so they share its lanes:
/// a cask or formula waits for any other `brew` work, an npm package for the
/// npm lane, and so on. Install tokens are `<kind>:<name>`.
struct DiscoverInstaller: UpdateSource {
    let id = "discover"
    let displayName = "Discover"

    func detect() async throws -> [UpdateItem] { [] }

    /// The queue item for an entry. For an extension, `editorKey` picks the
    /// editor to install it into.
    static func item(for entry: DiscoverEntry, editorKey: String? = nil) -> UpdateItem {
        let token: String
        switch entry.kind {
        case .cask: token = "cask:\(entry.name)"
        case .formula: token = "formula:\(entry.name)"
        case .npm: token = "npm:\(entry.name)"
        case .pypi: token = "pipx:\(entry.name)"
        case .crate: token = "cargo:\(entry.name)"
        case .gem: token = "gem:\(entry.name)"
        case .ext: token = "ext-\(editorKey ?? "code"):\(entry.name)"
        }
        return UpdateItem(sourceID: "discover", name: entry.title, installedVersion: "", latestVersion: entry.version,
                          url: entry.homepage, installToken: token, scriptedInstall: true)
    }

    /// The lane an install token runs in (see UpdateController.lane).
    static func lane(of token: String) -> String {
        let kind = token.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        switch kind {
        case "cask", "formula", "zap": return "brew"
        case "pipx", "uv": return "pip"
        case "npm", "cargo", "gem", "app": return kind
        default: return kind.hasPrefix("ext-") ? "editors" : "discover"
        }
    }

    /// "Homebrew", "npm", … for the Activity log.
    static func sourceTitle(of token: String) -> String {
        switch lane(of: token) {
        case "brew": "Homebrew"
        case "pip": "Python (pipx)"
        case "cargo": "Rust (cargo)"
        case "gem": "Ruby (gems)"
        case "editors": "Editor extensions"
        case "app": "Moved to the Trash"
        default: "npm"
        }
    }

    func needsAdmin(_ item: UpdateItem) -> Bool {
        HomebrewSource.caskToken(of: item).map(HomebrewSource.isInstallerCask) ?? false
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        let parts = item.installToken.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw PrismPackError.parseFailure("install token \(item.installToken)") }
        let (kind, name) = (parts[0], parts[1])
        switch kind {
        case "cask", "formula":
            guard let brew = HomebrewSource.brewPath else {
                throw PrismPackError.toolMissing("Homebrew", hint: "Install it from https://brew.sh")
            }
            try await run(brew, kind == "cask" ? ["install", "--cask", name] : ["install", name], progress)
        case "npm":
            guard let npm = Shell.which("npm") else {
                throw PrismPackError.toolMissing("npm", hint: "Install Node from Homebrew (the node formula).")
            }
            try await run(npm, ["install", "-g", name], progress)
        case "pipx":
            guard let pipx = Shell.which("pipx") else {
                throw PrismPackError.toolMissing("pipx", hint: "Install pipx from Homebrew (the pipx formula).")
            }
            try await run(pipx, ["install", name], progress)
        case "cargo":
            try await CargoSource.cargoInstall(name, progress: progress)
        case "gem":
            try await GemSource.gemInstall(name, progress: progress)
        case let k where k.hasPrefix("ext-"):
            try await EditorExtensionsSource.install(extension: name, editorKey: String(k.dropFirst(4)), progress: progress)
        default:
            throw PrismPackError.parseFailure("install token \(item.installToken)")
        }
    }

    private func run(_ tool: String, _ args: [String], _ progress: @escaping @Sendable (String) -> Void) async throws {
        let result = try await Shell.run(tool, args, tag: Shell.installTag, lineHandler: progress)
        guard result.status == 0 else {
            throw PrismPackError.commandFailed(([(tool as NSString).lastPathComponent] + args).joined(separator: " "),
                                                 output: result.combined)
        }
    }
}
