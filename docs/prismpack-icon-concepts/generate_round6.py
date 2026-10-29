#!/usr/bin/env python3
"""Round 6 of the PrismPack icon concepts (29 Oct 2026). The rainbow deck
with violet in front, on backdrops with less purple, and a clear glass
front card with a separate rainbow-sheen layer for Icon Composer's Liquid
Glass to work with. Run: python3 generate_round6.py"""
import pathlib
from generate import svg, GLINT, tile
from generate_round4 import prism, spectrum_gradient

ROOT = pathlib.Path(__file__).parent / "round6"
concepts = {}

BACKDROPS = {
    "blue": ("#5ac8fa", "#2f7bff", "#1d4ed8"),         # sky to deep blue, no violet
    "midnight": ("#24345f", "#141d3d", "#0a0f24"),     # dark navy: the rainbow pops
    "silver": ("#ffffff", "#eef1f8", "#d6dceb"),       # light, like Apple's own light icons
}

def backdrop(stops):
    a, b, c = stops
    return svg('<rect width="1024" height="1024" fill="url(#bg)"/>',
               f'<linearGradient id="bg" x1="0" y1="0" x2="0.6" y2="1"><stop offset="0" stop-color="{a}"/>'
               f'<stop offset="0.55" stop-color="{b}"/><stop offset="1" stop-color="{c}"/></linearGradient>')

FRONT = (262, 352, 500)
x, y, w = FRONT

# Clear glass: mostly transparent, so Icon Composer's glass does the work.
glass_card = svg(f'<rect x="{x}" y="{y}" width="{w}" height="{w}" rx="120" fill="#fff" fill-opacity="0.18" '
                 f'stroke="#fff" stroke-opacity="0.85" stroke-width="8"/>')
# The sheen: a soft diagonal rainbow across the card, strongest at the top
# left like light catching glass. Its own layer, so its blend and opacity
# can be tuned in Icon Composer.
sheen = svg(f'<rect x="{x}" y="{y}" width="{w}" height="{w}" rx="120" fill="url(#sh)" mask="url(#fade)"/>',
            spectrum_gradient("sh", 0, 0, 1, 1)
            + f'<linearGradient id="f" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.7"/>'
              f'<stop offset="0.55" stop-color="#fff" stop-opacity="0.15"/><stop offset="1" stop-color="#fff" stop-opacity="0.35"/></linearGradient>'
            + f'<mask id="fade"><rect x="{x}" y="{y}" width="{w}" height="{w}" fill="url(#f)"/></mask>')

CARDS = ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#0a84ff", "#bf5af2"]   # violet nearest the front
light, shade = prism(512, 602, 250)

for name, stops in BACKDROPS.items():
    layers = {"01-backdrop": backdrop(stops)}
    for i, c in enumerate(CARDS):
        cw = 300 + i * 40
        layers[f"{i + 2:02d}-card-{i + 1}"] = svg(tile(512 - cw // 2, 352 - (len(CARDS) - i) * 34, cw, c, 1, cw * 0.24))
    layers.update({"08-front-glass": glass_card, "09-front-sheen": sheen,
                   "10-prism-light": light, "11-prism-shade": shade})
    concepts[f"deck-violet-{name}"] = layers

if __name__ == "__main__":
    for name, layers in concepts.items():
        d = ROOT / name
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.svg"):
            old.unlink()
        for layer, text in layers.items():
            (d / f"{layer}.svg").write_text(text)
        (d / "99-glint.svg").write_text(GLINT)
    print("wrote", ", ".join(concepts))
