# Step 10: Other sources (plan, 2 Nov 2026, waiting for Nick's OK)

## What's there now (Settings)
- **Sources**: one switch per source (Homebrew, Sparkle…).
- **GitHub releases**: a list of linked apps (icon, name, repo, red Remove)
  and "Add an App…", which opens `GitHubLinkSheet` (pick an app, search
  GitHub or paste a link, "Checks out", Link).
- **Custom sources**: only "Open File" (you edit `custom_sources.json` by
  hand) plus a "Check X in the background" switch per entry.
- Both are search-aware in Settings (`sectionRows` / `rowWords`).

## What I'll build
1. **One "Other sources" section** replacing the two. One list, one row per
   linked app or custom source: icon, name, a line under it
   (`github.com/owner/name`, or the page it checks), a small tag (GitHub /
   Custom, `StatusPill`), and on the right a red Remove (`glassDestructive`,
   small). Custom rows also keep the "Check in the background" switch,
   shown on the row. One explaining caption, one **Add a Source…** glass
   button at the bottom right (same place as today's Add an App…).
   "Open File" stays as a small helper for Advanced users.
2. **`Views/AddSourceSheet.swift`**, a 520-wide sheet with the close circle
   (`.popupClose()`), opened by Add a Source…. A two-option `GlassSegmented`
   at the top: **GitHub** | **Custom**.
   - **GitHub**: the existing `GitHubLinkSheet` content, moved in unchanged
     (pick an app, search/paste, Link). Installed's "Not managed" pop-up still
     opens it directly with the app preselected.
   - **Custom**: App name; where its installed version comes from (pick the
     app with the glass menu, or Advanced: a plist path / a command);
     the version page link; **then** a choice, again `GlassSegmented`:
     *Open the download page* (field for the page) | *Run a command* (field
     for the command, with the sudo/password note). A **Test** button that
     reads the installed and latest version and shows "Installed 1.2, latest
     1.4" or what failed. **Advanced** (disclosure): pattern (regex) or JSON
     key, plist key, version command, notes. The version page's format is
     guessed (JSON → looks for `version`/`tag_name`, otherwise a version-like
     pattern) and shown in Test, so most people never open Advanced.
   - **Add** (prominent, bottom right) is disabled until Test has worked.
3. **Saving** uses the existing `custom_sources.json` format (same `Entry`
   fields), so 1.8.0 entries and the hand-edited file keep working. New
   entries are saved by re-reading the file and appending (never overwrite
   a hand edit), and start with background checking **off** (the existing
   rule for entries added after the first look). Removing an entry deletes
   only that entry.
4. Small additions to `CustomSource`: `save(_:)`, `remove(named:)` and a
   `test(_:)` that reuses `installedVersion`/`remoteVersion`.
5. Update the Settings search words, and a pure unit test for the guesser
   (JSON key / regex choice) and the add/remove file handling (using a temp
   file, not the real data folder).

## Questions for you
1. **Should "Add" be allowed before Test works?** I'd say no (a typo then
   can't create a source that silently never shows updates). Alternative:
   allow it with a warning. *Recommended: Test first.*
2. **Run a command** can run anything, including `sudo`. I'd keep today's
   rules: it isn't run in the background unless you switch it on, and the
   sheet shows the command you typed in plain text before you press Add. OK?
3. **Keep the "Drivers" paragraph** at the bottom of Settings as is (it only
   explains the Homebrew-cask trick)? I'd leave it.
4. Should hand-added GitHub links keep their own "Remove" only, or also an
   "Open on GitHub" link on the row? *I'd add nothing: fewer buttons.*

## After the build
Test build checked in light and dark (Theme setting, back to Light),
adding and removing a **throwaway** custom source (dummy plist in
`~/Applications`-style temp folder, no real apps), results recorded in
`docs/phase10-plan.md`. Not committed until you ask. Probes/tests of the
add/remove code use a temp file, not `~/Library/Application Support/UpdateScout/`.
