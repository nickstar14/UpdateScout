#!/usr/bin/env python3
"""Round 5 of the PrismPack icon concepts (29 Oct 2026). The white-glow box
with a taller prism, so the rays end at the opening instead of showing
through the box, and the five-card rainbow deck with the cards rearranged.
One object per layer for Icon Composer. Run: python3 generate_round5.py"""
import pathlib
from generate import svg, BACKDROP, GLINT, tile
from generate_round4 import box_layers, glow, prism, front

ROOT = pathlib.Path(__file__).parent / "round5"
concepts = {}

# Box: the prism's tip sits at the opening (y 500), so no ray shows below it.
def box(name, cy, h):
    b = box_layers(cy - h / 2)
    light, shade = prism(512, cy, h)
    concepts[name] = {
        "02-inside": b["inside"], "03-glow": glow(512, cy, 320), "04-rays": b["rays"],
        "05-prism-light": light, "06-prism-shade": shade,
        "07-flap-left": b["flap-left"], "08-flap-right": b["flap-right"], "09-box": b["box"],
    }

box("box-tall-flush", 662, 316)     # tip level with the rim
box("box-tall-peek", 645, 330)      # tip just above the rim, between the flaps

# Deck: five rainbow cards behind the 3D prism, arranged three ways.
light, shade = prism(512, 602, 250)

def deck(name, colours, step, front_layer):
    layers = {}
    for i, c in enumerate(colours):
        w = 300 + i * (200 // max(1, len(colours) - 1))
        layers[f"{i + 2:02d}-card-{i + 1}"] = svg(tile(512 - w // 2, 352 - (len(colours) - i) * step, w, c, 0.95, w * 0.24))
    n = len(colours) + 2
    layers[f"{n:02d}-front"] = front_layer
    layers[f"{n + 1:02d}-prism-light"] = light
    layers[f"{n + 2:02d}-prism-shade"] = shade
    concepts[name] = layers

RED_BACK = ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#0a84ff"]
deck("deck-red-on-top", RED_BACK, 40, front())
deck("deck-red-on-top-frosted", RED_BACK, 40,
     svg('<rect x="262" y="352" width="500" height="500" rx="120" fill="#f4f1ff" fill-opacity="0.9" '
         'stroke="#fff" stroke-opacity="0.9" stroke-width="10"/>'))
deck("deck-six-thin", ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#0a84ff", "#bf5af2"], 28, front())

if __name__ == "__main__":
    for name, layers in concepts.items():
        d = ROOT / name
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.svg"):
            old.unlink()
        (d / "01-backdrop.svg").write_text(BACKDROP)
        for layer, text in layers.items():
            (d / f"{layer}.svg").write_text(text)
        (d / "99-glint.svg").write_text(GLINT)
    print("wrote", ", ".join(concepts))
