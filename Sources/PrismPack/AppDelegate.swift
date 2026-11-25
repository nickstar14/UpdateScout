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
        // One copy at a time: a second launch (a test build, a double start)
        // shows the first copy's window and leaves, so there is never a second
        // menu bar prism or a second window.
        if Self.handOverToRunningCopy() { return }
        StatusItemController.shared.install()
        SetupWindow.showOnceIfNeeded()
        SelfUpdater.start()
        // With the app open the background agent leaves auto-updates to it;
        // the daily cleanup is the same, a little after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { Task { await Cleanup.runIfDue() } }
        // The rename pop-up lives in the main window, so open it once; and
        // after an update relaunch, come back to the window.
        let defaults = UserDefaults.standard
        let reopen = defaults.bool(forKey: SelfUpdater.reopenWindowKey)
        defaults.removeObject(forKey: SelfUpdater.reopenWindowKey)
        if reopen || defaults.bool(forKey: Migration.noticeKey) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { UpdatesWindow.shared.show() }
        }
    }

    /// Another PrismPack with a window app running (the headless background
    /// check has no activation policy, so it doesn't count).
    private static func otherCopy() -> NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first { $0.processIdentifier != me && $0.activationPolicy != .prohibited && !$0.isTerminated }
    }

    /// Build number first, then when the program file was written, so two
    /// builds of the same version still have a newer one.
    private struct Stamp: Comparable {
        let build: Int
        let written: Date
        static func < (a: Stamp, b: Stamp) -> Bool { (a.build, a.written) < (b.build, b.written) }
    }

    private static func stamp(of appURL: URL?) -> Stamp {
        guard let appURL, let bundle = Bundle(url: appURL) else { return Stamp(build: 0, written: .distantPast) }
        let build = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
        let written = bundle.executableURL
            .flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date } ?? .distantPast
        return Stamp(build: build, written: written)
    }

    /// Only one copy runs, and it is the newest build. If another copy is
    /// running: a newer one makes this launch quit (it shows its window); an
    /// older one is asked to quit, and this launch carries on. Returns true
    /// when this launch should stop. A copy on its way out (an update's
    /// relaunch) gets a few seconds to finish first.
    private static func handOverToRunningCopy() -> Bool {
        guard otherCopy() != nil else { return false }
        for _ in 0..<30 where otherCopy() != nil { Thread.sleep(forTimeInterval: 0.1) }
        guard let other = otherCopy() else { return false }
        // The running copy's code is no newer than when it started: a build
        // written over its file since (same path) leaves it running old code.
        var theirs = stamp(of: other.bundleURL)
        if let launched = other.launchDate, launched < theirs.written { theirs = Stamp(build: theirs.build, written: launched) }
        if stamp(of: Bundle.main.bundleURL) > theirs {
            // This one is newer: the old copy goes. Builds from before this
            // rule don't listen, so they are ended if they don't quit.
            DistributedNotificationCenter.default().postNotificationName(
                .prismPackQuitForNewer, object: nil,
                userInfo: ["pid": ProcessInfo.processInfo.processIdentifier], deliverImmediately: true)
            for _ in 0..<30 where otherCopy() != nil { Thread.sleep(forTimeInterval: 0.1) }
            if let still = otherCopy() {
                still.forceTerminate()
                for _ in 0..<20 where otherCopy() != nil { Thread.sleep(forTimeInterval: 0.1) }
            }
            return false
        }
        DistributedNotificationCenter.default().postNotificationName(
            .prismPackRefront, object: nil, userInfo: nil, deliverImmediately: true)
        other.activate()
        skipQuitPrompt = true
        NSApp.terminate(nil)
        return true
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
        // Clicked means seen: take PrismPack's notifications out of
        // Notification Center, whichever button was used (the background
        // check posts under other ids, so removing just this one left the
        // rest there).
        center.removeAllDeliveredNotifications()
        if response.actionIdentifier != Notifier.dismissAction {
            DispatchQueue.main.async { UpdatesWindow.shared.show(page: .updates) }
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
