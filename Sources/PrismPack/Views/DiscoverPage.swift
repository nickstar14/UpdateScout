import SwiftUI
import AppKit

/// Discover: search and install apps and tools from Homebrew, npm, PyPI,
/// crates.io, RubyGems and the editor extension stores. Never the App Store
/// or macOS updates.
struct DiscoverPage: View {
    @EnvironmentObject var controller: UpdateController
    @ObservedObject private var model = DiscoverModel.shared

    private var searchingText: Bool { !model.query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if let error = model.catalogError, usesHomebrew {
                    errorLine(error) { model.reloadCatalog() }
                }
                if model.chip == .fonts {
                    hint("Previews come from Google Fonts and aren't installed. Fonts that aren't there show their name only.")
                }
                if searchingText { results } else { home }
            }
            .padding([.horizontal, .bottom], 16)
            .padding(.top, 4)
            // Cards / List fades like moving between pages.
            .id(model.layout)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.14), value: model.layout)
        // The controls stay put; the cards scroll under them in glass.
        .pinnedHeader {
            PageControls {
                HStack(spacing: 8) {
                    GlassSearchField(prompt: "Search apps, command line tools and packages", text: $model.query)
                    SortMenu(selection: $model.sort, options: DiscoverModel.Sort.allCases.map { ($0, $0.title) })
                    SortDirectionButton(reversed: $model.reversed, order: model.sort.order(reversed: model.reversed))
                    LayoutSwitch(layout: $model.layout)
                }
                UpdatesReminder()
            }
        }
        .navigationSubtitle(model.subtitle)
        .onAppear {
            model.start()
            if controller.installed.isEmpty { controller.loadInstalled() }
        }
        .onChange(of: model.chip) { _, chip in
            if chip == .python { model.loadPythonVersions() }
            if chip != .fonts { FontPreviews.shared.releaseAll() }
        }
        // Only when the page is really left: moving between Discover's parts
        // builds the page again, and its old copy disappears after the new one.
        .onDisappear { if controller.page != .discover { FontPreviews.shared.releaseAll() } }
    }

    private var usesHomebrew: Bool { [.all, .apps, .cli, .runtimes, .fonts].contains(model.chip) }

    // MARK: Before typing

    @ViewBuilder
    private var home: some View {
        switch model.spot {
        case .new where model.snapshot != nil && model.browse.isEmpty:
            hint("New apps and tools show here once \(AppIdentity.name) has seen Homebrew's list change, usually after a day or two.")
        case .chip(.python):
            hint("PyPI can't be searched, so here are some popular command line apps. Type a package's exact name to find any other.")
            items(model.ordered(model.python))
        case .chip(let chip) where [.node, .rust, .ruby, .editors].contains(chip):
            hint(searchHint(chip))
        default:
            if model.snapshot == nil && model.loadingCatalog {
                loading("Loading Homebrew's lists…")
            } else {
                items(model.browse)
            }
        }
    }

    private func searchHint(_ chip: DiscoverModel.Chip) -> String {
        switch chip {
        case .node: "Type to search npm."
        case .rust: "Type to search crates.io. cargo builds crates from source, which can take a few minutes."
        case .ruby: "Type to search RubyGems. \(AppIdentity.name) never uses the Ruby built into macOS."
        default: "Type to search for extensions for VS Code, VSCodium and Cursor."
        }
    }

    // MARK: After typing

    /// One section per source (Nick, 1 Nov 2026), each in the chosen order.
    @ViewBuilder
    private var results: some View {
        if usesHomebrew {
            if model.snapshot == nil && model.loadingCatalog {
                loading("Loading Homebrew's lists…")
            } else {
                let found = model.ordered(model.homebrewResults)
                if !found.isEmpty || model.chip != .all { group("Homebrew", found, empty: "Nothing in Homebrew matches.") }
            }
        }
        if model.chip == .python {
            let text = model.query.lowercased()
            let curated = model.python.filter { $0.name.contains(text) || ($0.summary ?? "").lowercased().contains(text) }
            if !curated.isEmpty { group("Popular Python apps", model.ordered(curated), sectionID: "pip") }
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
                group(registry.title, model.ordered(entries), sectionID: registry.sectionID,
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
                items(entries)
            }
        }
    }

    /// Cards or a list.
    @ViewBuilder
    private func items(_ entries: [DiscoverEntry]) -> some View {
        let installed = Dictionary(controller.installed.compactMap { p in p.discoverKey.map { ($0, p) } },
                                   uniquingKeysWith: { first, _ in first })
        if model.layout == .cards {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                ForEach(entries) { entry in
                    DiscoverItem(entry: entry, pkg: installed[entry.installKey], label: label(of: entry), asRow: false)
                }
            }
        } else {
            // Each row on its own glass, like the cards (Nick, 2 Nov 2026).
            LazyVStack(spacing: 6) {
                ForEach(entries) { entry in
                    DiscoverItem(entry: entry, pkg: installed[entry.installKey], label: label(of: entry), asRow: true)
                }
            }
        }
    }

    /// The line under a name, and the card's tint: what it is, in the same
    /// colour as its sidebar dot (Nick, 1 Nov 2026). The source tag and the
    /// Install button keep the source's colour.
    private func label(of entry: DiscoverEntry) -> (text: String, color: Color) {
        if let category = model.category(of: entry) { return (category.rawValue, category.color) }
        let color = SourceStyle.forSource(entry.sectionID).color
        switch entry.kind {
        case .cask where entry.isFont: return ("Font", DiscoverModel.Chip.fonts.color)
        case .cask where entry.isRuntime: return ("Runtime", DiscoverModel.Chip.runtimes.color)
        case .cask: return ("App", color)
        case .formula where entry.isRuntime: return ("Runtime", DiscoverModel.Chip.runtimes.color)
        case .formula: return ("Command line", DiscoverModel.Chip.cli.color)
        case .npm: return ("npm", color)
        case .pypi: return ("PyPI", color)
        case .crate: return ("crates.io", color)
        case .gem: return ("RubyGems", color)
        case .ext: return ("Editor extension", color)
        }
    }

    private func groupHeader(_ title: String, sectionID: String) -> some View {
        HStack(spacing: 6) {
            GlassIconTile(style: SourceStyle.forSource(sectionID), size: 18)
            Text(title).font(.headline)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func loading(_ text: String) -> some View {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text).foregroundStyle(.secondary) }
    }

    private func errorLine(_ text: String, retry: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.orange.readable)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            if let retry { Button("Try Again", action: retry).glass().controlSize(.small) }
        }
    }
}

/// One entry as a card or a list row (Phase 10 mockup). Clicking anywhere
/// but its buttons opens its details.
private struct DiscoverItem: View {
    @EnvironmentObject var controller: UpdateController
    let entry: DiscoverEntry
    /// The installed copy, if any.
    let pkg: InstalledPackage?
    let label: (text: String, color: Color)
    let asRow: Bool
    @State private var showingCard = false
    @Environment(\.colorScheme) private var scheme

    /// The card's tint. Productivity's lemon is fainter in dark.
    private var tint: Color {
        label.color.opacity(scheme == .dark && label.color == Theme.lemon ? 0.18 : 0.35)
    }

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

    /// The same, for the progress line.
    private var progress: InstallProgress? {
        if entry.kind == .ext {
            return EditorExtensionsSource.editors().lazy
                .compactMap { controller.installProgress[DiscoverInstaller.item(for: entry, editorKey: $0.key).id] }.first
        }
        return controller.installProgress[item.id]
    }

    private var installed: Bool { pkg != nil || state == .done }

    /// A waiting update for the installed copy, unless it's hidden.
    private var update: UpdateItem? {
        guard let pkg, let found = controller.update(for: pkg), !controller.isIgnored(found) else { return nil }
        return found
    }

    var body: some View {
        Group {
            if asRow { row } else { card }
        }
        .contentShape(Rectangle())
        .onTapGesture { showingCard = true }
        .popover(isPresented: $showingCard, arrowEdge: .bottom) {
            DiscoverCard(entry: entry, installed: installed, appPath: pkg?.appPath).environmentObject(controller)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                DiscoverIcon(entry: entry)
                nameAndLabel
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) { tags }
            }
            // Always two lines tall, so every card and its buttons line up.
            Group {
                if entry.isFont { FontSample(entry: entry, size: 17).lineLimit(2, reservesSpace: true) }
                else {
                    Text(entry.summary ?? "").font(.callout).foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            Text(versionLine(entry.shortVersion)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Spacer()
                actions
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(SectionPanel(color: tint))
    }

    private var row: some View {
        HStack(spacing: 10) {
            DiscoverIcon(entry: entry, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.title).font(.body.weight(.semibold)).lineLimit(1)
                    Text(label.text).font(.caption).foregroundStyle(label.color.readable).lineLimit(1)
                }
                if entry.isFont { FontSample(entry: entry, size: 13).lineLimit(1) }
                else { Text(entry.summary ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            // Fixed columns, so tags, versions and buttons line up row to row.
            // Installed stacks under the source tag, as on cards, to keep
            // the column narrow.
            VStack(alignment: .trailing, spacing: 3) { tags }.frame(width: 115, alignment: .trailing)
            Text(versionLine(entry.shortVersion)).font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: 120, alignment: .leading)
            actions.frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .modifier(SectionPanel(color: tint))
    }

    private var nameAndLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.title).font(.body.weight(.semibold)).lineLimit(1)
            Text(label.text).font(.caption).foregroundStyle(label.color.readable).lineLimit(1)
        }
    }

    /// What it installs with, always (Nick, 1 Nov 2026), and Installed.
    @ViewBuilder
    private var tags: some View {
        StatusPill.source(entry.sectionID)
        if installed { StatusPill.installed }
    }

    /// Install for new things; Update or Open, plus the trash button, for
    /// installed ones.
    @ViewBuilder
    private var actions: some View {
        if let pkg {
            HStack(spacing: 6) {
                if let update {
                    UpdateAction(item: update, color: style.color)
                } else if let path = pkg.appPath, entry.kind == .cask {
                    Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        .glass().controlSize(.small)
                }
                // Move to Trash lives in the details pop-up (Nick, 2 Nov 2026).
            }
        } else {
            DiscoverAction(entry: entry, installed: false, state: state, progress: progress)
        }
    }
}

/// A card's Update button: the same queue and password batch as the
/// Updates page, with its progress while it runs (Discover and Installed).
struct UpdateAction: View {
    @EnvironmentObject var controller: UpdateController
    let item: UpdateItem
    let color: Color

    var body: some View {
        let state = controller.installStates[item.id]
        if let state, state.isActive {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(state == .queued ? "Queued" : "Updating").font(.caption).foregroundStyle(.secondary)
                    .help(state.label)
            }
        } else {
            Button(state?.errorMessage == nil ? item.actionLabel : "Retry") { controller.requestUpdate(item) }
                .glassProminent(color).controlSize(.small)
        }
    }
}

extension DiscoverModel.Chip {
    /// A part's colour: its sidebar dot, and the tint and label of its
    /// cards. Command line and Runtimes get their own, so Homebrew's brown
    /// isn't everywhere (Nick, 1 Nov 2026); fonts stay grey.
    var color: Color {
        switch self {
        case .fonts: .gray
        case .cli: .mint
        case .runtimes: .purple
        default: SourceStyle.forSource(sourceID).color
        }
    }
}

/// Install, its progress, or the Installed pill.
private struct DiscoverAction: View {
    @EnvironmentObject var controller: UpdateController
    let entry: DiscoverEntry
    let installed: Bool
    let state: InstallState?
    var progress: InstallProgress? = nil
    /// Small on cards; regular in the pop-up, beside its other buttons.
    var size: ControlSize = .small

    private var style: SourceStyle { SourceStyle.forSource(entry.sectionID) }

    var body: some View {
        if let state, state.isActive, state != .queued, state != .needsAdmin, state != .cancelling, let progress {
            InstallProgressView(progress: progress, barWidth: 70)
        } else if let state, state.isActive {
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
            StatusPill.installed
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
            .menuStyle(.button).glassProminent(style.color).controlSize(size).fixedSize()
        } else {
            Button(title) {
                controller.update(DiscoverInstaller.item(for: entry, editorKey: editors.first?.key))
            }
            .glassProminent(style.color).controlSize(size)
            .disabled(entry.kind == .ext && editors.isEmpty)
            .help(entry.kind == .ext && editors.isEmpty ? "Install VS Code, VSCodium or Cursor first." : "")
        }
    }
}

/// The floating card: what it is, where it comes from, and how it installs.
private struct DiscoverCard: View {
    @EnvironmentObject var controller: UpdateController
    @Environment(\.dismiss) private var dismiss
    let entry: DiscoverEntry
    let installed: Bool
    /// The installed app, so the main button is Open, as on Installed.
    var appPath: String? = nil

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
            if !entry.isFont { WebDetailsSection(entry: entry) }
            if !entry.version.isEmpty { LabeledContent("Version", value: entry.shortVersion) }
            if let note { Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary) }
            if entry.isFont, let family = FontPreviewName.family(forCask: entry.name, title: entry.title) {
                FontStylesSection(family: family)
            }
            // As on every details pop-up: helpers left, Move to Trash in red
            // and the main action right, one size; close is the circle.
            HStack(spacing: 8) {
                if let page = entry.homepage.flatMap(URL.init(string:)) {
                    Button("Website") { NSWorkspace.shared.open(page) }.glass()
                }
                Spacer()
                let state = controller.installStates[DiscoverInstaller.item(for: entry).id]
                if installed || state == .done {
                    UninstallButton(removal: Removal(entry))
                }
                if let appPath, installed {
                    Button("Open") { dismiss(); NSWorkspace.shared.open(URL(fileURLWithPath: appPath)) }
                        .glassProminent(SourceStyle.forSource(entry.sectionID).color)
                } else {
                    DiscoverAction(entry: entry, installed: installed, state: state,
                                   progress: controller.installProgress[DiscoverInstaller.item(for: entry).id], size: .regular)
                }
            }
        }
        .padding(18)
        .frame(width: 540)
        .popupClose()
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
