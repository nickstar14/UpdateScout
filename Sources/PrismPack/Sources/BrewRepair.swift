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
    /// The leftover staging folder named in Homebrew's error, or nil if the
    /// output isn't this failure. Deliberately strict: the path must sit
    /// directly in `Caskroom/<token>/` and end in `.upgrading`, because this
    /// folder is about to be moved to the Trash.
    static func staleUpgradeFolder(in output: String, token: String) -> URL? {
        guard output.contains("It seems there is already an App at"),
              let regex = try? NSRegularExpression(pattern: #"'(/[^']+?/Caskroom/[^/']+/[^/']+\.upgrading)/"#),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output)
        else { return nil }
        let folder = URL(fileURLWithPath: String(output[range]))
        let tokenDir = folder.deletingLastPathComponent()
        guard folder.lastPathComponent.hasSuffix(".upgrading"),
              tokenDir.lastPathComponent == token,
              tokenDir.deletingLastPathComponent().lastPathComponent == "Caskroom"
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
