import SwiftUI
import AppKit

// Phase 7: adoption and duplicates (docs/2.0.0-adoption.md, and the teal
// banner, review sheet and Settings group in the mockup).

/// The teal banner on Updates: apps Homebrew could keep up to date.
struct AdoptionBanner: View {
    @EnvironmentObject var controller: UpdateController

    var body: some View {
        let shown = controller.state.visibleAdoptions.filter { $0.verdict != .notBetter }
        if Prefs.adoptionEnabled, !shown.isEmpty {
            HStack(spacing: 10) {
                GlassIconTile(style: SourceStyle(symbol: "mug.fill", color: .teal), size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(shown.count == 1 ? "1 app could be updated by Homebrew"
                                          : "\(shown.count) apps could be updated by Homebrew")
                        .font(.callout.weight(.semibold))
                    Text(shown.allSatisfy { $0.updater == nil }
                         ? "\(shown.count == 1 ? "It has" : "They have") no updater of their own today. Nothing changes unless you say so."
                         : "Homebrew could update \(shown.count == 1 ? "it" : "them") with everything else. Nothing changes unless you say so.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Review") { controller.showingAdoptionReview = true }.glass()
                Button("Not now") { shown.forEach(controller.snoozeAdoption) }
                    .buttonStyle(.borderless).controlSize(.small)
                    .help("Hide these suggestions for 30 days")
            }
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(Color.teal.opacity(0.1))
        }
    }
}

/// "2 apps are installed twice", on Updates, linking to Installed.
struct DuplicatesNote: View {
    @EnvironmentObject var controller: UpdateController

    var body: some View {
        let count = controller.duplicates.count
        if count > 0 {
            Button {
                controller.installedChipRequest = "duplicates"
                controller.page = .installed
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.on.square").foregroundStyle(Color.orange.readable)
                    Text(count == 1 ? "1 app is found twice." : "\(count) apps are found twice.").font(.callout)
                    Text("Review in Installed").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20).padding(.vertical, 7)
                .background(Color.orange.opacity(0.07))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// "Move apps under Homebrew": every candidate with its checks, method,
/// costs and verdict. One click per app, or Adopt all safe ones.
struct AdoptionReviewSheet: View {
    @EnvironmentObject var controller: UpdateController
    @Environment(\.dismiss) private var dismiss
    @State private var showNotBetter = false

    var body: some View {
        let visible = controller.state.visibleAdoptions
        let shown = visible.filter { $0.verdict != .notBetter }
        let notBetter = visible.filter { $0.verdict == .notBetter }
        let safe = shown.filter(\.isSafe)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Move apps under Homebrew").font(.title2.bold())
                Text("\(AppIdentity.name) checks each app first and only suggests it when it is actually better.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(20)
            ScrollView {
                VStack(spacing: 12) {
                    if shown.isEmpty && notBetter.isEmpty {
                        Text("Nothing to suggest right now.").foregroundStyle(.secondary).padding(30)
                    }
                    ForEach(shown) { AdoptionCard(candidate: $0) }
                    if !notBetter.isEmpty {
                        HStack {
                            Text("Hidden because Homebrew would be worse: \(notBetter.count). \(notBetter[0].name): \(notBetter[0].reasons.first ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(showNotBetter ? "Hide" : "Show") { withAnimation { showNotBetter.toggle() } }
                                .buttonStyle(.borderless).controlSize(.small)
                        }
                        .padding(.horizontal, 4)
                        if showNotBetter { ForEach(notBetter) { AdoptionCard(candidate: $0) } }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
            }
            Divider()
            HStack {
                Spacer()
                Button("Adopt all safe ones (\(safe.count))") { controller.adoptAllSafe() }
                    .prismProminent()
                    .disabled(safe.isEmpty || safe.allSatisfy { controller.isBusy(controller.adoptionJob($0)) })
                    .help("Only Recommended apps that are adopted in place: nothing downloaded, no password.")
            }
            .padding(16)
        }
        .frame(width: 560, height: 600)
        .popupClose()
    }
}

/// One candidate in the review sheet.
struct AdoptionCard: View {
    @EnvironmentObject var controller: UpdateController
    let candidate: AdoptionCandidate
    @State private var size: Int64?
    @State private var sizeRead = false

    private var job: UpdateItem { controller.adoptionJob(candidate) }
    private var jobState: InstallState? { controller.installStates[job.id] }

    private var verdictColor: Color {
        switch candidate.verdict {
        case .recommended: .green
        case .worthConsidering: .orange
        case .notBetter: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RowIcon(name: candidate.name, appPath: candidate.appPath, sectionID: "unmanaged", size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.name).font(.headline)
                    Text("\(candidate.installedVersion) · \((candidate.appPath as NSString).deletingLastPathComponent) · cask \(candidate.token)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                StatusPill(text: candidate.verdict.title, color: verdictColor)
            }
            if candidate.verdict == .notBetter, let reason = candidate.reasons.first {
                Text(reason).font(.callout.weight(.medium))
            }
            VStack(alignment: .leading, spacing: 3) {
                line("Today", candidate.updater.map { "Updates itself through \($0)." }
                     ?? "No updater. You'd never be told about a new version.")
                line("With Homebrew", "Updates with everything else, in \(AppIdentity.name)."
                     + (candidate.needsAdmin ? " Needs your password each time." : ""))
            }
            Text(methodText).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if candidate.verdict != .notBetter {
                ForEach(candidate.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                }
            }
            ChipFlow(spacing: 6) {
                ForEach(candidate.checks, id: \.self) { check in
                    Label(check, systemImage: "checkmark").font(.caption2)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.1)))
                }
            }
            actions
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.teal.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.teal.opacity(0.25)))
        .task {
            guard !sizeRead else { return }
            guard let url = candidate.downloadURL else { sizeRead = true; return }
            size = await Adoption.downloadSize(url)
            sizeRead = true
        }
    }

    private func line(_ title: String, _ text: String) -> some View {
        (Text(title + "  ").font(.caption.weight(.semibold)).foregroundStyle(.secondary) + Text(text).font(.caption))
    }

    private var sizeText: String {
        size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            ?? (sizeRead ? "size unknown" : "reading the size…")
    }

    /// The method, in plain words. Sizes only when actually read.
    private var methodText: String {
        switch candidate.method {
        case .inPlace:
            return "Adopt in place. Nothing is replaced: Homebrew downloads its copy once (\(sizeText)) to check that yours is identical. The version matches the cask exactly. No password."
        case .replace:
            let what = candidate.needsAdmin ? "the installer" : "the app"
            return "Replace. Downloads \(what) (\(sizeText)) and installs it. Your copy waits in the Trash until the new one is checked, and comes back if anything is wrong."
                + (candidate.needsAdmin ? " Needs your password." : "")
                + (candidate.vendorDeltas ? " The vendor's own updater sends small delta updates; Homebrew downloads the whole app each time." : "")
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if let jobState, jobState.isActive {
                if let progress = controller.moveProgress[job.id], jobState != .queued {
                    MoveProgressView(progress: progress, compact: true)
                        .onTapGesture { MoveProgressWindow.shared.show(jobID: job.id) }
                } else {
                    ProgressView().controlSize(.small)
                    Text(jobState.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else if jobState == .done {
                StatusPill(text: "Moved to Homebrew", color: .green)
            } else {
                if let error = jobState?.errorMessage {
                    StatusPill(text: "Failed", color: .red).help(error)
                }
                Button(candidate.method == .inPlace ? "Adopt" : "Replace…") { start() }
                    .glassProminent(.teal)
                Button("Not now") { controller.snoozeAdoption(candidate) }.glass()
                    .help("Hide for 30 days")
                Button("Never for this app") { controller.neverAdopt(candidate) }.glass()
            }
            Spacer(minLength: 0)
        }
        .controlSize(.small)
    }

    private func start() {
        guard candidate.method == .replace else { controller.adopt(candidate); return }
        let alert = NSAlert()
        alert.icon = AskpassDialog.badgeIcon(symbol: "exclamationmark")
        alert.messageText = "Replace \(candidate.name) with Homebrew's copy?"
        alert.informativeText = "Your copy moves to the Trash, then Homebrew installs \(Adoption.core(candidate.caskVersion))."
            + " \(AppIdentity.name) checks that it opens, and puts your copy back if anything is wrong."
            + (candidate.needsAdmin ? " Homebrew runs an installer, which needs your password." : "")
            + " Quit \(candidate.name) first if it's open."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        if alert.runModal() == .alertFirstButtonReturn { controller.adopt(candidate) }
    }
}

/// A snoozed or turned-down suggestion, in the Hidden section.
struct HiddenAdoptionRow: View {
    @EnvironmentObject var controller: UpdateController
    let candidate: AdoptionCandidate

    var body: some View {
        HStack(spacing: 10) {
            RowIcon(name: candidate.name, appPath: candidate.appPath, sectionID: "unmanaged").opacity(0.7)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            .opacity(0.7)
            Spacer(minLength: 0)
            Button("Unhide") { controller.unhideAdoption(candidate) }.glass().controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    private var reason: String {
        if controller.state.adoptionNever.contains(candidate.hideKey) { return "Homebrew suggestion, never for this app" }
        let until = controller.state.adoptionSnoozed[candidate.hideKey]
        return "Homebrew suggestion, hidden" + (until.map { " until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")
    }
}

/// The duplicate's advice and its one fix, in the Installed card.
struct DuplicateActions: View {
    @EnvironmentObject var controller: UpdateController
    let group: DuplicateGroup
    let path: String?

    var body: some View {
        // On an extra copy the pop-up's own Move to Trash removes it, so no
        // second button here (two identical buttons confused Nick).
        let isExtra = path.map(group.extras.contains) ?? false
        VStack(alignment: .leading, spacing: 8) {
            Label(isExtra ? "This is a second copy of \(group.name). Keep the one in \(Self.folder(of: group.keep)); Move to Trash below removes this copy."
                          : group.advice,
                  systemImage: "square.on.square")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch group.kind {
            case .twoCopies:
                // On the copy to keep, offer the others, each named by folder.
                if !isExtra {
                    ForEach(group.extras, id: \.self) { extra in
                        UninstallButton(removal: Removal(token: "app:\(extra)", name: "\(group.name) in \(Self.folder(of: extra))"),
                                        title: "Move the Copy in \(Self.folder(of: extra)) to Trash")
                    }
                }
            case .twoStores(let cask):
                HStack {
                    StopManagingButton(cask: cask, appPath: group.keep, name: group.name,
                                       title: "Stop Homebrew tracking it")
                    SwitchToHomebrewButton(cask: cask, appPath: group.keep, name: group.name)
                }
            }
        }
    }
}

extension DuplicateActions {
    /// "~/Applications" rather than the full home path.
    static func folder(of path: String) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        return folder.hasPrefix(NSHomeDirectory()) ? "~" + folder.dropFirst(NSHomeDirectory().count) : folder
    }
}

/// Removes only Homebrew's record of a cask: the app stays.
struct StopManagingButton: View {
    @EnvironmentObject var controller: UpdateController
    let cask: String
    let appPath: String
    let name: String
    var title = "Stop managing with Homebrew"

    private var job: UpdateItem { Adopter.Job(action: "untrack", cask: cask, appPath: appPath).item(name: name) }

    var body: some View {
        let state = controller.installStates[job.id]
        if let state, state.isActive {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Working…").font(.caption) }
        } else if state == .done {
            StatusPill(text: "Homebrew no longer tracks it", color: .secondary)
        } else {
            HStack(spacing: 6) {
                if let error = state?.errorMessage { StatusPill(text: "Failed", color: .red).help(error) }
                Button(title) { confirm() }.glass()
            }
        }
    }

    private func confirm() {
        let alert = NSAlert()
        alert.icon = AskpassDialog.badgeIcon(symbol: "exclamationmark")
        alert.messageText = "\(title)?"
        alert.informativeText = "Homebrew forgets \(name) (cask \(cask)): its record goes to the Trash. The app itself isn't touched, and Homebrew won't update or remove it."
        alert.addButton(withTitle: title)
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        if alert.runModal() == .alertFirstButtonReturn {
            controller.stopManaging(cask: cask, appPath: appPath, name: name)
        }
    }
}

/// "Move to Homebrew…" for an App Store app a cask also installs (Nick,
/// 30 Oct 2026). Replace with one more step: Homebrew's old record of the
/// cask, if any, goes first. Never suggested; only from this button.
struct SwitchToHomebrewButton: View {
    @EnvironmentObject var controller: UpdateController
    let cask: String
    let appPath: String
    let name: String

    private var job: UpdateItem { Adopter.Job(action: "switch", cask: cask, appPath: appPath).item(name: name) }

    var body: some View {
        let state = controller.installStates[job.id]
        if let state, state.isActive {
            if let progress = controller.moveProgress[job.id], state != .queued {
                MoveProgressView(progress: progress, compact: true)
                    .frame(maxWidth: 260)
                    .onTapGesture { MoveProgressWindow.shared.show(jobID: job.id) }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(state.label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } else if state == .done {
            StatusPill(text: "Now from Homebrew", color: .green)
        } else {
            HStack(spacing: 6) {
                if let error = state?.errorMessage { StatusPill(text: "Failed", color: .red).help(error) }
                Button("Move to Homebrew…") { confirm() }.glass()
            }
        }
    }

    private func confirm() {
        let alert = NSAlert()
        alert.icon = AskpassDialog.badgeIcon(symbol: "exclamationmark")
        alert.messageText = "Move \(name) from the App Store to Homebrew?"
        alert.informativeText = "Your App Store copy moves to the Trash and Homebrew installs its own (cask \(cask)). "
            + "\(AppIdentity.name) checks that it's the same app from the same developer, so it keeps your settings, data and sign-ins, and puts your copy back if anything is wrong. "
            + "Homebrew may need your password and a large download. The App Store won't update it any more. Quit \(name) first."
        alert.addButton(withTitle: "Move to Homebrew")
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        if alert.runModal() == .alertFirstButtonReturn {
            controller.switchToHomebrew(cask: cask, appPath: appPath, name: name)
        }
    }
}
