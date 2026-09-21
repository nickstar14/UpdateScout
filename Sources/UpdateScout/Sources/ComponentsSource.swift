import Foundation

/// Best-effort coverage for third-party driver-adjacent components: DriverKit /
/// system extensions, audio HAL plug-ins, and legacy kexts. There is no unified
/// macOS API for third-party driver updates, so detected components are
/// version-checked against Homebrew's cask database — the ones with a cask get
/// a one-click update; components without one have no queryable update channel.
struct ComponentsSource: UpdateSource {
    let id = "components"
    let displayName = "Drivers & extensions"

    func detect() async throws -> [UpdateItem] {
        let casks = try await CaskIndex.load()
        let byName = CaskIndex.byAppName(casks)

        var components = halPlugins()
        components += await legacyKexts()
        components += await systemExtensions()

        var items: [UpdateItem] = []
        var seenTokens = Set<String>()
        for comp in components {
            guard let cask = match(comp.name, in: byName),
                  seenTokens.insert(cask.token).inserted,
                  isNewerVersion(cask.version, than: comp.version)
            else { continue }
            items.append(UpdateItem(sourceID: id, name: comp.name,
                                    installedVersion: comp.version,
                                    latestVersion: cask.version,
                                    url: cask.homepage ?? "https://formulae.brew.sh/cask/\(cask.token)",
                                    caveat: (comp.path.map { "Found at \($0). " } ?? "")
                                        + "Updates via Homebrew cask \"\(cask.token)\".",
                                    installToken: cask.token))
        }
        return items
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let brew = HomebrewSource.brewPath else {
            throw UpdateScoutError.toolMissing("Homebrew", hint: "Install it from https://brew.sh")
        }
        let args = ["install", "--cask", item.installToken, "--force"]
        let result = try await Shell.run(brew, args, tag: "install", lineHandler: progress)
        guard result.status == 0 else {
            throw UpdateScoutError.commandFailed("brew \(args.joined(separator: " "))", output: result.combined)
        }
    }

    // MARK: - Component scans

    private struct Component {
        let name: String
        let version: String
        let bundleID: String?
        /// Where the component lives on disk (nil for system extensions).
        let path: String?
    }

    /// Bundle-style components (HAL drivers, kexts): name from the bundle
    /// filename, version from its Info.plist.
    private func bundleComponents(in dir: String, extensions: Set<String>) -> [Component] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                        includingPropertiesForKeys: nil) else { return [] }
        return entries.compactMap { url in
            guard extensions.contains(url.pathExtension) else { return nil }
            let plistURL = url.appendingPathComponent("Contents/Info.plist")
            guard let data = fm.contents(atPath: plistURL.path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let version = (plist["CFBundleShortVersionString"] ?? plist["CFBundleVersion"]) as? String
            else { return nil }
            let bundleID = plist["CFBundleIdentifier"] as? String
            // Skip Apple's own components — those update through softwareupdate.
            if bundleID?.hasPrefix("com.apple.") == true { return nil }
            return Component(name: (url.lastPathComponent as NSString).deletingPathExtension,
                             version: version, bundleID: bundleID, path: url.path)
        }
    }

    /// HAL plug-ins are loaded by coreaudiod simply by being in the folder, so
    /// presence on disk means in use.
    private func halPlugins() -> [Component] {
        bundleComponents(in: "/Library/Audio/Plug-Ins/HAL", extensions: ["driver", "plugin"])
    }

    /// Legacy kexts are different: /Library/Extensions is full of leftovers from
    /// old installers (printer drivers, enclosure software) that macOS never
    /// loads — on Apple silicon it can't without reduced security. A kext that
    /// isn't loaded isn't a driver in use, and offering to "update" it would be
    /// misleading, so only loaded ones are reported.
    private func legacyKexts() async -> [Component] {
        // Unloaded leftovers are surfaced separately for removal (KextInventory).
        await KextInventory.partition().loaded.map {
            Component(name: $0.name, version: $0.version, bundleID: $0.bundleID, path: $0.path)
        }
    }

    /// Third-party DriverKit / network / endpoint system extensions.
    /// `systemextensionsctl list` lines look like:
    ///   *  *  TEAMID  com.vendor.thing (1.2.3/456)  Thing Extension  [activated enabled]
    private func systemExtensions() async -> [Component] {
        guard let result = try? await Shell.run("/usr/bin/systemextensionsctl", ["list"]) else { return [] }
        let pattern = #/\((?<version>[^/()\s]+)(?:/[^)]*)?\)\s+(?<name>.+?)\s+\[activated/#
        var comps: [Component] = []
        for line in result.stdout.split(separator: "\n") {
            guard line.contains("[activated"), !line.contains("com.apple."),
                  let m = line.firstMatch(of: pattern) else { continue }
            comps.append(Component(name: String(m.name), version: String(m.version),
                                   bundleID: nil, path: nil))
        }
        return comps
    }

    /// Match a component name to a cask: exact first, then with common
    /// driver/extension suffixes stripped. Conservative on purpose — a wrong
    /// match would offer the wrong software as an "update".
    private func match(_ name: String, in index: [String: CaskIndex.CaskInfo]) -> CaskIndex.CaskInfo? {
        var candidate = name.lowercased()
        if let hit = index[candidate] { return hit }
        for suffix in [" network extension", " system extension", " extension",
                       " audio", " driver", " virtualaudiodevice", " hal"] {
            if candidate.hasSuffix(suffix) {
                candidate = String(candidate.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                if let hit = index[candidate] { return hit }
            }
        }
        return nil
    }
}
