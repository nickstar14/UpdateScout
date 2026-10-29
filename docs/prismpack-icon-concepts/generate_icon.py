#!/usr/bin/env python3
"""Builds ../prismpack-icon-final/PrismPack.icon from the default/, dark/ and
clear/ layer folders, with the per-appearance overrides written in, so
Icon Composer doesn't have to be coaxed into them. Appearances in icon.json:
no "appearance" key = Default, "dark" = Dark, "tinted" = Mono (Clear and
Tinted). Run generate_final.py first, then: python3 generate_icon.py"""
import json, pathlib, shutil

FINAL = pathlib.Path(__file__).parent.parent / "prismpack-icon-final"
ICON = FINAL / "PrismPack.icon"

def asset(appearance, name):
    """Copy one layer file into Assets/ and return its asset name."""
    src = FINAL / appearance / f"{name}.svg"
    if not src.exists():
        return None
    dest = f"{appearance}-{name}.svg"
    shutil.copy(src, ICON / "Assets" / dest)
    return dest

def layer(name, glass, opacity=1.0, hide_in_mono=False):
    default, dark, mono = asset("default", name), asset("dark", name), asset("clear", name)
    entry = {"name": name, "image-name": default, "glass": glass,
             "opacity": opacity, "blend-mode": "normal"}
    images = [{"value": default}]
    if dark and (FINAL / "dark" / f"{name}.svg").read_text() != (FINAL / "default" / f"{name}.svg").read_text():
        images.append({"appearance": "dark", "value": dark})
    if mono:
        images.append({"appearance": "tinted", "value": mono})
    if len(images) > 1:
        entry["image-name-specializations"] = images
        del entry["image-name"]
    if hide_in_mono or not mono:
        entry["hidden-specializations"] = [{"value": False}, {"appearance": "tinted", "value": True}]
    return entry

NEUTRAL = {"kind": "neutral", "opacity": 0.5}

# Display P3 fills for the cards in Default and Dark: the same channel values
# read as P3 instead of sRGB, which pushes them toward P3's wider, richer
# primaries. Mono ("tinted") keeps its grey artwork ("automatic").
P3_CARDS = {"01-card-red": "#ff453a", "02-card-orange": "#ff9f0a", "03-card-yellow": "#ffd60a",
            "04-card-green": "#30d158", "05-card-blue": "#0a84ff", "06-card-violet": "#bf5af2"}

def p3_fill(hex_colour, alpha=0.85):
    r, g, b = (int(hex_colour[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return [{"value": {"solid": f"display-p3:{r:.5f},{g:.5f},{b:.5f},{alpha:.5f}"}},
            {"appearance": "tinted", "value": "automatic"}]

def main():
    if ICON.exists():
        shutil.rmtree(ICON)
    (ICON / "Assets").mkdir(parents=True)
    cards = ["01-card-red", "02-card-orange", "03-card-yellow", "04-card-green", "05-card-blue", "06-card-violet"]
    groups = [   # top of the stack first, as Icon Composer stores them
        # Glass and a full-strength shadow lift the prism off the cards, so it
        # reads as the top layer even in Clear and Tinted.
        {"name": "Prism", "layers": [layer("10-prism-shade", True), layer("09-prism-light", True)],
         "shadow": {"kind": "neutral", "opacity": 1}, "specular": True,
         "translucency": {"enabled": False, "value": 0.5}},
        # Sheen at 75% (Nick). A full-strength shadow behind the front card
        # sets it clearly in front of the stack.
        {"name": "Front", "layers": [layer("08-front-sheen", False, 0.75, hide_in_mono=True),
                                     layer("07-front-card", True)],
         "shadow": {"kind": "neutral", "opacity": 1}, "specular": True,
         "translucency": {"enabled": True, "value": 0.5}},
        {"name": "Cards", "layers": [dict(layer(n, True), **{"fill-specializations": p3_fill(P3_CARDS[n])})
                                     for n in reversed(cards)],
         "shadow": NEUTRAL, "translucency": {"enabled": True, "value": 0.3}},
        {"name": "Background", "layers": [layer("00-background", False)],
         "shadow": {"kind": "none", "opacity": 0.5}, "translucency": {"enabled": False, "value": 0.5}},
    ]
    doc = {"fill": "automatic", "groups": groups, "supported-platforms": {"squares": ["macOS"]},
           # Icon Composer's "Use Display P3 if untagged": the SVGs' plain hex
           # colours are read as Display P3, which makes the sheen more vivid.
           "color-space-for-untagged-svg-colors": "display-p3"}
    (ICON / "icon.json").write_text(json.dumps(doc, indent=2))
    # Drop copied files no layer points at (Dark copies identical to Default).
    used = set(json.dumps(doc).split('"'))
    for f in (ICON / "Assets").iterdir():
        if f.name not in used:
            f.unlink()
    print("wrote", ICON, "with", len(list((ICON / "Assets").iterdir())), "assets")

if __name__ == "__main__":
    main()
