import SwiftUI
import AppKit

/// Move to Trash for an app, AppCleaner's way (Phase 9): one window lists
/// the app and what it leaves in the user's Library before anything moves,
/// then moves the app and the ticked leftovers in one go. A panel of its
/// own, like MoveProgressWindow: sheets and dialogs opened from a popover
/// misbehave on macOS 27, and the popover goes with the app's row.
@MainActor
final class UninstallWindow {
    static let shared = UninstallWindow()
    private var windows: [String: NSPanel] = [:]

    func show(_ removal: Removal, updateID: String?) {
        let key = removal.item.id
        if let window = windows[key] { window.makeKeyAndOrderFront(nil); return }
        let view = UninstallPanel(removal: removal, updateID: updateID) { [weak self] in self?.close(key) }
            .environmentObject(UpdateController.shared)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
                            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.title = removal.actionTitle
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.contentViewController = NSHostingController(rootView: view)
        panel.isReleasedWhenClosed = false
        panel.center()
        windows[key] = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func close(_ key: String) {
        windows.removeValue(forKey: key)?.close()
    }
}

private struct UninstallPanel: View {
    @EnvironmentObject var controller: UpdateController
    let removal: Removal
    let updateID: String?
    let onClose: () -> Void

    /// What the window found, read off the main thread.
    private struct Look: Sendable {
        var appPath: String?
        var appSize: Int64 = 0
        var bundleID: String?
        var identity: Leftovers.Identity?
        var otherCopy: String?
        var found: [Leftovers.Found] = []
        var zap: Zap?
    }

    /// Read once: the app's own icon goes blank once it's in the Trash.
    @State private var icon: NSImage?

    @State private var look: Look?
    @State private var ticked: Set<String> = []
    @State private var zapTicked = false
    @State private var running = false
    /// The removal actually queued (the cask, or the cask with `--zap`).
    @State private var started: Removal?
    @State private var leftoversChosen = false
    @State private var retried: Leftovers.Outcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                } else {
                    AppLogo(size: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(removal.actionTitle) \(removal.name)").font(.headline)
                    if let id = look?.bundleID {
                        Text(id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            if let started {
                progress(started)
            } else if let look {
                choose(look)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for what \(removal.name) leaves behind…").foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
        .task { await load() }
        .task(id: look?.bundleID) { await watchRunning() }
    }

    // MARK: Before

    @ViewBuilder private func choose(_ look: Look) -> some View {
        if running {
            HStack {
                Label("Quit \(removal.name) first.", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.orange.readable)
                Spacer()
                Button("Quit \(removal.name)") { quitApp() }.glass()
            }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // The app always goes: leftovers of an app that stays would
                // just come back, or break it.
                row(path: look.appPath ?? removal.name, size: look.appSize, note: nil) {
                    Image(systemName: "checkmark.square.fill").foregroundStyle(.secondary)
                }
                ForEach(look.found) { item in
                    row(path: item.path, size: item.size, note: Self.note(item)) {
                        if item.movable {
                            Toggle("", isOn: binding(item.path)).toggleStyle(.checkbox).labelsHidden()
                        } else {
                            Button { Leftovers.showInFinder(item) } label: { Image(systemName: "folder").accessibilityLabel("Show in Finder") }
                                .glass()
                                .help("Show in Finder")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: min(CGFloat(look.found.count + 1) * 40 + 8, 300))

        if let other = look.otherCopy {
            note("Another copy of \(removal.name) stays installed at \(Self.shortPath(other)), so its files stay too.")
        } else if removal.kind == "app" {
            note(look.found.isEmpty ? "Nothing else of \(removal.name)'s was found in your Library."
                 : "Ticked items match \(removal.name)'s ID exactly. Everything goes to the Trash, so you can put it back.")
            if look.found.contains(where: { $0.label != nil }) {
                note("A background job that's still running is stopped first.")
            }
            if look.found.contains(where: { $0.path.contains("/Library/Containers/") || $0.path.contains("/Library/Group Containers/") }) {
                note("macOS may not let \(AppIdentity.name) move app data folders. If it refuses, you can still move them yourself in Finder.")
            }
        }
        if let zap = look.zap, !zap.isEmpty {
            zapChoice(zap)
        }
        HStack {
            Text(totalText(look)).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", action: onClose).glass().keyboardShortcut(.cancelAction)
            Button(role: .destructive) { Task { await go(look) } } label: {
                Label(removal.actionTitle, systemImage: "trash")
            }
            .glassDestructive()
            .disabled(running)
        }
    }

    private func zapChoice(_ zap: Zap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Also run Homebrew's cleanup list", isOn: $zapTicked).toggleStyle(.checkbox)
            if zap.needsPassword {
                note("It reaches outside your own folder, so it needs your password.")
            }
            ScrollView {
                Text(zap.summary).font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 110)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
        }
    }

    private func row(path: String, size: Int64, note: String?, @ViewBuilder box: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            box()
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.shortPath(path)).font(.callout).lineLimit(1).truncationMode(.middle).help(path)
                if let note { Text(note).font(.caption).foregroundStyle(Color.orange.readable) }
            }
            Spacer()
            Text(UninstallPanelText.size(size)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .help(size == 0 ? "macOS doesn't let \(AppIdentity.name) look inside this" : "")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func binding(_ path: String) -> Binding<Bool> {
        Binding(get: { ticked.contains(path) },
                set: { if $0 { ticked.insert(path) } else { ticked.remove(path) } })
    }

    private func totalText(_ look: Look) -> String {
        let leftovers = look.found.filter { ticked.contains($0.path) }
        let total = look.appSize + leftovers.reduce(0) { $0 + $1.size }
        return leftovers.isEmpty ? Self.bytes(total)
            : "\(Self.bytes(total)) with \(leftovers.count) leftover\(leftovers.count == 1 ? "" : "s")"
    }

    // MARK: After

    @ViewBuilder private func progress(_ started: Removal) -> some View {
        let state = controller.installStates[started.item.id]
        let outcome = retried ?? controller.leftoverOutcomes[started.item.id]
        VStack(alignment: .leading, spacing: 8) {
            if let state, state.isActive {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(state.label).foregroundStyle(.secondary).lineLimit(2)
                }
            } else if let error = state?.errorMessage {
                Text("\(removal.name) couldn't be removed: \(error). Nothing else was touched.")
                    .foregroundStyle(Color.red.readable).fixedSize(horizontal: false, vertical: true)
            } else if state == .done {
                Label(removal.kind == "app" ? "\(removal.name) is in the Trash." : "Homebrew removed \(removal.name).",
                      systemImage: "checkmark.circle.fill")
                if leftoversChosen {
                    if let outcome {
                        leftoverResult(outcome)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Moving its leftovers…").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done", action: onClose).prismProminent().keyboardShortcut(.defaultAction)
                    .disabled(state?.isActive == true)
            }
        }
    }

    @ViewBuilder private func leftoverResult(_ outcome: Leftovers.Outcome) -> some View {
        if !outcome.moved.isEmpty {
            Label("Moved \(UpdateController.leftoverSummary(outcome.moved)) to the Trash.", systemImage: "checkmark.circle.fill")
        }
        ForEach(outcome.failed, id: \.item.path) { failure in
            Text("\(Self.shortPath(failure.item.path)): \(failure.reason)").font(.caption).foregroundStyle(Color.red.readable)
                .fixedSize(horizontal: false, vertical: true)
        }
        let blocked = outcome.failed.filter(\.needsFullDiskAccess).map(\.item)
        if !blocked.isEmpty {
            BlockedLeftovers(items: blocked) { await retry(blocked, after: outcome) }
        }
    }

    // MARK: Work

    private func load() async {
        let removal = removal
        let installedPath = controller.installed.first { $0.detail == "cask \(removal.target)" }?.appPath
        var look = await Task.detached { () -> Look in
            var look = Look()
            look.appPath = removal.appOnDisk ?? installedPath
            if let path = look.appPath {
                look.appSize = Leftovers.size(of: URL(fileURLWithPath: path))
                look.bundleID = Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
            }
            if removal.kind == "app", let path = look.appPath, let identity = Leftovers.identity(ofApp: path) {
                look.identity = identity
                look.otherCopy = Leftovers.otherCopy(of: identity)
                if look.otherCopy == nil { look.found = Leftovers.scan(identity) }
            }
            return look
        }.value
        if removal.kind == "cask" { look.zap = await Zap.load(removal.target) }
        ticked = Set(look.found.filter(\.tickedByDefault).map(\.path))
        icon = look.appPath.map { NSWorkspace.shared.icon(forFile: $0) }
        self.look = look
    }

    /// Keeps "Quit first" current while the window is open.
    private func watchRunning() async {
        guard let id = look?.bundleID else { return }
        while !Task.isCancelled {
            running = !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func quitApp() {
        guard let id = look?.bundleID else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
    }

    private func go(_ look: Look) async {
        let chosen = look.found.filter { ticked.contains($0.path) }
        // Background jobs stop before the app moves, so nothing relaunches it.
        for label in chosen.compactMap(\.label) { await Leftovers.stopAgent(label) }
        let job = zapTicked ? (removal.zap ?? removal) : removal
        leftoversChosen = !chosen.isEmpty
        started = job
        controller.uninstall(job, updateID: updateID, leftovers: chosen)
    }

    private func retry(_ items: [Leftovers.Found], after earlier: Leftovers.Outcome) async {
        let again = await Leftovers.moveToTrash(items)
        controller.logLeftovers(of: removal.name, again)
        retried = Leftovers.Outcome(moved: earlier.moved + again.moved,
                                    failed: again.failed.filter { $0.reason != "It's already gone." })
    }

    // MARK: Text

    private static func note(_ item: Leftovers.Found) -> String? {
        switch item.match {
        case .id: nil
        case .name: "Name match only: may belong to something else"
        case .group: "Shared with this developer's other apps. Not moved: use the folder button if you want to check it"
        }
    }

    static func shortPath(_ path: String) -> String { UninstallPanelText.shortPath(path) }
    static func bytes(_ n: Int64) -> String { UninstallPanelText.bytes(n) }
}

/// What macOS refused to let PrismPack move: allow Full Disk Access, or
/// move them yourself in Finder (Nick, 31 Oct 2026).
struct BlockedLeftovers: View {
    let items: [Leftovers.Found]
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("To let \(AppIdentity.name) move these, allow it Full Disk Access in System Settings, quit and reopen \(AppIdentity.name), then try again. If you'd rather not, show them in Finder and drag them to the Trash yourself.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(4)  // not fixedSize: it sits in page headers too
            HStack {
                Button("Allow Full Disk Access…") { FullDiskAccess.openSettings() }.glass()
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(items.map { URL(fileURLWithPath: $0.path) })
                }
                .glass()
                Spacer()
                Button("Try Again") { Task { await retry() } }.glass()
            }
        }
        .padding(.top, 4)
    }
}

/// Full Disk Access lets PrismPack move other apps' data folders (Phase 9).
/// Paths and sizes as the uninstall window and Orphaned App Files show them.
enum UninstallPanelText {
    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    /// One item's size: "—" for nothing readable, which almost always means
    /// macOS didn't let PrismPack look inside.
    static func size(_ n: Int64) -> String { n == 0 ? "—" : bytes(n) }
}
