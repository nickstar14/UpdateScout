import AppKit

/// The words of the password prompts, so both prompts say what the password is
/// for and what set it off (Nick, 25 Nov 2026). Pure, so tests can read them.
enum PasswordText {
    enum Cause { case you, automatic, repair }

    /// "Signal", "Signal and Spotify", "Signal, Spotify and VLC",
    /// "Signal, Spotify, VLC and 2 more".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return "your apps"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        case 3: return "\(names[0]), \(names[1]) and \(names[2])"
        default: return "\(names[0]), \(names[1]), \(names[2]) and \(names.count - 3) more"
        }
    }

    /// What follows "needs your password": "to update Signal, which you started".
    static func purpose(apps: [String], cause: Cause) -> String {
        switch cause {
        case .repair:
            return "to repair and update \(list(apps))"
        case .automatic:
            return "to update your apps automatically: \(list(apps))"
        case .you:
            return apps.count == 1 ? "to update \(list(apps)), which you started"
                                   : "to update \(apps.count) apps you started: \(list(apps))"
        }
    }

    static func headline(apps: [String], cause: Cause) -> String {
        "\(AppIdentity.name) needs your password \(purpose(apps: apps, cause: cause))."
    }

    static func detail(count: Int) -> String {
        "It's used for this batch only and isn't saved. Cancel leaves \(count == 1 ? "it" : "them") for later."
    }
}

/// One password prompt for the whole app: a native alert, the app icon with
/// the key badge, a password field with the eye button, OK and Cancel. The
/// window's batch prompt and the askpass panel (AskpassDialog) both build it
/// here, so they look the same.
@MainActor
enum PasswordPrompt {
    final class Field {
        let view: NSView
        let secure: NSSecureTextField
        private let toggler: AskpassDialog.EyeToggler

        init() {
            view = NSView(frame: NSRect(x: 0, y: 0, width: 238, height: 24))
            secure = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 208, height: 24))
            secure.placeholderString = "Password"
            let plain = NSTextField(frame: secure.frame)
            plain.placeholderString = "Password"
            plain.isHidden = true
            let eye = NSButton(frame: NSRect(x: 212, y: 0, width: 26, height: 24))
            eye.bezelStyle = .accessoryBarAction
            eye.isBordered = false
            eye.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Show password")
            toggler = AskpassDialog.EyeToggler(secure: secure, plain: plain, button: eye)
            eye.target = toggler
            eye.action = #selector(AskpassDialog.EyeToggler.toggle)
            view.addSubview(secure); view.addSubview(plain); view.addSubview(eye)
        }

        var value: String { toggler.currentValue }
    }

    static func makeAlert(headline: String, detail: String) -> (alert: NSAlert, field: Field) {
        let alert = NSAlert()
        alert.messageText = headline
        alert.informativeText = detail
        alert.icon = AskpassDialog.circularKeyIcon()
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = Field()
        alert.accessoryView = field.view
        alert.window.initialFirstResponder = field.secure
        return (alert, field)
    }

    /// Asks until `verify` accepts the password or the user cancels. Shown as
    /// a sheet on `window` when there is one, else as its own panel.
    static func ask(window: NSWindow?, headline: String, detail: String,
                    verify: @escaping (String) async -> Bool) async -> Bool {
        var wrong = false
        while true {
            let (alert, field) = makeAlert(headline: headline,
                                           detail: wrong ? "That password didn't work. Try again." : detail)
            NSApp.activate(ignoringOtherApps: true)
            // The caret has to land in the field when the alert opens.
            DispatchQueue.main.async { alert.window.makeFirstResponder(field.secure) }
            let response: NSApplication.ModalResponse
            if let window, window.isVisible {
                response = await withCheckedContinuation { continuation in
                    alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
                }
            } else {
                response = alert.runModal()
            }
            guard response == .alertFirstButtonReturn else { return false }
            let password = field.value
            if password.isEmpty { continue }
            if await verify(password) { return true }
            wrong = true
        }
    }
}
