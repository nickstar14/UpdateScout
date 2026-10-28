import Foundation

/// Detects Sparkle-based apps (SUFeedURL in Info.plist), fetches their appcast,
/// and compares versions. Updates install in place via SparkleInstaller, which
/// verifies the download against the app's own SUPublicEDKey before replacing
/// anything. Apps whose feed carries no signature stay "Get…" (open the release
/// page) — an unverifiable bundle replacement is never worth it.
struct SparkleSource: UpdateSource {
    let id = "sparkle"
    let displayName = "Sparkle apps"

    /// Sentinel install token meaning "this is UpdateScout itself".
    static let selfUpdateToken = "__self__"

    func detect() async throws -> [UpdateItem] {
        let fm = FileManager.default
        var candidates: [(name: String, path: String, version: String, build: String?, feed: URL)] = []

        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            guard let entries = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                           includingPropertiesForKeys: nil) else { continue }
            for appURL in entries where appURL.pathExtension == "app" {
                let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
                guard let data = fm.contents(atPath: plistURL.path),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let feedString = plist["SUFeedURL"] as? String,
                      let feed = URL(string: feedString), feed.scheme?.hasPrefix("http") == true,
                      let installed = (plist["CFBundleShortVersionString"] ?? plist["CFBundleVersion"]) as? String
                else { continue }
                let name = (appURL.lastPathComponent as NSString).deletingPathExtension
                candidates.append((name, appURL.path, installed, plist["CFBundleVersion"] as? String, feed))
            }
        }

        // Fetch appcasts concurrently; ignore individual feed failures.
        return await withTaskGroup(of: UpdateItem?.self) { group in
            for c in candidates {
                group.addTask {
                    await checkAppcast(name: c.name, appPath: c.path, installed: c.version,
                                       build: c.build, feed: c.feed)
                }
            }
            var items: [UpdateItem] = []
            for await item in group { if let item { items.append(item) } }
            return items
        }
    }

    private func checkAppcast(name: String, appPath: String, installed: String, build: String?,
                              feed: URL) async -> UpdateItem? {
        guard let (data, response) = try? await Net.fetch(feed),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = AppcastParser.latestVersion(from: data, installed: installed, installedBuild: build)
        else { return nil }

        let latestVersion = latest.displayVersion
        guard isNewerVersion(latestVersion, than: installed) else { return nil }

        // We can't swap our own bundle out from under ourselves — UpdateScout
        // has an embedded Sparkle updater built for exactly that, so hand off
        // to it (it shows release notes and relaunches us cleanly).
        if appPath == Bundle.main.bundlePath {
            return UpdateItem(sourceID: id, name: name,
                              installedVersion: installed,
                              latestVersion: latestVersion,
                              url: latest.link ?? feed.absoluteString,
                              caveat: "Opens UpdateScout's own updater.",
                              installToken: Self.selfUpdateToken,
                              scriptedInstall: true,
                              releaseNotes: latest.notes, releaseNotesURL: latest.notesLink,
                              appPath: appPath)
        }

        // Installable in place only when we can verify the download: the app
        // must carry an SUPublicEDKey and the appcast must carry a signature.
        // Otherwise fall back to opening the release page.
        let installable = SparkleInstaller.plan(appPath: appPath, latest: latest) != nil
        return UpdateItem(sourceID: id, name: name,
                          installedVersion: installed,
                          latestVersion: latestVersion,
                          url: latest.link ?? feed.absoluteString,
                          caveat: installable
                            ? "Verified against the app's own signing key before installing; the app quits and relaunches."
                            : "This app's feed isn't signed, so it can't be verified — opens the release page instead.",
                          installToken: installable ? appPath : "",
                          scriptedInstall: installable,
                          releaseNotes: latest.notes, releaseNotesURL: latest.notesLink,
                          appPath: appPath)
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        let appPath = item.installToken
        guard !appPath.isEmpty else { return }   // "Get…" rows just open item.url

        if appPath == Self.selfUpdateToken {
            progress("Opening UpdateScout's updater…")
            await MainActor.run { SelfUpdater.checkForUpdates() }
            return
        }

        // Re-fetch the appcast so we install exactly what we verify right now.
        progress("Fetching update details…")
        guard let data = FileManager.default.contents(
                atPath: appPath + "/Contents/Info.plist"),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let feedString = plist["SUFeedURL"] as? String,
              let feed = URL(string: feedString),
              let installed = (plist["CFBundleShortVersionString"] ?? plist["CFBundleVersion"]) as? String
        else { throw UpdateScoutError.parseFailure("feed URL for \(item.name)") }

        let (feedData, response) = try await Net.fetch(feed)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = AppcastParser.latestVersion(from: feedData, installed: installed,
                                                       installedBuild: plist["CFBundleVersion"] as? String),
              let plan = SparkleInstaller.plan(appPath: appPath, latest: latest)
        else { throw UpdateScoutError.parseFailure("appcast for \(item.name)") }

        try await SparkleInstaller.install(plan, progress: progress)
    }
}

/// Minimal Sparkle appcast (RSS) parser — picks the newest item the installed
/// app should be offered.
enum AppcastParser {
    struct Latest {
        var version: String
        var shortVersion: String?
        var link: String?
        /// Download URL of the update archive.
        var enclosureURL: String?
        /// Base64 Ed25519 signature of the archive's bytes, verified against
        /// the target app's SUPublicEDKey before anything is installed.
        var edSignature: String?
        /// Release notes: inline <description> (usually HTML) and/or a
        /// <sparkle:releaseNotesLink> page.
        var notes: String?
        var notesLink: String?
        /// `sparkle:channel`, e.g. "beta". Absent means the default channel.
        var channel: String?
        var minimumSystemVersion: String?

        var displayVersion: String { shortVersion ?? version }

        /// 0 stable, 1 beta-like, 2 alpha-like. Feeds don't tag every
        /// prerelease (Thaw leaves some betas untagged), so a prerelease
        /// marker in the version counts as much as the channel tag.
        var track: Int {
            max(AppcastParser.track(ofChannel: channel), VersionParts(displayVersion).track)
        }
    }

    static func track(ofChannel channel: String?) -> Int {
        guard let c = channel?.lowercased(), !c.isEmpty else { return 0 }
        switch c {
        case "beta", "rc", "preview", "pre", "prerelease": return 1
        default: return 2   // alpha, dev, nightly, and anything unrecognised
        }
    }

    /// The newest item on the installed app's release track that this Mac
    /// can run. The track is read from the installed version: a stable
    /// install sees stable releases only, a beta sees betas and releases, an
    /// alpha sees everything. So someone on 3.0.0-beta.4 is offered beta.5
    /// and 3.0.0, never an alpha.
    static func latestVersion(from data: Data, installed: String, installedBuild: String?) -> Latest? {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        parser.parse()
        let items = delegate.items

        var installedTrack = VersionParts(installed).track
        // The installed build may itself be a tagged feed item.
        if let match = items.first(where: {
            ($0.shortVersion != nil && $0.shortVersion == installed)
                || (installedBuild != nil && $0.version == installedBuild)
        }) {
            installedTrack = max(installedTrack, match.track)
        }

        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        var best: Latest?
        for item in items where item.track <= installedTrack {
            if let min = item.minimumSystemVersion, isNewerVersion(min, than: os) { continue }
            if best == nil || isNewerVersion(item.displayVersion, than: best!.displayVersion) { best = item }
        }
        return best
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [Latest] = []
        private var current: Latest?
        private var currentElement = ""
        private var buffer = ""
        /// Appcasts may carry binary-patch enclosures inside <sparkle:deltas>.
        /// Applying those needs Sparkle's BinaryDelta tool, so we ignore them
        /// and always install the item's full archive.
        private var insideDeltas = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            currentElement = name
            buffer = ""
            if name == "item" { current = Latest(version: "") }
            if name == "sparkle:deltas" { insideDeltas = true }
            if name == "enclosure", !insideDeltas, attributes["sparkle:deltaFrom"] == nil, var item = current {
                if let v = attributes["sparkle:version"], item.version.isEmpty { item.version = v }
                if let sv = attributes["sparkle:shortVersionString"], item.shortVersion == nil { item.shortVersion = sv }
                if let url = attributes["url"] { item.enclosureURL = url }
                if let sig = attributes["sparkle:edSignature"] { item.edSignature = sig }
                current = item
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

        /// Release notes are normally shipped as <![CDATA[ …html… ]]>, which
        /// arrives here rather than through foundCharacters.
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            buffer += String(data: CDATABlock, encoding: .utf8) ?? ""
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "sparkle:deltas" { insideDeltas = false }
            guard var item = current else { return }
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "sparkle:version": item.version = text
            case "sparkle:shortVersionString": item.shortVersion = text
            case "sparkle:channel": if !text.isEmpty { item.channel = text }
            case "sparkle:minimumSystemVersion": if !text.isEmpty { item.minimumSystemVersion = text }
            case "link": if item.link == nil { item.link = text }
            case "description": if !text.isEmpty { item.notes = text }
            case "sparkle:releaseNotesLink": if !text.isEmpty { item.notesLink = text }
            case "item":
                if !item.version.isEmpty || item.shortVersion != nil { items.append(item) }
                current = nil
                return
            default: break
            }
            current = item
        }
    }
}
