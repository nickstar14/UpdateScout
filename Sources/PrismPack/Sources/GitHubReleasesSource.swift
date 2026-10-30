import AppKit

/// Apps updated from their GitHub releases (build guide Phase 9 item 2,
/// moved into Phase 7 by Nick on 30 Oct 2026). The user links an installed
/// app to its repository; PrismPack compares the latest full release with the
/// installed version, downloads the macOS asset, and replaces the app only
/// when the download is signed by the same developer (Team ID) as the copy
/// already installed.
struct GitHubApp: Codable, Hashable, Identifiable {
    /// "owner/name".
    var repo: String
    var appPath: String
    var bundleID: String
    /// The installed copy's Team ID when it was linked. Every download must match.
    var teamID: String
    var id: String { appPath }
    var name: String { ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension }
}

/// The linked apps, kept in github_sources.json beside custom_sources.json.
enum GitHubApps {
    static var configURL: URL { Store.supportDirectory.appendingPathComponent("github_sources.json") }

    static func load() -> [GitHubApp] {
        guard let data = FileManager.default.contents(atPath: configURL.path) else { return [] }
        return (try? JSONDecoder().decode([GitHubApp].self, from: data)) ?? []
    }

    static func save(_ apps: [GitHubApp]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(apps) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
}

struct GitHubReleasesSource: UpdateSource {
    let id = "github"
    let displayName = "GitHub releases"

    /// A pkg asset runs an installer, which needs the password.
    func needsAdmin(_ item: UpdateItem) -> Bool {
        GitHubAPI.cachedRelease(item.installToken).flatMap(GitHubAPI.pickAsset)?.kind == .pkg
    }

    func detect() async throws -> [UpdateItem] {
        let apps = GitHubApps.load()
        guard !apps.isEmpty else { return [] }
        var items: [UpdateItem] = []
        var failures: [String] = []
        for app in apps {
            guard let facts = Adoption.facts(at: app.appPath) else { continue }
            do {
                guard let release = try await GitHubAPI.latestRelease(app.repo),
                      isNewerVersion(release.version, than: facts.version),
                      GitHubAPI.pickAsset(release) != nil else { continue }
                items.append(UpdateItem(sourceID: id, name: app.name, installedVersion: facts.version,
                                        latestVersion: release.version, url: release.htmlURL,
                                        caveat: "From github.com/\(app.repo). Installed only if it's signed by the same developer as your copy.",
                                        installToken: app.repo, releaseNotes: release.notes,
                                        releaseNotesURL: release.htmlURL, appPath: app.appPath))
            } catch {
                failures.append("\(app.name): \(error.localizedDescription)")
            }
        }
        // One failing repository shouldn't hide the others' updates.
        if items.isEmpty, !failures.isEmpty {
            throw PrismPackError.commandFailed("GitHub", output: failures.joined(separator: "\n"))
        }
        return items
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let app = GitHubApps.load().first(where: { $0.repo == item.installToken && $0.appPath == item.appPath }) else {
            throw PrismPackError.parseFailure("GitHub link for \(item.name)")
        }
        guard let release = try await GitHubAPI.latestRelease(app.repo), let asset = GitHubAPI.pickAsset(release) else {
            throw PrismPackError.commandFailed("GitHub", output: "No macOS download in the latest release of \(app.repo).")
        }
        try await GitHubInstaller.install(app, asset: asset, progress: progress)
    }
}

// MARK: - GitHub's API

enum GitHubAPI {
    struct Release: Codable {
        let tag: String
        let notes: String?
        let htmlURL: String
        let assets: [Asset]
        /// The tag without a leading "v" ("v1.0.2" → "1.0.2").
        var version: String { tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag }
    }

    struct Asset: Codable, Hashable {
        enum Kind: String, Codable { case dmg, zip, pkg }
        let name: String
        let url: String
        let size: Int
        var kind: Kind? {
            let lower = name.lowercased()
            if lower.hasSuffix(".dmg") { return .dmg }
            if lower.hasSuffix(".pkg") { return .pkg }
            if lower.hasSuffix(".zip") { return .zip }
            return nil
        }
    }

    enum Failure: LocalizedError {
        case rateLimited(Date?)
        case http(Int)
        var errorDescription: String? {
            switch self {
            case .rateLimited(let reset):
                "GitHub's hourly limit for checks without an account was reached"
                    + (reset.map { "; it resets at \($0.formatted(date: .omitted, time: .shortened))" } ?? "") + "."
            case .http(let code): "GitHub answered with error \(code)."
            }
        }
    }

    /// The download for this Mac: a dmg, zip or pkg, preferring names that say
    /// arm64 or universal, never one that says Intel only.
    static func pickAsset(_ release: Release) -> Asset? {
        let usable = release.assets.filter { asset in
            let lower = asset.name.lowercased()
            return asset.kind != nil && !["x86_64", "x64", "intel", "amd64", "windows", "linux", ".exe"].contains { lower.contains($0) }
        }
        func score(_ asset: Asset) -> Int {
            let lower = asset.name.lowercased()
            var score = 0
            if ["arm64", "aarch64", "apple-silicon", "universal"].contains(where: lower.contains) { score += 10 }
            if lower.contains("mac") || lower.contains("darwin") || lower.contains("osx") { score += 5 }
            score += asset.kind == .dmg ? 3 : asset.kind == .zip ? 2 : 1
            return score
        }
        return usable.max { score($0) < score($1) }
    }

    // A small cache with ETags: answers GitHub says haven't changed (304)
    // don't count against the 60-an-hour limit.
    private struct CacheEntry: Codable { var etag: String?; var release: Release?; var fetched: Date }
    private static let lock = NSLock()
    private static var cacheURL: URL { Store.supportDirectory.appendingPathComponent("github-releases.json") }
    nonisolated(unsafe) private static var memory: [String: CacheEntry]?

    private static func cache() -> [String: CacheEntry] {
        lock.withLock {
            if let memory { return memory }
            let loaded = FileManager.default.contents(atPath: cacheURL.path)
                .flatMap { try? JSONDecoder().decode([String: CacheEntry].self, from: $0) } ?? [:]
            memory = loaded
            return loaded
        }
    }

    private static func store(_ repo: String, _ entry: CacheEntry) {
        lock.withLock {
            var all = memory ?? [:]
            all[repo] = entry
            memory = all
            if let data = try? JSONEncoder().encode(all) { try? data.write(to: cacheURL, options: .atomic) }
        }
    }

    static func cachedRelease(_ repo: String) -> Release? { cache()[repo]?.release }

    /// The latest full release (GitHub's /releases/latest skips drafts and
    /// prereleases). nil when the project publishes no releases.
    static func latestRelease(_ repo: String) async throws -> Release? {
        guard repo.wholeMatch(of: #/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+/#) != nil,
              let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw PrismPackError.parseFailure("repository \(repo)")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let cached = cache()[repo]
        if let etag = cached?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await Net.fetch(request)
        guard let http = response as? HTTPURLResponse else { throw Failure.http(0) }
        switch http.statusCode {
        case 304:
            store(repo, CacheEntry(etag: cached?.etag, release: cached?.release, fetched: Date()))
            return cached?.release
        case 404:
            store(repo, CacheEntry(etag: nil, release: nil, fetched: Date()))
            return nil
        case 403, 429:
            let reset = (http.value(forHTTPHeaderField: "X-RateLimit-Reset")).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
            if let release = cached?.release { return release }
            throw Failure.rateLimited(reset)
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { throw PrismPackError.parseFailure("GitHub release") }
            let assets = (json["assets"] as? [[String: Any]] ?? []).compactMap { a -> Asset? in
                guard let name = a["name"] as? String, let url = a["browser_download_url"] as? String else { return nil }
                return Asset(name: name, url: url, size: a["size"] as? Int ?? 0)
            }
            let release = Release(tag: tag, notes: json["body"] as? String,
                                  htmlURL: json["html_url"] as? String ?? "https://github.com/\(repo)/releases",
                                  assets: assets)
            store(repo, CacheEntry(etag: http.value(forHTTPHeaderField: "ETag"), release: release, fetched: Date()))
            return release
        default:
            throw Failure.http(http.statusCode)
        }
    }

    /// Repositories whose name matches an app's, best first (for "Find it").
    static func search(_ appName: String) async throws -> [String] {
        var parts = URLComponents(string: "https://api.github.com/search/repositories")!
        parts.queryItems = [URLQueryItem(name: "q", value: "\(appName) in:name"),
                            URLQueryItem(name: "per_page", value: "6")]
        let (data, response) = try await Net.fetch(parts.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { throw Failure.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        return items.compactMap { $0["full_name"] as? String }
    }
}

// MARK: - Downloading and replacing

enum GitHubInstaller {
    /// The asset's app, unpacked into a temporary folder, with its facts.
    struct Unpacked {
        let folder: URL
        let appURL: URL?
        let pkgURL: URL?
    }

    /// Downloads and unpacks an asset. Caller removes `folder`.
    static func fetch(_ asset: GitHubAPI.Asset, bundleID: String,
                      progress: @escaping @Sendable (String) -> Void) async throws -> Unpacked {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PrismPack-github-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let url = URL(string: asset.url), url.scheme == "https" else { throw PrismPackError.parseFailure("download link") }
        progress("§step:download")
        progress("Downloading \(asset.name)…")
        var request = URLRequest(url: url)
        request.setValue("PrismPack", forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await URLSession.shared.download(for: request,
                                                                    delegate: DownloadReporter(total: Int64(asset.size), progress: progress))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PrismPackError.commandFailed("Download", output: "GitHub didn't send \(asset.name).")
        }
        let file = folder.appendingPathComponent(asset.name)
        try FileManager.default.moveItem(at: temp, to: file)

        switch asset.kind {
        case .pkg:
            return Unpacked(folder: folder, appURL: nil, pkgURL: file)
        case .zip:
            let out = folder.appendingPathComponent("unzipped")
            let result = try await Shell.run("/usr/bin/ditto", ["-x", "-k", file.path, out.path])
            guard result.status == 0 else { throw PrismPackError.commandFailed("Unzip", output: result.combined) }
            return Unpacked(folder: folder, appURL: findApp(in: out, bundleID: bundleID), pkgURL: nil)
        case .dmg:
            let mount = folder.appendingPathComponent("mount")
            let attach = try await Shell.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen",
                                                                   "-mountpoint", mount.path, file.path])
            guard attach.status == 0 else { throw PrismPackError.commandFailed("Open disk image", output: attach.combined) }
            defer { Task { _ = try? await Shell.run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) } }
            guard let inside = findApp(in: mount, bundleID: bundleID) else {
                return Unpacked(folder: folder, appURL: nil, pkgURL: nil)
            }
            // Copy it out of the image so the image can go.
            let copy = folder.appendingPathComponent(inside.lastPathComponent)
            let ditto = try await Shell.run("/usr/bin/ditto", [inside.path, copy.path])
            guard ditto.status == 0 else { throw PrismPackError.commandFailed("Copy from disk image", output: ditto.combined) }
            return Unpacked(folder: folder, appURL: copy, pkgURL: nil)
        case nil:
            throw PrismPackError.parseFailure("asset \(asset.name)")
        }
    }

    /// The .app with this bundle id, at the top of a folder or one level down.
    private static func findApp(in folder: URL, bundleID: String) -> URL? {
        let fm = FileManager.default
        var candidates: [URL] = []
        for entry in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            if entry.pathExtension == "app" { candidates.append(entry) }
            else { candidates += ((try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "app" } }
        }
        return candidates.first { Adoption.facts(at: $0.path)?.bundleID == bundleID }
    }

    /// The Team ID a pkg is signed with (`pkgutil --check-signature`).
    static func pkgTeamID(_ pkg: URL) async -> String? {
        guard let result = try? await Shell.run("/usr/sbin/pkgutil", ["--check-signature", pkg.path]),
              result.status == 0,
              let match = result.stdout.firstMatch(of: #/Developer ID Installer: .*\(([A-Z0-9]{10})\)/#) else { return nil }
        return String(match.1)
    }

    static func install(_ app: GitHubApp, asset: GitHubAPI.Asset,
                        progress: @escaping @Sendable (String) -> Void) async throws {
        let unpacked = try await fetch(asset, bundleID: app.bundleID, progress: progress)
        defer { try? FileManager.default.removeItem(at: unpacked.folder) }

        progress("§step:check")
        if let pkg = unpacked.pkgURL {
            progress("Checking the installer's signature…")
            guard await pkgTeamID(pkg) == app.teamID else {
                throw refused("The installer isn't signed by the same developer as your copy, so it wasn't run.")
            }
            progress("§step:swap")
            let result = try await Shell.runPrivileged("/usr/sbin/installer -pkg '\(pkg.path.replacingOccurrences(of: "'", with: "'\\''"))' -target /",
                                                       reason: "\(AppIdentity.name) is installing an update for \(app.name).",
                                                       tag: Shell.installTag, lineHandler: progress)
            guard result.status == 0 else { throw PrismPackError.commandFailed("installer", output: result.combined) }
            return
        }

        guard let new = unpacked.appURL else {
            throw refused("The download has no copy of \(app.name) (\(app.bundleID)).")
        }
        progress("Checking the signature…")
        guard CodeSign.isValid(new.path) else { throw refused("The downloaded app's signature is broken.") }
        guard CodeSign.teamID(new.path) == app.teamID, CodeSign.teamID(app.appPath) == app.teamID else {
            throw refused("The downloaded app isn't signed by the same developer as your copy.")
        }
        progress("§step:swap")
        try await swap(app, with: new, progress: progress)
    }

    /// Quit, old copy to the Trash, new copy in, relaunch if it was open.
    private static func swap(_ app: GitHubApp, with new: URL, progress: @escaping @Sendable (String) -> Void) async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        if !running.isEmpty {
            progress("Quitting \(app.name)…")
            running.forEach { $0.terminate() }
            for _ in 0..<20 where !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty {
                try await Task.sleep(for: .milliseconds(500))
            }
            guard NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty else {
                throw PrismPackError.commandFailed("Update", output: "\(app.name) didn't quit. Quit it, then try again.")
            }
        }
        progress("Replacing \(app.name)…")
        let target = URL(fileURLWithPath: app.appPath)
        let trashed = try await Adopter.trash(app.appPath, name: app.name)
        do {
            try FileManager.default.moveItem(at: new, to: target)
        } catch {
            _ = await Adopter.restore(trashed, to: app.appPath)
            throw PrismPackError.commandFailed("Update", output: "Couldn't put the new \(app.name) in place (\(error.localizedDescription)). Your copy is back.")
        }
        if !running.isEmpty {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            _ = try? await NSWorkspace.shared.openApplication(at: target, configuration: config)
        }
    }

    private static func refused(_ message: String) -> Error { PrismPackError.commandFailed("Update refused", output: message) }

    /// Linking: the latest release's app must be signed by the installed
    /// copy's developer. Returns that Team ID, or throws why not.
    static func verifyLink(repo: String, appPath: String) async throws -> GitHubApp {
        guard let facts = Adoption.facts(at: appPath) else { throw refused("\(appPath) isn't an app.") }
        guard let team = CodeSign.teamID(appPath) else {
            throw refused("\(facts.name) isn't signed by a developer, so \(AppIdentity.name) can't check that an update comes from the same place.")
        }
        guard let release = try await GitHubAPI.latestRelease(repo) else {
            throw refused("\(repo) publishes no releases.")
        }
        guard let asset = GitHubAPI.pickAsset(release) else {
            throw refused("\(repo)'s latest release (\(release.tag)) has no macOS download.")
        }
        let unpacked = try await fetch(asset, bundleID: facts.bundleID) { _ in }
        defer { try? FileManager.default.removeItem(at: unpacked.folder) }
        let theirs: String?
        if let pkg = unpacked.pkgURL { theirs = await pkgTeamID(pkg) }
        else if let new = unpacked.appURL { theirs = CodeSign.teamID(new.path) }
        else { throw refused("\(repo)'s download doesn't contain \(facts.name).") }
        guard theirs == team else {
            throw refused("\(repo)'s download is signed by a different developer than your copy of \(facts.name).")
        }
        return GitHubApp(repo: repo, appPath: appPath, bundleID: facts.bundleID, teamID: team)
    }
}

/// Reports a download's bytes as `§download:` lines for MoveProgress.
private final class DownloadReporter: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let total: Int64
    let progress: @Sendable (String) -> Void
    private var lastReport = Date.distantPast

    init(total: Int64, progress: @escaping @Sendable (String) -> Void) {
        self.total = total
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard Date().timeIntervalSince(lastReport) > 0.3 else { return }
        lastReport = Date()
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : total
        progress("§download:\(totalBytesWritten)/\(expected)")
    }

    // The async download API hands the file back itself.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
