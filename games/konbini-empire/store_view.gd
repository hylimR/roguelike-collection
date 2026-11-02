extends Control
## The city stage: Tokyo (city.gd) as a city builder sees it, through an orthographic isometric camera. Streets,
## avenues, the elevated expressway and the Yamanote are generated meshes; buildings are boxes in one MultiMesh
## with a pixel facade shader; trees, landmarks, rival storefronts, cars and people are Codex sprites. Your
## focused shop is a cutaway interior on its own lot, with the city cut away in front of it. Replays a day's
## customers along AStarGrid2D paths, lets you arrange the shop, and in city mode pick lots. Bubbles, pins and
## labels draw on a 2D overlay. Shop-local nodes live under `site` at the shop's origin.

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
const TRAIN_SPEED := 14.0
const LANDMARK_PX := 0.085
const WALK_NEAR := 1.2  # customers' sidewalk line in front of the shop
const MAX_WALKERS := 70
const MAX_CARS := 70
const PITCH := 30.0
const SUN := Vector3(-0.35, 1.0, 0.6)  # towards the sun; the building shader lights its faces from here too
const SHADOW_RES := 4096
# Ground shadows: a mask rendered from the sun (buildings white on clear), looked up per ground point.
const SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
uniform sampler2D mask : filter_linear;
uniform mat4 light_vp;
uniform float strength;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = light_vp * vec4(wpos, 1.0);
	ALBEDO = vec3(0.08, 0.1, 0.2);
	ALPHA = texture(mask, vec2(c.x, -c.y) * 0.5 + 0.5).a * strength;
}
"""
# Buildings: boxes in a MultiMesh. Custom data = size and facade style (-1: plain shaded colour, for roofs); colour =
# wall tint, alpha = accent index / 8. Walls pick a 3-unit bay and floor tile from the facade atlas.
const BUILDING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D facades : filter_nearest_mipmap;
uniform sampler2D accents : filter_nearest_mipmap;
uniform float styles = 10.0;
uniform float night = 0.0;
varying vec3 lpos;
varying vec3 lnrm;
varying vec4 info;
varying vec4 tint;
const vec3 ACCENT[8] = vec3[8](vec3(0.89, 0.25, 0.22), vec3(0.96, 0.56, 0.16), vec3(0.98, 0.82, 0.25), vec3(0.24, 0.68, 0.36), vec3(0.22, 0.5, 0.86), vec3(0.6, 0.34, 0.8), vec3(0.95, 0.45, 0.65), vec3(0.2, 0.72, 0.74));
const vec3 ROOF[8] = vec3[8](vec3(0.62, 0.62, 0.6), vec3(0.72, 0.72, 0.7), vec3(0.62, 0.4, 0.32), vec3(0.47, 0.6, 0.38), vec3(0.46, 0.53, 0.6), vec3(0.6, 0.56, 0.5), vec3(0.44, 0.45, 0.48), vec3(0.7, 0.65, 0.53));

void vertex() {
	info = INSTANCE_CUSTOM;
	tint = COLOR;
	lnrm = NORMAL;
	lpos = (VERTEX + 0.5) * INSTANCE_CUSTOM.xyz;
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float shade = 0.6 + 0.4 * max(dot(n, normalize(vec3(-0.35, 1.0, 0.6))), 0.0);
	vec3 col = tint.rgb;
	vec3 glow = vec3(0.0);
	if (info.w > -0.5) {
		float style = floor(info.w);
		float seed = fract(info.w) * 2.0;
		int pick = int(tint.a * 8.0) % 8;
		if (lnrm.y > 0.5) {
			vec2 e = min(lpos.xz, info.xz - lpos.xz);
			col = mix(ROOF[pick], tint.rgb, 0.15) * (min(e.x, e.y) < 0.35 ? 1.12 : 0.92);
		} else {
			bool front = abs(lnrm.z) > 0.5;
			float width = front ? info.x : info.z;
			float bays = max(1.0, floor(width / 3.0 + 0.5));
			vec2 cont = vec2((front ? lpos.x : lpos.z) / width * bays, lpos.y / 3.0);
			float row = cont.y < 1.0 ? 0.0 : 1.0;
			vec2 uv = vec2((style + fract(cont.x)) / styles, (row + 1.0 - fract(cont.y)) / 2.0);
			vec2 gx = dFdx(cont) / vec2(styles, 2.0);
			vec2 gy = dFdy(cont) / vec2(styles, 2.0);
			vec4 t = textureGrad(facades, uv, gx, gy);
			vec4 m = textureGrad(accents, uv, gx, gy);
			col = mix(mix(t.rgb, t.rgb * tint.rgb, t.a), ACCENT[pick] * t.r, m.r);
			// after dark about half the windows light up, each its own, and signs keep shining
			vec2 cell = floor(cont) + vec2(lnrm.x * 7.0 + lnrm.z * 3.0, seed * 91.0);
			float r = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
			vec3 lamp = r > 0.85 ? vec3(0.78, 0.86, 1.0) : vec3(1.0, 0.8, 0.48);
			glow = (m.g * step(0.6, r) * lamp + m.r * ACCENT[pick] * 0.9) * night;
		}
		col *= mix(0.72, 1.0, clamp(lpos.y / 1.2, 0.0, 1.0));
	}
	ALBEDO = col * shade * (1.0 - 0.62 * night) + glow;
}
"""
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
var lm_sprites: Array = []  # [Sprite3D, half width]: landmarks, faded when they cover the shop
var lot_sprites: Array = []  # the same for storefronts on lots
var hover_lot := -1
var pick := ""  # city mode: "" | branch | buyout
var site: Node3D
var city: Node3D
var lots_node: Node3D
var C: Dictionary  # the City map
var trains: Array = []  # movers on the Yamanote
var paths: Array = []  # every road as a path for movers: {pts, cum, w, kind, closed, box}
var rail_path: Dictionary
var elevated: Array = []  # [MeshInstance3D, a, b]: deck pieces, hidden when they would cover the focused shop
var brecs: Array = []  # per building: {foot, h, box: [instance], roof: instance or -1, hidden}
var box_mm: MultiMesh
var box_base: Array = []
var building_mat: ShaderMaterial
var roof_mm: MultiMesh
var roof_base: Array = []
var pillar_mm: MultiMesh
var pillar_base: Array = []
var tree_mms: Array = []  # [MultiMesh, base transforms, height]
var mask_vp: SubViewport  # the city seen from the sun, for ground shadows
var shadow_mesh: CylinderMesh
var cam_target := Vector3.ZERO
var cam_offset := Vector3.ZERO
var cam_base := 12.0
var zoom := 1.0
var yaw := PI / 4

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
	lots_node = Node3D.new()
	vp.add_child(lots_node)
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
	m.texture_repeat = texture != null
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	yaw = PI / 4  # the shop cutaway is drawn for this angle
	pick = "" if m == "store" else pick
	update_camera()
	update_fade()


func update_camera() -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var target: Vector3
	if mode == "city":
		var b: Rect2 = sim.city_bounds()
		target = Vector3(b.get_center().x, 0, b.get_center().y)
		cam.size = (b.size.x + b.size.y) * 0.32 * zoom
	else:
		target = site.position + Vector3(lot.x / 2 + 0.3, 0.9, lot.y / 2 + 0.8)
		cam.size = (lot.x + lot.y) * 0.6 * zoom
	var pitch := deg_to_rad(PITCH)
	target += cam_offset
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 400.0
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


func city_sprite(parent: Node3D, sheet: String, region: Rect2, px: float, at: Vector3, list: Array) -> Sprite3D:
	var s := sprite(sheet, region, px)
	s.position = at + Vector3(0, region.size.y / 2.0 * px - 0.1, 0)
	parent.add_child(s)
	list.append([s, region.size.x / 2.0 * px])
	return s


func surface(m: Material) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(m)
	return st


func commit(sts: Array, parent: Node3D) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for st in sts:
		st.commit(mesh)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func add_quad(st: SurfaceTool, v: Array, uv: Array) -> void:
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(v[i])


## A flat rectangle at height y; u_reps > 0 tiles a stripe texture along x (or along z when along_z).
func rect_quad(st: SurfaceTool, r: Rect2, y: float, u_reps := 0.0, along_z := false, world_uv := 0.0) -> void:
	var v := [Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y)]
	var uv := [Vector2(0, 0), Vector2(u_reps, 0), Vector2(u_reps, 1), Vector2(0, 1)]
	if along_z:
		uv = [Vector2(0, 0), Vector2(0, 1), Vector2(u_reps, 1), Vector2(u_reps, 0)]
	if world_uv > 0.0:
		uv = v.map(func(p): return Vector2(p.x, p.z) * world_uv)
	add_quad(st, v, uv)


func poly_fill(st: SurfaceTool, poly: PackedVector2Array, y: float, uv_scale := 0.125) -> void:
	for i in Geometry2D.triangulate_polygon(poly):
		st.set_uv(poly[i] * uv_scale)
		st.add_vertex(Vector3(poly[i].x, y, poly[i].y))


static func left_of(pts: PackedVector3Array, i: int) -> Vector3:
	var tg := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
	var t2 := Vector2(tg.x, tg.z).normalized()
	return Vector3(t2.y, 0, -t2.x)


## A strip along pts between lateral offsets a and b (left of the points' direction is positive), dy above each
## point; u runs along the strip at u_scale per unit. Only segments first..last-1 are emitted.
func ribbon(st: SurfaceTool, pts: PackedVector3Array, a: float, b: float, dy := 0.0, u_scale := 0.0, first := 0, last := -1) -> void:
	last = pts.size() - 1 if last < 0 else last
	var u := 0.0
	for i in range(first, last):
		var l0 := left_of(pts, i)
		var l1 := left_of(pts, i + 1)
		var up := Vector3(0, dy, 0)
		var u1 := u + pts[i].distance_to(pts[i + 1]) * u_scale
		add_quad(st, [pts[i] + l0 * a + up, pts[i + 1] + l1 * a + up, pts[i + 1] + l1 * b + up, pts[i] + l0 * b + up], [Vector2(u, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u, 1)])
		u = u1


## A vertical band at lateral offset off, from y0 to y1 above the points (parapets, railings, fascias).
func wall(st: SurfaceTool, pts: PackedVector3Array, off: float, y0: float, y1: float, first := 0, last := -1) -> void:
	last = pts.size() - 1 if last < 0 else last
	for i in range(first, last):
		var p0 := pts[i] + left_of(pts, i) * off
		var p1 := pts[i + 1] + left_of(pts, i + 1) * off
		add_quad(st, [p0 + Vector3(0, y1, 0), p1 + Vector3(0, y1, 0), p1 + Vector3(0, y0, 0), p0 + Vector3(0, y0, 0)], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])


static func flat3(pts: PackedVector2Array, y := 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in pts:
		out.append(Vector3(p.x, y, p.y))
	return out


func multimesh(mesh: Mesh, count: int, colors := false, custom := false) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func mm_node(mm: MultiMesh, m: Material, parent: Node) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	parent.add_child(mmi)
	return mmi


## Builds the fixed city once: ground, water, parks, streets, avenues, the expressway and the Yamanote, buildings,
## trees and landmarks. Lot contents (stores, empty plots) are built by build_lots.
func build_static() -> void:
	C = Sim.City.get_city()
	for c in city.get_children():
		c.free()
	lm_sprites.clear()
	elevated.clear()
	var b: Rect2 = C.bounds
	var mid := b.get_center()
	var grass := tiled(speckle([Color("7fa35a"), Color("8cb064"), Color("739a52"), Color("98b86c")]), Vector2(500, 500))
	plane(city, Vector2(2000, 2000), Vector3(mid.x, -0.16, mid.y), grass)
	# built-up ground, coloured by what the district is
	var ground := mat(Color.WHITE)
	ground.vertex_color_use_as_albedo = true
	var gs := surface(ground)
	for bl in C.blocks:
		var dt: String = C.districts[bl.d].type
		gs.set_color(Color("bfc4a6") if dt in ["homes", "oldtown", "park"] else (Color("b8b2a6") if dt == "market" else Color("cdc6b6")))
		rect_quad(gs, bl.rect.grow(0.2), -0.15)
	commit([gs], city)
	var sea_tex := speckle([Color("3f7fbf"), Color("4a8ccb"), Color("3a74b0"), Color("5596d3")])
	var sea := mat(Color.WHITE, sea_tex)
	sea.texture_repeat = true
	var ws := surface(sea)
	poly_fill(ws, C.bay, -0.14)
	for poly in C.river:
		poly_fill(ws, poly, -0.14)
	var palace: Dictionary = C.parks[0]
	poly_fill(ws, Sim.City.ellipse(palace.center, palace.radii + Vector2(Sim.City.MOAT, Sim.City.MOAT), 40), -0.14)
	var land := surface(mat(Color("cdc6b6")))
	for isl in C.islands:
		poly_fill(land, isl, -0.135)
	var park_tex := tiled(speckle([Color("6f9e4c"), Color("7cab57"), Color("659446"), Color("86b360")]), Vector2.ONE)
	park_tex.texture_repeat = true
	var ps := surface(park_tex)
	for pk in C.parks:
		poly_fill(ps, Sim.City.ellipse(pk.center, pk.radii, 40), -0.13, 0.25)
	commit([ws, land, ps], city)
	build_roads()
	build_elevated()
	build_buildings()
	build_trees()
	build_shadows()
	for L in C.landmarks:
		var lm: Array = C.districts[L.d].lm
		city_sprite(city, lm[0], Rect2(lm[1] * LANDMARK, 0, LANDMARK, LANDMARK_H[lm[0]]), LANDMARK_PX, Vector3(L.pos.x + 3.0, 0, L.pos.y + 3.0), lm_sprites)
	build_paths()


## Side streets as rectangles (with junction mouths, zebra crossings and dashes) and the curved avenues.
func build_roads() -> void:
	var walkway := surface(mat(Color.WHITE, tiles(Color("c9c4bb"), Color("a9a49b"))))
	var asphalt := mat(Color("5d5f66"))
	var tar := surface(asphalt)
	var mouth := surface(asphalt)
	var dash_tex := stripes(Color("5d5f66"), Color("e8e2c8"), 8, 1, 4)
	var dm := mat(Color.WHITE, dash_tex)
	dm.texture_repeat = true
	var dash := surface(dm)
	var solid := surface(mat(Color("e8e2c8")))
	var zm := mat(Color.WHITE, stripes(Color("5d5f66"), Color("ece7d8"), 8, 1, 4))
	zm.texture_repeat = true
	var zebra := surface(zm)
	var rail := surface(mat(Color("d9d4c7")))
	var SW := Sim.City.SIDEWALK
	for s in C.streets:
		var along_z: bool = s.axis == "v"
		var a0: float = s.from - (SW if s.j[0] > 0.0 else 0.0)
		var a1: float = s.to + (SW if s.j[1] > 0.0 else 0.0)
		rect_quad(walkway, srect(s, s.from, s.to, 0.0, s.w), -0.12, 0.0, false, 0.5)
		rect_quad(tar, srect(s, a0, a1, SW, s.w - SW), -0.11)
		var len_: float = s.to - s.from
		if s.w > Sim.ROAD:
			rect_quad(solid, srect(s, s.from, s.to, s.w / 2 - 0.12, s.w / 2 + 0.12), -0.1)
			for off in [(s.w / 2 + SW) / 2, (s.w * 1.5 - SW) / 2]:
				rect_quad(dash, srect(s, s.from, s.to, off - 0.07, off + 0.07), -0.1, len_ / 2.0, along_z)
		else:
			rect_quad(dash, srect(s, s.from, s.to, s.w / 2 - 0.08, s.w / 2 + 0.08), -0.1, len_ / 2.0, along_z)
		# where the street meets the one across its end: clear that street's markings, paint a crossing
		for e in 2:
			if s.j[e] <= 0.0:
				continue
			var at_: float = s.from if e == 0 else s.to
			var dir := -1.0 if e == 0 else 1.0
			rect_quad(mouth, srect(s, minf(at_, at_ + dir * s.j[e]), maxf(at_, at_ + dir * s.j[e]), SW, s.w - SW), -0.095)
			rect_quad(zebra, srect(s, minf(at_ - dir * 0.6, at_ - dir * 2.6), maxf(at_ - dir * 0.6, at_ - dir * 2.6), SW, s.w - SW), -0.09, (s.w - 2 * SW) / 0.9, not along_z)
	for av in C.avenues:
		var pts := flat3(av.pts)
		var half: float = av.w / 2
		ribbon(walkway, pts, half, -half, -0.12, 0.5)
		ribbon(tar, pts, half - SW, SW - half, -0.11)
		if av.shuto == "":
			ribbon(solid, pts, 0.12, -0.12, -0.1)
			var mid_lane: float = (half - SW) / 2
			ribbon(dash, pts, mid_lane + 0.07, mid_lane - 0.07, -0.1, 0.5)
			ribbon(dash, pts, -mid_lane + 0.07, -mid_lane - 0.07, -0.1, 0.5)
		else:
			ribbon(solid, pts, 0.6, -0.6, -0.1)  # the expressway's pillars stand on this median
		# bridges: railings where the avenue crosses water
		var run := -1
		for i in pts.size():
			var wet := Sim.City.is_water(C, av.pts[i])
			if wet and run < 0:
				run = maxi(0, i - 1)
			elif (not wet or i == pts.size() - 1) and run >= 0:
				for side in [half - 0.2, 0.2 - half]:
					wall(rail, pts, side, -0.12, 0.55, run, i)
				run = -1
	commit([walkway, tar, mouth, dash, solid, zebra, rail], city)


## Rect of street s from a0 to a1 along it and c0 to c1 across from its top (or left) edge.
func srect(s: Dictionary, a0: float, a1: float, c0: float, c1: float) -> Rect2:
	return Rect2(a0, s.line + c0, a1 - a0, c1 - c0) if s.axis == "h" else Rect2(s.line + c0, a0, c1 - c0, a1 - a0)


## The Shuto expressway, its ramps and the Yamanote viaduct, in short pieces the shop view can hide; pillars below.
func build_elevated() -> void:
	var deck := mat(Color("4f5158"))
	var fascia := mat(Color("c3bfb6"))
	var lines := mat(Color("e8e2c8"))
	var dm := mat(Color.WHITE, stripes(Color("4f5158"), Color("e8e2c8"), 8, 1, 3))
	dm.texture_repeat = true
	var ballast := mat(Color("8a8174"))
	var steel := mat(Color("4a4440"))
	var green := mat(Color("7fc241"))
	var pillars: Array = []
	var routes: Array = []
	for sh in C.shuto:
		routes.append([sh.pts, sh.closed, Sim.City.EXPRESS_W, "shuto"])
	for rp in C.ramps:
		routes.append([rp.pts, false, Sim.City.RAMP_W, "ramp"])
	routes.append([flat3(C.rail, Sim.City.RAIL_DECK), true, 3.6, "rail"])
	for rt in routes:
		var pts: PackedVector3Array = rt[0].duplicate()
		if rt[1]:
			pts.append(pts[0])
			pts.append(pts[1])
		var half: float = rt[2] / 2
		var i := 0
		while i < pts.size() - 1 - (1 if rt[1] else 0):
			var j := mini(i + 8, pts.size() - 1 - (1 if rt[1] else 0))
			var lo := maxi(0, i - 1)
			var part := pts.slice(lo, mini(j + 2, pts.size()))
			var f := i - lo
			var l := j - lo
			var top := surface(ballast if rt[3] == "rail" else deck)
			var side := surface(fascia)
			var mark := surface(steel if rt[3] == "rail" else lines)
			var extra := surface(green if rt[3] == "rail" else dm)
			ribbon(top, part, half, -half, 0.3, 0.0, f, l)
			for s in [half, -half]:
				wall(side, part, s, -0.6, 0.9, f, l)
			if rt[3] == "rail":
				for s in [0.75, -0.75]:
					ribbon(mark, part, s + 0.08, s - 0.08, 0.34, 0.0, f, l)
				for s in [half + 0.01, -half - 0.01]:
					wall(extra, part, s, 0.25, 0.45, f, l)
			else:
				for s in [half - 0.5, 0.5 - half]:
					ribbon(mark, part, s + 0.07, s - 0.07, 0.32, 0.0, f, l)
				if rt[3] == "shuto":
					wall(side, part, 0.0, 0.3, 0.8, f, l)  # median barrier
					for s in [half / 2, -half / 2]:
						ribbon(extra, part, s + 0.07, s - 0.07, 0.32, 0.5, f, l)
			var mi := commit([top, side, mark, extra], city)
			elevated.append([mi, Vector2(pts[i].x, pts[i].z), Vector2(pts[j].x, pts[j].z)])
			i = j
		# pillars every so often where the deck is high enough to need one
		var gap := 10.0 if rt[3] == "rail" else 14.0
		var walked := gap
		for k in range(1, pts.size()):
			walked += pts[k - 1].distance_to(pts[k])
			if walked >= gap and pts[k].y > 1.5:
				walked = 0.0
				pillars.append([pts[k], 0.7 if rt[3] == "rail" else (1.0 if rt[3] == "ramp" else 1.5)])
	var pm := BoxMesh.new()
	pillar_mm = multimesh(pm, pillars.size())
	pillar_base.clear()
	for k in pillars.size():
		var p: Vector3 = pillars[k][0]
		var tf := Transform3D(Basis.from_scale(Vector3(pillars[k][1], p.y, pillars[k][1])), Vector3(p.x, p.y / 2.0, p.z))
		pillar_mm.set_instance_transform(k, tf)
		pillar_base.append(tf)
	mm_node(pillar_mm, mat(Color("aaa59b")), city)


## Every building as a box with a facade shader (one MultiMesh), gable roofs on houses and kit on flat roofs.
func build_buildings() -> void:
	var all: Array = Sim.City.buildings()
	var boxes := []
	var roofs := []
	brecs.clear()
	for bd in all:
		var r: Rect2 = bd.rect
		var c: Vector2 = bd.center
		var sz: Vector2 = bd.size
		var h: float = bd.floors * Sim.City.FLOOR
		var rec := {"foot": r, "h": h, "box": [boxes.size()], "roof": -1, "hidden": false}
		var tint: Color = bd.tint
		tint.a = (bd.accent + 0.5) / 8.0
		boxes.append([Vector3(sz.x, h, sz.y), Vector3(c.x, h / 2, c.y), tint, bd.style + bd.kit * 0.49, bd.angle])
		if bd.roof != "":
			var rh := minf(sz.x, sz.y) * 0.32
			rec.roof = roofs.size()
			roofs.append([c, sz, h, rh, Color(bd.roof), bd.angle])
			rec.h += rh
		elif bd.floors >= 3 and bd.angle == 0.0 and r.size.x > 6.0 and r.size.y > 6.0:
			var k: float = bd.kit
			var ks := Vector3(1.6 + 1.6 * k, 1.2, 1.4 + 1.8 * (1.0 - k))
			var at_ := Vector3(r.position.x + 1.0 + ks.x / 2 + (r.size.x - ks.x - 2.0) * k, h + 0.6, r.position.y + 1.0 + ks.z / 2 + (r.size.y - ks.z - 2.0) * (1.0 - k))
			rec.box.append(boxes.size())
			boxes.append([ks, at_, Color("c9c7c0"), Sim.City.PLAIN, 0.0])
		brecs.append(rec)
	var shader := Shader.new()
	shader.code = BUILDING_SHADER
	building_mat = ShaderMaterial.new()
	building_mat.shader = shader
	var atlas := facade_atlas()
	building_mat.set_shader_parameter("facades", atlas[0])
	building_mat.set_shader_parameter("accents", atlas[1])
	building_mat.set_shader_parameter("styles", float(Sim.City.STYLE_COUNT))
	var bm := BoxMesh.new()
	box_mm = multimesh(bm, boxes.size(), true, true)
	box_base.clear()
	for k in boxes.size():
		var e: Array = boxes[k]
		var tf := Transform3D(Basis(Vector3.UP, e[4]) * Basis.from_scale(e[0]), e[1])
		box_mm.set_instance_transform(k, tf)
		box_mm.set_instance_color(k, e[2])
		box_mm.set_instance_custom_data(k, Color(e[0].x, e[0].y, e[0].z, e[3]))
		box_base.append(tf)
	mm_node(box_mm, building_mat, city)
	roof_mm = multimesh(PrismMesh.new(), roofs.size(), true, true)
	roof_base.clear()
	for k in roofs.size():
		var e: Array = roofs[k]
		var sz: Vector2 = e[1]
		var basis := Basis.from_scale(Vector3(sz.x, e[3], sz.y))
		if sz.x > sz.y:  # ridge along the longer side
			basis = Basis(Vector3.UP, PI / 2) * Basis.from_scale(Vector3(sz.y, e[3], sz.x))
		var tf := Transform3D(Basis(Vector3.UP, e[5]) * basis, Vector3(e[0].x, e[2] + e[3] / 2, e[0].y))
		roof_mm.set_instance_transform(k, tf)
		roof_mm.set_instance_color(k, e[4])
		roof_mm.set_instance_custom_data(k, Color(0, 0, 0, -1))
		roof_base.append(tf)
	mm_node(roof_mm, building_mat, city)


## Ground shadows: the buildings, pillars and decks rendered from the sun into a mask, then a shadow plane over the
## ground looks each point up in it. Overlapping shadows don't darken twice; hidden buildings drop their shadow.
func build_shadows() -> void:
	if mask_vp:
		mask_vp.free()
	mask_vp = SubViewport.new()
	mask_vp.own_world_3d = true
	mask_vp.transparent_bg = true
	mask_vp.size = Vector2i(SHADOW_RES, SHADOW_RES)
	mask_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(mask_vp)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mm in [box_mm, roof_mm, pillar_mm]:
		mm_node(mm, white, mask_vp)
	for part in elevated:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0].mesh
		mi.material_override = white
		mask_vp.add_child(mi)
		part.append(mi)
	var b: Rect2 = C.bounds
	var mid := Vector3(b.get_center().x, 0, b.get_center().y)
	var sun := Camera3D.new()
	sun.projection = Camera3D.PROJECTION_ORTHOGONAL
	sun.size = b.size.length()
	sun.near = 1.0
	sun.far = 1500.0
	mask_vp.add_child(sun)
	sun.position = mid + SUN.normalized() * 600.0
	sun.look_at(mid)
	sun.current = true
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = SHADOW_SHADER
	sm.set_shader_parameter("mask", mask_vp.get_texture())
	sm.set_shader_parameter("light_vp", sun.get_camera_projection() * Projection(sun.global_transform.affine_inverse()))
	sm.set_shader_parameter("strength", 0.42)
	plane(city, b.grow(200.0).size, Vector3(mid.x, -0.06, mid.z), sm)


## Facade tiles, 32 px a bay (3 units) by a floor, one column per style: row 0 the ground floor, row 1 the floors
## above. Alpha 1 is wall (takes the building's tint), 0 is drawn as is; accent pixels (signs, awnings: alpha 0.5
## where drawn) go to a second mask texture and take the building's accent colour. Returns [facades, accents].
func facade_atlas() -> Array:
	var img := Image.create(32 * Sim.City.STYLE_COUNT, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var mask := Image.create(32 * Sim.City.STYLE_COUNT, 64, false, Image.FORMAT_RGBA8)
	mask.fill(Color.BLACK)
	var glass := fixed("3d5a78")
	var glass2 := fixed("4f6f8c")
	var dark := fixed("26313e")
	for s in Sim.City.STYLE_COUNT:
		for row in 2:
			var r := func(x: int, y: int, w: int, h: int, c: Color) -> void:
				var box := Rect2i(s * 32 + x, row * 32 + y, w, h)
				img.fill_rect(box, Color(c.r, c.g, c.b, 0.0) if c.a == 0.5 else c)
				var lit := c.a == 0.0 and c.to_html(false) in WINDOWS
				mask.fill_rect(box, Color(1, 0, 0) if c.a == 0.5 else (Color(0, 1, 0) if lit else Color.BLACK))
			var up := row == 1
			match s:
				0:  # glass curtain wall
					if up:
						r.call(1, 1, 30, 28, glass)
						r.call(1, 2, 30, 5, fixed("5d7f9c"))
						r.call(15, 1, 2, 28, wall_px(0.95))
						r.call(0, 29, 32, 3, wall_px(0.85))
					else:
						r.call(0, 0, 32, 6, wall_px(0.9))
						r.call(3, 6, 26, 26, dark)
						r.call(15, 6, 2, 26, wall_px(0.8))
				1:  # concrete office, ribbon windows
					if up:
						r.call(0, 9, 32, 13, glass)
						for x in [7, 15, 23, 31]:
							r.call(x, 9, 1, 13, wall_px(0.9))
						r.call(0, 22, 32, 2, wall_px(0.8))
					else:
						r.call(0, 8, 32, 3, wall_px(0.7))
						r.call(5, 11, 22, 21, dark)
				2:  # apartments with balconies
					if up:
						r.call(3, 6, 14, 14, glass2)
						r.call(20, 7, 8, 13, fixed("8a8f96"))
						r.call(0, 20, 32, 2, wall_px(0.75))
						r.call(1, 22, 30, 6, fixed("c8ccd0"))
						for x in range(2, 31, 3):
							r.call(x, 22, 1, 6, fixed("9aa0a6"))
					else:
						r.call(3, 10, 10, 10, glass2)
						r.call(16, 10, 12, 22, fixed("6b5a4a"))
				3:  # shops below, flats above
					if up:
						r.call(3, 7, 11, 13, glass2)
						r.call(18, 7, 11, 13, glass2)
						r.call(0, 20, 32, 2, wall_px(0.8))
						r.call(0, 30, 32, 2, wall_px(0.88))
					else:
						for x in range(0, 32, 4):
							r.call(x, 2, 2, 8, accent(1.0))
							r.call(x + 2, 2, 2, 8, accent(0.78))
						r.call(1, 11, 30, 21, fixed("8fb3c0"))
						r.call(4, 22, 6, 7, fixed("e0a040"))
						r.call(12, 22, 6, 7, fixed("d05050"))
						r.call(20, 22, 6, 7, fixed("60a060"))
				4:  # neon-sign buildings
					if up:
						r.call(2, 8, 15, 13, fixed("2c3644"))
						r.call(20, 2, 10, 28, accent(1.0))
						r.call(22, 4, 6, 24, accent(0.72))
						for y in [6, 12, 18, 24]:
							r.call(23, y, 4, 3, accent(1.0))
					else:
						r.call(2, 4, 28, 6, accent(0.9))
						r.call(2, 11, 28, 21, fixed("e8d9a0"))
				5:  # wooden machiya
					for x in range(1, 32, 4):
						r.call(x, 0, 1, 32, wall_px(0.84))
					if up:
						r.call(8, 8, 16, 12, fixed("ece6d2"))
						for x in [12, 16, 20]:
							r.call(x, 8, 1, 12, fixed("6e5a44"))
						r.call(8, 13, 16, 1, fixed("6e5a44"))
					else:
						r.call(4, 8, 24, 24, fixed("e8e0c8"))
						for x in [9, 15, 21]:
							r.call(x, 8, 1, 24, fixed("6e5a44"))
						r.call(6, 8, 20, 6, accent(0.95))
				6:  # plaster house
					if up:
						r.call(9, 8, 14, 13, fixed("f4f4f0"))
						r.call(10, 9, 12, 11, glass2)
						r.call(15, 9, 2, 11, fixed("f4f4f0"))
					else:
						r.call(4, 12, 8, 20, fixed("7a5a40"))
						r.call(16, 12, 12, 11, fixed("f4f4f0"))
						r.call(17, 13, 10, 9, glass2)
				7:  # warehouse
					for x in range(0, 32, 3):
						r.call(x, 0, 1, 32, wall_px(0.82))
					if up:
						r.call(9, 3, 14, 5, glass)
					else:
						r.call(3, 6, 26, 26, fixed("9aa0a4"))
						for y in range(7, 32, 3):
							r.call(3, y, 26, 1, fixed("7d848a"))
				8:  # stone and bronze
					if up:
						r.call(0, 15, 32, 1, wall_px(0.88))
						r.call(0, 31, 32, 1, wall_px(0.88))
						r.call(7, 3, 18, 25, fixed("c4a35a"))
						r.call(8, 4, 16, 23, dark)
					else:
						r.call(2, 2, 28, 4, accent(0.85))
						r.call(3, 7, 26, 25, fixed("c9b98a"))
						r.call(4, 8, 24, 23, fixed("39475a"))
						r.call(4, 23, 24, 8, fixed("e8dcb0"))
				_:  # plain
					r.call(0, 30, 32, 2, wall_px(0.86))
					r.call(12, 10, 8, 5, wall_px(0.7))
	img.generate_mipmaps()
	mask.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(mask)]


const WINDOWS := ["3d5a78", "4f6f8c", "26313e", "5d7f9c", "2c3644", "e8d9a0", "8fb3c0", "ece6d2", "e8e0c8", "c9b98a", "39475a", "e8dcb0"]


static func wall_px(v: float) -> Color:
	return Color(v, v, v, 1.0)


static func accent(v: float) -> Color:
	return Color(v, v, v, 0.5)


static func fixed(hex: String) -> Color:
	var c := Color(hex)
	c.a = 0.0
	return c


## Trees fill the parks, line the avenues and scatter over the countryside round the city: one MultiMesh of
## billboards per kind of tree.
func build_trees() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 77
	var spots := {}  # outdoor frame -> [Vector3 with w-less scale in y]
	var add := func(id: int, p: Vector2, s: float) -> void:
		if not spots.has(id):
			spots[id] = []
		spots[id].append([Vector3(p.x, 0, p.y), s])
	for pk in C.parks:
		var c: Vector2 = pk.center
		var rr: Vector2 = pk.radii - Vector2(2.5, 2.5)
		var y := c.y - rr.y
		while y < c.y + rr.y:
			var x := c.x - rr.x
			while x < c.x + rr.x:
				var p := Vector2(x + r.randf_range(-1.5, 1.5), y + r.randf_range(-1.5, 1.5))
				var near_lm: bool = C.landmarks.any(func(L): return L.pos.distance_to(p) < 13.0)
				if Sim.City.in_ellipse(p, c, rr) and not near_lm and r.randf() < 0.8:
					var id: int = [3, 3, 1][r.randi() % 3] if pk.name == "Imperial Palace" else ([2, 2, 1, 0][r.randi() % 4] if pk.name == "Ueno Park" else [1, 1, 0, 3, 2][r.randi() % 5])
					add.call(id, p, r.randf_range(0.8, 1.05))
				x += 5.5
			y += 5.0
	for av in C.avenues:
		if av.shuto != "":
			continue
		var cum := Sim.City.cumulative(av.pts)
		var s := 4.0
		while s < cum[-1]:
			var pt: Array = Sim.City.at(av.pts, cum, s)
			for side in [1.0, -1.0]:
				var p: Vector2 = pt[0] + Vector2(pt[1].y, -pt[1].x) * side * (av.w / 2 - 1.0)
				if not Sim.City.is_water(C, p) and not C.streets.any(func(st): return srect(st, st.from - 2.0, st.to + 2.0, -1.0, st.w + 1.0).has_point(p)):
					add.call(1 if r.randf() < 0.75 else 0, p, 0.55)
			s += 10.0
	var b: Rect2 = C.bounds.grow(150.0)
	for k in 1400:
		var p := Vector2(r.randf_range(b.position.x, b.end.x), r.randf_range(b.position.y, b.end.y))
		if Sim.City.nearest(C, p)[1] > Sim.City.URBAN + 8.0 and not Sim.City.is_water(C, p):
			add.call([1, 1, 3, 1, 4][r.randi() % 5], p, r.randf_range(0.7, 1.1))
	tree_mms.clear()
	for id in spots:
		var qs: Vector2 = Vector2(OUTDOOR, OUTDOOR) * OUTDOOR_PX * OUTDOOR_SCALE[id]
		var q := QuadMesh.new()
		q.size = qs
		q.center_offset = Vector3(0, qs.y / 2 - 0.1, 0)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tex.outdoor
		m.uv1_scale = Vector3(1.0 / 12.0, 1, 1)
		m.uv1_offset = Vector3(id / 12.0, 0, 0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		m.billboard_keep_scale = true
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var list: Array = spots[id]
		var mm := multimesh(q, list.size())
		var base := []
		for k in list.size():
			var tf := Transform3D(Basis.from_scale(Vector3.ONE * list[k][1]), list[k][0])
			mm.set_instance_transform(k, tf)
			base.append(tf)
		mm_node(mm, m, city)
		tree_mms.append([mm, base, qs.y])


## What stands on each lot: stores (Codex storefronts), an ordinary shop (a small building), or an empty plot.
func build_lots() -> void:
	for c in lots_node.get_children():
		c.free()
	lot_sprites.clear()
	var plot := surface(mat(Color.WHITE, tiles(Color("d8d2c4"), Color("bdb6a6"))))
	var shops := []
	for li in sim.lots.size():
		var L: Dictionary = sim.lots[li]
		rect_quad(plot, Rect2(L.x0, L.front - Sim.LOT_D, Sim.LOT_W, Sim.LOT_D), -0.08, 0.0, false, 0.5)
		if li == focus_lot():
			continue
		var at_ := Vector3(L.x0 + Sim.LOT_W * 0.62, 0, L.front - 0.4)
		match L.use:
			"shop":
				shops.append(li)
			"store":
				var st := store_on(li)
				var f: int = Sim.CHAINS[st[1]].frame * 2 + (1 if st[0].kind == "super" else 0)
				city_sprite(lots_node, "storefronts", Rect2(f * STOREFRONT.x, 0, STOREFRONT.x, STOREFRONT.y), STOREFRONT_PX, at_, lot_sprites)
	commit([plot], lots_node)
	if shops.is_empty():
		return
	var mm := multimesh(BoxMesh.new(), shops.size(), true, true)
	for k in shops.size():
		var L: Dictionary = sim.lots[shops[k]]
		var sz := Vector3(16.0, 3.0 * (2 + shops[k] % 3), 8.0)
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(sz), Vector3(L.x0 + Sim.LOT_W / 2, sz.y / 2, L.front - 4.6)))
		mm.set_instance_color(k, Color(["f0e6d2", "e8d8c0", "d8e2e6", "f2dccf"][shops[k] % 4], (shops[k] % 8 + 0.5) / 8.0))
		mm.set_instance_custom_data(k, Color(sz.x, sz.y, sz.z, Sim.City.SHOPS))
	mm_node(mm, building_mat, lots_node)


## [store dict, chain] standing on lot li.
func store_on(li: int) -> Array:
	for st in sim.stores:
		if st.lot == li:
			return [st, 0]
	return [sim.rival_at(li), sim.rival_at(li).get("chain", 1)]


func focus_lot() -> int:
	return store.get("lot", -1)


## What the lots look like; build_lots runs only when this changes.
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


## Store mode cuts the city away in front of the focused shop: sprites fade, buildings, trees, pillars and
## elevated decks that would cover it are hidden.
func update_fade() -> void:
	var on := mode == "store" and focus_lot() >= 0
	var shop := Rect2()
	var depth := INF
	var shop_at := Vector2(INF, INF)
	if on:
		var lo := iso(site.position)
		shop = Rect2(lo + Vector2(-lot.y * 0.71, -4.0), Vector2((lot.x + lot.y) * 0.71, (lot.x + lot.y) * 0.36 + 4.0))
		depth = site.position.x + site.position.z + (lot.x + lot.y) / 2
		shop_at = Sim.lot_pos(sim.lots[focus_lot()])
	for e in lm_sprites + lot_sprites:
		var s: Sprite3D = e[0]
		var base := iso(s.position - Vector3(0, s.position.y, 0))
		var tall: float = s.region_rect.size.y * s.pixel_size
		var r := Rect2(base + Vector2(-e[1], -tall * 0.87), Vector2(e[1] * 2, tall * 0.87))
		var fade_it: bool = on and r.intersects(shop) and s.position.x + s.position.z > site.position.x + site.position.z + lot.y
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED if fade_it else SpriteBase3D.ALPHA_CUT_DISCARD
		s.modulate = Color(1, 1, 1, 0.25) if fade_it else Color.WHITE
	var away := Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -50, 0))
	for rec in brecs:
		var f: Rect2 = rec.foot
		var cut: bool = on and f.end.x + f.end.y > depth and foot_rect(f, rec.h).intersects(shop)
		if cut != rec.hidden:
			rec.hidden = cut
			for k in rec.box:
				box_mm.set_instance_transform(k, away if cut else box_base[k])
			if rec.roof >= 0:
				roof_mm.set_instance_transform(rec.roof, away if cut else roof_base[rec.roof])
	for tm in tree_mms:
		for k in tm[1].size():
			var p: Vector3 = tm[1][k].origin
			var cut: bool = on and p.x + p.z > depth and foot_rect(Rect2(p.x - 1.5, p.z - 1.5, 3, 3), tm[2]).intersects(shop)
			tm[0].set_instance_transform(k, away if cut else tm[1][k])
	for k in pillar_base.size():
		var p: Vector3 = pillar_base[k].origin
		pillar_mm.set_instance_transform(k, away if on and shop_at.distance_to(Vector2(p.x, p.z)) < 24.0 else pillar_base[k])
	for part in elevated:
		part[0].visible = not on or shop_at.distance_to(Geometry2D.get_closest_point_to_segment(shop_at, part[1], part[2])) > 26.0
		if part.size() > 3:
			part[3].visible = part[0].visible
	if mask_vp:
		mask_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## Screen-plane box of a footprint standing h tall.
func foot_rect(f: Rect2, h: float) -> Rect2:
	var r := Rect2(iso(Vector3(f.position.x, 0, f.position.y)), Vector2.ZERO)
	r = r.expand(iso(Vector3(f.end.x, 0, f.position.y))).expand(iso(Vector3(f.end.x, 0, f.end.y))).expand(iso(Vector3(f.position.x, 0, f.end.y)))
	return Rect2(r.position - Vector2(0, h * 0.87), r.size + Vector2(0, h * 0.87))


## World xz to the iso screen plane (x right, y down), in world units.
func iso(p: Vector3) -> Vector2:
	return Vector2((p.x - p.z) * 0.7071, (p.x + p.z) * 0.3536 - p.y * 0.866)


# ---------- street life (cosmetic, not seeded) ----------

func view_center() -> Vector2:
	var t3 := cam.position - cam.global_transform.basis.z * 400.0
	return Vector2(t3.x, t3.z)


## Every road as a path movers follow: side streets, avenues, the expressway (cars only) and the Yamanote (trains).
func build_paths() -> void:
	paths.clear()
	for s in C.streets:
		var c: float = s.line + s.w / 2
		var pts := PackedVector3Array([Vector3(s.from, 0, c), Vector3(s.to, 0, c)] if s.axis == "h" else [Vector3(c, 0, s.from), Vector3(c, 0, s.to)])
		paths.append(make_path(pts, s.w, "street", false))
	for av in C.avenues:
		var pa := make_path(flat3(av.pts), av.w, "avenue", false)
		pa.name = av.name
		paths.append(pa)
	var decks := {}  # avenue name -> the expressway path above it
	for sh in C.shuto:
		var pts: PackedVector3Array = sh.pts.duplicate()
		for i in pts.size():
			pts[i] = pts[i] + Vector3(0, 0.3, 0)
		var pa := make_path(pts, Sim.City.EXPRESS_W, "shuto", sh.closed)
		paths.append(pa)
		decks[sh.name] = pa
	for rp in C.ramps:
		var av: Dictionary = C.avenues[rp.av]
		var pts: PackedVector3Array = rp.pts.duplicate()
		for i in pts.size():
			pts[i] = pts[i] + Vector3(0, 0.3 * pts[i].y / Sim.City.DECK, 0)
		var pa := make_path(pts, Sim.City.RAMP_W, "ramp", false)
		pa.dir = rp.side  # traffic keeps left: one way down each ramp
		pa.s0 = rp.s0
		pa.ground = paths.filter(func(q): return q.kind == "avenue" and q.name == av.name)[0]
		pa.deck = decks[av.shuto]
		paths.append(pa)
	rail_path = make_path(flat3(C.rail, Sim.City.RAIL_DECK + 0.3), 3.6, "rail", true)
	for trn in trains:
		trn.node.queue_free()
	trains.clear()
	for k in 2:
		var node := sprite("train", Rect2(0, 0, TRAIN.x, TRAIN.y), TRAIN_PX)
		street.add_child(node)
		trains.append({"path": rail_path, "s": rail_path.cum[-1] * k / 2.0, "v": TRAIN_SPEED * (1 if k == 0 else -1), "lat": 0.0, "node": node, "y": TRAIN.y / 2.0 * TRAIN_PX * 0.55 - 0.1})


func make_path(pts: PackedVector3Array, w: float, kind_: String, closed: bool) -> Dictionary:
	if closed:
		pts = pts.duplicate()
		pts.append(pts[0])
	var cum := PackedFloat32Array([0.0])
	var box := Rect2(Vector2(pts[0].x, pts[0].z), Vector2.ZERO)
	for i in range(1, pts.size()):
		cum.append(cum[-1] + pts[i - 1].distance_to(pts[i]))
		box = box.expand(Vector2(pts[i].x, pts[i].z))
	return {"pts": pts, "cum": cum, "w": w, "kind": kind_, "closed": closed, "box": box.grow(w)}


## [point, unit direction] at arc length s.
func path_at(p: Dictionary, s: float) -> Array:
	var cum: PackedFloat32Array = p.cum
	var i := clampi(cum.bsearch(s), 1, cum.size() - 1)
	var seg := cum[i] - cum[i - 1]
	var a: Vector3 = p.pts[i - 1]
	var b: Vector3 = p.pts[i]
	return [a.lerp(b, clampf((s - cum[i - 1]) / maxf(seg, 0.001), 0.0, 1.0)), (b - a).normalized()]


## Places a mover at its arc length, offset sideways into its lane or onto its sidewalk.
func place(m: Dictionary) -> void:
	var pa := path_at(m.path, m.s)
	var dir: Vector3 = pa[1]
	m.node.position = pa[0] + Vector3(dir.z, 0, -dir.x) * m.lat + Vector3(0, m.y, 0)
	m.dir = dir * signf(m.v)


## Picks the sprite frame for something travelling along `dir` (art: frame 0 heads down-right, 1 up-left).
func facing(node: Sprite3D, dir: Vector3, frame0: int, cell: Vector2i) -> void:
	var b := cam.global_transform.basis
	var toward := dir.dot(b.y) < 0.0
	var sx := dir.dot(b.x)
	node.region_rect = Rect2((frame0 + (0 if toward else 1)) * cell.x, node.region_rect.position.y, cell.x, cell.y)
	node.flip_h = sx < 0.0 if toward else sx > 0.0


func view_rect() -> Rect2:
	var r := cam.size * 1.5
	return Rect2(view_center() - Vector2(r, r), Vector2(r, r) * 2.0)


## A walker on a sidewalk (or a car in a lane) of a road in view; new ones start near the view's edge.
func spawn_mover(is_car: bool, mid := false) -> void:
	var view := view_rect()
	var cands := paths.filter(func(pa): return pa.box.intersects(view) and (is_car or pa.kind not in ["shuto", "ramp"]))
	if cands.is_empty():
		return
	var p: Dictionary = cands[randi() % cands.size()]
	var c := view.get_center()
	var sc := 0.0  # arc length of the path's point nearest the view centre
	var best := INF
	for i in range(1, p.pts.size()):
		var a := Vector2(p.pts[i - 1].x, p.pts[i - 1].z)
		var q := Geometry2D.get_closest_point_to_segment(c, a, Vector2(p.pts[i].x, p.pts[i].z))
		if q.distance_to(c) < best:
			best = q.distance_to(c)
			sc = p.cum[i - 1] + a.distance_to(q)
	var s := -1.0
	for k in 8:
		var try_s: float = clampf(sc + randf_range(-1.0, 1.0) * view.size.x * 0.7, 0.0, p.cum[-1])
		var at_: Vector3 = path_at(p, try_s)[0]
		var q := Vector2(at_.x, at_.z)
		if view.has_point(q) and (mid or q.distance_to(view.get_center()) > view.size.x * 0.3):
			s = try_s
			break
	if s < 0.0:
		return
	var dir: float = p.get("dir", 1.0 if randf() < 0.5 else -1.0)
	var m := {"path": p, "s": s, "v": 0.0, "lat": 0.0, "y": 0.0, "dir": Vector3.RIGHT}
	var node: Sprite3D
	if is_car:
		m.lat = lane(p, dir, randi() % 2)
		if cars.any(func(o): return o.path == p and signf(o.v) == dir and absf(o.lat - m.lat) < 0.5 and absf(o.s - s) < 7.0):
			return  # keep cars apart in their lane
		m.kv = randi() % 4
		node = sprite("vehicles", Rect2(m.kv * 2 * VEHICLE_CELL.x, 0, VEHICLE_CELL.x, VEHICLE_CELL.y), VEHICLE_PX)
		m.v = dir * randf_range(5.0, 8.0) * (0.6 if m.kv == 3 else 1.0) * (1.6 if p.kind == "shuto" else 1.0)
		m.y = VEHICLE_CELL.y / 2.0 * VEHICLE_PX - 0.1
		cars.append(m)
	else:
		m.a = randi() % 7
		m.lat = (1.0 if randf() < 0.5 else -1.0) * (p.w / 2 - Sim.City.SIDEWALK / 2 + randf_range(-0.4, 0.4))
		node = sprite("walk", Rect2(PERSON.x, m.a * PERSON.y, PERSON.x, PERSON.y), PERSON_PX)
		node.add_child(shadow())
		m.v = dir * randf_range(1.4, 2.4)
		m.y = 0.82
		m.step = randf() * 4.0
		walkers.append(m)
	m.node = node
	street.add_child(node)
	place(m)


## Lateral offset of a lane for traffic going `dir` along path p (keep left; lane 0 is the inner one).
func lane(p: Dictionary, dir: float, k: int) -> float:
	if p.kind == "ramp":
		return 0.0
	var half: float = p.w / 2 - (0.6 if p.kind == "shuto" else Sim.City.SIDEWALK)
	var lanes := 1 if p.w <= Sim.ROAD else 2
	return dir * half * (mini(k, lanes - 1) + 0.5) / lanes


## A car that reaches the end of a ramp carries on along the avenue below or the expressway above, outer lane.
func off_ramp(o: Dictionary) -> void:
	var p: Dictionary = o.path
	var top: bool = p.pts[-1 if o.v > 0.0 else 0].y > 1.0
	var next: Dictionary = p.deck if top else p.ground
	o.path = next
	o.s = p.s0 + (Sim.City.RAMP_L if o.v > 0.0 else 0.0)
	o.lat = lane(next, signf(o.v), 1)


func clear_street() -> void:
	for o in walkers + cars:
		o.node.queue_free()
	walkers.clear()
	cars.clear()
	for k in 40:
		spawn_mover(false, true)
	for k in 16:
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


## Walkers and traffic round the view (walkers only when close enough to see); busier at rush hours.
func street_life(delta: float) -> void:
	var busy := 1.0
	if playing:
		busy = 0.35 + Sim.BLOCK_W[mini(5, int(progress() * 6.0))] / 3.0
	var close := cam.size < 90.0
	next_walker -= delta * busy
	if next_walker <= 0.0 and close and walkers.size() < MAX_WALKERS:
		spawn_mover(false)
		next_walker = randf_range(0.15, 0.5)
	next_car -= delta * busy
	if next_car <= 0.0 and cars.size() < MAX_CARS:
		spawn_mover(true)
		next_car = randf_range(0.12, 0.45)
	var view := view_rect().grow(6.0)
	var gone := []
	for o in walkers + cars:
		o.s += o.v * delta
		if o.path.closed:
			o.s = fposmod(o.s, o.path.cum[-1])
		var at_: Vector3 = o.node.position
		if (o.s < 0.0 or o.s > o.path.cum[-1]) and o.path.kind == "ramp":
			off_ramp(o)
		if o.s < 0.0 or o.s > o.path.cum[-1] or not view.has_point(Vector2(at_.x, at_.z)) or (not close and o.has("a")):
			gone.append(o)
			continue
		place(o)
		if o.has("a"):
			stride(o, absf(o.v), delta)
			o.node.flip_h = o.dir.dot(cam.global_transform.basis.x) < 0.0
		else:
			facing(o.node, o.dir, o.kv * 2, VEHICLE_CELL)
	for o in gone:
		o.node.queue_free()
	walkers = walkers.filter(func(o): return not gone.has(o))
	cars = cars.filter(func(o): return not gone.has(o))
	var shop_at: Vector2 = Sim.lot_pos(sim.lots[focus_lot()]) if mode == "store" and focus_lot() >= 0 else Vector2(INF, INF)
	for trn in trains:
		trn.s = fposmod(trn.s + trn.v * delta, trn.path.cum[-1])
		place(trn)
		facing(trn.node, trn.dir, 0, TRAIN)
		trn.node.visible = shop_at.distance_to(Vector2(trn.node.position.x, trn.node.position.z)) > 22.0


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
		if city_sig == "":
			build_static()
		city_sig = sig
		build_lots()
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
		zoom = clampf(zoom * (0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.04 if mode == "city" else 0.55, 1.4 if mode == "city" else 6.0)
		update_camera()
		accept_event()
		return
	if mode == "city" and e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		yaw -= e.relative.x * 0.006
		update_camera()
		accept_event()
		return
	if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_MIDDLE or (not edit and e.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		var b := cam.global_transform.basis
		cam_offset += (-b.x * e.relative.x + b.y * e.relative.y) * cam.size / size.y
		cam_offset = cam_offset.limit_length(420.0 if mode == "city" else 40.0)
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
	if building_mat and building_mat.get_shader_parameter("night") != night:
		building_mat.set_shader_parameter("night", night)
	if night > 0.0:
		overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.07, 0.25, 0.32 * night))
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
	if city_view and zoom < 0.45:
		for av in C.avenues:
			var pts: PackedVector2Array = av.pts
			var third: Vector2 = pts[int(pts.size() / 3.0)]
			var at := screen_world(Vector3(third.x, 0, third.y))
			overlay.draw_string_outline(font, at + Vector2(-50, 0), av.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 10, 3, Color(1, 1, 1, 0.7))
			overlay.draw_string(font, at + Vector2(-50, 0), av.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 10, Color("5d5f66"))
		for sh in C.shuto:
			var pts: PackedVector3Array = sh.pts
			var at := screen_world(pts[int(pts.size() / 2.0)] + Vector3(0, 1.5, 0))
			overlay.draw_rect(Rect2(at + Vector2(-13, -9), Vector2(26, 16)), Color("1f6f43"))
			overlay.draw_rect(Rect2(at + Vector2(-13, -9), Vector2(26, 16)), Color.WHITE, false, 1.5)
			overlay.draw_string(font, at + Vector2(-13, 4), sh.name, HORIZONTAL_ALIGNMENT_CENTER, 26, 11, Color.WHITE)
	if city_view:
		for d in sim.districts:
			var at := screen_world(Vector3(d.center.x, 0, d.center.y - 4.0))
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
