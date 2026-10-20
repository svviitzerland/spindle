#!/usr/bin/env python3
"""Find props that intersect each other, or the deck, on the desk.

Footprints are taken in the x-z plane. Rectangular props are treated as
rotated rectangles and tested with the separating axis theorem; round ones as
circles. A bounding circle around a sleeve is far too generous and reports
overlaps that are not there, which is how the real ones stayed hidden.

Run after moving anything in addDressing:  python3 scripts/layout-audit.py
"""
import math, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PRESETS = (ROOT / "Sources/Spindle/Scene/Presets.swift").read_text()
SCENE = (ROOT / "Sources/Spindle/Scene/TurntableScene.swift").read_text()

def placements():
    """Read positions straight out of addDressing so this cannot drift."""
    body = SCENE[SCENE.index("private func addDressing"):]
    body = body[:body.index("\n    }")]
    found, current = {}, None
    for line in body.splitlines():
        flag = re.search(r"if dressing\.(\w+)", line)
        if flag:
            current = flag.group(1)
        pos = re.search(r"position = SCNVector3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\)", line)
        if pos and current and current not in found:
            x, y, z = (float(v) for v in pos.groups())
            if y < 0.3:                      # wall-mounted things have no footprint
                found[current] = (x, z)
        yaw = re.search(r"eulerAngles = SCNVector3\(0, ([-\d.]+), 0\)", line)
        if yaw and current in found and len(found[current]) == 2:
            found[current] = (*found[current], float(yaw.group(1)))
    return {k: (v[0], v[1], v[2] if len(v) > 2 else 0.0) for k, v in found.items()}

# half-extents for rectangles, radius for circles
SHAPES = {
    "sleeveStand":  ("rect", 0.184, 0.044),
    "sleeve":       ("rect", 0.158, 0.030),
    "stack":        ("rect", 0.158, 0.158),
    "books":        ("rect", 0.078, 0.108),
    "leaningFrame": ("rect", 0.128, 0.030),
    "mug":          ("circle", 0.070),
    # Pots, not foliage. Leaves drape over things and are meant to; a pot
    # standing inside a sleeve stand is the bug. Checking the leaf spread
    # pushed the planting out of frame to satisfy a collision that was never
    # one.
    "plant":        ("circle", 0.078),
    "bigPlant":     ("circle", 0.104),
    "headphones":   ("circle", 0.110),
    "lamp":         ("circle", 0.075),
}
DECK = ("rect", 0.2225, 0.179)

def corners(c, hx, hz, yaw):
    cos, sin = math.cos(yaw), math.sin(yaw)
    return [(c[0] + dx * cos - dz * sin, c[1] + dx * sin + dz * cos)
            for dx, dz in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz))]

def overlap_rects(a, b):
    """Separating axis theorem: any gap on any edge normal means no overlap."""
    least = float("inf")
    for poly in (a, b):
        for i in range(len(poly)):
            x1, z1 = poly[i]
            x2, z2 = poly[(i + 1) % len(poly)]
            nx, nz = -(z2 - z1), x2 - x1
            length = math.hypot(nx, nz) or 1
            nx, nz = nx / length, nz / length
            pa = [p[0] * nx + p[1] * nz for p in a]
            pb = [p[0] * nx + p[1] * nz for p in b]
            gap = max(min(pa) - max(pb), min(pb) - max(pa))
            if gap > 0:
                return None
            least = min(least, -gap)
    return least

def overlap_circle_rect(centre, r, poly):
    best = float("inf")
    inside = True
    for i in range(len(poly)):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % len(poly)]
        ex, ez = x2 - x1, z2 - z1
        t = max(0, min(1, ((centre[0]-x1)*ex + (centre[1]-z1)*ez) / (ex*ex + ez*ez)))
        best = min(best, math.dist(centre, (x1 + ex*t, z1 + ez*t)))
        if (centre[0]-x1)*ez - (centre[1]-z1)*ex > 0:
            inside = False
    if inside:
        return r + best
    return r - best if best < r else None

def shape_for(name, place):
    kind = SHAPES[name]
    if kind[0] == "rect":
        return ("rect", corners((place[0], place[1]), kind[1], kind[2], place[2]))
    return ("circle", (place[0], place[1]), kind[1])

def dressing():
    out = {}
    for m in re.finditer(r'id: "([a-z]+)",', PRESETS):
        name, start = m.group(1), m.start()
        nxt = PRESETS.find("    static let", start)
        block = PRESETS[start: nxt if nxt != -1 else len(PRESETS)]
        d = re.search(r"dressing: \.init\((.*?)\),\n", block, re.S)
        out[name] = {k: v == "true" for k, v in re.findall(r"(\w+): (true|false)", d.group(1))} if d else {}
    return out

def main():
    places = placements()
    deck_poly = corners((0, 0), DECK[1], DECK[2], 0)
    issues = []

    for scene, flags in dressing().items():
        present = []
        for name in SHAPES:
            if name == "sleeve" and not (flags.get("sleeve") and not flags.get("sleeveStand")):
                continue
            if name == "sleeveStand" and not flags.get("sleeveStand"):
                continue
            if name not in ("sleeve", "sleeveStand") and not flags.get(name):
                continue
            if name not in places:
                continue
            present.append((name, shape_for(name, places[name])))

        for name, shape in present:
            depth = (overlap_rects(shape[1], deck_poly) if shape[0] == "rect"
                     else overlap_circle_rect(shape[1], shape[2], deck_poly))
            if depth:
                issues.append((scene, name, "deck", depth))

        for i in range(len(present)):
            for j in range(i + 1, len(present)):
                (n1, s1), (n2, s2) = present[i], present[j]
                if s1[0] == "rect" and s2[0] == "rect":
                    depth = overlap_rects(s1[1], s2[1])
                elif s1[0] == "circle" and s2[0] == "circle":
                    d = math.dist(s1[1], s2[1]) - (s1[2] + s2[2])
                    depth = -d if d < 0 else None
                else:
                    circle, rect = (s1, s2) if s1[0] == "circle" else (s2, s1)
                    depth = overlap_circle_rect(circle[1], circle[2], rect[1])
                if depth:
                    issues.append((scene, n1, n2, depth))

    if not issues:
        print("no overlaps")
        return 0
    print(f"{'scene':<14}{'prop':<14}{'intersects':<14}depth")
    for scene, a, b, depth in sorted(issues, key=lambda x: -x[3]):
        print(f"{scene:<14}{a:<14}{b:<14}{depth*1000:5.0f} mm")
    print(f"\n{len(issues)} overlaps")
    return 1

sys.exit(main())
