import SwiftUI
import AppKit

/// The Updates page: one tinted glass section per source, each collapsible,
/// with rows inside and an "Update all <section>" button on its header.
struct UpdatesPage: View {
    @EnvironmentObject var controller: UpdateController
    /// Comma-separated ids of collapsed sections, remembered between launches.
    @AppStorage("collapsedSections") private var collapsedRaw = ""
    @AppStorage("showHidden") private var showHidden = false
    static let roll = Animation.smooth(duration: 0.32)

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }

    private func toggle(_ id: String) {
        var set = collapsed
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        withAnimation(Self.roll) { collapsedRaw = set.sorted().joined(separator: ",") }
    }

    /// Section order: the 1.8.0 sources, then what 2.0 adds.
    static let order = ["homebrew", "mas", "macos", "caskOracle", "components", "sparkle", "custom",
                        "github", "tools", "pip", "npm", "cargo", "gem", "editors"]

    private var grouped: [(id: String, items: [UpdateItem])] {
        let visible = controller.visibleItems
        return Self.order.compactMap { id in
            let items = visible.filter { $0.sectionID == id }
            return items.isEmpty ? nil : (id, items)
        }
    }

    static func title(of sectionID: String) -> String {
        switch sectionID {
        case "tools": "Tools"
        case "editors": "Editor extensions"
        case "leftover": "Leftover drivers"
        case "hidden": "Hidden"
        default: UpdateController.sourceName(sectionID)
        }
    }

    @AppStorage(Migration.noticeKey) private var showRenameNotice = false

    var body: some View {
        VStack(spacing: 0) {
            let nothingToDo = controller.visibleItems.isEmpty && controller.visibleLeftovers.isEmpty
            let hiddenCount = controller.hiddenItems.count + controller.hiddenLeftovers.count
                + controller.hiddenAdoptions.count
            if nothingToDo && hiddenCount == 0 {
                UpToDateView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Click an app's icon or name for details, release notes and hide options.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        if nothingToDo { UpToDateView(compact: true) }
                        ForEach(grouped, id: \.id) { group in
                            section(group.id, count: group.items.count, items: group.items) {
                                rows(for: group)
                            }
                        }
                        leftoverSection
                        hiddenSection
                    }
                    .padding(16)
                    // Collapse state lives in @AppStorage, whose changes land
                    // outside any withAnimation, so animate on the values
                    // themselves, on the whole list: the sections below glide
                    // with the one that's rolling instead of snapping.
                    .animation(Self.roll, value: collapsedRaw)
                    .animation(Self.roll, value: showHidden)
                }
            }
        }
        // The banner and the error summary stay put; sections scroll under
        // them in glass.
        .pinnedHeader {
            VStack(spacing: 0) {
                if Migration.showsRenameBanner { renameBanner }
                AdoptionBanner()
                DuplicatesNote()
            }
        }
        .pinnedHeader(edge: .bottom) { errorSummary }
        .toolbar { UpdatesToolbar() }
        .navigationSubtitle(subtitle)
    }

    private var subtitle: String {
        let count = controller.visibleItems.count
        let checked = controller.isSpinning ? "Checking…"
            : controller.state.lastCheck.map { "Checked \($0.formatted(.relative(presentation: .named)))" }
        let available = count == 0 ? "Up to date" : "\(count) available"
        return [checked, available].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func rows(for group: (id: String, items: [UpdateItem])) -> some View {
        // Apps the App Store has to update itself collapse into one hand-off
        // row: per-app rows would offer a button that can't do anything.
        let handoff = group.items.filter { !$0.scriptedInstall && $0.sourceID == "mas" }
        let rows = group.items.filter { !handoff.contains($0) }
        ForEach(rows) { item in
            UpdateRow(item: item)
            if item.id != rows.last?.id || !handoff.isEmpty { Divider() }
        }
        if !handoff.isEmpty { AppStoreHandoffRow(items: handoff) }
    }

    // MARK: Sections

    private func section<Content: View>(_ id: String, count: Int, items: [UpdateItem] = [],
                                        expanded: Bool? = nil, onToggle: (() -> Void)? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        let style = SourceStyle.forSource(id)
        let isExpanded = expanded ?? !collapsed.contains(id)
        let title = Self.title(of: id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button { (onToggle ?? { toggle(id) })() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 10)
                        GlassIconTile(style: style, size: 22)
                        Text(title).font(.headline)
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 1)
                            .background(style.color.opacity(0.25), in: Capsule())
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide \(title)" : "Show \(title)")
                headerButton(id: id, title: title, items: items)
            }
            .frame(height: 30)

            // The rows stay in the layout; their height rolls between zero and
            // natural size, clipped at the header, while they fade. Nothing
            // slides, so the wording fades in place as the section rolls.
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: isExpanded ? nil : 0, alignment: .top)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .modifier(SectionPanel(color: style.color))
    }

    @ViewBuilder
    private func headerButton(id: String, title: String, items: [UpdateItem]) -> some View {
        let installable = items.filter { $0.scriptedInstall && !controller.isPinned($0) }
        if !installable.isEmpty {
            Button(installable.count > 1 ? "Update all \(title)" : "Update \(title)") {
                controller.updateAll(sectionID: id)
            }
            .glass().controlSize(.small).buttonBorderShape(.capsule)
        } else if id == "macos", !items.isEmpty {
            // macOS installs happen in System Settings.
            Button("Update macOS") {
                if let url = URL(string: SystemUpdateSource.settingsURL) { NSWorkspace.shared.open(url) }
            }
            .glass().controlSize(.small).buttonBorderShape(.capsule)
            .help("Opens Software Update in System Settings")
        } else if id == "mas", items.contains(where: { !$0.scriptedInstall }) {
            Button("Open App Store") { NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!) }
                .glass().controlSize(.small).buttonBorderShape(.capsule)
        }
    }

    /// Third-party kexts in /Library/Extensions that macOS isn't loading.
    @ViewBuilder
    private var leftoverSection: some View {
        let leftovers = controller.visibleLeftovers
        if !leftovers.isEmpty {
            section("leftover", count: leftovers.count) {
                ForEach(leftovers) { kext in
                    LeftoverRow(kext: kext)
                    if kext.id != leftovers.last?.id { Divider() }
                }
            }
        }
    }

    /// Everything the user chose to ignore, collapsed by default.
    @ViewBuilder
    private var hiddenSection: some View {
        let items = controller.hiddenItems
        let kexts = controller.hiddenLeftovers
        let adoptions = controller.hiddenAdoptions
        if !items.isEmpty || !kexts.isEmpty || !adoptions.isEmpty {
            section("hidden", count: items.count + kexts.count + adoptions.count, expanded: showHidden,
                    onToggle: { withAnimation(Self.roll) { showHidden.toggle() } }) {
                // Dividers only between rows, never after the last one.
                ForEach(items) { item in
                    HiddenRow(item: item)
                    if item.id != items.last?.id || !kexts.isEmpty { Divider() }
                }
                ForEach(kexts) { kext in
                    HiddenLeftoverRow(kext: kext)
                    if kext.id != kexts.last?.id || !adoptions.isEmpty { Divider() }
                }
                ForEach(adoptions) { candidate in
                    HiddenAdoptionRow(candidate: candidate)
                    if candidate.id != adoptions.last?.id { Divider() }
                }
            }
        }
    }

    /// Stays for all of 2.0. Clicking it replays the rename pop-up.
    private var renameBanner: some View {
        Button {
            showRenameNotice = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                Text("UpdateScout is now \(AppIdentity.name)").font(.callout)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(Color.accentColor.opacity(0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Why the new name")
    }

    @ViewBuilder
    private var errorSummary: some View {
        let errors = controller.state.sourceErrors
        if !errors.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(errors.sorted(by: { $0.key < $1.key }), id: \.key) { sourceID, message in
                    Label("\(UpdateController.sourceName(sourceID)): \(message)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Color.orange.readable).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.orange.opacity(0.08))
        }
    }
}

/// Check Now and Update All, in the window's unified toolbar.
struct UpdatesToolbar: ToolbarContent {
    @EnvironmentObject var controller: UpdateController

    var body: some ToolbarContent {
        // Two separate items with a gap, so each sits in its own bubble
        // instead of both squeezed into one.
        ToolbarItem(placement: .primaryAction) {
            // A plain toolbar button, so it gets the system's own glass,
            // hover and press.
            // The arrow spins while any check runs (here or in the background).
            // Not disabled while checking: a dimmed button hid the spin.
            Button { if !controller.isChecking { controller.checkNow() } } label: {
                Label(controller.isSpinning ? "Checking…" : "Check Now", systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: controller.isSpinning)
            }
            .help(controller.isChecking ? "Checking…" : "Check every source for updates now")
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
            if controller.visibleItems.contains(where: { $0.scriptedInstall }) {
                // The system's toolbar glass, hover and press, with the
                // icon's colours as a faint blur inside.
                Button { controller.updateAll() } label: {
                    Text("Update All").fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .background { PrismBlur() }
                }
                .help("Update everything listed (major upgrades ask first)")
            }
        }
    }
}

/// "Everything is up to date": the app's prism, large, with a faint sheen.
struct UpToDateView: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 6 : 12) {
            ZStack {
                PrismSheen().opacity(0.55).mask(PrismShape())
                PrismShape().stroke(.white.opacity(0.85), lineWidth: compact ? 1.5 : 2.5)
                PrismRidge().stroke(.white.opacity(0.7), lineWidth: compact ? 1 : 1.8)
            }
            .frame(width: compact ? 44 : 96, height: compact ? 40 : 86)
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            Text("Everything is up to date").font(compact ? .headline : .title2.weight(.semibold))
            if !compact {
                Text("PrismPack checks again on its own. Check Now looks right away.".replacingOccurrences(
                    of: "PrismPack", with: AppIdentity.name))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: compact ? nil : .infinity)
        .padding(.vertical, compact ? 8 : 0)
    }
}

/// The prism outline: a triangle with softened corners.
struct PrismShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p.strokedPath(.init(lineWidth: 0.01, lineJoin: .round)).union(p)
    }
}

/// The off-centre ridge that makes the triangle read as a 3D prism.
struct PrismRidge: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let ridge = CGPoint(x: r.minX + r.width * 0.58, y: r.maxY - r.height * 0.22)
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: ridge)
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: ridge)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}
