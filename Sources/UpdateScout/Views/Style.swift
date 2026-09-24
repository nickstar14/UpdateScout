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

/// A section's container. The corner radius is half the header's height, so a
/// collapsed section is exactly a capsule — the header pill. Expanded, the
/// header keeps its solid fill right down to where that pill would end, then
/// fades out fast so the cards sit on clear glass; a firmer outline traces the
/// whole section, and an outer shadow lifts it off the window's glass.
struct SectionPanel: ViewModifier {
    static let headerHeight: CGFloat = 32
    static var radius: CGFloat { headerHeight / 2 }

    /// How far below the pill's edge the header band takes to fade out.
    static let fadeLength: CGFloat = 28
    /// Tint carried through the whole section under the header.
    static let bodyTint: Double = 0.2

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        let band = Self.headerHeight + Self.fadeLength
        content
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    // A faint tint through the whole section, so the pill and
                    // the area under it read as one surface opening up rather
                    // than a pill sitting above a hole.
                    shape.fill(Theme.card.opacity(Self.bodyTint))
                    // Solid to exactly where the collapsed pill ends, then an
                    // eased fade down into the faint tint. Fixed height (not
                    // relative to the panel), so it doesn't shift while the
                    // section rolls; collapsed, the clip cuts it at the pill
                    // edge and the pill is fully solid.
                    LinearGradient(stops: [
                        .init(color: Theme.card, location: 0),
                        .init(color: Theme.card, location: Self.headerHeight / band),
                        .init(color: Theme.card.opacity(0.72), location: (Self.headerHeight + 5) / band),
                        .init(color: Theme.card.opacity(0.4), location: (Self.headerHeight + 12) / band),
                        .init(color: Theme.card.opacity(0.14), location: (Self.headerHeight + 20) / band),
                        .init(color: Theme.card.opacity(0), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: band)
                    // Drawn over a Color.clear that takes exactly the panel's
                    // size, so the clip really is the panel. (A `.frame(maxHeight:
                    // .infinity)` wrapper grows to fit its 60 pt child instead,
                    // which left the fade hanging below a collapsed pill.)
                    .modifier(PinnedTop())
                    .clipShape(shape)
                }
            }
            .overlay(shape.strokeBorder(Color.primary.opacity(0.22)))
            .background { OuterShadow(shape: shape) }
    }
}

/// Lays content out at its own size, pinned to the top of a container that
/// takes exactly the proposed size — so anything clipped afterwards is clipped
/// to the container, not to the (possibly taller) content.
private struct PinnedTop: ViewModifier {
    func body(content: Content) -> some View {
        Color.clear.overlay(alignment: .top) { content }
    }
}

/// A shadow that only falls *outside* a shape. A plain `.shadow` on a mostly
/// clear panel would darken its interior (or shadow the outline stroke on both
/// sides); here the shape is drawn solid with its shadow and then masked so
/// only the part beyond the shape's edge shows.
private struct OuterShadow<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(Color.black)
            .shadow(color: .black.opacity(0.22), radius: 9, y: 4)
            .mask { Outside(base: shape).fill(style: FillStyle(eoFill: true)) }
            .allowsHitTesting(false)
    }

    /// Everything around a shape: a generous rectangle with the shape cut out.
    /// A Shape (not a GeometryReader), so SwiftUI redraws it with the animated
    /// frame on every animation frame; a GeometryReader jumped straight to the
    /// final size mid-animation and let the black caster show through.
    private struct Outside: Shape {
        let base: S
        func path(in rect: CGRect) -> Path {
            var path = Path(rect.insetBy(dx: -40, dy: -40))
            path.addPath(base.path(in: rect))
            return path
        }
    }
}

/// The frosted "title sheet" behind the window's header: glass with a light
/// tint, running past the top and side edges so only its rounded bottom is
/// visible — the bottom corners curve straight into the window's sides, and
/// the side outlines fall outside the window and are clipped away.
struct TitleSheet: View {
    static let bottomRadius: CGFloat = 22

    var body: some View {
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Self.bottomRadius,
                                           bottomTrailingRadius: Self.bottomRadius,
                                           style: .continuous)
        ZStack {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThickMaterial)
            }
            // A heavy frost: a blur layer plus a strong tint, so the header
            // reads as a solid sheet. Content scrolling up simply disappears
            // beneath it, which is intended.
            shape.fill(.thinMaterial)
            shape.fill(Theme.card.opacity(0.9))
        }
        .overlay(shape.strokeBorder(Color.primary.opacity(0.14)))
        .background { OuterShadow(shape: shape) }
        .padding(.horizontal, -1)    // side outlines land just outside the window
        .padding(.top, -60)          // run past the window's top edge
    }
}
