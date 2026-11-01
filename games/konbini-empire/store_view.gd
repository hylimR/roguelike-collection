extends Control
## The city stage: an isometric city (orthographic camera) of blocks, roads, landmarks and rival chains'
## storefronts, with your focused shop drawn as a cutaway interior on its own lot. Replays a day's customers
## along AStarGrid2D paths, lets you arrange the shop, and in city mode pick lots. Sprites are billboards;
## bubbles, pins and labels draw on a 2D overlay. Shop-local nodes live under `site` at the shop's origin.

signal finished
signal changed
signal lot_clicked(li: int)

const Sim := preload("res://sim.gd")
const DUR := 10.0
const PACE := 0.7  # share of DUR over which the day's customers arrive
const SPEED := 3.6
const MAX_SHOWN := 20
const PERSON_PX := 0.017
const STRIDE := 2.2  # walk frames per unit walked (art/walk.png: column 0 stands, 1-4 walk)
const MAX_FPS := 11.0
const ITEM_PX := 0.007
const DECOR_PX := 0.014
const OUTDOOR_PX := 0.03
# per-prop size: trees full, street furniture smaller (art/outdoor.png draws every prop the same size)
const OUTDOOR_SCALE := [1.0, 1.0, 0.95, 1.05, 0.45, 0.45, 0.6, 0.32, 0.38, 0.38, 0.36, 0.5]
const BUILDING_CELL := Vector2i(256, 256)
const BUILDING_PX := 0.03
const VEHICLE_CELL := Vector2i(128, 96)
const VEHICLE_PX := 0.025
# atlas cells (art is cut at 2x its own pixel grid)
const ITEM := 64
const PERSON := Vector2i(72, 96)
const DECOR := 96
const OUTDOOR := 128
const STOREFRONT := Vector2i(256, 192)
const STOREFRONT_PX := 0.13
const LANDMARK := 256
const LANDMARK_H := {"landmarks": 256, "tokyo": 384}  # the Tokyo sheet has tall cells for the towers
const TRAIN := Vector2i(320, 192)
const TRAIN_PX := 0.05
const DECK := 3.2  # Yamanote viaduct height
const TRAIN_SPEED := 14.0
const LANDMARK_PX := 0.085
const SHOP_PX := 0.075  # art/buildings.png on ordinary shop lots
# road cross-section from its top edge: sidewalk, two lanes [offset, direction along the road], sidewalk
const WALK_NEAR := 1.2
const WALK_LINES := [1.1, 8.1]
const LANES := [[3.5, -1.0], [5.9, 1.0]]
const MAX_WALKERS := 70
const MAX_CARS := 22
const PITCH := 30.0
# wall = crop of the side-view background used as the back wall texture
const LAYOUT := {
	"konbini": {"bg": "bg_konbini", "wall": Rect2i(0, 140, 544, 108), "rows": [0.42, 1.0], "gh": 1.42, "clerks": [0.0], "floor": [Color("ead9b8"), Color("cbb48e")], "stripe": [Color("f05a28"), Color("1f9d55")]},
	"super": {"bg": "bg_super", "wall": Rect2i(0, 124, 536, 120), "rows": [0.34, 0.84, 1.34], "gh": 1.8, "clerks": [-0.8, 0.8], "floor": [Color("efe3c8"), Color("d2c3a3")], "stripe": [Color("1f9d55"), Color("1f9d55")]},
}

var tex := {}
var sim
var si := 0
var store: Dictionary = {}
var kind := ""
var stock0: Array = []
var stock1: Array = []
var queue: Array = []
var people: Array = []
var floaters: Array = []
var shelf_sprites: Array = []  # per slot: [Sprite3D x3]
var t := 0.0
var playing := false
var paused := false
var edit := false
var carry := {}  # {"idx": object index} or {"new": decor id}
var hover := Sim.NO_CELL
var hover_obj := -1
var nav_grid: AStarGrid2D
var ghost_cells: Array = []
var ghost_ok := true

var lot := Vector2(14, 8)  # shop width and depth incl. walkway row
var walkers: Array = []
var cars: Array = []
var next_walker := 0.0
var next_car := 0.0
var mode := "store"  # store | city
var city_sig := ""
var city_sprites: Array = []  # [Sprite3D, half width] for occlusion fading
var hover_lot := -1
var pick := ""  # city mode: "" | branch | buyout
var site: Node3D
var city: Node3D
var trains: Array = []  # {node, d: distance along the loop, v}
var rail_parts: Array = []  # [node, a, b]: viaduct pieces, hidden when they would cover the focused shop
var loop: PackedVector2Array  # Yamanote Line, closed polyline in world xz
var shadow_mesh: CylinderMesh
var cam_target := Vector3.ZERO
var cam_offset := Vector3.ZERO
var cam_base := 12.0
var zoom := 1.0

var vp: SubViewport
var vp_scale := 1.0  # real pixels per UI unit
var cam: Camera3D
var room: Node3D
var street: Node3D
var props: Node3D
var actors: Node3D
var overlay: Control


func _ready() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var screen_rect := TextureRect.new()
	screen_rect.texture = vp.get_texture()
	screen_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(screen_rect)
	get_window().size_changed.connect(fit_viewport)
	fit_viewport.call_deferred()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b2d42")
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	cam = Camera3D.new()
	cam.fov = 38.0
	vp.add_child(cam)
	city = Node3D.new()
	vp.add_child(city)
	street = Node3D.new()
	vp.add_child(street)
	site = Node3D.new()
	vp.add_child(site)
	room = Node3D.new()
	site.add_child(room)
	props = Node3D.new()
	site.add_child(props)
	actors = Node3D.new()
	site.add_child(actors)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(draw_overlay)
	add_child(overlay)


# ---------- building ----------

func mat(color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_texture = texture
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func block(parent: Node3D, size_: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size_
	mi.mesh = bm
	mi.material_override = mat(color)
	mi.position = pos
	parent.add_child(mi)


func plane(parent: Node3D, size_: Vector2, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size_
	mi.mesh = pm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func sprite(sheet: String, region: Rect2, px: float, billboard := true) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex[sheet]
	s.region_enabled = true
	s.region_rect = region
	s.pixel_size = px
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	if billboard:
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	return s


func tiles(a: Color, b: Color) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(a)
	for i in 16:
		img.set_pixel(i, 15, b)
		img.set_pixel(15, i, b)
	return ImageTexture.create_from_image(img)


func build_room() -> void:
	for c in room.get_children():
		c.free()
	var L: Dictionary = LAYOUT[kind]
	var g: Vector2i = Sim.GRID[kind]
	var w := float(g.x)
	var depth := g.y + 1.0
	lot = Vector2(w, depth)
	# shop slab and floor
	block(room, Vector3(w + 0.5, 0.2, depth + 0.5), Vector3(w / 2, -0.1, depth / 2), Color("8a6e4b"))
	var fm := mat(Color.WHITE, tiles(L.floor[0], L.floor[1]))
	fm.uv1_scale = Vector3(w, depth, 1)
	fm.texture_repeat = true
	plane(room, Vector2(w, depth), Vector3(w / 2, 0.002, depth / 2), fm)
	# cutaway walls: the back one carries the Codex back-wall art, the left one is plain with the shop stripes
	var crop: Image = tex[L.bg].get_image().get_region(L.wall)
	var h: float = w * crop.get_height() / crop.get_width()
	block(room, Vector3(w + 0.5, h, 0.25), Vector3(w / 2, h / 2, -0.125), Color("e6dcc6"))
	var art := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	art.mesh = q
	art.material_override = mat(Color.WHITE, ImageTexture.create_from_image(crop))
	art.position = Vector3(w / 2, h / 2, 0.005)
	room.add_child(art)
	block(room, Vector3(0.25, h, depth + 0.5), Vector3(-0.125, h / 2, depth / 2), Color("efe6d2"))
	block(room, Vector3(0.02, 0.16, depth), Vector3(0.01, h * 0.72, depth / 2), L.stripe[0])
	block(room, Vector3(0.02, 0.16, depth), Vector3(0.01, h * 0.62, depth / 2), L.stripe[1])
	for z in [1.6, depth - 2.2]:
		block(room, Vector3(0.03, h * 0.38, 1.6), Vector3(0.02, h * 0.36, z), Color("9fd3ea"))
	block(room, Vector3(w + 0.6, 0.14, 0.35), Vector3(w / 2, h + 0.07, -0.125), Color("5b4632"))
	block(room, Vector3(0.35, 0.14, depth + 0.6), Vector3(-0.125, h + 0.07, depth / 2), Color("5b4632"))


## Store mode frames the focused shop; city mode frames the whole city. Drag pans, wheel zooms.
func set_mode(m: String) -> void:
	mode = m
	cam_offset = Vector3.ZERO
	zoom = 1.0
	pick = "" if m == "store" else pick
	update_camera()
	update_fade()


func update_camera() -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var target: Vector3
	if mode == "city":
		var b: Rect2 = sim.city_bounds()
		target = Vector3(b.get_center().x, 0, b.get_center().y)
		cam.size = (b.size.x + b.size.y) * 0.4 * zoom
	else:
		target = site.position + Vector3(lot.x / 2 + 0.3, 0.9, lot.y / 2 + 0.8)
		cam.size = (lot.x + lot.y) * 0.6 * zoom
	var pitch := deg_to_rad(PITCH)
	target += cam_offset
	cam.position = target + Vector3(sin(PI / 4) * cos(pitch), sin(pitch), cos(PI / 4) * cos(pitch)) * 400.0
	cam.far = 900.0
	cam.look_at(target)
	overlay.queue_redraw()


func stripes(a: Color, b: Color, w: int, h: int, on: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(a)
	for x in on:
		for y in h:
			img.set_pixel(x, y, b)
	return ImageTexture.create_from_image(img)


func tiled(tex_: Texture2D, reps: Vector2) -> StandardMaterial3D:
	var m := mat(Color.WHITE, tex_)
	m.uv1_scale = Vector3(reps.x, reps.y, 1)
	m.texture_repeat = true
	return m


func city_sprite(sheet: String, region: Rect2, px: float, at: Vector3) -> Sprite3D:
	var s := sprite(sheet, region, px)
	s.position = at + Vector3(0, region.size.y / 2.0 * px - 0.1, 0)
	city.add_child(s)
	city_sprites.append([s, region.size.x / 2.0 * px])
	return s


## Ground, streets, blocks, the river, the bay and every lot except the focused shop's.
func build_city() -> void:
	for c in city.get_children():
		c.free()
	city_sprites.clear()
	rail_parts.clear()
	var bounds: Rect2 = sim.city_bounds()
	var mid := bounds.get_center()
	var grass := tiled(speckle([Color("7fa35a"), Color("8cb064"), Color("739a52"), Color("98b86c")]), Vector2(400, 400))
	plane(city, Vector2(1600, 1600), Vector3(mid.x, -0.14, mid.y), grass)
	# Tokyo Bay: the coast steps along the ends of the southern rows and wraps under the last one
	var sea := tiled(speckle([Color("3f7fbf"), Color("4a8ccb"), Color("3a74b0"), Color("5596d3")]), Vector2(400, 400))
	for r in range(3, sim.rows.size()):
		var rw: Dictionary = sim.rows[r]
		var x0: float = rw.x1 + Sim.ROAD + 3.0 - (r - 3) * 6.0
		plane(city, Vector2(800, rw.z1 - rw.z0 + 0.2), Vector3(x0 + 400, -0.13, (rw.z0 + rw.z1) / 2 - Sim.ROAD / 2), sea)
	var last: Dictionary = sim.rows[-1]
	var south: float = last.z1 + 2.0
	plane(city, Vector2(1200, 800), Vector3(last.x0 + 170.0 + 600, -0.13, south + 400), sea)
	plane(city, Vector2(1200, 800), Vector3(last.x0 + 300.0 + 600, -0.13, south - 6.0 + 400), sea)
	# the outskirts: scattered trees and houses round the city's edge
	var out := RandomNumberGenerator.new()
	out.seed = 23
	for k in 70:
		var p2 := Vector2(out.randf_range(bounds.position.x - 60, bounds.end.x + 20), out.randf_range(bounds.position.y - 50, bounds.end.y + 30))
		if bounds.grow(-2.0).has_point(p2) or p2.x > bounds.end.x - 60 and p2.y > bounds.get_center().y:
			continue
		var id: int = [0, 1, 2, 3, 3, 4][out.randi() % 6]
		city_sprite("outdoor", Rect2(id * OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * OUTDOOR_SCALE[id], Vector3(p2.x, 0, p2.y))
	var asphalt := mat(Color("5d5f66"))
	var dash := stripes(Color("5d5f66"), Color("e8e2c8"), 8, 1, 4)
	for rd in sim.roads:
		var length: float = rd.to - rd.from
		var middle: float = (rd.from + rd.to) / 2.0
		if rd.axis == "h":
			plane(city, Vector2(length, rd.w), Vector3(middle, -0.12, rd.line + rd.w / 2), asphalt)
			plane(city, Vector2(length, 0.15), Vector3(middle, -0.11, rd.line + 4.6), tiled(dash, Vector2(length / 2.0, 1)))
		else:
			plane(city, Vector2(rd.w, length), Vector3(rd.line + rd.w / 2, -0.12, middle), asphalt)
			if rd.w >= Sim.ROAD:
				var mi := MeshInstance3D.new()
				var pm := PlaneMesh.new()
				pm.size = Vector2(length, 0.15)
				mi.mesh = pm
				mi.material_override = tiled(dash, Vector2(length / 2.0, 1))
				mi.rotation.y = PI / 2
				mi.position = Vector3(rd.line + 4.6, -0.11, middle)
				city.add_child(mi)
	for rd in sim.roads:
		if rd.axis == "h" and not rd.bridge.is_empty():
			var bx: float = rd.bridge[0] + rd.bridge[1] / 2
			plane(city, Vector2(rd.bridge[1] + 0.4, rd.w), Vector3(bx, -0.1, rd.line + rd.w / 2), mat(Color("6a6c73")))
			for side in [0.3, rd.w - 0.3]:
				block(city, Vector3(rd.bridge[1] + 0.6, 0.45, 0.15), Vector3(bx, 0.12, rd.line + side), Color("d9d4c7"))
	# the Sumida jogs from row to row under its bridges. Plazas between blocks are green with trees and a path.
	for rw in sim.rows:
		for g in rw.gaps:
			if g[2] == "p":
				plane(city, Vector2(g[1], rw.z1 - rw.z0), Vector3(g[0] + g[1] / 2, -0.115, (rw.z0 + rw.z1) / 2), grass)
				var pr := RandomNumberGenerator.new()
				pr.seed = int(g[0] * 13.0 + rw.z0)
				for k in int(rw.depth / 5.0):
					var id: int = [0, 1, 2, 3, 2][pr.randi() % 5]
					var side: float = 1.5 if k % 2 == 0 else g[1] - 1.5
					city_sprite("outdoor", Rect2(id * OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * OUTDOOR_SCALE[id] * 0.85, Vector3(g[0] + side, 0, rw.z0 + 2.0 + k * 5.0))
			if g[2] != "r":
				continue
			plane(city, Vector2(g[1], rw.z1 - rw.z0 + Sim.ROAD), Vector3(g[0] + g[1] / 2, -0.105, (rw.z0 - Sim.ROAD + rw.z1) / 2), sea)
	var walk_tiles := tiles(Color("c9c4bb"), Color("a9a49b"))
	var paving := tiles(Color("d8d2c4"), Color("bdb6a6"))
	var yard_paving := tiles(Color("bfb7a8"), Color("aaa293"))
	var zebra := tiled(stripes(Color("5d5f66"), Color("ece7d8"), 8, 1, 4), Vector2(6, 1))
	for d in sim.districts:
		var r2: Rect2 = d.rect
		var c := r2.get_center()
		var rim := r2.grow(2.2)
		plane(city, rim.size, Vector3(rim.get_center().x, -0.1, rim.get_center().y), tiled(walk_tiles, rim.size))
		var below: float = r2.end.y + Sim.ROAD
		var next_row: float = sim.rows[d.row].z1
		if next_row - below > 0.5:
			var gp := Vector2(r2.size.x, next_row - below)
			plane(city, gp, Vector3(c.x, -0.1, below + gp.y / 2), grass)
		var row_top: float = sim.rows[d.row].z0
		if r2.position.y - 2.2 > row_top + 0.5:  # pocket park behind a shallower block
			var pk := Vector2(r2.size.x + 4.4, r2.position.y - 2.2 - row_top)
			plane(city, pk, Vector3(c.x, -0.1, row_top + pk.y / 2), grass)
			for k in int(r2.size.x / 9.0):
				city_sprite("outdoor", Rect2(OUTDOOR * [0, 1, 2, 4][k % 4], 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * 0.55, Vector3(r2.position.x + 4.0 + k * 9.0, 0, row_top + pk.y * 0.5))
		var yard := r2.size.y - Sim.LOT_D
		var green: bool = d.type in ["park", "palace", "homes"]
		plane(city, Vector2(r2.size.x, yard), Vector3(c.x, -0.09, r2.position.y + yard / 2), grass if green else tiled(yard_paving, Vector2(r2.size.x, yard)))
		plane(city, Vector2(r2.size.x, Sim.LOT_D), Vector3(c.x, -0.09, r2.end.y - Sim.LOT_D / 2), tiled(paving, Vector2(r2.size.x, Sim.LOT_D)))
		var zm := MeshInstance3D.new()
		var zp := PlaneMesh.new()
		zp.size = Vector2(4.8, 2.6)
		zm.mesh = zp
		zm.material_override = zebra
		zm.rotation.y = PI / 2
		zm.position = Vector3(c.x, -0.105, r2.end.y + 4.6)
		city.add_child(zm)
		backyard(d)
	for li in sim.lots.size():
		lot_sprite(li)
	build_yamanote()


## The elevated Yamanote Line, straight from station to station over the blocks, with two trains on it.
func build_yamanote() -> void:
	loop = PackedVector2Array()
	for stn in Sim.YAMANOTE:
		for d in sim.districts:
			if d.name == stn:
				var yard: float = d.rect.size.y - Sim.LOT_D
				loop.append(Vector2(d.rect.get_center().x, d.rect.position.y + yard / 2))
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var along := b - a
		var angle := atan2(-along.y, along.x)
		var holder := Node3D.new()
		holder.position = Vector3((a.x + b.x) / 2, 0, (a.y + b.y) / 2)
		holder.rotation.y = angle
		city.add_child(holder)
		block(holder, Vector3(along.length() + 1.8, 0.35, 1.8), Vector3(0, DECK, 0), Color("b9b5ad"))
		block(holder, Vector3(along.length() + 1.8, 0.05, 0.3), Vector3(0, DECK + 0.2, 0.75), Color("7fc241"))
		var n := int(along.length() / 9.0)
		for k in n + 1:
			block(holder, Vector3(0.6, DECK, 0.6), Vector3(-along.length() / 2 + along.length() * k / maxf(1, n), DECK / 2, 0), Color("9c978d"))
		rail_parts.append([holder, a, b])
	for trn in trains:
		trn.node.queue_free()
	trains.clear()
	var length := loop_length()
	for k in 2:
		var node := sprite("train", Rect2(0, 0, TRAIN.x, TRAIN.y), TRAIN_PX)
		street.add_child(node)
		trains.append({"node": node, "d": length * k / 2.0, "v": TRAIN_SPEED * (1 if k == 0 else -1)})
	move_trains(0.0)


func loop_length() -> float:
	var total := 0.0
	for i in loop.size():
		total += loop[i].distance_to(loop[(i + 1) % loop.size()])
	return total


func move_trains(delta: float) -> void:
	if loop.is_empty():
		return
	var length := loop_length()
	for trn in trains:
		trn.d = fposmod(trn.d + trn.v * delta, length)
		var d: float = trn.d
		for i in loop.size():
			var a := loop[i]
			var b := loop[(i + 1) % loop.size()]
			var seg := a.distance_to(b)
			if d <= seg:
				var p2 := a.lerp(b, d / seg)
				var dir := (b - a).normalized() * signf(trn.v)
				var along_x := absf(dir.x) >= absf(dir.y)
				var forward := dir.x > 0 if along_x else dir.y > 0
				trn.node.region_rect = Rect2((0 if forward else 1) * TRAIN.x, 0, TRAIN.x, TRAIN.y)
				trn.node.flip_h = not along_x
				trn.node.position = Vector3(p2.x, DECK + 0.2 + TRAIN.y / 2.0 * TRAIN_PX * 0.55, p2.y)
				var near_shop := false
				if mode == "store":
					near_shop = p2.distance_to(Sim.lot_pos(sim.lots[focus_lot()])) < 20.0
				trn.node.visible = not near_shop
				break
			d -= seg


## Dense back streets: small houses and shops, greenery near the street behind; parks are all trees.
func backyard(d: Dictionary) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash(d.name)
	var r2: Rect2 = d.rect
	var yard := r2.size.y - Sim.LOT_D
	var green: bool = d.type in ["park", "palace"]
	var x := r2.position.x + r.randf_range(4.0, 8.0)
	while x < r2.end.x - 4.0:
		var z := r2.position.y + r.randf_range(yard * 0.45, yard - 1.0)
		if green or r.randf() < 0.3:
			var id: int = [0, 1, 2, 3][r.randi() % 4]
			city_sprite("outdoor", Rect2(id * OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * OUTDOOR_SCALE[id], Vector3(x, 0, z))
		else:
			var f: int = [4, 2, 0, 3, 1, 5][r.randi() % 6]
			city_sprite("buildings", Rect2(f * BUILDING_CELL.x, 0, BUILDING_CELL.x, BUILDING_CELL.y), SHOP_PX * 0.62, Vector3(x, 0, z))
		x += r.randf_range(8.0, 13.0)
	for k in int(r2.size.x / 12.0):
		var id: int = [4, 5, 10, 9][r.randi() % 4]
		city_sprite("outdoor", Rect2(id * OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * OUTDOOR_SCALE[id], Vector3(r.randf_range(r2.position.x + 2, r2.end.x - 2), 0, r2.position.y + r.randf_range(0.8, 3.0)))
	for k in maxi(1, int(r2.size.x / 20.0)):
		city_sprite("outdoor", Rect2(6 * OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * OUTDOOR_SCALE[6], Vector3(r2.position.x + 5.0 + k * 20.0, 0, r2.end.y + 2.0))


func lot_sprite(li: int) -> void:
	var L: Dictionary = sim.lots[li]
	if li == focus_lot():
		return
	var at := Vector3(L.x0 + Sim.LOT_W * 0.62, 0, L.front - 0.4)
	match L.use:
		"landmark":
			var lm: Array = sim.districts[L.block].lm
			if li > 0 and sim.lots[li - 1].block == L.block and sim.lots[li - 1].use == "landmark":
				lm = ["landmarks", 4]  # a block that is all landmark (the palace) gets gardens on its other lots
			city_sprite(lm[0], Rect2(lm[1] * LANDMARK, 0, LANDMARK, LANDMARK_H[lm[0]]), LANDMARK_PX, at)
		"shop":
			city_sprite("buildings", Rect2([0, 1, 3, 5][li % 4] * BUILDING_CELL.x, 0, BUILDING_CELL.x, BUILDING_CELL.y), SHOP_PX, at)
		"store":
			var st := store_on(li)
			var f: int = Sim.CHAINS[st[1]].frame * 2 + (1 if st[0].kind == "super" else 0)
			city_sprite("storefronts", Rect2(f * STOREFRONT.x, 0, STOREFRONT.x, STOREFRONT.y), STOREFRONT_PX, at)


## [store dict, chain] standing on lot li.
func store_on(li: int) -> Array:
	for st in sim.stores:
		if st.lot == li:
			return [st, 0]
	return [sim.rival_at(li), sim.rival_at(li).get("chain", 1)]


func focus_lot() -> int:
	return store.get("lot", -1)


## What the city looks like; the view rebuilds only when this changes.
func city_signature() -> String:
	var parts := [str(focus_lot()), store.get("kind", "")]
	for L in sim.lots:
		parts.append(L.use)
	for st in sim.stores:
		parts.append("%d%s" % [st.lot, st.kind])
	for rv in sim.rivals:
		if rv.open:
			parts.append("%d%d%s" % [rv.lot, rv.chain, rv.kind])
	return ",".join(parts)


## Fades city sprites that stand between the camera and the focused shop.
func update_fade() -> void:
	var shop := Rect2()
	if mode == "store":
		var lo := iso(site.position)
		shop = Rect2(lo + Vector2(-lot.y * 0.71, -4.0), Vector2((lot.x + lot.y) * 0.71, (lot.x + lot.y) * 0.36 + 4.0))
	for e in city_sprites:
		var s: Sprite3D = e[0]
		var base := iso(s.position - Vector3(0, s.position.y, 0))
		var tall: float = s.region_rect.size.y * s.pixel_size
		var r := Rect2(base + Vector2(-e[1], -tall * 0.87), Vector2(e[1] * 2, tall * 0.87))
		var fade_it: bool = mode == "store" and r.intersects(shop) and s.position.x + s.position.z > site.position.x + site.position.z + lot.y
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED if fade_it else SpriteBase3D.ALPHA_CUT_DISCARD
		s.modulate = Color(1, 1, 1, 0.25) if fade_it else Color.WHITE
	var shop_at: Vector2 = Sim.lot_pos(sim.lots[focus_lot()]) if focus_lot() >= 0 else Vector2(INF, INF)
	for part in rail_parts:
		var near: float = shop_at.distance_to(Geometry2D.get_closest_point_to_segment(shop_at, part[1], part[2]))
		part[0].visible = mode != "store" or near > 20.0


## World xz to the iso screen plane (x right, y down), in world units.
func iso(p: Vector3) -> Vector2:
	return Vector2((p.x - p.z) * 0.7071, (p.x + p.z) * 0.3536 - p.y * 0.866)


# ---------- street life (cosmetic, not seeded) ----------

func view_center() -> Vector2:
	var t3 := cam.position - cam.global_transform.basis.z * 400.0
	return Vector2(t3.x, t3.z)


## Street segments crossing the view (cars only on full-width streets).
func roads_near(c: Vector2, r: float, for_cars: bool) -> Array:
	var out := []
	for rd in sim.roads:
		if for_cars and rd.w < Sim.ROAD:
			continue
		var across: float = c.y if rd.axis == "h" else c.x
		var along: float = c.x if rd.axis == "h" else c.y
		if absf(rd.line + rd.w / 2 - across) < r and rd.from < along + r and rd.to > along - r:
			out.append(rd)
	return out


## A walker on a sidewalk (or a car in a lane) of a road in view, entering from the view's edge.
func spawn_mover(is_car: bool, mid := false) -> void:
	var c := view_center()
	var r := cam.size * 1.1
	var roads := roads_near(c, r, is_car)
	if roads.is_empty():
		return
	var rd: Dictionary = roads[randi() % roads.size()]
	var dir := 1.0 if randf() < 0.5 else -1.0
	var line: float
	if is_car:
		var lane: Array = LANES[randi() % 2]
		dir = lane[1] if rd.axis == "h" else -lane[1]
		line = rd.line + lane[0]
	elif rd.w < Sim.ROAD:
		line = rd.line + [0.9, rd.w - 0.9][randi() % 2]
	else:
		line = rd.line + WALK_LINES[randi() % 2] + randf_range(-0.5, 0.5)
	var centre: float = c.x if rd.axis == "h" else c.y
	var lo: float = maxf(rd.from, centre - r - 4.0)
	var hi: float = minf(rd.to, centre + r + 4.0)
	var s := randf_range(lo, hi) if mid else (lo if dir > 0 else hi)
	var node: Sprite3D
	var m := {"axis": rd.axis, "line": line, "s": s, "lo": lo - 0.5, "hi": hi + 0.5}
	if is_car and cars.any(func(o): return o.axis == rd.axis and absf(o.line - line) < 0.5 and absf(o.s - s) < 7.0):
		return  # keep cars apart in their lane
	if is_car:
		var kv := randi() % 4
		var frame := kv * 2 + (0 if (dir > 0) == (rd.axis == "h") else 1)
		node = sprite("vehicles", Rect2(frame * VEHICLE_CELL.x, 0, VEHICLE_CELL.x, VEHICLE_CELL.y), VEHICLE_PX)
		node.flip_h = rd.axis == "v"
		m.v = dir * randf_range(5.0, 8.0) * (0.6 if kv == 3 else 1.0)
		m.y = VEHICLE_CELL.y / 2.0 * VEHICLE_PX - 0.1
		cars.append(m)
	else:
		m.a = randi() % 7
		node = sprite("walk", Rect2(PERSON.x, m.a * PERSON.y, PERSON.x, PERSON.y), PERSON_PX)
		node.flip_h = dir < 0 if rd.axis == "h" else dir > 0
		node.add_child(shadow())
		m.v = dir * randf_range(1.4, 2.4)
		m.y = 0.82
		m.step = randf() * 4.0
		walkers.append(m)
	m.node = node
	street.add_child(node)
	place(m)


func place(m: Dictionary) -> void:
	m.node.position = Vector3(m.s, m.y, m.line) if m.axis == "h" else Vector3(m.line, m.y, m.s)


func clear_street() -> void:
	for o in walkers + cars:
		o.node.queue_free()
	walkers.clear()
	cars.clear()
	for k in 40:
		spawn_mover(false, true)
	for k in 10:
		spawn_mover(true, true)


## Advances a walker's or customer's walk cycle; speed 0 shows the standing frame.
func stride(p: Dictionary, speed: float, delta: float) -> void:
	var col := 0
	if speed > 0.0:
		p.step += delta * minf(speed * STRIDE, MAX_FPS)
		col = 1 + int(p.step) % 4
	p.node.region_rect = Rect2(col * PERSON.x, p.a * PERSON.y, PERSON.x, PERSON.y)


func shadow() -> MeshInstance3D:
	if shadow_mesh == null:
		shadow_mesh = CylinderMesh.new()
		shadow_mesh.top_radius = 0.34
		shadow_mesh.bottom_radius = 0.34
		shadow_mesh.height = 0.01
		shadow_mesh.material = mat(Color(0, 0, 0, 0.22))
	var sh := MeshInstance3D.new()
	sh.mesh = shadow_mesh
	sh.position = Vector3(0, -0.8, 0)
	return sh


## Walkers and traffic round the view; busier at rush hours while a day plays.
func street_life(delta: float) -> void:
	var busy := 1.0
	if playing:
		busy = 0.35 + Sim.BLOCK_W[mini(5, int(progress() * 6.0))] / 3.0
	next_walker -= delta * busy
	if next_walker <= 0.0 and walkers.size() < MAX_WALKERS:
		spawn_mover(false)
		next_walker = randf_range(0.15, 0.5)
	next_car -= delta * busy
	if next_car <= 0.0 and cars.size() < MAX_CARS:
		spawn_mover(true)
		next_car = randf_range(0.6, 1.6)
	for wk in walkers:
		wk.s += wk.v * delta
		place(wk)
		stride(wk, absf(wk.v), delta)
	for c in cars:
		c.s += c.v * delta
		place(c)
	move_trains(delta)
	var live := func(o): return o.s > o.lo and o.s < o.hi
	for o in walkers + cars:
		if not live.call(o):
			o.node.queue_free()
	walkers = walkers.filter(live)
	cars = cars.filter(live)


func speckle(colors: Array) -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, colors[0] if r.randf() < 0.55 else colors[r.randi() % colors.size()])
	return ImageTexture.create_from_image(img)


## Shelves, counter and decorations from store.objects; the carried object is drawn at the hovered cell.
func build_props() -> void:
	for c in props.get_children():
		c.free()
	shelf_sprites.clear()
	var L: Dictionary = LAYOUT[kind]
	var objs: Array = store.objects
	var shown := objs.duplicate(true)
	ghost_cells = []
	if edit and not carry.is_empty() and hover != Sim.NO_CELL:
		if carry.has("new"):
			shown.append({"type": "decor", "id": carry.new, "cell": hover})
			ghost_ok = Sim.placement_ok(store, -1, hover, {"type": "decor", "id": carry.new})
		else:
			shown[carry.idx].cell = hover
			ghost_ok = Sim.placement_ok(store, carry.idx, hover)
		ghost_cells = Sim.cells_of(shown[-1] if carry.has("new") else shown[carry.idx])
	for o in shown:
		var c: Vector2i = o.cell
		match o.type:
			"gondola":
				var gh: float = L.gh
				var x := c.x + 1.0
				var z := c.y + 0.5
				block(props, Vector3(1.9, gh, 0.8), Vector3(x, gh / 2, z), Color("e9e4d6"))
				block(props, Vector3(2.0, 0.12, 0.9), Vector3(x, gh + 0.06, z), Color("3b3f52"))
				block(props, Vector3(2.0, 0.14, 0.9), Vector3(x, 0.07, z), Color("3b3f52"))
				for ry in L.rows:
					block(props, Vector3(1.9, 0.05, 0.92), Vector3(x, ry - 0.03, z + 0.03), Color("8d8a80"))
					var row := []
					for k in 3:
						var s := sprite("products", Rect2(0, 0, ITEM, ITEM), ITEM_PX, false)
						s.position = Vector3(x - 0.58 + k * 0.58, ry + 0.22, z + 0.42)
						props.add_child(s)
						row.append(s)
					shelf_sprites.append(row)
			"counter":
				var x := c.x + 1.5
				var z := c.y + 0.5
				block(props, Vector3(2.9, 1.05, 0.85), Vector3(x, 0.525, z), Color("f3ecdc"))
				block(props, Vector3(2.92, 0.1, 0.87), Vector3(x, 0.62, z), L.stripe[0])
				block(props, Vector3(2.92, 0.1, 0.87), Vector3(x, 0.45, z), L.stripe[1])
				block(props, Vector3(0.5, 0.35, 0.4), Vector3(x + 1.0, 1.22, z - 0.1), Color("3b3f52"))
				for dx in L.clerks:
					var cl := sprite("people", Rect2(7 * PERSON.x, 0, PERSON.x, PERSON.y), PERSON_PX)
					cl.flip_h = true
					cl.position = Vector3(x + dx, 0.82, z - 0.75)
					props.add_child(cl)
			"decor":
				var d := sprite("decor", Rect2(o.id * DECOR, 0, DECOR, DECOR), DECOR_PX)
				d.position = Vector3(c.x + 0.5, DECOR / 2.0 * DECOR_PX, c.y + 0.5)
				props.add_child(d)
	refresh_shelves()


func refresh_shelves() -> void:
	for i in shelf_sprites.size():
		var s: Dictionary = store.slots[i] if i < store.slots.size() else {"pid": -1, "qty": 0}
		var q := shown_qty(i) if s.pid >= 0 else 0
		var n := mini(3, ceili(q / 10.0))
		for k in 3:
			var sp: Sprite3D = shelf_sprites[i][k]
			sp.visible = s.pid >= 0 and (k < n or (q == 0 and k == 1))
			if s.pid >= 0:
				sp.region_rect = Rect2(s.pid * ITEM, 0, ITEM, ITEM)
				sp.modulate = Color(0.45, 0.45, 0.5) if q == 0 else Color.WHITE


func show_store(st: Dictionary, index: int) -> void:
	var moved: bool = st.get("lot", -1) != store.get("lot", -2)
	store = st
	si = index
	stock0 = []
	playing = false
	carry = {}
	clear_people()
	floaters.clear()
	if st.kind != kind:
		kind = st.kind
		build_room()
	site.position = Sim.store_origin(sim.lots[st.lot], kind)
	build_props()
	refresh_city(moved)


## Rebuilds the city if lots changed hands; reframes the camera when the focused shop moved.
func refresh_city(reframe := false) -> void:
	var sig := city_signature()
	if sig != city_sig:
		city_sig = sig
		build_city()
		clear_street()
	if reframe:
		cam_offset = Vector3.ZERO
		zoom = 1.0
	update_camera()
	update_fade()


func set_edit(on: bool) -> void:
	edit = on
	carry = {}
	build_props()
	overlay.queue_redraw()


# ---------- arranging ----------

## Sizes the 3D render to the real pixels this view covers (the UI itself is laid out at 960x540).
func fit_viewport() -> void:
	var win := Vector2(get_window().size)
	vp_scale = clampf(minf(win.x / 960.0, win.y / 540.0), 1.0, 3.0)
	vp.size = Vector2i((size * vp_scale).round())
	overlay.queue_redraw()


## Shop-local point to this control's coordinates.
func screen(p: Vector3) -> Vector2:
	return cam.unproject_position(p + site.position) / vp_scale


func screen_world(p: Vector3) -> Vector2:
	return cam.unproject_position(p) / vp_scale


## Where the click ray meets the ground, in world coordinates.
func ground_at(pos: Vector2) -> Vector3:
	var o := cam.project_ray_origin(pos * vp_scale)
	var d := cam.project_ray_normal(pos * vp_scale)
	if d.y > -0.001:
		return Vector3(INF, 0, INF)
	return o + d * (-o.y / d.y)


func cell_at(pos: Vector2) -> Vector2i:
	var p := ground_at(pos) - site.position
	if is_inf(p.x):
		return Sim.NO_CELL
	return Vector2i(floori(p.x), floori(p.z))


## Lot under the pointer, its sidewalk included.
func lot_at(pos: Vector2) -> int:
	var p := ground_at(pos)
	for li in sim.lots.size():
		var L: Dictionary = sim.lots[li]
		if Rect2(L.x0, L.front - Sim.LOT_D, Sim.LOT_W, Sim.LOT_D + 2.2).has_point(Vector2(p.x, p.z)):
			return li
	return -1


## Nearest object whose box the click ray passes through, else whatever stands on the clicked tile.
func object_under(pos: Vector2) -> int:
	var o := cam.project_ray_origin(pos * vp_scale) - site.position
	var d := cam.project_ray_normal(pos * vp_scale)
	var best := -1
	var best_dist := INF
	for i in store.objects.size():
		var ob: Dictionary = store.objects[i]
		var f: Vector2i = Sim.FOOT[ob.type]
		var h: float = {"gondola": LAYOUT[kind].gh, "counter": 1.2, "decor": 1.3}[ob.type]
		var hit = AABB(Vector3(ob.cell.x, 0, ob.cell.y), Vector3(f.x, h, f.y)).intersects_ray(o, d)
		if hit != null and o.distance_to(hit) < best_dist:
			best = i
			best_dist = o.distance_to(hit)
	return best if best >= 0 else Sim.object_at(store, cell_at(pos))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom = clampf(zoom * (0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.12 if mode == "city" else 0.55, 1.4 if mode == "city" else 6.0)
		update_camera()
		accept_event()
		return
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_MIDDLE or (not edit and e.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		var b := cam.global_transform.basis
		cam_offset += (-b.x * e.relative.x + b.y * e.relative.y) * cam.size / size.y
		cam_offset = cam_offset.limit_length(200.0 if mode == "city" else 40.0)
		update_camera()
		accept_event()
		return
	if mode == "city":
		if e is InputEventMouseMotion:
			var li := lot_at(e.position)
			if li != hover_lot:
				hover_lot = li
				overlay.queue_redraw()
		elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var li := lot_at(e.position)
			if li >= 0:
				lot_clicked.emit(li)
			accept_event()
		return
	if not edit:
		return
	if e is InputEventMouseMotion:
		var c := cell_at(e.position)
		var ho := object_under(e.position)
		if c != hover or ho != hover_obj:
			hover = c
			hover_obj = ho
			if not carry.is_empty():
				build_props()
			overlay.queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		hover = cell_at(e.position)
		if e.button_index == MOUSE_BUTTON_RIGHT:
			cancel_carry()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			click(object_under(e.position))
		accept_event()


func click(picked := -1) -> void:
	if carry.is_empty():
		if picked >= 0:
			carry = {"idx": picked}
	else:
		var ok: bool = sim.buy_decor(si, carry.new, hover) if carry.has("new") else sim.move_object(si, carry.idx, hover)
		if ok:
			carry = {}
	build_props()
	overlay.queue_redraw()
	changed.emit()


func carry_new(id: int) -> void:
	carry = {"new": id}
	build_props()
	changed.emit()


func cancel_carry() -> void:
	carry = {}
	build_props()
	changed.emit()


func sell_carried() -> void:
	if carry.has("idx") and store.objects[carry.idx].type == "decor":
		sim.sell_decor(si, carry.idx)
	cancel_carry()


func carried_type() -> String:
	if carry.has("new"):
		return "new"
	return store.objects[carry.idx].type if carry.has("idx") else ""


# ---------- replay ----------

func play(events: Array, pre_stock: Array, post_stock: Array) -> void:
	stock0 = pre_stock
	stock1 = post_stock
	t = 0.0
	clear_people()
	floaters.clear()
	nav_grid = Sim.nav(store)
	var step := maxi(1, ceili(events.size() / float(MAX_SHOWN)))
	queue = []
	for i in range(0, events.size(), step):
		queue.append(events[i])
	playing = true


func skip() -> void:
	if playing:
		playing = false
		clear_people()
		queue.clear()
		stock0 = []
		refresh_shelves()
		overlay.queue_redraw()
		finished.emit()


func clear_people() -> void:
	for p in people:
		p.node.queue_free()
	people.clear()


func world(c: Vector2i, jitter := 0.0) -> Vector2:
	return Vector2(c.x + 0.5 + randf_range(-jitter, jitter), c.y + 0.5 + randf_range(-jitter, jitter))


## Appends a walk along the grid path from a to b; the last point waits `wait` seconds showing `bub`.
func walk(path: Array, a: Vector2i, b: Vector2i, wait: float, bub: String) -> void:
	var cells := nav_grid.get_id_path(a, b)
	for i in range(1, cells.size()):
		var last := i == cells.size() - 1
		path.append([world(cells[i], 0.25 if last else 0.12), wait if last else 0.0, bub if last else ""])


func spawn(cu: Dictionary) -> void:
	var g: Vector2i = Sim.GRID[kind]
	var entry := Sim.entry_cell(kind)
	var exit := Sim.exit_cell(kind)
	var walk_z := lot.y + WALK_NEAR + randf_range(-0.4, 0.4)
	var start := Vector2(-6.0 if randf() < 0.5 else lot.x + 12.0, walk_z)
	var path := [[Vector2(entry.x + 0.5, walk_z), 0.0, ""], [world(entry), 0.0, ""]]
	var gondolas: Array = store.objects.filter(func(o): return o.type == "gondola")
	var counter: Dictionary = store.objects.filter(func(o): return o.type == "counter")[0]
	var here := entry
	if cu.walkout:
		var c := Vector2i(entry.x + 1, g.y - 1)
		if nav_grid.is_point_solid(c):
			c = entry
		walk(path, entry, c, 0.9, "queue")
		here = c
	else:
		var gi: int = cu.slot / Sim.STORE[kind].rows if cu.slot >= 0 else randi() % gondolas.size()
		var at := Sim.access(store, nav_grid, gondolas[gi])
		if at != Sim.NO_CELL:
			walk(path, here, at, 0.6, "buy" if cu.buy.size() else ("miss" if cu.miss.size() else ""))
			here = at
		var pay := Sim.access(store, nav_grid, counter)
		if cu.spent > 0 and pay != Sim.NO_CELL:
			walk(path, here, pay, 0.45, "pay")
			here = pay
	walk(path, here, exit, 0.0, "")
	path.append([Vector2(exit.x + 0.5, walk_z), 0.0, ""])
	path.append([Vector2(-8.0 if randf() < 0.5 else lot.x + 14.0, walk_z), 0.0, ""])
	var node := sprite("walk", Rect2(PERSON.x, cu.a * PERSON.y, PERSON.x, PERSON.y), PERSON_PX)
	node.add_child(shadow())
	actors.add_child(node)
	people.append({"cu": cu, "a": cu.a, "pos": start, "path": path, "wait": -1.0, "step": randf() * 4.0, "node": node})


func _process(delta: float) -> void:
	if paused or kind == "" or city_sig == "":
		return
	street_life(delta)
	if not playing:
		return
	t += delta
	while queue.size() and queue[0].t * DUR * PACE <= t:
		spawn(queue.pop_front())
	for p in people:
		var step: Array = p.path[0]
		if p.wait >= 0.0:
			p.wait -= delta
			if p.wait < 0.0:
				p.path.pop_front()
			continue
		var target: Vector2 = step[0]
		var d: Vector2 = target - p.pos
		if absf(d.x) > 0.05:
			p.node.flip_h = d.x < 0
		var outside: bool = p.pos.y > lot.y - 0.5 and target.y > lot.y - 0.5
		var v := SPEED * (2.0 if outside else 1.0)
		if d.length() <= v * delta:
			p.pos = target
			p.wait = step[1]
			if step[2] == "pay":
				floaters.append({"text": "+¥" + Sim.money(p.cu.spent), "at": Vector3(p.pos.x, 2.0, p.pos.y), "life": 1.2})
			if step[1] <= 0.0:
				p.path.pop_front()
				p.wait = -1.0
		else:
			p.pos += d.normalized() * v * delta
		stride(p, 0.0 if p.wait >= 0.0 else v, delta)
		p.node.position = Vector3(p.pos.x, 0.82, p.pos.y)
	for p in people:
		if p.path.is_empty():
			p.node.queue_free()
	people = people.filter(func(p): return p.path.size() > 0)
	for f in floaters:
		f.at.y += 0.6 * delta
		f.life -= delta
	floaters = floaters.filter(func(f): return f.life > 0.0)
	refresh_shelves()
	if queue.is_empty() and people.is_empty() and t > 1.0:
		playing = false
		stock0 = []
		refresh_shelves()
		finished.emit()
	overlay.queue_redraw()


func progress() -> float:
	return clampf(t / (DUR * PACE), 0.0, 1.0) if playing else 0.0


func shown_qty(i: int) -> int:
	if stock0.is_empty():
		return store.slots[i].qty
	return roundi(lerpf(stock0[i], stock1[i], progress()))


# ---------- 2D overlay ----------

func draw_overlay() -> void:
	var font := get_theme_default_font()
	if sim and not sim.lots.is_empty():
		draw_city_marks(font)
	if mode == "city":
		return
	if edit:
		var g: Vector2i = Sim.GRID[kind]
		var line := Color(0.17, 0.18, 0.26, 0.3)
		for x in g.x + 1:
			overlay.draw_line(screen(Vector3(x, 0, 0)), screen(Vector3(x, 0, g.y)), line)
		for z in g.y + 1:
			overlay.draw_line(screen(Vector3(0, 0, z)), screen(Vector3(g.x, 0, z)), line)
		for c in ghost_cells:
			var quad := PackedVector2Array()
			for k in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]:
				quad.append(screen(Vector3(c.x, 0.02, c.y) + k))
			overlay.draw_colored_polygon(quad, Color(0.18, 0.75, 0.38, 0.45) if ghost_ok else Color(0.9, 0.2, 0.2, 0.5))
		if carry.is_empty() and hover_obj >= 0 and hover_obj < store.objects.size():
			var oc: Vector2i = store.objects[hover_obj].cell
			var at := screen(Vector3(oc.x + 0.5 * Sim.FOOT[store.objects[hover_obj].type].x, 0, oc.y + 1.0))
			overlay.draw_string_outline(font, at + Vector2(-40, 18), "PICK UP", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, 4, Color("2b2d42"))
			overlay.draw_string(font, at + Vector2(-40, 18), "PICK UP", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color.WHITE)
		return
	for p in people:
		if p.wait >= 0.0:
			bubble(p, screen(Vector3(p.pos.x, 1.75, p.pos.y)), font)
	for f in floaters:
		var at := screen(f.at)
		overlay.draw_string_outline(font, at + Vector2(-30, 0), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.WHITE)
		overlay.draw_string(font, at + Vector2(-30, 0), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("2f9e5b"))
	var hour := 6.0 + progress() * 24.0
	var night := clampf((hour - 18.0) / 4.0, 0.0, 1.0) * (1.0 - clampf((hour - 28.0) / 2.0, 0.0, 1.0))
	if night > 0.0:
		overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.25, 0.38 * night))
	if playing:
		var clock := "%02d:00  %s" % [int(hour) % 24, Sim.BLOCKS[mini(5, int(progress() * 6.0))]]
		overlay.draw_rect(Rect2(8, 8, 150, 24), Color(0.17, 0.18, 0.26, 0.85))
		overlay.draw_string(font, Vector2(16, 26), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func lot_poly(li: int) -> PackedVector2Array:
	var L: Dictionary = sim.lots[li]
	var out := PackedVector2Array()
	for k in [Vector2(0, -Sim.LOT_D), Vector2(Sim.LOT_W, -Sim.LOT_D), Vector2(Sim.LOT_W, 0), Vector2(0, 0)]:
		out.append(screen_world(Vector3(L.x0 + k.x, 0, L.front + k.y)))
	out.append(out[0])
	return out


## Chain-coloured pins over stores, district names, and in city mode the lots you can pick.
func draw_city_marks(font: Font) -> void:
	var city_view := mode == "city"
	if city_view:
		for d in sim.districts:
			var at := screen_world(Vector3(sim.block_center(d).x, 0, sim.block_center(d).y - 4.0))
			var nm: String = d.name.to_upper()
			overlay.draw_string_outline(font, at + Vector2(-60, 0), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, 4, Color(0.17, 0.18, 0.26, 0.8))
			overlay.draw_string(font, at + Vector2(-60, 0), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color("f7f3e8"))
		for li in sim.lots.size():
			var L: Dictionary = sim.lots[li]
			var mark := Color(0, 0, 0, 0)
			if pick == "branch" and L.use == "free":
				mark = Color("3fae49")
			elif pick == "buyout" and not sim.rival_at(li).is_empty():
				mark = Color("f08a24")
			elif pick == "" and L.use == "free":
				mark = Color(1, 1, 1, 0.5)
			if li == hover_lot:
				mark = Color.WHITE
			if mark.a > 0.0:
				overlay.draw_polyline(lot_poly(li), mark, 2.0)
	var stores: Array = sim.open_stores()
	for e in stores:
		var st: Dictionary = e[0]
		if not city_view and st == store:
			continue
		var p2: Vector2 = Sim.lot_pos(sim.lots[st.lot])
		var at := screen_world(Vector3(p2.x + 2.0, 7.0 if not city_view else 4.0, p2.y + 3.0))
		if not Rect2(Vector2.ZERO, size).grow(20).has_point(at):
			continue
		var c := Color(Sim.CHAINS[e[1]].color)
		var label: String = "YOU" if e[1] == 0 else Sim.CHAINS[e[1]].name
		if not city_view or e[1] == 0:
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10
			overlay.draw_rect(Rect2(at + Vector2(-w / 2, -9), Vector2(w, 16)), c)
			overlay.draw_string(font, at + Vector2(-w / 2 + 5, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
			if e[1] != 0 and st.get("war", 0) > 0:
				overlay.draw_string_outline(font, at + Vector2(-w / 2, -12), "PRICE WAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color.WHITE)
				overlay.draw_string(font, at + Vector2(-w / 2, -12), "PRICE WAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("d64545"))
		else:
			overlay.draw_circle(at, 5.0, Color.WHITE)
			overlay.draw_circle(at, 3.8, c)


func bubble(p: Dictionary, head: Vector2, font: Font) -> void:
	var kind_b: String = p.path[0][2]
	if kind_b == "" or kind_b == "pay":
		return
	var r := Rect2(head + Vector2(-20, -44), Vector2(40, 38))
	var edge := Color("2f9e5b") if kind_b == "buy" else Color("d64545")
	overlay.draw_rect(r, Color.WHITE)
	overlay.draw_rect(r, edge, false, 2.0)
	if kind_b == "queue":
		overlay.draw_string(font, r.position + Vector2(8, 26), "...", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, edge)
		return
	var pid: int = p.cu.buy[0] if kind_b == "buy" else p.cu.miss[0]
	overlay.draw_texture_rect_region(tex.products, Rect2(r.position + Vector2(4, 3), Vector2(32, 32)), Rect2(pid * ITEM, 0, ITEM, ITEM), Color(1, 1, 1, 1.0 if kind_b == "buy" else 0.55))
	if kind_b == "miss":
		overlay.draw_string_outline(font, r.position + Vector2(26, 34), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.WHITE)
		overlay.draw_string(font, r.position + Vector2(26, 34), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, edge)
