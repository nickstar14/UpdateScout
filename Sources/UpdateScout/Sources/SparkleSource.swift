import Foundation

/// Detects Sparkle-based apps (SUFeedURL in Info.plist), fetches their appcast,
/// and compares versions. Install action: if the app has a matching Homebrew cask
/// we hand off to `brew install --cask --force`; otherwise we open the app's page
/// (or the appcast enclosure's release page). Driving each app's own embedded
/// Sparkle for in-place install is a planned follow-up — replacing another app's
/// bundle without Sparkle's signature verification is deliberately out of scope.
struct SparkleSource: UpdateSource {
    let id = "sparkle"
    let displayName = "Sparkle apps"

    func detect() async throws -> [UpdateItem] {
        let fm = FileManager.default
        var candidates: [(name: String, version: String, feed: URL)] = []

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
                candidates.append((name, installed, feed))
            }
        }

        // Fetch appcasts concurrently; ignore individual feed failures.
        return await withTaskGroup(of: UpdateItem?.self) { group in
            for c in candidates {
                group.addTask { await checkAppcast(name: c.name, installed: c.version, feed: c.feed) }
            }
            var items: [UpdateItem] = []
            for await item in group { if let item { items.append(item) } }
            return items
        }
    }

    private func checkAppcast(name: String, installed: String, feed: URL) async -> UpdateItem? {
        guard let (data, response) = try? await URLSession.shared.data(from: feed),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = AppcastParser.latestVersion(from: data)
        else { return nil }

        let latestVersion = latest.shortVersion ?? latest.version
        guard isNewerVersion(latestVersion, than: installed) else { return nil }
        return UpdateItem(sourceID: id, name: name,
                          installedVersion: installed,
                          latestVersion: latestVersion,
                          url: latest.link ?? feed.absoluteString,
                          caveat: "Opens the app's release page — use the app's own \"Check for Updates…\" to install in place.",
                          installToken: "",
                          scriptedInstall: false)
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        // Not scripted; the UI opens item.url. Nothing to do here.
    }
}

/// Minimal Sparkle appcast (RSS) parser — pulls the newest item's version info.
enum AppcastParser {
    struct Latest {
        var version: String
        var shortVersion: String?
        var link: String?
    }

    static func latestVersion(from data: Data) -> Latest? {
        let parser = XMLParser(data: data)
        let delegate = Delegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.best
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var best: Latest?
        private var current: Latest?
        private var currentElement = ""
        private var buffer = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            currentElement = name
            buffer = ""
            if name == "item" { current = Latest(version: "") }
            if name == "enclosure", var item = current {
                if let v = attributes["sparkle:version"], item.version.isEmpty { item.version = v }
                if let sv = attributes["sparkle:shortVersionString"], item.shortVersion == nil { item.shortVersion = sv }
                current = item
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { buffer += string }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard var item = current else { return }
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "sparkle:version": item.version = text
            case "sparkle:shortVersionString": item.shortVersion = text
            case "link": if item.link == nil { item.link = text }
            case "item":
                if !item.version.isEmpty || item.shortVersion != nil {
                    let candidate = item
                    let candVer = candidate.shortVersion ?? candidate.version
                    let bestVer = best.map { $0.shortVersion ?? $0.version }
                    if bestVer == nil || isNewerVersion(candVer, than: bestVer!) { best = candidate }
                }
                current = nil
                return
            default: break
            }
            current = item
        }
    }
}
