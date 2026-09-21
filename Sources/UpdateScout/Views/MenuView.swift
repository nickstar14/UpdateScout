import SwiftUI

/// The compact menu bar bubble: a count + "click to view" button that opens
/// the main status window, plus settings and quit. Everything else lives in
/// UpdatesView.
struct MenuView: View {
    @EnvironmentObject var controller: UpdateController

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("UpdateScout").font(.headline)
                Spacer()
                Button { SettingsWindow.shared.show() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Quit UpdateScout")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            Button { UpdatesWindow.shared.show() } label: {
                VStack(spacing: 3) {
                    if controller.badgeCount == 0 {
                        Label("Everything is up to date", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.body.weight(.medium))
                    } else {
                        Text("^[\(controller.badgeCount) update](inflect: true) available")
                            .font(.title3.weight(.semibold))
                    }
                    let leftovers = controller.visibleLeftovers.count
                    Text(leftovers > 0
                         ? "Click here to view · ^[\(leftovers) leftover driver](inflect: true) to remove"
                         : "Click here to view")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            HStack {
                if let lastCheck = controller.state.lastCheck {
                    Text("Checked \(lastCheck.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if controller.isChecking {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(width: 280)
        .onAppear { controller.reloadFromDisk() }
    }
}
