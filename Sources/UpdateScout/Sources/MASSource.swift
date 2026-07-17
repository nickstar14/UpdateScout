import Foundation

struct MASSource: UpdateSource {
    let id = "mas"
    let displayName = "Mac App Store"

    func detect() async throws -> [UpdateItem] {
        guard let mas = Shell.which("mas") else {
            throw UpdateScoutError.toolMissing("mas-cli", hint: "Run `brew install mas` to enable App Store checks.")
        }
        let result = try await Shell.run(mas, ["outdated"])
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed("mas outdated", output: result.combined)
        }
        // Lines look like: 497799835  Xcode (14.2 -> 14.3)
        let pattern = #/^(\d+)\s+(.+?)\s+\(([^)]*?)\s*->\s*([^)]*)\)\s*$/#
        var items: [UpdateItem] = []
        for line in result.stdout.split(separator: "\n") {
            guard let m = line.firstMatch(of: pattern) else { continue }
            items.append(UpdateItem(sourceID: id,
                                    name: String(m.2),
                                    installedVersion: String(m.3),
                                    latestVersion: String(m.4),
                                    url: "macappstore://showUpdatesPage",
                                    installToken: String(m.1)))
        }
        return items
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let mas = Shell.which("mas") else {
            throw UpdateScoutError.toolMissing("mas-cli", hint: "Run `brew install mas`.")
        }
        let result = try await Shell.run(mas, ["upgrade", item.installToken], tag: "install", lineHandler: progress)
        let sudoBlocked = result.combined.contains("sudo: a terminal is required")
        if result.status == 0 && !sudoBlocked { return }
        // The row can be stale (app already updated, e.g. by the App Store
        // itself) — mas then reports the ADAM ID as not installed. Not an error.
        if result.combined.contains("No installed apps with ADAM ID") { return }

        if sudoBlocked {
            // mas 7 shells out to a hard-coded /usr/bin/sudo without -A, which
            // cannot prompt from a GUI app (no terminal, askpass ignored).
            // Re-run under real sudo instead — it sets SUDO_UID/SUDO_USER
            // properly so mas still operates on this user's account.
            progress("Authorizing — enter your password, then the install runs…")
            let priv = try await Shell.runPrivileged("'\(mas)' upgrade \(item.installToken)", tag: "install")
            if priv.combined.contains("No installed apps with ADAM ID") { return }
            guard priv.status == 0 else {
                throw UpdateScoutError.commandFailed("mas upgrade \(item.installToken) (admin)", output: priv.combined)
            }
            return
        }
        throw UpdateScoutError.commandFailed("mas upgrade \(item.installToken)", output: result.combined)
    }
}
