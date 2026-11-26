import Foundation

/// The plain-text report Activity exports, for sending to Nick when something
/// goes wrong. Pure, so tests can feed it entries.
enum ActivityExport {
    /// Your home folder becomes `~`, so the report doesn't carry the user name.
    static func scrub(_ text: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty, home != "/" else { return text }
        return text.replacingOccurrences(of: home, with: "~")
    }

    /// The labelled lines of one entry's dropdown, in order, blank ones left out.
    static func detailLines(_ entry: ActivityEntry) -> [(label: String, value: String)] {
        var lines: [(String, String)] = [
            ("When", entry.date.formatted(date: .complete, time: .standard)),
            ("Kind", entry.kind.title),
        ]
        if let id = entry.sourceID { lines.append(("Source", UpdateController.sourceName(id))) }
        if let from = entry.fromVersion, let to = entry.toVersion {
            lines.append(("Versions", from == to ? "\(from) (the same on both sides)" : "\(from) to \(to)"))
        }
        if let how = entry.how { lines.append(("Started", how)) }
        if let command = entry.command { lines.append(("Command", command)) }
        if let s = entry.seconds { lines.append(("Took", "\(s) s")) }
        if let path = entry.appPath { lines.append(("App", path)) }
        if let after = entry.versionAfter { lines.append(("Version on disk after", after)) }
        if let id = entry.itemID { lines.append(("Item", id)) }
        if let note = entry.note { lines.append(("Note", note)) }
        return lines.filter { !$0.1.isEmpty }
    }

    static func text(entries: [ActivityEntry], updates: [UpdateItem], brewVersion: String?, appVersion: String, now: Date = Date()) -> String {
        var out = [
            "PrismPack activity report",
            "Made: \(now.formatted(date: .complete, time: .standard))",
            "PrismPack: \(appVersion)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Homebrew: \(brewVersion ?? "not found")",
            "",
            "== Updates listed now (\(updates.count)) ==",
        ]
        if updates.isEmpty { out.append("None.") }
        for item in updates {
            out.append("- \(item.name): \(item.installedVersion) to \(item.latestVersion) [\(UpdateController.sourceName(item.sourceID))]")
        }
        out += ["", "== Activity (\(entries.count), newest first) =="]
        for entry in entries.sorted(by: { $0.date > $1.date }) {
            out += ["", "--- \(entry.title) ---"]
            if !entry.detail.isEmpty { out.append("Summary: \(entry.detail)") }
            for (label, value) in detailLines(entry) { out.append("\(label): \(value)") }
            if let log = entry.log, !log.isEmpty {
                out += ["Log:", log.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }.joined(separator: "\n")]
            }
        }
        return scrub(out.joined(separator: "\n") + "\n")
    }
}
