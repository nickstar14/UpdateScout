import Foundation
import AppKit

@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    nonisolated static let allSources: [any UpdateSource] = [
        HomebrewSource(), MASSource(), SystemUpdateSource(),
        CaskOracleSource(), ComponentsSource(), SparkleSource(), CustomSource(),
        PythonSource(), NPMSource(), CargoSource(), GemSource(), EditorExtensionsSource(),
        GitHubReleasesSource()
    ]

    @Published var state = Store.load()
    @Published var isChecking = false { didSet { updateSpinner() } }
    /// Menu bar pulse frame while a check runs; 0 when idle.
    @Published private(set) var spinFrame = 0
    /// Item id → where its install is. Absent means idle.
    @Published var installStates: [String: InstallState] = [:]
    /// Failed installs that PrismPack knows how to fix: item id → (cask
    /// token, leftover staging folder). The card offers Repair for these.
    @Published var repairable: [String: (token: String, folder: URL)] = [:]
    /// Major upgrades waiting for the user to review them before they queue.
    @Published var review: ReviewRequest?
    /// The page the main window shows.
    @Published var page: Page = .updates

    /// The Installed tab's list, read when the tab first opens.
    /// The same app found twice, from the last check (Phase 7).
    @Published var duplicates: [DuplicateGroup] = []
    /// Installed casks Homebrew marks as updating themselves (both can update them).
    @Published var selfUpdatingCasks: Set<String> = []
    /// Separate beta casks by stable cask, for "Separate beta available".
    @Published var separateBetas: [String: [String]] = [:]
    @Published var showingAdoptionReview = false
    /// A chip Installed should select when it next shows ("duplicates").
    @Published var installedChipRequest: String?
    @Published private(set) var installed: [InstalledPackage] = []
    @Published private(set) var loadingInstalled = false

    func loadInstalled() {
        guard !loadingInstalled else { return }
        loadingInstalled = true
        Task {
            let list = await Inventory.load()
            // Here too, not only after a check, and before the list shows:
            // stale duplicates hid Homebrew's Flux right after a switch, and
            // Show Duplicates read "Nothing matches" (Nick, 2 Nov 2026).
            duplicates = await Duplicates.scan(records: await Duplicates.caskRecords())
            installed = list
            loadingInstalled = false
            // Something removed and then put back (outside PrismPack) offers
            // Uninstall again, not "Removed" until the next launch.
            for pkg in list {
                guard let removal = Removal(pkg) else { continue }
                for job in [removal.item, removal.zap?.item].compactMap({ $0 }) where installStates[job.id] == .done {
                    installStates[job.id] = nil
                }
            }
            if separateBetas.isEmpty, installed.contains(where: { $0.detail?.hasPrefix("cask ") == true }) {
                separateBetas = await CaskIndex.separateBetas()
            }
            MemoryRelief.run()
        }
    }

    struct ReviewRequest: Identifiable {
        let id = UUID()
        /// Major-version jumps the user must opt into, one by one.
        let majors: [UpdateItem]
        /// Ordinary updates that were requested alongside them.
        let others: [UpdateItem]
    }

    private init() {
        startWatching()
    }

    var visibleItems: [UpdateItem] {
        state.items.filter { !isIgnored($0) }
    }

    /// Hidden by any of the three ignore options.
    func isIgnored(_ item: UpdateItem) -> Bool { state.isHidden(item) }

    /// The listed update for an installed package, if there is one
    /// (Installed's status, Discover's Update button).
    func update(for pkg: InstalledPackage) -> UpdateItem? {
        state.items.first {
            $0.sectionID == pkg.sourceID && $0.name.caseInsensitiveCompare(pkg.name) == .orderedSame
        } ?? (pkg.appPath.flatMap { path in state.items.first { $0.appPath == path } })
    }

    /// Why a hidden item is hidden, for the Hidden section.
    func ignoreReason(_ item: UpdateItem) -> String {
        if state.ignoredApps.contains(item.appKey) { return "All updates hidden" }
        if item.isMajorUpgrade && state.ignoredMajors.contains(item.appKey) { return "Major upgrades hidden" }
        return "Hidden \(item.latestVersion)"
    }
    var visibleLeftovers: [KextBundle] {
        state.leftoverKexts.filter { !state.dismissed.contains($0.id) }
    }
    /// Items the user chose to ignore — still tracked so they can be brought back.
    var hiddenItems: [UpdateItem] {
        state.items.filter { isIgnored($0) }
    }
    var hiddenLeftovers: [KextBundle] {
        state.leftoverKexts.filter { state.dismissed.contains($0.id) }
    }

    func unhide(id: String) {
        state = Store.mutate { $0.dismissed.remove(id) }
    }

    /// "Unhide": undo whichever ignore options hide this item.
    func unhide(_ item: UpdateItem) {
        state = Store.mutate {
            $0.dismissed.remove(item.id)
            $0.ignoredApps.remove(item.appKey)
            $0.ignoredMajors.remove(item.appKey)
        }
    }

    /// "Hide all updates from this app".
    func ignoreApp(_ item: UpdateItem) {
        state = Store.mutate { $0.ignoredApps.insert(item.appKey) }
    }

    /// "Hide major upgrades only".
    func ignoreMajors(_ item: UpdateItem) {
        state = Store.mutate { $0.ignoredMajors.insert(item.appKey) }
    }

    func clearActivity() {
        state = Store.mutate { $0.activity.removeAll() }
    }

    func deleteActivity(_ ids: Set<UUID>) {
        state = Store.mutate { $0.activity.removeAll { ids.contains($0.id) } }
    }

    private func log(_ entry: ActivityEntry) {
        state = Store.mutate { $0.log(entry) }
    }
    /// Leftover id → progress text while a removal is in flight.
    @Published var removing: [String: String] = [:]
    @Published var removeErrors: [String: String] = [:]
    var badgeCount: Int { visibleItems.count }

    private var enabledSources: [any UpdateSource] {
        Self.allSources.filter { !Prefs.disabledSources.contains($0.id) }
    }

    // MARK: - Detection

    /// Set when a check is asked for while one is already running, so the
    /// request runs afterwards instead of being dropped (the re-check after an
    /// install queue drains relies on this).
    private var checkQueued = false

    func checkNow() {
        guard !isChecking else { checkQueued = true; return }
        isChecking = true
        Task {
            async let detection = Self.runDetection(sources: enabledSources)
            async let leftovers = KextInventory.partition().leftover
            async let adoption = Adoption.scanIfEnabled()
            async let caskRecords = Duplicates.caskRecords()
            let (items, errors) = await detection
            apply(items: items, errors: errors, leftovers: await leftovers)
            if let scan = await adoption {
                var digest: [AdoptionCandidate] = []
                state = Store.mutate { digest = Adoption.merge(scan, into: &$0) }
                Notifier.notifyAdoptionDigest(digest)
            }
            let records = await caskRecords
            duplicates = await Duplicates.scan(records: records)
            selfUpdatingCasks = Set(records.filter(\.autoUpdates).map(\.token))
            isChecking = false
            if checkQueued {
                checkQueued = false
                checkNow()
            }
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
            // Several sources can describe the same installed app (a Homebrew-
            // managed cask and a custom_sources entry pointing at the same
            // bundle). Keep one row per app, preferring the source that
            // actually manages the install.
            let priority = ["homebrew": 0, "mas": 1, "caskOracle": 2, "sparkle": 3, "custom": 4, "components": 5]
            var seenApps: [String: Int] = [:]
            items.sort { (priority[$0.sourceID] ?? 9) < (priority[$1.sourceID] ?? 9) }
            items = items.filter { item in
                guard let app = item.appPath else { return true }
                if seenApps[app] != nil { return false }
                seenApps[app] = 1
                return true
            }
            items.sort { ($0.sourceID, $0.name.lowercased()) < ($1.sourceID, $1.name.lowercased()) }
            // Fill in changelogs for items whose source has none (Homebrew).
            items = await GitHubNotes.enrich(items)
            return (items, errors)
        }
    }

    private func apply(items: [UpdateItem], errors: [String: String], leftovers: [KextBundle]) {
        var fresh: [UpdateItem] = []
        state = Store.mutate { s in
            fresh = Self.merge(items: items, errors: errors, leftovers: leftovers, into: &s)
        }
        Notifier.notifyNewUpdates(fresh, waiting: state.items.filter { !state.isHidden($0) })
        maybeAutoUpdate()
    }

    nonisolated static func sourceName(_ id: String) -> String {
        source(for: id)?.displayName ?? id
    }

    /// The source that installs an item: one of the update sources, or
    /// Discover's installer (not listed in Settings, never detects).
    nonisolated static func source(for id: String) -> (any UpdateSource)? {
        allSources.first { $0.id == id }
            ?? (id == "discover" ? DiscoverInstaller() : id == "remove" ? Remover() : id == "adopt" ? Adopter() : nil)
    }

    /// Fold one check's results into the stored state. Shared with the
    /// headless background check; returns the items not notified about yet.
    nonisolated static func merge(items: [UpdateItem], errors: [String: String],
                                  leftovers: [KextBundle], into s: inout Store.State) -> [UpdateItem] {
        s.items = items
        s.sourceErrors = errors
        s.leftoverKexts = leftovers
        s.lastCheck = Date()
        s.checkStartedAt = nil
        // Prune dismissals/notifications for items that no longer exist,
        // so a future re-appearance notifies again.
        let ids = Set(items.map(\.id)).union(leftovers.map(\.id))
        s.dismissed.formIntersection(ids)
        s.notified.formIntersection(ids)

        let fresh = items.filter { !s.notified.contains($0.id) && !s.dismissed.contains($0.id) }
        s.notified.formUnion(fresh.map(\.id))
        if !fresh.isEmpty {
            let names = Set(fresh.map { sourceName($0.sourceID) }).sorted().joined(separator: ", ")
            s.log(ActivityEntry(kind: .checked,
                                title: fresh.count == 1 ? "Check found 1 new update" : "Check found \(fresh.count) new updates",
                                detail: names))
        }
        return fresh
    }

    // MARK: - Install

    private var pendingInstalls: [UpdateItem] = []
    /// Lanes held by each running install, keyed by item id.
    private var runningLanes: [String: Set<String>] = [:]
    private var busyLanes: Set<String> { runningLanes.values.reduce(into: []) { $0.formUnion($1) } }
    /// Running installs that may show a password prompt.
    private var runningAdmin: Set<String> = []
    /// Queued items already checked for needing admin, and those that do.
    private var classified: Set<String> = []
    private var adminItems: Set<String> = []
    private var classifying = false
    /// Queued Homebrew items whose download already ran in a shared `brew fetch`.
    private var prefetched: Set<String> = []
    /// Set while a batch is in flight, so the list is re-checked once it drains.
    private var batchActive = false
    /// Running installs by item id, so Cancel can stop work that isn't a
    /// child process (a Sparkle download).
    private var runningInstalls: [String: Task<Void, Error>] = [:]

    /// True while an item is queued or running (not failed or done).
    func isBusy(_ item: UpdateItem) -> Bool { installStates[item.id]?.isActive == true }

    /// Cancel a queued or in-flight install. Kills that item's child processes
    /// (and any pending auth prompt they spawned); other installs carry on and
    /// the item stays in the list for retry.
    func cancelInstall(_ item: UpdateItem) {
        // Still waiting (queued, or sharing the batch's brew download).
        if pendingInstalls.contains(where: { $0.id == item.id }) {
            pendingInstalls.removeAll { $0.id == item.id }
            installStates[item.id] = nil
            forget(item)
            if passwordRequest != nil, !pendingInstalls.contains(where: { adminItems.contains($0.id) }) {
                passwordRequest = nil
            }
            return
        }
        guard isBusy(item), let task = runningInstalls[item.id] else { return }
        installStates[item.id] = .cancelling
        task.cancel()
        ProcessRegistry.shared.terminate(tag: Self.processTag(item))
    }

    private static func processTag(_ item: UpdateItem) -> String { "install|\(item.id)" }

    /// Fix a cask stuck on a half-finished upgrade: move the leftover staging
    /// folder to the Trash (recoverable, not deleted), then reinstall.
    func repair(_ item: UpdateItem) {
        guard let (token, folder) = repairable[item.id] else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            // Already gone (fixed some other way) — just retry.
            repairable[item.id] = nil
            BrewRepair.markForReinstall(token)
            update(item)
            return
        }
        installStates[item.id] = .installing("Moving the leftover upgrade folder to the Trash…")
        NSWorkspace.shared.recycle([folder]) { _, error in
            Task { @MainActor in
                self.installStates[item.id] = nil
                if let error {
                    self.installStates[item.id] = .failed("Couldn't move \(folder.lastPathComponent) to the Trash: \(error.localizedDescription)")
                    return
                }
                self.repairable[item.id] = nil
                BrewRepair.markForReinstall(token)
                self.update(item)
            }
        }
    }

    /// Leftovers ticked in the uninstall window, by removal job id. They
    /// move only once the app itself is in the Trash.
    private var pendingLeftovers: [String: [Leftovers.Found]] = [:]
    /// What happened to them, for the uninstall window's result.
    @Published var leftoverOutcomes: [String: Leftovers.Outcome] = [:]

    /// Queue a removal. `updateID` is the update row it came from, if any,
    /// which goes once the removal succeeds. `leftovers` move after it.
    func uninstall(_ removal: Removal, updateID: String? = nil, leftovers: [Leftovers.Found] = []) {
        let job = removal.item
        removalUpdates[job.id] = updateID
        pendingLeftovers[job.id] = leftovers.isEmpty ? nil : leftovers
        leftoverOutcomes[job.id] = nil
        update(job)
    }

    /// "Try Again" and Orphaned App Files: their own Activity line.
    func logLeftovers(of name: String, _ outcome: Leftovers.Outcome) {
        guard !outcome.moved.isEmpty else { return }
        state = Store.mutate {
            $0.log(ActivityEntry(kind: .removed, title: "Leftovers of \(name)",
                                 detail: Self.leftoverSummary(outcome.moved) + ", moved to the Trash"))
        }
    }

    nonisolated static func leftoverSummary(_ moved: [Leftovers.Found]) -> String {
        let size = ByteCountFormatter.string(fromByteCount: moved.reduce(0) { $0 + $1.size }, countStyle: .file)
        return "\(moved.count) leftover\(moved.count == 1 ? "" : "s") (\(size))"
    }

    /// Update rows a running removal clears when it succeeds.
    private var removalUpdates: [String: String] = [:]

    private func finishRemoval(_ job: UpdateItem, seconds: Int) {
        let updateID = removalUpdates.removeValue(forKey: job.id)
        let removal = Removal(token: job.installToken, name: job.name)
        let leftovers = pendingLeftovers.removeValue(forKey: job.id) ?? []
        state = Store.mutate {
            if let updateID { $0.items.removeAll { $0.id == updateID } }
            if removal.kind == "app" { $0.items.removeAll { $0.appPath == removal.target } }
        }
        // Finished Discover installs would still say Installed.
        for (id, state) in installStates where id.hasPrefix("discover|") && state == .done { installStates[id] = nil }
        loadInstalled()
        Task {
            // The app is in the Trash: now its leftovers, then one Activity line.
            let outcome = leftovers.isEmpty ? Leftovers.Outcome() : await Leftovers.moveToTrash(leftovers)
            if !leftovers.isEmpty { leftoverOutcomes[job.id] = outcome }
            // Says whether Homebrew's cleanup list ran, and what else moved.
            let detail = DiscoverInstaller.sourceTitle(of: job.installToken)
                + (job.installToken.hasPrefix("zap:") ? ", with Homebrew's cleanup list" : "")
                + (outcome.moved.isEmpty ? "" : (job.installToken.hasPrefix("zap:") ? " and " : ", with ") + Self.leftoverSummary(outcome.moved))
            state = Store.mutate {
                $0.log(ActivityEntry(kind: .removed, title: job.name, detail: detail,
                                     itemID: job.id, sourceID: job.sourceID, seconds: seconds))
            }
        }
    }

    // MARK: - Adoption and duplicates (Phase 7)

    /// Queue one adoption job. Never runs on its own: only from a click.
    func adopt(_ candidate: AdoptionCandidate) {
        let action = candidate.method == .inPlace ? "adopt" : "replace"
        update(Adopter.Job(action: action, cask: candidate.token, appPath: candidate.appPath).item(name: candidate.name))
    }

    /// "Adopt all safe ones": only Recommended, in-place, password-free.
    func adoptAllSafe() {
        for candidate in state.visibleAdoptions where candidate.isSafe { adopt(candidate) }
    }

    /// Replace an App Store copy with Homebrew's (only from a click).
    func switchToHomebrew(cask: String, appPath: String, name: String) {
        update(Adopter.Job(action: "switch", cask: cask, appPath: appPath).item(name: name))
    }

    /// "Stop managing with Homebrew" for an adopted app, or a duplicate's
    /// "Stop Homebrew tracking it". Removes Homebrew's record only.
    /// Copy path → "Moving…" or why it wasn't moved, for the duplicates pop-up.
    @Published var duplicateMoves: [String: String] = [:]

    /// The Homebrew cask whose app is this copy, if any.
    func cask(at path: String) -> String? {
        installed.first { $0.appPath?.lowercased() == path.lowercased() && $0.detail?.hasPrefix("cask ") == true }
            .flatMap { $0.detail.map { String($0.dropFirst(5)) } }
    }

    /// Moves one copy of a duplicated app to the Trash, keeping `kept`.
    /// The safety checks run again right here, so a copy that was opened or
    /// a kept copy that went missing since the pop-up drew stops it. When
    /// Homebrew installed this copy, its record goes too, so it doesn't put
    /// the app back on its next update.
    func moveDuplicateCopy(_ path: String, keeping kept: String, name: String) {
        if let why = Duplicates.refusal(moving: path, keeping: kept) {
            duplicateMoves[path] = why
            return
        }
        let cask = cask(at: path)
        duplicateMoves[path] = "Moving…"
        Task {
            do {
                _ = try await Adopter.trash(path, name: name)
                // macOS has reported a Trash move as done while the folder stayed.
                guard !FileManager.default.fileExists(atPath: path) else {
                    throw PrismPackError.commandFailed("Move to Trash", output: "macOS didn't move \(path).")
                }
                var detail = "Copy in \(Duplicates.folder(of: path)) moved to the Trash"
                if let cask {
                    do { try await Adopter.removeRecord(cask); detail += "; Homebrew stopped tracking it" }
                    catch { detail += "; Homebrew's record stayed (\(error.localizedDescription))" }
                }
                state = Store.mutate { $0.log(ActivityEntry(kind: .removed, title: name, detail: detail)) }
                duplicateMoves[path] = nil
                loadInstalled()
            } catch {
                duplicateMoves[path] = error.localizedDescription
            }
        }
    }

    /// Group id → progress or why it stopped, for "Use Homebrew's copy".
    @Published var homebrewSwitches: [String: String] = [:]

    /// "Use Homebrew's copy" (Nick, 2 Nov 2026): quit any other copy that's
    /// open, move every other copy to the Trash, and open Homebrew's copy
    /// in its place if one was open. Nothing changes if a copy won't quit;
    /// if Homebrew's copy won't open, the moved copies are put back.
    func useHomebrewCopy(_ group: DuplicateGroup, brewPath: String) {
        let others = ([group.keep] + group.extras).filter { $0 != brewPath }
        for path in others {
            if let why = Duplicates.refusal(moving: path, keeping: brewPath, allowOpen: true) {
                homebrewSwitches[group.id] = why
                return
            }
        }
        let name = group.name
        homebrewSwitches[group.id] = "Starting…"
        Task {
            let open = others.filter(Duplicates.isRunning)
            if !open.isEmpty {
                homebrewSwitches[group.id] = "Quitting \(name)…"
                for app in NSWorkspace.shared.runningApplications {
                    if let url = app.bundleURL, open.contains(where: { $0.lowercased() == url.standardizedFileURL.path.lowercased() }) {
                        app.terminate()
                    }
                }
                for _ in 0..<20 where open.contains(where: Duplicates.isRunning) {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if open.contains(where: Duplicates.isRunning) {
                    homebrewSwitches[group.id] = "\(name) didn't quit, so nothing was changed. Quit it yourself, then try again."
                    return
                }
            }
            var moved: [(from: String, to: URL)] = []
            do {
                for path in others {
                    homebrewSwitches[group.id] = "Moving the copy in \(Duplicates.folder(of: path)) to the Trash…"
                    // Checked again right before each move.
                    if let why = Duplicates.refusal(moving: path, keeping: brewPath) {
                        throw PrismPackError.commandFailed("Use Homebrew's copy", output: why)
                    }
                    let to = try await Adopter.trash(path, name: name)
                    guard !FileManager.default.fileExists(atPath: path) else {
                        throw PrismPackError.commandFailed("Move to Trash", output: "macOS didn't move \(path).")
                    }
                    moved.append((path, to))
                }
                if !open.isEmpty {
                    homebrewSwitches[group.id] = "Opening Homebrew's copy…"
                    let config = NSWorkspace.OpenConfiguration()
                    _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: brewPath), configuration: config)
                    for _ in 0..<20 where !Duplicates.isRunning(brewPath) {
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                    guard Duplicates.isRunning(brewPath) else {
                        throw PrismPackError.commandFailed("Use Homebrew's copy", output: "Homebrew's copy of \(name) didn't open.")
                    }
                }
                let folders = moved.map { Duplicates.folder(of: $0.from) }.joined(separator: ", ")
                state = Store.mutate {
                    $0.log(ActivityEntry(kind: .removed, title: name,
                                         detail: "Switched to Homebrew's copy; the copy in \(folders) moved to the Trash"))
                }
                homebrewSwitches[group.id] = nil
                loadInstalled()
            } catch {
                // Put back whatever was moved.
                var restored = true
                for item in moved.reversed() where !(await Adopter.restore(item.to, to: item.from)) { restored = false }
                homebrewSwitches[group.id] = error.localizedDescription
                    + (moved.isEmpty ? "" : restored ? " The moved copy was put back." : " Put the moved copy back from the Trash.")
                if !open.isEmpty, restored, let first = open.first {
                    _ = try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: first),
                                                                       configuration: NSWorkspace.OpenConfiguration())
                }
                loadInstalled()
            }
        }
    }

    func stopManaging(cask: String, appPath: String, name: String) {
        update(Adopter.Job(action: "untrack", cask: cask, appPath: appPath).item(name: name))
    }

    /// The queue item for a candidate, for its progress and errors.
    func adoptionJob(_ candidate: AdoptionCandidate) -> UpdateItem {
        let action = candidate.method == .inPlace ? "adopt" : "replace"
        return Adopter.Job(action: action, cask: candidate.token, appPath: candidate.appPath).item(name: candidate.name)
    }

    func snoozeAdoption(_ candidate: AdoptionCandidate) {
        state = Store.mutate { $0.adoptionSnoozed[candidate.hideKey] = Date().addingTimeInterval(Adoption.snoozeInterval) }
    }

    func neverAdopt(_ candidate: AdoptionCandidate) {
        state = Store.mutate { $0.adoptionNever.insert(candidate.hideKey) }
    }

    func unhideAdoption(_ candidate: AdoptionCandidate) {
        state = Store.mutate {
            $0.adoptionNever.remove(candidate.hideKey)
            $0.adoptionSnoozed[candidate.hideKey] = nil
        }
    }

    /// The shown candidate for an installed app, for Installed's "Can adopt".
    func adoptionCandidate(at path: String?) -> AdoptionCandidate? {
        guard let path, Prefs.adoptionEnabled else { return nil }
        return state.visibleAdoptions.first { $0.appPath.lowercased() == path.lowercased() && $0.verdict != .notBetter }
    }

    /// The duplicate group an app belongs to, as the copy kept or an extra.
    func duplicateGroup(for path: String) -> DuplicateGroup? {
        // Case-blind: a cask's app found by token can differ in case from the folder.
        let key = path.lowercased()
        return duplicates.first { $0.keep.lowercased() == key || $0.extras.contains { $0.lowercased() == key } }
    }

    /// Snoozed or turned-down candidates, for the Hidden section.
    var hiddenAdoptions: [AdoptionCandidate] {
        state.adoptionCandidates.filter { state.isAdoptionHidden($0) }
    }

    private func finishAdoption(_ job: UpdateItem, seconds: Int) {
        guard let parsed = Adopter.Job(token: job.installToken) else { return }
        let bundleID = Adoption.facts(at: parsed.appPath)?.bundleID
        state = Store.mutate { s in
            s.adoptionCandidates.removeAll { $0.appPath == parsed.appPath }
            s.storeSwitches[parsed.appPath] = nil
            if parsed.action == "untrack" {
                s.adopted[parsed.cask] = nil
                s.adoptedBehind[parsed.cask] = nil
                s.log(ActivityEntry(kind: .removed, title: job.name,
                                    detail: "Homebrew stopped managing it (cask \(parsed.cask)). The app stays.",
                                    itemID: job.id, sourceID: job.sourceID, seconds: seconds))
            } else {
                s.adopted[parsed.cask] = bundleID ?? ""
                s.log(ActivityEntry(kind: .adopted, title: job.name,
                                    detail: ["adopt": "Adopted in place", "switch": "Moved from the App Store"][parsed.action, default: "Replaced"]
                                        + " · cask \(parsed.cask)",
                                    itemID: job.id, sourceID: job.sourceID, seconds: seconds))
            }
        }
        duplicates.removeAll { if case .twoStores(let cask) = $0.kind { return cask == parsed.cask }; return false }
        loadInstalled()
    }

    /// The Installed entry an update row is about, for its Uninstall button.
    func installedPackage(for item: UpdateItem) -> InstalledPackage? {
        if let path = item.appPath, let pkg = installed.first(where: { $0.appPath == path }) { return pkg }
        return installed.first { $0.sourceID == item.sectionID && $0.name.caseInsensitiveCompare(item.name) == .orderedSame }
    }

    func update(_ item: UpdateItem) {
        if !item.scriptedInstall {
            if let url = item.url.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
            return
        }
        guard !isBusy(item) else { return }
        installStates[item.id] = .queued
        repairable[item.id] = nil
        pendingInstalls.append(item)
        startReadyInstalls()
    }

    /// The lane an install runs in. One install at a time per lane, because
    /// package managers hold locks: every `brew` caller shares one lane
    /// (custom commands may call brew too), and each other manager has its own.
    nonisolated static func lane(for sourceID: String) -> String {
        switch sourceID {
        case "homebrew", "caskOracle", "components", "custom", "adopt": return "brew"
        default: return sourceID
        }
    }

    /// Every lane an install holds: its own, plus, for a package manager
    /// (Tools), the lane of the packages it manages.
    nonisolated static func lanes(for item: UpdateItem) -> Set<String> {
        if item.sourceID == "discover" || item.sourceID == "remove" {
            // Installing or removing a tool blocks its packages' lane too.
            var lanes: Set<String> = [DiscoverInstaller.lane(of: item.installToken)]
            if item.installToken.hasPrefix("formula:"),
               let extra = Tools.packageLane(ofFormula: String(item.installToken.dropFirst("formula:".count))) {
                lanes.insert(extra)
            }
            return lanes
        }
        var lanes: Set<String> = [lane(for: item.sourceID)]
        if let tool = Tools.formula(of: item), let extra = Tools.packageLane(ofFormula: tool) {
            lanes.insert(extra)
        }
        return lanes
    }

    /// Start every queued install that may run now: up to the "Update at once"
    /// limit, one per lane. Items that need admin wait for the password sheet.
    /// Without a batch password, only one install that may prompt runs at a
    /// time, so two password dialogs never appear together.
    private func startReadyInstalls() {
        if classifying { return }
        let unclassified = pendingInstalls.filter { !classified.contains($0.id) }
        if !unclassified.isEmpty { classify(unclassified); return }
        requestPasswordIfNeeded()
        if prefetchBrewDownloads() { return }
        let brokered = PasswordBroker.shared.isActive
        var index = 0
        while index < pendingInstalls.count, runningLanes.count < Prefs.updateConcurrency {
            let item = pendingInstalls[index]
            guard let source = Self.source(for: item.sourceID) else {
                pendingInstalls.remove(at: index)
                installStates[item.id] = nil
                continue
            }
            let lanes = Self.lanes(for: item)
            let admin = !brokered && Self.mayPrompt(item, needsAdmin: adminItems.contains(item.id))
            if !busyLanes.isDisjoint(with: lanes) || (admin && !runningAdmin.isEmpty)
                || (passwordRequest != nil && adminItems.contains(item.id)) {
                index += 1
                continue
            }
            pendingInstalls.remove(at: index)
            runningLanes[item.id] = lanes
            if admin { runningAdmin.insert(item.id) }
            batchActive = true
            run(item, with: source)
        }
        if batchActive, pendingInstalls.isEmpty, runningLanes.isEmpty {
            batchActive = false
            PasswordBroker.shared.stop()
            // Re-detect once the queue drains so completed/externally-updated
            // items fall off the list instead of going stale.
            checkNow()
        }
    }

    /// Could this install show a password dialog? Known pkg installers, plus
    /// tools that may fall back to sudo with no warning (mas, custom commands,
    /// Sparkle swaps, any cask).
    nonisolated static func mayPrompt(_ item: UpdateItem, needsAdmin: Bool) -> Bool {
        needsAdmin || ["mas", "custom", "sparkle", "caskOracle", "components"].contains(item.sourceID)
            || item.installToken.hasPrefix("cask:") || item.installToken.hasPrefix("zap:")
    }

    private func forget(_ item: UpdateItem) {
        prefetched.remove(item.id)
        classified.remove(item.id)
        adminItems.remove(item.id)
    }

    /// Work out which queued items need admin before any of them start. Casks
    /// are looked up in one `brew info` call; other sources answer directly.
    private func classify(_ items: [UpdateItem]) {
        classifying = true
        Task {
            let casks = items.compactMap(HomebrewSource.caskToken(of:))
            await HomebrewSource.lookUpInstallerCasks(casks)
            for item in items {
                classified.insert(item.id)
                if Self.source(for: item.sourceID)?.needsAdmin(item) == true {
                    adminItems.insert(item.id)
                }
            }
            classifying = false
            startReadyInstalls()
        }
    }

    // MARK: Password once per batch

    struct PasswordRequest: Identifiable {
        let id = UUID()
        let count: Int
    }
    /// Set while the password sheet should show.
    @Published var passwordRequest: PasswordRequest? { didSet { updateSpinner() } }

    private func requestPasswordIfNeeded() {
        guard Prefs.askPasswordOncePerBatch, passwordRequest == nil, !PasswordBroker.shared.isActive else { return }
        let waiting = pendingInstalls.filter { adminItems.contains($0.id) }.count
        guard waiting > 0 else { return }
        passwordRequest = PasswordRequest(count: waiting)
        UpdatesWindow.shared.show()
        // Bounce the Dock icon until the user comes to it (Nick, 30 Oct 2026).
        // Only possible while the Dock icon is shown.
        NSApp.requestUserAttention(.criticalRequest)
    }

    /// The sheet's Authorize. False when the password is wrong.
    func authorize(password: String) async -> Bool {
        guard await PasswordBroker.shared.start(password: password) else { return false }
        passwordRequest = nil
        startReadyInstalls()
        return true
    }

    /// The sheet's "Skip those N": leave them as "Needs admin" with a Retry.
    func skipAdminItems() {
        let skipped = pendingInstalls.filter { adminItems.contains($0.id) }
        pendingInstalls.removeAll { adminItems.contains($0.id) }
        for item in skipped {
            installStates[item.id] = .failed("Needs admin")
            forget(item)
        }
        state = Store.mutate { s in
            for item in skipped {
                s.log(ActivityEntry(kind: .skipped, title: item.logTitle,
                                    detail: "\(Self.sourceName(item.sourceID)) · needed admin, password skipped",
                                    itemID: item.id, sourceID: item.sourceID))
            }
        }
        passwordRequest = nil
        startReadyInstalls()
    }

    /// Homebrew downloads in parallel inside one command, so before the brew
    /// lane upgrades anything it runs one `brew fetch` for every queued
    /// formula and cask, then the upgrades go one at a time. Returns true while
    /// that fetch holds the lane. A failed fetch is harmless: each upgrade
    /// then downloads for itself.
    private func prefetchBrewDownloads() -> Bool {
        guard !busyLanes.contains("brew") else { return false }
        let batch = pendingInstalls.filter { Self.lane(for: $0.sourceID) == "brew" && !prefetched.contains($0.id) }
        var formulae: [String] = [], casks: [String] = []
        for item in batch {
            switch item.sourceID {
            case "homebrew":
                let parts = item.installToken.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                if parts[0] == "cask" { casks.append(parts[1]) } else { formulae.append(parts[1]) }
            case "caskOracle", "components":
                casks.append(item.installToken)
            default:
                continue
            }
        }
        prefetched.formUnion(batch.map(\.id))
        guard formulae.count + casks.count > 1, let brew = HomebrewSource.brewPath else { return false }

        let lane = "prefetch"
        runningLanes[lane] = ["brew"]
        batchActive = true
        for item in batch where Self.lane(for: item.sourceID) == "brew" && item.sourceID != "custom" {
            installStates[item.id] = .downloading(percent: nil, line: "Downloading with the rest of the batch…")
        }
        Task {
            if !formulae.isEmpty { _ = try? await Shell.run(brew, ["fetch", "--formula"] + formulae, tag: lane) }
            if !casks.isEmpty { _ = try? await Shell.run(brew, ["fetch", "--cask"] + casks, tag: lane) }
            for item in batch where installStates[item.id]?.isActive == true && installStates[item.id] != .cancelling {
                installStates[item.id] = .queued
            }
            runningLanes[lane] = nil
            startReadyInstalls()
        }
        return true
    }

    /// The last lines each running install printed, for Show log.
    private var outputTails: [String: [String]] = [:]

    /// Long moves in progress, by job id (MoveProgress).
    @Published var moveProgress: [String: MoveProgress] = [:]

    /// What each running install is doing, in words and (when measured)
    /// numbers, for the tiles.
    @Published var installProgress: [String: InstallProgress] = [:]

    private func run(_ item: UpdateItem, with source: any UpdateSource) {
        installStates[item.id] = .installing("Starting…")
        installProgress[item.id] = InstallProgress()
        outputTails[item.id] = []
        if let plan = MoveProgress.plan(for: item) {
            moveProgress[item.id] = plan
            MoveProgressWindow.shared.show(jobID: item.id)
        }
        let started = Date()
        let automatic = autoPending.contains(item.id)
        let how = automatic ? "Automatically · " : ""
        let install = Task {
            try await Shell.$installTag.withValue(Self.processTag(item)) {
              try await Shell.$noPasswordPrompt.withValue(automatic) {
                try await source.install(item) { line in
                    Task { @MainActor in
                        self.moveProgress[item.id]?.take(line)
                        if var progress = self.installProgress[item.id] {
                            progress.take(line)
                            if progress != self.installProgress[item.id] { self.installProgress[item.id] = progress }
                        }
                        // Step markers are for the progress view only.
                        if line.hasPrefix("§") { return }
                        self.outputTails[item.id, default: []].append(line)
                        if self.outputTails[item.id]!.count > 40 { self.outputTails[item.id]!.removeFirst() }
                        guard let current = self.installStates[item.id], current.isActive,
                              current != .cancelling else { return }
                        self.installStates[item.id] = InstallState(progressLine: line)
                    }
                }
              }
            }
        }
        runningInstalls[item.id] = install
        Task {
            do {
                try await install.value
                installStates[item.id] = .done
                moveProgress[item.id]?.finished = true
                let seconds = Int(Date().timeIntervalSince(started).rounded())
                if item.sourceID == "remove" {
                    finishRemoval(item, seconds: seconds)
                } else if item.sourceID == "adopt" {
                    finishAdoption(item, seconds: seconds)
                } else if item.sourceID == "discover" {
                    // A finished removal of the same thing would still say Removed.
                    for (id, done) in installStates where id.hasPrefix("remove|") && done == .done { installStates[id] = nil }
                    state = Store.mutate {
                        $0.log(ActivityEntry(kind: .installed, title: item.logTitle,
                                             detail: DiscoverInstaller.sourceTitle(of: item.installToken),
                                             itemID: item.id, sourceID: item.sourceID, seconds: seconds))
                    }
                    loadInstalled()
                } else {
                    state = Store.mutate {
                        $0.items.removeAll { $0.id == item.id }
                        $0.log(ActivityEntry(kind: .updated, title: "\(item.name) \(item.installedVersion) to \(item.latestVersion)",
                                             detail: how + Self.sourceName(item.sourceID), itemID: item.id,
                                             sourceID: item.sourceID, seconds: seconds))
                    }
                }
                autoFinished(item, ok: true)
            } catch {
                // A user-cancelled install isn't an error worth showing.
                installStates[item.id] = install.isCancelled ? nil : .failed(error.localizedDescription)
                moveProgress[item.id]?.finished = true
                moveProgress[item.id]?.failure = install.isCancelled ? "Cancelled." : error.localizedDescription
                log(install.isCancelled
                    ? ActivityEntry(kind: .cancelled, title: item.logTitle,
                                    detail: Self.sourceName(item.sourceID), itemID: item.id, sourceID: item.sourceID)
                    : ActivityEntry(kind: .failed, title: item.logTitle,
                                    detail: "\(how)\(Self.sourceName(item.sourceID)) · \(error.localizedDescription)",
                                    itemID: item.id, sourceID: item.sourceID,
                                    log: (outputTails[item.id] ?? []).joined(separator: "\n")))
                if case PrismPackError.staleCaskUpgrade(let token, let folder) = error {
                    repairable[item.id] = (token, folder)
                }
                autoFinished(item, ok: false)
            }
            runningInstalls[item.id] = nil
            outputTails[item.id] = nil
            runningLanes[item.id] = nil
            runningAdmin.remove(item.id)
            forget(item)
            startReadyInstalls()
        }
    }

    /// What the Update buttons call. A major-version jump goes through the
    /// review sheet first; everything else queues straight away.
    func requestUpdate(_ item: UpdateItem) {
        if item.scriptedInstall && item.isMajorUpgrade {
            review = ReviewRequest(majors: [item], others: [])
        } else {
            update(item)
        }
    }

    /// Queue every visible scripted update; lanes decide what runs together.
    func updateAll() {
        queueAll(visibleItems.filter { $0.scriptedInstall && !isPinned($0) && !isBusy($0) })
    }

    /// Queue every installable update in one window section.
    func updateAll(sectionID: String) {
        queueAll(visibleItems.filter {
            $0.sectionID == sectionID && $0.scriptedInstall && !isPinned($0) && !isBusy($0)
        })
    }

    /// Major upgrades are often paid, so a bulk update never includes them
    /// without the user reviewing each one.
    private func queueAll(_ items: [UpdateItem]) {
        let majors = items.filter(\.isMajorUpgrade)
        let others = items.filter { !$0.isMajorUpgrade }
        if majors.isEmpty {
            others.forEach(update)
        } else {
            review = ReviewRequest(majors: majors, others: others)
        }
    }

    /// The review sheet's answer: queue the majors the user included, plus the
    /// ordinary updates that came with them.
    func finishReview(including majors: [UpdateItem]) {
        guard let request = review else { return }
        review = nil
        (request.others + majors).forEach(update)
    }

    func dismiss(_ item: UpdateItem) {
        state = Store.mutate { $0.dismissed.insert(item.id) }
    }

    // MARK: - Leftover kexts

    func dismissLeftover(_ kext: KextBundle) {
        state = Store.mutate { $0.dismissed.insert(kext.id) }
    }

    /// Delete a leftover kext (admin prompt). Runs through the install queue's
    /// serialisation implicitly by being quick; there's nothing to download.
    func removeLeftover(_ kext: KextBundle) {
        guard removing[kext.id] == nil else { return }
        removing[kext.id] = "Starting…"
        removeErrors[kext.id] = nil
        Task {
            do {
                try await KextInventory.remove(kext) { line in
                    Task { @MainActor in
                        if self.removing[kext.id] != nil { self.removing[kext.id] = line }
                    }
                }
                removing[kext.id] = nil
                state = Store.mutate { $0.leftoverKexts.removeAll { $0.id == kext.id } }
            } catch {
                removing[kext.id] = nil
                removeErrors[kext.id] = error.localizedDescription
            }
        }
    }

    /// Re-read state from disk (a background check may have updated it).
    /// Every write goes through Store.mutate, so the file is always at least
    /// as new as what's in memory and reloading is safe at any time.
    func reloadFromDisk() {
        let fresh = Store.load()
        if fresh != state { state = fresh; maybeAutoUpdate() }
        updateSpinner()
    }

    // MARK: - Automatic updates

    /// Bumped when a pin or per-app rule changes, so views redraw.
    @Published private(set) var autoRulesVersion = 0
    /// Items queued by an automatic run, and how that run is going.
    private var autoPending: Set<String> = []
    private var autoUpdated: [String] = []
    private var autoFailed: [String] = []
    private var autoStarting = false

    func isPinned(_ item: UpdateItem) -> Bool { AutoUpdate.isPinned(item) }

    func setPinned(_ item: UpdateItem, _ pinned: Bool) {
        var all = AutoUpdate.pinned
        if pinned { all.insert(item.appKey) } else { all.remove(item.appKey) }
        AutoUpdate.pinned = all
        autoRulesVersion += 1
    }

    func autoRule(_ item: UpdateItem) -> AutoUpdate.Rule? { AutoUpdate.rule(for: item.appKey) }

    func setAutoRule(_ rule: AutoUpdate.Rule?, for item: UpdateItem) {
        AutoUpdate.setRule(rule, for: item.appKey)
        autoRulesVersion += 1
    }

    /// Why this update won't install on its own (for its card), or nil.
    func autoBlocker(_ item: UpdateItem) -> String? {
        AutoUpdate.blocker(item, hidden: isIgnored(item), pinned: isPinned(item),
                           needsAdmin: Self.source(for: item.sourceID)?.needsAdmin(item) ?? true,
                           appOpen: false, rule: autoRule(item))
    }

    /// After a check lands: queue what automatic updates allow, through the
    /// normal queue. The background agent leaves this to the app while it runs.
    func maybeAutoUpdate() {
        guard autoPending.isEmpty, !autoStarting, AutoUpdate.isActive, AutoUpdate.isDue() else { return }
        autoStarting = true
        Task {
            defer { autoStarting = false }
            if AutoUpdate.unmeteredOnly, await AutoUpdate.onMeteredNetwork() { return }
            // The agent may be mid-run from before the app opened.
            guard let lock = AutoUpdate.acquireLock() else { return }
            AutoUpdate.releaseLock(lock)
            await HomebrewSource.lookUpInstallerCasks(state.items.compactMap(HomebrewSource.caskToken(of:)))
            let items = state.items.filter { item in
                !isBusy(item) && AutoUpdate.blocker(
                    item, hidden: isIgnored(item), pinned: isPinned(item),
                    needsAdmin: Self.source(for: item.sourceID)?.needsAdmin(item) ?? true,
                    appOpen: AutoUpdate.isOpen(item), rule: autoRule(item)) == nil
            }
            AutoUpdate.lastRun = Date()
            guard !items.isEmpty else { return }
            autoPending = Set(items.map(\.id))
            autoUpdated = []; autoFailed = []
            items.forEach(update)
        }
    }

    /// An automatic install finished; the last one posts the summary.
    private func autoFinished(_ item: UpdateItem, ok: Bool) {
        guard autoPending.remove(item.id) != nil else { return }
        if ok { autoUpdated.append(item.name) } else { autoFailed.append(item.name) }
        if autoPending.isEmpty { Notifier.notifyAutoRun(updated: autoUpdated, failed: autoFailed) }
    }

    // MARK: - Menu bar spinner

    private var spinTimer: Timer?

    /// A background check in progress, as flagged in state.json. Ignored once
    /// stale, so an agent that crashed mid-check can't leave it spinning.
    private var backgroundCheckRunning: Bool {
        guard let started = state.checkStartedAt else { return false }
        return Date().timeIntervalSince(started) < 10 * 60
    }

    var isSpinning: Bool { isChecking || backgroundCheckRunning }

    /// Waiting for the password with no Dock icon to bounce: the menu bar
    /// prism pulses instead (Nick, 30 Oct 2026).
    var needsAttention: Bool { passwordRequest != nil && !Prefs.showDockIcon }

    /// The menu bar prism pulses while checking or while it needs attention.
    var isPulsing: Bool { isSpinning || needsAttention }

    private func updateSpinner() {
        let spinning = isPulsing
        if spinning, spinTimer == nil {
            // Twelve frames a second: one pulse takes about 1.7 seconds.
            spinTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.spinFrame = (self.spinFrame + 1) % MenuBarIcon.frameCount
                    // Catch a stale background flag without waiting for a reload.
                    if !self.isPulsing { self.updateSpinner() }
                }
            }
        } else if !spinning, let timer = spinTimer {
            timer.invalidate()
            spinTimer = nil
            spinFrame = 0
        }
    }

    // MARK: - Keeping the badge current

    private var directoryWatcher: DispatchSourceFileSystemObject?
    private var reloadPending = false
    private var fallbackTimer: Timer?

    /// The background agent writes state.json from another process, and the
    /// badge has to follow it without the window being opened. Watch the
    /// folder (state.json is replaced atomically, so a watch on the file
    /// itself would go stale after the first write), and also reload on wake,
    /// on activation, and on a slow timer in case an event is missed.
    private func startWatching() {
        let dir = Store.supportDirectory.path
        let fd = open(dir, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleReload() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            directoryWatcher = source
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReload() }
        }
    }

    /// Coalesce bursts of events (one save touches the folder several times).
    private func scheduleReload() {
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadPending = false
                self?.reloadFromDisk()
            }
        }
    }
}

extension Swift.Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) }
        catch { self = .failure(error) }
    }
}

extension UpdateItem {
    /// "Name 1.2.3" for the Activity log; just the name when there's no
    /// version (removals).
    var logTitle: String { latestVersion.isEmpty ? name : "\(name) \(latestVersion)" }
}
