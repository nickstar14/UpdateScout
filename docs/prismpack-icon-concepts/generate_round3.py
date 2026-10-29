#!/usr/bin/env python3
"""Round 3 of the PrismPack icon concepts (29 Oct 2026). An open box with
square-edged flaps and a rounded bottom, with light going in, and the deck
with a 3D prism that matches the menu bar glyph. One object per layer, ready
for Icon Composer. Run: python3 generate_round3.py"""
import pathlib
from generate import svg, BACKDROP, GLINT, tile, SPECTRUM

ROOT = pathlib.Path(__file__).parent / "round3"
concepts = {}

def poly(points, fill, alpha=0.9, stroke=False):
    pts = " ".join(f"{x:.0f},{y:.0f}" for x, y in points)
    edge = ' stroke="#fff" stroke-opacity="0.9" stroke-width="8" stroke-linejoin="miter"' if stroke else ""
    return f'<polygon points="{pts}" fill="{fill}" fill-opacity="{alpha}"{edge}/>'

def box_body(x0, x1, top, bottom, r):
    """Square top corners, rounded bottom corners."""
    d = (f"M{x0} {top} H{x1} V{bottom - r} Q{x1} {bottom} {x1 - r} {bottom} "
         f"H{x0 + r} Q{x0} {bottom} {x0} {bottom - r} Z")
    return svg(f'<path d="{d}" fill="#fff" fill-opacity="0.38" stroke="#fff" stroke-opacity="0.9" '
               f'stroke-width="10" stroke-linejoin="miter"/>')

def open_box(name, lift):
    """`lift` is how far the flaps lean out (dx) and up (dy)."""
    x0, x1, top, bottom = 292, 732, 500, 840
    dx, dy = lift
    rays = "".join(poly([(330 + i * 52, -10), (370 + i * 52, -10), (520, 510), (504, 510)], c, 0.88)
                   for i, c in enumerate(SPECTRUM))
    concepts[name] = {
        "02-inside": svg(f'<rect x="{x0}" y="{top}" width="{x1 - x0}" height="46" fill="#3a2a8c" fill-opacity="0.45"/>'),
        "03-rays": svg(rays),
        "04-flap-left": svg(poly([(x0, top), (512, top), (512 - dx, top - dy), (x0 - dx, top - dy)], "#fff", 0.62, True)),
        "05-flap-right": svg(poly([(512, top), (x1, top), (x1 + dx, top - dy), (512 + dx, top - dy)], "#fff", 0.62, True)),
        "06-box": box_body(x0, x1, top, bottom, 96),
    }

open_box("box-open-wide", (110, 130))
open_box("box-open-tall", (45, 170))

def prism_ridge(cx, cy, h):
    """Same shape as the menu bar glyph: a pyramid with an off-centre ridge,
    a bright left face and a dimmer right face, so it reads as 3D."""
    apex, left, right = (cx, cy - h / 2), (cx - h * 0.55, cy + h / 2), (cx + h * 0.55, cy + h / 2)
    ridge = (cx + h * 0.17, cy + h / 2)
    return (svg(poly([apex, left, ridge], "#fff", 0.97)),
            svg(poly([apex, ridge, right], "#fff", 0.6)))

def prism_extruded(cx, cy, h):
    """A triangular prism lying flat: front triangle plus its side face."""
    w = h * 0.78
    apex, left, right = (cx - 40, cy - h / 2), (cx - 40 - w / 2, cy + h / 2), (cx - 40 + w / 2, cy + h / 2)
    off = (h * 0.42, -h * 0.13)
    side = [apex, (apex[0] + off[0], apex[1] + off[1]), (right[0] + off[0], right[1] + off[1]), right]
    return (svg(poly(side, "#fff", 0.6)), svg(poly([apex, left, right], "#fff", 0.97)))

deck = {
    "02-back": svg(tile(372, 190, 280, "#40c8e0", 0.92, 66)),
    "03-mid": svg(tile(322, 262, 380, "#ff375f", 0.92, 90)),
    "04-front": svg('<rect x="262" y="352" width="500" height="500" rx="120" fill="#fff" fill-opacity="0.42" '
                    'stroke="#fff" stroke-opacity="0.9" stroke-width="10"/>'),
}
a, b = prism_ridge(512, 602, 250)
concepts["deck-ridge"] = {**deck, "05-prism-light": a, "06-prism-shade": b}
a, b = prism_extruded(512, 610, 230)
concepts["deck-extruded"] = {**deck, "05-prism-side": a, "06-prism-front": b}

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
