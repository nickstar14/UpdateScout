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

    /// What a chip shows before anything is typed.
    var browse: [DiscoverEntry] {
        guard let snap = snapshot else { return [] }
        switch chip {
        case .apps:
            if category != nil { return scoped.sorted { $0.popularity > $1.popularity }.prefix(80).map { $0 } }
            return snap.popularCasks.filter { !$0.isFont }.prefix(60).map { $0 }
        case .cli: return snap.popularFormulae.filter { !$0.isRuntime }.prefix(60).map { $0 }
        case .runtimes, .fonts: return scoped.sorted { $0.popularity > $1.popularity }.prefix(60).map { $0 }
        default: return []
        }
    }

    /// Popular this month for the All page: apps and command line tools in turn.
    var popular: [DiscoverEntry] {
        guard let snap = snapshot else { return [] }
        let casks = snap.popularCasks.filter { !$0.isFont }.prefix(12)
        let formulae = snap.popularFormulae.prefix(12)
        return zip(casks, formulae).flatMap { [$0, $1] }
    }

    var recent: [DiscoverEntry] { Array((snapshot?.recent ?? []).prefix(24)) }

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
