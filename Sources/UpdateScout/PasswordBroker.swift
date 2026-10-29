import Foundation
import Darwin

/// One password per batch. Homebrew runs `sudo` itself for pkg casks, so a
/// sudo cache primed by the app doesn't reach it (tested in phase 3). Instead
/// the app asks once, keeps the password in memory for the batch only, and
/// serves it to our own askpass helper over a private Unix socket:
///
/// - the socket lives in a 0700 folder and checks the caller is this user;
/// - every request must carry the batch's random token;
/// - the password is never written to disk, logged or put on a command line;
/// - `stop()` zeroes it, closes the socket and deletes the folder.
final class PasswordBroker: @unchecked Sendable {
    static let shared = PasswordBroker()

    private let lock = NSLock()
    private var secret: [UInt8]?
    private var token = ""
    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "PasswordBroker")

    static var directory: URL { Store.supportDirectory.appendingPathComponent("broker", isDirectory: true) }
    private static var socketURL: URL { directory.appendingPathComponent("s") }
    /// Holds the batch token so the askpass helper (started by sudo, possibly
    /// through brew, which strips our environment) can find it.
    private static var tokenURL: URL { directory.appendingPathComponent("token") }

    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return secret != nil }

    /// Check the password with sudo, then start serving it. False if it's wrong
    /// or the socket can't be set up (callers fall back to per-call prompts).
    func start(password: String) async -> Bool {
        guard await Self.verify(password) else { return false }
        stop()
        let fm = FileManager.default
        let dir = Self.directory
        try? fm.removeItem(at: dir)
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])) != nil else { return false }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return false }
        let newToken = bytes.map { String(format: "%02x", $0) }.joined()
        guard fm.createFile(atPath: Self.tokenURL.path, contents: Data(newToken.utf8),
                            attributes: [.posixPermissions: 0o600]),
              let fd = Self.listen(at: Self.socketURL.path) else {
            try? fm.removeItem(at: dir)
            return false
        }

        lock.withLock {
            secret = Array(password.utf8)
            token = newToken
            listenFD = fd
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.serveOne() }
        source.resume()
        lock.withLock { self.source = source }
        return true
    }

    /// End of batch: wipe the password and remove the socket and token.
    func stop() {
        lock.lock()
        if secret != nil {
            for i in secret!.indices { secret![i] = 0 }
        }
        secret = nil
        token = ""
        let source = self.source, fd = listenFD
        self.source = nil
        listenFD = -1
        lock.unlock()
        source?.cancel()
        if fd >= 0 { close(fd) }
        try? FileManager.default.removeItem(at: Self.directory)
    }

    private func serveOne() {
        lock.lock(); let fd = listenFD; lock.unlock()
        let client = accept(fd, nil, nil)
        guard client >= 0 else { return }
        defer { close(client) }
        // Only processes running as this user may ask.
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { return }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var buffer = [UInt8](repeating: 0, count: 128)
        let count = read(client, &buffer, buffer.count)
        guard count > 0 else { return }
        let sent = String(decoding: buffer[0..<count], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        let reply = (!token.isEmpty && sent == token) ? secret.map { $0 + [10] } : nil
        lock.unlock()
        guard var reply else { return }
        _ = reply.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
        for i in reply.indices { reply[i] = 0 }
    }

    private static func listen(at path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else { close(fd); return nil }
        return fd
    }

    /// The askpass side: fetch the batch password, or nil when no batch is
    /// running (the helper then shows its own dialog, as before).
    static func fetchPassword() -> String? {
        guard let token = try? String(contentsOf: tokenURL, encoding: .utf8), !token.isEmpty else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        guard connected == 0 else { return nil }
        let request = Array((token + "\n").utf8)
        guard write(fd, request, request.count) == request.count else { return nil }
        var buffer = [UInt8](repeating: 0, count: 1024)
        let count = read(fd, &buffer, buffer.count)
        guard count > 1 else { return nil }
        defer { for i in buffer.indices { buffer[i] = 0 } }
        return String(decoding: buffer[0..<(count - 1)], as: UTF8.self)
    }

    /// Check a password with `sudo -S -k`, which ignores any cached ticket and
    /// reads the password from stdin (never from the command line).
    private static func verify(_ password: String) async -> Bool {
        await withCheckedContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            process.arguments = ["-S", "-k", "-p", "", "/usr/bin/true"]
            var env = ProcessInfo.processInfo.environment
            env["SUDO_ASKPASS"] = nil
            process.environment = env
            let input = Pipe()
            process.standardInput = input
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { cont.resume(returning: $0.terminationStatus == 0) }
            do {
                try process.run()
                input.fileHandleForWriting.write(Data((password + "\n").utf8))
                try? input.fileHandleForWriting.close()
            } catch {
                cont.resume(returning: false)
            }
        }
    }
}
