import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var controller: UpdateController
    @StateObject private var deps = DependencyManager()
    @State private var intervalHours = Prefs.checkIntervalHours
    @State private var disabled = Prefs.disabledSources
    @State private var agentInstalled = LaunchAgent.isInstalled
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var agentError: String?
    @State private var appearance = Prefs.appearance
    @AppStorage("glassStyle") private var glassStyleRaw = GlassStyle.regular.rawValue
    @State private var showDockIcon = Prefs.showDockIcon

    var body: some View {
        VStack(spacing: 0) {
            // In-content title, same treatment as the status window header;
            // fixed above the form so scrolling never runs into the titlebar.
            HStack {
                Text("Settings").font(.title3).bold()
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 34)   // clear the traffic lights
            .padding(.bottom, 6)
            settingsForm
        }
        .frame(width: 400, height: 640)
        .background(GlassBackground())
    }

    private var settingsForm: some View {
        Form {
            if deps.anyMissing {
                Section("Setup") {
                    ForEach(deps.dependencies.filter { !$0.installed }) { dep in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Label(dep.name, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
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
                        Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
                    }
                }
            } else {
                Section("Setup") {
                    Label("All dependencies installed (Homebrew, mas-cli)", systemImage: "checkmark.circle")
                        .foregroundStyle(.green).font(.callout)
                }
            }

            Section("Background checking") {
                Toggle("Start UpdateScout at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                        catch { agentError = error.localizedDescription }
                    }
                Toggle("Check for updates in the background", isOn: $agentInstalled)
                    .onChange(of: agentInstalled) { _, on in
                        do { on ? try LaunchAgent.install(intervalHours: intervalHours) : try LaunchAgent.uninstall() }
                        catch { agentError = error.localizedDescription; agentInstalled = LaunchAgent.isInstalled }
                    }
                Picker("Check every", selection: $intervalHours) {
                    ForEach([1, 3, 6, 12, 24], id: \.self) { Text("\($0) hour\($0 == 1 ? "" : "s")").tag($0) }
                }
                .onChange(of: intervalHours) { _, hours in
                    Prefs.checkIntervalHours = hours
                    if agentInstalled { try? LaunchAgent.install(intervalHours: hours) }
                }
                if let agentError {
                    Text(agentError).font(.caption).foregroundStyle(.red)
                }
                Text("Background checks only detect and notify — updates are always installed by you, per item.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _, value in
                    Prefs.appearance = value
                    Appearance.apply(value, animated: true)
                }
                Picker("Window glass", selection: $glassStyleRaw) {
                    ForEach(GlassStyle.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Text("Glass affects the status window, not the menu bar bubble.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show icon in Dock", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, on in
                        Prefs.showDockIcon = on
                        NSApp.setActivationPolicy(on ? .regular : .accessory)
                        NSApp.activate(ignoringOtherApps: true)
                    }
            }

            Section("Sources") {
                ForEach(UpdateController.allSources, id: \.id) { source in
                    Toggle(source.displayName, isOn: Binding(
                        get: { !disabled.contains(source.id) },
                        set: { on in
                            if on { disabled.remove(source.id) } else { disabled.insert(source.id) }
                            Prefs.disabledSources = disabled
                        }
                    ))
                }
            }

            Section("Custom sources") {
                HStack {
                    Text("Edit custom_sources.json for apps nothing else covers.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open File") {
                        NSWorkspace.shared.activateFileViewerSelecting([CustomSource.configURL])
                    }
                }
            }

            Section("About") {
                HStack {
                    Text("UpdateScout \(SelfUpdater.version)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for App Updates…") { SelfUpdater.checkForUpdates() }
                }
            }

            Section {
                Text("There is no unified API for third-party driver updates on macOS — vendors like DisplayLink ship their own installers with no auto-update. UpdateScout uses Homebrew's cask database as a version oracle for those, and the custom-sources file for anything without a cask.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)   // let the glass show through
    }
}

/// Manages the periodic-check launchd agent in ~/Library/LaunchAgents.
enum LaunchAgent {
    static let label = "com.nickszun.updatescout.check"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func install(intervalHours: Int) throws {
        guard let exe = Bundle.main.executablePath else { return }
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [exe, "--background-check"],
            "StartInterval": intervalHours * 3600,
            "RunAtLoad": true,
            "ProcessType": "Background",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: plistURL)
        reload()
    }

    static func uninstall() throws {
        bootout()
        try? FileManager.default.removeItem(at: plistURL)
    }

    private static func reload() {
        bootout()
        run(["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    private static func bootout() {
        run(["bootout", "gui/\(getuid())/\(label)"])
    }

    private static func run(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}
