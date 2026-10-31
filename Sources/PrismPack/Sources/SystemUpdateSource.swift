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
                let fields = Self.fields(of: line)
                let title = fields["Title"].flatMap { $0.isEmpty ? nil : $0 } ?? label
                let version = fields["Version"] ?? ""
                let restart = fields["Action"]?.lowercased().contains("restart") ?? false
                // macOS installs are handed to System Settings rather than run
                // with `softwareupdate -i`: Settings handles the download,
                // restart scheduling and progress, and is the supported path.
                items.append(UpdateItem(sourceID: id, name: title,
                                        installedVersion: Self.currentOSVersion,
                                        latestVersion: version.isEmpty ? label : version,
                                        url: Self.settingsURL,
                                        caveat: restart
                                            ? "Requires a restart. Opens Software Update in System Settings to install."
                                            : "Opens Software Update in System Settings to install.",
                                        installToken: label,
                                        scriptedInstall: false))
                currentLabel = nil
            }
        }
        return items
    }

    /// Splits a `Title: …, Version: …, Size: …` line. Fields are cut only at
    /// a comma followed by a known key, so a title that itself contains a
    /// comma ("Safari 18.1, for macOS") stays whole.
    static func fields(of line: String) -> [String: String] {
        let keys = ["Title", "Version", "Size", "Recommended", "Action"]
        let pattern = "(?:^|,)\\s*(" + keys.joined(separator: "|") + "):"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
        var result: [String: String] = [:]
        for (i, match) in matches.enumerated() {
            let key = ns.substring(with: match.range(at: 1))
            let start = match.range.location + match.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            var value = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespaces)
            if value.hasSuffix(",") { value = String(value.dropLast()).trimmingCharacters(in: .whitespaces) }
            result[key] = value
        }
        return result
    }

    /// System Settings → General → Software Update.
    static let settingsURL = "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"

    /// The running macOS version, so rows read "27.1 → 27.2" rather than a
    /// placeholder.
    private static var currentOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.patchVersion > 0
            ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "\(v.majorVersion).\(v.minorVersion)"
    }

    /// Never reached: macOS rows aren't scripted (they open System Settings,
    /// which handles the download, restart and progress).
    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        throw PrismPackError.commandFailed(
            "softwareupdate", output: "macOS updates install from Software Update in System Settings.")
    }
}
