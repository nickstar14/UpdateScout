# PrismPack (formerly UpdateScout)

A Swift (SwiftPM) macOS menu bar update manager. It finds updates from
Homebrew, the Mac App Store (`mas`), Sparkle feeds, macOS updates and custom
sources, and installs them.

**Next up is 2.0.0, renamed PrismPack.** Read
[docs/2.0.0-build-guide.md](docs/2.0.0-build-guide.md) first. It's the single
entry point, with the status at handoff, Nick's answers (section 3.4), the
build order and links to every other 2.0 doc.
[docs/1.8.0-plan.md](docs/1.8.0-plan.md) records what 1.8.0 changed.
Phase 9 (leftover cleanup) has its own record in
[docs/phase9-leftovers-plan.md](docs/phase9-leftovers-plan.md).

## Rules for working here

- **Local first, publish only on request.** Build and test locally. Never
  push, tag, run `scripts/release.sh`, or edit `appcast.xml` unless Nick
  explicitly asks to publish. Work on a branch (for example `release/2.0.0`),
  not `main`.
- **Release notes are approved before publishing.** Draft them, show them to
  Nick, and wait for his OK.
- **GitHub account.** The default `gh` account on this Mac is `IHMS-IT`, which
  can't push to `nickstar14/UpdateScout`. To release: ask first, run
  `gh auth switch --user nickstar14`, release, then
  `gh auth switch --user IHMS-IT`. Check push access with
  `git push --dry-run origin main` before running the release script. The
  script pushes before it creates the GitHub release, so a failed push would
  leave a half-finished release.
- **Filesystem.** Nick's global rules apply: ask before reading or writing
  outside this folder.
- **Commit only when Nick asks.** Show `git status` first.
- **Consistency is the first rule (Nick, 2 Nov 2026).** Every page, card,
  pop-up, button, tag and colour follows the patterns listed under
  "Status at handoff" in `docs/phase10-plan.md`. Match them; if something
  new doesn't fit, ask Nick instead of inventing a new pattern. Check every
  change in light and dark (the app's Theme setting, back to Light after).
- **Plan the whole step before building.** Research, write the plan, show it,
  get Nick's OK. No trial-and-error builds, nothing built beyond the plan.
- **Batch feedback into one build.** Build, gather all of Nick's feedback,
  then roll it into the next build. No rebuild for a single small item, and
  never rebuild while Nick is mid-step.
- **Go easy on usage.** Nick is on a Pro plan: keep tool calls, screenshots
  and file reads lean. Check the 5-hour and weekly limits now and then and
  pause at a safe point near the limit.
- **Testing.** Only on throwaway apps. Never touch the keychain or change
  System Settings. For dark-mode checks use the app's own Theme setting and
  set it back to Light. Ask before pausing the 1.8.0 background agent and
  turn it back on afterwards. Never show a live password dialog as a preview
  (rendered images only).

## Build, test, release

- **Build:** `scripts/build-app.sh` writes `build/PrismPack.app` (named from
  `CFBundleName`; the executable inside is still `UpdateScout`). With
  `--install`, it also copies the app to `/Applications/PrismPack.app` and
  removes `/Applications/UpdateScout.app`.
- **Rename, Part 1 (2.0):** only the display and bundle name changed. The bundle
  ID `com.nickszun.updatescout`, executable `UpdateScout`, launchd label, data
  folder `Application Support/UpdateScout/` and preference keys stay until Part 2.
- **Signing:** `build-app.sh` signs with the self-signed "PrismPack Signing"
  certificate in Nick's login keychain (made once with
  `scripts/make-signing-cert.sh`), so Full Disk Access survives updates. If it
  prints "signing ad hoc", the certificate is missing: Full Disk Access will
  stop working in that build. Never read or touch the keychain yourself.
- **Compile check:** `swift build`.
- **Running a test build:**
  - Quit the installed copy first. Both copies share the bundle ID and
    `~/Library/Application Support/UpdateScout/`.
  - Don't toggle "Check for updates in the background" in a test build. It
    points the real launchd agent (`com.nickszun.updatescout.check`) at that
    build.
  - Open the running test build's window with `open build/PrismPack.app`.
    Opening the running app again shows its window. Add
    `--args --open-settings` on a fresh launch to start in Settings.
  - System Settings' "Quit & Reopen", after a privacy change, reopens the
    *installed* copy, because it finds the app by bundle ID. Quit that copy and
    reopen the test build.
  - Adding or removing an app in Full Disk Access is Nick's click, never
    Claude's.
- **Trigger a background check by hand:**
  `/Applications/PrismPack.app/Contents/MacOS/UpdateScout --background-check`
- **Release:**
  `scripts/release.sh <version> <notes.html> <notes.md>`
  - It bumps `CFBundleVersion`, builds, zips and EdDSA-signs the app.
  - It updates `appcast.xml`, commits, tags `v<version>` and pushes `main`.
  - It creates the GitHub release.
  - Afterwards, check that the appcast on `raw.githubusercontent.com` lists the
    new version and that the zip downloads.

## Things that bite

- **Two processes write `state.json`:** the app and the headless
  `--background-check` agent. Always go through `Store.mutate`, which locks,
  re-reads and applies only the change. Never save a stale in-memory copy.
- **The status item is an `NSStatusItem`** (2.0), not a `MenuBarExtra`, so
  left-click opens the window and right-click shows the menu. Its image can't
  be animated: the checking pulse uses pre-drawn template frames, as in
  `Views/MenuBarIcon.swift`. Keep a single status item and its `autosaveName`
  so menu bar managers (Thaw, Ice, Bartender) keep its position.
- **Testing 2.0 next to the installed 1.8.0:** the 1.8.0 background agent
  rewrites `state.json` without 2.0's new fields (Activity log, hide lists).
  Expect them to vanish in test builds; it's not a 2.0 bug.
- **Sparkle release tracks** come from the installed version (see
  `VersionParts` in `Models.swift` and `AppcastParser` in
  `Sources/SparkleSource.swift`). Some feeds leave betas untagged, so the
  version markers count too.
- **Probes and tests touch the real data folder.** `Store.supportDirectory`
  comes from FileManager, which ignores a `HOME` override, so a test or probe
  that loads Discover or the stores reads and writes
  `~/Library/Application Support/UpdateScout/`. Ask Nick before running one.
- **Item IDs include the install token.** Changing the ID format resets
  users' ignored and notified lists.
- **Page headers:** never put `fixedSize(horizontal: false, vertical: true)`
  on text in a page header (`pinnedHeader`). Measured at zero width, it made
  the page thousands of points tall, which stretched the window and pushed
  the sidebar off screen. Use a line limit. It's fine in fixed-width panels.
  Pages don't size the main window (`sizingOptions = []`).
- **Moving other apps' data:** macOS can report a Trash move as done while
  the folder stays put (a group container, 31 Oct 2026). `Leftovers.moveToTrash`
  checks afterwards; keep that. App-group folders are never moved, and
  nothing with `com.apple.` anywhere in its name is touched: a stuck Apple
  container can make the Trash impossible to empty.
- **Moving a user's app must be airtight (Nick, 2 Nov 2026).** Duplicates
  are grouped by bundle ID; two copies share one ID, so "is it open" is
  checked by path (`Duplicates.isRunning`), never by bundle ID. Every move
  goes through `Duplicates.refusal` right before acting. Test moves only on
  throwaway dummy apps (a minimal `.app` with its own bundle ID in
  `~/Applications`), never on Nick's apps without his go-ahead.
- **Testing Installed from the background:** menus can't be opened, so the
  Source filter can only be changed with
  `defaults write com.nickszun.updatescout installedSource ""` (Nick's own
  setting is `unmanaged`: put it back). Installed takes about 20 s to load
  (it calls `brew info`). An `NSAlert` opens as its own window: find it with
  `app_list_windows`.
- **Liquid Glass:** `build-app.sh` patches the linked-SDK version so AppKit
  uses the new UI. Use the `.glass()` and `.glassProminent(_:)` helpers and
  `GlassBackground` from `Views/Style.swift`.
