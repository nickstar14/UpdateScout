import AppKit

/// Icons for Discover's Homebrew tiles. Homebrew's lists carry none, so:
/// the installed app's own icon when there is one; else the square icon the
/// app's website offers (its apple-touch-icon, else its largest site icon);
/// else nil, and the tile keeps its letter. Fetched only when a tile shows,
/// one website at a time per tile, and kept in the data folder so each site
/// is asked once. A site with nothing usable is asked again after a week.
actor DiscoverIcons {
    static let shared = DiscoverIcons()

    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Hosts whose icon is the host's, not the app's.
    private static let genericHosts = ["github.com", "gitlab.com", "sourceforge.net", "codeberg.org", "bitbucket.org"]
    private static let retryEmptyAfter: TimeInterval = 7 * 86_400
    private static let maxConcurrent = 6

    private static var folder: URL {
        let url = Store.supportDirectory.appendingPathComponent("discover-icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    init() { memory.countLimit = 300 }

    /// Drops the decoded icons (the window closed); the files stay on disk.
    func releaseMemory() { memory.removeAllObjects() }

    /// The installed app's icon, found by the cask's app name. Cheap, so the
    /// tile asks this first, without waiting on the network.
    @MainActor static func installedIcon(for entry: DiscoverEntry) -> NSImage? {
        guard entry.kind == .cask else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for dir in ["/Applications", "\(home)/Applications"] {
            if let image = IconCache.shared.icon(forApp: "\(dir)/\(entry.title).app") { return image }
        }
        return nil
    }

    func icon(for entry: DiscoverEntry) async -> NSImage? {
        guard entry.kind == .cask || entry.kind == .formula, let homepage = entry.homepage,
              let site = URL(string: homepage), let host = site.host?.lowercased(),
              !Self.genericHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return nil }
        let key = "\(entry.kind.rawValue)-\(entry.name)".replacingOccurrences(of: "/", with: "_")
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let task = inFlight[key] { return await task.value }
        let task = Task { await self.load(key: key, site: site) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memory.setObject(image, forKey: key as NSString) }
        return image
    }

    private func load(key: String, site: URL) async -> NSImage? {
        let file = Self.folder.appendingPathComponent(key + ".img")
        let none = Self.folder.appendingPathComponent(key + ".none")
        if let image = NSImage(contentsOf: file) { return image }
        if let made = (try? none.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(made) < Self.retryEmptyAfter { return nil }

        await acquire()
        let found = await Self.fetchIcon(site: site)
        release()

        if let (data, image) = found {
            try? data.write(to: file, options: .atomic)
            try? FileManager.default.removeItem(at: none)
            return image
        }
        FileManager.default.createFile(atPath: none.path, contents: nil)
        return nil
    }

    private func acquire() async {
        if running < Self.maxConcurrent { running += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
    }

    // MARK: Fetching

    private static func fetchIcon(site: URL) async -> (Data, NSImage)? {
        guard let (html, response) = try? await Net.fetch(site) else { return nil }
        let base = response.url ?? site
        var candidates = iconLinks(in: String(decoding: html.prefix(512_000), as: UTF8.self), base: base)
        for path in ["/apple-touch-icon.png", "/favicon.ico"] {
            if let url = URL(string: path, relativeTo: base)?.absoluteURL, !candidates.contains(url) { candidates.append(url) }
        }
        for url in candidates.prefix(5) {
            guard let (data, reply) = try? await Net.fetch(url),
                  (reply as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data), usable(image),
                  let small = shrunk(image), let png = NSImage(data: small) else { continue }
            return (small, png)
        }
        return nil
    }

    /// `<link rel="…icon…">` hrefs, best first: apple-touch-icon, then site
    /// icons by their declared size.
    static func iconLinks(in html: String, base: URL) -> [URL] {
        let tag = #/<link\b[^>]*>/#.ignoresCase()
        var found: [(score: Int, url: URL)] = []
        for match in html.matches(of: tag) {
            let text = String(match.output)
            guard let rel = attribute("rel", in: text)?.lowercased(),
                  let href = attribute("href", in: text),
                  let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL
            else { continue }
            let words = rel.split(separator: " ")
            let declared = attribute("sizes", in: text).flatMap { Int($0.lowercased().split(separator: "x").first ?? "") } ?? 0
            if rel.contains("apple-touch-icon") {
                found.append((10_000 + declared, url))
            } else if words.contains("icon") {
                found.append((declared == 0 ? 16 : declared, url))
            }
        }
        var seen = Set<URL>()
        return found.sorted { $0.score > $1.score }.map(\.url).filter { seen.insert($0).inserted }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = try? Regex("\\b\(name)\\s*=\\s*[\"']([^\"']*)[\"']").ignoresCase()
        guard let pattern, let match = tag.firstMatch(of: pattern), let value = match.output[1].substring else { return nil }
        return String(value)
    }

    /// The icon redrawn at 128 px as PNG. Some sites serve 1024 px images,
    /// which would cost megabytes each once decoded.
    private static func shrunk(_ image: NSImage) -> Data? {
        let side = 128
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        let size = image.size, scale = min(CGFloat(side) / max(size.width, 1), CGFloat(side) / max(size.height, 1))
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: (CGFloat(side) - drawn.width) / 2, y: (CGFloat(side) - drawn.height) / 2,
                              width: drawn.width, height: drawn.height))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Big enough to look sharp on a tile; vector images always are.
    private static func usable(_ image: NSImage) -> Bool {
        let pixels = image.representations.map(\.pixelsWide).max() ?? 0
        return pixels == 0 || pixels >= 48
    }
}
