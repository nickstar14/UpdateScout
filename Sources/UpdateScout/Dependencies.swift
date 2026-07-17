import Foundation
import AppKit
import SwiftUI

/// Tracks the external tools UpdateScout relies on, and installs the ones
/// that can be installed with one click (currently just mas via brew).
@MainActor
final class DependencyManager: ObservableObject {
    struct Dependency: Identifiable {
        let id: String
        let name: String
        let purpose: String
        var installed: Bool
        /// Present when we can install it ourselves with one click.
        let brewFormula: String?
        /// Where to send the user when we can't.
        let manualURL: String?
    }

    @Published var dependencies: [Dependency] = []
    @Published var installingID: String?
    @Published var installError: String?

    var anyMissing: Bool { dependencies.contains { !$0.installed } }

    init() { refresh() }

    func refresh() {
        dependencies = [
            Dependency(id: "brew", name: "Homebrew",
                       purpose: "Required — powers most update checks and installs",
                       installed: Shell.which("brew") != nil,
                       brewFormula: nil,
                       manualURL: "https://brew.sh"),
            Dependency(id: "mas", name: "mas-cli",
                       purpose: "Enables Mac App Store update checks",
                       installed: Shell.which("mas") != nil,
                       brewFormula: "mas",
                       manualURL: nil),
        ]
    }

    func install(_ dep: Dependency) {
        guard let formula = dep.brewFormula, let brew = Shell.which("brew"),
              installingID == nil else { return }
        installingID = dep.id
        installError = nil
        Task {
            do {
                let result = try await Shell.run(brew, ["install", formula])
                guard result.status == 0 else {
                    throw UpdateScoutError.commandFailed("brew install \(formula)", output: result.combined)
                }
            } catch {
                installError = error.localizedDescription
            }
            installingID = nil
            refresh()
        }
    }
}

/// Our own settings window. The SwiftUI `Settings` scene / `openSettings` /
/// `showSettingsWindow:` paths all fail silently in a menu-bar-only
/// (LSUIElement) app on macOS 27, so we host SettingsView in a plain NSWindow.
@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(UpdateController.shared))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Settings"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
