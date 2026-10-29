import SwiftUI
import AppKit

/// The menu bar icon, one of three states:
/// - checking: a spoked spinner, like the one beside "Checking…" in the window,
/// - updates available: the circular arrows plus the count,
/// - up to date: a checkmark.
///
/// A MenuBarExtra label is flattened into the status item's image, so view
/// modifiers like rotation and SwiftUI animations are dropped. The spinner is
/// therefore drawn as separate template images, one per frame, and the
/// controller steps through them on a timer.
enum MenuBarIcon {
    static let spokes = 12

    /// Frames are cached: the timer asks for one twelve times a second.
    @MainActor private static var frames: [NSImage] = (0..<spokes).map(spinnerFrame)

    @MainActor static func spinner(frame: Int) -> NSImage {
        frames[frame % spokes]
    }

    /// Spoke `frame` is the darkest; the ones behind it fade out, so the
    /// bright spoke appears to travel clockwise as `frame` increases.
    private static func spinnerFrame(_ frame: Int) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            for i in 0..<spokes {
                // 0 is twelve o'clock, increasing clockwise.
                let angle = .pi / 2 - Double(i) * 2 * .pi / Double(spokes)
                let behind = (frame - i + spokes) % spokes
                let alpha = max(0.18, 1 - Double(behind) / Double(spokes - 2))
                let path = NSBezierPath()
                path.lineWidth = 1.7
                path.lineCapStyle = .round
                path.move(to: NSPoint(x: center.x + 3.6 * cos(angle), y: center.y + 3.6 * sin(angle)))
                path.line(to: NSPoint(x: center.x + 7.4 * cos(angle), y: center.y + 7.4 * sin(angle)))
                NSColor.black.withAlphaComponent(alpha).setStroke()
                path.stroke()
            }
            return true
        }
        // Template, so the menu bar tints it for light, dark and tinted bars.
        image.isTemplate = true
        image.accessibilityDescription = "Checking for updates"
        return image
    }
}

/// The MenuBarExtra label. One status item for every state, so menu bar
/// managers (Thaw, Ice, Bartender) keep it where the user placed it.
struct MenuBarLabel: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        if controller.isSpinning {
            Image(nsImage: MenuBarIcon.spinner(frame: controller.spinFrame))
        } else if controller.badgeCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .accessibilityLabel("Updates available")
                Text("\(controller.badgeCount)")
            }
        } else {
            Image(systemName: "checkmark.circle")
                .accessibilityLabel("Up to date")
        }
    }
}
