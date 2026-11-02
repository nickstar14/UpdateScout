import Foundation

/// Discover's state. Nothing is fetched until the page first opens; it then
/// lives for the session, so switching pages keeps the results.
@MainActor
final class DiscoverModel: ObservableObject {
    static let shared = DiscoverModel()

    enum Chip: String, CaseIterable, Identifiable {
        case all, apps, cli, python, node, rust, ruby, editors, runtimes, fonts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .apps: "Apps"
            case .cli: "Command line"
            case .python: "Python"
            case .node: "Node"
            case .rust: "Rust"
            case .ruby: "Ruby"
            case .editors: "Editor extensions"
            case .runtimes: "Runtimes"
            case .fonts: "Fonts"
            }
        }
        /// The update source a chip belongs to; switched off there, it's hidden here.
        var sourceID: String {
            switch self {
            case .all, .apps, .cli, .runtimes, .fonts: "homebrew"
            case .python: "pip"
            case .node: "npm"
            case .rust: "cargo"
            case .ruby: "gem"
            case .editors: "editors"
            }
        }
    }

    /// The live registries, each searched and failing on its own.
    enum Registry: String, CaseIterable, Identifiable {
        case npm, crates, gems, pypi, extensions
        var id: String { rawValue }
        var title: String {
            switch self {
            case .npm: "npm"
            case .crates: "crates.io (Rust)"
            case .gems: "RubyGems"
            case .pypi: "PyPI (Python)"
            case .extensions: "Editor extensions"
            }
        }
        var sectionID: String {
            switch self {
            case .npm: "npm"
            case .crates: "cargo"
            case .gems: "gem"
            case .pypi: "pip"
            case .extensions: "editors"
            }
        }
        var chip: Chip {
            switch self {
            case .npm: .node
            case .crates: .rust
            case .gems: .ruby
            case .pypi: .python
            case .extensions: .editors
            }
        }
    }

    /// Discover's Sort menu (Phase 10). Remembered.
    enum Sort: String, CaseIterable, Identifiable {
        case popular, name, newest, updated
        var id: String { rawValue }
        var title: String {
            switch self {
            case .popular: "Popular"
            case .name: "Name"
            case .newest: "Newest"
            case .updated: "Recently updated"
            }
        }

        /// The order shown, for the direction button's tooltip.
        func order(reversed: Bool) -> String {
            switch self {
            case .popular: reversed ? "Least popular first" : "Most popular first"
            case .name: reversed ? "Z to A" : "A to Z"
            case .newest: reversed ? "Oldest first" : "Newest first"
            case .updated: reversed ? "Least recently updated first" : "Most recently updated first"
            }
        }
    }

    @Published var sort = Sort(rawValue: UserDefaults.standard.string(forKey: "discoverSort") ?? "") ?? .popular {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "discoverSort") }
    }
    @Published var reversed = UserDefaults.standard.bool(forKey: "discoverSortReversed") {
        didSet { UserDefaults.standard.set(reversed, forKey: "discoverSortReversed") }
    }
    @Published var layout = CardLayout(rawValue: UserDefaults.standard.string(forKey: "discoverLayout") ?? "") ?? .cards {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: "discoverLayout") }
    }

    @Published var query = "" { didSet { if query != oldValue { scheduleSearch() } } }
    @Published var chip: Chip = .all { didSet { if chip != oldValue { scheduleSearch(delay: 0) } } }
    @Published var category: DiscoverCategories.Category?
    /// The sidebar's "New" entry: Recently added only.
    @Published var onlyNew = false
    /// Apps in each category, for the sidebar's counts.
    @Published private(set) var categoryCounts: [DiscoverCategories.Category: Int] = [:]
    /// Each app's category, worked out once per catalogue (the guess runs a
    /// few regexes per cask). Freed with the catalogue.
    private var categoryOf: [String: DiscoverCategories.Category] = [:]

    @Published private(set) var snapshot: DiscoverCatalog.Snapshot? { didSet { indexCategories() } }
    @Published private(set) var loadingCatalog = false
    @Published private(set) var catalogError: String?

    @Published private(set) var live: [Registry: [DiscoverEntry]] = [:]
    @Published private(set) var liveErrors: [Registry: String] = [:]
    @Published private(set) var liveNotes: [Registry: String] = [:]
    @Published private(set) var searching: Set<Registry> = []
    /// Curated Python list, with versions filled in once looked up.
    @Published private(set) var python = DiscoverRegistries.curatedPythonEntries

    private var cache: [String: (entries: [DiscoverEntry], note: String?)] = [:]
    private var searchTask: Task<Void, Never>?
    private var pythonLoaded = false

    var chips: [Chip] { Chip.allCases.filter { !Prefs.disabledSources.contains($0.sourceID) } }

    /// Where the sidebar has Discover: each entry sets the chip and category.
    enum Spot: Hashable {
        case featured, new, category(DiscoverCategories.Category), chip(Chip)
    }

    var spot: Spot {
        switch chip {
        case .all: onlyNew ? .new : .featured
        case .apps: category.map(Spot.category) ?? .featured
        default: .chip(chip)
        }
    }

    func show(_ spot: Spot) {
        switch spot {
        case .featured: chip = .all; category = nil; onlyNew = false
        case .new: chip = .all; category = nil; onlyNew = true
        case .category(let c): chip = .apps; category = c; onlyNew = false
        case .chip(let c): chip = c; category = nil; onlyNew = false
        }
    }

    private func indexCategories() {
        var index: [String: DiscoverCategories.Category] = [:]
        var counts: [DiscoverCategories.Category: Int] = [:]
        for e in snapshot?.entries ?? [] where e.kind == .cask && !e.isFont {
            if let c = DiscoverCategories.category(of: e) { index[e.name] = c; counts[c, default: 0] += 1 }
        }
        categoryOf = index
        categoryCounts = counts
    }

    /// First open of the page.
    func start() {
        guard snapshot == nil, !loadingCatalog else { return }
        reloadCatalog()
    }

    /// Shows the lists already on disk straight away, then refreshes them in
    /// the background when they're over a day old and swaps the new ones in.
    /// Only the very first load waits on the download.
    func reloadCatalog() {
        loadingCatalog = true
        catalogError = nil
        Task {
            if snapshot == nil, let cached = await DiscoverCatalog.cached() {
                snapshot = cached
                if DiscoverCatalog.isFresh { loadingCatalog = false; return }
            }
            do { snapshot = try await DiscoverCatalog.load() }
            catch where snapshot != nil { /* keep showing the older lists */ }
            catch { catalogError = "Homebrew's lists couldn't be loaded: \(error.localizedDescription)" }
            loadingCatalog = false
        }
    }

    func loadPythonVersions() {
        guard !pythonLoaded else { return }
        pythonLoaded = true
        Task {
            await withTaskGroup(of: (String, String)?.self) { group in
                for entry in python {
                    group.addTask {
                        guard let version = await PythonSource.pypiLatest(entry.name) else { return nil }
                        return (entry.name, version)
                    }
                }
                for await pair in group {
                    if let pair, let i = python.firstIndex(where: { $0.name == pair.0 }) { python[i].version = pair.1 }
                }
            }
        }
    }

    // MARK: Homebrew, searched locally

    /// Homebrew entries for the current chip and category.
    private var scoped: [DiscoverEntry] {
        guard let entries = snapshot?.entries else { return [] }
        switch chip {
        case .all: return entries
        case .apps:
            return entries.filter { e in
                e.kind == .cask && !e.isFont
                    && (category == nil || categoryOf[e.name] == category)
            }
        case .cli: return entries.filter { $0.kind == .formula && !$0.isRuntime }
        case .runtimes: return entries.filter(\.isRuntime)
        case .fonts: return entries.filter(\.isFont)
        default: return []
        }
    }

    var homebrewResults: [DiscoverEntry] {
        DiscoverCatalog.search(query, in: scoped)
    }

    /// What a part shows before anything is typed, in the chosen order.
    /// Featured and New are fixed sets sorted among themselves; the other
    /// parts sort their whole list and show the first 80.
    var browse: [DiscoverEntry] {
        guard let snap = snapshot else { return [] }
        switch spot {
        case .featured: return Self.sorted(snap.popularCasks.filter { !$0.isFont }.prefix(60).map { $0 }, by: sort, reversed: reversed)
        case .new: return Self.sorted(snap.recent.prefix(80).map { $0 }, by: sort, reversed: reversed)
        default: return Array(Self.sorted(scoped, by: sort, reversed: reversed).prefix(80))
        }
    }

    /// Search results in the chosen order. Popular keeps the best matches
    /// first, as each search already ranks them.
    func ordered(_ results: [DiscoverEntry]) -> [DiscoverEntry] {
        if sort == .popular { return reversed ? results.reversed() : results }
        return Self.sorted(results, by: sort, reversed: reversed)
    }

    /// Popular: most installs or downloads. Name: A to Z. Newest and
    /// Recently updated: latest date first; undated ones after, most popular
    /// first. Reversed flips the order; undated ones stay last either way.
    nonisolated static func sorted(_ entries: [DiscoverEntry], by sort: Sort, reversed: Bool = false) -> [DiscoverEntry] {
        let ordered = sorted(entries, by: sort)
        guard reversed else { return ordered }
        let date: (DiscoverEntry) -> Date? = { sort == .newest ? $0.added : sort == .updated ? $0.updated : nil }
        if sort == .newest || sort == .updated {
            return ordered.filter { date($0) != nil }.reversed() + ordered.filter { date($0) == nil }
        }
        return ordered.reversed()
    }

    private nonisolated static func sorted(_ entries: [DiscoverEntry], by sort: Sort) -> [DiscoverEntry] {
        func byPopularity(_ a: DiscoverEntry, _ b: DiscoverEntry) -> Bool {
            a.popularity != b.popularity ? a.popularity > b.popularity
                : a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        func byDate(_ a: Date?, _ b: Date?, _ x: DiscoverEntry, _ y: DiscoverEntry) -> Bool {
            switch (a, b) {
            case let (a?, b?) where a != b: a > b
            case (_?, nil): true
            case (nil, _?): false
            default: byPopularity(x, y)
            }
        }
        switch sort {
        case .popular: return entries.sorted(by: byPopularity)
        case .name: return entries.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .newest: return entries.sorted { byDate($0.added, $1.added, $0, $1) }
        case .updated: return entries.sorted { byDate($0.updated, $1.updated, $0, $1) }
        }
    }

    /// The category an app is listed under, if any.
    func category(of entry: DiscoverEntry) -> DiscoverCategories.Category? {
        entry.kind == .cask ? categoryOf[entry.name] : nil
    }

    /// The window title: "Discover" on Featured, "Discover · Browsers" elsewhere.
    var title: String {
        switch spot {
        case .featured: "Discover"
        case .new: "Discover · New"
        case .category(let c): "Discover · \(c.rawValue)"
        case .chip(let c): "Discover · \(c.title)"
        }
    }

    /// The subtitle under the title. While searching, it says where.
    var subtitle: String {
        let text = query.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            switch spot {
            case .featured, .new: return "Results for “\(text)” from every source"
            case .category(let c): return "Results for “\(text)” in \(c.rawValue)"
            case .chip(let c): return "Results for “\(text)” in \(c.title)"
            }
        }
        switch spot {
        case .featured: return "Popular this month"
        case .new: return "Added in the last 30 days"
        case .category(let c): return "\(categoryCounts[c] ?? 0) apps"
        case .chip(let c):
            switch c {
            case .cli, .runtimes: return "\(scoped.count.formatted()) tools"
            case .fonts: return "\(scoped.count.formatted()) fonts"
            case .python: return "Searches PyPI. Apps install with pipx."
            case .node: return "Searches npm. Packages install globally."
            case .rust: return "Searches crates.io. Crates install with cargo."
            case .ruby: return "Searches RubyGems. Gems install with Homebrew's Ruby."
            case .editors: return "Searches the VS Code and Open VSX stores."
            default: return ""
            }
        }
    }

    // MARK: Live registries

    /// The registries the current chip searches as you type.
    var activeRegistries: [Registry] {
        let all: [Registry] = chip == .all ? Registry.allCases : Registry.allCases.filter { $0.chip == chip }
        return all.filter { !Prefs.disabledSources.contains($0.sectionID) }
    }

    private func scheduleSearch(delay: Double = 0.4) {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        let registries = activeRegistries
        guard text.count >= 2, !registries.isEmpty else {
            live = [:]; liveErrors = [:]; liveNotes = [:]; searching = []
            return
        }
        searchTask = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            live = [:]; liveErrors = [:]; liveNotes = [:]
            searching = Set(registries)
            await withTaskGroup(of: Void.self) { group in
                for registry in registries {
                    group.addTask { await self.search(registry, text) }
                }
            }
        }
    }

    private func search(_ registry: Registry, _ text: String) async {
        let key = "\(registry.rawValue)|\(text.lowercased())"
        if let hit = cache[key] {
            finish(registry, text, hit.entries, note: hit.note, error: nil)
            return
        }
        do {
            let result: (entries: [DiscoverEntry], note: String?)
            switch registry {
            case .npm: result = (try await DiscoverRegistries.npm(text), nil)
            case .crates: result = (try await DiscoverRegistries.crates(text), nil)
            case .gems: result = (try await DiscoverRegistries.gems(text), nil)
            case .pypi: result = (try await DiscoverRegistries.pypi(text).map { [$0] } ?? [], nil)
            case .extensions: result = try await DiscoverRegistries.extensions(text)
            }
            cache[key] = result
            finish(registry, text, result.entries, note: result.note, error: nil)
        } catch {
            finish(registry, text, [], note: nil, error: error.localizedDescription)
        }
    }

    private func finish(_ registry: Registry, _ text: String, _ entries: [DiscoverEntry], note: String?, error: String?) {
        // A slower answer for older text is dropped.
        guard text == query.trimmingCharacters(in: .whitespaces) else { return }
        live[registry] = entries
        liveNotes[registry] = note
        liveErrors[registry] = error
        searching.remove(registry)
    }
}
