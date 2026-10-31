import Foundation
import UserNotifications

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    /// Fixed identifiers, so a new notification replaces the last one in
    /// Notification Center instead of piling up.
    static let updatesID = "updates"
    static let adoptionID = "adoption"

    /// One notification for updates. A check that finds new ones replaces the
    /// last; once nothing is waiting, it's taken down. Hidden items never
    /// notify. Older builds posted under random ids, so those go too.
    static func notifyNewUpdates(_ fresh: [UpdateItem], waiting: [UpdateItem]) {
        let waitingIDs = Set(waiting.map(\.id))
        let newItems = fresh.filter { waitingIDs.contains($0.id) }
        guard waiting.isEmpty || !newItems.isEmpty else { return }
        // Counts only (Nick, 30 Oct 2026): "2 new updates", "12 waiting to be updated".
        let content = UNMutableNotificationContent()
        content.title = newItems.count == 1 ? "1 new update" : "\(newItems.count) new updates"
        content.body = "\(waiting.count) waiting to be updated"
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            center.removeDeliveredNotifications(withIdentifiers:
                delivered.map(\.request.identifier).filter { $0 != adoptionID })
            guard !newItems.isEmpty else { return }
            center.add(UNNotificationRequest(identifier: updatesID, content: content, trigger: nil))
        }
    }

    /// At most one a week, never one per app (Adoption.merge decides when).
    static func notifyAdoptionDigest(_ candidates: [AdoptionCandidate]) {
        guard !candidates.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = candidates.count == 1
            ? "\(candidates[0].name) could be updated by Homebrew"
            : "\(candidates.count) apps could be updated by Homebrew"
        content.body = "Nothing updates them today. Nothing changes unless you say so."
        let request = UNNotificationRequest(identifier: adoptionID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
