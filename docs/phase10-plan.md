# Phase 10: Discover rework and consistency pass

Written 1 Nov 2026. Nick's requests and decisions are from the session that
made the mockups. **Not approved yet: nothing below is built.**

Mockups (approved designs, open in a browser):
[mockups/phase10-discover.html](mockups/phase10-discover.html) and
[mockups/phase10-round2.html](mockups/phase10-round2.html).

## Nick's decisions

- Not a CaskHub replica. Take the ideas (sidebar subcategories, sort, cards or
  list, one main button), keep PrismPack's look.
- **Top bar:** keep today's (sidebar button, title, one-line subtitle) on every
  page. Page-specific controls go in a row under it.
- **Categories:** our hand-made list first, then a guess from each cask's
  description, so every app lands somewhere.
- **Web details** (longer description, one screenshot): fetched only when an
  app's details open, then cached.
- **Betas:** inside each app's details ("A beta is available"), not a sidebar
  entry.
- **Tags:** keep the green "Installed" tag. When a list mixes sources, every
  card gets its source tag, with "Installed" stacked under it. One source
  only: no source tags. No download counts anywhere. Versions in the normal
  text font, written "Version 1.2".
- **Clicking a card or row anywhere** (except its buttons) opens its details.
  No ⓘ buttons.
- **Updates from cards:** cards keep their Update button. Installed and
  Discover show "N updates available · Review" under the top bar when there
  are updates; Review opens the Updates page.
- **⌘Q:** asks "Quit PrismPack?" with Close Window (⌘W) as the default, Quit,
  and "Don't ask again" (the right-hand version in the mockup). With
  background checking off, the first sentence says checks and automatic
  updates stop until PrismPack is opened again. Quit from the menu bar menu
  doesn't ask.
- **Memory and size:** approved rules under "Lightness" below.
- **Colours** (Nick, 1 Nov 2026): Install and Update buttons take the
  source's colour (Homebrew brown, npm red, and so on), as today. Selection
  highlights are grey or a faint rainbow, never purple.
- **Wording:** "Move to Trash" never has "…" after it.
- **Installed's "Update to x"** (Nick, 1 Nov 2026): today it's only a pill
  and does nothing. It becomes an **Update** button that updates right there,
  through the same queue and one-password batch as everywhere else
  (consistent with cards' Update buttons; Claude's call, Nick agreed either
  was fine). The orange reminder strip still leads to the Updates page.
- **Animations:** every change of what's on screen (pages, Discover's parts)
  uses the same quick fade.
- **Discover's card everywhere** (1 Nov 2026, mockup
  [mockups/phase10-cards.html](mockups/phase10-cards.html)): Updates and
  Installed use Discover's left-aligned card, with a Cards / List switch on
  all three pages. Updates stays grouped by source (each section in its colour
  with "Update all"); its cards show installed → new version in the source's
  colour and no source tag. Warnings use 2.0's round symbols (major version,
  restart, iPhone/iPad app) in the card's top-right corner, each opening its
  explanation. Installed is one flat list with the source pill and status
  stacked top right. "Ignore this version" and the old ⋯ menu move into the
  details pop-up.
- **Orphaned App Files, "Belongs to…"** (added 1 Nov 2026): pick the installed
  app the files belong to. PrismPack remembers it: the files leave the list
  and are offered with that app's own files when it's moved to the Trash.
  "Assigned files" at the bottom of the page undoes it.
- **Consistency check across every tab** before Phase 10 is called done:
  cards, rows, pills, buttons and pop-ups on Updates, Installed, Discover,
  Orphaned App Files, Activity and Settings, in light and dark.

## Progress

- **Step 1 done (1 Nov 2026):** `StatusPill.source/installed/upToDate/notManaged/update(to:)`,
  `versionLine`, `PageControls` and `UpdatesReminder` in `Views/Rows.swift`;
  Installed's source pills in colour; the reminder on Installed and Discover.
  `SourceStyle` already was the one colour table.
- **Step 2 done (1 Nov 2026):** sidebar order changed by Nick while building:
  Library first, Discover last (its parts open under it as one compact block),
  Activity and Settings pinned at the bottom in glass. Runtimes kept its own
  entry. Button lab removed. Discover tiles keep two description lines
  (Nick). Checked in light and dark (the app's Theme setting).
  Committed `5d7d199`.
- **Step 3 done (1 Nov 2026), not committed:** 12 categories with colours
  (`Discover/DiscoverCategories.swift`): hand-made list first, then a regex
  guess on the cask's description; tried on all 7,824 casks, about 80% of the
  5,207 non-font casks land in a category (the rest show in Featured, New and
  search). The model works out each cask's category once per catalogue
  (`categoryOf`). Three tests in `DiscoverTests` (list beats guess, guesses,
  known misfits). Sidebar names fit (smaller indent and counts).
- **Also this round (Nick, not committed):**
  - Moving between Discover's parts fades like moving between pages
    (`MainView.shown` in `Views/UpdatesWindow.swift`).
  - Duplicate pop-up had two identical Move to Trash buttons: on the extra
    copy the duplicate note no longer adds one (the pop-up's own button
    removes it); on the copy to keep it says "Move the Copy in <folder> to
    Trash". `UninstallButton` gained `title:`. **Seen live after a Check
    Now (1 Nov 2026):** the extra copy (~/Applications) has one Move to Trash;
    the copy to keep has "Move the Copy in ~/Applications to Trash" plus its
    own Move to Trash.
  - No "…" after Move to Trash anywhere (buttons; progress text keeps it).
  - The updates reminder is a light orange strip, as in the mockup.

Step 3 and the fixes are committed (`1e7cf0b`).

- **Step 4 built (1 Nov 2026), not committed, not yet seen on screen**
  (the screen was locked after the build). `swift build` passes; five
  Discover tests pass (three new: sort order, version-change dates, the
  source-tag rule). App built and signed, test build relaunched.
  Choices made while building: while searching, Popular keeps the best
  matches first; Featured and New sort within their own set, other parts
  sort the whole list and show the first 80; installed apps show Open,
  installed tools only the trash button; an app with no category shows
  "App". The update lookup moved from Installed to
  `UpdateController.update(for:)` so both pages share it. Registry dates:
  npm, crates.io, RubyGems, PyPI; editor extensions have none yet (they
  sort after dated ones).

- **Step 4 seen live (1 Nov 2026), light and dark** (Theme set back to
  Light): Featured cards, Browsers in cards and list (Firefox and Zen show
  Installed, Open and the trash button), search from Featured in sections
  (Homebrew, npm, …), Sort and Cards / List in the under-row, clicking a
  card opens its details. **Found, for the next build** (with Nick's
  feedback):
  1. Long Homebrew versions ("156.0.4314.58,bc665d48-…") crowd the row:
     show only the part before the comma, one line, truncated.
  2. While searching, the subtitle still says "Popular this month"; it
     should say what's being searched.
  3. Some npm descriptions show raw Markdown links ("[ripgrep](https://…)");
     show the link text only.
  4. The details pop-up still says "Uninstall" and is the old design; step
     5 replaces it.

- **Nick's feedback on step 4 (1 Nov 2026), plan proposed, not approved yet:**
  - Every card and row shows its **source tag** ("Homebrew", "npm", "PyPI",
    "cargo", "RubyGems", "Editors") so it's clear what it installs with.
    Cards: top right, "Installed" stacked under it. List: the tag, then
    "Installed" beside it, before the version. This replaces the earlier
    "one source only: no tags" rule.
  - The sidebar heading "Apps" becomes "Homebrew".
  - Too much brown. Proposed colour roles:
    - **Source colour = how it installs:** the source tag and the
      Install / Update button (the earlier rule, unchanged).
    - **Part colour = what it is:** the sidebar dot, the label under the
      name and the card's faint tint. Categories keep their colours;
      Command line becomes mint, Runtimes teal, Fonts grey; package pages
      keep their source colour.
  - Plus items 1 to 3 above.

  - **Built and seen live (1 Nov 2026), light and dark** (Theme back to
    Light), not committed. Source tags use the Installed page's names
    ("Homebrew", "Python (pip)", "Rust (cargo)" …). Command line mint,
    Runtimes teal (`DiscoverModel.Chip.color`, shared by the sidebar and
    the cards). Items 1 to 3 fixed (`shortVersion`,
    `DiscoverRegistries.plain`, search subtitle). Tests: 5 Discover tests
    pass (the mixed-source test replaced by one for the tidy-ups).
  - **Seen, for the next round:** in List view the tags and versions don't
    line up from row to row (version width varies); in dark, Productivity's
    yellow tint looks olive.

- **Round 3 (Nick, 1 Nov 2026), built and seen live, not committed:**
  Runtimes purple (mint and teal were too alike). An up/down arrow beside
  every Sort (`SortDirectionButton` in `Views/Rows.swift`; its tooltip
  says the order shown), remembered: Discover, and Orphaned App Files,
  whose Size / Name / Last changed chips became the same Sort menu.
  Undated items stay last either way. Installed gets its Sort and arrow in
  step 8 (Nick). Every tag has a thin outline in its colour (shared
  `StatusPill`, so app-wide). List rows: Installed stacks under the source
  tag; tag, version and button columns are fixed widths and line up.
  Yellow tint fainter in dark: better, though still a muted gold-brown.

- **Font previews** (Nick asked where they went, 2 Nov 2026): they were
  only ever in the mockup; step 6 builds them (full description under
  step 6 in the build order).
- **Screenshots** (Nick, 2 Nov 2026): the details pop-up shows up to 3
  pictures from the app's website (step 7 in the build order); step 5's
  pop-up leaves room for that row.
- **Round 4 (Nick, 2 Nov 2026), built and seen in light and dark, not committed:** the
  Sort menu (`SortMenu` in `Views/Rows.swift`) and the Cards / List switch
  (`GlassSegmented` with symbols) are Liquid Glass, matching the search
  field and the arrow, on Discover and Orphaned App Files.

- **Round 5 plan (Nick, 2 Nov 2026), waiting for Nick's OK.** One build:
  1. **Installed gets the new filtering now** (step 8's Installed part,
     pulled forward): the chip rows go. Under-row: search, a Show switch
     (All / Updates / Hidden, plus Duplicates when there are any), a
     Source menu (every source and Not managed), Sort (Name, Size, Date
     installed, Installation type) with the up/down arrow, and Cards /
     List. Sort and Cards / List remembered. Size and date are read from
     disk only when that sort is chosen, kept for the session; items
     without one go last. Cards are Discover's card: source tag top right
     with the status under it, "Version x", and an **Update** button in
     place of the "Update to x" pill. Clicking opens the details.
  2. **Updates:** more space between sections (12 → 20 points), and Cards /
     List. In Cards, each source section holds a grid of cards: installed
     → new version in the source's colour, the round warning symbols top
     right, Update button. No source tag (the section says it). Clicking
     a card opens today's details pop-up, which step 5 restyles.
  3. **Cards / List switch, smoother and draggable:** the switch is rebuilt
     as one glass track with a sliding glass bubble you can click or drag
     (it follows the pointer or a finger and snaps to the nearest side on
     release). The bubble moves first and the page swaps a moment later,
     so the slide isn't held up by the cards being rebuilt. The Theme
     switch in Settings uses the same control, so it gets this too.
  4. **Sort menu glass when closed:** its button gets the same glass
     capsule as the search field instead of the standard menu button.
  5. **UpdateScout → PrismPack animation** (`Views/RenameWelcome.swift`):
     the white shock ring knocks "UpdateScout" out as it passes (a quick
     flash, blur and fade), then the rainbow reveals "PrismPack" top to
     bottom with a soft edge, in step with the rays (Nick's ring idea,
     2 Nov 2026, chosen over the wipe). To see it in
     the test build, the one-time pop-up has to be shown again: Claude
     asks before resetting its "shown" flag in preferences.

- **Round 5 built and seen (2 Nov 2026), light and dark** (Theme back to
  Light), not committed. Installed: Show switch, Source menu, Sort with
  arrow, Cards / List, cards with tags, status, Update and trash
  (`InstalledMetrics` reads sizes and dates on demand; test added). Updates:
  20-point gaps, Cards / List with card grids inside sections. The glass
  switch slides on click and on drag (drag tested). Sort and Source
  buttons are glass capsules. Rename: ring knocks out the old name,
  rainbow reveals the new one; **not watched live** (the pop-up had
  finished before the first screenshot). Clicking the "UpdateScout is now
  PrismPack" banner on Updates replays it, so no preference reset is
  needed. Not tested: choosing from the Sort or Source menus (menus can't
  be opened in the background), and the Size and Date sorts on Nick's apps.

- **Round 6 plan (Nick's feedback, 2 Nov 2026), waiting for Nick's OK.**
  This pulls step 5 (the details pop-up) into this round. One build:
  1. **One details pop-up** for Updates, Installed and Discover (step 5):
     icon, name and source at the top; versions; "What's new"; then the
     controls in clear groups with even spacing instead of squeezed
     rows: hide options together; "Update automatically" as the glass
     slider (Use setting / Always / Never); Keep this version on its own
     line with its explanation. Bottom: helpers on the left (Info page,
     Show in Finder; the separate "Release notes" button goes, Nick),
     Close and the main action (Update, Install, Open) on the right,
     Move to Trash in red text set apart. Every button the same size.
     Betas offered here. (Built: "Uninstall" stays for Homebrew and
     packages, which are uninstalled rather than moved to the Trash; apps
     already say "Move to Trash".)
  2. **Updates cards show the first two lines of release notes** when the
     update has them (headings like "What's Changed" skipped, links shown
     as plain text). No extra downloads: the notes already come with the
     update.
  3. **App Store hand-off as a card**, always first in the Mac App Store
     section, filled with a solid soft blue rather than glass, so it reads
     as "open the App Store" rather than another update.
  4. **Updates list:** the Update buttons were cut off at the right edge;
     give the rows their proper trailing padding.
  5. **Installed:** more space above the first card, matching the sides.
  6. **Orphaned App Files:** each item gets its own buttons: Show files
     (the existing disclosure), Show in Finder, Keep, and Move to Trash
     (trash icon). Bulk actions for the ticked ones: Show in Finder (one
     Finder window with them selected), Keep, Move to Trash. Keep takes
     the item off the list and remembers it; a "Kept" section at the
     bottom undoes it (the same shape step 9's "Assigned files" will use).
  7. **Trash button only in the pop-up:** cards and rows no longer show a
     trash button; Move to Trash is in the details pop-up (point 1).
  8. **Settings, Setup:** both lines the same size. Dependencies becomes
     a row you can open, listing each one (Homebrew, mas-cli and the
     others PrismPack uses) with its version and Reinstall; Remove only
     for the small tools, never Homebrew itself (removing Homebrew would
     remove everything it installed; PrismPack points to Homebrew's own
     uninstall instructions instead).

  9. **Updates top bar like the other pages** (Nick): the row of controls
     (Cards / List, with the "Click an app for details" hint) moves out
     of the scrolling list into the pinned glass header, above the
     "UpdateScout is now PrismPack" banner, with the same hard edge the
     other pages have, so the sections scroll in behind it.
  Nick's answers: trash in the pop-up only, on every page; Keep hides and
  remembers, with a Kept section to undo; dependencies: Remove only for the
  small tools, never Homebrew.

- **Round 6 built (2 Nov 2026), not committed.** Seen live in light:
  Updates header (controls above the banner, sections scroll behind),
  list buttons no longer cut off, cards with two lines of release notes
  (`UpdateDetailView.preview`, tested), the App Store card (solid blue,
  first), the new pop-up's groups, slider and footer (only partly visible
  in a capture), Orphans' bulk buttons, Settings' Setup lines and the
  dependency list (a plain button, not a disclosure group, which didn't
  open from an accessibility click). Installed's list panel is no longer
  lazy (its bottom edge drew in the wrong place). Not tested: Reinstall /
  Remove for mas-cli (real tool), Keep / Put back and the per-item buttons
  on real orphans, dark mode for this round.

- **Round 7 (Nick, 2 Nov 2026), built and checked in light and dark:**
  "Info page" is "Website"; every pop-up (details pop-ups, warning
  badges, the log and adoption sheets) closes with a small glass circle
  top right (`.popupClose()`, Escape too) instead of a Close button; Move
  to Trash / Uninstall is a red button again in every pop-up and on each
  orphan; the rename banner is a rainbow strip the same shape as the
  orange updates strip, inside the header's controls; Discover's pop-up
  for an installed app has Open as its main button, as on Installed;
  Stable / Beta uses the glass slider. Long lists (Installed and Discover
  in List view) sit on a frosted `ListPanel`: Liquid Glass draws only what's
  on screen and put a rim where the window cut it off, which was the false
  bottom edge Nick saw while scrolling. Dependencies now list pipx, Node
  and npm, Rust and cargo, and Homebrew's Ruby too (optional: not flagged
  when missing), with Install, Reinstall and a red Remove, the last two
  only for copies Homebrew installed (versioned formulae like `node@22`
  included); Homebrew itself links to its own uninstall steps.

## Status at handoff (2 Nov 2026; patterns updated after rounds 9-11)

**Consistency is the first rule from here on (Nick).** Before adding or
changing anything, match what's below; when something new doesn't fit,
ask Nick rather than invent a new pattern.

**The patterns now in place** (use these, don't make new ones):

- **Page layout:** the window's top bar (title, subtitle). The page's own
  controls sit in the pinned glass header (`PageControls`), above any
  banner strip; the content scrolls in behind it.
- **Controls:** search is `GlassSearchField`; menus are `SortMenu` (a glass
  capsule, also the Source menu); sort direction is `SortDirectionButton`
  (its tooltip says the order shown); any choice between a few options is
  `GlassSegmented` (click or drag, the page swaps just after the bubble
  moves): Show filters, Cards / List, Theme, Update automatically,
  Stable / Beta. No chip rows for filters.
- **Cards / List** on Discover, Installed and Updates, remembered per page.
- **Cards:** icon, name, a label under the name; tags top right (source
  tag, then status under it); "Version x"; buttons bottom right; clicking
  anywhere else opens the details. No trash button on cards or rows.
- **Tags:** `StatusPill`, with a thin outline in its own colour; source
  names as on Installed ("Homebrew", "Python (pip)", "Rust (cargo)"…).
- **Colours:** the source's colour says how it installs (source tags,
  Install and Update buttons); the part's colour says what it is (sidebar
  dot, card tint, the label under the name). Discover: the 12 categories'
  colours; Command line mint, Runtimes purple, Fonts grey; package pages
  use their source colour. Selection is grey, never purple.
- **Pop-ups:** close circle top right (`.popupClose()`); helpers bottom
  left (Website, Show in Finder); Move to Trash or Uninstall as a red
  button; the main action (Update, Install, Open) bottom right; every
  button the same size; options in labelled groups with even spacing.
- **Destructive actions are always red tinted glass** (`glassDestructive()`):
  delete, remove, Move to Trash and Uninstall, everywhere.
- **Dropdowns are glass menus** (`SortMenu`), Settings included; no plain
  system pop-up buttons, no unstyled buttons.
- **Strips:** the orange updates strip and the rainbow rename strip share
  one shape.
- **Lists:** each row is its own small glass panel, like the cards (never
  one tall glass panel: glass draws only what's on screen and put a rim
  where the window cut it off).
- **Wording:** "Website" (not "Info page"); "Move to Trash" for apps,
  "Uninstall" for things that are uninstalled; never "…" after Move to
  Trash; "Version 1.2" in the normal font.
- **Motion:** pages, Discover's parts and Cards / List fade in 0.14 s.
- **Numbers:** `GlassStepper` (− n + on one glass capsule), never the
  system stepper.
- **Tags:** never wrap (`StatusPill` is one line at its own width).
- **Refresh arrows** spin while working and aren't greyed out (Updates'
  Check Now, Installed's Refresh, Orphaned App Files' Rescan).
- **Settings** is a page like the others: full width, search and Check
  for Updates in the pinned header, name and version as the first card.
- **Pop-ups** stay arrow pop-ups (Nick chose this over sheets); Updates'
  and Installed's are 540 wide.
- **Anything that moves a user's app** (duplicates, Use Homebrew's copy,
  Move to Homebrew) asks first naming the folders, re-checks right
  before acting (not open, the kept copy whole, never the last copy),
  and puts things back if a step fails. Nick: "airtight".

**More patterns, added 2 Nov 2026 (steps 12, 6, 7 and the install-progress
work; use these too):**

- **Strips:** one shape, `.strip(fill)` in `Style.swift`: the orange updates
  strip, the rainbow rename strip, the teal Homebrew strip and the
  duplicates strip all sit in the pinned header and share it.
- **Row buttons** on Orphaned App Files are all small (`.controlSize(.small)`);
  **Show in Finder is icon-only on rows and bars** (tooltip says it); pop-up
  footers keep the text.
- **Shared folders** look like normal rows: a `WarningBadge` (hover tooltip,
  click popover) where the checkbox would be, a greyed trash button.
- **Install progress:** one `InstallProgressView` everywhere (cards, rows,
  pop-ups). A bar and a small % only where something is measured; otherwise a
  spinner, the step word and "Can't measure progress" (plus the time after a
  minute). Never an invented percentage. Data: `InstallProgress` (pure parser)
  kept per item in `UpdateController.installProgress`.
- **Network features load on demand and in memory only** (font previews and
  styles, step 6) or are cached with a cap (web details, 50 MB). Nothing is
  fetched for tiles; details fetch when a pop-up opens.
- **Pop-ups need real buttons for anything clickable:** the automation can't
  click inside a pop-up with a raw click (it lands on the page behind), only
  press an accessibility button; a bare tap gesture isn't one. Label them.

**Done in Phase 10:** steps 1 to 4; most of step 5 (one pop-up layout on
Updates, Installed and Discover; the beta offer is still the Stable / Beta
section where an app has one); step 8's Installed and Updates work
(pulled forward); Orphaned App Files' item and bulk buttons and Kept;
Settings' dependency list; the rename animation (the white ring knocks out
"UpdateScout", the rainbow reveals "PrismPack"; replay it from the rainbow
strip on Updates).

**Also done (committed 2 Nov 2026):** step 12 (consistency pass), step 6
(font previews and the pop-up's style list), the install-progress work
(commit `2d4af7a`) and step 7 (web details, `4abde8c`).

**Left in Phase 10 (3 Nov 2026):** steps 9, 10, 11, 12b and the pictures work are built, checked and committed (step 11 `ad7d6af`, 12b `f7af3af`, pictures `cbc6e88`; nothing pushed). Left, in this order:
1. **Memory with the window closed** (approved 3 Nov; [memory-plan.md](memory-plan.md)): 152 MB closed after use vs 15 MB fresh; give freed memory back, free Discover's catalogue on close, re-measure.
2. **Step 13, the final review**, which now also holds: Productivity's yellow tint (gold-brown in dark, needs Nick's colour decision); the "What's new in 2.0" fine-tune ([whats-new-2.0-proposal.md](whats-new-2.0-proposal.md)); the Phase 9 leftovers list; dark-mode check of the new pop-up picture view and a try of the ← → / Esc keys inside it (automation can't send keys there; Nick tried them in the window, which work); the pop-up that hangs past the window's bottom edge (Nick: leave); the Lightness before/after table.
Done by Nick on 3 Nov: the ← → keys in the larger-picture window work.

**Step 10, other sources (built 2 Nov 2026, uncommitted;
[step10-other-sources-plan.md](step10-other-sources-plan.md)):** Settings'
GitHub releases and Custom sources are one "Other sources" list (icon, name,
detail line, GitHub / Custom tag, background switch on custom rows, red
Remove), with Add a Source… and Open File. The new `Views/AddSourceSheet.swift`
has a GitHub | Custom toggle; Custom has App, Name, version page, Open the
download page | Run a command, Advanced (installed-version command, plist key,
JSON key, pattern) and Test; Add stays off until Test works on exactly those
fields. A page with no JSON key or pattern gets a guess (version / tag_name /…
or a version-like number), kept in Advanced so what was tested is what's
saved. The sheet reads the window's height when it opens, never grows past it
(window height minus 60) and scrolls its fields, with Test and Add pinned.
`GlassField` is the one new control (a text field on the search field's glass
capsule). Saved entries use the existing `custom_sources.json` format; new
ones start off for the background check. **Checked in the test build:** list
in light and dark; the sheet's GitHub and Custom tabs in light and dark;
Advanced open fits inside the window; throwaway add (installed `echo 1.0`,
displaylink cask page: "Installed 1.0, latest 17.0,2026-09. (read from the
"version" key)"), the row appeared with background off, Remove deleted it,
`custom_sources.json` and the background list identical to before; Theme back
to Light. First build's sheet ran past the window with Advanced open (fixed).
**Not checked:** the App menu (menus can't be opened in the background), Run
a command, a GitHub link through the new sheet. Tests: `AddSourceTests`
(temp file only), 4 pass.

**Not verified live:** choosing from the Sort and Source menus (menus can't
be opened while Claude works in the background); the Size and Date sorts
on Installed; the whole details pop-up in one view (it ran past the edge of
what a capture shows); Reinstall / Remove / Install in Settings (real
tools, not throwaway); Keep, Put back and the per-item buttons on real
orphans; watching the rename animation play. The Orphaned App Files scan
starts again on every visit to the page and takes a while.

**Testing notes from this session:** buttons look grey in captures when the
window isn't in front (macOS draws inactive windows that way) and while a
check runs. Run only the Discover tests that don't touch the data folder
(the filter list in this session's commands); the full suite needs Nick's
OK. Clicking the rainbow strip on Updates replays the rename pop-up, so no
preference reset is needed to see it.

**Round 8 (Nick, 2 Nov 2026, after the handoff notes):** list rows back on
glass, every delete button red tinted glass, Settings' and the GitHub
sheet's dropdowns and plain buttons in glass, the GitHub sheet closes with
the circle. Adoption for apps nothing manages is built ("Can adopt" on
Installed, the review sheet, Settings → Homebrew adoption) but can't be
seen in a test build while the 1.8.0 agent rewrites `state.json` without
2.0's fields; checking it needs the agent paused (ask Nick).

**Round 9 plan (Nick, 2 Nov 2026), not built; waiting for Nick's OK.**
One build:
1. **Installed tags:** status pills never wrap or cut off ("Update to
   3.0.0-beta.5" wrapped to two lines, "Update to 22.23.4_2" was cut);
   pills stay one line at their own width, and the tag column sizes to
   them. When a card or row has no line under the name, the name gets that
   room (up to two lines on cards).
2. **App Store apps found by their App Store receipt** (Creator Studio
   apps showed as Not managed): `mas list` names them "Pages", "Keynote",
   and so on, while the apps are "Pages Creator Studio.app"; match on the
   bundle's own name (CFBundleName / display name) among apps with an
   `_MASReceipt`, so they count as App Store apps. Unit test for the match.
3. **Update at once:** one glass pill with − number + inside it (a shared
   `GlassStepper`), not the system stepper.
4. **Glass menus' text** in primary colour (it read grey, e.g. "5 minutes").
5. **Settings top bar like the other pages:** the pinned glass header holds
   a search field (and Check for Updates); the PrismPack name and version
   become the first section of the form. **Search** filters Settings to
   the sections and rows whose words match.
6. **Activity:** each entry on its own glass row (no broken bubble); kinds
   in their own colours (Updated green, Installed blue, Removed pink,
   Failed red, Skipped grey, Checked purple-free neutral; one table); the
   under-row gets search, a Show menu by kind, and the date and time on
   every row; tick entries to delete them, or Delete all. Entries stay
   until deleted (check there's no automatic trim; if there is, show it).
7. **Not bugs, testing setup:** Activity emptying and Zoom's missing "Can
   adopt" come from the installed 1.8.0's agent rewriting `state.json`
   every 5 minutes without 2.0's fields. Checking both needs the 1.8.0
   agent paused (ask Nick; turn it back on after).

**Round 9 built (2 Nov 2026), not committed.** Nick's choices: Activity
colours Updated blue, Installed green (green means installed everywhere),
Removed red, Failed pink, Skipped and Cancelled grey, Checked graphite,
Adopted Homebrew's colour; the 200-entry cap is gone (entries stay until
deleted); tick boxes with "Delete N" / "Delete All" (asks first) in the
control row; full date and time on every row. Settings search matches
section names, setting names and explanations; "No settings match" when
empty. Status pills never wrap anywhere (`StatusPill` is one line at its
own width). Added in the same build at Nick's request: the Sparkle
pop-up's footer buttons no longer cut off (Update pop-up 540 wide, labels
at full width); casks named unlike their app ("flux-app" → Flux.app) are
tied to it from `brew info`; duplicates are worked out when Installed
loads, not only after a check (Flux's two copies showed no tag); a "Link
to GitHub…" row on Not managed apps' pop-ups opens the Settings link
window with the app chosen (an unsigned app says it can't be linked). Pop-ups
keep the arrow style (Nick); macOS still picks the side by room.

Checked in the test build: Installed tags one line ("Update to 22.23.4_2"),
rows with no detail line, menu text dark, Flux tied to its cask with
Duplicate on both copies (light and dark), Thaw's pop-up footer, the GitHub
window on qView (unsigned message), Settings header, search ("dock",
"theme"), the glass stepper, Activity's controls (empty page) in light and
dark; Theme set back to Light. Tests: the 7 Discover tests, the new App
Store match tests and `activityIsKeptUntilDeleted` pass.
**Not verified:** dark mode (the change touches no views); whether SwiftUI
state is released (heap fell to 19.7 MB, so most of it is); Installed's list
stays on `UpdateController` after close and was not touched. The Installed
reading rose (114 vs 109 MB): run-to-run variation, not investigated.

**Survivors checked (3 Nov 2026, closed window, `heap -sortBySize`).** Nothing
big is left: 21 MB live in total, the largest items being non-objects 6 MB,
Swift metadata 4 MB, CoreSVG (SF Symbol drawing) about 2 MB, ObjC method caches
1.9 MB. No catalogue, no Installed list worth clearing. The rest of the
footprint is fragmentation: live objects scattered over about 107 MB of malloc
pages. macOS slowly compresses the idle pages (89 MB right after close, 73 MB a
few minutes later), but they still count. Clearing more state would not help;
only not dirtying those pages in the app process would (decode the catalogue
and parse `brew info` in a short-lived helper process, or search a
memory-mapped compact file). Both are bigger designs and need their own plan.

## Sidebar toggle fix (3 Nov 2026), built into the code, not yet run

Nick: on macOS 27 the collapse button belongs in the sidebar's own toolbar
section (left of the divider) and stays when the grey hides. The old
`ToolbarItem(placement: .navigation)` landed in the detail toolbar. Now
`DefaultToolbarItem(kind: .sidebarToggle, placement: .navigation)` (macOS 26+,
confirmed in the SDK), old button kept for macOS 15. Compiles. To check in the
next build: its position collapsed and open, light and dark. Fallback if it
lands wrong: AppKit `NSToolbarToggleSidebarItemIdentifier` plus
`NSToolbarSidebarTrackingSeparatorItemIdentifier`. Reusable notes:
[liquid-glass-guide.md](liquid-glass-guide.md).

## Lightness: before and after (3 Nov 2026, step 13)

`footprint <pid>` on the test build, GUI process only, same five moments as
[memory-plan.md](memory-plan.md). "Before" is the table there (before the memory
work, commit `1df9945`); "After" is a fresh run of the final build.

| Moment | Before | After |
|---|---|---|
| Fresh launch, window never opened, 20 s idle | 15 MB | **15 MB** |
| Updates page open | 60 MB | 69 MB |
| After Installed has loaded | 109 MB | 115 MB |
| After Discover has loaded | 151 MB | 127 MB |
| **Window closed**, 10 s later | 152 MB | **114 MB** |
| Window closed, about 2 minutes later | n/a | 114 MB |
| Window closed, about 5 minutes later | n/a | 95 MB |

Live heap objects with the window closed: 19.5 MB (nothing big is held). The rest
is fragmented malloc pages that macOS compresses slowly. The first run after
`1df9945` read 89 MB right after closing and 73 MB a few minutes later, so this run
is higher than that one; run-to-run variation (Installed's `brew info` and
icon decoding) is large. No helper process (Nick's decision). Not re-checked:
whether a second `MemoryRelief` pass a few seconds after closing returns more.
