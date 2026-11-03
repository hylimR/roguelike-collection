extends Control
## The city stage: Tokyo (city.gd) as a city builder sees it, through an orthographic isometric camera. Streets,
## avenues, the elevated expressway and the Yamanote are generated meshes; buildings are boxes in one MultiMesh
## with a pixel facade shader; trees, landmarks, storefronts, cars and people are Codex sprites. In store mode the
## focused branch's street set is carved into the city on its lot: your shop as a cutaway, the rival next door,
## the street with its crossing, and the sim's pedestrians, threats and staff live. Clicks on threats, tills and
## shelves go out as actions; in city mode you pick lots. Labels draw on a 2D overlay. Street-frame nodes live
## under `site` (sim.gd's street frame, 1:1), the shop interior under `room` (the shop's local frame).

signal act_requested(a: Dictionary)
signal lot_clicked(li: int)

const Sim := preload("res://sim.gd")
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
const SET := Rect2(-52, -32, 104, 52)  # the street set round your shop, in the street frame
const ROLE_TINT := {"stocker": Color(0.78, 0.86, 1.0), "cleaner": Color(1.0, 0.95, 0.72), "guard": Color(0.62, 0.66, 0.92), "promoter": Color(1.0, 0.78, 0.88)}
const FIELDS := ["9cb862", "b2c46e", "86a85a", "cdbb72", "a98f62", "79a05a", "bfc77e"]  # paddies, crops, tilled soil
# the day's weather over the view: [tint, then for falling rain or snow: drops, slant, speed px/s, streak length]
const WEATHER_LOOK := {
	"hot": [Color(1.0, 0.7, 0.3, 0.12)],
	"rain": [Color(0.2, 0.25, 0.38, 0.24), 170, -0.18, 950.0, 15.0],
	"cold": [Color(0.8, 0.88, 1.0, 0.2), 240, 0.15, 50.0, 0.0],
	"typhoon": [Color(0.1, 0.14, 0.24, 0.36), 360, -0.6, 1500.0, 24.0],
}
# the hour's light on everything outdoors, [hour, tint]: a pink dawn, plain day, golden hour, dusk, night; lit windows,
# your shop's interior and the street lamps' pools stay bright
const DAYLIGHT := [[6.0, Color(0.96, 0.86, 0.86)], [8.0, Color.WHITE], [15.5, Color.WHITE], [17.0, Color(1.0, 0.93, 0.8)],
	[18.3, Color(0.98, 0.84, 0.7)], [19.1, Color(0.8, 0.62, 0.7)], [19.8, Color(0.5, 0.5, 0.72)], [21.0, Color(0.36, 0.4, 0.62)],
	[24.0, Color(0.32, 0.36, 0.58)]]
const GOLDEN := [16.0, 17.8, 19.2]  # golden hour's rise, peak and end: walls facing the low sun glow, the rest go cool
const LAMP := Color(1.0, 0.85, 0.58)
const SEA := Color("3f7fbf")
const PITCH := 30.0
const SUN :=Vector3(-0.35, 1.0, 0.6)  # towards the sun; the building shader lights its faces from here too
const SHADOW_RES := 4096
const LOW := 0.9  # a city building in front of the street, cut down to its ground floor
const STANDING := INF  # building states in update_fade: standing, gone, or cut down from this z on
const GONE := -INF
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
uniform vec3 light = vec3(1.0);
uniform float golden = 0.0;
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
			if (info.y < 1.0)  // cut down in front of the street: the walls' section round a dim floor
				col = min(e.x, e.y) < 0.3 ? tint.rgb * 1.08 : mix(vec3(0.44, 0.4, 0.38), tint.rgb, 0.2);
			else
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
	float low_sun = max(dot(n, normalize(vec3(-0.5, 0.3, 0.8))), 0.0);
	vec3 grade = mix(vec3(0.8, 0.84, 1.04), vec3(1.2, 1.02, 0.78), low_sun);
	ALBEDO = col * shade * light * mix(vec3(1.0), grade, golden) + glow;
}
"""
# the back wall's art: a crop of the side-view background, tiled along the wall
const LAYOUT := {"bg": "bg_konbini", "wall": Rect2i(0, 140, 544, 108), "floor": [Color("ead9b8"), Color("cbb48e")], "stripe": [Color("f05a28"), Color("1f9d55")]}

var tex := {}
var sim
var branch: Dictionary = {}  # the focused branch (sim's own dictionary)
var set_sig := ""
var slot_icons := {}  # product -> [Sprite3D]: its stock on the shelf
var agent_nodes := {}  # sim id -> {node, a (walk row), step}
var threat_nodes := {}
var staff_nodes := {}
var floaters: Array = []
var paused := false
var hover := {}  # the action a click would take
var drag := 0.0
var bold: Font  # the HUD's heavy weight, for the clock and street tags
var styles := {}  # rounded boxes for tags and bars, by color and radius

var walkers: Array = []
var cars: Array = []
var next_walker := 0.0
var next_car := 0.0
var mode := "store"  # store | city
var city_sig := ""
var lm_sprites: Array = []  # [Sprite3D, half width]: landmarks, faded when they cover the shop
var lot_sprites: Array = []  # the same for storefronts on lots
var hover_lot := -1
var pick := ""  # city mode: "" | listing
var site: Node3D
var city: Node3D
var lots_node: Node3D
var C: Dictionary  # the City map
var trains: Array = []  # movers on the Yamanote
var paths: Array = []  # every road as a path for movers: {pts, cum, w, kind, closed, box}
var rail_path: Dictionary
var set_feet: Array = []  # world footprints of what the street set builds behind its street, where the city gives way
var pillar_deck: Array = []  # per pillar: the deck piece it holds up
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
var shadow_mat: ShaderMaterial
var env: Environment
var light := Color.WHITE  # the hour's tint (DAYLIGHT)
var night := 0.0  # 0 by day, 1 from 22:00: lit windows and lamp pools
var lit_mats: Array = []  # [weakref to an outdoor material, its own colour]
var lit_sprites: Array = []  # outdoor sprites that stand still, relit when the light changes
var pools: Array = []  # Vector3(x, z, radius) in the world: lamp light on the street after dark
var pool_mat: StandardMaterial3D
var shop_area := Rect2()  # your shop's floor in the world: full light inside
var vignette: GradientTexture2D
var box_mesh: ArrayMesh
var soft_mat: StandardMaterial3D  # soft contact shadows under people, cars and street things
var ao_mat: StandardMaterial3D  # the dark seam where a building meets the sidewalk
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
var set_node: Node3D
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
	resized.connect(fit_viewport)
	fit_viewport.call_deferred()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SEA  # open sea round the island
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	pool_mat = StandardMaterial3D.new()
	pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pool_mat.albedo_texture = radial([Color.WHITE, Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)], [0.0, 0.4, 1.0])
	pool_mat.albedo_color = Color(0, 0, 0, 0)
	vignette = radial([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.2, 0.12, 0.05)], [0.0, 0.55, 1.0])
	soft_mat = StandardMaterial3D.new()
	soft_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	soft_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soft_mat.albedo_texture = radial([Color(0.1, 0.08, 0.14), Color(0.1, 0.08, 0.14, 0.55), Color(0.1, 0.08, 0.14, 0)], [0.0, 0.5, 1.0])
	soft_mat.albedo_color = Color(1, 1, 1, 0.34)
	ao_mat = soft_mat.duplicate()
	var seam := GradientTexture2D.new()
	seam.fill_from = Vector2(0, 0)
	seam.fill_to = Vector2(0, 1)
	seam.gradient = Gradient.new()
	seam.gradient.colors = PackedColorArray([Color(0.1, 0.08, 0.14), Color(0.1, 0.08, 0.14, 0)])
	ao_mat.albedo_texture = seam
	ao_mat.albedo_color = Color(1, 1, 1, 0.3)
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
	set_node = Node3D.new()
	site.add_child(set_node)
	room = Node3D.new()
	room.position = Vector3(Sim.ORIGIN.x, 0, Sim.ORIGIN.y)
	site.add_child(room)
	actors = Node3D.new()
	site.add_child(actors)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(draw_overlay)
	add_child(overlay)


# ---------- building ----------

## Outdoor materials take the hour's light; indoor ones (your shop) keep their own colour.
func mat(color: Color, texture: Texture2D = null, indoor := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color if indoor else color * light
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.albedo_texture = texture
	m.texture_repeat = texture != null
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not indoor:
		lit_mats.append([weakref(m), color])
	return m


func block(parent: Node3D, size_: Vector3, pos: Vector3, color: Color, indoor := false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = shaded_box()
	mi.scale = size_
	var m := mat(color, null, indoor or parent == room)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


## A unit cube with each face pre-shaded as if lit from the sun's side (top brightest, the street face next), so
## unshaded boxes still read as solid.
func shaded_box() -> ArrayMesh:
	if box_mesh:
		return box_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in [[Vector3.UP, 1.0], [Vector3.BACK, 0.92], [Vector3.RIGHT, 0.8], [Vector3.LEFT, 0.88], [Vector3.FORWARD, 0.85], [Vector3.DOWN, 0.7]]:
		var n: Vector3 = f[0]
		var u := n.cross(Vector3.RIGHT if absf(n.x) < 0.5 else Vector3.UP) * 0.5
		var v := n.cross(u)
		st.set_color(Color(f[1], f[1], f[1]))
		add_quad(st, [n * 0.5 - u - v, n * 0.5 + u - v, n * 0.5 + u + v, n * 0.5 - u + v], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	box_mesh = st.commit()
	return box_mesh


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


## A picture on an upright quad facing +z (shop art, the rival's window), mipmapped so it stays clean when small.
func art_panel(parent: Node3D, img: Image, size_: Vector2, pos: Vector3, tint := Color.WHITE, reps := 1.0) -> void:
	img.generate_mipmaps()
	var m := mat(tint, ImageTexture.create_from_image(img), true)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.uv1_scale = Vector3(reps, 1, 1)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size_
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func radial(colors: Array, offsets: Array) -> GradientTexture2D:
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.gradient = Gradient.new()
	g.gradient.offsets = PackedFloat32Array(offsets)
	g.gradient.colors = PackedColorArray(colors)
	return g


# ---------- light ----------

## Follows the clock: tints outdoor materials, buildings, the sea and still sprites when the hour's light changes.
func update_light() -> void:
	var h: float = sim.hour()
	var k := 1
	while k < DAYLIGHT.size() - 1 and h > DAYLIGHT[k][0]:
		k += 1
	var t := clampf(inverse_lerp(DAYLIGHT[k - 1][0], DAYLIGHT[k][0], h), 0.0, 1.0)
	var c: Color = DAYLIGHT[k - 1][1].lerp(DAYLIGHT[k][1], t)
	var n := clampf((h - 18.0) / 4.0, 0.0, 1.0)
	if is_equal_approx(n, night) and Vector3(c.r - light.r, c.g - light.g, c.b - light.b).length() < 0.004:
		return
	light = c
	night = n
	lit_mats = lit_mats.filter(func(e): return e[0].get_ref() != null)
	for e in lit_mats:
		e[0].get_ref().albedo_color = e[1] * light
	if building_mat:
		building_mat.set_shader_parameter("light", Vector3(light.r, light.g, light.b))
		building_mat.set_shader_parameter("night", night)
		building_mat.set_shader_parameter("golden", golden_at(h))
	if shadow_mat:
		shadow_mat.set_shader_parameter("strength", 0.42 * (1.0 - night))
	env.background_color = SEA * light
	pool_mat.albedo_color = LAMP * Color(1, 1, 1, 0.75 * night)
	soft_mat.albedo_color.a = 0.34 - 0.14 * night
	ao_mat.albedo_color.a = 0.3 - 0.1 * night
	lit_sprites = lit_sprites.filter(func(s): return is_instance_valid(s))
	for s in lit_sprites:
		shine(s)


func golden_at(h: float) -> float:
	if h < GOLDEN[1]:
		return clampf(inverse_lerp(GOLDEN[0], GOLDEN[1], h), 0.0, 1.0)
	return clampf(inverse_lerp(GOLDEN[2], GOLDEN[1], h), 0.0, 1.0)


## What a sprite standing at p sees: the hour's light, lifted under a lamp after dark and full inside your shop.
func light_at(p: Vector3) -> Color:
	if mode != "store":
		return light
	if shop_area.has_point(Vector2(p.x, p.z)):
		return Color.WHITE
	var k := 0.0
	if night > 0.0:
		for q in pools:
			k = maxf(k, 1.0 - Vector2(p.x - q.x, p.z - q.y).length() / q.z)
	return light.lerp(LAMP, k * night * 0.8)


func shine(s: Sprite3D) -> void:
	s.modulate = s.get_meta("base", Color.WHITE) * light_at(s.global_position)


## A pool of lamp light on the ground, faded in after dusk.
func pool(parent: Node3D, at: Vector3, size_: Vector2) -> void:
	plane(parent, size_, Vector3(at.x, -0.03, at.z), pool_mat)
	var w := parent.global_position + at
	pools.append(Vector3(w.x, w.z, maxf(size_.x, size_.y) * 0.45))


func tiles(a: Color, b: Color) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(a)
	for i in 16:
		img.set_pixel(i, 15, b)
		img.set_pixel(15, i, b)
	return ImageTexture.create_from_image(img)



## Store mode frames the focused street; city mode frames the whole city. Drag pans, wheel zooms.
func set_mode(m: String) -> void:
	mode = m
	cam_offset = Vector3.ZERO
	zoom = 1.0
	yaw = PI / 4  # the shop cutaway is drawn for this angle
	pick = "" if m == "store" else pick
	hover = {}
	refresh_city()


func update_camera() -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var target: Vector3
	if mode == "city":
		var b: Rect2 = sim.city_bounds()
		target = Vector3(b.get_center().x, 0, b.get_center().y)
		cam.size = (b.size.x + b.size.y) * 0.4 * zoom
	else:
		target = site.position + Vector3(-1.3, 1.0, -10.2)  # your shop up close, the rival's sign still in frame
		cam.size = 24.0 * zoom
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
	lit_sprites.append(s)
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
	# farmland round the city: a patchwork of furrowed fields with grass between, kept off the roads and the shore
	var furrows := Image.create(4, 4, false, Image.FORMAT_RGB8)
	furrows.fill(Color.WHITE)
	furrows.fill_rect(Rect2i(0, 0, 1, 4), Color(0.84, 0.86, 0.78))
	furrows.generate_mipmaps()
	var fm := mat(Color.WHITE, ImageTexture.create_from_image(furrows))
	fm.vertex_color_use_as_albedo = true
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var fs := surface(fm)
	var fr := RandomNumberGenerator.new()
	fr.seed = 5
	var fb := b.grow(400.0)
	var fy := fb.position.y
	while fy < fb.end.y:
		var fh := fr.randf_range(14.0, 26.0)
		var fx := fb.position.x - fr.randf_range(0.0, 20.0)
		while fx < fb.end.x:
			var fw := fr.randf_range(16.0, 36.0)
			var r := Rect2(fx, fy, fw, fh).grow(-0.9)
			if Sim.City.nearest(C, r.get_center())[1] > Sim.City.URBAN + 16.0 and not Sim.City.blocked(C, r.grow(12.0)):
				var along := fr.randf() < 0.5
				fs.set_color(Color(FIELDS[fr.randi() % FIELDS.size()]))
				rect_quad(fs, r, -0.155, (r.size.y if along else r.size.x) / 3.0, along)
			fx += fw
		fy += fh
	commit([fs], city)
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
		if s.w > Sim.City.ROAD:
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
		var deck_at := []  # per point: the deck piece over it, so its pillar can go with it
		deck_at.resize(pts.size())
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
			for k in range(i, j + 1):
				deck_at[k] = mi
			i = j
		# pillars every so often where the deck is high enough to need one
		var gap := 10.0 if rt[3] == "rail" else 14.0
		var walked := gap
		for k in range(1, pts.size()):
			walked += pts[k - 1].distance_to(pts[k])
			if walked >= gap and pts[k].y > 1.5:
				walked = 0.0
				pillars.append([pts[k], 0.7 if rt[3] == "rail" else (1.0 if rt[3] == "ramp" else 1.5), deck_at[k]])
	var pm := BoxMesh.new()
	pillar_mm = multimesh(pm, pillars.size())
	pillar_base.clear()
	pillar_deck.clear()
	for k in pillars.size():
		pillar_deck.append(pillars[k][2])
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
		var rec := {"foot": r, "h": h, "box": [boxes.size()], "roof": -1, "hidden": STANDING}
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
	shadow_mat = ShaderMaterial.new()
	var sm := shadow_mat
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
	var b: Rect2 = C.bounds.grow(320.0)
	for k in 160:  # woods out in the country, clear of the roads
		var g := Vector2(r.randf_range(b.position.x, b.end.x), r.randf_range(b.position.y, b.end.y))
		var rad := r.randf_range(4.0, 14.0)
		for j in int(rad * rad * 0.12) + 3:
			var p := g + Vector2.from_angle(r.randf() * TAU) * rad * sqrt(r.randf())
			if Sim.City.nearest(C, p)[1] > Sim.City.URBAN + 8.0 and not Sim.City.blocked(C, Rect2(p - Vector2.ONE, Vector2(2, 2))):
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
		lit_mats.append([weakref(m), Color.WHITE])
		var list: Array = spots[id]
		var mm := multimesh(q, list.size())
		var base := []
		for k in list.size():
			var tf := Transform3D(Basis.from_scale(Vector3.ONE * list[k][1]), list[k][0])
			mm.set_instance_transform(k, tf)
			base.append(tf)
		mm_node(mm, m, city)
		tree_mms.append([mm, base, qs.y])


## Plots, and in city mode every branch's storefront with its rival beside it (the focused one is the street set).
func build_lots() -> void:
	for c in lots_node.get_children():
		c.free()
	lot_sprites.clear()
	var plot := surface(mat(Color.WHITE, tiles(Color("d8d2c4"), Color("bdb6a6"))))
	for L in sim.lots:
		rect_quad(plot, Rect2(L.x0, L.front - Sim.City.LOT_D, Sim.City.LOT_W, Sim.City.LOT_D), -0.08, 0.0, false, 0.5)
	commit([plot], lots_node)
	for b in sim.branches:
		if mode == "store" and is_same(b, branch):
			continue
		var L: Dictionary = sim.lots[b.lot]
		city_sprite(lots_node, "storefronts", Rect2(0, 0, STOREFRONT.x, STOREFRONT.y), STOREFRONT_PX, Vector3(L.x0 + Sim.City.LOT_W * 0.62, 0, L.front - 0.4), lot_sprites)
		if not b.rival.defeated:
			var o := frame_origin(b.lot)
			var f: int = Sim.RIVALS[b.rival.id].front
			city_sprite(lots_node, "storefronts", Rect2(f * STOREFRONT.x, 0, STOREFRONT.x, STOREFRONT.y), STOREFRONT_PX, Vector3(o.x + rival_span(b.rival).x + 4.0, 0, L.front - 0.4), lot_sprites)


## World position of a lot's street frame: your shop centred on the lot, its facade on the lot's front edge.
func frame_origin(li: int) -> Vector3:
	var L: Dictionary = sim.lots[li]
	return Vector3(L.x0 + Sim.City.LOT_W / 2 + 10.0, 0, L.front + 7.2)


## The rival building's x span (street frame): its door a third of the way in from the end facing you.
static func rival_span(r: Dictionary) -> Vector2:
	var c: float = r.x + 0.35 * r.width
	return Vector2(c - r.width / 2, c + r.width / 2)


## What the lots look like; build_lots runs only when this changes.
func city_signature() -> String:
	var parts := [mode, str(branch.get("id", -1))]
	for L in sim.lots:
		parts.append(L.use)
	for b in sim.branches:
		parts.append("%d%s%s" % [b.lot, b.rival.id, b.rival.defeated])
	return ",".join(parts)


## Store mode carves the street set into Tokyo: city buildings, trees, decks and sprites on its street, on the open
## ground in front of it or where the set builds its own go, and those in front that would cover the street are cut
## away. Everywhere else behind the street the city stays, its roads included.
func update_fade() -> void:
	var on := mode == "store" and not branch.is_empty()
	var front := Rect2()  # the set's street and the open ground between it and the camera
	var scr := Rect2()
	var depth := INF
	if on:
		var o := site.position
		front = Rect2(o.x + SET.position.x, o.z - 7.2, SET.size.x, SET.end.y + 7.2)
		scr = foot_rect(Rect2(o.x - 24.0, o.z - 18.0, 54.0, 26.0), 5.0)
		depth = o.x + o.z
	var taken := func(f: Rect2) -> bool: return on and (f.intersects(front) or set_feet.any(func(q): return f.intersects(q)))
	for e in lm_sprites + lot_sprites:
		var s: Sprite3D = e[0]
		var at_ := Vector2(s.position.x, s.position.z)
		var base := iso(s.position - Vector3(0, s.position.y, 0))
		var tall: float = s.region_rect.size.y * s.pixel_size
		var r := Rect2(base + Vector2(-e[1], -tall * 0.87), Vector2(e[1] * 2, tall * 0.87))
		s.visible = not taken.call(Rect2(at_ - Vector2(0.5, 0.5), Vector2.ONE))
		var fade_it: bool = on and r.intersects(scr) and at_.x + at_.y > depth
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED if fade_it else SpriteBase3D.ALPHA_CUT_DISCARD
		s.set_meta("base", Color(1, 1, 1, 0.25) if fade_it else Color.WHITE)
		shine(s)
	var away := Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -50, 0))
	# city buildings in front of the street are cut down to their ground floor (cut back to the far edge of the
	# near sidewalk when they reach over it), so the street shows over a block that still reads as city
	var edge := front.position.y + 14.8
	var dirty := {}
	for rec in brecs:
		var f: Rect2 = rec.foot
		var state := STANDING
		if on:
			if set_feet.any(func(q): return f.intersects(q)) or (f.intersects(front) and f.get_center().y < front.position.y + 7.2):
				state = GONE
			elif f.intersects(front) or (f.end.x + f.end.y > depth and foot_rect(f, rec.h).intersects(scr)):
				state = maxf(f.position.y, edge)
				var t0: Transform3D = box_base[rec.box[0]]
				if f.end.y - state < 2.0 or (state > f.position.y and t0.basis.x.z != 0.0):  # too thin, or turned
					state = GONE
		if state == rec.hidden:
			continue
		rec.hidden = state
		dirty[box_mm] = true
		for i in rec.box.size():
			var k: int = rec.box[i]
			var t: Transform3D = box_base[k]
			var sz := t.basis.get_scale()
			var cd := box_mm.get_instance_custom_data(k)
			if state == STANDING:
				box_mm.set_instance_transform(k, t)
				box_mm.set_instance_custom_data(k, Color(cd.r, sz.y, sz.z, cd.a))
			elif state == GONE or i > 0:
				box_mm.set_instance_transform(k, away)
			else:
				var z0 := maxf(state, t.origin.z - sz.z / 2)
				var z1 := t.origin.z + sz.z / 2
				box_mm.set_instance_transform(k, Transform3D(t.basis.orthonormalized() * Basis.from_scale(Vector3(sz.x, LOW, z1 - z0)), Vector3(t.origin.x, LOW / 2, (z0 + z1) / 2)))
				box_mm.set_instance_custom_data(k, Color(cd.r, LOW, z1 - z0, cd.a))
		if rec.roof >= 0:
			roof_mm.set_instance_transform(rec.roof, roof_base[rec.roof] if state == STANDING else away)
			dirty[roof_mm] = true
	for tm in tree_mms:
		for k in tm[1].size():
			var p: Vector3 = tm[1][k].origin
			var cut: bool = taken.call(Rect2(p.x - 1.5, p.z - 1.5, 3, 3)) or (on and p.x + p.z > depth and foot_rect(Rect2(p.x - 1.5, p.z - 1.5, 3, 3), tm[2]).intersects(scr))
			if tm[0].get_instance_transform(k) != (away if cut else tm[1][k]):
				tm[0].set_instance_transform(k, away if cut else tm[1][k])
				dirty[tm[0]] = true
	# a deck 6 m up hides the ground about 10 m behind it, so decks go only over the street and in front of it
	var over := Rect2(front.position.x - 4.0, front.position.y - 1.3, front.size.x + 8.0, 28.0)
	for part in elevated:
		part[0].visible = not on or not seg_hits(over, part[1], part[2])
		if part.size() > 3:
			part[3].visible = part[0].visible
	for k in pillar_base.size():  # a pillar goes with its deck
		var p: Vector3 = pillar_base[k].origin
		var deck: MeshInstance3D = pillar_deck[k]
		var cut: bool = taken.call(Rect2(p.x - 1.0, p.z - 1.0, 2, 2)) or (deck != null and not deck.visible)
		if pillar_mm.get_instance_transform(k) != (away if cut else pillar_base[k]):
			pillar_mm.set_instance_transform(k, away if cut else pillar_base[k])
			dirty[pillar_mm] = true
	# the Compatibility renderer can keep drawing a MultiMesh's old instances after it has been drawn and then edited
	# in place, so an edited one is swapped for a fresh copy, which uploads whole
	for mm in dirty:
		var fresh: MultiMesh = mm.duplicate()
		for n in city.get_children() + (mask_vp.get_children() if mask_vp else []):
			if n is MultiMeshInstance3D and n.multimesh == mm:
				n.multimesh = fresh
		if mm == box_mm:
			box_mm = fresh
		elif mm == roof_mm:
			roof_mm = fresh
		elif mm == pillar_mm:
			pillar_mm = fresh
		else:
			for tm in tree_mms:
				if tm[0] == mm:
					tm[0] = fresh
	if mask_vp:
		mask_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


static func seg_hits(r: Rect2, a: Vector2, b: Vector2) -> bool:
	return Sim.City.seg_rect_dist(a, b, r) <= 0.0 or r.has_point(a) or r.has_point(b)


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


## Every road as a path for city movers: side streets, avenues, the expressway (cars only) and the Yamanote (trains).
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
		lit_sprites.append(node)
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
	var r := cam.size * 0.85 * maxf(size.x / size.y, 16.0 / 9.0)  # wide screens see further along the street
	return Rect2(view_center() - Vector2(r, r), Vector2(r, r) * 2.0)


## The set's own street, sidewalk to sidewalk, in the world (empty outside store mode): city movers keep off it,
## while the city roads either side of it stay open to them.
func set_area() -> Rect2:
	if mode != "store" or branch.is_empty():
		return Rect2()
	return Rect2(site.position.x + SET.position.x, site.position.z - 7.2, SET.size.x, 14.4)


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
	var area := set_area()
	for k in 8:
		var try_s: float = clampf(sc + randf_range(-1.0, 1.0) * view.size.x * 0.7, 0.0, p.cum[-1])
		var at_: Vector3 = path_at(p, try_s)[0]
		var q := Vector2(at_.x, at_.z)
		if view.has_point(q) and not area.has_point(q) and (mid or q.distance_to(view.get_center()) > view.size.x * 0.3):
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
		node.add_child(shadow(m.y, 1.5))
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
	var lanes := 1 if p.w <= Sim.City.ROAD else 2
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


## Advances a walk cycle; speed 0 shows the standing frame.
func stride(p: Dictionary, speed: float, delta: float) -> void:
	var col := 0
	if speed > 0.0:
		p.step += delta * minf(speed * STRIDE, MAX_FPS)
		col = 1 + int(p.step) % 4
	p.node.region_rect = Rect2(col * PERSON.x, p.a * PERSON.y, PERSON.x, PERSON.y)


## A soft round shadow at a sprite's feet, `drop` below its centre, r across.
func shadow(drop := 0.8, r := 0.5) -> MeshInstance3D:
	var sh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(r, r) * 2.0
	sh.mesh = pm
	sh.material_override = soft_mat
	sh.position = Vector3(0, 0.02 - drop, 0)
	return sh


## The same soft shadow on the set's ground, for street furniture.
func blob(parent: Node3D, at: Vector2, r: float) -> void:
	plane(parent, Vector2(r, r) * 2.0, Vector3(at.x, -0.035, at.y), soft_mat)


## City walkers and traffic round the view (walkers only when close enough to see), kept out of the street set.
func street_life(delta: float) -> void:
	var busy: float = Sim.band(sim.hour()).traffic / 1.2 if sim.phase == "playing" else 1.0
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
	var area := set_area()
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
		shine(o.node)
		o.node.visible = not area.has_point(Vector2(o.node.position.x, o.node.position.z)) or o.node.position.y > 3.0
		if o.has("a"):
			stride(o, absf(o.v), delta)
			o.node.flip_h = o.dir.dot(cam.global_transform.basis.x) < 0.0
		else:
			facing(o.node, o.dir, o.kv * 2, VEHICLE_CELL)
	for o in gone:
		o.node.queue_free()
	walkers = walkers.filter(func(o): return not gone.has(o))
	cars = cars.filter(func(o): return not gone.has(o))
	for trn in trains:
		trn.s = fposmod(trn.s + trn.v * delta, trn.path.cum[-1])
		place(trn)
		facing(trn.node, trn.dir, 0, TRAIN)
		trn.node.visible = not area.grow(10.0).has_point(Vector2(trn.node.position.x, trn.node.position.z))


func speckle(colors: Array) -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, colors[0] if r.randf() < 0.55 else colors[r.randi() % colors.size()])
	return ImageTexture.create_from_image(img)


# ---------- the street set: your shop, the rival, the street ----------

## Shows branch i: places the set on its lot and frames it.
func show_branch(i: int) -> void:
	var b: Dictionary = sim.branches[i]
	var moved := not is_same(b, branch)
	branch = b
	if moved:
		clear_actors()
		floaters.clear()
		set_sig = ""
		set_feet.clear()
		site.position = frame_origin(b.lot)
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
	site.visible = mode == "store"
	if reframe:
		cam_offset = Vector3.ZERO
		zoom = 1.0
	update_camera()
	update_fade()
	night = -1.0  # relight: built or rebuilt, or switched between store and city


## The set's look: rebuilt when the shop grows, gets a line or a facility, or the rival changes hands.
func scene_signature() -> String:
	var st: Dictionary = branch.store
	return "%d|%s|%s|%s|%s|%s" % [st.size, ",".join(st.products.keys()), ",".join(st.facilities), branch.rival.id, branch.rival.defeated, st.registers[1].active]


func build_set() -> void:
	for c in set_node.get_children():
		c.free()
	for c in room.get_children():
		c.free()
	slot_icons.clear()
	pools.clear()
	var b := branch
	var st: Dictionary = b.store
	var type: String = sim.districts[sim.lots[b.lot].block].type
	var zl: float = Sim.ZONE_LEFT[st.size]
	shop_area = Rect2(site.position.x + Sim.ORIGIN.x + zl, site.position.z + Sim.ORIGIN.y - 4.7, 6.6 - zl, 9.4)
	# ground: the sidewalks, the road with its centre line and crossing. Either side the city's own blocks and roads
	# show, so the side streets and avenues that cross the set run on through it.
	var span := rival_span(b.rival)
	var roads := roads_near()
	var side_roads := roads.filter(func(rd): return rd is Array or rd.size.y > rd.size.x)  # avenues and cross streets
	# where the set runs out over water (the bay, a canal) it stands on made ground: its street with a strip either
	# side, and the lots of your shop and the rival. Elsewhere the water stays and the neighbours keep out of it.
	var made := surface(mat(Color("bfc4a6") if type in ["homes", "oldtown", "park"] else (Color("b8b2a6") if type == "market" else Color("cdc6b6"))))
	if near_water():
		for w in water_runs(-9.2, 9.2) + water_runs(-20.2, -7.2, -16.5, span.y):
			rect_quad(made, w, -0.125)  # over the water, under any bridge
		roads.append_array(water_runs(SET.position.y, -20.2) + water_runs(-20.2, -7.2, SET.position.x, -16.5) + water_runs(-20.2, -7.2, span.y, SET.end.x))
	var far_gaps := mouths(-8.2, -3.6, side_roads, Vector2(-16.5, span.y))  # none between your shop and the rival
	var near_gaps := mouths(3.6, 8.2, side_roads)
	var walk := surface(mat(Color.WHITE, tiles(Color("c9c4bb"), Color("a9a49b"))))
	var tar := surface(tiled(speckle([Color("5d5f66"), Color("585a61"), Color("63656c"), Color("55575d")]), Vector2.ONE))
	rect_quad(tar, Rect2(SET.position.x, -3.7, SET.size.x, 7.4), -0.045, 0.0, false, 0.5)
	var kerb := surface(mat(Color("8f8b84")))
	var tactile := surface(mat(Color("d2b862")))  # the yellow guide strip down each sidewalk
	for sd in [[far_gaps, -7.2, -3.8, -5.4], [near_gaps, 3.7, 3.6, 5.0]]:
		for o in open_spans(sd[0]):
			rect_quad(walk, Rect2(o.x, sd[1], o.y - o.x, 3.5), -0.045, 0.0, false, 0.5)
			rect_quad(kerb, Rect2(o.x, sd[2], o.y - o.x, 0.2), -0.04)
			rect_quad(tactile, Rect2(o.x, sd[3], o.y - o.x, 0.32), -0.042)
		for g in sd[0]:  # a side road's mouth: the asphalt runs through the sidewalk
			rect_quad(tar, Rect2(g.x, sd[1], g.y - g.x, 3.5), -0.045, 0.0, false, 0.5)
	var paint := surface(mat(Color("ebe7dc")))
	var x := SET.position.x
	while x < SET.end.x:
		if x + 2.0 < Sim.CROSS_X - 2.0 or x > Sim.CROSS_X + 2.0:
			rect_quad(paint, Rect2(x, -0.08, 2.0, 0.16), -0.04)
		x += 4.0
	var z := -3.3
	while z < 3.4:
		rect_quad(paint, Rect2(Sim.CROSS_X - 1.5, z, 3.0, 0.42), -0.04)
		z += 0.84
	# edge lines inside the kerbs, broken at the crossing and at side roads; a zebra across each side road's mouth
	for sd in [[far_gaps, -3.42, -6.95], [near_gaps, 3.3, 4.05]]:
		for o in open_spans(sd[0]):
			for seg in [Vector2(o.x, minf(o.y, Sim.CROSS_X - 1.7)), Vector2(maxf(o.x, Sim.CROSS_X + 1.7), o.y)]:
				if seg.y - seg.x > 0.5:
					rect_quad(paint, Rect2(seg.x, sd[1], seg.y - seg.x, 0.12), -0.04)
		for g in sd[0]:
			var zx: float = g.x + 0.5
			while zx + 0.45 < g.y - 0.4:
				rect_quad(paint, Rect2(zx, sd[2], 0.45, 2.9), -0.04)
				zx += 0.9
	# your parking: bays and bicycles between your shop and the alley, nothing tall to hide the till
	var bay := surface(mat(Color("74767c")))
	rect_quad(bay, Rect2(-3.4, -16.0, 7.1, 8.8), -0.042)
	for bx in [-2.2, 0.2, 2.6]:
		rect_quad(paint, Rect2(bx, -15.6, 0.12, 4.6), -0.038)
	commit([made, walk, tar, paint, kerb, bay, tactile], set_node)
	for cx in [-1.0, 1.4]:  # wheel stops
		block(set_node, Vector3(1.5, 0.12, 0.2), Vector3(cx, 0.02, -15.3), Color("bdb8ad"))
	var kv: int = b.lot % 3
	var car := sprite("vehicles", Rect2(kv * 2 * VEHICLE_CELL.x, 0, VEHICLE_CELL.x, VEHICLE_CELL.y), VEHICLE_PX)
	car.position = Vector3(1.4, VEHICLE_CELL.y / 2.0 * VEHICLE_PX - 0.1, -13.0)
	set_node.add_child(car)
	facing(car, Vector3(0, 0, -1), kv * 2, VEHICLE_CELL)  # nosed in towards the shop
	car.add_child(shadow(car.position.y, 1.5))
	lit_sprites.append(car)
	# your pole sign in the back corner of the car park, clear of the shop, lit like the shop after dark
	var ps := Vector3(3.0, 0, -16.5)
	block(set_node, Vector3(0.22, 6.2, 0.22), ps + Vector3(0, 3.1, 0), Color("9aa0a6"))
	block(set_node, Vector3(1.7, 1.5, 0.34), ps + Vector3(0, 6.4, 0), Color("fbfaf5"), true)
	block(set_node, Vector3(1.72, 0.2, 0.36), ps + Vector3(0, 6.15, 0), LAYOUT.stripe[0], true)
	block(set_node, Vector3(1.72, 0.2, 0.36), ps + Vector3(0, 5.92, 0), LAYOUT.stripe[1], true)
	blob(set_node, Vector2(ps.x, ps.z), 0.3)
	for mh in [Vector2(-34.0, -1.9), Vector2(-17.0, 1.9), Vector2(13.0, -1.9), Vector2(33.0, 1.9)]:
		for ring in [[0.46, Color("74767c"), -0.039], [0.36, Color("4d4f55"), -0.037]]:
			var disc := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = ring[0]
			cm.bottom_radius = ring[0]
			cm.height = 0.002
			cm.radial_segments = 20
			disc.mesh = cm
			disc.material_override = mat(ring[1])
			disc.position = Vector3(mh.x, ring[2], mh.y)
			set_node.add_child(disc)
	# utility poles and their sagging wires along the far sidewalk
	var wires := surface(mat(Color("34343a")))
	var poles := [SET.position.x, -42.0, -19.0, 12.0, 36.0, SET.end.x].filter(func(px): return absf(px) == SET.end.x or not in_gaps(px, near_gaps))
	for k in poles.size():
		var px: float = poles[k]
		if k > 0 and k < poles.size() - 1:
			block(set_node, Vector3(0.24, 7.0, 0.24), Vector3(px, 3.5, 6.85), Color("a19d94"))
			block(set_node, Vector3(0.3, 1.1, 0.3), Vector3(px, 0.55, 6.85), Color("e3c34a"))
			block(set_node, Vector3(0.12, 0.12, 1.4), Vector3(px, 6.6, 6.85), Color("6f6c66"))
			if k % 2 == 0:
				block(set_node, Vector3(0.5, 0.75, 0.5), Vector3(px, 5.5, 7.2), Color("8a979c"))
			blob(set_node, Vector2(px, 6.85), 0.3)
		if k == 0:
			continue
		var x0: float = poles[k - 1]
		for dz in [-0.55, 0.0, 0.55]:
			var pts := PackedVector3Array()
			for i in 9:
				var t := i / 8.0
				pts.append(Vector3(lerpf(x0, px, t), 6.66 - 0.035 * (px - x0) * 4.0 * t * (1.0 - t), 6.85 + dz))
			wall(wires, pts, 0.0, -0.025, 0.025)
	commit([wires], set_node)
	# neighbours: the district's own mix of buildings either side of your shop and the rival, a row behind them
	var mix: Array = Sim.City.MIX[type]
	var r := RandomNumberGenerator.new()
	r.seed = b.lot * 7919 + 3
	var boxes := []
	var roofs := []
	var mine: float = -10.0 + Sim.ZONE_LEFT[st.size]
	for seg in [[SET.position.x, -27.75], [-26.25, -16.5], [span.y, 29.75], [31.25, SET.end.x]]:
		set_row(seg[0], seg[1], -7.2, 13.0, mix, r, boxes, roofs, 0.7, roads)
	set_row(5.35, span.x, -7.2, 9.0, [[1, Sim.City.SHOPS, 1, 1, 6, 9, 9, 9]], r, boxes, roofs, 1.4, roads)  # low, so it doesn't hide your till
	set_row(SET.position.x, SET.end.x, -20.5, 11.0, mix, r, boxes, roofs, 1.0, roads)
	var bm := multimesh(BoxMesh.new(), boxes.size(), true, true)
	for k in boxes.size():
		var e: Array = boxes[k]
		bm.set_instance_transform(k, Transform3D(Basis.from_scale(e[0]), e[1]))
		bm.set_instance_color(k, e[2])
		bm.set_instance_custom_data(k, Color(e[0].x, e[0].y, e[0].z, e[3]))
	mm_node(bm, building_mat, set_node)
	if not roofs.is_empty():
		var rm := multimesh(PrismMesh.new(), roofs.size(), true, true)
		for k in roofs.size():
			var e: Array = roofs[k]
			var sz: Vector3 = e[0]
			var basis := Basis.from_scale(sz) if sz.x <= sz.z else Basis(Vector3.UP, PI / 2) * Basis.from_scale(Vector3(sz.z, sz.y, sz.x))
			rm.set_instance_transform(k, Transform3D(basis, e[1]))
			rm.set_instance_color(k, e[2])
			rm.set_instance_custom_data(k, Color(0, 0, 0, -1))
		mm_node(rm, building_mat, set_node)
	# the part of your unit you haven't knocked through yet
	if mine > -16.5:
		# stops short of your left wall, so the two faces don't fight
		block(set_node, Vector3(mine + 16.2, 3.6, 9.0), Vector3((mine - 16.8) / 2, 1.8, -11.7), Color("d9d3c4"))
		block(set_node, Vector3(mine + 16.2, 2.6, 0.06), Vector3((mine - 16.8) / 2, 1.3, -7.18), Color("a7a399"))
	build_rival(span)
	build_room()
	# a soft dark seam where each building meets the sidewalk
	var seam := surface(ao_mat)
	var fronts := [Vector2(span.x, span.y)]
	if mine > -16.5:
		fronts.append(Vector2(-16.5, mine - 0.3))
	for e in boxes:
		if absf(e[1].z + e[0].z / 2 + 7.2) < 0.3:
			fronts.append(Vector2(e[1].x - e[0].x / 2, e[1].x + e[0].x / 2))
	for f in fronts:
		rect_quad(seam, Rect2(f.x, -7.2, f.y - f.x, 0.9), -0.036)
	commit([seam], set_node)
	# street furniture
	var props_at := [[6, Vector2(-22.0, -4.3)], [6, Vector2(-38.0, -4.3)], [6, Vector2(9.0, -4.3)], [6, Vector2(34.0, -4.3)],
		[1, Vector2(-30.0, 5.6)], [2, Vector2(-14.0, 5.6)], [1, Vector2(12.0, 5.6)], [0, Vector2(26.0, 5.6)], [1, Vector2(42.0, 5.6)],
		[6, Vector2(-6.0, 4.3)], [6, Vector2(20.0, 4.3)], [7, Vector2(-1.6, -4.6)], [10, Vector2(-22.6, -6.6)],
		[8, Vector2(-1.5, -12.4)], [8, Vector2(-0.4, -12.8)], [4, Vector2(3.3, -15.2)]]
	if b.quirk == "busStop":
		props_at.append([11, Vector2(-24.5, -4.4)])
	for p in props_at:
		if in_gaps(p[1].x, far_gaps if p[1].y < 0.0 else near_gaps):
			continue
		var s := sprite("outdoor", Rect2(p[0] * OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * OUTDOOR_SCALE[p[0]] * 0.55)
		s.position = Vector3(p[1].x, OUTDOOR / 2.0 * OUTDOOR_PX * OUTDOOR_SCALE[p[0]] * 0.55 - 0.05, p[1].y)
		set_node.add_child(s)
		lit_sprites.append(s)
		blob(set_node, p[1], OUTDOOR_SCALE[p[0]] * (0.45 if p[0] == 6 else 1.5))
		if p[0] == 6:
			pool(set_node, Vector3(p[1].x, 0, p[1].y), Vector2(7.0, 7.0))
	pool(set_node, Vector3(Sim.ORIGIN.x + (zl + 6.6) / 2, 0, Sim.ORIGIN.y + 4.7), Vector2(10.6 - zl, 6.0))  # your shop's glass front
	for d in [[0, Vector2(-6.7, -6.75), 0.6], [0, Vector2(-4.1, -6.75), 0.6], [5, Vector2(-8.3, -6.2), 0.7]]:
		var s := sprite("decor", Rect2(d[0] * DECOR, 0, DECOR, DECOR), DECOR_PX * d[2])
		s.position = Vector3(d[1].x, DECOR / 2.0 * DECOR_PX * d[2], d[1].y)
		set_node.add_child(s)
		lit_sprites.append(s)
		blob(set_node, d[1], 0.45)
	for pole in [Vector3(Sim.CROSS_X - 1.8, 0, -4.0), Vector3(Sim.CROSS_X + 1.8, 0, 4.0)].filter(func(q): return not in_gaps(q.x, far_gaps if q.z < 0.0 else near_gaps)):
		block(set_node, Vector3(0.12, 2.6, 0.12), pole + Vector3(0, 1.3, 0), Color("4a4d57"))
		block(set_node, Vector3(0.36, 0.7, 0.3), pole + Vector3(0, 2.5, 0), Color("2b2d42"))
	# outside facilities
	var outside := {"vending": ["decor", 2, Vector3(Sim.VENDING_X, 0, -7.0)], "gacha": ["decor", 3, Vector3(Sim.GACHA_X, 0, -7.0)],
		"bench": ["decor", 1, Vector3(-13.6, 0, -6.6)], "delivery": ["perks", 7, Vector3(-2.4, 0, -6.4)]}
	for f in st.facilities:
		if outside.has(f):
			var e: Array = outside[f]
			var cell := DECOR if e[0] == "decor" else 80
			var px := DECOR_PX if e[0] == "decor" else 0.012
			var s := sprite(e[0], Rect2(e[1] * cell, 0, cell, cell), px)
			s.position = e[2] + Vector3(0, cell / 2.0 * px, 0)
			set_node.add_child(s)
			lit_sprites.append(s)
			blob(set_node, Vector2(e[2].x, e[2].z), 0.6 if f == "delivery" else 0.8)
			if f in ["vending", "gacha"]:
				pool(set_node, e[2] + Vector3(0, 0, 0.6), Vector2(3.5, 3.5))
	if st.facilities.has("neon"):
		block(set_node, Vector3(6.0, 0.7, 0.2), Vector3(-6.5, 3.75, -7.1), Color("ff4fa0"), true)
	# the city gives way to everything built behind the street: your shop, the rival and the rows of neighbours
	var o2 := Vector2(site.position.x, site.position.z)
	set_feet = [Rect2(o2 + Vector2(-16.5, -20.2), Vector2(span.y + 16.5, 13.0))]
	for e in boxes:
		set_feet.append(Rect2(o2 + Vector2(e[1].x - e[0].x / 2, e[1].z - e[0].z / 2), Vector2(e[0].x, e[0].z)))
	update_fade()
	set_sig = scene_signature()
	night = -1.0  # relight the new set


## A row of district buildings fronting z = zf (northwards into the block), shoulder to shoulder from x0 to x1.
## Gaps are left wherever a city road crosses the row, so the road runs on between the buildings.
func set_row(x0: float, x1: float, zf: float, max_depth: float, mix: Array, r: RandomNumberGenerator, boxes: Array, roofs: Array, tall: float, roads: Array) -> void:
	for run in free_runs(x0, x1, zf - max_depth, zf, roads):
		fill_row(run.x, run.y, zf, max_depth, mix, r, boxes, roofs, tall)


func fill_row(x0: float, x1: float, zf: float, max_depth: float, mix: Array, r: RandomNumberGenerator, boxes: Array, roofs: Array, tall: float) -> void:
	var w8 := PackedFloat32Array(mix.map(func(m): return float(m[0])))
	var pos := x0
	while x1 - pos > 2.5:
		var m: Array = mix[r.rand_weighted(w8)]
		var w := minf(r.randf_range(m[4], m[5]), x1 - pos)
		if x1 - pos - w < 3.0:
			w = x1 - pos
		var dep := clampf(r.randf_range(m[6], m[7]), max_depth * 0.6, max_depth)
		var floors := maxi(1, roundi(r.randf_range(m[2], m[3] + 0.99) * tall * 0.75))
		var fp := Rect2(pos + 0.15, zf - dep, w - 0.3, dep)
		var bd: Dictionary = Sim.City._building(r, m[1], fp, floors)
		var h: float = bd.floors * Sim.City.FLOOR
		var tint: Color = bd.tint
		tint.a = (bd.accent + 0.5) / 8.0
		boxes.append([Vector3(fp.size.x, h, fp.size.y), Vector3(fp.get_center().x, h / 2, fp.get_center().y), tint, bd.style + bd.kit * 0.49])
		if bd.roof != "":
			var rh := minf(fp.size.x, fp.size.y) * 0.32
			roofs.append([Vector3(fp.size.x, rh, fp.size.y), Vector3(fp.get_center().x, h + rh / 2, fp.get_center().y), Color(bd.roof)])
		pos += w


## The city's streets (rects) and avenue pieces ([a, b, half width]) that cross the set, in the street frame.
func roads_near() -> Array:
	var o := Vector2(site.position.x, site.position.z)
	var area := Rect2(o + SET.position, SET.size)
	var out := []
	for s in C.streets:
		var rr := Rect2(s.from, s.line, s.to - s.from, s.w) if s.axis == "h" else Rect2(s.line, s.from, s.w, s.to - s.from)
		if rr.intersects(area):
			out.append(Rect2(rr.position - o, rr.size))
	for av in C.avenues:
		for i in range(1, av.pts.size()):
			if seg_hits(area.grow(av.w / 2), av.pts[i - 1], av.pts[i]):
				out.append([av.pts[i - 1] - o, av.pts[i] - o, av.w / 2])
	return out


## Whether any water reaches into the set: a 4 m sample, narrower than any canal, so inland sets skip the fine scan.
func near_water() -> bool:
	var o := Vector2(site.position.x, site.position.z)
	for x in range(int(SET.position.x), int(SET.end.x) + 1, 4):
		for z in range(int(SET.position.y), int(SET.end.y) + 1, 4):
			if Sim.City.is_water(C, o + Vector2(x, z)):
				return true
	return false


## Water in the band z0..z1 between x0 and x1 (street frame), as runs 1 m deep on a 1 m grid.
func water_runs(z0: float, z1: float, x0: float = SET.position.x, x1: float = SET.end.x) -> Array:
	var o := Vector2(site.position.x, site.position.z)
	var out := []
	var z := z0
	while z < z1:
		var h := minf(1.0, z1 - z)
		var start := INF
		var x := x0
		while x < x1:
			var wet := Sim.City.is_water(C, o + Vector2(x + 0.5, z + h / 2))
			if wet and start == INF:
				start = x
			elif not wet and start < INF:
				out.append(Rect2(start, z, x - start, h))
				start = INF
			x += 1.0
		if start < INF:
			out.append(Rect2(start, z, x1 - start, h))
		z += h
	return out


## Where side roads meet the set's sidewalk band z0..z1, as x spans, leaving out any that touch `keep`.
func mouths(z0: float, z1: float, roads: Array, keep := Vector2(INF, INF)) -> Array:
	var out := []
	var x := SET.position.x
	for run in free_runs(SET.position.x, SET.end.x, z0, z1, roads) + [Vector2(SET.end.x, SET.end.x)]:
		if run.x > x and (x >= keep.y or run.x <= keep.x):
			out.append(Vector2(x, run.x))
		x = run.y
	return out


## The set's length with the gaps taken out.
static func open_spans(gaps: Array) -> Array:
	var out := []
	var x := SET.position.x
	for g in gaps + [Vector2(SET.end.x, SET.end.x)]:
		if g.x > x:
			out.append(Vector2(x, g.x))
		x = g.y
	return out


static func in_gaps(x: float, gaps: Array) -> bool:
	return gaps.any(func(g): return x > g.x - 0.6 and x < g.y + 0.6)


## The stretches of x0..x1 where the band z0..z1 is clear of every road, as Vector2(from, to), on a 0.5 m grid.
static func free_runs(x0: float, x1: float, z0: float, z1: float, roads: Array) -> Array:
	var band := Rect2(x0, z0, x1 - x0, z1 - z0)
	roads = roads.filter(func(rd): return band.intersects(rd, true) if rd is Rect2 else band.grow(rd[2]).intersects(Rect2(rd[0], Vector2.ZERO).expand(rd[1]), true))
	var runs := []
	var start := INF
	var x := x0
	while x < x1:
		var cell := Rect2(x, z0 + 0.05, minf(0.5, x1 - x), z1 - z0 - 0.1)  # inset, so a road only touching the band doesn't count
		var hit := roads.any(func(rd): return cell.intersects(rd) if rd is Rect2 else Sim.City.seg_rect_dist(rd[0], rd[1], cell) <= rd[2])
		if hit and start < INF:
			runs.append(Vector2(start, x))
			start = INF
		elif not hit and start == INF:
			start = x
		x += 0.5
	if start < INF:
		runs.append(Vector2(start, x1))
	return runs


## The rival's shop: chain colours on the fascia and awning, glass front; shutters once it has closed.
func build_rival(span: Vector2) -> void:
	var rv: Dictionary = branch.rival
	var w := span.y - span.x
	var cx := (span.x + span.y) / 2
	var c := Color(Sim.RIVALS[rv.id].color)
	block(set_node, Vector3(w, 4.2, 9.0), Vector3(cx, 2.1, -11.7), Color("f1eee6"))
	block(set_node, Vector3(w + 0.1, 0.8, 0.12), Vector3(cx, 3.65, -7.16), Color("8a8780") if rv.defeated else c)
	if rv.defeated:
		block(set_node, Vector3(w - 0.8, 2.9, 0.08), Vector3(cx, 1.45, -7.12), Color("a9a59c"))
		return
	# fascia in the chain's stripes, a grey roof inside a white rim with its air-conditioning units
	var band := Image.create(1, 10, false, Image.FORMAT_RGB8)
	band.fill(c)
	band.set_pixel(0, 6, Color.WHITE)
	for y in [7, 8, 9]:
		band.set_pixel(0, y, c.darkened(0.25))
	art_panel(set_node, band, Vector2(w + 0.1, 0.8), Vector3(cx, 3.65, -7.095))
	block(set_node, Vector3(w - 0.6, 0.05, 8.4), Vector3(cx, 4.22, -11.7), Color("a3a29e"))
	for k in 3:
		block(set_node, Vector3(1.0, 0.55, 0.9), Vector3(cx - w * 0.3 + k * 1.4, 4.5, -13.5 + k % 2 * 1.6), Color("cfd0cc"))
	# the shop floor behind the glass (the chain's shelves, lit at night), mullions, the sliding door
	var shelves: Image = load("res://art/bg_super.png").get_image().get_region(Rect2i(80, 126, 560, 119))
	art_panel(set_node, shelves, Vector2(w - 0.8, 2.6), Vector3(cx, 1.3, -7.075), Color(0.86, 0.94, 1.0))
	block(set_node, Vector3(w - 0.8, 0.12, 0.12), Vector3(cx, 2.6, -7.06), Color("5e6670"))
	block(set_node, Vector3(w - 0.8, 0.16, 0.14), Vector3(cx, 0.08, -7.06), Color("5e6670"))
	var x0 := span.x + 0.4
	while x0 < span.y - 0.3:
		if absf(x0 - rv.x) > 0.8:
			block(set_node, Vector3(0.08, 2.6, 0.1), Vector3(x0, 1.3, -7.05), Color("5e6670"))
		x0 += 2.0
	block(set_node, Vector3(1.4, 2.6, 0.1), Vector3(rv.x, 1.3, -7.05), Color(0.86, 0.93, 0.98, 0.55), true)
	for dx in [-0.72, 0.0, 0.72]:
		block(set_node, Vector3(0.07, 2.6, 0.12), Vector3(rv.x + dx, 1.3, -7.03), Color("8b96a1"))
	block(set_node, Vector3(w, 0.12, 0.9), Vector3(cx, 2.85, -6.7), c.lightened(0.15))
	pool(set_node, Vector3(cx, 0, -7.2), Vector2(w + 2.0, 5.0))


## Your shop as a cutaway (shop-local frame, 1:1): floor, back and side walls, counter and registers, a fixture per
## product line with its stock showing, and the facilities that live inside.
func build_room() -> void:
	var st: Dictionary = branch.store
	var zl: float = Sim.ZONE_LEFT[st.size]
	var w := 6.5 - zl
	var cx := (zl + 6.5) / 2
	var L: Dictionary = LAYOUT
	block(room, Vector3(w + 0.3, 0.2, 9.3), Vector3(cx, -0.1, 0.0), Color("8a6e4b"))
	var fm := mat(Color.WHITE, tiles(L.floor[0], L.floor[1]), true)
	fm.uv1_scale = Vector3(w, 9.0, 1)
	fm.texture_repeat = true
	plane(room, Vector2(w, 9.0), Vector3(cx, 0.002, 0.0), fm)
	# back wall with the shop art, tiled to the width; the left wall plain with the stripes
	var crop: Image = tex[L.bg].get_image().get_region(L.wall)
	var wall_h := 3.0
	block(room, Vector3(w + 0.25, wall_h, 0.25), Vector3(cx, wall_h / 2, -4.62), Color("e6dcc6"))
	art_panel(room, crop, Vector2(w, wall_h), Vector3(cx, wall_h / 2, -4.49), Color.WHITE, w / (wall_h * crop.get_width() / crop.get_height()))
	block(room, Vector3(0.25, wall_h, 9.25), Vector3(zl - 0.125, wall_h / 2, 0.0), Color("efe6d2"))
	block(room, Vector3(0.02, 0.16, 9.0), Vector3(zl + 0.01, wall_h * 0.72, 0.0), L.stripe[0])
	block(room, Vector3(0.02, 0.16, 9.0), Vector3(zl + 0.01, wall_h * 0.62, 0.0), L.stripe[1])
	block(room, Vector3(w + 0.6, 0.14, 0.35), Vector3(cx, wall_h + 0.07, -4.62), Color("5b4632"))
	block(room, Vector3(0.35, 0.14, 9.6), Vector3(zl - 0.125, wall_h + 0.07, 0.0), Color("5b4632"))
	# low stubs where the cut-away right wall and glass front stand, the door gap left open
	block(room, Vector3(0.2, 0.35, 9.25), Vector3(6.6, 0.175, 0.0), Color("efe6d2"))
	block(room, Vector3(Sim.DOOR_IN.x - 0.8 - zl, 0.35, 0.2), Vector3((zl + Sim.DOOR_IN.x - 0.8) / 2, 0.175, 4.6), Color("cfd9de"))
	block(room, Vector3(6.6 - Sim.DOOR_IN.x - 0.8, 0.35, 0.2), Vector3((6.6 + Sim.DOOR_IN.x + 0.8) / 2, 0.175, 4.6), Color("cfd9de"))
	# counter and registers
	block(room, Vector3(0.85, 1.0, 5.3), Vector3(4.5, 0.5, -0.75), Color("f3ecdc"))
	block(room, Vector3(0.87, 0.1, 5.32), Vector3(4.5, 0.62, -0.75), L.stripe[0])
	block(room, Vector3(0.87, 0.1, 5.32), Vector3(4.5, 0.45, -0.75), L.stripe[1])
	for reg in st.registers:
		if reg.active:
			var p: Vector2 = Sim.REGISTERS[reg.id].pos
			var till := sprite("perks", Rect2(10 * 80, 0, 80, 80), 0.0075)
			till.position = Vector3(p.x, 1.28, p.y)
			room.add_child(till)
	# a fixture per product line, its stock as up to three product icons
	for pid in st.products:
		var slot: Dictionary = Sim.SLOTS[Sim.PRODUCTS[pid].slot]
		var p: Vector2 = slot.pos
		var h := 1.0
		match Sim.PRODUCTS[pid].slot:
			"fridgeA", "fridgeB", "fridgeC":
				h = 2.0
				block(room, Vector3(2.3, h, 0.8), Vector3(p.x, h / 2, p.y), Color("dfe9ef"))
				block(room, Vector3(2.2, h - 0.3, 0.05), Vector3(p.x, h / 2, p.y + 0.41), Color("9fd3ea"))
				for y in [0.55, 0.95, 1.35]:  # shelves seen through the glass doors
					block(room, Vector3(2.2, 0.04, 0.02), Vector3(p.x, y, p.y + 0.44), Color("78b6d0"))
				for dx in [-0.37, 0.37]:
					block(room, Vector3(0.06, h - 0.3, 0.07), Vector3(p.x + dx, h / 2, p.y + 0.43), Color("c3ccd2"))
				block(room, Vector3(2.3, 0.18, 0.06), Vector3(p.x, h - 0.09, p.y + 0.42), LAYOUT.stripe[1])
			"shelfA", "shelfB", "shelfC":
				h = 1.4
				block(room, Vector3(2.3, h, 0.8), Vector3(p.x, h / 2, p.y), Color("e9e4d6"))
				block(room, Vector3(2.4, 0.1, 0.9), Vector3(p.x, h + 0.05, p.y), Color("3b3f52"))
				for y in [h / 3, h * 2 / 3]:
					block(room, Vector3(2.34, 0.05, 0.84), Vector3(p.x, y, p.y), Color("cfc4ac"))
			"frontA", "island":
				h = 0.9
				block(room, Vector3(2.3, h, 0.8), Vector3(p.x, h / 2, p.y), Color("eef3f6") if pid == "icecream" else Color("e9e4d6"))
			"rack":
				h = 1.3
				block(room, Vector3(2.0, h, 0.45), Vector3(p.x, h / 2, p.y), Color("b9a37f"))
			_:
				if pid == "coffee":
					var machine := sprite("perks", Rect2(3 * 80, 0, 80, 80), 0.0075)
					machine.position = Vector3(p.x, 1.28, p.y)
					room.add_child(machine)
				else:
					block(room, Vector3(0.5, 0.45, 0.6), Vector3(p.x, 1.22, p.y), {"chicken": Color("c9ccd1"), "oden": Color("8a5a3c")}.get(pid, Color.GRAY))
				h = 1.45
		var icons := []
		var ic: Array = Sim.PRODUCTS[pid].icon
		var cell: int = {"products": ITEM, "perks": 80, "decor": DECOR}[ic[0]]
		var n := 1 if slot.has("pick") == false else 3
		for k in n:
			var s := sprite(ic[0], Rect2(ic[1] * cell, 0, cell, cell), ITEM_PX * ITEM / cell)
			s.position = Vector3(p.x - 0.6 * (n - 1) / 2.0 + 0.6 * k, h + 0.25, p.y + 0.2)
			room.add_child(s)
			icons.append(s)
		slot_icons[pid] = icons
	# inside facilities
	var inside := {"atm": ["decor", 6, Vector3(6.0, 0, 3.7)], "maneki": ["perks", 9, Vector3(4.5, 1.0, 1.75)], "camera": ["perks", 6, Vector3(5.6, 2.5, -4.35)]}
	for f in st.facilities:
		if inside.has(f):
			var e: Array = inside[f]
			var cell := DECOR if e[0] == "decor" else 80
			var px := DECOR_PX if e[0] == "decor" else 0.006
			var s := sprite(e[0], Rect2(e[1] * cell, 0, cell, cell), px)
			s.position = e[2] + Vector3(0, cell / 2.0 * px, 0)
			room.add_child(s)


func refresh_stock() -> void:
	for pid in slot_icons:
		var p: Dictionary = branch.store.products[pid]
		var icons: Array = slot_icons[pid]
		var n := ceili(icons.size() * float(p.stock) / p.capacity)
		for k in icons.size():
			var s: Sprite3D = icons[k]
			s.visible = k < n or (p.stock == 0 and k == floori(icons.size() / 2.0))
			s.modulate = Color(0.4, 0.4, 0.45, 0.8) if p.stock == 0 else Color.WHITE


# ---------- actors: the sim's pedestrians, threats and staff as sprites ----------

func clear_actors() -> void:
	for d in [agent_nodes, threat_nodes, staff_nodes]:
		for id in d:
			d[id].node.queue_free()
		d.clear()


## Keeps one sprite per sim actor; new ones get made, gone ones freed.
func sync_actors(delta: float) -> void:
	var seen := {}
	for a in branch.agents:
		seen[a.id] = true
		var e = agent_nodes.get(a.id)
		if e == null:
			var node := sprite("walk", Rect2(0, (a.look % 7) * PERSON.y, PERSON.x, PERSON.y), PERSON_PX)
			node.add_child(shadow())
			if a.kind == "fan":
				node.set_meta("base", Color(1.0, 0.86, 0.93))
			actors.add_child(node)
			e = {"node": node, "a": a.look % 7, "step": randf() * 4.0}
			agent_nodes[a.id] = e
		e.node.visible = a.state != "inRival"
		move_sprite(e, a, a.speed if not a.inside else Sim.INSIDE_SPEED, delta)
	drop_missing(agent_nodes, seen)
	seen = {}
	var col := Color(Sim.RIVALS[branch.rival.id].color)
	for t in branch.threats:
		seen[t.id] = true
		var e = threat_nodes.get(t.id)
		if e == null:
			e = make_threat(t, col)
			threat_nodes[t.id] = e
		if e.has("a"):
			move_sprite(e, t, 2.0, delta)
		else:
			e.node.position = Vector3(t.x, e.node.position.y, t.z)
	drop_missing(threat_nodes, seen)
	seen = {}
	for s in branch.staff:
		seen[s.id] = true
		var e = staff_nodes.get(s.id)
		if e == null:
			var node: Sprite3D
			if s.role == "cat":
				node = sprite("perks", Rect2(9 * 80, 0, 80, 80), 0.007)
				e = {"node": node, "y": 0.28}
			else:
				node = sprite("walk", Rect2(0, 7 * PERSON.y, PERSON.x, PERSON.y), PERSON_PX)
				node.set_meta("base", ROLE_TINT.get(s.role, Color.WHITE))
				node.add_child(shadow())
				e = {"node": node, "a": 7, "step": 0.0}
			actors.add_child(node)
			staff_nodes[s.id] = e
		if e.has("a"):
			move_sprite(e, s, Sim.STAFF_WALK, delta)
			if not s.moving and s.role in ["cashier", "stocker"]:
				e.node.flip_h = true
		else:
			e.node.position = Vector3(s.x, e.y, s.z)
	drop_missing(staff_nodes, seen)
	for d in [agent_nodes, threat_nodes, staff_nodes]:
		for id in d:
			if d[id].node is Sprite3D:
				shine(d[id].node)


func drop_missing(d: Dictionary, seen: Dictionary) -> void:
	for id in d.keys():
		if not seen.has(id):
			d[id].node.queue_free()
			d.erase(id)


## A walking sprite at a sim position: walk cycle while it moves, facing its heading.
func move_sprite(e: Dictionary, o: Dictionary, speed: float, delta: float) -> void:
	var sc: float = e.get("scale", 1.0)
	e.node.position = Vector3(o.x, 0.82 * sc, o.z)
	var col := 0
	if o.moving:
		e.step += delta * minf(speed * STRIDE, MAX_FPS)
		col = 1 + int(e.step) % 4
		var dir := Vector3(cos(o.heading), 0, sin(o.heading))
		if absf(dir.dot(cam.global_transform.basis.x)) > 0.05:
			e.node.flip_h = dir.dot(cam.global_transform.basis.x) < 0.0
	e.node.region_rect = Rect2(col * PERSON.x, e.a * PERSON.y, PERSON.x, PERSON.y)


func make_threat(t: Dictionary, col: Color) -> Dictionary:
	var e := {}
	var row := {"flyer": 1, "mascot": 6, "shoplifter": 2, "suit": 0}
	if row.has(t.type):
		var node := sprite("walk", Rect2(0, row[t.type] * PERSON.y, PERSON.x, PERSON.y), PERSON_PX * (2.1 if t.type == "mascot" else 1.0))
		node.set_meta("base", {"flyer": Color.WHITE.lerp(col, 0.45), "mascot": Color.WHITE.lerp(col, 0.6), "shoplifter": Color(0.32, 0.32, 0.4), "suit": Color(0.5, 0.5, 0.56)}[t.type])
		node.add_child(shadow())
		e = {"node": node, "a": row[t.type], "step": 0.0, "scale": 2.1 if t.type == "mascot" else 1.0}
	else:
		var mi := MeshInstance3D.new()
		match t.type:
			"trash":
				var m := SphereMesh.new()
				m.radius = 0.32
				m.height = 0.5
				mi.mesh = m
				mi.material_override = mat(Color("8597ad"))
				mi.position.y = 0.25
				# a lit bulge on the sun side and the tied knot, so the bag reads round
				for part in [[0.22, Vector3(-0.06, 0.06, 0.12), Color("b3c3d6")], [0.1, Vector3(0, 0.27, 0), Color("8597ad")]]:
					var bit := MeshInstance3D.new()
					var bm := SphereMesh.new()
					bm.radius = part[0]
					bm.height = part[0] * 2.0
					bit.mesh = bm
					bit.material_override = mat(part[2])
					bit.position = part[1]
					mi.add_child(bit)
			"spill":
				var m := CylinderMesh.new()
				m.top_radius = 0.45
				m.bottom_radius = 0.45
				m.height = 0.01
				mi.mesh = m
				mi.material_override = mat(Color(0.53, 0.78, 0.94, 0.8))
				mi.position.y = 0.02
			"breaker":
				var m := BoxMesh.new()
				m.size = Vector3(0.55, 0.7, 0.2)
				mi.mesh = m
				mi.material_override = mat(Color("f2c230"))
				mi.position.y = 1.7
			_:
				var m := BoxMesh.new()
				m.size = Vector3(0.3, 0.5, 0.06)
				mi.mesh = m
				mi.material_override = mat(Color("2b2d42"))
				mi.position.y = 1.3
		e = {"node": mi}
	actors.add_child(e.node)
	e.node.position = Vector3(t.x, e.node.position.y, t.z)
	return e


## Floaters for what just happened on this street.
func add_events(evs: Array) -> void:
	if branch.is_empty():
		return
	for ev in evs:
		if ev.get("branch", -1) != branch.id or not ev.has("x"):
			continue
		var msg := ""
		var c := Color("2f9e5b")
		match ev.type:
			"sale":
				msg = ("LUCKY ¥" if ev.lucky else "+¥") + Sim.money(ev.amount)
				c = Color("d99a0b") if ev.lucky else (Color("4a9e7a") if ev.passive else c)
			"rivalHit":
				msg = "-%d" % roundi(ev.damage)
				c = Color("d64545")
			"combo":
				if ev.count >= 2:
					msg = "COMBO x%d" % ev.count
					c = Color("e07b1a")
			"poached":
				msg = "POACHED"
				c = Color("d64545")
			"stolen":
				msg = "-%d STOLEN" % ev.units
				c = Color("d64545")
			"takeoverHit":
				msg = "-¥" + Sim.money(ev.amount)
				c = Color("d64545")
			"reviewPosted":
				msg = "1★ REVIEW"
				c = Color("d64545")
			"caught":
				msg = "CAUGHT +¥200"
			"repelled":
				msg = "+6 XP"
				c = Color("2f6fd6")
			"cleaned":
				msg = "+2 XP"
				c = Color("2f6fd6")
			"recruit":
				msg = "!"
				c = Color("2f6fd6")
			"angry":
				if ev.reason != "stock":
					msg = "TOO SLOW" if ev.reason == "wait" else "QUEUE FULL"
					c = Color("d64545")
		if msg != "":
			floaters.append({"text": msg, "at": Vector3(ev.x, 5.6 if ev.type == "rivalHit" else 2.0, ev.z), "life": 1.2, "color": c})
	if floaters.size() > 40:
		floaters = floaters.slice(floaters.size() - 40)


# ---------- input ----------

## Sizes the 3D render to the real pixels this view covers. The UI is laid out at 960x540 or more: the window
## stretches it by min(width / 960, height / 540) and shows the extra width or height as more of the scene.
func fit_viewport() -> void:
	var win := Vector2(get_window().size)
	vp_scale = clampf(minf(win.x / 960.0, win.y / 540.0), 1.0, 3.0)
	vp.size = Vector2i((size * vp_scale).round())
	overlay.queue_redraw()


## A point in the street frame to this control's coordinates.
func screen(p: Vector3) -> Vector2:
	return cam.unproject_position(p + site.position) / vp_scale


func screen_room(p: Vector3) -> Vector2:
	return screen(p + Vector3(Sim.ORIGIN.x, 0, Sim.ORIGIN.y))


func screen_world(p: Vector3) -> Vector2:
	return cam.unproject_position(p) / vp_scale


## Where the click ray meets the ground, in world coordinates.
func ground_at(pos: Vector2) -> Vector3:
	var o := cam.project_ray_origin(pos * vp_scale)
	var d := cam.project_ray_normal(pos * vp_scale)
	if d.y > -0.001:
		return Vector3(INF, 0, INF)
	return o + d * (-o.y / d.y)


## Lot under the pointer, its sidewalk included.
func lot_at(pos: Vector2) -> int:
	var p := ground_at(pos)
	for li in sim.lots.size():
		var L: Dictionary = sim.lots[li]
		if Rect2(L.x0, L.front - Sim.City.LOT_D, Sim.City.LOT_W, Sim.City.LOT_D + 2.2).has_point(Vector2(p.x, p.z)):
			return li
	return -1


func threat_point(t: Dictionary) -> Vector3:
	var y: float = {"trash": 0.3, "spill": 0.05, "breaker": 1.7, "review": 1.4, "mascot": 1.8}.get(t.type, 1.0)
	return Vector3(t.x, y, t.z)


## What a click at pos would act on: a threat, else a register with a customer waiting, else a shelf.
func target_at(pos: Vector2) -> Dictionary:
	if branch.is_empty() or mode != "store":
		return {}
	var best := {}
	var best_d := 28.0
	for t in branch.threats:
		if t.fleeing:
			continue
		var d := screen(threat_point(t)).distance_to(pos)
		if d < best_d:
			best_d = d
			best = {"type": "clickThreat", "id": t.id}
	if not best.is_empty():
		return best
	best_d = 26.0
	for reg in branch.store.registers:
		if reg.active:
			var p: Vector2 = Sim.REGISTERS[reg.id].pos
			var d := screen_room(Vector3(p.x, 1.2, p.y)).distance_to(pos)
			if d < best_d:
				best_d = d
				best = {"type": "ringUp", "register": reg.id}
	if not best.is_empty():
		return best
	best_d = 30.0
	for pid in branch.store.products:
		var p: Vector2 = Sim.SLOTS[Sim.PRODUCTS[pid].slot].pos
		var d := screen_room(Vector3(p.x, 1.0, p.y)).distance_to(pos)
		if d < best_d:
			best_d = d
			best = {"type": "restock", "product": pid}
	return best


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom = clampf(zoom * (0.9 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), 0.04 if mode == "city" else 0.4, 1.4 if mode == "city" else 2.5)
		update_camera()
		accept_event()
		return
	if mode == "city" and e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		yaw -= e.relative.x * 0.006
		update_camera()
		accept_event()
		return
	if e is InputEventMouseMotion and e.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_LEFT):
		drag += e.relative.length()
		if drag > 6.0:
			var b := cam.global_transform.basis
			cam_offset += (-b.x * e.relative.x + b.y * e.relative.y) * cam.size / size.y
			cam_offset = cam_offset.limit_length(420.0 if mode == "city" else 40.0)
			update_camera()
		accept_event()
		return
	if e is InputEventMouseMotion:
		if mode == "city":
			var li := lot_at(e.position)
			if li != hover_lot:
				hover_lot = li
				overlay.queue_redraw()
		else:
			hover = target_at(e.position)
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			drag = 0.0
			return
		if drag > 6.0:
			return
		if mode == "city":
			var li := lot_at(e.position)
			if li >= 0:
				lot_clicked.emit(li)
		else:
			var a := target_at(e.position)
			if not a.is_empty():
				act_requested.emit(a)
		accept_event()


func _process(delta: float) -> void:
	if city_sig != "":
		update_light()
	if paused or city_sig == "":
		return
	street_life(delta)
	if mode == "store" and not branch.is_empty():
		if scene_signature() != set_sig:
			build_set()
		refresh_stock()
		sync_actors(delta)
		for f in floaters:
			f.at.y += 0.6 * delta
			f.life -= delta
		floaters = floaters.filter(func(f): return f.life > 0.0)
	overlay.queue_redraw()


# ---------- 2D overlay ----------

## The street event's weather over the view: heatwave haze, cold-snap snow that stays out of the shop.
func draw_weather() -> void:
	if branch.is_empty() or branch.event == null:
		return
	var look: Array = WEATHER_LOOK.get({"heatwave": "hot", "coldSnap": "cold"}.get(branch.event.id, ""), [])
	if look.is_empty() or mode != "store":
		return
	overlay.draw_rect(Rect2(Vector2.ZERO, size), look[0])
	if look.size() == 1:
		return
	var inside := PackedVector2Array()
	var zl: float = Sim.ZONE_LEFT[branch.store.size]
	for y in [0.0, 3.0]:
		for c in [Vector2(zl - 0.3, -4.8), Vector2(6.8, -4.8), Vector2(6.8, 4.8), Vector2(zl - 0.3, 4.8)]:
			inside.append(screen_room(Vector3(c.x, y, c.y)))
	inside = Geometry2D.convex_hull(inside)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var now := Time.get_ticks_msec() / 1000.0
	var span := size.y + 40.0
	var lines := PackedVector2Array()
	for i in look[1]:
		var y := fposmod(r.randf() * span + now * look[3] * r.randf_range(0.8, 1.2), span) - 20.0
		var x := fposmod(r.randf() * size.x + y * look[2], size.x)
		var p := Vector2(x + (sin(now * 1.4 + i) * 6.0 if look[4] == 0.0 else 0.0), y)
		if inside.size() > 2 and Geometry2D.is_point_in_polygon(p, inside):
			continue
		if look[4] == 0.0:
			overlay.draw_rect(Rect2(p, Vector2(3, 3)), Color(1, 1, 1, 0.9))
		else:
			lines.append_array([p, p + Vector2(look[2], 1.0).normalized() * look[4]])
	if not lines.is_empty():
		overlay.draw_multiline(lines, Color(0.86, 0.9, 1.0, 0.5))


func text(at: Vector2, s: String, px: int, c: Color, w := 0.0, outline := Color(1, 1, 1, 0.9)) -> void:
	var font := get_theme_default_font()
	var width := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var p := at - Vector2(width / 2 if w == 0.0 else 0.0, 0)
	overlay.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 4, outline)
	overlay.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, c)


func round_box(c: Color, r: float) -> StyleBoxFlat:
	var k := "%s/%d" % [c.to_html(), roundi(r)]
	if not styles.has(k):
		var s := StyleBoxFlat.new()
		s.bg_color = c
		s.set_corner_radius_all(roundi(r))
		styles[k] = s
	return styles[k]


## A rounded tag centred on `at` (its text's baseline), like the name bubbles over things on the island.
func pill(at: Vector2, s: String, px: int, bg: Color, fg := Color.WHITE) -> void:
	var font: Font = bold if bold else get_theme_default_font()
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var asc := font.get_ascent(px)
	var r := Rect2(at.x - w / 2 - 7, at.y - asc - 2, w + 14, asc + font.get_descent(px) + 4)
	overlay.draw_style_box(round_box(Color(0.42, 0.3, 0.15, 0.25), r.size.y / 2), Rect2(r.position + Vector2(0, 2), r.size))
	overlay.draw_style_box(round_box(bg, r.size.y / 2), r)
	overlay.draw_string(font, Vector2(at.x - w / 2, at.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, fg)


## A rounded meter in a cream rim.
func bar(r: Rect2, frac: float, c: Color, bg := Color("dccca4")) -> void:
	overlay.draw_style_box(round_box(Color(1.0, 0.98, 0.92, 0.95), r.size.y / 2 + 2), r.grow(2))
	overlay.draw_style_box(round_box(bg, r.size.y / 2), r)
	var f := clampf(frac, 0.0, 1.0)
	if f > 0.0:
		overlay.draw_style_box(round_box(c, r.size.y / 2), Rect2(r.position, Vector2(maxf(r.size.y, r.size.x * f), r.size.y)))


## The clock as the island shows it: big white time, a rule, the day in a white pill and the hour's name.
func draw_clock() -> void:
	var font: Font = bold if bold else get_theme_default_font()
	var h: float = sim.hour()
	var hh := int(h) % 24
	var t := "%d:%02d" % [12 if hh % 12 == 0 else hh % 12, int(fmod(h, 1.0) * 60.0)]
	var shade := Color(0.33, 0.23, 0.1, 0.55)
	var big := 34
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	for part in [[Vector2(16, 46), t, big], [Vector2(22 + w, 46), "AM" if hh < 12 else "PM", 16]]:
		overlay.draw_string_outline(font, part[0] + Vector2(1, 2), part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, part[2], 4, shade)
		overlay.draw_string(font, part[0], part[1], HORIZONTAL_ALIGNMENT_LEFT, -1, part[2], Color.WHITE)
	overlay.draw_style_box(round_box(shade, 2), Rect2(16, 55, 176, 3))
	overlay.draw_style_box(round_box(Color.WHITE, 2), Rect2(16, 53, 176, 3))
	var day := "Day %d" % sim.day
	var dw := font.get_string_size(day, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	pill(Vector2(16 + 7 + dw / 2, 78), day, 13, Color.WHITE, Color("6b5236"))
	var band := Sim.band(h)
	var at := Vector2(16 + dw + 22, 78)
	overlay.draw_string_outline(font, at + Vector2(1, 2), band.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, shade)
	overlay.draw_string(font, at, band.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("ffe27c") if band.rush else Color.WHITE)


func draw_overlay() -> void:
	if not sim:
		return
	# a soft vignette round the street
	overlay.draw_texture_rect(vignette, Rect2(-80, -60, size.x + 160, size.y + 120), false, Color(1, 1, 1, 0.22 + 0.12 * night))
	draw_weather()
	if not sim.lots.is_empty():
		draw_city_marks(get_theme_default_font())
	if mode == "store" and not branch.is_empty():
		draw_street()
	if not sim.branches.is_empty():
		draw_clock()


## Everything you read and click on the street: the rival's sign and health, shelves, registers, threats, moods.
func draw_street() -> void:
	var b := branch
	var st: Dictionary = b.store
	var rv: Dictionary = b.rival
	var def: Dictionary = Sim.RIVALS[rv.id]
	var span := rival_span(rv)
	var sign_at := screen(Vector3((span.x + span.y) / 2, 4.6, -7.2))
	pill(sign_at, def.name + ("  (closed)" if rv.defeated else ""), 13, Color("a99f8c") if rv.defeated else Color(def.color).darkened(0.1))
	if not rv.defeated:
		bar(Rect2(sign_at + Vector2(-50, 9), Vector2(100, 8)), rv.hp / rv.max_hp, Color(def.color))
		if rv.price_war > 0.0:
			pill(sign_at + Vector2(0, 36), "Price war %ds" % ceili(rv.price_war), 12, Color("e05a4e"))
		elif rv.telegraph != "":
			var blink := floori(Time.get_ticks_msec() / 250.0) % 2 == 0
			pill(sign_at + Vector2(0, 36), "! %s in %ds" % [Sim.ATTACKS[rv.telegraph].name, ceili(maxf(0.0, rv.attack_timer))], 12, Color("e05a4e") if blink else Color("b8372d"))
	# shelves: stock bars, red when low
	for pid in st.products:
		var p: Dictionary = st.products[pid]
		var sp: Vector2 = Sim.SLOTS[Sim.PRODUCTS[pid].slot].pos
		var at := screen_room(Vector3(sp.x, 0.05, sp.y + 0.5))
		var frac: float = float(p.stock) / p.capacity
		bar(Rect2(at + Vector2(-16, 2), Vector2(32, 5)), frac, Color("e05a4e") if frac < Sim.LOW_STOCK else Color("4fc4ab"))
		if p.stock == 0:
			pill(at + Vector2(0, 22), "Empty", 11, Color("e05a4e"))
	# registers: who's at the till, how far the checkout is; a waiting customer with no cashier needs you
	for reg in st.registers:
		if not reg.active:
			continue
		var rp: Vector2 = Sim.REGISTERS[reg.id].pos
		var at := screen_room(Vector3(rp.x, 1.6, rp.y))
		if not reg.queue.is_empty():
			var head = sim.agent_by_id(b, reg.queue[0])
			if head != null and head.at_head:
				var staffed: bool = sim.cashier_of(b, reg.id) != null
				bar(Rect2(at + Vector2(-18, -14), Vector2(36, 5)), reg.progress, Color("3a9bd9"))
				if not staffed or floori(Time.get_ticks_msec() / 400.0) % 2 == 0:
					pill(at + Vector2(0, -24), "Ring up!", 11, Color("e98a1d") if staffed else Color("e05a4e"))
			text(at + Vector2(0, 14), "%d" % reg.queue.size(), 11, Color("6b5236"))
	# threats: name and clicks left
	for t in b.threats:
		var at := screen(threat_point(t))
		if t.fleeing:
			continue
		var label: String = {"flyer": "Flyers", "mascot": "Mascot", "trash": "Trash", "review": "1★ review", "shoplifter": "Thief!", "breaker": "Breaker", "suit": "Suit", "spill": "Spill"}[t.type]
		var top := at + Vector2(0, -26 if t.type in ["flyer", "shoplifter", "suit"] else (-44 if t.type == "mascot" else -12))
		pill(top, label, 11, Color("e05a4e") if t.type != "spill" else Color("3a9bd9"))
		if t.max_clicks > 1:
			for k in t.max_clicks:
				var dot := top + Vector2((k - (t.max_clicks - 1) / 2.0) * 9, 9)
				overlay.draw_circle(dot, 4.0, Color(1.0, 0.98, 0.92))
				overlay.draw_circle(dot, 2.8, Color("e05a4e") if k < t.clicks else Color("dccca4"))
		if t.type == "review":
			bar(Rect2(top + Vector2(-16, 7), Vector2(32, 4)), t.ttl / (7.0 + 3.0 * sim.mods().thick_skin), Color("e05a4e"))
		if t.type == "breaker":
			overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.12, 0.15))
	# pedestrians: angry ones and what they carry
	for a in b.agents:
		if a.state == "inRival":
			continue
		var head := screen(Vector3(a.x, 1.75, a.z))
		if a.mood == "angry":
			overlay.draw_circle(head + Vector2(0, -6), 8.0, Color("d64545"))
			text(head + Vector2(0, -1), "!", 13, Color.WHITE, 0.0, Color("d64545"))
		elif a.mood == "happy":
			overlay.draw_circle(head + Vector2(0, -6), 6.0, Color("2f9e5b"))
		if a.bag != "":
			var hand := screen(Vector3(a.x, 0.7, a.z))
			overlay.draw_rect(Rect2(hand + Vector2(4, -4), Vector2(6, 7)), Color("f08a24") if a.bag == "player" else Color(Sim.RIVALS[b.rival.id].color))
		if a.state == "browse" and a.want != null:
			var ic: Array = Sim.PRODUCTS[a.want].icon
			var cell: int = {"products": ITEM, "perks": 80, "decor": DECOR}[ic[0]]
			overlay.draw_style_box(round_box(Color(1.0, 0.98, 0.92), 9), Rect2(head + Vector2(-13, -31), Vector2(26, 26)))
			overlay.draw_texture_rect_region(tex[ic[0]], Rect2(head + Vector2(-11, -29), Vector2(22, 22)), Rect2(ic[1] * cell, 0, cell, cell))
	for s in b.staff:
		if s.break_t > 0.0:
			pill(screen(Vector3(s.x, 1.9, s.z)), "Break", 10, Color(1.0, 0.98, 0.92), Color("a08c69"))
	# the crossing lights
	var lt: Array = sim.lights()
	for pole in [Vector3(Sim.CROSS_X - 1.8, 2.5, -4.0), Vector3(Sim.CROSS_X + 1.8, 2.5, 4.0)]:
		var at := screen(pole)
		overlay.draw_circle(at, 4.0, Color("35d06a") if lt[0] and (not lt[1] or floori(Time.get_ticks_msec() / 250.0) % 2 == 0) else Color("e04a3a"))
	if not hover.is_empty():
		var at := Vector2.ZERO
		match hover.type:
			"clickThreat":
				var t = sim.threat_by_id(b, hover.id)
				if t != null:
					at = screen(threat_point(t))
			"ringUp":
				var p: Vector2 = Sim.REGISTERS[hover.register].pos
				at = screen_room(Vector3(p.x, 1.2, p.y))
			"restock":
				if st.products.has(hover.product):
					var p: Vector2 = Sim.SLOTS[Sim.PRODUCTS[hover.product].slot].pos
					at = screen_room(Vector3(p.x, 1.0, p.y))
					var pr: Dictionary = st.products[hover.product]
					var each: float = Sim.PRODUCTS[hover.product].cost * sim.mods().restock
					var n: int = pr.capacity - pr.stock
					pill(at + Vector2(0, -30), "Restock %d  ¥%s" % [n, Sim.money(Sim.rnd(n * each))] if n > 0 else "Full", 11, Color(1.0, 0.98, 0.92), Color("6b5236"))
		if at != Vector2.ZERO:
			overlay.draw_arc(at, 16.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)
	for f in floaters:
		text(screen(f.at), f.text, 15, f.color)


func lot_poly(li: int) -> PackedVector2Array:
	var L: Dictionary = sim.lots[li]
	var out := PackedVector2Array()
	for k in [Vector2(0, -Sim.City.LOT_D), Vector2(Sim.City.LOT_W, -Sim.City.LOT_D), Vector2(Sim.City.LOT_W, 0), Vector2(0, 0)]:
		out.append(screen_world(Vector3(L.x0 + k.x, 0, L.front + k.y)))
	out.append(out[0])
	return out


## City mode: district names (stations first, overlapping ones left out), street names and route shields up close,
## the lots on offer, and a pin over each of your branches and its rival.
func draw_city_marks(font: Font) -> void:
	if mode != "city":
		return
	var taken: Array = []  # rects of labels already placed: one that would overlap them is left out
	var room_for := func(r: Rect2) -> bool:
		if taken.any(func(q): return q.intersects(r)):
			return false
		taken.append(r)
		return true
	var pins := []
	for b in sim.branches:
		var p2: Vector2 = Sim.lot_pos(sim.lots[b.lot])
		var at := screen_world(Vector3(p2.x + 2.0, 4.0, p2.y + 3.0))
		pins.append([at, b])
		taken.append(Rect2(at + Vector2(-40, -10), Vector2(80, 18)))
	var order := []
	for rank in 3:
		order += sim.districts.filter(func(d): return (0 if d.type == "hub" else (1 if d.lm[1] >= 0 else 2)) == rank)
	for d in order:
		var at := screen_world(Vector3(d.center.x, 0, d.center.y - 4.0))
		var nm: String = d.name.to_upper()
		var w := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		if not room_for.call(Rect2(at + Vector2(-w / 2 - 3, -12), Vector2(w + 6, 16))):
			continue
		overlay.draw_string_outline(font, at + Vector2(-60, 0), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, 4, Color(0.33, 0.23, 0.1, 0.75))
		overlay.draw_string(font, at + Vector2(-60, 0), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color("f7f3e8"))
	if zoom < 0.45:
		for av in C.avenues:
			var pts: PackedVector2Array = av.pts
			var third: Vector2 = pts[int(pts.size() / 3.0)]
			var at := screen_world(Vector3(third.x, 0, third.y))
			var w := font.get_string_size(av.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			if room_for.call(Rect2(at + Vector2(-w / 2 - 2, -10), Vector2(w + 4, 13))):
				overlay.draw_string_outline(font, at + Vector2(-50, 0), av.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 10, 3, Color(1, 1, 1, 0.7))
				overlay.draw_string(font, at + Vector2(-50, 0), av.name, HORIZONTAL_ALIGNMENT_CENTER, 100, 10, Color("5d5f66"))
		for sh in C.shuto:
			var pts: PackedVector3Array = sh.pts
			var at := screen_world(pts[int(pts.size() / 2.0)] + Vector3(0, 1.5, 0))
			if room_for.call(Rect2(at + Vector2(-13, -9), Vector2(26, 16))):
				overlay.draw_rect(Rect2(at + Vector2(-13, -9), Vector2(26, 16)), Color("1f6f43"))
				overlay.draw_rect(Rect2(at + Vector2(-13, -9), Vector2(26, 16)), Color.WHITE, false, 1.5)
				overlay.draw_string(font, at + Vector2(-13, 4), sh.name, HORIZONTAL_ALIGNMENT_CENTER, 26, 11, Color.WHITE)
	var offered := {}
	if pick == "listing" and sim.choice != null and sim.choice.source == "listing":
		for k in sim.choice.options.size():
			offered[sim.choice.options[k].lot] = k
	for li in sim.lots.size():
		var mark := Color(0, 0, 0, 0)
		if offered.has(li):
			mark = Color("3fae49")
		elif sim.lots[li].use == "free" and pick == "":
			mark = Color(1, 1, 1, 0.35)
		if li == hover_lot and (offered.has(li) or sim.branch_on(li) != null):
			mark = Color.WHITE
		if mark.a > 0.0:
			overlay.draw_polyline(lot_poly(li), mark, 2.0)
		if offered.has(li):
			var p2: Vector2 = Sim.lot_pos(sim.lots[li])
			var at := screen_world(Vector3(p2.x, 3.0, p2.y))
			overlay.draw_circle(at, 10.0, Color("3fae49"))
			overlay.draw_string(font, at + Vector2(-10, 5), str(offered[li] + 1), HORIZONTAL_ALIGNMENT_CENTER, 20, 13, Color.WHITE)
	for e in pins:
		var at: Vector2 = e[0]
		var b: Dictionary = e[1]
		if not Rect2(Vector2.ZERO, size).grow(20).has_point(at):
			continue
		pill(at + Vector2(0, 4), b.name, 11, Color("e98a1d") if is_same(b, branch) else Color("c46a14"))
		if not b.rival.defeated:
			var o := frame_origin(b.lot)
			var rat := screen_world(o + Vector3(rival_span(b.rival).x + 4.0, 4.0, -7.2))
			overlay.draw_circle(rat, 5.0, Color.WHITE)
			overlay.draw_circle(rat, 3.8, Color(Sim.RIVALS[b.rival.id].color))
