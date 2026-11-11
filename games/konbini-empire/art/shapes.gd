extends RefCounted
## Vertex-coloured mesh parts in the house's tones, for the props the game builds in code: tops full, walls turned to
## the sun 0.9, walls away 0.75, undersides 0.7, as BUILDING_SHADER and store_view's boxes shade theirs. Build into a
## SurfaceTool begun with PRIMITIVE_TRIANGLES; give the mesh an unshaded material with vertex_color_use_as_albedo,
## vertex_color_is_srgb and cull disabled (store_view's mat()). Metres: x east, y up, z south.


## The tone of a face with normal n. `soft` blends the walls' two tones round the sun instead of splitting them,
## for round things (crowns, drums).
static func tone(n: Vector3, soft := false) -> float:
	var f := n.z - n.x
	var side := (lerpf(0.75, 0.9, clampf(0.5 + f * 0.6, 0.0, 1.0)) if soft else (0.9 if f > 0.0 else 0.75))
	return lerpf(side, 1.0, n.y) if n.y > 0.0 else lerpf(side, 0.7, -n.y)


static func colored(c: Color, t: float) -> Color:
	return Color(c.r * t, c.g * t, c.b * t, c.a)


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, soft := false) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	st.set_color(colored(col, tone(n.normalized(), soft)))
	for p in [a, b, c]:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(p)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, soft := false) -> void:
	var n := (b - a).cross(c - a) + (c - a).cross(d - a)
	if n.length_squared() < 1e-12:
		return
	st.set_color(colored(col, tone(n.normalized(), soft)))
	for p in [a, b, c, a, c, d]:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(p)


## An axis-aligned box between corners a and b; `bottom` adds its underside.
static func box(st: SurfaceTool, a: Vector3, b: Vector3, col: Color, bottom := false) -> void:
	turned_box(st, Transform3D(Basis.from_scale((b - a).abs()), (a + b) / 2), col, bottom)


## A unit box (corners at ±0.5) under xf, each face toned by where it ends up facing.
static func turned_box(st: SurfaceTool, xf: Transform3D, col: Color, bottom := false) -> void:
	var c := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1),
		Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1)].map(func(v): return xf * (v * 0.5))
	quad(st, c[4], c[5], c[6], c[7], col)  # top
	quad(st, c[3], c[2], c[6], c[7], col)  # +z
	quad(st, c[0], c[1], c[5], c[4], col)  # -z
	quad(st, c[1], c[2], c[6], c[5], col)  # +x
	quad(st, c[0], c[3], c[7], c[4], col)  # -x
	if bottom:
		quad(st, c[0], c[1], c[2], c[3], col)


## A drum, cone or frustum about a vertical axis at c: radius r0 at height y0 to r1 at y1, `sides` faces, capped
## top and bottom where its radius is open. `turn` rotates its faces about the axis.
static func drum(st: SurfaceTool, c: Vector3, r0: float, r1: float, y0: float, y1: float, sides: int, col: Color, turn := 0.0, soft := true) -> void:
	for i in sides:
		var a0 := turn + TAU * i / sides
		var a1 := turn + TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var p00 := c + d0 * r0 + Vector3(0, y0, 0)
		var p10 := c + d1 * r0 + Vector3(0, y0, 0)
		var p01 := c + d0 * r1 + Vector3(0, y1, 0)
		var p11 := c + d1 * r1 + Vector3(0, y1, 0)
		if r1 <= 0.0:
			tri(st, p00, p10, p01, col, soft)
		elif r0 <= 0.0:
			tri(st, p00, p11, p01, col, soft)
		else:
			quad(st, p00, p10, p11, p01, col, soft)
		if r1 > 0.0:
			tri(st, c + Vector3(0, y1, 0), p01, p11, col, soft)
		if r0 > 0.0:
			tri(st, c + Vector3(0, y0, 0), p10, p00, col, soft)


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
		tri(st, v[f[0]], v[f[1]], v[f[2]], col, true)
