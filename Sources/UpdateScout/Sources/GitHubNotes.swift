import Foundation

/// Homebrew's API carries no changelogs, but most formulae and casks point at a
/// GitHub project. For items with no notes of their own, fetch the latest
/// release body from GitHub's public API. Best effort and rate-limit aware:
/// unauthenticated calls are capped at 60/hour, so only a handful per check.
enum GitHubNotes {
    static let maxLookupsPerCheck = 8

    static func enrich(_ items: [UpdateItem]) async -> [UpdateItem] {
        var budget = maxLookupsPerCheck
        var result = items
        for (index, item) in items.enumerated() {
            guard budget > 0, item.releaseNotes == nil,
                  let repo = repoSlug(from: item.url) else { continue }
            budget -= 1
            if let (notes, link) = await latestRelease(repo: repo, version: item.latestVersion) {
                result[index].releaseNotes = notes
                result[index].releaseNotesURL = link
            }
        }
        return result
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

    /// Notes for the release matching `version` if it's among the recent
    /// releases, otherwise the latest release. Returns (markdown body, html url).
    private static func latestRelease(repo: String, version: String) async -> (String, String)? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=10"),
              let (data, response) = try? await Net.fetch(url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !releases.isEmpty
        else { return nil }

        let wanted = version.lowercased()
        let match = releases.first { rel in
            let tag = ((rel["tag_name"] as? String) ?? "").lowercased()
            let name = ((rel["name"] as? String) ?? "").lowercased()
            return tag == wanted || tag == "v" + wanted || name.contains(wanted)
        } ?? releases.first { ($0["prerelease"] as? Bool) != true } ?? releases[0]

        let body = (match["body"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let link = match["html_url"] as? String ?? "https://github.com/\(repo)/releases"
        return body.isEmpty ? nil : (body, link)
    }
}
