"""Trace city landmarks from their drawings into box models, and pack the models into landmark_models.gd.

    python tools/trace/trace.py jobs [key ...]   cut each drawing into build/trace/<key>/ with render.py and a prompt
    sh tools/trace/run.sh key [key ...]          let Codex fit build/trace/<key>/model.json, 5 at a time
    python tools/trace/trace.py fix notes.json   a job per key in notes.json ({key: review notes}) that starts from the
                                                 kept model and fixes only what the notes say (then run.sh again; copy
                                                 tools/trace/models/ aside first, `keep` overwrites the reviewed model)
    python tools/trace/trace.py keep [key ...]   copy the fitted models into tools/trace/models/
    python tools/trace/trace.py pack             write landmark_models.gd from tools/trace/models/

Keys are sheet_frame (landmarks_0, tokyo_8). render.py scores a model against its drawing in the city camera's own
projection; the Codex prompt (prompt.txt) loops on it. Packing turns the green blocks a trace draws for tree crowns
into the game's tree sprites, standing on what is under them, and cuts the curved and slanted parts (cylinders, domes,
vaults, beams, temple roofs, arches) into the same flat faces render.py scored.
"""
import colorsys
import glob
import json
import math
import os
import shutil
import subprocess
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
JOBS = os.path.join(GAME, "build", "trace")
MODELS = os.path.join(HERE, "models")
WHAT = {
    "tokyo_0": "Tokyo Tower: a red and white lattice tower on four splayed legs with two observation decks, over a low white building",
    "tokyo_1": "Tokyo Skytree: a very tall white lattice tower, round and tapering, with two ring-shaped observation decks and a mast",
    "tokyo_10": "Odaiba: a big Ferris wheel on the waterfront with a low glass mall beside it",
    "landmarks_0": "a commuter railway station: station building, platform canopy, a train at the platform, tracks",
    "landmarks_2": "a university/school: classroom blocks, a sports ground, trees round the edge",
    "landmarks_3": "a Shinto shrine: hall with a curved tiled roof, torii gate, stone lanterns, trees",
    "landmarks_4": "a city park: a pond, paths, benches, lamps, many trees",
    "landmarks_6": "a shotengai shopping arcade: a glazed arched roof over a shop street, shops either side",
    "tokyo_2": "Asakusa's Kaminarimon: a red temple gate with a big tiled roof and lantern, on a stone plaza",
    "tokyo_3": "Tokyo Station's red-brick Marunouchi building with its domes",
    "tokyo_4": "the Nishi-Shinjuku skyscrapers: a cluster of glass towers on a plaza",
    "tokyo_5": "Shibuya scramble crossing: big screens on the corner buildings round the crossing",
    "tokyo_6": "Ginza's Wako building: a stone department store with a rounded corner and a clock tower",
    "tokyo_7": "Akihabara: tall buildings covered in colourful signboards",
    "tokyo_8": "the Imperial Palace: a moat, a stone double bridge, walls, a white turret, pines",
    "tokyo_9": "Meiji Shrine at Yoyogi: a great wooden torii on a gravel path through a forest",
    "tokyo_11": "Roppongi Hills: a tall rounded office tower on a podium with plazas",
}
# drawings the square can't hold as drawn, with what the trace should do instead (appended to their prompt)
NOTES = {
    "tokyo_3": "\nTHIS DRAWING\nTokyo Station is drawn longer than the square: in the picture it runs about 30 m along x. Keep x "
               "and z within [-11, 11] anyway and build the whole station compressed along x into the square's 22 m, at the "
               "drawing's low proportions: from west to east a domed end wing, the long body, the central entrance block, the "
               "long body again, the other domed end wing. The body is 2 storeys of red brick (6 m to the eaves, \"s\" 10 with "
               "#b4513c) with white stone bands as thin boxes, under a slate-blue (#4a5880) hipped \"roof\" about 2 m high; the "
               "centre block 7 m to its eaves under its own pointed hipped roof; each end wing a square block 7 m to its eaves "
               "carrying an octagonal brick drum (cyl, n 8) to about 8.5 m and a slate-blue \"dome\" (n 8) to about 11 m with "
               "a small finial (a thin cyl with top 0). The building is about 6 m deep along z (z about -2 to 4); in front (+z) "
               "a pale paved forecourt slab with a few lamps and trees, behind it a thin ground slab.\nBecause the drawing is "
               "longer than the square, render.py's iou cannot reach 0.85 here: stop when iou stops improving (expect about "
               "0.5) or after 15 runs, judging by compare.png that the parts stand in the drawing's order along the facade.\n",
}
HEIGHT = {"landmarks": 256, "tokyo": 384}
PINES = {"tokyo_8"}


def jobs(keys):
    prompt = open(os.path.join(HERE, "prompt.txt"), encoding="utf-8").read()
    for key in keys:
        sheet, frame = key.rsplit("_", 1)
        d = os.path.join(JOBS, key)
        os.makedirs(d, exist_ok=True)
        im = Image.open(os.path.join(GAME, "art", sheet + ".png")).convert("RGBA")
        im.crop((int(frame) * 256, 0, int(frame) * 256 + 256, HEIGHT[sheet])).save(os.path.join(d, "cell.png"))
        shutil.copy(os.path.join(HERE, "render.py"), d)
        open(os.path.join(d, "prompt.txt"), "w", encoding="utf-8").write(prompt.replace("{WHAT}", WHAT[key]) + NOTES.get(key, ""))
        print(key, "->", d)


def fix(path):
    notes = json.load(open(path, encoding="utf-8"))
    jobs(notes)
    for key, text in notes.items():
        d = os.path.join(JOBS, key)
        shutil.copy(os.path.join(MODELS, key + ".json"), os.path.join(d, "model.json"))
        # hold the fix to the kept model's own fit: some are kept well under 0.85 on purpose (a compressed or reworked one)
        out = subprocess.run([sys.executable, "render.py", "model.json", "cell.png"], cwd=d, capture_output=True, text=True).stdout
        floor = max(0.4, round(json.loads(out.splitlines()[0])["iou"] - 0.05, 2))
        with open(os.path.join(d, "prompt.txt"), "a", encoding="utf-8") as f:
            f.write("\nTHIS RUN\nmodel.json already holds a finished trace. A review of it in the game found the defects below. "
                    "Fix exactly these and keep everything else as it is; check with render.py that iou stays >= %.2f "
                    "(at most 8 runs), then reply with one line of scores.\n%s\n" % (floor, text))


def keep(keys):
    for key in keys:
        shutil.copy(os.path.join(JOBS, key, "model.json"), os.path.join(MODELS, key + ".json"))
        print(key, "kept")


def hsv(c):
    r, g, b = [int(c.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return colorsys.rgb_to_hsv(r, g, b)


def extent(p):
    if "box" in p:
        return p["box"]
    cx, cz, rx, rz, y0, h = p["dome"]
    return [cx - rx, cz - rz, cx + rx, cz + rz, y0, y0 + h]


def treeify(prims, pines):
    """Green boxes held up off the ground and green domes are tree crowns the trace drew as solids: they become the
    game's tree sprites (one per ~3.6 m of crown, sized by the crown's height), standing on whatever is under them (a
    bank, a plinth); the thin trunks under them go, and trees closer than 2.2 m merge. A broad thin green slab is a lawn, a thin upright one a sign, a flat one up a wall an awning."""
    green = lambda p: "c" in p and 0.2 < hsv(p["c"])[0] < 0.45 and hsv(p["c"])[1] > 0.25
    lawn = lambda b: b[5] - b[4] < 0.5 and (b[2] - b[0]) * (b[3] - b[1]) > 12.0
    panel = lambda b: min(b[2] - b[0], b[3] - b[1]) < 0.6 and b[5] - b[4] > min(b[2] - b[0], b[3] - b[1])  # a sign or screen
    awning = lambda b: b[5] - b[4] < 0.5 and b[4] > 2.5
    crowns = [p for p in prims if green(p) and ("dome" in p or "box" in p and p["box"][4] >= 0.8 and not any(f(p["box"]) for f in (lawn, panel, awning)))]
    rest = [p for p in prims if "box" in p and p not in crowns]

    def base(x, z, top):  # the highest broad surface under (x, z) that is not above `top`
        ys = [q["box"][5] for q in rest if q["box"][0] <= x <= q["box"][2] and q["box"][1] <= z <= q["box"][3] and q["box"][5] <= top + 0.3
              and (q["box"][2] - q["box"][0] > 1.0 or q["box"][3] - q["box"][1] > 1.0)]
        return max(ys, default=0.0)

    trees = []
    for p in prims:
        if "tree" in p:
            x, z, sc = p["tree"]
            trees.append([x, z, sc, 1, base(x, z, 4.0)])
    for p in crowns:
        x0, z0, x1, z1, y0, y1 = extent(p)
        nx, nz = max(1, math.ceil((x1 - x0) / 3.6 - 0.2)), max(1, math.ceil((z1 - z0) / 3.6 - 0.2))
        for i in range(nx):
            for j in range(nz):
                x, z = x0 + (i + 0.5) * (x1 - x0) / nx, z0 + (j + 0.5) * (z1 - z0) / nz
                y = base(x, z, y0)
                trees.append([x, z, min(1.8, max(0.75, (y1 - y) / 3.3)), 1, y])
    merged = []
    for t in sorted(trees, key=lambda t: -t[2]):
        if all(math.hypot(t[0] - u[0], t[1] - u[1]) >= 2.2 for u in merged):
            merged.append(t)
    for k, t in enumerate(merged):
        t[3] = 4 if t[2] < 0.6 else (3 if pines and k % 2 == 0 else 1)
    under = lambda x, z: any(extent(c)[0] - 0.5 <= x <= extent(c)[2] + 0.5 and extent(c)[1] - 0.5 <= z <= extent(c)[3] + 0.5 for c in crowns)

    def trunk(q):  # a thin upright box, or a dark upright beam, under a crown
        if "box" in q:
            b = q["box"]
            return b[2] - b[0] <= 1.0 and b[3] - b[1] <= 1.0 and b[5] - b[4] > 0.8 and under((b[0] + b[2]) / 2, (b[1] + b[3]) / 2)
        if "beam" in q:
            b = q["beam"]
            return abs(b[0] - b[3]) < 0.3 and abs(b[2] - b[5]) < 0.3 and abs(b[1] - b[4]) > 0.8 and hsv(q["c"])[2] < 0.5 and under(b[0], b[2])
        return False

    kept = [p for p in prims if p not in crowns and "tree" not in p and not trunk(p)]
    return kept + [{"tree": t[:3], "kind": t[3], "y": round(t[4], 2)} for t in merged[:40]]


def num(v):
    return ("%.2f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


def rows(p):
    """A primitive's rows in landmark_models.gd; a curved or slanted one becomes its faces (undersides dropped)."""
    if any(k in p for k in ("box", "gable", "tree")):
        return [row(p)]
    face = lambda q, n: [4, p["c"].lstrip("#"), *[round(float(v), 3) for v in n], *[round(float(v), 2) for v in q.ravel()]]
    if "cyl" in p and "s" in p and p.get("top", 1.0) == 1.0:  # a windowed drum: each side a turned box with the facade
        cx, cz, rx, rz, y0, y1 = p["cyl"]
        n = int(p.get("n", 12))
        ring = render.ring(cx, cz, rx, rz, y0, n)
        out = []
        for i in range(n):
            (ax, _, az), (bx, _, bz) = ring[i], ring[(i + 1) % n]
            w, tx, tz = math.hypot(bx - ax, bz - az), (bx - ax), (bz - az)
            nx, nz = tz / w, -tx / w  # outward, as the ring runs counter-clockwise seen from above
            if nx * ((ax + bx) / 2 - cx) + nz * ((az + bz) / 2 - cz) < 0:
                nx, nz = -nx, -nz
            mx, mz = (ax + bx) / 2 - nx * 0.15, (az + bz) / 2 - nz * 0.15
            out.append([0, mx - w / 2, mz - 0.15, mx + w / 2, mz + 0.15, y0, y1, p["c"].lstrip("#"), p["s"], p.get("a", 0), round(math.atan2(-tz, tx), 4)])
        return out + [face(q, nn) for q, nn, c in render.faces(p) if nn[1] > 0.9]
    return [face(q, n) for q, n, c in render.faces(p) if n[1] > -0.9]


def row(p):
    if "box" in p:
        return [0, *p["box"], p["c"].lstrip("#"), p.get("s", -1), p.get("a", 0)]
    if "gable" in p:
        return [1 if p.get("ridge", "z") == "x" else 2, *p["gable"], p["c"].lstrip("#")]
    return [3, *p["tree"], p.get("kind", 1), p.get("y", 0.0)]


def pack():
    keys = sorted(os.path.basename(f)[:-5] for f in glob.glob(os.path.join(MODELS, "*.json")))
    lines = []
    for key in keys:
        m = json.load(open(os.path.join(MODELS, key + ".json"), encoding="utf-8"))
        sheet, frame = key.rsplit("_", 1)
        rs = [r for p in treeify(m["prims"], key in PINES) for r in rows(p)]
        body = ",\n\t\t".join("[" + ", ".join('"%s"' % v if isinstance(v, str) else num(v) for v in r) + "]" for r in rs)
        lines.append('\t"%s:%s": [  # %s\n\t\t%s,\n\t],' % (sheet, frame, m.get("name", key), body))
    src = '''## Landmarks rebuilt as boxes, traced from their drawings in art/landmarks.png and art/tokyo.png by
## tools/trace/trace.py (the models are in tools/trace/models/); regenerate rather than edit. Keyed "sheet:frame";
## metres from the centre of the landmark's 22 m square, x east, z south, y up. Rows:
## [0, x0, z0, x1, z1, y0, y1, colour, facade style or -1, accent, turn] a box (turned about y by `turn` radians:
## a side of a windowed round wall);
## [1 or 2, x0, z0, x1, z1, y0, rise, colour] a gable roof with its ridge along x (1) or z (2);
## [3, x, z, scale, kind, base height] a tree, kind an art/outdoor.png frame (1 broadleaf, 3 pine, 4 bush);
## [4, colour, normal x, y, z, then x, y, z per corner] a flat face of a curved or slanted part, wound round its normal.

const MODELS := {
%s
}
''' % "\n".join(lines)
    open(os.path.join(GAME, "landmark_models.gd"), "w", encoding="utf-8", newline="\n").write(src)
    print("packed", len(keys), "models:", ", ".join(keys))


if __name__ == "__main__":
    cmd, keys = sys.argv[1], sys.argv[2:]
    {"jobs": lambda: jobs(keys or WHAT), "fix": lambda: fix(keys[0]), "keep": lambda: keep(keys), "pack": pack}[cmd]()
