# Step 12b: fixes from the 2 Nov a-z check (plan, 3 Nov 2026)

Status: **approved 3 Nov 2026 (Tools tag stays, pop-up edge left alone); built, being checked.**
Nick's lightness rule: the app must stay super light as a menu bar app with the window closed.
List of findings: step 12b in `docs/phase10-plan.md`.

## What I found in the code

1. **Installed's pop-up for a Homebrew formula** (`InstalledDetail`,
   `Views/InstalledPage.swift`): its "Tools" subtitle is correct, because
   formulae are the **Tools** source (`sourceID "tools"`, mint colour), not a
   mistake. What is missing is the **Website** button: Updates' and
   Discover's pop-ups show one, Installed's only looks the homepage up for
   casks (`DiscoverModel.entry(cask:)`), so formulae and everything else get
   no Website and no web details.
2. **Orphaned App Files** (`Views/OrphansPage.swift`) scans again every time
   the page opens (30 s or more on this Mac).
3. **Pop-ups past the window's bottom edge:** arrow pop-ups are positioned by
   SwiftUI/AppKit; the window is 628 pt tall. Nothing to fix cheaply (see
   questions).

## The build

1. **Website on Installed's pop-up.** Add `DiscoverModel.entry(formula:)`
   next to `entry(cask:)` (the Homebrew list already holds formulae with
   their homepage). In `InstalledDetail`, look up the cask or the formula
   and put **Website** bottom left (same `.glass()` button as Updates'),
   before Show in Finder. Formulae get the web details section too if the
   homepage allows it (hosts like GitHub are skipped, as today). Nothing
   else in the pop-up changes.
2. **Orphaned App Files keeps its last result.** Keep the scan result in
   the page's model for the session; opening the page shows it at once and
   the Rescan button (and any Move to Trash / Keep) refreshes it. First
   open still scans. Nothing is written to disk (Nick's question, 3 Nov): the list is a few hundred paths, well under 1 MB of memory; a disk copy would only add stale names of Library files, and a rescan after reopening is fine. It's emptied when the main window closes (new `willClose` hook in `UpdatesWindow`, which Discover's "free on close" can reuse), so with the window closed it holds nothing.
3. Check in the test build, light and dark: the Installed pop-up for a
   formula (`uv`), a cask and an app with no homepage; Orphaned App Files
   opened twice; then also the three checks I haven't done yet (Cards in
   dark, Installed pop-up for a cask app, Activity and Orphaned in dark).
   Record results in `docs/phase10-plan.md`; ask before committing.

## Questions for Nick

1. **The "Tools" tag stays**, because it names the Tools source (mint), like
   "Python (pip)". Is that what you want, or should command-line tools say
   "Homebrew" everywhere? (My recommendation: keep "Tools".)
2. **Pop-ups hanging past the window:** leave as is (my recommendation),
   or should the window's minimum height grow so they fit?
