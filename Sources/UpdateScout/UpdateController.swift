import Foundation
import AppKit

@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    nonisolated static let allSources: [any UpdateSource] = [
        HomebrewSource(), MASSource(), SystemUpdateSource(),
        CaskOracleSource(), ComponentsSource(), SparkleSource(), CustomSource()
    ]

    @Published var state = Store.load()
    @Published var isChecking = false
    /// Item ids with an install in flight → latest progress line.
    @Published var installing: [String: String] = [:]
    /// Item id → error message from a failed install.
    @Published var installErrors: [String: String] = [:]

    var visibleItems: [UpdateItem] {
        state.items.filter { !state.dismissed.contains($0.id) }
    }
    var badgeCount: Int { visibleItems.count }

    private var enabledSources: [any UpdateSource] {
        Self.allSources.filter { !Prefs.disabledSources.contains($0.id) }
    }

    // MARK: - Detection

    func checkNow() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            let (items, errors) = await Self.runDetection(sources: enabledSources)
            apply(items: items, errors: errors)
            isChecking = false
        }
    }

    /// Shared by the UI and the headless `--background-check` mode.
    /// `nonisolated` matters: headless mode blocks the main thread on a
    /// semaphore, so this must never require the main actor.
    nonisolated static func runDetection(sources: [any UpdateSource]) async -> ([UpdateItem], [String: String]) {
        await withTaskGroup(of: (String, Swift.Result<[UpdateItem], Error>).self) { group in
            for source in sources {
                group.addTask { (source.id, await Swift.Result { try await source.detect() }) }
            }
            var items: [UpdateItem] = []
            var errors: [String: String] = [:]
            for await (sourceID, result) in group {
                switch result {
                case .success(let found): items += found
                case .failure(let error): errors[sourceID] = error.localizedDescription
                }
            }
            // The same app can be found by several detectors (e.g. a Sparkle app
            // that also has a cask). Keep the row that can actually install it.
            let scriptedNames = Set(items.filter { $0.sourceID != "sparkle" }.map { $0.name.lowercased() })
            items.removeAll { $0.sourceID == "sparkle" && scriptedNames.contains($0.name.lowercased()) }
            let caskNames = Set(items.filter { $0.sourceID == "caskOracle" }.map { $0.name.lowercased() })
            items.removeAll { $0.sourceID == "custom" && caskNames.contains($0.name.lowercased()) }
            // An extension's parent app is often already listed by the oracle
            // or a brew cask — same cask token means the same update.
            let coveredTokens = Set(items.filter { $0.sourceID != "components" }.map(\.installToken))
            items.removeAll { $0.sourceID == "components" && coveredTokens.contains($0.installToken) }
            items.sort { ($0.sourceID, $0.name.lowercased()) < ($1.sourceID, $1.name.lowercased()) }
            return (items, errors)
        }
    }

    private func apply(items: [UpdateItem], errors: [String: String]) {
        var s = state
        s.items = items
        s.sourceErrors = errors
        s.lastCheck = Date()
        // Prune dismissals/notifications for items that no longer exist,
        // so a future re-appearance notifies again.
        let ids = Set(items.map(\.id))
        s.dismissed.formIntersection(ids)
        s.notified.formIntersection(ids)

        let fresh = items.filter { !s.notified.contains($0.id) && !s.dismissed.contains($0.id) }
        Notifier.notifyNewUpdates(fresh)
        s.notified.formUnion(fresh.map(\.id))

        state = s
        Store.save(s)
    }

    // MARK: - Install

    private var pendingInstalls: [UpdateItem] = []
    private var isProcessingQueue = false
    private var cancelRequested = false

    /// Cancel a queued or in-flight install. Kills the child process (and any
    /// pending auth prompt it spawned); the item stays in the list for retry.
    func cancelInstall(_ item: UpdateItem) {
        if installing[item.id] == "Queued…" {
            pendingInstalls.removeAll { $0.id == item.id }
            installing[item.id] = nil
            return
        }
        guard installing[item.id] != nil else { return }
        cancelRequested = true
        installing[item.id] = "Cancelling…"
        ProcessRegistry.shared.terminate(tag: "install")
    }

    func update(_ item: UpdateItem) {
        if !item.scriptedInstall {
            if let url = item.url.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
            return
        }
        guard installing[item.id] == nil else { return }
        // Installs run strictly one at a time: parallel `brew` processes fight
        // over Homebrew's cache lock and all but the first fail.
        installing[item.id] = "Queued…"
        installErrors[item.id] = nil
        pendingInstalls.append(item)
        processQueue()
    }

    private func processQueue() {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        Task {
            while !pendingInstalls.isEmpty {
                let item = pendingInstalls.removeFirst()
                guard let source = Self.allSources.first(where: { $0.id == item.sourceID }) else {
                    installing[item.id] = nil
                    continue
                }
                cancelRequested = false
                installing[item.id] = "Starting…"
                do {
                    try await source.install(item) { line in
                        Task { @MainActor in
                            if self.installing[item.id] != nil { self.installing[item.id] = line }
                        }
                    }
                    installing[item.id] = nil
                    var s = state
                    s.items.removeAll { $0.id == item.id }
                    state = s
                    Store.save(s)
                } catch {
                    installing[item.id] = nil
                    // A user-cancelled install isn't an error worth showing.
                    if !cancelRequested { installErrors[item.id] = error.localizedDescription }
                }
            }
            isProcessingQueue = false
            // Re-detect once the queue drains so completed/externally-updated
            // items fall off the list instead of going stale.
            checkNow()
        }
    }

    /// Queue every visible scripted update; they still run one at a time.
    func updateAll() {
        for item in visibleItems where item.scriptedInstall && installing[item.id] == nil {
            update(item)
        }
    }

    func dismiss(_ item: UpdateItem) {
        state.dismissed.insert(item.id)
        Store.save(state)
    }

    /// Re-read state from disk (a background check may have updated it).
    func reloadFromDisk() {
        guard installing.isEmpty, !isChecking else { return }
        state = Store.load()
    }
}

extension Swift.Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) }
        catch { self = .failure(error) }
    }
}
