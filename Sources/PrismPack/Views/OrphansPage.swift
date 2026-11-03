import SwiftUI
import AppKit

/// Orphaned App Files (Phase 9): files in the user's Library named for an
/// app ID that nothing on this Mac owns any more. Nothing is ticked: an ID
/// with no app can still belong to a command-line tool or a background
/// service, so the user ticks what they recognise. Scans only when opened or
/// on Rescan, never in the background check.
struct OrphansPage: View {
    @EnvironmentObject var controller: UpdateController
    @State private var orphans: [Leftovers.Orphan]?
    @State private var scanning = false
    @State private var ticked: Set<String> = []
    @State private var expanded: Set<String> = []
    @State private var moving = false
    @State private var outcome: Leftovers.Outcome?
    @State private var filter = ""
    @AppStorage("orphansSort") private var sort = "size"
    @AppStorage("orphansSortReversed") private var reversed = false

    private static let sorts = [("size", "Size"), ("name", "Name"), ("changed", "Last changed")]

    /// The order shown, for the direction button's tooltip.
    private var order: String {
        switch sort {
        case "name": reversed ? "Z to A" : "A to Z"
        case "changed": reversed ? "Least recently changed first" : "Most recently changed first"
        default: reversed ? "Smallest first" : "Largest first"
        }
    }

    /// Filtered by the search box, in the chosen order. Reversed flips it;
    /// files with no change date stay last either way.
    private var shown: [Leftovers.Orphan] {
        let list = (orphans ?? []).filter { filter.isEmpty || $0.id.localizedCaseInsensitiveContains(filter) }
        switch sort {
        case "name":
            let sorted = list.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
            return reversed ? sorted.reversed() : sorted
        case "changed":
            let dated = list.filter { $0.lastChanged != nil }.sorted { $0.lastChanged! > $1.lastChanged! }
            return (reversed ? dated.reversed() : dated) + list.filter { $0.lastChanged == nil }
        default:
            let sorted = list.sorted { $0.size > $1.size }
            return reversed ? sorted.reversed() : sorted
        }
    }

    private var tickedItems: [Leftovers.Found] {
        (orphans ?? []).filter { ticked.contains($0.id) }.flatMap(\.items).filter(\.movable)
    }

    var body: some View {
        Group {
            if let orphans, !scanning {
                if orphans.isEmpty {
                    ContentUnavailableView("No orphaned app files", systemImage: "archivebox",
                                           description: Text("Everything in your Library that's named for an app belongs to one that's installed."))
                } else {
                    List {
                        ForEach(shown) { orphan in row(orphan) }
                        if !kept.isEmpty { keptSection }
                    }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView("Looking through your Library…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .pinnedHeader { header }
        .navigationSubtitle(orphans.map { "\($0.count) app\($0.count == 1 ? "" : "s")" } ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Spins while scanning and isn't greyed out, like Check Now
                // on Updates (Nick, 2 Nov 2026).
                Button { if !scanning && !moving { Task { await scan() } } } label: {
                    Label(scanning ? "Scanning…" : "Rescan", systemImage: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: scanning)
                }
                .help(scanning ? "Scanning…" : "Scan again")
            }
        }
        .navigationSubtitle("Files left behind by apps that are gone")
        .task { if orphans == nil { await scan() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing is ticked: some may belong to a command-line tool or a background service, so tick only what you recognise. Everything goes to the Trash.")
                .font(.caption).foregroundStyle(.secondary)
                // A line limit, not fixedSize: measured at zero width, fixedSize
                // text made the page thousands of points tall, which pushed the
                // window and its sidebar off screen (31 Oct 2026).
                .lineLimit(3)
            if let outcome { result(outcome) }
            // Search, Sort and its direction, as on Discover.
            HStack(spacing: 8) {
                GlassSearchField(prompt: "Filter by app ID", text: $filter)
                SortMenu(selection: $sort, options: Self.sorts.map { ($0.0, $0.1) })
                SortDirectionButton(reversed: $reversed, order: order)
            }
            HStack {
                let items = tickedItems
                Text(items.isEmpty ? "Nothing ticked"
                     : "\(ticked.count) app\(ticked.count == 1 ? "" : "s"), \(UninstallPanelText.bytes(items.reduce(0) { $0 + $1.size })) ticked")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                // Bulk actions for the ticked ones (Nick, 2 Nov 2026).
                Button { showInFinder(items) } label: { Image(systemName: "folder") }
                    .glass().disabled(items.isEmpty)
                    .help("Show in Finder").accessibilityLabel("Show in Finder")
                Button("Keep") { tickedOrphans.forEach(keep) }
                    .glass().disabled(items.isEmpty)
                    .help("Stop listing the ticked apps. Their files stay where they are.")
                Button(role: .destructive) { confirmMove() } label: { Label("Move to Trash", systemImage: "trash") }
                    .glassDestructive()
                    .disabled(items.isEmpty || moving)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }

    private func row(_ orphan: Leftovers.Orphan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if orphan.isGroup {
                    // Shared folders are never moved (see Found.movable): the
                    // badge stands where the checkbox would be.
                    WarningBadge(title: "Shared folder",
                                 message: "It may be used by other apps from this developer, so \(AppIdentity.name) doesn't move it. Use Show in Finder to move it yourself.")
                } else {
                    Toggle("", isOn: Binding(get: { ticked.contains(orphan.id) },
                                             set: { if $0 { ticked.insert(orphan.id) } else { ticked.remove(orphan.id) } }))
                        .toggleStyle(.checkbox).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(orphan.id).font(.body.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    Text(subtitle(orphan)).font(.caption).foregroundStyle(.secondary)
                    if !orphan.isGroup, orphan.sameDeveloper {
                        Text("Another app from this developer is installed: these may be its shared files")
                            .font(.caption).foregroundStyle(Color.orange.readable)
                    }
                    if let date = orphan.lastChanged, date > Date.now.addingTimeInterval(-30 * 86_400) {
                        Text("Changed in the last month: something on this Mac may still use these")
                            .font(.caption).foregroundStyle(Color.orange.readable)
                    }
                }
                Spacer()
                // Each item's own buttons (Nick, 2 Nov 2026).
                Button(expanded.contains(orphan.id) ? "Hide files" : "Show files") {
                    if expanded.contains(orphan.id) { expanded.remove(orphan.id) } else { expanded.insert(orphan.id) }
                }
                .glass().controlSize(.small)
                Button { showInFinder(orphan.items) } label: { Image(systemName: "folder") }
                    .glass().controlSize(.small).help("Show in Finder").accessibilityLabel("Show in Finder")
                Button("Keep") { keep(orphan) }.glass().controlSize(.small)
                    .help("Stop listing these. They stay where they are.")
                // Red, like every Move to Trash (Nick, 2 Nov 2026). Shared
                // folders show it greyed out: they're never moved from here.
                Button(role: .destructive) { confirmMove(orphan.items.filter(\.movable), names: [orphan.id]) } label: {
                    Image(systemName: "trash")
                }
                .glassDestructive().controlSize(.small).disabled(moving || orphan.isGroup)
                .help(orphan.isGroup ? "Shared folders can't be moved from here" : "Move to Trash")
                .accessibilityLabel("Move to Trash")
            }
            if expanded.contains(orphan.id) {
                ForEach(orphan.items) { item in
                    HStack {
                        Text(UninstallPanelText.shortPath(item.path)).font(.caption).lineLimit(1).truncationMode(.middle)
                            .help(item.path)
                        Spacer()
                        Text(UninstallPanelText.size(item.size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 30)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(_ orphan: Leftovers.Orphan) -> String {
        var parts = ["\(orphan.items.count) item\(orphan.items.count == 1 ? "" : "s")", UninstallPanelText.size(orphan.size)]
        if let date = orphan.lastChanged {
            parts.append("last changed \(date.formatted(.dateTime.month(.wide).year()))")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func result(_ outcome: Leftovers.Outcome) -> some View {
        if !outcome.moved.isEmpty {
            Label("Moved \(outcome.moved.count) item\(outcome.moved.count == 1 ? "" : "s") to the Trash.", systemImage: "checkmark.circle.fill")
                .font(.callout)
        }
        ForEach(outcome.failed, id: \.item.path) { failure in
            Text("\(UninstallPanelText.shortPath(failure.item.path)): \(failure.reason)").font(.caption).foregroundStyle(Color.red.readable)
                .lineLimit(2)
        }
        let blocked = outcome.failed.filter(\.needsFullDiskAccess).map(\.item)
        if !blocked.isEmpty {
            BlockedLeftovers(items: blocked) { await move(blocked) }
        }
    }

    // MARK: Work

    private func scan() async {
        scanning = true
        let kept = Prefs.keptOrphans
        let found = await Task.detached { Leftovers.orphans(kept: kept) }.value
        orphans = found
        ticked = ticked.intersection(found.map(\.id))
        scanning = false
    }

    /// Kept apps' IDs, newest choices included, for the Kept section.
    private var kept: [String] { Prefs.keptOrphans.sorted() }

    private var tickedOrphans: [Leftovers.Orphan] { (orphans ?? []).filter { ticked.contains($0.id) } }

    /// What Keep took off the list, with a way to put each back.
    private var keptSection: some View {
        Section("Kept") {
            ForEach(kept, id: \.self) { id in
                HStack {
                    Text(id).font(.callout).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Put back") {
                        Prefs.keptOrphans.remove(id)
                        Task { await scan() }
                    }
                    .glass().controlSize(.small)
                    .help("List this app's files again")
                }
            }
        }
    }

    /// One Finder window with them all selected.
    private func showInFinder(_ items: [Leftovers.Found]) {
        NSWorkspace.shared.activateFileViewerSelecting(items.map { URL(fileURLWithPath: $0.path) })
    }

    private func keep(_ orphan: Leftovers.Orphan) {
        Prefs.keptOrphans.insert(orphan.id.lowercased())
        ticked.remove(orphan.id)
        orphans?.removeAll { $0.id == orphan.id }
    }

    private func confirmMove() {
        confirmMove(tickedItems, names: tickedOrphans.map(\.id))
    }

    private func confirmMove(_ items: [Leftovers.Found], names: [String]) {
        guard !items.isEmpty else { return }
        let alert = NSAlert()
        alert.icon = AskpassDialog.badgeIcon(symbol: "exclamationmark")
        alert.messageText = "Move \(items.count) item\(items.count == 1 ? "" : "s") to the Trash?"
        alert.informativeText = names.joined(separator: "\n")
            + "\n\nYou can put them back from the Trash."
        alert.alertStyle = .warning
        let go = alert.addButton(withTitle: "Move to Trash")
        go.hasDestructiveAction = true
        go.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await move(items) }
    }

    private func move(_ items: [Leftovers.Found]) async {
        moving = true
        let result = await Leftovers.moveToTrash(items)
        controller.logLeftovers(of: "apps no longer installed", result)
        outcome = Leftovers.Outcome(moved: result.moved,
                                    failed: result.failed.filter { $0.reason != "It's already gone." })
        ticked = []
        moving = false
        await scan()
    }
}
