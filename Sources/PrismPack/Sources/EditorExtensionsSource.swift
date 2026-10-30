import Foundation

/// Extensions of VS Code and the editors built on it. Installed versions come
/// from each editor's own command line tool. VS Code's latest versions come
/// from the Visual Studio Marketplace (Open VSX if it doesn't answer);
/// VSCodium's and Cursor's from Open VSX, the registry they use themselves.
struct EditorExtensionsSource: UpdateSource {
    let id = "editors"
    let displayName = "Editor extensions"

    struct Editor: Sendable, Hashable {
        /// Short key used in install tokens: "code", "codium", "cursor".
        let key: String
        let name: String
        let cli: String
        /// The VS Code version it's built on, for extension engine checks.
        let engine: String?
        var usesMarketplace: Bool { key == "code" }
    }

    /// Installed editors, found by their app bundles.
    static func editors() -> [Editor] {
        let known = [("code", "Visual Studio Code", "VS Code", "code"),
                     ("codium", "VSCodium", "VSCodium", "codium"),
                     ("cursor", "Cursor", "Cursor", "cursor")]
        let fm = FileManager.default
        return known.compactMap { key, bundle, name, tool in
            for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
                let app = "\(dir)/\(bundle).app/Contents/Resources/app"
                let cli = "\(app)/bin/\(tool)"
                guard fm.isExecutableFile(atPath: cli) else { continue }
                let product = fm.contents(atPath: "\(app)/product.json")
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let engine = (product?["vsCodeVersion"] ?? product?["version"]) as? String
                return Editor(key: key, name: name, cli: cli, engine: engine)
            }
            return nil
        }
    }

    /// One editor failing (its command broken mid-update, say) doesn't hide
    /// the others' updates; the source only errors when every editor fails.
    func detect() async throws -> [UpdateItem] {
        var items: [UpdateItem] = []
        var failures: [Error] = []
        let editors = Self.editors()
        for editor in editors {
            do { items += try await outdated(in: editor) }
            catch { failures.append(error) }
        }
        if !editors.isEmpty, failures.count == editors.count, let first = failures.first { throw first }
        return items
    }

    static func installed(in editor: Editor) async throws -> [(id: String, version: String)] {
        let result = try await Shell.run(editor.cli, ["--list-extensions", "--show-versions"])
        guard result.status == 0 else {
            throw PrismPackError.commandFailed("\(editor.key) --list-extensions", output: result.combined)
        }
        return parseList(result.stdout)
    }

    /// `esbenp.prettier-vscode@12.4.0`
    static func parseList(_ text: String) -> [(id: String, version: String)] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: "@", maxSplits: 1)
            guard parts.count == 2, parts[0].contains(".") else { return nil }
            return (String(parts[0]), String(parts[1]))
        }
    }

    private func outdated(in editor: Editor) async throws -> [UpdateItem] {
        let installed = try await Self.installed(in: editor)
        guard !installed.isEmpty else { return [] }
        var latest: [String: String] = [:]
        var fellBack = false
        if editor.usesMarketplace {
            do { latest = try await Marketplace.latest(installed.map(\.id), engine: editor.engine) }
            catch { fellBack = true }
        }
        if !editor.usesMarketplace || fellBack {
            latest = await OpenVSX.latest(installed.map(\.id), engine: editor.engine)
        }
        return installed.compactMap { ext in
            guard let newest = latest[ext.id.lowercased()], isNewerVersion(newest, than: ext.version) else { return nil }
            let url = editor.usesMarketplace && !fellBack
                ? "https://marketplace.visualstudio.com/items?itemName=\(ext.id)"
                : "https://open-vsx.org/extension/\(OpenVSX.path(of: ext.id))"
            return UpdateItem(sourceID: id,
                              name: editor.key == "code" ? ext.id : "\(ext.id) (\(editor.name))",
                              installedVersion: ext.version, latestVersion: newest, url: url,
                              caveat: fellBack ? "The VS Code Marketplace didn't answer, so this version comes from Open VSX." : nil,
                              installToken: "\(editor.key):\(ext.id)", scriptedInstall: true)
        }
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        let parts = item.installToken.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw PrismPackError.parseFailure("install token \(item.installToken)") }
        try await Self.install(extension: parts[1], editorKey: parts[0], progress: progress)
    }

    /// `--force` moves an installed extension to the newest version that suits
    /// the editor, so the same command installs (Discover) and updates.
    static func install(extension id: String, editorKey: String,
                        progress: @escaping @Sendable (String) -> Void) async throws {
        guard let editor = editors().first(where: { $0.key == editorKey }) else {
            throw PrismPackError.toolMissing(editorKey, hint: "The editor was removed after the last check.")
        }
        let args = ["--install-extension", id, "--force"]
        let result = try await Shell.run(editor.cli, args, tag: Shell.installTag, lineHandler: progress)
        guard result.status == 0 else {
            throw PrismPackError.commandFailed("\(editor.key) " + args.joined(separator: " "), output: result.combined)
        }
    }

    /// True when an extension's `engines.vscode` range ("^1.90.0", ">=1.80")
    /// allows this editor. Unknown on either side counts as allowed.
    static func engineAllows(_ range: String?, editor: String?) -> Bool {
        guard let range, let editor else { return true }
        // The lower bound only: ">=1.80.0 <2.0.0" → "1.80.0".
        let minimum = range.trimmingCharacters(in: CharacterSet(charactersIn: "^>=~ "))
            .split(separator: " ").first.map(String.init) ?? ""
        guard let first = minimum.first, first.isNumber else { return true }
        return !isNewerVersion(minimum, than: editor)
    }
}

/// The Visual Studio Marketplace's extension query. An undocumented preview
/// API that works without a login; Nick chose to use it (3.4, item 12).
enum Marketplace {
    static let endpoint = URL(string: "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery")!

    struct Hit: Sendable {
        let id: String, name: String, version: String, summary: String?, installs: Int
    }

    /// One request for every id. Returns lowercased id → newest stable version
    /// that suits the editor. Throws when the Marketplace doesn't answer.
    static func latest(_ ids: [String], engine: String?) async throws -> [String: String] {
        let criteria = ids.map { ["filterType": 7, "value": $0] as [String: Any] }
            + [["filterType": 8, "value": "Microsoft.VisualStudio.Code"]]
        let exts = try await query(criteria: criteria, pageSize: ids.count, flags: 0x1 | 0x10 | 0x100)
        var out: [String: String] = [:]
        for ext in exts {
            guard let id = extensionID(ext), let versions = ext["versions"] as? [[String: Any]] else { continue }
            if let version = versions.first(where: { usable($0, engine: engine) })?["version"] as? String {
                out[id.lowercased()] = version
            }
        }
        return out
    }

    /// Search by text, most installed first.
    static func search(_ text: String) async throws -> [Hit] {
        let criteria: [[String: Any]] = [["filterType": 10, "value": text],
                                         ["filterType": 8, "value": "Microsoft.VisualStudio.Code"]]
        let exts = try await query(criteria: criteria, pageSize: 30, flags: 0x100 | 0x200 | 0x1, sortBy: 4)
        return exts.compactMap { ext in
            guard let id = extensionID(ext) else { return nil }
            let installs = (ext["statistics"] as? [[String: Any]])?
                .first { $0["statisticName"] as? String == "install" }?["value"] as? Double ?? 0
            let version = (ext["versions"] as? [[String: Any]])?.first?["version"] as? String ?? ""
            return Hit(id: id, name: ext["displayName"] as? String ?? id, version: version,
                       summary: ext["shortDescription"] as? String, installs: Int(installs))
        }
    }

    private static func query(criteria: [[String: Any]], pageSize: Int, flags: Int,
                              sortBy: Int = 0) async throws -> [[String: Any]] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json;api-version=7.2-preview.1", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["filters": [["criteria": criteria, "pageNumber": 1,
                                                "pageSize": pageSize, "sortBy": sortBy]],
                                   "flags": flags]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        let (data, response) = try await Net.fetch(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw PrismPackError.commandFailed("VS Code Marketplace",
                                                 output: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return results.first?["extensions"] as? [[String: Any]] ?? []
    }

    private static func extensionID(_ ext: [String: Any]) -> String? {
        guard let publisher = (ext["publisher"] as? [String: Any])?["publisherName"] as? String,
              let name = ext["extensionName"] as? String else { return nil }
        return "\(publisher).\(name)"
    }

    /// A stable version for this Mac (no pre-release, right platform) whose
    /// engine range allows the editor.
    private static func usable(_ version: [String: Any], engine: String?) -> Bool {
        if let platform = version["targetPlatform"] as? String, platform != "darwin-arm64", platform != "universal" {
            return false
        }
        let props = (version["properties"] as? [[String: Any]]) ?? []
        func prop(_ key: String) -> String? { props.first { $0["key"] as? String == key }?["value"] as? String }
        if prop("Microsoft.VisualStudio.Code.PreRelease") == "true" { return false }
        return EditorExtensionsSource.engineAllows(prop("Microsoft.VisualStudio.Code.Engine"), editor: engine)
    }
}

/// Open VSX (open-vsx.org): the open registry VSCodium and Cursor use.
enum OpenVSX {
    struct Hit: Sendable {
        let id: String, name: String, version: String, summary: String?, installs: Int
    }

    /// Lowercased id → latest stable version that suits the editor. Best effort:
    /// an extension Open VSX doesn't have is just left out.
    static func latest(_ ids: [String], engine: String?) async -> [String: String] {
        await withTaskGroup(of: (String, String)?.self) { group in
            for id in ids {
                group.addTask {
                    guard let url = URL(string: "https://open-vsx.org/api/\(path(of: id))"),
                          let json = try? await Net.json(url) as? [String: Any],
                          json["preRelease"] as? Bool != true,
                          let version = json["version"] as? String,
                          EditorExtensionsSource.engineAllows((json["engines"] as? [String: Any])?["vscode"] as? String,
                                                             editor: engine)
                    else { return nil }
                    return (id.lowercased(), version)
                }
            }
            var out: [String: String] = [:]
            for await pair in group { if let pair { out[pair.0] = pair.1 } }
            return out
        }
    }

    /// `publisher.name` → `publisher/name`. Only the first dot splits:
    /// extension names may contain dots, publishers don't.
    static func path(of id: String) -> String {
        let parts = id.split(separator: ".", maxSplits: 1)
        return parts.count == 2 ? "\(parts[0])/\(parts[1])" : id
    }

    static func search(_ text: String) async throws -> [Hit] {
        var parts = URLComponents(string: "https://open-vsx.org/api/-/search")!
        parts.queryItems = [URLQueryItem(name: "query", value: text), URLQueryItem(name: "size", value: "30"),
                            URLQueryItem(name: "sortBy", value: "downloadCount")]
        guard let json = try await Net.json(parts.url!) as? [String: Any],
              let exts = json["extensions"] as? [[String: Any]] else {
            throw PrismPackError.parseFailure("Open VSX search")
        }
        return exts.compactMap { ext in
            guard let ns = ext["namespace"] as? String, let name = ext["name"] as? String else { return nil }
            return Hit(id: "\(ns).\(name)", name: ext["displayName"] as? String ?? name,
                       version: ext["version"] as? String ?? "", summary: ext["description"] as? String,
                       installs: ext["downloadCount"] as? Int ?? 0)
        }
    }
}
