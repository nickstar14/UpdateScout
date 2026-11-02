import SwiftUI
import AppKit

/// Every installed item across sources (Phase 10): search, a Show switch,
/// a Source menu, Sort with its direction, and Cards or List.
struct InstalledPage: View {
    @EnvironmentObject var controller: UpdateController
    @ObservedObject private var metrics = InstalledMetrics.shared
    @State private var filter = ""
    @AppStorage("installedShow") private var show = "all"
    @AppStorage("installedSource") private var source = ""
    @AppStorage("installedSort") private var sort = "name"
    @AppStorage("installedSortReversed") private var reversed = false
    @AppStorage("installedLayout") private var layout = CardLayout.cards

    private var shows: [(value: String, label: String)] {
        [("all", "All"), ("updates", "Updates"), ("ignored", "Hidden")]
            + (controller.duplicates.isEmpty ? [] : [("duplicates", "Duplicates")])
    }

    /// Every installation type present, for the Source menu.
    private var sources: [(value: String, title: String)] {
        let present = Set(controller.installed.map(\.sourceID))
        return [("", "All sources")]
            + UpdatesPage.order.filter(present.contains).map { ($0, UpdatesPage.title(of: $0)) }
            + (present.contains("unmanaged") ? [("unmanaged", "Not managed")] : [])
    }

    private static let sorts = [("name", "Name"), ("size", "Size"), ("date", "Date installed"), ("type", "Installation type")]

    private var order: String {
        switch sort {
        case "size": reversed ? "Smallest first" : "Largest first"
        case "date": reversed ? "Oldest first" : "Newest first"
        case "type": reversed ? "Installation type, Z to A" : "Installation type, A to Z"
        default: reversed ? "Z to A" : "A to Z"
        }
    }

    private func update(for pkg: InstalledPackage) -> UpdateItem? { controller.update(for: pkg) }

    private var shown: [InstalledPackage] {
        let list = controller.installed.filter { pkg in
            if !filter.isEmpty, !pkg.name.localizedCaseInsensitiveContains(filter) { return false }
            if !source.isEmpty, pkg.sourceID != source { return false }
            let item = update(for: pkg)
            switch show {
            case "updates": return item.map { !controller.isIgnored($0) } ?? false
            case "ignored": return item.map(controller.isIgnored) ?? false
            case "duplicates": return pkg.appPath.map { controller.duplicateGroup(for: $0) != nil } ?? false
            default: return true
            }
        }
        return InstalledMetrics.sorted(list, by: sort, reversed: reversed,
                                       sizes: metrics.sizes, dates: metrics.dates)
    }

    var body: some View {
        Group {
            if controller.installed.isEmpty && controller.loadingInstalled {
                ProgressView("Reading what's installed…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // The same gap above as at the sides (Nick, 2 Nov 2026).
                    items(shown)
                        .padding(16)
                        .id(layout)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.14), value: layout)
            }
        }
        // The controls stay put; the cards scroll under them in glass.
        .pinnedHeader {
            PageControls {
                GlassSearchField(prompt: "Filter installed apps and packages", text: $filter)
                HStack(spacing: 8) {
                    GlassSegmented(selection: $show, options: shows)
                    SortMenu(selection: $source, options: sources, help: "Show one installation type")
                    Spacer(minLength: 8)
                    if metrics.measuring { ProgressView().controlSize(.small).help("Reading sizes and dates") }
                    SortMenu(selection: $sort, options: Self.sorts.map { ($0.0, $0.1) })
                    SortDirectionButton(reversed: $reversed, order: order)
                    LayoutSwitch(layout: $layout)
                }
                UpdatesReminder()
            }
        }
        .navigationSubtitle("\(controller.installed.count) items")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { controller.loadInstalled() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(controller.loadingInstalled)
            }
        }
        .onAppear {
            if controller.installed.isEmpty { controller.loadInstalled() }
            takeChipRequest()
            metrics.measure(sort, controller.installed)
        }
        .onChange(of: controller.installedChipRequest) { takeChipRequest() }
        .onChange(of: sort) { _, sort in metrics.measure(sort, controller.installed) }
        .onChange(of: controller.installed.count) { metrics.measure(sort, controller.installed) }
    }

    @ViewBuilder
    private func items(_ list: [InstalledPackage]) -> some View {
        if list.isEmpty {
            Text("Nothing matches.").font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if layout == .cards {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                ForEach(list) { pkg in InstalledItem(pkg: pkg, item: update(for: pkg), asRow: false) }
            }
        } else {
            // Not lazy: the glass panel behind a lazy stack was measured
            // before its last rows were, so its bottom edge drew in the
            // wrong place (Nick, 2 Nov 2026).
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, pkg in
                    if index > 0 { Divider().padding(.leading, 50) }
                    InstalledItem(pkg: pkg, item: update(for: pkg), asRow: true)
                }
            }
            .modifier(ListPanel(color: .gray))
        }
    }
}

extension InstalledPage {
    /// Updates' "Review in Installed" asks for the Duplicates view.
    private func takeChipRequest() {
        guard let request = controller.installedChipRequest else { return }
        show = request
        source = ""
        controller.installedChipRequest = nil
    }
}

/// Sizes and install dates, read from disk only when that sort is chosen
/// and kept for the session (Phase 10). Items without one sort last.
@MainActor
final class InstalledMetrics: ObservableObject {
    static let shared = InstalledMetrics()
    @Published private(set) var sizes: [String: Int64] = [:]
    @Published private(set) var dates: [String: Date] = [:]
    @Published private(set) var measuring = false
    private var measured: Set<String> = []

    func measure(_ sort: String, _ pkgs: [InstalledPackage]) {
        guard sort == "size" || sort == "date" else { return }
        let todo = pkgs.filter { !measured.contains("\(sort)|\($0.id)") }
        guard !todo.isEmpty, !measuring else { return }
        measuring = true
        let jobs = todo.map { ($0.id, Self.path(of: $0)) }
        Task {
            let found = await Task.detached(priority: .utility) { () -> [(String, Int64?, Date?)] in
                jobs.map { id, path in
                    guard let path else { return (id, nil, nil) }
                    return sort == "size" ? (id, Self.size(at: path), nil) : (id, nil, Self.dateAdded(path))
                }
            }.value
            for (id, size, date) in found {
                measured.insert("\(sort)|\(id)")
                if let size { sizes[id] = size }
                if let date { dates[id] = date }
            }
            measuring = false
        }
    }

    /// The app, or a Homebrew formula's folder in the Cellar. Other
    /// packages have no folder of their own here, so they sort last.
    nonisolated static func path(of pkg: InstalledPackage) -> String? {
        if let app = pkg.appPath { return app }
        guard ["homebrew", "tools"].contains(pkg.sourceID), pkg.detail?.hasPrefix("cask ") != true else { return nil }
        return ["/opt/homebrew/Cellar", "/usr/local/Cellar"].map { "\($0)/\(pkg.name)" }
            .first { FileManager.default.fileExists(atPath: $0) }
    }

    nonisolated static func size(at path: String) -> Int64? {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
        guard let walk = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys)
        else { return nil }
        var total: Int64 = 0
        for case let url as URL in walk {
            total += Int64((try? url.resourceValues(forKeys: Set(keys)))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Finder's "Date Added", else when the folder was made.
    nonisolated static func dateAdded(_ path: String) -> Date? {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.addedToDirectoryDateKey, .creationDateKey])
        return values?.addedToDirectoryDate ?? values?.creationDate
    }

    /// Name A to Z; Size largest first; Date newest first; Installation
    /// type A to Z, then name. Reversed flips it; unmeasured items stay last.
    nonisolated static func sorted(_ list: [InstalledPackage], by sort: String, reversed: Bool,
                                   sizes: [String: Int64], dates: [String: Date]) -> [InstalledPackage] {
        func name(_ a: InstalledPackage, _ b: InstalledPackage) -> Bool {
            a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        func type(_ p: InstalledPackage) -> String {
            p.sourceID == "unmanaged" ? "Not managed" : UpdatesPage.title(of: p.sourceID)
        }
        switch sort {
        case "size", "date":
            let has = { (p: InstalledPackage) in sort == "size" ? sizes[p.id] != nil : dates[p.id] != nil }
            let measured = list.filter(has).sorted { a, b in
                sort == "size" ? sizes[a.id]! > sizes[b.id]! : dates[a.id]! > dates[b.id]!
            }
            return (reversed ? measured.reversed() : measured) + list.filter { !has($0) }.sorted(by: name)
        case "type":
            let sorted = list.sorted { a, b in
                let (x, y) = (type(a), type(b))
                return x == y ? name(a, b) : x.localizedCaseInsensitiveCompare(y) == .orderedAscending
            }
            return reversed ? sorted.reversed() : sorted
        default:
            let sorted = list.sorted(by: name)
            return reversed ? sorted.reversed() : sorted
        }
    }
}

/// One installed item as a card or a list row, like Discover's (Phase 10):
/// source tag top right with its status under it, "Version x", and the
/// Update, Unhide or Can adopt button with the trash button. Clicking
/// anywhere else opens its details.
private struct InstalledItem: View {
    @EnvironmentObject var controller: UpdateController
    let pkg: InstalledPackage
    let item: UpdateItem?
    let asRow: Bool
    @State private var showingDetail = false

    private var sectionTitle: String {
        pkg.sourceID == "unmanaged" ? "Not managed" : UpdatesPage.title(of: pkg.sourceID)
    }
    private var color: Color { pkg.sourceID == "unmanaged" ? .gray : SourceStyle.forSource(pkg.sourceID).color }

    var body: some View {
        Group {
            if asRow { row } else { card }
        }
        .contentShape(Rectangle())
        .onTapGesture { showingDetail = true }
        .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
            if let item {
                UpdateDetailView(item: item).environmentObject(controller)
            } else {
                InstalledDetail(pkg: pkg, sectionTitle: sectionTitle).environmentObject(controller)
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RowIcon(name: pkg.name, appPath: pkg.appPath, sectionID: pkg.sourceID)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pkg.name).font(.body.weight(.semibold)).lineLimit(1)
                    Text(pkg.detail ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) { tags }
            }
            Text(versionLine(pkg.version)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Spacer()
                actions
            }
            .frame(minHeight: 22)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(SectionPanel(color: color.opacity(0.35)))
    }

    private var row: some View {
        HStack(spacing: 10) {
            RowIcon(name: pkg.name, appPath: pkg.appPath, sectionID: pkg.sourceID, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(pkg.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(pkg.detail ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) { tags }.frame(width: 125, alignment: .trailing)
            Text(versionLine(pkg.version)).font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: 120, alignment: .leading)
            actions.frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private var tags: some View {
        if pkg.sourceID == "unmanaged" { StatusPill.notManaged } else { StatusPill.source(pkg.sourceID) }
        if let path = pkg.appPath, controller.duplicateGroup(for: path) != nil {
            StatusPill(text: "Duplicate", color: .orange)
        }
        if let item, controller.isIgnored(item) {
            StatusPill(text: "Hidden", color: .secondary)
        } else if let item {
            StatusPill.update(to: item.latestVersion)
        } else if pkg.sourceID != "unmanaged" {
            StatusPill.upToDate
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 6) {
            if let candidate = controller.adoptionCandidate(at: pkg.appPath) {
                Button("Can adopt") { controller.showingAdoptionReview = true }
                    .glass().controlSize(.small)
                    .help("\(candidate.verdict.title): Homebrew could keep this app up to date")
            } else if let item, controller.isIgnored(item) {
                Button("Unhide") { controller.unhide(item) }.glass().controlSize(.small)
            } else if let item {
                UpdateAction(item: item, color: color)
            }
        }
    }
}

/// The card for something with no update listed.
private struct InstalledDetail: View {
    @EnvironmentObject var controller: UpdateController
    @Environment(\.dismiss) private var dismiss
    let pkg: InstalledPackage
    let sectionTitle: String

    private var color: Color { pkg.sourceID == "unmanaged" ? .gray : SourceStyle.forSource(pkg.sourceID).color }

    /// The cask token, for Homebrew-managed apps.
    private var cask: String? {
        pkg.detail.flatMap { $0.hasPrefix("cask ") ? String($0.dropFirst(5)) : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RowIcon(name: pkg.name, appPath: pkg.appPath, sectionID: pkg.sourceID, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pkg.name).font(.title3).bold()
                    Text(sectionTitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Installed", value: pkg.version)
            if let path = pkg.appPath, ["sparkle", "github"].contains(pkg.sourceID) {
                ChannelSection(appPath: path)
            }
            if let cask, let betas = controller.separateBetas[cask] {
                Label("Separate beta available: \(betas.joined(separator: ", "))", systemImage: "testtube.2")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if pkg.sourceID == "unmanaged" {
                Text("Nothing here updates this app. It may update itself.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let cask, controller.selfUpdatingCasks.contains(cask) {
                Text("This app also updates itself. Either it or Homebrew can update it.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let cask, let vendor = controller.state.adoptedBehind[cask] {
                Label("Homebrew is behind the vendor's release (\(vendor)).", systemImage: "exclamationmark.circle")
                    .font(.callout).foregroundStyle(Color.orange.readable)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let path = pkg.appPath, let group = controller.duplicateGroup(for: path) {
                DuplicateActions(group: group, path: path)
            }
            if let path = pkg.appPath, controller.duplicateGroup(for: path) == nil,
               let token = controller.state.storeSwitches[path] {
                SwitchToHomebrewButton(cask: token, appPath: path, name: pkg.name)
            }
            if let cask, let path = pkg.appPath, controller.state.adopted[cask] != nil {
                StopManagingButton(cask: cask, appPath: path, name: pkg.name)
            }
            // As on every details pop-up: helpers left, Move to Trash in red
            // and the main action right, one size; close is the circle.
            HStack(spacing: 8) {
                if let path = pkg.appPath {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: { Label("Show in Finder", systemImage: "folder") }
                    .glass()
                }
                Spacer()
                if let removal = Removal(pkg) {
                    UninstallButton(removal: removal)
                }
                if let path = pkg.appPath {
                    Button("Open") { dismiss(); NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        .glassProminent(color)
                }
            }
        }
        .padding(18)
        .frame(width: 420, alignment: .leading)
        .popupClose()
    }
}

/// Installs, failures, skips and checks, newest first.
struct ActivityPage: View {
    @EnvironmentObject var controller: UpdateController
    @State private var shownLog: ActivityEntry?

    var body: some View {
        Group {
            if controller.state.activity.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Installs, failures and checks that find something show up here."))
            } else {
                // Each entry in its own clear Liquid Glass bubble.
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(controller.state.activity) { entry in
                            HStack(spacing: 10) {
                                pill(entry.kind).frame(width: 84, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title).font(.body.weight(.semibold)).lineLimit(1)
                                    Text(detail(entry)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if [.failed, .skipped, .cancelled].contains(entry.kind),
                                   let id = entry.itemID, let item = controller.visibleItems.first(where: { $0.id == id }),
                                   !controller.isBusy(item) {
                                    Button("Retry") { controller.requestUpdate(item) }.glass().controlSize(.small)
                                }
                                if let log = entry.log, !log.isEmpty {
                                    Button("Show log") { shownLog = entry }.glass().controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .modifier(ClearBubble())
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationSubtitle("What was installed, checked and skipped")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") { controller.clearActivity() }
                    .disabled(controller.state.activity.isEmpty)
            }
        }
        .sheet(item: $shownLog) { entry in
            VStack(alignment: .leading, spacing: 10) {
                Text(entry.title).font(.headline)
                ScrollView {
                    Text(entry.log ?? "").font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 560, height: 300)
            }
            .padding(18)
            .popupClose()
        }
    }

    private func detail(_ entry: ActivityEntry) -> String {
        var parts = [entry.detail, entry.date.formatted(.relative(presentation: .named))].filter { !$0.isEmpty }
        if let s = entry.seconds { parts.append("\(s) s") }
        return parts.joined(separator: " · ")
    }

    private func pill(_ kind: ActivityEntry.Kind) -> StatusPill {
        switch kind {
        case .updated: StatusPill(text: "Updated", color: .green)
        case .installed: StatusPill(text: "Installed", color: .green)
        case .removed: StatusPill(text: "Removed", color: .secondary)
        case .failed: StatusPill(text: "Failed", color: .red)
        case .skipped: StatusPill(text: "Skipped", color: .orange)
        case .cancelled: StatusPill(text: "Cancelled", color: .secondary)
        case .checked: StatusPill(text: "Checked", color: .blue)
        case .adopted: StatusPill(text: "Adopted", color: .teal)
        }
    }
}

/// A clear Liquid Glass bubble, like the toolbar's buttons.
struct ClearBubble: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: shape)
        } else {
            content.background(.thinMaterial, in: shape)
        }
    }
}
