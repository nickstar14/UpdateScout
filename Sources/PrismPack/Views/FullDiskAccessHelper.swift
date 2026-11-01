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

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
        showHelper()
    }

    static func showHelper() {
        if let panel { panel.orderFrontRegardless(); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
                        styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                        backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.title = "Full Disk Access"
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

    /// Quit and open this same copy again, so the new grant applies. Asking
    /// System Settings to do it reopened the installed copy instead.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
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
                .help("Drag into the Full Disk Access list")
            Text("Drag this icon into the list").font(.headline)
            Text("macOS guards each app's data folders. Only apps with Full Disk Access may move them to the Trash for you.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                // Safe here: the panel has a fixed width, unlike the pages.
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                step(1, "In System Settings, select any old \(AppIdentity.name) or UpdateScout entry and click −.")
                step(2, "Drag the icon above into the list (or drag it from Show in Finder), and make sure its switch is on.")
                step(3, "Quit and reopen \(AppIdentity.name).")
            }
            Text("This copy: \(UninstallPanelText.shortPath(appURL.path))")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle)
            HStack {
                Button("Close", action: onClose)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([appURL]) }
                    .help("Drag it from Finder into the list instead")
                Spacer()
                Button("Quit and Reopen") { FullDiskAccess.relaunch() }.glass()
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
