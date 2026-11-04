"""Render a landmark box model the way Konbini Empire's city camera shows it, and score it against the drawn sprite.

usage: python render.py model.json cell.png [compare.png]

The camera is orthographic at yaw 45 deg, pitch 30 deg, so a world point (x, y, z) in metres (origin = centre of
the landmark's 22 m square, x east, z south, y up) lands on screen at
    sx = 0.7071 * (x - z)            (right)
    sy = 0.3536 * (x + z) - 0.866 * y (down)
in screen metres. The sprite is drawn in that same view: its opaque width spans 29.5 screen metres, and the
square's centre sits at (opaque bbox centre x, lowest opaque row - opaque width / 4).
Faces take the game shader's three tones: tops 1.0, walls turned to the sun 0.9, walls away 0.75, a gable slope
away from the sun 0.85.
"""
import json
import sys

import numpy as np
from PIL import Image, ImageDraw

SPAN = 29.5
CAM = np.array([0.7071 * 0.866, 0.5, 0.7071 * 0.866])  # toward the camera
TREE = 3.84  # a city tree billboard's size at scale 1, metres
TREE_RGB = (88, 140, 66)


def shade(n):
    sun = -0.35 * n[0] + 0.6 * n[2]
    if n[1] > 0.95:
        return 1.0
    if n[1] > 0.5:
        return 1.0 if sun >= 0 else 0.85
    return 0.9 if sun > 0 else 0.75


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], float)


def faces(p):
    """[(verts Nx3, outward normal, rgb)] of one primitive."""
    out = []
    if "box" in p:
        x0, z0, x1, z1, y0, y1 = p["box"]
        c = hex_rgb(p["c"])
        v = lambda x, y, z: (x, y, z)
        quads = [
            ([v(x0, y1, z0), v(x1, y1, z0), v(x1, y1, z1), v(x0, y1, z1)], (0, 1, 0)),
            ([v(x1, y0, z0), v(x1, y1, z0), v(x1, y1, z1), v(x1, y0, z1)], (1, 0, 0)),
            ([v(x0, y0, z1), v(x1, y0, z1), v(x1, y1, z1), v(x0, y1, z1)], (0, 0, 1)),
            ([v(x0, y0, z0), v(x0, y1, z0), v(x0, y1, z1), v(x0, y0, z1)], (-1, 0, 0)),
            ([v(x0, y0, z0), v(x1, y0, z0), v(x1, y1, z0), v(x0, y1, z0)], (0, 0, -1)),
        ]
        for q, n in quads:
            out.append((np.array(q, float), np.array(n, float), c))
    elif "gable" in p:
        x0, z0, x1, z1, y0, h = p["gable"]
        c = hex_rgb(p["c"])
        yt = y0 + h
        if p.get("ridge", "z") == "z":
            xm = (x0 + x1) / 2
            a, b = [(x0, y0, z0), (xm, yt, z0), (xm, yt, z1), (x0, y0, z1)], [(x1, y0, z0), (xm, yt, z0), (xm, yt, z1), (x1, y0, z1)]
            ends = [[(x0, y0, z0), (x1, y0, z0), (xm, yt, z0)], [(x0, y0, z1), (x1, y0, z1), (xm, yt, z1)]]
        else:
            zm = (z0 + z1) / 2
            a, b = [(x0, y0, z0), (x0, yt, zm), (x1, yt, zm), (x1, y0, z0)], [(x0, y0, z1), (x0, yt, zm), (x1, yt, zm), (x1, y0, z1)]
            ends = [[(x0, y0, z0), (x0, y0, z1), (x0, yt, zm)], [(x1, y0, z0), (x1, y0, z1), (x1, yt, zm)]]
        centre = np.array([(x0 + x1) / 2, y0 + h / 3, (z0 + z1) / 2])
        for poly in [a, b] + ends:
            q = np.array(poly, float)
            n = np.cross(q[1] - q[0], q[2] - q[0])
            n /= np.linalg.norm(n) or 1
            if np.dot(n, q.mean(0) - centre) < 0:
                n = -n
            out.append((q, n, c))
    return out


def project(q, fc, ppm):
    sx = 0.7071 * (q[:, 0] - q[:, 2])
    sy = 0.3536 * (q[:, 0] + q[:, 2]) - 0.866 * q[:, 1]
    return np.stack([fc[0] + sx * ppm, fc[1] + sy * ppm], 1)


def render(model, size, fc, ppm):
    w, h = size
    img = np.zeros((h, w, 3), float)
    cov = np.zeros((h, w), bool)
    zb = np.full((h, w), -1e9)
    ys, xs = np.mgrid[0:h, 0:w]
    for p in model["prims"]:
        for q, n, c in faces(p):
            if np.dot(n, CAM) <= 1e-6:
                continue
            pts = project(q, fc, ppm)
            m = Image.new("L", (w, h), 0)
            ImageDraw.Draw(m).polygon([tuple(t) for t in pts], fill=255)
            mask = np.array(m) > 0
            if not mask.any():
                continue
            d = q @ CAM
            A = np.c_[pts, np.ones(len(pts))]
            coef = np.linalg.lstsq(A, d, rcond=None)[0]
            depth = coef[0] * xs + coef[1] * ys + coef[2]
            win = mask & (depth > zb)
            zb[win] = depth[win]
            img[win] = c * shade(n)
            cov |= mask
        if "tree" in p:
            x, z, s = p["tree"]
            r = TREE * s * 0.45 * ppm
            foot = project(np.array([[x, 0, z]], float), fc, ppm)[0]
            cx, cy = foot[0], foot[1] - TREE * s * 0.55 * ppm
            mask = (xs - cx) ** 2 + (ys - cy) ** 2 <= r * r
            d = np.dot([x, 0, z], CAM) + 0.5
            win = mask & (d > zb)
            zb[win] = d
            img[win] = TREE_RGB
            cov |= mask
    return img, cov


def main():
    model = json.load(open(sys.argv[1], encoding="utf-8"))
    cell = Image.open(sys.argv[2]).convert("RGBA")
    a = np.array(cell)
    S = a[:, :, 3] > 128
    ys, xs = np.nonzero(a[:, :, 3] > 0)  # the game's used rect counts every pixel with any alpha
    bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    uw = bx1 - bx0
    ppm = uw / SPAN
    fc = ((bx0 + bx1) / 2, by1 - uw / 4)
    img, R = render(model, cell.size, fc, ppm)
    inter, union = (S & R).sum(), (S | R).sum()
    iou = inter / max(union, 1)
    srgb = a[:, :, :3].astype(float)
    err = np.abs(srgb - img)[S & R].mean() if inter else 255.0
    # colour by 6 px blocks (where drawing and model both cover most of the block), each block's median, so the
    # drawing's outlines and pixel texture don't count, only whether the right material stands in the right place
    B = 6
    blk = []
    berr = np.zeros(S.shape)
    for y in range(by0, by1 - B + 1, B):
        for x in range(bx0, bx1 - B + 1, B):
            both = (S & R)[y:y + B, x:x + B]
            if both.mean() > 0.5:
                e = np.abs(np.median(srgb[y:y + B, x:x + B][both], 0) - np.median(img[y:y + B, x:x + B][both], 0)).mean()
                blk.append(e)
                berr[y:y + B, x:x + B] = e
    block_err = float(np.mean(blk)) if blk else 255.0
    # a 6 x 6 grid over the sprite's box: % of each cell's sprite pixels missing (M), % extra render pixels (E),
    # and the mean block colour error there (C)
    grid = []
    gx = np.linspace(bx0, bx1, 7).astype(int)
    gy = np.linspace(by0, by1, 7).astype(int)
    for j in range(6):
        row = []
        for i in range(6):
            s = S[gy[j]:gy[j + 1], gx[i]:gx[i + 1]]
            r = R[gy[j]:gy[j + 1], gx[i]:gx[i + 1]]
            n = s.size
            bc = berr[gy[j]:gy[j + 1], gx[i]:gx[i + 1]]
            c = bc[bc > 0].mean() if (bc > 0).any() else 0
            row.append("M%02d E%02d C%02d" % (round(100 * (s & ~r).sum() / n), round(100 * (r & ~s).sum() / n), min(99, round(c))))
        grid.append(" | ".join(row))
    prims = model["prims"]
    print(json.dumps({"iou": round(float(iou), 3), "block_err": round(block_err, 1), "rgb_err": round(float(err), 1),
                      "boxes": sum("box" in p for p in prims), "gables": sum("gable" in p for p in prims),
                      "trees": sum("tree" in p for p in prims)}))
    print("grid rows top to bottom, columns left to right (M = % of the drawing the model misses, E = % of the model outside the drawing, C = block colour error 0-99):")
    for g in grid:
        print("  " + g)
    if len(sys.argv) > 3:
        ren = np.zeros((*S.shape, 4), np.uint8)
        ren[R, :3] = img[R].clip(0, 255)
        ren[R, 3] = 255
        ov = np.zeros((*S.shape, 4), np.uint8)
        ov[S & R] = (150, 150, 150, 255)
        ov[S & ~R] = (230, 40, 40, 255)
        ov[R & ~S] = (40, 90, 230, 255)
        crop = (max(bx0 - 8, 0), max(by0 - 8, 0), min(bx1 + 8, cell.size[0]), min(by1 + 8, cell.size[1]))
        parts = [cell.crop(crop), Image.fromarray(ren).crop(crop), Image.fromarray(ov).crop(crop)]
        cw, ch = parts[0].size
        sheet = Image.new("RGBA", (cw * 3 + 16, ch), (255, 255, 255, 255))
        for k, im in enumerate(parts):
            sheet.alpha_composite(im, (k * (cw + 8), 0))
        sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
        sheet.save(sys.argv[3])


if __name__ == "__main__":
    main()
