# Starter for the next PrismPack session

Paste this as the first message of a new Claude Code session in
`~/Desktop/PrismPack` (model: Opus 5.5 or Sonnet 5.5).

---

Continue PrismPack 2.0 on the `release/2.0.0` branch (last commit `cbc6e88`,
everything committed, nothing pushed).

Read first, in this order:
1. `CLAUDE.md` (my working rules: plan before building, batch feedback into
   one build, go easy on usage, consistency is the first rule, never
   push/tag/release, commit only when I ask, ask before leaving the project
   folder, test only on throwaway apps, and "Things that bite").
2. The Status line in `docs/2.0.0-build-guide.md`.
3. In `docs/phase10-plan.md`: "Status at handoff" (the UI patterns every page
   must follow) and "Left in Phase 10".

Done and committed: Phase 10 steps 1 to 12, install progress, the a-z check
fixes (step 12b), the pictures work and the ⌘Q prompt. Records:
`docs/step11-quit-prompt-plan.md`, `docs/step12b-fixes-plan.md`,
`docs/step15-pictures-plan.md`, and the results sections at the end of
`docs/phase10-plan.md`.

Tasks, in this order:

1. **Memory with the window closed** (I approved the plan on 3 Nov:
   `docs/memory-plan.md`). Build it as written: give freed memory back
   (`malloc_zone_pressure_relief`) after the window closes and after the heavy
   loads; free Discover's catalogue, caches and icons when the main window
   closes (the `willClose` hook in `UpdatesWindow` already drops the window
   and views); check the leftover SwiftUI state. Measure with `footprint <pid>`
   (and `heap <pid> -s`) before and after at the same five moments and put the
   table in `docs/phase10-plan.md`. Check light and dark, ask before
   committing.
2. **Step 13, the final review** (see its list in `docs/phase10-plan.md`).
   Plan it first, show me the plan, wait for my OK.

Productivity's yellow tint looks gold-brown in dark and needs a colour
decision from me, at step 13.

Testing notes:
- The installed 1.8.0's background agent rewrites `state.json` every 5 minutes
  without 2.0's fields, so Activity empties in test builds; ask me before
  pausing it. Never toggle "Check for updates in the background" or change
  "Check every" in a test build. Never touch the keychain or System Settings.
- Quit the installed copy before running a test build; both share the bundle
  ID and data folder. `open build/PrismPack.app` twice if its window doesn't
  appear. Kill the old test copy with `kill <pid>` before rebuilding.
- Driving the window from the background: use `app_click` with an
  `element_index` (Theme, Cards / List and other segmented controls ignore
  raw clicks); ⌘W via `app_key` with a `coordinate`; Installed takes about
  25 s to load; Orphaned App Files about 40 s. Put Theme back to Light and
  Installed back to List afterwards.
- Don't read `~/Library` (not even the details cache) without asking me.
