import SwiftUI
import AppKit

/// "Uninstall…" for the app pop-ups (Discover, Installed, Updates). It asks
/// first, then shows the removal's progress, failure or result in place.
/// The question is an NSAlert: SwiftUI's confirmationDialog, opened from
/// inside a popover, hung without taking clicks on macOS 27.
struct UninstallButton: View {
    @EnvironmentObject var controller: UpdateController
    let removal: Removal
    /// The update row this pop-up belongs to, which goes once removed.
    var updateID: String? = nil

    private var state: InstallState? { controller.installStates[removal.item.id] }

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
                    Label(removal.actionTitle, systemImage: "trash")
                }
                .glassProminent(.red)
            }
        }
    }

    private func confirm() {
        let alert = NSAlert()
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
