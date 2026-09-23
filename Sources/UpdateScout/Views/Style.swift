import SwiftUI

/// Per-source icon and accent colour, so rows and headers read at a glance.
struct SourceStyle {
    let symbol: String
    let color: Color

    static func forSource(_ id: String) -> SourceStyle {
        switch id {
        case "homebrew":   SourceStyle(symbol: "mug.fill",             color: .brown)
        case "mas":        SourceStyle(symbol: "bag.fill",             color: .blue)
        case "macos":      SourceStyle(symbol: "apple.logo",           color: .primary)
        case "caskOracle": SourceStyle(symbol: "shippingbox.fill",     color: .teal)
        case "components": SourceStyle(symbol: "cpu.fill",             color: .purple)
        case "sparkle":    SourceStyle(symbol: "sparkles",             color: .yellow)
        case "custom":     SourceStyle(symbol: "slider.horizontal.3",  color: .green)
        default:           SourceStyle(symbol: "arrow.down.circle.fill", color: .accentColor)
        }
    }
}

/// Liquid Glass button styles on macOS 26+, with sensible fallbacks below.
struct GlassProminentButton: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent).tint(tint)
        } else {
            content.buttonStyle(.borderedProminent).tint(tint)
        }
    }
}

struct GlassButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func glassProminent(_ tint: Color) -> some View { modifier(GlassProminentButton(tint: tint)) }
    func glass() -> some View { modifier(GlassButton()) }
}

/// A small warning triangle that explains itself on hover (tooltip) and on
/// click (popover) — replaces walls of orange text.
struct WarningBadge: View {
    let title: String
    let message: String
    var symbol: String = "exclamationmark.triangle.fill"
    var color: Color = .orange
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .help(message)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.headline).foregroundStyle(color)
                Text(message).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 320, alignment: .leading)
        }
    }
}
