import Foundation
import SwiftUI
import CoreText

/// Font previews on Discover's Fonts page (Phase 10 step 6). A font card draws
/// a sample line in the font itself, fetched from Google Fonts for the cards
/// on screen. The font is held in memory only for drawing: never installed,
/// never registered with macOS, never written to disk, dropped when the
/// page closes. Only the family name and the sample's letters are sent.
enum FontPreviewName {
    static let sample = "The quick brown fox jumps over the lazy dog"

    /// The Google Fonts family for a font cask. Google wants the family's own
    /// capitals ("JetBrains Mono", "IBM Plex Sans"), so the cask's title is
    /// used, without a bracketed note; the token is the fallback. Nil for
    /// fonts Google doesn't have (Nerd Font builds and the like), which show
    /// their name only.
    static func family(forCask name: String, title: String) -> String? {
        guard name.hasPrefix("font-") else { return nil }
        var family = title
        if let bracket = family.firstIndex(of: "(") { family = String(family[..<bracket]) }
        family = family.trimmingCharacters(in: .whitespaces)
        if family.isEmpty || family == name {
            family = name.dropFirst(5).split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        let lower = family.lowercased()
        guard !family.isEmpty, !lower.contains("nerd"), !lower.hasSuffix(" nf"), !lower.contains(" nf ") else { return nil }
        return family
    }

    /// The Google Fonts CSS address for just the sample's letters, so the
    /// download is a few kilobytes.
    static func cssURL(family: String) -> URL? {
        var parts = URLComponents(string: "https://fonts.googleapis.com/css2")
        parts?.queryItems = [URLQueryItem(name: "family", value: family),
                             URLQueryItem(name: "text", value: sample)]
        return parts?.url
    }

    /// The first `url(...)` in the CSS Google answers with.
    static func fontURL(inCSS css: String) -> URL? {
        guard let start = css.range(of: "url("), let end = css.range(of: ")", range: start.upperBound..<css.endIndex)
        else { return nil }
        let text = css[start.upperBound..<end.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
        guard let url = URL(string: text), url.scheme == "https", url.host?.hasSuffix("gstatic.com") == true else { return nil }
        return url
    }
}

/// Keeps the fonts fetched for the cards on screen.
@MainActor
final class FontPreviews: ObservableObject {
    static let shared = FontPreviews()

    @Published private var fonts: [String: CTFontDescriptor] = [:]
    private var tried: Set<String> = []
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var tasks: [Task<Void, Never>] = []

    /// Ephemeral: nothing is cached on disk.
    private let session = URLSession(configuration: {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        return c
    }())

    func font(for entry: DiscoverEntry, size: CGFloat) -> Font? {
        fonts[entry.name].map { Font(CTFontCreateWithFontDescriptor($0, size, nil)) }
    }

    /// Called as a card appears. The fetch isn't tied to the card's view (a
    /// lazy grid cancels those as it scrolls); it runs on its own, and a failed
    /// or finished one isn't tried again until the page is closed.
    func request(_ entry: DiscoverEntry) {
        let name = entry.name
        guard fonts[name] == nil, !tried.contains(name),
              let family = FontPreviewName.family(forCask: name, title: entry.title) else { return }
        tried.insert(name)
        tasks.append(Task {
            await slot()
            defer { releaseSlot() }
            let got = await fetch(family: family)
            if let font = got, !Task.isCancelled { fonts[name] = font }
        })
    }

    /// Four downloads at a time.
    private func slot() async {
        if active < 4 { active += 1; return }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func releaseSlot() {
        if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
    }

    private func fetch(family: String) async -> CTFontDescriptor? {
        guard let cssURL = FontPreviewName.cssURL(family: family) else { return nil }
        var request = URLRequest(url: cssURL)
        // An old browser name makes Google answer with a plain TrueType file.
        request.setValue("Mozilla/4.0", forHTTPHeaderField: "User-Agent")
        guard let (css, _) = try? await session.data(for: request),
              let text = String(data: css, encoding: .utf8),
              let fontURL = FontPreviewName.fontURL(inCSS: text),
              let (data, _) = try? await session.data(from: fontURL),
              data.count < 2_000_000,
              let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData)
        else { return nil }
        return descriptor
    }

    /// Everything goes when the page closes or leaves Fonts.
    func releaseAll() {
        tasks.forEach { $0.cancel() }
        tasks = []
        fonts = [:]
        tried = []
    }
}

/// The sample line, or the description until the font is there.
struct FontSample: View {
    let entry: DiscoverEntry
    let size: CGFloat
    var lines = 1
    @ObservedObject private var previews = FontPreviews.shared

    var body: some View {
        Group {
            if let font = previews.font(for: entry, size: size) {
                Text(FontPreviewName.sample).font(font)
            } else {
                Text(entry.summary ?? " ").font(size > 14 ? .callout : .caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { previews.request(entry) }
    }
}

// MARK: - Styles in the details pop-up

/// One style of a family as Google Fonts has it.
struct FontFace: Identifiable, Hashable, Sendable {
    let weight: Int
    let italic: Bool
    let url: URL
    var id: String { "\(weight)\(italic ? "i" : "")" }
    var name: String { FontStyleName.name(weight: weight, italic: italic) }
}

enum FontStyleName {
    /// "Bold", "SemiBold Italic"…
    static func name(weight: Int, italic: Bool) -> String {
        let base: String
        switch weight {
        case ...150: base = "Thin"
        case ...250: base = "ExtraLight"
        case ...350: base = "Light"
        case ...450: base = "Regular"
        case ...550: base = "Medium"
        case ...650: base = "SemiBold"
        case ...750: base = "Bold"
        case ...850: base = "ExtraBold"
        default: base = "Black"
        }
        if italic { return base == "Regular" ? "Italic" : "\(base) Italic" }
        return base
    }

    /// Google's address for every style a family might have; it answers with
    /// only the ones that exist, one file each, cut down to `text`.
    static func cssURL(family: String, text: String) -> URL? {
        let weights = stride(from: 100, through: 900, by: 100).flatMap { ["\($0)", "\($0)i"] }
        var parts = URLComponents(string: "https://fonts.googleapis.com/css")
        parts?.queryItems = [URLQueryItem(name: "family", value: "\(family):\(weights.joined(separator: ","))"),
                             URLQueryItem(name: "text", value: text)]
        return parts?.url
    }

    /// The styles in Google's CSS, one `@font-face` each, in weight order.
    static func faces(inCSS css: String) -> [FontFace] {
        var faces: [FontFace] = []
        for block in css.components(separatedBy: "@font-face").dropFirst() {
            func value(_ key: String) -> String? {
                guard let r = block.range(of: "\(key):") else { return nil }
                let rest = block[r.upperBound...]
                return rest.prefix { $0 != ";" }.trimmingCharacters(in: .whitespaces)
            }
            guard let weightText = value("font-weight"), let weight = Int(weightText.split(separator: " ").first ?? ""),
                  let url = FontPreviewName.fontURL(inCSS: block) else { continue }
            faces.append(FontFace(weight: weight, italic: value("font-style") == "italic", url: url))
        }
        return faces.sorted { ($0.italic ? 1 : 0, $0.weight) < ($1.italic ? 1 : 0, $1.weight) }
    }

    /// "9 weights, with italics", for the heading.
    static func summary(_ faces: [FontFace]) -> String {
        let upright = faces.filter { !$0.italic }.count
        let italics = faces.filter(\.italic).count
        let total = faces.count
        let styles = "\(total) style\(total == 1 ? "" : "s")"
        if italics > 0, upright > 0 { return "\(styles) (\(upright) upright, \(italics) italic)" }
        return styles
    }
}

/// The styles of one family, fetched when its pop-up opens and dropped when
/// it closes. Held in memory only, like the tile previews.
@MainActor
final class FontFamilyPreview: ObservableObject {
    enum Phase { case loading, ready, failed }

    static let longSample = "Sphinx of black quartz, judge my vow. Pack my box with five dozen liquor jugs! 0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz &?@#%()"

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var faces: [FontFace] = []
    @Published private var descriptors: [String: CTFontDescriptor] = [:]
    private var task: Task<Void, Never>?
    private let session = URLSession(configuration: {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        return c
    }())

    func font(_ face: FontFace, size: CGFloat) -> Font? {
        descriptors[face.id].map { Font(CTFontCreateWithFontDescriptor($0, size, nil)) }
    }

    func load(family: String) {
        guard task == nil else { return }
        task = Task {
            var request = URLRequest(url: FontStyleName.cssURL(family: family, text: Self.longSample)!)
            request.setValue("Mozilla/4.0", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await session.data(for: request),
                  let css = String(data: data, encoding: .utf8) else { phase = .failed; return }
            let found = FontStyleName.faces(inCSS: css)
            guard !found.isEmpty, !Task.isCancelled else { phase = .failed; return }
            faces = found
            phase = .ready
            // A few at a time, each a few KB.
            for batch in stride(from: 0, to: found.count, by: 4) {
                await withTaskGroup(of: (String, CTFontDescriptor?).self) { group in
                    for face in found[batch..<min(batch + 4, found.count)] {
                        group.addTask { [session] in
                            guard let (bytes, _) = try? await session.data(from: face.url), bytes.count < 2_000_000
                            else { return (face.id, nil) }
                            return (face.id, CTFontManagerCreateFontDescriptorFromData(bytes as CFData))
                        }
                    }
                    for await (id, descriptor) in group {
                        if let descriptor, !Task.isCancelled { descriptors[id] = descriptor }
                    }
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// "Styles": the count and names, a longer preview, and each style drawn in
/// itself. Google's list is what the family offers; Homebrew installs its own files.
struct FontStylesSection: View {
    let family: String
    @StateObject private var preview = FontFamilyPreview()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch preview.phase {
            case .loading:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Looking up its styles…").font(.caption).foregroundStyle(.secondary) }
            case .failed:
                EmptyView()
            case .ready:
                Text(FontStyleName.summary(preview.faces)).font(.callout.weight(.semibold))
                if let regular = preview.faces.first(where: { $0.weight == 400 && !$0.italic }) ?? preview.faces.first,
                   let font = preview.font(regular, size: 15) {
                    Text(FontFamilyPreview.longSample).font(font).fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(preview.faces) { face in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(face.name).font(.caption).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
                                if let font = preview.font(face, size: 15) {
                                    Text("The quick brown fox jumps over the lazy dog").font(font).lineLimit(1)
                                } else {
                                    Text(" ").font(.callout)
                                }
                            }
                        }
                    }
                }
                // An exact height: a scroll view in a pop-up collapses otherwise.
                .frame(height: min(CGFloat(preview.faces.count) * 22 + 4, 150))
                Text("Google Fonts lists these styles. Homebrew's package installs its own files, which can differ.")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { preview.load(family: family) }
        .onDisappear { preview.cancel() }
    }
}
