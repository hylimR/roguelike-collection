extends Control
## 2.5D store stage: a small 3D room (Codex back-wall art, tiled floor, box shelves) under a tilted camera,
## pixel sprites as billboards. Replays a simulated day's customers along AStarGrid2D paths, and in arrange
## mode lets the player pick up, move, buy and place objects on the floor grid. Bubbles draw on a 2D overlay.

signal finished
signal changed

const Sim := preload("res://sim.gd")
const DUR := 10.0
const PACE := 0.7  # share of DUR over which the day's customers arrive
const SPEED := 3.6
const MAX_SHOWN := 20
const PERSON_PX := 0.034
const ITEM_PX := 0.014
const DECOR_PX := 0.028
# wall = crop of the side-view background used as the back wall texture
const LAYOUT := {
	"konbini": {"bg": "bg_konbini", "wall": Rect2i(0, 18, 272, 106), "rows": [0.42, 1.0], "gh": 1.42, "clerks": [0.0], "floor": [Color("ead9b8"), Color("cbb48e")], "stripe": [Color("f05a28"), Color("1f9d55")]},
	"super": {"bg": "bg_super", "wall": Rect2i(0, 10, 268, 112), "rows": [0.34, 0.84, 1.34], "gh": 1.8, "clerks": [-0.8, 0.8], "floor": [Color("efe3c8"), Color("d2c3a3")], "stripe": [Color("1f9d55"), Color("1f9d55")]},
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
var nav_grid: AStarGrid2D
var ghost_cells: Array = []
var ghost_ok := true

var cam: Camera3D
var room: Node3D
var props: Node3D
var actors: Node3D
var overlay: Control


func _ready() -> void:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	box.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b2d42")
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	cam = Camera3D.new()
	cam.fov = 38.0
	vp.add_child(cam)
	room = Node3D.new()
	vp.add_child(room)
	props = Node3D.new()
	vp.add_child(props)
	actors = Node3D.new()
	vp.add_child(actors)
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
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
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
	var crop: Image = tex[L.bg].get_image().get_region(L.wall)
	var h: float = w * crop.get_height() / crop.get_width()
	var wall := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	wall.mesh = q
	wall.material_override = mat(Color.WHITE, ImageTexture.create_from_image(crop))
	wall.position = Vector3(w / 2, h / 2, 0)
	room.add_child(wall)
	var depth := g.y + 1.0
	var fm := mat(Color.WHITE, tiles(L.floor[0], L.floor[1]))
	fm.uv1_scale = Vector3(w, depth, 1)
	fm.texture_repeat = true
	plane(room, Vector2(w, depth), Vector3(w / 2, 0, depth / 2), fm)
	plane(room, Vector2(w + 12, 8), Vector3(w / 2, -0.01, depth + 4), mat(Color("8e8a86")))
	block(room, Vector3(0.3, h, depth), Vector3(-0.15, h / 2, depth / 2), Color("d9cfb8"))
	block(room, Vector3(0.3, h, depth), Vector3(w + 0.15, h / 2, depth / 2), Color("d9cfb8"))
	cam.position = Vector3(w / 2, w * 0.43, g.y + w * 0.6)
	cam.look_at(Vector3(w / 2, h * 0.24, g.y * 0.45))


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
						var s := sprite("products", Rect2(0, 0, 32, 32), ITEM_PX, false)
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
					var cl := sprite("people", Rect2(7 * 36, 0, 36, 48), PERSON_PX)
					cl.flip_h = true
					cl.position = Vector3(x + dx, 0.82, z - 0.75)
					props.add_child(cl)
			"decor":
				var d := sprite("decor", Rect2(o.id * 48, 0, 48, 48), DECOR_PX)
				d.position = Vector3(c.x + 0.5, 24 * DECOR_PX, c.y + 0.5)
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
				sp.region_rect = Rect2(s.pid * 32, 0, 32, 32)
				sp.modulate = Color(0.45, 0.45, 0.5) if q == 0 else Color.WHITE


func show_store(st: Dictionary, index: int) -> void:
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
	build_props()
	overlay.queue_redraw()


func set_edit(on: bool) -> void:
	edit = on
	carry = {}
	build_props()
	overlay.queue_redraw()


# ---------- arranging ----------

func cell_at(pos: Vector2) -> Vector2i:
	var o := cam.project_ray_origin(pos)
	var d := cam.project_ray_normal(pos)
	if d.y > -0.001:
		return Sim.NO_CELL
	var p := o + d * (-o.y / d.y)
	return Vector2i(floori(p.x), floori(p.z))


func _gui_input(e: InputEvent) -> void:
	if not edit:
		return
	if e is InputEventMouseMotion:
		var c := cell_at(e.position)
		if c != hover:
			hover = c
			if not carry.is_empty():
				build_props()
			overlay.queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		hover = cell_at(e.position)
		if e.button_index == MOUSE_BUTTON_RIGHT:
			cancel_carry()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			click()
		accept_event()


func click() -> void:
	if carry.is_empty():
		var idx := Sim.object_at(store, hover)
		if idx >= 0:
			carry = {"idx": idx}
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
	var start := Vector2(entry.x + 0.5, g.y + 3.0)
	var path := [[world(entry), 0.0, ""]]
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
	path.append([Vector2(exit.x + 0.5, g.y + 3.0), 0.0, ""])
	var node := sprite("people", Rect2(cu.a * 36, 0, 36, 48), PERSON_PX)
	var shadow := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.34
	cyl.bottom_radius = 0.34
	cyl.height = 0.01
	shadow.mesh = cyl
	shadow.material_override = mat(Color(0, 0, 0, 0.22))
	shadow.position = Vector3(0, -0.8, 0)
	node.add_child(shadow)
	actors.add_child(node)
	people.append({"cu": cu, "pos": start, "path": path, "wait": -1.0, "bob": randf() * 6.0, "node": node})


func _process(delta: float) -> void:
	if not playing or paused:
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
		var v := SPEED * (1.5 if p.path.size() <= 3 else 1.0)
		p.bob += delta * 12.0
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
		var bob := 0.0 if p.wait >= 0.0 else absf(sin(p.bob)) * 0.06
		p.node.position = Vector3(p.pos.x, 0.82 + bob, p.pos.y)
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
	if edit:
		var g: Vector2i = Sim.GRID[kind]
		var line := Color(0.17, 0.18, 0.26, 0.3)
		for x in g.x + 1:
			overlay.draw_line(cam.unproject_position(Vector3(x, 0, 0)), cam.unproject_position(Vector3(x, 0, g.y)), line)
		for z in g.y + 1:
			overlay.draw_line(cam.unproject_position(Vector3(0, 0, z)), cam.unproject_position(Vector3(g.x, 0, z)), line)
		for c in ghost_cells:
			var quad := PackedVector2Array()
			for k in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)]:
				quad.append(cam.unproject_position(Vector3(c.x, 0.02, c.y) + k))
			overlay.draw_colored_polygon(quad, Color(0.18, 0.75, 0.38, 0.45) if ghost_ok else Color(0.9, 0.2, 0.2, 0.5))
		if carry.is_empty() and Sim.object_at(store, hover) >= 0:
			var at := cam.unproject_position(Vector3(hover.x + 0.5, 0, hover.y + 0.5))
			overlay.draw_string_outline(font, at + Vector2(-40, 18), "PICK UP", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, 4, Color("2b2d42"))
			overlay.draw_string(font, at + Vector2(-40, 18), "PICK UP", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color.WHITE)
		return
	for p in people:
		if p.wait >= 0.0:
			bubble(p, cam.unproject_position(Vector3(p.pos.x, 1.75, p.pos.y)), font)
	for f in floaters:
		var at := cam.unproject_position(f.at)
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
	overlay.draw_texture_rect_region(tex.products, Rect2(r.position + Vector2(4, 3), Vector2(32, 32)), Rect2(pid * 32, 0, 32, 32), Color(1, 1, 1, 1.0 if kind_b == "buy" else 0.55))
	if kind_b == "miss":
		overlay.draw_string_outline(font, r.position + Vector2(26, 34), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.WHITE)
		overlay.draw_string(font, r.position + Vector2(26, 34), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, edge)
