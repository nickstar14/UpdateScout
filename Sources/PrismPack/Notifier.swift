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

    /// At most one a week, never one per app (Adoption.merge decides when).
    static func notifyAdoptionDigest(_ candidates: [AdoptionCandidate]) {
        guard !candidates.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = candidates.count == 1
            ? "\(candidates[0].name) could be updated by Homebrew"
            : "\(candidates.count) apps could be updated by Homebrew"
        content.body = "Nothing updates them today. Nothing changes unless you say so."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
