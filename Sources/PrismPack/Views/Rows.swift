import SwiftUI
import AppKit

// MARK: - Icons

/// Real app icons where we know the bundle, cached so the list scrolls smoothly.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(forApp path: String) -> NSImage? {
        if let hit = cache[path] { return hit }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 128, height: 128)
        cache[path] = image
        return image
    }
}

/// An item's icon: the app's real icon when it has one; else the first letter
/// on a neutral tile for apps; else, for packages that never have an icon
/// (pip, npm, tools), the section's glass tile. macOS keeps the Apple logo.
struct RowIcon: View {
    let name: String
    let appPath: String?
    let sectionID: String
    var size: CGFloat = 32

    /// Sections whose items are packages, not apps.
    static let packageSections: Set<String> = ["pip", "npm", "cargo", "gem", "tools", "editors", "custom"]

    var body: some View {
        if let path = appPath, let image = IconCache.shared.icon(forApp: path) {
            Image(nsImage: image)
                .resizable().interpolation(.high)
                .frame(width: size, height: size)
        } else if sectionID == "macos" || Self.packageSections.contains(sectionID) {
            GlassIconTile(style: SourceStyle.forSource(sectionID), size: size * 0.9)
                .frame(width: size, height: size)
        } else {
            let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            Text(name.first.map { String($0).uppercased() } ?? "?")
                .font(.system(size: size * 0.48, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: size * 0.9, height: size * 0.9)
                .background(Color.primary.opacity(0.08), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1)))
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Row building blocks

/// A small status capsule (Queued, Installing, Needs admin, Failed…).
struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color.readable)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// The same pills on every page (Phase 10): a source pill in that source's
/// Updates colour, and one colour per status, used for nothing else.
extension StatusPill {
    static func source(_ sourceID: String) -> StatusPill {
        sourceID == "unmanaged" ? notManaged
            : StatusPill(text: UpdatesPage.title(of: sourceID), color: SourceStyle.forSource(sourceID).color)
    }
    static let installed = StatusPill(text: "Installed", color: .green)
    static let upToDate = StatusPill(text: "Up to date", color: .green)
    static let notManaged = StatusPill(text: "Not managed", color: .secondary)
    static func update(to version: String) -> StatusPill { StatusPill(text: "Update to \(version)", color: .orange) }
}

/// "Version 1.2", in the normal text font, the same on every page.
func versionLine(_ version: String, _ extras: String?...) -> String {
    ([version.isEmpty ? nil : "Version \(version)"] + extras).compactMap { $0 }.joined(separator: " · ")
}

/// A page's own controls, in the row under the window's title bar. Same
/// padding on every page.
struct PageControls<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }
}

/// "12 updates available · Review" on Installed and Discover (Phase 10).
/// Shows only when updates are waiting; Review opens the Updates page.
struct UpdatesReminder: View {
    @EnvironmentObject var controller: UpdateController

    var body: some View {
        let count = controller.visibleItems.count
        if count > 0 {
            HStack(spacing: 6) {
                Circle().fill(Color.orange).frame(width: 7, height: 7)
                Text("\(count) update\(count == 1 ? "" : "s") available")
                Text("·").foregroundStyle(.secondary)
                Button("Review") { controller.page = .updates }
                    .buttonStyle(.link)
            }
            .font(.callout)
        }
    }
}

/// Icon, name and the line under it; clicking either opens `detail`.
private struct RowTitle<Detail: View>: View {
    let icon: RowIcon
    let name: String
    let subtitle: String
    var dimmed = false
    @ViewBuilder var detail: () -> Detail
    @State private var showingDetail = false

    var body: some View {
        Button { showingDetail = true } label: {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.body.weight(.semibold)).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.7 : 1)
        .popover(isPresented: $showingDetail, arrowEdge: .bottom, content: detail)
        .help("Details, release notes and hide options")
    }
}

// MARK: - Update row

struct UpdateRow: View {
    @EnvironmentObject var controller: UpdateController
    let item: UpdateItem

    private var style: SourceStyle { SourceStyle.forSource(item.sectionID) }
    private var installState: InstallState? { controller.installStates[item.id] }
    private var running: InstallState? { installState?.isActive == true ? installState : nil }
    private var error: String? { installState?.errorMessage }

    private var subtitle: String {
        var parts = ["\(item.installedVersion) to \(item.latestVersion)"]
        let pinned = controller.isPinned(item)
        if pinned { parts.append("pinned") }
        if let caveat = item.caveat, !pinned { parts.append(caveat) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            RowTitle(icon: RowIcon(name: item.name, appPath: item.appPath, sectionID: item.sectionID),
                     name: item.name, subtitle: subtitle) {
                UpdateDetailView(item: item).environmentObject(controller)
            }
            badges
            trailing
        }
        .padding(.vertical, 6)
        .help(item.caveat ?? "")
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            if item.isIOSApp { WarningBadge(.iosApp) }
            if let jump = item.majorUpgradeSummary { WarningBadge(.majorUpgrade(jump)) }
            if let caveat = item.caveat, caveat.localizedCaseInsensitiveContains("restart") {
                WarningBadge(.restart(caveat))
            }
        }
        .font(.system(size: 13))
    }

    /// Which trailing look is showing, so changes between them animate.
    private var trailingKey: String {
        switch running {
        case nil: error == nil ? "idle" : "failed"
        case .queued?: "queued"
        case .needsAdmin?: "admin"
        case .cancelling?: "cancelling"
        case .downloading(let p?, _)?: "download\(p)"
        default: "installing"
        }
    }

    private var trailing: some View {
        trailingContent
            .transition(.blurReplace)
            .id(trailingKey)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: trailingKey)
    }

    @ViewBuilder
    private var trailingContent: some View {
        if let running {
            HStack(spacing: 8) {
                switch running {
                case _ where controller.moveProgress[item.id] != nil && running != .queued && running != .cancelling:
                    // Long moves show their step and real download size.
                    MoveProgressView(progress: controller.moveProgress[item.id]!, compact: true)
                        .frame(width: 170)
                        .onTapGesture { MoveProgressWindow.shared.show(jobID: item.id) }
                        .help("Click for the steps")
                case .downloading(let percent?, _):
                    ProgressView(value: Double(percent), total: 100).frame(width: 90)
                    Text("\(percent)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                case .queued:
                    Text("Queued").font(.caption).foregroundStyle(.secondary)
                case .needsAdmin:
                    StatusPill(text: "Needs admin", color: .orange)
                case .cancelling:
                    Text("Cancelling…").font(.caption).foregroundStyle(.secondary)
                default:
                    StatusPill(text: "Installing", color: .blue)
                        .help(running.label)
                }
                if running != .cancelling {
                    Button("Cancel") { controller.cancelInstall(item) }
                        .glass().controlSize(.small)
                }
            }
        } else {
            HStack(spacing: 8) {
                if let error {
                    StatusPill(text: error == "Needs admin" ? "Needs admin" : "Failed",
                               color: error == "Needs admin" ? .orange : .red)
                        .help(error)
                }
                if controller.repairable[item.id] != nil {
                    Button("Repair") { controller.repair(item) }
                        .glassProminent(.orange).controlSize(.small)
                        .help("Moves Homebrew's leftover upgrade folder to the Trash and reinstalls")
                } else {
                    Button(error == nil ? item.actionLabel : "Retry") { controller.requestUpdate(item) }
                        .glassProminent(style.color).controlSize(.small)
                }
            }
        }
    }
}

// MARK: - Other rows

/// Every App Store item PrismPack can't install itself, as one hand-off row.
struct AppStoreHandoffRow: View {
    let items: [UpdateItem]

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(name: "App Store", appPath: "/System/Applications/App Store.app", sectionID: "mas")
            VStack(alignment: .leading, spacing: 1) {
                Text(items.count == 1 ? "1 app updates in the App Store" : "\(items.count) apps update in the App Store")
                    .font(.body.weight(.semibold))
                Text(items.map(\.name).joined(separator: ", ") + " · the App Store has to do these itself")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Open in App Store") {
                NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!)
            }
            .glassProminent(.blue).controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

struct LeftoverRow: View {
    @EnvironmentObject var controller: UpdateController
    let kext: KextBundle
    @State private var confirmingRemoval = false

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(name: kext.name, appPath: nil, sectionID: "leftover")
            VStack(alignment: .leading, spacing: 1) {
                Text(kext.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(kext.modified.map { "v\(kext.version) · \($0.formatted(.dateTime.month(.abbreviated).year())) · on disk but the kernel isn't using it" }
                     ?? "v\(kext.version) · on disk but the kernel isn't using it")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let error = controller.removeErrors[kext.id] {
                StatusPill(text: "Failed", color: .red).help(error)
            }
            if let progress = controller.removing[kext.id] {
                ProgressView().controlSize(.small)
                Text(progress).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Button("Hide this one") { controller.dismissLeftover(kext) }
                    .glass().controlSize(.small)
                Button("Remove…", role: .destructive) { confirmingRemoval = true }
                    .glassProminent(.red).controlSize(.small)
                    .confirmationDialog("Remove \(kext.name)?", isPresented: $confirmingRemoval) {
                        Button("Remove", role: .destructive) { controller.removeLeftover(kext) }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This deletes \(kext.path). macOS isn't loading it, but the software that installed it may stop working. This can't be undone.")
                    }
            }
        }
        .padding(.vertical, 6)
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: kext.path)])
            }
        }
        .help(kext.path)
    }
}

/// Something the user ignored, with a way back.
struct HiddenRow: View {
    @EnvironmentObject var controller: UpdateController
    let item: UpdateItem

    var body: some View {
        HStack(spacing: 10) {
            RowTitle(icon: RowIcon(name: item.name, appPath: item.appPath, sectionID: item.sectionID),
                     name: item.name, subtitle: controller.ignoreReason(item), dimmed: true) {
                UpdateDetailView(item: item).environmentObject(controller)
            }
            Button("Unhide") { controller.unhide(item) }
                .glass().controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

struct HiddenLeftoverRow: View {
    @EnvironmentObject var controller: UpdateController
    let kext: KextBundle

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(name: kext.name, appPath: nil, sectionID: "leftover").opacity(0.7)
            VStack(alignment: .leading, spacing: 1) {
                Text(kext.name).font(.body.weight(.semibold)).lineLimit(1)
                Text("v\(kext.version) · leftover driver, hidden").font(.caption).foregroundStyle(.secondary)
            }
            .opacity(0.7)
            Spacer(minLength: 0)
            Button("Unhide") { controller.unhide(id: kext.id) }
                .glass().controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}
