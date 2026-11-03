# Step 13: the final review (plan, 3 Nov 2026)

**Status: waiting for Nick's OK. Nothing built.** Follows the rules in
`CLAUDE.md`: one build, feedback batched, test builds only on throwaway apps,
Theme set back to Light and Installed back to List afterwards, nothing pushed,
nothing committed until Nick asks.

## What goes into the one build

1. **Sidebar toggle (carried over, committed in `20760ba`, never run).**
   `DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation)` in
   `Views/UpdatesWindow.swift`. Check it **open and collapsed, light and dark**:
   it must sit in the sidebar's own toolbar section (left of the divider) and
   stay put when the sidebar's grey hides.
   - If it lands wrong, the fallback is an AppKit `NSToolbar` with
     `NSToolbarToggleSidebarItemIdentifier` plus
     `NSToolbarSidebarTrackingSeparatorItemIdentifier` ("Sidebar toggle fix" in
     `phase10-plan.md`). That is a bigger change, so I would stop and show Nick
     the screenshot before writing it.
2. **Productivity's tint (Nick decides).** Today `.productivity` is
   `Color.yellow` in `Discover/DiscoverCategories.swift:28`; at the faint card
   opacity it reads gold-brown in dark. I'll render the same Productivity card
   in light and dark with candidates and Nick picks one: (a) a lighter lemon
   (yellow mixed with white, so it doesn't go brown on dark); (b) a warm amber
   (orange is Design's, so it must stay clearly yellower); (c) keep yellow.
   The choice changes one line; the sidebar dot, card tint and label under the
   name follow because they share the colour.
3. **"What's new in 2.0" fine-tune.** Nick edits the wording; I put the
   agreed text into `RenameWelcome.changes` (`Views/RenameWelcome.swift`) and
   bring the Orphaned App Files entry in line with step 9 ("Belongs to…").
   Nothing goes in without his approval of the wording
   (`whats-new-2.0-proposal.md`).
4. **Phase 9 leftovers** (`phase9-leftovers-plan.md`, "Left to do"). Each is
   settled, not silently dropped:
   - Item 3 (in-app drag of the Full Disk Access helper) and item 4 (the "Off"
     look of that Settings row): need Nick's click or Full Disk Access
     toggled, which is his to do. I'll show the "Off" row as a rendered image
     if the code allows, otherwise list it as unverified.
   - Item 5 (Sparkle accepts a changed signature): deferred by Nick to just
     before the first certificate-signed release. Stays deferred; noted in the
     release checklist.
   - Item 8 (test leftovers in `~/Library/Group Containers/…leftovertest2` and
     the Trash): I'll ask Nick before looking, since it's outside this folder.
   - Items 7 (commit) only when Nick asks.
   - The three small polish items from item 2 (stale "Removed" card after a
     reinstall, lowercase `/Applications/itsycal.app`, Activity lines not saying
     whether the cleanup list ran): I'll check whether Phase 10 already fixed
     them and fix only the ones still there, if Nick agrees.
5. **Picture view dark check.** Open a pop-up's larger-picture view in dark
   and confirm the controls, caption and background match the other pop-ups.
   ← → and Esc already work (Nick tried them), so no key testing.
6. **Lightness before/after table.** Measure with `footprint <pid>` on the
   final test build at the same five moments as `memory-plan.md`:
   fresh launch (20 s idle), Updates open, after Installed loaded, after
   Discover loaded, window closed. Known so far: before 15 / 60 / 109 / 151 /
   **152 MB**; after the memory work the closed-window number was **89 MB**
   (73 MB a few minutes later). The other four "after" numbers get measured
   now. The table goes in `phase10-plan.md`. No helper process (Nick decided).
7. **Left alone:** the pop-up that hangs past the window's bottom edge (Nick:
   leave).

## Consistency pass over every page (the "a to z" check)

Walk Updates, Installed, Discover (all parts), Orphaned App Files, Activity,
Settings and every pop-up in **light and dark**, against the patterns in
"Status at handoff" (`phase10-plan.md`): glass search, `SortMenu`,
`GlassSegmented`, one card shape, tags one line, red tinted glass for
destructive buttons, close circle on pop-ups, strips, wording ("Website",
"Move to Trash", no "…"). Anything that doesn't match is **listed for Nick**,
not invented around. Real data only for viewing; no moves, installs or
removes on Nick's apps.

## How I'll run it (lean on usage)

- Plan approved → one `scripts/build-app.sh` build (fix list from items 2 to 4
  rolled in first), quit the installed copy first, launch `build/PrismPack.app`.
- Drive from the background with `app_click` using `element_index`; close the
  window via Window > Close; Installed takes 25 to 40 s; Orphaned App Files
  about 40 s. Screenshots only where a picture is the proof (toggle position
  open/collapsed, light/dark; the three tint candidates; picture view in
  dark). Everything else by reading the accessibility tree.
- Don't toggle the background-check setting; don't touch the keychain or
  System Settings; don't read `~/Library` without asking.
- Check the 5-hour usage at the start and pause at a safe point near the limit.
- Afterwards: Theme back to Light, Installed back to List, update
  `phase10-plan.md` and `2.0.0-build-guide.md` status, then show `git status`
  and wait for Nick to say commit.

## Nick's answers (3 Nov 2026) and what they change

- **Productivity colour:** my call. Start with a **lighter lemon** (yellow
  with white mixed in; the brown comes from a saturated yellow at low opacity
  over dark grey). If it still looks muddy in dark, next is a brighter warm
  yellow. Rendered in light and dark before it goes in.
- **"What's new":** keep the current text for now (Nick suggests edits after
  seeing it), **plus a new entry for RAM management**: "Closing the window
  gives the memory back: PrismPack idles at about 15 MB and drops Discover's
  catalogue and pictures when the window closes." Claude's draft wording;
  Nick edits it after seeing it. Numbers re-checked in item 6 first.
- **Fixes and polish:** all the Phase 9 polish items still present get fixed
  in this build; the a-z pass fixes what it finds (anything that would need a
  new pattern is listed for Nick instead).
- **Every nook, both directions:** the pass is done twice, in sidebar order
  (Updates to Settings) and then reversed, each in light and dark, covering
  hover, pressed and disabled looks, empty, loading and error states, and
  every animation (page fades 0.14 s, Discover parts, Cards / List slide,
  Theme switch, progress, refresh arrows, pop-up open and close, the rename
  animation, sidebar collapse).
- **Permissions:** I ask before anything outside this folder.

## Part 2 of the rename, and the version bump (new, needs Nick's OK)

Research from the code (inside this folder only). The old name still appears
in: `Info.plist` (executable `UpdateScout`, bundle ID, `SUFeedURL`),
`scripts/build-app.sh`, `scripts/release.sh` (`REPO`), `appcast.xml` (title,
description, old items), the data folder in `Store.swift`, the launch agent
label in `Views/SettingsView.swift`, the askpass notification and
`UPDATESCOUT_ASKPASS_REASON`, the User-Agent in `Shell.swift`, the menu bar
item's `autosaveName`, README and CLAUDE.md. Old plan docs and
`archive/updatescout/` are history and stay.

### Must stay, or the updater breaks

| Item | Why it stays |
|---|---|
| `SUPublicEDKey` | Every 1.8.0 install trusts only this key. Never changes. |
| `SUFeedURL` in 2.0.0 (old repo URL) | 1.8.0 reads the old feed, and 2.0.0 does too until a later build says otherwise. The 2.0.0 item has to be in that feed. |
| `appcast.xml` name, path, old items and their download URLs | Same reason; old users and old release assets keep working. |
| `REPO` in `release.sh` for the 2.0.0 release | The script pushes and releases there. |
| Bundle ID `com.nickszun.updatescout` (**Nick's call; my advice: keep for good**) | Full Disk Access, notifications and every preference are filed under it, and I believe Sparkle expects the same ID across an update (unproven; a throwaway rehearsal would settle it). Nobody sees it. Changing it makes every user lose those grants. |
| Menu bar item `autosaveName` | Thaw, Ice and Bartender remember its position by it (CLAUDE.md). Revisit with a check in Thaw. |

### Changes now, in 2.0.0 (with a one-time migration)

1. **Version:** `CFBundleShortVersionString` 2.0.0. The build number is left
   for `release.sh`, which adds one when it stamps the release.
2. **Executable** `UpdateScout` becomes `PrismPack` (it shows in Activity
   Monitor); `build-app.sh` and CLAUDE.md follow; `--install` still removes
   the old `/Applications/UpdateScout.app`.
3. **Launch agent label** becomes `com.nickszun.prismpack.check`. On first
   launch: write the new agent, then stop and delete the old
   `com.nickszun.updatescout.check`, so the 1.8.0 agent never runs against a
   moved data folder.
4. **Data folder** `Application Support/UpdateScout/` becomes
   `Application Support/PrismPack/`, moved after the agent switch, only when
   the new one doesn't exist yet, logged, never deleting anything it didn't
   move.
5. **Internal names:** askpass variable, notification name and error names
   follow the new name. The repo URL in the User-Agent and in `release.sh`
   comes from **one constant** (`AppIdentity`) so the later repo rename is one
   line.
6. **Appcast** title, link text and description say PrismPack (cosmetic;
   old items untouched).
7. **README, CLAUDE.md, build guide:** updated; "Formerly UpdateScout" stays.
8. **A migration ledger** in `Migration`: each step has a number saved in
   preferences, so 2.0.1 or 2.1.0 just appends steps without touching what
   already ran.

### How the next update (2.0.1 or 2.1.0) changes the rest, repo name included

- The new build's own `Info.plist` carries the new `SUFeedURL`, so the update
  that arrives through the **old** feed moves everyone to the new one. The
  same release can add migration steps for anything else (status item name,
  and the bundle ID if ever wanted).
- Order: (1) release through the old feed with the new `SUFeedURL`;
  (2) rename the repo on GitHub, which redirects the old web, raw and
  download addresses; (3) **never create a new repo called UpdateScout**, or
  the redirect dies for anyone still on 1.8.0 or 2.0.0; (4) update the repo
  constant.
- To confirm GitHub's redirect covers `raw.githubusercontent.com` and release
  downloads, rehearse with a **throwaway repo** (needs `gh auth switch` to
  `nickstar14`; I ask first).

### Testing the rename safely

- Migration code takes its paths as parameters, so unit tests run on temp
  folders only.
- One real run on Nick's Mac only **after a backup** of the data folder and
  the launch agent plist to a folder Nick names, with his go-ahead and the
  installed copy quit. Nothing real is deleted.

## Questions for Nick

1. OK to go ahead with all of the above, **including Part 2 and the 2.0.0
   version bump**?
2. **Bundle ID:** keep for good (my advice), or plan to change it later after
   a rehearsal?
3. May I do the one real migration run on this Mac, after a backup you name?

## Nick's decision (3 Nov 2026): rename everything, bundle ID and menu bar item too

Approved, with: "it's OK if Full Disk Access and notifications reset; I'd
rather they're on the correct PrismPack; 1 day of pain so everything makes
sense in the future." This replaces the "keep the bundle ID and the menu bar
name" rows above. **Now changes in 2.0.0:**

- Bundle ID `com.nickszun.updatescout` becomes `com.nickszun.prismpack`.
  Preferences are copied from the old domain on first launch (old domain left
  untouched). Full Disk Access and notification permission start over: the
  app says so on first launch.
- Menu bar item `autosaveName` becomes `PrismPackStatusItem`; its saved
  position is copied from the old key. Thaw / Ice / Bartender may still need
  one drag.
- Still unchanged: `SUPublicEDKey`, `SUFeedURL` (old repo URL), `appcast.xml`
  path.

**Sparkle finding (read in `.build/checkouts/Sparkle/Autoupdate/SUInstaller.m`):**
after unzipping, Sparkle looks for the new app by the **host's** file name
(`UpdateScout.app`) or the host's display name + `.app`, and only then by
matching bundle ID. With a new bundle ID and a zip holding `PrismPack.app`,
**a 1.8.0 install would not find the app and the update would fail.** So the
2.0.0 release zip must hold the app under the legacy name `UpdateScout.app`
(`release.sh` stages a copy for the zip). `Migration` already renames it to
`PrismPack.app` on first launch. Later releases (2.0.1+) zip `PrismPack.app`
as normal, because their hosts are already PrismPack. **Before any release, a
rehearsal with throwaway apps (old name and ID to new name and ID through a
local feed) must pass**; Sparkle's code-signature check on a changed
signing identity is the other thing it has to prove (Phase 9 item 5).

## Results so far (3 Nov 2026, test build, nothing committed)

- **Backup** of 1.8.0's data, prefs, agent plist and installed app:
  `~/Desktop/PrismPack-backup` (Nick's Desktop, outside the repo).
- **Real migration run, passed:** old launch agent gone, new
  `com.nickszun.prismpack.check` loaded (pointing at the test build in
  `build/` until the installed copy launches and repairs it); data folder
  moved to `Application Support/PrismPack/` with all 18 items; preferences
  carried over; Settings opened on first launch because Full Disk Access
  starts over.
- **Sidebar toggle:** `DefaultToolbarItem` inside a SwiftUI NavigationSplitView
  was a dead blank capsule. Fixed by building the window as an
  `NSSplitViewController` (sidebar and page in their own hosting views) with an
  `NSToolbar` of `[flexibleSpace, toggleSidebar, sidebarTrackingSeparator]`:
  the toggle sits at the **right end of the sidebar section against the
  divider** (like Canary Mail and Notes, Nick's examples), and moves beside
  the traffic lights when the sidebar is collapsed (system behaviour). Checked
  open and collapsed, light, and open in dark. Sidebar opens 210 wide.
- **Pass (light, then dark):** Updates, Installed, Discover (Featured and
  Productivity), Activity and Settings looked consistent in both; the
  Orphaned App Files scan was started but not watched to its end in this
  build. Productivity's lemon label and dot read clean yellow in dark (no
  gold-brown); its card tint is faint, like the other categories.
- **Memory:** 124 MB with the window open after Updates, Installed and
  Discover; **114 MB** 8 s after closing it (earlier run: 89 MB). Not a
  clean measurement (a background check and an interrupted Orphans scan ran
  in this one); the five-moment table still needs a calm run.
- **Phase 9 polish items:** looked at, **not fixed**: the stale "Removed" pill
  needs an uninstall and reinstall in one session (`UninstallButton`'s
  `installStates` entry stays `.done`); the lowercase `itsycal.app` is the
  cask's own file name; the Activity lines not saying whether the cleanup list
  ran. Listed for Nick.

## Added 3 Nov 2026 (Nick)

- **Older macOS (15):** audited the code. Every macOS 26 API (`glassEffect`,
  `.glass` / `.glassProminent` button styles, `safeAreaBar`,
  `scrollEdgeEffectStyle`, `ToolbarSpacer`) sits inside `#available(macOS
  26.0, *)` with a fallback (`.bordered` / `.borderedProminent` buttons,
  `.regularMaterial` capsules and circles, `.bar` header via `safeAreaInset`,
  drawn glass for the icon tiles). The deployment target is 15, so an
  unguarded call would not compile. The new split-view window uses only old
  AppKit API (`NSSplitViewItem`, `NSToolbar`). **Not run on macOS 15** (this
  Mac is on 27): looked at in code only.
- **Glass slider removed** (Settings, Appearance; `Prefs.glassTintKey`,
  `GlassStyle`, `Theme.wash`, its search keywords). The window background is
  the plain system one, which is what Nick's own setting (Clear, 0) already
  showed. Old `glassTint` / `glassStyle` values stay in preferences, unused.
- **Full Disk Access window:** now "Allow PrismPack"; the Show in Finder and
  Quit and Reopen test aids are gone; a blue **Open System Settings** button
  opens the page (macOS 13+ address first, the older one as a fallback);
  steps say drag the icon or click +, and "If macOS asks, choose Quit &
  Reopen". **Not seen on screen** (opening it opens System Settings; Nick to
  click Allow… and look).
- **Name check (Nick, 3 Nov 2026):** the page is still Full Disk Access, but
  macOS's own search lists it as "Allow applications to access all user
  files" (Privacy & Security), so typing "full disk" finds nothing. The
  Allow window's first step now says both. Not rebuilt yet (batched with the
  next build).
- **After macOS's Quit & Reopen** (Nick tried it, it worked) PrismPack comes
  back in the menu bar without its window. Step 3 of the Allow window now says
  to click the prism to open the window again. Not rebuilt yet.

## Wording editor (3 Nov 2026) and a plan for in-app release notes

- **`docs/wording-editor.html`** (open it in a browser; saves in that browser
  as you type): every piece of 2.0 wording in one place. 39 fields: the rename
  pop-up (headline, three paragraphs, banner), the 21 "What's new" entries,
  **draft** release notes (Sparkle HTML and GitHub Markdown), the app
  description (README intro, repo one-liner) and the Allow window. Each field
  has Reset and a Locked tick. "Copy everything for Claude" puts all of it,
  with its locked / edited state, on the clipboard to paste into the chat; I
  then put the wording into the app, README and release files. It is generated
  from the Swift source by a script, so the starting text is exactly what is in
  the app now. Nothing is released from it.
- **In-app release notes (proposed, not built, needs Nick's OK):**
  - *Where:* Settings, in the first card under the name and version: a row
    "Release notes" with a glass **View…** button.
  - *What opens:* a sheet in the same style as the other sheets (close circle
    top right, glass menu to pick the version): this version first, any older
    version from the menu, "Open on GitHub" as the helper. The notes are the
    GitHub release's own text (Markdown shown as formatted text, links work).
  - *Source:* GitHub's releases list for the repo named in one place
    (`AppIdentity.repo`), fetched only when the sheet opens, cached in memory
    for that visit plus a small file in the data folder for offline. Works
    after the repo rename because GitHub redirects the old name. Drafts and
    betas are skipped unless the beta channel is on.
  - *Limits:* GitHub allows 60 unsigned requests an hour per network; one
    request when the sheet opens is nothing. Old releases that were made with
    "generate notes" show GitHub's generated list; those without text say "No
    notes for this version" with the GitHub link.
  - *Check:* light and dark, offline, a version with no notes, and macOS 15
    fallbacks (a plain sheet and bordered button).

## Round 2 of the wording, and how the beta reaches people (3 Nov 2026)

- Nick's locked wording from round 1 plus review fixes are in
  `docs/wording-editor.html` (now 32 fields, new storage key so round 1's
  edits don't mix in). Not applied to the app yet: grouping 21 entries into 14
  needs Nick's lock first.
- **Beta reach (found in code):** 1.8.0 has no per-app Stable / Beta choice
  (`docs/1.8.0-plan.md` lists it as not done), so a 1.8.0 install on stable
  sees only untagged appcast items. A beta item tagged `--channel beta` reaches
  nobody on 1.8.0; testers download the zip from the GitHub pre-release. Once
  running a beta (`VersionParts.track > 0`), PrismPack follows betas and the
  final 2.0.0 by itself. The Stable / Beta choice for PrismPack's own card
  already exists (Installed → PrismPack); a **Settings row** (GlassSegmented
  Stable | Beta writing `Channels.set(..., for: ownBundleID)`) would make it
  findable. Also needed: carry `channelChoices[old bundle ID]` to the new
  bundle ID in `EarlyMigration`, and `release.sh --channel beta` should add
  `gh release create --prerelease`. All three wait for Nick's OK.

## Built after Nick locked the wording (3 Nov 2026)

- Nick's round 2 lock: all 32 fields locked, one edit (the pop-up headline
  loses its "!"). Applied to `RenameWelcome` (story and the 14 grouped
  entries). The release notes and README text come from the same lock.
- **Settings → Beta versions** (a switch in Updating; writes
  `Channels.set(…, for: own bundle ID)`), found by Settings search ("beta").
  `EarlyMigration.carriedChannelChoices` copies an old bundle ID's choice to the
  new one. `release.sh --channel beta` now adds `gh release create --prerelease`.
- **Settings → Release Notes…** (button in the name card): `ReleaseNotes.swift`,
  GitHub's release list for `AppIdentity.repo`, drafts skipped, betas shown only
  on the Beta track, cached in `release-notes.json`, a version menu, Open on
  GitHub, and an offline message. 2 new tests pass (`ReleaseHistoryTests`).
- **README** rebuilt with logo, badges, hero shot, feature table, screenshots,
  Download, Upgrading, Safe by design; the older sections follow. Screenshot
  files expected in `docs/screenshots/`: `updates-light.jpg` (a placeholder
  capture is there), `discover-light.jpg`, `installed-light.jpg`,
  `updates-dark.jpg`, `settings-light.jpg`.
- Not yet seen on screen (the screen locked): the new wording in the pop-up,
  the beta switch, the release notes sheet. Screenshots for the README still
  to capture.

## Checked in the test build (3 Nov 2026, after the lock)

- Rename pop-up shows the locked wording (headline without "!", positive
  paragraph 2, paragraph 3 about macOS asking again).
- Settings: **Release Notes…** button in the name card opens the sheet; it read
  GitHub's real release list (Version 1.8.0 · Oct 28, 2026 shown, formatted
  notes, version menu, Open on GitHub). **Beta versions** switch is in Updating
  (off), found by search. Theme set back to Light, Discover and Updates back to
  List.
- README screenshots captured from the test build (active window, light and one
  dark): `docs/screenshots/updates-light.jpg` (cards), `discover-light.jpg`
  (cards), `installed-light.jpg`, `settings-light.jpg`, `updates-dark.jpg`;
  `logo.png` is the 256 px dark icon. Nick may replace any with retina captures
  using the same names.
- Not checked: release notes sheet in dark, the offline message, the beta switch
  actually changing what Sparkle offers (needs a published beta), macOS 15.
- Locked release notes saved as docs/release-notes-2.0.0.html (Sparkle) and .md (GitHub) for scripts/release.sh --channel beta <version> <html> <md>. The version string for the beta is chosen at release time; Info.plist says 2.0.0.
