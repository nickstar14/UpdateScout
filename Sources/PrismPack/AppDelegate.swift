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
