import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted by the --askpass process when its dialog closes.
    static let updateScoutRefront = Notification.Name("com.nickszun.updatescout.refront")
}

/// `UpdateScout --askpass`: sudo runs this (via askpass.sh) when an install
/// needs elevation and there is no terminal. Shows a native-styled auth
/// dialog and prints the entry to stdout for sudo. Nothing is stored.
enum AskpassDialog {
    @MainActor static func run() -> Never {
        // During a batch the app already has the password: hand it to sudo
        // without showing anything.
        if let password = PasswordBroker.fetchPassword() {
            FileHandle.standardOutput.write(Data((password + "\n").utf8))
            exit(0)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let alert = NSAlert()
        // runPrivileged passes what the password is for; anything else that
        // reaches sudo (brew installing a pkg cask) is an update install.
        alert.messageText = ProcessInfo.processInfo.environment[Askpass.reasonKey]
            ?? "UpdateScout is trying to install an update."
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

    /// The password prompt's badge: the app's prism sheen in a disc, with a
    /// faint halo and the white key glyph.
    @MainActor static func circularKeyIcon() -> NSImage {
        let disc = SwiftUI.ZStack {
            SwiftUI.Circle().fill(PrismSheen.lavender.opacity(0.3))
            PrismSheen(frosted: false)
                .clipShape(SwiftUI.Circle())
                .padding(9)
            SwiftUI.Image(systemName: "key.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        }
        .frame(width: 64, height: 64)
        let renderer = ImageRenderer(content: disc)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 64, height: 64))
        image.size = NSSize(width: 64, height: 64)
        return image
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
