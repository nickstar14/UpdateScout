#!/usr/bin/env python3
"""Final PrismPack icon layers (29 Oct 2026): the rainbow deck with violet in
front and the 3D prism. Writes one folder per Icon Composer appearance into
../prismpack-icon-final/: default/ (also light mode), dark/, and clear/ (the
Mono appearance, which drives Clear and Tinted). Every folder has the same
filenames, so each dark or clear file drops onto the matching layer as that
appearance's variant. Layers are flat and full-canvas with no mask, with a slight
baked-in transparency (ALPHA). Icon Composer adds the glass and highlights.
Run: python3 generate_final.py"""
import pathlib
from generate import svg, tile, SPECTRUM
from generate_round4 import spectrum_gradient
from generate_round6 import backdrop, BACKDROPS

OUT = pathlib.Path(__file__).parent.parent / "prismpack-icon-final"
NAMES = ["red", "orange", "yellow", "green", "blue", "violet"]
FRONT_W = 540
FRONT_Y = 322   # front card spans y 322 to 862; red, the top card, starts at 118
# Baked-in transparency, so the layers look right as soon as they are
# imported. Icon Composer's own Opacity slider multiplies on top of these.
ALPHA = {"card": 0.85, "front": 0.3, "sheen": 0.45, "prism-light": 0.95, "prism-shade": 0.85}

def poly(points, fill, alpha=1):
    pts = " ".join(f"{x:.0f},{y:.0f}" for x, y in points)
    return f'<polygon points="{pts}" fill="{fill}" fill-opacity="{alpha}"/>'

def mono_sheen_gradient(gid):
    """The rainbow sheen without colour: the same diagonal bands, each
    colour replaced by a grey of its own brightness, stretched a little so
    the soft light and dark stripes still read in Clear and Tinted."""
    stops = ""
    for i, c in enumerate(SPECTRUM):
        r, g, b = (int(c[k:k + 2], 16) / 255 for k in (1, 3, 5))
        lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        grey = round(255 * min(1, max(0, 0.45 + (lum - 0.45) * 2.4)))
        stops += f'<stop offset="{i / 6:.3f}" stop-color="#{grey:02x}{grey:02x}{grey:02x}"/>'
    return f'<linearGradient id="{gid}" x1="0" y1="0" x2="1" y2="1">{stops}</linearGradient>'

def layer_set(background, cards, front, sheen, prism_light, prism_shade, prism_alpha=None):
    layers = {"00-background": backdrop(background)}
    # Each card is 40 wider and 34 lower than the one behind it, and the
    # front card takes the next step (540), so the deck grows toward you.
    for i, c in enumerate(cards):
        cw = 300 + i * 40
        layers[f"{i + 1:02d}-card-{NAMES[i]}"] = svg(tile(512 - cw // 2, FRONT_Y - (6 - i) * 34, cw, c, ALPHA["card"], cw * 0.24))
    fx, fw = 512 - FRONT_W // 2, FRONT_W
    front_a, sheen_a = ALPHA["front"], ALPHA["sheen"]
    layers["07-front-card"] = svg(f'<rect x="{fx}" y="{FRONT_Y}" width="{fw}" height="{fw}" rx="{fw * 0.24:.0f}" fill="{front}" fill-opacity="{front_a}"/>')
    if sheen == "mono":
        # Stronger than the colour sheen: grey bands need more to show.
        layers["08-front-sheen"] = svg(f'<rect x="{fx}" y="{FRONT_Y}" width="{fw}" height="{fw}" rx="{fw * 0.24:.0f}" fill="url(#sh)" fill-opacity="0.8"/>',
                                       mono_sheen_gradient("sh"))
    elif sheen:
        layers["08-front-sheen"] = svg(f'<rect x="{fx}" y="{FRONT_Y}" width="{fw}" height="{fw}" rx="{fw * 0.24:.0f}" fill="url(#sh)" fill-opacity="{sheen_a}"/>',
                                       spectrum_gradient("sh", 0, 0, 1, 1))
    cx, cy, h = 512, FRONT_Y + FRONT_W / 2, 270
    apex, left, right, ridge = (cx, cy - h / 2), (cx - h * .55, cy + h / 2), (cx + h * .55, cy + h / 2), (cx + h * .17, cy + h / 2)
    layers["09-prism-light"] = svg(poly([apex, left, ridge], prism_light, prism_alpha or ALPHA["prism-light"]))
    layers["10-prism-shade"] = svg(poly([apex, ridge, right], prism_shade, prism_alpha or ALPHA["prism-shade"]))
    return layers

APPEARANCES = {
    # Default (light mode): silver background, full rainbow.
    "default": layer_set(BACKDROPS["silver"],
                         ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#0a84ff", "#bf5af2"],
                         "#ffffff", True, "#ffffff", "#d8d2f2"),
    # Dark: midnight background. Apple's dark-mode colours, a softer front
    # card so it doesn't glare, and a deeper shade so the prism stays 3D.
    "dark": layer_set(BACKDROPS["midnight"],
                      ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#0a84ff", "#bf5af2"],
                      "#e8e4ff", True, "#ffffff", "#b4abe0"),
    # Mono (Clear and Tinted): greyscale with the prism as the one full-white
    # element, as Apple recommends. No sheen: it turns muddy without colour.
    "clear": layer_set(("#3a3a3c", "#2c2c2e", "#1c1c1e"),
                       ["#8e8e8e", "#999999", "#a4a4a4", "#afafaf", "#bababa", "#c5c5c5"],
                       "#dedede", "mono", "#ffffff", "#5c5c5c", prism_alpha=1),
}

if __name__ == "__main__":
    for old in OUT.glob("*.svg"):
        old.unlink()
    for appearance, layers in APPEARANCES.items():
        d = OUT / appearance
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.svg"):
            old.unlink()
        for name, text in layers.items():
            # Mono has no background of its own: the system draws Clear and
            # Tinted backgrounds itself.
            if appearance == "clear" and name == "00-background":
                continue
            (d / f"{name}.svg").write_text(text)
        print(appearance, len(layers), "layers")
