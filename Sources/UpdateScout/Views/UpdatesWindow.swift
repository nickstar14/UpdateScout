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
            w.setContentSize(NSSize(width: 560, height: 640))
            w.minSize = NSSize(width: 380, height: 380)
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
    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: ",").map(String.init)) }
    private func toggleCollapsed(_ id: String) {
        var set = collapsed
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        withAnimation(.easeInOut(duration: 0.2)) { collapsedRaw = set.sorted().joined(separator: ",") }
    }

    private var grouped: [(source: any UpdateSource, items: [UpdateItem])] {
        UpdateController.allSources.compactMap { source in
            let items = controller.visibleItems.filter { $0.sourceID == source.id }
            return items.isEmpty ? nil : (source, items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            statusBanner
            Divider().padding(.horizontal, 20)
            updateList
            errorSummary
        }
        .frame(minWidth: 380, minHeight: 380)
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
        .padding(.top, 34)   // clear the transparent titlebar's traffic lights
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
    private static let tileWidth: CGFloat = 152
    private let columns = [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth),
                                    spacing: 12, alignment: .top)]

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
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(grouped, id: \.source.id) { group in
                        let style = SourceStyle.forSource(group.source.id)
                        sectionHeader(title: group.source.displayName, symbol: style.symbol,
                                      color: style.color, count: group.items.count,
                                      sourceID: group.source.id, items: group.items)
                        if !collapsed.contains(group.source.id) {
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
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                        }
                    }
                    leftoverSection
                    hiddenSection
                }
                .padding(.vertical, 12)
            }
        }
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
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.bold()).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                        .frame(width: 10)
                    Image(systemName: symbol).foregroundStyle(color)
                    Text(title).foregroundStyle(.primary)
                    // Number in the primary text colour, source colour in the
                    // pill: coloured digits on a same-colour pill vanished in
                    // dark mode (App Store blue) and would in light (Sparkle yellow).
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
                // Match the header bar's capsule; the default small glass shape
                // is a rounded rectangle with visibly tighter corners.
                .buttonBorderShape(.capsule)
            }
        }
        // A full-width outlined bar: keeps the title legible on any glass
        // tint and doubles as the divider between sections.
        .padding(.leading, 10).padding(.trailing, 5).padding(.vertical, 5)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14)))
        .font(.subheadline.bold())
        .padding(.horizontal, 20).padding(.top, 10)
    }

    /// Third-party kexts sitting in /Library/Extensions that macOS isn't
    /// loading — leftovers from old installers, offered for removal.
    @ViewBuilder
    private var leftoverSection: some View {
        let leftovers = controller.visibleLeftovers
        if !leftovers.isEmpty {
            sectionHeader(title: "Leftover drivers", symbol: "trash.slash.fill", color: .red,
                          count: leftovers.count, subtitle: "not loaded — safe to remove")
            if !collapsed.contains("Leftover drivers") {
                Text("On disk but the kernel isn't using them — typically left behind by an old printer, dock, or drive-enclosure installer.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(leftovers) { kext in LeftoverCard(kext: kext) }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
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
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showHidden.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showHidden ? "chevron.down" : "chevron.right")
                        .font(.caption.bold()).frame(width: 10)
                    Image(systemName: "eye.slash.fill").foregroundStyle(.secondary)
                    Text("Hidden").foregroundStyle(.secondary)
                    Text("\(total)")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                    Spacer()
                }
                .font(.subheadline.bold())
                .contentShape(Rectangle())
                .padding(.leading, 10).padding(.trailing, 10).padding(.vertical, 5)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.top, 14)

            if showHidden {
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
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
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
