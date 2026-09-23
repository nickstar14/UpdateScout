#!/usr/bin/env python3
"""Generate the UpdateScout icon as aligned SVG layers for Icon Composer.

The geometry is computed rather than hand-drawn: the ring is two arcs defined
by angle pairs, and each arrowhead is derived from the tangent at its arc's
end, so the two halves stay symmetric if the radius or stroke weight changes.

Corner rounding uses the fill-plus-same-colour-stroke trick with a round line
join — SVG has no "corner radius" for polygons. The stroke grows the shape by
half its width all round, so the triangle geometry is inset by that amount to
keep the finished size unchanged.
"""
import math
import pathlib

OUT = pathlib.Path(__file__).parent
C = 512.0            # canvas centre
R = 330.0            # ring radius
STROKE = 74.0        # ring thickness
LENS_R = 196.0

ROUND_RING = 40.0    # corner diameter on the ring arrowheads
ROUND_ARROW = 30.0   # corner diameter on the download arrow

# Ring arrowhead, sized so stroke growth lands back on the intended extent.
HEAD_LEN = 168.0 - ROUND_RING
HEAD_HALF = 104.0 - ROUND_RING / 2


def P(theta, r=R):
    """Point on the ring. Math angles mapped onto SVG's y-down canvas."""
    return (C + r * math.cos(math.radians(theta)),
            C - r * math.sin(math.radians(theta)))


def arc(a, b, r=R):
    """Clockwise arc path from angle a to angle b."""
    x1, y1 = P(a, r)
    x2, y2 = P(b, r)
    large = 1 if (a - b) % 360 > 180 else 0
    return f"M {x1:.1f} {y1:.1f} A {r} {r} 0 {large} 1 {x2:.1f} {y2:.1f}"


def head(theta, r=R):
    """Arrowhead triangle at an arc's end, pointing along the direction of travel."""
    px, py = P(theta, r)
    dx, dy = math.sin(math.radians(theta)), math.cos(math.radians(theta))
    nx, ny = -dy, dx
    tip = (px + dx * HEAD_LEN * 0.55, py + dy * HEAD_LEN * 0.55)
    b1 = (px - dx * HEAD_LEN * 0.45 + nx * HEAD_HALF,
          py - dy * HEAD_LEN * 0.45 + ny * HEAD_HALF)
    b2 = (px - dx * HEAD_LEN * 0.45 - nx * HEAD_HALF,
          py - dy * HEAD_LEN * 0.45 - ny * HEAD_HALF)
    return (f"M {tip[0]:.1f} {tip[1]:.1f} L {b1[0]:.1f} {b1[1]:.1f} "
            f"L {b2[0]:.1f} {b2[1]:.1f} Z")


def svg(body, defs=""):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024">\n{defs}{body}</svg>\n')


# 1 — backdrop -----------------------------------------------------------------
backdrop = svg(
    '  <rect width="1024" height="1024" fill="url(#bg)"/>\n',
    '  <defs>\n'
    '    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">\n'
    '      <stop offset="0" stop-color="#4F8DFF"/>\n'
    '      <stop offset="0.55" stop-color="#2F5FE0"/>\n'
    '      <stop offset="1" stop-color="#5B34C7"/>\n'
    '    </linearGradient>\n'
    '  </defs>\n')

# 2 — update ring --------------------------------------------------------------
TOP_A, TOP_B = 168.0, 22.0
BOT_A, BOT_B = 348.0, 202.0
ring = svg(
    f'  <g stroke="#FFFFFF" stroke-width="{STROKE}" stroke-linecap="round" fill="none">\n'
    f'    <path d="{arc(TOP_A, TOP_B)}"/>\n'
    f'    <path d="{arc(BOT_A, BOT_B)}"/>\n'
    '  </g>\n'
    # Fill + matching stroke with a round join rounds the arrowhead corners.
    f'  <g fill="#FFFFFF" stroke="#FFFFFF" stroke-width="{ROUND_RING}" '
    'stroke-linejoin="round" stroke-linecap="round">\n'
    f'    <path d="{head(TOP_B)}"/>\n'
    f'    <path d="{head(BOT_B)}"/>\n'
    '  </g>\n')

# 3 — lens ---------------------------------------------------------------------
lens = svg(
    f'  <circle cx="{C:.0f}" cy="{C:.0f}" r="{LENS_R:.0f}" fill="url(#lens)"/>\n',
    '  <defs>\n'
    '    <radialGradient id="lens" cx="0.35" cy="0.3" r="0.85">\n'
    '      <stop offset="0" stop-color="#FFFFFF"/>\n'
    '      <stop offset="0.6" stop-color="#E8F1FF"/>\n'
    '      <stop offset="1" stop-color="#BFD4F5"/>\n'
    '    </radialGradient>\n'
    '  </defs>\n')

# 4 — download arrow -----------------------------------------------------------
SHAFT_W = 58.0
TOP_Y = C - 118
MID_Y = C + 6
WING = 104.0 - ROUND_ARROW / 2          # inset for the rounding stroke
TIP_Y = C + 120 - ROUND_ARROW / 2
SHOULDER_Y = MID_Y - 34 + ROUND_ARROW / 2
arrow = svg(
    f'  <g fill="#1E3E8F" stroke="#1E3E8F" stroke-width="{ROUND_ARROW}" '
    'stroke-linejoin="round" stroke-linecap="round">\n'
    f'    <rect x="{C - SHAFT_W / 2:.1f}" y="{TOP_Y:.1f}" width="{SHAFT_W:.0f}" '
    f'height="{MID_Y - TOP_Y:.1f}" rx="{SHAFT_W / 2:.0f}" stroke="none"/>\n'
    f'    <path d="M {C - WING:.1f} {SHOULDER_Y:.1f} L {C:.0f} {TIP_Y:.1f} '
    f'L {C + WING:.1f} {SHOULDER_Y:.1f} Z"/>\n'
    '  </g>\n')

# 5 — specular glint -----------------------------------------------------------
glint = svg(
    '  <g clip-path="url(#lensClip)" fill="#FFFFFF">\n'
    '    <ellipse cx="428" cy="404" rx="74" ry="30" '
    'transform="rotate(-38 428 404)" opacity="0.75"/>\n'
    '    <ellipse cx="392" cy="452" rx="30" ry="14" '
    'transform="rotate(-38 392 452)" opacity="0.45"/>\n'
    '  </g>\n',
    '  <defs>\n'
    f'    <clipPath id="lensClip"><circle cx="{C:.0f}" cy="{C:.0f}" r="{LENS_R:.0f}"/></clipPath>\n'
    '  </defs>\n')

for name, data in [("01-backdrop.svg", backdrop), ("02-ring.svg", ring),
                   ("03-lens.svg", lens), ("04-arrow.svg", arrow),
                   ("05-glint.svg", glint)]:
    (OUT / name).write_text(data)
    print("wrote", name)
