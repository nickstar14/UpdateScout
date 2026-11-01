import AppKit

/// How one installed thing is removed, worked out from where it came from.
/// It runs as a queue job (`Remover`), so it shares the install lanes:
/// a Homebrew removal waits for any other `brew` work, and so on.
/// Tokens are `<kind>:<name>`, as for Discover installs, plus `uv:`,
/// `ext-all:` (every editor that has the extension) and `app:<path>`.
struct Removal: Hashable, Sendable {
    let token: String
    let name: String
    /// The app on disk, for a Homebrew app: shown and checked for running
    /// in the uninstall window. Apps (`app:`) carry it in the token.
    var appPath: String? = nil

    /// Apps and Homebrew apps open the uninstall window (Phase 9).
    var opensWindow: Bool { kind == "app" || kind == "cask" }

    /// The app on disk, if this removes one.
    var appOnDisk: String? { kind == "app" ? target : appPath }

    /// The same cask with Homebrew's cleanup list (`--zap`).
    var zap: Removal? {
        kind == "cask" ? Removal(token: "zap:" + target, name: name, appPath: appPath) : nil
    }

    /// What the confirmation says happens.
    var explanation: String {
        switch kind {
        case "app": "\(name) moves to the Trash. You can put it back from there."
        case "cask": "Homebrew removes the app. Its settings and data stay."
        case "zap": "Homebrew removes the app, then cleans up the files on its list for it."
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
                self.init(token: "cask:" + detail.dropFirst(5), name: pkg.name, appPath: pkg.appPath)
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

    init(token: String, name: String, appPath: String? = nil) {
        self.token = token
        self.name = name
        self.appPath = appPath
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

    /// pkg-based casks need the admin password to remove, as to install,
    /// and so does a zap list that reaches outside the user's own folder.
    func needsAdmin(_ item: UpdateItem) -> Bool {
        let removal = Removal(token: item.installToken, name: item.name)
        switch removal.kind {
        case "cask": return HomebrewSource.isInstallerCask(removal.target)
        case "zap": return HomebrewSource.isInstallerCask(removal.target) || Zap.cached(removal.target)?.needsPassword != false
        default: return false
        }
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        let removal = Removal(token: item.installToken, name: item.name)
        let name = removal.target
        switch removal.kind {
        case "cask", "formula", "zap":
            guard let brew = HomebrewSource.brewPath else {
                throw PrismPackError.toolMissing("Homebrew", hint: "It was removed after the last check.")
            }
            let args = switch removal.kind {
            case "cask": ["uninstall", "--cask", name]
            case "zap": ["uninstall", "--cask", "--zap", name]
            default: ["uninstall", name]
            }
            try await run(brew, args, progress)
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

/// Homebrew's own cleanup list for a cask (`zap`), shown before
/// `brew uninstall --zap` runs (Phase 9).
struct Zap: Sendable {
    /// Moved to the Trash by Homebrew.
    var trash: [String] = []
    /// Deleted outright by Homebrew (`delete`, and `rmdir` when empty).
    var delete: [String] = []
    /// Background jobs stopped, installer records removed, apps quit.
    var other: [String] = []
    /// The app's pkg installer or a path outside `~` needs the password.
    var needsPassword = false

    var isEmpty: Bool { trash.isEmpty && delete.isEmpty && other.isEmpty }

    /// The list as shown in the uninstall alert.
    var summary: String {
        var parts: [String] = []
        if !trash.isEmpty { parts.append("To the Trash:\n" + trash.map { "  " + $0 }.joined(separator: "\n")) }
        if !delete.isEmpty { parts.append("Deleted by Homebrew (not to the Trash):\n" + delete.map { "  " + $0 }.joined(separator: "\n")) }
        if !other.isEmpty { parts.append("Also:\n" + other.map { "  " + $0 }.joined(separator: "\n")) }
        return parts.joined(separator: "\n\n")
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var plans: [String: Zap] = [:]

    static func cached(_ token: String) -> Zap? { lock.withLock { plans[token] } }

    /// One `brew info` call. nil when Homebrew can't say.
    static func load(_ token: String) async -> Zap? {
        guard let brew = HomebrewSource.brewPath,
              let result = try? await Shell.run(brew, ["info", "--json=v2", "--cask", token]), result.status == 0,
              let zap = parse(Data(result.stdout.utf8)) else { return nil }
        lock.withLock { plans[token] = zap }
        return zap
    }

    /// From `brew info --json=v2 --cask` output.
    static func parse(_ data: Data) -> Zap? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cask = (json["casks"] as? [[String: Any]])?.first,
              let artifacts = cask["artifacts"] as? [[String: Any]] else { return nil }
        var zap = Zap()
        func strings(_ value: Any?) -> [String] {
            if let s = value as? String { return [s] }
            return (value as? [Any])?.compactMap { $0 as? String } ?? []
        }
        for artifact in artifacts {
            if artifact["pkg"] != nil { zap.needsPassword = true }
            for stanza in (artifact["zap"] as? [Any]) ?? [] {
                guard let stanza = stanza as? [String: Any] else { continue }
                zap.trash += strings(stanza["trash"])
                zap.delete += strings(stanza["delete"]) + strings(stanza["rmdir"])
                zap.other += strings(stanza["launchctl"]).map { "Stop background job \($0)" }
                    + strings(stanza["pkgutil"]).map { "Forget installer record \($0)" }
                    + strings(stanza["quit"]).map { "Quit \($0)" }
                if stanza["pkgutil"] != nil || stanza["script"] != nil || stanza["launchctl"] != nil { zap.needsPassword = true }
                if stanza["script"] != nil { zap.other.append("Run the cask's own cleanup script") }
            }
        }
        if (zap.trash + zap.delete).contains(where: { !$0.hasPrefix("~") }) { zap.needsPassword = true }
        return zap
    }
}
