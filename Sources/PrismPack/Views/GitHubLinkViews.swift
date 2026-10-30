import SwiftUI
import AppKit

/// Settings' "GitHub releases" group: the linked apps, and Add an app.
struct GitHubAppsSection: View {
    @State private var apps = GitHubApps.load()
    @State private var adding = false

    var body: some View {
        Section("GitHub releases") {
            ForEach(apps) { app in
                HStack(spacing: 8) {
                    RowIcon(name: app.name, appPath: app.appPath, sectionID: "github", size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                        Text("github.com/\(app.repo)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove") {
                        apps.removeAll { $0 == app }
                        GitHubApps.save(apps)
                        UpdateController.shared.checkNow()
                    }
                    .controlSize(.small)
                }
            }
            HStack(alignment: .top) {
                Text("Apps that publish their updates as GitHub releases. Only a download signed by the same developer as your copy is installed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Add an App…") { adding = true }.fixedSize()
            }
        }
        .sheet(isPresented: $adding) {
            GitHubLinkSheet { linked in
                apps.removeAll { $0.appPath == linked.appPath }
                apps.append(linked)
                GitHubApps.save(apps)
                UpdateController.shared.checkNow()
            }
        }
    }
}

/// Pick an installed app, then paste its repository or let "Find it" search.
struct GitHubLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onLink: (GitHubApp) -> Void

    @State private var choices: [AppFacts] = []
    @State private var appPath = ""
    @State private var link = ""
    @State private var working: String?
    @State private var message: String?

    private var app: AppFacts? { choices.first { $0.path == appPath } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Update an app from GitHub").font(.title3.bold())
            Picker("App", selection: $appPath) {
                Text("Choose an app").tag("")
                ForEach(choices, id: \.path) { app in Text("\(app.name) \(app.version)").tag(app.path) }
            }
            HStack {
                TextField("Repository link, like github.com/owner/name", text: $link)
                    .textFieldStyle(.roundedBorder)
                Button("Find It") { find() }.disabled(app == nil || working != nil)
                    .help("Search GitHub by the app's name, and keep only a project whose release is signed by the same developer as your copy")
            }
            if let working {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(working).font(.caption).foregroundStyle(.secondary) }
            } else if let message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("\(AppIdentity.name) downloads the latest release once to check who signed it, then only checks for new releases. Apps not signed by a developer can't be linked.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Link") { linkIt() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(app == nil || GitHubNotes.repoSlug(from: normalized) == nil || working != nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .task {
            // Signed apps that aren't from the App Store; Homebrew's and
            // Sparkle's are listed too, in case the user prefers GitHub.
            choices = Adoption.installedApps()
                .filter { !$0.hasMASReceipt && CodeSign.teamID($0.path) != nil }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// "owner/name" or a github.com link, as a URL repoSlug understands.
    private var normalized: String {
        let trimmed = link.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("github.com") { return trimmed.hasPrefix("http") ? trimmed : "https://" + trimmed }
        return "https://github.com/" + trimmed
    }

    private func linkIt() {
        guard let app, let repo = GitHubNotes.repoSlug(from: normalized) else { return }
        working = "Checking \(repo)'s latest release…"
        message = nil
        Task {
            do {
                let linked = try await GitHubInstaller.verifyLink(repo: repo, appPath: app.path)
                working = nil
                onLink(linked)
                dismiss()
            } catch {
                working = nil
                message = error.localizedDescription
            }
        }
    }

    private func find() {
        guard let app else { return }
        working = "Searching GitHub for \(app.name)…"
        message = nil
        Task {
            defer { working = nil }
            do {
                let repos = try await GitHubAPI.search(app.name)
                // Check at most three: each check downloads a release.
                for repo in repos.prefix(3) {
                    working = "Checking \(repo)…"
                    if (try? await GitHubInstaller.verifyLink(repo: repo, appPath: app.path)) != nil {
                        link = "github.com/\(repo)"
                        message = "Found \(repo). Its latest release is signed by the same developer as your copy."
                        return
                    }
                }
                message = "No matching project found. Paste the link from the app's website instead."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
