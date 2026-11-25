import SwiftUI
import AppKit
import Combine

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

/// The pages in the sidebar.
enum Page: String, CaseIterable, Identifiable {
    case updates, discover, installed, orphans, activity, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .updates: "Updates"
        case .discover: "Discover"
        case .installed: "Installed"
        case .orphans: "Orphaned App Files"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .updates: "arrow.down.circle"
        case .discover: "magnifyingglass"
        case .installed: "checkmark.circle"
        case .orphans: "archivebox"
        case .activity: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }

}

/// The sidebar toggle as a titlebar accessory: a glass circle at the right end
/// of the sidebar section, which follows the divider as the sidebar is resized
/// and sits beside the traffic lights when the sidebar is collapsed.
@MainActor
final class SidebarToggleAccessory: NSTitlebarAccessoryViewController {
    private weak var split: NSSplitViewController?
    private weak var sidebarItem: NSSplitViewItem?
    private let model = Model()
    private var observers: [NSObjectProtocol] = []
    /// Where the accessory starts (after the traffic lights) plus the gap kept
    /// between the circle and the divider.
    private static let lightsWidth: CGFloat = 96
    private static let height: CGFloat = 52

    final class Model: ObservableObject { @Published var open = true }

    init(split: NSSplitViewController, sidebarItem: NSSplitViewItem) {
        self.split = split
        self.sidebarItem = sidebarItem
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .leading
        let host = NSHostingView(rootView: ToggleButton(model: model) { [weak split] in split?.toggleSidebar(nil) })
        host.frame = NSRect(x: 0, y: 0, width: 140, height: Self.height)
        view = host
        // The sidebar's width changes by dragging the divider or collapsing.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: split.splitView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        })
        DispatchQueue.main.async { [weak self] in self?.follow() }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func follow() {
        guard let split, let sidebarItem else { return }
        let open = !sidebarItem.isCollapsed
        model.open = open
        let sidebarWidth = split.splitView.arrangedSubviews.first?.frame.width ?? 210
        let width = open ? max(sidebarWidth - Self.lightsWidth, 40) : 48
        if abs(view.frame.width - width) > 0.5 { view.frame.size.width = width }
    }

    private struct ToggleButton: View {
        @ObservedObject var model: Model
        let action: () -> Void

        var body: some View {
            HStack {
                Spacer(minLength: 0)
                Button(action: action) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 13, weight: .regular))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .modifier(CircleGlass())
                .help("Show or hide the sidebar")
                .accessibilityLabel("Sidebar")
            }
            .frame(maxHeight: .infinity)
        }
    }

    private struct CircleGlass: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 26.0, *) {
                content.buttonStyle(.glass).buttonBorderShape(.circle)
            } else {
                content.buttonStyle(.bordered).buttonBorderShape(.circle)
            }
        }
    }
}

/// The main window: an edge-to-edge sidebar and one unified toolbar.
@MainActor
final class UpdatesWindow {
    static let shared = UpdatesWindow()
    private var window: NSWindow?
    private var titleWatch: AnyCancellable?
    private var sidebarToggle: SidebarToggleAccessory?

    /// The window, for sheets that attach to it.
    var mainWindow: NSWindow? { window }

    /// Frame of the window when it's on screen — other windows centre on it
    /// rather than on the display.
    var visibleFrame: NSRect? {
        guard let window, window.isVisible else { return nil }
        return window.frame
    }

    func show(page: Page? = nil) {
        if let page { UpdateController.shared.page = page }
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            // A native split view, so the system's sidebar toggle and the
            // sidebar tracking separator work: the toggle sits in the sidebar's
            // own toolbar section, left of the divider, and stays put when
            // the sidebar's grey hides (Nick, 3 Nov 2026). Two hosting views,
            // one per column. (A single hosting view around a SwiftUI
            // NavigationSplitView gave a dead toggle.)
            let sidebarHost = NSHostingController(
                rootView: Sidebar().environmentObject(UpdateController.shared))
            sidebarHost.sizingOptions = []
            let detailHost = NSHostingController(
                rootView: MainView().environmentObject(UpdateController.shared))
            // SwiftUI's .navigationTitle and .navigationSubtitle drive the
            // window's title.
            detailHost.sceneBridgingOptions = [.toolbars, .title]
            // Pages never size the window; a long page scrolls. Even
            // `.minSize` let Orphaned App Files stretch it to 2,367 pt
            // (31 Oct 2026): wrapping text measured at its narrowest made the
            // minimum height huge. The window's own minSize below is enough.
            detailHost.sizingOptions = []
            let split = NSSplitViewController()
            let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
            sidebarItem.minimumThickness = 190
            sidebarItem.maximumThickness = 260
            sidebarItem.canCollapse = true
            split.addSplitViewItem(sidebarItem)
            split.addSplitViewItem(NSSplitViewItem(viewController: detailHost))
            let w = NSWindow(contentViewController: split)
            w.title = UpdateController.shared.page.title
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            // The sidebar toggle: SwiftUI owns the toolbar (each page's refresh and
            // Update All), and its toolbar has no room for the system's toggle in
            // the sidebar's section. So a titlebar accessory holds it: at the right
            // end of the sidebar, against the divider, and beside the traffic
            // lights when the sidebar is collapsed (Nick, 3 Nov 2026).
            let toggle = SidebarToggleAccessory(split: split, sidebarItem: sidebarItem)
            w.addTitlebarAccessoryViewController(toggle)
            sidebarToggle = toggle
            titleWatch = detailHost.publisher(for: \.title).sink { [weak w] title in
                if let title, !title.isEmpty { w?.title = title }
            }
            w.isReleasedWhenClosed = false
            // Nick's chosen opening size (31 Oct 2026); the saved frame wins after.
            w.setContentSize(NSSize(width: 914, height: 706))
            w.minSize = NSSize(width: 640, height: 420)
            w.setFrameAutosaveName("MainWindow")
            // The split view opens the sidebar at its minimum; give it the
            // ideal width so Discover's category names fit.
            split.view.layoutSubtreeIfNeeded()
            split.splitView.setPosition(210, ofDividerAt: 0)
            window = w
            // Closing the window frees everything the pages hold (Nick: light
            // as a menu bar app with the window closed). The window and its
            // views are dropped and built again on the next show; the saved
            // frame and the chosen page are kept.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    OrphanCache.shared.clear()
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.titleWatch = nil
                            self?.sidebarToggle = nil
                            self?.window?.contentViewController = nil
                            self?.window = nil
                            // With the views gone, free what they were showing
                            // (Discover's catalogue, icons), then hand the
                            // freed pages back to the system.
                            DiscoverModel.shared.releaseMemory()
                            IconCache.shared.clear()
                            Task { await DiscoverIcons.shared.releaseMemory() }
                            MemoryRelief.run(after: 0.5)
                        }
                    }
                }
            }
        }
        let wasVisible = window?.isVisible ?? false
        window?.makeKeyAndOrderFront(nil)
        // The first time, centre it; after that the autosaved frame wins.
        if !wasVisible, UserDefaults.standard.string(forKey: "NSWindow Frame MainWindow") == nil {
            window?.centerExactly()
        }
        // A frame saved while a page stretched the window can be taller than
        // the screen; bring it back within it.
        if let w = window, let visible = w.screen?.visibleFrame, w.frame.height > visible.height {
            w.setFrame(w.frame.intersection(visible), display: true)
        }
    }
}

/// The page column of the main window (the sidebar is its own hosting view,
/// see `UpdatesWindow`).
struct MainView: View {
    @EnvironmentObject var controller: UpdateController
    @AppStorage(Migration.noticeKey) private var showRenameNotice = false
    @ObservedObject private var discover = DiscoverModel.shared

    /// What's on screen: the page, and for Discover which of its parts, so
    /// moving between Discover's parts fades like moving between pages (Nick).
    private var shown: String {
        controller.page == .discover ? "discover:\(discover.spot)" : controller.page.rawValue
    }

    var body: some View {
        // A very quick cross-fade between pages: each page is its own
        // identity, so changing page removes one and inserts the other,
        // and the container animates both.
        ZStack {
            Group {
                switch controller.page {
                case .updates: UpdatesPage()
                case .discover: DiscoverPage()
                case .installed: InstalledPage()
                case .orphans: OrphansPage()
                case .activity: ActivityPage()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(shown)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.14), value: shown)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassBackground())
        .navigationTitle(controller.page == .discover ? discover.title : controller.page.title)
        .onAppear { controller.reloadFromDisk() }
        .sheet(item: $controller.review) { request in
            MajorUpgradeReview(request: request).environmentObject(controller)
        }
        .sheet(isPresented: $controller.showingAdoptionReview) {
            AdoptionReviewSheet().environmentObject(controller)
        }
        .sheet(isPresented: $showRenameNotice) {
            RenameWelcome { showRenameNotice = false }
        }
    }
}

/// App icon, name and version at the top, then the Library group and
/// Discover last (its parts open under it while it's the page); Activity and
/// Settings are pinned at the bottom (Phase 10). Standard rows, so the system's sidebar icon size applies.
struct Sidebar: View {
    @EnvironmentObject var controller: UpdateController
    @ObservedObject private var discover = DiscoverModel.shared

    /// A page, or one of Discover's parts.
    enum Item: Hashable { case page(Page), discover(DiscoverModel.Spot) }

    private var selection: Binding<Item?> {
        Binding(
            get: { controller.page == .discover ? .discover(discover.spot) : .page(controller.page) },
            set: { item in
                switch item {
                case .page(.discover)?: controller.page = .discover; discover.show(.featured)
                case .page(let page)?: controller.page = page
                case .discover(let spot)?: controller.page = .discover; discover.show(spot)
                case nil: break
                }
            })
    }

    var body: some View {
        List(selection: selection) {
            HStack(spacing: 10) {
                AppLogo(size: 52, trimmed: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppIdentity.name)
                        .font(.title2.weight(.semibold))
                    Text("Version \(SelfUpdater.version)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.bottom, 10)
            .selectionDisabled()

            // Discover goes last: its parts open under it, so nothing above
            // ever scrolls out of view (Nick, 1 Nov 2026).
            Section("Library") {
                row(.updates)
                row(.installed)
                row(.orphans)
            }
            Section {
                row(.discover)
                if controller.page == .discover { discoverParts }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 20)
        // Activity and Settings stay at the bottom; the list scrolls under
        // them in glass, as pages scroll under their own controls (Nick).
        .pinnedHeader(edge: .bottom) {
            VStack(spacing: 2) {
                pinnedRow(.activity)
                pinnedRow(.settings)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
    }

    /// A row in the bottom bar, drawn like the list's own rows.
    private func pinnedRow(_ page: Page) -> some View {
        Button { controller.page = page } label: {
            Label(page.title, systemImage: page.symbol)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
                .background(controller.page == page
                            ? RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.1))
                            : nil)
        }
        .buttonStyle(.plain)
    }

    private func row(_ page: Page) -> some View {
        Label(page.title, systemImage: page.symbol)
            .frame(minHeight: 26)
            .badge(page == .updates ? controller.visibleItems.count : 0)
            .tag(Item.page(page))
    }

    /// Discover's parts as one compact block: the list's own rows are all
    /// one height, which left big gaps between categories (Nick).
    private var discoverParts: some View {
        VStack(alignment: .leading, spacing: 0) {
            part("Featured", .featured, symbol: "star")
            part("New", .new, symbol: "sparkles")
            if discover.chips.contains(.apps) {
                heading("Homebrew")
                ForEach(DiscoverCategories.Category.allCases) { category in
                    part(category.rawValue, .category(category), dot: category.color,
                         count: discover.categoryCounts[category] ?? 0)
                }
            }
            heading("Tools and packages")
            // Homebrew's own lists first, then the package managers.
            let order: [DiscoverModel.Chip] = [.cli, .fonts, .runtimes, .python, .node, .rust, .ruby, .editors]
            ForEach(order.filter(discover.chips.contains)) { chip in
                part(chip.title, .chip(chip), dot: chip.color)
            }
        }
        .selectionDisabled()
    }

    private func part(_ title: String, _ spot: DiscoverModel.Spot, symbol: String? = nil,
                      dot: Color? = nil, count: Int = 0) -> some View {
        Button { controller.page = .discover; discover.show(spot) } label: {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 14)
                } else if let dot {
                    Circle().fill(dot).frame(width: 8, height: 8).frame(width: 14)
                }
                Text(title)
                Spacer(minLength: 4)
                if count > 0 { Text("\(count)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            }
            .font(.callout)
            .lineLimit(1)
            .padding(.leading, 10).padding(.trailing, 6)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .contentShape(Rectangle())
            .background(discover.spot == spot
                        ? RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.1))
                        : nil)
        }
        .buttonStyle(.plain)
    }

    private func heading(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.leading, 10).padding(.top, 8).padding(.bottom, 2)
    }

}

/// The window background: the plain system background. (A Glass slider that
/// laid a wash over it was removed: it changed nothing about the buttons and
/// panels, Nick, 3 Nov 2026.)
struct GlassBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
        }
        .ignoresSafeArea()
    }
}

