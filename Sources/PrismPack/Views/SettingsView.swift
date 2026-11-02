import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var controller: UpdateController
    @StateObject private var deps = DependencyManager()
    @State private var showDeps = false
    @State private var intervalMinutes = Prefs.checkIntervalMinutes
    @State private var disabled = Prefs.disabledSources
    @State private var agentInstalled = LaunchAgent.isInstalled
    @State private var agentStalled = LaunchAgent.isStalled
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var agentError: String?
    @State private var appearance = Prefs.appearance
    @State private var updateConcurrency = Prefs.updateConcurrency
    @State private var passwordOnce = Prefs.askPasswordOncePerBatch
    @State private var autoEnabled = AutoUpdate.enabled
    @State private var autoSchedule = AutoUpdate.schedule
    @State private var autoUnmetered = AutoUpdate.unmeteredOnly
    @AppStorage(Prefs.glassTintKey) private var glassTint: Double = 0.35
    @State private var showDockIcon = Prefs.showDockIcon
    @State private var adoptionEnabled = Prefs.adoptionEnabled
    @State private var adoptionSelfUpdating = Prefs.adoptionIncludeSelfUpdating
    @State private var customNames: [String] = []
    @State private var customBackground: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            // In-content title, same treatment as the status window header;
            // fixed above the form so scrolling never runs into the titlebar.
            HStack(spacing: 12) {
                AppLogo(size: 50, trimmed: true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppIdentity.name)
                        .font(.title2.weight(.semibold))
                    Text("Version \(SelfUpdater.version)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    SelfUpdater.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .glass().controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
            settingsForm
        }
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    private func dependencyRow(_ dep: DependencyManager.Dependency) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(dep.name + (deps.versions[dep.id].map { " \($0)" } ?? ""))
                Text(dep.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if deps.installingID == dep.id {
                ProgressView().controlSize(.small)
            } else if let formula = dep.brewFormula, !dep.installed {
                Button("Install") { deps.install(dep) }.glassProminent(SourceStyle.forSource("homebrew").color).controlSize(.small)
                    .help("Installs \(formula) with Homebrew")
            } else if dep.brewFormula != nil, !deps.managedLoaded {
                ProgressView().controlSize(.small)
            } else if deps.managedFormula(dep) != nil {
                Button("Reinstall") { deps.reinstall(dep) }.glass().controlSize(.small)
                // Red, like every removal (Nick, 2 Nov 2026).
                Button("Remove") { confirmRemove(dep) }.glassProminent(.red).controlSize(.small)
            } else if dep.brewFormula != nil {
                Text("Installed outside Homebrew").font(.caption).foregroundStyle(.secondary)
                    .help("\(AppIdentity.name) only reinstalls or removes copies Homebrew installed.")
            } else if dep.id == "brew", let page = URL(string: "https://github.com/Homebrew/install#uninstall-homebrew") {
                // Never removed from here: it would take everything it installed with it.
                Link("How to remove", destination: page).font(.caption)
                    .help("Removing Homebrew removes everything it installed. Homebrew's own page explains how.")
            }
        }
    }

    private func confirmRemove(_ dep: DependencyManager.Dependency) {
        let alert = NSAlert()
        alert.messageText = "Remove \(dep.name)?"
        alert.informativeText = "\(dep.purpose.prefix(1).uppercased() + dep.purpose.dropFirst()). Without it, that stops until you install it again from here."
        alert.alertStyle = .warning
        let go = alert.addButton(withTitle: "Remove")
        go.hasDestructiveAction = true
        go.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        if alert.runModal() == .alertFirstButtonReturn { deps.remove(dep) }
    }

    private var settingsForm: some View {
        Form {
            if deps.anyMissing {
                Section("Setup") {
                    ForEach(deps.dependencies.filter { !$0.installed && !$0.optional }) { dep in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Label(dep.name, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(Color.orange.readable)
                                Text(dep.purpose).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if deps.installingID == dep.id {
                                ProgressView().controlSize(.small)
                            } else if dep.brewFormula != nil {
                                Button("Install") { deps.install(dep) }
                            } else if let manual = dep.manualURL.flatMap(URL.init(string:)) {
                                Link("Get…", destination: manual)
                            }
                        }
                    }
                    if let error = deps.installError {
                        Text(error).font(.caption).foregroundStyle(Color.red.readable).lineLimit(3)
                    }
                    FullDiskAccessRow()
                }
            } else {
                Section("Setup") {
                    // Same size as the Full Disk Access line, and opens to
                    // each tool with Reinstall and Remove (Nick, 2 Nov 2026).
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showDeps.toggle() }
                        if showDeps { deps.loadVersions() }
                    } label: {
                        HStack {
                            Label("Everything \(AppIdentity.name) needs is installed", systemImage: "checkmark.circle")
                                .foregroundStyle(Color.green.readable)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showDeps ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showDeps ? "Hide the list" : "Show each dependency")
                    if showDeps {
                        ForEach(deps.dependencies) { dep in dependencyRow(dep) }
                        if let error = deps.installError {
                            Text(error).font(.caption).foregroundStyle(Color.red.readable).lineLimit(3)
                        }
                    }
                    FullDiskAccessRow()
                }
            }

            Section("Updating") {
                Stepper(value: $updateConcurrency, in: 1...8) {
                    LabeledContent("Update at once", value: "\(updateConcurrency)")
                }
                .onChange(of: updateConcurrency) { _, value in Prefs.updateConcurrency = value }
                Text("Installs from different sources run side by side. Each package manager still updates one item at a time.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Ask for my password once per batch", isOn: $passwordOnce)
                    .onChange(of: passwordOnce) { _, value in Prefs.askPasswordOncePerBatch = value }
                Text("Kept in memory for that batch only, then wiped. Never saved. When off, each installer asks for itself.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Install updates automatically", isOn: $autoEnabled)
                    .onChange(of: autoEnabled) { _, value in AutoUpdate.enabled = value }
                if autoEnabled {
                    Picker("How often", selection: $autoSchedule) {
                        ForEach(AutoUpdate.Schedule.allCases) { Text($0.title).tag($0) }
                    }
                    .onChange(of: autoSchedule) { _, value in AutoUpdate.schedule = value }
                    Toggle("Only on Wi-Fi or Ethernet", isOn: $autoUnmetered)
                        .onChange(of: autoUnmetered) { _, value in AutoUpdate.unmeteredOnly = value }
                }
                Text("Never automatic: anything that needs your password, apps that are open, macOS, custom sources, betas, major upgrades, and anything hidden or pinned. \"Only on Wi-Fi or Ethernet\" skips a phone hotspot and Low Data Mode. Each app's card can override this.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Homebrew adoption") {
                Toggle("Suggest apps that can move under Homebrew", isOn: $adoptionEnabled)
                    .onChange(of: adoptionEnabled) { _, value in
                        Prefs.adoptionEnabled = value
                        UpdateController.shared.checkNow()
                    }
                Toggle("Include apps that already update themselves", isOn: $adoptionSelfUpdating)
                    .disabled(!adoptionEnabled)
                    .onChange(of: adoptionSelfUpdating) { _, value in
                        Prefs.adoptionIncludeSelfUpdating = value
                        UpdateController.shared.checkNow()
                    }
                Text("Only apps with no updater are suggested by default, and only when Homebrew's version is current. \(AppIdentity.name) never changes an app without asking, and sends at most one notification a week.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Background checking") {
                Toggle("Start \(AppIdentity.name) at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { agentError = error.localizedDescription }
                    }
                Toggle("Check for updates in the background", isOn: $agentInstalled)
                    .onChange(of: agentInstalled) { _, on in
                        guard on != LaunchAgent.isInstalled else { return }
                        Task {
                            do {
                                agentError = nil
                                on ? try await LaunchAgent.install(intervalMinutes: intervalMinutes)
                                   : try await LaunchAgent.uninstall()
                            } catch {
                                agentError = error.localizedDescription
                                agentInstalled = LaunchAgent.isInstalled
                            }
                            agentStalled = LaunchAgent.isStalled
                        }
                    }
                Picker("Check every", selection: $intervalMinutes) {
                    ForEach(Prefs.checkIntervalChoices, id: \.self) {
                        Text(Prefs.intervalLabel($0)).tag($0)
                    }
                }
                .onChange(of: intervalMinutes) { _, minutes in
                    Prefs.checkIntervalMinutes = minutes
                    guard agentInstalled else { return }
                    Task {
                        do { agentError = nil; try await LaunchAgent.install(intervalMinutes: minutes) }
                        catch { agentError = error.localizedDescription }
                    }
                }
                if !agentInstalled && agentStalled {
                    Text("The background check is set up but isn't running. Turn it on again to restart it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let agentError {
                    Text(agentError).font(.caption).foregroundStyle(Color.red.readable)
                }
                Text(autoEnabled
                     ? "Background checks also install automatic updates while \(AppIdentity.name) isn't open; when it is, it installs them itself."
                     : "Background checks only detect and notify. Updates are installed by you, unless an app's card says Always.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Appearance") {
                LabeledContent("Theme") {
                    GlassSegmented(selection: $appearance,
                                   options: Appearance.allCases.map { ($0, $0.label) })
                }
                .onChange(of: appearance) { _, value in
                    Prefs.appearance = value
                    // Straight away: waiting for the bubble read as a hang.
                    Appearance.apply(value, animated: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Glass")
                    Slider(value: $glassTint, in: 0...1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("Clear").font(.caption).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("Opaque").font(.caption).foregroundStyle(.secondary)
                    }
                    // Otherwise the grouped Form reserves a label column and the
                    // slider gets squeezed into the right half of the row.
                    .labelsHidden()
                    Text("Clear is the system's Liquid Glass with no tint; toward Opaque adds a light or dark wash to match the theme.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Show icon in Dock", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, on in
                        Prefs.showDockIcon = on
                        NSApp.setActivationPolicy(on ? .regular : .accessory)
                        NSApp.activate(ignoringOtherApps: true)
                    }
            }

            Section("Sources") {
                ForEach(UpdateController.allSources, id: \.id) { source in
                    Toggle(isOn: Binding(
                        get: { !disabled.contains(source.id) },
                        set: { on in
                            if on { disabled.remove(source.id) } else { disabled.insert(source.id) }
                            Prefs.disabledSources = disabled
                        }
                    )) {
                        HStack(spacing: 8) {
                            GlassIconTile(style: SourceStyle.forSource(source.id), size: 22)
                            Text(source.displayName)
                        }
                    }
                }
            }

            GitHubAppsSection()

            Section("Custom sources") {
                HStack {
                    Text("Edit custom_sources.json for apps nothing else covers.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open File") {
                        NSWorkspace.shared.activateFileViewerSelecting([CustomSource.configURL])
                    }
                }
                ForEach(customNames, id: \.self) { name in
                    Toggle("Check \(name) in the background", isOn: Binding(
                        get: { customBackground.contains(name) },
                        set: { on in
                            if on { customBackground.insert(name) } else { customBackground.remove(name) }
                            Prefs.customBackgroundNames = customBackground
                        }))
                }
                if !customNames.isEmpty {
                    Text("Custom sources run your own commands. Those switched off are only checked while \(AppIdentity.name) is open.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onAppear {
                customNames = (CustomSource.entries() ?? []).map(\.name)
                customBackground = CustomSource.backgroundNames
            }

            Section {
                Text("There is no unified API for third-party driver updates on macOS — vendors like DisplayLink ship their own installers with no auto-update. \(AppIdentity.name) uses Homebrew's cask database as a version oracle for those, and the custom-sources file for anything without a cask.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)   // let the glass show through
        // Match the update cards so both surfaces read as the same material.
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.card)
        )
    }
}

/// Manages the periodic-check launchd agent in ~/Library/LaunchAgents.
enum LaunchAgent {
    static let label = "com.nickszun.updatescout.check"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var hasPlist: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    /// On only when launchd actually has the job loaded, not just when the
    /// plist exists (a booted-out or failed agent used to show as on).
    static var isInstalled: Bool { hasPlist && isLoaded }

    /// Set up but not running: the plist exists, launchd doesn't have it.
    static var isStalled: Bool { hasPlist && !isLoaded }

    /// `launchctl print` exits 0 only for a loaded job. It answers at once,
    /// so a synchronous call is fine for Settings. Waits on a semaphore, not
    /// `waitUntilExit`, which runs the run loop and crashed SwiftUI when
    /// called while it was building the Settings page.
    static var isLoaded: Bool {
        let process = Process()
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        exited.wait()
        return process.terminationStatus == 0
    }

    static func install(intervalMinutes: Int) async throws {
        guard let exe = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe, "--background-check"],
            "StartInterval": max(5, intervalMinutes) * 60,
            "RunAtLoad": true,
            "ProcessType": "Background",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: plistURL)
        // bootout has to finish before bootstrap, or bootstrap can fail with
        // "service already loaded". Shell.run waits for each to exit, off the
        // main thread. bootout failing just means it wasn't loaded.
        await bootout()
        let result = try await Shell.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        guard result.status == 0 else {
            throw PrismPackError.commandFailed("launchctl bootstrap", output: result.combined)
        }
    }

    static func uninstall() async throws {
        await bootout()
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func bootout() async {
        _ = try? await Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
    }
}

/// Optional Full Disk Access (Phase 9): without it, other apps' data folders
/// can't be moved, only shown in Finder. Rechecked whenever the app comes back
/// to the front, for example from System Settings.
private struct FullDiskAccessRow: View {
    @State private var granted = FullDiskAccess.isGranted

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                if granted {
                    Label("Full Disk Access is on", systemImage: "checkmark.circle")
                        .foregroundStyle(Color.green.readable)
                } else {
                    Label("Full Disk Access (optional)", systemImage: "lock.shield")
                }
                Text(granted
                     ? "\(AppIdentity.name) can move apps' data folders to the Trash when you remove an app or clean up orphaned files. It stays on through updates."
                     : "Apps keep their data in folders macOS guards, so other apps can't change them. Only apps you give Full Disk Access may move them; an administrator password doesn't unlock them. With it, \(AppIdentity.name) can move an app's data folders to the Trash when you remove the app or clean up orphaned files. Without it, those folders are listed with Show in Finder so you can move them yourself. Once on, it stays on through updates.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(6)
            }
            Spacer()
            if !granted {
                Button("Allow…") { FullDiskAccess.openSettings() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = FullDiskAccess.isGranted
        }
    }
}
