import SwiftUI

/// What a running install is doing, the same in every tile and pop-up. A bar
/// and a small % only where something was really measured (a download's
/// bytes, or a percentage the tool printed); otherwise a small spinner and a
/// notice that progress can't be measured, with the time so far (Nick,
/// 2 Nov 2026). The line under says the step: Downloading, Verifying,
/// Unzipping, Installing, Cleaning up…
struct InstallProgressView: View {
    let progress: InstallProgress
    /// The bar's width when there is one.
    var barWidth: CGFloat = 90

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if let percent = progress.percentText, let fraction = progress.fraction {
                HStack(spacing: 6) {
                    ProgressView(value: fraction).frame(width: barWidth)
                    Text("\(percent)%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(progress.phase.title + "…").font(.caption).lineLimit(1)
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(note(now: context.date)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .fixedSize()
    }

    private func note(now: Date) -> String {
        // Bytes without a total are still real: show them instead of the notice.
        if progress.fraction != nil || progress.bytesText != nil { return progress.line(now: now) }
        let seconds = Int(now.timeIntervalSince(progress.startedAt))
        return seconds >= 60 ? "Can't measure progress · \(InstallProgress.clock(seconds))" : "Can't measure progress"
    }
}
