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
        // One row per duplicated app: the other copies are compared in its
        // pop-up (Nick, 2 Nov 2026).
        let extras = Set(controller.duplicates.filter { $0.kind == .twoCopies }
            .flatMap(\.extras).map { $0.lowercased() })
        let list = controller.installed.filter { pkg in
            if let path = pkg.appPath, extras.contains(path.lowercased()) { return false }
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
                // Spins while reading and isn't greyed out, like Check Now
                // on Updates (Nick, 2 Nov 2026).
                Button { controller.loadInstalled() } label: {
                    Label(controller.loadingInstalled ? "Reading…" : "Refresh", systemImage: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: controller.loadingInstalled)
                }
                .help(controller.loadingInstalled ? "Reading what's installed…" : "Read what's installed again")
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
            // Each row on its own glass, like the cards: one tall glass panel
            // drew a false edge where the window cut it off (Nick, 2 Nov 2026).
            LazyVStack(spacing: 6) {
                ForEach(list) { pkg in InstalledItem(pkg: pkg, item: update(for: pkg), asRow: true) }
            }
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
    @State private var linkingGitHub = false

    private var sectionTitle: String {
        pkg.sourceID == "unmanaged" ? "Not managed" : UpdatesPage.title(of: pkg.sourceID)
    }
    private var color: Color { pkg.sourceID == "unmanaged" ? .gray : SourceStyle.forSource(pkg.sourceID).color }
    private var hasDetail: Bool { !(pkg.detail ?? "").isEmpty }

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
                InstalledDetail(pkg: pkg, sectionTitle: sectionTitle) {
                    // The link window opens from the page once the pop-up has closed.
                    showingDetail = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { linkingGitHub = true }
                }
                .environmentObject(controller)
            }
        }
        .sheet(isPresented: $linkingGitHub) {
            GitHubLinkSheet(preselect: pkg.appPath) { linked in
                GitHubApps.link(linked)
                controller.loadInstalled()
            }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                RowIcon(name: pkg.name, appPath: pkg.appPath, sectionID: pkg.sourceID)
                VStack(alignment: .leading, spacing: 1) {
                    // With no line under it, the name gets that room.
                    Text(pkg.name).font(.body.weight(.semibold)).lineLimit(hasDetail ? 1 : 2)
                    if hasDetail {
                        Text(pkg.detail ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
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
                if hasDetail {
                    Text(pkg.detail ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            // Sized to its tags, so a long "Update to …" is never cut.
            VStack(alignment: .trailing, spacing: 3) { tags }.frame(minWidth: 125, alignment: .trailing)
            Text(versionLine(pkg.version)).font(.callout).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: 120, alignment: .leading)
            actions.frame(minWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .modifier(SectionPanel(color: color.opacity(0.35)))
    }

    @ViewBuilder
    private var tags: some View {
        if pkg.sourceID == "unmanaged" { StatusPill.notManaged } else { StatusPill.source(pkg.sourceID) }
        if let path = pkg.appPath, let group = controller.duplicateGroup(for: path) {
            StatusPill(text: group.kind == .twoCopies ? "\(group.extras.count + 1) copies" : "Duplicate", color: .orange)
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
    /// Its homepage comes from Homebrew's list, which loads here if it hasn't yet.
    @ObservedObject private var discover = DiscoverModel.shared
    let pkg: InstalledPackage
    let sectionTitle: String
    var linkGitHub: () -> Void = {}

    private var isDuplicate: Bool {
        pkg.appPath.flatMap { controller.duplicateGroup(for: $0) }?.kind == .twoCopies
    }

    private var color: Color { pkg.sourceID == "unmanaged" ? .gray : SourceStyle.forSource(pkg.sourceID).color }

    /// The cask token, for Homebrew-managed apps.
    private var cask: String? {
        pkg.detail.flatMap { $0.hasPrefix("cask ") ? String($0.dropFirst(5)) : nil }
    }

    /// Homebrew's list entry, for its homepage: a cask for apps, else a
    /// formula for command-line tools.
    private var homebrewEntry: DiscoverEntry? {
        if let cask { return discover.entry(cask: cask) }
        return pkg.sourceID == "tools" ? discover.entry(formula: pkg.name) : nil
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
            if let entry = homebrewEntry { WebDetailsSection(entry: entry) }
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
                if pkg.appPath != nil {
                    // Nick, 2 Nov 2026: a way in for apps released on GitHub.
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update from GitHub releases").font(.callout.weight(.semibold))
                            Text("If the app publishes its releases on GitHub.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Link to GitHub…") { linkGitHub() }.glass().fixedSize()
                    }
                }
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
                if let page = homebrewEntry?.homepage.flatMap(URL.init(string:)) {
                    Button {
                        NSWorkspace.shared.open(page)
                    } label: { Label("Website", systemImage: "safari") }
                    .glass()
                }
                if let path = pkg.appPath {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: { Label("Show in Finder", systemImage: "folder") }
                    .glass()
                }
                Spacer()
                // Duplicates have a Move to Trash on each copy instead.
                if let removal = Removal(pkg), !isDuplicate {
                    UninstallButton(removal: removal)
                }
                if let path = pkg.appPath {
                    Button("Open") { dismiss(); NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                        .glassProminent(color)
                }
            }
        }
        .padding(18)
        // As wide as the Updates pop-up, so the copies compare in full.
        .frame(width: 540, alignment: .leading)
        .popupClose()
        .onAppear { if cask != nil || pkg.sourceID == "tools" { discover.start() } }
    }
}

/// Installs, failures, skips and checks, newest first. Kept until deleted.
struct ActivityPage: View {
    @EnvironmentObject var controller: UpdateController
    @State private var shownLog: ActivityEntry?
    @State private var query = ""
    @State private var show = "all"
    @State private var ticked: Set<UUID> = []
    @AppStorage("activityOldestFirst") private var oldestFirst = false

    private var shows: [(value: String, title: String)] {
        [("all", "All activity")] + ActivityEntry.Kind.allCases.map { ($0.rawValue, $0.title) }
    }

    private var shown: [ActivityEntry] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        let list = oldestFirst ? controller.state.activity.reversed() : controller.state.activity
        return list.filter { entry in
            guard show == "all" || entry.kind.rawValue == show else { return false }
            let text = "\(entry.title) \(entry.detail) \(entry.kind.title)".lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
    }

    var body: some View {
        let shown = shown
        Group {
            if controller.state.activity.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("Installs, failures and checks that find something show up here."))
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    // Each entry on its own small glass panel, like Installed's rows.
                    LazyVStack(spacing: 8) {
                        ForEach(shown) { entry in row(entry) }
                    }
                    .padding(16)
                }
            }
        }
        // Fills the page, so the controls stay at the top when it's empty.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pinnedHeader {
            PageControls {
                GlassSearchField(prompt: "Filter activity", text: $query)
                HStack(spacing: 8) {
                    SortMenu(selection: $show, options: shows, help: "Show one kind")
                    SortDirectionButton(reversed: $oldestFirst, order: oldestFirst ? "Oldest first" : "Newest first")
                    Spacer(minLength: 8)
                    let selected = ticked.intersection(controller.state.activity.map(\.id))
                    if selected.isEmpty {
                        Button("Delete All") { confirmDeleteAll() }
                            .glassDestructive()
                            .disabled(controller.state.activity.isEmpty)
                    } else {
                        Button("Delete \(selected.count)") {
                            controller.deleteActivity(selected)
                            ticked.removeAll()
                        }
                        .glassDestructive()
                    }
                }
            }
        }
        .navigationSubtitle("What was installed, checked and skipped")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { controller.reloadFromDisk() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Read the history again, including what background checks added")
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

    private func row(_ entry: ActivityEntry) -> some View {
        HStack(spacing: 10) {
            Toggle("Select", isOn: Binding(
                get: { ticked.contains(entry.id) },
                set: { on in if on { ticked.insert(entry.id) } else { ticked.remove(entry.id) } }))
                .toggleStyle(.checkbox).labelsHidden()
            StatusPill(text: entry.kind.title, color: entry.kind.color).frame(width: 84, alignment: .leading)
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
        .padding(.horizontal, 12).padding(.vertical, 8)
        .modifier(SectionPanel(color: entry.kind.color.opacity(0.35)))
    }

    /// Date and time on every row (Nick, 2 Nov 2026), then the details.
    private func detail(_ entry: ActivityEntry) -> String {
        var parts = [entry.date.formatted(date: .abbreviated, time: .shortened), entry.detail].filter { !$0.isEmpty }
        if let s = entry.seconds { parts.append("\(s) s") }
        return parts.joined(separator: " · ")
    }

    private func confirmDeleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete all activity?"
        alert.informativeText = "Every entry is deleted, with its log. This can't be undone."
        alert.alertStyle = .warning
        let go = alert.addButton(withTitle: "Delete All")
        go.hasDestructiveAction = true
        go.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        if alert.runModal() == .alertFirstButtonReturn {
            controller.clearActivity()
            ticked.removeAll()
        }
    }
}

/// Activity's kinds: one name and one colour each, used on this page only
/// (Nick, 2 Nov 2026). Green means installed here as everywhere else.
extension ActivityEntry.Kind {
    var title: String {
        switch self {
        case .updated: "Updated"
        case .installed: "Installed"
        case .removed: "Removed"
        case .failed: "Failed"
        case .skipped: "Skipped"
        case .cancelled: "Cancelled"
        case .checked: "Checked"
        case .adopted: "Adopted"
        }
    }

    var color: Color {
        switch self {
        case .updated: .blue
        case .installed: .green
        case .removed: .red
        case .failed: Theme.leftoverPink
        case .skipped, .cancelled: .gray
        case .checked: Theme.graphite
        case .adopted: SourceStyle.forSource("homebrew").color
        }
    }
}
