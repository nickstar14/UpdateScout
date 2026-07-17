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

    /// A key glyph inside a tinted circle, like macOS's own auth prompts.
    private static func circularKeyIcon() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let config = NSImage.SymbolConfiguration(pointSize: 30, weight: .medium)
                .applying(.init(hierarchicalColor: .controlAccentColor))
            if let symbol = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Key")?
                .withSymbolConfiguration(config) {
                let s = symbol.size
                symbol.draw(in: NSRect(x: (rect.width - s.width) / 2,
                                       y: (rect.height - s.height) / 2,
                                       width: s.width, height: s.height))
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
