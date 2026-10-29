import Foundation
import UserNotifications

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// Post one notification summarizing newly found updates.
    static func notifyNewUpdates(_ newItems: [UpdateItem]) {
        guard !newItems.isEmpty else { return }
        let content = UNMutableNotificationContent()
        if newItems.count == 1, let item = newItems.first {
            content.title = "Update available: \(item.name)"
            content.body = "\(item.installedVersion) → \(item.latestVersion)"
        } else {
            content.title = "\(newItems.count) new updates available"
            content.body = newItems.prefix(5).map(\.name).joined(separator: ", ")
                + (newItems.count > 5 ? ", …" : "")
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
