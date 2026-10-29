#!/usr/bin/env python3
"""Round 2 of the PrismPack icon concepts (29 Oct 2026): three variants of
each concept Nick liked in round 1. Same layer format as generate.py.
Run: python3 generate_round2.py"""
import pathlib
from generate import svg, BACKDROP, GLINT, glass, tile, SPECTRUM

ROOT = pathlib.Path(__file__).parent / "round2"
concepts = {}

def poly(points, fill, alpha=0.9):
    pts = " ".join(f"{x:.0f},{y:.0f}" for x, y in points)
    return f'<polygon points="{pts}" fill="{fill}" fill-opacity="{alpha}"/>'

def box_tile(x, y, w, h):
    """An app-icon-shaped box: a rounded glass tile with a lid band."""
    r = w * 0.22
    return {
        "box": svg(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r:.0f}" fill="#fff" fill-opacity="0.34" '
                   f'stroke="#fff" stroke-opacity="0.9" stroke-width="10"/>'),
        "lid": svg(f'<path d="M{x} {y + h*0.24:.0f} H{x + w}" stroke="#fff" stroke-width="12" stroke-opacity="0.9"/>'
                   f'<rect x="{x + w/2 - 26:.0f}" y="{y}" width="52" height="{h*0.24:.0f}" fill="#fff" fill-opacity="0.75"/>'),
    }

def arrow(cx, cy, r, colour="#6b5cff"):
    return (f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r}" fill="#fff"/>'
            f'<path d="M{cx:.0f} {cy - r*0.5:.0f} V{cy + r*0.42:.0f} M{cx - r*0.4:.0f} {cy + 0.04*r:.0f} '
            f'L{cx:.0f} {cy + r*0.44:.0f} L{cx + r*0.4:.0f} {cy + 0.04*r:.0f}" stroke="{colour}" '
            f'stroke-width="{r*0.22:.0f}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>')

# --- Prism Box: the box is an app tile; beams run to the icon's edge -------
b = box_tile(292, 440, 440, 400)
fan = "".join(poly([(500, 444), (524, 444), (180 + (i + 1) * 95, -10), (180 + i * 95, -10)], c, 0.88)
              for i, c in enumerate(SPECTRUM))
concepts["box-1-fan-up"] = {"02-beams": svg(fan), "03-box": b["box"], "04-lid": b["lid"]}

b = box_tile(362, 352, 300, 300)
beams = poly([(-10, 470), (-10, 540), (362, 512), (362, 498)], "#fff", 0.9)
beams += "".join(poly([(662, 494 + i * 5), (662, 499 + i * 5), (1034, 300 + (i + 1) * 62), (1034, 300 + i * 62)], c, 0.88)
                 for i, c in enumerate(SPECTRUM))
concepts["box-2-through"] = {"02-beams": svg(beams), "03-box": b["box"], "04-lid": b["lid"]}

b = box_tile(312, 470, 400, 360)
pour = "".join(poly([(60 + i * 130, -10), (130 + i * 130, -10), (520, 480), (504, 480)], c, 0.85)
               for i, c in enumerate(SPECTRUM))
flaps = (poly([(312, 470), (220, 380), (420, 470)], "#fff", 0.55)
         + poly([(712, 470), (804, 380), (604, 470)], "#fff", 0.55))
concepts["box-3-pour-in"] = {"02-beams": svg(pour), "03-box": b["box"],
                             "04-flaps": svg(flaps), "05-lid": b["lid"]}

# --- Spectrum Stack ------------------------------------------------------------
front = lambda x, y, s: svg(f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="{s*0.24:.0f}" fill="#fff" '
                            f'fill-opacity="0.45" stroke="#fff" stroke-opacity="0.9" stroke-width="10"/>')
prism = lambda cx, cy, h: svg(f'<polygon points="{cx - h*0.55:.0f},{cy + h/2:.0f} {cx:.0f},{cy - h/2:.0f} '
                              f'{cx + h*0.55:.0f},{cy + h/2:.0f}" fill="#fff" stroke="#fff" stroke-width="18" '
                              f'stroke-linejoin="round"/>')
concepts["stack-1-four"] = {
    "02-back": svg(tile(472, 172, 300, "#ff453a", 0.92, 72)),
    "03-mid-back": svg(tile(392, 252, 300, "#ffd60a", 0.92, 72)),
    "04-mid": svg(tile(312, 332, 300, "#30d158", 0.92, 72)),
    "05-front": front(232, 412, 300), "06-prism": prism(382, 562, 170),
}
concepts["stack-2-deck"] = {
    "02-back": svg(tile(372, 190, 280, "#40c8e0", 0.92, 66)),
    "03-mid": svg(tile(322, 262, 380, "#ff375f", 0.92, 90)),
    "04-front": front(262, 352, 500), "05-prism": prism(512, 602, 240),
}
side = lambda a, c: svg(f'<g transform="rotate({a} 512 860)">{tile(332, 300, 360, c, 0.92, 86)}</g>')
concepts["stack-3-fan"] = {
    "02-left": side(-16, "#ff9f0a"), "03-right": side(16, "#40c8e0"),
    "04-front": front(332, 300, 360), "05-prism": prism(512, 480, 190),
}

# --- Prism Hub: the hex hub's coloured facets, in a prism shape ------------
A, B, C = (512, 190), (842, 780), (182, 780)
G = ((A[0] + B[0] + C[0]) / 3, (A[1] + B[1] + C[1]) / 3)
mid = lambda p, q: ((p[0] + q[0]) / 2, (p[1] + q[1]) / 2)
three = poly([G, A, B], "#ff9f0a") + poly([G, B, C], "#30d158") + poly([G, C, A], "#0a84ff")
concepts["facet-1-three"] = {"02-facets": svg(three), "03-glass": glass([A, B, C], 0.14),
                             "04-centre": svg(arrow(*G, 96))}
pts = [A, mid(A, B), B, mid(B, C), C, mid(C, A)]
six = "".join(poly([G, pts[k], pts[(k + 1) % 6]], SPECTRUM[[0, 1, 2, 3, 5, 6][k]]) for k in range(6))
concepts["facet-2-six"] = {"02-facets": svg(six), "03-glass": glass([A, B, C], 0.14),
                           "04-centre": svg(arrow(*G, 96))}
fa, fb, fc = (430, 230), (722, 770), (138, 770)
off = (150, -50)
back = lambda p: (p[0] + off[0], p[1] + off[1])
bands = ""
for i, c in enumerate(SPECTRUM):          # spectrum bands across the side face
    t0, t1 = i / 7, (i + 1) / 7
    p0 = (fa[0] + (fb[0] - fa[0]) * t0, fa[1] + (fb[1] - fa[1]) * t0)
    p1 = (fa[0] + (fb[0] - fa[0]) * t1, fa[1] + (fb[1] - fa[1]) * t1)
    bands += poly([p0, p1, back(p1), back(p0)], c, 0.9)
fg = ((fa[0] + fb[0] + fc[0]) / 3, (fa[1] + fb[1] + fc[1]) / 3)
concepts["facet-3-solid"] = {"02-side": svg(bands), "03-front": glass([fa, fb, fc], 0.4),
                             "04-centre": svg(arrow(fg[0], fg[1] + 40, 90))}

# --- Prism Grid: the apps sit inside the prism -----------------------------
A, B, C = (512, 160), (892, 830), (132, 830)
def rows(n_rows, size, gap, top, colours, white=False):
    out = ""; k = 0
    for r in range(n_rows):
        n = r + 1
        x0 = 512 - (n * size + (n - 1) * gap) / 2
        y = top + r * (size + gap)
        for i in range(n):
            x = x0 + i * (size + gap)
            if white:
                out += tile(round(x), round(y), size, "#fff", 0.92, size * 0.24)
                out += f'<circle cx="{x + size/2:.0f}" cy="{y + size/2:.0f}" r="{size*0.2:.0f}" fill="{colours[k % len(colours)]}"/>'
            else:
                out += tile(round(x), round(y), size, colours[k % len(colours)], 0.92, size * 0.24)
            k += 1
    return out
concepts["inside-1-six"] = {"02-apps": svg(rows(3, 120, 22, 400, SPECTRUM)),
                            "03-prism": glass([A, B, C], 0.22)}
concepts["inside-2-ten"] = {"02-apps": svg(rows(4, 92, 16, 360, SPECTRUM)),
                            "03-prism": glass([A, B, C], 0.22)}
spread = "".join(poly([(700, 498 + i * 5), (704, 503 + i * 5), (1034, 380 + (i + 1) * 50), (1034, 380 + i * 50)], c, 0.88)
                 for i, c in enumerate(SPECTRUM))
concepts["inside-3-spread"] = {"02-beams": svg(spread),
                               "03-apps": svg(rows(3, 120, 22, 400, SPECTRUM, white=True)),
                               "04-prism": glass([A, B, C], 0.22)}

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
    print("wrote", len(concepts), "concepts")
