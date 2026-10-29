#!/usr/bin/env python3
"""Final PrismPack icon layers (29 Oct 2026): the rainbow deck with violet in
front and the 3D prism. Silver background for Default (light mode),
midnight for Dark. Every layer is a solid shape at full opacity with no
baked-in edges, glow or glint: Icon Composer adds the glass, translucency
and highlights. Writes ../prismpack-icon-final/. Run: python3 generate_final.py"""
import pathlib
from generate import svg, tile
from generate_round4 import spectrum_gradient
from generate_round6 import backdrop, BACKDROPS, CARDS

OUT = pathlib.Path(__file__).parent.parent / "prismpack-icon-final"

def poly(points, fill):
    pts = " ".join(f"{x:.0f},{y:.0f}" for x, y in points)
    return f'<polygon points="{pts}" fill="{fill}"/>'

layers = {
    "00-background-default-silver": backdrop(BACKDROPS["silver"]),
    "00-background-dark-midnight": backdrop(BACKDROPS["midnight"]),
}
for i, c in enumerate(CARDS):
    cw = 300 + i * 40
    layers[f"{i + 1:02d}-card-{['red','orange','yellow','green','blue','violet'][i]}"] = \
        svg(tile(512 - cw // 2, 352 - (len(CARDS) - i) * 34, cw, c, 1, cw * 0.24))
layers["07-front-card"] = svg('<rect x="262" y="352" width="500" height="500" rx="120" fill="#ffffff"/>')
layers["08-front-sheen"] = svg('<rect x="262" y="352" width="500" height="500" rx="120" fill="url(#sh)"/>',
                               spectrum_gradient("sh", 0, 0, 1, 1))
cx, cy, h = 512, 602, 250
apex, left, right, ridge = (cx, cy - h / 2), (cx - h * .55, cy + h / 2), (cx + h * .55, cy + h / 2), (cx + h * .17, cy + h / 2)
layers["09-prism-light"] = svg(poly([apex, left, ridge], "#ffffff"))
# Solid shade instead of 60% white, so the 3D survives without opacity tricks.
layers["10-prism-shade"] = svg(poly([apex, ridge, right], "#d8d2f2"))

if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    for old in OUT.glob("*.svg"):
        old.unlink()
    for name, text in layers.items():
        (OUT / f"{name}.svg").write_text(text)
    print("wrote", len(layers), "layers to", OUT)
