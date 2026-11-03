# Phase 10 step 7: web details in the pop-ups

Plan written 2 Nov 2026. **Built 2 Nov 2026 (Nick OK'd the recommended picks), not yet seen live or committed; see "Built" at the end.** Follows
step 7 in [phase10-plan.md](phase10-plan.md) (Nick: "up to 3 pictures",
fetched only when details open, 50 MB cache cap).

## What Nick gets

In an app's details pop-up, under Homebrew's one-line description:

- **A longer description** from the app's own website (its meta
  description), labelled with where it came from ("From obsidian.md").
- **Up to 3 pictures** from the same page, as a row of thumbnails. Click
  one to see it larger in a small window (arrow keys flip between them).
  One picture or none when the page has nothing good; the section simply
  doesn't show.

## Research (2 Nov 2026, read-only test of 9 real homepages)

| Site | Preview image (og/twitter) | Description |
|---|---|---|
| obsidian.md | yes (a banner) | yes |
| iina.io | yes (a real screenshot) | yes |
| audacityteam.org | yes | yes |
| ollama.com | yes | yes |
| zen-browser.app | no | yes |
| handbrake.fr | no | yes |
| videolan.org/vlc | no | yes (18 `<img>` tags to choose from) |
| krita.org, inkscape.org | page returned nothing readable to a plain request | no |

So about half the apps get a picture, three quarters a description. Preview
images are often a banner or social card, not a screenshot: the plan accepts
that ("one or none when nothing good is found"), and picks screen-shaped
images from the page's own `<img>` tags when there's no preview image.

## Design

- **New `Discover/DiscoverDetails.swift`**, modelled on `DiscoverIcons`
  (same fetch helper `Net.fetch`, same "ask each site once" cache, hosts
  like GitHub/GitLab skipped because their pages aren't the app's own).
- **Fetch only when a pop-up opens**, never for tiles. One request for the
  page's HTML (first 512 KB, https only), then at most 6 candidate images,
  4 at a time, each capped at 3 MB and a few seconds. The pop-up showing
  "Looking for pictures…" is a spinner line, never a blocked pop-up.
- **Description:** `<meta name="description">`, else `og:description`;
  entities decoded, whitespace collapsed, cut at about 400 characters, shown
  as plain text (never links or markup) with the site name.
- **Pictures, chosen in this order:** `og:image`, `twitter:image`, then
  `<img>` tags that look like screenshots (declared width ≥ 400 or a large
  `srcset` entry). Skipped: SVG, GIF, anything whose name has logo, icon,
  avatar, sprite, badge, favicon or tracking. After download an image counts
  only if it is at least 480 px wide and roughly screen-shaped (aspect 1.2 to
  2.4). Duplicates removed; first three win.
- **Shrunk before saving:** each picture is scaled to at most 640 px wide
  and saved as a JPEG (about 50 to 90 KB). Memory holds them only while the
  pop-up is open.
- **Cache:** `discover-details/` in the data folder, one folder per app
  (description text plus up to three images and the time fetched). Refetched
  after 30 days; "nothing found" is asked again after a week (like icons).
  Total capped at **50 MB**, oldest folder removed first, checked each time
  something is saved.
- **Where it shows:** one shared `WebDetailsSection` in Discover's pop-up and
  in Installed's and Updates' pop-ups, wherever the app has a known homepage
  (Discover entries, and Installed/Updates items that map to a Homebrew
  cask or formula). Apps with no homepage show nothing extra.
- **Privacy:** the only requests go to the app's own website, with the usual
  "PrismPack" user agent, and only when you open its details. Nothing about
  you is sent beyond what any web request includes (your IP address).

## Consistency (the first rule)

Same pop-up layout: helpers bottom-left, main action bottom-right, close
circle top-right. The section sits between the description and the buttons,
in the normal text sizes, glass-edged thumbnails at the pattern's corner
radius, a spinner and a one-line grey note while loading. Light and dark
checked, Theme set back to Light. Pop-ups stay 540 wide; the picture row is
about 105 px tall, so the pop-ups don't get taller than they are now when
there are no pictures.

## Tests

Pure functions, no network and no data folder: meta description and
`og:image` extraction, entity decoding and the length cut, the candidate
order and the logo/format filters, the screen-shape test, and the cache
eviction (given folder sizes and dates, which go first). Then `swift build`,
one app build, and a live check on four real tiles (Obsidian, IINA,
Audacity, Ollama) plus one with nothing to show (Krita). The live check
writes the app's own cache folder, as icons already do; the full test
suite is not run without Nick's OK.

## Questions for Nick

1. **Banners are fine?** Many sites give a banner or social card rather
   than a screenshot. Is "up to 3, screen-shaped, else none" right?
2. **The description:** show it **under** Homebrew's one-liner with the site
   name (recommended), or replace the one-liner?
3. **Viewing larger:** a small separate window you flip through with the
   arrow keys (recommended, like the move-progress window), or enlarge in
   place inside the pop-up?

## Built (2 Nov 2026), not committed

- `Discover/DiscoverDetails.swift`: `WebDetailsParser` (pure), `DetailsCache`
  (pure eviction rule), `DiscoverDetails` (fetch, disk cache in
  `discover-details/`), `WebDetailsSection` (the pop-up section) and
  `PicturePreviewWindow` (the larger view, arrow keys flip).
- Shown in Discover's pop-up (not for fonts), and in Installed's and Updates'
  pop-ups for Homebrew casks (`DiscoverModel.entry(cask:)`, once the Homebrew
  list has loaded).
- Tests: `WebDetailsTests` (7, pure) pass.
- Seen in the test build (light, and the Updates pop-up in dark; Theme back
  to Light): Obsidian (description "From obsidian.md" and two pictures),
  Ollama (description and one picture), Krita (nothing found: the spinner line
  goes away and the pop-up is as before), and Obsidian's Updates pop-up
  (Homebrew cask, same section). A picture opens in a small window and the
  next/previous buttons flip it. Thumbnails are real buttons (labelled
  "Picture 1 of 2 from Obsidian's website"): a bare tap gesture couldn't be
  pressed by the automation, and it reads better for VoiceOver.
- Found and fixed on a second look: the larger window opened 420 wide (now
  680 x 484, checked); and Installed's and Updates' pop-ups showed nothing on
  a fresh launch because Homebrew's list hadn't loaded: they now load it
  themselves (from the disk copy) when a Homebrew cask's pop-up opens,
  checked on a fresh launch with Obsidian's Updates pop-up.
- Checked afterwards (2 Nov 2026): Audacity (installed, up to date) in
  Installed's own pop-up: description from audacityteam.org and three
  pictures, all three thumbnails fit the 540 pop-up; IINA in Discover:
  description from iina.io and one picture, under Homebrew's one-liner.
- **Not seen:** the arrow keys in the larger window (the automation can't
  send keys to a panel); the on-screen buttons work.
