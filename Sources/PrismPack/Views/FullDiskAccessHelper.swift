import SwiftUI
import AppKit

/// Full Disk Access (Phase 9). An app can't add itself to the list, and
/// macOS keeps the signature of the copy that was added: switching an old
/// entry off and on doesn't cover a new build (31 Oct 2026 test). So this
/// opens the Settings page next to a small window holding *this* copy's icon,
/// to drag into the list.
enum FullDiskAccess {
    private static var panel: NSPanel?

    /// Whether this running copy has Full Disk Access. macOS has no API for
    /// it; the system privacy database opens only with it, so open it and
    /// close it at once, reading nothing. A new grant shows after a relaunch.
    static var isGranted: Bool {
        let fd = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        guard fd >= 0 else { return false }
        Darwin.close(fd)
        return true
    }

    /// Opens System Settings on the page with the list. The address macOS 13
    /// and later use first, the older one (macOS 12) if that fails.
    static func openSystemSettingsPage() {
        let current = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")!
        let older = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(current, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { NSWorkspace.shared.open(older) }
        }
    }

    static func openSettings() {
        openSystemSettingsPage()
        showHelper()
    }

    static func showHelper() {
        if let panel { panel.orderFrontRegardless(); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 360),
                        styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                        backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.title = "Allow \(AppIdentity.name)"
        // Above System Settings, so the icon stays reachable while dragging.
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentViewController = NSHostingController(rootView: FullDiskAccessHelper { close() })
        if let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.maxX - 360, y: screen.maxY - 420))
        }
        panel = p
        p.orderFrontRegardless()
    }

    static func close() {
        panel?.close()
        panel = nil
    }
}

private struct FullDiskAccessHelper: View {
    let onClose: () -> Void
    private let appURL = Bundle.main.bundleURL

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable().frame(width: 80, height: 80)
                // A plain file URL. `NSItemProvider(contentsOf:)` offered a file
                // copy, which System Settings' list ignored (31 Oct 2026).
                .onDrag { NSItemProvider(object: appURL as NSURL) }
                .help("Drag into the list in System Settings")
            Text("Drag this icon into the list").font(.headline)
            Text("macOS guards each app's data folders. Only apps you allow in System Settings may move them to the Trash for you.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                // Safe here: the panel has a fixed width, unlike the pages.
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                step(1, "Open System Settings. It goes straight to Privacy & Security, Full Disk Access. (In Settings' own search it is listed as \"Allow applications to access all user files\".)")
                step(2, "Drag the icon above into the list, or click + and choose \(AppIdentity.name), and make sure its switch is on.")
                step(3, "If macOS asks, choose Quit & Reopen. \(AppIdentity.name) restarts in the menu bar: click the prism to open the window again.")
            }
            HStack {
                Button("Close", action: onClose).glass()
                Spacer()
                Button("Open System Settings") { FullDiskAccess.openSystemSettingsPage() }.glassProminent(.blue)
            }
        }
        .padding(20)
        .padding(.top, 8)
        .frame(width: 340)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Text(text).font(.callout)
                // Safe here: the panel has a fixed width, unlike the pages.
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
