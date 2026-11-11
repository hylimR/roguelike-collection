extends RefCounted
## Vertex-coloured mesh parts in the house's tones, for the props the game builds in code: tops full, walls turned to
## the sun 0.9, walls away 0.75, undersides 0.7, as BUILDING_SHADER and store_view's boxes shade theirs. Build into a
## SurfaceTool begun with PRIMITIVE_TRIANGLES; give the mesh an unshaded material with vertex_color_use_as_albedo,
## vertex_color_is_srgb and cull disabled (store_view's mat()). Metres: x east, y up, z south. A face is toned by its
## normal pointing away from `inside`, a point within its solid, when given; else its corners must run
## counter-clockwise seen from outside.

const NOWHERE := Vector3(INF, INF, INF)


## The tone of a face with normal n. `soft` blends the walls' two tones round the sun instead of splitting them,
## for round things (crowns, drums).
static func tone(n: Vector3, soft := false) -> float:
	var f := n.z - n.x
	var side := (lerpf(0.75, 0.9, clampf(0.5 + f * 0.6, 0.0, 1.0)) if soft else (0.9 if f > 0.0 else 0.75))
	return lerpf(side, 1.0, n.y) if n.y > 0.0 else lerpf(side, 0.7, -n.y)


static func colored(c: Color, t: float) -> Color:
	return Color(c.r * t, c.g * t, c.b * t, c.a)


## The outward normal of the face through a, b, c (and d).
static func outward(n: Vector3, mid: Vector3, inside: Vector3) -> Vector3:
	if inside != NOWHERE and n.dot(mid - inside) < 0.0:
		n = -n
	return n.normalized()


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, soft := false, inside := NOWHERE) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	st.set_color(colored(col, tone(outward(n, (a + b + c) / 3.0, inside), soft)))
	for p in [a, b, c]:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(p)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, soft := false, inside := NOWHERE) -> void:
	var n := (b - a).cross(c - a) + (c - a).cross(d - a)
	if n.length_squared() < 1e-12:
		return
	st.set_color(colored(col, tone(outward(n, (a + b + c + d) / 4.0, inside), soft)))
	for p in [a, b, c, a, c, d]:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(p)


## A unit box (corners at ±0.5) under xf, each face toned by where it ends up facing.
static func turned_box(st: SurfaceTool, xf: Transform3D, col: Color, bottom := false) -> void:
	var c := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1),
		Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)].map(func(v): return xf * (v * 0.5))
	var o := xf.origin
	quad(st, c[4], c[5], c[6], c[7], col, false, o)  # top
	quad(st, c[3], c[2], c[6], c[7], col, false, o)  # +z
	quad(st, c[0], c[1], c[5], c[4], col, false, o)  # -z
	quad(st, c[1], c[2], c[6], c[5], col, false, o)  # +x
	quad(st, c[0], c[3], c[7], c[4], col, false, o)  # -x
	if bottom:
		quad(st, c[0], c[1], c[2], c[3], col, false, o)


## A faceted lump (an icosahedron) at c with radii r, its corners pushed in or out by up to `jitter` of r with seed,
## for crowns of leaves, shrubs and rocks. Bands its faces' tones: the house's sides, softened round the sun.
static func lump(st: SurfaceTool, c: Vector3, r: Vector3, col: Color, jitter := 0.12, seed := 0) -> void:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in v.size():
		v[i] = c + v[i].normalized() * r * (1.0 + rng.randf_range(-jitter, jitter))
	for f in [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
			[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]:
		tri(st, v[f[0]], v[f[1]], v[f[2]], col, true, c)
