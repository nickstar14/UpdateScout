import AppKit
import SwiftUI

/// The app's own website's words and pictures, for its details pop-up (Phase
/// 10 step 7). Fetched only when a pop-up opens, kept in `discover-details/`
/// in the data folder (capped at 50 MB, oldest removed first), never for tiles.
struct WebDetails: Equatable, Sendable {
    var description: String?
    var site: String
    /// Shrunk JPEGs, at most three.
    var images: [Data]

    var isEmpty: Bool { description == nil && images.isEmpty }
}

/// Reading a page's HTML. Pure, so it's tested without a network.
enum WebDetailsParser {
    static let maxDescription = 400
    private static let logoWords = ["logo", "icon", "avatar", "sprite", "badge", "favicon", "pixel", "spacer", "tracking", "emoji"]

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let pattern = try? Regex("\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')").ignoresCase(),
              let match = tag.firstMatch(of: pattern) else { return nil }
        return (match.output[1].substring ?? match.output[2].substring).map(String.init)
    }

    private static func tags(_ name: String, in html: String) -> [String] {
        guard let pattern = try? Regex("<\(name)\\b[^>]*>").ignoresCase() else { return [] }
        return html.matches(of: pattern).map { String($0.output[0].substring ?? "") }
    }

    /// The content of the first `<meta>` named (or with the property) in `names`.
    static func meta(_ names: [String], in html: String) -> String? {
        let wanted = names.map { $0.lowercased() }
        for tag in tags("meta", in: html) {
            let key = (attribute("name", in: tag) ?? attribute("property", in: tag))?.lowercased()
            if let key, wanted.contains(key), let content = attribute("content", in: tag) {
                let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    static func description(in html: String) -> String? {
        meta(["description", "og:description", "twitter:description"], in: html)
            .map { cut(collapse(decodeEntities($0)), to: maxDescription) }
            .flatMap { $0.count >= 20 ? $0 : nil }
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
                               ("&#x27;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&#8217;", "\u{2019}"), ("&#8211;", "\u{2013}")] {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }

    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// At most `limit` characters, cut at a word with an ellipsis.
    static func cut(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = String(text.prefix(limit))
        let words = head.split(separator: " ", omittingEmptySubsequences: true)
        let trimmed = words.dropLast().joined(separator: " ")
        return (trimmed.isEmpty ? head : trimmed) + "…"
    }

    static func looksLikeLogo(_ url: URL) -> Bool {
        let name = url.path.lowercased()
        let ext = url.pathExtension.lowercased()
        if ["svg", "gif", "ico"].contains(ext) { return true }
        return logoWords.contains { name.contains($0) }
    }

    /// A picture shaped like a screen, big enough to see.
    static func isScreenShaped(width: Int, height: Int) -> Bool {
        guard width >= 480, height > 0 else { return false }
        let ratio = Double(width) / Double(height)
        return ratio >= 1.2 && ratio <= 2.4
    }

    /// Where the page's pictures might be, best first: its preview images,
    /// then large `<img>` tags. Up to eight, https only, logos and vector or
    /// animated formats left out.
    static func imageCandidates(in html: String, base: URL) -> [URL] {
        var raw: [String] = []
        for tag in tags("meta", in: html) {
            let key = (attribute("property", in: tag) ?? attribute("name", in: tag))?.lowercased()
            if let key, ["og:image", "og:image:secure_url", "twitter:image", "twitter:image:src"].contains(key),
               let content = attribute("content", in: tag) { raw.append(content) }
        }
        for tag in tags("img", in: html) {
            let declared = attribute("width", in: tag).flatMap { Int($0.filter(\.isNumber)) } ?? 0
            var best = declared
            var source = attribute("src", in: tag) ?? attribute("data-src", in: tag)
            if let set = attribute("srcset", in: tag) {
                for part in set.split(separator: ",") {
                    let pieces = part.split(separator: " ", omittingEmptySubsequences: true)
                    if pieces.count == 2, pieces[1].hasSuffix("w"), let w = Int(pieces[1].dropLast()), w > best {
                        best = w
                        source = String(pieces[0])
                    }
                }
            }
            if best >= 400, let source { raw.append(source) }
        }
        var seen = Set<URL>()
        var result: [URL] = []
        for text in raw {
            guard let url = URL(string: decodeEntities(text), relativeTo: base)?.absoluteURL,
                  url.scheme == "https", !looksLikeLogo(url), seen.insert(url).inserted else { continue }
            result.append(url)
            if result.count == 8 { break }
        }
        return result
    }
}

/// The disk cache's rule: which folders go when it's over its cap.
enum DetailsCache {
    static let cap: Int64 = 50 * 1_048_576
    static let refetchAfter: TimeInterval = 30 * 86_400
    static let retryEmptyAfter: TimeInterval = 7 * 86_400

    /// Oldest first, until what's left fits.
    static func evictions(_ folders: [(name: String, size: Int64, date: Date)], cap: Int64 = DetailsCache.cap) -> [String] {
        var total = folders.reduce(Int64(0)) { $0 + $1.size }
        var gone: [String] = []
        for folder in folders.sorted(by: { $0.date < $1.date }) where total > cap {
            gone.append(folder.name)
            total -= folder.size
        }
        return gone
    }
}

actor DiscoverDetails {
    static let shared = DiscoverDetails()

    private struct Meta: Codable {
        var fetched: Date
        var description: String?
        var site: String
        var count: Int
    }

    private var inFlight: [String: Task<WebDetails?, Never>] = [:]
    private static let genericHosts = ["github.com", "gitlab.com", "sourceforge.net", "codeberg.org", "bitbucket.org"]

    private static var root: URL {
        let url = Store.supportDirectory.appendingPathComponent("discover-details", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The page, for entries whose homepage is the app's own.
    static func site(for entry: DiscoverEntry) -> URL? {
        guard entry.kind == .cask || entry.kind == .formula, let text = entry.homepage,
              let url = URL(string: text), url.scheme == "https", let host = url.host?.lowercased(),
              !genericHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return nil }
        return url
    }

    func details(for entry: DiscoverEntry) async -> WebDetails? {
        guard let site = Self.site(for: entry) else { return nil }
        let key = "\(entry.kind.rawValue)-\(entry.name)".replacingOccurrences(of: "/", with: "_")
        if let task = inFlight[key] { return await task.value }
        let task = Task { await Self.load(key: key, site: site) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private static func load(key: String, site: URL) async -> WebDetails? {
        let folder = root.appendingPathComponent(key, isDirectory: true)
        if let data = try? Data(contentsOf: folder.appendingPathComponent("meta.json")),
           let meta = try? JSONDecoder().decode(Meta.self, from: data) {
            let age = Date().timeIntervalSince(meta.fetched)
            let empty = meta.description == nil && meta.count == 0
            if age < (empty ? DetailsCache.retryEmptyAfter : DetailsCache.refetchAfter) {
                let images = (0..<meta.count).compactMap { try? Data(contentsOf: folder.appendingPathComponent("\($0).jpg")) }
                let result = WebDetails(description: meta.description, site: meta.site, images: images)
                return result.isEmpty ? nil : result
            }
        }
        let fetched = await fetch(site: site)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, data) in fetched.images.enumerated() {
            try? data.write(to: folder.appendingPathComponent("\(index).jpg"), options: .atomic)
        }
        let meta = Meta(fetched: Date(), description: fetched.description, site: fetched.site, count: fetched.images.count)
        if let data = try? JSONEncoder().encode(meta) { try? data.write(to: folder.appendingPathComponent("meta.json"), options: .atomic) }
        trim()
        return fetched.isEmpty ? nil : fetched
    }

    private static func fetch(site: URL) async -> WebDetails {
        let host = (site.host ?? "").replacingOccurrences(of: "www.", with: "")
        var empty = WebDetails(description: nil, site: host, images: [])
        var request = URLRequest(url: site)
        request.timeoutInterval = 8
        guard let (data, response) = try? await Net.fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return empty }
        let html = String(decoding: data.prefix(512_000), as: UTF8.self)
        empty.description = WebDetailsParser.description(in: html)
        let candidates = WebDetailsParser.imageCandidates(in: html, base: response.url ?? site)
        let pictures = await withTaskGroup(of: (Int, Data?).self) { group -> [Data] in
            for (index, url) in candidates.prefix(6).enumerated() {
                group.addTask { (index, await Self.picture(at: url)) }
            }
            var found: [(Int, Data)] = []
            for await (index, data) in group { if let data { found.append((index, data)) } }
            return found.sorted { $0.0 < $1.0 }.prefix(3).map(\.1)
        }
        empty.images = pictures
        return empty
    }

    /// One candidate: kept only if it is a screen-shaped picture, shrunk to
    /// 640 px wide.
    private static func picture(at url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await Net.fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 3_000_000,
              let rep = NSBitmapImageRep(data: data),
              WebDetailsParser.isScreenShaped(width: rep.pixelsWide, height: rep.pixelsHigh) else { return nil }
        return shrunk(rep)
    }

    private static func shrunk(_ rep: NSBitmapImageRep) -> Data? {
        let width = min(640, rep.pixelsWide)
        let height = max(1, Int((Double(rep.pixelsHigh) * Double(width) / Double(rep.pixelsWide)).rounded()))
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        rep.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return out.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    /// Over the cap: the oldest folders go.
    private static func trim() {
        let fm = FileManager.default
        let folders: [(name: String, size: Int64, date: Date)] = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).compactMap { name in
            let dir = root.appendingPathComponent(name)
            let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            let size = files.reduce(Int64(0)) { $0 + ((try? fm.attributesOfItem(atPath: dir.appendingPathComponent($1).path)[.size] as? NSNumber)?.int64Value ?? 0) }
            let date = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return (name, size, date)
        }
        for name in DetailsCache.evictions(folders) { try? fm.removeItem(at: root.appendingPathComponent(name)) }
    }
}

// MARK: - The pop-up's section

/// The description and up to three pictures, between the pop-up's text and
/// its buttons. Shows nothing when the app's website gave nothing.
struct WebDetailsSection: View {
    let entry: DiscoverEntry
    @State private var details: WebDetails?
    @State private var loading: Bool

    init(entry: DiscoverEntry) {
        self.entry = entry
        _loading = State(initialValue: DiscoverDetails.site(for: entry) != nil)
    }

    var body: some View {
        Group {
            if loading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Looking for the app's own description…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let details {
                VStack(alignment: .leading, spacing: 8) {
                    if let text = details.description {
                        Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text("From \(details.site)").font(.caption).foregroundStyle(.secondary)
                    }
                    if !details.images.isEmpty { pictures(details) }
                }
            }
        }
        .task(id: entry.id) {
            guard DiscoverDetails.site(for: entry) != nil else { loading = false; return }
            details = await DiscoverDetails.shared.details(for: entry)
            loading = false
        }
    }

    private func pictures(_ details: WebDetails) -> some View {
        let images = details.images.compactMap { NSImage(data: $0) }
        return HStack(spacing: 8) {
            ForEach(images.indices, id: \.self) { index in
                Button {
                    PicturePreviewWindow.shared.show(images: images, index: index, title: entry.title)
                } label: {
                    Image(nsImage: images[index])
                        .resizable().scaledToFill()
                        .frame(width: 160, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Click to see it larger")
                .accessibilityLabel("Picture \(index + 1) of \(images.count) from \(entry.title)'s website")
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Larger view

/// The pictures larger, in a small window; the arrow keys flip through them.
@MainActor
final class PicturePreviewWindow {
    static let shared = PicturePreviewWindow()
    private var panel: NSPanel?

    func show(images: [NSImage], index: Int, title: String) {
        panel?.close()
        let view = PicturePreview(images: images, start: index)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = title
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: view)
        // The window's own size, not the view's smallest (it opened 420 wide).
        host.sizingOptions = []
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 680, height: 460))
        panel.center()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }
}

private struct PicturePreview: View {
    let images: [NSImage]
    @State var current: Int
    @FocusState private var focused: Bool

    init(images: [NSImage], start: Int) {
        self.images = images
        _current = State(initialValue: min(max(start, 0), max(images.count - 1, 0)))
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: images[current]).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if images.count > 1 {
                HStack(spacing: 10) {
                    Button { current = (current - 1 + images.count) % images.count } label: { Image(systemName: "chevron.left") }
                        .glass().accessibilityLabel("Previous picture")
                    Text("\(current + 1) of \(images.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Button { current = (current + 1) % images.count } label: { Image(systemName: "chevron.right") }
                        .glass().accessibilityLabel("Next picture")
                }
            }
        }
        .padding(16)
        .frame(minWidth: 420, idealWidth: 680, minHeight: 320, idealHeight: 460)
        .focusable()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { if images.count > 1 { current = (current - 1 + images.count) % images.count }; return .handled }
        .onKeyPress(.rightArrow) { if images.count > 1 { current = (current + 1) % images.count }; return .handled }
    }
}
