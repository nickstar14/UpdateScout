import Foundation

struct SystemUpdateSource: UpdateSource {
    let id = "macos"
    let displayName = "macOS"

    func detect() async throws -> [UpdateItem] {
        // softwareupdate has no JSON output; parse the classic text format:
        //   * Label: macOS Tahoe 27.1-26B123
        //       Title: macOS Tahoe 27.1, Version: 27.1, Size: ..., Recommended: YES, Action: restart,
        let result = try await Shell.run("/usr/sbin/softwareupdate", ["-l", "--no-scan"])
        // A full scan is slow; try the cached list first, fall back to a scan if empty.
        var text = result.combined
        if !text.contains("* Label:") && !text.contains("No new software available") {
            let scanned = try await Shell.run("/usr/sbin/softwareupdate", ["-l"])
            text = scanned.combined
        }
        if text.contains("No new software available") { return [] }

        var items: [UpdateItem] = []
        var currentLabel: String? = nil
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("* Label:") {
                currentLabel = line.replacingOccurrences(of: "* Label:", with: "").trimmingCharacters(in: .whitespaces)
            } else if let label = currentLabel, line.hasPrefix("Title:") {
                var title = label, version = "", restart = false
                for field in line.split(separator: ",") {
                    let kv = field.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard kv.count == 2 else { continue }
                    switch kv[0] {
                    case "Title": title = kv[1]
                    case "Version": version = kv[1]
                    case "Action": restart = kv[1].lowercased().contains("restart")
                    default: break
                    }
                }
                items.append(UpdateItem(sourceID: id, name: title,
                                        installedVersion: "installed",
                                        latestVersion: version.isEmpty ? label : version,
                                        url: nil,
                                        caveat: restart ? "Requires a restart to finish installing." : "Requires an administrator password.",
                                        installToken: label))
                currentLabel = nil
            }
        }
        return items
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        progress("Authorizing — enter your password, then the install runs…")
        // Quote the label for the embedded shell; labels come from softwareupdate itself.
        let quoted = "'" + item.installToken.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let result = try await Shell.runPrivileged("/usr/sbin/softwareupdate -i \(quoted)", tag: "install")
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed("softwareupdate -i \(item.installToken)", output: result.combined)
        }
    }
}
