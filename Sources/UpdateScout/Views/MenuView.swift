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
                    Text("Click here to view")
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

/// One update row — shared by the status window.
struct UpdateRow: View {
    @EnvironmentObject var controller: UpdateController
    let item: UpdateItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).fontWeight(.medium)
                    Text("\(item.installedVersion) → \(item.latestVersion)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let progress = controller.installing[item.id] {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Button { controller.cancelInstall(item) } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("Cancel this update")
                        }
                        Text(progress).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).frame(maxWidth: 160, alignment: .trailing)
                    }
                } else {
                    Button(item.scriptedInstall ? "Update" : "Get…") { controller.update(item) }
                        .controlSize(.small)
                    Menu {
                        Button("Ignore this version") { controller.dismiss(item) }
                        if let url = item.url.flatMap(URL.init(string:)) {
                            Link("Open info page", destination: url)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(width: 22)
                }
            }
            if let caveat = item.caveat {
                Label(caveat, systemImage: "info.circle")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let error = controller.installErrors[item.id] {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(3)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
    }
}
