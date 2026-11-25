import Foundation

/// Recovery for a cask upgrade that Homebrew left half-finished.
///
/// During `brew upgrade --cask`, Homebrew moves the installed version into a
/// `<version>.upgrading` staging folder in its Caskroom, installs the new one,
/// then deletes the staging folder. If that is interrupted, the folder stays
/// behind — Homebrew even records it as the installed version — and every
/// later upgrade stops with "It seems there is already an App at
/// '…/Caskroom/<token>/<version>.upgrading/<App>.app'".
///
/// The repair moves that leftover folder to the Trash (recoverable) and then
/// reinstalls the cask with `--force`, which writes a clean install record.
enum BrewRepair {
    /// The leftover folder named in Homebrew's error, or nil if the output isn't
    /// this failure. Two shapes: `<version>.upgrading` (an interrupted upgrade),
    /// and a plain `<version>` folder that holds a real copy of the app (Signal
    /// and Spotify, 19 Nov 2026: Homebrew backed the app up into it, then
    /// stopped when it needed an administrator password, and every later
    /// upgrade said "already an App"). Deliberately strict: the folder must sit
    /// directly in `Caskroom/<token>/`, be a real folder (not a link), and is
    /// only ever moved to the Trash. The app in /Applications and the app's own
    /// data are never touched.
    static func staleUpgradeFolder(in output: String, token: String) -> URL? {
        guard output.contains("It seems there is already an App at"),
              let regex = try? NSRegularExpression(pattern: #"'(/[^']+?/Caskroom/[^/']+/[^/']+)/[^/']+\.app'"#),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output)
        else { return nil }
        let folder = URL(fileURLWithPath: String(output[range]))
        let tokenDir = folder.deletingLastPathComponent()
        guard tokenDir.lastPathComponent == token,
              tokenDir.deletingLastPathComponent().lastPathComponent == "Caskroom",
              !folder.lastPathComponent.hasPrefix("."),
              (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true
        else { return nil }
        return folder
    }

    // Casks whose next install should be a forced reinstall rather than an
    // upgrade (Homebrew can't `upgrade` from a corrupted install record).
    private static let lock = NSLock()
    nonisolated(unsafe) private static var pendingReinstall: Set<String> = []

    static func markForReinstall(_ token: String) {
        lock.lock(); pendingReinstall.insert(token); lock.unlock()
    }

    /// True once per marked token, then cleared.
    static func consumeReinstall(_ token: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pendingReinstall.remove(token) != nil
    }
}
