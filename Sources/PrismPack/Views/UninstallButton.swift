import SwiftUI
import AppKit

/// "Uninstall…" for the app pop-ups (Discover, Installed, Updates). Apps
/// and Homebrew apps open the uninstall window, which lists the app and what
/// it leaves behind before anything moves (Phase 9). Everything else asks
/// with an NSAlert: SwiftUI's confirmationDialog, opened from inside a
/// popover, hung without taking clicks on macOS 27.
struct UninstallButton: View {
    @EnvironmentObject var controller: UpdateController
    let removal: Removal
    /// The update row this pop-up belongs to, which goes once removed.
    var updateID: String? = nil
    /// Says which copy, when a pop-up offers more than one removal.
    var title: String? = nil

    private var state: InstallState? {
        controller.installStates[removal.item.id] ?? removal.zap.flatMap { controller.installStates[$0.item.id] }
    }

    var body: some View {
        if let state, state.isActive {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(state == .queued ? "Queued" : "Removing").font(.caption).foregroundStyle(.secondary)
                    .help(state.label)
            }
        } else if state == .done {
            StatusPill(text: removal.kind == "app" ? "In the Trash" : "Removed", color: .secondary)
        } else {
            HStack(spacing: 6) {
                if let error = state?.errorMessage {
                    StatusPill(text: error == "Needs admin" ? "Needs admin" : "Failed",
                               color: error == "Needs admin" ? .orange : .red).help(error)
                }
                Button(role: .destructive) { confirm() } label: {
                    Label(title ?? removal.actionTitle, systemImage: "trash")
                }
                .glassDestructive()
            }
        }
    }

    private func confirm() {
        if removal.opensWindow {
            UninstallWindow.shared.show(removal, updateID: updateID)
            return
        }
        let alert = NSAlert()
        alert.icon = AskpassDialog.badgeIcon(symbol: "exclamationmark")
        alert.messageText = "\(removal.actionTitle) \(removal.name)?"
        alert.informativeText = removal.explanation
        alert.alertStyle = .warning
        let go = alert.addButton(withTitle: removal.actionTitle)
        go.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        go.keyEquivalent = ""
        if alert.runModal() == .alertFirstButtonReturn {
            controller.uninstall(removal, updateID: updateID)
        }
    }
}
