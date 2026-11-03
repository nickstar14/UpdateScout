import AppKit
import Combine

/// The menu bar glyph: a prism (a triangle with an off-centre ridge, so it
/// reads as 3D and not as a warning sign), drawn as a template image so the
/// system tints it for light, dark and tinted menu bars.
///
/// While a check runs the prism pulses by stepping its alpha between 1.0 and
/// about 0.35. Status item images can't be animated, so the pulse is a set of
/// pre-drawn frames that the controller steps through on a timer.
enum MenuBarIcon {
    static let frameCount = 20

    @MainActor private static var frames: [NSImage] = (0..<frameCount).map { frame in
        let phase = Double(frame) / Double(frameCount) * 2 * .pi
        return prism(alpha: 0.35 + 0.65 * (0.5 + 0.5 * cos(phase)))
    }
    @MainActor static let still = prism(alpha: 1)

    @MainActor static func pulse(frame: Int) -> NSImage { frames[frame % frameCount] }

    private static func prism(alpha: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let apex = NSPoint(x: 9, y: 2.2)
            let left = NSPoint(x: 1.6, y: 15.4), right = NSPoint(x: 16.4, y: 15.4)
            let ridge = NSPoint(x: 10.6, y: 12.3)
            let ink = NSColor.black.withAlphaComponent(alpha)

            // The shaded face, right of the ridge, at partial alpha.
            let face = NSBezierPath()
            face.move(to: apex); face.line(to: ridge); face.line(to: right); face.close()
            ink.withAlphaComponent(alpha * 0.38).setFill()
            face.fill()

            let outline = NSBezierPath()
            outline.move(to: apex); outline.line(to: right); outline.line(to: left); outline.close()
            outline.lineWidth = 1.5
            outline.lineJoinStyle = .round
            ink.setStroke()
            outline.stroke()

            let edges = NSBezierPath()
            edges.move(to: apex); edges.line(to: ridge)
            edges.move(to: left); edges.line(to: ridge); edges.line(to: right)
            edges.lineWidth = 1.1
            edges.lineCapStyle = .round
            edges.lineJoinStyle = .round
            edges.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The one status item. Left-click opens the window (or brings it to the
/// front); right-click or Control-click shows a plain native menu. A
/// MenuBarExtra can't tell the two clicks apart, hence an NSStatusItem.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()
    private var item: NSStatusItem?
    private var observation: AnyCancellable?

    func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A stable name, so menu bar managers (Thaw, Ice, Bartender) and
        // macOS keep the position the user chose.
        item.autosaveName = "PrismPackStatusItem"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        self.item = item
        let controller = UpdateController.shared
        observation = controller.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the change lands.
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        guard let button = item?.button else { return }
        let controller = UpdateController.shared
        let count = controller.badgeCount
        button.image = controller.isPulsing ? MenuBarIcon.pulse(frame: controller.spinFrame) : MenuBarIcon.still
        button.title = count > 0 ? "\(count)" : ""
        button.setAccessibilityLabel(controller.needsAttention ? "Waiting for your password"
                                     : controller.isSpinning ? "Checking for updates"
                                     : count > 0 ? "\(count) updates available" : "Up to date")
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            UpdatesWindow.shared.show()
        }
    }

    private func showMenu() {
        let name = AppIdentity.name
        let menu = NSMenu()
        menu.addItem(withTitle: "Open \(name)", action: #selector(openWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Check Now", action: #selector(checkNow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(name)", action: #selector(quit), keyEquivalent: "q").target = self
        item?.menu = menu
        item?.button?.performClick(nil)
        // Detach again, or the next left-click would open the menu too.
        item?.menu = nil
    }

    @objc private func openWindow() { UpdatesWindow.shared.show() }
    @objc private func checkNow() { UpdateController.shared.checkNow() }
    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func quit() { AppDelegate.quitWithoutAsking() }
}
