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
# each art/outdoor.png prop's sun shadow, as [from, to, width] fractions of its drawn size, soft all round when marked:
# a tree's trunk and crown, a bush, the lamp, the post box, a bicycle, the stone lantern, the planter, the bus stop's
# pole and its disc
const OUTDOOR_CAST := [[[0.0, 0.3, 0.08], [0.12, 1.02, 0.95, true]], [[0.0, 0.3, 0.08], [0.12, 1.02, 0.95, true]],
	[[0.0, 0.3, 0.08], [0.12, 1.02, 0.98, true]], [[0.0, 0.2, 0.06], [0.05, 1.05, 0.65, true]], [[-0.1, 0.6, 0.8, true]],
	[[-0.1, 0.6, 0.75, true]], [[0.0, 0.9, 0.06]], [[0.0, 0.74, 0.3]], [[0.0, 0.62, 0.42]], [[0.0, 0.85, 0.36]],
	[[0.0, 0.42, 0.72]], [[0.0, 0.72, 0.04], [0.7, 0.96, 0.22]]]
const DECOR_CAST := {0: [0.0, 0.85, 0.42], 5: [0.0, 0.9, 0.42]}  # the potted plant and the A-board, the same way
const FACILITY_CAST := {"vending": [0.0, 1.8, 1.0], "gacha": [0.0, 1.35, 1.3], "bench": [0.3, 0.85, 1.2]}  # metres
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
const FIELD_WEIGHTS := [3.0, 2.0, 0.8, 0.8, 0.7, 2.0, 1.5]  # mostly green, with a gold or bare field here and there
# the day's weather over the view: [tint, then for falling rain or snow: drops, slant, speed px/s, streak length]
const WEATHER_LOOK := {
	"hot": [Color(1.0, 0.68, 0.3, 0.15)],
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
const BLACKOUT := [Color(0.62, 0.65, 0.74), Color(0.17, 0.2, 0.32)]  # your shop with its power cut: by daylight through the glass, after dark
const SEA := Color("3a8cc8")
const SEA_NIGHT := Color(0.5, 0.48, 0.46)  # water goes darker than the land after dark instead of glowing blue under the night tint
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
# A person's shadow, metres from the feet (y away from the sun): a soft contact patch, and while the sun is up a
# body-length shadow tapering away from it, as the poles cast theirs, but not across your shop's roofed floor.
const FOOT_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color;
uniform float core;
uniform float sun;
uniform float reach;
uniform vec2 size;
uniform float back;
uniform vec4 indoor;
varying vec2 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * size.x, UV.y * size.y - back);
	float contact = core * (1.0 - smoothstep(0.08, 0.3, length(p * vec2(1.0, 1.25))));
	float t = p.y / reach;
	float hw = mix(0.17, 0.08, clamp(t, 0.0, 1.0));
	float body = sun * smoothstep(-0.05, 0.12, p.y) * (1.0 - smoothstep(0.5, 1.0, t)) * (1.0 - smoothstep(hw * 0.45, hw, abs(p.x)));
	vec2 in_shop = step(indoor.xy, wpos) * step(wpos, indoor.xy + indoor.zw);
	body *= 1.0 - in_shop.x * in_shop.y;
	ALBEDO = tint.rgb;
	ALPHA = 1.0 - (1.0 - contact) * (1.0 - body);
}
"""
const FOOT := Vector3(0.7, 0.35, 1.6)  # a person's shadow plane: width, behind the feet, and the height it casts
# Farmland: each field's crop colour, furrowed, under the hour's light; after dark the crops fade into one dark green
# so the lit city stands out rather than a patchwork of maroon, olive and green round it.
const FIELD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D furrows : filter_linear_mipmap, repeat_enable;
uniform vec3 light = vec3(1.0);
uniform float night = 0.0;

void fragment() {
	float l = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	vec3 crop = mix(COLOR.rgb, vec3(0.47, 0.62, 0.36) * (0.9 + 0.4 * (l - 0.66)), 0.8 * night);
	ALBEDO = crop * texture(furrows, UV).rgb * light;
}
"""
# Open water on the map: the sea's blue, mottled in broad patches, with short wave crests over a darker trough
# scattered across it at a steady size on screen at any zoom (two sizes crossfaded), slowly glinting in and out.
const SWELL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 sea : source_color = vec3(0.23, 0.55, 0.78);
uniform vec3 light = vec3(1.0);
varying vec2 wp;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

// x: crest, y: trough, for cells s metres across
vec2 crests(vec2 p, float s, float aa) {
	vec2 q = p / s;
	vec2 c = floor(q);
	float r = hash(c);
	vec2 d = fract(q) - (vec2(hash(c + 3.1), hash(c + 7.7)) * 0.5 + 0.25);
	float len = 0.16 + 0.14 * hash(c + 1.3);
	float bow = d.y + 1.6 * d.x * d.x;
	float along = 1.0 - smoothstep(len, len + aa, abs(d.x));
	float on = step(0.42, r) * (0.55 + 0.45 * sin(TIME * 0.7 + r * 40.0));
	float crest = along * (1.0 - smoothstep(0.045, 0.045 + aa, abs(bow))) * on;
	float trough = along * (1.0 - smoothstep(0.035, 0.035 + aa, abs(bow - 0.08))) * on;
	return vec2(crest, trough);
}

void vertex() {
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	wp = vec2(w.x - w.y, w.x + w.y) * 0.7071;  // crests lie across the view at the map's usual heading
}

void fragment() {
	float px = max(length(fwidth(wp)), 1e-4);
	float lv = log2(px * 16.0);
	float s = exp2(floor(lv));
	float aa = 0.5 / 16.0;
	vec2 w = mix(crests(wp, s, aa), crests(wp, s * 2.0, aa * 0.5), fract(lv));
	float m = noise(wp / 260.0) * 0.6 + noise(wp / 70.0) * 0.4;
	vec3 col = sea * (0.92 + 0.14 * m);
	col = mix(col, sea * 0.82, w.y * 0.6);
	col = mix(col, mix(sea, vec3(1.0), 0.55), w.x * 0.85);
	ALBEDO = col * light;
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
uniform float snow = 0.0;  // a cold snap: snow lying on every roof
uniform sampler2D snow_tex : filter_nearest, repeat_enable;
varying vec3 lpos;
varying vec2 wxz;
// per instance or face: flat, as the hashes below blow up the slightest drift across a triangle into patches
varying flat vec3 lnrm;
varying flat vec4 info;
varying flat vec4 tint;
varying vec2 sunl;
const vec3 ACCENT[8] = vec3[8](vec3(0.89, 0.25, 0.22), vec3(0.96, 0.56, 0.16), vec3(0.98, 0.82, 0.25), vec3(0.24, 0.68, 0.36), vec3(0.22, 0.5, 0.86), vec3(0.6, 0.34, 0.8), vec3(0.95, 0.45, 0.65), vec3(0.2, 0.72, 0.74));
const vec3 FLOOR[4] = vec3[4](vec3(0.6, 0.46, 0.33), vec3(0.68, 0.64, 0.42), vec3(0.52, 0.52, 0.5), vec3(0.68, 0.66, 0.61));  // boards, tatami, concrete, tile
const vec3 ROOF[8] = vec3[8](FLAT_ROOFS);  // Sim.City.FLAT_ROOFS

void vertex() {
	info = INSTANCE_CUSTOM;
	tint = COLOR;
	lnrm = NORMAL;
	lpos = (VERTEX + 0.5) * INSTANCE_CUSTOM.xyz;
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	sunl = vec2(dot(normalize(MODEL_MATRIX[0].xz), vec2(-0.35, 0.6)), dot(normalize(MODEL_MATRIX[2].xz), vec2(-0.35, 0.6)));
}

// a light whose own threshold (0-1) the falling dark has passed: full on (a little dimmer until full night), not faded in
float switched(float at, float dark) {
	return smoothstep(0.08 + 0.6 * at, 0.12 + 0.6 * at, dark) * mix(0.8, 1.0, dark);
}

// a cut-down wall's window in this bay (wall 0, 1: along x at the near and far z; 2, 3: along z): how far in from its jambs
float window_in(float along, float bay, float wall, float seed) {
	float n = floor(along / bay);
	float r = fract(sin(dot(vec2(n, wall) + seed * 19.0, vec2(12.9898, 78.233))) * 43758.5453);
	return r < 0.8 ? min(0.75, bay * 0.28) - abs(along - (n + 0.5) * bay) : -1.0;
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
				// a doorway in each wall between rooms, placed by that wall's own hash so the rooms either side agree
				vec2 bnd = floor(rc + 0.5);
				float dx = fract(sin(dot(vec2(bnd.x, floor(rc.y)) + seed * 23.0, vec2(39.35, 11.13))) * 43758.5453);
				float dz = fract(sin(dot(vec2(floor(rc.x), bnd.y) + seed * 29.0, vec2(17.71, 51.37))) * 43758.5453);
				wd.x = abs(fract(rc.y) - 0.3 - 0.4 * dx) * bay.y < 0.4 ? 1.0 : wd.x;
				wd.y = abs(fract(rc.x) - 0.3 - 0.4 * dz) * bay.x < 0.4 ? 1.0 : wd.y;
				float wall = min(min(e.x, e.y) - 0.3, min(wd.x, wd.y) - 0.06);
				float r = fract(sin(dot(floor(rc) + seed * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
				int k = int(r * 4.0);
				vec2 g = fract(lpos.xz * (k == 0 ? vec2(0.0, 4.0) : (k == 1 ? vec2(1.1, 0.55) : vec2(1.0))));
				float seam = min(k == 0 ? 1.0 : min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y)) < 0.05 ? 0.86 : 1.0;
				// laid piece by piece: boards a shade apart and staggered at their butt joints, tatami edged in dark cloth
				// down their long sides and each mat's rush catching the light its own way, concrete mottled, tiles each a shade
				vec2 pc = floor(lpos.xz * (k == 0 ? vec2(0.0, 4.0) : (k == 1 ? vec2(1.1, 0.55) : vec2(1.0))));
				float ph = fract(sin(dot(pc + seed * 41.0, vec2(78.233, 12.9898))) * 43758.5453);
				if (k == 0) {
					float bu = lpos.x / 1.8 + ph;
					float bh = fract(sin((pc.y * 7.0 + floor(bu) + seed * 13.0) * 12.9898) * 43758.5453);
					seam *= (0.9 + 0.16 * bh) * (min(fract(bu), 1.0 - fract(bu)) < 0.018 ? 0.84 : 1.0);
				} else if (k == 1) {
					seam = min(g.x, 1.0 - g.x) < 0.04 ? 0.42 : seam * (mod(pc.x + pc.y, 2.0) < 0.5 ? 1.06 : 0.93) * (0.97 + 0.06 * ph);
				} else if (k == 2) {
					vec2 cp = lpos.xz * 0.9 + seed * 7.0;
					vec2 ci = floor(cp);
					vec2 cf = smoothstep(0.0, 1.0, fract(cp));
					vec4 h = fract(sin(vec4(dot(ci, vec2(12.9898, 78.233)), dot(ci + vec2(1.0, 0.0), vec2(12.9898, 78.233)), dot(ci + vec2(0.0, 1.0), vec2(12.9898, 78.233)), dot(ci + 1.0, vec2(12.9898, 78.233)))) * 43758.5453);
					seam *= 0.91 + 0.14 * mix(mix(h.x, h.y, cf.x), mix(h.z, h.w, cf.x), cf.y);
				} else {
					seam *= 0.95 + 0.09 * ph;
				}
				vec3 fl = FLOOR[k] * seam;
				// furnished to suit the floor: a piece against one wall (sofa, futon, steel racking, a kitchen counter)
				// and one in the room (a rug, a low table, boxes, a dining table), the standing ones shadowed off the sun
				vec2 o = floor(rc) * bay;
				vec2 lo = max(o + 0.06, vec2(0.3));
				vec2 hi = min(o + bay - 0.06, info.xz - 0.3);
				vec2 mid = (lo + hi) * 0.5;
				vec2 room = hi - lo;
				int side = int(fract(r * 7.13) * 4.0);
				float run = room[side / 2 == 0 ? 1 : 0] * (0.45 + 0.25 * fract(r * 3.71));
				float deep = k == 1 ? 0.55 : 0.4;
				vec2 ha = side / 2 == 0 ? vec2(deep, run) * 0.5 : vec2(run, deep) * 0.5;
				vec2 ca = mid + (side / 2 == 0 ? vec2((room.x * 0.5 - ha.x) * (side == 0 ? -1.0 : 1.0), 0.0) : vec2(0.0, (room.y * 0.5 - ha.y) * (side == 2 ? -1.0 : 1.0)));
				vec2 hb = min(room * (k == 0 ? vec2(0.24, 0.22) : vec2(0.15, 0.12)) + 0.05, vec2(0.75));
				vec2 cb = mid + (vec2(fract(r * 5.3), fract(r * 9.7)) - 0.5) * 0.25 * room - (ca - mid) * 0.15;
				vec3 ACol[4] = vec3[4](mix(ACCENT[(pick + 4) % 8], vec3(0.45), 0.45), vec3(0.93, 0.9, 0.84), vec3(0.6, 0.65, 0.7), vec3(0.9, 0.9, 0.87));
				vec3 BCol[4] = vec3[4](mix(ACCENT[(pick + int(r * 5.0) + 1) % 8], fl, 0.35), vec3(0.42, 0.27, 0.17), vec3(0.77, 0.6, 0.4), vec3(0.74, 0.56, 0.36));
				float ta = k == 1 ? 0.12 : 0.35;  // how far each casts its shadow: a futon barely, racking far
				float tb = k == 0 ? 0.0 : 0.25;  // a rug casts none
				vec2 da = abs(lpos.xz - ca) - ha;
				vec2 db = abs(lpos.xz - cb) - hb;
				vec2 sa = abs(lpos.xz + sunl * ta - ca) - ha;
				vec2 sb = abs(lpos.xz + sunl * tb - cb) - hb;
				float ina = max(da.x, da.y);
				float inb = fract(r * 17.0) < 0.8 ? max(db.x, db.y) : 1.0;
				if (min(max(sa.x, sa.y), tb > 0.0 ? max(sb.x, sb.y) : 1.0) < 0.0 && min(ina, inb) > 0.0) {
					fl *= 0.78;
				}
				if (k == 1 && fract(r * 17.0) < 0.8) {  // a zabuton on the floor at each long side of the low table
					vec2 off = hb.x >= hb.y ? vec2(0.0, hb.y + 0.3) : vec2(hb.x + 0.3, 0.0);
					vec2 z1 = abs(lpos.xz - cb - off) - 0.24;
					vec2 z2 = abs(lpos.xz - cb + off) - 0.24;
					float inz = min(max(z1.x, z1.y), max(z2.x, z2.y));
					fl = inz < 0.0 ? mix(ACCENT[(pick + 2) % 8], vec3(0.55, 0.3, 0.3), 0.35) * (inz > -0.04 ? 0.8 : (inz > -0.2 ? 1.0 : 0.88)) : fl;
				}
				if (inb < 0.0) {
					fl = BCol[k] * (inb > -0.05 ? 0.82 : (k == 0 && inb > -0.14 ? 1.15 : (k == 1 && inb < -0.08 ? 1.3 : 1.0)));
					if (k == 2) {  // a strip of tape across each box
						fl *= abs(lpos.x - cb.x) < 0.04 ? 1.2 : 1.0;
					}
				}
				if (ina < 0.0) {
					fl = ACol[k] * (ina > -0.05 ? 0.8 : 1.0);
					if (k == 0) {  // a sofa: its back to the wall and an arm at each end, the seat in cushions
						vec2 lc = lpos.xz - ca;
						float across = (side % 2 == 0 ? 1.0 : -1.0) * (side / 2 == 0 ? lc.x : lc.y) + (side / 2 == 0 ? ha.x : ha.y);
						float along = (side / 2 == 0 ? lc.y : lc.x) + run * 0.5;
						float n = run > 1.5 ? 3.0 : 2.0;
						float cu = (along - 0.12) / (run - 0.24) * n;
						bool frame = across < 0.13 || along < 0.12 || along > run - 0.12;
						fl = ina > -0.05 ? fl : ACol[k] * (frame ? 1.12 : (min(fract(cu), 1.0 - fract(cu)) < 0.06 ? 0.8 : 0.95));
					} else if (k == 1) {  // a futon: a blue quilt up to the pillow at its head
						fl = dot(lpos.xz - ca, side / 2 == 0 ? vec2(0.0, 1.0) : vec2(1.0, 0.0)) < run * 0.28 && ina < -0.04 ? vec3(0.45, 0.58, 0.8) : fl;
					} else if (k == 3) {  // a steel sink let into the counter
						vec2 sk = abs(lpos.xz - ca) - min(ha, vec2(0.18));
						fl = max(sk.x, sk.y) < 0.0 ? vec3(0.66, 0.7, 0.74) : fl;
					}
				}
				fl *= mix(0.72, 1.0, smoothstep(0.0, 0.5, wall));
				col = wall < 0.0 ? tint.rgb * 1.08 : fl;
				// windows cut through the outer walls below the cut: the reveal down to the sill, the glass's section across it
				bool along_x = e.y < e.x;
				float win = window_in(along_x ? lpos.x : lpos.z, along_x ? bay.x : bay.y, along_x ? step(info.z * 0.5, lpos.z) : 2.0 + step(info.x * 0.5, lpos.x), seed);
				if (min(e.x, e.y) < 0.3 && win > 0.0) {
					col = win < 0.05 ? vec3(0.78, 0.8, 0.82) : (abs(min(e.x, e.y) - 0.15) < 0.035 ? vec3(0.72, 0.86, 0.92) : tint.rgb * 0.8);
				}
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
				// its windows from the sill up, glazed in an aluminium frame, the sky caught in a streak across the glass
				vec2 bay = info.xz / max(vec2(1.0), floor(info.xz / vec2(3.0, 4.0) + 0.5));
				float along = front ? lpos.x : lpos.z;
				float win = window_in(along, front ? bay.x : bay.y, front ? step(0.0, lnrm.z) : 2.0 + step(0.0, lnrm.x), seed);
				if (win > 0.0 && lpos.y > 0.46) {
					float streak = fract((along + lpos.y * 1.5) * 0.9);
					col = win < 0.05 || lpos.y < 0.52 ? vec3(0.78, 0.8, 0.82) : mix(vec3(0.34, 0.46, 0.56), vec3(0.6, 0.74, 0.83), lpos.y / info.y) * (streak < 0.18 ? 1.18 : 1.0);
				}
				glow = vec3(0.0);
				inside = 0.0;
			}
		}
		col *= mix(0.72, 1.0, clamp(lpos.y / 1.2, 0.0, 1.0));
	} else if (info.x == 0.0 && tint.a < 0.99) {  // a landmark face packed with alpha under 1 is floodlit after dark
		glow = vec3(1.0, 0.62, 0.3) * (1.0 - tint.a) * 2.0 * night;  // a warm floodlight, its strength in the alpha
	}
	if (snow > 0.0 && lnrm.y > 0.25 && !(info.w > -0.5 && info.y < 1.0)) {  // drifts as on the ground, not on the cut-down floors
		vec4 s = texture(snow_tex, wxz * 0.125);
		col = mix(col, s.rgb, s.a * snow);
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
var floor_tex := {}  # shop floor texture by left wall
var set_sig := ""
var tarmac_m: StandardMaterial3D
var car_park_m: StandardMaterial3D
var street_x := Vector2(SET.position.x, SET.end.x)  # how far the set's street runs (street_reach)
var entries := []  # x of the side roads that meet the set's street, where cars come in when both its ends are quays
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
var skylight_pair: Array = []  # weakrefs to the rival's skylight glass and its night glow, shared by both skylights

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
var rails: Array = []  # [pts, offset, segment]: the city's bridge and quay railings, one piece per segment
var rail_node: MeshInstance3D  # those railings, rebuilt without the pieces that would stand on the set's street
var rail_sig := Rect2(1, 1, -1, -1)
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
var lit_mats: Array = []  # [weakref to an outdoor material (or a sign's Label3D), its own colour, how far it lights up after dark (lightboxes)]
var lit_sprites: Array = []  # outdoor sprites that stand still, relit when the light changes
var pools: Array = []  # Vector3(x, z, radius) in the world: lamp light on the street after dark
var pool_mat: StandardMaterial3D
var lamp_mat: StandardMaterial3D  # street lamp heads: pale by day, lit after dark
var halo_mat: StandardMaterial3D  # the glow round a lit lamp head
var beam_mat: StandardMaterial3D  # the cone of light falling from a lit lamp head to its pool
var spill_mat: StandardMaterial3D  # shop light falling out of a glass front across the sidewalk
var shop_spill_mat: StandardMaterial3D  # the same out of your own shop, which a blackout puts out
var room_dim := Color.WHITE  # your shop's lighting, dimmed while a blackout has cut its power
var set_sign_mats: Array = []  # your pole sign's lightbox faces on the set
var breaker_lamp: Array = []  # [the tripped board's lamp, its glow]
var flood_mat: StandardMaterial3D  # your car park's floodlight on the bays
var sign_glow_mat: StandardMaterial3D  # the glow round your lit pole sign
var fascia_glows: Array = []  # [weakref to the glow round a rival's lit fascia, its chain's colour]
var fascia_glow_tex: ImageTexture
var snow_tex: ImageTexture  # patchy settled snow, tiled 8 m
var snow_cover: MeshInstance3D  # the set's snowy ground, shown on a cold snap
var matsuri: Node3D  # the set's festival lanterns and yatai, shown on a Summer Matsuri
var lantern_glow_mat: StandardMaterial3D
var stall_glow_mat: StandardMaterial3D  # the yatai's lamplight on the bay after dark
var works: Node3D  # the set's roadworks, shown on a Roadworks day
var works_glow_mat: StandardMaterial3D  # the works' flashing lamps and arrow board after dark
var tv: Node3D  # the set's TV crew, shown on a TV Feature day
var health: Node3D  # the health centre's wagon and a sanitiser stand, shown on a Health Inspection day
var heat: Node3D  # a shaved-ice stand and a splashed sidewalk, shown on a Heatwave day
var light_poles: Array = []  # the crossing lights' heads, in the street frame
var shop_area := Rect2()  # your shop's floor in the world: full light inside
var vignette: GradientTexture2D
var box_mesh: ArrayMesh
var sign_tex: ImageTexture
var plate_tex: ImageTexture
var soft_mat: StandardMaterial3D  # soft contact shadows under people, cars and street things
var ao_mat: StandardMaterial3D  # the dark seam where a building meets the sidewalk
var cast_mat: StandardMaterial3D  # the sun's shadow of a pole or post laid on the street
var crown_mat: StandardMaterial3D  # the same for a tree's crown or a bush, soft all round
var casts: Array = []  # those shadows, stretched as the sun goes down
var foot_mat: ShaderMaterial  # people's shadows
var foot_mesh: PlaneMesh
var sea_mat: StandardMaterial3D
var field_mat: ShaderMaterial
var swell_mat: ShaderMaterial  # the map's open sea and rivers
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
	lantern_glow_mat = halo_mat.duplicate()
	stall_glow_mat = pool_mat.duplicate()
	works_glow_mat = halo_mat.duplicate()
	var fall := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var u := x / 63.0
			fall.set_pixel(x, y, Color(1, 1, 1, (exp(-2.2 * y / 31.0) - exp(-2.2)) / (1.0 - exp(-2.2)) * smoothstep(0.0, 0.2, u) * smoothstep(0.0, 0.2, 1.0 - u)))
	spill_mat.albedo_texture = ImageTexture.create_from_image(fall)
	shop_spill_mat = spill_mat.duplicate()
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
	cast_mat = soft_mat.duplicate()
	var fade := GradientTexture2D.new()
	fade.fill_from = Vector2(0, 0)
	fade.fill_to = Vector2(0, 1)
	fade.gradient = Gradient.new()
	fade.gradient.offsets = PackedFloat32Array([0.0, 0.75, 1.0])
	fade.gradient.colors = PackedColorArray([Color(0.1, 0.08, 0.14), Color(0.1, 0.08, 0.14, 0.7), Color(0.1, 0.08, 0.14, 0)])
	cast_mat.albedo_texture = fade
	crown_mat = soft_mat.duplicate()
	var reach_max := FOOT.z * Vector2(SUN.x, SUN.z).length() / SUN.y * 1.9
	foot_mesh = PlaneMesh.new()
	foot_mesh.size = Vector2(FOOT.x, FOOT.y + reach_max)
	foot_mesh.center_offset = Vector3(0, 0, foot_mesh.size.y / 2 - FOOT.y)
	foot_mat = ShaderMaterial.new()
	foot_mat.shader = Shader.new()
	foot_mat.shader.code = FOOT_SHADER
	foot_mat.set_shader_parameter("tint", Color(0.1, 0.08, 0.14))
	foot_mat.set_shader_parameter("size", foot_mesh.size)
	foot_mat.set_shader_parameter("back", FOOT.y)
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
		var o: Object = e[0].get_ref()
		o.set("modulate" if o is Label3D else "albedo_color", e[1] * light.lerp(Color.WHITE, e[2] * night))
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
	cast_mat.albedo_color.a = 0.42 * (1.0 - night) * (1.0 + 0.3 * golden_at(h))
	crown_mat.albedo_color.a = 0.62 * (1.0 - night) * (1.0 + 0.3 * golden_at(h))
	foot_mat.set_shader_parameter("core", 0.5 - 0.15 * night)
	foot_mat.set_shader_parameter("sun", 0.42 * (1.0 - night) * (1.0 + 0.3 * golden_at(h)))
	foot_mat.set_shader_parameter("reach", FOOT.z * Vector2(SUN.x, SUN.z).length() / SUN.y * (1.0 + 0.9 * golden_at(h)))
	casts = casts.filter(func(s): return is_instance_valid(s))
	for s in casts:
		s.scale.z = 1.0 + 0.9 * golden_at(h)
	var dusk_sea := light * Color.WHITE.lerp(SEA_NIGHT, night)
	env.background_color = SEA * dusk_sea
	if sea_mat:
		sea_mat.albedo_color = dusk_sea
		swell_mat.set_shader_parameter("light", Vector3(dusk_sea.r, dusk_sea.g, dusk_sea.b))
	if field_mat:
		field_mat.set_shader_parameter("light", Vector3(light.r, light.g, light.b))
		field_mat.set_shader_parameter("night", night)
	pool_mat.albedo_color = LAMP * Color(1, 1, 1, 0.75 * night)
	halo_mat.albedo_color = LAMP * Color(1, 1, 1, 0.55 * night)
	beam_mat.albedo_color = LAMP * Color(1, 1, 1, 0.5 * night)
	spill_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.55 * night)
	var on := 1.0 if room_dim == Color.WHITE or mode != "store" else 0.0
	shop_spill_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.55 * night * on)
	flood_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.85 * night * on)
	sign_glow_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.7 * night * on)
	lantern_glow_mat.albedo_color = Color(1.0, 0.55, 0.3, 0.75 * night)
	stall_glow_mat.albedo_color = Color(1.0, 0.6, 0.3, 0.95 * night)
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
		return room_dim
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
func spill(parent: Node3D, cx: float, w: float, face_z: float, m: Material = null) -> void:
	plane(parent, Vector2(w, 4.6), Vector3(cx, -0.028, face_z + 2.3), m if m else spill_mat)
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


## A 4 m square of 1 m paving slabs, white so the district's colour tints it, each row set half a slab along: each
## slab a shade off and flecked, a few weathered darker, bevelled light on its sunny edges, joints darker.
func paving() -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for sy in 4:
		for sx in 4:
			var base := r.randf_range(0.95, 1.01) if r.randf() < 0.85 else r.randf_range(0.88, 0.92)
			for y in 8:
				for x in 8:
					var fleck := r.randf_range(0.98, 1.01) if r.randf() < 0.9 else r.randf_range(0.93, 0.96)
					var edge := 0.86 if x == 7 or y == 7 else (1.03 if x == 0 or y == 0 else 1.0)
					var v := minf(base * fleck * edge, 1.0)
					img.set_pixel(posmod(sx * 8 + x + 4 * (sy % 2), 32), sy * 8 + y, Color(v, v, v))
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


## Poured concrete for a 1.8 m repeat: one slab a pixel short of the repeat each way, flecked, its score lines darker.
func slabs() -> StandardMaterial3D:
	var r := RandomNumberGenerator.new()
	r.seed = 31
	var base := Color("cbc6bb")
	var img := Image.create(18, 18, false, Image.FORMAT_RGB8)
	for y in 18:
		for x in 18:
			var v := r.randf_range(0.97, 1.01) if r.randf() < 0.86 else r.randf_range(0.92, 0.95)
			if x == 17 or y == 17:
				v = 0.84
			img.set_pixel(x, y, Color(base.r * v, base.g * v, base.b * v))
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m


## The set's street for a 32 m repeat across its whole 8 m width (uv x/8, z/8, scaled to a quarter along x): coarse
## grain, both lanes' wheel paths worn darker and smoother with a drip line between them, dust along each kerb, two
## utility cuts patched in fresher tarmac behind a sealed seam, and a few cracks.
func tarmac() -> StandardMaterial3D:
	if tarmac_m:
		return tarmac_m
	var r := RandomNumberGenerator.new()
	r.seed = 41
	var img := Image.create(256, 64, false, Image.FORMAT_RGB8)
	var patches := [Rect2(40, 50, 56, 7), Rect2(150, 10, 12, 13)]  # pixels; rows 32-63 are the far lane (z < 0)
	for py in 64:
		var z := (py + 0.5) / 8.0
		if z >= 4.0:
			z -= 8.0
		var lane_z := absf(absf(z) - 1.7)
		for px in 256:
			var grain := r.randf()
			var v := r.randf_range(0.95, 1.03) if grain < 0.8 else (r.randf_range(1.07, 1.12) if grain < 0.9 else r.randf_range(0.86, 0.9))
			var c := ASPHALT
			if absf(lane_z - 0.62) < 0.24:
				v = lerpf(v, 0.87, 0.75)
			elif lane_z < 0.2 and r.randf() < 0.35:
				v *= 0.88
			if absf(z) > 3.3:
				c = c.lerp(Color("8d8577"), (absf(z) - 3.3) * 0.5)
			for p: Rect2 in patches:
				if p.grow(1).has_point(Vector2(px, py)):
					c = ASPHALT.darkened(0.16)
					v = r.randf_range(0.97, 1.02)
					if not p.has_point(Vector2(px, py)):
						c = ASPHALT.darkened(0.3)
			img.set_pixel(px, py, Color(c.r * v, c.g * v, c.b * v))
	for k in 5:  # hairline cracks, wandering across a lane
		var at := Vector2i(r.randi_range(0, 255), r.randi_range(0, 63))
		for s in r.randi_range(6, 14):
			var cc := img.get_pixelv(at)
			img.set_pixelv(at, cc.darkened(0.3))
			at = Vector2i(posmod(at.x + r.randi_range(0, 2) - (1 if k % 2 else 0), 256), posmod(at.y + r.randi_range(-1, 1), 64))
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.texture_repeat = true
	m.uv1_scale = Vector3(0.25, 1, 1)
	tarmac_m = m
	return m


## Your car park across its whole 7.1 x 8.8 m (uv 0-1 over Rect2(-3.4, -16, 7.1, 8.8)), 16 px a metre: the street's
## coarse grain a shade paler, tyre paths polished darker into each bay and scuffed across the aisle, an oil stain
## where each car's engine stands, dust along the kerbs, and the bay lines and arrow painted in, worn thin at
## their ends and wherever the tyres run over them.
func car_park() -> StandardMaterial3D:
	if car_park_m:
		return car_park_m
	const PX := 16.0
	var r := RandomNumberGenerator.new()
	r.seed = 53
	var img := Image.create(114, 141, false, Image.FORMAT_RGB8)
	var base := ASPHALT.lightened(0.08)
	var paint := Color("ebe7dc")
	var noise := FastNoiseLite.new()
	noise.seed = 53
	noise.frequency = 0.9
	var lines := [Rect2(-2.2, -15.6, 0.12, 4.6), Rect2(0.2, -15.6, 0.12, 4.6), Rect2(2.6, -15.6, 0.12, 4.6), Rect2(-2.2, -15.6, 4.92, 0.12), Rect2(0.95, -9.6, 0.24, 1.5)]
	var head := PackedVector2Array([Vector2(0.55, -9.55), Vector2(1.07, -10.35), Vector2(1.59, -9.55)])
	var grain := {}
	for py in img.get_height():
		var z := -16.0 + (py + 0.5) / PX
		for px in img.get_width():
			var x := -3.4 + (px + 0.5) / PX
			var cell := Vector2i(px / 2, py / 2)  # the grain at the street's 8 px a metre
			if not grain.has(cell):
				var g := r.randf()
				grain[cell] = r.randf_range(0.96, 1.03) if g < 0.8 else (r.randf_range(1.06, 1.1) if g < 0.9 else r.randf_range(0.87, 0.91))
			var v: float = grain[cell]
			var c := base
			var tyre := 0.0
			for bx in [-1.0, 1.4]:
				for wx in [-0.72, 0.72]:
					var d := absf(x - bx - wx)
					if d < 0.16 and z > -15.2:
						tyre = maxf(tyre, clampf((z + 15.2) / 2.0, 0.25, 1.0))
			if z > -11.0:  # the aisle, where every car turns in
				tyre = maxf(tyre, 0.45 + 0.25 * noise.get_noise_2d(x * 0.7, z * 0.7))
			v = lerpf(v, 0.84, tyre * 0.7)
			for bx in [-1.0, 1.4]:  # an oil stain under each engine, ragged at its edge
				var e := Vector2((x - bx) / 0.42, (z + 14.35) / 0.55).length() + 0.35 * noise.get_noise_2d(x * 3.0, z * 3.0)
				if e < 1.0:
					c = c.lerp(Color("2c2f38"), 0.55 * (1.0 - e * e))
			if z < -15.75 or x > 3.45:
				c = c.lerp(Color("8d8577"), 0.35 + 0.25 * noise.get_noise_2d(x * 2.0, z * 2.0))
			var col := Color(c.r * v, c.g * v, c.b * v)
			var at := Vector2(x, z)
			if lines.any(func(l: Rect2): return l.has_point(at)) or Geometry2D.is_point_in_polygon(at, head):
				var wear := 0.03 + tyre * 0.22 + (0.12 if z > -12.0 and z < -11.0 else 0.0) + 0.2 * noise.get_noise_2d(x * 4.0, z * 4.0)
				if r.randf() > wear:
					col = paint.lerp(col, clampf(wear, 0.0, 0.5))
			img.set_pixel(px, py, col)
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	car_park_m = m
	return m


## The shop floor, 0.5 m vinyl tiles each a shade off the next under bevelled grout, polished to a sheen under the
## ceiling lights over each aisle, scuffed grey where the traffic runs (in at the door, along the queue and the cross
## aisle) and shaded where it meets the walls and the counter.
func shop_floor(zl: float, a: Color, b: Color) -> ImageTexture:
	const PX := 24
	var wpx := roundi((6.5 - zl) * PX)
	var img := Image.create(wpx, 9 * PX, false, Image.FORMAT_RGB8)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var shade := {}
	var mid := (zl + 6.5) / 2.0
	var lanes: Array = [Rect2(4.6, 3.6, 0.0, 0.9), Rect2(3.5, -2.5, 0.0, 6.1), Rect2(Sim.AISLE_COLUMN, -2.3, 0.0, 5.9), Rect2(zl + 0.6, 3.3, 4.0 - zl, 0.0)]
	var counter := Rect2(4.075, -3.4, 0.85, 5.3)
	for py in img.get_height():
		var z := (py + 0.5) / PX - 4.5
		for px in wpx:
			var x := zl + (px + 0.5) / PX
			var t := Vector2i(floori(x * 2.0 + 20.0), floori(z * 2.0 + 20.0))
			if not shade.has(t):
				shade[t] = r.randf_range(-0.03, 0.03)
			var sh: float = shade[t]
			var c := a.lightened(sh) if sh > 0.0 else a.darkened(-sh)
			var gx := posmod(px, PX / 2)
			var gy := posmod(py, PX / 2)
			if gx == PX / 2 - 1 or gy == PX / 2 - 1:
				c = c.lerp(b, 0.75)
			elif gx == 0 or gy == 0:
				c = c.lightened(0.12)
			elif r.randf() < 0.02:
				c = c.darkened(0.08)
			for row in Sim.ROWS:
				var d := Vector2((x - mid) / ((6.5 - zl) * 0.45), (z - row) / 0.38)
				c = c.lerp(Color("fffdf6"), 0.7 * clampf(1.0 - d.length_squared(), 0.0, 1.0))
			for ln in lanes:
				var dd := Vector2(x - clampf(x, ln.position.x, ln.end.x), z - clampf(z, ln.position.y, ln.end.y)).length()
				if dd < 0.5:
					c = c.lerp(Color("aa9f8c"), 0.3 * (1.0 - dd / 0.5) * (0.7 + 0.3 * r.randf()))
			var near := minf(minf(x - zl, z + 4.5), Vector2(x - clampf(x, counter.position.x, counter.end.x), z - clampf(z, counter.position.y, counter.end.y)).length())
			if near < 0.4:
				c = c.darkened(0.2 * pow(1.0 - near / 0.4, 2.0))
			img.set_pixel(px, py, c)
	return ImageTexture.create_from_image(img)


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


## The car park's plate in pixels: a white P on blue inside a white rule, as on the pole of every konbini lot.
func park_face() -> ImageTexture:
	if plate_tex:
		return plate_tex
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(Color("2a62b8"))
	for e in [Rect2i(1, 1, 14, 1), Rect2i(1, 14, 14, 1), Rect2i(1, 1, 1, 14), Rect2i(14, 1, 1, 14)]:
		img.fill_rect(e, Color("f4f6f8"))
	for e in [Rect2i(5, 4, 2, 9), Rect2i(5, 4, 5, 2), Rect2i(5, 8, 5, 2), Rect2i(9, 5, 2, 4)]:
		img.fill_rect(e, Color("f4f6f8"))
	plate_tex = ImageTexture.create_from_image(img)
	return plate_tex


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
	# well under the farmland: across this one quad 6 km wide, software WebGL lost the 5 mm the fields once stood above
	# it and tore them into wedges and slivers
	plane(city, Vector2(6000, 6000), Vector3(mid.x, -0.4, mid.y), grass)
	# farmland round the city: a patchwork of furrowed fields with grass between, kept off the roads and the shore
	var furrows := Image.create(4, 4, false, Image.FORMAT_RGB8)
	furrows.fill(Color.WHITE)
	furrows.fill_rect(Rect2i(0, 0, 1, 4), Color(0.84, 0.86, 0.78))
	furrows.generate_mipmaps()
	var fm := ShaderMaterial.new()
	fm.shader = Shader.new()
	fm.shader.code = FIELD_SHADER
	fm.set_shader_parameter("furrows", ImageTexture.create_from_image(furrows))
	fm.set_shader_parameter("light", Vector3(light.r, light.g, light.b))
	fm.set_shader_parameter("night", maxf(night, 0.0))
	field_mat = fm
	var fs := surface(fm)
	var fr := RandomNumberGenerator.new()
	fr.seed = 5
	var fb := b.grow(1300.0)
	# neighbouring fields mostly share a crop, so the farmland reads as broad patches of one colour rather than a
	# checkerboard; each field still takes its own shade
	var crops := {}
	var fw8 := PackedFloat32Array(FIELD_WEIGHTS)
	var fy := fb.position.y
	while fy < fb.end.y:
		var fh := fr.randf_range(14.0, 26.0)
		var fx := fb.position.x - fr.randf_range(0.0, 20.0)
		while fx < fb.end.x:
			var fw := fr.randf_range(16.0, 36.0)
			var r := Rect2(fx, fy, fw, fh).grow(-0.9)
			if country(r.grow(12.0), 16.0):
				var along := fr.randf() < 0.5
				var at := r.get_center() + Vector2(fr.randf_range(-40.0, 40.0), fr.randf_range(-40.0, 40.0))
				var cell := Vector2i((at / 110.0).floor())
				if not crops.has(cell):
					crops[cell] = fr.rand_weighted(fw8)
				var crop: int = crops[cell] if fr.randf() < 0.75 else fr.rand_weighted(fw8)
				var shade := fr.randf_range(-0.06, 0.06)
				var fc := Color(FIELDS[crop])
				fs.set_color(fc.lightened(shade) if shade > 0.0 else fc.darkened(-shade))
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
	sea.albedo_color = light * Color.WHITE.lerp(SEA_NIGHT, night)
	sea_mat = sea
	swell_mat = ShaderMaterial.new()
	swell_mat.shader = Shader.new()
	swell_mat.shader.code = SWELL_SHADER
	swell_mat.set_shader_parameter("sea", Vector3(SEA.r, SEA.g, SEA.b))
	swell_mat.set_shader_parameter("light", Vector3(sea.albedo_color.r, sea.albedo_color.g, sea.albedo_color.b))
	var ws := surface(swell_mat)
	poly_fill(ws, C.bay, -0.14)
	poly_fill(ws, bay_mouth, -0.14)
	for poly in C.river:
		poly_fill(ws, poly, -0.14)
	for p in moat_ring(C.parks[0]):
		ws.set_uv(p * 0.125)
		ws.add_vertex(Vector3(p.x, -0.14, p.y))
	var land := surface(ground_mat(paving()))  # paved like the blocks it covers, rather than a bare sheet
	land.set_color(Color(Sim.City.GROUND.hub))
	for isl in C.islands:
		poly_fill(land, isl, -0.135, 0.25)
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
	rails = []
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
				rails.append([PackedVector3Array([pt.call(br[0] - 1.0), pt.call(br[1] + 1.0)]), side, 0])
		for e in 2:
			if s.quay[e]:
				var x: float = s.from + 0.1 if e == 0 else s.to - 0.1
				rails.append([PackedVector3Array([pt.call(x, -s.w / 2), pt.call(x, s.w / 2)]), 0.0, 0])
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
					for k in range(run, i):
						rails.append([pts, side, k])
				run = -1
	commit([walkway, tar, mouth, dash, solid, zebra], city)
	rail_node = commit([], city)
	rail_sig = Rect2(1, 1, -1, -1)
	build_rails([])


## The city's railings, leaving out every piece that crosses one of `clear` (the set's street and buildings), where
## the set lays its own ground and quays over the city's.
func build_rails(clear: Array) -> void:
	var rail := surface(mat(Color("d9d4c7")))
	var any := false
	for r in rails:
		var pts: PackedVector3Array = r[0]
		var a := Vector2(pts[r[2]].x, pts[r[2]].z)
		var b := Vector2(pts[r[2] + 1].x, pts[r[2] + 1].z)
		if not clear.any(func(q): return seg_hits(q, a, b)):
			wall(rail, pts, r[1], -0.12, 0.55, r[2], r[2] + 1)
			any = true
	var mesh := ArrayMesh.new()
	if any:
		rail.commit(mesh)
	rail_node.mesh = mesh


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


## A box from corner p0 to p1 into a vertex-coloured surface, each face in the house's three tones of col.
func box_into(st: SurfaceTool, p0: Vector3, p1: Vector3, col: Color) -> void:
	var c := (p0 + p1) / 2
	var h := (p1 - p0).abs() / 2
	for fc in [[Vector3.UP, 1.0], [Vector3.BACK, 0.9], [Vector3.LEFT, 0.9], [Vector3.RIGHT, 0.75], [Vector3.FORWARD, 0.75]]:
		var fn: Vector3 = fc[0]
		var u := Vector3.UP if absf(fn.y) < 0.5 else Vector3.RIGHT
		var v := fn.cross(u)
		var ctr := c + fn * absf(fn.dot(h))
		var hu := u * absf(u.dot(h))
		var hv := v * absf(v.dot(h))
		st.set_color(Color(col.r * fc[1], col.g * fc[1], col.b * fc[1]))
		add_quad(st, [ctr - hu - hv, ctr + hu - hv, ctr + hu + hv, ctr - hu + hv], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])


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
	building_mat.set_shader_parameter("snow_tex", snow_tex)
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
	if rail_node and front != rail_sig:
		rail_sig = front
		build_rails([front] + set_feet if on else [])
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
		node.add_child(foot())
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


## A person's shadow at the feet of a sprite standing sc tall: a contact patch and its cast away from the sun.
func foot(sc := 1.0) -> MeshInstance3D:
	var sh := MeshInstance3D.new()
	sh.mesh = foot_mesh
	sh.material_override = foot_mat
	sh.position = Vector3(0, 0.04 - 0.82 * sc, 0)
	sh.rotation.y = atan2(-SUN.x, -SUN.z)
	sh.scale = Vector3.ONE * sc
	return sh


## The same soft shadow on the set's ground, for street furniture.
func blob(parent: Node3D, at: Vector2, r: float) -> void:
	plane(parent, Vector2(r, r) * 2.0, Vector3(at.x, -0.035, at.y), soft_mat)


## The sun's shadow of whatever stands w wide between heights h0 and h1 over `at`, laid along the ground away from
## SUN (as the city's buildings cast theirs), lengthening through golden hour.
func cast(parent: Node3D, at: Vector2, h0: float, h1: float, w: float, round := false) -> void:
	var d := Vector2(-SUN.x, -SUN.z) / SUN.y
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, (h1 - h0) * d.length())
	pm.center_offset = Vector3(0, 0, (h0 + h1) / 2 * d.length())
	mi.mesh = pm
	mi.material_override = crown_mat if round else cast_mat
	mi.position = Vector3(at.x, -0.033, at.y)
	mi.rotation.y = atan2(d.x, d.y)
	mi.scale.z = 1.0 + 0.9 * golden_at(sim.hour())
	parent.add_child(mi)
	casts.append(mi)


## The sun's shadow of art/outdoor.png prop `id` standing at `at`, drawn at scale k of its sheet cell.
func outdoor_cast(parent: Node3D, id: int, at: Vector2, k: float) -> void:
	var size: float = OUTDOOR * OUTDOOR_PX * k
	for c in OUTDOOR_CAST[id]:
		cast(parent, at, c[0] * size, c[1] * size, c[2] * size, c.size() > 3)


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
## Whether the set's street runs on into the city at its end toward `dir` (else it stops at a quay).
func street_open(dir: float) -> bool:
	return street_x.y == SET.end.x if dir > 0.0 else street_x.x == SET.position.x


func street_traffic(delta: float) -> void:
	delta = minf(delta, 0.5)
	var lt: Array = sim.lights()
	var held: bool = lt[0] or lt[2]
	next_set_car -= delta * (Sim.band(sim.hour()).traffic / 1.2 if sim.phase == "playing" else 1.0)
	if next_set_car <= 0.0:
		next_set_car = randf_range(1.5, 4.0)
		var dir := 1.0 if randf() < 0.5 else -1.0
		# cars come in off the city at an open end of the street; where both its ends are quays, from a side road
		if not street_open(-dir) and street_open(dir):
			dir = -dir
		var x0 := SET.position.x if dir > 0.0 else SET.end.x
		if not street_open(-dir):
			x0 = INF if entries.is_empty() else entries[randi() % entries.size()]
		if x0 < INF and not set_cars.any(func(o): return o.dir == dir and absf(o.x - x0) < 8.0):
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
			set_cars.append({"node": node, "x": x0, "v": cruise, "dir": dir, "cruise": cruise, "kv": kv, "turn": -1.0, "back": false})
	var gone := []
	for o in set_cars:
		if o.turn >= 0.0:  # turning round short of a quay: a half circle from its lane into the other one
			o.turn = minf(o.turn + 3.0 * delta / 1.7, PI)
			var t := Vector3(o.dir * cos(o.turn), 0, o.dir * sin(o.turn))
			o.node.position = Vector3(o.x + o.dir * 1.7 * sin(o.turn), o.node.position.y, -o.dir * 1.7 * cos(o.turn))
			if o.turn >= PI:
				o.dir = -o.dir
				o.turn = -1.0
				o.back = true
				o.v = 3.0
				t = Vector3(o.dir, 0, 0)
			facing(o.node, t, o.kv * 2, VEHICLE_CELL)
			var beam: Node3D = o.node.get_child(1)
			beam.position = Vector3(t.x * 3.2, beam.position.y, t.z * 3.2)
			shine(o.node)
			continue
		var room_ := INF
		for q in set_cars:
			if q != o and q.dir == o.dir and (q.x - o.x) * o.dir > 0.0:
				room_ = minf(room_, (q.x - o.x) * o.dir - 5.5)
		var line: float = (Sim.CROSS_X - 4.0 * o.dir - o.x) * o.dir  # the car's centre to its stop line
		if held and line > -0.2:
			room_ = minf(room_, line)
		var turn_at: float = (street_x.y if o.dir > 0.0 else street_x.x) - o.dir * 4.0
		if not street_open(o.dir):
			room_ = minf(room_, (turn_at - o.x) * o.dir + 2.5)  # slow for the turn
		o.v = minf(move_toward(o.v, o.cruise, 4.0 * delta), maxf(room_, 0.0) * 1.2)
		var was: float = o.x
		o.x += o.dir * o.v * delta
		o.node.position.x = o.x
		shine(o.node)
		if not street_open(o.dir) and (o.x - turn_at) * o.dir >= 0.0:
			o.x = turn_at
			o.turn = 0.0
		if o.x > SET.end.x or o.x < SET.position.x:
			gone.append(o)
		elif o.back and not street_open(o.dir) and entries.any(func(e): return (e - was) * (e - o.x) <= 0.0):
			gone.append(o)  # off down the side road it came in by
	for o in gone:
		o.node.queue_free()
	set_cars = set_cars.filter(func(o): return not gone.has(o))


## Settled snow for an 8 m repeat at 32 px a metre: drifts on seamless noise, a shaded lip where a drift's edge faces
## the street, powder dithered out round its rim, a crust of fine grain and the odd glint.
func snow_patches() -> ImageTexture:
	const N := 256
	var fn := FastNoiseLite.new()
	fn.seed = 23
	fn.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	var drifts := fn.get_seamless_image(N, N).get_data()
	fn.seed = 29
	fn.frequency = 0.25
	fn.fractal_octaves = 1
	var grain := fn.get_seamless_image(N, N).get_data()
	var bayer := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	for y in N:
		for x in N:
			var v := drifts[y * N + x] / 255.0
			var g := grain[y * N + x] / 255.0 - 0.5
			var c := Color(1, 1, 1, 0)
			if v > 0.5:
				var lip := 0
				for k in [1, 2, 3]:
					if lip == 0 and drifts[(y + k) % N * N + x] / 255.0 <= 0.5:
						lip = k
				c = Color(0.95, 0.97, 1.0, 0.94).darkened(0.05 * g)
				if lip > 0:
					c = Color(0.76, 0.82, 0.94, 0.94) if lip == 1 else Color(0.85, 0.89, 0.97, 0.94)
				elif drifts[(y + N - 1) % N * N + x] / 255.0 <= 0.5:
					c = Color(1, 1, 1, 0.96)  # the drift's crest, caught by the light
				elif g > 0.46:
					c = Color(1, 1, 1, 1)
			elif v > 0.42 and (v - 0.42) / 0.08 * 16.0 > bayer[y % 4 * 4 + x % 4] + g * 6.0:
				c = Color(0.88, 0.92, 0.99, 0.8)
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
	var span := rival_span(branch.rival)
	rect_quad(deep, Rect2(3.7, -20.2, span.x - 3.7, 13.0), -0.034, 0.0, false, 0.125)
	rect_quad(deep, Rect2(-16.5, -20.2, 20.2, 3.95), -0.034, 0.0, false, 0.125)
	rect_quad(deep, Rect2(span.x + 0.2, -16.0, span.y - span.x - 0.4, 8.6), 4.27, 0.0, false, 0.125)  # the rival's roof, round its kit
	for band in [Vector2(-3.7, -3.05), Vector2(-2.25, -1.55), Vector2(-0.45, 0.45), Vector2(1.55, 2.25), Vector2(3.05, 3.7)]:
		rect_quad(thin, Rect2(street_x.x, band.x, street_x.y - street_x.x, band.y - band.x), -0.034, 0.0, false, 0.125)
	var mi := commit([deep, thin], set_node)
	mi.visible = false
	return mi


## Summer Matsuri: paper lanterns, red and white, strung on sagging ropes between poles along both kerbs, glowing after
## dark. Not across your shopfront and car park, so the till stays in plain view. Built hidden.
func matsuri_lanterns(far_gaps: Array, near_gaps: Array) -> Node3D:
	var node := Node3D.new()
	node.visible = false
	set_node.add_child(node)
	var rope := surface(mat(Color("3b2f2b")))
	var spots := []
	var mine: float = Sim.ORIGIN.x + Sim.ZONE_LEFT[branch.store.size]
	for side in [[far_gaps + [Vector2(mine - 0.6, 4.3)], -4.65], [near_gaps, 4.65]]:
		var gaps: Array = side[0].duplicate()
		gaps.sort_custom(func(a, b2): return a.x < b2.x)
		for o in open_spans(gaps):
			if o.y - o.x < 3.4:
				continue
			var n: int = maxi(1, roundi((o.y - o.x - 0.8) / 6.5))
			var step: float = (o.y - o.x - 0.8) / n
			for k in n + 1:
				var px: float = o.x + 0.4 + k * step
				block(node, Vector3(0.08, 3.35, 0.08), Vector3(px, 1.675, side[1]), Color("b8955a"))
				block(node, Vector3(0.14, 0.06, 0.14), Vector3(px, 3.38, side[1]), Color("6b4a2e"))
				if k == 0:
					continue
				var sag := func(t: float) -> float: return 3.25 - 0.05 * step * 4.0 * t * (1.0 - t)
				var pts := PackedVector3Array()
				for i in 9:
					pts.append(Vector3(px - step + step * i / 8.0, sag.call(i / 8.0), side[1]))
				wall(rope, pts, 0.0, -0.014, 0.014)
				var m := maxi(2, roundi(step / 1.2))
				for j in m:
					var t: float = (j + 0.5) / m
					spots.append(Vector3(px - step + step * t, sag.call(t) - 0.36, side[1]))
	commit([rope], node)
	var ribs := Image.create(1, 16, false, Image.FORMAT_RGB8)
	for y in 16:  # bamboo ribs round the paper, darker toward the caps
		var v := absf(y - 7.5) / 7.5
		ribs.set_pixel(0, y, Color.WHITE * (lerpf(1.0, 0.72, v * v) * (0.8 if y % 3 == 1 else 1.0)))
	var body := SphereMesh.new()
	body.radius = 0.19
	body.height = 0.48
	body.radial_segments = 10
	body.rings = 6
	var bm := multimesh(body, spots.size(), true)
	var cm := multimesh(shaded_box(), spots.size() * 2, true)
	var gm := multimesh(QuadMesh.new(), spots.size())
	for i in spots.size():
		var at: Vector3 = spots[i]
		bm.set_instance_transform(i, Transform3D(Basis(), at))
		bm.set_instance_color(i, Color("d6402e") if i % 3 != 2 else Color("f4ead6"))
		for c in 2:
			cm.set_instance_transform(i * 2 + c, Transform3D(Basis().scaled(Vector3(0.21, 0.06, 0.21)), at + Vector3(0, 0.24 if c == 0 else -0.24, 0)))
			cm.set_instance_color(i * 2 + c, Color("2e2523"))
		gm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.25, 1.25, 1.25)), at))
	var paper := mat(Color.WHITE, ImageTexture.create_from_image(ribs))
	paper.vertex_color_use_as_albedo = true
	paper.vertex_color_is_srgb = true
	paper.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	light_up(paper, 1.0)
	mm_node(bm, paper, node)
	var cap := mat(Color.WHITE)
	cap.vertex_color_use_as_albedo = true
	cap.vertex_color_is_srgb = true
	mm_node(cm, cap, node)
	mm_node(gm, lantern_glow_mat, node)
	yatai(node, paper)
	return node


## A yakisoba yatai in your free bay, its counter to the street: a wooden frame under a red and white striped canopy, a
## noren of three cream panels, a red and white skirt round the counter, noodles on the griddle, red lanterns at the
## front corners and a bare bulb, lit after dark with their warm light thrown on the bay.
func yatai(node: Node3D, paper: StandardMaterial3D) -> void:
	var kit := mat(Color.WHITE)
	kit.vertex_color_use_as_albedo = true
	kit.vertex_color_is_srgb = true
	var st := surface(kit)
	var under := mat(Color.WHITE)  # what the bulb and lanterns light: the counter, its griddle and the noren
	under.vertex_color_use_as_albedo = true
	under.vertex_color_is_srgb = true
	light_up(under, 0.7)
	var lt := surface(under)
	var wood := Color("8a5a34")
	var red := Color("d6402e")
	var cream := Color("f4ead6")
	const X0 := -1.5
	const X1 := 0.4
	const ZB := -13.7  # the back
	const ZF := -11.35  # the counter's front
	for c in [Vector2(X0, ZB), Vector2(X1, ZB), Vector2(X0, ZF), Vector2(X1, ZF)]:
		box_into(st, Vector3(c.x, 0, c.y) + Vector3(-0.05, 0, -0.05), Vector3(c.x, 0, c.y) + Vector3(0.05, 2.3, 0.05), wood)
	box_into(st, Vector3(X0, 0.05, ZB), Vector3(X1, 0.85, ZB + 0.06), wood.darkened(0.15))  # the back board
	# the counter, skirted in red and white stripes on the faces you see
	box_into(st, Vector3(X0 + 0.05, 0.05, ZF - 0.5), Vector3(X1 - 0.05, 0.9, ZF), Color("b8955a"))
	var n := 8
	for k in n:
		var x := lerpf(X0 + 0.05, X1 - 0.05, float(k) / n)
		box_into(st, Vector3(x, 0.08, ZF), Vector3(x + (X1 - X0 - 0.1) / n, 0.86, ZF + 0.02), red if k % 2 == 0 else cream)
	for k in 6:
		var z := lerpf(ZB + 0.06, ZF, float(k) / 6)
		box_into(st, Vector3(X1, 0.08, z), Vector3(X1 + 0.02, 0.86, z + (ZF - ZB - 0.06) / 6), cream if k % 2 == 0 else red)
	box_into(lt, Vector3(X0 - 0.02, 0.9, ZF - 0.58), Vector3(X1 + 0.04, 0.96, ZF + 0.1), Color("c9a26b"))
	# the griddle with its noodles, cabbage and pickled ginger, a squeeze bottle and a stack of trays
	box_into(lt, Vector3(X0 + 0.25, 0.96, ZF - 0.48), Vector3(X1 - 0.75, 1.0, ZF - 0.04), Color("2b2c30"))
	for lump in [[0.3, 0.22, Color("c98a45")], [0.62, 0.3, Color("b5773a")], [0.48, 0.12, Color("6aa84f")], [0.8, 0.16, Color("e0607a")]]:
		var lx: float = X0 + 0.25 + lump[0]
		box_into(lt, Vector3(lx - 0.09, 1.0, ZF - 0.36), Vector3(lx + 0.09, 1.04, ZF - 0.36 + lump[1]), lump[2])
	box_into(lt, Vector3(X1 - 0.6, 0.96, ZF - 0.35), Vector3(X1 - 0.3, 1.06, ZF - 0.12), cream)
	box_into(lt, Vector3(X1 - 0.22, 0.96, ZF - 0.3), Vector3(X1 - 0.14, 1.18, ZF - 0.22), Color("e2a63a"))
	box_into(st, Vector3(X0 + 0.3, 0.05, ZB + 0.3), Vector3(X0 + 0.9, 0.5, ZB + 0.75), Color("3f6fb8"))  # a cool box
	box_into(st, Vector3(X0 + 0.28, 0.5, ZB + 0.28), Vector3(X0 + 0.92, 0.56, ZB + 0.77), Color("fbfaf5"))
	# the canopy, striped front to back, and the noren hung from its front edge
	var m := 6
	for k in m:
		var x := lerpf(X0 - 0.12, X1 + 0.12, float(k) / m)
		box_into(st, Vector3(x, 2.3, ZB - 0.15), Vector3(x + (X1 - X0 + 0.24) / m, 2.38, ZF + 0.3), red if k % 2 == 0 else cream)
	box_into(st, Vector3(X0 - 0.12, 2.18, ZF + 0.26), Vector3(X1 + 0.12, 2.3, ZF + 0.3), red)
	for k in 3:
		var x := lerpf(X0 + 0.02, X1 - 0.02, float(k) / 3)
		box_into(lt, Vector3(x + 0.02, 1.72, ZF + 0.22), Vector3(x + (X1 - X0 - 0.04) / 3 - 0.02, 2.18, ZF + 0.25), cream)
		box_into(lt, Vector3(x + 0.02, 2.06, ZF + 0.25), Vector3(x + (X1 - X0 - 0.04) / 3 - 0.02, 2.12, ZF + 0.26), red)
		box_into(lt, Vector3(x + 0.2, 1.84, ZF + 0.25), Vector3(x + (X1 - X0 - 0.04) / 3 - 0.2, 1.98, ZF + 0.26), Color("8f2a22"))
	box_into(st, Vector3((X0 + X1) / 2 - 0.01, 1.98, ZF - 0.6), Vector3((X0 + X1) / 2 + 0.01, 2.3, ZF - 0.58), Color("3b2f2b"))
	for c in [X0, X1]:  # a lantern's cord at each front corner
		box_into(st, Vector3(c - 0.01, 1.8, ZF + 0.33), Vector3(c + 0.01, 2.3, ZF + 0.35), Color("3b2f2b"))
	commit([st, lt], node)
	var hung := [Vector3(X0, 1.56, ZF + 0.34), Vector3(X1, 1.56, ZF + 0.34)]
	var bulb := Vector3((X0 + X1) / 2, 1.92, ZF - 0.59)
	var body := SphereMesh.new()
	body.radius = 0.17
	body.height = 0.44
	body.radial_segments = 10
	body.rings = 6
	var bm := multimesh(body, hung.size(), true)
	for i in hung.size():
		bm.set_instance_transform(i, Transform3D(Basis(), hung[i]))
		bm.set_instance_color(i, Color("d6402e"))
	mm_node(bm, paper, node)
	var bl := MeshInstance3D.new()
	bl.mesh = shaded_box()
	bl.scale = Vector3(0.09, 0.11, 0.09)
	bl.position = bulb
	var lm := mat(Color("fff1c8"))
	light_up(lm, 1.0)
	bl.material_override = lm
	node.add_child(bl)
	var gm := multimesh(QuadMesh.new(), hung.size() + 1)
	for i in hung.size():
		gm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.2, 1.2, 1.2)), hung[i]))
	gm.set_instance_transform(hung.size(), Transform3D(Basis().scaled(Vector3(1.6, 1.6, 1.6)), bulb))
	mm_node(gm, lantern_glow_mat, node)
	plane(node, Vector2(4.4, 4.4), Vector3((X0 + X1) / 2, -0.031, ZF + 0.4), stall_glow_mat)
	plane(node, Vector2(2.4, 2.4), Vector3((X0 + X1) / 2, -0.03, ZF - 0.4), stall_glow_mat)
	cast(node, Vector2((X0 + X1) / 2, (ZB + ZF) / 2), 0.0, 2.38, 2.1)
	blob(node, Vector2((X0 + X1) / 2, (ZB + ZF) / 2), 1.5)


## Roadworks: a stretch of the near kerb lane fenced off with striped barricades, cones on a striped bar, steel plates
## over a trench, and an arrow board turning traffic out; their red lamps and the arrow flash after dark. Built hidden.
func roadworks(near_gaps: Array) -> Node3D:
	var node := Node3D.new()
	node.visible = false
	set_node.add_child(node)
	var gaps: Array = near_gaps.duplicate()
	gaps.sort_custom(func(a, b2): return a.x < b2.x)
	const L := 7.6
	var x0 := INF
	for o in open_spans(gaps):  # the clear kerb nearest the middle of the view, off the crossing
		for run in [Vector2(o.x + 1.4, minf(o.y - 2.4, Sim.CROSS_X - 4.8)), Vector2(maxf(o.x + 1.4, Sim.CROSS_X + 3.2), o.y - 2.4)]:
			if run.y - run.x >= L:
				var at := clampf(-7.0 - L / 2, run.x, run.y - L)
				if x0 == INF or absf(at + L / 2 + 7.0) < absf(x0 + L / 2 + 7.0):
					x0 = at
	if x0 == INF:
		return node
	var x1 := x0 + L
	var kit := mat(Color.WHITE)
	kit.vertex_color_use_as_albedo = true
	kit.vertex_color_is_srgb = true
	var st := surface(kit)
	var plate := Color("7f8388")
	var bar := func(a: Vector3, b2: Vector3, h: float, seg: float) -> void:  # a yellow and black striped rail from a to b2
		var n := maxi(1, roundi(a.distance_to(b2) / seg))
		for i in n:
			var p := a.lerp(b2, float(i) / n)
			var q := a.lerp(b2, float(i + 1) / n)
			box_into(st, Vector3(minf(p.x, q.x), p.y - h / 2, minf(p.z, q.z)) - Vector3(0.025, 0, 0.025),
				Vector3(maxf(p.x, q.x), p.y + h / 2, maxf(p.z, q.z)) + Vector3(0.025, 0, 0.025), Color("f2c230") if i % 2 == 0 else Color("2b2a2c"))
	# the dug lane: steel road plates with their seams, a trench left open and a patch of fresh black tarmac
	box_into(st, Vector3(x0 + 0.9, -0.045, 2.75), Vector3(x0 + 4.6, -0.02, 3.5), plate)
	for k in 4:
		box_into(st, Vector3(x0 + 1.8 + k * 0.92, -0.045, 2.75), Vector3(x0 + 1.84 + k * 0.92, -0.016, 3.5), plate.darkened(0.35))
	box_into(st, Vector3(x0 + 4.6, -0.045, 2.75), Vector3(x0 + 5.7, -0.03, 3.5), Color("8a6440"))
	box_into(st, Vector3(x0 + 4.8, -0.045, 2.88), Vector3(x0 + 5.5, -0.025, 3.37), Color("3e2c20"))
	box_into(st, Vector3(x0 + 5.7, -0.045, 2.7), Vector3(x1 - 0.8, -0.03, 3.52), Color("2f3135"))
	for b in [x0 + 0.35, x1 - 0.35]:  # a barricade across each end, two striped boards on white legs, a lamp on top
		for z in [2.62, 3.48]:
			box_into(st, Vector3(b - 0.04, -0.04, z - 0.04), Vector3(b + 0.04, 0.95, z + 0.04), Color("eceae4"))
			box_into(st, Vector3(b - 0.16, -0.04, z - 0.1), Vector3(b + 0.16, 0.03, z + 0.1), Color("3a3a3e"))
		bar.call(Vector3(b, 0.8, 2.58), Vector3(b, 0.8, 3.52), 0.2, 0.16)
		bar.call(Vector3(b, 0.4, 2.58), Vector3(b, 0.4, 3.52), 0.14, 0.16)
	var cones := []
	var cx := x0 + 1.4
	while cx < x1 - 0.9:
		cones.append(Vector3(cx, 0.0, 2.58))
		cx += 1.15
	for i in cones.size():  # bases, and the striped bar resting in the cones' tops
		box_into(st, cones[i] + Vector3(-0.2, -0.045, -0.2), cones[i] + Vector3(0.2, 0.0, 0.2), Color("2b2a2c"))
		if i > 0:
			bar.call(cones[i - 1] + Vector3(0, 0.6, 0), cones[i] + Vector3(0, 0.6, 0), 0.06, 0.2)
	bar.call(Vector3(x0 + 0.35, 0.6, 2.58), cones[0] + Vector3(0, 0.6, 0), 0.06, 0.2)
	bar.call(cones[-1] + Vector3(0, 0.6, 0), Vector3(x1 - 0.35, 0.6, 2.58), 0.06, 0.2)
	# the arrow board on its trailer stand, out ahead of the works where oncoming cars meet it
	var ab := x1 + 0.7
	box_into(st, Vector3(ab - 0.35, -0.04, 2.85), Vector3(ab + 0.35, 0.3, 3.4), Color("d9c25a"))
	box_into(st, Vector3(ab - 0.04, 0.35, 3.08), Vector3(ab + 0.04, 1.1, 3.16), Color("5a5d63"))
	box_into(st, Vector3(ab - 0.06, 1.1, 2.6), Vector3(ab + 0.06, 2.12, 3.64), Color("2b2a2c"))
	commit([st], node)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 0.16
	cone.height = 0.7
	cone.radial_segments = 8
	cone.rings = 1
	var band := CylinderMesh.new()
	band.top_radius = 0.085
	band.bottom_radius = 0.105
	band.height = 0.14
	band.radial_segments = 8
	band.rings = 1
	var lamps: Array = [Vector3(x0 + 0.35, 0.98, 3.05), Vector3(x1 - 0.35, 0.98, 3.05)]
	var cm := multimesh(cone, cones.size(), true)
	var bm := multimesh(band, cones.size(), true)
	for i in cones.size():
		cm.set_instance_transform(i, Transform3D(Basis(), cones[i] + Vector3(0, 0.35, 0)))
		cm.set_instance_color(i, Color("f0662a"))
		bm.set_instance_transform(i, Transform3D(Basis(), cones[i] + Vector3(0, 0.38, 0)))
		bm.set_instance_color(i, Color("f4f1ea"))
	var paint := mat(Color.WHITE)
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	mm_node(cm, paint, node)
	mm_node(bm, paint, node)
	var lm := multimesh(shaded_box(), lamps.size())
	for i in lamps.size():
		lm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(0.12, 0.1, 0.12)), lamps[i]))
	var lamp := mat(Color("e8392c"))
	light_up(lamp, 1.0)
	mm_node(lm, lamp, node)
	# the board's face: amber chevrons pointing traffic away from the kerb, lit like a sign
	var img := Image.create(12, 12, false, Image.FORMAT_RGB8)
	img.fill(Color("1d1c20"))
	for y in range(2, 10):
		for tip in [6, 10]:
			for w in 2:
				img.set_pixel(tip - w - absi(y * 2 - 11) / 2, y, Color("ffb52e"))
	var face := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.96, 0.92)
	face.mesh = fq
	var fm := mat(Color.WHITE, ImageTexture.create_from_image(img))
	light_up(fm, 1.0)
	face.material_override = fm
	face.rotation.y = PI / 2
	face.position = Vector3(ab + 0.065, 1.61, 3.12)
	node.add_child(face)
	var gm := multimesh(QuadMesh.new(), lamps.size() + 1)
	for i in lamps.size():
		gm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.2, 1.2, 1.2)), lamps[i]))
	gm.set_instance_transform(lamps.size(), Transform3D(Basis().scaled(Vector3(2.2, 2.2, 2.2)), Vector3(ab + 0.2, 1.61, 3.12)))
	mm_node(gm, works_glow_mat, node)
	cast(node, Vector2(ab, 3.12), 1.1, 2.12, 1.0)
	return node


## TV Feature: an outside-broadcast van in the station's livery backed into your free bay with a dish on its roof, a
## camera on a tripod at the kerb and a light on a stand by the shopfront, both on your door; the camera's red tally
## and the light glow after dark. Built hidden.
func tv_crew() -> Node3D:
	var node := Node3D.new()
	node.visible = false
	set_node.add_child(node)
	var kit := mat(Color.WHITE)
	kit.vertex_color_use_as_albedo = true
	kit.vertex_color_is_srgb = true
	var st := surface(kit)
	var body := Color("f1efe8")
	var dark := Color("2b2c30")
	var glass := Color("33414f")
	var blue := Color("2f6fd0")
	# the van, nose to the street: a high box with a stepped bonnet, wheels showing under its skirt, the station's
	# blue band and orange pinstripe right round it and its badge on the side you see
	box_into(st, Vector3(-1.88, 0.0, -14.75), Vector3(-0.12, 0.55, -14.05), Color("232326"))
	box_into(st, Vector3(-1.88, 0.0, -12.35), Vector3(-0.12, 0.55, -11.65), Color("232326"))
	box_into(st, Vector3(-1.85, 0.3, -15.25), Vector3(-0.15, 2.0, -11.6), body)
	box_into(st, Vector3(-1.85, 0.3, -11.6), Vector3(-0.15, 1.12, -11.05), body)
	box_into(st, Vector3(-1.87, 0.72, -15.27), Vector3(-0.13, 1.0, -11.03), blue)
	box_into(st, Vector3(-1.87, 1.0, -15.27), Vector3(-0.13, 1.07, -11.6), Color("f08a24"))
	box_into(st, Vector3(-1.75, 1.18, -11.63), Vector3(-0.25, 1.88, -11.57), glass)
	for x in [-1.88, -0.14]:
		box_into(st, Vector3(x, 1.24, -12.45), Vector3(x + 0.02, 1.86, -11.75), glass)
	box_into(st, Vector3(-1.86, 0.26, -11.06), Vector3(-0.14, 0.46, -10.96), Color("9aa0a6"))
	box_into(st, Vector3(-1.86, 0.26, -15.36), Vector3(-0.14, 0.46, -15.24), Color("9aa0a6"))
	for x in [-1.7, -0.3]:
		box_into(st, Vector3(x - 0.13, 0.8, -11.06), Vector3(x + 0.13, 0.92, -11.02), Color("fff3c4"))
	box_into(st, Vector3(-0.14, 1.28, -14.0), Vector3(-0.11, 1.86, -12.85), blue)
	box_into(st, Vector3(-0.11, 1.42, -13.68), Vector3(-0.1, 1.72, -13.17), Color("fbfaf5"))
	box_into(st, Vector3(-0.1, 1.51, -13.5), Vector3(-0.09, 1.63, -13.35), Color("e8392c"))
	for x in [-1.72, -0.28]:  # roof rails, a folded mast and the dish's turntable
		box_into(st, Vector3(x - 0.05, 2.0, -15.0), Vector3(x + 0.05, 2.07, -11.9), Color("8e9196"))
	box_into(st, Vector3(-1.52, 2.07, -14.9), Vector3(-1.36, 2.2, -12.2), Color("b9bcc0"))
	box_into(st, Vector3(-1.52, 2.07, -12.2), Vector3(-1.36, 2.24, -11.98), Color("e8392c"))
	box_into(st, Vector3(-0.95, 2.0, -14.3), Vector3(-0.55, 2.14, -13.9), Color("6e737d"))
	box_into(st, Vector3(-0.8, 2.14, -14.15), Vector3(-0.7, 2.42, -14.05), Color("6e737d"))
	# the camera at the kerb, aimed at your door: tripod legs on a spreader, a head, the body with its lens, hood and
	# viewfinder, a pan bar reaching back to the operator
	var cam_at := Vector3(-5.6, 0, -4.8)
	for leg in [Vector2(0, -0.32), Vector2(-0.28, 0.17), Vector2(0.28, 0.17)]:
		box_into(st, cam_at + Vector3(leg.x - 0.025, 0, leg.y - 0.025), cam_at + Vector3(leg.x + 0.025, 1.0, leg.y + 0.025), Color("3a3b40"))
		box_into(st, cam_at + Vector3(minf(leg.x, 0) - 0.02, 0.18, minf(leg.y, 0) - 0.02), cam_at + Vector3(maxf(leg.x, 0) + 0.02, 0.22, maxf(leg.y, 0) + 0.02), Color("3a3b40"))
	box_into(st, cam_at + Vector3(-0.12, 0.98, -0.12), cam_at + Vector3(0.12, 1.08, 0.12), Color("4a4b50"))
	box_into(st, cam_at + Vector3(-0.13, 1.08, -0.3), cam_at + Vector3(0.13, 1.38, 0.25), dark)
	box_into(st, cam_at + Vector3(-0.08, 1.13, -0.55), cam_at + Vector3(0.08, 1.31, -0.3), Color("18191b"))
	box_into(st, cam_at + Vector3(-0.12, 1.1, -0.63), cam_at + Vector3(0.12, 1.34, -0.55), Color("18191b"))
	box_into(st, cam_at + Vector3(-0.2, 1.3, -0.18), cam_at + Vector3(-0.13, 1.44, 0.05), Color("4a4b50"))
	box_into(st, cam_at + Vector3(0.1, 1.02, 0.25), cam_at + Vector3(0.14, 1.06, 0.62), Color("4a4b50"))
	box_into(st, cam_at + Vector3(-0.13, 1.2, -0.3), cam_at + Vector3(0.13, 1.25, 0.25), blue)
	# the light, on a stand against your shopfront left of the door: three feet, a pole and a framed soft panel
	# turned along the front to light whoever stands at the door
	var lt_at := Vector3(-8.4, 0, -6.1)
	for f in [Vector2(-0.3, 0), Vector2(0.15, -0.26), Vector2(0.15, 0.26)]:
		box_into(st, lt_at + Vector3(minf(f.x, 0) - 0.02, 0, minf(f.y, 0) - 0.02), lt_at + Vector3(maxf(f.x, 0) + 0.02, 0.05, maxf(f.y, 0) + 0.02), Color("3a3b40"))
	box_into(st, lt_at + Vector3(-0.025, 0, -0.025), lt_at + Vector3(0.025, 1.62, 0.025), Color("8e9196"))
	box_into(st, lt_at + Vector3(-0.1, 1.55, -0.42), lt_at + Vector3(0.0, 2.12, 0.42), dark)
	commit([st], node)
	var face := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.74, 0.47)
	face.mesh = fq
	var fm := mat(Color("fff4dc"))
	light_up(fm, 1.0)
	face.material_override = fm
	face.rotation.y = PI / 2
	face.position = lt_at + Vector3(0.01, 1.835, 0)
	node.add_child(face)
	var tally := MeshInstance3D.new()
	tally.mesh = shaded_box()
	tally.scale = Vector3(0.07, 0.06, 0.07)
	tally.position = cam_at + Vector3(0.08, 1.41, -0.24)
	var tm := mat(Color("e8392c"))
	light_up(tm, 1.0)
	tally.material_override = tm
	node.add_child(tally)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.5
	dm.bottom_radius = 0.42
	dm.height = 0.07
	dm.radial_segments = 16
	dm.rings = 1
	disc.mesh = dm
	disc.material_override = mat(Color("d9d8d2"))
	disc.basis = Basis(Vector3(1, 0, -1).normalized(), 0.8)
	disc.position = Vector3(-0.75, 2.55, -14.1)
	node.add_child(disc)
	var gm := multimesh(QuadMesh.new(), 2)
	gm.set_instance_transform(0, Transform3D(Basis().scaled(Vector3(2.4, 2.4, 2.4)), face.position))
	gm.set_instance_transform(1, Transform3D(Basis().scaled(Vector3(0.6, 0.6, 0.6)), tally.position))
	mm_node(gm, halo_mat, node)
	cast(node, Vector2(-1.0, -13.15), 0.3, 2.1, 1.7)
	cast(node, Vector2(cam_at.x, cam_at.z), 0.0, 1.4, 0.4)
	cast(node, Vector2(lt_at.x, lt_at.z), 1.55, 2.12, 0.84)
	cast(node, Vector2(lt_at.x, lt_at.z), 0.0, 1.55, 0.06)
	blob(node, Vector2(-1.0, -13.15), 1.6)
	blob(node, Vector2(cam_at.x, cam_at.z), 0.5)
	return node


## Health Inspection: the ward health centre's white wagon nosed into your free bay, a green band round it and a green
## cross on its roof sign, and a sanitiser stand set out by your door; the sign lights up after dark. Built hidden.
func health_check() -> Node3D:
	var node := Node3D.new()
	node.visible = false
	set_node.add_child(node)
	var kit := mat(Color.WHITE)
	kit.vertex_color_use_as_albedo = true
	kit.vertex_color_is_srgb = true
	var st := surface(kit)
	var body := Color("f4f3ee")
	var green := Color("2e9a5c")
	var glass := Color("33414f")
	var tyre := Color("232326")
	# a compact wagon, nose to the street: wheels under the skirt, a low bonnet, a glass house over the cabin and the
	# band along its sides, the centre's badge on the door you see
	for z in [-14.4, -12.1]:
		box_into(st, Vector3(-1.72, 0.0, z - 0.32), Vector3(-0.28, 0.5, z + 0.32), tyre)
	box_into(st, Vector3(-1.7, 0.26, -14.95), Vector3(-0.3, 0.92, -11.35), body)
	box_into(st, Vector3(-1.6, 0.92, -14.88), Vector3(-0.4, 1.5, -12.3), body)
	box_into(st, Vector3(-1.72, 0.58, -14.97), Vector3(-0.28, 0.72, -11.33), green)
	box_into(st, Vector3(-1.52, 0.97, -12.33), Vector3(-0.48, 1.43, -12.27), glass)
	box_into(st, Vector3(-1.52, 0.99, -14.91), Vector3(-0.48, 1.4, -14.85), glass)
	for x in [-1.62, -0.42]:  # side glass in two panes either side of a pillar
		box_into(st, Vector3(x - 0.02, 0.98, -14.72), Vector3(x + 0.04, 1.43, -13.62), glass)
		box_into(st, Vector3(x - 0.02, 0.98, -13.46), Vector3(x + 0.04, 1.43, -12.42), glass)
	box_into(st, Vector3(-1.72, 0.22, -11.38), Vector3(-0.28, 0.4, -11.28), Color("9aa0a6"))
	box_into(st, Vector3(-1.72, 0.22, -15.02), Vector3(-0.28, 0.4, -14.92), Color("9aa0a6"))
	for x in [-1.55, -0.45]:
		box_into(st, Vector3(x - 0.12, 0.74, -11.36), Vector3(x + 0.12, 0.84, -11.32), Color("fff3c4"))
	box_into(st, Vector3(-0.3, 0.76, -13.3), Vector3(-0.27, 0.9, -12.95), Color("fbfaf5"))
	box_into(st, Vector3(-0.27, 0.8, -13.18), Vector3(-0.26, 0.86, -13.07), green)
	# the roof sign on two feet, side-on like a taxi's lamp
	for z in [-13.85, -13.05]:
		box_into(st, Vector3(-1.04, 1.5, z - 0.05), Vector3(-0.96, 1.6, z + 0.05), Color("8e9196"))
	box_into(st, Vector3(-1.06, 1.6, -14.0), Vector3(-0.94, 1.95, -12.9), body)
	# the sanitiser stand right of your door: a weighted foot, a white post, the pump bottle on its tray and a green card
	var sa := Vector3(-3.4, 0, -6.55)
	box_into(st, sa + Vector3(-0.17, 0, -0.17), sa + Vector3(0.17, 0.05, 0.17), Color("3a3b40"))
	box_into(st, sa + Vector3(-0.03, 0.05, -0.03), sa + Vector3(0.03, 1.0, 0.03), Color("eceae4"))
	box_into(st, sa + Vector3(-0.13, 1.0, -0.11), sa + Vector3(0.13, 1.04, 0.11), Color("eceae4"))
	box_into(st, sa + Vector3(-0.06, 1.04, -0.06), sa + Vector3(0.06, 1.24, 0.06), Color("bfe3dc"))
	box_into(st, sa + Vector3(-0.025, 1.24, -0.025), sa + Vector3(0.025, 1.31, 0.025), Color("fbfaf5"))
	box_into(st, sa + Vector3(-0.025, 1.29, -0.025), sa + Vector3(0.025, 1.31, 0.09), Color("fbfaf5"))
	box_into(st, sa + Vector3(-0.12, 0.62, 0.03), sa + Vector3(0.12, 0.88, 0.05), green)
	box_into(st, sa + Vector3(-0.04, 0.72, 0.05), sa + Vector3(0.04, 0.78, 0.055), body)
	commit([st], node)
	# the sign's faces: a green cross on white, lit like a lightbox
	var img := Image.create(16, 10, false, Image.FORMAT_RGB8)
	img.fill(Color("fbfaf5"))
	img.fill_rect(Rect2i(7, 1, 2, 8), green)
	img.fill_rect(Rect2i(4, 4, 8, 2), green)
	var fm := mat(Color.WHITE, ImageTexture.create_from_image(img))
	light_up(fm, 1.0)
	var fq := QuadMesh.new()
	fq.size = Vector2(1.04, 0.3)
	for side in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		face.mesh = fq
		face.material_override = fm
		face.rotation.y = PI / 2 * side
		face.position = Vector3(-1.0 + 0.065 * side, 1.775, -13.45)
		node.add_child(face)
	var gm := multimesh(QuadMesh.new(), 1)
	gm.set_instance_transform(0, Transform3D(Basis().scaled(Vector3(1.8, 1.8, 1.8)), Vector3(-0.9, 1.775, -13.45)))
	mm_node(gm, halo_mat, node)
	cast(node, Vector2(-1.0, -13.15), 0.26, 1.6, 1.5)
	cast(node, Vector2(sa.x, sa.z), 0.0, 1.3, 0.12)
	blob(node, Vector2(-1.0, -13.15), 1.5)
	blob(node, Vector2(sa.x, sa.z), 0.3)
	return node


## Heatwave: a kakigōri stand in your free bay, a table under a striped parasol with the red shaved-ice machine, a
## bowl of ice and the syrups, a cool box of drinks on ice and a 氷 flag on its pole at the kerb end; the sidewalk at
## your door is splashed dark against the heat, the bucket and ladle left by the step. Built hidden.
func ice_stand() -> Node3D:
	var node := Node3D.new()
	node.visible = false
	set_node.add_child(node)
	var kit := mat(Color.WHITE)
	kit.vertex_color_use_as_albedo = true
	kit.vertex_color_is_srgb = true
	var st := surface(kit)
	var steel := Color("8e9196")
	var red := Color("d6402e")
	var blue := Color("2f6fd0")
	var white := Color("fbfaf5")
	var ice := Color("dff1f7")
	const X0 := -1.75
	const X1 := -0.35
	const ZB := -13.3
	const ZF := -12.3  # the table's front, to the street
	for c in [Vector2(X0 + 0.06, ZB + 0.06), Vector2(X1 - 0.06, ZB + 0.06), Vector2(X0 + 0.06, ZF - 0.06), Vector2(X1 - 0.06, ZF - 0.06)]:
		box_into(st, Vector3(c.x - 0.025, 0, c.y - 0.025), Vector3(c.x + 0.025, 0.72, c.y + 0.025), steel)
	box_into(st, Vector3(X0, 0.72, ZB), Vector3(X1, 0.76, ZF), Color("e9e4d8"))
	# a cloth over its front and the side you see, white with a blue hem of waves
	box_into(st, Vector3(X0, 0.3, ZF), Vector3(X1, 0.76, ZF + 0.02), white)
	box_into(st, Vector3(X1, 0.3, ZB), Vector3(X1 + 0.02, 0.76, ZF + 0.02), white)
	var n := 7
	for k in n:
		var x := lerpf(X0, X1, float(k) / n)
		box_into(st, Vector3(x, 0.3, ZF + 0.02), Vector3(x + (X1 - X0) / n, 0.42 if k % 2 == 0 else 0.38, ZF + 0.03), blue)
	for k in 5:
		var z := lerpf(ZB, ZF, float(k) / 5)
		box_into(st, Vector3(X1 + 0.02, 0.3, z), Vector3(X1 + 0.03, 0.42 if k % 2 == 0 else 0.38, z + (ZF - ZB) / 5), blue)
	# the shaved-ice machine: a cast red frame on a foot, the wheel and crank on top, a bowl of ice heaped under the blade
	var mx := X0 + 0.38
	var mz := (ZB + ZF) / 2
	box_into(st, Vector3(mx - 0.2, 0.76, mz - 0.17), Vector3(mx + 0.2, 0.8, mz + 0.17), red)
	box_into(st, Vector3(mx - 0.2, 0.8, mz - 0.17), Vector3(mx - 0.14, 1.28, mz - 0.11), red)
	box_into(st, Vector3(mx - 0.2, 0.8, mz + 0.11), Vector3(mx - 0.14, 1.28, mz + 0.17), red)
	box_into(st, Vector3(mx - 0.2, 1.1, mz - 0.17), Vector3(mx + 0.14, 1.16, mz + 0.17), red)
	box_into(st, Vector3(mx - 0.2, 1.28, mz - 0.17), Vector3(mx + 0.08, 1.33, mz + 0.17), red)
	box_into(st, Vector3(mx - 0.08, 1.33, mz - 0.13), Vector3(mx + 0.01, 1.46, mz + 0.13), Color("c9a24a"))
	box_into(st, Vector3(mx - 0.05, 1.46, mz - 0.02), Vector3(mx + 0.2, 1.49, mz + 0.02), Color("3b2f2b"))
	box_into(st, Vector3(mx + 0.17, 1.49, mz - 0.02), Vector3(mx + 0.21, 1.6, mz + 0.02), Color("3b2f2b"))
	box_into(st, Vector3(mx - 0.08, 0.8, mz - 0.09), Vector3(mx + 0.1, 0.86, mz + 0.09), Color("a9cdd6"))
	box_into(st, Vector3(mx - 0.06, 0.86, mz - 0.07), Vector3(mx + 0.08, 0.95, mz + 0.07), ice)
	box_into(st, Vector3(mx - 0.03, 0.95, mz - 0.04), Vector3(mx + 0.05, 1.0, mz + 0.04), ice)
	# the syrups in a row along the front, strawberry, melon, blue Hawaii and lemon, and a stack of cups
	var sx := X1 - 0.62
	for col in [Color("e2384a"), Color("4cbf56"), Color("2fa3e0"), Color("f2cf3a")]:
		box_into(st, Vector3(sx, 0.76, ZF - 0.2), Vector3(sx + 0.08, 0.98, ZF - 0.12), col)
		box_into(st, Vector3(sx + 0.02, 0.98, ZF - 0.18), Vector3(sx + 0.06, 1.03, ZF - 0.14), white)
		sx += 0.12
	box_into(st, Vector3(X1 - 0.24, 0.76, ZB + 0.2), Vector3(X1 - 0.12, 0.98, ZB + 0.32), white)
	# the parasol's pole through the table into a weighted base
	box_into(st, Vector3(-1.2, 0, -12.95), Vector3(-0.9, 0.1, -12.65), Color("4a4b50"))
	box_into(st, Vector3(-1.07, 0.1, -12.82), Vector3(-1.03, 2.32, -12.78), white)
	# the cool box on the kerb side of the table, lid off, its ice bristling with cans and bottles
	var c0 := Vector3(-1.9, 0, -12.0)
	var c1 := Vector3(-1.15, 0.5, -11.5)
	box_into(st, c0, c1, Color("f2f0ea"))
	box_into(st, Vector3(c0.x - 0.01, 0.34, c0.z - 0.01), Vector3(c1.x + 0.01, 0.42, c1.z + 0.01), blue)
	box_into(st, Vector3(c0.x + 0.05, 0.5, c0.z + 0.05), Vector3(c1.x - 0.05, 0.53, c1.z - 0.05), ice)
	var cans := [Color("e8392c"), Color("3fae49"), Color("f2f0ea"), Color("2f6fd0"), Color("f08a24"), Color("8fd0e8")]
	for i in 6:
		var at := Vector3(c0.x + 0.17 + (i % 3) * 0.2, 0.53, c0.z + 0.15 + (i / 3) * 0.2)
		box_into(st, at - Vector3(0.05, 0, 0.05), at + Vector3(0.05, 0.1 if i % 2 == 0 else 0.16, 0.05), cans[i])
	box_into(st, Vector3(c1.x + 0.04, 0, c0.z + 0.02), Vector3(c1.x + 0.1, 0.48, c1.z - 0.02), Color("2f6fd0"))  # its lid, leant against it
	# the flag's pole at the kerb end of the bay, an arm along its top
	var fp := Vector3(-2.05, 0, -11.15)
	box_into(st, fp + Vector3(-0.12, 0, -0.12), fp + Vector3(0.12, 0.12, 0.12), Color("4a4b50"))
	box_into(st, fp + Vector3(-0.025, 0, -0.025), fp + Vector3(0.025, 2.55, 0.025), Color("d8d2c4"))
	box_into(st, fp + Vector3(-0.02, 2.4, -0.6), fp + Vector3(0.02, 2.44, 0.0), Color("d8d2c4"))
	# the bucket and ladle by your door
	var bk := Vector3(-7.55, 0, -6.45)
	box_into(st, bk + Vector3(-0.15, 0, -0.15), bk + Vector3(0.15, 0.3, 0.15), Color("a8794a"))
	for y in [0.06, 0.22]:
		box_into(st, bk + Vector3(-0.16, y, -0.16), bk + Vector3(0.16, y + 0.03, 0.16), Color("3b2f2b"))
	box_into(st, bk + Vector3(-0.12, 0.26, -0.12), bk + Vector3(0.12, 0.28, 0.12), Color("6f9fb4"))
	box_into(st, bk + Vector3(-0.01, 0.28, -0.02), bk + Vector3(0.01, 0.62, 0.02), Color("c9a26b"))
	box_into(st, bk + Vector3(-0.06, 0.24, -0.06), bk + Vector3(0.06, 0.3, 0.06), Color("c9a26b"))
	commit([st], node)
	# the parasol: eight panels, blue and white
	var img := Image.create(8, 1, false, Image.FORMAT_RGB8)
	for i in 8:
		img.set_pixel(i, 0, blue if i % 2 == 0 else white)
	var top := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 1.3
	cm.height = 0.4
	cm.radial_segments = 8
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	top.mesh = cm
	top.material_override = mat(Color.WHITE, ImageTexture.create_from_image(img))
	top.position = Vector3(-1.05, 2.18, -12.8)
	node.add_child(top)
	# the flag: a red 氷 on white between a blue band and a hem of waves, hung from the arm
	var fl := Image.create(10, 30, false, Image.FORMAT_RGB8)
	fl.fill(white)
	fl.fill_rect(Rect2i(0, 0, 10, 3), blue)
	fl.fill_rect(Rect2i(0, 25, 10, 5), blue)
	for x in 10:
		fl.set_pixel(x, 24, blue if x % 4 < 2 else white)
		fl.set_pixel(x, 23, blue if x % 4 == 1 else white)
	var glyph := ["....#...", "#...#...", ".#..#.#.", "..####..", "..#.#.#.", ".#..#..#", "#...#...", "...##..."]
	for y in glyph.size():
		for x in 8:
			if glyph[y][x] == "#":
				fl.fill_rect(Rect2i(1 + x, 6 + y * 2, 1, 2), red)
	var fm := mat(Color.WHITE, ImageTexture.create_from_image(fl))
	var fq := QuadMesh.new()
	fq.size = Vector2(0.52, 1.56)
	for side in [1.0, -1.0]:
		var face := MeshInstance3D.new()
		face.mesh = fq
		face.material_override = fm
		face.rotation.y = PI / 2 * side
		face.position = fp + Vector3(0.01 * side, 1.6, -0.3)
		node.add_child(face)
	# the splashed sidewalk, darker where the water lies thickest
	var wet := mat(Color(0.18, 0.22, 0.3, 0.62), radial([Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)], [0.0, 0.45, 1.0]))
	wet.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	plane(node, Vector2(3.4, 1.5), Vector3(-5.5, -0.031, -5.95), wet)
	plane(node, Vector2(1.4, 1.0), Vector3(-7.5, -0.031, -5.6), wet)
	cast(node, Vector2(-1.05, -12.8), 1.98, 2.38, 2.5)
	cast(node, Vector2(-1.05, -12.8), 0.0, 1.98, 0.05)
	cast(node, Vector2(fp.x, fp.z - 0.3), 0.82, 2.44, 0.52)
	cast(node, Vector2(fp.x, fp.z), 0.0, 0.82, 0.05)
	blob(node, Vector2((X0 + X1) / 2, (ZB + ZF) / 2), 0.9)
	blob(node, Vector2(-1.5, -11.75), 0.5)
	blob(node, Vector2(bk.x, bk.z), 0.22)
	return node


## The block's garbage station: a green cage on a kerbed slab, its net walls showing the night's bags heaped inside
## under a hinged lid, the ward's collection-day board on a post at the sidewalk end and a crate of empties beside it.
func garbage_station(gs: Vector3) -> void:
	var kit := mat(Color.WHITE)
	kit.vertex_color_use_as_albedo = true
	kit.vertex_color_is_srgb = true
	var st := surface(kit)
	var frame := Color("2f5a3a")
	var h := Vector3(0.38, 0, 0.8)
	box_into(st, gs - h - Vector3(0.06, 0, 0.06), gs + h + Vector3(0.06, 0.07, 0.06), Color("b4afa4"))
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(-1, 0), Vector2(1, 0)]:
		var at := gs + Vector3(c.x * (h.x - 0.025), 0, c.y * (h.z - 0.025))
		box_into(st, at + Vector3(-0.025, 0.07, -0.025), at + Vector3(0.025, 0.9, 0.025), frame)
	for x in [-1, 1]:  # the top and foot rails along each side
		for y in [0.1, 0.88]:
			box_into(st, gs + Vector3(x * h.x - 0.02, y - 0.02, -h.z), gs + Vector3(x * h.x + 0.02, y + 0.02, h.z), frame)
	for z in [-1, 1]:
		box_into(st, gs + Vector3(-h.x, 0.86, z * h.z - 0.02), gs + Vector3(h.x, 0.9, z * h.z + 0.02), frame)
	# the bags heaped inside, each a lumpy sack with its neck tied off
	for bag in [[Vector3(-0.12, 0, -0.45), 0.5, Color("e9edf0")], [Vector3(0.13, 0, -0.38), 0.42, Color("d6e4ec")],
			[Vector3(-0.08, 0, 0.05), 0.46, Color("f1efe6")], [Vector3(0.14, 0, 0.42), 0.38, Color("e9edf0")], [Vector3(-0.15, 0, 0.5), 0.3, Color("efe3b4")]]:
		var bc: Vector3 = gs + bag[0] + Vector3(0, 0.07, 0)
		var r: float = bag[1] / 2
		box_into(st, bc + Vector3(-r, 0, -r), bc + Vector3(r, r * 1.3, r), bag[2])
		box_into(st, bc + Vector3(-r * 0.7, r * 1.3, -r * 0.7), bc + Vector3(r * 0.7, r * 1.75, r * 0.7), bag[2].darkened(0.04))
		box_into(st, bc + Vector3(-0.03, r * 1.75, -0.03), bc + Vector3(0.03, r * 1.75 + 0.07, 0.03), bag[2].darkened(0.2))
	# the lid, lipped over the frame, with a grab bar on the sidewalk end
	box_into(st, gs + Vector3(-h.x - 0.04, 0.9, -h.z - 0.04), gs + Vector3(h.x + 0.04, 0.95, h.z + 0.04), Color("4f8a5c"))
	box_into(st, gs + Vector3(-0.2, 0.86, h.z + 0.04), gs + Vector3(0.2, 0.9, h.z + 0.08), Color("c9c6be"))
	# the collection-day board: white, a blue header, a row of coloured days for burnables, plastics and cans
	var sp := gs + Vector3(-0.15, 0, h.z + 0.32)
	box_into(st, sp + Vector3(-0.03, 0, -0.03), sp + Vector3(0.03, 1.2, 0.03), Color("9aa0a6"))
	box_into(st, sp + Vector3(-0.28, 0.82, 0.03), sp + Vector3(0.28, 1.24, 0.05), Color("fbfaf5"))
	box_into(st, sp + Vector3(-0.28, 1.15, 0.05), sp + Vector3(0.28, 1.24, 0.055), Color("3f6fb8"))
	for k in 3:
		var row: Color = [Color("d8493a"), Color("2e9a5c"), Color("e2a63a")][k]
		var y := 1.08 - k * 0.085
		box_into(st, sp + Vector3(-0.23, y - 0.025, 0.05), sp + Vector3(-0.14, y + 0.025, 0.055), row)
		box_into(st, sp + Vector3(-0.1, y - 0.012, 0.05), sp + Vector3(0.22, y + 0.012, 0.055), Color("8a8780"))
	# a crate of empty bottles at the back end, their caps in rows
	var cr := gs + Vector3(0.05, 0, -h.z - 0.42)
	box_into(st, cr + Vector3(-0.25, 0, -0.2), cr + Vector3(0.25, 0.3, 0.2), Color("3f7fc4"))
	box_into(st, cr + Vector3(-0.22, 0.3, -0.17), cr + Vector3(0.22, 0.31, 0.17), Color("2c5c96"))
	for i in 4:
		for j in 3:
			var bt := cr + Vector3(-0.165 + i * 0.11, 0.3, -0.11 + j * 0.11)
			box_into(st, bt + Vector3(-0.03, 0, -0.03), bt + Vector3(0.03, 0.08, 0.03), Color("5c8f6a") if (i + j) % 2 else Color("8a5a3a"))
	# the net: a diamond mesh, see-through, on all four sides
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			if (x + y) % 8 < 2 or (x - y + 8) % 8 < 2:
				img.set_pixel(x, y, Color("3a6b47"))
	var nm := mat(Color.WHITE, ImageTexture.create_from_image(img))
	nm.vertex_color_use_as_albedo = true
	nm.vertex_color_is_srgb = true
	nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var net := surface(nm)
	var lo := gs + Vector3(0, 0.1, 0)
	for f in [[Vector3(-h.x, 0, h.z), Vector3(h.x, 0, h.z), 0.9], [Vector3(h.x, 0, h.z), Vector3(h.x, 0, -h.z), 0.75],
			[Vector3(-h.x, 0, -h.z), Vector3(h.x, 0, -h.z), 0.75], [Vector3(-h.x, 0, h.z), Vector3(-h.x, 0, -h.z), 0.9]]:
		var a: Vector3 = lo + f[0]
		var b: Vector3 = lo + f[1]
		var len_ := (b - a).length() / 0.3
		net.set_color(Color(f[2], f[2], f[2]))
		add_quad(net, [a, b, b + Vector3(0, 0.78, 0), a + Vector3(0, 0.78, 0)], [Vector2(0, 2.6), Vector2(len_, 2.6), Vector2(len_, 0), Vector2.ZERO])
	commit([st, net], set_node)
	cast(set_node, Vector2(gs.x, gs.z), 0.0, 0.96, 0.8)
	cast(set_node, Vector2(sp.x, sp.z), 0.0, 1.24, 0.1)
	blob(set_node, Vector2(gs.x, gs.z - 0.3), 1.0)


## The car park's furniture in one surface: wheel stops banded in yellow, and a low planter along the back below the
## till's sight line, a coped concrete trough holding a clipped hedge of lumpy shrubs with a few azaleas in flower.
func car_park_kit() -> void:
	var kit := mat(Color.WHITE)
	kit.vertex_color_use_as_albedo = true
	kit.vertex_color_is_srgb = true
	var st := surface(kit)
	for cx in [-1.0, 1.4]:
		box_into(st, Vector3(cx - 0.75, -0.04, -15.4), Vector3(cx + 0.75, 0.08, -15.2), Color("d8d2c4"))
		for bx in [-0.42, 0.42]:
			box_into(st, Vector3(cx + bx - 0.1, -0.04, -15.41), Vector3(cx + bx + 0.1, 0.085, -15.19), Color("e2b23a"))
	var p0 := Vector3(-3.2, -0.04, -16.8)
	var p1 := Vector3(2.0, 0.26, -16.3)
	box_into(st, p0, p1, Color("b3ad9f"))
	box_into(st, p0 - Vector3(0.01, 0, 0.01), Vector3(p1.x + 0.01, 0.03, p1.z + 0.01), Color("8c877c"))  # grime at its foot
	box_into(st, Vector3(p0.x - 0.04, 0.26, p0.z - 0.04), Vector3(p1.x + 0.04, 0.31, p1.z + 0.04), Color("d6d0c3"))
	box_into(st, Vector3(p0.x + 0.06, 0.31, p0.z + 0.06), Vector3(p1.x - 0.06, 0.315, p1.z - 0.06), Color("5a4636"))
	var r := RandomNumberGenerator.new()
	r.seed = 31
	var leaf := Color("4f8a43")
	box_into(st, Vector3(p0.x + 0.08, 0.31, p0.z + 0.08), Vector3(p1.x - 0.08, 0.47, p1.z - 0.08), leaf.darkened(0.06))
	var x := p0.x + 0.08
	while x < p1.x - 0.12:  # the clipped top rises and dips in soft lumps, each lit a shade on its crown
		var x1 := minf(x + r.randf_range(0.3, 0.42), p1.x - 0.08)
		var top := r.randf_range(0.5, 0.56)
		var g: Color = leaf.lightened(r.randf_range(-0.04, 0.08))
		var z0 := p0.z + r.randf_range(0.06, 0.1)
		var z1 := p1.z - r.randf_range(0.06, 0.1)
		box_into(st, Vector3(x, 0.4, z0), Vector3(x1, top, z1), g)
		var ix := (x1 - x) * 0.18
		box_into(st, Vector3(x + ix, top, z0 + 0.05), Vector3(x1 - ix, top + 0.03, z1 - 0.05), g.lightened(0.12))
		if r.randf() < 0.45:  # an azalea in flower poking through the clipped face
			var fx := r.randf_range(x + 0.04, x1 - 0.1)
			var fy := r.randf_range(0.36, top - 0.06)
			var fz := maxf(z1, p1.z - 0.08)
			box_into(st, Vector3(fx, fy, fz), Vector3(fx + 0.06, fy + 0.05, fz + 0.03), Color("e86a9a") if r.randf() < 0.6 else Color("f4f0ec"))
		if x1 >= p1.x - 0.08:
			break
		x = x1 - r.randf_range(0.08, 0.14)
	commit([st], set_node)


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
	set_sign_mats.clear()
	room_dim = Color.WHITE  # the new fittings are built lit; update_power dims them again if the power is still out
	set_cars.clear()
	var b := branch
	var st: Dictionary = b.store
	var type: String = sim.districts[sim.lots[b.lot].block].type
	var zl: float = Sim.ZONE_LEFT[st.size]
	shop_area = Rect2(site.position.x + Sim.ORIGIN.x + zl, site.position.z + Sim.ORIGIN.y - 4.7, 6.6 - zl, 9.4)
	foot_mat.set_shader_parameter("indoor", Color(shop_area.position.x, shop_area.position.y, shop_area.size.x, shop_area.size.y))
	# ground: the sidewalks, the road with its centre line and crossing. Either side the city's own blocks and roads
	# show, so the side streets and avenues that cross the set run on through it.
	var span := rival_span(b.rival)
	var here := Vector2(site.position.x, site.position.z)
	var roads := roads_near()
	street_x = street_reach(C, here, span, roads)
	var side_roads := roads.filter(func(rd): return rd is Array or rd.size.y > rd.size.x)  # avenues and cross streets
	# where the set runs out over water (the bay, a canal) it stands on made ground: its street with a strip either
	# side, and the lots of your shop and the rival. Elsewhere the water stays and the neighbours keep out of it.
	var made := surface(ground_mat(paving()))
	made.set_color(Color(Sim.City.GROUND[type]))
	var made_runs := []
	if near_water():
		made_runs = made_ground(C, here, street_x, span)
		for w in made_runs:
			rect_quad(made, w, -0.125, 0.0, false, 0.25)  # over the water, under any bridge
		roads.append_array(water_runs(C, here, SET.position.y, -20.2) + water_runs(C, here, -20.2, -7.2, SET.position.x, -16.5) + water_runs(C, here, -20.2, -7.2, span.y, SET.end.x))
	var far_gaps := mouths(-8.2, -3.6, side_roads, Vector2(-16.5, span.y))  # none between your shop and the rival
	var near_gaps := mouths(3.6, 8.2, side_roads)
	entries = (far_gaps + near_gaps).map(func(g): return (g.x + g.y) / 2)
	var overhead := decks_near()
	var under := [mouths(-8.2, -3.6, overhead), mouths(3.6, 8.2, overhead)]  # where a deck crosses each sidewalk
	var walk := surface(pavers())
	var tar := surface(tiled(speckle([ASPHALT, ASPHALT.darkened(0.05), ASPHALT.lightened(0.06), ASPHALT.darkened(0.08)]), Vector2.ONE))
	var road := surface(tarmac())
	rect_quad(road, Rect2(street_x.x, -3.7, street_x.y - street_x.x, 7.4), -0.045, 0.0, false, 0.125)
	var kerb := surface(mat(Color("8f8b84")))
	var kerb_m := mat(Color.WHITE)
	kerb_m.vertex_color_use_as_albedo = true
	kerb_m.vertex_color_is_srgb = true
	var kerbs := surface(kerb_m)
	var tactile := surface(mat(Color("d2b862")))  # the yellow guide strip down each sidewalk
	# a raised kerb along each sidewalk, dropped flush at the crossing and, on your side, across the car park's mouth
	for sd in [[far_gaps, -7.2, -3.8, -5.4, Vector2(-3.4, Sim.CROSS_X + 1.7)], [near_gaps, 3.7, 3.6, 5.0, Vector2(Sim.CROSS_X - 1.7, Sim.CROSS_X + 1.7)]]:
		var drop: Vector2 = sd[4]
		for o in open_spans(sd[0]):
			rect_quad(walk, Rect2(o.x, sd[1], o.y - o.x, 3.5), -0.045, 0.0, false, 0.5)
			rect_quad(kerb, Rect2(o.x, sd[2], o.y - o.x, 0.2), -0.04)
			rect_quad(tactile, Rect2(o.x, sd[3], o.y - o.x, 0.32), -0.042)
			for seg in [Vector2(o.x, minf(o.y, drop.x)), Vector2(maxf(o.x, drop.y), o.y)]:
				if seg.y - seg.x > 0.3:
					box_into(kerbs, Vector3(seg.x, -0.045, sd[2]), Vector3(seg.y, 0.09, sd[2] + 0.2), Color("bdb7ab"))
		for g in sd[0]:  # a side road's mouth: the asphalt runs through the sidewalk, the kerb turning the corners
			rect_quad(tar, Rect2(g.x, sd[1], g.y - g.x, 3.5), -0.045, 0.0, false, 0.5)
			for ex in [g.x - 0.2, g.y]:
				if ex > street_x.x and ex + 0.2 < street_x.y:
					box_into(kerbs, Vector3(ex, -0.045, sd[1]), Vector3(ex + 0.2, 0.09, sd[1] + 3.5), Color("bdb7ab"))
	var paint := surface(mat(Color("ebe7dc")))
	var x := SET.position.x
	while x < SET.end.x:
		if x >= street_x.x and x + 2.0 <= street_x.y and (x + 2.0 < Sim.CROSS_X - 2.0 or x > Sim.CROSS_X + 2.0):
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
	var bay := surface(car_park())  # its lines and the arrow leading drivers in off the street are painted on it
	rect_quad(bay, Rect2(-3.4, -16.0, 7.1, 8.8), -0.042, 1.0)
	for kb in [Rect2(-3.4, -16.25, 7.1, 0.25), Rect2(3.45, -16.25, 0.25, 9.05)]:  # kerb round the back and side
		rect_quad(kerb, kb, -0.036)
	var hatch := surface(mat(Color("e2c048")))
	var hz := -15.4
	while hz < -11.2:  # yellow hatching keeps the strip along your wall clear for bicycles
		add_quad(hatch, [Vector3(-3.25, -0.038, hz), Vector3(-3.25, -0.038, hz + 0.16), Vector3(-2.35, -0.038, hz + 0.66), Vector3(-2.35, -0.038, hz + 0.5)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		hz += 0.7
	for hr in [Rect2(-3.3, -15.6, 1.04, 0.1), Rect2(-3.3, -11.1, 1.04, 0.1), Rect2(-3.3, -15.6, 0.1, 4.6)]:
		rect_quad(hatch, hr, -0.038)
	# the yard round the back of the car park and on to the rival, where the set's lots meet: poured concrete scored
	# into slabs, with a drain grating along the sidewalk, rather than the bare district ground the set cleared
	var yard := surface(slabs())
	rect_quad(yard, Rect2(3.7, -20.2, span.x - 3.7, 13.0), -0.043, 0.0, false, 1.0 / 1.8)
	rect_quad(yard, Rect2(-16.5, -20.2, 20.2, 3.95), -0.043, 0.0, false, 1.0 / 1.8)
	var grate := surface(mat(Color("6c6a66")))
	rect_quad(grate, Rect2(3.75, -7.75, span.x - 3.8, 0.28), -0.04)
	commit([made, walk, road, tar, kerb, bay, paint, hatch, tactile, kerbs, yard, grate], set_node)
	quay(made_runs, side_roads)
	snow_cover = settled_snow(far_gaps, near_gaps)
	matsuri = matsuri_lanterns(far_gaps + under[0], near_gaps + under[1])
	works = roadworks(near_gaps + under[1])
	tv = tv_crew()
	health = health_check()
	heat = ice_stand()
	car_park_kit()
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
	# where a city street runs in under the yard and leaves it unbuilt: the block's garbage station at the sidewalk, a
	# couple of bicycles along the car park's kerb and a tree at the back, all on the side the rival doesn't hide
	if span.x > 8.0 and free_runs(5.35, span.x, -16.2, -7.2, roads + overhead).is_empty() and free_runs(3.7, span.x, -20.2, -7.2, overhead) == [Vector2(3.7, span.x)]:
		garbage_station(Vector3(4.55, 0, -9.5))
		for bz in [-12.4, -13.5]:
			var bike := sprite("outdoor", Rect2(8 * OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * OUTDOOR_SCALE[8] * 0.55)
			bike.position = Vector3(4.35, OUTDOOR / 2.0 * OUTDOOR_PX * OUTDOOR_SCALE[8] * 0.55 - 0.05, bz)
			set_node.add_child(bike)
			lit_sprites.append(bike)
			blob(set_node, Vector2(4.35, bz), PROP_BLOB[8])
			outdoor_cast(set_node, 8, Vector2(4.35, bz), OUTDOOR_SCALE[8] * 0.55)
		var tx := minf(6.6, span.x - 1.5)
		var tree := sprite("outdoor", Rect2(OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * 0.8)
		tree.position = Vector3(tx, OUTDOOR / 2.0 * OUTDOOR_PX * 0.8 - 0.05, -19.3)
		set_node.add_child(tree)
		lit_sprites.append(tree)
		blob(set_node, Vector2(tx, -19.3), 1.3)
		outdoor_cast(set_node, 1, Vector2(tx, -19.3), 0.8)
	for mh in [Vector2(-34.0, -1.9), Vector2(-17.0, 1.9), Vector2(13.0, -1.9), Vector2(33.0, 1.9)]:
		if mh.x < street_x.x + 0.6 or mh.x > street_x.y - 0.6:
			continue
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
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var closures := surface(km)
	var poles := [-42.0, -19.0, 12.0, 36.0].filter(func(px): return px > street_x.x + 1.0 and px < street_x.y - 1.0 and not in_gaps(px, near_gaps + under[1]))
	if street_x.x == SET.position.x:  # the wires run on off the set where the street does; at a quay they stop at a pole
		poles.push_front(SET.position.x)
	if street_x.y == SET.end.x:
		poles.append(SET.end.x)
	for k in poles.size():
		var px: float = poles[k]
		if absf(px) != SET.end.x:
			utility_pole(Vector3(px, 0, 6.85), k)
		if k == 0 or under[1].any(func(g): return g.y > poles[k - 1] and g.x < px):  # no wire up through a deck
			continue
		var x0: float = poles[k - 1]
		for line in [[6.76, -0.55, 0.035, 0.025], [6.76, 0.0, 0.035, 0.025], [6.76, 0.55, 0.035, 0.025], [4.6, -0.2, 0.045, 0.032]]:
			var pts := PackedVector3Array()
			for i in 9:
				var t := i / 8.0
				pts.append(Vector3(lerpf(x0, px, t), line[0] - line[2] * (px - x0) * 4.0 * t * (1.0 - t), 6.85 + line[1]))
			wall(wires, pts, 0.0, -line[3], line[3])
		if k % 2 == 1:  # a telecom closure slung under the cable near the pole
			var cx := lerpf(x0, px, 0.86)
			var cy := 4.6 - 0.045 * (px - x0) * 4.0 * 0.86 * 0.14
			box_into(closures, Vector3(cx - 0.4, cy - 0.2, 6.56), Vector3(cx + 0.4, cy - 0.03, 6.74), Color("2c2d31"))
			box_into(closures, Vector3(cx - 0.44, cy - 0.17, 6.58), Vector3(cx + 0.44, cy - 0.06, 6.72), Color("3a3b40"))
	commit([wires, closures] if poles.size() > 2 else [wires], set_node)
	# neighbours: the district's own mix of buildings either side of your shop and the rival, a row behind them
	var mix: Array = Sim.City.MIX[type]
	var r := RandomNumberGenerator.new()
	r.seed = b.lot * 7919 + 3
	var boxes := []
	var roofs := []
	var mine: float = -10.0 + Sim.ZONE_LEFT[st.size]
	for seg in [[SET.position.x, -27.75], [-26.25, -16.5], [span.y, 29.75], [31.25, SET.end.x]]:
		set_row(seg[0], seg[1], -7.2, 13.0, mix, r, boxes, roofs, 0.7, roads + overhead)
	var low := boxes.size()
	set_row(5.35, span.x, -7.2, 9.0, [[1, Sim.City.SHOPS, 1, 1, 6, 9, 9, 9]], r, boxes, roofs, 0.9, roads + overhead)  # one floor, so it hides neither your till nor the car park
	var low_roofs := boxes.slice(low).filter(func(e): return not roofs.any(func(rf): return is_equal_approx(rf[1].x, e[1].x)))
	set_row(SET.position.x, SET.end.x, -20.5, 11.0, mix, r, boxes, roofs, 1.0, roads + overhead)
	shop_roofs(low_roofs)
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
		var drift := surface(mat(Color(1, 1, 1, 0.999), snow_tex))
		rect_quad(drift, Rect2(xl + 0.2, -15.95, vw - 0.4, 8.4), 3.665, 0.0, false, 0.125)
		commit([drift], snow_cover)
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
		# the shutter, 14 ribbed slats at 23 px a metre: road grime climbing from the foot, rust run down from the box
		var sw := vw - 0.8
		var slats := Image.create(maxi(8, roundi(sw * 23.0)), 56, false, Image.FORMAT_RGB8)
		var rr := RandomNumberGenerator.new()
		rr.seed = 7
		var runs := {}
		for k in roundi(sw * 1.2):
			runs[rr.randi_range(1, slats.get_width() - 2)] = rr.randi_range(10, 34)
		for px in slats.get_width():
			for y in 56:
				var c := Color("8f959b") if y % 4 == 3 else (Color("d3d7d9") if y % 4 == 0 else Color("c4c8cb"))
				c = c.lerp(Color("7c7366"), 0.75 * pow(clampf((y - 20.0) / 36.0, 0.0, 1.0), 1.3))
				if runs.has(px) and y < runs[px]:
					c = c.lerp(Color("94603e"), 0.7 * (1.0 - float(y) / runs[px]))
				slats.set_pixel(px, y, c)
		var shutter := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(sw, 2.45)
		shutter.mesh = q
		shutter.material_override = mat(Color.WHITE, ImageTexture.create_from_image(slats))
		shutter.position = Vector3(vx, 1.235, -7.17)
		set_node.add_child(shutter)
		block(set_node, Vector3(vw - 0.7, 0.1, 0.1), Vector3(vx, 0.05, -7.13), Color("7d8389"))
		for side in [-1, 1]:
			block(set_node, Vector3(0.12, 2.5, 0.14), Vector3(vx + side * (sw / 2 + 0.02), 1.25, -7.13), Color("7d8389"))  # guide rails
			block(set_node, Vector3(0.07, 0.1, 0.05), Vector3(vx + side * (sw / 2 - 0.45), 0.13, -7.06), Color("c9a24a"))  # padlocked to the kerb
		# old flyers taped up and peeling, and the post nobody collects heaped at the foot
		for f in [[Vector2(0.45 - sw / 2, 1.3), Vector2(0.42, 0.58), Color("efe2a4")], [Vector2(0.9 - sw / 2, 1.05), Vector2(0.36, 0.5), Color("cfe0ec")]]:
			block(set_node, Vector3(f[1].x, f[1].y, 0.02), Vector3(vx + f[0].x, f[0].y, -7.15), f[2])
			block(set_node, Vector3(f[1].x * 0.6, 0.05, 0.025), Vector3(vx + f[0].x, f[0].y + f[1].y * 0.22, -7.145), Color("6b6359"))
		for m in [[Vector3(0.42, 0.04, 0.24), Vector3(-0.3, 0.02, -6.98), Color("f2efe6")], [Vector3(0.3, 0.03, 0.2), Vector3(-0.05, 0.045, -6.95), Color("e7c9a0")], [Vector3(0.26, 0.03, 0.18), Vector3(-0.45, 0.05, -6.92), Color("d9e4ee")]]:
			block(set_node, m[0], Vector3(vx, 0, 0) + m[1], m[2])
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
		if p[1].x < street_x.x + 0.5 or p[1].x > street_x.y - 0.5 or in_gaps(p[1].x, far_gaps if p[1].y < 0.0 else near_gaps) or in_gaps(p[1].x, under[0] if p[1].y < 0.0 else under[1]):
			continue
		if p[0] == 6:
			street_lamp(Vector3(p[1].x, 0, p[1].y))
			continue
		var s := sprite("outdoor", Rect2(p[0] * OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * OUTDOOR_SCALE[p[0]] * 0.55)
		s.position = Vector3(p[1].x, OUTDOOR / 2.0 * OUTDOOR_PX * OUTDOOR_SCALE[p[0]] * 0.55 - 0.05, p[1].y)
		set_node.add_child(s)
		lit_sprites.append(s)
		blob(set_node, p[1], PROP_BLOB.get(p[0], OUTDOOR_SCALE[p[0]] * 1.5))
		outdoor_cast(set_node, p[0], p[1], OUTDOOR_SCALE[p[0]] * 0.55)
	spill(set_node, Sim.ORIGIN.x + (zl + 6.6) / 2, 8.6 - zl, Sim.ORIGIN.y + 4.7, shop_spill_mat)  # your shop's open front
	for d in [[0, Vector2(-6.7, -6.75), 0.6], [0, Vector2(-4.1, -6.75), 0.6], [5, Vector2(-8.3, -6.2), 0.7]]:
		var s := sprite("decor", Rect2(d[0] * DECOR, 0, DECOR, DECOR), DECOR_PX * d[2])
		s.position = Vector3(d[1].x, DECOR / 2.0 * DECOR_PX * d[2], d[1].y)
		set_node.add_child(s)
		lit_sprites.append(s)
		blob(set_node, d[1], 0.45)
		var dc: Array = DECOR_CAST[d[0]]
		cast(set_node, d[1], dc[0] * DECOR * DECOR_PX * d[2], dc[1] * DECOR * DECOR_PX * d[2], dc[2] * DECOR * DECOR_PX * d[2])
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
		crossing_signal(pole)
	# outside facilities
	var outside := {"vending": Vector3(Sim.VENDING_X, 0, -7.2 + 0.375), "gacha": Vector3(Sim.GACHA_X - 0.1, 0, -7.2 + 0.25), "bench": Vector3(-13.6, 0, -6.6)}
	for f in st.facilities:
		if outside.has(f):
			var at: Vector3 = outside[f]
			lit_sprites.append(prop(set_node, f, at))
			blob(set_node, Vector2(at.x, at.z), 0.8)
			var fc: Array = FACILITY_CAST[f]
			cast(set_node, Vector2(at.x, at.z), fc[0], fc[1], fc[2])
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


## A crossing light's pole: a footing collar, the yellow push-button box at hand height, the pedestrian head in its
## backplate with a visor over each lamp (the lamps themselves are drawn on the overlay), and the blue crossing sign
## with its walking figure up top, all turned to the view, in one mesh per pole.
func crossing_signal(at: Vector3) -> void:
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var kit := surface(km)
	var steel := Color("80868f")
	var dark := Color("4f535c")
	var body := Color("33363f")
	box_into(kit, at + Vector3(-0.12, 0, -0.12), at + Vector3(0.12, 0.28, 0.12), dark)
	box_into(kit, at + Vector3(-0.065, 0.28, -0.065), at + Vector3(0.065, 1.9, 0.065), steel)
	box_into(kit, at + Vector3(-0.075, 1.84, -0.075), at + Vector3(0.075, 1.9, 0.075), dark)
	box_into(kit, at + Vector3(-0.055, 1.9, -0.055), at + Vector3(0.055, 3.56, 0.055), steel)
	box_into(kit, at + Vector3(-0.07, 3.56, -0.07), at + Vector3(0.07, 3.6, 0.07), dark)
	# the push-button box, its white face and the button
	box_into(kit, at + Vector3(-0.09, 0.98, 0.065), at + Vector3(0.09, 1.34, 0.17), Color("f2c230"))
	box_into(kit, at + Vector3(-0.065, 1.04, 0.17), at + Vector3(0.065, 1.24, 0.18), Color("f4f1e8"))
	box_into(kit, at + Vector3(-0.03, 1.1, 0.18), at + Vector3(0.03, 1.16, 0.2), Color("d8432f"))
	# the head round the pole: a backplate a size larger, the lamp box and a visor over each lamp
	box_into(kit, at + Vector3(-0.2, 2.12, -0.16), at + Vector3(0.2, 2.88, -0.13), dark)
	box_into(kit, at + Vector3(-0.17, 2.15, -0.13), at + Vector3(0.17, 2.85, 0.1), body)
	for y in [2.5, 2.84]:
		box_into(kit, at + Vector3(-0.15, y - 0.03, 0.1), at + Vector3(0.15, y, 0.22), body)
	# the crossing sign: a white rim round blue, the figure and the stripes under its feet
	var c := Color("f4f1e8")
	var face := func(x0: float, y0: float, x1: float, y1: float, d: float, col: Color) -> void:
		box_into(kit, at + Vector3(x0, y0, 0.05 + d), at + Vector3(x1, y1, 0.06 + d), col)
	face.call(-0.24, 3.04, 0.24, 3.52, -0.02, c)
	face.call(-0.21, 3.07, 0.21, 3.49, 0.0, Color("2f6fb0"))
	face.call(-0.03, 3.38, 0.03, 3.44, 0.01, c)
	face.call(-0.04, 3.22, 0.03, 3.36, 0.01, c)
	face.call(-0.09, 3.16, -0.02, 3.22, 0.01, c)
	face.call(0.01, 3.16, 0.08, 3.22, 0.01, c)
	for i in 3:
		var x := -0.16 + i * 0.12
		face.call(x, 3.1, x + 0.07, 3.13, 0.01, c)
	commit([kit], set_node)
	blob(set_node, Vector2(at.x, at.z), 0.2)
	cast(set_node, Vector2(at.x, at.z), 0.0, 3.6, 0.12)
	cast(set_node, Vector2(at.x, at.z), 2.12, 2.88, 0.4)
	cast(set_node, Vector2(at.x, at.z), 3.04, 3.52, 0.3)


## A concrete utility pole on the near sidewalk: tapering as it rises from a guard sleeve banded yellow and black, an
## advertising plate at eye level, step bolts up to a crossarm with a porcelain insulator under each wire, a bracket
## for the telecom cable and, on every other pole, a transformer can with its leads up to the arm, in one mesh per pole.
func utility_pole(at: Vector3, k: int) -> void:
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var kit := surface(km)
	var concrete := Color("aaa69c")
	var dark := Color("55585f")
	var y := 0.0
	for seg in [[0.3, 2.0], [0.27, 4.0], [0.24, 5.8], [0.21, 7.0]]:
		var h: float = seg[0] / 2
		box_into(kit, at + Vector3(-h, y, -h), at + Vector3(h, seg[1], h), concrete.darkened(0.04 * (3 - int(y / 2.0))))
		y = seg[1]
	box_into(kit, at + Vector3(-0.115, 7.0, -0.115), at + Vector3(0.115, 7.06, 0.115), Color("8d8a83"))
	for i in 8:  # the guard sleeve
		box_into(kit, at + Vector3(-0.18, i * 0.2, -0.18), at + Vector3(0.18, i * 0.2 + 0.2, 0.18), Color("e8c43a") if i % 2 == 0 else Color("2e2f33"))
	# the advertising plate on the sidewalk face: a band in its colour, lines of type and a footer
	var ad: Color = [Color("2f6fb0"), Color("c8452f"), Color("3c8f5a")][k % 3]
	var z := 0.135
	box_into(kit, at + Vector3(-0.17, 1.95, z), at + Vector3(0.17, 3.0, z + 0.02), Color("f4f1e8"))
	box_into(kit, at + Vector3(-0.15, 2.72, z + 0.02), at + Vector3(0.15, 2.95, z + 0.03), ad)
	for i in 4:
		var ty := 2.6 - i * 0.12
		box_into(kit, at + Vector3(-0.11, ty - 0.04, z + 0.02), at + Vector3(0.11 - 0.05 * (i % 2), ty, z + 0.03), Color("4a4d55"))
	box_into(kit, at + Vector3(-0.15, 2.0, z + 0.02), at + Vector3(0.15, 2.1, z + 0.03), ad)
	for i in 9:  # step bolts, side to side
		var by := 2.5 + i * 0.42
		var sx := 1.0 if i % 2 == 0 else -1.0
		box_into(kit, at + Vector3(minf(0.1 * sx, 0.26 * sx), by, -0.02), at + Vector3(maxf(0.1 * sx, 0.26 * sx), by + 0.04, 0.02), dark)
	# the crossarm on its band, an insulator under each wire
	box_into(kit, at + Vector3(-0.13, 6.44, -0.13), at + Vector3(0.13, 6.54, 0.13), dark)
	box_into(kit, at + Vector3(-0.06, 6.54, -0.7), at + Vector3(0.06, 6.66, 0.7), Color("6f6c66"))
	for dz in [-0.55, 0.0, 0.55]:
		box_into(kit, at + Vector3(-0.035, 6.66, dz - 0.035), at + Vector3(0.035, 6.7, dz + 0.035), Color("8d8a83"))
		box_into(kit, at + Vector3(-0.05, 6.7, dz - 0.05), at + Vector3(0.05, 6.78, dz + 0.05), Color("e9e6dc"))
	box_into(kit, at + Vector3(-0.1, 4.55, -0.2), at + Vector3(0.1, 4.62, -0.11), dark)  # the telecom cable's bracket
	if k % 2 == 0:
		# the transformer can on two bands, its lid, ribs, bushings and leads up to the arm
		for by in [5.25, 5.62]:
			box_into(kit, at + Vector3(-0.13, by, -0.13), at + Vector3(0.13, by + 0.06, 0.18), dark)
		var c := at + Vector3(0, 0, 0.36)
		box_into(kit, c + Vector3(-0.22, 5.1, -0.2), c + Vector3(0.22, 5.8, 0.2), Color("8f9ca0"))
		box_into(kit, c + Vector3(-0.23, 5.1, -0.21), c + Vector3(0.23, 5.18, 0.21), Color("6c777b"))
		for ry in [5.38, 5.58]:
			box_into(kit, c + Vector3(-0.23, ry, -0.21), c + Vector3(0.23, ry + 0.03, 0.21), Color("7c878b"))
		box_into(kit, c + Vector3(-0.24, 5.8, -0.22), c + Vector3(0.24, 5.86, 0.22), Color("a7b2b5"))
		for bx in [-0.1, 0.1]:
			box_into(kit, c + Vector3(bx - 0.03, 5.86, -0.03), c + Vector3(bx + 0.03, 6.0, 0.03), Color("e9e6dc"))
			box_into(kit, c + Vector3(bx - 0.01, 6.0, -0.01), c + Vector3(bx + 0.01, 6.54, 0.01), Color("34343a"))
		box_into(kit, c + Vector3(-0.07, 5.3, 0.2), c + Vector3(0.07, 5.36, 0.21), Color("f2c230"))  # its warning label
		cast(set_node, Vector2(c.x, c.z), 5.1, 5.86, 0.46)
	commit([kit], set_node)
	blob(set_node, Vector2(at.x, at.z), 0.3)
	cast(set_node, Vector2(at.x, at.z), 0.0, 7.0, 0.26)
	cast(set_node, Vector2(at.x, at.z), 6.54, 6.66, 0.5)


## A row of district buildings fronting z = zf (northwards into the block), shoulder to shoulder from x0 to x1.
## Gaps are left wherever a city road crosses the row, so the road runs on between the buildings.
## A street lamp at the kerb: a pole on a plinth with its inspection hatch, stepping in at collars as it rises, a
## gooseneck arm curving out over the road and a slim luminaire whose lens lights after dark, with a halo round it, a
## cone of light under it and a pool on the ground below.
func street_lamp(at: Vector3) -> void:
	var out := 1.0 if at.z < 0.0 else -1.0
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var kit := surface(km)
	var steel := Color("7a808a")
	var dark := Color("4f535c")
	box_into(kit, at + Vector3(-0.15, 0, -0.15), at + Vector3(0.15, 0.55, 0.15), dark)
	box_into(kit, at + Vector3(-0.17, 0.5, -0.17), at + Vector3(0.17, 0.58, 0.17), Color("5c616b"))
	box_into(kit, at + Vector3(-0.07, 0.12, 0.15 * out), at + Vector3(0.07, 0.42, 0.16 * out), Color("6a6f79"))
	var y := 0.58
	for seg in [[0.17, 1.9], [0.14, 3.2], [0.11, 4.15]]:
		var h: float = seg[0] / 2
		box_into(kit, at + Vector3(-h, y, -h), at + Vector3(h, seg[1], h), steel)
		box_into(kit, at + Vector3(-h - 0.02, seg[1] - 0.06, -h - 0.02), at + Vector3(h + 0.02, seg[1], h + 0.02), dark)
		y = seg[1]
	box_into(kit, at + Vector3(-0.1, 2.35, 0.07 * out), at + Vector3(0.1, 2.6, 0.08 * out), Color("2f6fb0"))  # the ward's number plate
	box_into(kit, at + Vector3(-0.08, 2.44, 0.072 * out), at + Vector3(0.08, 2.52, 0.085 * out), Color("eef0ee"))
	for i in 7:  # the gooseneck, a quarter turn from upright to level
		var a := i / 6.0 * PI / 2
		var c := at + Vector3(0, 4.1 + 0.42 * sin(a), 0.42 * (1.0 - cos(a)) * out)
		box_into(kit, c - Vector3(0.05, 0.05, 0.05), c + Vector3(0.05, 0.05, 0.05), steel)
	var ay := 4.52
	box_into(kit, at + Vector3(-0.045, ay - 0.045, 0.42 * out), at + Vector3(0.045, ay + 0.045, 0.78 * out), steel)
	var z0 := minf(0.72 * out, 1.32 * out)
	box_into(kit, at + Vector3(-0.17, ay - 0.05, z0), at + Vector3(0.17, ay + 0.06, z0 + 0.6), Color("8c929b"))
	box_into(kit, at + Vector3(-0.15, ay + 0.06, z0 + 0.04), at + Vector3(0.15, ay + 0.09, z0 + 0.5), dark)
	commit([kit], set_node)
	var head := MeshInstance3D.new()
	head.mesh = shaded_box()
	head.scale = Vector3(0.28, 0.04, 0.5)
	head.position = at + Vector3(0, ay - 0.07, 1.02 * out)
	head.material_override = lamp_mat
	set_node.add_child(head)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	halo.mesh = q
	halo.material_override = halo_mat
	halo.position = at + Vector3(0, 4.2, 1.02 * out)  # below the head, so its housing doesn't hide the bright core
	set_node.add_child(halo)
	var beam := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(3.0, 4.0)
	beam.mesh = bq
	beam.material_override = beam_mat
	beam.position = at + Vector3(0, 2.25, 1.02 * out)
	set_node.add_child(beam)
	blob(set_node, Vector2(at.x, at.z), 0.25)
	cast(set_node, Vector2(at.x, at.z), 0.0, 4.15, 0.15)
	cast(set_node, Vector2(at.x, at.z + 1.02 * out), 4.45, 4.6, 0.34)
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


## The one-floor shops between your car park and the rival, seen from above: a parapet with a coping round a membrane
## laid in strips, its drain, AC condensers on pads piped to the edge, a vent stack and a roof hatch, all low.
func shop_roofs(list: Array) -> void:
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var kit := surface(km)
	var drift := surface(mat(Color(1, 1, 1, 0.999), snow_tex))
	var r := RandomNumberGenerator.new()
	r.seed = branch.lot * 131 + 7
	for e in list:
		var sz: Vector3 = e[0]
		var x0: float = e[1].x - sz.x / 2
		var x1: float = e[1].x + sz.x / 2
		var z0: float = e[1].z - sz.z / 2
		var z1: float = e[1].z + sz.z / 2
		var y := sz.y
		var wall_c := Color(e[2].r, e[2].g, e[2].b).lightened(0.12)
		var coping := Color("d6d1c6")
		var skin := Color(Sim.City.FLAT_ROOFS[[1, 2, 5, 6][r.randi() % 4]]).darkened(0.08)
		box_into(kit, Vector3(x0 + 0.15, y, z0 + 0.15), Vector3(x1 - 0.15, y + 0.03, z1 - 0.15), skin)
		for pr in [[x0, z0, x1, z0 + 0.15], [x0, z1 - 0.15, x1, z1], [x0, z0, x0 + 0.15, z1], [x1 - 0.15, z0, x1, z1]]:
			box_into(kit, Vector3(pr[0], y, pr[1]), Vector3(pr[2], y + 0.3, pr[3]), wall_c)
			box_into(kit, Vector3(pr[0] - 0.02, y + 0.3, pr[1] - 0.02), Vector3(pr[2] + 0.02, y + 0.36, pr[3] + 0.02), coping)
		var along_z := sz.z >= sz.x
		var long_ := maxf(sz.x, sz.z)
		var at := func(t: float, side: float) -> Vector3:  # t from the street end along the roof, side across it from its centre
			return Vector3(e[1].x + side, y + 0.03, z1 - t) if along_z else Vector3(x0 + t, y + 0.03, e[1].z + side)
		var t := 1.0
		while t < long_ - 0.4:  # the membrane's lapped seams across the roof
			var sp: Vector3 = at.call(t, 0.0)
			var hw := (minf(sz.x, sz.z) - 0.3) / 2
			var half := Vector3(hw, 0, 0.05) if along_z else Vector3(0.05, 0, hw)
			box_into(kit, sp - half, sp + half + Vector3(0, 0.015, 0), skin.darkened(0.16))
			t += 1.0
		var drain: Vector3 = at.call(long_ - 0.5, -minf(sz.x, sz.z) / 2 + 0.45)
		box_into(kit, drain + Vector3(-0.13, 0, -0.13), drain + Vector3(0.13, 0.02, 0.13), Color("4d4a44"))
		rect_quad(drift, Rect2(x0 + 0.15, z0 + 0.15, sz.x - 0.3, sz.z - 0.3), y + 0.06, 0.0, false, 0.125)
		var units := 1 if long_ < 5.0 else 2
		for k in units:
			var ac: Vector3 = at.call(long_ * 0.3 + k * 1.25, r.randf_range(-0.2, 0.2))
			box_into(kit, ac + Vector3(-0.55, 0, -0.4), ac + Vector3(0.55, 0.1, 0.4), Color("8e8d88"))
			box_into(kit, ac + Vector3(-0.47, 0.1, -0.32), ac + Vector3(0.47, 0.62, 0.32), Color("d2cfc4"))
			box_into(kit, ac + Vector3(-0.32, 0.18, 0.32), ac + Vector3(0.32, 0.54, 0.34), Color("7a8088"))
			box_into(kit, ac + Vector3(-0.47, 0.18, -0.25), ac + Vector3(-0.49, 0.54, 0.25), Color("9a9d9f"))
		var pipe: Vector3 = at.call(long_ * 0.3, 0.0)  # their pipes run along the roof to drop down the back
		var end_: Vector3 = at.call(long_ - 0.15, 0.0)
		var off := Vector3(0.62, 0, 0) if along_z else Vector3(0, 0, 0.5)
		box_into(kit, pipe + off - Vector3(0.05, 0, 0.05), end_ + off + Vector3(0.05, 0.1, 0.05), Color("bdb8ad"))
		var hatch: Vector3 = at.call(long_ * 0.72, -0.1)
		box_into(kit, hatch + Vector3(-0.45, 0, -0.45), hatch + Vector3(0.45, 0.28, 0.45), Color("a9a49a"))
		box_into(kit, hatch + Vector3(-0.38, 0.28, -0.38), hatch + Vector3(0.38, 0.32, 0.38), Color("8c949b"))
		var vent: Vector3 = at.call(0.9 + r.randf_range(0.0, 0.5), minf(sz.x, sz.z) / 2 - 0.55)
		box_into(kit, vent + Vector3(-0.09, 0, -0.09), vent + Vector3(0.09, 0.6, 0.09), Color("9aa0a6"))
		box_into(kit, vent + Vector3(-0.17, 0.6, -0.17), vent + Vector3(0.17, 0.67, 0.17), Color("6e737d"))
	commit([kit], set_node)
	commit([drift], snow_cover)


## The city's streets (rects) and avenue pieces ([a, b, half width]) that cross the set, in the street frame.
func roads_near() -> Array:
	return roads_at(C, Vector2(site.position.x, site.position.z))


static func roads_at(town: Dictionary, o: Vector2) -> Array:
	var area := Rect2(o + SET.position, SET.size)
	var out := []
	for s in town.streets:
		var rr := Rect2(s.from, s.line, s.to - s.from, s.w) if s.axis == "h" else Rect2(s.line, s.from, s.w, s.to - s.from)
		if rr.intersects(area):
			out.append(Rect2(rr.position - o, rr.size))
	for av in town.avenues:
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
				var on := edges.filter(func(e): return e[2] == n and e[1].is_equal_approx(a))  # across a quay's end, run by run
				if on.is_empty():
					edges.append([a, b, n])
				else:
					on[0][1] = b
	var m := mat(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var wall_ := surface(m)
	var shade := surface(mat(Color("2d5b88")))
	var box := func(p0: Vector3, p1: Vector3, col: Color) -> void: box_into(wall_, p0, p1, col)
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


## How far along the street (street frame x, on water_runs' grid) the set's street runs: as far as land or a city road
## reaches anywhere across its band, from the rival's lot to the made ground's near edge, and always past everywhere
## the game puts people (the alleys, the rival, fans out front). Beyond it lies open water to the set's end, so the
## street stops there at a quay rather than running on as a pier to nowhere.
static func street_reach(town: Dictionary, o: Vector2, span: Vector2, roads: Array) -> Vector2:
	var solid := func(x: float) -> bool:
		var z := -20.2
		while z < 9.2:
			var p := Vector2(x + 0.5, z + 0.5)
			if not Sim.City.is_water(town, o + p) or roads.any(func(rd): return rd.has_point(p) if rd is Rect2 else Geometry2D.get_closest_point_to_segment(p, rd[0], rd[1]).distance_to(p) < rd[2]):
				return true
			z += 1.0
		return false
	var lo := floorf(minf(Sim.ALLEYS.min(), Sim.DOOR.x - 26.0) - 2.0)  # fans gather up to 26 m either side of your door
	var hi := ceilf(maxf(Sim.ALLEYS.max(), span.y) + 1.5)
	var x0 := SET.position.x
	while x0 < lo and not solid.call(x0):
		x0 += 1.0
	var x1 := SET.end.x - 1.0
	while x1 >= hi and not solid.call(x1):
		x1 -= 1.0
	return Vector2(x0, maxf(x1 + 1.0, hi))


## The made ground the set stands on over water: its street and sidewalks out to `street_x`, your shop's and the rival's lots.
static func made_ground(town: Dictionary, o: Vector2, reach_: Vector2, span: Vector2) -> Array:
	return water_runs(town, o, -9.2, 9.2, reach_.x, reach_.y) + water_runs(town, o, -20.2, -7.2, -16.5, span.y)


## Water in the band z0..z1 between x0 and x1 (street frame), as runs 1 m deep on a 1 m grid.
static func water_runs(town: Dictionary, o: Vector2, z0: float, z1: float, x0: float = SET.position.x, x1: float = SET.end.x) -> Array:
	var out := []
	var z := z0
	while z < z1:
		var h := minf(1.0, z1 - z)
		var start := INF
		var x := x0
		while x < x1:
			var wet := Sim.City.is_water(town, o + Vector2(x + 0.5, z + h / 2))
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
	var x := street_x.x
	for run in free_runs(street_x.x, street_x.y, z0, z1, roads) + [Vector2(street_x.y, street_x.y)]:
		if run.x > x and (x >= keep.y or run.x <= keep.x):
			out.append(Vector2(x, run.x))
		x = run.y
	return out


## The street's length with the gaps taken out.
func open_spans(gaps: Array) -> Array:
	var out := []
	var x := street_x.x
	for g in gaps + [Vector2(street_x.y, street_x.y)]:
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
	rival_sign(parent, rv, cx, c)
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
		plane(parent, Vector2(1.6, 1.0), Vector3(sx, 4.405, -10.0), skylight_mats()[0])
		if not rv.defeated:
			plane(parent, Vector2(2.4, 1.6), Vector3(sx, 4.45, -10.0), skylight_mats()[1])
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
	# the end wall: the fascia's stripes wrap round the corner and run its depth, a downpipe at each corner
	var ex := span.y
	for s in [[Vector3(0.12, 0.8, 9.1), Vector3(ex + 0.01, 3.65, -11.65), c, 0.8], [Vector3(0.02, 0.08, 9.1), Vector3(ex + 0.08, 3.53, -11.65), Color.WHITE, 1.0],
			[Vector3(0.02, 0.24, 9.1), Vector3(ex + 0.08, 3.37, -11.65), c.darkened(0.25), 1.0]]:
		var sm := block(parent, s[0], s[1], s[2])
		if not rv.defeated:
			light_up(sm, s[3])
	for z in [-7.45, -15.95]:
		block(parent, Vector3(0.1, 3.2, 0.1), Vector3(ex + 0.1, 1.65, z), Color("b4b1a9"))
		block(parent, Vector3(0.26, 0.08, 0.14), Vector3(ex + 0.17, 0.04, z), Color("8f8c85"))
	if parent != set_node:
		return  # a shop on the city map: too small for the fittings
	# the yard side: a steel staff door under a hood and a lamp, crates of empties by it, the refrigeration condensers
	# humming on their pads, the meter boxes and their conduit, and a staff-wanted poster in the chain's colours
	var dz := -14.4
	block(parent, Vector3(0.06, 2.25, 1.15), Vector3(ex + 0.03, 1.125, dz), Color("5e6670"))
	block(parent, Vector3(0.04, 2.1, 0.95), Vector3(ex + 0.06, 1.05, dz), Color("a3abb2"))
	block(parent, Vector3(0.05, 0.05, 0.2), Vector3(ex + 0.1, 1.0, dz + 0.32), Color("d9d6cf"))
	block(parent, Vector3(0.02, 0.22, 0.44), Vector3(ex + 0.085, 1.65, dz), Color("f4f1e8"))
	block(parent, Vector3(0.02, 0.05, 0.44), Vector3(ex + 0.09, 1.74, dz), c)
	block(parent, Vector3(0.5, 0.06, 1.35), Vector3(ex + 0.25, 2.42, dz), Color("8f959b"))
	block(parent, Vector3(0.5, 0.12, 1.4), Vector3(ex + 0.25, 0.06, dz), Color("bdb9b0"))
	var lamp := block(parent, Vector3(0.16, 0.14, 0.3), Vector3(ex + 0.12, 2.62, dz), Color("fff3cf"))
	light_up(lamp, 1.0)
	pool(parent, Vector3(ex + 1.0, 0, dz), Vector2(2.2, 2.2))
	for k in 3:
		var cr := Vector3(ex + 0.35, 0.15 + 0.29 * int(k == 1), dz + 1.0 + 0.48 * int(k == 2))
		block(parent, Vector3(0.45, 0.28, 0.42), cr, c.lerp(Color("c8c4ba"), 0.35))
		block(parent, Vector3(0.36, 0.03, 0.34), cr + Vector3(0, 0.14, 0), Color("6b6359"))
	blob(parent, Vector2(ex + 0.35, dz + 1.25), 0.55)
	for k in 2:
		var cz := -11.9 + k * 1.05
		block(parent, Vector3(0.62, 0.1, 0.95), Vector3(ex + 0.36, 0.05, cz), Color("9c988f"))
		block(parent, Vector3(0.5, 0.75, 0.85), Vector3(ex + 0.33, 0.475, cz), Color("dcddd8"))
		block(parent, Vector3(0.02, 0.56, 0.56), Vector3(ex + 0.585, 0.5, cz), Color("41464c"))
		block(parent, Vector3(0.025, 0.1, 0.1), Vector3(ex + 0.59, 0.5, cz), Color("a7adb3"))
		cast(parent, Vector2(ex + 0.33, cz), 0.0, 0.85, 0.85)
	block(parent, Vector3(0.08, 3.0, 0.08), Vector3(ex + 0.06, 2.35, -11.6), Color("c9c6bd"))  # the units' pipes up to the roof
	block(parent, Vector3(0.14, 0.5, 0.36), Vector3(ex + 0.07, 1.65, -9.4), Color("b8bcbf"))
	block(parent, Vector3(0.02, 0.18, 0.22), Vector3(ex + 0.145, 1.72, -9.4), Color("39424a"))
	block(parent, Vector3(0.18, 0.36, 0.3), Vector3(ex + 0.09, 0.95, -9.4), Color("d4d0c6"))
	block(parent, Vector3(0.05, 0.05, 0.05), Vector3(ex + 0.05, 2.7, -9.4), Color("7a8088"))
	block(parent, Vector3(0.05, 1.3, 0.05), Vector3(ex + 0.04, 2.55, -9.25), Color("b8bcbf"))
	block(parent, Vector3(0.03, 0.95, 0.68), Vector3(ex + 0.015, 1.55, -8.3), Color("5e6670"))
	block(parent, Vector3(0.02, 0.85, 0.6), Vector3(ex + 0.035, 1.55, -8.3), Color("fbfaf5"))
	block(parent, Vector3(0.02, 0.22, 0.6), Vector3(ex + 0.045, 1.86, -8.3), c)
	for k in 3:
		block(parent, Vector3(0.02, 0.04, 0.44 - k * 0.1), Vector3(ex + 0.045, 1.6 - k * 0.12, -8.3), Color("3d3a36"))


## The chain's lightbox on its fascia: a cream plate with its mascot's head in a roundel ringed in the chain's colour
## and its name beside it, lit after dark; a beaten chain's goes grey and dark.
func rival_sign(parent: Node3D, rv: Dictionary, cx: float, c: Color) -> void:
	var font: Font = bold if bold else get_theme_default_font()
	var label := Label3D.new()
	label.text = Sim.RIVALS[rv.id].name
	label.font = font
	label.font_size = 64
	label.outline_size = 0
	label.pixel_size = 0.0072
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tw := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x * label.pixel_size
	var pw := tw + 1.7
	var x0 := cx - pw / 2
	var cream := Color("cfccc4") if rv.defeated else Color("fbfaf5")
	block(parent, Vector3(pw, 0.72, 0.08), Vector3(cx, 3.65, -6.95), cream)
	var blank := Image.create(1, 1, false, Image.FORMAT_RGB8)
	blank.fill(cream)
	var plate := art_panel(parent, blank, Vector2(pw - 0.04, 0.68), Vector3(cx, 3.65, -6.906), Color.WHITE, 1.0, false)  # the face flat, not shaded as the box's side
	block(parent, Vector3(pw + 0.06, 0.05, 0.1), Vector3(cx, 3.27, -6.95), c.darkened(0.2))
	var face: Image = (load("res://art/walk.png") as Texture2D).get_image().get_region(
			Rect2i(4, (WALK_ROW.mascot + Sim.RIVALS.keys().find(rv.id)) * PERSON.y, 64, 54))
	face.convert(Image.FORMAT_RGBA8)
	face.resize(48, 40, Image.INTERPOLATE_LANCZOS)
	var disc := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(32, 32))
			var px := cream if d > 31.0 else (c if d > 26.5 else cream.lightened(0.3))
			if d < 26.5 and x >= 8 and x < 56 and y >= 12 and y < 52:
				var f := face.get_pixel(x - 8, y - 12)
				if rv.defeated:
					f = Color(f.get_luminance(), f.get_luminance(), f.get_luminance(), f.a)
				px = px.lerp(Color(f.r, f.g, f.b), f.a)
			disc.set_pixel(x, y, px)
	var roundel := art_panel(parent, disc, Vector2(0.66, 0.66), Vector3(x0 + 0.52, 3.65, -6.9), Color.WHITE, 1.0, false)
	label.position = Vector3(x0 + 1.05 + tw / 2, 3.64, -6.895)
	parent.add_child(label)
	var ink := c.darkened(0.15)
	label.modulate = ink * light
	lit_mats.append([weakref(label), ink, 0.0])
	if not rv.defeated:
		light_up(plate, 1.3)  # past 1 so the plate reads white before full night
		light_up(roundel, 1.3)
		lit_mats[-1][2] = 1.3


## The rival's skylights, 20 px a metre (the glow 10): [four panes in a pale frame, darker sky reflected toward the far edge with a
## sheen across them, dimming with the day; the shop's cool light through the panes after dark, softly past the frame].
func skylight_mats() -> Array:
	if skylight_pair.size() == 2 and skylight_pair[0].get_ref() and skylight_pair[1].get_ref():
		return [skylight_pair[0].get_ref(), skylight_pair[1].get_ref()]
	var glass := Image.create(32, 20, false, Image.FORMAT_RGB8)
	for y in 20:
		for x in 32:
			var bar := x == 0 or x == 31 or y == 0 or y == 19 or x == 16 or y == 10
			var c := Color("5d86a0").lerp(Color("93b6c9"), y / 19.0)
			if posmod(x + y, 16) < 3:
				c = c.lerp(Color("d8eaf2"), 0.4)
			glass.set_pixel(x, y, Color("8f989d") if bar else c)
	glass.generate_mipmaps()
	var gm := mat(Color.WHITE, ImageTexture.create_from_image(glass))
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	gm.texture_repeat = false
	var mask := Image.create(24, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 24:
			var px := x - 4
			var py := y - 3
			var a := 0.0
			if px >= 0 and px < 16 and py >= 0 and py < 10:
				a = 0.3 if px == 0 or px == 15 or py == 0 or py == 9 or px == 8 or py == 5 else 1.0
			else:
				var d := Vector2(maxf(maxf(-px, px - 15), 0), maxf(maxf(-py, py - 9), 0)).length()
				a = 0.3 * pow(clampf(1.0 - d / 4.0, 0.0, 1.0), 2.0)
			mask.set_pixel(x, y, Color(1, 1, 1, a))
	var lm: StandardMaterial3D = sign_glow_mat.duplicate()
	lm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	lm.albedo_texture = ImageTexture.create_from_image(mask)
	lm.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.85 * night)
	fascia_glows.append([weakref(lm), SHOP_LIGHT])
	skylight_pair = [weakref(gm), weakref(lm)]
	return [gm, lm]


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
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var kit := surface(km)
	var steel := Color("9aa0a6")
	var frame := Color("5a6068")
	box_into(kit, ps + Vector3(-0.34, 0, -0.34), ps + Vector3(0.34, 0.2, 0.34), Color("c3beb4"))  # the footing
	box_into(kit, ps + Vector3(-0.28, 0.2, -0.28), ps + Vector3(0.28, 0.26, 0.28), Color("aca79d"))
	for i in 6:  # a guard sleeve in hazard bands where bumpers reach
		box_into(kit, ps + Vector3(-0.16, 0.26 + i * 0.17, -0.16), ps + Vector3(0.16, 0.43 + i * 0.17, 0.16), Color("e3c34a") if i % 2 == 0 else Color("3b3c40"))
	box_into(kit, ps + Vector3(-0.13, 1.28, -0.13), ps + Vector3(0.13, 3.3, 0.13), steel)
	box_into(kit, ps + Vector3(-0.15, 3.24, -0.15), ps + Vector3(0.15, 3.32, 0.15), frame)
	box_into(kit, ps + Vector3(-0.1, 3.32, -0.1), ps + Vector3(0.1, 5.65, 0.1), steel)
	box_into(kit, ps + Vector3(-0.35, 3.48, -0.13), ps + Vector3(0.35, 4.18, 0.13), Color("1f4f99"))  # the parking plate's case
	box_into(kit, ps + Vector3(-0.92, 7.15, -0.21), ps + Vector3(0.92, 7.23, 0.21), frame)  # the lightbox's cap, rails and pan
	box_into(kit, ps + Vector3(-0.9, 5.58, -0.2), ps + Vector3(0.9, 5.65, 0.2), frame)
	for sx in [-1.0, 1.0]:
		box_into(kit, ps + Vector3(0.85 * sx - 0.04, 5.58, -0.2), ps + Vector3(0.85 * sx + 0.04, 7.15, 0.2), frame)
	commit([kit], parent)
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
		if parent == set_node:
			set_sign_mats.append(lf.material_override)
		lf.position = ps + Vector3(0, 6.7, 0.175 * side)
		lf.rotation.y = 0.0 if side > 0 else PI
		parent.add_child(lf)
		var pf := MeshInstance3D.new()  # a lit blue P plate on the pole for the car park
		var pq := QuadMesh.new()
		pq.size = Vector2(0.64, 0.64)
		pf.mesh = pq
		pf.material_override = mat(Color.WHITE, park_face(), true)
		if parent == set_node:
			set_sign_mats.append(pf.material_override)
		pf.position = ps + Vector3(0, 3.83, 0.135 * side)
		pf.rotation.y = 0.0 if side > 0 else PI
		parent.add_child(pf)
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
	cast(parent, Vector2(ps.x, ps.z), 0.0, 1.3, 0.32)
	cast(parent, Vector2(ps.x, ps.z), 1.3, 5.7, 0.22)
	cast(parent, Vector2(ps.x, ps.z), 5.7, 7.15, 1.3)


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
	if not floor_tex.has(zl):
		floor_tex[zl] = shop_floor(zl, L.floor[0], L.floor[1])
	plane(room, Vector2(w, 9.0), Vector3(cx, 0.002, 0.0), mat(Color.WHITE, floor_tex[zl], true))
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
	build_counter(L.stripe, st.registers.filter(func(r): return r.active).map(func(r): return Sim.REGISTERS[r.id].pos.y))
	for reg in st.registers:
		if reg.active:
			var p: Vector2 = Sim.REGISTERS[reg.id].pos
			prop(room, "till", Vector3(p.x, COUNTER_H, p.y))
	# a fixture per product line, its stock stood on its own boards
	for pid in st.products:
		var p: Vector2 = Sim.SLOTS[Sim.PRODUCTS[pid].slot].pos
		var kind := slot_kind(Sim.PRODUCTS[pid].slot)
		if FIXTURES.has(kind):
			fixture_shell(kind, p, pid)
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


## The till counter (x 4.075-4.925, z -3.4-1.9) as one mesh, its clerks' side to the camera: open bays under a
## striped fascia, two shelves each of carrier bags, receipt rolls, cartons and baskets (bags under each till, at z in
## tills), between posts over a dark toe kick, and a worktop on a dark edge band.
func build_counter(stripe: Array, tills: Array) -> void:
	var m := mat(Color.WHITE, null, true)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var s := surface(m)
	const Z0 := -3.4
	const Z1 := 1.9
	const XB := 4.74  # the bays' back
	const XF := 4.925
	var body := Color("f3ecdc")
	box_into(s, Vector3(4.11, 0.0, Z0 + 0.05), Vector3(XF - 0.06, 0.08, Z1 - 0.05), Color("4a4540"))  # toe kick
	box_into(s, Vector3(4.075, 0.08, Z0), Vector3(XB, 0.71, Z1), body)
	box_into(s, Vector3(XB, 0.08, Z0), Vector3(XB + 0.01, 0.54, Z1), Color("6a6158"))
	box_into(s, Vector3(XB, 0.08, Z0), Vector3(XF, 0.12, Z1), body.darkened(0.06))
	box_into(s, Vector3(XB + 0.01, 0.3, Z0), Vector3(XF - 0.01, 0.32, Z1), body.darkened(0.06))
	box_into(s, Vector3(XB, 0.54, Z0), Vector3(XF, 0.71, Z1), body)
	box_into(s, Vector3(4.065, 0.63, Z0 - 0.01), Vector3(XF + 0.01, 0.68, Z1 + 0.01), stripe[0])
	box_into(s, Vector3(4.065, 0.565, Z0 - 0.01), Vector3(XF + 0.01, 0.615, Z1 + 0.01), stripe[1])
	box_into(s, Vector3(4.0, 0.71, Z0 - 0.04), Vector3(4.95, 0.725, Z1 + 0.04), Color("5b4632"))  # the worktop's edge band
	box_into(s, Vector3(4.0, 0.725, Z0 - 0.04), Vector3(4.95, COUNTER_H, Z1 + 0.04), Color("d8d2c6"))
	const BAYS := 4
	var bw := (Z1 - Z0) / BAYS
	for k in BAYS + 1:
		var z := Z0 + bw * k
		box_into(s, Vector3(XB, 0.08, clampf(z - 0.03, Z0, Z1 - 0.06)), Vector3(XF, 0.54, clampf(z + 0.03, Z0 + 0.06, Z1)), body)
	var bag := Color("f6f5f0")
	var card := Color("c79c62")
	for k in BAYS:
		var z0 := Z0 + bw * k + 0.06
		var z1 := z0 + bw - 0.12
		var till: bool = tills.any(func(t): return t > z0 - 0.06 and t < z1 + 0.06)
		for y: float in [0.12, 0.32]:
			var top: bool = y == 0.32
			if till and top:  # carrier bags stacked by size, then a tray of receipt rolls
				for i in 3:
					var bz := z0 + 0.04 + i * 0.3
					for j in 3 - i:
						box_into(s, Vector3(XB + 0.02, y + j * 0.045, bz), Vector3(XF - 0.03, y + j * 0.045 + 0.04, bz + 0.26 - i * 0.03), bag.darkened(0.04 * (j % 2)))
				for i in 4:
					box_into(s, Vector3(XF - 0.1, y, z1 - 0.3 + i * 0.07), Vector3(XF - 0.04, y + 0.06, z1 - 0.24 + i * 0.07), Color("fbfbf8"))
			elif (k + int(top)) % 2 == 0:  # cartons of stock
				box_into(s, Vector3(XB + 0.02, y, z0 + 0.05), Vector3(XF - 0.02, y + 0.17, z0 + 0.5), card)
				box_into(s, Vector3(XB + 0.02, y + 0.17, z0 + 0.05), Vector3(XF - 0.02, y + 0.175, z0 + 0.5), card.darkened(0.15))
				box_into(s, Vector3(XB + 0.03, y, z0 + 0.56), Vector3(XF - 0.03, y + 0.12, z0 + 0.9), card.lightened(0.12))
				box_into(s, Vector3(XB + 0.02, y, z1 - 0.2), Vector3(XF - 0.02, y + 0.06, z1 - 0.02), bag)
			else:  # nested shopping baskets and a bin
				for j in 3:
					box_into(s, Vector3(XB + 0.03, y + j * 0.04, z0 + 0.06), Vector3(XF - 0.03, y + j * 0.04 + 0.05, z0 + 0.46), Color("3f7fc8").darkened(0.08 * j))
				box_into(s, Vector3(XB + 0.03, y, z1 - 0.32), Vector3(XF - 0.03, y + 0.17, z1 - 0.06), Color("7d858d"))
				box_into(s, Vector3(XB + 0.03, y + 0.17, z1 - 0.32), Vector3(XF - 0.03, y + 0.18, z1 - 0.06), Color("5d646b"))
	commit([s], room)


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
func fixture_shell(kind: String, p: Vector2, pid: String) -> void:
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
			block(room, Vector3(w + 0.1, 0.05, 0.9), Vector3(p.x, h + 0.025, p.y), Color("3b3f52"))  # the cap's edge band
			block(room, Vector3(w + 0.06, 0.05, 0.86), Vector3(p.x, h + 0.075, p.y), Color("f6f2e8"))
			block(room, Vector3(w + 0.06, 0.025, 0.01), Vector3(p.x, h + 0.0625, p.y + 0.435), LAYOUT.stripe[0])
			# a POP card on the end panel: the line's pack over its price
			var ex := p.x + w / 2
			var cy := h - 0.32
			block(room, Vector3(0.02, 0.5, 0.56), Vector3(ex + 0.01, cy, p.y), LAYOUT.stripe[1])
			block(room, Vector3(0.02, 0.42, 0.48), Vector3(ex + 0.02, cy, p.y), Color("fffaf0"))
			block(room, Vector3(0.02, 0.09, 0.36), Vector3(ex + 0.03, cy - 0.13, p.y), Color("fff3c4"))  # the price flash
			block(room, Vector3(0.02, 0.025, 0.2), Vector3(ex + 0.04, cy - 0.13, p.y), LAYOUT.stripe[0])
			var ic: Array = Sim.PRODUCTS[pid].icon
			var cell: int = {"products": ITEM, "perks": 80, "decor": DECOR}[ic[0]]
			var s := sprite(ic[0], Rect2(ic[1] * cell, 0, cell, cell), 0.28 / cell, false)
			s.rotation.y = PI / 2
			s.position = Vector3(ex + 0.04, cy + 0.05, p.y)
			room.add_child(s)
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
			s.modulate = (Color(0.4, 0.4, 0.45, 0.8) if p.stock == 0 else Color.WHITE) * room_dim


# ---------- actors: the sim's pedestrians, threats and staff as sprites ----------

func clear_actors() -> void:
	for d in [agent_nodes, threat_nodes, staff_nodes]:
		for id in d:
			d[id].node.queue_free()
		d.clear()


## Keeps one sprite per sim actor; new ones get made, gone ones freed.
## Whether a pedestrian shows: not while in the rival's shop, nor past a quay (the game walks people in from 44 m
## along the street; there they are still on their way round to it).
func in_view(a: Dictionary) -> bool:
	return a.state != "inRival" and a.x > street_x.x - 0.3 and a.x < street_x.y + 0.3


func sync_actors(delta: float) -> void:
	var seen := {}
	for a in branch.agents:
		seen[a.id] = true
		var e = agent_nodes.get(a.id)
		if e == null:
			var node := sprite("walk", Rect2(0, (a.look % 7) * PERSON.y, PERSON.x, PERSON.y), PERSON_PX)
			node.add_child(foot())
			if a.kind == "fan":
				node.set_meta("base", Color(1.0, 0.86, 0.93))
			actors.add_child(node)
			e = {"node": node, "a": a.look % 7, "step": randf() * 4.0}
			agent_nodes[a.id] = e
		e.node.visible = in_view(a)
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
				node.add_child(foot())
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


## A blackout dims your shop to daylight through the glass, or near dark after dusk: every fitting and the shoppers
## inside, the pole sign and the light it throws on the car park and sidewalk, while the tripped board's lamp flashes.
func update_power() -> void:
	var cut: bool = branch.threats.any(func(t): return t.type == "breaker")
	if not breaker_lamp.is_empty() and is_instance_valid(breaker_lamp[0]):
		var on := fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.45
		breaker_lamp[0].material_override.albedo_color = Color("ff4a3d") if on else Color("6e2a26")
		breaker_lamp[1].material_override.albedo_color = Color(1.0, 0.25, 0.2, 0.7 if on else 0.0)
	var d: Color = BLACKOUT[0].lerp(BLACKOUT[1], snappedf(clampf(night, 0.0, 1.0), 0.05)) if cut else Color.WHITE
	if d == room_dim:
		return
	if (d == Color.WHITE) != (room_dim == Color.WHITE):
		night = -1.0  # relight the sign's glow, floodlight and spill
	room_dim = d
	var mats := set_sign_mats.duplicate()
	for n in room.find_children("*", "", true, false):
		if n is Sprite3D:
			if not n.has_meta("own"):
				n.set_meta("own", n.modulate)
			n.modulate = n.get_meta("own") * d
		elif n is GeometryInstance3D:
			if n.material_override is StandardMaterial3D:
				mats.append(n.material_override)
			if n is MeshInstance3D and n.mesh:
				for i in n.mesh.get_surface_count():
					if n.mesh.surface_get_material(i) is StandardMaterial3D:
						mats.append(n.mesh.surface_get_material(i))
	for m: StandardMaterial3D in mats:
		if not m.has_meta("own"):
			m.set_meta("own", m.albedo_color)
		m.albedo_color = m.get_meta("own") * d


## The tripped distribution board on the back wall (its face to +z): a steel case with its door swung open on rows of
## breakers, the main one thrown down in red, and a warning lamp over it, in the dark shop's own light.
func breaker_board(mi: MeshInstance3D) -> void:
	mi.position.y = 1.7
	var d: Color = BLACKOUT[0].lerp(BLACKOUT[1], clampf(night, 0.0, 1.0))
	block(mi, Vector3(0.55, 0.7, 0.14), Vector3(0, 0, -0.03), Color("9aa3ab") * d, true)
	block(mi, Vector3(0.47, 0.62, 0.02), Vector3(0, 0, 0.045), Color("353a41") * d, true)
	for r in 2:
		block(mi, Vector3(0.43, 0.025, 0.02), Vector3(0, 0.08 - r * 0.24, 0.055), Color("6c737b") * d, true)  # the DIN rail
		for k in 6:
			var main := r == 0 and k == 0
			var h := 0.13 if main else 0.1
			block(mi, Vector3(0.055, h, 0.04), Vector3(-0.185 + k * 0.074, 0.14 - r * 0.24, 0.065), Color("eceae4") * d, true)
			block(mi, Vector3(0.025, 0.035, 0.03), Vector3(-0.185 + k * 0.074, 0.14 - r * 0.24 + (-0.03 if main else 0.025), 0.095), (Color("e05a4e") if main else Color("3b4047")) * d, true)
	var door := MeshInstance3D.new()
	door.mesh = shaded_box()
	door.scale = Vector3(0.5, 0.66, 0.025)
	door.rotation.y = -1.1
	door.position = Vector3(0.275, 0, 0.05) + Vector3(cos(-1.1), 0, -sin(-1.1)) * 0.25
	var dm := mat(Color("aab3ba") * d, null, true)
	dm.vertex_color_use_as_albedo = true
	dm.vertex_color_is_srgb = true
	door.material_override = dm
	mi.add_child(door)
	block(door, Vector3(0.5, 0.18, 1.2), Vector3(0, 0.3, 0.0), Color("f2c230") * d, true)  # the hazard label inside the door
	var lamp := MeshInstance3D.new()
	lamp.mesh = shaded_box()
	lamp.scale = Vector3(0.1, 0.07, 0.06)
	lamp.position = Vector3(0, 0.43, 0.0)
	var lm := mat(Color("ff4a3d"), null, true)
	lm.vertex_color_use_as_albedo = true
	lm.vertex_color_is_srgb = true
	lamp.material_override = lm
	mi.add_child(lamp)
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.2)
	glow.mesh = q
	glow.material_override = halo_mat.duplicate()
	glow.position = Vector3(0, 0.43, 0.12)
	mi.add_child(glow)
	breaker_lamp = [lamp, glow]


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
		node.add_child(foot(sc))
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
				breaker_board(mi)
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
		var cold: bool = mode == "store" and not branch.is_empty() and branch.event != null and branch.event.id == "coldSnap"
		building_mat.set_shader_parameter("snow", 1.0 if cold else 0.0)
	if paused or city_sig == "":
		return
	street_life(delta)
	if mode == "store" and not branch.is_empty():
		if scene_signature() != set_sig:
			build_set()
		if snow_cover:
			snow_cover.visible = branch.event != null and branch.event.id == "coldSnap"
		if matsuri:
			matsuri.visible = branch.event != null and branch.event.id == "festival"
		if works:
			works.visible = branch.event != null and branch.event.id == "roadworks"
			if works.visible:
				works_glow_mat.albedo_color = Color(1.0, 0.45, 0.2, (0.9 if fmod(Time.get_ticks_msec() / 1000.0, 0.9) < 0.5 else 0.45) * night)
		if tv:
			tv.visible = branch.event != null and branch.event.id == "tv"
		if health:
			health.visible = branch.event != null and branch.event.id == "inspector"
		if heat:
			heat.visible = branch.event != null and branch.event.id == "heatwave"
		refresh_stock()
		sync_actors(delta)
		update_power()
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
	var inside := PackedVector2Array()
	var zl: float = Sim.ZONE_LEFT[branch.store.size]
	for y in [0.0, 3.0]:
		for c in [Vector2(zl - 0.3, -4.8), Vector2(6.8, -4.8), Vector2(6.8, 4.8), Vector2(zl - 0.3, 4.8)]:
			inside.append(screen_room(Vector3(c.x, y, c.y)))
	inside = Geometry2D.convex_hull(inside)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	var now := Time.get_ticks_msec() / 1000.0
	if look.size() == 1:
		draw_heat(look[0], inside, r, now)
		return
	overlay.draw_rect(Rect2(Vector2.ZERO, size), look[0])
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


## A heatwave goes with the sun: a warm haze (eased off in the already amber golden hour), glare washing down from the
## sky, and shimmer rising off the street but never inside your air-conditioned shop; after dark only a faint warmth is left.
func draw_heat(tint: Color, inside: PackedVector2Array, r: RandomNumberGenerator, now: float) -> void:
	var day := 1.0 - night
	overlay.draw_rect(Rect2(Vector2.ZERO, size), tint * Color(1, 1, 1, lerpf(0.25, 1.0, day) * (1.0 - 0.5 * golden_at(sim.hour()))))
	if day <= 0.01:
		return
	var glare := Color(1.0, 0.88, 0.58)
	var low := size.y * 0.6
	overlay.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, low * 0.6), Vector2(0, low)]),
		PackedColorArray([glare * Color(1, 1, 1, 0.42 * day), glare * Color(1, 1, 1, 0.22 * day), Color(glare, 0.0), Color(glare, 0.0)]))
	for i in 34:
		var x := r.randf() * size.x
		var y0 := size.y * r.randf_range(0.2, 1.05)
		var w := r.randf_range(50.0, 110.0)
		var life := fposmod(now * r.randf_range(0.16, 0.24) + r.randf(), 1.0)
		var c := Vector2(x, y0 - life * 70.0)
		if inside.size() > 2 and Geometry2D.is_point_in_polygon(c, inside):
			continue
		var wave := PackedVector2Array()
		for k in 9:
			var u := k / 8.0
			wave.append(c + Vector2((u - 0.5) * w, sin(u * TAU * 1.5 + now * 3.0 + i) * 2.5))
		var a := sin(life * PI) * day * day
		overlay.draw_polyline(wave, Color(1.0, 0.95, 0.82, 0.14 * a), 6.0)
		overlay.draw_polyline(wave, Color(1.0, 0.98, 0.9, 0.34 * a), 2.0)


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
		var top := at + Vector2(0, -26 if t.type in ["flyer", "shoplifter", "suit", "review"] else (-36 if t.type == "mascot" else (-30 if t.type == "breaker" else -12)))
		pill(top, label, 11, Color("e05a4e") if t.type != "spill" else Color("3a9bd9"))
		if t.max_clicks > 1:
			for k in t.max_clicks:
				var dot := top + Vector2((k - (t.max_clicks - 1) / 2.0) * 9, 9)
				overlay.draw_circle(dot, 4.0, Color(1.0, 0.98, 0.92))
				overlay.draw_circle(dot, 2.8, Color("e05a4e") if k < t.clicks else Color("dccca4"))
		if t.type == "review":
			bar(Rect2(top + Vector2(-16, 7), Vector2(32, 4)), t.ttl / (7.0 + 3.0 * sim.mods().thick_skin), Color("e05a4e"))
	# pedestrians: angry ones and what they carry
	for a in b.agents:
		if not in_view(a):
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
