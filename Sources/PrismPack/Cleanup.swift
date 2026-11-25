import Foundation

/// A daily tidy-up of installer caches (Nick, 25 Nov 2026: about 6 GB of
/// Homebrew leftovers had piled up in a month). Only caches that the tools
/// rebuild by themselves are cleared: nothing installed is removed, and no
/// old library versions that a project might still use.
///
/// - Homebrew: `brew cleanup --prune=all` (old versions of installed
///   formulae, and every cached download).
/// - pip: `pip cache purge`. npm: `npm cache clean --force`.
///
/// It runs from the background check or, with the app open, a little after
/// launch; at most once a day. It doesn't wait for a manual install (Nick,
/// 25 Nov 2026: overlapping one is fine), only for an automatic run's lock.
enum Cleanup {
    private static let lastRunKey = "dailyCleanupLastRun"
    private static let enabledKey = "dailyCleanup"

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var isDue: Bool {
        guard enabled, !AppIdentity.isFreshProfile else { return false }
        guard let last = UserDefaults.standard.object(forKey: lastRunKey) as? Date else { return true }
        return Date().timeIntervalSince(last) >= 23 * 3600
    }

    /// Runs the cleanup if it is on and due, and logs what it did.
    static func runIfDue() async {
        guard isDue, let lock = AutoUpdate.acquireLock() else { return }
        defer { AutoUpdate.releaseLock(lock) }
        UserDefaults.standard.set(Date(), forKey: lastRunKey)
        var lines: [String] = []
        var failed = false
        for step in steps() {
            do {
                let result = try await Shell.$noPasswordPrompt.withValue(true) {
                    try await Shell.run(step.path, step.args)
                }
                if result.status == 0 {
                    lines.append("\(step.label): \(summary(result.combined, step: step))")
                } else {
                    failed = true
                    lines.append("\(step.label): failed (\(result.combined.split(separator: "\n").last.map(String.init) ?? "no message"))")
                }
            } catch {
                failed = true
                lines.append("\(step.label): \(error.localizedDescription)")
            }
        }
        guard !lines.isEmpty else { return }
        Store.mutate {
            $0.log(ActivityEntry(kind: failed ? .failed : .checked, title: "Daily cleanup",
                                 detail: lines.joined(separator: " \u{00B7} "),
                                 log: lines.joined(separator: "\n")))
        }
    }

    private struct Step { let label: String; let path: String; let args: [String] }

    private static func steps() -> [Step] {
        var list: [Step] = []
        if let brew = HomebrewSource.brewPath { list.append(Step(label: "Homebrew", path: brew, args: ["cleanup", "--prune=all"])) }
        if let pip = Shell.which("pip3") ?? Shell.which("pip") { list.append(Step(label: "pip", path: pip, args: ["cache", "purge"])) }
        if let npm = Shell.which("npm") { list.append(Step(label: "npm", path: npm, args: ["cache", "clean", "--force"])) }
        return list
    }

    /// The freed amount if the tool says one ("freed approximately 1.2GB"),
    /// else a plain "done".
    private static func summary(_ output: String, step: Step) -> String {
        for line in output.split(separator: "\n") where line.contains("freed approximately") {
            return String(line).replacingOccurrences(of: "==> ", with: "")
        }
        for line in output.split(separator: "\n") where line.lowercased().contains("files purged") || line.lowercased().contains("freed") {
            return String(line)
        }
        return "done"
    }
}
