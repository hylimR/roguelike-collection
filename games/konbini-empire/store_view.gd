extends Control
## The city stage: Tokyo (city.gd) as a city builder sees it, through an orthographic isometric camera. Streets,
## avenues, the elevated expressway and the Yamanote are generated meshes; buildings are boxes in one MultiMesh
## with a pixel facade shader, as are most landmarks (traced from their drawings); each branch's shop and its rival
## are boxes too; trees, the other landmarks, cars and people are Codex sprites. In store mode the focused branch's
## street set is carved into the city on its lot: your shop as a cutaway, the rival next door, the street with its
## crossing, and the sim's pedestrians, threats and staff live. Clicks on threats, tills and
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
const OUTDOOR_SCALE := [1.0, 1.0, 0.95, 1.05, 0.45, 0.45, 0.6, 0.84, 0.66, 0.38, 0.5, 1.23]
const PROP_BLOB := {7: 0.35, 8: 0.5, 10: 0.6, 11: 0.25}  # street props whose shadow is narrower than their art
const VEHICLE_CELL := Vector2i(128, 96)
const VEHICLE_PX := 0.025
# atlas cells (art is cut at 2x its own pixel grid)
const ITEM := 64
const PERSON := Vector2i(72, 96)
const DECOR := 96
const OUTDOOR := 128
# art/props.png: fittings drawn in the store camera's own 2:1 view, each cell's footprint centre at (64, 150).
# name: [cell, metres per texel, footprint along x and z]
const PROP := Vector2i(128, 176)
const PROPS := {"till": [0, 0.0075, Vector2(0.34, 0.44)], "coffee": [1, 0.0075, Vector2(0.42, 0.45)], "atm": [2, 0.014, Vector2(0.7, 0.8)],
	"vending": [3, 0.014, Vector2(1.0, 0.75)], "gacha": [4, 0.014, Vector2(1.5, 0.5)], "bench": [5, 0.014, Vector2(1.5, 0.4)],
	"cat": [6, 0.009, Vector2.ZERO], "karaage": [7, 0.0075, Vector2(0.47, 0.52)], "oden": [8, 0.0075, Vector2(0.4, 0.55)]}
const COUNTER_H := 0.75  # the counter top, at the staff's elbows
const LANDMARK := 256
const Models := preload("res://landmark_models.gd")  # landmarks traced from their drawings into boxes
const LANDMARK_H := {"landmarks": 256, "tokyo": 384}  # the Tokyo sheet has tall cells for the towers
const LANDMARK_SPAN := 29.5  # screen width of a landmark: most of the 22 m square the city reserves for it
const WALK_NEAR := 1.2  # customers' sidewalk line in front of the shop
const MAX_WALKERS := 70
const MAX_CARS := 70
const SET := Rect2(-52, -32, 104, 52)  # the street set round your shop, in the street frame
# art/walk.png rows past the seven customers: staff and threats, then a flyer girl and a mascot per rival chain in
# Sim.RIVALS order
const WALK_ROW := {"cashier": 7, "guard": 8, "cleaner": 9, "promoter": 10, "stocker": 11, "shoplifter": 12, "suit": 13, "review": 14, "flyer": 15, "mascot": 21}
const MASCOT_SCALE := 1.35  # a 2 m costume over the 1.5 m adults
const FIXTURE_W := 2.3  # every fixture's face; each is 0.8 deep, open to +z, the aisle its shoppers stand in
# Where each kind of fixture holds its stock, in its slot's frame: rows of [the board's top, the most a pack may reach
# above it, how far toward the aisle the front packs stand], the lines of packs on each board (how far behind the front,
# each one behind staggered half a pack), the spans across the face they fill (one per fridge door), the room inside
# its shell, the biggest a pack is drawn, and how far packs lean back (a chest freezer's lie in its well).
const FIXTURES := {
	"shelf": {"h": 1.4, "rows": [[0.1, 0.49, 0.27], [0.52, 0.91, 0.27], [0.94, 1.4, 0.27]], "lines": [0.0, -0.14], "bays": [[-1.08, 1.08]],
		"inner": Rect2(-1.11, 0.02, 2.22, 0.4), "pack": Vector2(0.3, 0.34), "lean": 0.0},
	"low": {"h": 0.9, "rows": [[0.1, 0.47, 0.27], [0.5, 0.9, 0.27]], "lines": [0.0, -0.14], "bays": [[-1.08, 1.08]],
		"inner": Rect2(-1.11, 0.02, 2.22, 0.4), "pack": Vector2(0.3, 0.33), "lean": 0.0},
	"fridge": {"h": 2.0, "rows": [[0.12, 0.52, 0.14], [0.54, 0.94, 0.14], [0.96, 1.36, 0.14], [1.38, 1.75, 0.14]], "lines": [0.0, -0.18],
		"bays": [[-1.06, -0.42], [-0.31, 0.31], [0.42, 1.06]], "inner": Rect2(-1.09, -0.34, 2.18, 0.72), "pack": Vector2(0.24, 0.34), "lean": 0.0},
	"freezer": {"h": 0.9, "rows": [[0.62, 0.88, 0.2], [0.62, 0.88, 0.03], [0.62, 0.88, -0.13]], "lines": [0.0], "bays": [[-1.06, 1.06]],
		"inner": Rect2(-1.09, -0.34, 2.18, 0.68), "pack": Vector2(0.26, 0.26), "lean": 60.0},
}
const PACK_STEP := 1.05  # a row's packs stand shoulder to shoulder, this many drawn widths apart
const RACK_H := 1.05  # the magazine racks' drawn height, stood on the floor
const FIELDS := ["8cc458", "a8cc66", "d0c468", "c8b064", "a88e66", "70aa50", "98c488"]  # paddies, young rice, rapeseed, wheat, soil, greens, cabbages
# the day's weather over the view: [tint, then for falling rain or snow: drops, slant, speed px/s, streak length]
const WEATHER_LOOK := {
	"hot": [Color(1.0, 0.7, 0.3, 0.12)],
	"rain": [Color(0.2, 0.25, 0.38, 0.24), 170, -0.18, 950.0, 15.0],
	"cold": [Color(0.8, 0.88, 1.0, 0.2), 240, 0.15, 50.0, 0.0],
	"typhoon": [Color(0.1, 0.14, 0.24, 0.36), 360, -0.6, 1500.0, 24.0],
}
# the hour's light on everything outdoors, [hour, tint]: a pink dawn, plain day, golden hour, dusk, night; lit windows,
# your shop's interior and the street lamps' pools stay bright
const DAYLIGHT := [[6.0, Color(0.62, 0.58, 0.8)], [6.6, Color(1.0, 0.8, 0.8)], [7.3, Color(1.0, 0.9, 0.84)], [8.0, Color.WHITE], [15.5, Color.WHITE], [16.8, Color(1.0, 0.92, 0.77)],
	[17.8, Color(1.0, 0.84, 0.62)], [18.5, Color(0.97, 0.75, 0.62)], [19.1, Color(0.8, 0.62, 0.7)], [19.8, Color(0.5, 0.5, 0.72)], [21.0, Color(0.36, 0.4, 0.62)],
	[24.0, Color(0.32, 0.36, 0.58)]]
const GOLDEN := [16.0, 17.8, 19.2]  # golden hour's rise, peak and end: walls facing the low sun glow, the rest go cool
const DAWN := [6.0, 6.5, 7.8]  # the same for sunrise, from the other side and rosier
const LAMP := Color(1.0, 0.85, 0.58)
const SHOP_LIGHT := Color(0.86, 0.95, 1.0)  # a konbini's cool white strip lights
const SEA := Color("3a8cc8")
const ROOF_TINT := 0.3  # how much of its walls' tint a flat roof takes over its membrane
const ASPHALT := Color("576074")  # a cool slate rather than flat grey
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
	vec2 uv = vec2(c.x, -c.y) * 0.5 + 0.5;
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));  // past the sun's view there is nothing to cast
	ALPHA = texture(mask, uv).a * strength * inside.x * inside.y;
}
"""
# Buildings: boxes in a MultiMesh. Custom data = size and facade style (-1: plain shaded colour, for roofs); colour =
# wall tint, alpha = accent index / 8. A landmark's curved faces (no size) use alpha below 1 for floodlighting. Walls pick a 3-unit bay and floor tile from the facade atlas.
const BUILDING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D facades : filter_nearest_mipmap;
uniform sampler2D accents : filter_nearest_mipmap;
uniform float styles = 10.0;
uniform float night = 0.0;
uniform vec3 light = vec3(1.0);
uniform float golden = 0.0;
uniform float dawn = 0.0;
varying vec3 lpos;
varying vec3 lnrm;
varying vec4 info;
varying vec4 tint;
varying vec2 sunl;
const vec3 ACCENT[8] = vec3[8](vec3(0.89, 0.25, 0.22), vec3(0.96, 0.56, 0.16), vec3(0.98, 0.82, 0.25), vec3(0.24, 0.68, 0.36), vec3(0.22, 0.5, 0.86), vec3(0.6, 0.34, 0.8), vec3(0.95, 0.45, 0.65), vec3(0.2, 0.72, 0.74));
const vec3 FLOOR[4] = vec3[4](vec3(0.6, 0.46, 0.33), vec3(0.68, 0.64, 0.42), vec3(0.52, 0.52, 0.5), vec3(0.68, 0.66, 0.61));  // boards, tatami, concrete, tile
const vec3 ROOF[8] = vec3[8](FLAT_ROOFS);  // Sim.City.FLAT_ROOFS

void vertex() {
	info = INSTANCE_CUSTOM;
	tint = COLOR;
	lnrm = NORMAL;
	lpos = (VERTEX + 0.5) * INSTANCE_CUSTOM.xyz;
	sunl = vec2(dot(normalize(MODEL_MATRIX[0].xz), vec2(-0.35, 0.6)), dot(normalize(MODEL_MATRIX[2].xz), vec2(-0.35, 0.6)));
}

// a light whose own threshold (0-1) the falling dark has passed: full on (a little dimmer until full night), not faded in
float switched(float at, float dark) {
	return smoothstep(0.08 + 0.6 * at, 0.12 + 0.6 * at, dark) * mix(0.8, 1.0, dark);
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// the house's three tones, shared with shaded_box: roofs full, walls turned to the sun 0.9, walls away 0.75 (the
	// drawn art's shaded wall is 0.83 of its lit one); a gable's slope away from the sun 0.85
	float sun = dot(n.xz, vec2(-0.35, 0.6));
	float shade = n.y > 0.95 ? 1.0 : (n.y > 0.5 ? (sun >= 0.0 ? 1.0 : 0.85) : (sun > 0.0 ? 0.9 : 0.75));
	vec3 col = tint.rgb;
	vec3 glow = vec3(0.0);
	float inside = 0.0;  // a lit shop seen through its window: its own colours under warm light, not dimmed by the dark
	vec3 lit_in = vec3(0.0);
	if (info.w > -0.5) {
		float style = floor(info.w);
		float seed = fract(info.w) * 2.0;
		int pick = int(tint.a * 8.0) % 8;
		if (lnrm.y > 0.5) {
			vec2 e = min(lpos.xz, info.xz - lpos.xz);
			if (info.y < 1.0) {  // cut down in front of the street: the walls' section round a floor plan of rooms
				vec2 bay = info.xz / max(vec2(1.0), floor(info.xz / vec2(3.0, 4.0) + 0.5));
				vec2 rc = lpos.xz / bay;
				vec2 wd = min(fract(rc), 1.0 - fract(rc)) * bay;
				float wall = min(min(e.x, e.y) - 0.3, min(wd.x, wd.y) - 0.06);
				float r = fract(sin(dot(floor(rc) + seed * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
				int k = int(r * 4.0);
				vec2 g = fract(lpos.xz * (k == 0 ? vec2(0.0, 4.0) : (k == 1 ? vec2(1.1, 0.55) : vec2(1.0))));
				float seam = min(k == 0 ? 1.0 : min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y)) < 0.05 ? 0.86 : 1.0;
				vec3 fl = FLOOR[k] * seam * mix(0.72, 1.0, smoothstep(0.0, 0.5, wall));
				col = wall < 0.0 ? tint.rgb * 1.08 : fl;
				glow = wall < 0.0 ? vec3(0.0) : fl * vec3(1.0, 0.86, 0.62) * step(0.5, fract(r * 13.0)) * 0.45 * switched(fract(r * 29.0), night);
			} else {  // a flat roof: coping round a parapet that shades the roof on its sunny sides, membrane in strips, a hatch
				vec2 q = lpos.xz;
				float fine = 1.0 - smoothstep(0.1, 0.3, fwidth(q.x) + fwidth(q.y));
				float u = (info.x >= info.z ? q.y : q.x) / 1.2;
				float lane = fract(sin((floor(u) + seed * 53.0) * 12.9898) * 43758.5453);
				float f = mix(1.0, (0.95 + 0.07 * lane) * (min(fract(u), 1.0 - fract(u)) < 0.035 ? 0.88 : 1.0), fine) * 0.92;
				vec2 into = vec2(sunl.x < 0.0 ? q.x : info.x - q.x, sunl.y > 0.0 ? info.z - q.y : q.y) - 0.3;
				float shadow = max(step(0.0, into.x) * step(into.x, 0.7 * abs(sunl.x)), step(0.0, into.y) * step(into.y, 0.7 * abs(sunl.y)));
				f *= 1.0 - 0.2 * shadow;
				if (min(info.x, info.z) > 3.5) {
					vec2 hc = info.xz * vec2(0.22 + 0.56 * fract(seed * 7.31), 0.25 + 0.5 * fract(seed * 3.17));
					vec2 hd = abs(q - hc);
					vec2 sd = abs(q - hc + sunl * 0.45);
					f = max(hd.x, hd.y) < 0.5 ? (max(hd.x, hd.y) < 0.4 ? 1.12 : 0.8) : (max(sd.x, sd.y) < 0.5 ? f * 0.78 : f);
				}
				col = mix(ROOF[pick], tint.rgb, ROOF_TINT) * (min(e.x, e.y) < 0.3 ? 1.14 : f);
			}
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
			// after dark about half the windows light up, each its own, switching on one by one through dusk (shops and
			// signs first) and off again at first light; every shop lights up and signs keep shining
			vec2 cell = floor(cont) + vec2(lnrm.x * 7.0 + lnrm.z * 3.0, seed * 91.0);
			float r = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
			vec3 lamp = r > 0.85 ? vec3(0.78, 0.86, 1.0) : vec3(1.0, 0.8, 0.48);
			glow = m.g * (1.0 - m.b) * step(0.6, r) * lamp * switched(fract(r * 29.0), night) + m.r * ACCENT[pick] * 0.9 * switched(0.1 * fract(r * 17.0), night);
			inside = m.b * switched(0.3 * fract(r * 29.0), night);
			lit_in = mix(t.rgb * vec3(1.06, 0.96, 0.8), vec3(1.0, 0.9, 0.68), m.g);  // goods and shelves on a warm glow
			if (info.y < 1.0) {  // cut down: the wall's solid section on a dark plinth, not a slice of its windows
				col = tint.rgb * (lpos.y < 0.16 ? 0.62 : (lpos.y > info.y - 0.06 ? 1.08 : 0.96));
				glow = vec3(0.0);
				inside = 0.0;
			}
		}
		col *= mix(0.72, 1.0, clamp(lpos.y / 1.2, 0.0, 1.0));
	} else if (info.x == 0.0 && tint.a < 0.99) {  // a landmark face packed with alpha under 1 is floodlit after dark
		glow = vec3(1.0, 0.62, 0.3) * (1.0 - tint.a) * 2.0 * night;  // a warm floodlight, its strength in the alpha
	}
	float low_sun = max(dot(n, normalize(vec3(-0.5, 0.3, 0.8))), 0.0);
	vec3 grade = mix(vec3(0.8, 0.84, 1.04), vec3(1.2, 1.02, 0.78), low_sun);
	float east = max(dot(n, normalize(vec3(0.8, 0.3, 0.5))), 0.0);
	vec3 rose = mix(vec3(0.84, 0.84, 1.06), vec3(1.2, 0.94, 0.92), east);
	ALBEDO = mix(col * shade * light * mix(vec3(1.0), grade, golden) * mix(vec3(1.0), rose, dawn), lit_in * mix(1.0, shade, 0.5), inside) + glow;
}
"""
# the back wall's art: a crop of the side-view background, tiled along the wall
const LAYOUT := {"bg": "bg_konbini", "wall": Rect2i(208, 44, 316, 201), "floor": [Color("ead9b8"), Color("cbb48e")], "stripe": [Color("f05a28"), Color("1f9d55")]}

var tex := {}
var sheet_imgs := {}  # sheet images read back for their cells' used rects
var sim
var branch: Dictionary = {}  # the focused branch (sim's own dictionary)
var set_sig := ""
var slot_icons := {}  # product -> [Sprite3D]: its stock on the shelf
var slot_goods := {}  # product -> MultiMesh: packs faced up on its fixture, as many showing as are in stock
var agent_nodes := {}  # sim id -> {node, a (walk row), step}
var threat_nodes := {}
var staff_nodes := {}
var floaters: Array = []
var paused := false
var hover := {}  # the action a click would take
var drag := 0.0
var bold: Font  # the HUD's heavy weight, for the clock and street tags
var styles := {}  # rounded boxes for tags and bars, by color and radius
var roof_texs := {}  # the rival's roof, by the width of its shop

var walkers: Array = []
var cars: Array = []
var next_walker := 0.0
var next_car := 0.0
var set_cars: Array = []  # traffic on the set's own street, which city movers keep off
var next_set_car := 0.0
var mode := "store"  # store | city
var city_sig := ""
var lm_ground := {}  # "water" / "grass" -> [material, uv per metre]: the city's ground, for landmarks' own pools and lawns
var lm_sprites: Array = []  # [Sprite3D, half width]: landmarks, cleared when they cover the street
var lot_nodes: Array = []  # [Node3D, footprint centre]: the shops built on other branches' lots, hidden under the set
var lm_trees: Array = []  # [world position, scale, outdoor frame]: trees planted by landmark models
var lot_feet: Array = []  # their world footprints (your shop's and the rival's), where the city gives way
var hover_lot := -1
var pick := ""  # city mode: "" | listing
var site: Node3D
var city: Node3D
var lots_node: Node3D
var C: Dictionary  # the City map
var trains: Array = []  # on the Yamanote: {dir, k, cars: [MeshInstance3D]}
var rail_t := 0.0  # the trains' clock, seconds
var car_glass: StandardMaterial3D  # train windows: dark by day, lit after dark
var paths: Array = []  # every road as a path for movers: {pts, cum, w, kind, closed, box}
var set_feet: Array = []  # world footprints of what the street set builds behind its street, where the city gives way
var elevated: Array = []  # deck pieces (MeshInstance3D), drawn again into the shadow mask
var brecs: Array = []  # per building: {foot, h, box: [instance], roof: instance or -1, hidden}
var box_mm: MultiMesh
var box_base: Array = []
var building_mat: ShaderMaterial
var roof_mm: MultiMesh
var roof_base: Array = []
var pillar_mm: MultiMesh
var tree_mms: Array = []  # [MultiMesh, base transforms, height]
var mask_vp: SubViewport  # the city seen from the sun, for ground shadows
var shadow_mat: ShaderMaterial
var env: Environment
var light := Color.WHITE  # the hour's tint (DAYLIGHT)
var night := 0.0  # 0 by day, 1 from 22:00, fading out at first light: lit windows and lamp pools
var lit_mats: Array = []  # [weakref to an outdoor material, its own colour, how far it lights up after dark (lightboxes)]
var lit_sprites: Array = []  # outdoor sprites that stand still, relit when the light changes
var pools: Array = []  # Vector3(x, z, radius) in the world: lamp light on the street after dark
var pool_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D  # street lamp heads: pale by day, lit after dark
var halo_mat: StandardMaterial3D  # the glow round a lit lamp head
var beam_mat: StandardMaterial3D  # the cone of light falling from a lit lamp head to its pool
var spill_mat: StandardMaterial3D  # shop light falling out of a glass front across the sidewalk
var flood_mat: StandardMaterial3D  # your car park's floodlight on the bays
var sign_glow_mat: StandardMaterial3D  # the glow round your lit pole sign
var fascia_glows: Array = []  # [weakref to the glow round a rival's lit fascia, its chain's colour]
var fascia_glow_tex: ImageTexture
var snow_tex: ImageTexture  # patchy settled snow, tiled 8 m
var snow_cover: MeshInstance3D  # the set's snowy ground, shown on a cold snap
var light_poles: Array = []  # the crossing lights' heads, in the street frame
var shop_area := Rect2()  # your shop's floor in the world: full light inside
var vignette: GradientTexture2D
var box_mesh: ArrayMesh
var sign_tex: ImageTexture
var soft_mat: StandardMaterial3D  # soft contact shadows under people, cars and street things
var ao_mat: StandardMaterial3D  # the dark seam where a building meets the sidewalk
var cam_target := Vector3.ZERO
var cam_offset := Vector3.ZERO
var cam_base := 12.0
var zoom := 1.0
var cam_dist := 400.0
# the bay's open water carried on south past the city's own bay, widening as it goes, so the map never shows its edge
var bay_mouth := PackedVector2Array([Vector2(-380, 999), Vector2(640, 999), Vector2(790, 1300), Vector2(760, 1640), Vector2(1080, 2050), Vector2(1450, 2800), Vector2(-1300, 2800), Vector2(-880, 2120), Vector2(-600, 1720), Vector2(-590, 1380)])
var yaw := PI / 4
var yaw_drag := 0.0  # right-drag turned so far; yaw follows it in quarter turns

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
	halo_mat = pool_mat.duplicate()
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spill_mat = pool_mat.duplicate()
	flood_mat = pool_mat.duplicate()
	sign_glow_mat = halo_mat.duplicate()
	var fall := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var u := x / 63.0
			fall.set_pixel(x, y, Color(1, 1, 1, (exp(-2.2 * y / 31.0) - exp(-2.2)) / (1.0 - exp(-2.2)) * smoothstep(0.0, 0.2, u) * smoothstep(0.0, 0.2, 1.0 - u)))
	spill_mat.albedo_texture = ImageTexture.create_from_image(fall)
	var halo := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 64:
			var d := Vector2(maxf(absf(x - 31.5) - 22.0, 0.0) / 10.0, maxf(absf(y - 7.5) - 2.0, 0.0) / 6.0).length()
			halo.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
	fascia_glow_tex = ImageTexture.create_from_image(halo)
	beam_mat = halo_mat.duplicate()
	beam_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	var cone := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var v := y / 63.0
		var hw := lerpf(0.1, 0.5, v)
		for x in 32:
			var d := absf(x / 31.0 - 0.5)
			cone.set_pixel(x, y, Color(1, 1, 1, smoothstep(hw, hw * 0.4, d) * pow(1.0 - v, 1.1) * smoothstep(0.0, 0.04, v)))
	beam_mat.albedo_texture = ImageTexture.create_from_image(cone)
	snow_tex = snow_patches()
	lamp_mat = StandardMaterial3D.new()
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.vertex_color_use_as_albedo = true
	lamp_mat.vertex_color_is_srgb = true
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
		lit_mats.append([weakref(m), color, 0.0])
	return m


## Marks an outdoor material as a lightbox: after dark it lights up toward its own colour by k instead of dimming.
func light_up(m: StandardMaterial3D, k: float) -> void:
	for i in range(lit_mats.size() - 1, -1, -1):  # just made, so near the end
		if lit_mats[i][0].get_ref() == m:
			lit_mats[i][2] = k
			return


func block(parent: Node3D, size_: Vector3, pos: Vector3, color: Color, indoor := false) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	mi.mesh = shaded_box()
	mi.scale = size_
	var m := mat(color, null, indoor or parent == room)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return m


## A unit cube with each face pre-shaded in the house's three tones (top full, the walls turned to the sun 0.9, the
## walls away 0.75, as BUILDING_SHADER shades), so unshaded boxes still read as solid.
func shaded_box() -> ArrayMesh:
	if box_mesh:
		return box_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in [[Vector3.UP, 1.0], [Vector3.BACK, 0.9], [Vector3.RIGHT, 0.75], [Vector3.LEFT, 0.9], [Vector3.FORWARD, 0.75], [Vector3.DOWN, 0.7]]:
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


## A fitting from art/props.png with its footprint centred on `at`. Its art is drawn in the store camera's own view
## (the till's front to the clerk, the rest to the street), which holds because that camera's yaw is locked.
func prop(parent: Node3D, kind: String, at: Vector3) -> Sprite3D:
	var p: Array = PROPS[kind]
	var s := sprite("props", Rect2(p[0] * PROP.x, 0, PROP.x, PROP.y), p[1])
	s.offset = Vector2(0, 150 - PROP.y / 2.0)
	s.position = at
	if p[2] != Vector2.ZERO:
		s.scale.y = 1.0 / cos(deg_to_rad(PITCH))  # the art already is the tilted view: undo the billboard's foreshortening
		# slid toward the camera along its line of sight (the screen spot stays) till the plane clears the footprint's
		# near corner, so the floor or counter top never cuts off the art's lower edge
		var reach: float = (p[2].x + p[2].y) / (2.0 * sqrt(2.0)) / cos(deg_to_rad(PITCH)) + 0.02
		s.position += Vector3(sin(PI / 4) * cos(deg_to_rad(PITCH)), sin(deg_to_rad(PITCH)), cos(PI / 4) * cos(deg_to_rad(PITCH))) * reach
	if parent:
		parent.add_child(s)
	return s


## A picture on an upright quad facing +z (shop art, the rival's window), mipmapped so it stays clean when small.
func art_panel(parent: Node3D, img: Image, size_: Vector2, pos: Vector3, tint := Color.WHITE, reps := 1.0, lit := true) -> StandardMaterial3D:
	img.generate_mipmaps()
	var m := mat(tint, ImageTexture.create_from_image(img), lit)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.uv1_scale = Vector3(reps, 1, 1)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size_
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return m


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
	var n := maxf(clampf((h - 18.0) / 4.0, 0.0, 1.0), 0.7 * clampf((7.0 - h) / 1.0, 0.0, 1.0))  # lamps still on at first light
	if is_equal_approx(n, night) and Vector3(c.r - light.r, c.g - light.g, c.b - light.b).length() < 0.004:
		return
	light = c
	night = n
	lit_mats = lit_mats.filter(func(e): return e[0].get_ref() != null)
	for e in lit_mats:
		e[0].get_ref().albedo_color = e[1] * light.lerp(Color.WHITE, e[2] * night)
	fascia_glows = fascia_glows.filter(func(e): return e[0].get_ref() != null)
	for e in fascia_glows:
		e[0].get_ref().albedo_color = e[1] * Color(1, 1, 1, 0.85 * night)
	if building_mat:
		building_mat.set_shader_parameter("light", Vector3(light.r, light.g, light.b))
		building_mat.set_shader_parameter("night", night)
		building_mat.set_shader_parameter("golden", golden_at(h))
		building_mat.set_shader_parameter("dawn", dawn_at(h))
	if shadow_mat:
		shadow_mat.set_shader_parameter("strength", 0.42 * (1.0 - night) * (1.0 + 0.3 * golden_at(h)))
	env.background_color = SEA * light
	pool_mat.albedo_color = LAMP * Color(1, 1, 1, 0.75 * night)
	halo_mat.albedo_color = LAMP * Color(1, 1, 1, 0.55 * night)
	beam_mat.albedo_color = LAMP * Color(1, 1, 1, 0.5 * night)
	spill_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.55 * night)
	flood_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.85 * night)
	sign_glow_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.7 * night)
	lamp_mat.albedo_color = (Color("dfe3e2") * light).lerp(Color(1.0, 0.96, 0.82), night)
	if car_glass:
		car_glass.albedo_color = (Color("33424c") * light).lerp(Color(1.0, 0.93, 0.74), night * 0.9)
	soft_mat.albedo_color.a = 0.34 - 0.14 * night
	ao_mat.albedo_color.a = 0.3 - 0.1 * night
	lit_sprites = lit_sprites.filter(func(s): return is_instance_valid(s))
	for s in lit_sprites:
		shine(s)


func golden_at(h: float) -> float:
	if h < GOLDEN[1]:
		return clampf(inverse_lerp(GOLDEN[0], GOLDEN[1], h), 0.0, 1.0)
	return clampf(inverse_lerp(GOLDEN[2], GOLDEN[1], h), 0.0, 1.0)


func dawn_at(h: float) -> float:
	return lerpf(0.6, 1.0, clampf(inverse_lerp(DAWN[0], DAWN[1], h), 0.0, 1.0)) * clampf(inverse_lerp(DAWN[2], DAWN[1], h), 0.0, 1.0)


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


## Shop light falling out of a glass front at face_z across the sidewalk to the kerb, faded in after dusk.
func spill(parent: Node3D, cx: float, w: float, face_z: float) -> void:
	plane(parent, Vector2(w, 4.6), Vector3(cx, -0.028, face_z + 2.3), spill_mat)
	if parent != set_node:
		return  # a shop on the city map: its glow only, the lamp pools that light sprites belong to the set
	var x := cx - w / 2 + 1.5
	while x < cx + w / 2 - 1.0:
		var g := parent.global_position + Vector3(x, 0, face_z + 1.2)
		pools.append(Vector3(g.x, g.z, 2.2))
		x += 2.5


func ground_mat(tex_: ImageTexture) -> StandardMaterial3D:
	var img := tex_.get_image()
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.vertex_color_use_as_albedo = true
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m


## A 4 m square of 2 m paving slabs, white so the district's colour tints it: each slab a shade off, joints darker.
func paving() -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	for sy in 2:
		for sx in 2:
			var base := r.randf_range(0.94, 1.0)
			for y in 8:
				for x in 8:
					var v := base * r.randf_range(0.97, 1.0) * (0.9 if x == 7 or y == 7 else 1.0)
					img.set_pixel(sx * 8 + x, sy * 8 + y, Color(v, v, v))
	return ImageTexture.create_from_image(img)


## Sidewalk pavers for a 2 m repeat: 50 x 25 cm blocks in running bond along the street, each a shade off, joints
## darker; mipmapped so whole streets of them stay calm from the city view.
func pavers() -> StandardMaterial3D:
	var r := RandomNumberGenerator.new()
	r.seed = 23
	var base := Color("dcc4ac")  # warm clay pavers
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for row in 8:
		for k in 4:
			var shade := r.randf_range(0.96, 1.02) if r.randf() < 0.88 else r.randf_range(0.9, 0.93)
			for y in 4:
				for x in 8:
					var px := posmod(k * 8 + x - 4 * (row % 2), 32)
					var v := shade * (0.9 if x == 7 or y == 3 else (1.02 if y == 0 else 1.0))
					img.set_pixel(px, row * 4 + y, Color(base.r * v, base.g * v, base.b * v))
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m


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
	yaw_drag = 0.0
	for e in lm_sprites:
		anchor(e)
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
	# far enough back, and far reaching enough, that the ground stays whole to the frame's top and bottom edges
	cam_dist = maxf(400.0, cam.size * 1.2)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * cam_dist
	cam.far = cam_dist * 2.0 + 100.0
	cam.look_at(target)
	overlay.queue_redraw()


func stripes(a: Color, b: Color, w: int, h: int, on: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(a)
	for x in on:
		for y in h:
			img.set_pixel(x, y, b)
	return ImageTexture.create_from_image(img)


## Your chain's pole-sign face in pixels: a roundel in the stripes' colors and "24" for open all hours.
func sign_face() -> ImageTexture:
	if sign_tex:
		return sign_tex
	var img := Image.create(48, 24, false, Image.FORMAT_RGB8)
	img.fill(Color("fbfaf5"))
	for x in 24:
		for y in 24:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(12, 12))
			if d < 10.5:
				img.set_pixel(x, y, LAYOUT.stripe[0] if d > 7.0 else (Color("fbfaf5") if d > 4.5 else LAYOUT.stripe[1]))
	var glyphs := ["111001111100111", "101101111001001"]  # 2 and 4, 3x5 columns top to bottom
	for g in glyphs.size():
		for i in 15:
			if glyphs[g][i] == "1":
				img.fill_rect(Rect2i(25 + g * 12 + (i % 3) * 3, 5 + floori(i / 3.0) * 3, 3, 3), LAYOUT.stripe[1])
	sign_tex = ImageTexture.create_from_image(img)
	return sign_tex


func tiled(tex_: Texture2D, reps: Vector2) -> StandardMaterial3D:
	var m := mat(Color.WHITE, tex_)
	m.uv1_scale = Vector3(reps.x, reps.y, 1)
	m.texture_repeat = true
	return m


## A city sprite drawn in 2:1 (a landmark, a storefront), its footprint centred on `center` and its drawing `span`
## wide on screen: the cell's empty top trimmed off and the billboard's foreshortening undone (the art already is the
## tilted view). The footprint centre is midway across the drawing, a quarter of its width above its lowest point.
func city_sprite(parent: Node3D, sheet: String, cell: Rect2, span: float, center: Vector3, list: Array) -> Sprite3D:
	if not sheet_imgs.has(sheet):
		sheet_imgs[sheet] = tex[sheet].get_image()
	var u: Rect2i = sheet_imgs[sheet].get_region(Rect2i(cell)).get_used_rect()
	var r := Rect2(cell.position.x, cell.position.y + u.position.y, cell.size.x, u.size.y)
	var px := span / u.size.x
	var s := sprite(sheet, r, px)
	s.scale.y = 1.0 / cos(deg_to_rad(PITCH))
	var ox := r.size.x / 2.0 - u.get_center().x
	s.offset = Vector2(ox, u.size.y / 2.0 - u.size.x / 4.0)
	parent.add_child(s)
	var e := [s, span / 2.0, center, u.size.y * px, u.size.x / 4.0 * px, ox]  # sprite, half width, footprint, height, drop, offset x
	list.append(e)
	anchor(e)
	lit_sprites.append(s)
	return s


## Mirrors a city sprite on the odd quarter turns and slides it along the view line, so its near half stands clear of
## the ground (the ortho view keeps it in place on screen).
func anchor(e: Array) -> void:
	var s: Sprite3D = e[0]
	s.flip_h = posmod(roundi((yaw - PI / 4) / (PI / 2)), 2) == 1
	s.offset.x = -e[5] if s.flip_h else e[5]
	var p := deg_to_rad(PITCH)
	s.position = e[2] + Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * ((e[4] * s.scale.y - 0.1) / sin(p))


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


## Whether r is open country, at least `edge` past the built-up land and clear of roads, parks and water. Out past
## every road, river, park and plot (C.bounds grown by 120 holds them all) only the sea is in the way.
func country(r: Rect2, edge: float) -> bool:
	var p := r.get_center()
	if not C.bounds.grow(120.0).intersects(r):
		return not Geometry2D.is_point_in_polygon(p, C.bay) and not Geometry2D.is_point_in_polygon(p, bay_mouth)
	return Sim.City.nearest(C, p)[1] > Sim.City.URBAN + edge and not Sim.City.blocked(C, r)


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
	var grass := tiled(speckle([Color("7cb058"), Color("8abd62"), Color("70a44e"), Color("98c86c")]), Vector2(1500, 1500))
	plane(city, Vector2(6000, 6000), Vector3(mid.x, -0.16, mid.y), grass)
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
	var fb := b.grow(1300.0)
	var fy := fb.position.y
	while fy < fb.end.y:
		var fh := fr.randf_range(14.0, 26.0)
		var fx := fb.position.x - fr.randf_range(0.0, 20.0)
		while fx < fb.end.x:
			var fw := fr.randf_range(16.0, 36.0)
			var r := Rect2(fx, fy, fw, fh).grow(-0.9)
			if country(r.grow(12.0), 16.0):
				var along := fr.randf() < 0.5
				fs.set_color(Color(FIELDS[fr.randi() % FIELDS.size()]))
				rect_quad(fs, r, -0.155, (r.size.y if along else r.size.x) / 3.0, along)
			fx += fw
		fy += fh
	commit([fs], city)
	# built-up ground, coloured by what the district is: paving slabs in town, fine gravel where it's leafy
	var paved := surface(ground_mat(paving()))
	var gravel := surface(ground_mat(speckle([Color(1, 1, 1), Color(0.95, 0.96, 0.93), Color(0.98, 0.97, 0.94), Color(0.9, 0.92, 0.88)])))
	for bl in C.blocks:
		var dt: String = C.districts[bl.d].type
		var gs: SurfaceTool = gravel if dt in Sim.City.LEAFY else paved
		gs.set_color(Color(Sim.City.GROUND[dt]))
		rect_quad(gs, bl.rect.grow(0.2), -0.15, 0.0, false, 0.25)
	commit([paved, gravel], city)
	var sea_tex := speckle([SEA, SEA.lightened(0.08), SEA.darkened(0.08), SEA.lightened(0.16)])
	var sea := mat(Color.WHITE, sea_tex)
	sea.texture_repeat = true
	var ws := surface(sea)
	poly_fill(ws, C.bay, -0.14)
	poly_fill(ws, bay_mouth, -0.14)
	for poly in C.river:
		poly_fill(ws, poly, -0.14)
	for p in moat_ring(C.parks[0]):
		ws.set_uv(p * 0.125)
		ws.add_vertex(Vector3(p.x, -0.14, p.y))
	var land := surface(mat(Color(Sim.City.GROUND.hub)))
	for isl in C.islands:
		poly_fill(land, isl, -0.135)
	var park_tex := tiled(speckle([Color("68a84a"), Color("76b656"), Color("5c9c42"), Color("86c262")]), Vector2.ONE)
	park_tex.texture_repeat = true
	var ps := surface(park_tex)
	lm_ground = {"water": [sea, 0.125], "grass": [park_tex, 0.25]}
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
		if Models.MODELS.has("%s:%d" % lm):
			continue
		city_sprite(city, lm[0], Rect2(lm[1] * LANDMARK, 0, LANDMARK, LANDMARK_H[lm[0]]), LANDMARK_SPAN * L.size / 22.0, Vector3(L.pos.x, 0, L.pos.y), lm_sprites)
	build_paths()


## The palace moat as triangles: a ring of water from the park's lawn (the same 40-point ellipse) out to the moat's
## bank, so no water lies under the lawn for it to cover by a centimetre; software WebGL loses that centimetre across
## the lawn's long fan triangles and showed the moat over half the lawn.
static func moat_ring(pk: Dictionary) -> PackedVector2Array:
	var inner := Sim.City.ellipse(pk.center, pk.radii, 40)
	var outer := Sim.City.ellipse(pk.center, pk.radii + Vector2(Sim.City.MOAT, Sim.City.MOAT), 40)
	var tris := PackedVector2Array()
	for i in inner.size():
		var j := (i + 1) % inner.size()
		tris.append_array([inner[i], outer[i], outer[j], inner[i], outer[j], inner[j]])
	return tris


## Side streets as rectangles (with junction mouths, zebra crossings and dashes) and the curved avenues.
func build_roads() -> void:
	var walkway := surface(pavers())
	var asphalt := mat(ASPHALT)
	var tar := surface(asphalt)
	var mouth := surface(asphalt)
	var dash_tex := stripes(ASPHALT, Color("e8e2c8"), 8, 1, 4)
	var dm := mat(Color.WHITE, dash_tex)
	dm.texture_repeat = true
	var dash := surface(dm)
	var solid := surface(mat(Color("e8e2c8")))
	var zm := mat(Color.WHITE, stripes(ASPHALT, Color("ece7d8"), 8, 1, 4))
	zm.texture_repeat = true
	var zebra := surface(zm)
	var rail := surface(mat(Color("d9d4c7")))
	var SW := Sim.City.SIDEWALK
	for s in C.streets:
		var along_z: bool = s.axis == "v"
		# the tarmac runs into a T's crossing sidewalk and a park road; at a corner the sidewalk turns round the end,
		# at a quay it meets the railing
		var a0: float = s.from + (0.0 if s.quay[0] else (SW if s.j[0] < 0.0 else -SW))
		var a1: float = s.to - (0.0 if s.quay[1] else (SW if s.j[1] < 0.0 else -SW))
		var d0: float = s.from - minf(s.j[0], 0.0)  # lane markings stop short of a corner
		var d1: float = s.to + minf(s.j[1], 0.0)
		rect_quad(walkway, srect(s, s.from, s.to, 0.0, s.w), -0.12, 0.0, false, 0.5)
		rect_quad(tar, srect(s, a0, a1, SW, s.w - SW), -0.11)
		var len_: float = d1 - d0
		if s.w > Sim.City.ROAD:
			rect_quad(solid, srect(s, d0, d1, s.w / 2 - 0.12, s.w / 2 + 0.12), -0.1)
			for off in [(s.w / 2 + SW) / 2, (s.w * 1.5 - SW) / 2]:
				rect_quad(dash, srect(s, d0, d1, off - 0.07, off + 0.07), -0.1, len_ / 2.0, along_z)
		else:
			rect_quad(dash, srect(s, d0, d1, s.w / 2 - 0.08, s.w / 2 + 0.08), -0.1, len_ / 2.0, along_z)
		# railings: along both sides of a bridge, across a quay
		var c: float = s.line + s.w / 2
		var pt := func(x: float, off := 0.0) -> Vector3: return Vector3(x, 0, c + off) if s.axis == "h" else Vector3(c + off, 0, x)
		for br in s.bridges:
			for side in [s.w / 2 - 0.2, 0.2 - s.w / 2]:
				wall(rail, PackedVector3Array([pt.call(br[0] - 1.0), pt.call(br[1] + 1.0)]), side, -0.12, 0.55)
		for e in 2:
			if s.quay[e]:
				var x: float = s.from + 0.1 if e == 0 else s.to - 0.1
				wall(rail, PackedVector3Array([pt.call(x, -s.w / 2), pt.call(x, s.w / 2)]), 0.0, -0.12, 0.55)
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
		if av.w <= Sim.City.ROAD:  # a park's road: two lanes, as a side street
			ribbon(dash, pts, 0.08, -0.08, -0.1, 0.5)
		elif av.shuto == "":
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


## The Shuto expressway, its ramps and the Yamanote viaduct, in short pieces; pillars below.
func build_elevated() -> void:
	var deck := mat(Color("4f5158"))
	var fascia := mat(Color("c3bfb6"))
	var lines := mat(Color("e8e2c8"))
	var dm := mat(Color.WHITE, stripes(Color("4f5158"), Color("e8e2c8"), 8, 1, 3))
	dm.texture_repeat = true
	var pillars: Array = []  # transforms
	var routes: Array = Sim.City.elevated(C)
	for ri in routes.size():
		var e: Dictionary = routes[ri]
		var pts := lifted(e.pts)
		if e.closed:
			pts.append(pts[1])  # so the loop's last piece turns into its first
		var half: float = e.w / 2
		var i := 0
		while i < e.pts.size() - 1:
			var j := mini(i + 8, e.pts.size() - 1)
			var lo := maxi(0, i - 1)
			var part := pts.slice(lo, mini(j + 2, pts.size()))
			var top := surface(deck)
			var side := surface(fascia)
			ribbon(top, part, half, -half, 0.0, 0.0, i - lo, j - lo)
			for sd in [half, -half]:
				wall(side, part, sd, -0.9, 0.0, i - lo, j - lo)
			elevated.append(commit([top, side], city))
			i = j
		# parapets, edge lines, the median barrier and lane lines, left out where another carriageway runs into this one
		var walls := surface(fascia)
		var mark := surface(lines)
		var extra := surface(dm)
		var specs := [[half, walls, 0.6], [-half, walls, 0.6], [half - 0.5, mark, 0.0], [0.5 - half, mark, 0.0]]
		if not e.ramp:
			specs += [[0.0, walls, 0.5], [half / 2, extra, 0.0], [-half / 2, extra, 0.0]]
		for sp in specs:
			for run in Sim.City.line_runs(C, ri, sp[0]):
				var sub := sub_line(e, pts, run[0], run[1])
				if sp[2] > 0.0:
					wall(sp[1], sub[0], sp[0], 0.0, sp[2], sub[1], sub[2])
				else:
					ribbon(sp[1], sub[0], sp[0] + 0.07, sp[0] - 0.07, 0.02, 0.5 if sp[1] == extra else 0.0, sub[1], sub[2])
		elevated.append(commit([walls, mark, extra], city))
	for dp in Sim.City.deck_pillars(C):  # where the city put the pillars: off the Yamanote's viaduct and the shop sets
		var p: Vector3 = dp[2]
		pillars.append(Transform3D(Basis.from_scale(Vector3(dp[3], p.y, dp[3])), Vector3(p.x, p.y / 2.0, p.z)))
	build_rail(pillars)
	pillar_mm = multimesh(BoxMesh.new(), pillars.size())
	for k in pillars.size():
		pillar_mm.set_instance_transform(k, pillars[k])
	mm_node(pillar_mm, mat(Color("aaa59b")), city)


## An elevated carriageway's surface: 0.3 over its points on the deck, down to the road's own where a ramp lands.
static func lifted(pts: PackedVector3Array) -> PackedVector3Array:
	var out := pts.duplicate()
	for i in out.size():
		out[i].y += lerpf(-0.105, 0.3, clampf(pts[i].y / Sim.City.DECK, 0.0, 1.0))
	return out


## The surface points of carriageway e between arc lengths a and b, cut where those fall between its points, with the
## loop's points either side of its start added undrawn so lines run on round it: [points, first, last] for ribbon.
static func sub_line(e: Dictionary, pts: PackedVector3Array, a: float, b: float) -> Array:
	var cum: PackedFloat32Array = e.cum
	var n: int = e.pts.size()
	var cut := func(x: float) -> Vector3:
		var k := clampi(cum.bsearch(x), 1, n - 1)
		var seg := cum[k] - cum[k - 1]
		return pts[k - 1].lerp(pts[k], (x - cum[k - 1]) / seg if seg > 0.0 else 0.0)
	var out := PackedVector3Array()
	if e.closed and a <= 0.001:
		out.append(pts[n - 2])
	var first := out.size()
	out.append(cut.call(a))
	for k in n:
		if cum[k] > a + 0.001 and cum[k] < b - 0.001:
			out.append(pts[k])
	out.append(cut.call(b))
	var last := out.size() - 1
	if e.closed and b >= cum[-1] - 0.001:
		out.append(pts[1])
	return [out, first, last]


## The Yamanote viaduct: two tracks on a ballasted deck with parapets and the line's green stripe, an island platform
## under a canopy at each station; a column and cap beam under it at each pier.
func build_rail(pillars: Array) -> void:
	var CT := Sim.City
	var ballast := tiled(speckle([Color("8a8174"), Color("938a7d"), Color("80786c"), Color("9b9285")]), Vector2(1, CT.RAIL_W / 3.2))
	var bed := mat(Color.WHITE, sleepers())
	var steel := mat(Color("aeaca6"))
	var web := mat(Color("4a4440"))
	var fascia := mat(Color("c3bfb6"))
	var green := mat(Color("7fc241"))
	var slab := mat(Color("d6d2c6"))
	var edge := mat(Color("e8c84a"))
	var roof := mat(Color("8f979b"))
	var post := mat(Color("6d7378"))
	var half: float = CT.RAIL_W / 2
	var y: float = CT.RAIL_DECK
	var loop: PackedVector3Array = flat3(C.rail_loop, y)
	var i := 0
	while i < loop.size() - 1:
		var j := mini(i + 8, loop.size() - 1)
		var part := PackedVector3Array()
		for k in range(i - 1, j + 2):  # one point either side, so the strip's edges turn with the line
			part.append(loop[posmod(k, loop.size() - 1)])
		var top := surface(ballast)
		var beds := surface(bed)
		var rails := surface(steel)
		var webs := surface(web)
		var side := surface(fascia)
		var stripe := surface(green)
		var f := 1
		var l := part.size() - 2
		ribbon(top, part, half, -half, 0.3, 1.0 / 3.2, f, l)
		for t in [CT.TRACK, -CT.TRACK]:
			ribbon(beds, part, t + 1.3, t - 1.3, 0.31, 1.0 / 0.6, f, l)
			for g in [0.6, -0.6]:
				ribbon(rails, part, t + g + 0.06, t + g - 0.06, 0.37, 0.0, f, l)
				for e in [0.05, -0.05]:
					wall(webs, part, t + g + e * 1.2, 0.31, 0.37, f, l)
		for s in [half, -half]:
			wall(side, part, s, -0.6, 0.9, f, l)
		for s in [half + 0.01, -half - 0.01]:
			wall(stripe, part, s, 0.25, 0.45, f, l)
		elevated.append(commit([top, beds, webs, rails, side, stripe], city))
		i = j
	# stations: an island platform between the tracks, its yellow edges, a canopy on posts
	for st in C.stations:
		var pts := PackedVector3Array()
		for k in int(CT.PLATFORM_L / 2.0) + 3:
			var pt: Array = CT.rail_at(C, st.s - CT.PLATFORM_L / 2 + (k - 1) * 2.0)
			pts.append(Vector3(pt[0].x, y, pt[0].y))
		var pw: float = CT.PLATFORM_W / 2
		var deckp := surface(slab)
		var lines := surface(edge)
		var sides := surface(fascia)
		var canopy := surface(roof)
		var posts := surface(post)
		var f := 1
		var l := pts.size() - 2
		ribbon(deckp, pts, pw, -pw, 1.1, 0.0, f, l)
		for s in [pw, -pw]:
			wall(sides, pts, s, 0.3, 1.1, f, l)
			ribbon(lines, pts, s * 0.8 + 0.08, s * 0.8 - 0.08, 1.12, 0.0, f, l)
		ribbon(canopy, pts, pw + 0.25, -pw - 0.25, 3.6, 0.0, f, l)  # over the platform, just above the cars' roofs
		for s in [pw + 0.25, -pw - 0.25]:
			wall(canopy, pts, s, 3.45, 3.6, f, l)
		for k in range(f, l + 1, 3):
			var d := pts[mini(k + 1, pts.size() - 1)] - pts[k - 1]
			block_into(posts, pts[k] + Vector3(0, 2.3, 0), Vector3(0.22, 2.4, 0.22), atan2(d.x, d.z))
		elevated.append(commit([deckp, lines, sides, canopy, posts], city))
	# piers: a column where the city found room for one, under a cap beam across the deck
	for pr in C.piers:
		var at_: Vector2 = pr[1]
		var on: Array = CT.rail_at(C, pr[0])
		var turn := atan2(on[1].x, on[1].y)
		pillars.append(Transform3D(Basis.from_scale(Vector3(1.2, y - 0.6, 1.2)), Vector3(at_.x, (y - 0.6) / 2.0, at_.y)))
		pillars.append(Transform3D(Basis(Vector3.UP, turn) * Basis.from_scale(Vector3(CT.RAIL_W - 0.6, 0.7, 1.1)), Vector3(on[0].x, y - 0.6, on[0].y)))


## One sleeper on its ballast bed, u along the track (a sleeper every texture width), v across it: a concrete tie
## between the bed's shoulders, a shadow on its far side.
func sleepers() -> ImageTexture:
	var img := Image.create(6, 13, false, Image.FORMAT_RGB8)
	img.fill(Color("6a6259"))
	img.fill_rect(Rect2i(1, 1, 2, 11), Color("b3ada2"))
	img.fill_rect(Rect2i(3, 1, 1, 11), Color("58514a"))
	for y in [0, 12]:
		for x in 6:
			img.set_pixel(x, y, Color("7b7368") if x % 2 else Color("8a8174"))
	return ImageTexture.create_from_image(img)


## A box into a surface: centre c, size, turned `turn` about y (unshaded flat colour, as the walls round it).
func block_into(st: SurfaceTool, c: Vector3, size_: Vector3, turn: float) -> void:
	var b := Basis(Vector3.UP, turn)
	var h := size_ / 2
	for n: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3.UP]:
		var u := Vector3.UP if absf(n.y) < 0.5 else Vector3.RIGHT
		var v := n.cross(u)
		var q := [n + u + v, n - u + v, n - u - v, n + u - v].map(func(o): return c + b * (o * h))
		add_quad(st, q, [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])


## Every building as a box with a facade shader (one MultiMesh), gable roofs on houses and kit on flat roofs.
func build_buildings() -> void:
	var shader := Shader.new()
	shader.code = BUILDING_SHADER.replace("FLAT_ROOFS", ", ".join(Sim.City.FLAT_ROOFS.map(func(h): return "vec3(%.3f, %.3f, %.3f)" % [Color(h).r, Color(h).g, Color(h).b]))).replace("ROOF_TINT", "%.2f" % ROOF_TINT)
	building_mat = ShaderMaterial.new()
	building_mat.shader = shader
	var atlas := facade_atlas()
	building_mat.set_shader_parameter("facades", atlas[0])
	building_mat.set_shader_parameter("accents", atlas[1])
	building_mat.set_shader_parameter("styles", float(Sim.City.STYLE_COUNT))
	var all: Array = Sim.City.buildings()
	var boxes := []
	var roofs := []
	brecs.clear()
	for bd in all:
		var r: Rect2 = bd.rect
		var c: Vector2 = bd.center
		var sz: Vector2 = bd.size
		var h: float = bd.floors * Sim.City.FLOOR
		var rec := {"foot": r, "h": h, "box": [boxes.size()], "roof": [], "hidden": STANDING}
		var tint: Color = bd.tint
		tint.a = (bd.accent + 0.5) / 8.0
		boxes.append([Vector3(sz.x, h, sz.y), Vector3(c.x, h / 2, c.y), tint, bd.style + bd.kit * 0.49, bd.angle])
		if bd.roof != "":
			var rh := minf(sz.x, sz.y) * 0.32
			rec.roof.append(roofs.size())
			roofs.append([c, sz, h, rh, Color(bd.roof), bd.angle])
			rec.h += rh
		elif bd.floors >= 3 and bd.angle == 0.0 and r.size.x > 6.0 and r.size.y > 6.0:
			var k: float = bd.kit
			var ks := Vector3(1.6 + 1.6 * k, 1.2, 1.4 + 1.8 * (1.0 - k))
			var at_ := Vector3(r.position.x + 1.0 + ks.x / 2 + (r.size.x - ks.x - 2.0) * k, h + 0.6, r.position.y + 1.0 + ks.z / 2 + (r.size.y - ks.z - 2.0) * (1.0 - k))
			rec.box.append(boxes.size())
			boxes.append([ks, at_, Color("c9c7c0"), Sim.City.PLAIN, 0.0])
		brecs.append(rec)
	# landmarks with a traced model join the city's boxes and roofs on their square, one record each, so they cast
	# shadows, light up and clear for the street set like any building, but go whole
	lm_trees.clear()
	for L in C.landmarks:
		var key := "%s:%d" % C.districts[L.d].lm
		if not Models.MODELS.has(key):
			continue
		var k: float = L.size / 22.0  # models are traced on a 22 m square; a smaller square gets a smaller landmark
		var rec := {"foot": Rect2(L.pos - Vector2.ONE * L.size / 2, Vector2.ONE * L.size), "h": 0.0, "box": [], "roof": [], "hidden": STANDING, "lm": true}
		var st: SurfaceTool = null
		var grounds := {}
		for q in Models.MODELS[key]:
			if q[0] == 3:
				lm_trees.append([Vector3(L.pos.x + q[1] * k, q[5] * k, L.pos.y + q[2] * k), q[3] * k, q[4]])
				continue
			if q[0] == 4:
				if st == null:
					st = SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
				var pts: Array[Vector3] = []
				for i in range(5, q.size(), 3):
					pts.append(Vector3(L.pos.x + q[i] * k, q[i + 1] * k, L.pos.y + q[i + 2] * k))
					rec.h = maxf(rec.h, q[i + 1] * k)
				st.set_color(Color(q[1]))
				st.set_normal(Vector3(q[2], q[3], q[4]).normalized())
				for i in range(1, pts.size() - 1):  # packed counter-clockwise round the normal; Godot's front faces are clockwise
					st.add_vertex(pts[0])
					st.add_vertex(pts[i + 1])
					st.add_vertex(pts[i])
				continue
			var lo := Vector2(q[1], q[2]) * k
			var sz := Vector2(q[3] - q[1], q[4] - q[2]) * k
			var at_: Vector2 = L.pos + lo + sz / 2
			if q[0] == 0:
				var tint := Color(q[7])
				# a pool or lawn slab takes the city's own textured water or park ground on top: a pool lies flush on the
				# ground in place of its slab, a lawn keeps its slab (a raised bank) under a textured top
				var gk := ""
				if q[8] < 0 and q[6] - q[5] <= 0.6 and sz.x * sz.y >= 4.0 and tint.s > 0.3 and tint.v > 0.35:
					gk = "water" if tint.h > 0.5 and tint.h < 0.67 and tint.v > 0.45 and q[5] < 1.0 else ("grass" if tint.h > 0.17 and tint.h < 0.45 else "")
				if gk != "":
					if not grounds.has(gk):
						grounds[gk] = surface(lm_ground[gk][0])
					var gy: float = maxf(q[5] * k, 0.0) + 0.01 if gk == "water" else q[6] * k + 0.01
					rect_quad(grounds[gk], Rect2(L.pos + lo, sz), gy, 0.0, false, lm_ground[gk][1])
					if gk == "water":
						continue
				tint.a = (q[9] + 0.5) / 8.0
				rec.box.append(boxes.size())
				boxes.append([Vector3(sz.x, (q[6] - q[5]) * k, sz.y), Vector3(at_.x, (q[5] + q[6]) / 2 * k, at_.y), tint, q[8] + 0.245 if q[8] >= 0 else -1.0, q[10] if q.size() > 10 else 0.0])
				rec.h = maxf(rec.h, q[6] * k)
			else:
				rec.roof.append(roofs.size())
				roofs.append([at_, sz, q[5] * k, q[6] * k, Color(q[7]), 0.0, q[0] == 1])
				rec.h = maxf(rec.h, (q[5] + q[6]) * k)
		if st:  # the curved and slanted parts: one mesh in vertex colours, shaded as the plain path of the boxes' shader
			var mm := multimesh(st.commit(), 1, true, true)
			mm.set_instance_transform(0, Transform3D.IDENTITY)
			mm.set_instance_color(0, Color.WHITE)
			mm.set_instance_custom_data(0, Color(0, 0, 0, -1))
			rec.shapes = [mm_node(mm, building_mat, city)]
		if not grounds.is_empty():
			rec.shapes = rec.get("shapes", []) + [commit(grounds.values(), city)]
		brecs.append(rec)
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
		if e[6] if e.size() > 6 else sz.x > sz.y:  # ridge along the longer side, or as a landmark model says
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
	for rec in brecs:
		for n in rec.get("shapes", []).duplicate():
			if n is MultiMeshInstance3D:
				rec.shapes.append(mm_node(n.multimesh, white, mask_vp))
	for part in elevated:
		var mi := MeshInstance3D.new()
		mi.mesh = part.mesh
		mi.material_override = white
		mask_vp.add_child(mi)
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
					else:  # a shopfront: striped awning, shelves behind mullioned glass, a glazed door, lit after dark
						r.call(0, 0, 32, 2, wall_px(0.82))
						for x in range(0, 32, 4):
							r.call(x, 2, 2, 7, accent(1.0))
							r.call(x + 2, 2, 2, 7, accent(0.78))
							r.call(x + 1, 9, 2, 1, accent(0.78))
						r.call(0, 10, 32, 1, wall_px(0.55))
						r.call(1, 11, 21, 18, fixed("4a525a"))
						r.call(2, 12, 19, 16, fixed(SHOP_GLASS))
						r.call(11, 12, 1, 16, fixed("4a525a"))
						for y in [19, 24]:
							r.call(2, y, 19, 1, fixed("b9bdb8"))
						var goods := ["e0a040", "d05050", "60a060", "5a8fd0", "e8e0c8"]
						for i in 8:
							var gx: int = [3, 6, 8, 13, 15, 18, 3, 14][i]
							var gy := 21 if i < 6 else 15
							r.call(gx, gy, 2, 3, fixed(goods[i % goods.size()]))
						r.call(13, 22, 6, 2, fixed("f2efe4"))
						r.call(1, 29, 21, 3, wall_px(0.68))
						r.call(23, 11, 8, 21, fixed("4a525a"))
						r.call(24, 12, 6, 19, fixed(SHOP_GLASS))
						r.call(24, 12, 6, 3, accent(0.9))
						r.call(25, 21, 1, 3, fixed("d8d8d0"))
						r.call(23, 31, 8, 1, fixed("8a8a84"))
						# the shop inside the glass (shelves, goods, the door's pane) lights up after dark in its own colours
						for win in [Rect2i(2, 12, 19, 16), Rect2i(24, 15, 6, 16)]:
							for y in range(win.position.y, win.end.y):
								for x in range(win.position.x, win.end.x):
									var px := img.get_pixel(s * 32 + x, y).to_html(false)
									if px != "4a525a":
										mask.set_pixel(s * 32 + x, y, Color(0, 1 if px == SHOP_GLASS else 0, 1))
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
				10:  # brick: two upright windows a bay in white stone frames on every floor, a string course at the floor line
					r.call(0, 29, 32, 3, fixed("e6e0d2"))
					for x in [5, 19]:
						r.call(x, 6, 8, 19, fixed("efe9dc"))
						r.call(x + 1, 7, 6, 17, glass2)
						r.call(x + 1, 13, 6, 1, fixed("efe9dc"))
				_:  # plain
					r.call(0, 30, 32, 2, wall_px(0.86))
					r.call(12, 10, 8, 5, wall_px(0.7))
	img.generate_mipmaps()
	mask.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(mask)]


const SHOP_GLASS := "a9cdd6"  # a shop window's pane: the back of the shop, glowing after dark
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
	for t in lm_trees:  # the trees a landmark model plants, on the bank or plinth under them
		if not spots.has(t[2]):
			spots[t[2]] = []
		spots[t[2]].append([t[0], t[1]])
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
	var b: Rect2 = C.bounds.grow(1300.0)
	for k in 900:  # woods out in the country, clear of the roads
		var g := Vector2(r.randf_range(b.position.x, b.end.x), r.randf_range(b.position.y, b.end.y))
		var rad := r.randf_range(4.0, 14.0)
		for j in int(rad * rad * 0.12) + 3:
			var p := g + Vector2.from_angle(r.randf() * TAU) * rad * sqrt(r.randf())
			if country(Rect2(p - Vector2.ONE, Vector2(2, 2)), 8.0):
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
		lit_mats.append([weakref(m), Color.WHITE, 0.0])
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
	lot_nodes.clear()
	lot_feet.clear()
	var plot := surface(mat(Color.WHITE, tiles(Color("d8d2c4"), Color("bdb6a6"))))
	for L in sim.lots:
		rect_quad(plot, Rect2(L.x0, L.front - Sim.City.LOT_D, Sim.City.LOT_W, Sim.City.LOT_D), -0.08, 0.0, false, 0.5)
	commit([plot], lots_node)
	for b in sim.branches:
		if mode == "store" and is_same(b, branch):
			continue
		# your shop and the rival next door, built from the same boxes as the street set, in the lot's street frame
		var o := frame_origin(b.lot)
		var n := Node3D.new()
		n.position = o
		lots_node.add_child(n)
		build_shop(n, Sim.ZONE_LEFT[b.store.size])
		build_rival(n, b.rival, rival_span(b.rival))
		lot_nodes.append([n, Vector2(o.x + Sim.ORIGIN.x, o.z + Sim.ORIGIN.y)])
		var zl: float = Sim.ZONE_LEFT[b.store.size]
		var rs := rival_span(b.rival)
		lot_feet.append(Rect2(o.x + Sim.ORIGIN.x + zl, o.z + Sim.ORIGIN.y - 4.65, 6.6 - zl, 9.3))
		lot_feet.append(Rect2(o.x + rs.x, o.z - 16.2, rs.y - rs.x, 9.0))


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
		parts.append("%d%s%s%d" % [b.lot, b.rival.id, b.rival.defeated, b.store.size])
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
	for e in lot_nodes:
		e[0].visible = not taken.call(Rect2(e[1] - Vector2(0.5, 0.5), Vector2.ONE))
	for e in lm_sprites:
		var s: Sprite3D = e[0]
		var at_ := Vector2(e[2].x, e[2].z)
		var base := iso(e[2])
		var r := Rect2(base + Vector2(-e[1], e[4] - e[3]), Vector2(e[1] * 2, e[3]))
		# cleared like the trees when in front of the street, rather than left as a see-through ghost over it
		s.visible = not taken.call(Rect2(at_ - Vector2(0.5, 0.5), Vector2.ONE)) and not (on and r.intersects(scr) and at_.x + at_.y > depth)
	var away := Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -50, 0))
	# city buildings in front of the street are cut down to their ground floor (cut back to the far edge of the
	# near sidewalk when they reach over it), so the street shows over a block that still reads as city
	var edge := front.position.y + 14.8
	var dirty := {}
	for rec in brecs:
		var f: Rect2 = rec.foot
		var state := STANDING
		if lot_feet.any(func(q): return f.intersects(q)):
			state = GONE
		elif on:
			if set_feet.any(func(q): return f.intersects(q)) or (f.intersects(front) and f.get_center().y < front.position.y + 7.2):
				state = GONE
			elif f.intersects(front) or (f.end.x + f.end.y > depth and foot_rect(f, rec.h).intersects(scr)):
				state = maxf(f.position.y, edge)
				if rec.has("lm") or f.end.y - state < 2.0 or (state > f.position.y and box_base[rec.box[0]].basis.x.z != 0.0):  # too thin, or turned
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
		for k in rec.roof:
			roof_mm.set_instance_transform(k, roof_base[k] if state == STANDING else away)
			dirty[roof_mm] = true
		for n in rec.get("shapes", []):
			n.visible = state == STANDING
	for tm in tree_mms:
		for k in tm[1].size():
			var p: Vector3 = tm[1][k].origin
			var cut: bool = taken.call(Rect2(p.x - 1.5, p.z - 1.5, 3, 3)) or lot_feet.any(func(q): return q.has_point(Vector2(p.x, p.z))) or (on and p.x + p.z > depth and foot_rect(Rect2(p.x - 1.5, p.z - 1.5, 3, 3), tm[2]).intersects(scr))
			if tm[0].get_instance_transform(k) != (away if cut else tm[1][k]):
				tm[0].set_instance_transform(k, away if cut else tm[1][k])
				dirty[tm[0]] = true
	# the decks overhead, their pillars and the trains always stay: the city keeps them off the set (City.under_deck)
	# and the set's own buildings and street furniture keep out from under them (decks_near)
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
	var t3 := cam.position - cam.global_transform.basis.z * cam_dist
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
		pa.span = rp.span
		pa.ground = paths.filter(func(q): return q.kind == "avenue" and q.name == av.name)[0]
		pa.deck = decks[av.shuto]
		paths.append(pa)
	for trn in trains:
		for car in trn.cars:
			car.queue_free()
	trains.clear()
	var mesh := car_mesh()
	for dir in [1, -1]:
		for k in Sim.City.TRAINS:
			var set_ := []
			for j in Sim.City.CARS:
				var car := MeshInstance3D.new()
				car.mesh = mesh
				street.add_child(car)
				set_.append(car)
			trains.append({"dir": dir, "k": k, "cars": set_})


## A Yamanote car: stainless body on its bogies, green door panels and stripes, a window band that lights up after
## dark, a roof with its air-conditioning unit. Length along x, across z, y up from the rail; walls shaded as boxes.
func car_mesh() -> ArrayMesh:
	var L: float = Sim.City.CAR_L / 2
	var W: float = Sim.City.CAR_W / 2
	var H: float = Sim.City.CAR_H
	var body := mat(Color.WHITE)
	body.vertex_color_use_as_albedo = true
	body.vertex_color_is_srgb = true
	if not car_glass:
		car_glass = StandardMaterial3D.new()
		car_glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		car_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
		car_glass.albedo_color = Color("33424c") * light
	var sb := surface(body)
	var sg := surface(car_glass)
	var boxes := [  # [from, to, colour, the surface]
		[Vector3(-L + 1.0, 0.0, -W + 0.45), Vector3(-L + 2.2, 0.55, W - 0.45), "2b2b2e", sb],
		[Vector3(L - 2.2, 0.0, -W + 0.45), Vector3(L - 1.0, 0.55, W - 0.45), "2b2b2e", sb],
		[Vector3(-L + 0.3, 0.3, -W + 0.25), Vector3(L - 0.3, 0.7, W - 0.25), "3d3e42", sb],
		[Vector3(-L, 0.7, -W), Vector3(L, H - 0.2, W), "c9cdd0", sb],
		[Vector3(-L + 0.1, H - 0.2, -W + 0.1), Vector3(L - 0.1, H - 0.05, W - 0.1), "a8aeb2", sb],
		[Vector3(-1.3, H - 0.05, -0.8), Vector3(1.3, H + 0.2, 0.8), "8d9397", sb],
		[Vector3(-L + 0.35, 1.45, -W - 0.02), Vector3(L - 0.35, 2.1, W + 0.02), "", sg],
		[Vector3(-L, 0.9, -W - 0.03), Vector3(L, 1.12, W + 0.03), "7fc241", sb],
		[Vector3(-L, 2.2, -W - 0.03), Vector3(L, 2.34, W + 0.03), "7fc241", sb],
	]
	for x in [-L * 0.55, L * 0.55]:  # a door each way, green, with its window
		boxes.append([Vector3(x - 0.5, 0.8, -W - 0.05), Vector3(x + 0.5, 2.45, W + 0.05), "5fa83a", sb])
		boxes.append([Vector3(x - 0.3, 1.55, -W - 0.07), Vector3(x + 0.3, 2.1, W + 0.07), "", sg])
	for bx in boxes:
		var a: Vector3 = bx[0]
		var b: Vector3 = bx[1]
		var st: SurfaceTool = bx[3]
		var c := Color(bx[2]) if bx[2] != "" else Color.WHITE
		for fc in [[Vector3.UP, 1.0], [Vector3.BACK, 0.9], [Vector3.FORWARD, 0.75], [Vector3.RIGHT, 0.85], [Vector3.LEFT, 0.8]]:
			var n: Vector3 = fc[0]
			var u := Vector3.UP if absf(n.y) < 0.5 else Vector3.RIGHT
			var v := n.cross(u)
			var mid := (a + b) / 2
			var h := (b - a) / 2
			st.set_color(Color(c.r * fc[1], c.g * fc[1], c.b * fc[1]))
			add_quad(st, [n + u + v, n - u + v, n - u - v, n + u - v].map(func(o): return mid + o * h), [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var mesh := ArrayMesh.new()
	sb.commit(mesh)
	sg.commit(mesh)
	return mesh


## Every train where the timetable has it: each car between its two bogies on its own track (keeping left), so a
## train bends round the curves.
func run_trains() -> void:
	var CT := Sim.City
	var pitch: float = CT.CAR_L + CT.CAR_GAP
	var y: float = CT.RAIL_DECK + 0.36
	for trn in trains:
		var s: float = CT.train_s(C, trn.dir, trn.k, rail_t)
		for j in trn.cars.size():
			var car: MeshInstance3D = trn.cars[j]
			var c: float = s + trn.dir * ((CT.CARS - 1) / 2.0 - j) * pitch
			var ends := []
			for e in [1.0, -1.0]:
				var pt: Array = CT.rail_at(C, c + trn.dir * e * (CT.CAR_L / 2 - 1.6))
				ends.append(pt[0] + Vector2(pt[1].y, -pt[1].x) * CT.TRACK * trn.dir)
			var fw: Vector2 = (ends[0] - ends[1]).normalized()
			var m: Vector2 = (ends[0] + ends[1]) / 2
			var x3 := Vector3(fw.x, 0, fw.y)
			car.transform = Transform3D(Basis(x3, Vector3.UP, x3.cross(Vector3.UP)), Vector3(m.x, y, m.y))


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
	o.s = p.span[1] if o.v > 0.0 else p.span[0]
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
	rail_t += delta
	run_trains()


## Cars on the set's street, keeping left: each waits behind the one ahead and stops at the crossing on amber and
## red, headlights washing the road ahead after dark.
func street_traffic(delta: float) -> void:
	delta = minf(delta, 0.5)
	var lt: Array = sim.lights()
	var held: bool = lt[0] or lt[2]
	next_set_car -= delta * (Sim.band(sim.hour()).traffic / 1.2 if sim.phase == "playing" else 1.0)
	if next_set_car <= 0.0:
		next_set_car = randf_range(1.5, 4.0)
		var dir := 1.0 if randf() < 0.5 else -1.0
		var x0 := SET.position.x if dir > 0.0 else SET.end.x
		if not set_cars.any(func(o): return o.dir == dir and absf(o.x - x0) < 8.0):
			var kv := randi() % 4
			var node := sprite("vehicles", Rect2(kv * 2 * VEHICLE_CELL.x, 0, VEHICLE_CELL.x, VEHICLE_CELL.y), VEHICLE_PX)
			var y := VEHICLE_CELL.y / 2.0 * VEHICLE_PX - 0.1
			node.add_child(shadow(y, 1.5))
			var beam := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(3.2, 2.2)
			beam.mesh = pm
			beam.material_override = pool_mat
			beam.position = Vector3(3.2 * dir, 0.03 - y, 0)
			node.add_child(beam)
			node.position = Vector3(x0, y, -1.7 * dir)
			set_node.add_child(node)
			facing(node, Vector3(dir, 0, 0), kv * 2, VEHICLE_CELL)
			var cruise := randf_range(5.0, 8.0) * (0.6 if kv == 3 else 1.0)
			set_cars.append({"node": node, "x": x0, "v": cruise, "dir": dir, "cruise": cruise})
	var gone := []
	for o in set_cars:
		var room_ := INF
		for q in set_cars:
			if q != o and q.dir == o.dir and (q.x - o.x) * o.dir > 0.0:
				room_ = minf(room_, (q.x - o.x) * o.dir - 5.5)
		var line: float = (Sim.CROSS_X - 4.0 * o.dir - o.x) * o.dir  # the car's centre to its stop line
		if held and line > -0.2:
			room_ = minf(room_, line)
		o.v = minf(move_toward(o.v, o.cruise, 4.0 * delta), maxf(room_, 0.0) * 1.2)
		o.x += o.dir * o.v * delta
		o.node.position.x = o.x
		shine(o.node)
		if o.x > SET.end.x or o.x < SET.position.x:
			gone.append(o)
	for o in gone:
		o.node.queue_free()
	set_cars = set_cars.filter(func(o): return not gone.has(o))


## Settled snow for an 8 m repeat: drifts at three scales on wrapping value noise, in whole pixels like the pavers.
func snow_patches() -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 23
	var grids := []
	for n in [4, 8, 16]:
		var g := PackedFloat32Array()
		for i in n * n:
			g.append(r.randf())
		grids.append([n, g])
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var v := 0.0
			for k in grids.size():
				var n: int = grids[k][0]
				var g: PackedFloat32Array = grids[k][1]
				var fx := x * n / 64.0
				var fy := y * n / 64.0
				var ix := int(fx)
				var iy := int(fy)
				var tx := smoothstep(0.0, 1.0, fx - ix)
				var ty := smoothstep(0.0, 1.0, fy - iy)
				var a := lerpf(g[iy * n + ix], g[iy * n + (ix + 1) % n], tx)
				var b := lerpf(g[(iy + 1) % n * n + ix], g[(iy + 1) % n * n + (ix + 1) % n], tx)
				v += lerpf(a, b, ty) * [0.5, 0.3, 0.2][k]
			v += r.randf_range(-0.03, 0.03)
			var c := Color(0.94, 0.96, 1.0, 0.92) if v > 0.42 else (Color(0.86, 0.9, 0.98, 0.62) if v > 0.3 else Color(1, 1, 1, 0))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Snow lying on the set: drifts over the sidewalks and the car park, and on the road a dusting along the kerbs and
## between the wheel tracks, which stay dark. Hidden until a cold snap.
func settled_snow(far_gaps: Array, near_gaps: Array) -> MeshInstance3D:
	var deep := surface(mat(Color(1, 1, 1, 0.999), snow_tex))
	var thin := surface(mat(Color(1, 1, 1, 0.6), snow_tex))
	for sd in [[far_gaps, -7.2], [near_gaps, 3.7]]:
		for o in open_spans(sd[0]):
			rect_quad(deep, Rect2(o.x, sd[1], o.y - o.x, 3.5), -0.034, 0.0, false, 0.125)
	rect_quad(deep, Rect2(-3.4, -16.0, 7.1, 8.8), -0.034, 0.0, false, 0.125)
	for band in [Vector2(-3.7, -3.05), Vector2(-2.25, -1.55), Vector2(-0.45, 0.45), Vector2(1.55, 2.25), Vector2(3.05, 3.7)]:
		rect_quad(thin, Rect2(SET.position.x, band.x, SET.size.x, band.y - band.x), -0.034, 0.0, false, 0.125)
	var mi := commit([deep, thin], set_node)
	mi.visible = false
	return mi


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
	slot_goods.clear()
	pools.clear()
	set_cars.clear()
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
	var made := surface(mat(Color(Sim.City.GROUND[type])))
	var made_runs := []
	if near_water():
		made_runs = water_runs(-9.2, 9.2) + water_runs(-20.2, -7.2, -16.5, span.y)
		for w in made_runs:
			rect_quad(made, w, -0.125)  # over the water, under any bridge
		roads.append_array(water_runs(SET.position.y, -20.2) + water_runs(-20.2, -7.2, SET.position.x, -16.5) + water_runs(-20.2, -7.2, span.y, SET.end.x))
	var far_gaps := mouths(-8.2, -3.6, side_roads, Vector2(-16.5, span.y))  # none between your shop and the rival
	var near_gaps := mouths(3.6, 8.2, side_roads)
	var overhead := decks_near()
	var under := [mouths(-8.2, -3.6, overhead), mouths(3.6, 8.2, overhead)]  # where a deck crosses each sidewalk
	var walk := surface(pavers())
	var tar := surface(tiled(speckle([ASPHALT, ASPHALT.darkened(0.05), ASPHALT.lightened(0.06), ASPHALT.darkened(0.08)]), Vector2.ONE))
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
	var bay := surface(tiled(speckle([ASPHALT.lightened(0.1), ASPHALT.lightened(0.06), ASPHALT.lightened(0.14), ASPHALT.lightened(0.03)]), Vector2.ONE))
	rect_quad(bay, Rect2(-3.4, -16.0, 7.1, 8.8), -0.042, 0.0, false, 0.5)
	for kb in [Rect2(-3.4, -16.25, 7.1, 0.25), Rect2(3.45, -16.25, 0.25, 9.05)]:  # kerb round the back and side
		rect_quad(kerb, kb, -0.036)
	for bx in [-2.2, 0.2, 2.6]:
		rect_quad(paint, Rect2(bx, -15.6, 0.12, 4.6), -0.038)
	rect_quad(paint, Rect2(-2.2, -15.6, 4.92, 0.12), -0.038)  # the bays' back line
	var hatch := surface(mat(Color("e2c048")))
	var hz := -15.4
	while hz < -11.2:  # yellow hatching keeps the strip along your wall clear for bicycles
		add_quad(hatch, [Vector3(-3.25, -0.038, hz), Vector3(-3.25, -0.038, hz + 0.16), Vector3(-2.35, -0.038, hz + 0.66), Vector3(-2.35, -0.038, hz + 0.5)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		hz += 0.7
	for hr in [Rect2(-3.3, -15.6, 1.04, 0.1), Rect2(-3.3, -11.1, 1.04, 0.1), Rect2(-3.3, -15.6, 0.1, 4.6)]:
		rect_quad(hatch, hr, -0.038)
	# a painted arrow in the aisle leads drivers in off the street
	rect_quad(paint, Rect2(0.95, -9.6, 0.24, 1.5), -0.038)
	poly_fill(paint, PackedVector2Array([Vector2(0.55, -9.55), Vector2(1.07, -10.35), Vector2(1.59, -9.55)]), -0.038)
	commit([made, walk, tar, kerb, bay, paint, hatch, tactile], set_node)
	quay(made_runs, side_roads)
	snow_cover = settled_snow(far_gaps, near_gaps)
	for cx in [-1.0, 1.4]:  # wheel stops
		block(set_node, Vector3(1.5, 0.12, 0.2), Vector3(cx, 0.02, -15.3), Color("d8d2c4"))
	# a low planter along the back of the car park, below the till's sight line
	block(set_node, Vector3(5.2, 0.32, 0.5), Vector3(-0.6, 0.12, -16.55), Color("b9b3a6"))
	block(set_node, Vector3(5.0, 0.26, 0.38), Vector3(-0.6, 0.36, -16.55), Color("5f8f4a"))
	# a car nosed into the right-hand bay, front wheels at the stop: its art's footprint centre (midway across, a quarter
	# of its drawn width above its lowest point) held on the bay's centre line, slid along the view to clear the ground
	var kv: int = b.lot % 3
	var car := sprite("vehicles", Rect2(kv * 2 * VEHICLE_CELL.x, 0, VEHICLE_CELL.x, VEHICLE_CELL.y), VEHICLE_PX)
	set_node.add_child(car)
	facing(car, Vector3(0, 0, -1), kv * 2, VEHICLE_CELL)
	var u: Rect2i = tex["vehicles"].get_image().get_region(Rect2i(car.region_rect)).get_used_rect()
	var fx: float = u.get_center().x if not car.flip_h else VEHICLE_CELL.x - u.get_center().x
	var fy: float = u.end.y - u.size.x / 4.0
	car.offset = Vector2(VEHICLE_CELL.x / 2.0 - fx, fy - VEHICLE_CELL.y / 2.0)
	var long_: float = (u.end.x - u.position.x) * VEHICLE_PX * 0.5 / 0.7071  # roughly its length along the bay
	var foot := Vector2(1.46, -15.5 + long_ / 2.0)
	var tilt := deg_to_rad(PITCH)
	car.position = Vector3(foot.x, 0, foot.y) + Vector3(sin(PI / 4) * cos(tilt), sin(tilt), cos(PI / 4) * cos(tilt)) * ((u.size.x / 4.0 * VEHICLE_PX - 0.05) / sin(tilt))
	blob(set_node, foot, 1.3)
	lit_sprites.append(car)
	pole_sign(set_node)
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
	var poles := [SET.position.x, -42.0, -19.0, 12.0, 36.0, SET.end.x].filter(func(px): return absf(px) == SET.end.x or not in_gaps(px, near_gaps + under[1]))
	for k in poles.size():
		var px: float = poles[k]
		if k > 0 and k < poles.size() - 1:
			block(set_node, Vector3(0.24, 7.0, 0.24), Vector3(px, 3.5, 6.85), Color("a19d94"))
			block(set_node, Vector3(0.3, 1.1, 0.3), Vector3(px, 0.55, 6.85), Color("e3c34a"))
			block(set_node, Vector3(0.12, 0.12, 1.4), Vector3(px, 6.6, 6.85), Color("6f6c66"))
			if k % 2 == 0:
				block(set_node, Vector3(0.5, 0.75, 0.5), Vector3(px, 5.5, 7.2), Color("8a979c"))
			blob(set_node, Vector2(px, 6.85), 0.3)
		if k == 0 or under[1].any(func(g): return g.y > poles[k - 1] and g.x < px):  # no wire up through a deck
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
		set_row(seg[0], seg[1], -7.2, 13.0, mix, r, boxes, roofs, 0.7, roads + overhead)
	set_row(5.35, span.x, -7.2, 9.0, [[1, Sim.City.SHOPS, 1, 1, 6, 9, 9, 9]], r, boxes, roofs, 0.9, roads + overhead)  # one floor, so it hides neither your till nor the car park
	set_row(SET.position.x, SET.end.x, -20.5, 11.0, mix, r, boxes, roofs, 1.0, roads + overhead)
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
	# the part of your unit you haven't knocked through yet: a vacant shopfront, shutter down, its sign taken off
	if mine > -16.5:
		var vw := mine + 16.2  # stops short of your left wall, so the two faces don't fight
		var vx := (mine - 16.8) / 2
		block(set_node, Vector3(vw, 3.6, 9.0), Vector3(vx, 1.8, -11.7), Color("d9d3c4"))
		block(set_node, Vector3(vw + 0.2, 0.14, 0.35), Vector3(vx, 3.67, -7.3), Color("5b4632"))
		block(set_node, Vector3(0.35, 0.14, 9.3), Vector3(vx - vw / 2, 3.67, -11.7), Color("5b4632"))
		block(set_node, Vector3(vw + 0.2, 0.14, 0.35), Vector3(vx, 3.67, -16.1), Color("5b4632"))
		# its roof: a weathered membrane laid in strips with a drain, an old water tank on a frame, two tired AC units
		# and a vent stack, all kept low so nothing rises over your shop
		var xl := vx - vw / 2
		block(set_node, Vector3(vw - 0.4, 0.04, 8.4), Vector3(vx, 3.61, -11.75), Color(Sim.City.FLAT_ROOFS[2]))
		var sz := -8.6
		while sz > -15.6:
			block(set_node, Vector3(vw - 0.4, 0.05, 0.14), Vector3(vx, 3.62, sz), Color(Sim.City.FLAT_ROOFS[2]).darkened(0.18))
			sz -= 1.4
		block(set_node, Vector3(0.3, 0.05, 0.3), Vector3(xl + 0.45, 3.63, -7.95), Color("4d4a44"))
		var tank := Vector3(xl + 1.0, 3.6, -14.9)
		for lg in [Vector2(-0.45, -0.45), Vector2(0.45, -0.45), Vector2(-0.45, 0.45), Vector2(0.45, 0.45)]:
			block(set_node, Vector3(0.08, 0.5, 0.08), tank + Vector3(lg.x, 0.25, lg.y), Color("6e737d"))
		block(set_node, Vector3(1.05, 0.08, 1.05), tank + Vector3(0, 0.52, 0), Color("6e737d"))
		for part in [[0.5, 0.85, 0.98, Color("8fb3c2")], [0.53, 0.06, 1.0, Color("6f95a6")], [0.53, 0.06, 0.62, Color("6f95a6")], [0.18, 0.12, 1.47, Color("b9cdd5")]]:
			var cyl := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = part[0]
			cm.bottom_radius = part[0]
			cm.height = part[1]
			cm.radial_segments = 16
			cyl.mesh = cm
			cyl.material_override = mat(part[3])
			cyl.position = tank + Vector3(0, part[2], 0)
			set_node.add_child(cyl)
		for k in 2:
			var ac := Vector3(xl + 0.9 + k * 1.4, 3.6, -11.6)
			block(set_node, Vector3(1.1, 0.1, 0.8), ac + Vector3(0, 0.05, 0), Color("8e8d88"))
			block(set_node, Vector3(0.95, 0.55, 0.65), ac + Vector3(0, 0.37, 0), Color("d2cfc4"))
			block(set_node, Vector3(0.7, 0.36, 0.03), ac + Vector3(0, 0.37, 0.33), Color("7a8088"))
		block(set_node, Vector3(0.1, 0.1, 3.1), Vector3(xl + 2.3, 3.68, -13.3), Color("bdb8ad"))  # their pipe to the back
		var vent := Vector3(vx + vw / 2 - 0.7, 3.6, -9.2)
		block(set_node, Vector3(0.18, 0.7, 0.18), vent + Vector3(0, 0.35, 0), Color("9aa0a6"))
		block(set_node, Vector3(0.34, 0.08, 0.34), vent + Vector3(0, 0.74, 0), Color("6e737d"))
		block(set_node, Vector3(vw - 0.3, 0.55, 0.12), Vector3(vx, 3.1, -7.16), Color("cfc7b6"))
		block(set_node, Vector3(vw - 1.1, 0.4, 0.06), Vector3(vx, 3.1, -7.08), Color("e9e4d8"))  # where the old sign hung
		block(set_node, Vector3(vw - 0.5, 0.3, 0.32), Vector3(vx, 2.62, -7.05), Color("9aa0a6"))
		var slats := Image.create(1, 4, false, Image.FORMAT_RGB8)
		slats.fill(Color("c4c8cb"))
		slats.set_pixel(0, 3, Color("8f959b"))
		var shutter := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(vw - 0.8, 2.45)
		shutter.mesh = q
		shutter.material_override = tiled(ImageTexture.create_from_image(slats), Vector2(1, 14))
		shutter.position = Vector3(vx, 1.235, -7.17)
		set_node.add_child(shutter)
		block(set_node, Vector3(vw - 0.7, 0.1, 0.1), Vector3(vx, 0.05, -7.13), Color("7d8389"))
		block(set_node, Vector3(1.04, 0.76, 0.03), Vector3(vx + 0.4, 1.55, -7.15), Color("d8493a"))  # to-let notice
		block(set_node, Vector3(0.9, 0.5, 0.04), Vector3(vx + 0.4, 1.5, -7.14), Color("fbfaf5"))
		block(set_node, Vector3(0.6, 0.06, 0.05), Vector3(vx + 0.4, 1.56, -7.13), Color("3d3a36"))
		block(set_node, Vector3(0.42, 0.06, 0.05), Vector3(vx + 0.4, 1.42, -7.13), Color("3d3a36"))
	build_rival(set_node, b.rival, span)
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
		[8, Vector2(-2.75, -12.3)], [8, Vector2(-2.75, -13.5)], [4, Vector2(3.3, -15.2)]]
	if b.quirk == "busStop":
		props_at.append([11, Vector2(-24.5, -4.4)])
	for p in props_at:
		if in_gaps(p[1].x, far_gaps if p[1].y < 0.0 else near_gaps) or in_gaps(p[1].x, under[0] if p[1].y < 0.0 else under[1]):
			continue
		if p[0] == 6:
			street_lamp(Vector3(p[1].x, 0, p[1].y))
			continue
		var s := sprite("outdoor", Rect2(p[0] * OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * OUTDOOR_SCALE[p[0]] * 0.55)
		s.position = Vector3(p[1].x, OUTDOOR / 2.0 * OUTDOOR_PX * OUTDOOR_SCALE[p[0]] * 0.55 - 0.05, p[1].y)
		set_node.add_child(s)
		lit_sprites.append(s)
		blob(set_node, p[1], PROP_BLOB.get(p[0], OUTDOOR_SCALE[p[0]] * 1.5))
	spill(set_node, Sim.ORIGIN.x + (zl + 6.6) / 2, 8.6 - zl, Sim.ORIGIN.y + 4.7)  # your shop's open front
	for d in [[0, Vector2(-6.7, -6.75), 0.6], [0, Vector2(-4.1, -6.75), 0.6], [5, Vector2(-8.3, -6.2), 0.7]]:
		var s := sprite("decor", Rect2(d[0] * DECOR, 0, DECOR, DECOR), DECOR_PX * d[2])
		s.position = Vector3(d[1].x, DECOR / 2.0 * DECOR_PX * d[2], d[1].y)
		set_node.add_child(s)
		lit_sprites.append(s)
		blob(set_node, d[1], 0.45)
	# the crossing lights stand at its corners; where a side road opens there, at that road's corner instead
	light_poles = []
	for pole in [Vector3(Sim.CROSS_X - 1.8, 0, -4.0), Vector3(Sim.CROSS_X + 1.8, 0, 4.0)]:
		var gaps: Array = far_gaps if pole.z < 0.0 else near_gaps
		for g in gaps:
			if in_gaps(pole.x, [g]):
				pole.x = g.x - 0.7 if absf(g.x - 0.7 - Sim.CROSS_X) < absf(g.y + 0.7 - Sim.CROSS_X) else g.y + 0.7
		if in_gaps(pole.x, gaps) or in_gaps(pole.x, under[0] if pole.z < 0.0 else under[1]):
			continue
		light_poles.append(pole + Vector3(0, 2.5, 0))
		block(set_node, Vector3(0.12, 2.6, 0.12), pole + Vector3(0, 1.3, 0), Color("4a4d57"))
		block(set_node, Vector3(0.36, 0.7, 0.3), pole + Vector3(0, 2.5, 0), Color("2b2d42"))
	# outside facilities
	var outside := {"vending": Vector3(Sim.VENDING_X, 0, -7.2 + 0.375), "gacha": Vector3(Sim.GACHA_X - 0.1, 0, -7.2 + 0.25), "bench": Vector3(-13.6, 0, -6.6)}
	for f in st.facilities:
		if outside.has(f):
			var at: Vector3 = outside[f]
			lit_sprites.append(prop(set_node, f, at))
			blob(set_node, Vector2(at.x, at.z), 0.8)
			if f in ["vending", "gacha"]:
				pool(set_node, at + Vector3(0, 0, 0.6), Vector2(3.5, 3.5))
	if st.facilities.has("delivery"):  # the courier waits on the car park's apron, nose to the street
		var dv := sprite("vehicles", Rect2(6 * VEHICLE_CELL.x, 0, VEHICLE_CELL.x, VEHICLE_CELL.y), 0.016)
		dv.position = Vector3(-2.0, VEHICLE_CELL.y / 2.0 * 0.016 - 0.05, -8.2)
		set_node.add_child(dv)
		facing(dv, Vector3(0, 0, 1), 6, VEHICLE_CELL)
		lit_sprites.append(dv)
		blob(set_node, Vector2(-2.0, -8.2), 0.6)
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
## A street lamp at the kerb: a tapered pole on a base, an arm reaching out over the road and a head that lights after
## dark, with a halo round it, a cone of light under it and a pool on the ground below.
func street_lamp(at: Vector3) -> void:
	var out := 1.0 if at.z < 0.0 else -1.0
	block(set_node, Vector3(0.26, 0.4, 0.26), at + Vector3(0, 0.2, 0), Color("5c616b"))
	block(set_node, Vector3(0.14, 4.2, 0.14), at + Vector3(0, 2.1, 0), Color("6e737d"))
	block(set_node, Vector3(0.1, 0.1, 1.1), at + Vector3(0, 4.15, 0.5 * out), Color("6e737d"))
	var head := MeshInstance3D.new()
	head.mesh = shaded_box()
	head.scale = Vector3(0.34, 0.12, 0.56)
	head.position = at + Vector3(0, 4.06, 1.0 * out)
	head.material_override = lamp_mat
	set_node.add_child(head)
	block(set_node, Vector3(0.38, 0.06, 0.6), at + Vector3(0, 4.15, 1.0 * out), Color("4f535c"))
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	halo.mesh = q
	halo.material_override = halo_mat
	halo.position = at + Vector3(0, 3.8, 1.0 * out)  # below the head, so its housing doesn't hide the bright core
	set_node.add_child(halo)
	var beam := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(3.0, 4.0)
	beam.mesh = bq
	beam.material_override = beam_mat
	beam.position = at + Vector3(0, 2.0, 1.0 * out)
	set_node.add_child(beam)
	blob(set_node, Vector2(at.x, at.z), 0.25)
	pool(set_node, at + Vector3(0, 0, 0.9 * out), Vector2(7.0, 7.0))


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


## The decks overhead that cross the set, as [a, b, half width and a margin] in the street frame: the viaduct, the
## expressway and its ramps where they are up off the road. Its own buildings and street furniture keep out from
## under them, as from the roads.
func decks_near() -> Array:
	var o := Vector2(site.position.x, site.position.z)
	var area := Rect2(o + SET.position, SET.size)
	var lines := [[C.rail_loop, Sim.City.RAIL_W]]
	for sh in C.shuto:
		var pts := Sim.City._flat(sh.pts)
		if sh.closed:
			pts.append(pts[0])
		lines.append([pts, Sim.City.EXPRESS_W])
	for rp in C.ramps:
		var pts := PackedVector2Array()
		for p in rp.pts:
			if p.y > 1.5:
				pts.append(Vector2(p.x, p.z))
		lines.append([pts, Sim.City.RAMP_W])
	var out := []
	for ln in lines:
		var half: float = ln[1] / 2 + 1.0
		for i in range(1, ln[0].size()):
			if seg_hits(area.grow(half), ln[0][i - 1], ln[0][i]):
				out.append([ln[0][i - 1] - o, ln[0][i] - o, half])
	return out


## Whether any water reaches into the set: a 4 m sample, narrower than any canal, so inland sets skip the fine scan.
func near_water() -> bool:
	var o := Vector2(site.position.x, site.position.z)
	for x in range(int(SET.position.x), int(SET.end.x) + 1, 4):
		for z in range(int(SET.position.y), int(SET.end.y) + 1, 4):
			if Sim.City.is_water(C, o + Vector2(x, z)):
				return true
	return false


## Where the made ground meets open water: a concrete quay wall with its coping, standing in its own shade on the
## water, left open where a road runs on over a bridge.
func quay(runs: Array, roads: Array) -> void:
	if runs.is_empty():
		return
	var o := Vector2(site.position.x, site.position.z)
	var open_water := func(p: Vector2) -> bool:
		return Sim.City.is_water(C, o + p) and not runs.any(func(r): return r.grow(0.01).has_point(p)) \
			and not roads.any(func(rd): return rd.has_point(p) if rd is Rect2 else Geometry2D.get_closest_point_to_segment(p, rd[0], rd[1]).distance_to(p) < rd[2])
	var edges := []  # [from, to, outward normal], merged along each side
	for r in runs:
		for sd in [[r.position, Vector2(r.end.x, r.position.y), Vector2.UP], [Vector2(r.position.x, r.end.y), r.end, Vector2.DOWN], [r.position, Vector2(r.position.x, r.end.y), Vector2.LEFT], [Vector2(r.end.x, r.position.y), r.end, Vector2.RIGHT]]:
			var n: Vector2 = sd[2]
			if n.x != 0.0 and absf(sd[0].x) == SET.end.x:  # the set's cut ends: the street runs on
				continue
			var len_: float = sd[0].distance_to(sd[1])
			var d: Vector2 = (sd[1] - sd[0]) / len_
			for i in ceili(len_ - 0.01):  # 1 m cells from the run's start, on water_runs' own grid
				var a: Vector2 = sd[0] + d * i
				var b: Vector2 = sd[0] + d * minf(i + 1.0, len_)
				if not open_water.call((a + b) / 2 + n * 0.5):  # the next cell's own sample, as water_runs takes it
					continue
				if not edges.is_empty() and edges[-1][2] == n and edges[-1][1].is_equal_approx(a):
					edges[-1][1] = b
				else:
					edges.append([a, b, n])
	var m := mat(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var wall_ := surface(m)
	var shade := surface(mat(Color("2d5b88")))
	var box := func(p0: Vector3, p1: Vector3, col: Color) -> void:
		var c := (p0 + p1) / 2
		var h := (p1 - p0).abs() / 2
		for fc in [[Vector3.UP, 1.0], [Vector3.BACK, 0.9], [Vector3.LEFT, 0.9], [Vector3.RIGHT, 0.75], [Vector3.FORWARD, 0.75]]:
			var fn: Vector3 = fc[0]
			var u := Vector3.UP if absf(fn.y) < 0.5 else Vector3.RIGHT
			var v := fn.cross(u)
			var ctr := c + fn * absf(fn.dot(h))
			var hu := u * absf(u.dot(h))
			var hv := v * absf(v.dot(h))
			wall_.set_color(Color(col.r * fc[1], col.g * fc[1], col.b * fc[1]))
			add_quad(wall_, [ctr - hu - hv, ctr + hu - hv, ctr + hu + hv, ctr - hu + hv], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	const T := 0.3  # the wall's thickness, inside the made ground's edge
	const TOP := 0.34
	for e in edges:
		var n: Vector2 = e[2]
		var lo := Vector2(minf(e[0].x, e[1].x), minf(e[0].y, e[1].y))
		var hi := Vector2(maxf(e[0].x, e[1].x), maxf(e[0].y, e[1].y))
		rect_quad(shade, Rect2(lo, hi - lo).merge(Rect2(lo + n * 0.55, hi - lo)), -0.137)
		var r := Rect2(lo, hi - lo).merge(Rect2(lo - n * T, hi - lo))
		box.call(Vector3(r.position.x, -0.14, r.position.y), Vector3(r.end.x, TOP, r.end.y), Color("c4bfb3"))
		var st_ := Rect2(lo + n * 0.02, hi - lo).merge(Rect2(lo - n * 0.02, hi - lo))  # a wet tide line along its foot
		box.call(Vector3(st_.position.x, -0.14, st_.position.y), Vector3(st_.end.x, 0.02, st_.end.y), Color("7d8079"))
		# a railing along the coping: posts every 2 m, a top rail and a mid rail
		var mid := lo - n * T / 2
		var posts := maxi(1, roundi(lo.distance_to(hi) / 2.0))
		for i in posts + 1:
			var q := mid + (hi - lo) * i / posts
			box.call(Vector3(q.x - 0.04, TOP, q.y - 0.04), Vector3(q.x + 0.04, TOP + 0.75, q.y + 0.04), Color("5d6a6c"))
		for ry in [TOP + 0.7, TOP + 0.35]:
			var p0 := Vector3(mid.x, ry, mid.y) - Vector3(n.x, 0, n.y) * 0.03
			var p1 := Vector3(mid.x + (hi - lo).x, ry + 0.06, mid.y + (hi - lo).y) + Vector3(n.x, 0, n.y) * 0.03
			box.call(Vector3(minf(p0.x, p1.x), p0.y, minf(p0.z, p1.z)), Vector3(maxf(p0.x, p1.x), p1.y, maxf(p0.z, p1.z)), Color("6b7a7c"))
	commit([shade, wall_], set_node)


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
func build_rival(parent: Node3D, rv: Dictionary, span: Vector2) -> void:
	var w := span.y - span.x
	var cx := (span.x + span.y) / 2
	var c := Color("8a8780") if rv.defeated else Color(Sim.RIVALS[rv.id].color)  # a beaten chain's sign goes grey
	block(parent, Vector3(w, 4.2, 9.0), Vector3(cx, 2.1, -11.7), Color("f1eee6"))
	var box := block(parent, Vector3(w + 0.1, 0.8, 0.12), Vector3(cx, 3.65, -7.16), c)
	# fascia in the chain's stripes, a lightbox that glows after dark (a beaten chain's stays dark); a grey roof inside a parapet, with a stair hatch, a walkway, skylights over the
	# shop floor (lit from below at night) and the air-conditioning units on their plinths, piped into one trunk
	var band := Image.create(1, 10, false, Image.FORMAT_RGB8)
	band.fill(c)
	band.set_pixel(0, 6, Color.WHITE)
	for y in [7, 8, 9]:
		band.set_pixel(0, y, c.darkened(0.25))
	var face := art_panel(parent, band, Vector2(w + 0.1, 0.8), Vector3(cx, 3.65, -7.095), Color.WHITE, 1.0, false)
	if not rv.defeated:
		light_up(box, 0.8)
		light_up(face, 1.0)
		var gm := sign_glow_mat.duplicate()
		gm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		gm.albedo_texture = fascia_glow_tex
		gm.albedo_color = Color(0, 0, 0, 0)
		fascia_glows.append([weakref(gm), c.lightened(0.45)])
		var glow := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(w + 3.0, 2.8)
		glow.mesh = q
		glow.material_override = gm
		glow.position = Vector3(cx, 3.55, -6.98)
		parent.add_child(glow)
	plane(parent, Vector2(w - 0.4, 8.6), Vector3(cx, 4.245, -11.7), rival_roof(span))
	for e in [[Vector3(w, 0.34, 0.2), Vector3(cx, 4.37, -7.3)], [Vector3(w, 0.34, 0.2), Vector3(cx, 4.37, -16.1)],
			[Vector3(0.2, 0.34, 9.0), Vector3(span.x + 0.1, 4.37, -11.7)], [Vector3(0.2, 0.34, 9.0), Vector3(span.y - 0.1, 4.37, -11.7)]]:
		block(parent, e[0], e[1], Color("e6e2d8"))
	var hatch := Vector3(span.x + 1.4, 4.2, -14.9)
	block(parent, Vector3(1.8, 1.3, 1.6), hatch + Vector3(0, 0.65, 0), Color("dedad0"))
	block(parent, Vector3(1.95, 0.1, 1.75), hatch + Vector3(0, 1.35, 0), Color("aca89f"))
	block(parent, Vector3(0.7, 1.0, 0.04), hatch + Vector3(0.3, 0.5, 0.81), Color("7d8590"))
	block(parent, Vector3(w - 2.2, 0.03, 0.8), Vector3(cx + 0.5, 4.25, -13.4), Color("c9c6bd"))
	for k in 2:
		var sx := span.x + 3.2 + k * 2.6
		block(parent, Vector3(1.9, 0.2, 1.3), Vector3(sx, 4.3, -10.0), Color("d6d3ca"))
		block(parent, Vector3(1.6, 0.04, 1.0), Vector3(sx, 4.41, -10.0), Color("dceaf0"), not rv.defeated)
	for k in 3:
		var ac := Vector3(span.x + 4.2 + k * 1.6, 4.25, -14.4)
		block(parent, Vector3(1.25, 0.1, 1.05), ac + Vector3(0, 0.05, 0), Color("8e8d88"))
		block(parent, Vector3(1.05, 0.6, 0.85), ac + Vector3(0, 0.4, 0), Color("dcddd8"))
		block(parent, Vector3(0.85, 0.36, 0.03), ac + Vector3(0, 0.38, 0.43), Color("7a8088"))
		block(parent, Vector3(0.1, 0.1, 0.75), ac + Vector3(0.3, 0.1, -0.8), Color("c9c6bd"))
		for ring in [[0.32, Color("41464c")], [0.09, Color("a7adb3")]]:
			var fan := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = ring[0]
			cm.bottom_radius = ring[0]
			cm.height = 0.02
			cm.radial_segments = 16
			fan.mesh = cm
			fan.material_override = mat(ring[1])
			fan.position = ac + Vector3(0, 0.71 + (0.01 if ring[0] < 0.2 else 0.0), 0)
			parent.add_child(fan)
	block(parent, Vector3(span.y - span.x - 5.0, 0.12, 0.12), Vector3((span.x + 4.5 + span.y - 0.5) / 2, 4.35, -15.25), Color("c9c6bd"))
	# the shop floor behind the glass (the chain's shelves, lit at night), mullions, the sliding door; a beaten chain's
	# shop is shut behind roll-down shutters and stays dark
	if rv.defeated:
		var slats := Image.create(1, 16, false, Image.FORMAT_RGB8)
		for y in 16:
			slats.set_pixel(0, y, Color("b8b5ad") if y % 2 == 0 else Color("a29f97"))
		art_panel(parent, slats, Vector2(w - 0.8, 2.6), Vector3(cx, 1.3, -7.075), Color.WHITE, 1.0, false)
		block(parent, Vector3(w - 0.6, 0.3, 0.3), Vector3(cx, 2.72, -7.0), Color("8f8c85"))  # the shutter boxes
	else:
		var shelves: Image = load("res://art/bg_super.png").get_image().get_region(Rect2i(80, 126, 560, 119))
		art_panel(parent, shelves, Vector2(w - 0.8, 2.6), Vector3(cx, 1.3, -7.075), Color(0.86, 0.94, 1.0))
	block(parent, Vector3(w - 0.8, 0.12, 0.12), Vector3(cx, 2.6, -7.06), Color("5e6670"))
	block(parent, Vector3(w - 0.8, 0.16, 0.14), Vector3(cx, 0.08, -7.06), Color("5e6670"))
	var x0 := span.x + 0.4
	while x0 < span.y - 0.3:
		if absf(x0 - rv.x) > 0.8:
			block(parent, Vector3(0.08, 2.6, 0.1), Vector3(x0, 1.3, -7.05), Color("5e6670"))
		x0 += 2.0
	if not rv.defeated:
		block(parent, Vector3(1.4, 2.6, 0.1), Vector3(rv.x, 1.3, -7.05), Color(0.86, 0.93, 0.98, 0.55), true)
		for dx in [-0.72, 0.0, 0.72]:
			block(parent, Vector3(0.07, 2.6, 0.12), Vector3(rv.x + dx, 1.3, -7.03), Color("8b96a1"))
	var awning := block(parent, Vector3(w, 0.12, 0.9), Vector3(cx, 2.85, -6.7), c.lightened(0.15))
	if not rv.defeated:
		light_up(awning, 0.5)
		spill(parent, cx, w + 1.6, -7.05)


## The rival's roof as the city's flat roofs are drawn: membrane in strips across its depth, each a shade off, the
## parapets' shadow along its sunny sides, a dark seam round the hatch, skylights, AC units and walkway and each one's
## shadow away from the sun, and a drain in the front corner with a damp stain round it. 10 px a metre, street frame.
func rival_roof(span: Vector2) -> StandardMaterial3D:
	var x0 := span.x + 0.2
	var iw := roundi((span.y - span.x - 0.4) * 10.0)
	if iw in roof_texs:
		return roof_mat(roof_texs[iw])
	var ih := 86
	var r := RandomNumberGenerator.new()
	r.seed = 41
	var lanes := []
	for k in 8:
		lanes.append(r.randf_range(0.91, 1.04))
	var casts := [[Rect2(span.x + 0.5, -15.7, 1.8, 1.6), Vector2(0.49, -0.84)]]  # footprint, shadow offset (street frame)
	for k in 2:
		casts.append([Rect2(span.x + 2.25 + k * 2.6, -10.65, 1.9, 1.3), Vector2(0.12, -0.2)])
	for k in 3:
		casts.append([Rect2(span.x + 3.575 + k * 1.6, -14.925, 1.25, 1.05), Vector2(0.25, -0.42)])
	casts.append([Rect2(span.x + 1.6, -13.8, span.y - span.x - 2.2, 0.8), Vector2.ZERO])  # the walkway
	var drain := Vector2(span.y - 0.8, -7.95)
	var base := Color(Sim.City.FLAT_ROOFS[4])  # a teal coating
	var img := Image.create(iw, ih, false, Image.FORMAT_RGB8)
	for j in ih:
		var z := -16.0 + (j + 0.5) / 10.0
		var u := (j + 0.5) / 12.0
		var lane: float = lanes[int(u) % lanes.size()] * (0.84 if j % 12 == 0 else 1.0)
		for i in iw:
			var x := x0 + (i + 0.5) / 10.0
			var f := lane
			if i < 3 or j >= ih - 4:
				f *= 0.74
			elif i >= iw - 2 or j < 2:
				f *= 0.86
			for c in casts:
				var at: Rect2 = c[0]
				var out := Vector2(maxf(maxf(at.position.x - x, x - at.end.x), 0.0), maxf(maxf(at.position.y - z, z - at.end.y), 0.0))
				if at.grow(-0.05).has_point(Vector2(x, z) - c[1]):
					f *= 0.7
					break
				elif out.length() < 0.25:  # a dark seam where each fitting meets the roof
					f *= lerpf(0.78, 1.0, out.length() / 0.25)
					break
			var d := Vector2(x, z).distance_to(drain)
			if d < 0.15:
				f = 0.45
			elif d < 1.1:
				f *= lerpf(0.86, 1.0, d / 1.1)
			img.set_pixel(i, j, Color(base.r * f, base.g * f, base.b * f))
	img.generate_mipmaps()
	roof_texs[iw] = ImageTexture.create_from_image(img)
	return roof_mat(roof_texs[iw])


func roof_mat(t: ImageTexture) -> StandardMaterial3D:
	var m := mat(Color.WHITE, t)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m


## Your pole sign in the back corner of the car park, clear of the shop, lit like the shop after dark (street frame),
## with a glow round its lightbox and a pair of floodlights under it washing the bays in shop light.
func pole_sign(parent: Node3D) -> void:
	var ps := Vector3(3.0, 0, -16.5)
	block(parent, Vector3(0.22, 6.2, 0.22), ps + Vector3(0, 3.1, 0), Color("9aa0a6"))
	block(parent, Vector3(1.7, 1.5, 0.34), ps + Vector3(0, 6.4, 0), Color("fbfaf5"), true)
	block(parent, Vector3(1.72, 0.2, 0.36), ps + Vector3(0, 6.15, 0), LAYOUT.stripe[0], true)
	block(parent, Vector3(1.72, 0.2, 0.36), ps + Vector3(0, 5.92, 0), LAYOUT.stripe[1], true)
	var face := PlaneMesh.new()
	face.orientation = PlaneMesh.FACE_Z
	face.size = Vector2(1.5, 0.75)
	for side in [1.0, -1.0]:  # the logo on both faces of the lightbox
		var lf := MeshInstance3D.new()
		lf.mesh = face
		lf.material_override = mat(Color.WHITE, sign_face(), true)
		lf.position = ps + Vector3(0, 6.7, 0.175 * side)
		lf.rotation.y = 0.0 if side > 0 else PI
		parent.add_child(lf)
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(4.2, 3.2)
	glow.mesh = q
	glow.material_override = sign_glow_mat
	glow.position = ps + Vector3(0, 6.45, 0.4)
	parent.add_child(glow)
	for arm in [Vector3(-0.55, 0, 0), Vector3(0, 0, 0.55)]:  # floodlights aimed into the bays
		block(parent, Vector3(0.08, 0.08, 0.08) + arm.abs(), ps + Vector3(0, 4.9, 0) + arm / 2, Color("9aa0a6"))
		var head := MeshInstance3D.new()
		head.mesh = shaded_box()
		head.scale = Vector3(0.3, 0.14, 0.3)
		head.position = ps + Vector3(0, 4.82, 0) + arm * 1.2
		head.material_override = lamp_mat
		parent.add_child(head)
	var lot := ps + Vector3(-2.8, 0, 4.2)
	plane(parent, Vector2(10.5, 10.5), Vector3(lot.x, -0.032, lot.z), flood_mat)
	if parent == set_node:
		var w := parent.global_position + lot
		pools.append(Vector3(w.x, w.z, 4.4))
	blob(parent, Vector2(ps.x, ps.z), 0.3)


## Your shop closed up, as the city map shows it on a lot (street frame, 1:1, where the street set's cutaway stands):
## the box, the glass front, the fascia in your stripes round the front and the street-side wall, a parapet roof.
func build_shop(parent: Node3D, zl: float) -> void:
	var o := Sim.ORIGIN
	var w := 6.6 - zl
	var cx := o.x + (zl + 6.6) / 2
	var front := o.y + 4.65
	block(parent, Vector3(w, 3.1, 9.3), Vector3(cx, 1.55, o.y), Color("f4f1e8"))
	var crop: Image = tex[LAYOUT.bg].get_image().get_region(LAYOUT.wall)  # the shop's back wall, seen through the glass
	art_panel(parent, crop, Vector2(w - 1.0, 2.05), Vector3(cx, 1.12, front + 0.04), Color(0.86, 0.94, 1.0), (w - 1.0) / (2.05 * crop.get_width() / crop.get_height()))
	var x := cx - (w - 1.0) / 2
	while x <= cx + (w - 1.0) / 2 + 0.01:
		block(parent, Vector3(0.08, 2.05, 0.1), Vector3(x, 1.12, front + 0.05), Color("5e6670"))
		x += (w - 1.0) / maxf(1.0, roundf((w - 1.0) / 2.0))
	block(parent, Vector3(w - 1.0, 0.1, 0.1), Vector3(cx, 0.05, front + 0.05), Color("5e6670"))
	for k in 2:  # the stripes run round the corner like the cutaway's side wall
		var y := 2.62 - k * 0.2
		block(parent, Vector3(w + 0.04, 0.18, 0.06), Vector3(cx, y, front + 0.03), LAYOUT.stripe[k])
		block(parent, Vector3(0.06, 0.18, 9.34), Vector3(o.x + 6.63, y, o.y), LAYOUT.stripe[k])
	block(parent, Vector3(w - 0.4, 0.05, 8.9), Vector3(cx, 3.12, o.y), Color(Sim.City.FLAT_ROOFS[0]))  # a green coating
	for e in [[Vector3(w, 0.3, 0.2), Vector3(cx, 3.25, front - 0.1)], [Vector3(w, 0.3, 0.2), Vector3(cx, 3.25, o.y - 4.55)],
			[Vector3(0.2, 0.3, 9.3), Vector3(o.x + zl + 0.1, 3.25, o.y)], [Vector3(0.2, 0.3, 9.3), Vector3(o.x + 6.5, 3.25, o.y)]]:
		block(parent, e[0], e[1], Color("e6e2d8"))
	block(parent, Vector3(1.05, 0.6, 0.85), Vector3(cx - w / 4, 3.45, o.y - 2.4), Color("dcddd8"))
	spill(parent, cx, w + 1.6, front)
	pole_sign(parent)


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
	block(room, Vector3(0.02, 0.15, 9.0), Vector3(zl + 0.01, wall_h * 0.927, 0.0), L.stripe[0])  # level with the back wall art's stripes
	block(room, Vector3(0.02, 0.15, 9.0), Vector3(zl + 0.01, wall_h * 0.866, 0.0), L.stripe[1])
	left_wall(zl, st.products.keys())
	block(room, Vector3(w + 0.6, 0.14, 0.35), Vector3(cx, wall_h + 0.07, -4.62), Color("5b4632"))
	block(room, Vector3(0.35, 0.14, 9.6), Vector3(zl - 0.125, wall_h + 0.07, 0.0), Color("5b4632"))
	# low stubs where the cut-away right wall and glass front stand, the door gap left open
	block(room, Vector3(0.2, 0.35, 9.25), Vector3(6.6, 0.175, 0.0), Color("efe6d2"))
	glass_front(zl, Sim.DOOR_IN.x - 0.8)
	glass_front(Sim.DOOR_IN.x + 0.8, 6.6)
	# the sliding door's floor track between its jambs, and the entrance mat inside it
	block(room, Vector3(1.6, 0.02, 0.14), Vector3(Sim.DOOR_IN.x, 0.01, 4.6), Color("8b96a1"))
	block(room, Vector3(1.5, 0.02, 0.95), Vector3(Sim.DOOR_IN.x, 0.01, 3.95), Color("3d434b"))
	block(room, Vector3(1.26, 0.025, 0.71), Vector3(Sim.DOOR_IN.x, 0.012, 3.95), Color("525a64"))
	block(room, Vector3(1.26, 0.03, 0.08), Vector3(Sim.DOOR_IN.x, 0.012, 3.75), L.stripe[0])
	block(room, Vector3(1.26, 0.03, 0.08), Vector3(Sim.DOOR_IN.x, 0.012, 3.87), L.stripe[1])
	# counter and registers
	block(room, Vector3(0.85, COUNTER_H, 5.3), Vector3(4.5, COUNTER_H / 2, -0.75), Color("f3ecdc"))
	block(room, Vector3(0.87, 0.08, 5.32), Vector3(4.5, 0.47, -0.75), L.stripe[0])
	block(room, Vector3(0.87, 0.08, 5.32), Vector3(4.5, 0.34, -0.75), L.stripe[1])
	for reg in st.registers:
		if reg.active:
			var p: Vector2 = Sim.REGISTERS[reg.id].pos
			prop(room, "till", Vector3(p.x, COUNTER_H, p.y))
	# a fixture per product line, its stock stood on its own boards
	for pid in st.products:
		var p: Vector2 = Sim.SLOTS[Sim.PRODUCTS[pid].slot].pos
		var kind := slot_kind(Sim.PRODUCTS[pid].slot)
		if FIXTURES.has(kind):
			fixture_shell(kind, p)
			goods(pid, kind, p)
		elif kind == "rack":
			# the magazine racks' art is the fixture with its stock, three of them stood on the floor
			var ic: Array = Sim.PRODUCTS[pid].icon
			var region := Rect2(ic[1] * DECOR, 0, DECOR, DECOR)
			var u: Rect2i = tex[ic[0]].get_image().get_region(Rect2i(region)).get_used_rect()
			var px := RACK_H / u.size.y
			var icons := []
			for k in 3:
				var s := sprite(ic[0], region, px)
				s.position = Vector3(p.x - 0.62 + 0.62 * k, (u.end.y - DECOR / 2.0) * px, p.y)
				room.add_child(s)
				icons.append(s)
			slot_icons[pid] = icons
		else:
			# a counter line is its own station (coffee machine, hot-snack case, oden pot), greyed when sold out
			slot_icons[pid] = [prop(room, {"coffee": "coffee", "chicken": "karaage", "oden": "oden"}[pid], Vector3(p.x, COUNTER_H, p.y))]
	# inside facilities
	if st.facilities.has("atm"):  # in the front corner facing the door, its side to the right stub
		prop(room, "atm", Vector3(6.1, 0, 3.95))
	if st.facilities.has("neon"):  # the shopfront is the cut-away side, so the sign tops the back wall: a lit tube on a dark board
		var sw := minf(6.0, w - 1.0)
		block(room, Vector3(sw, 0.62, 0.12), Vector3(cx, wall_h + 0.45, -4.62), Color("2b2d42"))
		block(room, Vector3(sw - 0.24, 0.34, 0.04), Vector3(cx, wall_h + 0.45, -4.54), Color("ff4fa0"))
	var inside := {"maneki": ["perks", 9, Vector3(4.5, COUNTER_H, 1.75)], "camera": ["perks", 6, Vector3(5.6, 2.5, -4.35)]}
	for f in st.facilities:
		if inside.has(f):
			var e: Array = inside[f]
			var cell := DECOR if e[0] == "decor" else 80
			var px := DECOR_PX if e[0] == "decor" else 0.006
			var s := sprite(e[0], Rect2(e[1] * cell, 0, cell, cell), px)
			s.position = e[2] + Vector3(0, cell / 2.0 * px, 0)
			room.add_child(s)


## The glass front cut away at knee height from x0 to x1 (shop-local, z = 4.6): an aluminium sill, the glass's
## section with its cut edge catching the light, and mullion stubs every bay and at each end.
func glass_front(x0: float, x1: float) -> void:
	var w := x1 - x0
	if w <= 0.1:
		return
	var cx := (x0 + x1) / 2
	block(room, Vector3(w, 0.12, 0.26), Vector3(cx, 0.06, 4.6), Color("5e6670"))
	block(room, Vector3(w, 0.3, 0.06), Vector3(cx, 0.27, 4.6), Color(0.78, 0.89, 0.96, 0.6))
	block(room, Vector3(w, 0.025, 0.07), Vector3(cx, 0.43, 4.6), Color("f2f9fc"))
	var bays := maxi(1, roundi(w / 1.6))
	for k in bays + 1:
		block(room, Vector3(0.09, 0.48, 0.14), Vector3(x0 + 0.045 + (w - 0.09) * k / bays, 0.24, 4.6), Color("6d7680"))


## The left wall's face (at x = zl, facing +x): a skirting board, the staff door in the aisle by the fridges under a
## green exit sign, and promo posters of the shop's own lines over the fixtures, clear of the fridge's height.
func left_wall(zl: float, products: Array) -> void:
	var f := zl + 0.01
	block(room, Vector3(0.03, 0.12, 9.0), Vector3(f + 0.005, 0.06, 0.0), Color("a08a68"))
	var dz := -2.25
	block(room, Vector3(0.04, 2.15, 1.0), Vector3(f + 0.01, 1.075, dz), Color("6b7078"))
	block(room, Vector3(0.03, 2.05, 0.84), Vector3(f + 0.03, 1.025, dz), Color("c9d0d6"))
	block(room, Vector3(0.02, 0.42, 0.3), Vector3(f + 0.05, 1.55, dz + 0.12), Color("9fc3d6"))  # the door's wired-glass light
	block(room, Vector3(0.02, 0.24, 0.84), Vector3(f + 0.05, 0.13, dz), Color("9aa2aa"))  # kick plate
	block(room, Vector3(0.04, 0.05, 0.16), Vector3(f + 0.06, 1.02, dz - 0.28), Color("5e6670"))
	block(room, Vector3(0.04, 0.2, 0.46), Vector3(f + 0.02, 2.34, dz), Color("1f9d55"))
	block(room, Vector3(0.02, 0.1, 0.12), Vector3(f + 0.05, 2.34, dz - 0.1), Color("f4fbf6"))
	block(room, Vector3(0.02, 0.04, 0.16), Vector3(f + 0.05, 2.34, dz + 0.1), Color("f4fbf6"))
	var spots := [-0.55, 1.85, 3.5]
	for k in mini(products.size(), spots.size()):
		var z: float = spots[k]
		var ic: Array = Sim.PRODUCTS[products[k]].icon
		block(room, Vector3(0.02, 0.88, 0.86), Vector3(f + 0.01, 1.99, z), LAYOUT.stripe[k % 2])
		block(room, Vector3(0.02, 0.62, 0.74), Vector3(f + 0.03, 2.09, z), Color("fffaf0"))
		block(room, Vector3(0.02, 0.09, 0.42), Vector3(f + 0.03, 1.67, z), Color("fff3c4"))  # the price flash
		var cell: int = {"products": ITEM, "perks": 80, "decor": DECOR}[ic[0]]
		var s := sprite(ic[0], Rect2(ic[1] * cell, 0, cell, cell), 0.58 / cell, false)
		s.rotation.y = PI / 2
		s.position = Vector3(f + 0.05, 2.09, z)
		room.add_child(s)


## A fixture's shell round the boards its FIXTURES rows stand on: a gondola's or low shelf's end panels, back and cap
## over open tiers; a fridge's lit cabinet behind glass doors; a chest freezer's well under glass lids.
func fixture_shell(kind: String, p: Vector2) -> void:
	var f: Dictionary = FIXTURES[kind]
	var h: float = f.h
	var w := FIXTURE_W
	var deck: float = f.rows[0][0]
	var trim := Color("c3ccd2")
	match kind:
		"shelf", "low":
			var body := Color("e9e4d6")
			var board := Color("cfc4ac")
			block(room, Vector3(w, h, 0.42), Vector3(p.x, h / 2, p.y - 0.19), body)  # the back half: the far side's tiers
			block(room, Vector3(w, deck, 0.4), Vector3(p.x, deck / 2, p.y + 0.2), board)
			for dx in [-1, 1]:
				block(room, Vector3(0.04, h, 0.8), Vector3(p.x + dx * (w / 2 - 0.02), h / 2, p.y), body)
			for r in f.rows:
				if r[0] > deck:
					block(room, Vector3(w - 0.08, 0.03, 0.38), Vector3(p.x, r[0] - 0.015, p.y + 0.21), board)
				block(room, Vector3(w - 0.08, 0.045, 0.015), Vector3(p.x, r[0] - 0.0225, p.y + 0.405), Color("fbf7ee"))  # price rail
			block(room, Vector3(w + 0.1, 0.1, 0.9), Vector3(p.x, h + 0.05, p.y), Color("3b3f52"))
		"fridge":
			var body := Color("dfe9ef")
			var top: float = f.rows[-1][1]  # the header's underside
			block(room, Vector3(w, h, 0.06), Vector3(p.x, h / 2, p.y - 0.37), Color("eef6fa"))  # the lit back
			for dx in [-1, 1]:
				block(room, Vector3(0.06, h, 0.8), Vector3(p.x + dx * (w / 2 - 0.03), h / 2, p.y), body)
			block(room, Vector3(w, deck, 0.8), Vector3(p.x, deck / 2, p.y), body)
			block(room, Vector3(w, h - top, 0.8), Vector3(p.x, (h + top) / 2, p.y), body)
			block(room, Vector3(w, 0.18, 0.02), Vector3(p.x, h - 0.12, p.y + 0.41), LAYOUT.stripe[1])
			for r in f.rows.slice(1):  # wire shelves, a price strip on each
				block(room, Vector3(w - 0.12, 0.02, 0.62), Vector3(p.x, r[0] - 0.01, p.y - 0.03), trim)
				block(room, Vector3(w - 0.12, 0.03, 0.01), Vector3(p.x, r[0] - 0.015, p.y + 0.285), Color("fbf7ee"))
			var gh: float = top - deck
			for dx in [-0.365, 0.365]:  # the door mullions
				block(room, Vector3(0.05, gh, 0.05), Vector3(p.x + dx, deck + gh / 2, p.y + 0.375), trim)
			block(room, Vector3(w - 0.12, gh, 0.01), Vector3(p.x, deck + gh / 2, p.y + 0.39), Color(0.78, 0.9, 0.96, 0.12))
		"freezer":
			var body := Color("eef3f6")
			block(room, Vector3(w, deck, 0.8), Vector3(p.x, deck / 2, p.y), body)
			for dz in [-1, 1]:
				block(room, Vector3(w, h - deck, 0.06), Vector3(p.x, (h + deck) / 2, p.y + dz * 0.37), body)
			for dx in [-1, 1]:
				block(room, Vector3(0.06, h - deck, 0.8), Vector3(p.x + dx * (w / 2 - 0.03), (h + deck) / 2, p.y), body)
			block(room, Vector3(w + 0.02, 0.08, 0.82), Vector3(p.x, 0.04, p.y), trim)
			block(room, Vector3(0.03, 0.025, 0.68), Vector3(p.x, h - 0.0125, p.y), trim)  # where the sliding lids meet
			block(room, Vector3(w - 0.12, 0.02, 0.68), Vector3(p.x, h - 0.01, p.y), Color(0.78, 0.9, 0.96, 0.18))


## A product line's stock on its fixture's boards: packs in its own art, upright to the locked store camera (laid back
## in a freezer's well), as many facings as fit each row, as many showing as are in stock.
func goods(pid: String, kind: String, p: Vector2) -> void:
	var f: Dictionary = FIXTURES[kind]
	var ic: Array = Sim.PRODUCTS[pid].icon
	var sheet: Texture2D = tex[ic[0]]
	var cell: int = {"products": ITEM, "perks": 80, "decor": DECOR}[ic[0]]
	var region := Rect2i(ic[1] * cell, 0, cell, cell)
	var u: Rect2i = sheet.get_image().get_region(region).get_used_rect()
	var px: float = minf(f.pack.x / u.size.x, f.pack.y / u.size.y)
	var q := QuadMesh.new()
	q.size = Vector2(cell, cell) * px
	q.center_offset = Vector3((cell / 2.0 - u.position.x - u.size.x / 2.0) * px, (u.end.y - cell / 2.0) * px, 0)  # the drawn pack's foot at the origin
	var m := mat(Color.WHITE, sheet, true)
	m.uv1_scale = Vector3(float(cell) / sheet.get_width(), float(cell) / sheet.get_height(), 1)
	m.uv1_offset = Vector3(float(region.position.x) / sheet.get_width(), 0, 0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var at := facings(kind, p, Vector2(u.size) * px)
	var mm := multimesh(q, at.size())
	for k in at.size():
		mm.set_instance_transform(k, at[k])
	mm_node(mm, m, room)
	slot_goods[pid] = mm


## Where a line's packs stand on its fixture, each drawn `pack` wide and tall with its foot at its origin: shoulder to
## shoulder along every row and door, turned to the locked store camera, in a scattered order so selling down thins
## every row instead of emptying one end.
static func facings(kind: String, p: Vector2, pack: Vector2) -> Array:
	var f: Dictionary = FIXTURES[kind]
	var lean := deg_to_rad(f.lean)
	var step := pack.x * PACK_STEP
	var back := sin(lean) * pack.y * 0.7071  # how far a leaning pack's top reaches back, along x and z alike
	var reach := pack.x * 0.3536 + back  # how far a pack spans from its foot
	var inner: Rect2 = f.inner
	var at := []
	for r in f.rows:
		for j in f.lines.size():
			var z := clampf(r[2] + f.lines[j], inner.position.y + reach, inner.end.y - pack.x * 0.3536)  # kept inside the shell
			for bay in f.bays:
				var n := floori((bay[1] - bay[0] - 2.0 * reach) / step) + (0 if j > 0 else 1)  # one fewer behind, in the gaps
				for i in n:
					at.append(Vector3(p.x + (bay[0] + bay[1]) / 2.0 + (i - (n - 1) / 2.0) * step, r[0], p.y + z))
	var order := range(at.size())
	order.sort_custom(func(a: int, b: int) -> bool: return fposmod(a * 0.618034, 1.0) < fposmod(b * 0.618034, 1.0))
	var basis := Basis(Vector3.UP, PI / 4) * Basis(Vector3.RIGHT, -lean)
	return order.map(func(k: int) -> Transform3D: return Transform3D(basis, at[k]))


static func slot_kind(slot: String) -> String:
	if slot.begins_with("fridge"):
		return "fridge"
	if slot.begins_with("shelf"):
		return "shelf"
	return {"frontA": "low", "island": "freezer", "rack": "rack"}.get(slot, "")


func refresh_stock() -> void:
	for pid in slot_goods:
		var mm: MultiMesh = slot_goods[pid]
		var p: Dictionary = branch.store.products[pid]
		mm.visible_instance_count = ceili(mm.instance_count * float(p.stock) / p.capacity)
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
		if a.state == "browse" and Sim.PRODUCTS.has(a.get("want", "")):
			turn_to(e.node, Vector2(a.x, a.z), Sim.world(Sim.SLOTS[Sim.PRODUCTS[a.want].slot].pos))
		elif a.state == "queue" and not a.moving:
			turn_to(e.node, Vector2(a.x, a.z), Sim.world(Sim.REGISTERS[a.register].pos))
		# a fixed sideways step per walker, so a group through the door walks abreast instead of stacked
		e.node.position += Vector3(a.cross_j * 0.25, 0, (a.lane - 0.5) * 0.5)
	drop_missing(agent_nodes, seen)
	seen = {}
	for t in branch.threats:
		seen[t.id] = true
		var e = threat_nodes.get(t.id)
		if e == null:
			e = make_threat(t)
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
				node = prop(null, "cat", Vector3.ZERO)
				node.add_child(shadow(0.0, 0.25))
				e = {"node": node, "y": 0.0}
			else:
				var row: int = WALK_ROW.get(s.role, 7)
				node = sprite("walk", Rect2(0, row * PERSON.y, PERSON.x, PERSON.y), PERSON_PX)
				node.add_child(shadow())
				e = {"node": node, "a": row, "step": 0.0}
			actors.add_child(node)
			staff_nodes[s.id] = e
		if e.has("a"):
			move_sprite(e, s, Sim.STAFF_WALK, delta)
			if not s.moving and s.role in ["cashier", "stocker"]:
				var at := Vector2(s.x - 1.0, s.z)  # the counter is on the clerks' -x side
				if s.role == "stocker" and s.get("phase", "") == "work" and Sim.PRODUCTS.has(s.get("task", "")):
					at = Sim.world(Sim.SLOTS[Sim.PRODUCTS[s.task].slot].pos)
				turn_to(e.node, Vector2(s.x, s.z), at)
		else:
			e.node.position = Vector3(s.x, e.y, s.z)
			if s.moving:
				turn_to(e.node, Vector2(s.x, s.z), Vector2(s.x + cos(s.heading), s.z + sin(s.heading)))
	drop_missing(staff_nodes, seen)
	for d in [agent_nodes, threat_nodes, staff_nodes]:
		for id in d:
			if d[id].node is Sprite3D:
				shine(d[id].node)


## Turns a standing sprite's profile toward a spot, in screen terms (the art faces screen-right).
func turn_to(node: Sprite3D, from: Vector2, to: Vector2) -> void:
	var sx := Vector3(to.x - from.x, 0, to.y - from.y).dot(cam.global_transform.basis.x)
	if absf(sx) > 0.05:
		node.flip_h = sx < 0.0


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


func make_threat(t: Dictionary) -> Dictionary:
	var e := {}
	if WALK_ROW.has(t.type):
		var row: int = WALK_ROW[t.type]
		if t.type in ["flyer", "mascot"]:
			row += Sim.RIVALS.keys().find(branch.rival.id)
		var sc := MASCOT_SCALE if t.type == "mascot" else 1.0
		var node := sprite("walk", Rect2(0, row * PERSON.y, PERSON.x, PERSON.y), PERSON_PX * sc)
		node.add_child(shadow(0.82 * sc - 0.02, 0.5 * sc))
		e = {"node": node, "a": row, "step": 0.0, "scale": sc}
		if t.type == "review":  # stands on the sidewalk typing at your door
			e.erase("a")
			node.position.y = 0.82
			turn_to(node, Vector2(t.x, t.z), Sim.DOOR)
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
	var y: float = {"trash": 0.3, "spill": 0.05, "breaker": 1.7, "mascot": 1.4}.get(t.type, 1.0)
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
			var d := screen_room(Vector3(p.x, COUNTER_H + 0.2, p.y)).distance_to(pos)
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
		# turns in quarter steps: the landmarks are drawn for the diagonal views only
		yaw_drag -= e.relative.x * 0.006
		var snapped_ := PI / 4 + roundf(yaw_drag / (PI / 2)) * PI / 2
		if not is_equal_approx(snapped_, yaw):
			yaw = snapped_
			for s in lm_sprites:
				anchor(s)
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
		if snow_cover:
			snow_cover.visible = branch.event != null and branch.event.id == "coldSnap"
		refresh_stock()
		sync_actors(delta)
		street_traffic(delta)
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
		var d := r.randf()  # snow falls at three depths: near flakes bigger, faster and swaying wider
		var y := fposmod(r.randf() * span + now * look[3] * r.randf_range(0.8, 1.2) * (lerpf(0.5, 1.7, d) if look[4] == 0.0 else 1.0), span) - 20.0
		var x := fposmod(r.randf() * size.x + y * look[2], size.x)
		var p := Vector2(x + (sin(now * 1.4 + i) * lerpf(3.0, 10.0, d) if look[4] == 0.0 else 0.0), y)
		if inside.size() > 2 and Geometry2D.is_point_in_polygon(p, inside):
			continue
		if look[4] == 0.0:
			var px := 2.0 if d < 0.45 else (3.0 if d < 0.85 else 4.0)
			if px == 4.0:
				overlay.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(1, 1, 1, 0.2))
			overlay.draw_rect(Rect2(p - Vector2(px, px) / 2, Vector2(px, px)), Color(1, 1, 1, lerpf(0.5, 0.95, d)))
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
	var bw := font.get_string_size(band.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	pill(Vector2(16 + dw + 14 + 8 + 7 + bw / 2, 78), band.name, 13, Color("ffc94a") if band.rush else Color("7a5c3a"), Color("6b4512") if band.rush else Color.WHITE)


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
	# the rival's name rides a pin over its roof, like a branch on the city map, so the plate never covers its fascia
	var roof_at := screen(Vector3((span.x + span.y) / 2, 4.42, -9.4))
	var sign_at := roof_at + Vector2(0, -58)
	overlay.draw_line(roof_at + Vector2(1, 0), sign_at + Vector2(1, 0), Color(0, 0, 0, 0.3), 3.0)
	overlay.draw_line(roof_at, sign_at, Color.WHITE, 2.0)
	overlay.draw_circle(roof_at + Vector2(0, 1.5), 5.5, Color(0, 0, 0, 0.3))
	overlay.draw_circle(roof_at, 5.0, Color.WHITE)
	overlay.draw_circle(roof_at, 3.6, Color("8a8780") if rv.defeated else Color(def.color))
	if not rv.defeated:
		# name and takings on one cream plate, so the bar never sits on the chain's own fascia color
		var font: Font = bold if bold else get_theme_default_font()
		var w := maxf(font.get_string_size(def.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14, 100) + 12
		var plate := Rect2(sign_at + Vector2(-w / 2, -font.get_ascent(13) - 8), Vector2(w, font.get_ascent(13) + 32))
		overlay.draw_style_box(round_box(Color(0.42, 0.3, 0.15, 0.25), 11), Rect2(plate.position + Vector2(0, 3), plate.size))
		overlay.draw_style_box(round_box(Color(1.0, 0.98, 0.92, 0.96), 11), plate)
		pill(sign_at, def.name, 13, Color(def.color).darkened(0.1))
		bar(Rect2(Vector2(plate.position.x + 8, plate.end.y - 13), Vector2(w - 16, 7)), rv.hp / rv.max_hp, Color(def.color), Color(0.42, 0.3, 0.15, 0.22))
	else:
		pill(sign_at, def.name + "  (closed)", 13, Color("a99f8c"))
	if not rv.defeated:
		if rv.price_war > 0.0:
			pill(sign_at + Vector2(0, 44), "Price war %ds" % ceili(rv.price_war), 12, Color("e05a4e"))
		elif rv.telegraph != "":
			var blink := floori(Time.get_ticks_msec() / 250.0) % 2 == 0
			pill(sign_at + Vector2(0, 44), "! %s in %ds" % [Sim.ATTACKS[rv.telegraph].name, ceili(maxf(0.0, rv.attack_timer))], 12, Color("e05a4e") if blink else Color("b8372d"))
	# shelves once they've sold some: a shelf tag with the product and its stock bar, red when low
	for pid in st.products:
		var p: Dictionary = st.products[pid]
		var sp: Vector2 = Sim.SLOTS[Sim.PRODUCTS[pid].slot].pos
		var at := screen_room(Vector3(sp.x, 0.05, sp.y + 0.5))
		var frac: float = float(p.stock) / p.capacity
		if frac < 1.0:
			var tag := Rect2(at + Vector2(-25, -6), Vector2(50, 18))
			overlay.draw_style_box(round_box(Color(0.42, 0.3, 0.15, 0.3), 9), Rect2(tag.position + Vector2(0, 2), tag.size))
			overlay.draw_style_box(round_box(Color(1.0, 0.98, 0.92, 0.97), 9), tag)
			var ic: Array = Sim.PRODUCTS[pid].icon
			var cell: int = {"products": ITEM, "perks": 80, "decor": DECOR}[ic[0]]
			overlay.draw_texture_rect_region(tex[ic[0]], Rect2(tag.position + Vector2(3, 1), Vector2(16, 16)), Rect2(ic[1] * cell, 0, cell, cell))
			bar(Rect2(tag.position + Vector2(22, 7), Vector2(23, 4)), frac, Color("e05a4e") if frac < Sim.LOW_STOCK else Color("3fb59a"), Color(0.42, 0.3, 0.15, 0.28))
		if p.stock == 0:
			pill(at + Vector2(0, 30), "Empty", 11, Color("e05a4e"))
	# registers: who's at the till, how far the checkout is; a waiting customer with no cashier needs you
	for reg in st.registers:
		if not reg.active:
			continue
		var rp: Vector2 = Sim.REGISTERS[reg.id].pos
		var at := screen_room(Vector3(rp.x, COUNTER_H + 0.6, rp.y))
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
		var top := at + Vector2(0, -26 if t.type in ["flyer", "shoplifter", "suit", "review"] else (-36 if t.type == "mascot" else -12))
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
	var walk: bool = lt[0] and (not lt[1] or floori(Time.get_ticks_msec() / 250.0) % 2 == 0)
	for pole in light_poles:
		draw_signal(screen(pole + Vector3(0, 0.17, 0)), screen(pole - Vector3(0, 0.17, 0)), walk)
	if not hover.is_empty():
		var at := Vector2.ZERO
		match hover.type:
			"clickThreat":
				var t = sim.threat_by_id(b, hover.id)
				if t != null:
					at = screen(threat_point(t))
			"ringUp":
				var p: Vector2 = Sim.REGISTERS[hover.register].pos
				at = screen_room(Vector3(p.x, COUNTER_H + 0.2, p.y))
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


## A Japanese pedestrian signal's two lamps, red standing figure over green walking one; the lit one glows after dark.
func draw_signal(top: Vector2, bottom: Vector2, walk: bool) -> void:
	var r := maxf(3.0, top.distance_to(bottom) * 0.46)
	for k in 2:
		var c := top if k == 0 else bottom
		var on := (k == 1) == walk
		var hue := Color("35d06a") if k == 1 else Color("ff4a36")
		if on:
			overlay.draw_circle(c, r * 1.9, Color(hue, 0.15 + 0.3 * night))
		overlay.draw_circle(c, r, hue if on else Color("1a1b26"))
		var fig := hue.lightened(0.75) if on else hue.darkened(0.7)
		var w := maxf(1.0, r * 0.2)
		overlay.draw_circle(c + Vector2(0.05, -0.5) * r, r * 0.17, fig)
		if k == 1:
			overlay.draw_polyline(PackedVector2Array([c + Vector2(-0.35, 0.65) * r, c + Vector2(-0.05, 0.25) * r, c + Vector2(0.3, 0.65) * r]), fig, w)
			overlay.draw_line(c + Vector2(0.05, -0.28) * r, c + Vector2(-0.05, 0.25) * r, fig, w * 1.3)
			overlay.draw_polyline(PackedVector2Array([c + Vector2(-0.35, 0.05) * r, c + Vector2(0.03, -0.18) * r, c + Vector2(0.35, 0.0) * r]), fig, w)
		else:
			overlay.draw_line(c + Vector2(0.05, -0.28) * r, c + Vector2(0.05, 0.25) * r, fig, w * 1.6)
			overlay.draw_line(c + Vector2(-0.07, 0.25) * r, c + Vector2(-0.07, 0.68) * r, fig, w)
			overlay.draw_line(c + Vector2(0.17, 0.25) * r, c + Vector2(0.17, 0.68) * r, fig, w)
			overlay.draw_line(c + Vector2(-0.18, -0.22) * r, c + Vector2(-0.18, 0.2) * r, fig, w)
			overlay.draw_line(c + Vector2(0.28, -0.22) * r, c + Vector2(0.28, 0.2) * r, fig, w)


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
		var ground := screen_world(Vector3(p2.x + 2.0, 0.0, p2.y + 3.0))
		pins.append([ground, b])
		taken.append(Rect2(ground + Vector2(-40, -42), Vector2(80, 46)))
	var order := []
	for rank in 3:
		order += sim.districts.filter(func(d): return (0 if d.type == "hub" else (1 if d.lm[1] >= 0 else 2)) == rank)
	var bf: Font = bold if bold else font
	for d in order:
		var at := screen_world(Vector3(d.center.x, 0, d.center.y - 4.0))
		var nm: String = d.name.to_upper()
		var px := 11 if d.type == "hub" else 9
		var w := bf.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var asc := bf.get_ascent(px)
		var r := Rect2(at.x - w / 2 - 5, at.y - asc - 1, w + 10, asc + bf.get_descent(px) + 2)
		if not room_for.call(r.grow(1)):
			continue
		overlay.draw_style_box(round_box(Color(0.22, 0.16, 0.1, 0.62), r.size.y / 2), r)
		overlay.draw_string(bf, Vector2(at.x - w / 2, at.y), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color("fff1c9") if d.type == "hub" else Color("f7f3e8"))
	if zoom < 0.45:
		for av in C.avenues:
			if av.name == "":
				continue
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
	# each branch as a map pin: its name raised on a stem over a dot on the lot, the rival's dot beside it on the ground
	for e in pins:
		var ground: Vector2 = e[0]
		var b: Dictionary = e[1]
		if not Rect2(Vector2.ZERO, size).grow(40).has_point(ground):
			continue
		var c := Color("e98a1d") if is_same(b, branch) else Color("c46a14")
		var at := ground + Vector2(0, -26)
		if not b.rival.defeated:
			var rat := screen_world(frame_origin(b.lot) + Vector3(rival_span(b.rival).x + 4.0, 0.0, -7.2))
			overlay.draw_circle(rat + Vector2(0, 1.5), 5.5, Color(0, 0, 0, 0.3))
			overlay.draw_circle(rat, 5.0, Color.WHITE)
			overlay.draw_circle(rat, 3.6, Color(Sim.RIVALS[b.rival.id].color))
		overlay.draw_line(ground + Vector2(1, 0), at + Vector2(1, 0), Color(0, 0, 0, 0.3), 3.0)
		overlay.draw_line(ground, at, Color.WHITE, 2.0)
		overlay.draw_circle(ground + Vector2(0, 1.5), 5.5, Color(0, 0, 0, 0.3))
		overlay.draw_circle(ground, 5.0, Color.WHITE)
		overlay.draw_circle(ground, 3.6, c)
		pill(at, b.name, 11, c)
