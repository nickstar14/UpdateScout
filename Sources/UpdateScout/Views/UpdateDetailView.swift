import SwiftUI
import AppKit

/// "More info" popover for one update: what it is, where it comes from, what
/// changed, and any caveats — everything the row is too small to show.
struct UpdateDetailView: View {
    @EnvironmentObject var controller: UpdateController
    let item: UpdateItem
    @Environment(\.dismiss) private var dismiss

    private var style: SourceStyle { SourceStyle.forSource(item.sourceID) }
    private var sourceName: String {
        UpdateController.allSources.first { $0.id == item.sourceID }?.displayName ?? item.sourceID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            versions
            if item.isMajorUpgrade || item.caveat != nil { notices }
            notesSection
            Divider()
            footer
        }
        .padding(18)
        .frame(width: 440)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: style.symbol)
                .font(.system(size: 26))
                .foregroundStyle(style.color)
                .frame(width: 40, height: 40)
                .background(style.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.title3).bold()
                Label(sourceName, systemImage: style.symbol)
                    .font(.caption).foregroundStyle(.secondary)
                    .labelStyle(.titleOnly)
            }
            Spacer()
        }
    }

    private var versions: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Installed").font(.caption).foregroundStyle(.secondary)
                Text(item.installedVersion).font(.body.monospacedDigit())
            }
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Available").font(.caption).foregroundStyle(.secondary)
                Text(item.latestVersion).font(.body.monospacedDigit()).bold()
                    .foregroundStyle(style.color)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var notices: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let jump = item.majorUpgradeSummary {
                Label("Major version change (\(jump)). For paid apps this is often a separate purchase — check the vendor's terms first.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if let caveat = item.caveat {
                Label(caveat, systemImage: "info.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What's new").font(.headline)
            if let notes = item.releaseNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Text(Self.attributed(from: notes))
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            } else {
                Text(item.releaseNotesURL != nil
                     ? "This vendor publishes notes on the web — use the link below."
                     : "No release notes are published for this update. Homebrew formulae and cask updates don't carry changelogs; the project page usually does.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let notesURL = item.releaseNotesURL.flatMap(URL.init(string:)) {
                Link("Full release notes", destination: notesURL).font(.callout)
            }
            if let url = item.url.flatMap(URL.init(string:)) {
                Link("Info page", destination: url).font(.callout)
            }
            Spacer()
            Button("Close") { dismiss() }.glass()
            if controller.installing[item.id] == nil {
                Button(item.scriptedInstall ? "Update" : "Get…") {
                    controller.update(item); dismiss()
                }
                .glassProminent(style.color)
            }
        }
    }

    /// Vendors ship notes as HTML (Sparkle) or plain text (App Store). Render
    /// HTML when it looks like HTML; otherwise show the text as-is.
    static func attributed(from notes: String) -> AttributedString {
        let looksLikeHTML = notes.range(of: "<[a-zA-Z][^>]*>", options: .regularExpression) != nil
        if looksLikeHTML, let data = notes.data(using: .utf8),
           let ns = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil) {
            // Drop the HTML's own fonts/colours so it follows the app's theme.
            let plain = NSMutableAttributedString(attributedString: ns)
            plain.removeAttribute(.font, range: NSRange(location: 0, length: plain.length))
            plain.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: plain.length))
            plain.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: plain.length))
            return AttributedString(plain)
        }
        return AttributedString(notes)
    }
}
