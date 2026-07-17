# UpdateScout

Menu bar app that finds available updates across everything on the Mac and lets
you install each one with a click. Nothing installs silently — every update is
user-initiated, per item.

## Update sources

| Source | Detects via | Updates via |
|---|---|---|
| Homebrew | `brew outdated --json=v2` | `brew upgrade [--cask] <name>` |
| Mac App Store | `mas outdated` (needs `brew install mas`) | `mas upgrade <id>` |
| macOS | `softwareupdate -l` | `softwareupdate -i` behind macOS's own admin prompt; restart-required updates say so up front |
| Other apps (cask oracle) | Matches /Applications apps against Homebrew's cask database — catches apps like **DisplayLink Manager** that have no auto-update and weren't installed via brew | `brew install --cask <token> --force` (the app becomes Homebrew-managed; the row says so) |
| Sparkle apps | `SUFeedURL` in app Info.plists → fetch appcast, compare versions | Opens the release page (in-place install via the embedded Sparkle framework is a planned follow-up) |
| Custom sources | `custom_sources.json` — plist/command for installed version, URL + regex/JSON-path for latest | A shell command per entry, or opens the vendor download page |

## Build & install

```bash
scripts/build-app.sh --install   # builds and copies to /Applications
open /Applications/UpdateScout.app
```

Requires Xcode command line tools. Homebrew is expected; `mas` is optional
(the App Store row tells you how to enable it).

## Background checks

Settings → "Check for updates in the background" installs a launchd user agent
(`~/Library/LaunchAgents/com.nickszun.updatescout.check.plist`) that runs the
app binary with `--background-check` on the chosen interval. That mode only
detects and notifies — installs still happen from the menu, by you.

Notifications fire only for updates not seen before (new app or new version),
not on every check. "Ignore this version" suppresses an item until a newer
version appears.

## Files

- State: `~/Library/Application Support/UpdateScout/state.json`
- Custom sources: `~/Library/Application Support/UpdateScout/custom_sources.json`
  (seeded with a DisplayLink Manager example on first run)
- Cask index cache: `~/Library/Application Support/UpdateScout/cask-index.json`
  (refreshed daily from formulae.brew.sh)

## Known limitation

There is no unified API for third-party driver/firmware updates on macOS.
Vendors like DisplayLink distribute their own installers with no auto-update.
Homebrew's cask database is the best available proxy (maintainers already track
vendor releases); anything without a cask goes in `custom_sources.json`, where
"open the download page" is the guaranteed baseline action.
