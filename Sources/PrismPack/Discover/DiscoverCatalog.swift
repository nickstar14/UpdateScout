import Foundation

/// One thing Discover can install.
struct DiscoverEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case cask, formula, npm, pypi, crate, gem, ext
    }
    let kind: Kind
    /// Cask token, formula or package name, or extension id.
    let name: String
    let title: String
    var summary: String?
    var version: String
    var homepage: String?
    /// Installs over 30 days (Homebrew), or downloads (registries).
    var popularity: Int = 0
    /// When it first appeared (Homebrew: first seen by PrismPack; crates.io:
    /// published), for the Newest sort. Nil when unknown.
    var added: Date? = nil
    /// When its version last changed (Homebrew: seen changing by PrismPack;
    /// registries: last publish), for the Recently updated sort.
    var updated: Date? = nil

    var id: String { "\(kind.rawValue):\(name)" }

    /// Matches `InstalledPackage.discoverKey`.
    var installKey: String {
        switch kind {
        case .pypi, .ext: "\(kind.rawValue):\(name.lowercased())"
        default: id
        }
    }

    /// The section whose colour and icon it borrows.
    var sectionID: String {
        switch kind {
        case .cask, .formula: "homebrew"
        case .npm: "npm"
        case .pypi: "pip"
        case .crate: "cargo"
        case .gem: "gem"
        case .ext: "editors"
        }
    }

    /// The small tag after the description ("cask", "formula", "npm").
    var tag: String {
        switch kind {
        case .cask: "cask"
        case .formula: "formula"
        case .npm: "npm"
        case .pypi: "PyPI"
        case .crate: "crate"
        case .gem: "gem"
        case .ext: "extension"
        }
    }

    /// The version without Homebrew's build suffix ("156.0.4314.58,bc665d48…").
    var shortVersion: String {
        String(version.split(separator: ",", maxSplits: 1).first ?? Substring(version))
    }

    var isFont: Bool { kind == .cask && name.hasPrefix("font-") }
    var isRuntime: Bool { DiscoverCatalog.runtimes.contains(name) && (kind == .formula || kind == .cask) }
}

extension InstalledPackage {
    /// The key a Discover entry for the same thing has, for the Installed pill.
    var discoverKey: String? {
        switch sourceID {
        case "homebrew", "tools":
            if let detail, detail.hasPrefix("cask ") { return "cask:" + detail.dropFirst(5) }
            return "formula:\(name)"
        case "pip": return "pypi:\(name.lowercased())"
        case "npm": return "npm:\(name)"
        case "cargo": return "crate:\(name)"
        case "gem": return "gem:\(name)"
        case "editors": return "ext:" + (name.split(separator: " ").first.map(String.init) ?? name).lowercased()
        default: return nil
        }
    }
}

/// Homebrew's casks and formulae for Discover: downloaded at most daily,
/// cached on disk and searched locally, so search works offline. The big
/// lists are decoded once into compact entries and the raw JSON is dropped.
enum DiscoverCatalog {
    struct Snapshot: Sendable {
        var entries: [DiscoverEntry] = []
        /// Token or name → entry, for the popular and recent lists.
        var byID: [String: DiscoverEntry] = [:]
        /// Popular this month, most installed first.
        var popularCasks: [DiscoverEntry] = []
        var popularFormulae: [DiscoverEntry] = []
        /// New since PrismPack last looked, newest first.
        var recent: [DiscoverEntry] = []
    }

    /// Language runtimes, shown under Runtimes rather than Command line.
    static let runtimes: Set<String> = [
        "node", "node@20", "node@22", "node@24", "python@3.12", "python@3.13", "python@3.14", "python@3.15",
        "ruby", "rust", "rustup", "go", "openjdk", "openjdk@17", "openjdk@21", "deno", "bun", "php", "perl", "lua",
        "luajit", "erlang", "elixir", "julia", "kotlin", "scala", "swift", "zig", "nim", "crystal", "ocaml", "ghc",
        "dotnet", "r", "temurin", "temurin@17", "temurin@21", "temurin@25", "dotnet-sdk", "zulu@17", "zulu@21",
    ]

    private static var folder: URL { Store.supportDirectory }
    private static let day: TimeInterval = 24 * 3600

    static func load() async throws -> Snapshot {
        // Off the main actor, and one big list at a time, so the memory
        // used while decoding never doubles up.
        try await Task.detached(priority: .userInitiated) {
            async let counts = loadPopularity()
            let casks = try await loadCasks()
            let formulae = try await loadFormulae()
            return build(casks: casks, formulae: formulae, popularity: await counts)
        }.value
    }

    /// What's on disk, however old, with no network at all, so the page
    /// fills at once; nil before the first download. `load()` then refreshes
    /// when `isFresh` says the copies are over a day old.
    static func cached() async -> Snapshot? {
        await Task.detached(priority: .userInitiated) { () -> Snapshot? in
            guard let casks = readJSON(CompactCasks.self, casksURL),
                  let formulae = readJSON([CompactFormula].self, formulaeURL) else { return nil }
            return build(casks: entries(casks.casks),
                         formulae: formulae.map {
                             DiscoverEntry(kind: .formula, name: $0.n, title: $0.n, summary: $0.d, version: $0.v, homepage: $0.h)
                         },
                         popularity: readJSON(Popularity.self, popularityURL) ?? Popularity())
        }.value
    }

    /// Whether every list on disk is under a day old.
    /// The refresh arrow: mark the saved lists old so the next load downloads
    /// them again. The old files stay, so a failed download keeps what's shown.
    static func markStale() {
        let old = Date(timeIntervalSince1970: 0)
        for url in [CaskIndex.cacheURL, casksURL, formulaeURL, popularityURL] {
            try? FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
        }
    }

    static var isFresh: Bool {
        [CaskIndex.cacheURL, casksURL, formulaeURL, popularityURL].allSatisfy { age(of: $0) < day }
    }

    private static func build(casks: [DiscoverEntry], formulae: [DiscoverEntry],
                              popularity: Popularity) -> Snapshot {
        var snap = Snapshot()
        snap.entries.reserveCapacity(casks.count + formulae.count)
        for var e in casks { e.popularity = popularity.casks[e.name] ?? 0; snap.entries.append(e) }
        for var e in formulae { e.popularity = popularity.formulae[e.name] ?? 0; snap.entries.append(e) }
        let added = recentlyAdded(casks: casks.map(\.name), formulae: formulae.map(\.name))
        let addedOn = Dictionary(added.map { ($0.id, $0.date) }, uniquingKeysWith: { first, _ in first })
        let changed = versionChanges(snap.entries)
        for i in snap.entries.indices {
            let id = snap.entries[i].id
            snap.entries[i].added = addedOn[id]
            snap.entries[i].updated = changed[id] ?? addedOn[id]
        }
        for e in snap.entries { snap.byID[e.id] = e }
        snap.popularCasks = popularity.caskOrder.compactMap { snap.byID["cask:\($0)"] }
        snap.popularFormulae = popularity.formulaOrder.compactMap { snap.byID["formula:\($0)"] }
        snap.recent = added.compactMap { snap.byID[$0.id] }
        return snap
    }

    // MARK: Search

    /// Local search, best match first: exact name, then names that start with
    /// the text, then names, titles and descriptions that contain it. Ties go
    /// to the more installed.
    static func search(_ text: String, in entries: [DiscoverEntry], limit: Int = 60) -> [DiscoverEntry] {
        let q = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var scored: [(Int, DiscoverEntry)] = []
        for e in entries {
            let name = e.name.lowercased(), title = e.title.lowercased()
            let score: Int
            if name == q || title == q { score = 4 }
            else if name.hasPrefix(q) || title.hasPrefix(q) { score = 3 }
            else if name.contains(q) || title.contains(q) { score = 2 }
            else if e.summary?.lowercased().contains(q) == true { score = 1 }
            else { continue }
            scored.append((score, e))
        }
        scored.sort { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.popularity > $1.1.popularity }
        return scored.prefix(limit).map(\.1)
    }

    // MARK: Casks

    private struct CaskJSON: Decodable {
        let token: String
        let name: [String]?
        let desc: String?
        let version: String?
        let homepage: String?
        let deprecated: Bool?
        let disabled: Bool?
    }

    private struct CompactCasks: Codable {
        /// The cask file's modification date this was made from.
        let stamp: Date
        let casks: [CompactCask]
    }
    private struct CompactCask: Codable {
        let t: String, n: String, d: String?, v: String, h: String?
    }

    private static var casksURL: URL { folder.appendingPathComponent("discover-casks.json") }

    /// From the cask oracle's own daily file (CaskIndex), so it's one download.
    /// The 19 MB file is decoded only when it changes; otherwise the compact
    /// copy made from it last time is read.
    private static func loadCasks() async throws -> [DiscoverEntry] {
        func stamp() -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: CaskIndex.cacheURL.path))?[.modificationDate] as? Date
        }
        let cached = readJSON(CompactCasks.self, casksURL)
        // Still current: the cask file is under a day old and unchanged.
        if let cached, age(of: CaskIndex.cacheURL) < day, cached.stamp == stamp() {
            return entries(cached.casks)
        }
        let data = try await CaskIndex.rawData()
        let stamp = stamp()
        let compact: [CompactCask]
        if let stamp, let cached, cached.stamp == stamp {
            compact = cached.casks
        } else {
            compact = try autoreleasepool {
                try JSONDecoder().decode([CaskJSON].self, from: data).compactMap { c in
                    guard c.deprecated != true, c.disabled != true else { return nil }
                    return CompactCask(t: c.token, n: c.name?.first ?? c.token, d: c.desc,
                                       v: c.version ?? "latest", h: c.homepage)
                }
            }
            if let stamp { writeJSON(CompactCasks(stamp: stamp, casks: compact), casksURL) }
        }
        return entries(compact)
    }

    private static func entries(_ compact: [CompactCask]) -> [DiscoverEntry] {
        compact.map {
            DiscoverEntry(kind: .cask, name: $0.t, title: $0.n, summary: $0.d, version: $0.v, homepage: $0.h)
        }
    }

    // MARK: Formulae

    private struct FormulaJSON: Decodable {
        struct Versions: Decodable { let stable: String? }
        let name: String
        let desc: String?
        let homepage: String?
        let versions: Versions?
        let deprecated: Bool?
        let disabled: Bool?
    }

    /// The compact form kept on disk (about 1 MB, not formula.json's 32 MB).
    private struct CompactFormula: Codable {
        let n: String, d: String?, v: String, h: String?
    }

    private static var formulaeURL: URL { folder.appendingPathComponent("discover-formulae.json") }

    private static func loadFormulae() async throws -> [DiscoverEntry] {
        var compact: [CompactFormula]? = nil
        if age(of: formulaeURL) < day { compact = readJSON([CompactFormula].self, formulaeURL) }
        if compact == nil {
            do {
                let url = URL(string: "https://formulae.brew.sh/api/formula.json")!
                let (data, response) = try await Net.fetch(url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw PrismPackError.parseFailure("Homebrew formula list download")
                }
                let fresh = try autoreleasepool {
                    try JSONDecoder().decode([FormulaJSON].self, from: data).compactMap { f -> CompactFormula? in
                        guard f.deprecated != true, f.disabled != true, let v = f.versions?.stable else { return nil }
                        return CompactFormula(n: f.name, d: f.desc, v: v, h: f.homepage)
                    }
                }
                writeJSON(fresh, formulaeURL)
                compact = fresh
            } catch {
                // Offline: an old list is better than none.
                guard let stale = readJSON([CompactFormula].self, formulaeURL) else { throw error }
                compact = stale
            }
        }
        return (compact ?? []).map {
            DiscoverEntry(kind: .formula, name: $0.n, title: $0.n, summary: $0.d, version: $0.v, homepage: $0.h)
        }
    }

    // MARK: Popularity

    struct Popularity: Codable, Sendable {
        var casks: [String: Int] = [:]
        var formulae: [String: Int] = [:]
        var caskOrder: [String] = []
        var formulaOrder: [String] = []
    }

    private static var popularityURL: URL { folder.appendingPathComponent("discover-popular.json") }

    /// 30-day install counts. Formulae use installs on request, so libraries
    /// pulled in as dependencies (openssl, ca-certificates) don't top the list.
    /// Best effort: without it Discover still works, just unranked.
    private static func loadPopularity() async -> Popularity {
        if age(of: popularityURL) < day, let cached = readJSON(Popularity.self, popularityURL) { return cached }
        async let casks = counts("https://formulae.brew.sh/api/analytics/cask-install/30d.json", key: "cask")
        async let formulae = counts("https://formulae.brew.sh/api/analytics/install-on-request/30d.json", key: "formula")
        let (c, f) = await (casks, formulae)
        guard !c.isEmpty || !f.isEmpty else { return readJSON(Popularity.self, popularityURL) ?? Popularity() }
        let pop = Popularity(casks: Dictionary(c, uniquingKeysWith: max), formulae: Dictionary(f, uniquingKeysWith: max),
                             caskOrder: c.prefix(300).map(\.0), formulaOrder: f.prefix(300).map(\.0))
        writeJSON(pop, popularityURL)
        return pop
    }

    /// Name and count, most installed first. Counts come as "188,584".
    private static func counts(_ address: String, key: String) async -> [(String, Int)] {
        guard let url = URL(string: address), let json = try? await Net.json(url) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let name = item[key] as? String, !name.contains("/") else { return nil }
            let count = Int((item["count"] as? String ?? "").replacingOccurrences(of: ",", with: "")) ?? 0
            return (name, count)
        }
    }

    // MARK: Recently added

    private struct Known: Codable {
        struct Added: Codable { let id: String; let date: Date }
        var ids: [String] = []
        var added: [Added] = []
    }

    private static var knownURL: URL { folder.appendingPathComponent("discover-known.json") }

    /// Homebrew doesn't publish when something was added, so compare today's
    /// lists with the ones seen last time. Empty until a second list has been
    /// seen. Entries stay for 30 days.
    static func recentlyAdded(casks: [String], formulae: [String], now: Date = Date()) -> [(id: String, date: Date)] {
        let current = casks.map { "cask:\($0)" } + formulae.map { "formula:\($0)" }
        var known = readJSON(Known.self, knownURL) ?? Known()
        let next = diff(known: known, current: current, now: now)
        if next.ids != known.ids || next.added.count != known.added.count {
            writeJSON(next, knownURL)
        }
        known = next
        return known.added.sorted { $0.date > $1.date }.map { ($0.id, $0.date) }
    }

    private static func diff(known: Known, current: [String], now: Date) -> Known {
        var next = known
        if !known.ids.isEmpty {
            let seen = Set(known.ids)
            next.added += current.filter { !seen.contains($0) }.map { Known.Added(id: $0, date: now) }
        }
        let present = Set(current)
        next.added.removeAll { now.timeIntervalSince($0.date) > 30 * day || !present.contains($0.id) }
        next.ids = current.sorted()
        return next
    }

    // MARK: Recently updated

    /// Each entry's version as last seen, and when it was seen to change.
    /// Homebrew doesn't publish update dates, so these fill in over the
    /// days after Discover first loads (Nick, 1 Nov 2026).
    private struct Versions: Codable {
        var versions: [String: String] = [:]
        var changed: [String: Date] = [:]
    }

    private static var versionsURL: URL { folder.appendingPathComponent("discover-versions.json") }

    /// Entry id → when its version last changed.
    static func versionChanges(_ entries: [DiscoverEntry], now: Date = Date()) -> [String: Date] {
        let old = readJSON(Versions.self, versionsURL) ?? Versions()
        let next = trackVersions(old, current: entries.map { ($0.id, $0.version) }, now: now)
        if next.versions != old.versions { writeJSON(next, versionsURL) }
        return next.changed
    }

    /// Entries no longer listed drop out; a first sighting has no date.
    private static func trackVersions(_ old: Versions, current: [(String, String)], now: Date) -> Versions {
        var next = Versions()
        next.versions.reserveCapacity(current.count)
        for (id, version) in current {
            next.versions[id] = version
            if let before = old.versions[id], before != version { next.changed[id] = now }
            else if let date = old.changed[id] { next.changed[id] = date }
        }
        return next
    }

    // MARK: Files

    private static func age(of url: URL) -> TimeInterval {
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return modified.map { Date().timeIntervalSince($0) } ?? .infinity
    }

    private static func readJSON<T: Decodable>(_ type: T.Type, _ url: URL) -> T? {
        FileManager.default.contents(atPath: url.path).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func writeJSON<T: Encodable>(_ value: T, _ url: URL) {
        try? JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
}

extension DiscoverCatalog {
    /// For tests: the recently-added bookkeeping without touching disk.
    static func testDiff(knownIDs: [String], added: [(String, Date)], current: [String], now: Date) -> [String] {
        let known = Known(ids: knownIDs, added: added.map { Known.Added(id: $0.0, date: $0.1) })
        return diff(known: known, current: current, now: now).added.map(\.id)
    }

    /// For tests: version tracking without touching disk.
    static func testTrackVersions(old: [String: String], changed: [String: Date],
                                  current: [(String, String)], now: Date) -> [String: Date] {
        trackVersions(Versions(versions: old, changed: changed), current: current, now: now).changed
    }
}
