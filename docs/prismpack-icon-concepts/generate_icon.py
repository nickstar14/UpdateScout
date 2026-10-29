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

def main():
    if ICON.exists():
        shutil.rmtree(ICON)
    (ICON / "Assets").mkdir(parents=True)
    cards = ["01-card-red", "02-card-orange", "03-card-yellow", "04-card-green", "05-card-blue", "06-card-violet"]
    groups = [   # top of the stack first, as Icon Composer stores them
        {"name": "Prism", "layers": [layer("10-prism-shade", False), layer("09-prism-light", False)],
         "shadow": NEUTRAL, "specular": True, "translucency": {"enabled": False, "value": 0.5}},
        {"name": "Front", "layers": [layer("08-front-sheen", False, 0.5, hide_in_mono=True),
                                     layer("07-front-card", True)],
         "shadow": NEUTRAL, "specular": True, "translucency": {"enabled": True, "value": 0.5}},
        {"name": "Cards", "layers": [layer(n, True) for n in reversed(cards)],
         "shadow": NEUTRAL, "translucency": {"enabled": True, "value": 0.3}},
        {"name": "Background", "layers": [layer("00-background", False)],
         "shadow": {"kind": "none", "opacity": 0.5}, "translucency": {"enabled": False, "value": 0.5}},
    ]
    doc = {"fill": "automatic", "groups": groups, "supported-platforms": {"squares": ["macOS"]}}
    (ICON / "icon.json").write_text(json.dumps(doc, indent=2))
    # Drop copied files no layer points at (Dark copies identical to Default).
    used = set(json.dumps(doc).split('"'))
    for f in (ICON / "Assets").iterdir():
        if f.name not in used:
            f.unlink()
    print("wrote", ICON, "with", len(list((ICON / "Assets").iterdir())), "assets")

if __name__ == "__main__":
    main()
