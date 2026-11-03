# Step 11: the ⌘Q prompt (plan, 2 Nov 2026)

Status: **plan, waiting for Nick's OK. Nothing built.**

## What Nick already decided

(`docs/phase10-plan.md`, "Nick's decisions", and the right-hand alert in
`docs/mockups/phase10-round2.html`, `quitAlert()`.)

- ⌘Q asks "Quit PrismPack?". Buttons: **Close Window (⌘W)** (the default,
  Return), **Quit**, and a **"Don't ask again"** checkbox.
- Text: "Checks and automatic updates keep running in the background either
  way. Closing the window keeps the menu bar prism and update notifications
  in PrismPack."
- With background checking off, the first sentence becomes: "Checks and
  automatic updates stop until you open PrismPack again."
- Quit from the menu bar menu doesn't ask.

## What I found

- `AppDelegate` has no `applicationShouldTerminate` yet. ⌘Q, the Dock's Quit
  and `NSApp.terminate(nil)` all go through it.
- `NSApp.terminate(nil)` is also called, and must **not** ask, from:
  the menu bar menu's Quit (`MenuBarIcon.swift:113`), Migration
  (`Migration.swift:68`), Full Disk Access's "Quit and Reopen"
  (`FullDiskAccessHelper.swift:60`), and Sparkle's own relaunch after a
  self-update (`SelfUpdater`).
- Log out / restart / shut down also ask the app to terminate; those must
  never be held up by a prompt.
- Every other dialog in the app is an `NSAlert` (`SettingsView.swift:128`,
  `OrphansPage.swift:325`, `UninstallButton.swift`), so the prompt is one too:
  same look as the others, no new pattern.
- Preferences live in `enum Prefs` in `Store.swift` (UserDefaults).
  Background checking on/off is `LaunchAgent.isInstalled`
  (`SettingsView.swift`).

## The build

1. **`Prefs.askBeforeQuit`** (`Store.swift`): Bool, default true, key
   `askBeforeQuit`. Stored in UserDefaults like the other preferences.
2. **`AppDelegate.applicationShouldTerminate`**:
   - Returns `.terminateNow` when: the preference is off; `skipQuitPrompt`
     is set; or the quit came from the system (log out, restart, shut down:
     checked with the Apple event's quit reason).
   - Otherwise shows an `NSAlert` (icon = app icon, like the others):
     title "Quit PrismPack?", text as above, buttons **Close Window (⌘W)**
     (Return, default), **Quit**, checkbox **Don't ask again**
     (`showsSuppressionButton`, relabelled).
   - Close Window: closes the main window (if it's open) and returns
     `.terminateCancel`. Quit: `.terminateNow`. Ticking the box saves
     `askBeforeQuit = false` for either button.
   - Reading `LaunchAgent.isInstalled` runs `launchctl` (answers at once,
     already used in Settings) and is only done when the prompt shows.
3. **`AppDelegate.skipQuitPrompt`** flag, set by the menu bar Quit,
   Migration, Full Disk Access's relaunch and the self-updater before they
   call `NSApp.terminate`.
4. **Settings**: a small "Ask before quitting" switch (in the same card style
   as the other switches) so "Don't ask again" can be undone. Without it,
   the only way back is a Terminal command.

## Questions for Nick

1. **Settings switch:** OK to add "Ask before quitting" to Settings so he can
   turn the prompt back on? (My recommendation: yes.)
2. **While an install is running:** should ⌘Q also say "An update is still
   installing" in the prompt? Not in his decision, so I'd leave it out
   unless he wants it.

## Checking (after the build, in the test build)

- Light and dark (Theme setting, back to Light afterwards): look at the
  alert in both.
- ⌘Q shows the prompt; Return = Close Window (window closes, app and prism
  stay); Quit quits; "Don't ask again" ticked then ⌘Q again quits at once;
  menu bar Quit never asks; the switch in Settings turns it back on.
- Wording with background checking on and off. The launchd agent is the
  real one, so I won't toggle it: I'll read the wording for "off" from a
  rendered image / forced preview of the text only.
- Record the results in `docs/phase10-plan.md`, then ask before committing.
