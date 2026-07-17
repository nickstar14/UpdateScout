import SwiftUI
import AppKit

@main
struct Main {
    static func main() {
        if CommandLine.arguments.contains("--askpass") {
            AskpassDialog.run()
        } else if CommandLine.arguments.contains("--background-check") {
            backgroundCheck()
        } else {
            UpdateScoutApp.main()
        }
    }

    /// Headless mode, run by the launchd agent: detect, persist, notify, exit.
    /// Installs never happen here — detection only.
    static func backgroundCheck() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let sources = UpdateController.allSources.filter { !Prefs.disabledSources.contains($0.id) }
            let (items, errors) = await UpdateController.runDetection(sources: sources)
            var s = Store.load()
            s.items = items
            s.sourceErrors = errors
            s.lastCheck = Date()
            let ids = Set(items.map(\.id))
            s.dismissed.formIntersection(ids)
            s.notified.formIntersection(ids)
            let fresh = items.filter { !s.notified.contains($0.id) && !s.dismissed.contains($0.id) }
            Notifier.notifyNewUpdates(fresh)
            s.notified.formUnion(fresh.map(\.id))
            Store.save(s)
            // Give the notification a moment to post before exiting.
            try? await Task.sleep(for: .seconds(2))
            semaphore.signal()
        }
        semaphore.wait()
    }
}

struct UpdateScoutApp: App {
    @ObservedObject private var controller = UpdateController.shared

    init() {
        Notifier.requestPermission()
        CustomSource.seedIfMissing()
        DispatchQueue.main.async {
            Appearance.apply(Prefs.appearance)
            if Prefs.showDockIcon { NSApp.setActivationPolicy(.regular) }
        }
        // When the askpass dialog closes, bring the status window back to the
        // front (the auth prompt pushes us behind other apps).
        DistributedNotificationCenter.default().addObserver(
            forName: .updateScoutRefront, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                UpdatesWindow.shared.show()
            }
        }
        // First launch with missing dependencies → open Settings so the
        // Setup section can offer one-click installs.
        if !UserDefaults.standard.bool(forKey: "didFirstRunSetup") {
            UserDefaults.standard.set(true, forKey: "didFirstRunSetup")
            if Shell.which("brew") == nil || Shell.which("mas") == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    SettingsWindow.shared.show()
                }
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
        } label: {
            // Rotated slightly so the arrow sweep matches the app icon's angle.
            let icon = Image(systemName: "arrow.triangle.2.circlepath")
            if controller.badgeCount > 0 {
                HStack(spacing: 3) {
                    icon.rotationEffect(.degrees(-15))
                    Text("\(controller.badgeCount)")
                }
            } else {
                icon.rotationEffect(.degrees(-15))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
