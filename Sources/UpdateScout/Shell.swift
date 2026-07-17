import Foundation

/// Tracks live child processes by tag so an in-flight install can be cancelled.
final class ProcessRegistry: @unchecked Sendable {
    static let shared = ProcessRegistry()
    private let lock = NSLock()
    private var procs: [String: [Process]] = [:]

    func add(_ p: Process, tag: String) {
        lock.lock(); procs[tag, default: []].append(p); lock.unlock()
    }
    func remove(_ p: Process, tag: String) {
        lock.lock(); procs[tag]?.removeAll { $0 === p }; lock.unlock()
    }
    func terminate(tag: String) {
        lock.lock(); let list = procs[tag] ?? []; lock.unlock()
        list.forEach { $0.terminate() }
    }
}

/// Async subprocess runner. Everything UpdateScout does externally goes through here.
enum Shell {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
        var combined: String { stdout + (stderr.isEmpty ? "" : "\n" + stderr) }
    }

    /// Run an executable directly (no shell interpretation of arguments).
    @discardableResult
    static func run(_ executable: String, _ args: [String], tag: String? = nil,
                    lineHandler: (@Sendable (String) -> Void)? = nil) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        // brew/mas need a sane PATH even when launched from launchd. Our shim
        // dir goes first so child processes calling `sudo` get the -A variant
        // (sudo only consults SUDO_ASKPASS when -A is passed; brew adds it
        // itself, but mas does not).
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = Askpass.shimDir + ":" + (env["PATH"].map { $0 + ":" } ?? "") + extra
        // Keep brew quiet and non-interactive.
        env["HOMEBREW_NO_AUTO_UPDATE"] = env["HOMEBREW_NO_AUTO_UPDATE"] ?? "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        // GUI apps have no terminal for sudo to prompt on; pkg-based casks and
        // some mas updates need elevation. SUDO_ASKPASS makes sudo show a
        // graphical prompt instead — the password goes directly to sudo.
        env["SUDO_ASKPASS"] = Askpass.path
        process.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        actor Collector {
            var out = Data(); var err = Data()
            func addOut(_ d: Data) { out.append(d) }
            func addErr(_ d: Data) { err.append(d) }
        }
        let collector = Collector()

        outPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            Task { await collector.addOut(d) }
            if let lineHandler, let s = String(data: d, encoding: .utf8) {
                for line in s.split(separator: "\n") { lineHandler(String(line)) }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            Task { await collector.addErr(d) }
            if let lineHandler, let s = String(data: d, encoding: .utf8) {
                for line in s.split(separator: "\n") { lineHandler(String(line)) }
            }
        }

        return try await withCheckedThrowingContinuation { cont in
            process.terminationHandler = { p in
                if let tag { ProcessRegistry.shared.remove(p, tag: tag) }
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let outRest = try? outPipe.fileHandleForReading.readToEnd()
                let errRest = try? errPipe.fileHandleForReading.readToEnd()
                Task {
                    if let outRest { await collector.addOut(outRest) }
                    if let errRest { await collector.addErr(errRest) }
                    let out = String(data: await collector.out, encoding: .utf8) ?? ""
                    let err = String(data: await collector.err, encoding: .utf8) ?? ""
                    cont.resume(returning: Result(status: p.terminationStatus, stdout: out, stderr: err))
                }
            }
            do {
                try process.run()
                if let tag { ProcessRegistry.shared.add(process, tag: tag) }
            } catch { cont.resume(throwing: error) }
        }
    }

    /// Locate a tool in the usual places; nil if not installed.
    static func which(_ tool: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            let p = dir + "/" + tool
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    // (Askpass helper lives below runPrivileged.)

    /// Run a command that needs admin rights. Uses `sudo -A`, which prompts
    /// through our own askpass dialog (AskpassDialog) and — unlike the
    /// osascript route — sets the real SUDO_UID/SUDO_USER environment that
    /// tools like mas rely on. Callers pass pre-quoted, trusted commands only.
    static func runPrivileged(_ command: String, tag: String? = nil) async throws -> Result {
        // (Refronting after the auth dialog is handled via the distributed
        // notification the askpass process posts when it closes.)
        return try await run("/usr/bin/sudo", ["-A", "/bin/sh", "-c", command], tag: tag)
    }
}

/// A tiny helper script sudo runs when it needs a password and has no
/// terminal: it shows a native password dialog and prints the entry to
/// stdout, which sudo reads directly. UpdateScout itself never sees it.
enum Askpass {
    static var path: String {
        let url = Store.supportDirectory.appendingPathComponent("askpass.sh")
        // Re-invoke our own binary in --askpass mode, which shows a
        // native-styled auth dialog (AskpassDialog). Rewritten every time so
        // the path tracks wherever the app currently lives.
        let exe = Bundle.main.executablePath ?? "/Applications/UpdateScout.app/Contents/MacOS/UpdateScout"
        let script = "#!/bin/sh\nexec \"\(exe)\" --askpass\n"
        if (try? String(contentsOf: url, encoding: .utf8)) != script {
            try? script.write(to: url, atomically: true, encoding: .utf8)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }

    /// Directory holding a `sudo` wrapper that adds -A, so tools that invoke
    /// plain `sudo` (like mas) still get the graphical askpass prompt.
    static var shimDir: String {
        let dir = Store.supportDirectory.appendingPathComponent("bin", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shim = dir.appendingPathComponent("sudo")
        let script = "#!/bin/sh\nexec /usr/bin/sudo -A \"$@\"\n"
        if (try? String(contentsOf: shim, encoding: .utf8)) != script {
            try? script.write(to: shim, atomically: true, encoding: .utf8)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        return dir.path
    }
}
