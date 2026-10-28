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
    /// `environment` adds or overrides variables for this one process.
    @discardableResult
    static func run(_ executable: String, _ args: [String], tag: String? = nil,
                    environment: [String: String] = [:],
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
        env.merge(environment) { _, new in new }
        process.environment = env

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        // Appended synchronously under a lock, so output keeps its order (a
        // Task per chunk could run out of order or after the process ended).
        let out = OutputBuffer(), err = OutputBuffer()
        func attach(_ pipe: Pipe, _ buffer: OutputBuffer) {
            pipe.fileHandleForReading.readabilityHandler = { h in
                let d = h.availableData
                guard !d.isEmpty else { return }
                let lines = buffer.append(d)
                if let lineHandler { lines.forEach(lineHandler) }
            }
        }
        attach(outPipe, out)
        attach(errPipe, err)

        return try await withCheckedThrowingContinuation { cont in
            process.terminationHandler = { p in
                if let tag { ProcessRegistry.shared.remove(p, tag: tag) }
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                var tail: [String] = []
                if let rest = try? outPipe.fileHandleForReading.readToEnd() { tail += out.append(rest) }
                if let rest = try? errPipe.fileHandleForReading.readToEnd() { tail += err.append(rest) }
                tail += out.finish() + err.finish()
                if let lineHandler { tail.forEach(lineHandler) }
                cont.resume(returning: Result(status: p.terminationStatus,
                                              stdout: out.text, stderr: err.text))
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

    /// Run a command that needs admin rights. Uses `sudo -A`, which prompts
    /// through our own askpass dialog (AskpassDialog) and — unlike the
    /// osascript route — sets the real SUDO_UID/SUDO_USER environment that
    /// tools like mas rely on. Callers pass pre-quoted, trusted commands only.
    /// `reason` is the prompt's headline, so it says what the password is for.
    static func runPrivileged(_ command: String, reason: String, tag: String? = nil,
                              lineHandler: (@Sendable (String) -> Void)? = nil) async throws -> Result {
        // (Refronting after the auth dialog is handled via the distributed
        // notification the askpass process posts when it closes.)
        return try await run("/usr/bin/sudo", ["-A", "/bin/sh", "-c", command],
                             tag: tag, environment: [Askpass.reasonKey: reason],
                             lineHandler: lineHandler)
    }
}

/// Collects one pipe's output and cuts it into lines for progress display.
/// Lines end at \n or \r (brew redraws progress bars with \r); a line split
/// across two reads is held until its end arrives.
final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var partial = Data()

    func append(_ chunk: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        partial.append(chunk)
        var lines: [String] = []
        while let i = partial.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = partial[partial.startIndex..<i]
            partial = Data(partial[partial.index(after: i)...])
            if !line.isEmpty, let s = String(data: line, encoding: .utf8) { lines.append(s) }
        }
        return lines
    }

    /// Whatever is left after the last line break.
    func finish() -> [String] {
        lock.lock(); defer { lock.unlock() }
        defer { partial = Data() }
        guard !partial.isEmpty, let s = String(data: partial, encoding: .utf8) else { return [] }
        return [s]
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// A tiny helper script sudo runs when it needs a password and has no
/// terminal: it shows a native password dialog and prints the entry to
/// stdout, which sudo reads directly. UpdateScout itself never sees it.
enum Askpass {
    /// Environment variable carrying the prompt's headline from
    /// runPrivileged, through sudo, to the askpass process.
    static let reasonKey = "UPDATESCOUT_ASKPASS_REASON"

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

/// Networking for version checks. These must never read from the local HTTP
/// cache: appcasts and the cask API send `Cache-Control: max-age=300`, so a
/// cached copy makes a just-published update invisible for minutes (or longer,
/// if the cache entry lingers) — the update simply never shows up.
enum Net {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func fetch(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try await session.data(for: request)
    }
}
