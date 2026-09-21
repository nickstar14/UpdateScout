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

/// One update row — shared by the status window.
struct UpdateRow: View {
    @EnvironmentObject var controller: UpdateController
    let item: UpdateItem

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(item.name).fontWeight(.medium)
                        if item.isMajorUpgrade {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    Text("\(item.installedVersion) → \(item.latestVersion)")
                        .font(.caption)
                        .foregroundStyle(item.isMajorUpgrade ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                Spacer()
                if controller.installing[item.id] != nil {
                    // Status text goes on its own full-width line below, so it
                    // isn't squeezed into a narrow column here.
                    ProgressView().controlSize(.small)
                    Button { controller.cancelInstall(item) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Cancel this update")
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
            if let progress = controller.installing[item.id] {
                Text(progress)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if let jump = item.majorUpgradeSummary {
                    Label("Major version change (\(jump)). For paid apps this is often a separate purchase, not a free update — check the vendor's terms before updating.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let caveat = item.caveat {
                    Label(caveat, systemImage: "info.circle")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let error = controller.installErrors[item.id] {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(3)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
    }
}

/// One leftover-kext row: name, version, path, and a Remove button.
struct LeftoverRow: View {
    @EnvironmentObject var controller: UpdateController
    let kext: KextBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(kext.name).fontWeight(.medium)
                    HStack(spacing: 6) {
                        Text("v\(kext.version)")
                        if let modified = kext.modified {
                            Text("· installed \(modified.formatted(.dateTime.month(.abbreviated).year()))")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if controller.removing[kext.id] != nil {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Remove", role: .destructive) { controller.removeLeftover(kext) }
                        .controlSize(.small)
                    Menu {
                        Button("Ignore this one") { controller.dismissLeftover(kext) }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: kext.path)])
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(width: 22)
                }
            }
            if let progress = controller.removing[kext.id] {
                Text(progress)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Label(kext.path, systemImage: "folder")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = controller.removeErrors[kext.id] {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(3)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
    }
}
