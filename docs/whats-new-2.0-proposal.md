# "What's new in 2.0": gaps and proposed wording

Checked 2 Nov 2026 against everything built through Phase 10 step 7 (commit
`4abde8c`). The in-app list is `RenameWelcome.changes` in
`Sources/PrismPack/Views/RenameWelcome.swift`. **The app text is unchanged:
Nick approves new wording before it goes in** (his rule for what's said to
users). **Approved by Nick 2 Nov 2026** (with "A calmer window" folding Cards or a list and Search Settings, and adding that there are no separate windows: Settings is a page, details are pop-ups; and the prism menu bar entry reworded to say clicking opens the window and there is no small pop-up menu). It went into the app that day; Nick will fine-tune the wording in step 13. Original note: nothing below was in the app yet.

## What's missing or out of date

| Built since the list was last approved (31 Oct) | In the list now? |
|---|---|
| Cards or a list on Updates, Installed and Discover, remembered per page | No |
| Installed filtered by source, sorted by name / size / date / type | No (its entry only says "one list") |
| Install and update progress: a bar with a percent, and a step line | No |
| Duplicates compared side by side (version, size, how often each copy is opened); "Use Homebrew's copy" in one click | Partly (old "Duplicates" text) |
| Apple's own apps shown as macOS, updated by Software Update | No |
| GitHub linking (Settings, or an app's pop-up), including unsigned apps after a warning | No |
| Web descriptions and pictures in pop-ups; font previews and styles | No |
| Settings search; Theme and Glass controls | No |
| Activity: search, filter by kind, tick and delete, kept until deleted | Partly |
| Orphaned App Files: per-item Keep, Show in Finder; shared folders explained | Partly |

Still true as written: the new window, menu bar prism, Discover, more kinds
of updates, several updates at once, one password per batch, Uninstall,
Full Disk Access, Move apps under Homebrew, Stable or Beta, automatic
updates, hide options, betas for testers. One wording fix: **"A new window"**
should add Orphaned App Files to the sidebar list.

## Proposed changes to the list

Edit in place (same icon and title unless noted):

- **A new window:** "A sidebar with Updates, Installed, Orphaned App Files,
  Discover, Activity and Settings, in the macOS 27 Liquid Glass look."
- **Discover:** keep, and add: "Each app's page shows its own description
  and pictures, and fonts show a preview and every style."
- **Installed:** "Everything on your Mac in one list, showing where each
  item came from and whether it's up to date. Filter by source, sort by name,
  size or date, and see it as cards or a list."
- **Duplicates:** "Two copies of one app, or an App Store app Homebrew also
  tracks, are shown side by side with their versions, sizes and how often you
  open each. Keep Homebrew's copy in one click. Nothing is removed without
  asking, and copies go to the Trash."
- **Activity:** "A history of checks, updates, installs and removals, with
  search and filters. It stays until you delete it. Failures keep their log,
  and you can retry them."

New entries:

- **Cards or a list** (symbol `square.grid.2x2`): "Updates, Installed and
  Discover can be cards or a list, remembered for each page."
- **Progress you can see** (symbol `chart.bar`): "Installs and updates show a
  bar and a percent while a download can be measured, and the step they're on
  (verifying, installing…). When nothing can be measured, it says so."
- **Apps on GitHub** (symbol `arrow.triangle.2.circlepath`): "Link an app that
  publishes its releases on GitHub, from Settings or the app's page. Only a
  download signed by the same developer is installed; apps that aren't signed
  need a clear OK first."
- **Search Settings** (symbol `gearshape`): "Settings has a search field, and a
  Theme and Glass setting to suit your Mac."

The existing "Orphaned App Files" entry stays; once step 9 is built it gets:
"Tell \(AppIdentity.name) which app a file belongs to, and it's offered when
you move that app to the Trash."

## Questions for Nick

1. Approve the wording above (or edit it)?
2. Eleven-plus entries is a long list in the welcome sheet; keep all of
   them, or fold "Cards or a list" and "Search Settings" into one "A
   calmer window" entry?
