#!/usr/bin/env python3
"""
Sands-of-Time style single-run track builder (时之沙 仿制).

Bakes the centerline from segments A-G (straights / arcs with given lengths & radii),
a height profile (basin jump, dune undulations, finish jump), gameplay markers
(boost pads, item box sites, checkpoints, jumps) and decoration placements, plus
a dune terrain heightmap.  Output:
    res://data/track_data.json      (centerline + markers + decorations)
    res://data/terrain_height.bin   (float32 heightmap, row-major)
The Godot side (scripts/sands_track.gd) turns this into Path3D/Curve3D, road mesh,
walls, collision, pads, item boxes and procedural props at load time.

Usage:  python3 tools/track_builder.py   (run from project root)
"""
import json, math, os, random, struct
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STEP = 2.0            # metres between centerline samples
HALF_WIDTH = 7.0      # road half width (6 karts side-by-side-ish)

# ---------------------------------------------------------------------------
# Segment table (A-G).  ("S", length) straight, ("L"/"R", radius, degrees) arc
# ---------------------------------------------------------------------------
SEGMENTS = [
    ("A", "起始直线加速带",  [("S", 340)]),
    ("B", "入镇弯",          [("L", 60, 60), ("S", 110)]),
    ("C", "沙漠小镇",        [("R", 12, 90),            # 直角弯
                               ("S", 80),
                               ("L", 16, 180),           # U 弯
                               ("S", 70),
                               ("R", 25, 70), ("L", 25, 70),  # S 弯
                               ("S", 60),
                               ("S", 110)]),             # 飞跃进凹地
    ("D", "开阔沙丘",        [("S", 140),
                               ("R", 17, 180),           # U 弯 1
                               ("S", 210),
                               ("L", 30, 180),           # U 弯 2
                               ("S", 250)]),
    ("E", "石柱沙丘",        [("R", 80, 70), ("S", 230)]),
    ("F", "终点段",          [("S", 140),                # 梯形加速区
                               ("S", 70),                # 跳台
                               ("L", 50, 90),            # 普通弯道
                               ("S", 290)]),             # 长加速带
    ("G", "冲线",            [("R", 45, 60), ("S", 260)]),
]


def build_centerline():
    pts = []      # (s, x, z, heading)
    seg_ranges = {}
    piece_ranges = []
    x = z = 0.0
    th = 0.0      # heading; dir = (-sin th, -cos th); +th = left turn
    s = 0.0
    pts.append((s, x, z, th))
    for sid, name, pieces in SEGMENTS:
        s0 = s
        for p in pieces:
            ps = s
            if p[0] == "S":
                L = p[1]
                n = max(1, int(round(L / STEP)))
                ds = L / n
                for _ in range(n):
                    x += -math.sin(th) * ds
                    z += -math.cos(th) * ds
                    s += ds
                    pts.append((s, x, z, th))
            else:
                R, deg = p[1], p[2]
                sign = 1.0 if p[0] == "L" else -1.0
                L = R * math.radians(deg)
                n = max(2, int(round(L / STEP)))
                ds = L / n
                dth = sign * ds / R
                for _ in range(n):
                    # exact arc step (chord)
                    mid = th + dth * 0.5
                    chord = 2 * R * math.sin(abs(dth) / 2)
                    x += -math.sin(mid) * chord
                    z += -math.cos(mid) * chord
                    th += dth
                    s += ds
                    pts.append((s, x, z, th))
            piece_ranges.append({"segment": sid, "type": p[0], "params": list(p[1:]),
                                 "start": round(ps, 2), "end": round(s, 2)})
        seg_ranges[sid] = {"name": name, "start": round(s0, 2), "end": round(s, 2)}
    return pts, seg_ranges, piece_ranges


def smoothstep(a, b, v):
    t = min(max((v - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def make_height_fn(seg, pieces):
    c_end = seg["C"]["end"]
    d0, e_end = seg["D"]["start"], seg["E"]["end"]
    f0 = seg["F"]["start"]
    # basin jump: last C straight (110 m) – ramp starts 30 m into it
    jump1 = c_end - 110 + 30
    jump1_len, jump1_h, basin = 14.0, 2.6, -5.0
    # finish jump: F piece 2 (the 70 m straight)
    jump2 = f0 + 140 + 20
    jump2_len, jump2_h = 16.0, 3.0

    def h(s):
        y = 0.0
        if s < jump1:
            y = 0.0
        elif s < jump1 + jump1_len:
            y = jump1_h * (s - jump1) / jump1_len
        elif s < e_end - 120:
            # basin floor rising back to 0 through the dunes
            y = basin + (0 - basin) * smoothstep(d0 + 60, e_end - 140, s)
            # dune undulation (起伏地形) only on D/E
            w = smoothstep(d0 + 20, d0 + 60, s) * (1 - smoothstep(e_end - 200, e_end - 140, s))
            y += 2.2 * math.sin((s - d0) * 2 * math.pi / 72.0) * w
        elif s < jump2:
            y = 0.0
        elif s < jump2 + jump2_len:
            y = jump2_h * (s - jump2) / jump2_len
        else:
            y = 0.0
        return y

    jumps = [
        {"s": jump1, "len": jump1_len, "height": jump1_h, "name": "飞跃凹地"},
        {"s": jump2, "len": jump2_len, "height": jump2_h, "name": "终点跳台"},
    ]
    return h, jumps


def main():
    random.seed(20261019)
    pts, seg, pieces = build_centerline()
    total = pts[-1][0]
    h, jumps = make_height_fn(seg, pieces)

    P = np.array([[p[1], p[2]] for p in pts])
    S = np.array([p[0] for p in pts])
    # self-clearance check
    worst = 1e9
    for i in range(0, len(P), 3):
        far = np.abs(S - S[i]) > 90
        if far.any():
            d = np.min(np.linalg.norm(P[far] - P[i], axis=1))
            worst = min(worst, d)
    print(f"track length {total:.1f} m, points {len(pts)}, min clearance {worst:.1f} m")
    assert worst > 2 * HALF_WIDTH + 14, "track sections too close"

    centerline = []
    for (s, x, z, th) in pts:
        centerline.append([round(x, 3), round(h(s), 3), round(z, 3), round(th, 5), round(s, 2)])

    def at(s):
        i = min(int(np.searchsorted(S, s)), len(S) - 1)
        return pts[i]

    # ---------------- gameplay markers ----------------
    boost_pads = [
        {"s": 45, "len": 30, "shape": "strip", "bonus": 4.0, "time": 1.5, "name": "起始加速带"},
        {"s": seg["F"]["start"] + 40, "len": 50, "shape": "trapezoid", "bonus": 5.0, "time": 1.8, "name": "梯形加速区"},
        {"s": seg["F"]["end"] - 270, "len": 30, "shape": "strip", "bonus": 4.5, "time": 1.6, "name": "长加速带1"},
        {"s": seg["F"]["end"] - 170, "len": 30, "shape": "strip", "bonus": 4.5, "time": 1.6, "name": "长加速带2"},
        {"s": seg["F"]["end"] - 70, "len": 30, "shape": "strip", "bonus": 4.5, "time": 1.6, "name": "长加速带3"},
    ]
    item_sites = [
        {"s": 200, "count": 6},
        {"s": seg["C"]["start"] + 165, "count": 4},
        {"s": seg["D"]["start"] + 100, "count": 5},
        {"s": seg["D"]["end"] - 120, "count": 6},
        {"s": seg["E"]["end"] - 60, "count": 3},
    ]
    checkpoints = [round(c, 1) for c in np.arange(150, total - 20, 150)]

    # ---------------- decorations ----------------
    def clear_of_road(x, z, margin):
        return np.min(np.linalg.norm(P - np.array([x, z]), axis=1)) > HALF_WIDTH + margin

    def side_point(s, side, dist):
        _, x, z, th = at(s)
        rx, rz = math.cos(th), -math.sin(th)   # right vector
        return x + rx * dist * side, z + rz * dist * side, h(s)

    buildings, pillars, arches, cacti, palms, rocks = [], [], [], [], [], []
    cs, ce = seg["C"]["start"], seg["C"]["end"] - 90
    s = cs + 10
    while s < ce:
        for side in (-1, 1):
            if random.random() < 0.75:
                w, d, hh = random.uniform(8, 14), random.uniform(7, 12), random.uniform(5, 11)
                dist = HALF_WIDTH + 2.5 + d * 0.5 + random.uniform(0.5, 3)
                x, z, y = side_point(s, side, dist)
                if clear_of_road(x, z, 1.5 + max(w, d) * 0.5):
                    th = at(s)[3]
                    buildings.append({"x": round(x, 2), "y": round(y, 2), "z": round(z, 2), "rot": round(th, 3),
                                      "w": round(w, 2), "d": round(d, 2), "h": round(hh, 2),
                                      "lshape": random.random() < 0.35, "dome": random.random() < 0.25})
        s += random.uniform(16, 24)
    for s_arch in (seg["C"]["start"] + 2, seg["C"]["end"] - 100, seg["D"]["start"] + 260, seg["F"]["end"] - 10):
        _, x, z, th = at(s_arch)
        arches.append({"x": round(x, 2), "y": round(h(s_arch), 2), "z": round(z, 2), "rot": round(th, 3), "span": HALF_WIDTH * 2 + 3})
    # stone pillars (散落石柱) on D/E, some near road
    for _ in range(46):
        s = random.uniform(seg["D"]["start"] + 30, seg["E"]["end"])
        side = random.choice((-1, 1))
        x, z, y = side_point(s, side, HALF_WIDTH + random.uniform(4, 30))
        if clear_of_road(x, z, 3):
            pillars.append({"x": round(x, 2), "y": round(y - 1, 2), "z": round(z, 2),
                            "r": round(random.uniform(1.0, 2.4), 2), "h": round(random.uniform(6, 16), 2),
                            "tilt": round(random.uniform(-0.12, 0.12), 3)})
    # vegetation
    xmin, zmin = P.min(axis=0) - 120
    xmax, zmax = P.max(axis=0) + 120
    tries = 0
    while (len(cacti) < 90 or len(palms) < 28 or len(rocks) < 30) and tries < 20000:
        tries += 1
        s = random.uniform(0, total)
        side = random.choice((-1, 1))
        dist = HALF_WIDTH + random.uniform(3, 45)
        x, z, y = side_point(s, side, dist)
        if not clear_of_road(x, z, 2.5):
            continue
        in_dunes = seg["D"]["start"] <= s <= seg["E"]["end"]
        r = random.random()
        item = {"x": round(x, 2), "z": round(z, 2), "rot": round(random.uniform(0, 6.28), 2),
                "scale": round(random.uniform(0.8, 1.4), 2), "variant": random.randint(0, 5)}
        if r < 0.55 and len(cacti) < 90:
            item["variant"] %= 6; cacti.append(item)
        elif r < 0.8 and len(palms) < 28 and not in_dunes or (r < 0.8 and len(palms) < 28 and random.random() < 0.3):
            item["variant"] %= 4; palms.append(item)
        elif len(rocks) < 30:
            item["variant"] %= 3; rocks.append(item)

    # ---------------- terrain heightmap ----------------
    cell = 6.0
    nx = int((xmax - xmin) / cell) + 1
    nz = int((zmax - zmin) / cell) + 1
    gx = xmin + np.arange(nx) * cell
    gz = zmin + np.arange(nz) * cell
    GX, GZ = np.meshgrid(gx, gz)          # shape (nz, nx)
    flat = np.stack([GX.ravel(), GZ.ravel()], axis=1)
    road_h = np.array([c[1] for c in centerline])
    best_d = np.full(len(flat), 1e9)
    best_h = np.zeros(len(flat))
    best_s = np.zeros(len(flat))
    for i in range(0, len(P), 2):
        d = np.linalg.norm(flat - P[i], axis=1)
        m = d < best_d
        best_d[m] = d[m]; best_h[m] = road_h[i]; best_s[m] = S[i]
    X, Z = flat[:, 0], flat[:, 1]
    dune = (3.5 * np.sin(X * 0.021 + 1.3) * np.cos(Z * 0.017) +
            2.0 * np.sin(X * 0.047 + Z * 0.031) +
            1.2 * np.sin(Z * 0.083 + 0.7) + 3.0)
    town = (best_s >= seg["C"]["start"]) & (best_s <= seg["C"]["end"] - 90)
    dune = np.where(town, dune * 0.15, dune)
    t = np.clip((best_d - (HALF_WIDTH + 3)) / 40.0, 0, 1)
    t = t * t * (3 - 2 * t)
    hgt = (best_h - 0.35) * (1 - t) + (np.minimum(best_h, 0) - 0.5 + dune) * t
    hgt = hgt.reshape(nz, nx).astype(np.float32)
    with open(os.path.join(ROOT, "data", "terrain_height.bin"), "wb") as f:
        f.write(hgt.tobytes())

    data = {
        "name": "时之沙 · Sands of Time (demo)",
        "length": round(total, 2),
        "half_width": HALF_WIDTH,
        "segments": seg,
        "pieces": pieces,
        "centerline": centerline,          # [x, y, z, heading, s]
        "jumps": jumps,
        "boost_pads": boost_pads,
        "item_sites": item_sites,
        "checkpoints": checkpoints,
        "start_s": 22.0,
        "decor": {"buildings": buildings, "pillars": pillars, "arches": arches,
                  "cacti": cacti, "palms": palms, "rocks": rocks},
        "terrain": {"x0": float(xmin), "z0": float(zmin), "cell": cell, "nx": nx, "nz": nz},
    }
    with open(os.path.join(ROOT, "data", "track_data.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    for k, v in seg.items():
        print(k, v)
    print("buildings", len(buildings), "pillars", len(pillars), "arches", len(arches),
          "cacti", len(cacti), "palms", len(palms), "rocks", len(rocks), "terrain", nx, nz)


if __name__ == "__main__":
    main()
