import Foundation
import AppKit
import SwiftUI

/// Tracks the external tools PrismPack relies on, and installs the ones
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
                    throw PrismPackError.commandFailed("brew install \(formula)", output: result.combined)
                }
            } catch {
                installError = error.localizedDescription
            }
            installingID = nil
            refresh()
        }
    }
}

/// Settings is a page of the main window now; this keeps the old entry
/// points (menu, `--open-settings`, first-run setup) working.
@MainActor
enum SettingsWindow {
    static let shared = SettingsWindow.self
    static func show() { UpdatesWindow.shared.show(page: .settings) }
}
