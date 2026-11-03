# Starter for the next PrismPack session

Paste this as the first message of a new Claude Code session in
`~/Desktop/PrismPack` (model: Opus 5.5 or Sonnet 5.5).

---

Continue PrismPack on branch `release/2.0.0` (same as `main` at `a273c0a`,
2.0.0-beta.1 is published as a GitHub pre-release).

Read first, in this order:
1. `CLAUDE.md` (my rules: plan before building, batch feedback into one build,
   go easy on usage, consistency first, never push/tag/release unless I ask,
   commit only when I ask, ask before leaving the project folder, test only on
   throwaway apps).
2. `docs/step13-final-review-plan.md`: "Published: 2.0.0-beta.1" and "Where to
   go from here". The status of everything else is in `docs/2.0.0-build-guide.md`
   (top of the status block) and `docs/phase10-plan.md`.

State: the beta is installed on my Mac at `/Applications/PrismPack.app`. Nothing
is waiting to be committed unless `git status` says so.

Likely tasks, in this order (ask me which):
1. Fix what I find in the beta, then release `2.0.0-beta.2` the same way.
2. The Sparkle rehearsal with throwaway apps (plan in the step 13 doc), then
   the final 2.0.0 for UpdateScout 1.8.0 users.
3. 2.0.1 / 2.1.0: switch the feed URL, rename the repo, notarization question.

Testing notes:
- Don't touch the keychain or System Settings; use the app's own Theme setting
  and put it back to Light; Installed takes 25-40 s to load; Orphaned App
  Files about 40 s.
- Drive the window from the background with `app_click` and `element_index` (or
  coordinates from a fresh screenshot); the green traffic light goes full
  screen, not zoom. Close the window with Window > Close.
- Measure memory with `footprint <pid>` on the GUI process only.
- Release only when I say so: `gh auth switch --user nickstar14`, run
  `scripts/release.sh` on `main`, then `gh auth switch --user IHMS-IT`.
