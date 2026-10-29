# UpdateScout

A Swift (SwiftPM) macOS menu bar update manager. It finds updates from
Homebrew, the Mac App Store (`mas`), Sparkle feeds, macOS updates and custom
sources, and installs them.

**Next up is 2.0.0, renamed PrismPack.** Read
[docs/2.0.0-build-guide.md](docs/2.0.0-build-guide.md) first. It's the single
entry point, with the status at handoff, Nick's answers (section 3.4), the
build order and links to every other 2.0 doc.
[docs/1.8.0-plan.md](docs/1.8.0-plan.md) records what 1.8.0 changed.

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

## Build, test, release

- **Build:** `scripts/build-app.sh` writes `build/UpdateScout.app`. With
  `--install`, it also copies the app to `/Applications`.
- **Compile check:** `swift build`.
- **Running a test build:**
  - Quit the installed copy first. Both copies share the bundle ID and
    `~/Library/Application Support/UpdateScout/`.
  - Don't toggle "Check for updates in the background" in a test build. It
    points the real launchd agent (`com.nickszun.updatescout.check`) at that
    build.
- **Trigger a background check by hand:**
  `/Applications/UpdateScout.app/Contents/MacOS/UpdateScout --background-check`
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
- **`MenuBarExtra` labels are flattened to an image.** View modifiers
  (rotation and so on) and SwiftUI animations are dropped. Animate with
  pre-drawn template frames, as in `Views/MenuBarIcon.swift`. Keep a single
  status item so menu bar managers (Thaw, Ice, Bartender) keep its position.
- **Sparkle release tracks** come from the installed version (see
  `VersionParts` in `Models.swift` and `AppcastParser` in
  `Sources/SparkleSource.swift`). Some feeds leave betas untagged, so the
  version markers count too.
- **Item IDs include the install token.** Changing the ID format resets
  users' ignored and notified lists.
- **Liquid Glass:** `build-app.sh` patches the linked-SDK version so AppKit
  uses the new UI. Use the `.glass()` and `.glassProminent(_:)` helpers and
  `GlassBackground` from `Views/Style.swift`.
