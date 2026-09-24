import SwiftUI
import AppKit

// MARK: - Icons

/// Real app icons where we know the bundle, cached so the grid scrolls smoothly.
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

/// App icon if available, otherwise the source's symbol in a tinted tile.
struct AppIconView: View {
    let appPath: String?
    let style: SourceStyle
    var size: CGFloat = 56

    var body: some View {
        if let path = appPath, let image = IconCache.shared.icon(forApp: path) {
            Image(nsImage: image)
                .resizable().interpolation(.high)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        } else {
            Image(systemName: style.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(style.color)
                .frame(width: size, height: size)
                .background(style.color.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        }
    }
}

// MARK: - Card chrome

/// Shared square card surface: subtle fill so cards read on any glass tint.
struct CardSurface: ViewModifier {
    var dimmed = false
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.card.opacity(dimmed ? 0.6 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
            .opacity(dimmed ? 0.7 : 1)
    }
}

extension View {
    func cardSurface(dimmed: Bool = false) -> some View { modifier(CardSurface(dimmed: dimmed)) }
}

// MARK: - Update card

struct UpdateCard: View {
    @EnvironmentObject var controller: UpdateController
    let item: UpdateItem
    @State private var showingDetails = false

    private var style: SourceStyle { SourceStyle.forSource(item.sourceID) }
    private var progress: String? { controller.installing[item.id] }
    private var error: String? { controller.installErrors[item.id] }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                AppIconView(appPath: item.appPath, style: style)
                // Warnings sit on the icon's corner instead of as orange prose.
                HStack(spacing: 2) {
                    if item.isIOSApp {
                        WarningBadge(title: "iPhone / iPad app",
                                     message: "This is an iOS app running on your Mac. mas and Homebrew can't update these — the button opens the App Store's Updates page, where you can update it.",
                                     symbol: "iphone.gen3", color: .blue)
                    }
                    if let jump = item.majorUpgradeSummary {
                        WarningBadge(
                            title: "Major version change (\(jump))",
                            message: "For paid apps a new major version is often a separate purchase rather than a free update. Check the vendor's terms before updating.")
                    }
                    if item.caveat?.localizedCaseInsensitiveContains("restart") == true {
                        WarningBadge(title: "Requires restart", message: item.caveat ?? "", color: .yellow)
                    }
                    if let error {
                        WarningBadge(title: "Update failed", message: error, color: .red)
                    }
                }
                .font(.system(size: 13))
                .offset(x: 8, y: -6)
            }
            .padding(.top, 4)

            VStack(spacing: 3) {
                Text(item.name)
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(item.installedVersion).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text(item.latestVersion).foregroundStyle(style.color).fontWeight(.medium)
                }
                .font(.caption2.monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6)

            if let progress {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Button { controller.cancelInstall(item) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain).help("Cancel")
                    }
                    Text(progress).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.center)
                        .frame(height: 26)
                }
            } else {
                HStack(spacing: 6) {
                    Button { showingDetails = true } label: {
                        Image(systemName: "info.circle")
                    }
                    .glass().controlSize(.small)
                    .help("Details and release notes")
                    .popover(isPresented: $showingDetails, arrowEdge: .bottom) {
                        UpdateDetailView(item: item).environmentObject(controller)
                    }

                    Button(item.actionLabel) { controller.update(item) }
                        .glassProminent(style.color)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)

                    Menu {
                        Button("Ignore this version") { controller.dismiss(item) }
                        if let url = item.url.flatMap(URL.init(string:)) {
                            Link("Open info page", destination: url)
                        }
                        if let path = item.appPath {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(width: 20)
                }
            }
        }
        .cardSurface()
        .help(item.caveat ?? "")
    }
}

// MARK: - Leftover driver card

struct LeftoverCard: View {
    @EnvironmentObject var controller: UpdateController
    let kext: KextBundle

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "trash.slash.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 56, height: 56)
                    .background(Color.red.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let error = controller.removeErrors[kext.id] {
                    WarningBadge(title: "Removal failed", message: error, color: .red)
                        .font(.system(size: 13)).offset(x: 8, y: -6)
                }
            }
            .padding(.top, 4)

            Text(kext.name)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center).lineLimit(2)
                .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)

            Text(kext.modified.map { "v\(kext.version) · \($0.formatted(.dateTime.month(.abbreviated).year()))" }
                 ?? "v\(kext.version)")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)

            Spacer(minLength: 6)

            if let progress = controller.removing[kext.id] {
                VStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2).multilineTextAlignment(.center).frame(height: 26)
                }
            } else {
                HStack(spacing: 6) {
                    Button("Remove", role: .destructive) { controller.removeLeftover(kext) }
                        .glassProminent(.red).controlSize(.small)
                        .frame(maxWidth: .infinity)
                    Menu {
                        Button("Ignore this one") { controller.dismissLeftover(kext) }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: kext.path)])
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden)
                    .frame(width: 20)
                }
            }
        }
        .cardSurface()
        .help(kext.path)
    }
}

// MARK: - Hidden card

/// A dimmed card for something the user ignored, with a way back.
struct HiddenCard: View {
    @EnvironmentObject var controller: UpdateController
    let id: String
    let name: String
    let detail: String
    let appPath: String?
    let style: SourceStyle

    var body: some View {
        VStack(spacing: 8) {
            AppIconView(appPath: appPath, style: style).saturation(0.2).padding(.top, 4)
            Text(name)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.center).lineLimit(2)
                .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 6)
            Button {
                controller.unhide(id: id)
            } label: {
                Label("Unhide", systemImage: "eye").frame(maxWidth: .infinity)
            }
            .glass().controlSize(.small)
        }
        .cardSurface(dimmed: true)
    }
}

/// One card standing in for every App Store item UpdateScout can't install
/// itself (iPhone/iPad apps, and anything mas refuses). A per-app card would
/// show an Update button that can't do the job, so these collapse into a
/// single hand-off to the App Store.
struct AppStoreHandoffCard: View {
    let items: [UpdateItem]

    private var appStoreIcon: NSImage? {
        IconCache.shared.icon(forApp: "/System/Applications/App Store.app")
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let icon = appStoreIcon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "bag.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.blue)
                        .background(Color.blue.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(width: 56, height: 56)
            .padding(.top, 4)

            VStack(spacing: 3) {
                Text("^[\(items.count) app update](inflect: true)")
                    .font(.callout.weight(.semibold))
                    .multilineTextAlignment(.center).lineLimit(2)
                    .frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                Text(items.map(\.name).joined(separator: ", "))
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            Button {
                NSWorkspace.shared.open(URL(string: "macappstore://showUpdatesPage")!)
            } label: {
                Text("Open App Store").frame(maxWidth: .infinity)
            }
            .glassProminent(.blue).controlSize(.small)
        }
        .cardSurface()
        .help("These can only be updated in the App Store: " + items.map(\.name).joined(separator: ", "))
    }
}
