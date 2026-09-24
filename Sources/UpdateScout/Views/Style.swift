import SwiftUI

/// Per-source icon and accent colour, so rows and headers read at a glance.
struct SourceStyle {
    let symbol: String
    let color: Color

    static func forSource(_ id: String) -> SourceStyle {
        switch id {
        case "homebrew":   SourceStyle(symbol: "mug.fill",             color: .brown)
        case "mas":        SourceStyle(symbol: "bag.fill",             color: .blue)
        // Graphite rather than .primary: primary is solid black in light mode,
        // which made the Update button far heavier than every other card. One
        // fixed graphite was too dim on dark cards, so it shifts per theme.
        case "macos":      SourceStyle(symbol: "apple.logo", color: Theme.graphite)
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

/// Shared surface colours. The system window background is near-black in dark
/// mode and near-white in light; both make the glass look flat and harsh, so
/// these sit closer to mid-grey while still reading as light or dark.
enum Theme {
    static let wash = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.30, alpha: 1)
            : NSColor(calibratedWhite: 0.72, alpha: 1)
    })

    /// Mid-tone blue-grey for macOS items: deep enough to carry white button
    /// text in light mode, bright enough to read on dark cards.
    static let graphite = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.62, green: 0.67, blue: 0.76, alpha: 1)
            : NSColor(srgbRed: 0.40, green: 0.44, blue: 0.52, alpha: 1)
    })

    /// Card / settings-pane fill, so both surfaces match.
    static let card = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.30, alpha: 0.55)
            : NSColor(calibratedWhite: 0.98, alpha: 0.55)
    })
}

/// The app's own icon, rendered at the exact backing-pixel size it's shown at.
/// `Image(nsImage:).resizable()` can pick a small representation and scale it
/// up, which is what made the header logo look soft and pixelated.
struct AppLogo: View {
    var size: CGFloat
    @Environment(\.displayScale) private var scale

    var body: some View {
        Image(nsImage: Self.rendered(points: size, scale: scale))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func rendered(points: CGFloat, scale: CGFloat) -> NSImage {
        let key = "\(points)@\(scale)"
        if let hit = cache[key] { return hit }
        let px = Int((points * scale).rounded())
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            return NSApp.applicationIconImage
        }
        rep.size = NSSize(width: points, height: points)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        // Drawing into a rect this size makes NSImage pick its best
        // representation for the destination instead of a small one.
        NSApp.applicationIconImage.draw(in: NSRect(x: 0, y: 0, width: points, height: points))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: points, height: points))
        image.addRepresentation(rep)
        cache[key] = image
        return image
    }
}
