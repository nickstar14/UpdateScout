import Foundation

/// User-editable fallback: ~/Library/Application Support/UpdateScout/custom_sources.json
/// Each entry defines where to read the installed version, where to fetch the
/// latest version, and either a shell command to update or a download page to open.
struct CustomSource: UpdateSource {
    let id = "custom"
    let displayName = "Custom sources"

    struct Entry: Codable {
        var name: String
        /// Skip this entry without error if the app isn't installed.
        var enabled: Bool? = true
        /// Path to a plist to read the installed version from...
        var installedPlist: String?
        var installedPlistKey: String? // default CFBundleShortVersionString
        /// ...or a shell command whose stdout is the installed version.
        var installedCommand: String?
        /// Where to learn the latest version.
        var remoteURL: String
        /// Either a regex with one capture group over the response body...
        var remoteRegex: String?
        /// ...or a dot-separated JSON key path (e.g. "version" or "release.tag").
        var remoteJSONPath: String?
        /// Update action: a shell command (runs via /bin/sh -c)...
        var installCommand: String?
        /// ...or (as the baseline) a download page for the button to open.
        var downloadPage: String?
        var notes: String?
    }

    static var configURL: URL {
        Store.supportDirectory.appendingPathComponent("custom_sources.json")
    }

    /// Written on first run so there's a working example to edit.
    static func seedIfMissing() {
        let url = configURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let seed: [Entry] = [
            Entry(name: "DisplayLink Manager",
                  installedPlist: "/Applications/DisplayLink Manager.app/Contents/Info.plist",
                  remoteURL: "https://formulae.brew.sh/api/cask/displaylink.json",
                  remoteJSONPath: "version",
                  installCommand: "brew install --cask displaylink --force",
                  downloadPage: "https://www.synaptics.com/products/displaylink-graphics/downloads/macos",
                  notes: "Covered by the cask oracle too; kept here as the reference example.")
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(seed) { try? data.write(to: url) }
    }

    func detect() async throws -> [UpdateItem] {
        Self.seedIfMissing()
        guard let data = FileManager.default.contents(atPath: Self.configURL.path) else { return [] }
        let entries: [Entry]
        do { entries = try JSONDecoder().decode([Entry].self, from: data) }
        catch { throw UpdateScoutError.parseFailure("custom_sources.json (\(error.localizedDescription))") }

        var items: [UpdateItem] = []
        for (index, entry) in entries.enumerated() where entry.enabled ?? true {
            guard let installed = await installedVersion(of: entry) else { continue }
            guard let latest = await remoteVersion(of: entry) else { continue }
            if isNewerVersion(latest, than: installed) {
                let scripted = entry.installCommand != nil
                items.append(UpdateItem(sourceID: id, name: entry.name,
                                        installedVersion: installed, latestVersion: latest,
                                        url: entry.downloadPage ?? entry.remoteURL,
                                        caveat: scripted ? entry.notes : "Opens the vendor download page.",
                                        installToken: String(index),
                                        scriptedInstall: scripted))
            }
        }
        return items
    }

    private func installedVersion(of entry: Entry) async -> String? {
        if let plistPath = entry.installedPlist {
            guard let data = FileManager.default.contents(atPath: plistPath),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { return nil }
            return plist[entry.installedPlistKey ?? "CFBundleShortVersionString"] as? String
        }
        if let cmd = entry.installedCommand {
            let result = try? await Shell.run("/bin/sh", ["-c", cmd])
            let out = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return (out?.isEmpty == false) ? out : nil
        }
        return nil
    }

    private func remoteVersion(of entry: Entry) async -> String? {
        guard let url = URL(string: entry.remoteURL),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }

        if let path = entry.remoteJSONPath {
            var node = try? JSONSerialization.jsonObject(with: data)
            for key in path.split(separator: ".") {
                node = (node as? [String: Any])?[String(key)]
            }
            if let s = node as? String { return s }
            if let n = node as? NSNumber { return n.stringValue }
            return nil
        }
        if let pattern = entry.remoteRegex, let body = String(data: data, encoding: .utf8) {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: body)
            else { return nil }
            return String(body[range])
        }
        return nil
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let data = FileManager.default.contents(atPath: Self.configURL.path),
              let entries = try? JSONDecoder().decode([Entry].self, from: data),
              let index = Int(item.installToken), entries.indices.contains(index),
              let cmd = entries[index].installCommand
        else { throw UpdateScoutError.parseFailure("custom_sources.json entry for \(item.name)") }

        let result = try await Shell.run("/bin/sh", ["-c", cmd], tag: "install", lineHandler: progress)
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed(cmd, output: result.combined)
        }
    }
}
