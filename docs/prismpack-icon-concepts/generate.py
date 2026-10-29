#!/usr/bin/env python3
"""PrismPack icon concepts: one folder per concept, one SVG per layer, on a
1024 x 1024 canvas for Icon Composer. Run: python3 generate.py"""
import pathlib

ROOT = pathlib.Path(__file__).parent
SPECTRUM = ["#ff453a", "#ff9f0a", "#ffd60a", "#30d158", "#40c8e0", "#0a84ff", "#bf5af2"]

def svg(body, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{defs}</defs>{body}</svg>\n')

BACKDROP = svg('<rect width="1024" height="1024" fill="url(#bg)"/>',
               '<linearGradient id="bg" x1="0" y1="0" x2="0.6" y2="1">'
               '<stop offset="0" stop-color="#58a6ff"/><stop offset="0.55" stop-color="#6b5cff"/>'
               '<stop offset="1" stop-color="#a64bff"/></linearGradient>')

GLINT = svg('<path d="M300 236 Q360 206 430 214" stroke="#fff" stroke-width="14" stroke-linecap="round" fill="none" opacity="0.9"/>'
            '<circle cx="270" cy="252" r="10" fill="#fff"/>')

def glass(points, alpha=0.32, edge=0.85):
    pts = " ".join(f"{x},{y}" for x, y in points)
    return svg(f'<polygon points="{pts}" fill="#fff" fill-opacity="{alpha}" stroke="#fff" '
               f'stroke-opacity="{edge}" stroke-width="10" stroke-linejoin="round"/>')

def tile(x, y, s, fill, alpha=0.95, r=None):
    r = r or s * 0.24
    return f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{r}" fill="{fill}" fill-opacity="{alpha}"/>'

concepts = {}

# 1. Prism Hub: white light enters the prism and fans out to app tiles.
tiles_y = [270, 400, 530, 660]
beams = '<polygon points="170,560 380,520 380,540" fill="#fff" opacity="0.9"/>'
for i, ty in enumerate(tiles_y):
    c = SPECTRUM[[0, 2, 3, 5][i]]
    beams += f'<polygon points="590,505 745,{ty+20} 745,{ty+75}" fill="{c}" opacity="0.85"/>'
tiles = "".join(tile(745, ty, 95, "#fff", 0.92, 24) +
                f'<circle cx="792" cy="{ty+47}" r="20" fill="{SPECTRUM[[0,2,3,5][i]]}"/>'
                for i, ty in enumerate(tiles_y))
concepts["1-prism-hub"] = {
    "02-beams": svg(beams), "03-tiles": svg(tiles),
    "04-prism": glass([(250, 720), (470, 320), (690, 720)]),
}

# 2. Prism Grid: a 3x3 grid of app tiles seen through one glass prism.
grid = ""
for row in range(3):
    for col in range(3):
        c = SPECTRUM[(row * 3 + col) % 7]
        grid += tile(262 + col * 175, 262 + row * 175, 150, c, 0.9, 36)
concepts["2-prism-grid"] = {
    "02-tiles": svg(grid),
    "03-prism": glass([(222, 800), (512, 240), (802, 800)], 0.30),
}

# 3. Prism Box: a glass package with the spectrum rising out of it.
fan = ""
for i, c in enumerate(SPECTRUM):
    x0 = 300 + i * (424 / 7)
    fan += f'<polygon points="500,470 524,470 {x0+60:.0f},205 {x0:.0f},205" fill="{c}" opacity="0.9"/>'
concepts["3-prism-box"] = {
    "02-spectrum": svg(fan),
    "03-box": svg('<rect x="292" y="500" width="440" height="300" rx="44" fill="#fff" fill-opacity="0.32" '
                  'stroke="#fff" stroke-opacity="0.85" stroke-width="10"/>'),
    "04-lid": svg('<rect x="262" y="440" width="500" height="96" rx="40" fill="#fff" fill-opacity="0.7"/>'
                  '<rect x="482" y="440" width="60" height="96" fill="#6b5cff" fill-opacity="0.35"/>'),
}

# 4. Hex Hub: a hexagonal prism seen from above, one coloured facet per source.
import math
cx = cy = 512; R = 300
v = [(cx + R * math.cos(math.radians(60 * k - 90)), cy + R * math.sin(math.radians(60 * k - 90))) for k in range(6)]
facets = "".join(f'<polygon points="{cx},{cy} {v[k][0]:.0f},{v[k][1]:.0f} {v[(k+1)%6][0]:.0f},{v[(k+1)%6][1]:.0f}" '
                 f'fill="{SPECTRUM[[0,1,2,3,5,6][k]]}" fill-opacity="0.9"/>' for k in range(6))
concepts["4-hex-hub"] = {
    "02-facets": svg(facets),
    "03-glass": glass(v, 0.16),
    "04-centre": svg('<circle cx="512" cy="512" r="118" fill="#fff"/>'
                     '<path d="M512 452 V560 M466 516 L512 562 L558 516" stroke="#6b5cff" stroke-width="26" '
                     'stroke-linecap="round" stroke-linejoin="round" fill="none"/>'),
}

# 5. Spectrum Stack: stacked app tiles, the front one carries the prism.
concepts["5-spectrum-stack"] = {
    "02-back": svg(tile(432, 212, 380, "#ff9f0a", 0.92, 90)),
    "03-mid": svg(tile(322, 322, 380, "#30d158", 0.92, 90)),
    "04-front": svg('<rect x="212" y="432" width="380" height="380" rx="90" fill="#fff" fill-opacity="0.45" '
                    'stroke="#fff" stroke-opacity="0.9" stroke-width="10"/>'),
    "05-prism": svg('<polygon points="292,742 402,532 512,742" fill="#fff" stroke="#fff" stroke-width="18" '
                    'stroke-linejoin="round"/>'),
}

if __name__ == "__main__":
    for name, layers in concepts.items():
        d = ROOT / name
        d.mkdir(exist_ok=True)
        (d / "01-backdrop.svg").write_text(BACKDROP)
        for layer, text in layers.items():
            (d / f"{layer}.svg").write_text(text)
        (d / "99-glint.svg").write_text(GLINT)
    print("wrote", ", ".join(concepts))
