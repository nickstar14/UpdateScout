import SwiftUI
import AppKit

extension Notification.Name {
    /// Posted by the --askpass process when its dialog closes.
    static let prismPackRefront = Notification.Name("com.nickszun.prismpack.refront")
    /// A newer build started: the older copy quits (userInfo "pid" is the newer one).
    static let prismPackQuitForNewer = Notification.Name("com.nickszun.prismpack.quitForNewer")
}

/// `PrismPack --askpass`: sudo runs this (via askpass.sh) when an install
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

        // What the password is for: a sentence from runPrivileged, else the
        // cause the app wrote down when it started the install, else a
        // general line.
        let env = ProcessInfo.processInfo.environment
        let written = (try? String(contentsOf: Askpass.reasonFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let headline = env[Askpass.reasonKey]
            ?? written.flatMap { $0.isEmpty ? nil : "\(AppIdentity.name) needs your password \($0)." }
            ?? "\(AppIdentity.name) needs your password to install an update."
        let (alert, field) = PasswordPrompt.makeAlert(headline: headline,
                                                      detail: "It's used for this step only and isn't saved.")
        let secureField = field.secure

        app.activate(ignoringOtherApps: true)
        // initialFirstResponder alone doesn't always land (the alert can hand
        // focus to its default button), leaving no blinking caret. This block
        // runs once runModal's run loop starts, so it claims focus reliably.
        DispatchQueue.main.async {
            alert.window.makeFirstResponder(secureField)
            secureField.currentEditor()?.selectedRange = NSRange(location: 0, length: 0)
        }
        let response = alert.runModal()

        // Tell the main app instance to bring its window back to the front now
        // that the auth dialog is gone (the install keeps running behind it).
        DistributedNotificationCenter.default().postNotificationName(
            .prismPackRefront, object: nil, userInfo: nil, deliverImmediately: true)

        if response == .alertFirstButtonReturn {
            let password = field.value
            FileHandle.standardOutput.write(Data((password + "\n").utf8))
            exit(0)
        }
        exit(1) // sudo treats a non-zero askpass exit as "cancelled"
    }

    /// The password prompt's icon: the app icon with the glass key badge
    /// (AppIconKeyBadge), drawn for the current light or dark look.
    @MainActor static func circularKeyIcon() -> NSImage { badgeIcon(symbol: "key.fill") }

    /// The same icon with another symbol in the bubble: "exclamationmark"
    /// for confirmation pop-ups.
    @MainActor static func badgeIcon(symbol: String) -> NSImage {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let renderer = ImageRenderer(content: AppIconKeyBadge(size: 64, realGlass: false, symbol: symbol)
            .environment(\.colorScheme, dark ? .dark : .light))
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
