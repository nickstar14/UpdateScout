import Foundation

/// Ruby gems of Homebrew's Ruby. macOS's own Ruby (/usr/bin/gem) is never
/// touched: its gems live in a system folder and would need sudo. Without
/// Homebrew's Ruby the section is just empty.
struct GemSource: UpdateSource {
    let id = "gem"
    let displayName = "Ruby (gems)"

    /// The one gem command PrismPack uses: Homebrew's Ruby, which is keg-only,
    /// so it isn't on PATH and is found by its opt link.
    static var gem: String? {
        ["/opt/homebrew/opt/ruby/bin/gem", "/usr/local/opt/ruby/bin/gem"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func detect() async throws -> [UpdateItem] {
        guard let gem = Self.gem else { return [] }
        async let outdated = Shell.run(gem, ["outdated"])
        async let list = Shell.run(gem, ["list", "--local"])
        let (result, local) = try await (outdated, list)
        guard result.status == 0 else { throw PrismPackError.commandFailed("gem outdated", output: result.combined) }
        // Gems that ship with Ruby itself update with Ruby (in Tools): the
        // default ones, and bundled ones still at the version Ruby brought.
        let defaults = Self.defaultOnly(local.stdout)
        let shipped = Self.shippedSpecs(gem: gem)
        return Self.parseOutdated(result.stdout).filter { g in
            !defaults.contains(g.name) && !shipped.contains("\(g.name)-\(g.installed)")
        }.map { g in
            UpdateItem(sourceID: id, name: g.name, installedVersion: g.installed, latestVersion: g.latest,
                       url: "https://rubygems.org/gems/\(g.name)", caveat: nil,
                       installToken: g.name, scriptedInstall: true)
        }
    }

    /// `rake (13.0.6 < 13.2.1)`
    static func parseOutdated(_ text: String) -> [(name: String, installed: String, latest: String)] {
        let pattern = #/^(\S+) \((\S+) < (\S+)\)$/#
        return text.split(separator: "\n").compactMap { line in
            guard let m = line.firstMatch(of: pattern) else { return nil }
            return (String(m.1), String(m.2), String(m.3))
        }
    }

    /// Gems whose only installed copy is Ruby's bundled one: `json (default: 2.7.2)`.
    static func defaultOnly(_ text: String) -> Set<String> {
        let pattern = #/^(\S+) \(default: [^,)]+\)$/#
        return Set(text.split(separator: "\n").compactMap { line in line.firstMatch(of: pattern).map { String($0.1) } })
    }

    /// `name-version` of every gem Ruby's own keg ships, from its
    /// specifications folder (the opt link resolves into the Cellar keg).
    /// A gem the user updated themselves has a newer version and still shows.
    static func shippedSpecs(gem: String) -> Set<String> {
        let keg = URL(fileURLWithPath: gem).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
        let gems = keg.appendingPathComponent("lib/ruby/gems")
        let fm = FileManager.default
        let versions = (try? fm.contentsOfDirectory(atPath: gems.path)) ?? []
        return Set(versions.flatMap { version -> [String] in
            let specs = gems.appendingPathComponent(version).appendingPathComponent("specifications")
            return ((try? fm.contentsOfDirectory(atPath: specs.path)) ?? [])
                .filter { $0.hasSuffix(".gemspec") }.map { String($0.dropLast(".gemspec".count)) }
        })
    }

    func install(_ item: UpdateItem, progress: @escaping @Sendable (String) -> Void) async throws {
        try await Self.gemInstall(item.installToken, progress: progress)
    }

    /// `gem install` puts the newest version beside the old one, which is how
    /// RubyGems updates; the same command installs from Discover.
    static func gemInstall(_ name: String, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let gem else {
            throw PrismPackError.toolMissing("Ruby from Homebrew",
                                             hint: "Install the ruby formula first. \(AppIdentity.name) never uses the Ruby built into macOS.")
        }
        let result = try await Shell.run(gem, ["install", name, "--no-document"], tag: Shell.installTag,
                                         lineHandler: progress)
        guard result.status == 0 else {
            throw PrismPackError.commandFailed("gem install \(name)", output: result.combined)
        }
    }
}
