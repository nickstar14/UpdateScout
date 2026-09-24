import Foundation

/// Homebrew's API carries no changelogs, but most formulae and casks point at a
/// GitHub project. For items with no notes of their own, fetch the latest
/// release body from GitHub's public API. Best effort and rate-limit aware:
/// unauthenticated calls are capped at 60/hour, so only a handful per check.
enum GitHubNotes {
    static let maxLookupsPerCheck = 8

    static func enrich(_ items: [UpdateItem]) async -> [UpdateItem] {
        var budget = maxLookupsPerCheck
        var cache = Cache.load()
        var result = items
        for (index, item) in items.enumerated() {
            guard item.releaseNotes == nil, let repo = repoSlug(from: item.url) else { continue }
            let key = "\(repo)@\(item.latestVersion)"
            // A version's notes don't change, so each is fetched once. Without
            // this, short check intervals blow through GitHub's 60-requests-
            // per-hour limit and notes silently stop appearing.
            if let hit = cache.entries[key] {
                if let notes = hit.notes {
                    result[index].releaseNotes = notes
                    result[index].releaseNotesURL = hit.url
                }
                continue
            }
            guard budget > 0 else { continue }
            budget -= 1
            switch await latestRelease(repo: repo, version: item.latestVersion) {
            case .notes(let notes, let link):
                cache.entries[key] = Cache.Entry(notes: notes, url: link)
                result[index].releaseNotes = notes
                result[index].releaseNotesURL = link
            case .none:
                // A real answer: this release has no notes. Remember it.
                cache.entries[key] = Cache.Entry(notes: nil, url: nil)
            case .failed:
                // Network error or rate limit — say nothing, ask again next time.
                break
            }
        }
        cache.save()
        return result
    }

    /// Notes already fetched, keyed "owner/repo@version". A missing-notes
    /// result is cached too, so a project with no release body isn't re-asked.
    private struct Cache: Codable {
        struct Entry: Codable { var notes: String?; var url: String? }
        var entries: [String: Entry] = [:]

        private static var url: URL { Store.supportDirectory.appendingPathComponent("github-notes.json") }

        static func load() -> Cache {
            guard let data = FileManager.default.contents(atPath: url.path),
                  let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return Cache() }
            return cache
        }

        func save() {
            // Keep the file from growing forever: old versions are never asked for again.
            var trimmed = self
            if trimmed.entries.count > 400 {
                trimmed.entries = Dictionary(uniqueKeysWithValues: Array(trimmed.entries.suffix(400)))
            }
            if let data = try? JSONEncoder().encode(trimmed) { try? data.write(to: Self.url, options: .atomic) }
        }
    }

    /// "owner/repo" from a github.com URL, or nil.
    static func repoSlug(from urlString: String?) -> String? {
        guard let urlString, let url = URL(string: urlString),
              url.host?.hasSuffix("github.com") == true else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        return "\(parts[0])/\(repo)"
    }

    enum Outcome { case notes(String, String), none, failed }

    /// Notes for the release matching `version` if it's among the recent
    /// releases, otherwise the latest release.
    private static func latestRelease(repo: String, version: String) async -> Outcome {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=10"),
              let (data, response) = try? await Net.fetch(url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return .failed }
        guard !releases.isEmpty else { return .none }

        let wanted = version.lowercased()
        let match = releases.first { rel in
            let tag = ((rel["tag_name"] as? String) ?? "").lowercased()
            let name = ((rel["name"] as? String) ?? "").lowercased()
            return tag == wanted || tag == "v" + wanted || name.contains(wanted)
        } ?? releases.first { ($0["prerelease"] as? Bool) != true } ?? releases[0]

        let body = (match["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let link = match["html_url"] as? String ?? "https://github.com/\(repo)/releases"
        return body.isEmpty ? .none : .notes(body, link)
    }
}
