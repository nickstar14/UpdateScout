# PrismPack icon: "Prism Layers" (draft)

Six aligned SVG layers on a 1024 x 1024 canvas, one object per file, for
import into **Icon Composer**. Stack in the order below. Draft art to react to,
not final.

| Order | File | What it is | Suggested treatment |
|---|---|---|---|
| 1 | `01-backdrop.svg` | Blue to violet gradient (`#58a6ff`, `#6b5cff`, `#a64bff`) | Background. Same blue-violet family as the UpdateScout icon, so the change reads as the same app grown up. |
| 2 | `02-layer-back.svg` | Largest glass triangle, white 34% to 10%, thin edge | Glass on, low elevation. |
| 3 | `03-layer-mid.svg` | Middle triangle, white 26%, brighter edge | Glass on, medium elevation. |
| 4 | `04-layer-front.svg` | Smallest triangle, white 62%, almost solid | Highest of the three. The "pack" at the front. |
| 5 | `05-sheen.svg` | Soft diagonal gloss over the back triangle's upper left | Specular or hard-light blend. Reduce if Icon Composer's own specular fights it. |
| 6 | `06-glint.svg` | Small bright streak and dot near the top-left edge | Topmost, no depth. This is the sharp glossy shine. |

Geometry: the three triangles share a centre line (x = 512) and step down and
shrink toward the viewer: bases at y 724, 760 and 796, widths 640, 480 and 320.
Corners are rounded in the paths themselves (radius 46, 40, 34), so there is
nothing to round in Icon Composer. Artwork stays inside x 192 to 832 and
y 170 to 796, clear of the squircle mask.

Keep each layer as SVG. The same shapes are drawn in `2.0.0-mockups.html`.
