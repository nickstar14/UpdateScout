# Pictures: view in the pop-up, and sharper (plan, 3 Nov 2026)

Status: **approved 3 Nov 2026 (window kept, 1280 px); built and checked in light; uncommitted.**
Changed from the plan: the large picture opens **inside the pop-up's picture section** (the description and buttons stay), not by replacing the whole pop-up, so Updates, Installed and Discover share it with no changes to the three pop-ups. It is drawn at an explicit 504 pt width (a self-sizing picture measured tiny).
Nick (3 Nov 2026): "another way to view images not in a new window if
possible", and "they seem a bit low res, can they be a bit bigger?" Nick's
standing rule applies: keep it light (menu bar app).

## What I found (`Discover/DiscoverDetails.swift`)

- Clicking a picture opens `PicturePreviewWindow`, a separate 680 x 460
  window (the arrow keys work, Nick checked 3 Nov).
- **Why they look soft:** every picture is shrunk to **640 px wide**
  (`shrunk`, JPEG quality 0.8) when it's fetched. The larger window is 680 pt
  wide, which is 1360 px on a Retina screen, so a 640 px picture is stretched
  to twice its size. The pop-up thumbnails are 160 x 100 pt.
- Up to 3 pictures per app are kept; the disk cache is capped at 50 MB and
  only fetched when a pop-up opens.

## The build

1. **Sharper pictures:** shrink to **1280 px wide** instead of 640 (same JPEG
   quality). Typical size per picture goes from roughly 60-100 KB to
   150-250 KB on disk, so the 50 MB cap holds roughly 70+ apps' pictures
   instead of 200+; the cap and the oldest-first clean-up stay as they are.
   Pictures already cached are 640 px, so I add a version number to the cache
   so they are fetched again the next time that app's pop-up opens (nothing
   is re-downloaded in bulk).
2. **View in the pop-up (no new window):** clicking a thumbnail swaps the
   pop-up's content for the picture, shown as wide as the pop-up (540 pt, so
   about 340 pt tall) with ‹ n of 3 › buttons and the ← → keys, and a
   **Back** button (and Esc) to return to the details. The pop-up stays an
   arrow pop-up (Nick's pattern: pop-ups, not sheets); the close circle works
   as before. The same picture views are used on Updates, Installed and
   Discover pop-ups (they share `WebDetailsSection`).
3. **The window stays as the big view:** a small "Open in window" button on
   the in-pop-up view opens the existing window, now larger by default
   (960 x 640, still resizable), for when Nick wants it big. If Nick would
   rather not keep it, I remove the window instead.
4. **Lightness:** pictures are decoded only while a pop-up is on screen
   (today they are decoded again on every redraw of the details; I decode
   once per pop-up). Nothing new is kept in memory with the window closed.
5. Check in the test build, light and dark: the in-pop-up view on Updates,
   Installed and Discover; arrow keys and Back; the window button; a picture
   fetched at the new size (CaskHub, Claude Code). Record results in
   `docs/phase10-plan.md`; ask before committing.

## Questions for Nick

1. **Inline first, window as the extra** (my recommendation), or inline only
   and drop the window?
2. **1280 px** is my pick for "a bit bigger"; 1920 px would be sharper still
   at about twice the disk again. OK with 1280?
