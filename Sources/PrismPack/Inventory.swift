import Foundation

/// One installed thing, for the Installed tab.
struct InstalledPackage: Identifiable, Hashable, Sendable {
    /// The path too: two copies of one app share a name and source.
    var id: String { "\(sourceID)|\(name)|\(appPath ?? "")" }
    let name: String
    let version: String
    /// The section it belongs to ("homebrew", "pip", …), or "unmanaged" for
    /// an app nothing here updates.
    let sourceID: String
    var appPath: String? = nil
    var detail: String? = nil
}

/// Builds the Installed list from what's on disk and each tool's own list.
/// Reads only; nothing here changes anything.
enum Inventory {
    static func load() async -> [InstalledPackage] {
        async let brew = homebrew()
        async let mas = appStore()
        async let python = pythonTools()
        async let npm = npmGlobal()
        async let cargo = rustCrates()
        async let gems = rubyGems()
        async let extensions = editorExtensions()
        let managed = await brew + mas + python + npm + cargo + gems + extensions
        let apps = applications(excluding: managed)
        return (managed + apps).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Formulae and casks from the Cellar and Caskroom folders. Reading the
    /// folders avoids `brew list --cask`, which refuses to run at all while
    /// any untrusted tap is installed.
    private static func homebrew() async -> [InstalledPackage] {
        // What each cask says it installs, for a cask named unlike its app
        // ("flux-app" installs Flux.app; Nick, 2 Nov 2026).
        let caskApps = Dictionary(await Duplicates.caskRecords().map { ($0.token, $0.apps) },
                                  uniquingKeysWith: { a, _ in a })
        let fm = FileManager.default
        var found: [InstalledPackage] = []
        for prefix in ["/opt/homebrew", "/usr/local"] {
            for (folder, isCask) in [("Cellar", false), ("Caskroom", true)] {
                let root = "\(prefix)/\(folder)"
                for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !name.hasPrefix(".") {
                    let versions = ((try? fm.contentsOfDirectory(atPath: "\(root)/\(name)")) ?? [])
                        .filter { !$0.hasPrefix(".") }
                    guard let version = versions.max(by: { compareVersions($0, $1) == .orderedAscending }) else { continue }
                    let tool = !isCask && Tools.isTool(formula: name)
                    // A cask's app, found by token, so it isn't listed twice
                    // and shows its real name and icon.
                    let app = isCask ? (AppLocator.find(named: name)
                        ?? caskApps[name]?.lazy.compactMap { AppLocator.find(named: ($0 as NSString).deletingPathExtension) }.first
                        ?? AppLocator.findUnique(prefix: name)) : nil
                    found.append(InstalledPackage(
                        name: app.map { (fm.displayName(atPath: $0) as NSString).deletingPathExtension } ?? name,
                        version: version, sourceID: tool ? "tools" : "homebrew", appPath: app,
                        detail: isCask ? "cask \(name)" : "formula"))
                }
            }
        }
        return found
    }

    private static func appStore() async -> [InstalledPackage] {
        guard let mas = Shell.which("mas"), let result = try? await Shell.run(mas, ["list"]) else { return [] }
        let pattern = #/^\s*(\d+)\s+(.+?)\s+\(([^)]*)\)\s*$/#
        let receipted = appStoreApps()
        return result.stdout.split(separator: "\n").compactMap { line in
            guard let m = line.firstMatch(of: pattern) else { return nil }
            let name = String(m.2)
            return InstalledPackage(name: name, version: String(m.3), sourceID: "mas",
                                    appPath: AppLocator.find(named: name) ?? masMatch(name, among: receipted))
        }
    }

    /// Apps with an App Store receipt, with the names their bundles give
    /// (CFBundleDisplayName, CFBundleName).
    private static func appStoreApps() -> [(path: String, names: [String])] {
        let fm = FileManager.default
        return AppFolders.appPaths().compactMap { path in
            guard fm.fileExists(atPath: path + "/Contents/_MASReceipt"),
                  let data = fm.contents(atPath: path + "/Contents/Info.plist"),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return nil }
            return (path, ["CFBundleDisplayName", "CFBundleName"].compactMap { plist[$0] as? String })
        }
    }

    /// An Apple app updated with macOS: Apple's bundle id, no App Store receipt.
    static func isMacOSApp(bundleID: String?, hasReceipt: Bool) -> Bool {
        !hasReceipt && (bundleID?.hasPrefix("com.apple.") ?? false)
    }

    /// The receipted app whose bundle calls itself `name`. `mas list` gives
    /// the bundle's name ("Pages") while the app on disk can be named
    /// otherwise ("Pages Creator Studio.app"), which left those apps showing
    /// as Not managed (Nick, 2 Nov 2026). Only a single match counts.
    static func masMatch(_ name: String, among apps: [(path: String, names: [String])]) -> String? {
        let hits = apps.filter { app in
            app.names.contains { $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        }
        return hits.count == 1 ? hits[0].path : nil
    }

    private static func pythonTools() async -> [InstalledPackage] {
        var found: [InstalledPackage] = []
        if let pipx = Shell.which("pipx"), let result = try? await Shell.run(pipx, ["list", "--json"]),
           let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
           let venvs = json["venvs"] as? [String: Any] {
            for case let (name, venv as [String: Any]) in venvs {
                let meta = (venv["metadata"] as? [String: Any])?["main_package"] as? [String: Any]
                found.append(InstalledPackage(name: name, version: meta?["package_version"] as? String ?? "?",
                                              sourceID: "pip", detail: "pipx"))
            }
        }
        if let uv = Shell.which("uv"), let result = try? await Shell.run(uv, ["tool", "list"]) {
            for line in result.stdout.split(separator: "\n") where !line.hasPrefix("-") {
                let parts = line.split(separator: " ")
                guard parts.count >= 2, parts[1].hasPrefix("v") else { continue }
                found.append(InstalledPackage(name: String(parts[0]), version: String(parts[1].dropFirst()),
                                              sourceID: "pip", detail: "uv tool"))
            }
        }
        return found
    }

    private static func npmGlobal() async -> [InstalledPackage] {
        guard let npm = Shell.which("npm"),
              let result = try? await Shell.run(npm, ["ls", "-g", "--depth=0", "--json"]),
              let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let deps = json["dependencies"] as? [String: Any] else { return [] }
        return deps.compactMap { name, value in
            guard let version = (value as? [String: Any])?["version"] as? String else { return nil }
            return InstalledPackage(name: name, version: version, sourceID: "npm",
                                    detail: NPMSource.skipped.contains(name) ? "updated with node" : nil)
        }
    }

    private static func rustCrates() async -> [InstalledPackage] {
        guard let cargo = Shell.which("cargo"), let result = try? await Shell.run(cargo, ["install", "--list"]) else { return [] }
        return CargoSource.parseList(result.stdout).map {
            InstalledPackage(name: $0.name, version: $0.version, sourceID: "cargo")
        }
    }

    /// Homebrew Ruby's gems, without the ones bundled with Ruby itself.
    private static func rubyGems() async -> [InstalledPackage] {
        guard let gem = GemSource.gem, let result = try? await Shell.run(gem, ["list", "--local"]) else { return [] }
        let bundled = GemSource.defaultOnly(result.stdout)
        let pattern = #/^(\S+) \((?:default: )?([^,)\s]+)/#
        return result.stdout.split(separator: "\n").compactMap { line in
            guard let m = line.firstMatch(of: pattern), !bundled.contains(String(m.1)) else { return nil }
            return InstalledPackage(name: String(m.1), version: String(m.2), sourceID: "gem")
        }
    }

    private static func editorExtensions() async -> [InstalledPackage] {
        var found: [InstalledPackage] = []
        for editor in EditorExtensionsSource.editors() {
            for ext in (try? await EditorExtensionsSource.installed(in: editor)) ?? [] {
                // Named as the update rows name them, so the two match up.
                let name = editor.key == "code" ? ext.id : "\(ext.id) (\(editor.name))"
                found.append(InstalledPackage(name: name, version: ext.version, sourceID: "editors",
                                              detail: editor.name))
            }
        }
        return found
    }

    /// Apps in /Applications and ~/Applications. An app with a Sparkle feed
    /// counts as Sparkle; one matched by Homebrew or the App Store above is
    /// left out here; the rest are "Not managed".
    private static func applications(excluding managed: [InstalledPackage]) -> [InstalledPackage] {
        // Lowercased: a path found by name can differ in case from the
        // folder listing on the case-insensitive disk.
        let claimed = Set(managed.compactMap { $0.appPath?.lowercased() })
        let github = Set(GitHubApps.load().map { $0.appPath.lowercased() })
        let fm = FileManager.default
        var found: [InstalledPackage] = []
        for path in AppFolders.appPaths() {
            guard !claimed.contains(path.lowercased()),
                  let data = fm.contents(atPath: "\(path)/Contents/Info.plist"),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let version = plist["CFBundleShortVersionString"] as? String ?? plist["CFBundleVersion"] as? String ?? "?"
            let sparkle = plist["SUFeedURL"] != nil
            // Apple's own apps outside the App Store (Safari and the like)
            // come with macOS and its updates (Nick, 2 Nov 2026).
            let apple = isMacOSApp(bundleID: plist["CFBundleIdentifier"] as? String,
                                   hasReceipt: fm.fileExists(atPath: path + "/Contents/_MASReceipt"))
            let source = github.contains(path.lowercased()) ? "github" : sparkle ? "sparkle" : apple ? "macos" : "unmanaged"
            found.append(InstalledPackage(name: name, version: version, sourceID: source, appPath: path,
                                          detail: apple ? "Updated by macOS" : nil))
        }
        return found
    }
}
