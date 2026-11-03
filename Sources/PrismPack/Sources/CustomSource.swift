import Foundation
import CryptoKit

/// User-editable fallback: ~/Library/Application Support/PrismPack/custom_sources.json
/// Each entry defines where to read the installed version, where to fetch the
/// latest version, and either a shell command to update or a download page to open.
struct CustomSource: UpdateSource {
    let id = "custom"
    let displayName = "Custom sources"

    /// Custom commands are opaque: they can't be marked ahead of time. If one
    /// calls sudo, the batch password (or the usual dialog) answers it.
    func needsAdmin(_ item: UpdateItem) -> Bool { false }

    struct Entry: Codable, Equatable {
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

    /// Entries as written in custom_sources.json; nil if the file is missing
    /// or can't be read.
    static func entries() -> [Entry]? {
        guard let data = FileManager.default.contents(atPath: configURL.path) else { return nil }
        return try? JSONDecoder().decode([Entry].self, from: data)
    }

    /// Entries allowed to run their commands in the headless background check.
    /// The first time 2.0 looks, every entry already in the file is allowed
    /// (1.8.0 ran them all); entries added after that start off.
    static var backgroundNames: Set<String> {
        if let names = Prefs.customBackgroundNames { return names }
        let names = Set((entries() ?? []).map(\.name))
        Prefs.customBackgroundNames = names
        return names
    }

    func detect() async throws -> [UpdateItem] {
        let allowed = Self.backgroundNames   // before the seed, so a fresh seed starts off
        Self.seedIfMissing()
        guard let data = FileManager.default.contents(atPath: Self.configURL.path) else { return [] }
        let entries: [Entry]
        do { entries = try JSONDecoder().decode([Entry].self, from: data) }
        catch { throw PrismPackError.parseFailure("custom_sources.json (\(error.localizedDescription))") }

        // Headless, an entry that isn't allowed keeps its last result instead
        // of running: dropping its row would also drop its hidden version.
        let headless = CommandLine.arguments.contains("--background-check")
        let previous = headless ? Store.load().items.filter { $0.sourceID == id } : []
        var items: [UpdateItem] = []
        for entry in entries where entry.enabled ?? true {
            if headless && !allowed.contains(entry.name) {
                let token = Self.token(for: entry)
                items += previous.filter { $0.installToken == token }
                continue
            }
            guard let installed = await installedVersion(of: entry) else { continue }
            guard let latest = await remoteVersion(of: entry) else { continue }
            if isNewerVersion(latest, than: installed) {
                let scripted = entry.installCommand != nil
                items.append(UpdateItem(sourceID: id, name: entry.name,
                                        installedVersion: installed, latestVersion: latest,
                                        url: entry.downloadPage ?? entry.remoteURL,
                                        caveat: scripted ? entry.notes : "Opens the vendor download page.",
                                        installToken: Self.token(for: entry),
                                        scriptedInstall: scripted,
                                        appPath: entry.installedPlist.flatMap { plist in
                                            let r = plist.range(of: "/Contents/Info.plist")
                                            return r.map { String(plist[..<$0.lowerBound]) }
                                        }))
            }
        }
        return items
    }

    func installedVersion(of entry: Entry) async -> String? {
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

    func remoteVersion(of entry: Entry) async -> String? {
        guard let url = URL(string: entry.remoteURL),
              let (data, response) = try? await Net.fetch(url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return Self.parseRemote(data, entry)
    }

    static func parseRemote(_ data: Data, _ entry: Entry) -> String? {
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

    // MARK: - Adding and removing entries (Settings' Add a Source sheet)

    /// How to read the version from a page, when the user didn't say: a
    /// well-known JSON key, else the first version-like number.
    static func guessRemote(_ data: Data) -> (jsonPath: String?, regex: String?) {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = ["version", "tag_name", "latest_version", "latest", "name"]
            for key in keys where json[key] is String || json[key] is NSNumber { return (key, nil) }
            for (outer, value) in json.sorted(by: { $0.key < $1.key }) {
                if let inner = value as? [String: Any] {
                    for key in keys where inner[key] is String || inner[key] is NSNumber { return ("\(outer).\(key)", nil) }
                }
            }
        }
        return (nil, #"(\d+(?:\.\d+)+)"#)
    }

    /// Adds an entry to the file, keeping everything already in it (hand
    /// edits included). Throws if the name is taken or the file can't be
    /// read. New entries start off for the background check.
    static func add(_ entry: Entry, to url: URL = configURL) throws {
        var all: [Entry] = []
        if let data = FileManager.default.contents(atPath: url.path) {
            all = try JSONDecoder().decode([Entry].self, from: data)
        }
        guard !all.contains(where: { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }) else {
            throw PrismPackError.parseFailure("a source named \(entry.name) already exists")
        }
        if url == configURL { _ = backgroundNames }   // first look: existing entries stay allowed, this one doesn't
        all.append(entry)
        try write(all, to: url)
    }

    /// Removes the entry with this name, and its background switch.
    static func remove(named name: String, from url: URL = configURL) throws {
        guard let data = FileManager.default.contents(atPath: url.path) else { return }
        var all = try JSONDecoder().decode([Entry].self, from: data)
        all.removeAll { $0.name == name }
        try write(all, to: url)
        if url == configURL, var names = Prefs.customBackgroundNames {
            names.remove(name)
            Prefs.customBackgroundNames = names
        }
    }

    private static func write(_ entries: [Entry], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(entries).write(to: url, options: .atomic)
    }

    /// Identifies an entry by name plus a fingerprint of its install command.
    /// A position in the array would point at a different entry if the file
    /// were edited between the check and the install, and run its command.
    static func token(for entry: Entry) -> String {
        let digest = SHA256.hash(data: Data((entry.installCommand ?? "").utf8))
        return entry.name + "|" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let data = FileManager.default.contents(atPath: Self.configURL.path),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { throw PrismPackError.parseFailure("custom_sources.json") }
        guard let entry = entries.first(where: { Self.token(for: $0) == item.installToken }),
              let cmd = entry.installCommand
        else {
            throw PrismPackError.commandFailed(
                item.name, output: "This entry changed in custom_sources.json since the last check. Check Now, then try again.")
        }

        let result = try await Shell.run("/bin/sh", ["-c", cmd], tag: Shell.installTag, lineHandler: progress)
        guard result.status == 0 else {
            throw PrismPackError.commandFailed(cmd, output: result.combined)
        }
    }
}
