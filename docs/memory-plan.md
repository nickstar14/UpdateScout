# Memory with the window closed (plan, 3 Nov 2026)

Status: **approved by Nick 3 Nov 2026 (both answers: yes, free only when the window closes); to be built in a new session. Nothing built.**
Nick's rule: super light as a menu bar app, especially with the window closed.
Measured on the test build with macOS's `footprint` (what Activity Monitor
calls Memory), not RSS.

## Measured (3 Nov 2026)

| Moment | Footprint |
|---|---|
| Fresh launch, window never opened, 20 s idle | **15 MB** |
| Updates page open | 60 MB |
| After Installed has loaded | 109 MB |
| After Discover has loaded | 151 MB |
| **Window closed** (views dropped) | **152 MB** |

So the menu bar app is already light until the window is used; the problem is
that **nothing goes back after the window closes**.

`heap` on the closed process: live objects are only **61 MB**; the other
~90 MB is memory freed by the app that malloc keeps instead of giving back
(from decoding Homebrew's 19 MB lists, `brew info`, icons, pictures). Of the
61 MB live, the biggest parts are Discover's catalogue (entries dictionary and
arrays, roughly 10-15 MB) and about 4.5 MB of leftover SwiftUI state.

## The build

1. **Give freed memory back:** call `malloc_zone_pressure_relief` (the system
   call made for this) after the window closes and after the heavy loads
   (catalogue decode, Installed's `brew info`, Discover search). No
   behaviour change, just returns pages the app already freed.
2. **Free Discover's catalogue when the window closes** (already on the
   Lightness list): clear the snapshot, category index, search cache and
   registry results in `DiscoverModel`, and the icon cache; they are read back
   from the compact copy on disk the next time something needs them (Discover
   opens, or an Installed/Updates pop-up looks up a homepage), as `cached()`
   does today. Nothing new is written to disk.
3. **Check the leftover SwiftUI state** after the window closes; if the
   views aren't released I find what keeps them.
4. **Measure again** the same five moments and put the table in
   `docs/phase10-plan.md`. My target is a closed window within about
   25-35 MB of the fresh-launch number, but I will report what I actually
   get; if it is not enough I come back with the next biggest holder before
   changing anything else.

Not touched: the background-check agent (its own short-lived process).

## Questions for Nick

1. **Reopening Discover after closing** reads the catalogue from disk again,
   so its first view after a reopen may take a moment instead of being
   instant. OK? (Recommended: yes, this is the cost of being light.)
2. **Free only when the window closes** (recommended), or also free the
   catalogue when you leave the Discover page with the window open?
