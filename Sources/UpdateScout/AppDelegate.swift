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
    }

    /// User clicked (or actioned) a notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
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
