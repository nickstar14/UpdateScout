# UpdateScout icon — layered source

Five aligned SVG layers on a shared 1024×1024 canvas, meant to be imported into
**Icon Composer** so it can apply its own depth, translucency and specular
passes per layer. Stacking them in order reproduces the flat artwork.

| Order | File | What it is | Suggested treatment in Icon Composer |
|---|---|---|---|
| 1 | `01-backdrop.svg` | Blue→violet gradient fill | **Background.** Icon Composer masks it to the icon shape; no depth needed. |
| 2 | `02-ring.svg` | The update ring — two arcs with arrowheads | Bottom foreground layer. A little depth/shadow so it lifts off the backdrop. |
| 3 | `03-lens.svg` | The scout's lens: a light disc | Middle layer. This is the one to give **glass/translucency** — it's shaped and coloured to refract nicely. |
| 4 | `04-arrow.svg` | Download arrow inside the lens | Above the lens, small depth so it sits *inside* the glass rather than on top. |
| 5 | `05-glint.svg` | Specular highlight, clipped to the lens | Top layer, minimal depth. Reduce or drop it if Icon Composer's own specular pass already gives enough shine — two highlights can fight. |

## Notes

- Everything is vector, so it scales without resampling. Keep them as SVG in
  Icon Composer rather than exporting PNGs.
- The design is 180°-rotationally symmetric around the ring, so the icon looks
  balanced at any size and in the menu bar.
- Artwork sits within the centre ~660 pt of the canvas, inside Apple's icon
  grid safe area, so the squircle mask never clips the arrowheads.
- Layers 3–5 share the same 196 pt lens circle centred at (512, 512); if you
  resize the lens, resize all three together or the glint will drift.
- Checked at 16/32/64/128 pt: the ring-and-dot silhouette stays readable.

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
