"""Render a landmark box model the way Konbini Empire's city camera shows it, and score it against the drawn sprite.

usage: python render.py model.json cell.png [compare.png]

The camera is orthographic at yaw 45 deg, pitch 30 deg, so a world point (x, y, z) in metres (origin = centre of
the landmark's 22 m square, x east, z south, y up) lands on screen at
    sx = 0.7071 * (x - z)            (right)
    sy = 0.3536 * (x + z) - 0.866 * y (down)
in screen metres. The sprite is drawn in that same view: its opaque width spans 29.5 screen metres, and the
square's centre sits at (opaque bbox centre x, lowest opaque row - opaque width / 4).
Faces take the game shader's three tones: tops 1.0, walls turned to the sun 0.9, walls away 0.75, a gable slope
away from the sun 0.85. The curved and slanted shapes (cyl, dome, vault, beam, roof, arch) are cut into flat faces
here, and trace.py packs those same faces into the game, so the game draws exactly what this scores.
"""
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw

SPAN = 29.5
CAM = np.array([0.7071 * 0.866, 0.5, 0.7071 * 0.866])  # toward the camera
TREE = 3.84  # a city tree billboard's size at scale 1, metres
TREE_RGB = (88, 140, 66)
KINDS = ["box", "gable", "cyl", "dome", "vault", "beam", "roof", "arch", "tree"]


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


def newell(q):
    n = np.zeros(3)
    for i in range(len(q)):
        a, b = q[i], q[(i + 1) % len(q)]
        n += [(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])]
    ln = np.linalg.norm(n)
    return n / ln if ln > 1e-9 else n


def face(poly, inside, c):
    """A flat face wound counter-clockwise round its normal, which points away from `inside`."""
    q = np.array(poly, float)
    n = newell(q)
    if np.dot(n, q.mean(0) - np.asarray(inside, float)) < 0:
        q, n = q[::-1].copy(), -n
    return q, n, c


def ring(cx, cz, rx, rz, y, n):
    """n corners round (cx, cz) with flat sides rx and rz out (n 4 is an axis-aligned rectangle)."""
    k = 1 / math.cos(math.pi / n)
    return [(cx + k * rx * math.cos(2 * math.pi * (i + 0.5) / n), y, cz + k * rz * math.sin(2 * math.pi * (i + 0.5) / n)) for i in range(n)]


def bands(eave, ridge, y0, yt, sori, nb):
    """Edges from an eave edge up to a ridge edge (plan points (a, b)), the height rising as u ** (1 + 2 * sori), so a
    temple roof (sori > 0) is steep at the ridge and sweeps out flat at the eaves."""
    out = []
    for i in range(nb + 1):
        u = i / nb
        y = y0 + (yt - y0) * u ** (1 + 2 * sori)
        out.append([(e[0] + (r[0] - e[0]) * u, y, e[1] + (r[1] - e[1]) * u) for e, r in zip(eave, ridge)])
    return out


def faces(p):
    """[(verts Nx3, outward normal, rgb)] of one primitive."""
    out = []
    c = hex_rgb(p["c"]) if "c" in p else None
    if "box" in p:
        x0, z0, x1, z1, y0, y1 = p["box"]
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
        yt = y0 + h
        if p.get("ridge", "z") == "z":
            xm = (x0 + x1) / 2
            a, b = [(x0, y0, z0), (xm, yt, z0), (xm, yt, z1), (x0, y0, z1)], [(x1, y0, z0), (xm, yt, z0), (xm, yt, z1), (x1, y0, z1)]
            ends = [[(x0, y0, z0), (x1, y0, z0), (xm, yt, z0)], [(x0, y0, z1), (x1, y0, z1), (xm, yt, z1)]]
        else:
            zm = (z0 + z1) / 2
            a, b = [(x0, y0, z0), (x0, yt, zm), (x1, yt, zm), (x1, y0, z0)], [(x0, y0, z1), (x0, yt, zm), (x1, yt, zm), (x1, y0, z1)]
            ends = [[(x0, y0, z0), (x0, y0, z1), (x0, yt, zm)], [(x1, y0, z0), (x1, y0, z1), (x1, yt, zm)]]
        centre = ((x0 + x1) / 2, y0 + h / 3, (z0 + z1) / 2)
        out += [face(poly, centre, c) for poly in [a, b] + ends]
    elif "cyl" in p:  # a round or n-sided column, tapering to `top` x its radius (0: a cone or spire)
        cx, cz, rx, rz, y0, y1 = p["cyl"]
        t, n = p.get("top", 1.0), int(p.get("n", 12))
        b, u = ring(cx, cz, rx, rz, y0, n), ring(cx, cz, rx * t, rz * t, y1, n)
        mid = (cx, (y0 + y1) / 2, cz)
        for i in range(n):
            j = (i + 1) % n
            out.append(face([b[i], b[j], u[j], u[i]] if t > 0.01 else [b[i], b[j], (cx, y1, cz)], mid, c))
        if t > 0.01:
            out.append(face(u, (cx, y0, cz), c))
    elif "dome" in p:  # half an ellipsoid of height h on an n-sided base
        cx, cz, rx, rz, y0, h = p["dome"]
        n = int(p.get("n", 12))
        rings = [ring(cx, cz, rx * math.cos(a), rz * math.cos(a), y0 + h * math.sin(a), n) for a in (0, 0.42, 0.82, 1.2)]
        inside = (cx, y0 + 0.01 * h, cz)
        for lo, hi in zip(rings, rings[1:]):
            for i in range(n):
                out.append(face([lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]], inside, c))
        out.append(face(rings[-1], inside, c))
    elif "vault" in p:  # a barrel roof: a half ellipse of height h across the rectangle, running along `axis`
        x0, z0, x1, z1, y0, h = p["vault"]
        along_x = p.get("axis", "x") == "x"
        a0, a1, b0, b1 = (x0, x1, z0, z1) if along_x else (z0, z1, x0, x1)
        P = (lambda a, y, b: (a, y, b)) if along_x else (lambda a, y, b: (b, y, a))
        bc, rb = (b0 + b1) / 2, (b1 - b0) / 2
        m = int(p.get("n", 8))
        arc = [(bc - rb * math.cos(math.pi * i / m), y0 + h * math.sin(math.pi * i / m)) for i in range(m + 1)]
        inside = P((a0 + a1) / 2, y0 + 0.01 * h, bc)
        for (ba, ya), (bb, yb) in zip(arc, arc[1:]):
            out.append(face([P(a0, ya, ba), P(a1, ya, ba), P(a1, yb, bb), P(a0, yb, bb)], inside, c))
        for a in (a0, a1):
            out.append(face([P(a, y, b) for b, y in arc], inside, c))
    elif "beam" in p:  # a square strut w thick from one point to another: lattice legs, braces, spokes, masts
        p0, p1 = np.array(p["beam"][:3], float), np.array(p["beam"][3:], float)
        w = p.get("w", 0.4) / 2
        d = (p1 - p0) / (np.linalg.norm(p1 - p0) or 1)
        up = np.array([1.0, 0, 0]) if abs(d[1]) > 0.9 else np.array([0, 1.0, 0])
        e1 = np.cross(d, up)
        e1 /= np.linalg.norm(e1)
        e2 = np.cross(e1, d)
        sx, sy = [1, 1, -1, -1], [-1, 1, 1, -1]
        corner = lambda o, i: o + w * (e1 * sx[i] + e2 * sy[i])
        mid = (p0 + p1) / 2
        for i in range(4):
            j = (i + 1) % 4
            out.append(face([corner(p0, i), corner(p0, j), corner(p1, j), corner(p1, i)], mid, c))
        for o in (p0, p1):
            out.append(face([corner(o, i) for i in range(4)], mid, c))
    elif "roof" in p:  # a hipped roof (hip 0 is a gable), its slopes swept into a temple curve by sori 0-1
        x0, z0, x1, z1, y0, h = p["roof"]
        along_x = p.get("ridge", "x") == "x"
        a0, a1, b0, b1 = (x0, x1, z0, z1) if along_x else (z0, z1, x0, x1)
        P = (lambda a, y, b: (a, y, b)) if along_x else (lambda a, y, b: (b, y, a))
        bc = (b0 + b1) / 2
        d = max(0.0, min(p.get("hip", 1.0) * (b1 - b0) / 2, (a1 - a0) / 2 - 0.01))
        sori = p.get("sori", 0.0)
        nb = 3 if sori > 0 else 1
        inside = P((a0 + a1) / 2, y0 + 0.01, bc)
        r0, r1 = a0 + d, a1 - d
        slopes = [([(a0, b1), (a1, b1)], [(r0, bc), (r1, bc)]), ([(a1, b0), (a0, b0)], [(r1, bc), (r0, bc)])]
        if d > 0.05:
            slopes += [([(a0, b0), (a0, b1)], [(r0, bc), (r0, bc)]), ([(a1, b1), (a1, b0)], [(r1, bc), (r1, bc)])]
        for eave, ridge in slopes:
            edges = bands(eave, ridge, y0, y0 + h, sori, nb)
            for lo, hi in zip(edges, edges[1:]):
                poly = [P(*lo[0]), P(*lo[1]), P(*hi[1]), P(*hi[0])]
                if np.linalg.norm(np.subtract(poly[2], poly[3])) < 1e-6:
                    poly = poly[:3]
                out.append(face(poly, inside, c))
        if d <= 0.05:  # gable ends, fanned from the middle of the eave line up under the swept profile
            prof = [(b0 + (bc - b0) * u, y0 + h * u ** (1 + 2 * sori)) for u in np.linspace(0, 1, nb + 1)]
            prof += [(b1 - (b1 - bc) * u, y0 + h * u ** (1 + 2 * sori)) for u in np.linspace(1, 0, nb + 1)][1:]
            for a in (a0, a1):
                for (ba, ya), (bb, yb) in zip(prof, prof[1:]):
                    out.append(face([P(a, y0, bc), P(a, ya, ba), P(a, yb, bb)], inside, c))
    elif "arch" in p:  # a wall with n round-topped openings through it along `axis` (bridges, gates, arcade fronts)
        x0, z0, x1, z1, y0, y1 = p["arch"]
        thru_z = p.get("axis", "z") == "z"
        a0, a1, b0, b1 = (x0, x1, z0, z1) if thru_z else (z0, z1, x0, x1)
        P = (lambda a, y, b: (a, y, b)) if thru_z else (lambda a, y, b: (b, y, a))
        n, r = int(p.get("n", 1)), p["r"]
        ys = y0 + p.get("spring", 0.0)
        bm = (b0 + b1) / 2
        centres = [a0 + (k + 0.5) * (a1 - a0) / n for k in range(n)]
        m = 8
        arcs = [[(ac + r * math.cos(math.pi * (1 - i / m)), ys + r * math.sin(math.pi * (1 - i / m))) for i in range(m + 1)] for ac in centres]
        out.append(face([P(a0, y1, b0), P(a1, y1, b0), P(a1, y1, b1), P(a0, y1, b1)], P((a0 + a1) / 2, y0, bm), c))
        for a in (a0, a1):
            out.append(face([P(a, y0, b0), P(a, y1, b0), P(a, y1, b1), P(a, y0, b1)], P((a0 + a1) / 2, (y0 + y1) / 2, bm), c))
        edges = [a0] + [e for ac in centres for e in (ac - r, ac + r)] + [a1]
        for b in (b0, b1):
            for k in range(0, len(edges), 2):  # piers
                if edges[k + 1] - edges[k] > 1e-6:
                    out.append(face([P(edges[k], y0, b), P(edges[k + 1], y0, b), P(edges[k + 1], y1, b), P(edges[k], y1, b)], P(edges[k], y0, bm), c))
            for arc in arcs:  # spandrels over each opening
                for (aa, ya), (ab, yb) in zip(arc, arc[1:]):
                    out.append(face([P(aa, ya, b), P(ab, yb, b), P(ab, y1, b), P(aa, y1, b)], P(aa, ya, bm), c))
        for ac, arc in zip(centres, arcs):
            for (aa, ya), (ab, yb) in zip(arc, arc[1:]):
                th = math.atan2((ya + yb) / 2 - ys, (aa + ab) / 2 - ac)
                out.append(face([P(aa, ya, b0), P(ab, yb, b0), P(ab, yb, b1), P(aa, ya, b1)], P(ac + 1.2 * r * math.cos(th), ys + 1.2 * r * math.sin(th), bm), c))
            if ys > y0:
                out.append(face([P(ac - r, y0, b0), P(ac - r, ys, b0), P(ac - r, ys, b1), P(ac - r, y0, b1)], P(ac - r - 0.1, y0, bm), c))
                out.append(face([P(ac + r, y0, b0), P(ac + r, ys, b0), P(ac + r, ys, b1), P(ac + r, y0, b1)], P(ac + r + 0.1, y0, bm), c))
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
            bx0, by0 = max(int(pts[:, 0].min()), 0), max(int(pts[:, 1].min()), 0)
            bx1, by1 = min(int(pts[:, 0].max()) + 2, w), min(int(pts[:, 1].max()) + 2, h)
            if bx1 <= bx0 or by1 <= by0:
                continue
            m = Image.new("L", (bx1 - bx0, by1 - by0), 0)
            ImageDraw.Draw(m).polygon([(t[0] - bx0, t[1] - by0) for t in pts], fill=255)
            mask = np.array(m) > 0
            if not mask.any():
                continue
            d = q @ CAM
            A = np.c_[pts, np.ones(len(pts))]
            coef = np.linalg.lstsq(A, d, rcond=None)[0]
            depth = coef[0] * xs[by0:by1, bx0:bx1] + coef[1] * ys[by0:by1, bx0:bx1] + coef[2]
            zs = zb[by0:by1, bx0:bx1]
            win = mask & (depth > zs)
            zs[win] = depth[win]
            img[by0:by1, bx0:bx1][win] = c * shade(n)
            cov[by0:by1, bx0:bx1] |= mask
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
                      **{{"box": "boxes", "arch": "arches"}.get(k, k + "s"): sum(k in p for p in prims) for k in KINDS if any(k in p for p in prims)}}))
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
