import SwiftUI

/// What an app's card needs to offer Stable / Beta.
struct ChannelInfo {
    enum Kind { case sparkle, github(repo: String), ownApp }
    let kind: Kind
    let bundleID: String
    let name: String
    let installed: String
    let offersBeta: Bool
    /// The stable version "Go back to stable" installs: set when a beta is
    /// installed and the newest stable release is older than it.
    let stableBelow: String?

    /// Reads the app's feed or GitHub releases. nil for apps without channels.
    static func load(appPath: String) async -> ChannelInfo? {
        guard let facts = Adoption.facts(at: appPath) else { return nil }
        let name = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        if let app = GitHubApps.load().first(where: { $0.appPath == appPath }) {
            let newest = try? await GitHubAPI.newestRelease(app.repo)
            let stable = try? await GitHubAPI.latestRelease(app.repo)
            var below: String?
            if VersionParts(facts.version).track > 0, let stable, isNewerVersion(facts.version, than: stable.version) {
                below = stable.version
            }
            return ChannelInfo(kind: .github(repo: app.repo), bundleID: app.bundleID, name: name,
                               installed: facts.version, offersBeta: newest?.prerelease == true, stableBelow: below)
        }
        guard let feed = facts.feedURL,
              let (data, response) = try? await Net.fetch(feed),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let own = appPath == Bundle.main.bundlePath
        let build = Bundle(path: appPath)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        // Sparkle never installs an older PrismPack, so its own card has no
        // "Go back to stable": Stable takes effect with the next stable release.
        let below = own ? nil
            : AppcastParser.stableBelow(from: data, installed: facts.version, installedBuild: build)?.displayVersion
        return ChannelInfo(kind: own ? .ownApp : .sparkle, bundleID: facts.bundleID,
                           name: own ? AppIdentity.name : name, installed: facts.version,
                           offersBeta: AppcastParser.offersBetas(data), stableBelow: below)
    }
}

/// Stable / Beta on an app's card, with "Go back to stable" when a beta is
/// installed and Stable is chosen (a downgrade: its own button and a warning,
/// never part of Update All).
struct ChannelSection: View {
    @EnvironmentObject var controller: UpdateController
    let appPath: String
    @State private var info: ChannelInfo?
    @State private var channel: Channel = .stable
    @State private var confirmingDowngrade = false
    @State private var downgrade: UpdateItem?
    /// Bumped when a go-back finishes, so the card reads the new version.
    @State private var reloads = 0

    var body: some View {
        // A VStack, not a Group: an empty Group has no view to run `.task` on.
        VStack(alignment: .leading, spacing: 0) {
            if let info, info.offersBeta || channel == .beta || info.stableBelow != nil {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Updates") {
                        // The glass slider, as everywhere (Nick, 2 Nov 2026).
                        GlassSegmented(selection: $channel, options: Channel.allCases.map { ($0, $0.title) })
                    }
                    caption(info)
                    if channel == .stable, let version = info.stableBelow { goBack(info, version: version) }
                }
                .onChange(of: channel) { _, new in
                    Channels.set(new, for: info.bundleID)
                    controller.checkNow()
                }
            }
        }
        .onChange(of: downgrade.map(controller.isBusy) ?? false) { was, now in
            guard was, !now else { return }
            reloads += 1
            controller.loadInstalled()
        }
        .task(id: "\(appPath)#\(reloads)") {
            guard let loaded = await ChannelInfo.load(appPath: appPath) else { return }
            channel = Channels.effective(Channels.choice(for: loaded.bundleID), installedVersion: loaded.installed)
            info = loaded
        }
    }

    @ViewBuilder
    private func caption(_ info: ChannelInfo) -> some View {
        let text: String = switch (channel, info.kind) {
        case (.beta, .github): "Includes the pre-releases the developer posts."
        case (.beta, _): "Betas and stable releases, whichever is newer."
        case (.stable, .ownApp) where VersionParts(info.installed).track > 0:
            "You stay on this beta until a newer stable release comes out."
        case (.stable, _): "Stable releases only."
        }
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func goBack(_ info: ChannelInfo, version: String) -> some View {
        if let downgrade, controller.isBusy(downgrade) {
            Label("Going back to \(version)…", systemImage: "arrow.uturn.backward")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Button {
                confirmingDowngrade = true
            } label: {
                Label("Go back to stable, version \(version)", systemImage: "arrow.uturn.backward")
            }
            .glass()
            .confirmationDialog("Go back to \(info.name) \(version)?", isPresented: $confirmingDowngrade) {
                Button("Go back to \(version)", role: .destructive) { start(info, version: version) }
            } message: {
                Text("This installs an older version than the beta you have. Going back can leave \(info.name) unable to read data the beta saved. The beta goes to the Trash.")
            }
        }
    }

    private func start(_ info: ChannelInfo, version: String) {
        let (source, token): (String, String) = switch info.kind {
        case .github(let repo): ("github", repo)
        default: ("sparkle", appPath)
        }
        let item = UpdateItem(sourceID: source, name: info.name, installedVersion: info.installed,
                              latestVersion: version, caveat: "Going back to the stable release.",
                              installToken: token, scriptedInstall: true, appPath: appPath)
        downgrade = item
        controller.update(item)
    }
}
