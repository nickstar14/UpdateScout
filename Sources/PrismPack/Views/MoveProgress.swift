import SwiftUI
import AppKit

/// Where a long move is: adopt, Replace, Move to Homebrew, a GitHub update
/// (Nick, 30 Oct 2026: a user should know roughly what's happening). Jobs
/// report steps as marker lines (`§step:download`, `§download:<done>/<total>`)
/// through their normal progress output; the controller turns them into this.
struct MoveProgress: Equatable {
    enum Step: String, CaseIterable {
        case trash, download, install, check, launch, swap

        var title: String {
            switch self {
            case .trash: "Move your copy to the Trash"
            case .download: "Download"
            case .install: "Install"
            case .check: "Check it's the same app"
            case .launch: "Test launch"
            case .swap: "Put the new copy in place"
            }
        }
    }

    let title: String
    let steps: [Step]
    var current: Step?
    var done: Set<Step> = []
    var downloaded: Int64 = 0
    var total: Int64?
    /// The last plain line of output, for detail under the steps.
    var detail = ""
    var finished = false
    var failure: String?

    /// The steps for a job, or nil for jobs that don't show this.
    static func plan(for item: UpdateItem) -> MoveProgress? {
        switch item.sourceID {
        case "github":
            return MoveProgress(title: "Updating \(item.name) from GitHub", steps: [.download, .check, .swap])
        case "caskOracle":
            return MoveProgress(title: "Updating \(item.name) with Homebrew", steps: [.trash, .download, .install, .check, .launch])
        case "adopt":
            guard let job = Adopter.Job(token: item.installToken) else { return nil }
            switch job.action {
            case "adopt": return MoveProgress(title: "Moving \(item.name) under Homebrew", steps: [.download, .install, .check])
            case "replace": return MoveProgress(title: "Replacing \(item.name) with Homebrew's copy", steps: [.trash, .download, .install, .check, .launch])
            case "switch": return MoveProgress(title: "Moving \(item.name) to Homebrew", steps: [.trash, .download, .install, .check, .launch])
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Fold in one line of output. Homebrew's own headings mark steps too.
    mutating func take(_ line: String) {
        if line.hasPrefix("§step:"), let step = Step(rawValue: String(line.dropFirst(6))) {
            start(step)
        } else if line.hasPrefix("§download:") {
            let parts = line.dropFirst(10).split(separator: "/")
            downloaded = Int64(parts.first ?? "") ?? downloaded
            if parts.count > 1, let t = Int64(parts[1]), t > 0 { total = t }
        } else if line.hasPrefix("==> Fetching") || line.hasPrefix("==> Downloading") {
            start(.download)
        } else if line.hasPrefix("==> Installing") || line.hasPrefix("==> Running installer") || line.hasPrefix("==> Adopting") {
            start(.install)
        } else if !line.hasPrefix("§") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { detail = trimmed }
        }
    }

    private mutating func start(_ step: Step) {
        guard steps.contains(step) else { return }
        for earlier in steps.prefix(while: { $0 != step }) { done.insert(earlier) }
        current = step
    }

    /// 0…1 across the steps, with the download counted by its bytes.
    var fraction: Double {
        if finished && failure == nil { return 1 }
        guard let current, let index = steps.firstIndex(of: current) else { return 0 }
        var within = 0.5
        if current == .download, let total, total > 0 { within = min(1, Double(downloaded) / Double(total)) }
        return (Double(index) + within) / Double(steps.count)
    }

    var downloadText: String? {
        guard downloaded > 0 else { return nil }
        let done = ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
        return total.map { "\(done) of \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))" } ?? done
    }
}

/// The steps, a bar and the download size. Used in the pop-up and in place.
struct MoveProgressView: View {
    let progress: MoveProgress
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 10) {
            ProgressView(value: progress.fraction)
                .tint(progress.failure == nil ? .accentColor : .red)
            if compact {
                Text(currentLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(progress.steps, id: \.self) { step in
                        HStack(spacing: 8) {
                            symbol(for: step).frame(width: 16)
                            Text(step.title)
                                .foregroundStyle(progress.current == step && !progress.finished ? .primary : .secondary)
                            if step == .download, let text = progress.downloadText {
                                Text(text).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .font(.callout)
                    }
                }
                if let failure = progress.failure {
                    Text(failure).font(.caption).foregroundStyle(Color.red.readable)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !progress.finished, !progress.detail.isEmpty {
                    Text(progress.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    private var currentLine: String {
        if let failure = progress.failure { return failure }
        if progress.finished { return "Done" }
        guard let current = progress.current else { return "Starting…" }
        if current == .download, let text = progress.downloadText { return "Downloading · \(text)" }
        return current.title + "…"
    }

    @ViewBuilder
    private func symbol(for step: MoveProgress.Step) -> some View {
        if progress.done.contains(step) || (progress.finished && progress.failure == nil) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green.readable)
        } else if progress.current == step && progress.failure != nil {
            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.red.readable)
        } else if progress.current == step {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}

/// The pop-up: opens when a long move starts, can be closed while it runs.
@MainActor
final class MoveProgressWindow {
    static let shared = MoveProgressWindow()
    private var windows: [String: NSPanel] = [:]

    func show(jobID: String) {
        if let window = windows[jobID] { window.orderFront(nil); return }
        let view = MoveProgressPanel(jobID: jobID) { [weak self] in self?.close(jobID) }
            .environmentObject(UpdateController.shared)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.title = "Progress"
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.contentViewController = NSHostingController(rootView: view)
        panel.isReleasedWhenClosed = false
        if let frame = UpdatesWindow.shared.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 400, y: frame.maxY - 340))
        } else {
            panel.center()
        }
        windows[jobID] = panel
        panel.orderFront(nil)
    }

    func close(_ jobID: String) {
        windows.removeValue(forKey: jobID)?.close()
    }
}

private struct MoveProgressPanel: View {
    @EnvironmentObject var controller: UpdateController
    let jobID: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let progress = controller.moveProgress[jobID] {
                HStack(spacing: 10) {
                    AppLogo(size: 32)
                    Text(progress.title).font(.headline)
                }
                MoveProgressView(progress: progress)
                HStack {
                    Text(progress.finished ? (progress.failure == nil ? "Finished." : "Stopped.")
                                           : "You can close this; it carries on.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(progress.finished ? "Done" : "Close", action: onClose)
                        .keyboardShortcut(progress.finished ? .defaultAction : .cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
