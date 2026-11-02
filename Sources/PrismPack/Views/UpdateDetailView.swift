import SwiftUI
import AppKit

/// "More info" popover for one update: what it is, where it comes from, what
/// changed, and any caveats — everything the row is too small to show.
struct UpdateDetailView: View {
    @EnvironmentObject var controller: UpdateController
    let item: UpdateItem
    @Environment(\.dismiss) private var dismiss

    private var style: SourceStyle { SourceStyle.forSource(item.sectionID) }
    private var sourceName: String {
        UpdateController.allSources.first { $0.id == item.sourceID }?.displayName ?? item.sourceID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            versions
            if item.isMajorUpgrade || item.caveat != nil || selfUpdatingCask != nil || behindVendor != nil { notices }
            if let path = item.appPath, ["sparkle", "github"].contains(item.sourceID) {
                ChannelSection(appPath: path)
            }
            if item.installToken.hasPrefix("cask:"), let betas = controller.separateBetas[String(item.installToken.dropFirst(5))] {
                Label("Separate beta available: \(betas.joined(separator: ", "))", systemImage: "testtube.2")
                    .font(.callout).foregroundStyle(.secondary)
            }
            notesSection
            Divider()
            // Clear groups with even spacing, not squeezed rows (Nick, 2 Nov 2026).
            ignoreGroup
            AutoUpdateControls(item: item)
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 500)
        .popupClose()
        // Uninstall needs the Installed list to know how the item got here.
        .onAppear { if controller.installed.isEmpty, !controller.loadingInstalled { controller.loadInstalled() } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            RowIcon(name: item.name, appPath: item.appPath, sectionID: item.sectionID, size: 40)
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
                    .foregroundStyle(style.color.readable)
            }
            Spacer()
        }
    }

    /// The vendor's own newer release, for a cask PrismPack adopted.
    private var behindVendor: String? {
        HomebrewSource.caskToken(of: item).flatMap { controller.state.adoptedBehind[$0] }
    }

    /// A Homebrew cask that Homebrew marks as updating itself.
    private var selfUpdatingCask: String? {
        guard item.sourceID == "homebrew", let cask = HomebrewSource.caskToken(of: item),
              controller.selfUpdatingCasks.contains(cask) else { return nil }
        return cask
    }

    @ViewBuilder
    private var notices: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let jump = item.majorUpgradeSummary {
                Label("Major version change (\(jump)). For paid apps this is often a separate purchase — check the vendor's terms first.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange.readable)
            }
            if let caveat = item.caveat {
                Label(caveat, systemImage: "info.circle.fill")
                    .foregroundStyle(.secondary)
            }
            if selfUpdatingCask != nil {
                Label("This app also updates itself. Either it or Homebrew can update it.", systemImage: "info.circle.fill")
                    .foregroundStyle(.secondary)
            }
            if let vendor = behindVendor {
                Label("Homebrew is behind the vendor's release (\(vendor)).", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.orange.readable)
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
            } else if let notesURL = item.releaseNotesURL.flatMap(URL.init(string:)) {
                // The notes link lives here now; the footer's Release notes
                // button went (Nick, 2 Nov 2026).
                HStack(spacing: 4) {
                    Text("This vendor publishes its notes on the web.").foregroundStyle(.secondary)
                    Button("Read them") { NSWorkspace.shared.open(notesURL) }.buttonStyle(.link)
                }
                .font(.callout)
            } else {
                Text("No release notes are published for this update. Homebrew formulae and cask updates don't carry changelogs; the project page usually does.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The three hide options. Hidden items show "Unhide" instead.
    @ViewBuilder
    private var ignoreGroup: some View {
        if controller.isIgnored(item) {
            HStack {
                Label(controller.ignoreReason(item), systemImage: "eye.slash")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Unhide") { controller.unhide(item); dismiss() }.glass()
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hide").font(.callout.weight(.semibold))
                HStack(spacing: 10) {
                    Button { controller.dismiss(item); dismiss() } label: {
                        Text("This version").frame(maxWidth: .infinity)
                    }
                    .glass()
                    .help("Hide \(item.latestVersion). The next version shows again.")
                    Button { controller.ignoreApp(item); dismiss() } label: {
                        Text("All updates").frame(maxWidth: .infinity)
                    }
                    .glass()
                    .help("Hide every update for \(item.name) until you unhide it.")
                    Button { controller.ignoreMajors(item); dismiss() } label: {
                        Text("Major upgrades").frame(maxWidth: .infinity)
                    }
                    .glass()
                    .help("Keep offering minor fixes, never the next major version.")
                }
            }
        }
    }

    /// Helpers on the left; Move to Trash (or Uninstall) in red, set apart,
    /// and the main action on the right; close is the circle top right.
    /// Every button the same size.
    private var footer: some View {
        HStack(spacing: 8) {
            if let url = item.url.flatMap(URL.init(string:)) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Website", systemImage: "safari")
                }
                .glass()
            }
            if let path = item.appPath {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .glass()
            }
            Spacer()
            if !controller.isBusy(item), let pkg = controller.installedPackage(for: item), let removal = Removal(pkg) {
                UninstallButton(removal: removal, updateID: item.id)
            }
            if !controller.isBusy(item) && !controller.isIgnored(item) {
                Button {
                    dismiss(); controller.requestUpdate(item)
                } label: {
                    Label(item.actionLabelLong, systemImage: item.actionSymbol)
                }
                .glassProminent(style.color)
            }
        }
    }

    /// The first two lines of release notes, as plain text, for a card:
    /// tags, headings ("What's Changed"), bullets, links and web addresses
    /// left out. Nil when nothing readable is left.
    static func preview(_ notes: String) -> String? {
        let text = notes
            .replacingOccurrences(of: "<h[1-6][^>]*>", with: "\n# ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<br\\s*/?>|</p>|</li>|</h[1-6]>|</div>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s*(in )?https?://\S+"#, with: "", options: .regularExpression)
        let lines = text.components(separatedBy: .newlines).compactMap { raw -> String? in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { return nil }
            line = line.replacingOccurrences(of: #"^([-*+•]|\d+\.)\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            let lower = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            if line.isEmpty || ["what's changed", "what's new", "changes", "changelog", "release notes"].contains(lower) {
                return nil
            }
            return line
        }
        return lines.isEmpty ? nil : lines.prefix(2).joined(separator: "\n")
    }

    /// Rendered notes, keyed by their source text: the HTML importer is slow,
    /// and SwiftUI asks for this on every redraw.
    @MainActor private static var renderedNotes: [String: AttributedString] = [:]

    /// Vendors ship notes as HTML (Sparkle), Markdown (GitHub) or plain text
    /// (App Store). Remote images, scripts and stylesheets are stripped first
    /// so rendering never fetches anything from the vendor's page.
    @MainActor static func attributed(from notes: String) -> AttributedString {
        if let hit = renderedNotes[notes] { return hit }
        let rendered = render(notes)
        if renderedNotes.count > 100 { renderedNotes.removeAll() }
        renderedNotes[notes] = rendered
        return rendered
    }

    private static func render(_ notes: String) -> AttributedString {
        let looksLikeHTML = notes.range(of: "<[a-zA-Z][^>]*>", options: .regularExpression) != nil
        if looksLikeHTML {
            let safe = notes.replacingOccurrences(
                of: "<(img|script|link|iframe|video|audio|source|object|embed)\\b[^>]*>(</\\1>)?",
                with: "", options: [.regularExpression, .caseInsensitive])
            if let data = safe.data(using: .utf8),
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
        }
        // Inline Markdown (bold, code, links) with line breaks kept. Headings
        // ("## What's new") become bold lines and list dashes become bullets,
        // since inline parsing would print their markers as written.
        let lines = notes.components(separatedBy: "\n").map { line -> String in
            if let m = line.firstMatch(of: #/^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$/#) { return "**\(m.1)**" }
            if let m = line.firstMatch(of: #/^(\s*)[-*+]\s+(.*)$/#) { return "\(m.1)• \(m.2)" }
            return line
        }
        if let md = try? AttributedString(
            markdown: lines.joined(separator: "\n"),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return md
        }
        return AttributedString(notes)
    }
}

/// Pin and "Update automatically" on an update's card (Phase 8).
struct AutoUpdateControls: View {
    @EnvironmentObject var controller: UpdateController
    let item: UpdateItem

    private var rule: Binding<String> {
        Binding(get: { controller.autoRule(item)?.rawValue ?? "setting" },
                set: { controller.setAutoRule(AutoUpdate.Rule(rawValue: $0), for: item) })
    }

    var body: some View {
        let _ = controller.autoRulesVersion
        let pinned = controller.isPinned(item)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if pinned {
                    Label("Pinned at \(item.installedVersion)", systemImage: "pin.fill").font(.callout)
                    Spacer()
                    if !item.isPinned {   // uv's own pins are changed in uv
                        Button("Unpin") { controller.setPinned(item, false) }.glass().controlSize(.small)
                    }
                } else {
                    // Segmented, not a menu: a pop-up menu inside the card's
                    // popover dropped the choice (tested 30 Oct 2026). The
                    // glass slider, as on the pages (Nick, 2 Nov 2026).
                    Text("Update automatically").font(.callout.weight(.semibold)).fixedSize()
                    Spacer()
                    GlassSegmented(selection: rule, options: [("setting", "Use setting"),
                                                              (AutoUpdate.Rule.always.rawValue, "Always"),
                                                              (AutoUpdate.Rule.never.rawValue, "Never")])
                }
            }
            if !pinned {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep \(item.installedVersion)").font(.callout.weight(.semibold))
                        Text("Pinned: never automatic, not in Update All.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Keep this version") { controller.setPinned(item, true) }
                        .glass().fixedSize()
                }
            }
            if !pinned, let reason = controller.autoBlocker(item) {
                Text("Won't install automatically: \(reason.prefix(1).lowercased() + reason.dropFirst()).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
