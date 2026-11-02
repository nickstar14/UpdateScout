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
                    .glassDestructive().controlSize(.small)
                }
            }
            HStack(alignment: .top) {
                Text("Apps that publish their updates as GitHub releases. Only a download signed by the same developer as your copy is installed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Add an App…") { adding = true }.glass().fixedSize()
            }
        }
        .sheet(isPresented: $adding) {
            GitHubLinkSheet { linked in
                GitHubApps.link(linked)
                apps = GitHubApps.load()
            }
        }
    }
}

/// Pick an installed app; GitHub is searched for it straight away and the
/// best project that checks out is chosen. Search other words or paste a
/// link if it guessed wrong (Nick, 2 Nov 2026). Apps with no developer
/// signature can be linked after a warning.
struct GitHubLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// The app to start with, from a Not managed app's pop-up on Installed.
    var preselect: String? = nil
    let onLink: (GitHubApp) -> Void

    private struct Choice {
        let facts: AppFacts
        let signed: Bool
    }

    @State private var choices: [Choice] = []
    @State private var appPath = ""
    @State private var query = ""
    @State private var hits: [GitHubAPI.Hit] = []
    @State private var selected: String?
    @State private var checked: Set<String> = []
    @State private var trusted = false
    @State private var working: String?
    @State private var message: String?
    @State private var searchTask: Task<Void, Never>?

    private var choice: Choice? { choices.first { $0.facts.path == appPath } }
    private var unsigned: Bool { choice.map { !$0.signed } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Update an app from GitHub").font(.title3.bold())
            // The glass menu, as everywhere (Nick, 2 Nov 2026).
            LabeledContent("App") {
                SortMenu(selection: $appPath,
                         options: [("", "Choose an app")] + choices.map {
                             ($0.facts.path, "\($0.facts.name) \($0.facts.version)" + ($0.signed ? "" : " (not signed)"))
                         },
                         help: "The app to update from GitHub")
            }
            if unsigned {
                VStack(alignment: .leading, spacing: 6) {
                    Label("This app has no developer signature, so \(AppIdentity.name) can only check that a download is the same app (its ID), not who made it. Anyone who takes over the GitHub project could send a harmful update. Link it only if the project is yours or you trust it.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Color.orange.readable)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("I trust this project", isOn: $trusted).toggleStyle(.checkbox).font(.caption)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                GlassSearchField(prompt: "Search GitHub, or paste a link", text: $query)
                    .onSubmit { search(checking: true) }
                    .disabled(choice == nil)
                if !hits.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(hits) { hit in hitRow(hit) }
                    }
                }
            }
            if let working {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text(working).font(.caption).foregroundStyle(.secondary) }
            } else if let message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(unsigned
                 ? "\(AppIdentity.name) downloads the latest release once to check it's the same app. Updates for unsigned apps are only installed from an app download, never an installer package."
                 : "\(AppIdentity.name) downloads the latest release once to check who signed it, then only checks for new releases.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            // Closes with the circle, as every pop-up does (Nick, 2 Nov 2026).
            HStack {
                Spacer()
                Button("Link") { linkIt() }
                    .prismProminent()
                    .keyboardShortcut(.defaultAction)
                    .disabled(choice == nil || selected == nil || working != nil || (unsigned && !trusted))
            }
        }
        .padding(20)
        .frame(width: 520)
        .popupClose()
        .task {
            // Not App Store apps, and not Apple's own. Unsigned apps are
            // listed too, marked, for linking after the warning.
            choices = Adoption.installedApps()
                .filter { !$0.hasMASReceipt && !$0.bundleID.hasPrefix("com.apple.") }
                .map { Choice(facts: $0, signed: CodeSign.teamID($0.path) != nil) }
                .sorted { $0.facts.name.localizedCaseInsensitiveCompare($1.facts.name) == .orderedAscending }
            if let preselect {
                appPath = choices.first { $0.facts.path.lowercased() == preselect.lowercased() }?.facts.path ?? ""
            }
        }
        .onChange(of: appPath) { _, _ in
            trusted = false
            guard let choice else { hits = []; selected = nil; return }
            query = choice.facts.name
            search(checking: true)
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func hitRow(_ hit: GitHubAPI.Hit) -> some View {
        let isSelected = hit.repo == selected
        return Button { selected = hit.repo } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.repo).font(.callout.weight(.semibold)).lineLimit(1)
                    if !hit.about.isEmpty {
                        Text(hit.about).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if checked.contains(hit.repo) { StatusPill(text: "Checks out", color: .green) }
                if hit.stars > 0 {
                    Label("\(hit.stars)", systemImage: "star").font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .contentShape(Rectangle())
            // Selection is grey, never purple.
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isSelected ? 0.12 : 0.04)))
        }
        .buttonStyle(.plain)
    }

    /// "owner/name" from a github.com link or a bare "owner/name".
    private var pastedRepo: String? {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.contains("/"), !text.contains(" ") else { return nil }
        let link = text.contains("github.com") ? (text.hasPrefix("http") ? text : "https://" + text)
                                               : "https://github.com/" + text
        return GitHubNotes.repoSlug(from: link)
    }

    /// Lists projects for the query (or the pasted one), then checks the
    /// first few and chooses the first that checks out.
    private func search(checking: Bool) {
        guard let choice else { return }
        searchTask?.cancel()
        message = nil
        checked = []
        if let repo = pastedRepo {
            hits = [GitHubAPI.Hit(repo: repo, about: "", stars: 0)]
            selected = repo
            return
        }
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { hits = []; selected = nil; return }
        searchTask = Task {
            working = "Searching GitHub for \(text)…"
            defer { working = nil }
            do {
                let found = try await GitHubAPI.searchHits(text)
                guard !Task.isCancelled else { return }
                hits = found
                selected = found.first?.repo
                guard !found.isEmpty else {
                    message = "Nothing found. Try other words, or paste the project's link."
                    return
                }
                guard checking else { return }
                // Each check downloads a release, so at most three.
                for hit in found.prefix(3) {
                    working = "Checking \(hit.repo)…"
                    if (try? await GitHubInstaller.verifyLink(repo: hit.repo, appPath: choice.facts.path,
                                                              allowUnsigned: !choice.signed)) != nil {
                        guard !Task.isCancelled else { return }
                        checked.insert(hit.repo)
                        selected = hit.repo
                        message = "\(hit.repo) checks out: its latest release is " + (choice.signed
                            ? "signed by the same developer as your copy." : "the same app as yours.")
                        return
                    }
                    if Task.isCancelled { return }
                }
                message = "None of the first matches checked out. Pick one to try it, search other words, or paste the link."
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func linkIt() {
        guard let choice, let repo = selected else { return }
        working = "Checking \(repo)'s latest release…"
        message = nil
        Task {
            do {
                let linked = try await GitHubInstaller.verifyLink(repo: repo, appPath: choice.facts.path,
                                                                  allowUnsigned: !choice.signed && trusted)
                working = nil
                onLink(linked)
                dismiss()
            } catch {
                working = nil
                message = error.localizedDescription
            }
        }
    }
}
