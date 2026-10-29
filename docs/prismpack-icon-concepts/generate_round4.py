#!/usr/bin/env python3
"""Round 4 of the PrismPack icon concepts (29 Oct 2026). The wide-flap open
box with a glowing prism inside, lit by the incoming rays, and the 3D-prism
deck with rainbow cards behind it. One object per layer for Icon Composer.
Run: python3 generate_round4.py"""
import pathlib
from generate import svg, BACKDROP, GLINT, tile, SPECTRUM

ROOT = pathlib.Path(__file__).parent / "round4"
concepts = {}

def poly(points, fill, alpha=0.9, stroke=False):
    pts = " ".join(f"{x:.0f},{y:.0f}" for x, y in points)
    edge = ' stroke="#fff" stroke-opacity="0.9" stroke-width="8" stroke-linejoin="miter"' if stroke else ""
    return f'<polygon points="{pts}" fill="{fill}" fill-opacity="{alpha}"{edge}/>'

def spectrum_gradient(gid, x1=0, y1=0, x2=1, y2=0):
    stops = "".join(f'<stop offset="{i / 6:.3f}" stop-color="{c}"/>' for i, c in enumerate(SPECTRUM))
    return f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{stops}</linearGradient>'

def glow(cx, cy, r, colour="#fff6d6"):
    return svg(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#g)"/>',
               f'<radialGradient id="g"><stop offset="0" stop-color="{colour}" stop-opacity="0.95"/>'
               f'<stop offset="0.45" stop-color="{colour}" stop-opacity="0.45"/>'
               f'<stop offset="1" stop-color="{colour}" stop-opacity="0"/></radialGradient>')

def prism(cx, cy, h, light="#fff", shade="#fff", light_a=0.97, shade_a=0.6, defs=""):
    """The 3D pyramid from the menu bar glyph: off-centre ridge, light and
    shaded faces. Returns the two faces as separate layers."""
    apex, left, right = (cx, cy - h / 2), (cx - h * 0.55, cy + h / 2), (cx + h * 0.55, cy + h / 2)
    ridge = (cx + h * 0.17, cy + h / 2)
    return (svg(poly([apex, left, ridge], light, light_a), defs),
            svg(poly([apex, ridge, right], shade, shade_a), defs))

# --- Open box, wide flaps, glowing prism inside ----------------------------
X0, X1, TOP, BOTTOM = 292, 732, 500, 840

def box_layers(apex_y):
    rays = "".join(poly([(330 + i * 52, -10), (370 + i * 52, -10), (520, apex_y), (504, apex_y)], c, 0.88)
                   for i, c in enumerate(SPECTRUM))
    r = 96
    body = (f"M{X0} {TOP} H{X1} V{BOTTOM - r} Q{X1} {BOTTOM} {X1 - r} {BOTTOM} "
            f"H{X0 + r} Q{X0} {BOTTOM} {X0} {BOTTOM - r} Z")
    dx, dy = 110, 130
    return {
        "inside": svg(f'<rect x="{X0}" y="{TOP}" width="{X1 - X0}" height="46" fill="#3a2a8c" fill-opacity="0.45"/>'),
        "rays": svg(rays),
        "flap-left": svg(poly([(X0, TOP), (512, TOP), (512 - dx, TOP - dy), (X0 - dx, TOP - dy)], "#fff", 0.62, True)),
        "flap-right": svg(poly([(512, TOP), (X1, TOP), (X1 + dx, TOP - dy), (512 + dx, TOP - dy)], "#fff", 0.62, True)),
        # Thinner glass than round 3 so the lit prism shows through.
        "box": svg(f'<path d="{body}" fill="#fff" fill-opacity="0.22" stroke="#fff" stroke-opacity="0.9" '
                   f'stroke-width="10" stroke-linejoin="miter"/>'),
    }

def box_concept(name, prism_cy, prism_h, glow_layer, faces):
    b = box_layers(prism_cy - prism_h / 2)
    concepts[name] = {
        "02-inside": b["inside"], "03-glow": glow_layer, "04-rays": b["rays"],
        "05-prism-light": faces[0], "06-prism-shade": faces[1],
        "07-flap-left": b["flap-left"], "08-flap-right": b["flap-right"], "09-box": b["box"],
    }

box_concept("box-glow-white", 690, 250, glow(512, 680, 300), prism(512, 690, 250))
box_concept("box-glow-spectrum", 690, 250, glow(512, 680, 300, "#ffe9a8"),
            prism(512, 690, 250, "url(#s)", "url(#s)", 0.95, 0.65, spectrum_gradient("s", 0, 0, 1, 1)))
box_concept("box-glow-rising", 590, 300, glow(512, 560, 320), prism(512, 590, 300))

# --- Deck with rainbow cards behind the 3D prism --------------------------
def front(fill_defs=""):
    return svg('<rect x="262" y="352" width="500" height="500" rx="120" fill="#fff" fill-opacity="0.42" '
               'stroke="#fff" stroke-opacity="0.9" stroke-width="10"/>')
light, shade = prism(512, 602, 250)

concepts["deck-rainbow-gradient"] = {
    "02-back": svg('<rect x="372" y="190" width="280" height="280" rx="66" fill="url(#a)"/>',
                   spectrum_gradient("a", 0, 0, 1, 1)),
    "03-mid": svg('<rect x="322" y="262" width="380" height="380" rx="90" fill="url(#b)"/>',
                  spectrum_gradient("b", 1, 0, 0, 1)),
    "04-front": front(), "05-prism-light": light, "06-prism-shade": shade,
}

five = {}
for i, c in enumerate(["#bf5af2", "#0a84ff", "#30d158", "#ffd60a", "#ff453a"]):
    w = 300 + i * 50
    five[f"0{i + 2}-card-{i + 1}"] = svg(tile(512 - w // 2, 180 + i * 40, w, c, 0.95, w * 0.24))
concepts["deck-rainbow-five"] = {**five, "07-front": front(), "08-prism-light": light, "09-prism-shade": shade}

concepts["deck-rainbow-lit"] = {
    "02-back": svg(tile(372, 190, 280, "#0a84ff", 0.95, 66)),
    "03-mid": svg(tile(322, 262, 380, "#ff453a", 0.95, 90)),
    "04-front": front(),
    "05-wash": svg('<rect x="267" y="357" width="490" height="490" rx="116" fill="url(#w)" fill-opacity="0.55"/>',
                   spectrum_gradient("w", 0, 1, 1, 0)),
    "06-prism-light": light, "07-prism-shade": shade,
}

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
