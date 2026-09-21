import Foundation

/// A third-party kernel extension bundle found in /Library/Extensions.
struct KextBundle: Codable, Hashable, Identifiable {
    var id: String { path }
    let name: String
    let version: String
    let bundleID: String
    let path: String
    let modified: Date?
}

/// Inventory of legacy kexts, split into the ones the kernel actually has
/// loaded and the leftovers. /Library/Extensions accumulates bundles from old
/// installers (printer drivers, enclosure software) that macOS never loads —
/// on Apple silicon it can't without reduced security — so "on disk" and "in
/// use" are very different things.
enum KextInventory {
    static let directory = "/Library/Extensions"

    static func onDisk() -> [KextBundle] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: directory),
                                                        includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        return entries.compactMap { url in
            guard url.pathExtension == "kext" else { return nil }
            let plistURL = url.appendingPathComponent("Contents/Info.plist")
            guard let data = fm.contents(atPath: plistURL.path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let bundleID = plist["CFBundleIdentifier"] as? String,
                  !bundleID.hasPrefix("com.apple.")   // Apple's own update via softwareupdate
            else { return nil }
            let version = (plist["CFBundleShortVersionString"] ?? plist["CFBundleVersion"]) as? String ?? "?"
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return KextBundle(name: (url.lastPathComponent as NSString).deletingPathExtension,
                              version: version, bundleID: bundleID, path: url.path, modified: modified)
        }
    }

    /// Bundle identifiers the kernel currently has loaded.
    static func loadedIDs() async -> Set<String> {
        guard let result = try? await Shell.run("/usr/bin/kmutil", ["showloaded", "--no-kernel-components"]),
              result.status == 0 else { return [] }
        // Each line lists the bundle ID in its own column; a substring check
        // against the full output is enough and tolerant of column changes.
        var ids = Set<String>()
        for kext in onDisk() where result.stdout.contains(kext.bundleID) { ids.insert(kext.bundleID) }
        return ids
    }

    static func partition() async -> (loaded: [KextBundle], leftover: [KextBundle]) {
        let all = onDisk()
        let loaded = await loadedIDs()
        return (all.filter { loaded.contains($0.bundleID) },
                all.filter { !loaded.contains($0.bundleID) })
    }

    // MARK: - Removal

    /// Only ever delete a .kext directly inside /Library/Extensions. The path
    /// comes from our own scan, but this is the last line before `rm -rf` as
    /// root, so it's checked again here regardless.
    static func isSafeToRemove(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        return url.pathExtension == "kext"
            && url.deletingLastPathComponent().path == directory
            && !url.lastPathComponent.isEmpty
            && !path.contains("..")
    }

    /// Delete a leftover kext. Needs admin rights, so this goes through the
    /// same password dialog installs use. Touching the directory afterwards
    /// invalidates the legacy kext cache; nothing to rebuild since the kext
    /// wasn't loaded.
    static func remove(_ kext: KextBundle, progress: @escaping @Sendable (String) -> Void) async throws {
        guard isSafeToRemove(kext.path) else {
            throw UpdateScoutError.commandFailed("remove", output: "Refusing to delete outside \(directory): \(kext.path)")
        }
        progress("Authorizing — enter your password to remove…")
        let quoted = "'" + kext.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let result = try await Shell.runPrivileged(
            "/bin/rm -rf \(quoted) && /usr/bin/touch '\(directory)'", tag: "install")
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed("rm -rf \(kext.name).kext", output: result.combined)
        }
        if FileManager.default.fileExists(atPath: kext.path) {
            throw UpdateScoutError.commandFailed("remove", output: "\(kext.path) still exists after removal.")
        }
    }
}
