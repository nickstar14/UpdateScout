import SwiftUI
import AppKit

/// Discover: search and install apps and tools from Homebrew, npm, PyPI,
/// crates.io, RubyGems and the editor extension stores. Never the App Store
/// or macOS updates.
struct DiscoverPage: View {
    @EnvironmentObject var controller: UpdateController
    @ObservedObject private var model = DiscoverModel.shared

    private var installedKeys: Set<String> { Set(controller.installed.compactMap(\.discoverKey)) }
    private var searchingText: Bool { !model.query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let error = model.catalogError, usesHomebrew {
                    errorLine(error) { model.reloadCatalog() }
                }
                if searchingText { results } else { home }
            }
            .padding([.horizontal, .bottom], 16)
            .padding(.top, 4)
        }
        // Search and chips stay put; the tiles scroll under them in glass.
        .pinnedHeader {
            VStack(alignment: .leading, spacing: 10) {
                GlassSearchField(prompt: "Search apps, command line tools and packages", text: $model.query)
                chipRow
                if model.chip == .apps { categoryRow }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        }
        .navigationSubtitle("Apps and tools from Homebrew, pip, npm and more")
        .onAppear {
            model.start()
            if controller.installed.isEmpty { controller.loadInstalled() }
        }
        .onChange(of: model.chip) { _, chip in if chip == .python { model.loadPythonVersions() } }
    }

    private var usesHomebrew: Bool { [.all, .apps, .cli, .runtimes, .fonts].contains(model.chip) }

    // The chips wrap rather than scroll, so none hide past the edge.
    private var chipRow: some View {
        ChipFlow(spacing: 6) {
            ForEach(model.chips) { chip in
                ChipButton(title: chip.title, selected: model.chip == chip, size: .small) {
                    model.chip = chip; model.category = nil
                }
            }
        }
    }

    private var categoryRow: some View {
        ChipFlow(spacing: 6) {
            ChipButton(title: "Every app", selected: model.category == nil, size: .mini) { model.category = nil }
            ForEach(DiscoverCategories.Category.allCases) { category in
                ChipButton(title: category.rawValue, selected: model.category == category, size: .mini) {
                    model.category = category
                }
            }
        }
    }

    // MARK: Before typing

    @ViewBuilder
    private var home: some View {
        switch model.chip {
        case .all:
            if model.snapshot == nil && model.loadingCatalog {
                loading("Loading Homebrew's lists…")
            } else {
                group("Popular this month", model.popular)
                if model.recent.isEmpty {
                    hint("Recently added", "New apps and tools show here once \(AppIdentity.name) has seen Homebrew's list change, usually after a day or two.")
                } else {
                    group("Recently added", model.recent)
                }
            }
        case .python:
            hint(nil, "PyPI can't be searched, so here are some popular command line apps. Type a package's exact name to find any other. Python apps install with pipx.")
            group("Popular Python apps", model.python)
        case .node, .rust, .ruby, .editors:
            hint(nil, searchHint(model.chip))
        default:
            if model.snapshot == nil && model.loadingCatalog {
                loading("Loading Homebrew's lists…")
            } else {
                group(model.category.map { "Popular in \($0.rawValue)" } ?? "Popular this month", model.browse)
            }
        }
    }

    private func searchHint(_ chip: DiscoverModel.Chip) -> String {
        switch chip {
        case .node: "Type to search npm. Packages install globally with npm."
        case .rust: "Type to search crates.io. Crates install with cargo, which builds them from source and can take a few minutes."
        case .ruby: "Type to search RubyGems. Gems install with Homebrew's Ruby, never the Ruby built into macOS."
        default: "Type to search for extensions for VS Code, VSCodium and Cursor."
        }
    }

    // MARK: After typing

    @ViewBuilder
    private var results: some View {
        if usesHomebrew {
            if model.snapshot == nil && model.loadingCatalog {
                loading("Loading Homebrew's lists…")
            } else {
                let found = model.homebrewResults
                if !found.isEmpty || model.chip != .all { group("Homebrew", found, empty: "Nothing in Homebrew matches.") }
            }
        }
        if model.chip == .python {
            let text = model.query.lowercased()
            let curated = model.python.filter { $0.name.contains(text) || ($0.summary ?? "").lowercased().contains(text) }
            if !curated.isEmpty { group("Popular Python apps", curated) }
        }
        ForEach(model.activeRegistries) { registry in
            registryGroup(registry)
        }
    }

    @ViewBuilder
    private func registryGroup(_ registry: DiscoverModel.Registry) -> some View {
        let all = model.live[registry] ?? []
        // PyPI's exact match may repeat a curated entry; it's dropped here,
        // and so is the group, rather than claiming PyPI has no such package.
        let entries = all.filter { e in
            !(registry == .pypi && model.chip == .python && model.python.contains { $0.name.lowercased() == e.name.lowercased() })
        }
        let onlyRepeats = !all.isEmpty && entries.isEmpty
        if model.searching.contains(registry) {
            VStack(alignment: .leading, spacing: 6) {
                groupHeader(registry.title, sectionID: registry.sectionID)
                ProgressView().controlSize(.small)
            }
        } else if let error = model.liveErrors[registry] {
            VStack(alignment: .leading, spacing: 6) {
                groupHeader(registry.title, sectionID: registry.sectionID)
                errorLine("\(registry.title) didn't answer: \(error)", retry: nil)
            }
        } else if !onlyRepeats, !entries.isEmpty || model.chip != .all {
            VStack(alignment: .leading, spacing: 6) {
                if let note = model.liveNotes[registry] {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                group(registry.title, entries, sectionID: registry.sectionID,
                      empty: registry == .pypi ? "PyPI has no package with exactly that name." : "No matches.")
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func group(_ title: String, _ entries: [DiscoverEntry], sectionID: String = "homebrew",
                       empty: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            groupHeader(title, sectionID: sectionID)
            if entries.isEmpty {
                if let empty { Text(empty).font(.callout).foregroundStyle(.secondary) }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                    ForEach(entries) { entry in
                        DiscoverTile(entry: entry, installed: installedKeys.contains(entry.installKey))
                    }
                }
            }
        }
    }

    private func groupHeader(_ title: String, sectionID: String) -> some View {
        HStack(spacing: 6) {
            GlassIconTile(style: SourceStyle.forSource(sectionID), size: 18)
            Text(title).font(.headline)
        }
    }

    private func hint(_ title: String?, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title { Text(title).font(.headline) }
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loading(_ text: String) -> some View {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text).foregroundStyle(.secondary) }
    }

    private func errorLine(_ text: String, retry: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let retry { Button("Try Again", action: retry).glass().controlSize(.small) }
        }
    }
}

/// One result: icon, name, description with its source tag, and Install or
/// an Installed pill. Clicking the icon or name opens its card.
private struct DiscoverTile: View {
    @EnvironmentObject var controller: UpdateController
    let entry: DiscoverEntry
    let installed: Bool
    @State private var showingCard = false

    private var item: UpdateItem { DiscoverInstaller.item(for: entry) }
    private var style: SourceStyle { SourceStyle.forSource(entry.sectionID) }

    /// Install state across every editor an extension can go into.
    private var state: InstallState? {
        if entry.kind == .ext {
            return EditorExtensionsSource.editors().lazy
                .compactMap { controller.installStates[DiscoverInstaller.item(for: entry, editorKey: $0.key).id] }.first
        }
        return controller.installStates[item.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { showingCard = true } label: {
                HStack(spacing: 10) {
                    DiscoverIcon(entry: entry)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title).font(.body.weight(.semibold)).lineLimit(1)
                        Text([entry.summary, entry.tag].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingCard, arrowEdge: .bottom) {
                DiscoverCard(entry: entry, installed: installed).environmentObject(controller)
            }
            HStack {
                Spacer()
                DiscoverAction(entry: entry, installed: installed, state: state)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(SectionPanel(color: style.color.opacity(0.35)))
    }
}

/// Install, its progress, or the Installed pill.
private struct DiscoverAction: View {
    @EnvironmentObject var controller: UpdateController
    let entry: DiscoverEntry
    let installed: Bool
    let state: InstallState?

    private var style: SourceStyle { SourceStyle.forSource(entry.sectionID) }

    var body: some View {
        if let state, state.isActive {
            HStack(spacing: 6) {
                if case .downloading(let percent?, _) = state {
                    ProgressView(value: Double(percent), total: 100).frame(width: 70)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(state == .queued ? "Queued" : "Installing").font(.caption).foregroundStyle(.secondary)
                    .help(state.label)
            }
        } else if installed || state == .done {
            StatusPill(text: "Installed", color: .green)
        } else {
            HStack(spacing: 6) {
                if let error = state?.errorMessage {
                    StatusPill(text: error == "Needs admin" ? "Needs admin" : "Failed",
                               color: error == "Needs admin" ? .orange : .red).help(error)
                }
                installButton(title: state?.errorMessage == nil ? "Install" : "Retry")
            }
        }
    }

    @ViewBuilder
    private func installButton(title: String) -> some View {
        let editors = entry.kind == .ext ? EditorExtensionsSource.editors() : []
        if editors.count > 1 {
            Menu(title) {
                ForEach(editors, id: \.key) { editor in
                    Button("Install in \(editor.name)") {
                        controller.update(DiscoverInstaller.item(for: entry, editorKey: editor.key))
                    }
                }
            }
            .menuStyle(.button).glassProminent(style.color).controlSize(.small).fixedSize()
        } else {
            Button(title) {
                controller.update(DiscoverInstaller.item(for: entry, editorKey: editors.first?.key))
            }
            .glassProminent(style.color).controlSize(.small)
            .disabled(entry.kind == .ext && editors.isEmpty)
            .help(entry.kind == .ext && editors.isEmpty ? "Install VS Code, VSCodium or Cursor first." : "")
        }
    }
}

/// The floating card: what it is, where it comes from, and how it installs.
private struct DiscoverCard: View {
    @EnvironmentObject var controller: UpdateController
    let entry: DiscoverEntry
    let installed: Bool

    private var source: String {
        switch entry.kind {
        case .cask: "Homebrew app (cask \(entry.name))"
        case .formula: "Homebrew command line tool (formula)"
        case .npm: "npm package, installed globally"
        case .pypi: "Python app from PyPI, installed with pipx"
        case .crate: "Rust crate, installed with cargo"
        case .gem: "Ruby gem, installed with Homebrew's Ruby"
        case .ext: "Editor extension"
        }
    }

    /// What to know before installing, in plain words.
    private var note: String? {
        switch entry.kind {
        case .crate: "cargo builds crates from source, which can take a few minutes."
        case .gem where GemSource.gem == nil: "Needs Ruby from Homebrew first. \(AppIdentity.name) never uses the Ruby built into macOS."
        case .pypi where Shell.which("pipx") == nil: "Needs pipx first (the pipx formula in Homebrew)."
        case .npm where Shell.which("npm") == nil: "Needs Node first (the node formula in Homebrew)."
        case .crate where Shell.which("cargo") == nil: "Needs Rust first (the rust formula in Homebrew)."
        case .ext where EditorExtensionsSource.editors().isEmpty: "Needs VS Code, VSCodium or Cursor."
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DiscoverIcon(entry: entry, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.title3).bold()
                    Text(source).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let summary = entry.summary { Text(summary).fixedSize(horizontal: false, vertical: true) }
            if !entry.version.isEmpty { LabeledContent("Latest version", value: entry.version) }
            if entry.popularity > 0 {
                LabeledContent(entry.kind == .cask || entry.kind == .formula ? "Installs, last 30 days" : "Downloads",
                               value: entry.popularity.formatted())
            }
            if let note { Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
            HStack {
                if let page = entry.homepage.flatMap(URL.init(string:)) {
                    Button("Website") { NSWorkspace.shared.open(page) }.glass()
                }
                Spacer()
                let state = controller.installStates[DiscoverInstaller.item(for: entry).id]
                if installed || state == .done { UninstallButton(removal: Removal(entry)) }
                DiscoverAction(entry: entry, installed: installed, state: state)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

/// A filter chip: filled when selected. A bordered button's tint doesn't
/// show on macOS 27, so selection switches the style instead.
struct ChipButton: View {
    let title: String
    let selected: Bool
    let size: ControlSize
    let action: () -> Void

    var body: some View {
        if selected {
            Button(title, action: action).buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule).controlSize(size)
        } else {
            Button(title, action: action).buttonStyle(.bordered)
                .buttonBorderShape(.capsule).controlSize(size)
        }
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                let next = row.y + row.height + spacing
                rows.append(row)
                row = Row(y: next)
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// A tile's icon: the app's own or its website's (`DiscoverIcons`), loaded
/// when the tile appears; the usual letter or section tile until then.
private struct DiscoverIcon: View {
    let entry: DiscoverEntry
    var size: CGFloat = 32
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.9, height: size * 0.9)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                    .frame(width: size, height: size)
            } else {
                RowIcon(name: entry.title, appPath: nil, sectionID: entry.sectionID, size: size)
            }
        }
        .task(id: entry.id) {
            if let local = DiscoverIcons.installedIcon(for: entry) { image = local; return }
            image = await DiscoverIcons.shared.icon(for: entry)
        }
    }
}
