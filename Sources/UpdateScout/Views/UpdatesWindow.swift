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

/// The pages in the sidebar.
enum Page: String, CaseIterable, Identifiable {
    case updates, discover, installed, activity, settings, buttonLab
    var id: String { rawValue }

    var title: String {
        switch self {
        case .updates: "Updates"
        case .discover: "Discover"
        case .installed: "Installed"
        case .activity: "Activity"
        case .settings: "Settings"
        case .buttonLab: "Button lab"
        }
    }

    var symbol: String {
        switch self {
        case .updates: "arrow.down.circle"
        case .discover: "magnifyingglass"
        case .installed: "checkmark.circle"
        case .activity: "clock.arrow.circlepath"
        case .settings: "gearshape"
        case .buttonLab: "flask"
        }
    }

    /// In the sidebar, in order. The Button lab only while it's compiled in.
    static var sidebar: [Page] {
        [.updates, .discover, .installed, .activity, .settings] + (ButtonLab.enabled ? [.buttonLab] : [])
    }
}

/// The main window: an edge-to-edge sidebar and one unified toolbar.
@MainActor
final class UpdatesWindow {
    static let shared = UpdatesWindow()
    private var window: NSWindow?

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
            let hosting = NSHostingController(
                rootView: MainView().environmentObject(UpdateController.shared))
            // SwiftUI's .toolbar and .navigationTitle drive the window's own
            // unified toolbar and title.
            hosting.sceneBridgingOptions = [.toolbars, .title]
            let w = NSWindow(contentViewController: hosting)
            w.title = UpdateController.shared.page.title
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 860, height: 680))
            w.minSize = NSSize(width: 640, height: 420)
            w.setFrameAutosaveName("MainWindow")
            window = w
        }
        let wasVisible = window?.isVisible ?? false
        window?.makeKeyAndOrderFront(nil)
        // The first time, centre it; after that the autosaved frame wins.
        if !wasVisible, UserDefaults.standard.string(forKey: "NSWindow Frame MainWindow") == nil {
            window?.centerExactly()
        }
    }
}

struct MainView: View {
    @EnvironmentObject var controller: UpdateController
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            // A very quick cross-fade between pages: each page is its own
            // identity, so changing page removes one and inserts the other,
            // and the container animates both.
            ZStack {
                Group {
                    switch controller.page {
                    case .updates: UpdatesPage()
                    case .discover: DiscoverPlaceholder()
                    case .installed: InstalledPage()
                    case .activity: ActivityPage()
                    case .settings: SettingsView()
                    case .buttonLab: ButtonLabPage()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(controller.page)
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.14), value: controller.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlassBackground())
        }
        .navigationTitle(controller.page.title)
        .toolbar {
            // The system didn't add its own sidebar toggle to this window, so
            // put the standard one where it goes, at the toolbar's leading end.
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                }
                .help("Show or hide the sidebar")
            }
        }
        .onAppear { controller.reloadFromDisk() }
        .sheet(item: $controller.review) { request in
            MajorUpgradeReview(request: request).environmentObject(controller)
        }
        .sheet(item: $controller.passwordRequest) { request in
            PasswordSheet(request: request).environmentObject(controller)
                .interactiveDismissDisabled()
        }
    }
}

/// App icon, name and version at the top, a visible gap, then the pages as
/// standard rows (so the system's sidebar icon size setting applies).
private struct Sidebar: View {
    @EnvironmentObject var controller: UpdateController

    var body: some View {
        List(selection: Binding(get: { controller.page }, set: { if let p = $0 { controller.page = p } })) {
            HStack(spacing: 10) {
                AppLogo(size: 52, trimmed: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "UpdateScout")
                        .font(.title2.weight(.semibold))
                    Text("Version \(SelfUpdater.version)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.bottom, 10)
            .selectionDisabled()

            ForEach(Page.sidebar) { page in
                Label(page.title, systemImage: page.symbol)
                    .badge(badge(for: page))
                    .tag(page)
            }
        }
        .listStyle(.sidebar)
    }

    private func badge(for page: Page) -> Int {
        switch page {
        case .updates: controller.visibleItems.count
        default: 0
        }
    }
}

/// Discover arrives in phase 6; until then its page says so.
private struct DiscoverPlaceholder: View {
    var body: some View {
        ContentUnavailableView("Discover is coming", systemImage: "magnifyingglass",
                               description: Text("Search and install apps and tools from Homebrew, npm, crates.io and more. Built in a later phase."))
    }
}

/// The window background: the plain system background, with the Glass
/// slider's wash (silver in light, midnight in dark) over it. The slider
/// changes only this wash, never the section panels.
struct GlassBackground: View {
    @AppStorage(Prefs.glassTintKey) private var tint: Double = 0.35

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Theme.wash.opacity(tint * 0.9)
        }
        .ignoresSafeArea()
    }
}
