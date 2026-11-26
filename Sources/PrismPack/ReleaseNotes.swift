import SwiftUI

/// One GitHub release of PrismPack, for Settings' Release notes (Nick, 3 Nov
/// 2026): the notes are the release page's own text.
struct ReleaseEntry: Codable, Identifiable, Equatable {
    let tag: String
    let name: String
    let date: Date?
    let body: String
    let url: String
    let prerelease: Bool

    var id: String { tag }
    /// "v2.0.0" is shown and compared as "2.0.0".
    var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }
}

enum ReleaseHistory {
    private static var cacheURL: URL { Store.supportDirectory.appendingPathComponent("release-notes.json") }
    static var apiURL: URL { URL(string: "https://api.github.com/repos/\(AppIdentity.repo)/releases?per_page=30")! }

    /// GitHub's list, newest first, without drafts. Pure, so tests can feed it text.
    static func parse(_ data: Data) -> [ReleaseEntry] {
        struct Raw: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: String
            let published_at: String?
            let draft: Bool
            let prerelease: Bool
        }
        guard let raw = try? JSONDecoder().decode([Raw].self, from: data) else { return [] }
        let formatter = ISO8601DateFormatter()
        return raw.filter { !$0.draft }.map {
            ReleaseEntry(tag: $0.tag_name, name: $0.name ?? $0.tag_name,
                         date: $0.published_at.flatMap { formatter.date(from: $0) },
                         body: $0.body ?? "", url: $0.html_url, prerelease: $0.prerelease)
        }
    }

    /// What the last visit saw, so the sheet has something offline.
    static func cached() -> [ReleaseEntry] {
        guard let data = try? Data(contentsOf: cacheURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ReleaseEntry].self, from: data)) ?? []
    }

    /// Asked once when the sheet opens: one request, far under GitHub's 60 an
    /// hour. A renamed repo still answers (GitHub redirects the old name).
    static func fetch() async throws -> [ReleaseEntry] {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await Net.fetch(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw PrismPackError.parseFailure("GitHub's release list")
        }
        let entries = parse(data)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let saved = try? encoder.encode(entries) { try? saved.write(to: cacheURL, options: .atomic) }
        return entries
    }

    /// The version the window opens on: always the newest (Nick, 26 Nov 2026).
    static func initialTag(in shown: [ReleaseEntry]) -> String {
        shown.first?.tag ?? ""
    }

    /// Betas are listed only for someone on the Beta track.
    static func visible(_ entries: [ReleaseEntry], includePrereleases: Bool) -> [ReleaseEntry] {
        includePrereleases ? entries : entries.filter { !$0.prerelease }
    }
}

/// Settings → Release notes: the newest version first, earlier ones from the menu.
struct ReleaseNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries = ReleaseHistory.cached()
    @State private var selected = ""
    /// Set once the user chooses a version, so a late list never overrides it.
    @State private var picked = false
    @State private var loading = true
    @State private var failed = false

    private var includePrereleases: Bool {
        Channels.effective(Channels.choice(for: Bundle.main.bundleIdentifier),
                           installedVersion: SelfUpdater.version) == .beta
    }
    private var shown: [ReleaseEntry] { ReleaseHistory.visible(entries, includePrereleases: includePrereleases) }
    private var current: ReleaseEntry? { shown.first { $0.tag == selected } ?? shown.first }

    private func label(_ entry: ReleaseEntry) -> String {
        var text = "Version \(entry.version)"
        if entry.version == SelfUpdater.version { text += " (this version)" }
        if let date = entry.date { text += " · " + date.formatted(date: .abbreviated, time: .omitted) }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Release notes").font(.title3.weight(.semibold))
                if loading { ProgressView().controlSize(.small) }
                Spacer()
            }
            .padding(.trailing, 34)   // room for the close circle
            if let entry = current {
                HStack {
                    SortMenu(selection: Binding(get: { selected }, set: { selected = $0; picked = true }),
                             options: shown.map { (value: $0.tag, title: label($0)) }, help: "Version")
                    Spacer()
                    Button("Open on GitHub") {
                        if let url = URL(string: entry.url) { NSWorkspace.shared.open(url) }
                    }
                    .glass().controlSize(.small)
                }
                ScrollView {
                    Group {
                        if entry.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("No notes for this version. The release page may say more.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(UpdateDetailView.attributed(from: entry.body)).textSelection(.enabled)
                        }
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Spacer()
                Text(loading ? "Reading the release list from GitHub…"
                     : failed ? "Couldn't reach GitHub, and nothing is saved from an earlier visit. Check your connection and try again."
                     : "No releases are listed yet.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            }
            if failed, current != nil {
                Text("Couldn't reach GitHub: showing what was saved from your last visit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 540, height: 460)
        .popupClose()
        .task {
            selected = ReleaseHistory.initialTag(in: shown)
            do {
                entries = try await ReleaseHistory.fetch()
                failed = false
            } catch {
                failed = true
            }
            loading = false
            // The saved list can be older than the newest release, so choose
            // again now that the fresh list is in, unless the user has
            // already picked one.
            if !picked || current == nil || !shown.contains(where: { $0.tag == selected }) {
                selected = ReleaseHistory.initialTag(in: shown)
            }
        }
    }
}
