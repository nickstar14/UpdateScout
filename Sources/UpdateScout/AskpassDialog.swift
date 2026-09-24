import AppKit

extension Notification.Name {
    /// Posted by the --askpass process when its dialog closes.
    static let updateScoutRefront = Notification.Name("com.nickszun.updatescout.refront")
}

/// `UpdateScout --askpass`: sudo runs this (via askpass.sh) when an install
/// needs elevation and there is no terminal. Shows a native-styled auth
/// dialog and prints the entry to stdout for sudo. Nothing is stored.
enum AskpassDialog {
    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let alert = NSAlert()
        alert.messageText = "UpdateScout is trying to install an update."
        alert.informativeText = "Enter your password to allow this."
        alert.icon = circularKeyIcon()
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        // Accessory: secure field + overlaid plain field, with an eye toggle.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 238, height: 24))
        let secureField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 208, height: 24))
        secureField.placeholderString = "Password"
        let plainField = NSTextField(frame: secureField.frame)
        plainField.placeholderString = "Password"
        plainField.isHidden = true
        let eyeButton = NSButton(frame: NSRect(x: 212, y: 0, width: 26, height: 24))
        eyeButton.bezelStyle = .accessoryBarAction
        eyeButton.isBordered = false
        eyeButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Show password")

        let toggler = EyeToggler(secure: secureField, plain: plainField, button: eyeButton)
        eyeButton.target = toggler
        eyeButton.action = #selector(EyeToggler.toggle)

        container.addSubview(secureField)
        container.addSubview(plainField)
        container.addSubview(eyeButton)
        alert.accessoryView = container
        // Focus the field immediately so the cursor is blinking on arrival.
        alert.window.initialFirstResponder = secureField

        app.activate(ignoringOtherApps: true)
        // initialFirstResponder alone doesn't always land (the alert can hand
        // focus to its default button), leaving no blinking caret. This block
        // runs once runModal's run loop starts, so it claims focus reliably.
        DispatchQueue.main.async {
            alert.window.makeFirstResponder(secureField)
            secureField.currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
        }
        let response = alert.runModal()
        withExtendedLifetime(toggler) {}

        // Tell the main app instance to bring its window back to the front now
        // that the auth dialog is gone (the install keeps running behind it).
        DistributedNotificationCenter.default().postNotificationName(
            .updateScoutRefront, object: nil, userInfo: nil, deliverImmediately: true)

        if response == .alertFirstButtonReturn {
            let password = toggler.currentValue
            FileHandle.standardOutput.write(Data((password + "\n").utf8))
            exit(0)
        }
        exit(1) // sudo treats a non-zero askpass exit as "cancelled"
    }

    /// A key badge in the same style as the main window's "N updates
    /// available" badge — a faint halo ring around a solid disc — coloured with
    /// the app icon's blue-to-violet gradient so the prompt is recognisably
    /// UpdateScout's. The white glyph keeps contrast on any background.
    private static func circularKeyIcon() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            // The app icon's blue-to-violet, weighted toward violet: indigo by
            // the middle so the violet reads across the lower half of the disc.
            guard let gradient = NSGradient(
                colors: [
                    NSColor(srgbRed: 0.31, green: 0.55, blue: 1.00, alpha: 1),   // #4F8DFF blue
                    NSColor(srgbRed: 0.36, green: 0.36, blue: 0.90, alpha: 1),   // #5C5CE6 indigo
                    NSColor(srgbRed: 0.48, green: 0.21, blue: 0.82, alpha: 1),   // #7A35D1 violet
                ],
                atLocations: [0.0, 0.42, 1.0],
                colorSpace: .sRGB) else { return false }

            // Faint outer halo — the gradient at low opacity, like the badge's
            // `tint.opacity(0.15)` backing circle.
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.cgContext.setAlpha(0.22)
            gradient.draw(in: NSBezierPath(ovalIn: rect), angle: -90)
            NSGraphicsContext.restoreGraphicsState()

            // Solid inner disc.
            let disc = rect.insetBy(dx: 9, dy: 9)
            gradient.draw(in: NSBezierPath(ovalIn: disc), angle: -90)

            // White key.
            let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let key = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Password")?
                .withSymbolConfiguration(config) {
                let size = key.size
                key.draw(in: NSRect(x: disc.midX - size.width / 2, y: disc.midY - size.height / 2,
                                    width: size.width, height: size.height))
            }
            return true
        }
    }

    /// Swaps between the secure and plain fields, keeping their text in sync.
    final class EyeToggler: NSObject {
        private let secure: NSSecureTextField
        private let plain: NSTextField
        private let button: NSButton
        private var revealed = false

        init(secure: NSSecureTextField, plain: NSTextField, button: NSButton) {
            self.secure = secure; self.plain = plain; self.button = button
        }

        var currentValue: String { revealed ? plain.stringValue : secure.stringValue }

        @objc func toggle() {
            revealed.toggle()
            if revealed {
                plain.stringValue = secure.stringValue
                plain.isHidden = false
                secure.isHidden = true
                button.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide password")
                plain.window?.makeFirstResponder(plain)
                plain.currentEditor()?.moveToEndOfLine(nil)
            } else {
                secure.stringValue = plain.stringValue
                secure.isHidden = false
                plain.isHidden = true
                button.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Show password")
                secure.window?.makeFirstResponder(secure)
                secure.currentEditor()?.moveToEndOfLine(nil)
            }
        }
    }
}
