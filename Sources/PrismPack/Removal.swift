import AppKit

/// How one installed thing is removed, worked out from where it came from.
/// It runs as a queue job (`Remover`), so it shares the install lanes:
/// a Homebrew removal waits for any other `brew` work, and so on.
/// Tokens are `<kind>:<name>`, as for Discover installs, plus `uv:`,
/// `ext-all:` (every editor that has the extension) and `app:<path>`.
struct Removal: Hashable, Sendable {
    let token: String
    let name: String

    /// What the confirmation says happens.
    var explanation: String {
        switch kind {
        case "app": "\(name) moves to the Trash. You can put it back from there."
        case "cask": "Homebrew removes the app. Its settings and data stay."
        case "formula" where Tools.packageLane(ofFormula: target) != nil:
            "Homebrew removes it, and any libraries nothing else needs. Packages you installed with \(target) stop working until it's back."
        case "formula": "Homebrew removes it, and any libraries nothing else needs."
        case "npm": "npm removes the global package."
        case "pipx", "uv": "The app and its private Python environment are removed."
        case "cargo": "cargo removes the installed program."
        case "gem": "Every installed version of the gem is removed."
        default: "The extension is removed from the editor."
        }
    }

    /// "Move to Trash" for apps, else "Uninstall".
    var actionTitle: String { kind == "app" ? "Move to Trash" : "Uninstall" }

    var kind: String { token.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "" }
    var target: String { token.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? "" }

    /// The queue job.
    var item: UpdateItem {
        UpdateItem(sourceID: "remove", name: name, installedVersion: "", latestVersion: "",
                   url: nil, installToken: token, scriptedInstall: true)
    }

    // MARK: Building one

    /// From the Installed list. nil for what can't or mustn't be removed
    /// here: PrismPack itself, and npm's own bundled packages.
    init?(_ pkg: InstalledPackage) {
        switch pkg.sourceID {
        case "homebrew", "tools":
            if let detail = pkg.detail, detail.hasPrefix("cask ") {
                self.init(token: "cask:" + detail.dropFirst(5), name: pkg.name)
            } else {
                self.init(token: "formula:\(pkg.name)", name: pkg.name)
            }
        case "pip":
            self.init(token: (pkg.detail == "uv tool" ? "uv:" : "pipx:") + pkg.name, name: pkg.name)
        case "npm":
            guard pkg.detail == nil else { return nil }
            self.init(token: "npm:\(pkg.name)", name: pkg.name)
        case "cargo", "gem":
            self.init(token: "\(pkg.sourceID):\(pkg.name)", name: pkg.name)
        case "editors":
            let id = pkg.name.split(separator: " ").first.map(String.init) ?? pkg.name
            guard let editor = EditorExtensionsSource.editors().first(where: { $0.name == pkg.detail }) else { return nil }
            self.init(token: "ext-\(editor.key):\(id)", name: pkg.name)
        default:
            // App Store, Sparkle and unmanaged apps go to the Trash.
            guard let path = pkg.appPath, !Self.isSelf(path) else { return nil }
            self.init(token: "app:\(path)", name: pkg.name)
        }
    }

    /// From a Discover entry that's installed.
    init(_ entry: DiscoverEntry) {
        let kind: String
        switch entry.kind {
        case .cask: kind = "cask"
        case .formula: kind = "formula"
        case .npm: kind = "npm"
        case .pypi: kind = "pipx"
        case .crate: kind = "cargo"
        case .gem: kind = "gem"
        case .ext: kind = "ext-all"
        }
        self.init(token: "\(kind):\(entry.name)", name: entry.title)
    }

    init(token: String, name: String) {
        self.token = token
        self.name = name
    }

    private static func isSelf(_ path: String) -> Bool {
        URL(fileURLWithPath: path).standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }
}

/// Runs removals through the update queue. Its `install` removes.
struct Remover: UpdateSource {
    let id = "remove"
    let displayName = "Uninstall"

    func detect() async throws -> [UpdateItem] { [] }

    /// pkg-based casks need the admin password to remove, as to install.
    func needsAdmin(_ item: UpdateItem) -> Bool {
        let removal = Removal(token: item.installToken, name: item.name)
        return removal.kind == "cask" && HomebrewSource.isInstallerCask(removal.target)
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        let removal = Removal(token: item.installToken, name: item.name)
        let name = removal.target
        switch removal.kind {
        case "cask", "formula":
            guard let brew = HomebrewSource.brewPath else {
                throw PrismPackError.toolMissing("Homebrew", hint: "It was removed after the last check.")
            }
            try await run(brew, removal.kind == "cask" ? ["uninstall", "--cask", name] : ["uninstall", name], progress)
        case "npm":
            try await run(tool("npm"), ["uninstall", "-g", name], progress)
        case "pipx":
            try await run(tool("pipx"), ["uninstall", name], progress)
        case "uv":
            try await run(tool("uv"), ["tool", "uninstall", name], progress)
        case "cargo":
            try await run(tool("cargo"), ["uninstall", name], progress)
        case "gem":
            guard let gem = GemSource.gem else {
                throw PrismPackError.toolMissing("Ruby from Homebrew", hint: "It was removed after the last check.")
            }
            try await run(gem, ["uninstall", name, "--all", "--executables"], progress)
        case "app":
            progress("Moving \(removal.name) to the Trash…")
            do {
                _ = try await NSWorkspace.shared.recycle([URL(fileURLWithPath: name)])
            } catch {
                throw PrismPackError.commandFailed("Move to Trash",
                    output: "macOS didn't let \(AppIdentity.name) move it (\(error.localizedDescription)). Drag it to the Trash in Finder instead.")
            }
        case "ext-all":
            for editor in EditorExtensionsSource.editors() {
                let has = (try? await EditorExtensionsSource.installed(in: editor))?
                    .contains { $0.id.caseInsensitiveCompare(name) == .orderedSame } ?? false
                if has { try await run(editor.cli, ["--uninstall-extension", name], progress) }
            }
        case let k where k.hasPrefix("ext-"):
            guard let editor = EditorExtensionsSource.editors().first(where: { $0.key == String(k.dropFirst(4)) }) else {
                throw PrismPackError.toolMissing(String(k.dropFirst(4)), hint: "The editor was removed after the last check.")
            }
            try await run(editor.cli, ["--uninstall-extension", name], progress)
        default:
            throw PrismPackError.parseFailure("removal token \(item.installToken)")
        }
    }

    private func tool(_ name: String) throws -> String {
        guard let path = Shell.which(name) else {
            throw PrismPackError.toolMissing(name, hint: "It was removed after the last check.")
        }
        return path
    }

    private func run(_ tool: String, _ args: [String], _ progress: @escaping @Sendable (String) -> Void) async throws {
        let result = try await Shell.run(tool, args, tag: Shell.installTag, lineHandler: progress)
        guard result.status == 0 else {
            throw PrismPackError.commandFailed(([(tool as NSString).lastPathComponent] + args).joined(separator: " "),
                                                 output: result.combined)
        }
    }
}
