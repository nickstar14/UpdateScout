# Starter for the next PrismPack session

Paste this as the first message of a new Claude Code session in
`~/Desktop/PrismPack` (model: Opus 5.5 or Sonnet 5.5).

---

Continue PrismPack 2.0 on the `release/2.0.0` branch (step 7 is `4abde8c`, followed by one docs commit,
everything committed, nothing pushed).

Read first, in this order:
1. `CLAUDE.md` (my working rules: plan before building, batch feedback into
   one build, go easy on usage, consistency is the first rule, never
   push/tag/release, commit only when I ask, ask before leaving the project
   folder, test only on throwaway apps, and the new "Driving pop-ups from the
   background" and network notes under "Things that bite").
2. The Status line in `docs/2.0.0-build-guide.md`.
3. In `docs/phase10-plan.md`: "Status at handoff" (the UI patterns every page
   must follow, including the ones added on 2 Nov) and "Left in Phase 10".

Done and committed since the last starter: step 12 (consistency pass), step 6
(font previews and style list), install progress everywhere (a bar and % only
where measured), step 7 (web descriptions and pictures in pop-ups). The
records are `docs/install-progress-plan.md` and `docs/step7-web-details-plan.md`.

Tasks, in this order:

1. **Step 9, Orphaned App Files "Belongs to…".** The plan is written:
   `docs/step9-belongs-to-plan.md`. Put its three questions to me in plain
   words first (where to store it, button placement, ticked by default), then
   build it in one build and check it live with a throwaway dummy app and fake
   leftovers (never my real apps or orphans), in light and dark (Theme back to
   Light). Record the results in `docs/phase10-plan.md` and ask before
   committing.
2. **"What's new in 2.0"** is in the app with the wording I approved on
   2 Nov (`RenameWelcome.changes`; record in
   `docs/whats-new-2.0-proposal.md`). Add step 9's line once built; I fine-tune
   the whole list in step 13.
3. **Steps 10 (other sources) and 11 (⌘Q prompt),** each planned and shown
   before building, as always.
4. **Step 13, the final review** (visual, operations and wording
   consistency, the "What's new" fine-tune, the arrow keys, lightness
   measurements, a written list of what was checked).

The ← → arrow keys in the larger-picture window wait for step 13 (the
automation can't send keys to that panel). Productivity's yellow tint still looks gold-brown in dark
and needs a colour decision from me.

Testing notes:
- The installed 1.8.0's background agent rewrites `state.json` every 5 minutes
  without 2.0's fields, so Activity empties and Zoom's "Can adopt" vanish in
  test builds; ask me before pausing it. Never toggle "Check for updates in
  the background" or change "Check every" in a test build. Never touch the
  keychain or System Settings.
- The full test suite and probes touch the real data folder; the pure suites
  (`InstallProgressTests`, `FontPreviewTests`, `FontStyleTests`,
  `WebDetailsTests`, `DiscoverTests`, `HomebrewCopyTests`) don't. Ask me
  before running the whole suite.
- Quit the installed copy before running a test build; both share the bundle
  ID and data folder. `open build/PrismPack.app` twice if its window doesn't
  appear. If the app's window is on another Space (for example mine is
  full-screen), ask me to bring it.
- Installs for progress checks only on uncached throwaway packages, removed
  afterwards (Krita worked); I'm leaving a few updates waiting on the Updates
  page in case a live update test is useful (one or two are fine).
