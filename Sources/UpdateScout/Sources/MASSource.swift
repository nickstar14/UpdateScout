import Foundation
import AppKit

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
        // Lines look like: 497799835  Xcode (14.2 -> 14.3). mas right-aligns
        // the id column, so shorter ids arrive with leading spaces.
        let pattern = #/^\s*(\d+)\s+(.+?)\s+\(([^)]*?)\s*->\s*([^)]*)\)\s*$/#
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
        // mas can't see iPhone/iPad apps running on Apple silicon at all, so
        // check those against Apple's catalogue separately.
        let known = Set(items.map(\.installToken))
        items += await Self.iosAppsOutdated(excluding: known)

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

    /// iPhone/iPad apps running on this Mac. They ship as a wrapper bundle
    /// whose iTunesMetadata.plist carries the store id and the *iOS* version —
    /// the same number the catalogue reports, so the comparison is sound.
    ///
    /// Mac App Store apps deliberately aren't cross-checked this way: Apple's
    /// lookup API exposes one `version` per store id, and for an app published
    /// universally (Canva, the iWork apps) that's the iOS version, which has
    /// nothing to do with the installed Mac build's numbering. Comparing them
    /// invents updates that don't exist, so Mac apps rely on `mas outdated`.
    private static func iosAppsOutdated(excluding known: Set<String>) async -> [UpdateItem] {
        struct Wrapped { let id: String; let name: String; let version: String; let path: String }
        var apps: [Wrapped] = []
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where entry.hasSuffix(".app") {
                let path = "\(dir)/\(entry)"
                guard let data = FileManager.default.contents(atPath: path + "/Wrapper/iTunesMetadata.plist"),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let version = plist["bundleShortVersionString"] as? String else { continue }
                let id = (plist["itemId"] as? NSNumber)?.stringValue ?? (plist["itemId"] as? String) ?? ""
                guard !id.isEmpty, !known.contains(id) else { continue }
                // Use the store's name so it matches what the App Store shows
                // ("Vocal Remover", not the bundle's "Musiclab"), minus the
                // marketing tagline ("Shop: All your favorite brands" → "Shop").
                let bundleName = (entry as NSString).deletingPathExtension
                let storeName = (plist["itemName"] as? String)?
                    .components(separatedBy: ":").first?
                    .components(separatedBy: " - ").first?
                    .trimmingCharacters(in: .whitespaces)
                let name = (storeName?.isEmpty == false ? storeName! : bundleName)
                apps.append(Wrapped(id: id, name: name, version: version, path: path))
            }
        }
        guard !apps.isEmpty else { return [] }

        let storefront = Locale.current.region?.identifier.lowercased() ?? "us"
        let ids = apps.map(\.id).joined(separator: ",")
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(ids)&country=\(storefront)"),
              let (data, _) = try? await Net.fetch(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        var storeVersions: [String: String] = [:]
        for r in results {
            if let id = r["trackId"] as? Int, let v = r["version"] as? String { storeVersions[String(id)] = v }
        }

        return apps.compactMap { app in
            guard let store = storeVersions[app.id], isNewerVersion(store, than: app.version) else { return nil }
            return UpdateItem(sourceID: "mas", name: app.name,
                              installedVersion: app.version, latestVersion: store,
                              url: "macappstore://showUpdatesPage",
                              caveat: "iPhone or iPad app running on your Mac. These can only be updated in the App Store — the button opens its Updates page.",
                              installToken: app.id,
                              scriptedInstall: false,
                              appPath: app.path,
                              isIOSApp: true)
        }
    }

    /// The wrapper bundle for an iOS app, by store id.
    private static func wrapperApp(id: String) -> String? {
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for entry in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where entry.hasSuffix(".app") {
                let path = "\(dir)/\(entry)"
                guard let data = FileManager.default.contents(atPath: path + "/Wrapper/iTunesMetadata.plist"),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                else { continue }
                let found = (plist["itemId"] as? NSNumber)?.stringValue ?? (plist["itemId"] as? String)
                if found == id { return path }
            }
        }
        return nil
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
        if result.status == 0 && !sudoBlocked {
            // mas can "succeed" without doing anything when its cached update
            // list doesn't include the app yet (catalogue-detected items). If
            // the installed version is unchanged, send the user to the App
            // Store's Updates page, which does have it.
            if let path = item.appPath,
               let data = FileManager.default.contents(atPath: path + "/Contents/Info.plist"),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let now = plist["CFBundleShortVersionString"] as? String,
               now == item.installedVersion {
                progress("mas hasn't caught up — opening the App Store's Updates page…")
                await MainActor.run {
                    NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!)
                }
                throw UpdateScoutError.commandFailed(
                    "mas upgrade \(item.installToken)",
                    output: "mas doesn't see this update yet. Finish it in the App Store window that just opened, then Check Now.")
            }
            return
        }
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
