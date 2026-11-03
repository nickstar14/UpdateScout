import AppKit
import UserNotifications

/// Owns the notification-center delegate so clicking a notification opens the
/// status window. Two paths land here: the running menu bar app (notification
/// posted by "Check Now"), and a cold launch — macOS starts the app when the
/// user clicks a notification the background agent posted, and delivers the
/// response as soon as a delegate exists. That's why this is wired in
/// applicationDidFinishLaunching rather than lazily.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        // Relaunching from the renamed bundle: the new copy does the rest.
        if Migration.runAtLaunch() { return }
        StatusItemController.shared.install()
        SelfUpdater.start()
        // The rename pop-up lives in the main window, so open it once; and
        // after an update relaunch, come back to the window.
        let defaults = UserDefaults.standard
        let reopen = defaults.bool(forKey: SelfUpdater.reopenWindowKey)
        defaults.removeObject(forKey: SelfUpdater.reopenWindowKey)
        if reopen || defaults.bool(forKey: Migration.noticeKey) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { UpdatesWindow.shared.show() }
        }
    }

    /// Set by quits that must not ask: the menu bar's Quit, the rename
    /// migration, Full Disk Access's relaunch.
    nonisolated(unsafe) static var skipQuitPrompt = false

    /// Quit without the "Quit PrismPack?" prompt.
    static func quitWithoutAsking() {
        skipQuitPrompt = true
        NSApp.terminate(nil)
    }

    /// ⌘Q and the Dock's Quit ask first (Nick, step 11). Close Window is the
    /// default, so Return keeps the menu bar prism and notifications.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.skipQuitPrompt || !Prefs.askBeforeQuit || Self.isSystemQuit { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit \(AppIdentity.name)?"
        alert.informativeText = Self.quitPromptText(backgroundOn: LaunchAgent.isInstalled)
        alert.icon = NSApp.applicationIconImage
        let close = alert.addButton(withTitle: "Close Window (\u{2318}W)")
        close.keyEquivalent = "\r"
        alert.addButton(withTitle: "Quit").keyEquivalent = ""
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        NSApp.activate(ignoringOtherApps: true)
        let reply = alert.runModal()
        if alert.suppressionButton?.state == .on { Prefs.askBeforeQuit = false }
        if reply == .alertSecondButtonReturn { return .terminateNow }
        NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.performClose(nil)
        return .terminateCancel
    }

    static func quitPromptText(backgroundOn: Bool) -> String {
        let first = backgroundOn
            ? "Checks and automatic updates keep running in the background either way."
            : "Checks and automatic updates stop until you open \(AppIdentity.name) again."
        return first + " Closing the window keeps the menu bar prism and update notifications in \(AppIdentity.name)."
    }

    /// Log out, restart and shut down also ask apps to quit; never hold those up.
    private static var isSystemQuit: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) else { return false }
        return [kAELogOut, kAEReallyLogOut, kAERestart, kAEShowRestartDialog, kAEShutDown, kAEShowShutdownDialog]
            .contains(reason.enumCodeValue)
    }

    /// Opening the app again (Finder, Spotlight, `open`) while it's running
    /// shows the window, as other Mac apps do.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        UpdatesWindow.shared.show()
        return false
    }

    /// User clicked (or actioned) a notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Clicked means seen: take it out of Notification Center.
        center.removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier])
        DispatchQueue.main.async {
            UpdatesWindow.shared.show()
        }
        completionHandler()
    }

    /// Still show banners while the app is frontmost (default would hide them).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
