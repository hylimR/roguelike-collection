"""Trace city landmarks from their drawings into box models, and pack the models into landmark_models.gd.

    python tools/trace/trace.py jobs [key ...]   cut each drawing into build/trace/<key>/ with render.py and a prompt
    sh tools/trace/run.sh key [key ...]          let Codex fit build/trace/<key>/model.json, 5 at a time
    python tools/trace/trace.py fix notes.json   a job per key in notes.json ({key: review notes}) that starts from the
                                                 kept model and fixes only what the notes say (then run.sh again)
    python tools/trace/trace.py keep [key ...]   copy the fitted models into tools/trace/models/
    python tools/trace/trace.py pack             write landmark_models.gd from tools/trace/models/

Keys are sheet_frame (landmarks_0, tokyo_8). render.py scores a model against its drawing in the city camera's own
projection; the Codex prompt (prompt.txt) loops on it. Packing turns the green blocks a trace draws for tree crowns
into the game's tree sprites, standing on what is under them. Tokyo Tower, the Skytree and the Odaiba wheel are
lattices and a wheel, so they stay drawings.
"""
import colorsys
import glob
import json
import math
import os
import shutil
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, "..", ".."))
JOBS = os.path.join(GAME, "build", "trace")
MODELS = os.path.join(HERE, "models")
WHAT = {
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
        open(os.path.join(d, "prompt.txt"), "w", encoding="utf-8").write(prompt.replace("{WHAT}", WHAT[key]))
        print(key, "->", d)


def fix(path):
    notes = json.load(open(path, encoding="utf-8"))
    jobs(notes)
    for key, text in notes.items():
        d = os.path.join(JOBS, key)
        shutil.copy(os.path.join(MODELS, key + ".json"), os.path.join(d, "model.json"))
        with open(os.path.join(d, "prompt.txt"), "a", encoding="utf-8") as f:
            f.write("\nTHIS RUN\nmodel.json already holds a finished trace. A review of it in the game found the defects below. "
                    "Fix exactly these and keep everything else as it is; check with render.py that iou stays >= 0.85 "
                    "(at most 8 runs), then reply with one line of scores.\n" + text + "\n")


def keep(keys):
    for key in keys:
        shutil.copy(os.path.join(JOBS, key, "model.json"), os.path.join(MODELS, key + ".json"))
        print(key, "kept")


def hsv(c):
    r, g, b = [int(c.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return colorsys.rgb_to_hsv(r, g, b)


def treeify(prims, pines):
    """Green boxes held up off the ground are tree crowns the trace drew as blocks: they become the game's tree
    sprites (one per ~3.6 m of crown, sized by the crown's height), standing on whatever is under them (a bank, a
    plinth); the thin trunks under them go, and trees closer than 2.2 m merge."""
    crowns = [p for p in prims if "box" in p and p["box"][4] >= 0.8 and 0.2 < hsv(p["c"])[0] < 0.45 and hsv(p["c"])[1] > 0.25]
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
        x0, z0, x1, z1, y0, y1 = p["box"]
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
    under = lambda q: any(c["box"][0] - 0.5 <= (q["box"][0] + q["box"][2]) / 2 <= c["box"][2] + 0.5 and c["box"][1] - 0.5 <= (q["box"][1] + q["box"][3]) / 2 <= c["box"][3] + 0.5 for c in crowns)
    trunk = lambda q: "box" in q and q["box"][2] - q["box"][0] <= 1.0 and q["box"][3] - q["box"][1] <= 1.0 and q["box"][5] - q["box"][4] > 0.8 and under(q)
    kept = [p for p in prims if p not in crowns and "tree" not in p and not trunk(p)]
    return kept + [{"tree": t[:3], "kind": t[3], "y": round(t[4], 2)} for t in merged[:40]]


def num(v):
    return ("%.2f" % v).rstrip("0").rstrip(".") if isinstance(v, float) else str(v)


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
        rows = [row(p) for p in treeify(m["prims"], key in PINES)]
        body = ",\n\t\t".join("[" + ", ".join('"%s"' % v if isinstance(v, str) else num(v) for v in r) + "]" for r in rows)
        lines.append('\t"%s:%s": [  # %s\n\t\t%s,\n\t],' % (sheet, frame, m.get("name", key), body))
    src = '''## Landmarks rebuilt as boxes, traced from their drawings in art/landmarks.png and art/tokyo.png by
## tools/trace/trace.py (the models are in tools/trace/models/); regenerate rather than edit. Keyed "sheet:frame";
## metres from the centre of the landmark's 22 m square, x east, z south, y up. Rows:
## [0, x0, z0, x1, z1, y0, y1, colour, facade style or -1, accent] a box;
## [1 or 2, x0, z0, x1, z1, y0, rise, colour] a gable roof with its ridge along x (1) or z (2);
## [3, x, z, scale, kind, base height] a tree, kind an art/outdoor.png frame (1 broadleaf, 3 pine, 4 bush).

const MODELS := {
%s
}
''' % "\n".join(lines)
    open(os.path.join(GAME, "landmark_models.gd"), "w", encoding="utf-8", newline="\n").write(src)
    print("packed", len(keys), "models:", ", ".join(keys))


if __name__ == "__main__":
    cmd, keys = sys.argv[1], sys.argv[2:]
    {"jobs": lambda: jobs(keys or WHAT), "fix": lambda: fix(keys[0]), "keep": lambda: keep(keys), "pack": pack}[cmd]()
