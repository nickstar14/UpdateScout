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
        case "github":     SourceStyle(symbol: "chevron.left.forwardslash.chevron.right", color: .cyan)
        case "pip":        SourceStyle(symbol: "terminal.fill",        color: .orange)
        case "npm":        SourceStyle(symbol: "square.stack.3d.up.fill", color: Theme.npmRed)
        case "tools":      SourceStyle(symbol: "wrench.and.screwdriver.fill", color: .mint)
        case "editors":    SourceStyle(symbol: "puzzlepiece.extension.fill", color: .indigo)
        case "cargo":      SourceStyle(symbol: "gearshape.2.fill",     color: Theme.rustCopper)
        case "gem":        SourceStyle(symbol: "diamond.fill",         color: Theme.rubyCrimson)
        case "leftover":   SourceStyle(symbol: "trash.slash.fill",     color: Theme.leftoverPink)
        case "hidden":     SourceStyle(symbol: "eye",                  color: Theme.navy)
        default:           SourceStyle(symbol: "arrow.down.circle.fill", color: .accentColor)
        }
    }
}

/// Liquid Glass button styles on macOS 26+, with sensible fallbacks below.
struct GlassProminentButton: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        // Bright hues are deepened so the white label stays readable.
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent).tint(tint.prominentFill)
        } else {
            content.buttonStyle(.borderedProminent).tint(tint.prominentFill)
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

/// Every delete, remove and Move to Trash button: Liquid Glass tinted red
/// with a red label, so it reads as glass and as destructive (Nick,
/// 2 Nov 2026).
struct GlassDestructiveButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass).tint(.red).foregroundStyle(Color.red.readable)
        } else {
            content.buttonStyle(.bordered).tint(.red)
        }
    }
}

extension View {
    func glassProminent(_ tint: Color) -> some View { modifier(GlassProminentButton(tint: tint)) }
    func glass() -> some View { modifier(GlassButton()) }
    func glassDestructive() -> some View { modifier(GlassDestructiveButton()) }
}

/// A small warning triangle that explains itself on hover (tooltip) and on
/// click (popover) — replaces walls of orange text.
struct WarningBadge: View {
    let title: String
    let message: String
    /// A filled circle with a white glyph: crisp at badge size, unlike the
    /// triangle, whose "!" got lost.
    var symbol: String = "exclamationmark.circle.fill"
    var color: Color = .orange
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, color.prominentFill)
                .font(.system(size: 17, weight: .semibold))
                .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
        }
        .buttonStyle(.plain)
        .help(message)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            WarningCard(title: title, message: message, symbol: symbol, color: color).popupClose()
        }
    }
}

extension WarningBadge {
    init(_ kind: WarningKind) {
        self.init(title: kind.title, message: kind.message, symbol: kind.symbol, color: kind.color)
    }
}

/// What a warning badge opens when clicked.
struct WarningCard: View {
    let title: String
    let message: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.headline).foregroundStyle(color.readable)
            Text(message).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}

/// Every warning a row can carry, in one place, so rows and the Button lab
/// show the same thing.
struct WarningKind {
    let title: String
    let message: String
    var symbol = "exclamationmark.circle.fill"
    var color: Color = .orange

    static func majorUpgrade(_ jump: String) -> WarningKind {
        WarningKind(title: "Major version change (\(jump))",
                    message: "For paid apps a new major version is often a separate purchase rather than a free update. Check the vendor's terms before updating.")
    }

    static func restart(_ caveat: String) -> WarningKind {
        WarningKind(title: "Requires restart", message: caveat,
                    symbol: "arrow.clockwise.circle.fill", color: .yellow)
    }

    static let iosApp = WarningKind(
        title: "iPhone / iPad app",
        message: "This is an iOS app running on your Mac. mas and Homebrew can't update these. The button opens the App Store's Updates page, where you can update it.",
        symbol: "iphone.circle.fill", color: .blue)
}

/// Shared surface colours. The system window background is near-black in dark
/// mode and near-white in light; both make the glass look flat and harsh, so
/// these sit closer to mid-grey while still reading as light or dark.
enum Theme {
    /// The Glass slider's wash leans toward the app icon's backgrounds:
    /// silver in light, midnight in dark.
    static let wash = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(displayP3Red: 0x14 / 255, green: 0x1a / 255, blue: 0x2e / 255, alpha: 1)
            : NSColor(displayP3Red: 0xee / 255, green: 0xf1 / 255, blue: 0xf8 / 255, alpha: 1)
    })

    /// npm's red, a shade deeper than the system red so it stands apart
    /// from Leftover drivers' pink.
    static let npmRed = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(displayP3Red: 0.86, green: 0.24, blue: 0.22, alpha: 1)
            : NSColor(displayP3Red: 0.72, green: 0.13, blue: 0.12, alpha: 1)
    })

    /// Leftover drivers: a clear pink, well away from npm's red.
    static let leftoverPink = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(displayP3Red: 1.00, green: 0.50, blue: 0.75, alpha: 1)
            : NSColor(displayP3Red: 0.96, green: 0.40, blue: 0.68, alpha: 1)
    })

    /// Rust (cargo): copper, between Homebrew's brown and pip's orange.
    static let rustCopper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(displayP3Red: 0.89, green: 0.52, blue: 0.33, alpha: 1)
            : NSColor(displayP3Red: 0.66, green: 0.30, blue: 0.14, alpha: 1)
    })

    /// Ruby (gems): a crimson that leans to magenta, apart from npm's red
    /// and Leftover drivers' pink.
    static let rubyCrimson = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(displayP3Red: 0.93, green: 0.30, blue: 0.52, alpha: 1)
            : NSColor(displayP3Red: 0.68, green: 0.06, blue: 0.36, alpha: 1)
    })

    /// The Hidden section's colour, so no two sections share one.
    static let navy = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(displayP3Red: 0.36, green: 0.45, blue: 0.80, alpha: 1)
            : NSColor(displayP3Red: 0.17, green: 0.24, blue: 0.55, alpha: 1)
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
    /// Drop the transparent margin macOS icons carry (about a tenth on each
    /// side), so the artwork itself fills `size`.
    var trimmed = false
    @Environment(\.displayScale) private var scale

    var body: some View {
        let drawn = trimmed ? (size / 0.82).rounded() : size
        Image(nsImage: Self.rendered(points: drawn, scale: scale))
            .resizable()
            .interpolation(.high)
            .frame(width: drawn, height: drawn)
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

/// A section's container: tinted Liquid Glass in the section's colour, like
/// the icon's front card. Clear glass, a thin white edge, a soft neutral
/// shadow, and nothing glass stacked inside it (rows are plain).
/// The close button every pop-up shares (Nick, 2 Nov 2026): a small glass
/// circle in the top-right corner, which leaves the footer room for its
/// real buttons. Escape closes too.
struct PopupClose: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background {
                        if #available(macOS 26.0, *) {
                            Circle().fill(.clear).glassEffect(.regular.interactive(), in: Circle())
                        } else {
                            Circle().fill(.regularMaterial)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close")
            .padding(10)
        }
    }
}

extension View {
    func popupClose() -> some View { modifier(PopupClose()) }
}

struct SectionPanel: ViewModifier {
    let color: Color
    static let radius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        content
            .background {
                if #available(macOS 26.0, *) {
                    // Fixed tint: the Glass slider changes only the window wash.
                    Color.clear.glassEffect(.regular.tint(color.opacity(0.32)), in: shape)
                } else {
                    shape.fill(.regularMaterial)
                    shape.fill(color.opacity(0.16))
                }
            }
            .overlay(shape.strokeBorder(.white.opacity(0.28), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }
}

/// A section or package icon as a small Liquid Glass tile tinted with the
/// section colour, like macOS 27's app icons. Solid colour before macOS 26.
struct GlassIconTile: View {
    let style: SourceStyle
    var size: CGFloat = 32

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        Image(systemName: style.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            .frame(width: size, height: size)
            .background {
                if #available(macOS 26.0, *) {
                    // The colour underneath keeps the tile readable when the
                    // system makes glass clearer; the glass gives it depth.
                    shape.fill(style.color.opacity(0.78))
                        .glassEffect(.regular.tint(style.color.opacity(0.55)), in: shape)
                } else {
                    shape.fill(style.color.gradient)
                }
            }
            .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 0.6))
    }
}

// MARK: - The prism sheen (primary actions only)

/// The app icon's rainbow as a soft colour mesh: blurred blobs of the card
/// colours over a lavender base, frosted so it reads as a tint. Used for the
/// "up to date" prism (not for buttons or the password badge any more).
struct PrismSheen: View {
    enum Variant: String, CaseIterable, Identifiable {
        case warmToCool = "B: warm to cool", aurora = "D: scattered aurora"
        var id: String { rawValue }
    }
    var variant: Variant = .warmToCool
    /// False drops the frost, for small badges that carry a white glyph.
    var frosted = true
    @Environment(\.colorScheme) private var scheme

    private struct Blob { let color: Color; let x: CGFloat; let y: CGFloat; let size: CGFloat }
    private static func p3(_ hex: UInt32) -> Color {
        Color(.displayP3, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
              blue: Double(hex & 0xff) / 255)
    }
    static let red = p3(0xff453a), orange = p3(0xff9f0a), yellow = p3(0xffd60a)
    static let green = p3(0x30d158), blue = p3(0x0a84ff), violet = p3(0xbf5af2)
    static let lavender = p3(0xc9b8f0), midnight = p3(0x141a2e)

    private var blobs: [Blob] {
        switch variant {
        case .warmToCool: [
            .init(color: Self.red, x: 0.00, y: 0.00, size: 1.6), .init(color: Self.orange, x: 0.22, y: 0.90, size: 1.4),
            .init(color: Self.yellow, x: 0.38, y: 0.10, size: 1.3), .init(color: Self.green, x: 0.62, y: 0.90, size: 1.3),
            .init(color: Self.blue, x: 0.80, y: 0.15, size: 1.5), .init(color: Self.violet, x: 1.00, y: 1.00, size: 1.7)]
        case .aurora: [
            .init(color: Self.blue, x: 0.08, y: 0.20, size: 1.4), .init(color: Self.yellow, x: 0.30, y: 0.85, size: 1.3),
            .init(color: Self.red, x: 0.50, y: 0.10, size: 1.2), .init(color: Self.violet, x: 0.68, y: 0.90, size: 1.4),
            .init(color: Self.green, x: 0.85, y: 0.15, size: 1.3), .init(color: Self.orange, x: 0.98, y: 0.80, size: 1.3)]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Self.lavender
                ForEach(blobs.indices, id: \.self) { i in
                    let blob = blobs[i]
                    Circle().fill(blob.color)
                        .frame(width: blob.size * h, height: blob.size * h)
                        .position(x: blob.x * w, y: blob.y * h)
                }
            }
            .blur(radius: 0.45 * h)
            // The frost: 62% white in light, 62% midnight in dark.
            .overlay((scheme == .dark ? Self.midnight : .white).opacity(frosted ? 0.62 : 0))
        }
    }
}

/// The primary-action button (Nick, 29 Oct): a real Liquid Glass button,
/// with the system's own hover and press, and the icon's colours as a faint
/// blur behind the glass. Used sparingly: Update All, the password sheet's
/// Authorize, and Adopt all safe ones.
struct PrismProminent: ViewModifier {
    /// How strong the colour reads through the glass.
    static let strength = 0.22

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .background { PrismBlur().allowsHitTesting(false) }
        } else {
            content
                .buttonStyle(.bordered)
                .background { PrismBlur().allowsHitTesting(false) }
        }
    }
}

/// The icon's card colours, left to right, blurred into a soft wash.
struct PrismBlur: View {
    static let spectrum: [Color] = [PrismSheen.red, PrismSheen.orange, PrismSheen.yellow,
                                    PrismSheen.green, PrismSheen.blue, PrismSheen.violet]
    var strength = PrismProminent.strength

    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: Self.spectrum, startPoint: .leading, endPoint: .trailing))
            .blur(radius: 6)
            .opacity(strength)
            .padding(2)
    }
}

extension View {
    /// Update All, the password sheet's Authorize, and Adopt all safe ones.
    func prismProminent() -> some View { modifier(PrismProminent()) }
}

// MARK: - The password badge

/// The key on Liquid Glass, with the icon's colours blurred behind it, as on
/// Update All. `realGlass` false draws a glass look instead, for NSImage
/// icons (the askpass alert), where the system glass can't render.
struct GlassKeyBadge: View {
    var size: CGFloat
    var realGlass = true
    /// The key for password prompts; an exclamation mark for confirmations.
    var symbol = "key.fill"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let disc = size * 0.8
        ZStack {
            Circle()
                .fill(AngularGradient(colors: PrismBlur.spectrum + [PrismBlur.spectrum[0]], center: .center))
                .frame(width: disc * 0.9, height: disc * 0.9)
                .blur(radius: size * 0.08)
                .opacity(scheme == .dark ? 0.75 : 0.5)
                .saturation(scheme == .dark ? 1.05 : 1)
            if realGlass, #available(macOS 26.0, *) {
                Circle().fill(.clear)
                    .frame(width: disc, height: disc)
                    .glassEffect(.regular, in: Circle())
            } else {
                drawnGlass.frame(width: disc, height: disc)
            }
            Image(systemName: symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: size, height: size)
    }

    /// Clear glass by hand: a frosted fill, a bright top edge fading down,
    /// a soft top highlight and a neutral shadow.
    private var drawnGlass: some View {
        let dark = scheme == .dark
        return Circle()
            .fill((dark ? PrismSheen.midnight : .white).opacity(dark ? 0.22 : 0.45))
            .overlay(
                Ellipse()
                    .fill(LinearGradient(colors: [.white.opacity(dark ? 0.25 : 0.6), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .scaleEffect(x: 0.8, y: 0.5, anchor: .top)
                    .padding(size * 0.04)
            )
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(dark ? 0.4 : 0.9), .white.opacity(dark ? 0.06 : 0.15)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .shadow(color: .black.opacity(dark ? 0.4 : 0.15), radius: size * 0.04, y: size * 0.02)
    }
}

/// The password prompts' icon (Nick, 30 Oct 2026): the app icon with the
/// glass key over its lower right corner, the way macOS badges an app that
/// asks for a password. In dark mode it uses the icon's midnight version.
struct AppIconKeyBadge: View {
    var size: CGFloat
    /// False for the askpass alert, which can only show a flat image.
    var realGlass = true
    /// "exclamationmark" on confirmation pop-ups (Nick, 30 Oct 2026).
    var symbol = "key.fill"
    @Environment(\.colorScheme) private var scheme

    /// The flat icon apps are handed is the light one only, so the dark
    /// version is bundled (an export of AppIcon.icon's dark appearance).
    static let darkIcon: NSImage? = Bundle.main.image(forResource: "AppIconDark")

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if scheme == .dark, let dark = Self.darkIcon {
                // The export has no transparent margin: draw it at the system
                // icon's artwork size (about 82%) so both look the same size.
                Image(nsImage: dark)
                    .resizable().interpolation(.high)
                    .frame(width: size * 0.82, height: size * 0.82)
                    .frame(width: size, height: size)
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high)
                    .frame(width: size, height: size)
            }
            GlassKeyBadge(size: size * 0.5, realGlass: realGlass, symbol: symbol)
                .offset(x: size * 0.06, y: size * 0.06)
        }
        .frame(width: size, height: size)
    }
}

extension Color {
    /// This hue as text: deepened in light mode and lightened in dark mode,
    /// so it reads on its own section's tint either way.
    var readable: Color { adjusted(light: 0.4, dark: -0.4, brightOnly: false) }

    /// This hue as a button fill under white text: bright hues (yellow, mint,
    /// teal, green, orange) are deepened in both modes; dark hues stay.
    var prominentFill: Color { adjusted(light: 0.3, dark: 0.2, brightOnly: true) }

    private func adjusted(light: CGFloat, dark: CGFloat, brightOnly: Bool) -> Color {
        let base = NSColor(self)
        return Color(nsColor: NSColor(name: nil) { appearance in
            var resolved = base
            appearance.performAsCurrentDrawingAppearance {
                resolved = base.usingColorSpace(.sRGB) ?? base
            }
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            var amount = isDark ? dark : light
            if brightOnly {
                let luminance = 0.2126 * resolved.redComponent + 0.7152 * resolved.greenComponent
                    + 0.0722 * resolved.blueComponent
                amount = luminance < 0.45 ? 0 : max(amount, luminance - 0.4)
            }
            // Positive deepens toward black, negative lightens toward white.
            if amount > 0 { return resolved.blended(withFraction: amount, of: .black) ?? resolved }
            if amount < 0 { return resolved.blended(withFraction: -amount, of: .white) ?? resolved }
            return resolved
        })
    }
}

/// A segmented control whose selection is a Liquid Glass bubble that slides
/// to the chosen segment. Click a segment, or drag the bubble with the
/// pointer or a finger; it snaps to the nearest one on release (Nick,
/// 2 Nov 2026). The bubble moves at once and `selection` follows a beat
/// later, so a page swapping its contents doesn't hold up the slide.
struct GlassSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    /// Labels are SF Symbol names (Cards / List), with these tooltips.
    var symbols = false
    var tips: [String] = []
    /// The segment the bubble shows until `selection` catches up.
    @State private var chosen: Int?
    @State private var frames: [Int: CGRect] = [:]
    @State private var dragX: CGFloat?
    private static var space: String { "glassSegmented" }

    private var selectedIndex: Int { options.firstIndex { $0.value == selection } ?? 0 }
    private var index: Int { dragX.map(nearest) ?? chosen ?? selectedIndex }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                Group {
                    if symbols { Image(systemName: options[i].label) } else { Text(options[i].label) }
                }
                .font(.callout.weight(i == index ? .semibold : .regular))
                .foregroundStyle(i == index ? .primary : .secondary)
                .padding(.horizontal, symbols ? 12 : 14).padding(.vertical, 5)
                .contentShape(Capsule())
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[i] = $0 }
                .help(tip(i))
                .accessibilityElement()
                .accessibilityLabel(tip(i))
                .accessibilityAddTraits(i == index ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { choose(i) }
            }
        }
        .background(alignment: .topLeading) { bubble }
        .coordinateSpace(name: Self.space)
        .contentShape(Capsule())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { dragX = $0.location.x }
            .onEnded { value in
                let i = nearest(value.location.x)
                dragX = nil
                choose(i)
            })
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .fixedSize()
    }

    /// Follows the pointer while dragging, clamped to the track; otherwise
    /// sits on its segment.
    @ViewBuilder
    private var bubble: some View {
        if let frame = frames[index] {
            let end = frames.values.map(\.maxX).max() ?? frame.maxX
            let x = dragX.map { min(max($0 - frame.width / 2, 0), end - frame.width) } ?? frame.minX
            SelectionBubble()
                .frame(width: frame.width, height: frame.height)
                .offset(x: x, y: frame.minY)
                .animation(dragX == nil ? .snappy(duration: 0.22) : .interactiveSpring(duration: 0.1), value: x)
                .animation(.snappy(duration: 0.22), value: frame.width)
        }
    }

    private func tip(_ i: Int) -> String { i < tips.count ? tips[i] : options[i].label }

    private func nearest(_ x: CGFloat) -> Int {
        frames.min { abs($0.value.midX - x) < abs($1.value.midX - x) }?.key ?? selectedIndex
    }

    private func choose(_ i: Int) {
        chosen = i
        let value = options[i].value
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            selection = value
            chosen = nil
        }
    }
}

private struct SelectionBubble: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.regular.interactive(), in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        } else {
            Capsule().fill(.background).shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
    }
}

// MARK: - Stepper

/// A number with − and + on one Liquid Glass capsule, like the search
/// field, in place of the system stepper (Nick, 2 Nov 2026). Each end greys
/// out at its limit.
struct GlassStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 2) {
            step("minus", by: -1, enabled: value > range.lowerBound, tip: "Fewer")
            Text("\(value)").font(.callout.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 22)
            step("plus", by: 1, enabled: value < range.upperBound, tip: "More")
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background { GlassCapsule() }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func step(_ symbol: String, by delta: Int, enabled: Bool, tip: String) -> some View {
        Button { value = min(max(value + delta, range.lowerBound), range.upperBound) } label: {
            Image(systemName: symbol).font(.caption.weight(.semibold))
                .frame(width: 22, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .primary : .tertiary)
        .disabled(!enabled)
        .help(tip)
    }
}

// MARK: - Search field

/// A search box on a Liquid Glass capsule: magnifying glass, plain text
/// field, and a clear button once something is typed. Material on macOS 15.
struct GlassSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Clear")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background { GlassCapsule() }
    }
}

/// The search field's glass capsule, shared with the Sort button so both
/// look the same closed. Material on macOS 15.
struct GlassCapsule: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule().fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        }
    }
}

// MARK: - Pinned page header

extension View {
    /// Pins `header` at one edge of a page's scroll view the way macOS 26's
    /// own windows do (System Settings' toolbar): the content scrolls under
    /// it, and the system draws the Liquid Glass scroll edge effect there.
    /// Apple's recommended route is `safeAreaBar`, which extends the scroll
    /// view's edge effect; the style is set explicitly because `automatic`
    /// has resolved to `hard` on some SDKs. macOS 15 gets a material bar.
    @ViewBuilder
    func pinnedHeader<Header: View>(edge: VerticalEdge = .top, @ViewBuilder _ header: () -> Header) -> some View {
        let bar = header()
        if #available(macOS 26.0, *) {
            self.safeAreaBar(edge: edge, spacing: 0) { bar }
                .scrollEdgeEffectStyle(.soft, for: edge == .top ? .top : .bottom)
        } else {
            self.safeAreaInset(edge: edge, spacing: 0) { bar.background(.bar) }
        }
    }
}
