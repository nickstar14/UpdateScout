# Starter for the next PrismPack session

Paste this as the first message of a new Claude Code session in
`~/Desktop/PrismPack` (model: Opus 5.5).

---

Continue PrismPack 2.0 on the `release/2.0.0` branch (last commit
`44b7156`, everything committed, nothing pushed).

Read first, in this order:
1. `CLAUDE.md` (my working rules: plan before building, batch feedback into
   one build, go easy on usage, consistency is the first rule, never
   push/tag/release, commit only when I ask, ask before leaving the
   project folder, test only on throwaway apps).
2. The Status line in `docs/2.0.0-build-guide.md`.
3. In `docs/phase10-plan.md`: "Status at handoff" (the UI patterns every
   page must follow) and "Open items from rounds 9-11".

Task: Phase 10 step 12, the consistency pass. Go through every page
(Updates, Discover, Installed, Orphaned App Files, Activity, Settings) and
every pop-up, in light and dark (the app's Theme setting, back to Light
after), and list each place that doesn't follow the patterns: layout,
controls, tags, colours, buttons, wording, widths, motion. Don't fix
anything yet. Show me the list in plain words, grouped by page, with your
suggested fix for each, and wait for my OK. Then build all the fixes in
one build, check them in the test build, record the results in
`docs/phase10-plan.md`, and ask me before committing.

While you're in the test build, also check the one fix from last session
that hasn't been seen in a build yet: right after "Use Homebrew's copy",
Installed should show the Homebrew row straight away (no "Nothing
matches"), and Show → Duplicates shouldn't be blank while loading.

Testing notes: the installed 1.8.0's background agent rewrites
`state.json` every 5 minutes without 2.0's fields, so Activity empties in
test builds; ask me before pausing it. Never toggle "Check for updates in
the background" or change "Check every" in a test build. Never touch the
keychain or System Settings.

After step 12, the plan's order is steps 6, 7, 9, 10, 11 and 13.
