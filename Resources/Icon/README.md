# UpdateScout icon — layered source

Five aligned SVG layers on a shared 1024×1024 canvas, meant to be imported into
**Icon Composer** so it can apply its own depth, translucency and specular
passes per layer. Stacking them in order reproduces the flat artwork.

| Order | File | What it is | Suggested treatment in Icon Composer |
|---|---|---|---|
| 1 | `01-backdrop.svg` | Blue→violet gradient fill | **Background.** Icon Composer masks it to the icon shape; no depth needed. |
| 2 | `02-ring.svg` | The update ring — two arcs with arrowheads | Bottom foreground layer. A little depth/shadow so it lifts off the backdrop. |
| 3 | `03-lens.svg` | The scout's lens: a light disc | Middle layer. This is the one to give **glass/translucency** — it's shaped and coloured to refract nicely. |
| 4 | `04-glint.svg` | Specular highlight, clipped to the lens | Sits on the glass. Minimal depth. Reduce or drop it if Icon Composer's own specular pass already gives enough shine — two highlights can fight. |
| 5 | `05-arrow.svg` | Green download arrow | **Topmost.** Give it the most elevation so it floats *above* the glass and casts a shadow onto the lens, rather than looking embedded in it. |

## Notes

- Everything is vector, so it scales without resampling. Keep them as SVG in
  Icon Composer rather than exporting PNGs.
- The design is 180°-rotationally symmetric around the ring, so the icon looks
  balanced at any size and in the menu bar.
- Artwork sits within the centre ~660 pt of the canvas, inside Apple's icon
  grid safe area, so the squircle mask never clips the arrowheads.
- Layers 3 and 4 share the same 196 pt lens circle centred at (512, 512); if
  you resize the lens, resize both or the glint will drift.
- The arrow is green (`#4BE07B` → `#16A34A`) to read as "update complete". It
  also separates the arrow from the white ring at small sizes, where a dark
  arrow used to merge into a blob.
- Checked at 16/32/64/128 pt: the silhouette stays readable.

## Corner rounding

Every corner is rounded: the arcs use round line caps, and the arrowheads
(both on the ring and inside the lens) are filled *and* stroked in their own
colour with a round line join — SVG has no corner radius for polygons. The
stroke grows a shape by half its width all round, so the triangle geometry is
inset by that amount to keep the finished size unchanged. `ROUND_RING` and
`ROUND_ARROW` in the generator control how soft the corners are.

## Regenerating

    python3 Resources/Icon/generate.py

The geometry is computed rather than hand-drawn: arcs are defined by angle
pairs and each arrowhead is derived from the tangent at its arc's end, so the
two halves stay symmetric if you change the radius or stroke weight.
