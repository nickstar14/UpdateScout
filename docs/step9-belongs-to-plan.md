# Phase 10 step 9: Orphaned App Files, "Belongs to…"

Plan written 2 Nov 2026. **Not built; waiting for Nick's OK.** From the
decision in [phase10-plan.md](phase10-plan.md): pick the installed app the
files belong to; PrismPack remembers it; the files leave the list and are
offered with that app's own files when it's moved to the Trash; "Assigned
files" at the bottom undoes it.

## What Nick sees

1. **A "Belongs to…" button on each orphan row** (small glass button, same
   size as Keep and the folder button, between Show files and Show in
   Finder). Not on shared folders (those are never moved by PrismPack).
2. **An arrow pop-up (540 wide, close circle top right):** a search field,
   then the installed apps, **same-developer apps first** (marked "Same
   developer"), then the rest A to Z. Clicking an app shows one confirmation
   inside the pop-up: "Files named for com.example.foo belong to **Foo**.
   They leave this list and are offered when you move Foo to the Trash.
   Nothing is moved now." Buttons: Assign (main action, bottom right),
   Cancel. Apple's apps aren't listed (PrismPack never moves those).
3. **The files leave the list.** An **"Assigned files"** section (like the
   existing "Kept" section) lists them: `com.example.foo → Foo`, with a
   small glass **Undo** button that puts them back in the list.
4. **When that app is moved to the Trash** (its Move to Trash window), the
   assigned files are in its list with the others, **ticked** (Nick chose
   them), each marked "You assigned these to Foo", and move with the same
   checks as every leftover (re-checked right before moving, only inside
   `~/Library`, never Apple's, never a shared folder, undone if a step
   fails).

## Rules that can't be skipped (the "airtight" rule)

- **Assigning moves nothing.** It only records a choice.
- Never assignable: Apple's IDs (`isSafeID`), shared group folders (they're
  Show in Finder only), PrismPack's own, and IDs without a dot.
- If the app it was assigned to is **no longer installed**, the assignment
  is ignored and the files show in the list again (never lost, never moved
  by an app that isn't there).
- At the moment of moving, the file must still be in `~/Library`, directly
  inside the folder it was found in, and not a link (the existing
  `Leftovers.moveToTrash` check, unchanged).
- One app copy still using the same ID keeps the files, as today.

## How

- **`Prefs.assignedOrphans`** (`Store.swift`): `[ownerBundleID: [orphanID]]`
  as plain lowercase IDs in `UserDefaults`, like `keptOrphans`. Chosen over
  `state.json` (the earlier note): the 1.8.0 background agent rewrites
  `state.json` without 2.0's fields every 5 minutes (Activity empties), so
  an assignment there would vanish in test builds and be at risk beside a
  1.8.0 install. See question 1.
- **`Leftovers.orphans(...)`** gets an `assigned: Set<String>` like `kept`:
  those IDs aren't listed.
- **`Leftovers.scan(_ identity)`** gets the IDs assigned to that app's bundle
  ID as extra matches (normal ID matches: ticked, movable); each is marked
  so the window can say who assigned it.
- **Owners list for the pop-up:** the installed apps (`AppFolders.appPaths()`,
  bundle ID and name), minus unsafe IDs, sorted as above.
- **`Views/OrphansPage.swift`:** the button, the pop-up (new
  `AssignOwnerPopup`), the "Assigned files" section. **`UninstallWindow`:**
  the "You assigned these" note.
- Consistency: glass buttons, the pop-up pattern, 0.14 s fades, the same
  wording ("Move to Trash", "Show in Finder"), light and dark checked,
  Theme back to Light.

## Tests (pure; temp library, no real data folder)

- `orphans` leaves out assigned IDs; an assignment whose owner isn't
  installed is ignored.
- `scan` for an app includes its assigned IDs' files, ticked, and not other
  apps'.
- Refusals: an Apple ID, a group ID and an ID without a dot can't be assigned.
- Then `swift build`, one app build.

## Live check (throwaway only)

A dummy app with its own bundle ID in `~/Applications`, plus a couple of fake
leftover folders named for a made-up ID in `~/Library/Application Support`
and `~/Library/Caches` (as in the Phase 9 zap test). Assign them to the dummy
app; confirm they leave the list, show in Assigned files, Undo puts them
back, then assign again and move the dummy app to the Trash: the files appear
ticked with the note and go to the Trash. Real apps and real orphans are
never touched. Light and dark.

## Questions for Nick

1. **Where to keep it:** `UserDefaults` like Kept (recommended), or
   `state.json` as first written?
2. **Placement:** a "Belongs to…" button on every row (recommended), or only
   in an expanded row?
3. **Ticked by default** in the app's Move to Trash window (recommended,
   since you picked them, and marked "You assigned these"), or unticked?
