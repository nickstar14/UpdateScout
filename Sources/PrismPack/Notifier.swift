import Foundation
import UserNotifications

enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        registerCategories()
    }

    /// Every notification has the same two buttons: open the app, or dismiss
    /// it (Nick, 25 Nov 2026). Whichever is used, the notification is removed
    /// from Notification Center (see AppDelegate).
    static let categoryID = "prismpack"
    static let openAction = "open"
    static let dismissAction = "dismiss"

    static func registerCategories() {
        let open = UNNotificationAction(identifier: openAction, title: "Open \(AppIdentity.name)", options: [.foreground])
        let dismiss = UNNotificationAction(identifier: dismissAction, title: "Dismiss", options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [open, dismiss],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// An automatic update failed on a leftover that Repair fixes. One per
    /// app and version (the id repeats), so it never nags.
    static func notifyNeedsRepair(name: String, itemID: String) {
        registerCategories()
        let content = UNMutableNotificationContent()
        content.title = "\(name) needs repair"
        content.body = "\(name) failed to update. Open \(AppIdentity.name), go to Updates and click Repair and Update to fix it."
        content.categoryIdentifier = categoryID
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "repair|\(itemID)", content: content, trigger: nil))
    }

    /// Fixed identifiers, so a new notification replaces the last one in
    /// Notification Center instead of piling up.
    static let updatesID = "updates"
    static let adoptionID = "adoption"
    static let autoID = "auto"

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
        content.categoryIdentifier = categoryID
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { delivered in
            center.removeDeliveredNotifications(withIdentifiers:
                delivered.map(\.request.identifier).filter { $0 != adoptionID && $0 != autoID })
            guard !newItems.isEmpty else { return }
            center.add(UNNotificationRequest(identifier: updatesID, content: content, trigger: nil))
        }
    }

    /// One summary per automatic run, replacing the last.
    static func notifyAutoRun(updated: [String], failed: [String]) {
        guard !updated.isEmpty || !failed.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = updated.isEmpty ? "Automatic updates didn't finish"
            : updated.count == 1 ? "1 app updated automatically" : "\(updated.count) apps updated automatically"
        var lines: [String] = []
        if !updated.isEmpty { lines.append(updated.prefix(4).joined(separator: ", ") + (updated.count > 4 ? ", …" : "")) }
        if !failed.isEmpty { lines.append(failed.count == 1 ? "1 couldn't update" : "\(failed.count) couldn't update") }
        content.body = lines.joined(separator: " · ")
        content.categoryIdentifier = categoryID
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: autoID, content: content, trigger: nil))
    }

    /// At most one a week, never one per app (Adoption.merge decides when).
    static func notifyAdoptionDigest(_ candidates: [AdoptionCandidate]) {
        guard !candidates.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = candidates.count == 1
            ? "\(candidates[0].name) could be updated by Homebrew"
            : "\(candidates.count) apps could be updated by Homebrew"
        content.body = "Nothing updates them today. Nothing changes unless you say so."
        content.categoryIdentifier = categoryID
        let request = UNNotificationRequest(identifier: adoptionID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
