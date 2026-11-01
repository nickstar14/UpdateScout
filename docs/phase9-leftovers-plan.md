# Phase 9 plan: leftover cleanup (31 Oct 2026)

Replaces the first Phase 9 design after three test runs. **Approved by Nick
and built** on `release/2.0.0`; **not committed** (ask Nick).

## Status at handoff (31 Oct 2026)

**Built and working:**
- **Move to Trash window** (`Views/UninstallWindow.swift`): the app plus its
  exact-ID leftovers (ticked), name matches (unticked), app-group folders
  (Show in Finder only), a running-app Quit step, Homebrew's cleanup list
  (zap, unticked), one run, one Activity line.
- **Orphaned App Files page** (`Views/OrphansPage.swift`): filter box, sort by
  Size / Name / Last changed, Keep, Show files, nothing ticked; notes for
  "another app from this developer is installed", "changed in the last
  month" and shared folders.
- **Safety** (`Leftovers.swift`): Apple IDs excluded anywhere in the name;
  installed apps' nested helpers, extensions and app groups count as owners;
  every move is re-checked before and **verified after** (macOS can report a
  move that didn't happen); app-group folders are never moved.
- **Full Disk Access**: optional row in Settings → Setup (first launch opens
  it when off), explaining why macOS needs it; "Allow…" opens System
  Settings plus a floating helper (this copy's icon to drag, Show in Finder,
  Quit and Reopen). **Survives updates** thanks to the "PrismPack Signing"
  certificate (`scripts/make-signing-cert.sh`, `scripts/build-app.sh`).
- **Window fixes**: pages no longer size the main window (it opens at
  914 × 706, Nick's choice); oversized saved frames are pulled back; opening
  the running app again shows its window.
- **Tests:** `LeftoverTests`, 10 tests, temp folders only, all pass.

**Left to do:**
1. **Homebrew cleanup-list (zap) test** on a throwaway cask Nick picks: with
   and without the list, checking the shown list matches what Homebrew does.
2. **Running-app Quit step** test (a throwaway app left open).
3. **The helper's in-app icon drag** into the Full Disk Access list: fixed
   (it now offers the app's file URL) but untested; Finder drag is proven.
4. **"Off" look of the Settings row**: not seen live (access is on).
5. **Sparkle and the signing change**: before the first release signed with
   the certificate, confirm Sparkle accepts an update whose code signature
   changed from ad hoc.
6. **"What's new in 2.0"** (`Views/RenameWelcome.swift`): add leftover cleanup,
   Orphaned App Files and Full Disk Access; show Nick.
7. **Commit**, when Nick asks.
8. **Cleanup on Nick's Mac:** `~/Library/Group Containers/group.com.nickszun.leftovertest2`
   (Nick can try Finder), test leftovers in the Trash.

## What the test runs taught us

1. **Offering leftovers after the app is gone doesn't work.** The pop-up
   disappears with the app's row. So everything is shown *before* anything
   moves, as AppCleaner does.
2. **Exact-ID matching worked.** 11 of 11 test leftovers were found, the
   name-only folder was left unticked, and the running test agent was
   stopped before its file moved.
3. **`~/Library/Containers` is protected by macOS** (since macOS 14). PrismPack
   was refused, and so was asking Finder to move it, with no prompt.

## Research (sources at the end)

- **Containers.** Other apps' containers are protected. Several sources (Docker's
  uninstall docs, an Apple Community thread, an open-source AppCleaner clone)
  say **Full Disk Access** lets an app remove them. One Apple forum thread from
  a cleaner app said deletion was still blocked on macOS 14 even with Full Disk
  Access. **So it is not proven. We test it on a real container before relying on it.**
- **Full Disk Access and our signing.** PrismPack is signed "ad hoc" (no Apple
  Developer ID). macOS ties Full Disk Access for such apps to the exact build,
  so **the switch would likely stop working after every PrismPack update** and
  need turning off and on again. Not verified; the test checks it.
- **Group Containers.** Since macOS 15 they're protected by System Integrity
  Protection, and they're often shared between a developer's apps.
- **A real danger.** An open Pearcleaner bug (26 Oct 2026, macOS 27): it moved an
  Apple system container to the Trash, and the Trash can now never be emptied,
  not even with `sudo` or Finder. Lesson: never touch anything Apple's, and test
  that a moved container can actually be emptied from the Trash.
- **AppCleaner's model.** Drop an app, see the app plus its files with
  checkboxes, remove all in one go. It warns if the app is running.
- **Pearcleaner's "orphaned files" search** lists everything in the Library
  folders that doesn't loosely match an installed app (name, ID, team).
  Too loose for us; ours uses exact IDs only.

## The design

### A. Move to Trash: one window, everything at once

1. Clicking **Move to Trash…** on an app (Installed, Updates, Discover,
   Duplicates) opens a window. Nothing has moved yet.
2. **If the app is running:** "Quit Leftover Test first", with a **Quit**
   button. Moving stays disabled until it has quit.
3. The window lists:
   - **The app** itself, ticked, with its size.
   - **Its leftovers**, exact ID matches, ticked: Application Support, Caches,
     Preferences (and per-Mac ones), Containers, Application Scripts, Saved
     Application State, HTTPStorages, WebKit, Logs, LaunchAgents. Also the
     app's own helpers' IDs (IDs starting with the app's full ID).
   - **Name-only matches**, unticked, marked "Name match only".
   - **Group Containers** from the app's own entitlement, unticked, marked
     "May be shared with other apps from this developer" (Q2).
   - The total ticked size.
4. **Move to Trash** does, in order: stop any running leftover background
   job; move the app; then move the ticked leftovers. If the app can't be
   moved, nothing else is touched.
5. Afterwards the same window says what moved. Anything macOS refused is listed
   with the reason and **Show in Finder** (and, if Q1 says so, the Full Disk
   Access button). **Try Again** retries those.
6. One Activity line: "Moved Leftover Test to the Trash, with 11 leftovers (1.8 MB)".
7. **Duplicates:** when another copy of the same app stays installed, the
   window lists only the app, with a note that its files stay for the other copy.
8. **Homebrew apps:** the same window, listing the app and a checkbox
   **"Also run Homebrew's cleanup list"** with that list shown underneath
   (what goes to the Trash, what Homebrew deletes outright, and whether it
   needs your password). Unticked, Homebrew removes only the app, as today.
9. Other kinds (npm, pip, extensions…) keep today's simple confirmation.

### B. The page for apps that are already gone

1. A sidebar page under Installed: **Orphaned App Files**.
2. It looks in the same Library folders for items **named with an app ID**
   (like `com.example.foo`) that **nothing on this Mac owns**. "Owned" means
   any of: an app in the Applications folders (one level deep); any app
   macOS knows by that ID anywhere on the disk; an app whose ID the item's ID
   starts with (its helpers); a LaunchAgent whose program still exists.
3. Never: anything starting with `com.apple.`, names that aren't app IDs, name
   matches. Group Containers whose group no installed app claims are listed
   unticked, as in A (subject to the Q2 safeguard).
4. Grouped by ID: "com.example.foo, 3 items, 12 MB, last changed March 2024".
5. **Nothing ticked by default.** An ID with no app can still belong to a
   command-line tool or a background service. You tick what you recognise.
6. **Keep** hides a group for good. **Move to Trash** works as in A.5.
7. It scans only when the page is opened or you click Rescan, never in the
   background check.

### C. Safety rules (both)

- Exact IDs only; never `com.apple.`; never an ID without a dot; never
  PrismPack's own.
- Only inside `~/Library` (and the app itself). Never `/Library` or anything
  system-wide.
- Links move as links, never their target; a Library folder that's itself a
  link is skipped.
- Every item is checked again just before it moves.
- Everything goes to the Trash. The only exception is Homebrew's own cleanup
  list, which may delete some items outright; the window says which.
- A container whose metadata names an Apple ID is never listed, even if its
  folder name doesn't look like one.

## Nick's answers (31 Oct 2026)

- **Q1. Containers:** Nick asked whether `sudo` with the password prompt could
  do it, with Finder as backup. Research says no: the block is macOS's own
  policy, not file permissions, and `sudo rm` fails with "Operation not
  permitted" (AppCleaner clone README; Pearcleaner #616). The test confirms it
  once on the throwaway container (step 2b). If `sudo` fails as expected:
  **optional Full Disk Access** in setup and Settings (noting it may need
  switching on again after an update), **Show in Finder** as the backup.
- **Q2. Group Containers: listed, unticked**, marked "May be shared with other
  apps from this developer". **Safeguard:** only if the test shows a moved
  group container can still be emptied from the Trash (step 3b). If it gets
  stuck, as in Pearcleaner #616, group containers get **Show in Finder** only,
  never Move to Trash, and Nick is told.
- **Q3. Page name: "Orphaned App Files".**
- **Q4. Homebrew's cleanup list: kept, unticked**, with the list shown and
  outright deletions marked.

## Test plan (throwaway apps only, real `~/Library` paths approved per item)

1. Build a tiny **sandboxed** throwaway app and launch it once, so macOS
   creates a **real** container (the earlier one was a hand-made folder).
2. **Without Full Disk Access:** run A; the container is refused; Show in Finder;
   can Nick drag it to the Trash himself?
   2b. With Nick's OK at that moment: one `sudo` move of the throwaway
   container with the password prompt, to confirm it's refused.
3. **With Full Disk Access** for the test build (Nick switches it on, then
   relaunch): the container moves. Then Nick deletes just that item from the
   Trash, to prove it can be emptied.
   3b. The same for a throwaway **group container** (the test app gets an
   app-group entitlement).
4. **Rebuild** the test build without touching Full Disk Access: does it still
   work? (Answers the "after every update" question.)
5. Page B finds the throwaway app's files after the app is in the Trash, and
   never lists anything of an installed app (checked against Nick's real
   Library **read-only**: needs Nick's OK, the list is shown to him, nothing
   ticked or moved).
6. Homebrew: one throwaway cask Nick picks, with and without its cleanup list.
7. Running app: the Quit step.
8. Afterwards: Full Disk Access switched back off, test files removed, a list
   of what was left behind.

## Test results (31 Oct 2026)

- **Containers, no Full Disk Access:** refused, also through Finder and with
  `sudo` ("Operation not permitted"). Show in Finder works.
- **Containers, with Full Disk Access on the test build:** a real container
  (`com.nickszun.leftovertest2`) and the hand-made one moved, and Nick emptied
  the Trash normally afterwards with no error. So a moved app container can be
  emptied.
- **Full Disk Access after a rebuild: lost.** After about six rebuilds,
  with the switch untouched, the test build couldn't move a fresh real
  container (`com.nickszun.leftovertest3`); only its Application Scripts
  folder moved. An ad-hoc signature changes with every build, and macOS ties
  the grant to it. A Sparkle update installs a new build in the same way, so
  **with ad-hoc signing every update loses Full Disk Access.** Options: a
  stable signing certificate (self-signed, or a Developer ID), or detecting
  the loss and asking the user to fix the switch.
- **Turning the switch off and on doesn't bring it back.** Nick toggled it and
  relaunched; the container was still refused. macOS seems to keep the
  signature from when the app was first added.
- **Removing the entry and adding the current build again does.** Nick
  removed it, dragged `build/PrismPack.app` in from Finder, and after a
  relaunch the container moved. So with ad-hoc signing, after every update
  the user would have to remove PrismPack from the list and add it again.
- **Fix: a stable signing certificate. Full Disk Access now survives an
  update.** `scripts/make-signing-cert.sh` (run once by Nick) created the
  self-signed "PrismPack Signing" code-signing certificate in his login
  keychain, and `build-app.sh` signs with it (ad hoc, with a warning, if it's
  missing). The designated requirement is now `identifier
  "com.nickszun.updatescout" and certificate leaf = H"d0e45ba3…"`, the same
  for every build. Test: Nick added the signed build once; a new build with a
  higher build number and a different code hash (as a release has) then moved
  a fresh real container (`com.nickszun.leftovertest4`) and its Application
  Scripts folder with no change in Settings. Before the first release signed
  this way, check that Sparkle accepts an update whose code signature changed
  from ad hoc (its EdDSA signature should be what counts).
- **Full Disk Access in setup and Settings:** the Setup section at the top of
  Settings (which first launch opens) has a Full Disk Access row: "is on", or
  optional with Allow…, saying what it's for, that Show in Finder works
  without it, and that it stays on through updates. It rechecks whenever the
  app comes to the front. First launch now also opens Settings when Full
  Disk Access is off. The check opens the system privacy database and closes
  it without reading (only possible with Full Disk Access). Seen "on" in a
  later build than the one Nick added; the "off" look isn't checked live.
- **Full Disk Access helper:** "Allow Full Disk Access…" opens the Settings
  page plus a floating window with this copy's icon to drag in, Show in
  Finder, and Quit and Reopen (which reopens this copy; System Settings' own
  "Quit & Reopen" opened the installed copy). The first version's drag offered
  a file copy that Settings ignored; it now offers the file URL. Dragging
  from Finder is confirmed to work; the fixed in-app drag is not yet tested.
- **Group container (step 3b): failed safely.** PrismPack's move of
  `group.com.nickszun.leftovertest2` came back as a success, but the folder
  stayed where it was (same inode, created 10:54). Per the Q2 safeguard,
  **group containers are now Show in Finder only**, in both the Move to Trash
  window and Orphaned App Files. Every move is now checked afterwards: an item
  still in place counts as a failure, never as moved.
- **Orphaned App Files on Nick's Mac (read-only review):** 233 entries (369
  before the owner fixes), no Apple entries at the top. Entries changed in the
  last month (for example `org.swift.swiftpm`, used by the Swift tools) now
  carry an orange "may still be in use" note.
- **App-group folders outside Group Containers** (for example
  `Application Scripts/group.com.facebook.family`) were listed as normal,
  tickable orphans. They're now treated as groups: owned if an installed app
  claims the group, and Show in Finder only. The list went from 232 to 211.
- **Window:** the page stretched the main window to 2,367 pt. The cause was the
  header's `fixedSize` caption, measured at zero width, which also pushed the
  sidebar off screen. The header now uses a line limit, pages no longer size
  the window, a saved frame taller than the screen is pulled back on open, and
  the window first opens at 914 × 706 (Nick's choice).
- **Opening the app while it's running** (Finder, Spotlight, `open`) now shows
  the window, as other Mac apps do.

## Sources

- Eclectic Light, "What are all those Containers?" (Aug 2024)
- Apple Developer Forums 736945 (cleaner app denied on macOS 14 with Full Disk Access)
- Pearcleaner issue #616 (system container stuck in the Trash, macOS 27)
- github.com/popyapp/app_cleaner README (Full Disk Access, running-app warning)
- Docker Desktop uninstall docs (container removal needs Full Disk Access)
- Pearcleaner source: `ReversePathsFetch.swift`, `AppPathsFetch.swift`
