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

        if sudoBlocked {
            // mas 7 shells out to a hard-coded /usr/bin/sudo without -A, which
            // cannot prompt from a GUI app (no terminal, askpass ignored).
            // Re-run as root via macOS's own admin prompt instead; the SUDO_*
            // variables mimic a sudo launch so mas still targets this user.
            progress("Authorizing — enter your password, then the install runs…")
            let cmd = "SUDO_UID=\(getuid()) SUDO_GID=\(getgid()) SUDO_USER='\(NSUserName())' "
                + "'\(mas)' upgrade \(item.installToken)"
            let priv = try await Shell.runPrivileged(cmd, tag: "install")
            guard priv.status == 0 else {
                throw UpdateScoutError.commandFailed("mas upgrade \(item.installToken) (admin)", output: priv.combined)
            }
            return
        }
        throw UpdateScoutError.commandFailed("mas upgrade \(item.installToken)", output: result.combined)
    }
}
