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

Done and committed: steps 12, 6, 7 and 9, install progress everywhere, and the
approved "What's new in 2.0" list (in `RenameWelcome.changes`). Records:
`docs/install-progress-plan.md`, `docs/step7-web-details-plan.md`,
`docs/step9-belongs-to-plan.md`, `docs/whats-new-2.0-proposal.md`.

Tasks, in this order:

1. **Step 10, other sources** (Settings list, "Add a Source…" sheet for GitHub
   links or custom sources; see step 10 in the build order of
   `docs/phase10-plan.md`). Plan it first (research the existing
   `Views/SettingsView.swift`, `Views/GitHubLinkViews.swift` and
   `CustomSource`), show me the plan with any questions in plain words, and
   wait for my OK before building.
2. **Step 11, the ⌘Q prompt** (`AppDelegate.applicationShouldTerminate`; see
   "Nick's decisions" in the Phase 10 plan). Same: plan, show, OK, build.
3. **Step 13, the final review** (visual, operations and wording
   consistency, the "What's new" fine-tune with me, the ← → arrow keys in the
   larger-picture window, lightness measurements, a written list of what was
   checked).

Productivity's yellow tint looks gold-brown in dark (the tint over dark glass
muddies it) and needs a colour decision from me, probably at step 13.

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
