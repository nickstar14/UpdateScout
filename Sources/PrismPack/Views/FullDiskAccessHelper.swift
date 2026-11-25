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
        if fd >= 0 { Darwin.close(fd); return true }
        // A second guarded place, in case macOS 27.3 changes the first: the
        // user's Safari folder opens only with Full Disk Access (when it
        // exists; a missing folder says nothing).
        if let dir = opendir(NSHomeDirectory() + "/Library/Safari") { closedir(dir); return true }
        return false
    }

    /// macOS 27.3 reworked the privacy lists (Files & Folders, Full Disk
    /// Access, System & App Protection Override). It is still in beta, so
    /// this wording may change until 27.3 ships.
    static var isMacOS27_3OrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 3, patchVersion: 0))
    }

    static let purpose = "Apps keep their data in folders macOS guards, so other apps can't change them. With Full Disk Access, \(AppIdentity.name) can move an app's data folders to the Trash when you remove the app or clean up orphaned files. Without it, those folders are listed with Show in Finder so you can move them yourself. Updates and installs never need it."

    /// How to switch it off again, for the macOS in use.
    static var disableSteps: String {
        isMacOS27_3OrLater
            ? "To turn it off: System Settings, Privacy & Security, Full Disk Access, select \(AppIdentity.name) and click \u{2212}."
            : "To turn it off: System Settings, Privacy & Security, Full Disk Access, switch \(AppIdentity.name) off."
    }

    /// How to allow it, for the macOS in use.
    static var allowSteps: String {
        isMacOS27_3OrLater
            ? "Click Allow\u{2026}, then in Full Disk Access click +, choose \(AppIdentity.name) and choose Bypass System Protections."
            : "Click Allow\u{2026}, then drag the \(AppIdentity.name) icon from the small window into the Full Disk Access list and switch it on."
    }

    static let betaNote = "macOS 27.3's Full Disk Access is still in beta and may change before it is released."

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
        // On the display of the window the user clicked from (it opened on the
        // main display even when that was somewhere else, 25 Nov 2026).
        if let screen = (NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main)?.visibleFrame {
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
    private let new27 = FullDiskAccess.isMacOS27_3OrLater

    var body: some View {
        VStack(spacing: 14) {
            icon
            Text(new27 ? "Add \(AppIdentity.name) to Full Disk Access" : "Drag this icon into the list").font(.headline)
            Text("macOS guards each app's data folders. Only apps you allow in System Settings may move them to the Trash for you. This is optional.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                // Safe here: the panel has a fixed width, unlike the pages.
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                if new27 {
                    step(1, "Click Open System Settings. It goes to Privacy & Security.")
                    step(2, "Click Full Disk Access, click +, and choose \(AppIdentity.name). Show in Finder finds it for you.")
                    step(3, "Choose Bypass System Protections, then confirm with your password.")
                    step(4, "If macOS says Quit Now, click it, then click the prism in the menu bar to open \(AppIdentity.name) again.")
                } else {
                    step(1, "Open System Settings. It goes straight to Privacy & Security, Full Disk Access. (In Settings' own search it is listed as \"Allow applications to access all user files\".)")
                    step(2, "Drag the icon above into the list, or click + and choose \(AppIdentity.name), and make sure its switch is on.")
                    step(3, "If macOS asks, choose Quit & Reopen. \(AppIdentity.name) restarts in the menu bar: click the prism to open the window again.")
                }
            }
            if new27 {
                Text(FullDiskAccess.betaNote).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Close", action: onClose).glass()
                if new27 {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([appURL]) }.glass()
                }
                Spacer()
                Button("Open System Settings") { FullDiskAccess.openSystemSettingsPage() }.glassProminent(.blue)
            }
        }
        .padding(20)
        .padding(.top, 8)
        .frame(width: 340)
    }

    @ViewBuilder private var icon: some View {
        let image = Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path)).resizable().frame(width: 80, height: 80)
        if new27 {
            // macOS 27.3 reportedly no longer takes a dragged icon: only +.
            image
        } else {
            // A plain file URL. `NSItemProvider(contentsOf:)` offered a file
            // copy, which System Settings' list ignored (31 Oct 2026).
            image.onDrag { NSItemProvider(object: appURL as NSURL) }
                .help("Drag into the list in System Settings")
        }
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
