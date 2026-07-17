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
            w.minSize = NSSize(width: 460, height: 380)
            window = w
        }
        let wasVisible = window?.isVisible ?? false
        window?.makeKeyAndOrderFront(nil)
        if !wasVisible { window?.centerExactly() }
    }
}

struct UpdatesView: View {
    @EnvironmentObject var controller: UpdateController

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
        .frame(minWidth: 460, minHeight: 380)
        .background(GlassBackground())
        .onAppear { controller.reloadFromDisk() }
    }

    // MARK: Chrome


    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text("UpdateScout").font(.title3).bold()
                if let lastCheck = controller.state.lastCheck {
                    Text("Last checked \(lastCheck.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if controller.isChecking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button("Check Now") { controller.checkNow() }
                    .buttonStyle(.borderedProminent)
            }
            Button { SettingsWindow.shared.show() } label: {
                Image(systemName: "gearshape").font(.title3)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)   // clear the transparent titlebar's traffic lights
        .padding(.bottom, 30)
    }

    @ViewBuilder
    private var statusBanner: some View {
        let count = controller.visibleItems.count
        HStack(spacing: 10) {
            Image(systemName: count == 0 ? "checkmark.seal.fill" : "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .font(.title2)
                .foregroundStyle(count == 0 ? .green : .orange)
            Text(count == 0 ? "Everything is up to date"
                            : "^[\(count) update](inflect: true) available")
                .font(.title2.weight(.semibold))
            Spacer()
            if count > 0 && controller.visibleItems.contains(where: { $0.scriptedInstall }) {
                Button("Update All") { controller.updateAll() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: Content

    @ViewBuilder
    private var updateList: some View {
        if controller.visibleItems.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.secondary)
                Text("Nothing to do — check back later.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(grouped, id: \.source.id) { group in
                        Text(group.source.displayName)
                            .font(.subheadline).bold().foregroundStyle(.secondary)
                            .padding(.horizontal, 20).padding(.top, 12)
                        ForEach(group.items) { item in
                            UpdateRow(item: item)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .padding(.bottom, 16)
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
    @AppStorage("glassStyle") private var glassStyleRaw = GlassStyle.regular.rawValue
    private var glassStyle: GlassStyle { GlassStyle.from(glassStyleRaw) }

    var body: some View {
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(glassStyle.washOpacity))
                .animation(.easeInOut(duration: 0.25), value: glassStyleRaw)
        }
        .ignoresSafeArea()
    }
}
