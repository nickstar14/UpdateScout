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
    Trash". `UninstallButton` gained `title:`. **Not seen live:** a fresh
    launch hadn't found Flux's duplicates yet; check after a Check Now.
  - No "…" after Move to Trash anywhere (buttons; progress text keeps it).
  - The updates reminder is a light orange strip, as in the mockup.

**Next:** commit the above when Nick says, then step 4 (Discover page: drop
both chip rows, under-row with search, Sort and Cards/List, the new cards).

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
   web description and screenshot (step 7).
6. **Fonts:** sample line drawn from Google Fonts while the Fonts page is on
   screen; name only when a font isn't on Google Fonts.
7. **Web details** (new `Discover/DiscoverDetails.swift`): page description and
   preview image from the app's homepage, image shrunk before saving, on-disk
   cache capped at 50 MB, oldest removed first.
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
11. **⌘Q prompt** (`AppDelegate.swift`): `applicationShouldTerminate` asks
    as above; "Don't ask again" stored in preferences.
12. **Consistency pass:** apply button placement to Move to Trash, adoption,
    duplicates and the major-upgrade review; filters as segmented control or
    menu; then go through every tab (Updates, Installed, Discover, Orphaned
    App Files, Activity, Settings) checking cards, rows, pills, buttons and
    pop-ups match, in light and dark, and list anything left for Nick.

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
    - **Lightness:** the before/after measurements below.
    - A written list of what was checked, what was fixed, and anything left
      for Nick.

## Lightness

- Free Discover's catalogue and search results when the main window closes;
  read back from the disk copy when it reopens.
- Web details: text plus one shrunk image per app, fetched only on opening
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
