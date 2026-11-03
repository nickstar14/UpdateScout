# Install progress everywhere, and the font pop-up's style list

**Built 2 Nov 2026, not committed (see "Built" at the end).** Plan written 2 Nov 2026 after Nick's feedback. Nick said to
wait until his LM Studio install via Homebrew has finished, then execute.
One build for both parts.

## Nick's asks

1. "Installing" for 3+ minutes tells him nothing. He wants a **progress
   bar with a small % beside it** in the tile, and a **one-line note under
   it** ("Unzipping…", "Installing…", "Cleaning up…") **wherever it's
   possible**: new installs, updates, moving to Homebrew, everywhere.
2. **Permission given (2 Nov 2026):** anything needed for this, including
   reading file sizes in Homebrew's cache folder (`brew --cache`, under
   `~/Library/Caches/Homebrew`). Still: read sizes only, write nothing
   there, touch nothing else outside the project.
3. Fonts: **an expanded preview in the details pop-up**: how many styles
   the family has (Regular, Bold, Italic, SemiBold…), each style listed so
   you know what's available, and a longer preview.

## What exists today (so this reuses it)

- `InstallState` (`Models.swift`) has `.downloading(percent:line:)`, and the
  tiles draw a bar and "%" when a percent is known (`Rows.swift`
  trailingContent, `DiscoverPage.swift` DiscoverAction). It's almost never
  known: **Homebrew prints no percentage when its output isn't a terminal**
  (it's read through a pipe), so a cask shows one line for the whole job.
- `MoveProgress` (`Views/MoveProgress.swift`) already does steps, a bar and
  real downloaded bytes for GitHub updates and the Homebrew adoption jobs,
  fed by `§step:` and `§download:` marker lines.
- `Adopter.watchingDownload` already measures a Homebrew download by
  watching its file in `brew --cache` (`.incomplete` while it arrives)
  against the size the server reports (`Adoption.downloadSize`).
- `DownloadReporter` (`GitHubReleasesSource.swift`) reports bytes of
  PrismPack's own downloads.
- Sources with **no** progress at all today: Homebrew install/upgrade,
  CaskOracle, npm, pip, cargo, gem, custom, editor extensions, components,
  macOS updates. Mas, Sparkle and the installer helper report a few lines.

## Part 1: install progress

**Rule: a bar and a % only where the number is real.** Where the tool
reports nothing measurable (Nick, 2 Nov 2026): **no bar. A small animated
circle (spinner) sits beside "Installing…" with a small grey notice,
"Can't measure progress" (wording to confirm), and the time so far, so it
never looks frozen. No invented percentages and no fake moving bar.**

### The tile

- **Line 1:** bar plus a small `42%` while a measurement exists. When
  nothing can be measured: a small spinner and the phase word instead of
  the bar, with a small grey "Can't measure progress" notice beside it.
- **Line 2** (caption, grey, one line): what it's doing now, from this
  vocabulary: *Waiting in the queue · Downloading 412 MB of 1.2 GB ·
  Verifying · Unzipping · Installing · Moving to Applications · Running the
  vendor's installer · Cleaning up · Finishing · Needs your password*. The
  time so far is added after a minute ("Installing · 2:41"). In the
  unmeasurable case line 2 is that notice plus the time.
- **One shared view** (`InstallProgressView`) used by Updates (cards and
  rows), Discover (cards, rows and its pop-up), Installed's pop-up and the
  details pop-ups, so every place looks the same. On a card it takes the
  buttons' place across the width; in a list row it widens the button
  column; in a pop-up it sits where the main action is. Cancel stays
  reachable as today.
- Long moves keep clicking through to the steps window
  (`MoveProgressWindow`); that window gets the same phase words.

### The data

- New `InstallProgress` (phase, bytes done and total, tool percent, started
  time, last line) kept per item in the controller next to `installStates`
  and `moveProgress`. `InstallProgress.take(_ line:)` is a **pure parser**
  for `§step:` / `§download:` markers and the tools' own lines, so it's
  unit-tested without running anything.
- **Download watcher generalised:** `Adopter.watchingDownload` becomes a
  shared `DownloadWatcher` used by Homebrew installs and updates (cask:
  total from the cask's URL; formula bottle: bytes only when the total
  can't be had without a login), by CaskOracle, and still by adoption.
- The elapsed time is drawn by the view (`TimelineView`), not polled.

### Per source: what's measurable

| Source | Download | Other phases | Notes |
|---|---|---|---|
| Homebrew cask (new install, update, Move to Homebrew, Use Homebrew's copy) | real bytes and %, from the cache file against the server's size | phases from brew's `==>` lines: Downloading, Verifying, Installing Cask, Moving App, Running installer, Purging files, Cleaning up | the long silent part is usually the vendor installer (Outlook's 1.2 GB package): shows "Running the vendor's installer · 3:10", no %. If `installer` prints `Percent complete` lines, they're used. Check on a throwaway. |
| Homebrew formula | bytes (total only if known) | Fetching, Pouring, Installing, Cleaning up | |
| GitHub, Sparkle, installer helper | real bytes and % (already reported) | Verifying signature, Unzipping, Replacing the app | map existing lines onto the phase words |
| Adoption / duplicates moves | real bytes (existing) | existing steps | phase words only |
| Mac App Store (`mas`) | % if `mas` prints one, else phase only | | check its real output |
| macOS updates | `softwareupdate` prints percent: use it | | check its real output |
| npm, pip, cargo, gem | none measurable | phase words from their lines ("Downloading", "Collecting", "Compiling x", "Installing") | cargo shows the crate being compiled; spinner and notice, no % |
| Editor extensions, custom sources, components | none | Installing… with the time | |

### Throwaway testing (CLAUDE.md: throwaway only)

- Pure tests first (parser, fraction, phase words).
- Live: a tiny font cask (a few hundred KB), then a mid-size cask if Nick
  agrees which one, and one small formula, each installed then removed from
  the test build. **Nick picks or OKs the packages before any install.**
  Real apps are never used. A vendor-installer cask is only watched if Nick
  starts one himself (like his LM Studio install).
- Checked in light and dark, Theme back to Light; Cards, List and the
  pop-up; with a slow connection if one can be had.

## Part 2: font pop-up, styles and a longer preview

Applies to Discover → Fonts details pop-up (step 6 already has the sample
line on the tiles).

- **A "Styles" section:** "18 styles on Google Fonts" and the styles as
  small tags: *Thin, ExtraLight, Light, Regular, Medium, SemiBold, Bold,
  ExtraBold, Black*, and *Italic* variants. For a variable font it says so
  ("variable, weights 100 to 900").
- **A longer preview:** a paragraph sample, the alphabet and digits, drawn
  in the regular style, then **each style drawn on its own row** in its own
  weight ("Bold: The quick brown fox…"). Loaded only when the pop-up opens,
  one small request per style (letters of the sample only), the same
  in-memory-only rules as the tiles, dropped when it closes.
- **Where the list comes from:** Google Fonts' metadata for the family.
  **First thing to check when building:** whether `fonts.google.com/metadata/fonts`
  or the CSS API's axis list is the lighter, reliable source; the plan uses
  whichever answers per family without pulling the whole catalogue.
- **Honest limits, said in the pop-up:** Google's list is what the family
  offers; what Homebrew installs can differ ("The Homebrew package installs
  its own files"). Fonts not on Google show the name only, as today.
- Tests: style names from the metadata (pure), weight number to name.

## Also in this build / carried over

- The consistency pass and font tiles are built and **uncommitted** (see
  `phase10-plan.md`); commit them first if Nick says so, so this build's
  diff stays separate.
- Wording stays consistent: "Website", "Move to Trash", glass buttons,
  0.14 s fades.

## Order of work (after LM Studio finishes)

1. Wait for Nick's go (LM Studio's Homebrew install done; no brew running).
2. `InstallProgress` + parser + tests; shared `DownloadWatcher`.
3. Hook each source's `install`; map lines to phases.
4. `InstallProgressView` in every tile and pop-up.
5. Font pop-up styles and longer preview.
6. `swift build`, tests, one app build, throwaway checks, light and dark,
   record in `phase10-plan.md`, ask before committing.

## Questions for Nick

1. Which throwaway packages may be installed for the live check? Suggested:
   a small font cask, one small formula (e.g. `hello`), one mid-size cask
   of his choice. All removed afterwards.
2. ~~Honest rule~~ **Answered (Nick, 2 Nov 2026):** where it can't be
   measured, show a small animated circle beside "Installing" with a small
   notice that progress can't be measured; no moving bar.

## Built (2 Nov 2026), not committed

- `InstallProgress.swift` (phases, a pure parser, real % only), shared
  `Views/InstallProgressView.swift` in Updates and Discover tiles and
  pop-ups; the controller keeps `installProgress` per running item.
- `HomebrewSource.watched` wraps Homebrew updates and Discover installs and
  reports the download's bytes (cask total from its URL; formula bytes only);
  "Preparing" shows while `brew --cache` and `brew info` run. The tile shows
  a spinner, the step word and "Can't measure progress" (plus the time after a
  minute) when nothing is measured; a bar and % when it is.
- Font pop-up: "N styles (x upright, y italic)", a longer sample, each style
  drawn in itself, the note about Homebrew's files. Source: Google's v1 CSS
  API asked for all 18 weight/italic combinations; it answers with only the
  styles that exist, one small file each (the 2.7 MB catalogue metadata was
  not used).
- Tests: `InstallProgressTests` (9), `FontStyleTests` (4), `FontPreviewTests`.
- Checked in the test build with two throwaway installs (the Monoid font
  cask, 145 KB, and the `hello` formula), both removed afterwards: the tile
  went Queued, Preparing, Downloading with the spinner and notice. The
  packages were too small to see a bar fill or the later phases.
- **IINA (Nick OK'd, 108 MB, removed afterwards):** Homebrew already had the
  download cached from 2 Oct, so there was no fresh download. The tile went
  Queued, Preparing, then the bar at 100% ("Downloading · 113 MB of 113 MB"),
  then (after the fix that treats a complete file as being checked)
  "Verifying…" with the spinner, then Installed. Piped brew output streams
  live (Fetching downloads, Installing Cask, Moving App, Linking Binary), so
  the later steps pass in about a second for an app cask.
- **HandBrake (46 MB, throwaway, removed) and a real Audacity update
  (4.0.1 to 4.0.2, Nick OK'd):** HandBrake downloaded fresh in under 20
  seconds, too fast to catch between checks; the tile went Preparing then
  Verifying (the file was complete). Audacity's 4.0.2 file had already been
  downloaded earlier that day (cache), so it went Preparing, Verifying,
  done; the row left the list. A real mid-download fill still wasn't seen
  (a 374 MB cask such as Krita would give a window long enough).
- **Krita (392 MB, Nick OK'd, throwaway, removed):** the bar filled for
  real: "Downloading · 16.2 MB of 392 MB" at 4%, 8%, 12% ... 38%, then
  "Verifying…" with the spinner and "Can't measure progress · 1:05" (the
  time counts from the start), then Installed. Verifying lasted a couple of
  minutes: Homebrew prints nothing between the finished download and
  "Installing Cask", so the tile's "Verifying" covers the checksum and the
  disk image mounting. Krita's 374 MB download stays in Homebrew's cache
  (`brew cleanup` would clear it; Nick's call).
- **Not seen (superseded: the bar filling is now seen):** a bar filling with real bytes during a fresh download, Unzipping, Moving, Cleaning up,
  a vendor installer, and the tile on adoption/GitHub/Sparkle jobs: they
  need a mid-size download (Nick to pick one, or run an update he already
  has waiting).
