import Foundation

struct MASSource: UpdateSource {
    let id = "mas"
    let displayName = "Mac App Store"

    func detect() async throws -> [UpdateItem] {
        guard let mas = Shell.which("mas") else {
            throw UpdateScoutError.toolMissing("mas-cli", hint: "Run `brew install mas` to enable App Store checks.")
        }
        let result = try await Shell.run(mas, ["outdated"])
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed("mas outdated", output: result.combined)
        }
        // Lines look like: 497799835  Xcode (14.2 -> 14.3)
        let pattern = #/^(\d+)\s+(.+?)\s+\(([^)]*?)\s*->\s*([^)]*)\)\s*$/#
        var items: [UpdateItem] = []
        for line in result.stdout.split(separator: "\n") {
            guard let m = line.firstMatch(of: pattern) else { continue }
            items.append(UpdateItem(sourceID: id,
                                    name: String(m.2),
                                    installedVersion: String(m.3),
                                    latestVersion: String(m.4),
                                    url: "macappstore://showUpdatesPage",
                                    installToken: String(m.1),
                                    appPath: AppLocator.find(named: String(m.2))))
        }
        // Enrich with "What's New" from Apple's public lookup API, concurrently.
        // Best effort: a lookup failure just leaves the notes empty.
        return await withTaskGroup(of: UpdateItem.self) { group in
            for item in items {
                group.addTask { await Self.withReleaseNotes(item) }
            }
            var enriched: [UpdateItem] = []
            for await item in group { enriched.append(item) }
            return enriched.sorted { $0.name < $1.name }
        }
    }

    private static func withReleaseNotes(_ item: UpdateItem) async -> UpdateItem {
        let storefront = Locale.current.region?.identifier.lowercased() ?? "us"
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(item.installToken)&country=\(storefront)"),
              let (data, _) = try? await Net.fetch(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let app = (json["results"] as? [[String: Any]])?.first
        else { return item }
        var copy = item
        copy.releaseNotes = app["releaseNotes"] as? String
        copy.releaseNotesURL = app["trackViewUrl"] as? String
        return copy
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let mas = Shell.which("mas") else {
            throw UpdateScoutError.toolMissing("mas-cli", hint: "Run `brew install mas`.")
        }
        let result = try await Shell.run(mas, ["upgrade", item.installToken], tag: "install", lineHandler: progress)
        let sudoBlocked = result.combined.contains("sudo: a terminal is required")
        if result.status == 0 && !sudoBlocked { return }
        // The row can be stale (app already updated, e.g. by the App Store
        // itself) — mas then reports the ADAM ID as not installed. Not an error.
        if result.combined.contains("No installed apps with ADAM ID") { return }

        if sudoBlocked {
            // mas 7 shells out to a hard-coded /usr/bin/sudo without -A, which
            // cannot prompt from a GUI app (no terminal, askpass ignored).
            // Re-run under real sudo instead — it sets SUDO_UID/SUDO_USER
            // properly so mas still operates on this user's account.
            progress("Authorizing — enter your password, then the install runs…")

            // mas prints almost nothing while a multi-gigabyte app downloads, so
            // drive a heartbeat that shows elapsed time. It stands down whenever
            // mas does emit something real.
            let tracker = ProgressTracker()
            let heartbeat = Task {
                let start = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3))
                    if Task.isCancelled { break }
                    guard tracker.quietFor(seconds: 3) else { continue }
                    let secs = Int(Date().timeIntervalSince(start))
                    progress("Installing… \(secs / 60)m \(secs % 60)s (large apps take a while)")
                }
            }
            defer { heartbeat.cancel() }

            let priv = try await Shell.runPrivileged(
                "'\(mas)' upgrade \(item.installToken)", tag: "install") { line in
                    let text = line.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    tracker.noteOutput()
                    progress(text)
                }
            if priv.combined.contains("No installed apps with ADAM ID") { return }
            guard priv.status == 0 else {
                throw UpdateScoutError.commandFailed("mas upgrade \(item.installToken) (admin)", output: priv.combined)
            }
            return
        }
        throw UpdateScoutError.commandFailed("mas upgrade \(item.installToken)", output: result.combined)
    }
}

/// Tracks when a subprocess last printed something, so a heartbeat can fill
/// long silences without stomping on real output.
final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast

    func noteOutput() {
        lock.lock(); last = Date(); lock.unlock()
    }

    func quietFor(seconds: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(last) >= seconds
    }
}
