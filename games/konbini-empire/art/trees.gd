extends RefCounted
## Trees, bushes and street furniture built in code in the house's tones (art/shapes.gd): a broadleaf's crown of
## faceted lumps over its trunk, the red maple and the pink cherry the same way, a cedar of stacked shaggy cones, a
## round bush, and the street's post box, bicycle, flower planter and bus stop. Metres, standing on the origin, fronts
## (a post box's slot, a sign's face) to +z and a bicycle's front wheel to +x. A tree comes in three forms: FULL for
## the street and the city up close, its leaves in their own surface named "leaves" with a texture's UVs (leaf_texture,
## LEAF_TILE metres a tile, laid flat on each face); SIMPLE, a crown of one lump in plain colours, for the city further
## out; TINY, a crown of a few faces, for the city seen whole.

const Shapes := preload("res://art/shapes.gd")

const MAPLE := 0
const BROADLEAF := 1
const CHERRY := 2
const PINE := 3
const BUSH := 4
const POST_BOX := 5
const BICYCLE := 6
const PLANTER := 7
const BUS_STOP := 8
const TINY := 0
const SIMPLE := 1
const FULL := 2
const LEAF_TILE := 0.9

## Each tree as limbs ([from, to, radius at foot, radius at tip]; the first is its trunk) in its bark's colour, and
## a crown of lumps ([centre, radii, shade]) in shades of its leaves, darkest first. The cedar stacks shaggy cones
## instead ([foot, tip, radius, shade]). The simpler forms keep the trunk and take the crown `far`, one lump (two plain
## cones for the cedar), drawn in a few faces when tiny.
const TREES := {
	BROADLEAF: {"bark": "6e4a2f", "leaf": ["3b8430", "4b9a36", "5bac3d", "6ebd48"],
		"limbs": [[Vector3(0, -0.1, 0), Vector3(0.04, 1.75, 0), 0.24, 0.13]],
		"lumps": [[Vector3(0, 2.45, 0), Vector3(1.2, 0.98, 1.2), 1], [Vector3(0.72, 2.15, -0.5), Vector3(0.8, 0.7, 0.8), 0],
			[Vector3(-0.72, 2.3, -0.38), Vector3(0.84, 0.72, 0.84), 1], [Vector3(0.42, 2.0, 0.66), Vector3(0.76, 0.64, 0.76), 1],
			[Vector3(-0.58, 2.02, 0.52), Vector3(0.7, 0.6, 0.7), 0], [Vector3(0.08, 3.12, -0.06), Vector3(0.86, 0.68, 0.86), 2],
			[Vector3(-0.3, 3.3, 0.26), Vector3(0.66, 0.52, 0.66), 3]],
		"far": [Vector3(0, 2.55, 0), Vector3(1.45, 1.25, 1.45), 1]},
	MAPLE: {"bark": "694531", "leaf": ["c8392a", "e04a2c", "ec602e", "f47f33"],
		"limbs": [[Vector3(0, -0.1, 0), Vector3(-0.03, 1.6, 0), 0.23, 0.12]],
		"lumps": [[Vector3(0, 2.35, 0), Vector3(1.3, 0.9, 1.3), 1], [Vector3(0.8, 2.05, -0.4), Vector3(0.82, 0.66, 0.82), 0],
			[Vector3(-0.8, 2.2, -0.3), Vector3(0.86, 0.68, 0.86), 1], [Vector3(0.36, 1.95, 0.72), Vector3(0.78, 0.6, 0.78), 0],
			[Vector3(-0.62, 1.98, 0.6), Vector3(0.72, 0.58, 0.72), 1], [Vector3(0.12, 3.0, 0.0), Vector3(0.92, 0.66, 0.92), 2],
			[Vector3(-0.36, 3.2, 0.3), Vector3(0.66, 0.48, 0.66), 3], [Vector3(0.55, 2.7, 0.45), Vector3(0.6, 0.46, 0.6), 2]],
		"far": [Vector3(0, 2.45, 0), Vector3(1.5, 1.18, 1.5), 1]},
	CHERRY: {"bark": "5a3f37", "leaf": ["ec8fb2", "f5a5c3", "fab9d0", "fdcde0"],
		"limbs": [[Vector3(0, -0.1, 0), Vector3(0.08, 1.15, 0.02), 0.24, 0.15], [Vector3(0.08, 1.1, 0.02), Vector3(0.95, 2.0, -0.25), 0.12, 0.06],
			[Vector3(0.08, 1.1, 0.02), Vector3(-0.85, 2.05, 0.2), 0.12, 0.06], [Vector3(0.06, 1.1, 0.0), Vector3(-0.1, 2.2, -0.75), 0.1, 0.05]],
		"lumps": [[Vector3(0, 2.4, 0), Vector3(1.25, 0.78, 1.25), 1], [Vector3(1.05, 2.2, -0.3), Vector3(0.85, 0.6, 0.85), 0],
			[Vector3(-1.0, 2.28, 0.22), Vector3(0.88, 0.62, 0.88), 1], [Vector3(0.3, 2.12, 0.92), Vector3(0.8, 0.58, 0.8), 0],
			[Vector3(-0.3, 2.2, -0.95), Vector3(0.82, 0.58, 0.82), 1], [Vector3(0.1, 2.95, 0.05), Vector3(0.95, 0.6, 0.95), 2],
			[Vector3(-0.42, 3.1, 0.32), Vector3(0.66, 0.44, 0.66), 3], [Vector3(0.66, 2.75, 0.48), Vector3(0.58, 0.42, 0.58), 2]],
		"far": [Vector3(0, 2.5, 0), Vector3(1.75, 1.0, 1.75), 1]},
	PINE: {"bark": "6b4a2e", "leaf": ["275f3b", "2f6e44", "387d4d", "468d58"],
		"limbs": [[Vector3(0, -0.1, 0), Vector3(0, 1.1, 0), 0.16, 0.11]],
		"tiers": [[0.75, 2.35, 1.2, 0], [1.45, 2.95, 0.98, 1], [2.15, 3.5, 0.74, 2], [2.8, 3.95, 0.5, 3]],
		"far": [[0.7, 2.7, 1.18, 1], [1.95, 3.95, 0.8, 2]]},
	BUSH: {"bark": "", "leaf": ["468d35", "549d3c", "62ac44", "73bb50"],
		"limbs": [],
		"lumps": [[Vector3(0, 0.5, 0), Vector3(0.56, 0.46, 0.56), 1], [Vector3(0.36, 0.36, -0.2), Vector3(0.38, 0.33, 0.38), 0],
			[Vector3(-0.32, 0.38, 0.22), Vector3(0.4, 0.34, 0.4), 1], [Vector3(-0.06, 0.78, 0.04), Vector3(0.36, 0.28, 0.36), 2]],
		"far": [Vector3(0, 0.48, 0), Vector3(0.66, 0.52, 0.66), 1]},
}

static var meshes := {}
static var leaves_tex: ImageTexture


## A kind's model in a tree's form `detail`, cached. `variant` reseeds a tree's lumps, so neighbours on the street
## differ.
static func mesh(kind: int, detail := FULL, variant := 0) -> ArrayMesh:
	var key := "%d:%d:%d" % [kind, detail, variant]
	if not meshes.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var leaves: SurfaceTool = null
		if detail == FULL and TREES.has(kind):
			leaves = SurfaceTool.new()
			leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
		build(st, kind, Transform3D.IDENTITY, detail, variant, leaves)
		var m := ArrayMesh.new()
		st.commit(m)
		if leaves:
			leaves.commit(m)
			m.surface_set_name(m.get_surface_count() - 1, "leaves")
		meshes[key] = m
	return meshes[key]


## Builds a kind into st under xf (turned, scaled and placed), toned by where each face ends up facing; a tree's
## leaves go into `leaves` with their texture's UVs when given.
static func build(st: SurfaceTool, kind: int, xf: Transform3D, detail := FULL, variant := 0, leaves: SurfaceTool = null) -> void:
	match kind:
		POST_BOX:
			post_box(st, xf)
		BICYCLE:
			bicycle(st, xf, variant)
		PLANTER:
			planter(st, xf, variant)
		BUS_STOP:
			bus_stop(st, xf)
		_:
			tree(st, kind, xf, detail, variant, leaves)


## How tall a tree stands.
static func height(kind: int) -> float:
	var t: Dictionary = TREES[kind]
	if t.has("tiers"):
		return t.tiers[-1][1]
	return t.lumps.reduce(func(m, l): return maxf(m, l[0].y + l[1].y), 0.0)


## A kind's shadows on the street, from its model's size: the radius of its soft contact shadow, then what it casts
## from the sun as [from height, to height, width], soft all round when marked (a crown).
static func shadows(kind: int) -> Array:
	match kind:
		POST_BOX:
			return [0.36, [0.0, 1.36, 0.46]]
		BICYCLE:
			return [0.6, [0.0, 1.05, 1.1]]
		PLANTER:
			return [0.6, [0.0, 0.62, 0.9]]
		BUS_STOP:
			return [0.32, [0.0, 0.14, 0.5], [0.14, 1.9, 0.08], [1.9, 2.36, 0.5]]
	var t: Dictionary = TREES[kind]
	var wide := 0.0
	var low := INF
	for l in t.get("lumps", []):
		wide = maxf(wide, Vector2(l[0].x, l[0].z).length() + l[1].x)
		low = minf(low, l[0].y - l[1].y * 0.6)
	for tr in t.get("tiers", []):
		wide = maxf(wide, tr[2])
		low = minf(low, tr[0])
	if t.limbs.is_empty():  # a bush sits on the ground
		return [wide * 1.05, [0.0, height(kind), wide * 1.8, true]]
	return [wide * 1.05, [0.0, low, t.limbs[0][2] * 2.0], [low, height(kind), wide * 1.8, true]]


## Where a tree of the city stands: at `at`, scale s, turned a little about y and mirrored across the sun's plane
## (both keep the faces it was toned with facing near enough the same way), and stretched a little.
static func placed(r: RandomNumberGenerator, at: Vector3, s: float) -> Transform3D:
	var b := Basis(Vector3.UP, r.randf_range(-0.35, 0.35))
	if r.randf() < 0.5:
		b = b * Basis(Vector3(0, 0, -1), Vector3.UP, Vector3(-1, 0, 0))
	return Transform3D(b.scaled_local(Vector3(r.randf_range(0.94, 1.06), r.randf_range(0.9, 1.12), r.randf_range(0.94, 1.06)) * s), at)


## A tree's own shade among its neighbours: a little lighter or darker, warmer or cooler.
static func tint(r: RandomNumberGenerator) -> Color:
	var v := r.randf_range(0.88, 1.08)
	var w := r.randf_range(-0.05, 0.05)
	return Color(v * (1.0 + w), v, v * (1.0 - w * 1.5))


## Clipped leaves in grey, a tile seamless both ways: lit leaf tips over darker undersides, dark gaps between, nearly
## white on the whole so the leaves keep their colours; mipmapped, so a crown far off settles to its average.
static func leaf_texture() -> ImageTexture:
	if leaves_tex:
		return leaves_tex
	var r := RandomNumberGenerator.new()
	r.seed = 31
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(Color(0.93, 0.93, 0.93))
	for i in 30:
		var x := r.randi() % 16
		var y := r.randi() % 16
		img.set_pixel((x + 1) % 16, (y + 1) % 16, Color(0.66, 0.67, 0.7))
		img.set_pixel(x, (y + 1) % 16, Color(0.8, 0.8, 0.8))
		img.set_pixel(x, y, Color(1.0, 1.0, 0.96))
		img.set_pixel((x + 1) % 16, y, Color(1.0, 1.0, 0.94) if r.randf() < 0.5 else Color(0.94, 0.94, 0.92))
	for i in 8:
		img.set_pixel(r.randi() % 16, r.randi() % 16, Color(0.56, 0.58, 0.62))
	img.generate_mipmaps()
	leaves_tex = ImageTexture.create_from_image(img)
	return leaves_tex


## Copies src's triangles into st with UVs laid flat on each face, LEAF_TILE metres a tile.
static func leafy(st: SurfaceTool, src: SurfaceTool) -> void:
	var arr := src.commit_to_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	for i in range(0, v.size(), 3):
		var n := (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).normalized()
		var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var w := n.cross(u)
		for j in 3:
			st.set_color(c[i + j])
			st.set_uv(Vector2(v[i + j].dot(u), v[i + j].dot(w)) / LEAF_TILE)
			st.add_vertex(v[i + j])


## A tree of `kind` in form `detail` (see build and mesh).
static func tree(st: SurfaceTool, kind: int, xf: Transform3D, detail: int, variant: int, leaves: SurfaceTool = null) -> void:
	var t: Dictionary = TREES[kind]
	var r := RandomNumberGenerator.new()
	r.seed = kind * 7919 + variant * 104729 + 1
	var leaf: Array = t.leaf.map(func(h): return Color(h))
	for i in t.limbs.size() if detail == FULL else mini(1, t.limbs.size()):
		var l: Array = t.limbs[i]
		pipe(st, xf, l[0], l[1], l[2], l[3], 5 if detail == FULL else 3, Color(t.bark), i * 0.7)
	var k := xf.basis.get_scale().abs()
	var crown := st
	if leaves:
		crown = SurfaceTool.new()
		crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	if t.has("tiers"):
		for i in t.tiers.size() if detail == FULL else 0:
			var tr: Array = t.tiers[i]
			cone(crown, xf, tr[0], tr[1], tr[2], 7, 0.68, leaf[tr[3]], i * 1.3 + variant * 0.4)
		for tr in t.far if detail == SIMPLE else []:
			cone(crown, xf, tr[0], tr[1], tr[2], 6, 1.0, leaf[tr[3]].darkened(0.05), 0.3)
		if detail == TINY:
			cone(crown, xf, t.far[0][0], t.far[-1][1], t.far[0][2], 5, 1.0, leaf[1].darkened(0.05), 0.3)
	elif detail == SIMPLE:
		var f: Array = t.far
		Shapes.lump(crown, xf * f[0], f[1] * k, leaf[f[2]].darkened(0.05), 0.1, kind)
	elif detail == TINY:
		var f: Array = t.far
		var c: Vector3 = f[0]
		var rim := []
		for i in 5:
			rim.append(xf * (c + Vector3(cos(TAU * i / 5 + 0.3) * f[1].x, 0.0, sin(TAU * i / 5 + 0.3) * f[1].z)))
		for i in 5:
			Shapes.tri(crown, xf * (c + Vector3(0, f[1].y * 1.15, 0)), rim[i], rim[(i + 1) % 5], leaf[f[2]].darkened(0.05), true, xf * c)
			Shapes.tri(crown, xf * (c - Vector3(0, f[1].y * 0.9, 0)), rim[i], rim[(i + 1) % 5], leaf[f[2]].darkened(0.05), true, xf * c)
	else:
		for l in t.lumps:
			var c: Vector3 = l[0]
			if variant > 0:
				c += Vector3(r.randf_range(-0.1, 0.1), r.randf_range(-0.06, 0.06), r.randf_range(-0.1, 0.1)) * l[1].x
			Shapes.lump(crown, xf * c, l[1] * k * r.randf_range(0.94, 1.06), leaf[l[2]], 0.12, r.randi())
	if leaves:
		leafy(leaves, crown)


## A tapered prism from a to b (in xf's frame), `sides` faces round it, open at the ends unless `caps`.
static func pipe(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color, turn := 0.0, caps := false) -> void:
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.FORWARD if absf(ax.z) < 0.9 else Vector3.RIGHT).normalized()
	var w := ax.cross(u)
	var mid := xf * ((a + b) / 2)
	var ring0 := []
	var ring1 := []
	for i in sides:
		var d := u * cos(turn + TAU * i / sides) + w * sin(turn + TAU * i / sides)
		ring0.append(xf * (a + d * r0))
		ring1.append(xf * (b + d * r1))
	for i in sides:
		var j := (i + 1) % sides
		Shapes.quad(st, ring0[i], ring0[j], ring1[j], ring1[i], col, true, mid)
		if caps:
			Shapes.tri(st, xf * a, ring0[i], ring0[j], col, false, mid)
			Shapes.tri(st, xf * b, ring1[i], ring1[j], col, false, mid)


## A cedar's tier: a cone from y0 up to its tip at y1, its skirt cut into `tips` points of radius r, the notches
## between them drawn in to `notch` of it and lifted.
static func cone(st: SurfaceTool, xf: Transform3D, y0: float, y1: float, r: float, tips: int, notch: float, col: Color, turn: float) -> void:
	var top := xf * Vector3(0, y1, 0)
	var inside := xf * Vector3(0, y0 + (y1 - y0) * 0.2, 0)
	var n := tips * 2 if notch < 1.0 else tips
	var rim := []
	for i in n:
		var a := turn + TAU * i / n
		var lift := i % 2 == 1 and notch < 1.0
		rim.append(xf * Vector3(cos(a) * r * (notch if lift else 1.0), y0 + (r * 0.22 if lift else 0.0), sin(a) * r * (notch if lift else 1.0)))
	for i in n:
		Shapes.tri(st, top, rim[i], rim[(i + 1) % n], col, true, inside)


## An axis-aligned box between corners a and b in xf's frame.
static func block(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, col: Color) -> void:
	Shapes.turned_box(st, xf * Transform3D(Basis.from_scale((b - a).abs()), (a + b) / 2), col)


## The four walls of an open box between corners a and b, t thick.
static func hoop(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, t: float, col: Color) -> void:
	block(st, xf, a, Vector3(b.x, b.y, a.z + t), col)
	block(st, xf, Vector3(a.x, a.y, b.z - t), b, col)
	block(st, xf, Vector3(a.x, a.y, a.z + t), Vector3(a.x + t, b.y, b.z - t), col)
	block(st, xf, Vector3(b.x - t, a.y, a.z + t), Vector3(b.x, b.y, b.z - t), col)


## A ring of `segs` straight pieces round c in the plane of u and v (unit, square to each other), radius big, its
## tube radius small: a tyre or a rim.
static func ring(st: SurfaceTool, xf: Transform3D, c: Vector3, u: Vector3, v: Vector3, big: float, small: float, segs: int, col: Color) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		pipe(st, xf, c + (u * cos(a0) + v * sin(a0)) * big, c + (u * cos(a1) + v * sin(a1)) * big, small, small, 4, col, PI / 4)


## Japan's red round post box: a drum on a stone foot under a domed cap with a hooded slot to the front, the
## collection times on a white plate below it and the post office's mark.
static func post_box(st: SurfaceTool, xf: Transform3D) -> void:
	var red := Color("d8392b")
	var deep := Color("ab2a21")
	block(st, xf, Vector3(-0.27, -0.05, -0.27), Vector3(0.27, 0.08, 0.27), Color("9c978d"))
	pipe(st, xf, Vector3(0, 0.08, 0), Vector3(0, 0.2, 0), 0.25, 0.24, 12, deep, 0.0, true)
	pipe(st, xf, Vector3(0, 0.2, 0), Vector3(0, 1.1, 0), 0.22, 0.22, 12, red, 0.0, true)
	pipe(st, xf, Vector3(0, 1.1, 0), Vector3(0, 1.16, 0), 0.265, 0.265, 12, deep, 0.0, true)
	pipe(st, xf, Vector3(0, 1.16, 0), Vector3(0, 1.27, 0), 0.25, 0.19, 12, red, 0.0, true)
	pipe(st, xf, Vector3(0, 1.27, 0), Vector3(0, 1.36, 0), 0.19, 0.04, 12, red, 0.0, true)
	block(st, xf, Vector3(-0.14, 1.0, 0.17), Vector3(0.14, 1.04, 0.25), deep)  # the slot's hood
	block(st, xf, Vector3(-0.12, 0.955, 0.2), Vector3(0.12, 1.0, 0.225), Color("2b211f"))
	block(st, xf, Vector3(-0.1, 0.6, 0.205), Vector3(0.1, 0.86, 0.228), Color("f2eee4"))  # collection times
	for k in 4:
		block(st, xf, Vector3(-0.07, 0.65 + k * 0.05, 0.226), Vector3(0.07 - (k % 2) * 0.03, 0.665 + k * 0.05, 0.232), Color("7c776f"))
	block(st, xf, Vector3(-0.05, 0.4, 0.21), Vector3(0.05, 0.43, 0.232), Color("f2eee4"))  # the 〒 mark
	block(st, xf, Vector3(-0.012, 0.33, 0.21), Vector3(0.012, 0.4, 0.232), Color("f2eee4"))
	block(st, xf, Vector3(-0.05, 0.375, 0.21), Vector3(0.05, 0.39, 0.232), Color("f2eee4"))
	block(st, xf, Vector3(0.1, 0.24, 0.2), Vector3(0.13, 0.29, 0.228), Color("3a302c"))  # the door's lock


## A mamachari: a step-through frame on two wheels with a basket on the front, a carrier on the back, a chain guard
## and mudguards, parked on its stand. `variant` picks its paint.
static func bicycle(st: SurfaceTool, xf: Transform3D, variant: int) -> void:
	var paint: Color = [Color("a9bdd0"), Color("ece6d8"), Color("d98c9a"), Color("8f969e"), Color("8fb9a0")][variant % 5]
	var steel := Color("c3c8cd")
	var tyre := Color("34343a")
	var wr := 0.33
	var back := Vector3(-0.54, wr, 0)
	var front := Vector3(0.54, wr, 0)
	for c in [back, front]:
		ring(st, xf, c, Vector3.RIGHT, Vector3.UP, wr - 0.018, 0.022, 14, tyre)
		ring(st, xf, c, Vector3.RIGHT, Vector3.UP, wr - 0.05, 0.01, 14, steel)
		for a in 3:  # spokes, crossed through the hub
			var d := Vector3(cos(a * PI / 3), sin(a * PI / 3), 0) * (wr - 0.05)
			pipe(st, xf, c - d, c + d, 0.005, 0.005, 3, Color("9da3aa"))
		pipe(st, xf, c + Vector3(0, 0, -0.05), c + Vector3(0, 0, 0.05), 0.03, 0.03, 6, steel, 0.0, true)
		for i in 5:  # the mudguard over the top of the wheel
			var a0 := PI * (0.12 + i * 0.16)
			var a1 := PI * (0.12 + (i + 1) * 0.16)
			var p0: Vector3 = c + Vector3(cos(a0) * (1 if c == front else -1), sin(a0), 0) * (wr + 0.03)
			var p1: Vector3 = c + Vector3(cos(a1) * (1 if c == front else -1), sin(a1), 0) * (wr + 0.03)
			pipe(st, xf, p0, p1, 0.035, 0.035, 4, paint, PI / 4)
	var bb := Vector3(-0.04, 0.3, 0)
	var seat := Vector3(-0.2, 0.86, 0)
	var head := Vector3(0.4, 0.78, 0)
	for e in [[bb, seat, 0.022], [bb, Vector3(0.18, 0.4, 0), 0.026], [Vector3(0.18, 0.4, 0), head, 0.026], [head, Vector3(0.44, 0.96, 0), 0.03]]:
		pipe(st, xf, e[0], e[1], e[2], e[2], 5, paint)
	for z in [-0.045, 0.045]:
		pipe(st, xf, bb + Vector3(0, 0, z * 0.6), back + Vector3(0, 0, z), 0.012, 0.012, 4, paint)
		pipe(st, xf, seat + Vector3(0.02, -0.08, z * 0.4), back + Vector3(0, 0, z), 0.012, 0.012, 4, paint)
		pipe(st, xf, head + Vector3(0.0, 0.02, z * 0.6), front + Vector3(0, 0, z), 0.014, 0.014, 4, paint)
	block(st, xf, Vector3(-0.52, 0.24, 0.045), Vector3(0.04, 0.38, 0.07), paint)  # the chain guard
	pipe(st, xf, Vector3(0.44, 0.96, 0), Vector3(0.38, 1.06, 0), 0.015, 0.015, 4, steel)  # stem and bars, swept back
	pipe(st, xf, Vector3(0.38, 1.06, -0.2), Vector3(0.38, 1.06, 0.2), 0.013, 0.013, 4, steel)
	for z in [-1.0, 1.0]:
		pipe(st, xf, Vector3(0.38, 1.06, 0.2 * z), Vector3(0.25, 1.05, 0.3 * z), 0.018, 0.018, 4, Color("3b3633"))
	pipe(st, xf, seat, seat + Vector3(-0.02, 0.06, 0), 0.012, 0.012, 4, steel)
	block(st, xf, Vector3(-0.33, 0.9, -0.075), Vector3(-0.1, 0.96, 0.075), Color("6b4a37"))  # the saddle
	var wicker := Color("c69a5a")
	block(st, xf, Vector3(0.5, 0.82, -0.17), Vector3(0.82, 0.84, 0.17), Color("6e5432"))  # the basket over the front wheel
	hoop(st, xf, Vector3(0.5, 0.82, -0.17), Vector3(0.82, 1.06, 0.17), 0.02, wicker)
	for k in 3:  # the weave in darker bands, and a lighter rim
		hoop(st, xf, Vector3(0.496, 0.87 + k * 0.06, -0.174), Vector3(0.824, 0.888 + k * 0.06, 0.174), 0.024, wicker.darkened(0.18))
	hoop(st, xf, Vector3(0.494, 1.04, -0.176), Vector3(0.826, 1.06, 0.176), 0.026, wicker.lightened(0.1))
	block(st, xf, Vector3(-0.8, 0.72, -0.1), Vector3(-0.3, 0.74, 0.1), steel)  # the carrier on its struts
	for z in [-0.09, 0.09]:
		pipe(st, xf, Vector3(-0.72, 0.72, z), back + Vector3(0, 0, z), 0.01, 0.01, 3, steel)
	pipe(st, xf, back + Vector3(0, 0, 0.06), Vector3(-0.62, 0.0, 0.16), 0.012, 0.012, 4, steel)  # the stand


## A flower planter: a box of stained planks on two rails, a cap round its rim, soil, and leaves among pansies and
## marigolds in red, pink, yellow, white and violet. `variant` reseeds the flowers.
static func planter(st: SurfaceTool, xf: Transform3D, variant: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 4111 + variant
	var wood := Color("9c6639")
	var hw := 0.46
	var hd := 0.22
	for x in [-hw + 0.08, hw - 0.08]:
		block(st, xf, Vector3(x - 0.04, 0.0, -hd - 0.02), Vector3(x + 0.04, 0.05, hd + 0.02), wood.darkened(0.35))
	block(st, xf, Vector3(-hw, 0.05, -hd), Vector3(hw, 0.39, hd), wood.darkened(0.3))
	for k in 3:  # the planks, a dark seam between each
		var y := 0.06 + k * 0.11
		block(st, xf, Vector3(-hw - 0.006, y, -hd - 0.006), Vector3(hw + 0.006, y + 0.1, hd + 0.006), wood if k % 2 == 0 else wood.darkened(0.06))
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		block(st, xf, Vector3(c.x * hw - 0.03, 0.05, c.y * hd - 0.03), Vector3(c.x * hw + 0.03, 0.4, c.y * hd + 0.03), wood.darkened(0.15))
	block(st, xf, Vector3(-hw - 0.03, 0.39, -hd - 0.03), Vector3(hw + 0.03, 0.42, hd + 0.03), wood.lightened(0.12))
	block(st, xf, Vector3(-hw + 0.03, 0.4, -hd + 0.03), Vector3(hw - 0.03, 0.425, hd - 0.03), Color("4c3628"))
	for i in 4:
		var c := Vector3(-0.3 + i * 0.2 + r.randf_range(-0.04, 0.04), 0.47, r.randf_range(-0.06, 0.06))
		Shapes.lump(st, xf * c, Vector3(0.14, 0.09, 0.13), Color("4f963d") if i % 2 else Color("62a849"), 0.2, r.randi())
	var flowers := [Color("e8443a"), Color("f27aa8"), Color("f5c842"), Color("f6f2ea"), Color("9a6ad0"), Color("f08a3a")]
	for i in 14:
		var c := Vector3(r.randf_range(-0.36, 0.36), r.randf_range(0.53, 0.6), r.randf_range(-0.13, 0.13))
		Shapes.lump(st, xf * c, Vector3(0.07, 0.045, 0.07), flowers[(i + variant) % flowers.size()], 0.15, r.randi())


## A bus stop: a pole on a round concrete foot, the timetable on a framed white plate with the operator's colour
## across its head, and the stop's sign up top, a white disc in a blue ring with a bus on it, facing the road.
static func bus_stop(st: SurfaceTool, xf: Transform3D) -> void:
	var blue := Color("2f6fb5")
	pipe(st, xf, Vector3(0, -0.02, 0), Vector3(0, 0.12, 0), 0.25, 0.22, 10, Color("b9b4aa"), 0.0, true)
	pipe(st, xf, Vector3(0, 0.12, 0), Vector3(0, 0.15, 0), 0.2, 0.16, 10, Color("cbc6bc"), 0.0, true)
	pipe(st, xf, Vector3(0, 0.15, 0), Vector3(0, 2.3, 0), 0.032, 0.03, 6, Color("d3d7da"), 0.0, true)
	block(st, xf, Vector3(-0.22, 0.98, 0.035), Vector3(0.22, 1.6, 0.06), Color("8a9097"))  # the timetable
	block(st, xf, Vector3(-0.2, 1.0, 0.06), Vector3(0.2, 1.5, 0.068), Color("f4f2ea"))
	block(st, xf, Vector3(-0.2, 1.5, 0.06), Vector3(0.2, 1.58, 0.07), Color("2f8a5a"))
	for k in 7:
		block(st, xf, Vector3(-0.16, 1.05 + k * 0.06, 0.066), Vector3(0.16 - (k % 3) * 0.05, 1.07 + k * 0.06, 0.072), Color("5d6268"))
	var c := Vector3(0, 2.12, 0.03)
	pipe(st, xf, c - Vector3(0, 0, 0.025), c + Vector3(0, 0, 0.015), 0.25, 0.25, 14, blue, 0.0, true)
	pipe(st, xf, c + Vector3(0, 0, 0.015), c + Vector3(0, 0, 0.022), 0.2, 0.2, 14, Color("f7f6f1"), 0.0, true)
	block(st, xf, c + Vector3(-0.1, -0.06, 0.02), c + Vector3(0.1, 0.06, 0.028), blue)  # the bus
	block(st, xf, c + Vector3(-0.08, 0.0, 0.026), c + Vector3(0.08, 0.035, 0.03), Color("f7f6f1"))
	for x in [-0.055, 0.055]:
		block(st, xf, c + Vector3(x - 0.02, -0.085, 0.02), c + Vector3(x + 0.02, -0.055, 0.028), Color("1f3550"))
