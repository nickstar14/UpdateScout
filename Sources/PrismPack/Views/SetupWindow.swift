import SwiftUI
import AppKit

/// The first-run Setup window (Nick, 25 Nov 2026): opens once on a first
/// launch, even when everything is in place, and again from Settings > Setup.
/// The tools come first; Full Disk Access is optional and says what it is for,
/// in words that follow the macOS in use.
@MainActor
enum SetupWindow {
    static let shownKey = "didShowSetupWindow"
    private static var window: NSWindow?

    static func showOnceIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: shownKey) else { return }
        UserDefaults.standard.set(true, forKey: shownKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { show() }
    }

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil); return }
        let host = NSHostingController(rootView: SetupView { close() })
        let w = NSWindow(contentViewController: host)
        w.title = "Set up \(AppIdentity.name)"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
        window = nil
    }
}

private struct SetupView: View {
    let onDone: () -> Void
    @StateObject private var deps = DependencyManager()
    @State private var granted = FullDiskAccess.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AppLogo(size: 50, trimmed: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up \(AppIdentity.name)").font(.title2.weight(.semibold))
                    Text("What it uses to find and install updates. You can open this again in Settings.")
                        .font(.callout).foregroundStyle(.secondary).wraps()
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(deps.dependencies.filter { !$0.optional }) { dep in toolRow(dep) }
                if let error = deps.installError {
                    Text(error).font(.caption).foregroundStyle(Color.red.readable).lineLimit(3)
                }
                Divider()
                fullDiskRow
            }
            HStack {
                Spacer()
                Button("Done", action: onDone).glassProminent(.blue).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = FullDiskAccess.isGranted
            deps.refresh()
        }
    }

    private func toolRow(_ dep: DependencyManager.Dependency) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if dep.installed {
                    Label(dep.name, systemImage: "checkmark.circle.fill").foregroundStyle(Color.green.readable)
                } else {
                    Label(dep.name, systemImage: "exclamationmark.triangle").foregroundStyle(Color.orange.readable)
                }
                Text(dep.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !dep.installed {
                if deps.installingID == dep.id {
                    ProgressView().controlSize(.small)
                } else if dep.brewFormula != nil {
                    Button("Install") { deps.install(dep) }.glassProminent(SourceStyle.forSource("homebrew").color)
                } else if let manual = dep.manualURL.flatMap(URL.init(string:)) {
                    Link("Get\u{2026}", destination: manual)
                }
            }
        }
    }

    private var fullDiskRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if granted {
                    Label("Full Disk Access: Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.green.readable)
                    Text("It stays on through updates. \(FullDiskAccess.disableSteps)")
                        .font(.caption).foregroundStyle(.secondary).wraps()
                } else {
                    Label("Full Disk Access (optional)", systemImage: "lock.shield")
                    Text(FullDiskAccess.purpose).font(.caption).foregroundStyle(.secondary).wraps()
                    Text(FullDiskAccess.allowSteps).font(.caption).foregroundStyle(.secondary).wraps()
                }
                if FullDiskAccess.isMacOS27_3OrLater {
                    Text(FullDiskAccess.betaNote).font(.caption).foregroundStyle(.secondary).wraps()
                }
            }
            Spacer(minLength: 12)
            if !granted {
                Button("Allow\u{2026}") { FullDiskAccess.openSettings() }.glass()
            }
        }
    }
}

private extension View {
    /// Wraps to as many lines as it needs. Safe here: the Setup window has a
    /// fixed width, unlike the pages (see the page-header note in CLAUDE.md).
    func wraps() -> some View { fixedSize(horizontal: false, vertical: true) }
}
