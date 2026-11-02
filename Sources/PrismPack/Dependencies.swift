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
        /// Only some sources need it; missing, it isn't flagged in Setup.
        var optional = false
        /// The tool whose `--version` names its version.
        var binary: String? = nil
    }

    @Published var dependencies: [Dependency] = []
    /// Each tool's version, read when the Setup list is opened.
    @Published private(set) var versions: [String: String] = [:]
    /// The formulae Homebrew manages, so Reinstall and Remove are only
    /// offered for copies Homebrew installed.
    @Published private(set) var managed: Set<String> = []
    /// Whether `managed` has been read yet.
    @Published private(set) var managedLoaded = false

    /// The Homebrew formula behind a tool, versioned ones included
    /// (`node@22` for Node); nil when Homebrew didn't install it.
    func managedFormula(_ dep: Dependency) -> String? {
        guard let formula = dep.brewFormula else { return nil }
        if managed.contains(formula) { return formula }
        return managed.filter { $0.hasPrefix(formula + "@") }.sorted().last
    }
    @Published var installingID: String?
    @Published var installError: String?

    var anyMissing: Bool { dependencies.contains { !$0.installed && !$0.optional } }

    init() { refresh() }

    func refresh() {
        dependencies = [
            Dependency(id: "brew", name: "Homebrew",
                       purpose: "Required — powers most update checks and installs",
                       installed: Shell.which("brew") != nil,
                       brewFormula: nil,
                       manualURL: "https://brew.sh",
                       binary: Shell.which("brew")),
            Dependency(id: "mas", name: "mas-cli",
                       purpose: "Enables Mac App Store update checks",
                       installed: Shell.which("mas") != nil,
                       brewFormula: "mas",
                       manualURL: nil,
                       binary: Shell.which("mas")),
            // The languages' own tools, for those sources and Discover
            // (Nick, 2 Nov 2026). Optional: each only matters if you use it.
            Dependency(id: "pipx", name: "pipx",
                       purpose: "Installs and updates Python apps",
                       installed: Shell.which("pipx") != nil,
                       brewFormula: "pipx", manualURL: nil, optional: true,
                       binary: Shell.which("pipx")),
            Dependency(id: "node", name: "Node and npm",
                       purpose: "Installs and updates npm packages",
                       installed: Shell.which("npm") != nil,
                       brewFormula: "node", manualURL: nil, optional: true,
                       binary: Shell.which("node")),
            Dependency(id: "rust", name: "Rust and cargo",
                       purpose: "Installs and updates Rust crates",
                       installed: Shell.which("cargo") != nil,
                       brewFormula: "rust", manualURL: nil, optional: true,
                       binary: Shell.which("cargo")),
            Dependency(id: "ruby", name: "Ruby (Homebrew's)",
                       purpose: "Installs and updates Ruby gems; the Ruby built into macOS is never used",
                       installed: GemSource.gem != nil,
                       brewFormula: "ruby", manualURL: nil, optional: true,
                       binary: GemSource.gem.map { ($0 as NSString).deletingLastPathComponent + "/ruby" }),
        ]
    }

    func install(_ dep: Dependency) { brew("install", dep) }

    /// Settings' dependency list (Nick, 2 Nov 2026). Homebrew itself is
    /// never reinstalled or removed here: removing it would remove
    /// everything it installed.
    func reinstall(_ dep: Dependency) { brew("reinstall", dep, formula: managedFormula(dep)) }
    func remove(_ dep: Dependency) { brew("uninstall", dep, formula: managedFormula(dep)) }

    func loadVersions() {
        let tools = dependencies.compactMap { dep in dep.binary.map { (dep.id, $0) } }
        Task {
            var found: [String: String] = [:]
            for (id, binary) in tools {
                guard let out = try? await Shell.run(binary, [id == "mas" ? "version" : "--version"]),
                      out.status == 0, let line = out.combined.split(separator: "\n").first else { continue }
                // "Homebrew 4.6.0", "rustc 1.90.0 (…)", "ruby 3.4.1 (…)": keep the number.
                found[id] = line.split(separator: " ").first { $0.first?.isNumber == true }.map(String.init)
                    ?? String(line).replacingOccurrences(of: "v", with: "")
            }
            versions = found
            if let brew = Shell.which("brew"), let out = try? await Shell.run(brew, ["list", "--formula", "-1"]),
               out.status == 0 {
                managed = Set(out.combined.split(separator: "\n").map(String.init))
            }
            managedLoaded = true
        }
    }

    private func brew(_ verb: String, _ dep: Dependency, formula exact: String? = nil) {
        guard let formula = exact ?? dep.brewFormula, let brew = Shell.which("brew"),
              installingID == nil else { return }
        installingID = dep.id
        installError = nil
        Task {
            do {
                let result = try await Shell.run(brew, [verb, formula])
                guard result.status == 0 else {
                    throw PrismPackError.commandFailed("brew \(verb) \(formula)", output: result.combined)
                }
            } catch {
                installError = error.localizedDescription
            }
            installingID = nil
            refresh()
            loadVersions()
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
