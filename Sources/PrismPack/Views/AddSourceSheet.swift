import SwiftUI

/// Settings' "Add a Source…": link an app to its GitHub releases, or define a
/// custom source (a version page plus a download page or a command). Custom
/// entries go into custom_sources.json in its existing format.
struct AddSourceSheet: View {
    enum Kind: Hashable { case github, custom }

    @Environment(\.dismiss) private var dismiss
    let onGitHub: (GitHubApp) -> Void
    let onCustom: () -> Void

    @State private var kind: Kind = .github
    /// The app window's height, read when the sheet opens; the sheet never
    /// grows past it and scrolls instead (Nick, 2 Nov 2026).
    @State private var maxHeight: CGFloat = 560

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a Source").font(.title3.bold())
            GlassSegmented(selection: $kind, options: [(.github, "GitHub"), (.custom, "Custom")])
            switch kind {
            case .github:
                ScrollView { GitHubLinkSheet(embedded: true) { onGitHub($0) } }
            case .custom:
                CustomSourceForm { onCustom(); dismiss() }
            }
        }
        .padding(20)
        .frame(width: 520)
        .frame(maxHeight: maxHeight)
        .popupClose()
        .onAppear {
            let window = NSApp.keyWindow?.sheetParent ?? NSApp.mainWindow
            if let height = window?.contentLayoutRect.height { maxHeight = max(300, height - 60) }
        }
    }
}

private struct CustomSourceForm: View {
    enum Action: Hashable { case page, command }
    let onAdded: () -> Void

    @State private var apps: [AppFacts] = []
    @State private var appPath = ""
    @State private var name = ""
    @State private var versionPage = ""
    @State private var action: Action = .page
    @State private var downloadPage = ""
    @State private var command = ""
    @State private var showAdvanced = false
    @State private var installedCommand = ""
    @State private var plistKey = ""
    @State private var pattern = ""
    @State private var jsonKey = ""
    @State private var testing = false
    @State private var result: String?
    @State private var passed: CustomSource.Entry?

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            content()
        }
    }

    /// What the form says now; nil until the needed fields are filled.
    private var entry: CustomSource.Entry? {
        let name = name.trimmingCharacters(in: .whitespaces)
        let page = versionPage.trimmingCharacters(in: .whitespaces)
        let usesCommand = !installedCommand.trimmingCharacters(in: .whitespaces).isEmpty
        guard !name.isEmpty, URL(string: page)?.scheme?.hasPrefix("http") == true,
              usesCommand || !appPath.isEmpty else { return nil }
        let dl = downloadPage.trimmingCharacters(in: .whitespaces)
        let cmd = command.trimmingCharacters(in: .whitespaces)
        if action == .page, URL(string: dl)?.scheme?.hasPrefix("http") != true { return nil }
        if action == .command, cmd.isEmpty { return nil }
        func opt(_ s: String) -> String? { s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s.trimmingCharacters(in: .whitespaces) }
        return CustomSource.Entry(
            name: name, enabled: true,
            installedPlist: usesCommand ? nil : appPath + "/Contents/Info.plist",
            installedPlistKey: opt(plistKey),
            installedCommand: usesCommand ? opt(installedCommand) : nil,
            remoteURL: page, remoteRegex: opt(pattern), remoteJSONPath: opt(jsonKey),
            installCommand: action == .command ? cmd : nil,
            downloadPage: action == .page ? dl : opt(dl), notes: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The fields scroll (Advanced makes them tall); the result and
            // the buttons stay in view.
            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
            group("App") {
                SortMenu(selection: $appPath,
                         options: [("", "Choose an app")] + apps.map { ($0.path, "\($0.name) \($0.version)") },
                         help: "The app to keep up to date")
            }
            group("Name") { GlassField(prompt: "Name in the list", text: $name) }
            group("Where the latest version is published") {
                GlassField(prompt: "Link to a page or JSON with the version", text: $versionPage)
            }
            group("To update") {
                GlassSegmented(selection: $action, options: [(.page, "Open the download page"), (.command, "Run a command")])
                if action == .page {
                    GlassField(prompt: "Download page link", text: $downloadPage)
                } else {
                    GlassField(prompt: "Command, e.g. brew install --cask app --force", text: $command)
                    Text("Runs as you type it, in the shell. It isn't run in the background unless you switch that on in Settings. If it uses sudo, \(AppIdentity.name) asks for your password.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 10) {
                    group("Read the installed version with a command instead of the app") {
                        GlassField(prompt: "Command that prints the version", text: $installedCommand)
                    }
                    group("Version key in the app's Info.plist (default: CFBundleShortVersionString)") {
                        GlassField(prompt: "Key", text: $plistKey)
                    }
                    group("Find the latest version with a JSON key (e.g. release.tag) or a pattern (one capture group)") {
                        GlassField(prompt: "JSON key", text: $jsonKey)
                        GlassField(prompt: "Pattern", text: $pattern)
                    }
                }
                .padding(.top, 8)
            }
            }
            }
            if testing {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Testing…").font(.caption).foregroundStyle(.secondary) }
            } else if let result {
                Text(result).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Test") { test() }.glass().disabled(entry == nil || testing)
                Button("Add") { add() }.prismProminent()
                    .keyboardShortcut(.defaultAction)
                    .disabled(passed == nil || passed != entry)
            }
        }
        .task { apps = Adoption.installedApps().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
        .onChange(of: appPath) { _, path in
            if let app = apps.first(where: { $0.path == path }), name.isEmpty { name = app.name }
        }
    }

    private func test() {
        guard var e = entry else { return }
        testing = true; result = nil; passed = nil
        Task {
            let source = CustomSource()
            let installed = await source.installedVersion(of: e)
            guard let installed else {
                result = "Couldn't read the installed version. Check the app, or the command in Advanced."
                testing = false; return
            }
            guard let url = URL(string: e.remoteURL),
                  let (data, response) = try? await Net.fetch(url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                result = "Couldn't load the version page."
                testing = false; return
            }
            if e.remoteRegex == nil && e.remoteJSONPath == nil {
                let guess = CustomSource.guessRemote(data)
                e.remoteJSONPath = guess.jsonPath
                e.remoteRegex = guess.regex
            }
            if let latest = CustomSource.parseRemote(data, e) {
                result = "Installed \(installed), latest \(latest)."
                    + (e.remoteJSONPath != nil && jsonKey.isEmpty ? " (read from the “\(e.remoteJSONPath!)” key)" : "")
                // The guess is kept in the form so what was tested is what's added.
                if jsonKey.isEmpty && pattern.isEmpty {
                    jsonKey = e.remoteJSONPath ?? ""
                    pattern = e.remoteRegex ?? ""
                }
                passed = entry
            } else {
                result = "Installed \(installed), but no version was found on that page. Try Advanced: a JSON key or a pattern."
            }
            testing = false
        }
    }

    private func add() {
        guard let e = passed else { return }
        do { try CustomSource.add(e); onAdded() }
        catch { result = error.localizedDescription }
    }
}
