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

**Left in Phase 10:** step 9 is built (uncommitted; [step9-belongs-to-plan.md](step9-belongs-to-plan.md)), step 10 is built and checked (uncommitted; see below), step 11 (⌘Q prompt) is built and checked (uncommitted) and step 13 (final review). Also: Productivity's
yellow tint still looks gold-brown in dark (needs a colour decision);
"What's new in 2.0" new wording is in the app (Nick approved it 2 Nov;
fine-tuned in step 13, [whats-new-2.0-proposal.md](whats-new-2.0-proposal.md)); the arrow keys in
step 7's larger-picture window (Nick to try; automation can't send keys to a
panel); the Phase 9 leftovers list.

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
**Not verified:** Activity rows, colours, ticking and deleting (Activity is
empty while the 1.8.0 agent rewrites `state.json`; needs it paused);
Creator Studio apps as App Store (no such app here to see); linking a
signed app end to end (writes the real `github_sources.json`); Delete All's
confirmation.

**Round 10 plan (Nick, 2 Nov 2026), approved and built (see below).** One build:
1. **Duplicates you choose between.** Installed shows one row per
   duplicated app (tag "2 copies"), not one row per copy. Its pop-up
   compares the copies side by side: folder, version, size, times opened
   and last opened (macOS's own counts), and "Open now" on a running copy.
   The suggestion goes to the copy that's open, then the one opened most;
   the user picks which to move to the Trash. Rules that can't be skipped:
   never the copy that's open (checked by its path at the moment of the
   move), never the last copy, the copy kept must still be there and
   intact, and a confirmation names the folder being moved. Data folders
   are shared by both copies and never touched; the pop-up says so.
   Found: Flux runs from ~/Applications (31 opens) while the old rule
   kept /Applications (6 opens).
2. **Apple's own apps** (Safari and the like: `com.apple.` IDs with no
   App Store receipt) show as **macOS**, updated by Software Update, not
   Not managed.
3. **GitHub linking:** unsigned (ad-hoc) apps can be linked after a clear
   warning (only the app's ID is checked; anyone who takes over the GitHub
   project could ship a bad update). The window: the app list includes
   unsigned apps (marked); choosing an app searches GitHub straight away
   and lists matching projects in a search menu, the best one that checks
   out chosen for you; you can search other words or paste a link.
4. **Consistency:** Settings full width like the other pages; Activity
   gets the sort direction arrow (Newest first / Oldest first); the
   refresh arrows on Installed and Orphaned App Files spin while working
   and aren't greyed out, like Check Now on Updates.

**Round 10 built (2 Nov 2026), not committed.** As planned, plus: the
pop-up's own Move to Trash is hidden for duplicates (each copy has its
own); Installed's pop-up is 540 wide like Updates'; Apple's apps can't be
removed from here; an unsigned link never runs an installer package, only
an app download with the same ID. Checked in the test build: Flux as one
row ("2 copies"), its pop-up comparing ~/Applications (open now, 31 opens,
suggested) and /Applications (6 opens, Homebrew), the open copy's button
greyed out; a real move on a throwaway app (two copies in ~/Applications):
confirmation named both folders, the chosen copy went to the Trash and the
list dropped to one; Safari as macOS; RoTools in the GitHub window
(preselected, "not signed", warning and trust box, search ran by itself,
none of the top three was Nick's project); Settings full width; Activity's
sort arrow; the Installed refresh arrow spinning; light and dark, Theme
back to Light. Tests: 14 pass (7 Discover, App Store match, duplicate
choice, macOS apps, Activity). **Not verified:** linking a project end to
end (writes the real `github_sources.json`); moving a Homebrew-installed
copy (also drops Homebrew's record); Orphaned App Files' Rescan spin;
Activity rows (agent).

**Round 11 plan (Nick, 2 Nov 2026), approved and built (see below).** One build:
**"Use Homebrew's copy"** for duplicates where one copy is Homebrew's.
- **Where:** the duplicates comparison in the pop-up, under the copies,
  shown only when one copy is Homebrew's and another isn't. Glass button in
  Homebrew's colour (it installs from Homebrew), like the other Homebrew
  actions.
- **Confirmation** (asks first, names the folders):
  "Use Homebrew's copy of Flux?" / "Flux in ~/Applications moves to the
  Trash and the copy in /Applications, which Homebrew keeps, is the one you
  use from now on. Settings and data are shared and stay put. [If open:]
  Flux is open: it quits now and Homebrew's copy opens in its place. If
  Flux opens at login, turn that on again in Flux once it's open."
  Buttons: "Use Homebrew's Copy", "Cancel".
- **Steps,** shown as progress on the button: quit the running copy (stop
  if it doesn't quit within 10 s, nothing changed); the same checks as
  every duplicate move (Homebrew's copy there and whole, same app ID,
  never the last copy); move each other copy to the Trash; if one was open,
  open Homebrew's copy and wait for it to run. If it doesn't open, put the
  moved copy back from the Trash and say so.
- **After:** one row for the app, tagged Homebrew; Activity logs
  "Switched to Homebrew's copy" with the folder moved.
- **Not changed:** single apps keep "Move to Homebrew…"; App Store copies
  are never offered this; login items aren't touched (macOS keeps them by
  location; the confirmation tells the user).
- **Test:** throwaway only (a dummy app as a fake cask copy is not
  possible without Homebrew, so the flow is tested with two dummy copies
  and the Homebrew check stubbed in a pure test; the button is checked
  visually on Flux without pressing it).

**Round 11 built (2 Nov 2026), not committed.** "Use Homebrew's copy" as
planned (`UpdateController.useHomebrewCopy`, `Duplicates.homebrewCopy`).
Checked in the test build: Flux's pop-up shows "Keep only Homebrew's copy"
with the button in Homebrew's colour, in light and dark; the confirmation
reads as planned (names both folders, says Flux quits and Homebrew's copy
opens, the login note); Cancel left both copies and the running Flux
untouched. Tests: `HomebrewCopyTests` (offered only with exactly one
Homebrew copy and no App Store copy) plus the earlier 14, all pass.
**Pressed for real on Flux (Nick's go-ahead, 2 Nov 2026):** the
~/Applications copy quit and went to the Trash, Homebrew's /Applications
copy opened and runs, Activity logged "Switched to Homebrew's copy",
Homebrew still tracks flux-app, and Installed shows one Flux row
(Homebrew). The put-back path (Homebrew's copy won't open) wasn't
exercised. Found and fixed after: Installed published the list before
the duplicate rescan, so Homebrew's Flux was briefly hidden and Show
Duplicates read "Nothing matches"; duplicates are now worked out first
(compiled, not yet seen in a build).

Outlook (2 Nov, 11:58): moved to Homebrew; the old app went to the Trash
and Microsoft's 1.2 GB installer ran for about a minute, so Outlook was
missing meanwhile. Installed and working (Nick confirmed). Its data folder
was never touched.

**Open items from rounds 9-11** (not bugs found in code, just unchecked):
Activity rows, colours, ticking and deleting (needs the 1.8.0 agent
paused; ask Nick); Creator Studio apps as App Store (none on this Mac);
linking a GitHub project end to end; moving a Homebrew-installed duplicate
copy; the put-back path of Use Homebrew's copy; the list-order fix in
`loadInstalled` (in `44b7156`, compiled, not seen in a build). Nick's
RoTools is ad-hoc signed: it can be linked after the warning once he
pastes its project link.

**Step 12, the consistency pass (2 Nov 2026), built, not committed.** Nick
approved the list; one build. Changes: one shared strip shape (`.strip(_)`
in `Style.swift`) for the orange updates strip, the rainbow rename strip,
the teal Homebrew strip and the duplicates strip, the last two now inside
the pinned header instead of flat full-width bands; "Not now" and
Adoption's Show / Hide are glass; Discover's pop-up is 540 wide like
Updates and Installed; unused `ChipButton` removed; Orphaned App Files has
a top-bar subtitle, its "Show files / Hide files" and folder buttons are
glass; Uninstall's Cancel (glass), Done (main action) and the Full Disk
Access helper's Close and Show in Finder are glass; error and warning text
and the move-progress icons use the readable red, orange and green (dark
mode); Activity's search says "Filter activity" and its menu "All
activity"; Adoption's, Settings' dependency list and Major-upgrade Notes'
animations are 0.14 s fades. Checked in the test build, light and dark
(Theme back to Light): Updates strips, Activity controls, Orphaned App
Files header, Discover pop-up width, Installed → Duplicates (not blank).
**Not changed:** the other pop-up widths (340 to 560 are windows with
different jobs); Productivity's gold-brown tint in dark (needs a colour
decision); the "1.8.0" version label (bumped at release).
**Not seen:** Activity rows and colours (agent rewrites `state.json`), the
Uninstall and Full Disk Access helper windows (real apps / settings), the
teal Homebrew strip (no candidates right now), and the exact "Use Homebrew's
copy" race (Flux is already switched; Installed and Duplicates load with
no "Nothing matches").

**Step 12 follow-up (2 Nov 2026, Nick), built, not committed.** Orphaned
App Files: a shared folder's row looks like a normal row. The checkbox slot
holds a `WarningBadge` ("Shared folder", hover tooltip and click popover,
like "Requires restart"), Show in Finder and Keep are the same as on other
rows, and the trash is there but greyed out (shared folders are never moved
from here); the long orange sentence is gone from the row. All four row
buttons (Show files, Show in Finder, Keep, trash) are small; Show in Finder
is icon-only on rows and in the bulk bar (pop-up footers keep the text).
Checked in light and dark; the popover opened. Theme back to Light.

**Step 6, font previews (2 Nov 2026), built, not committed.** Discover →
Fonts: each font card and row draws "The quick brown fox jumps over the lazy
dog" in the font, fetched from Google Fonts (`Discover/FontPreview.swift`)
for the cards on screen, four at a time, only the sample's letters (a few
KB), through an ephemeral session. The font is held in memory as a
descriptor and drawn with `Font(CTFont)`: never installed, registered or
written to disk; everything is dropped when the page is left or Fonts is
left. The family comes from the cask's title ("JetBrains Mono"; Google
wants the family's own capitals), Nerd Font and NF builds and anything
Google lacks show the description slot empty (name only). A note at the top
of the page says so. Cards and List both show it. Found while building: a
card's own `.task` was cancelled by the lazy grid, and the page's old copy
released the fonts right after the new one started fetching; fetches now run
on the store and release only when the page is really left. Tests:
`FontPreviewTests` (title to family, Nerd Fonts skipped, Google CSS read,
only Google's file host followed). Checked in light and dark, Cards and
List; Theme back to Light. **Not seen:** the fetch under a slow or failed
connection (falls back to name only by design).

**Records of the 2 Nov 2026 builds:** [install-progress-plan.md](install-progress-plan.md)
(install progress and the font pop-up's styles, built and checked, including the
Krita download that showed the bar fill) and
[step7-web-details-plan.md](step7-web-details-plan.md) (built and checked).
The step 9 plan is [step9-belongs-to-plan.md](step9-belongs-to-plan.md).

**Next:** a new session reads the starter in [next-session.md](next-session.md):
step 9 (after Nick's OK on its plan), then steps 10, 11 and 13, with the
"What's new" wording approval and the leftovers above.

## Step 4 plan: Discover page

Files: `Views/DiscoverPage.swift`, `Discover/DiscoverModel.swift`,
`Discover/DiscoverCatalog.swift` (only if Nick picks option A for the first question), `Prefs`, tests in
`DiscoverTests`. The details pop-up stays as it is until step 5, apart from
the change in point 4.

1. **Top bar.** Title "Discover" on Featured, "Discover · Browsers" (and so
   on) elsewhere. Subtitle: "Popular this month", "Added in the last 30
   days", "N apps" (categories), "N tools" (Command line, Runtimes), "N fonts",
   or what a package page searches ("Searches npm. Packages install
   globally.").
2. **Row under the top bar** (`PageControls`): search field, a Sort menu
   (Popular, Name, Newest, Recently updated) and a Cards / List switch, then
   the orange updates strip. Both chip rows go. Sort and Cards / List are
   remembered in preferences.
3. **What each part shows.**
   - Featured: popular apps. New: added in the last 30 days (today's
     hint while it's empty). A category: its apps. Command line, Runtimes,
     Fonts: their Homebrew lists. Fonts get ordinary cards until step 6.
   - Python, Node, Rust, Ruby, Editor extensions: a one-line note on what
     it searches and how it installs, popular ones first where we have
     them (Python's list), results once you type.
   - **Search covers the part you're in.** On Featured and New it covers
     everything (Homebrew and every source that's switched on).
   - Sort applies to every list. Popular means installs for Homebrew,
     downloads for the other sources.
4. **Cards** (as in the mockup): icon, name, and the category in its colour
   under it (package pages show the source name in the source's colour);
   tags top right (source tag only when the list mixes sources, "Installed"
   under it); two lines of description; "Version 1.2"; buttons bottom right:
   - not installed: **Install** in the source's colour
   - update waiting: **Update** (same queue and password batch) and a
     trash button
   - installed app: **Open** and a trash button
   - installed tool or package: the trash button only
   The trash button runs today's Move to Trash, with its confirmation.
   Clicking anywhere else on the card opens the details. The download
   count comes out of the details pop-up ("No download counts anywhere").
5. **List** shows one row per item: icon, name and category, a one-line
   description, the tags, "Version 1.2" and the same buttons. Clicking a
   row opens the details too. Switching between Cards and List uses the
   same fade as moving between pages.
6. **Tests:** sort order and the mixed-source tag rule, as pure functions
   (no data folder touched). `swift build`, these tests, one app build,
   then a check in light and dark (app Theme, set back to Light) and
   screenshots for Nick.

**Nick's answers:** dates, option A, track version changes (1 Nov 2026).
Search from Featured: **a section per source**, as today, no source tags
(Nick, after the pros and cons: each section sorts fairly by its own numbers
and nothing shifts while slower sources answer). Sort applies within each
section.

**Questions as asked:**
- *Newest / Recently updated for Homebrew:* Homebrew's list has no dates.
  PrismPack already notes when an app first appears (that's how New works).
  (A) It also notes when an app's version changes. The dates fill in over
  the following days, and undated apps sort after dated ones by
  popularity. That adds one small file next to the existing one.
  (B) Leave Recently updated out for Homebrew. The other sources give real
  dates either way.
- *Searching from Featured:* (A) one list with source tags on every card,
  as the tag rule says, or (B) one section per source, as today, with no
  tags.

## Build order

Each step builds, gets checked in light and dark, and is shown to Nick before
the next. No rebuild while Nick is mid-step.

1. **Shared pieces** (`Views/Style.swift`, `Views/Rows.swift`): one source
   colour table used everywhere; status pill colours; "Version x" text; the
   top bar + under-row layout; the updates reminder line.
2. **Sidebar** (`Views/UpdatesWindow.swift`): Discover with its parts nested
   while open (Featured, New, 12 app categories with counts, Command line,
   Fonts, Python, Node, Rust, Ruby, Editor extensions); Library group;
   Activity; Settings. Remove the Button lab page.
3. **Categories** (`Discover/DiscoverCategories.swift`): grow to the 12
   categories (AI, Audio & Music, Browsers, Cloud & Storage, Communication,
   Design, Developer Tools, Games, Menu Bar, Productivity, Utilities, Video);
   description-based guess for unlisted casks. Unit tests for the guess.
4. **Discover page** (`Views/DiscoverPage.swift`, `Discover/DiscoverModel.swift`):
   drop both chip rows; search, Sort (Popular, Name, Newest, Recently
   updated) and Cards/List (remembered per page) in the under-row; cards and
   rows as mocked; source tags by the mixed-list rule.
5. **Details pop-up** (new `Views/DetailsPopup.swift`): one pop-up for
   Discover, Installed and Updates. Helpers bottom left, Close then the main
   action bottom right, Move to Trash in red set apart; beta offer;
   web description and a row of up to 3 screenshots (step 7).
6. **Fonts, BUILT 2 Nov 2026** (font previews; Nick asked for them again, 2 Nov 2026): as in
   the mockup, each font card draws a sample line ("The quick brown fox
   jumps over the lazy dog") in that font, previewed from Google Fonts
   without installing it. The cask's name (`font-inter`) maps to the Google
   Fonts family ("Inter"); fonts that aren't on Google Fonts show their name
   only. A line at the top of the page says so. Font files are fetched only
   while the Fonts page is on screen, for the cards being shown, and are
   neither installed nor kept: they're released when the page closes.
   Cards and List both show the sample.
7. **Web details, BUILT 2 Nov 2026** (new `Discover/DiscoverDetails.swift`): page description and
   **up to 3 pictures** from the app's homepage (Nick, 2 Nov 2026): the
   page's main preview image, plus up to two more large, screen-shaped
   images from the page (logos and small images skipped; one or none when
   nothing good is found), shown as a small row to click through. Fetched
   only when details open, shrunk before saving, dropped from memory when
   the pop-up closes; on-disk cache capped at 50 MB, oldest removed first.
8. **Installed and Updates pages** (`Views/InstalledPage.swift`,
   `Views/UpdatesPage.swift`, shared card in `Views/Rows.swift`): Cards / List
   switch on both; Discover's card; Updates kept in source sections with
   warnings top right; Installed gets All / Updates / Hidden,
   an Update button in place of the "Update to x" pill, a Source menu (show one installation type, e.g. Homebrew), Sort by Name,
   Size, Date installed or Installation type with a button that reverses it
   (A → Z / Z → A, largest / smallest first, newest / oldest first), both
   remembered; and the coloured source pill. Size and date installed are read
   from disk only when that sort is chosen (date: the app's 'date added', or the
   package's folder for Homebrew, npm, pip and so on), kept for the session,
   and items without one sort last; click opens details.
9. **Orphaned App Files "Belongs to…"** (`Views/OrphansPage.swift`,
   `Leftovers.swift`, `Store`): app picker (search, same-developer apps first),
   saved owner list in `state.json` via `Store.mutate`, "Assigned files"
   section to undo, and the assigned files offered in that app's Move to Trash
   window. Unit test that assigned files count as owned.
10. **Other sources** (`Views/SettingsView.swift`, `Views/GitHubLinkViews.swift`,
   new `Views/AddSourceSheet.swift`): one list, Add a Source… sheet (GitHub
   link, or app + version page + "open download page / run a command", Test
   button, Advanced for pattern / JSON key / version command). Saves to the
   existing `custom_sources.json` format, so 1.8.0 entries keep working.
11. **⌘Q prompt, BUILT 2 Nov 2026** ([step11-quit-prompt-plan.md](step11-quit-prompt-plan.md); uncommitted) (`AppDelegate.swift`): `applicationShouldTerminate` asks
    as above; "Don't ask again" stored in preferences.
12. **Consistency pass, BUILT 2 Nov 2026:** apply button placement to Move to Trash, adoption,
    duplicates and the major-upgrade review; filters as segmented control or
    menu; then go through every tab (Updates, Installed, Discover, Orphaned
    App Files, Activity, Settings) checking cards, rows, pills, buttons and
    pop-ups match, in light and dark, and list anything left for Nick.

12b. **Fixes from the 2 Nov a-z check, BUILT 3 Nov 2026** ([step12b-fixes-plan.md](step12b-fixes-plan.md); uncommitted; Nick kept the "Tools" tag and left the pop-up edge alone). Before step 13.
    Found by checking every page, light and dark, with the window in front
    (nothing built yet; plan with Nick first):
    - **Installed's pop-up** (checked on `uv`) doesn't match the shared pop-up
      layout: just "Installed 0.13.6" and Uninstall, no Website, and the
      subtitle says "Tools" where Updates' pop-up says "Homebrew". Use the
      same layout and show the source. Related: Installed's row tag also
      says "Tools" (a category) instead of the source; Nick decides which.
    - **Orphaned App Files rescans on every visit** (30 s or more, spinner
      each time). Keep the last result and rescan on Rescan.
    - **Pop-ups hang past the window's bottom edge** when the row is near the
      top of a short window (Updates). Inherent to arrow pop-ups; Nick
      decides whether to do anything.
    - **Not yet checked:** Cards view in dark, Installed's pop-up for a cask
      app, a dark pass on Activity and Orphaned App Files with results.
    - Checked fine: Updates and Discover pop-ups (light and dark), Remove
      buttons in Settings (red when the window is active).

13. **Final review** (Nick, 1 Nov 2026), before Phase 10 is called done:
    - **Arbitrary and leftover code:** anything unused, half-finished,
      experimental or debug-only (old variants, test switches, dead
      branches, stray TODOs) is removed or listed for Nick.
    - **Visual consistency:** every tab, card, row, pill, pop-up, sheet and
      button in light and dark against the decisions above.
    - **Operations consistency:** every install, update and removal goes
      through the same queue, password batch, progress, cancel and Activity
      line, wherever it starts (card, row, pop-up, menu bar).
    - **Wording:** the same words for the same thing everywhere.
    - **"What's new in 2.0" fine-tune (Nick, 2 Nov 2026):** the list went in
      the app on 2 Nov with his approved wording; he fine-tunes it here (and
      step 9's line is added once built). Check each entry is still true: for
      example "no separate windows" (the move-progress window, the
      larger-picture viewer and the Full Disk Access helper are small
      windows).
    - **Arrow keys** in the larger-picture window: Nick tries them here.
    - **Lightness:** the before/after measurements below.
    - A written list of what was checked, what was fixed, and anything left
      for Nick.

## Lightness

- Free Discover's catalogue and search results when the main window closes;
  read back from the disk copy when it reopens.
- Web details: text plus up to three shrunk images per app, fetched only on opening
  details; 50 MB cap.
- Font previews load only while Fonts is on screen and aren't kept.
- Icons in memory stay capped at 300.
- No new libraries; the app stays about 13 MB.
- **Measure before and after:** memory with the window closed, and after
  browsing Discover (162 MB measured on 31 Oct 2026, window open). Cache
  sizes in `~/Library/Application Support/UpdateScout/` need Nick's OK to
  read.

## Not in Phase 10

The Sparkle signing test (before the first certificate-signed release), the
three Phase 9 polish items, and the Full Disk Access helper's in-app drag stay
on their own lists.

## Step 11 results (2 Nov 2026, test build)

Built as in [step11-quit-prompt-plan.md](step11-quit-prompt-plan.md), plus the
"Ask before quitting (⌘Q)" switch under Settings > Background checking.

Checked in the test build: the prompt in light and dark (Theme set back to
Light); Close Window (Return default) closes the window and the app stays
running; the Quit menu item shows the prompt; ticking "Don't ask again" then
Quit quit the app and saved `askBeforeQuit = false` (key then deleted, so
Nick's setting is back to "ask"); the switch shows in Settings (search
"quit"). Not driven: the real menu bar prism's Quit (it uses the
no-prompt path by code), the "background checking off" wording (pure text
function, not toggled so the real launchd agent is untouched), log out
and shutdown (skipped by the Apple event quit reason).

## Step 12b results (3 Nov 2026, test build, light)

Installed's pop-up for a Homebrew formula (`rust`) now shows Website,
the description and picture. Orphaned App Files shows its last scan at once
when you come back to it (first open still scans, about 40 s here); the
scan is held in memory only and emptied when the main window closes
(`OrphanCache`, `willClose` hook in `UpdatesWindow`). Not checked: Cards in
dark, a cask app's Installed pop-up, dark pass on Activity and Orphaned with
results, and that the cache empties on close (by code, not measured).

**Remaining checks, done 3 Nov 2026:** Cards view in dark, a cask app's Installed
pop-up (CaskHub: Website, Show in Finder, Uninstall, Open and its pictures),
and Orphaned App Files with results and Activity in dark all look right.

**Found while checking, fixed:** closing the main window freed nothing (the
same window and its pages stayed alive, so the Orphaned list stayed too).
`UpdatesWindow` now drops the window and its views on close and rebuilds
them on the next show (saved frame and chosen page kept; reopening checked).

**Measured, still open:** memory with the window closed is about 237 MB
(227 MB open, after browsing Installed and Discover; the old build held
201 MB closed), so dropping the views alone doesn't lower it. What's left
is the Discover catalogue held in memory (the planned "free Discover's
catalogue when the window closes, read back from the disk copy" in
Lightness) plus memory the system hasn't taken back. Needs its own plan.
