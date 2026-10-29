import SwiftUI

/// TEMPORARY (build guide 5.6): a sidebar page for judging the Update All
/// button with real Liquid Glass, and every section colour for legibility.
/// Not a 2.0 feature. Remove it, and this file, once Nick has signed off,
/// and before any beta or release build.
enum ButtonLab {
    /// The one switch: false takes the page out of the sidebar.
    static let enabled = true
}

struct ButtonLabPage: View {
    @State private var scheme: ColorScheme? = nil

    /// Every warning a row can show, with example text.
    private let warnings: [WarningKind] = [
        .majorUpgrade("6 → 8"),
        .restart("Requires restart. Opens Software Update in System Settings to install."),
        .iosApp,
    ]

    private let sections = ["homebrew", "mas", "macos", "caskOracle", "components", "sparkle", "custom",
                            "tools", "pip", "npm", "editors", "leftover", "hidden"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Temporary page, never shipped.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    GlassSegmented(selection: $scheme, options: [(nil, "System"), (.light, "Light"), (.dark, "Dark")])
                }

                Text("Update All").font(.headline)
                HStack(spacing: 18) {
                    sample("Regular") { Button("Update All") {}.prismProminent() }
                    sample("Large") { Button("Update All") {}.prismProminent().controlSize(.large) }
                    sample("Disabled") { Button("Update All") {}.prismProminent().disabled(true) }
                    sample("Authorize") { Button("Authorize") {}.prismProminent() }
                }

                Text("Every section colour: buttons, pills and text").font(.headline)
                VStack(spacing: 8) {
                    ForEach(sections, id: \.self) { id in
                        colourRow(id)
                    }
                }

                Text("Status pills").font(.headline)
                HStack(spacing: 8) {
                    StatusPill(text: "Installing", color: .blue)
                    StatusPill(text: "Needs admin", color: .orange)
                    StatusPill(text: "Failed", color: .red)
                    StatusPill(text: "Up to date", color: .green)
                    StatusPill(text: "Not managed", color: .secondary)
                    StatusPill(text: "Skipped", color: .orange)
                }
                Text("Warning badges, and the card each one opens").font(.headline)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, kind in
                        HStack(alignment: .top, spacing: 14) {
                            WarningBadge(kind).padding(.top, 12)
                            WarningCard(title: kind.title, message: kind.message,
                                        symbol: kind.symbol, color: kind.color)
                                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Label("All dependencies installed", systemImage: "checkmark.circle")
                        .foregroundStyle(Color.green.readable)
                }
            }
            .padding(20)
        }
        .background(GlassBackground())
        .preferredColorScheme(scheme)
    }

    private func colourRow(_ id: String) -> some View {
        let style = SourceStyle.forSource(id)
        return HStack(spacing: 12) {
            GlassIconTile(style: style, size: 26)
            Text(UpdatesPage.title(of: id)).frame(width: 150, alignment: .leading)
            Text("1.2 to 1.3").foregroundStyle(style.color.readable).fontWeight(.medium)
            Spacer()
            StatusPill(text: "Example", color: style.color)
            Button("Update") {}.glassProminent(style.color).controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .modifier(SectionPanel(color: style.color))
    }

    private func sample<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}
