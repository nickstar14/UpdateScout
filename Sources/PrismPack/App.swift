import SwiftUI
import AppKit

@main
struct Main {
    static func main() {
        // Before anything reads preferences or the data folder.
        EarlyMigration.run()
        if CommandLine.arguments.contains("--askpass") {
            AskpassDialog.run()
        } else if CommandLine.arguments.contains("--background-check") {
            backgroundCheck()
        } else {
            PrismPackApp.main()
        }
    }

    /// Headless mode, run by the launchd agent: detect, persist, install
    /// what automatic updates allow (only while the app isn't running), notify, exit.
    static func backgroundCheck() {
        let semaphore = DispatchSemaphore(value: 0)
        // Tell the menu bar app a check is under way (merge clears it).
        Store.mutate { $0.checkStartedAt = Date() }
        Task {
            let sources = UpdateController.allSources.filter { !Prefs.disabledSources.contains($0.id) }
            async let detection = UpdateController.runDetection(sources: sources)
            async let leftovers = KextInventory.partition().leftover
            // Adoption only reads here: it never adopts headless.
            async let adoption = Adoption.scanIfEnabled()
            let (items, errors) = await detection
            let kexts = await leftovers
            let scan = await adoption
            var fresh: [UpdateItem] = []
            var digest: [AdoptionCandidate] = []
            Store.mutate { s in
                fresh = UpdateController.merge(items: items, errors: errors, leftovers: kexts, into: &s)
                if let scan { digest = Adoption.merge(scan, into: &s) }
            }
            // Before notifying, so what updated automatically isn't announced.
            let auto = await AutoUpdate.runHeadless()
            Notifier.notifyAutoRun(updated: auto.updated, failed: auto.failed)
            let after = Store.load()
            Notifier.notifyNewUpdates(fresh, waiting: after.items.filter { !after.isHidden($0) })
            Notifier.notifyAdoptionDigest(digest)
            await Cleanup.runIfDue()
            // Give the notification a moment to post before exiting.
            try? await Task.sleep(for: .seconds(2))
            semaphore.signal()
        }
        semaphore.wait()
    }
}

struct PrismPackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var controller = UpdateController.shared

    init() {
        Notifier.requestPermission()
        _ = CustomSource.backgroundNames   // before the seed, so a fresh seed starts off
        CustomSource.seedIfMissing()
        DispatchQueue.main.async {
            Appearance.apply(Prefs.appearance)
            if Prefs.showDockIcon { NSApp.setActivationPolicy(.regular) }
            // `open PrismPack.app --args --open-window` shows the status
            // window straight away (handy for screenshots and testing).
            if CommandLine.arguments.contains("--open-window") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { UpdatesWindow.shared.show() }
            }
            // `--open-settings` also opens the status window first, so the
            // centring path being exercised is the real one.
            // `--show-fda-helper` opens the Full Disk Access helper window by itself (testing).
            if CommandLine.arguments.contains("--show-fda-helper") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { FullDiskAccess.showHelper() }
            }
            if CommandLine.arguments.contains("--open-settings") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { UpdatesWindow.shared.show() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { SettingsWindow.shared.show() }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: .prismPackQuitForNewer, object: nil, queue: .main
        ) { note in
            let sender = (note.userInfo?["pid"] as? Int32) ?? (note.userInfo?["pid"] as? Int).map(Int32.init) ?? 0
            guard sender != ProcessInfo.processInfo.processIdentifier else { return }
            AppDelegate.quitWithoutAsking()
        }
        // When the askpass dialog closes, bring the status window back to the
        // front (the auth prompt pushes us behind other apps).
        DistributedNotificationCenter.default().addObserver(
            forName: .prismPackRefront, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                UpdatesWindow.shared.show()
            }
        }
        Migration.prepareNotice()
        // First launch: the Setup window (tools, then optional Full Disk
        // Access), even when nothing is missing. After the 2.0 rename macOS
        // starts Full Disk Access over, so it opens once more for that.
        let recheck = UserDefaults.standard.bool(forKey: EarlyMigration.recheckPermissionsKey)
        UserDefaults.standard.removeObject(forKey: EarlyMigration.recheckPermissionsKey)
        UserDefaults.standard.set(true, forKey: "didFirstRunSetup")
        if recheck { UserDefaults.standard.removeObject(forKey: SetupWindow.shownKey) }
    }

    // The status item is an NSStatusItem (StatusItemController), so left and
    // right clicks can differ; SwiftUI still needs a scene, so an empty one
    // that's never inserted.
    var body: some Scene {
        MenuBarExtra("", isInserted: .constant(false)) { EmptyView() }
    }
}
