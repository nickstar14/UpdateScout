import SwiftUI
import AppKit

extension NSWindow {
    /// AppKit's center() sits windows above the vertical midpoint; this puts
    /// them at the true center of the screen.
    func centerExactly() {
        guard let screen = screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        setFrameOrigin(NSPoint(x: vf.midX - frame.width / 2,
                               y: vf.midY - frame.height / 2))
    }
}

/// The main status window — borderless-titlebar, Liquid Glass background,
/// movable by grabbing anywhere, resizable.
@MainActor
final class UpdatesWindow {
    static let shared = UpdatesWindow()
    private var window: NSWindow?

    /// Frame of the status window when it's on screen — other windows centre
    /// on it rather than on the display.
    var visibleFrame: NSRect? {
        guard let window, window.isVisible else { return nil }
        return window.frame
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let hosting = NSHostingController(
                rootView: UpdatesView().environmentObject(UpdateController.shared))
            let w = NSWindow(contentViewController: hosting)
            w.title = "UpdateScout"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            // Exactly three tiles across; tall enough for two expanded
            // sections plus the Hidden bar.
            w.setContentSize(NSSize(width: UpdatesView.idealWidth(columns: 3), height: 720))
            w.minSize = NSSize(width: UpdatesView.minimumWidth, height: 380)
            window = w
        }
        let wasVisible = window?.isVisible ?? false
        window?.makeKeyAndOrderFront(nil)
        if !wasVisible { window?.centerExactly() }
    }
}

struct UpdatesView: View {
    @EnvironmentObject var controller: UpdateController
    /// Comma-separated ids of collapsed sections, remembered between launches.
    @AppStorage("collapsedSections") private var collapsedRaw = ""
    /// The section roll animation, shared by every collapse/expand path.
    static let rollDuration: Double = 0.38
    static let roll = Animation.smooth(duration: rollDuration)

    /// Scroll bookkeeping that must not re-render the view on every scroll
    /// frame, so it lives in a reference type rather than @State values.
    @MainActor final class ScrollState {
        var geometry: ScrollGeometry?
        /// Each section's expanded content height — what collapsing removes.
        var contentHeights: [String: CGFloat] = [:]
    }
    @State private var scrollState = ScrollState()
    @State private var scrollPosition = ScrollPosition(edge: .top)
    /// Temporary bottom padding that holds the content height during a
    /// collapse — see `setSection`.
    @State private var scrollSlack: CGFloat = 0

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }

    private func toggleCollapsed(_ id: String) {
        var set = collapsed
        let collapsing = !set.contains(id)
        if collapsing { set.insert(id) } else { set.remove(id) }
        setSection(id, collapsing: collapsing) { collapsedRaw = set.sorted().joined(separator: ",") }
    }

    /// Run a collapse or expand so the whole list moves as one animation.
    ///
    /// Collapsing near the end of the list shrinks the content under the
    /// scroll position; the scroll view would then snap back to its new end
    /// *instantly*, before the roll animation ran — the "jump". So: hold the
    /// content height with temporary bottom slack (nothing to snap to), animate
    /// the scroll to its new resting place in the same animation as the roll,
    /// and drop the slack once both have finished.
    private func setSection(_ id: String, collapsing: Bool, apply: @escaping () -> Void) {
        guard collapsing, let geo = scrollState.geometry,
              let removed = scrollState.contentHeights[id], removed > 0 else {
            withAnimation(Self.roll) { apply() }
            return
        }
        let minOffset = -geo.contentInsets.top
        let newMax = max(minOffset,
                         geo.contentSize.height - removed + geo.contentInsets.bottom - geo.containerSize.height)
        let offset = geo.contentOffset.y
        guard offset > newMax + 0.5 else {
            withAnimation(Self.roll) { apply() }
            return
        }
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { scrollSlack = offset - newMax }
        // Next runloop turn: in the same turn SwiftUI merges the instant
        // transaction with the animated one and the roll doesn't animate.
        DispatchQueue.main.async {
            withAnimation(Self.roll) {
                apply()
                scrollPosition.scrollTo(y: newMax)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.rollDuration + 0.1) {
                withTransaction(instant) { scrollSlack = 0 }
            }
        }
    }

    private var grouped: [(source: any UpdateSource, items: [UpdateItem])] {
        UpdateController.allSources.compactMap { source in
            let items = controller.visibleItems.filter { $0.sourceID == source.id }
            return items.isEmpty ? nil : (source, items)
        }
    }

    /// Measured height of the title sheet, so the list can start below it.
    @State private var sheetHeight: CGFloat = 190

    var body: some View {
        VStack(spacing: 0) {
            // The list runs all the way up *under* the frosted title sheet,
            // with a top margin the height of the sheet: cards start below it
            // but scroll up behind it and frost through, instead of being
            // clipped at a hard line just short of its edge.
            ZStack(alignment: .top) {
                updateList
                VStack(spacing: 0) {
                    header
                    statusBanner
                }
                .background { TitleSheet() }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
            }
            errorSummary
        }
        .frame(minWidth: Self.minimumWidth, minHeight: 380)
        .background(GlassBackground())
        .onAppear { controller.reloadFromDisk() }
    }

    // MARK: Chrome


    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            // Logo centred against a two-line block (name + version), the same
            // arrangement as the Settings header.
            HStack(alignment: .center, spacing: 12) {
                AppLogo(size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text("UpdateScout").font(.title.weight(.semibold))
                            .lineLimit(1).fixedSize()
                        Button { SettingsWindow.shared.show() } label: {
                            Image(systemName: "gearshape.fill")
                        }
                        .glass()
                        .help("Settings")
                    }
                    Text("Version \(SelfUpdater.version)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            // Check Now, with the last-checked time beneath it.
            VStack(alignment: .trailing, spacing: 3) {
                if controller.isChecking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking…").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(height: 26)
                } else {
                    Button {
                        controller.checkNow()
                    } label: {
                        Label("Check Now", systemImage: "arrow.clockwise")
                    }
                    .glassProminent(.accentColor)
                }
                if let lastCheck = controller.state.lastCheck {
                    Text("Checked \(lastCheck.formatted(.relative(presentation: .named)))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)   // just clears the traffic lights, which end at y = 24
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var statusBanner: some View {
        let count = controller.visibleItems.count
        let leftovers = controller.visibleLeftovers.count
        let upToDate = count == 0
        let tint: Color = upToDate ? .green : .orange
        HStack(spacing: 12) {
            Image(systemName: upToDate ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.15), in: Circle())
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 1) {
                Text(upToDate ? "Everything is up to date"
                              : "^[\(count) update](inflect: true) available")
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                if leftovers > 0 {
                    Text("^[\(leftovers) leftover driver](inflect: true) can be removed")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if count > 0 && controller.visibleItems.contains(where: { $0.scriptedInstall }) {
                Button {
                    controller.updateAll()
                } label: {
                    Label("Update All", systemImage: "arrow.down.to.line")
                }
                .glassProminent(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: Content

    /// Tiles keep a fixed size; widening the window fits more per row rather
    /// than stretching them. `.adaptive` with equal min/max does exactly that.
    static let tileWidth: CGFloat = 152
    /// Narrowest the window may go: wide enough that the header, status banner
    /// and section headers never wrap, while still allowing two columns.
    static let minimumWidth: CGFloat = 450
    static let tileSpacing: CGFloat = 12
    /// Section panel padding: inside the outline, and between panel and window.
    static let panelInset: CGFloat = 10
    static let panelMargin: CGFloat = 16
    private let columns = [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth),
                                    spacing: tileSpacing, alignment: .top)]

    /// Window width that fits exactly `n` tiles per row with no leftover. When
    /// scroll bars are set to always show, the scroller takes real width, so
    /// add it — otherwise the exact fit would drop to one column fewer.
    static func idealWidth(columns n: Int) -> CGFloat {
        let tiles = CGFloat(n) * tileWidth + CGFloat(n - 1) * tileSpacing
        let scroller = NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        return tiles + 2 * panelInset + 2 * panelMargin + scroller
    }

    @ViewBuilder
    private var updateList: some View {
        let nothingToDo = controller.visibleItems.isEmpty && controller.visibleLeftovers.isEmpty
        let hiddenCount = controller.hiddenItems.count + controller.hiddenLeftovers.count
        if nothingToDo && hiddenCount == 0 {
            VStack(spacing: 8) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.secondary)
                Text("Nothing to do — check back later.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, sheetHeight)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(grouped, id: \.source.id) { group in
                        let style = SourceStyle.forSource(group.source.id)
                        section(id: group.source.id) {
                            sectionHeader(title: group.source.displayName, symbol: style.symbol,
                                          color: style.color, count: group.items.count,
                                          sourceID: group.source.id, items: group.items)
                        } content: {
                            LazyVGrid(columns: columns, spacing: 12) {
                                // Apps the App Store has to update itself collapse
                                // into one hand-off card — individual cards would
                                // offer a button that can't do anything.
                                let handoff = group.items.filter { !$0.scriptedInstall && $0.sourceID == "mas" }
                                ForEach(group.items.filter { !handoff.contains($0) }) { item in
                                    UpdateCard(item: item)
                                }
                                if !handoff.isEmpty { AppStoreHandoffCard(items: handoff) }
                            }
                        }
                    }
                    leftoverSection
                    hiddenSection
                }
                .padding(.top, 10).padding(.bottom, 12 + scrollSlack)
                // Collapse state lives in @AppStorage, whose updates arrive
                // outside any withAnimation transaction — so animate on the
                // value itself. On the whole list, so the sections below slide
                // up and down with the one that's rolling.
                .animation(Self.roll, value: collapsedRaw)
                .animation(Self.roll, value: showHidden)
            }
            .scrollPosition($scrollPosition)
            .contentMargins(.top, sheetHeight, for: .scrollContent)
            .contentMargins(.top, sheetHeight, for: .scrollIndicators)
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geo in
                scrollState.geometry = geo
            }
        }
    }

    /// One section: a header, and — unless collapsed — its content, together
    /// in a SectionPanel so the outline shows what belongs to the section and
    /// collapsing rolls the panel up into the header pill.
    private func section<Header: View, Content: View>(
        id: String, expanded: Bool? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isExpanded = expanded ?? !collapsed.contains(id)
        return VStack(alignment: .leading, spacing: 0) {
            header()
            // The content stays in the layout and its height animates between
            // zero and natural size, clipped and pinned to the top — so it
            // unrolls from under the header rather than popping or fading.
            content()
                .frame(maxWidth: .infinity)
                // Room below the header band's fade before the first cards.
                .padding(.horizontal, Self.panelInset).padding(.top, 14).padding(.bottom, 12)
                // Keep the natural height even while the frame is shrunk, so
                // the clip uncovers the cards instead of squashing them.
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    scrollState.contentHeights[id] = height
                }
                .frame(height: isExpanded ? nil : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
        }
        .modifier(SectionPanel())
        .padding(.horizontal, Self.panelMargin)
    }

    private func sectionHeader(title: String, symbol: String, color: Color, count: Int,
                               subtitle: String? = nil,
                               sourceID: String? = nil,
                               items: [UpdateItem] = []) -> some View {
        let id = sourceID ?? title
        let isCollapsed = collapsed.contains(id)
        return HStack(spacing: 6) {
            // Everything left of the Update button toggles the section.
            Button { toggleCollapsed(id) } label: {
                headerLabel(symbol: symbol, color: color, title: title, count: count,
                            subtitle: subtitle, expanded: !isCollapsed)
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Show \(title)" : "Hide \(title)")

            if let sourceID, items.contains(where: { $0.scriptedInstall }) {
                let pending = items.filter { $0.scriptedInstall }.count
                Button {
                    controller.updateAll(sourceID: sourceID)
                } label: {
                    Text(pending > 1 ? "Update all \(title)" : "Update \(title)")
                        .font(.caption)
                }
                .glass().controlSize(.small)
                // Match the panel's capsule ends; the default small glass shape
                // is a rounded rectangle with visibly tighter corners.
                .buttonBorderShape(.capsule)
            } else if sourceID == "macos", !items.isEmpty {
                // macOS installs happen in System Settings, but the section
                // still gets the same pill button as every other source.
                Button {
                    if let url = URL(string: SystemUpdateSource.settingsURL) { NSWorkspace.shared.open(url) }
                } label: {
                    Text("Update macOS").font(.caption)
                }
                .glass().controlSize(.small)
                .buttonBorderShape(.capsule)
                .help("Opens Software Update in System Settings")
            }
        }
        .padding(.leading, 10).padding(.trailing, 5)
        .frame(height: SectionPanel.headerHeight)
        .font(.subheadline.bold())
    }

    /// Chevron, icon, title and count — shared by every section header.
    private func headerLabel(symbol: String, color: Color, title: String, count: Int,
                             subtitle: String?, expanded: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.caption2.bold()).foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 10)
            Image(systemName: symbol).foregroundStyle(color)
            Text(title).foregroundStyle(.primary)
            // Number in the primary text colour, source colour in the pill:
            // coloured digits on a same-colour pill vanished in dark mode (App
            // Store blue) and would in light (Sparkle yellow).
            Text("\(count)")
                .font(.caption2).foregroundStyle(.primary)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(color.opacity(0.32), in: Capsule())
            if let subtitle {
                Text(subtitle).font(.caption).fontWeight(.regular).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    /// Third-party kexts sitting in /Library/Extensions that macOS isn't
    /// loading — leftovers from old installers, offered for removal.
    @ViewBuilder
    private var leftoverSection: some View {
        let leftovers = controller.visibleLeftovers
        if !leftovers.isEmpty {
            section(id: "Leftover drivers") {
                sectionHeader(title: "Leftover drivers", symbol: "trash.slash.fill", color: .red,
                              count: leftovers.count, subtitle: "not loaded — safe to remove")
            } content: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("On disk but the kernel isn't using them — typically left behind by an old printer, dock, or drive-enclosure installer.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(leftovers) { kext in LeftoverCard(kext: kext) }
                    }
                }
            }
        }
    }

    @AppStorage("showHidden") private var showHidden = false

    /// Everything the user chose to ignore, collapsed by default.
    @ViewBuilder
    private var hiddenSection: some View {
        let items = controller.hiddenItems
        let kexts = controller.hiddenLeftovers
        let total = items.count + kexts.count
        if total > 0 {
            section(id: "Hidden", expanded: showHidden) {
                Button {
                    let collapsing = showHidden
                    setSection("Hidden", collapsing: collapsing) { showHidden.toggle() }
                } label: {
                    headerLabel(symbol: "eye.slash.fill", color: .secondary, title: "Hidden",
                                count: total, subtitle: nil, expanded: showHidden)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .frame(height: SectionPanel.headerHeight)
                .font(.subheadline.bold())
            } content: {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(items) { item in
                        HiddenCard(id: item.id, name: item.name,
                                   detail: "\(item.installedVersion) → \(item.latestVersion)",
                                   appPath: item.appPath,
                                   style: SourceStyle.forSource(item.sourceID))
                    }
                    ForEach(kexts) { kext in
                        HiddenCard(id: kext.id, name: kext.name, detail: "v\(kext.version) · leftover driver",
                                   appPath: nil, style: SourceStyle(symbol: "trash.slash.fill", color: .red))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var errorSummary: some View {
        let errors = controller.state.sourceErrors
        if !errors.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(errors.sorted(by: { $0.key < $1.key }), id: \.key) { sourceID, message in
                    let name = UpdateController.allSources.first { $0.id == sourceID }?.displayName ?? sourceID
                    Label("\(name): \(message)", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.orange.opacity(0.08))
        }
    }
}

/// Shared Liquid Glass window background: real glassEffect (macOS 26+) with a
/// user-tunable window-background wash. No custom edge treatment — the titled
/// window already gets the system's corner mask, border, and shadow, and
/// drawing our own on top reads as fake white lines.
struct GlassBackground: View {
    static let cornerRadius: CGFloat = 16
    @AppStorage(Prefs.glassTintKey) private var tint: Double = 0.35

    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
            // 0 leaves the system's Liquid Glass untouched; higher values lay
            // an increasingly opaque light/dark wash over it.
            Rectangle()
                .fill(Theme.wash.opacity(tint * 0.9))
        }
        .ignoresSafeArea()
    }
}
