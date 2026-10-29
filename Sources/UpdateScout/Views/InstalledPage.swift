import SwiftUI
import AppKit

/// Every installed item across sources, with a filter box and chips.
struct InstalledPage: View {
    @EnvironmentObject var controller: UpdateController
    @State private var filter = ""
    @State private var chip = "all"

    private var chips: [(id: String, title: String)] {
        let present = Set(controller.installed.map(\.sourceID))
        let sources = UpdatesPage.order.filter(present.contains).map { ($0, UpdatesPage.title(of: $0)) }
        return [("all", "All"), ("updates", "Updates available")] + sources
            + (present.contains("unmanaged") ? [("unmanaged", "Not managed")] : [])
            + [("ignored", "Hidden")]
    }

    /// The listed update for an installed package, if there is one.
    private func update(for pkg: InstalledPackage) -> UpdateItem? {
        controller.state.items.first {
            $0.sectionID == pkg.sourceID && $0.name.caseInsensitiveCompare(pkg.name) == .orderedSame
        } ?? (pkg.appPath.flatMap { path in controller.state.items.first { $0.appPath == path } })
    }

    private var shown: [InstalledPackage] {
        controller.installed.filter { pkg in
            if !filter.isEmpty, !pkg.name.localizedCaseInsensitiveContains(filter) { return false }
            let item = update(for: pkg)
            switch chip {
            case "all": return true
            case "updates": return item.map { !controller.isIgnored($0) } ?? false
            case "ignored": return item.map(controller.isIgnored) ?? false
            default: return pkg.sourceID == chip
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Filter installed apps and packages", text: $filter)
                .textFieldStyle(.roundedBorder)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.id) { c in
                        Button(c.title) { chip = c.id }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                            .tint(chip == c.id ? .accentColor : nil)
                    }
                }
            }
            if controller.installed.isEmpty && controller.loadingInstalled {
                ProgressView("Reading what's installed…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown) { pkg in
                    InstalledRow(pkg: pkg, item: update(for: pkg))
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(16)
        .navigationSubtitle("\(controller.installed.count) items")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { controller.loadInstalled() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(controller.loadingInstalled)
            }
        }
        .onAppear { if controller.installed.isEmpty { controller.loadInstalled() } }
    }
}

private struct InstalledRow: View {
    @EnvironmentObject var controller: UpdateController
    let pkg: InstalledPackage
    let item: UpdateItem?
    @State private var showingDetail = false

    private var sectionTitle: String {
        pkg.sourceID == "unmanaged" ? "Not managed" : UpdatesPage.title(of: pkg.sourceID)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { showingDetail = true } label: {
                HStack(spacing: 10) {
                    RowIcon(name: pkg.name, appPath: pkg.appPath, sectionID: pkg.sourceID)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pkg.name).font(.body.weight(.semibold)).lineLimit(1)
                        Text([pkg.version, pkg.detail].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDetail, arrowEdge: .bottom) {
                if let item {
                    UpdateDetailView(item: item).environmentObject(controller)
                } else {
                    InstalledDetail(pkg: pkg, sectionTitle: sectionTitle)
                }
            }
            if pkg.sourceID != "unmanaged" { StatusPill(text: sectionTitle, color: .secondary) }
            status
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var status: some View {
        if let item, controller.isIgnored(item) {
            Button("Unhide") { controller.unhide(item) }.glass().controlSize(.small)
        } else if let item {
            StatusPill(text: "Update to \(item.latestVersion)", color: .orange)
        } else if pkg.sourceID == "unmanaged" {
            StatusPill(text: "Not managed", color: .secondary)
        } else {
            StatusPill(text: "Up to date", color: .green)
        }
    }
}

/// The card for something with no update listed.
private struct InstalledDetail: View {
    let pkg: InstalledPackage
    let sectionTitle: String

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
            if pkg.sourceID == "unmanaged" {
                Text("Nothing here updates this app. It may update itself.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let path = pkg.appPath {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: { Label("Show in Finder", systemImage: "folder") }
                .glass()
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
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
                HStack { Spacer(); Button("Close") { shownLog = nil }.keyboardShortcut(.defaultAction) }
            }
            .padding(18)
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
        case .failed: StatusPill(text: "Failed", color: .red)
        case .skipped: StatusPill(text: "Skipped", color: .orange)
        case .cancelled: StatusPill(text: "Cancelled", color: .secondary)
        case .checked: StatusPill(text: "Checked", color: .blue)
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
