"""Build the desert kart track layout data.

Runs offline and writes res://data/track_layout.json.
The Godot runtime only reads that JSON, so the geometry stays identical
between this script and the game.

Segment notation:
    ("S", length)          straight, metres
    ("A", angle_deg, R)    arc; positive angle turns right (toward +Z when heading +X)
"""

import json
import math
import os

STEP = 2.0
RUN_OUT = 150.0          # straight after the finish line where finished karts coast
RAMP_LEN = 18.0          # kicker length (concave, steepest at the lip)
RAMP_HEIGHT = 2.6
RAMP_DROP = 3.0          # length of the drop back to grade after the lip

# ---------------------------------------------------------------------------
# Course definition (single run: start gate -> finish line -> run-out)
# ---------------------------------------------------------------------------
SEGS = [
    ("S", 130),        # start straight, grid painted here
    ("A", 90, 20),     # turn 1, right hand bowl
    ("S", 40),
    ("A", -180, 22),   # hairpin left
    ("S", 40),
    ("A", 90, 18),     # tight right
    ("S", 25),
    ("A", 50, 45),     # flowing esses
    ("A", -50, 45),
    ("S", 175),        # ramp basin
    ("A", 180, 24),    # U turn right
    ("S", 45),
    ("A", -180, 24),   # U turn left
    ("S", 28),
    ("A", 90, 60),     # wide sweepers into the dunes
    ("S", 250),
    ("A", 90, 70),
    ("S", 560),        # long dune straight
    ("A", -90, 55),
    ("S", 420),        # second long straight
    ("A", 90, 60),
    ("S", 140),
    ("A", 90, 45),
    ("S", 280),        # final straight to the finish line
    ("S", RUN_OUT),    # run-out beyond the finish
]


def path_points(segs, step=STEP):
    pts = [(0.0, 0.0)]
    kinds = [0.0]        # per-sample: 0 for straight, otherwise the arc radius
    heading = 0.0
    x = z = 0.0
    for seg in segs:
        if seg[0] == "S":
            length = float(seg[1])
            n = max(1, int(round(length / step)))
            ds = length / n
            for _ in range(n):
                x += math.cos(heading) * ds
                z += math.sin(heading) * ds
                pts.append((x, z))
                kinds.append(0.0)
        else:
            _, angle, radius = seg
            length = math.radians(abs(angle)) * radius
            n = max(1, int(round(length / step)))
            ds = length / n
            dh = math.radians(angle) / n
            for _ in range(n):
                mid = heading + dh * 0.5
                x += math.cos(mid) * ds
                z += math.sin(mid) * ds
                heading += dh
                pts.append((x, z))
                kinds.append(float(radius))
    return pts, kinds


def base_elevation(s):
    return 2.4 * math.sin(s / 120.0) + 1.1 * math.sin(s / 55.0 + 2.1)


def ramp_lift(s, ramps):
    """Kicker ramps: concave rise (steepest at the lip) then a short drop."""
    lift = 0.0
    for r in ramps:
        if r <= s < r + RAMP_LEN:
            t = (s - r) / RAMP_LEN
            lift = max(lift, RAMP_HEIGHT * t ** 1.6)
        elif r + RAMP_LEN <= s < r + RAMP_LEN + RAMP_DROP:
            t = (s - (r + RAMP_LEN)) / RAMP_DROP
            lift = max(lift, RAMP_HEIGHT * (1.0 - t) ** 0.5)
    return lift


def is_straight(kinds, s0, s1):
    i0 = max(0, int(s0 / STEP))
    i1 = min(len(kinds) - 1, int(math.ceil(s1 / STEP)))
    return all(k == 0.0 for k in kinds[i0:i1 + 1])


def min_separation(pts, step=STEP, min_gap=60.0):
    worst = (1e9, None, None)
    n = len(pts)
    gap_samples = int(min_gap / step)
    for i in range(n):
        for j in range(i + gap_samples, n):
            d = math.dist(pts[i], pts[j])
            if d < worst[0]:
                worst = (d, i * step, j * step)
    return worst


def main():
    pts2, kinds = path_points(SEGS)
    length = (len(pts2) - 1) * STEP
    finish = length - RUN_OUT

    taken = []

    def place(target, span, window=160.0, gap=45.0):
        """Closest offset to target whose [s, s+span] is straight and away from other features."""
        best = None
        s = target - window
        while s <= target + window:
            ok = 60.0 < s < finish - 40.0 and is_straight(kinds, s - 4.0, s + span)
            ok = ok and all(abs(s - t) > gap for t in taken)
            if ok and (best is None or abs(s - target) < abs(best - target)):
                best = s
            s += STEP
        if best is None:
            raise SystemExit(f"cannot place feature near {target}")
        taken.append(best)
        return round(best, 1)

    ramps = [place(f * finish, RAMP_LEN + RAMP_DROP + 45.0, 220.0, 60.0) for f in (0.17, 0.47, 0.83)]
    boosts = [place(f * finish, 12.0) for f in (0.06, 0.23, 0.39, 0.575, 0.71, 0.92)]
    items = [place(f * finish, 6.0) for f in (0.10, 0.215, 0.33, 0.52, 0.645, 0.77, 0.875)]

    points = []
    for i, (x, z) in enumerate(pts2):
        s = i * STEP
        y = base_elevation(s) + ramp_lift(s, ramps)
        points.append([round(x, 3), round(y, 3), round(z, 3)])

    worst = min_separation(pts2)
    print("ramps ", ramps)
    print("boosts", boosts)
    print("items ", items)
    print(f"total length  : {length:.1f} m (race {finish - 40.0:.1f} m, run-out {RUN_OUT:.0f} m)")
    print(f"end position  : ({pts2[-1][0]:.1f}, {pts2[-1][1]:.1f})")
    print(f"min separation: {worst[0]:.1f} m  between s={worst[1]} and s={worst[2]}")

    checkpoints = [round(finish * (k / 14.0), 1) for k in range(1, 14)]

    data = {
        "name": "Sands of Time",
        "step": STEP,
        "length": round(length, 2),
        "road_width": 12.0,
        "wall_height": 0.8,
        "start_offset": 40.0,
        "finish_offset": round(finish, 1),
        "points": points,
        "ramps": ramps,
        "ramp_length": RAMP_LEN,
        "boosts": boosts,
        "item_rows": items,
        "checkpoints": checkpoints,
    }

    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "data", "track_layout.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(data, fh, separators=(",", ":"))
    print(f"wrote {out}  ({len(points)} points)")


if __name__ == "__main__":
    main()
