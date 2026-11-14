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
const DECOR_CAST := {0: [0.0, 0.85, 0.42]}  # the potted plant, the same way
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
const SEA_DEEP := Color("1d5a98")  # open water far off any shore, and the sky-less background past the map
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
# After dark one standing in a lamp's pool or a shop's spill (lamps: x, z, radius) casts it away from that light
# instead, short under it and lengthening toward the rim; drawn over the light, so it shades what the light lit.
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
uniform float glow;
uniform vec3 lamps[64];
uniform int lamp_count;
varying vec2 wpos;
varying float cast_a;
varying float cast_len;

void vertex() {
	vec2 o = MODEL_MATRIX[3].xz;
	float best = 0.0;
	vec2 away = vec2(0.0);
	for (int i = 0; i < lamp_count; i++) {
		vec2 d = o - lamps[i].xy;
		float k = 1.0 - length(d) / lamps[i].z;
		if (k > best) {
			best = k;
			away = d;
		}
	}
	float lamp = glow * 0.7 * smoothstep(0.0, 0.45, best);
	cast_a = sun;
	cast_len = reach;
	if (lamp > sun && length(away) > 0.05) {
		vec2 s = MODEL_MATRIX[2].xz;
		float f = atan(away.x, away.y) - atan(s.x, s.y);
		VERTEX.xz = vec2(VERTEX.x * cos(f) + VERTEX.z * sin(f), VERTEX.z * cos(f) - VERTEX.x * sin(f));
		cast_a = lamp;
		cast_len = mix(1.9, 0.5, best);
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * size.x, UV.y * size.y - back);
	float contact = core * (1.0 - smoothstep(0.08, 0.3, length(p * vec2(1.0, 1.25))));
	float t = p.y / cast_len;
	float hw = mix(0.17, 0.08, clamp(t, 0.0, 1.0));
	float body = cast_a * smoothstep(-0.05, 0.12, p.y) * (1.0 - smoothstep(0.5, 1.0, t)) * (1.0 - smoothstep(hw * 0.45, hw, abs(p.x)));
	vec2 in_shop = step(indoor.xy, wpos) * step(wpos, indoor.xy + indoor.zw);
	body *= 1.0 - in_shop.x * in_shop.y;
	ALBEDO = tint.rgb;
	ALPHA = 1.0 - (1.0 - contact) * (1.0 - body);
}
"""
const FOOT := Vector3(0.7, 0.35, 1.6)  # a person's shadow plane: width, behind the feet, and the height it casts
# Daylight through your shop's glass front, laid over its floor: every point takes the light that came in over the
# sill above it, so the panes fall as a band slanting away from the sun, barred by the mullions and brightest out of
# the open door. `gate` holds what each pane lets through (u across the front, v the depth the light falls to).
const SUN_IN_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
uniform sampler2D gate : filter_linear, repeat_disable;
uniform vec4 tint : source_color;  // the sun's own warmth where it lands
uniform vec4 shade : source_color;  // and the cool the floor keeps where it doesn't
uniform vec2 size;
uniform vec2 span;  // the glazing: its near end in the floor's x, and its width
uniform float front;  // the glass line in the floor's z
uniform float slant;  // metres along the front per metre into the room
uniform float reach = 1.0;  // how deep the light falls, lengthening through golden hour

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * size.x, (UV.y - 0.5) * size.y);
	float d = front - p.y;
	float v = d / reach;
	float u = (p.x - slant * d - span.x) / span.y;
	vec2 inside = step(vec2(0.0), vec2(u, v)) * step(vec2(u, v), vec2(1.0));
	float sun = texture(gate, vec2(u, v)).r * inside.x * inside.y;
	ALBEDO = mix(shade.rgb, tint.rgb, sun);
	ALPHA = mix(shade.a, tint.a, sun);
}
"""
# a city tree's shadows (build_trees): a soft patch round its foot (COLOR.r 1), kept faintly after dark, and its
# crown's laid away from the sun, stretched along it through golden hour
const TREE_SHADOW_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
uniform sampler2D blob : source_color;
uniform float strength;
uniform float contact;
uniform float stretch = 1.0;
uniform vec2 dir;
varying float foot;

void vertex() {
	foot = COLOR.r;
	VERTEX.xz += dir * dot(VERTEX.xz, dir) * (stretch - 1.0) * (1.0 - foot);
}

void fragment() {
	vec4 c = texture(blob, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a * mix(strength, contact, foot);
}
"""
# Farmland: each field's crop colour, furrowed, under the hour's light; after dark the crops fade into one dark green
# so the lit city stands out rather than a patchwork of maroon, olive and green round it, while the lanes stay gravel.
const FIELD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D furrows : filter_linear_mipmap, repeat_enable;
uniform vec3 light = vec3(1.0);
uniform float night = 0.0;

void fragment() {
	float field = step(0.99, COLOR.a);  // lanes come in at alpha below 1: bare gravel, no furrows, no crop at night
	float l = dot(COLOR.rgb, vec3(0.3, 0.59, 0.11));
	// by moonlight each field keeps its own shade and a trace of its crop, so the patchwork still reads after dark
	vec3 moon = mix(vec3(l), COLOR.rgb, 0.55) * vec3(1.0, 1.02, 0.94);
	moon = max(vec3(0.0), moon + (l - 0.62) * 0.6);
	vec3 crop = mix(COLOR.rgb, moon, night * field);
	ALBEDO = crop * mix(vec3(1.0), texture(furrows, UV).rgb, field) * light;
}
"""
# The map's streetlights after dark, the lamps a unit of u apart along both kerbs and staggered: a hot spot under
# each lamp's head, its pool cast out over the carriageway cooling to amber at the rim, the kerbs lit all along between
# them, over a faint warm wash down the whole road; COLOR.r carries the carriageway's width / 40.
const ROAD_LIGHT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;
uniform vec3 tint = vec3(1.0, 0.85, 0.58);
uniform float spacing = 24.0;
uniform float wash = 0.07;
uniform float glow = 0.0;

void fragment() {
	float w = COLOR.r * 40.0;
	vec3 lit = vec3(0.0);
	float kerb = 0.0;
	for (int k = 0; k < 2; k++) {
		float x = (fract(UV.x + 0.5 * float(k)) - 0.5) * spacing;
		float y = (UV.y - (k == 0 ? 0.1 : 0.9)) * w;
		float core = exp(-(x * x + y * y) / 1.2);
		float pool = exp(-(x * x * 0.55 + y * y) / 9.0);
		lit += tint * core * 0.55 + mix(vec3(1.0, 0.6, 0.28), tint, pool) * pool * 0.26;
		kerb += exp(-y * y / 0.6) * (0.35 + 0.65 * exp(-x * x / 40.0));
	}
	float edge = smoothstep(0.0, 0.12, UV.y) * smoothstep(1.0, 0.88, UV.y);
	ALBEDO = glow * (mix(tint, vec3(1.0, 0.66, 0.34), 0.5) * wash * (0.8 + 0.8 * edge) + lit + vec3(1.0, 0.7, 0.4) * kerb * 0.16);
}
"""
# A heatwave's air over the street, on the 3D view's own picture: rows of it waver sideways as the heat climbs off the
# asphalt, and mirages lie in long sheens down the lanes, the sky's pale blue streaked across them over a wavering
# glimpse of the street beyond. ground_x/ground_z/ground_o take a screen pixel to the street frame's (x, z).
const HEAT_SHADER := """
shader_type canvas_item;
uniform vec2 view_size = vec2(1.0);
uniform vec2 ground_x;
uniform vec2 ground_z;
uniform vec2 ground_o;
uniform vec2 reach;
uniform float day = 1.0;
uniform vec3 sky : source_color = vec3(0.7, 0.84, 1.0);
uniform vec4 sheens[6];

void fragment() {
	vec2 p = UV * view_size;
	vec2 g = ground_x * p.x + ground_z * p.y + ground_o;
	float road = smoothstep(4.2, 2.6, abs(g.y)) * smoothstep(reach.x, reach.x + 3.0, g.x) * smoothstep(reach.y, reach.y - 3.0, g.x);
	float t = TIME;
	float rows = sin(p.y * 0.26 - t * 3.8 + sin(p.x * 0.013 + t * 0.6) * 2.0) + 0.35 * sin(p.y * 0.53 + p.x * 0.021 - t * 5.1);
	vec2 off = vec2(rows * 0.9, 0.3 * sin(p.x * 0.04 + t * 2.2)) * road * day / view_size;
	vec4 c = texture(TEXTURE, UV + off);
	float m = 0.0;
	float far = 0.0;
	for (int i = 0; i < 6; i++) {
		vec4 s = sheens[i];
		vec2 d = (g - s.xy) / vec2(s.z, 0.62);
		float e = smoothstep(0.0, 0.55, 1.0 - dot(d, d)) * (0.8 + 0.2 * sin(t * 1.3 + s.w));
		if (e > m) {
			m = e;
			far = clamp(d.x * 0.5 + 0.5, 0.0, 1.0);
		}
	}
	m *= road * day * day;
	if (m > 0.001) {
		vec2 up = vec2(off.x * 4.0, -(14.0 + 10.0 * far + 3.0 * sin(p.x * 0.05 + t * 2.0)) / view_size.y);
		vec3 beyond = texture(TEXTURE, UV + up).rgb;
		float streak = 0.93 + 0.07 * sin(p.y * 0.3 + p.x * 0.012 - t * 1.8);
		vec3 sheen = mix(sky, beyond, 0.3) * streak;
		c.rgb = mix(c.rgb, sheen, m * 0.6);
	}
	COLOR = c;
}
"""
# Open water on the map: the sea's blue, a paler turquoise over the shallows deepening to navy out from every shore, mottled in broad patches, with short wave crests over a darker trough
# scattered across it at a steady size on screen at any zoom (two sizes crossfaded), slowly glinting in and out.
# After dark the crests catch the moon, and off the built-up shore the water carries the city's lights: a warm haze
# over each light's reflection broken into ripple bars down the view, lamp-gold, shop-white or neon, thinning out away from the land.
const SWELL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 sea : source_color = vec3(0.23, 0.55, 0.78);
uniform vec3 deep : source_color = vec3(0.11, 0.35, 0.6);
uniform sampler2D depth : filter_linear, repeat_disable;  // distance out from the shore, 1 by open sea
uniform vec4 depth_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec3 light = vec3(1.0);
uniform float night = 0.0;
uniform sampler2D town : filter_linear, repeat_disable;  // the built-up blocks, blurred
uniform vec4 town_rect = vec4(0.0, 0.0, 1.0, 1.0);  // its origin and size on the ground
varying vec2 wp;
varying vec2 gp;

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

// x: a reflected light's ripple bars, y: which light, for columns s metres apart; each light's reflection runs a few
// bars down the view, and shows where `g` (nearness to town) is
vec2 dashes(vec2 p, float s, float g) {
	vec2 q = p / vec2(s * 0.35, s * 0.2);
	float c = floor(q.x);
	float run = floor(q.y / 7.0 + hash(vec2(c, 2.0)));
	float r = hash(vec2(c, run) + 11.0);
	float fl = hash(vec2(c, floor(q.y)) + 3.0);
	vec2 f = fract(q) - 0.5;
	f.x += 0.16 * sin(TIME * 1.3 + fl * 30.0);
	float hw = 0.1 + 0.22 * fl;
	float d = (1.0 - smoothstep(hw, hw + 0.1, abs(f.x))) * (1.0 - smoothstep(0.14, 0.3, abs(f.y))) * step(1.0 - g * 0.8, r) * step(0.2, fl);
	return vec2(d, hash(vec2(c, run) + 5.0));
}

void vertex() {
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	gp = w;
	wp = vec2(w.x - w.y, w.x + w.y) * 0.7071;  // crests lie across the view at the map's usual heading
}

void fragment() {
	float px = max(length(fwidth(wp)), 1e-4);
	float lv = log2(px * 16.0);
	float s = exp2(floor(lv));
	float aa = 0.5 / 16.0;
	vec2 w = mix(crests(wp, s, aa), crests(wp, s * 2.0, aa * 0.5), fract(lv));
	float m = noise(wp / 260.0) * 0.6 + noise(wp / 70.0) * 0.4;
	vec2 du = (gp - depth_rect.xy) / depth_rect.zw;
	float dp = texture(depth, du).r * step(0.0, min(du.x, du.y)) * step(max(du.x, du.y), 1.0);
	dp = smoothstep(0.0, 1.0, dp + (m - 0.5) * 0.25 * dp);
	vec3 water = mix(mix(sea, vec3(0.34, 0.76, 0.8), 0.45), deep, dp);
	vec3 col = water * (0.92 + 0.14 * m);
	col = mix(col, water * 0.82, w.y * 0.6);
	col = mix(col, mix(water, vec3(1.0), 0.5 + 0.1 * dp), w.x * 0.85);
	col *= light;
	if (night > 0.0) {
		vec2 tu = (gp - town_rect.xy) / town_rect.zw;
		vec2 tx = 1.5 / vec2(textureSize(town, 0));
		float g = (texture(town, tu).r * 2.0 + texture(town, tu + vec2(tx.x, 0.0)).r + texture(town, tu - vec2(tx.x, 0.0)).r
			+ texture(town, tu + vec2(0.0, tx.y)).r + texture(town, tu - vec2(0.0, tx.y)).r) / 6.0;
		g = smoothstep(0.01, 0.5, g) * step(0.0, min(tu.x, tu.y)) * step(max(tu.x, tu.y), 1.0);
		col += vec3(1.0, 0.72, 0.42) * 0.16 * g * night * (0.8 + 0.4 * m);
		col = mix(col, vec3(0.5, 0.58, 0.74), w.x * 0.55 * night);
		vec2 d = mix(dashes(wp, s, g), dashes(wp, s * 2.0, g), fract(lv));
		vec3 lc = d.y < 0.6 ? vec3(1.0, 0.8, 0.5) : (d.y < 0.82 ? vec3(0.88, 0.95, 1.0) : (d.y < 0.92 ? vec3(1.0, 0.45, 0.75) : vec3(0.45, 0.9, 1.0)));
		col = mix(col, lc, d.x * (0.55 + 0.45 * g) * night);
	}
	ALBEDO = col;
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
varying vec3 slope;  // a gable's face: along the ridge, up from the eave along the slope, the slope's length (metres)
varying flat float rseed;
varying flat vec2 viewl;  // run along the roof (local x, z) toward the camera per metre of height
varying flat float square;  // set square to the world, as the city's rooftop kit boxes are
const vec3 ACCENT[8] = vec3[8](vec3(0.89, 0.25, 0.22), vec3(0.96, 0.56, 0.16), vec3(0.98, 0.82, 0.25), vec3(0.24, 0.68, 0.36), vec3(0.22, 0.5, 0.86), vec3(0.6, 0.34, 0.8), vec3(0.95, 0.45, 0.65), vec3(0.2, 0.72, 0.74));
const vec3 FLOOR[4] = vec3[4](vec3(0.6, 0.46, 0.33), vec3(0.8, 0.77, 0.5), vec3(0.5, 0.6, 0.56), vec3(0.8, 0.76, 0.66));  // boards, tatami, painted concrete, tile
const vec3 ROOF[8] = vec3[8](FLAT_ROOFS);  // Sim.City.FLAT_ROOFS

void vertex() {
	info = INSTANCE_CUSTOM;
	tint = COLOR;
	lnrm = NORMAL;
	lpos = (VERTEX + 0.5) * INSTANCE_CUSTOM.xyz;
	wxz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	sunl = vec2(dot(normalize(MODEL_MATRIX[0].xz), vec2(-0.35, 0.6)), dot(normalize(MODEL_MATRIX[2].xz), vec2(-0.35, 0.6)));
	float run = length(vec2(0.5 * length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz)));
	slope = vec3(VERTEX.z * length(MODEL_MATRIX[2].xyz), (0.5 - abs(VERTEX.x)) * 2.0 * run, run);
	rseed = fract(sin(dot(MODEL_MATRIX[3].xz, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 back = INV_VIEW_MATRIX[2].xyz;
	viewl = vec2(dot(back.xz, normalize(MODEL_MATRIX[0].xz)), dot(back.xz, normalize(MODEL_MATRIX[2].xz))) / max(back.y, 0.05);
	square = abs(normalize(MODEL_MATRIX[0].xz).y) < 0.001 ? 1.0 : 0.0;
}

// a box standing on a roof, centre c, half size hs, h tall, seen from q along run (per metre of height): x 0 for bare
// roof, 1 its top, 2 its side across x, 3 its side across z; y how high up it the view meets it
vec2 stood(vec2 q, vec2 run, vec2 c, vec2 hs, float h) {
	vec2 d = vec2(abs(run.x) < 1e-4 ? 1e-4 : run.x, abs(run.y) < 1e-4 ? 1e-4 : run.y);
	vec2 t0 = (c - hs - q) / d;
	vec2 t1 = (c + hs - q) / d;
	vec2 lo = min(t0, t1);
	vec2 hi = max(t0, t1);
	float a = max(max(lo.x, lo.y), 0.0);
	float b = min(hi.x, hi.y);
	if (a > b || a > h) {
		return vec2(0.0);
	}
	return b >= h ? vec2(1.0, h) : vec2(hi.x < hi.y ? 2.0 : 3.0, b);
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

// a carton seen from above, bc from its centre, half size h: taped down its length over the flaps' seam, its edges
// lit toward the sun, and a label with a barcode in one corner on about half of them
vec3 carton(vec2 bc, vec2 h, vec3 c, vec2 sun, float r) {
	bool lx = h.x >= h.y;
	float al = lx ? bc.x : bc.y;
	float ac = lx ? bc.y : bc.x;
	vec2 ed = h - abs(bc);
	vec2 en = ed.x < ed.y ? vec2(sign(bc.x), 0.0) : vec2(0.0, sign(bc.y));
	vec3 o = c * (0.94 + 0.1 * r) * (abs(abs(ac) - 0.05) < 0.012 ? 0.84 : 1.0);
	o = abs(ac) < 0.04 ? vec3(0.86, 0.75, 0.55) * (abs(ac) < 0.008 ? 0.9 : 1.0) : o;
	vec2 hl = lx ? h : h.yx;
	vec2 lb = vec2(al - hl.x * 0.5, abs(ac) - hl.y * 0.6);
	vec2 ls = min(vec2(0.09, 0.055), hl * vec2(0.25, 0.22));
	if (r < 0.5 && abs(lb.x) < ls.x && abs(lb.y) < ls.y) {
		o = ls.y > 0.04 && abs(lb.y) < ls.y * 0.45 && fract(lb.x * 70.0) < 0.5 ? vec3(0.25) : vec3(0.93, 0.92, 0.88);
	}
	return min(ed.x, ed.y) < 0.03 ? o * (dot(en, sun) > 0.0 ? 1.18 : 0.72) : o;
}

// a tatami room laid from its corner p (metres) in the auspicious way, no four corners meeting: a row of mats standing
// down the room, then a row lying across it, its joints at the standing mats' middles. Each mat's rush catches the
// light by which way it lies, brightening toward the sun down its length; its long sides are bound in the room's cloth.
vec3 tatami(vec2 p, vec3 base, vec2 sun, float seed) {
	float row = floor(p.y / 2.73);
	float bz = p.y - row * 2.73;
	bool stand = bz < 1.82;
	float u = stand ? p.x / 0.91 : (p.x + 0.455) / 1.82;
	vec2 id = vec2(floor(u), row * 2.0 + (stand ? 0.0 : 1.0));
	float across = stand ? (fract(u) - 0.5) * 0.91 : bz - 2.275;
	float along = stand ? bz - 0.91 : (fract(u) - 0.5) * 1.82;
	float h = fract(sin(dot(id + seed * 31.0, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 c = base * (stand ? 1.05 : 0.93) * (0.96 + 0.08 * h);
	c *= 1.0 + 0.05 * along / 0.91 * (stand ? sun.y : sun.x);
	if (0.91 - abs(along) < 0.014) {
		c *= 0.78;
	}
	float hs = fract(seed * 7.31);
	vec3 heri = hs < 0.4 ? vec3(0.13, 0.16, 0.26) : (hs < 0.7 ? vec3(0.16, 0.13, 0.11) : vec3(0.13, 0.2, 0.16));
	vec2 ow = stand ? vec2(sign(across), 0.0) : vec2(0.0, sign(across));
	return 0.455 - abs(across) < 0.055 ? heri * (dot(ow, sun) > 0.0 ? 1.2 : 0.9) * (0.455 - abs(across) < 0.01 ? 0.75 : 1.0) : c;
}

// how far p (metres) is from the nearest wall of a cut-down floor plan, size across, in rooms bay by bay: outer walls
// 0.3 thick, the partitions between rooms 0.18 with a doorway in each, placed by that wall's own hash so the rooms either
// side agree; below 0 inside a wall
float plan_wall(vec2 p, vec2 size, vec2 bay, float seed) {
	vec2 e = min(p, size - p);
	vec2 rc = p / bay;
	vec2 wd = min(fract(rc), 1.0 - fract(rc)) * bay;
	vec2 bnd = floor(rc + 0.5);
	float dx = fract(sin(dot(vec2(bnd.x, floor(rc.y)) + seed * 23.0, vec2(39.35, 11.13))) * 43758.5453);
	float dz = fract(sin(dot(vec2(floor(rc.x), bnd.y) + seed * 29.0, vec2(17.71, 51.37))) * 43758.5453);
	wd.x = abs(fract(rc.y) - 0.3 - 0.4 * dx) * bay.y < 0.4 ? 1.0 : wd.x;
	wd.y = abs(fract(rc.x) - 0.3 - 0.4 * dz) * bay.x < 0.4 ? 1.0 : wd.y;
	return min(min(e.x, e.y) - 0.3, min(wd.x, wd.y) - 0.09);
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
				// the floor lies sunk below the walls' cut: look down from the cut toward the floor, and where the view meets
				// a wall on the way, show its face, lit by the way it faces and darkening to its foot
				const float SINK = 0.45;
				float wall = plan_wall(lpos.xz, info.xz, bay, seed);
				vec2 fp = lpos.xz - viewl * SINK;
				vec3 face = vec3(-1.0);
				vec2 prev = lpos.xz;
				for (int i = 1; i <= 8 && wall >= 0.0; i++) {
					vec2 sp = lpos.xz - viewl * (SINK * float(i) / 8.0);
					if (plan_wall(sp, info.xz, bay, seed) < 0.0) {
						vec2 fn = plan_wall(vec2(sp.x, prev.y), info.xz, bay, seed) < 0.0 ? vec2(sign(viewl.x), 0.0) : vec2(0.0, sign(viewl.y));
						face = tint.rgb * (dot(fn, sunl) > 0.0 ? 0.9 : 0.75) * mix(1.0, 0.8, float(i) / 8.0);
						fp = sp;
						break;
					}
					prev = sp;
				}
				vec2 rc = fp / bay;
				float r = fract(sin(dot(floor(rc) + seed * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
				int k = int(r * 4.0);
				vec2 cell = k == 0 ? vec2(0.0, 4.0) : (k == 1 ? vec2(1.1, 0.55) : (k == 2 ? vec2(0.42) : vec2(3.3)));
				vec2 g = fract(fp * cell);
				float seam = min(k == 0 ? 1.0 : min(g.x, 1.0 - g.x), min(g.y, 1.0 - g.y)) < (k == 2 ? 0.012 : 0.07) ? (k == 2 ? 0.8 : 0.84) : 1.0;
				// laid piece by piece: boards a shade apart and staggered at their butt joints, tatami (see tatami()), concrete painted, worn in patches between saw cuts
				// every 2.4 m, the kitchen's 30 cm tiles cream and buff in a check, each a shade off
				vec2 pc = floor(fp * cell);
				float ph = fract(sin(dot(pc + seed * 41.0, vec2(78.233, 12.9898))) * 43758.5453);
				if (k == 0) {
					float bu = fp.x / 1.8 + ph;
					float bh = fract(sin((pc.y * 7.0 + floor(bu) + seed * 13.0) * 12.9898) * 43758.5453);
					seam *= (0.9 + 0.16 * bh) * (min(fract(bu), 1.0 - fract(bu)) < 0.018 ? 0.84 : 1.0);
				} else if (k == 2) {
					vec2 cp = fp * 0.9 + seed * 7.0;
					vec2 ci = floor(cp);
					vec2 cf = smoothstep(0.0, 1.0, fract(cp));
					vec4 h = fract(sin(vec4(dot(ci, vec2(12.9898, 78.233)), dot(ci + vec2(1.0, 0.0), vec2(12.9898, 78.233)), dot(ci + vec2(0.0, 1.0), vec2(12.9898, 78.233)), dot(ci + 1.0, vec2(12.9898, 78.233)))) * 43758.5453);
					seam *= 0.91 + 0.14 * mix(mix(h.x, h.y, cf.x), mix(h.z, h.w, cf.x), cf.y);
				} else {
					seam *= (0.96 + 0.06 * ph) * (mod(pc.x + pc.y, 2.0) < 0.5 ? 1.04 : 0.92);
				}
				vec3 fl = FLOOR[k] * seam;
				// furnished to suit the floor: a piece against one wall (sofa, futon, steel racking, a kitchen counter)
				// and one in the room (a rug, a low table, boxes, a dining table), the standing ones shadowed off the sun
				vec2 o = floor(rc) * bay;
				vec2 lo = max(o + 0.09, vec2(0.3));
				vec2 hi = min(o + bay - 0.09, info.xz - 0.3);
				vec2 mid = (lo + hi) * 0.5;
				vec2 room = hi - lo;
				if (k == 2) {  // a yellow line painted round the storeroom, keeping the aisle clear of the racking
					vec2 ed = min(fp - lo, hi - fp);
					fl = abs(min(ed.x, ed.y) - 0.72) < 0.03 ? vec3(0.88, 0.72, 0.22) * seam : fl;
				}
				if (k == 1) {
					fl = tatami(fp - lo, FLOOR[1], sunl, fract(seed * 13.0 + r));
				}
				int side = int(fract(r * 7.13) * 4.0);
				float run = room[side / 2 == 0 ? 1 : 0] * (0.45 + 0.25 * fract(r * 3.71));
				float deep = k == 0 ? 0.85 : 0.55;
				vec2 ha = side / 2 == 0 ? vec2(deep, run) * 0.5 : vec2(run, deep) * 0.5;
				vec2 ca = mid + (side / 2 == 0 ? vec2((room.x * 0.5 - ha.x) * (side == 0 ? -1.0 : 1.0), 0.0) : vec2(0.0, (room.y * 0.5 - ha.y) * (side == 2 ? -1.0 : 1.0)));
				vec2 hb = min(room * (k == 0 ? vec2(0.24, 0.22) : vec2(0.15, 0.12)) + 0.05, vec2(0.75));
				vec2 cb = mid + (vec2(fract(r * 5.3), fract(r * 9.7)) - 0.5) * 0.25 * room + (ca - mid) * (k == 0 ? 0.25 : -0.15);  // a rug runs under the sofa's front
				vec3 ACol[4] = vec3[4](mix(ACCENT[(pick + 4) % 8], vec3(0.4), 0.35), vec3(0.93, 0.9, 0.84), vec3(0.6, 0.65, 0.7), vec3(0.9, 0.9, 0.87));
				vec3 BCol[4] = vec3[4](mix(ACCENT[(pick + int(r * 5.0) + 1) % 8], fl, 0.35), vec3(0.42, 0.27, 0.17), vec3(0.77, 0.6, 0.4), vec3(0.74, 0.56, 0.36));
				float ta = k == 1 ? 0.12 : (k == 0 ? 0.45 : 0.35);  // how far each casts its shadow: a futon barely, a sofa's back far
				float tb = k == 0 ? 0.0 : 0.25;  // a rug casts none
				vec2 da = abs(fp - ca) - ha;
				vec2 db = abs(fp - cb) - hb;
				vec2 sa = abs(fp + sunl * ta - ca) - ha;
				vec2 sb = abs(fp + sunl * tb - cb) - hb;
				float ina = max(da.x, da.y);
				float inb = fract(r * 17.0) < 0.8 ? max(db.x, db.y) : 1.0;
				// a living room's TV board against the wall facing the sofa
				vec2 tw = side / 2 == 0 ? vec2(side == 0 ? -1.0 : 1.0, 0.0) : vec2(0.0, side == 2 ? -1.0 : 1.0);
				vec2 tp = abs(tw.yx);
				vec2 ht = tw * tw * 0.19 + tp * min(run * 0.42, 0.8);
				vec2 ct = mid - tw * (dot(abs(tw), room) * 0.5 - 0.19);
				vec2 dtv = abs(fp - ct) - ht;
				vec2 stv = abs(fp + sunl * 0.3 - ct) - ht;
				float intv = k == 0 && fract(r * 19.0) < 0.7 ? max(dtv.x, dtv.y) : 1.0;
				if (min(min(max(sa.x, sa.y), tb > 0.0 && inb < 1.0 ? max(sb.x, sb.y) : 1.0), intv < 1.0 ? max(stv.x, stv.y) : 1.0) < 0.0 && min(min(ina, inb), intv) > 0.0) {
					fl *= 0.78;
				}
				if (k == 1 && fract(r * 17.0) < 0.8) {  // a zabuton on the floor at each long side of the low table
					vec2 off = hb.x >= hb.y ? vec2(0.0, hb.y + 0.3) : vec2(hb.x + 0.3, 0.0);
					vec2 z1 = abs(fp - cb - off) - 0.24;
					vec2 z2 = abs(fp - cb + off) - 0.24;
					float inz = min(max(z1.x, z1.y), max(z2.x, z2.y));
					vec2 zs1 = abs(fp + sunl * 0.07 - cb - off) - 0.24;
					vec2 zs2 = abs(fp + sunl * 0.07 - cb + off) - 0.24;
					fl *= inz > 0.0 && min(max(zs1.x, zs1.y), max(zs2.x, zs2.y)) < 0.0 ? 0.8 : 1.0;
					// stuffed plump: piped round its edge, rounding up to a tuft of thread at its middle
					vec2 zl = max(z1.x, z1.y) < max(z2.x, z2.y) ? fp - cb - off : fp - cb + off;
					vec3 zc = mix(ACCENT[(pick + 2) % 8], vec3(0.55, 0.3, 0.3), 0.35);
					float zm = max(abs(zl.x), abs(zl.y));
					float zt = zm < 0.035 && min(abs(zl.x), abs(zl.y)) < 0.012 ? 0.66 : (inz > -0.03 ? 0.74 : 0.86 + 0.18 * smoothstep(0.03, 0.17, -inz) + 0.08 * clamp(dot(zl, sunl) * 3.0, -1.0, 1.0));
					fl = inz < 0.0 ? zc * zt : fl;
				}
				if (k == 3 && inb < 1.0) {  // four chairs drawn up to the table, two a side, each shadowed, its back away from it
					bool lx = hb.x >= hb.y;
					vec2 hl = lx ? hb : hb.yx;
					float inc = 1.0;
					float shc = 1.0;
					vec2 cq = vec2(0.0);
					vec2 cout = vec2(0.0);
					for (int ci = 0; ci < 4; ci++) {
						vec2 sg = vec2(ci % 2 == 0 ? -1.0 : 1.0, ci / 2 == 0 ? -1.0 : 1.0);
						vec2 cc = cb + (lx ? vec2(sg.x * hl.x * 0.5, sg.y * (hl.y + 0.1)) : vec2(sg.y * (hl.y + 0.1), sg.x * hl.x * 0.5));
						vec2 cd = abs(fp - cc) - 0.15;
						vec2 cs = abs(fp + sunl * 0.1 - cc) - 0.15;
						if (max(cd.x, cd.y) < inc) {
							inc = max(cd.x, cd.y);
							cq = fp - cc;
							cout = lx ? vec2(0.0, sg.y) : vec2(sg.y, 0.0);
						}
						shc = min(shc, max(cs.x, cs.y));
					}
					if (inb > 0.0) {
						fl *= inc > 0.0 && shc < 0.0 ? 0.8 : 1.0;
						if (inc < 0.0) {
							float bk = dot(cq, cout);
							vec3 seat = mix(ACCENT[(pick + 3) % 8], vec3(0.85, 0.8, 0.7), 0.45);
							fl = bk > 0.095 ? vec3(0.5, 0.33, 0.2) * (bk > 0.13 ? 0.78 : 1.25) : (inc > -0.025 ? vec3(0.5, 0.33, 0.2) * (dot(cq, sunl) > 0.0 ? 1.15 : 0.75) : seat * (inc > -0.045 ? 0.88 : 1.0));
						}
					}
				}
				if (k == 0 && fract(r * 17.0) < 0.8 && inb > 0.0) {  // a fringe of cream threads off each short end of the rug
					vec2 fc = fp - cb;
					bool lx = hb.x >= hb.y;
					float fa = abs(lx ? fc.x : fc.y) - (lx ? hb.x : hb.y);
					float fw = (lx ? hb.y : hb.x) - 0.03 - abs(lx ? fc.y : fc.x);
					fl = fa < 0.07 && fw > 0.0 ? (fract((lx ? fc.y : fc.x) * 24.0) < 0.55 ? vec3(0.9, 0.86, 0.76) * (1.0 - 1.6 * fa) : fl * 0.8) : fl;
				}
				if (inb < 0.0) {
					fl = BCol[k] * (inb > -0.05 ? 0.82 : (k == 1 && inb < -0.08 ? 1.3 : 1.0));
					if (k == 0) {  // a woven rug: a dark binding, a cream border, and a medallion on a field in its own colour
						vec3 rug = mix(ACCENT[(pick + int(r * 5.0) + 1) % 8], vec3(0.34, 0.18, 0.16), 0.32);
						vec3 cream = vec3(0.9, 0.85, 0.74);
						float bw = min(hb.x, hb.y);
						vec2 dn = abs(fp - cb) / hb;
						float m = dn.x + dn.y;
						float d = -inb / bw;
						fl = d < 0.07 ? rug * 0.6 : (d < 0.2 ? cream * 0.9 : (d < 0.26 ? rug * 0.72 : (m < 0.16 ? cream : (m < 0.36 ? rug * 0.78 : (m < 0.52 ? mix(rug, cream, 0.55) : rug)))));
						vec2 pp = floor(fp * 24.0);
						fl *= 0.95 + 0.08 * fract(sin(dot(pp, vec2(12.9898, 78.233))) * 43758.5453);
					} else if (k == 1) {  // a low table: its top grained down its length, its rim lit toward the sun, tea set out on it
						vec2 tc = fp - cb;
						bool lx = hb.x >= hb.y;
						float gr = fract((lx ? tc.y : tc.x) * 11.0 + 0.35 * sin((lx ? tc.x : tc.y) * 2.6 + r * 40.0));
						vec2 en = db.x > db.y ? vec2(sign(tc.x), 0.0) : vec2(0.0, sign(tc.y));
						fl = vec3(0.52, 0.32, 0.19) * (inb > -0.05 ? (dot(en, sunl) > 0.0 ? 1.28 : 0.66) : (inb > -0.07 ? 0.86 : 0.93 + 0.12 * gr));
						if (fract(r * 23.0) < 0.75 && inb < -0.07) {
							vec2 tp = tc - (lx ? vec2(hb.x * 0.35, -hb.y * 0.2) : vec2(-hb.x * 0.2, hb.y * 0.35));
							vec2 cu = (lx ? vec2(hb.x * 0.25, 0.0) : vec2(0.0, hb.y * 0.25));
							float c1 = min(length(tc + cu - (lx ? vec2(0.0, hb.y * 0.3) : vec2(hb.x * 0.3, 0.0))), length(tc + cu + (lx ? vec2(0.0, hb.y * 0.3) : vec2(hb.x * 0.3, 0.0))));
							float c1s = min(length(tc + sunl * 0.04 + cu - (lx ? vec2(0.0, hb.y * 0.3) : vec2(hb.x * 0.3, 0.0))), length(tc + sunl * 0.04 + cu + (lx ? vec2(0.0, hb.y * 0.3) : vec2(hb.x * 0.3, 0.0))));
							fl *= length(tp + sunl * 0.07) < 0.08 || c1s < 0.04 ? 0.72 : 1.0;
							fl = c1 < 0.04 ? (c1 < 0.022 ? vec3(0.55, 0.6, 0.28) : vec3(0.92, 0.9, 0.84)) : fl;
							float pl = length(tp);
							fl = pl < 0.08 ? vec3(0.22, 0.23, 0.25) * (pl < 0.018 ? 0.7 : (length(tp - sunl * 0.035) < 0.025 ? 2.2 : (pl > 0.065 ? 0.8 : 1.0))) : fl;
						}
					} else if (k == 2) {  // a stack of cartons: a smaller one set on the big one, laying its shadow across it
						vec2 tc = fp - cb;
						bool lx = hb.x >= hb.y;
						vec2 c2 = lx ? vec2(-hb.x * 0.35, hb.y * 0.12) : vec2(hb.x * 0.12, -hb.y * 0.35);
						vec2 h2 = hb * (lx ? vec2(0.5, 0.62) : vec2(0.62, 0.5));
						vec2 d2 = abs(tc - c2) - h2;
						vec2 s2 = abs(tc + sunl * 0.12 - c2) - h2;
						fl = max(d2.x, d2.y) < 0.0 ? carton(tc - c2, h2, BCol[2] * 1.06, sunl, fract(r * 43.0)) : carton(tc, hb, BCol[2], sunl, fract(r * 47.0)) * (max(s2.x, s2.y) < 0.0 ? 0.78 : 1.0);
					} else {  // a dining table: its top grained along its length, its rim lit toward the sun, a fruit bowl at its middle
						vec2 tc = fp - cb;
						bool lx = hb.x >= hb.y;
						float gr = fract((lx ? tc.y : tc.x) * 9.0 + 0.3 * sin((lx ? tc.x : tc.y) * 2.2 + r * 40.0));
						vec2 en = db.x > db.y ? vec2(sign(tc.x), 0.0) : vec2(0.0, sign(tc.y));
						fl = vec3(0.68, 0.48, 0.3) * (inb > -0.04 ? (dot(en, sunl) > 0.0 ? 1.22 : 0.7) : 0.93 + 0.1 * gr);
						fl *= inb < -0.04 && length(tc + sunl * 0.05) < 0.12 ? 0.8 : 1.0;
						float bl = length(tc);
						vec2 fr = tc - vec2(0.03, 0.02);
						fl = bl < 0.12 ? (bl > 0.095 ? vec3(0.95, 0.94, 0.9) * (dot(tc, sunl) > 0.0 ? 1.0 : 0.8) : (length(fr) < 0.045 ? vec3(0.95, 0.55, 0.15) : (length(tc + vec2(0.04, -0.03)) < 0.04 ? vec3(0.8, 0.2, 0.18) : vec3(0.98, 0.85, 0.3)))) : fl;
					}
				}
				if (intv < 0.0) {  // low and white-lacquered, its top lit along the front, the set's slim black panel standing at the back on its foot
					vec2 tl = fp - ct;
					float tac = 0.19 + dot(tl, tw);
					float tal = dot(tl, tp) + ht.x * tp.x + ht.y * tp.y;
					float tlen = 2.0 * dot(ht, tp);
					fl = vec3(0.9, 0.88, 0.84) * (intv > -0.03 ? (dot(tw, sunl) > 0.0 ? 1.08 : 0.7) : 0.95 + 0.1 * fract(tal * 7.0 + 0.3 * sin(tac * 9.0)));
					float tvh = tlen * 0.42;
					float tvc = abs(tal - tlen * 0.5);
					fl *= tvc < tvh && abs(tac - 0.12) < 0.07 && tac > 0.12 ? 0.75 : 1.0;
					fl = tvc < tvh && abs(tac - 0.08) < 0.035 ? vec3(0.08, 0.09, 0.1) * (abs(tac - 0.11) < 0.008 ? 2.6 : 1.0) : fl;
					fl = tvc < 0.14 && abs(tac - 0.15) < 0.05 ? vec3(0.14, 0.15, 0.16) * (tac > 0.18 ? 1.5 : 1.0) : fl;
					fl = abs(tal - tlen * 0.86) < 0.05 && abs(tac - 0.24) < 0.06 ? vec3(0.3, 0.55, 0.3) * (length(vec2(tal - tlen * 0.86, tac - 0.24) + sunl * 0.02) < 0.035 ? 1.3 : 0.85) : fl;
				}
				if (ina < 0.0) {
					fl = ACol[k] * (ina > -0.05 ? 0.8 : 1.0);
					if (k == 0) {  // a sofa: a cushioned back to the wall and a rolled arm each end round a seat of plump cushions
						vec2 lc = fp - ca;
						float across = (side % 2 == 0 ? 1.0 : -1.0) * (side / 2 == 0 ? lc.x : lc.y) + (side / 2 == 0 ? ha.x : ha.y);
						float along = (side / 2 == 0 ? lc.y : lc.x) + run * 0.5;
						vec2 outw = -tw;
						float sa2 = dot(sunl, tp);  // the sun along the sofa
						float n = run > 1.7 ? 3.0 : 2.0;
						vec3 c0 = ACol[k];
						float am = 0.17;
						float bk = 0.24;
						float sl = run - 2.0 * am;
						float ci = clamp(floor((along - am) / sl * n), 0.0, n - 1.0);
						float cl = along - am - ci * sl / n;
						float ce = min(min(cl, sl / n - cl), min(across - bk, deep - across));  // how far inside its seat cushion
						float be = min(min(along - am, run - am - along), bk - across);  // inside the back
						if (ina > -0.035) {  // the frame's edge: its front face toward the sun or away
							fl = c0 * (deep - across < 0.04 ? (dot(outw, sunl) > 0.0 ? 0.9 : 0.6) : 0.62);
						} else if (along < am || along > run - am) {  // the arms, rounded over the top and shaded on the inside face
							float ai = along < am ? am - along : along - run + am;
							float ab = 1.0 - abs(ai / am - 0.5) * 2.0;
							fl = c0 * (ai < 0.035 ? (sign(along - run * 0.5) * sa2 < 0.0 ? 0.8 : 1.12) : 1.0 + 0.24 * ab);
						} else if (across < bk) {  // the back cushions, lit along their top roll
							float bc = abs(fract((along - am) / sl * n) - 0.5) * sl / n;
							fl = c0 * (be < 0.03 ? 0.62 : (bc > sl / n * 0.5 - 0.02 ? 0.85 : 1.02 + 0.3 * (1.0 - abs(across / bk - 0.45) * 2.0)));
						} else {  // the seat cushions, puffed up toward their middles and shaded where they tuck under the back
							float puff = smoothstep(0.0, 0.12, ce);
							fl = c0 * (ce < 0.018 ? 0.62 : 0.74 + 0.22 * puff + 0.05 * clamp(dot(vec2(cl - sl / n * 0.5, across - (bk + deep) * 0.5), vec2(sa2, dot(sunl, outw))) * 4.0, -1.0, 1.0));
							fl *= across - bk < 0.08 ? 0.72 : 1.0;
						}
						// a throw cushion propped in each corner, set on its point, laying a shadow on the seat
						for (int ti = 0; ti < 2; ti++) {
							float tc = ti == 0 ? am + 0.22 : run - am - 0.22;
							vec2 tq = vec2(along - tc, across - bk - 0.1);
							float tdm = abs(tq.x) + abs(tq.y);
							float tds = abs(tq.x + sa2 * 0.06) + abs(tq.y + dot(sunl, outw) * 0.06);
							vec3 tcol = ti == 0 ? vec3(0.92, 0.87, 0.76) : mix(ACCENT[(pick + 6) % 8], vec3(0.9), 0.25);
							if (ina < -0.035 && fract(r * (ti == 0 ? 53.0 : 59.0)) < 0.75) {
								fl = tdm < 0.2 ? tcol * (tdm > 0.175 ? 0.78 : 0.95 + 0.15 * clamp(dot(tq, vec2(sa2, dot(sunl, outw))) * 6.0, -1.0, 1.0)) : (tds < 0.2 && across > bk ? fl * 0.74 : fl);
							}
						}
					} else if (k == 1) {  // a futon: a patterned quilt turned down below the pillow, the mattress showing round them
						vec2 lc = fp - ca;
						float al = (side / 2 == 0 ? lc.y : lc.x) + run * 0.5;
						float ac = side / 2 == 0 ? lc.x : lc.y;
						float hw = 0.5 * deep;
						float qr = fract(r * 31.7);
						vec3 quilt = qr < 0.5 ? vec3(0.3, 0.42, 0.68) : (qr < 0.75 ? vec3(0.78, 0.46, 0.5) : vec3(0.46, 0.58, 0.42));
						float qe = min(min(al - 0.03, run - 0.44 - al), hw - 0.02 - abs(ac));
						vec2 pq = vec2(run - 0.22 - al, 0.17 - abs(ac));
						if (ina > -0.04) {
							fl *= dot(side / 2 == 0 ? vec2(sign(lc.x), 0.0) : vec2(0.0, sign(lc.y)), sunl) > 0.0 ? 1.1 : 0.9;
						} else if (qe > 0.0) {
							vec2 kp = vec2(al, ac + floor(al / 0.16) * 0.08) / 0.16;
							vec2 kf = abs(fract(kp) - 0.5);
							float body = 1.06 - 0.24 * smoothstep(hw * 0.35, hw, abs(ac)) + 0.06 * sign(ac) * sign(dot(side / 2 == 0 ? vec2(1.0, 0.0) : vec2(0.0, 1.0), sunl));
							fl = run - 0.44 - al < 0.13 ? mix(quilt, vec3(0.95, 0.93, 0.88), 0.72) * (run - 0.44 - al < 0.025 ? 1.08 : 0.96) : quilt * body * (min(kf.x, kf.y) < 0.07 && max(kf.x, kf.y) < 0.28 ? 1.32 : 1.0);
							fl *= qe < 0.025 ? 0.8 : (abs(run - 0.57 - al) < 0.025 ? 0.7 : 1.0);
						} else if (abs(pq.x) < 0.14 && pq.y > 0.0) {
							float pe = min(0.14 - abs(pq.x), pq.y);
							fl = vec3(0.88, 0.82, 0.68) * (pe < 0.025 ? 0.8 : 0.94 + 0.12 * smoothstep(0.02, 0.1, pe));
						} else {
							fl *= run - 0.44 - al > -0.04 && al < run ? 0.84 : 1.0;
						}
					} else {  // steel racking or a kitchen counter, both seen from above against the wall
						vec2 lc = fp - ca;
						float across = (side % 2 == 0 ? 1.0 : -1.0) * (side / 2 == 0 ? lc.x : lc.y) + (side / 2 == 0 ? ha.x : ha.y);
						float along = (side / 2 == 0 ? lc.y : lc.x) + run * 0.5;
						vec2 outw = side / 2 == 0 ? vec2(side == 0 ? 1.0 : -1.0, 0.0) : vec2(0.0, side == 2 ? 1.0 : -1.0);
						vec2 s2 = vec2(dot(sunl, side / 2 == 0 ? vec2(0.0, 1.0) : vec2(1.0, 0.0)), dot(sunl, outw));
						if (k == 2) {  // racking: goods on its perforated top shelf, a beam front and back, an end frame each bay
							float nb = max(1.0, floor(run / 0.8 + 0.5));
							float bl = run / nb;
							float bi = floor(along / bl);
							float ba = along - bi * bl;
							float hf = step(bl * 0.5, ba);
							float ih = fract(sin(dot(vec2(bi, hf) + r * 61.0, vec2(12.9898, 78.233))) * 43758.5453);
							float a0 = bi * bl + hf * bl * 0.5 + 0.06;
							float a1 = bi * bl + (hf + 1.0) * bl * 0.5 - 0.04;
							float d1 = deep - 0.07 - 0.1 * fract(ih * 7.0);
							vec2 ihs = vec2(a1 - a0, d1 - 0.05) * 0.5;
							vec2 ip = vec2(along - (a0 + a1) * 0.5, across - (0.05 + d1) * 0.5);
							vec2 ie = abs(ip) - ihs;
							vec2 ish = abs(ip + s2 * 0.08) - ihs;
							fl = vec3(0.6, 0.64, 0.68) * (fract(along * 14.0) < 0.3 && fract(across * 14.0) < 0.3 ? 0.84 : 1.0) * (ih > 0.15 && max(ish.x, ish.y) < 0.0 ? 0.74 : 1.0);
							if (ih > 0.15 && max(ie.x, ie.y) < 0.0) {
								if (ih < 0.7) {
									fl = carton(ip, ihs, vec3(0.77, 0.6, 0.4), s2, fract(ih * 13.0));
								} else {  // a plastic tote, its rim lit and its sunny side wall shading the inside
									vec3 bc = mix(ACCENT[int(ih * 37.0) % 8], vec3(0.55), 0.3);
									vec2 bq = abs(ip + s2 * 0.07) - (ihs - 0.025);
									fl = min(-ie.x, -ie.y) < 0.025 ? bc * 1.15 : bc * (max(bq.x, bq.y) > 0.0 ? 0.55 : 0.75);
								}
							}
							fl = ba < 0.03 || ba > bl - 0.03 ? vec3(0.36, 0.4, 0.46) : fl;
							fl = across < 0.035 || across > deep - 0.035 ? vec3(0.4, 0.44, 0.5) * (across > deep * 0.5 ? 1.25 : 1.0) : fl;
						} else {  // the counter: a speckled worktop lit along its front, tiles up the wall, a sink and a hob
							fl = vec3(0.9, 0.9, 0.87) * (0.97 + 0.05 * fract(sin(dot(floor(fp * 20.0), vec2(12.9898, 78.233))) * 43758.5453));
							fl = across > deep - 0.03 ? fl * (dot(outw, sunl) > 0.0 ? 1.08 : 0.78) : (across < 0.06 ? vec3(0.78, 0.86, 0.85) * (fract(along * 10.0) < 0.12 ? 0.82 : 1.0) : fl);
							vec2 sp = vec2(along - run * 0.3, across - deep * 0.55);
							vec2 sh = vec2(min(0.18, run * 0.13), 0.12);
							vec2 se = abs(sp) - sh;
							if (max(se.x, se.y) < 0.0) {
								vec2 sq = abs(sp + s2 * 0.06) - (sh - 0.03);
								fl = max(se.x, se.y) > -0.03 ? vec3(0.74, 0.77, 0.8) : (length(sp) < 0.02 ? vec3(0.3) : vec3(0.62, 0.66, 0.7) * (max(sq.x, sq.y) > 0.0 ? 0.72 : 1.0));
							}
							fl = length(sp - vec2(0.0, -sh.y - 0.035)) < 0.025 ? vec3(0.8, 0.82, 0.85) : fl;
							vec2 hp = vec2(along - run * 0.74, across - deep * 0.52);
							vec2 hh = vec2(min(0.2, run * 0.15), 0.13);
							vec2 he = abs(hp) - hh;
							if (max(he.x, he.y) < 0.0) {
								float rg = length(vec2(abs(hp.x) - hh.x * 0.5, hp.y));
								fl = vec3(0.15, 0.16, 0.18) * (abs(rg - 0.06) < 0.012 ? 2.6 : (hp.x + hp.y > hh.x * 0.6 && hp.x + hp.y < hh.x * 0.8 ? 1.8 : 1.0));
							}
						}
					}
				}
				// and each wall casts its shadow across the floor away from the sun
				float cast = min(plan_wall(fp + sunl * 0.3, info.xz, bay, seed), plan_wall(fp + sunl * 0.6, info.xz, bay, seed));
				fl *= mix(0.72, 1.0, smoothstep(0.0, 0.5, plan_wall(fp, info.xz, bay, seed))) * (cast < 0.0 ? 0.8 : 1.0);
				fl = face.r >= 0.0 ? face : fl;
				// after dark a lit room glows warm in a pool round the ceiling light over its middle, dimming to its corners,
				// and the rooms left dark fall into shadow
				float on = step(0.5, fract(r * 13.0)) * switched(fract(r * 29.0), night);
				vec2 rm = (fract(rc) - 0.5) * 2.0;
				float pool = 0.2 + exp(-2.2 * dot(rm, rm));
				col = wall < 0.0 ? tint.rgb * 1.08 : fl * (1.0 - 0.4 * night * (1.0 - on));
				// windows cut through the outer walls below the cut: the reveal down to the sill, the glass's section across it
				bool along_x = e.y < e.x;
				float win = window_in(along_x ? lpos.x : lpos.z, along_x ? bay.x : bay.y, along_x ? step(info.z * 0.5, lpos.z) : 2.0 + step(info.x * 0.5, lpos.x), seed);
				if (min(e.x, e.y) < 0.3 && win > 0.0) {
					col = win < 0.05 ? vec3(0.78, 0.8, 0.82) : (abs(min(e.x, e.y) - 0.15) < 0.035 ? vec3(0.72, 0.86, 0.92) : tint.rgb * 0.8);
				}
				glow = wall < 0.0 ? vec3(0.0) : fl * vec3(1.0, 0.84, 0.58) * pool * on * 0.6;
			} else {  // a flat roof: coping round a parapet that shades the roof on its sunny sides, membrane in strips, a hatch
				vec2 q = lpos.xz;
				float fine = 1.0 - smoothstep(0.1, 0.3, fwidth(q.x) + fwidth(q.y));
				float u = (info.x >= info.z ? q.y : q.x) / 1.2;
				float lane = fract(sin((floor(u) + seed * 53.0) * 12.9898) * 43758.5453);
				float f = mix(1.0, (0.95 + 0.07 * lane) * (min(fract(u), 1.0 - fract(u)) < 0.035 ? 0.88 : 1.0), fine) * 0.92;
				vec2 into = vec2(sunl.x < 0.0 ? q.x : info.x - q.x, sunl.y > 0.0 ? info.z - q.y : q.y) - 0.3;
				float shadow = max(step(0.0, into.x) * step(into.x, 0.7 * abs(sunl.x)), step(0.0, into.y) * step(into.y, 0.7 * abs(sunl.y)));
				f *= 1.0 - 0.2 * shadow;
				vec4 over = vec4(0.0);  // kit painted over the membrane, and how strongly
				if (min(info.x, info.z) > 3.5) {
					// drawn while a few pixels across: grime in broad patches, a drain in one corner with rain ponded round it
					float near = 1.0 - smoothstep(0.25, 0.7, fwidth(q.x) + fwidth(q.y));
					vec2 mp = q * 0.35 + seed * 17.0;
					vec2 mi = floor(mp);
					vec2 mf = smoothstep(0.0, 1.0, fract(mp));
					vec4 mh = fract(sin(vec4(dot(mi, vec2(12.9898, 78.233)), dot(mi + vec2(1.0, 0.0), vec2(12.9898, 78.233)), dot(mi + vec2(0.0, 1.0), vec2(12.9898, 78.233)), dot(mi + 1.0, vec2(12.9898, 78.233)))) * 43758.5453);
					float grime = 0.88 + 0.16 * mix(mix(mh.x, mh.y, mf.x), mix(mh.z, mh.w, mf.x), mf.y);
					vec2 dr = vec2(fract(seed * 5.7) < 0.5 ? 0.75 : info.x - 0.75, fract(seed * 8.3) < 0.5 ? 0.75 : info.z - 0.75);
					vec2 dv = q - dr;
					float dd = length(dv);
					float pond = (0.9 + 1.1 * fract(seed * 11.3)) * (1.0 + 0.14 * sin(atan(dv.y, dv.x) * 5.0 + seed * 9.0));
					float wet = dd < 0.12 ? 0.45 : (dd < 0.18 ? 1.08 : (dd < pond ? (pond - dd < 0.07 ? 0.84 : 0.92) : 1.0));
					f *= mix(1.0, grime * wet, near);
					// the plant room on most roofs (kit_box) lays its shadow across the membrane
					float k = seed / 0.98;
					vec3 ks = vec3(1.6 + 1.6 * k, 1.2, 1.4 + 1.8 * (1.0 - k));
					vec2 kc = vec2(1.0 + ks.x / 2.0 + (info.x - ks.x - 2.0) * k, 1.0 + ks.z / 2.0 + (info.z - ks.z - 2.0) * (1.0 - k));
					bool boxed = square > 0.5 && info.y > 8.9 && min(info.x, info.z) > 6.0;
					if (boxed && stood(q, sunl, kc, ks.xz / 2.0, ks.y).x > 0.5) {
						f *= mix(1.0, 0.78, near);
					}
					vec2 hc = info.xz * vec2(0.22 + 0.56 * fract(seed * 7.31), 0.25 + 0.5 * fract(seed * 3.17));
					vec2 hd = abs(q - hc);
					vec2 sd = abs(q - hc + sunl * 0.45);
					f = max(hd.x, hd.y) < 0.5 ? (max(hd.x, hd.y) < 0.4 ? 1.12 : 0.8) : (max(sd.x, sd.y) < 0.5 ? f * 0.78 : f);
					// air-conditioning condensers in a row across the roof from the plant room, each shadowed off the sun, its
					// casing louvred on top and its fan grille on the long side
					if (min(info.x, info.z) > 5.0) {
						float az = k < 0.5 ? 1.7 : info.z - 1.7;
						float best = -1e9;
						for (int i = 0; i < 4; i++) {
							if (float(i) >= clamp(floor(info.x * 0.3 / 1.25), 1.0, 4.0)) {
								break;
							}
							vec2 c = vec2(k < 0.5 ? info.x - 1.8 - 1.25 * float(i) : 1.8 + 1.25 * float(i), az);
							vec2 kd = abs(c - kc) - ks.xz / 2.0;
							if (length(c - hc) < 1.3 || boxed && max(kd.x, kd.y) < 0.9) {
								continue;
							}
							vec2 hs = vec2(0.45, 0.22);
							if (stood(q, sunl, c, hs, 0.7).x > 0.5) {
								f *= mix(1.0, 0.78, near);
							}
							vec2 s = stood(q, viewl, c, hs, 0.7);
							float depth = dot(c, viewl);
							if (s.x > 0.5 && depth > best) {
								best = depth;
								vec2 at = q + viewl * s.y - c;
								vec3 cas = vec3(0.86, 0.86, 0.83);
								vec3 uc;
								if (s.x < 1.5) {
									uc = cas * (fract(at.x * 9.0) < 0.3 ? 0.9 : 1.0);
								} else if (s.x < 2.5) {
									uc = cas * (dot(vec2(sign(viewl.x), 0.0), sunl) > 0.0 ? 0.9 : 0.75);
								} else {
									float fan = length(vec2(at.x + 0.1, s.y - 0.35));
									uc = cas * (dot(vec2(0.0, sign(viewl.y)), sunl) > 0.0 ? 0.9 : 0.75) * (fan < 0.22 ? (fan < 0.04 || abs(fan - 0.13) < 0.02 ? 0.75 : 0.45) : 1.0);
								}
								over = vec4(uc, near);
							}
						}
					}
				}
				col = mix(mix(ROOF[pick], tint.rgb, ROOF_TINT) * (min(e.x, e.y) < 0.3 ? 1.14 : f), over.rgb, over.a);
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
			float lit = step(0.6, r);
			float sw = fract(r * 29.0);
			if (info.y > 24.0 && row > 0.5) {
				// a tower's offices light floor by floor, the same floor all the way round: a working floor's bays nearly all
				// on in office white, a few lit at random on the dark ones, a warmer floor here and there
				float fl = fract(sin(dot(vec2(floor(cont.y), seed * 53.0), vec2(12.9898, 78.233))) * 43758.5453);
				float on = fl < 0.42 ? 1.0 : 0.0;
				lit = mix(step(0.88, fract(r * 7.13)), step(0.1, fract(r * 7.13)), on);
				lamp = fl < 0.34 ? vec3(0.86, 0.92, 1.0) : vec3(1.0, 0.84, 0.56);
				sw = mix(sw, fract(fl * 37.0), on);
				// a cell under two pixels blurs to its floor's share of light, a floor under two to the tower's
				float fx = smoothstep(0.5, 1.0, fwidth(cont.x));
				float fy = smoothstep(0.5, 1.0, fwidth(cont.y));
				lit = mix(mix(lit, mix(0.12, 0.9, on), fx), 0.45, fy);
				lamp *= 0.88 + 0.12 * fract(r * 3.7);
			}
			// a lit pane is the room behind it, not white glass: brightest up under its ceiling light, warming and dimming
			// toward the sill, each room a little brighter or dimmer than its neighbours, the glass's own sheen dropping out
			float pane = m.g * (1.0 - m.b) * lit * switched(sw, night);
			// (a storey under a few pixels, as on the city map, keeps its plain glow so the lit floors still read)
			float tiny = smoothstep(0.12, 0.35, fwidth(cont.y));
			vec3 room = lamp * mix(mix(lamp.b > lamp.r ? vec3(0.58, 0.6, 0.64) : vec3(0.6, 0.47, 0.36), vec3(1.0), smoothstep(0.2, 0.85, fract(cont.y))) * (0.8 + 0.2 * fract(r * 5.3)), vec3(1.0), tiny);
			col *= 1.0 - 0.65 * pane * (1.0 - tiny);
			glow = pane * room + m.r * ACCENT[pick] * 0.9 * switched(0.1 * fract(r * 17.0), night);
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
	} else if (info.w < -0.5 && lnrm.y > 0.2 && lnrm.y < 0.98) {  // a gable's slope: kawara in courses, or ribbed sheet metal
		vec2 q = slope.xy;
		float fine = 1.0 - smoothstep(0.035, 0.11, max(fwidth(q.x), fwidth(q.y)));
		float f = 1.0;
		if (rseed < 0.72) {  // tiles laid in columns of rolls, each course's lip lit over the shadow it casts down the slope
			vec2 c = vec2(q.x / 0.3, q.y / 0.28);
			vec2 cf = fract(c);
			float tone = fract(sin(dot(floor(c) + rseed * 41.0, vec2(12.9898, 78.233))) * 43758.5453);
			f = (1.0 + 0.09 * sin(cf.x * 6.2832)) * (0.95 + 0.08 * tone) * (cf.y > 0.82 ? 0.78 : (cf.y < 0.08 ? 1.1 : 1.0));
		} else {  // standing seams every 45 cm, each lit on one side and shaded on the other, weathered in streaks
			float s = fract(q.x / 0.45);
			float streak = fract(sin(floor(q.x / 0.15) * 12.9898 + rseed * 7.0) * 43758.5453);
			f = (s < 0.06 ? 1.16 : (s < 0.14 ? 0.82 : 1.0)) * (0.96 + 0.05 * streak);
		}
		float up = slope.z - q.y;
		f = up < 0.2 ? (up < 0.05 ? 1.12 : 0.8) : (q.y < 0.1 ? 0.7 : f);  // the ridge cap, and the eave's edge
		col = tint.rgb * mix(1.0, f, fine);
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
var floor_tex := {}  # shop floor texture by left wall and fixtures
var sun_gate_tex := {}  # what each pane of the glass front lets through, by left wall
var set_sig := ""
var tarmac_m: StandardMaterial3D
var slabs_m: StandardMaterial3D
var plot_m: StandardMaterial3D  # a vacant lot on the city map
var tactile_m: StandardMaterial3D
var car_park_m: StandardMaterial3D
var road_paint_m: StandardMaterial3D
var side_tar_m: StandardMaterial3D
var manhole_m: StandardMaterial3D
var tree_pit_m: StandardMaterial3D
var condenser_m: StandardMaterial3D
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
var faces := {}  # the rival chains' mascot roundels for the plate over their roofs, by chain
var roof_texs := {}  # the rival's roof by the width of its shop, and the vacant unit's by minus its width
var glass_sheen: StandardMaterial3D  # the knee-height glass front's sheen, tiled per run
var skylight_pair: Array = []  # weakrefs to the rival's skylight glass, its night glow and its unlit glass, shared by both skylights

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
var farms: Array = []  # farmsteads out in the fields past the built-up edge: buildings like the city's
var farm_grounds: Array = []  # [rect, gravel yard or greenhouse soil]
var built := {}  # 64 m cell -> footprints of the city's blocks, buildings and landmarks in it
var farm_yards := {}  # 64 m cell -> the farmsteads' yards in it, kept clear of fields, lanes and woods
var box_mm: MultiMesh
var box_base: Array = []
var building_mat: ShaderMaterial
var roof_mm: MultiMesh
var roof_base: Array = []
var pillar_mm: MultiMesh
var tree_mms: Array = []  # [MultiMesh, base transforms, height, its shadows' MultiMesh]
var tree_shadow_mat: ShaderMaterial
var mask_vp: SubViewport  # the city seen from the sun, for ground shadows
var shadow_mat: ShaderMaterial
var run_off_shadow_mat: StandardMaterial3D  # the shadows the expressway lays out of town, past shadow_mat's reach
var env: Environment
var light := Color.WHITE  # the hour's tint (DAYLIGHT)
var night := 0.0  # 0 by day, 1 from 22:00, fading out at first light: lit windows and lamp pools
var lit_mats: Array = []  # [weakref to an outdoor material (or a sign's Label3D), its own colour, how far it lights up after dark (lightboxes)]
var lit_sprites: Array = []  # outdoor sprites that stand still, relit when the light changes
var pools: Array = []  # Vector3(x, z, radius) in the world: lamp light on the street after dark
var pool_mat: StandardMaterial3D
var street_pool_mat: StandardMaterial3D  # a street lamp's pool: a broad, evenly lit core with a soft rim
var lamp_mat: StandardMaterial3D  # street lamp heads: pale by day, lit after dark
var halo_mat: StandardMaterial3D  # the glow round a lit lamp head
var glare_mat: StandardMaterial3D  # the hot glare of a lit lamp head's lens
var beam_mat: StandardMaterial3D  # the cone of light falling from a lit lamp head to its pool
var headlight_mat: StandardMaterial3D  # a moving car's low beams thrown along the road ahead
var tail_glow_mat: StandardMaterial3D  # the red its tail lamps cast on the road behind
var spill_mat: StandardMaterial3D  # shop light falling out of a glass front across the sidewalk
var shop_spill_mat: StandardMaterial3D  # the same out of your own shop, which a blackout puts out
var rival_spill_mat: StandardMaterial3D  # the same out of the rival's glass front, by its mullions and door
var room_dim := Color.WHITE  # your shop's lighting, dimmed while a blackout has cut its power
var set_sign_mats: Array = []  # your pole sign's lightbox faces on the set
var breaker_lamp: Array = []  # [the tripped board's lamp, its glow]
var flood_mat: StandardMaterial3D  # your car park's floodlight on the bays
var sign_glow_mat: StandardMaterial3D  # the glow round your lit pole sign
var fascia_glows: Array = []  # [weakref to the glow round a rival's lit fascia, its chain's colour]
var fascia_glow_tex: ImageTexture
var snow_tex: ImageTexture  # patchy settled snow, tiled 8 m
var snow_walk_tex: ImageTexture  # a sidewalk's snow across its 3.5 m from wall to kerb, tiled 8 m along it
var snow_lot_tex: ImageTexture  # the car park's ploughed snow
var snow_cover: MeshInstance3D  # the set's snowy ground, shown on a cold snap
var matsuri: Node3D  # the set's festival lanterns and yatai, shown on a Summer Matsuri
var lantern_glow_mat: StandardMaterial3D
var lantern_pool_mat: StandardMaterial3D  # the matsuri lanterns' warm light on the sidewalk under their strings
var stall_glow_mat: StandardMaterial3D  # the yatai's lamplight on the bay after dark
var works: Node3D  # the set's roadworks, shown on a Roadworks day
var works_glow_mat: StandardMaterial3D  # the works' flashing lamps and arrow board after dark
var car_lamp_tex: ImageTexture  # the vehicles sheet's lamps lit, frame for frame, over a clear ground
var tv: Node3D  # the set's TV crew, shown on a TV Feature day
var health: Node3D  # the health centre's wagon and a sanitiser stand, shown on a Health Inspection day
var heat: Node3D  # a shaved-ice stand and a splashed sidewalk, shown on a Heatwave day
var sale: Node3D  # the rival's sale flags along its front and posters on its glass, shown through a price war
var wall_bikes: Node3D  # the bicycles along your shop's wall, wheeled off when an event's stall or van takes the bay
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
var awning_mat: StandardMaterial3D  # the sun's shadow of the rival's canopy down its glass
var casts: Array = []  # those shadows, stretched as the sun goes down
var foot_mat: ShaderMaterial  # people's shadows
var sun_in_mat: ShaderMaterial  # daylight through your shop's glass front, over its floor
var foot_mesh: PlaneMesh
var foot_lamps := []  # the lights people's shadows fall away from after dark, as last sent to foot_mat
var sea_mat: StandardMaterial3D
var shore_mat: StandardMaterial3D  # foam and shallows, dimmed after dark with the sea
var field_mat: ShaderMaterial
var road_lights: MeshInstance3D  # the map's streetlights on its roads and the expressway, only on the map
var road_light_mats: Array = []
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
var screen_rect: TextureRect  # the 3D view's picture; a heatwave's air wavers it (HEAT_SHADER)
var heat_mat: ShaderMaterial
var vp_scale := 1.0  # real pixels per UI unit
var cam: Camera3D
var room: Node3D
var street: Node3D
var set_node: Node3D
var actors: Node3D
var overlay: Control
var hud_card := Rect2()  # the HUD's store card over the view: the rival's pin keeps clear of it
var hud_keep: Array = []  # the HUD's chips and buttons over the city map: its labels keep clear of them
var hud_dock: Array = []  # the HUD's store tabs and bottom buttons over the street: threat tags stack up clear of them


func _ready() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	screen_rect = TextureRect.new()
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
	env.background_color = SEA_DEEP  # open sea round the island
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	pool_mat = StandardMaterial3D.new()
	pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pool_mat.albedo_texture = radial([Color.WHITE, Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)], [0.0, 0.4, 1.0])
	pool_mat.albedo_color = Color(0, 0, 0, 0)
	street_pool_mat = pool_mat.duplicate()
	var spot := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			spot.set_pixel(x, y, Color(1, 1, 1, 0.6 * smoothstep(1.0, 0.3, d) + 0.4 * smoothstep(0.5, 0.0, d)))
	street_pool_mat.albedo_texture = ImageTexture.create_from_image(spot)
	halo_mat = pool_mat.duplicate()
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spill_mat = pool_mat.duplicate()
	flood_mat = pool_mat.duplicate()
	sign_glow_mat = halo_mat.duplicate()
	lantern_glow_mat = halo_mat.duplicate()
	lantern_pool_mat = pool_mat.duplicate()
	stall_glow_mat = pool_mat.duplicate()
	works_glow_mat = halo_mat.duplicate()
	var fall := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var u := x / 63.0
			fall.set_pixel(x, y, Color(1, 1, 1, (exp(-2.2 * y / 31.0) - exp(-2.2)) / (1.0 - exp(-2.2)) * smoothstep(0.0, 0.2, u) * smoothstep(0.0, 0.2, 1.0 - u)))
	spill_mat.albedo_texture = ImageTexture.create_from_image(fall)
	shop_spill_mat = spill_mat.duplicate()
	rival_spill_mat = spill_mat.duplicate()
	var halo := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 64:
			var d := Vector2(maxf(absf(x - 31.5) - 22.0, 0.0) / 10.0, maxf(absf(y - 7.5) - 2.0, 0.0) / 6.0).length()
			halo.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
	fascia_glow_tex = ImageTexture.create_from_image(halo)
	var ring := Image.create(32, 32, false, Image.FORMAT_RGBA8)  # the pole sign's: even all round its cabinet
	for y in 32:
		for x in 32:
			var d := Vector2(maxf(absf(x - 15.5) - 9.0, 0.0), maxf(absf(y - 15.5) - 9.0, 0.0)).length() / 6.5
			ring.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.0)))
	sign_glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	sign_glow_mat.albedo_texture = ImageTexture.create_from_image(ring)
	glare_mat = halo_mat.duplicate()
	glare_mat.albedo_texture = radial([Color.WHITE, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)], [0.0, 0.14, 0.38, 1.0])
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
	headlight_mat = pool_mat.duplicate()
	var throw := Image.create(64, 32, false, Image.FORMAT_RGBA8)  # forward along x: two lamps fanning into one wash
	for y in 32:
		var v := (y - 15.5) / 32.0
		for x in 64:
			var u := x / 63.0
			var hw := lerpf(0.16, 0.4, sqrt(u))
			var side := maxf(smoothstep(hw, 0.0, absf(v - 0.2)), smoothstep(hw, 0.0, absf(v + 0.2)))
			side = maxf(side, smoothstep(0.5, 0.05, absf(v)) * smoothstep(0.0, 0.3, u))
			var along := smoothstep(0.0, 0.1, u) * pow(1.0 - u, 1.6) * (1.0 + 0.8 * smoothstep(0.35, 0.1, absf(u - 0.22)))
			throw.set_pixel(x, y, Color(1, 1, 1, clampf(side * along, 0.0, 1.0)))
	headlight_mat.albedo_texture = ImageTexture.create_from_image(throw)
	tail_glow_mat = pool_mat.duplicate()
	snow_tex = snow_patches()
	var walk := func(d: float) -> float:  # d metres out from the wall toward the kerb
		return 0.2 * exp(-pow(d / 0.55, 2.0)) + 0.4 * smoothstep(2.5, 3.3, d) - 0.26 * exp(-pow((d - 1.7) / 0.8, 2.0))
	snow_walk_tex = snow_patches(256, 112, func(_x: float, d: float) -> float: return walk.call(d))
	snow_lot_tex = snow_patches(227, 282, func(x: float, z: float) -> float:  # 7.1 x 8.8 m, the street at z 8.8
		var edge := minf(x, 7.1 - x)
		return -0.2 + 0.5 * smoothstep(1.6, 0.2, z) + 0.3 * smoothstep(0.9, 0.1, edge) * smoothstep(5.5, 3.0, z) + 0.25 * exp(-pow((x - 6.0) / 1.1, 2.0) - pow((z - 1.2) / 1.5, 2.0)))
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
	awning_mat = soft_mat.duplicate()
	var shade := Image.create(1, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		shade.set_pixel(0, y, Color(0.1, 0.08, 0.14, 1.0 - smoothstep(12.0, 31.0, y)))
	awning_mat.albedo_texture = ImageTexture.create_from_image(shade)
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
	foot_mat.render_priority = 1
	sun_in_mat = ShaderMaterial.new()
	sun_in_mat.shader = Shader.new()
	sun_in_mat.shader.code = SUN_IN_SHADER
	sun_in_mat.set_shader_parameter("front", 4.5)
	sun_in_mat.set_shader_parameter("slant", SUN.x / -SUN.z)
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
		run_off_shadow_mat.albedo_color = Color(0.08, 0.1, 0.2, 0.42 * (1.0 - night) * (1.0 + 0.3 * golden_at(h)))
	cast_mat.albedo_color.a = 0.42 * (1.0 - night) * (1.0 + 0.3 * golden_at(h))
	crown_mat.albedo_color.a = 0.62 * (1.0 - night) * (1.0 + 0.3 * golden_at(h))
	if tree_shadow_mat:
		tree_shadow_mat.set_shader_parameter("strength", crown_mat.albedo_color.a)
		tree_shadow_mat.set_shader_parameter("contact", 0.7 - 0.3 * night)
		tree_shadow_mat.set_shader_parameter("stretch", 1.0 + 0.9 * golden_at(h))
	awning_mat.albedo_color.a = 0.36 * (1.0 - night) * (1.0 + 0.3 * golden_at(h))
	foot_mat.set_shader_parameter("core", 0.5 - 0.15 * night)
	foot_mat.set_shader_parameter("glow", night)
	foot_mat.set_shader_parameter("sun", 0.42 * (1.0 - night) * (1.0 + 0.3 * golden_at(h)))
	foot_mat.set_shader_parameter("reach", FOOT.z * Vector2(SUN.x, SUN.z).length() / SUN.y * (1.0 + 0.9 * golden_at(h)))
	casts = casts.filter(func(s): return is_instance_valid(s))
	for s in casts:
		s.scale.z = 1.0 + 0.9 * golden_at(h)
	var dusk_sea := light * Color.WHITE.lerp(SEA_NIGHT, night)
	env.background_color = SEA_DEEP * dusk_sea
	if sea_mat:
		sea_mat.albedo_color = dusk_sea
		shore_mat.albedo_color = dusk_sea
		swell_mat.set_shader_parameter("light", Vector3(dusk_sea.r, dusk_sea.g, dusk_sea.b))
		swell_mat.set_shader_parameter("night", night)
	if field_mat:
		field_mat.set_shader_parameter("light", Vector3(light.r, light.g, light.b))
		field_mat.set_shader_parameter("night", night)
	for m in road_light_mats:
		m.set_shader_parameter("glow", night)
	pool_mat.albedo_color = LAMP * Color(1, 1, 1, 0.75 * night)
	street_pool_mat.albedo_color = LAMP * Color(1, 1, 1, minf(1.3 * night, 1.0))
	halo_mat.albedo_color = LAMP * Color(1, 1, 1, 0.55 * night)
	beam_mat.albedo_color = LAMP * Color(1, 1, 1, 0.5 * night)
	glare_mat.albedo_color = Color(1.0, 0.94, 0.8, 0.95 * night)
	headlight_mat.albedo_color = Color(1.0, 0.9, 0.7, 0.6 * night)
	tail_glow_mat.albedo_color = Color(1.0, 0.12, 0.06, 0.6 * night)
	spill_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.55 * night)
	var low := maxf(golden_at(h), dawn_at(h))  # the lower the sun, the deeper daylight reaches into your shop
	sun_in_mat.set_shader_parameter("reach", 5.2 * SUN.z / SUN.y * (1.0 + 0.9 * low))
	var sun_c := Color(1.0, 0.95, 0.84).lerp(Color(1.0, 0.82, 0.52), golden_at(h)).lerp(Color(1.0, 0.76, 0.66), dawn_at(h))
	sun_in_mat.set_shader_parameter("tint", sun_c * Color(1, 1, 1, (1.0 - night) * (0.14 + 0.2 * low)))
	sun_in_mat.set_shader_parameter("shade", Color(0.38, 0.44, 0.62) * Color(1, 1, 1, (1.0 - night) * 0.28))
	var on := 1.0 if room_dim == Color.WHITE or mode != "store" else 0.0
	shop_spill_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.9 * night * on)
	rival_spill_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.9 * night)
	flood_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.85 * night * on)
	sign_glow_mat.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.7 * night * on)
	lantern_glow_mat.albedo_color = Color(1.0, 0.55, 0.3, 0.75 * night)
	lantern_pool_mat.albedo_color = Color(1.0, 0.5, 0.28, 0.6 * night)
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
func pool(parent: Node3D, at: Vector3, size_: Vector2, m: Material = null) -> void:
	plane(parent, size_, Vector3(at.x, -0.03, at.z), m if m else pool_mat)
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


## Your shop's light out of its glass front (zl to 6.6, shop-local) over the sidewalk, as spill() lays it.
func shop_spill_tex(zl: float) -> ImageTexture:
	var mull: Array[float] = []
	for seg in [Vector2(zl, Sim.DOOR_IN.x - 0.8), Vector2(Sim.DOOR_IN.x + 0.8, 6.6)]:
		var bays := maxi(1, roundi((seg.y - seg.x) / 1.6))
		for k in bays + 1:
			mull.append(seg.x + 0.045 + (seg.y - seg.x - 0.09) * k / bays)
	return front_spill_tex(zl, 6.6, zl - 1.0, 8.6 - zl, Sim.DOOR_IN.x, mull, 0.45)


## Light out of a glass front from zl to zr over a spill() plane w wide from x0: panes fanning out from the ceiling
## lights, split by the mullions' soft shadows at mull, brighter by `open` out of the door at door.
func front_spill_tex(zl: float, zr: float, x0: float, w: float, door: float, mull: Array[float], open: float) -> ImageTexture:
	var cx := (zl + zr) / 2
	var iw := int(w * 16)
	var img := Image.create(iw, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var d := (y + 0.5) / 64.0 * 4.6
		var fall := pow(1.0 - d / 4.6, 1.5) * (0.7 + 0.3 * exp(-2.0 * d))
		var spread := 0.25 * d  # the light fans past the glass's ends as it falls away from it
		for x in iw:
			var lx := x0 + (x + 0.5) / 16.0
			var a := smoothstep(zl - spread - 0.3, zl - spread + 0.5, lx) * smoothstep(zr + spread + 0.3, zr + spread - 0.5, lx)
			var shade := 1.0
			for m in mull:
				var sx := m + (m - cx) * d / 7.0
				var sw := 0.08 + 0.09 * d
				shade -= 0.6 * exp(-pow((lx - sx) / sw, 2.0)) * (1.0 - d / 6.0)
			var lit := exp(-pow((lx - door - (door - cx) * d / 7.0) / (0.7 + 0.12 * d), 4.0))
			a *= maxf(shade, 0.35) * (0.8 + open * lit) * fall
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## What the glass front (zl to 6.6, shop-local) lets in, for SUN_IN_SHADER: u runs along the front, v is how far the
## light has fallen into the room, the mullions' bars softening and the whole band fading out as it goes.
func sun_gate(zl: float) -> ImageTexture:
	var w := 6.6 - zl
	var mull: Array[float] = []
	for seg in [Vector2(zl, Sim.DOOR_IN.x - 0.8), Vector2(Sim.DOOR_IN.x + 0.8, 6.6)]:
		var bays := maxi(1, roundi((seg.y - seg.x) / 1.6))
		for k in bays + 1:
			mull.append(seg.x + 0.045 + (seg.y - seg.x - 0.09) * k / bays)
	var iw := int(w * 32)
	var img := Image.create(iw, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var v := (y + 0.5) / 64.0
		var fade := (1.0 - smoothstep(0.86, 1.0, v)) * (1.0 - 0.3 * v)
		var sw := 0.07 + 0.2 * v  # the bars soften the further the light falls past the mullion
		for x in iw:
			var lx := zl + (x + 0.5) / 32.0
			var shade := 1.0
			for m in mull:
				shade -= (0.8 - 0.35 * v) * exp(-pow((lx - m) / sw, 2.0))
			var door := exp(-pow((lx - Sim.DOOR_IN.x) / (0.9 + 0.3 * v), 4.0))  # no glass in the doorway
			var a := fade * maxf(shade, 0.12) * (1.0 + 0.25 * door)
			img.set_pixel(x, y, Color(clampf(a, 0.0, 1.0), 0, 0))
	return ImageTexture.create_from_image(img)


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


## Tenji blocks for a 1.28 m repeat of 32 cm tiles (8 px each): guide tiles ribbed with raised bars along the
## way to walk in the top half (v 0-0.5), warning tiles studded with a grid of studs in the bottom half, each bar and
## stud lit on its top edge over the shadow it casts; every tile a shade off, scuffed and grimy, its grout dark.
func tactile() -> StandardMaterial3D:
	if tactile_m:
		return tactile_m
	var r := RandomNumberGenerator.new()
	r.seed = 37
	var base := Color("d8bb5c")
	var img := Image.create(32, 16, false, Image.FORMAT_RGB8)
	for t in 8:
		var tone := r.randf_range(0.97, 1.02) if r.randf() < 0.85 else r.randf_range(0.93, 0.95)
		for y in 8:
			for x in 8:
				var f := tone * r.randf_range(0.97, 1.02)
				if t < 4 and x >= 1 and x <= 6:
					f *= [1.04, 1.14, 0.82, 1.0, 1.14, 0.82, 1.0, 1.0][y]
				elif t >= 4:
					var dx := posmod(x - 1, 3)
					var dy := posmod(y - 1, 3)
					if x < 7 and y < 7:
						f *= [[1.14, 1.06, 1.0], [1.06, 0.82, 1.0], [1.0, 1.0, 1.0]][dy][dx]
				if x == 7 or y == 7:
					f = 0.74 * r.randf_range(0.96, 1.03)
				elif x == 0 or y == 0:
					f *= 1.04
				img.set_pixel((t % 4) * 8 + x, (t / 4) * 8 + y, Color(minf(base.r * f, 1.0), minf(base.g * f, 1.0), minf(base.b * f, 1.0)))
	img.generate_mipmaps()
	tactile_m = mat(Color.WHITE, ImageTexture.create_from_image(img))
	tactile_m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return tactile_m


## A run of tenji tiles over r at height y, laid on the world's 32 cm grid: guide tiles (or warning ones when warn)
## whose bars run along x, or along z when along_z.
func tactile_run(st: SurfaceTool, r: Rect2, y: float, warn := false, along_z := false) -> void:
	var v0 := 0.5 if warn else 0.0
	var v := [Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y)]
	var uv := v.map(func(p): return Vector2(p.z / 1.28, v0 + (p.x - r.position.x) / r.size.x * 0.5)) if along_z \
		else v.map(func(p): return Vector2(p.x / 1.28, v0 + (p.z - r.position.y) / r.size.y * 0.5))
	add_quad(st, v, uv)


## Poured concrete for a 7.2 m repeat of 1.8 m slabs (32 px each): each slab a shade off, mottled with grime in
## broad patches and flecked with aggregate, its score lines dark with dirt and lit on their sunny lip, a few hairline
## cracks and the odd oil or rust stain.
func slabs() -> StandardMaterial3D:
	if slabs_m:
		return slabs_m
	const N := 128
	var r := RandomNumberGenerator.new()
	r.seed = 31
	var fn := FastNoiseLite.new()
	fn.seed = 31
	fn.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	fn.frequency = 0.03
	fn.fractal_octaves = 3
	var mottle := fn.get_seamless_image(N, N).get_data()
	var base := Color("cbc6bb")
	var tone := []
	for k in 16:
		tone.append(r.randf_range(0.95, 1.02) if r.randf() < 0.8 else r.randf_range(0.89, 0.93))
	var v := PackedFloat32Array()
	v.resize(N * N)
	for y in N:
		for x in N:
			var lx := x % 32
			var ly := y % 32
			var f: float = tone[(y >> 5) * 4 + (x >> 5)] * lerpf(0.9, 1.04, mottle[y * N + x] / 255.0)
			var g := r.randf()
			f *= r.randf_range(0.97, 1.01) if g < 0.88 else (r.randf_range(0.91, 0.94) if g < 0.96 else 1.04)
			if lx == 31 or ly == 31:
				f = 0.74 * r.randf_range(0.95, 1.02)
			elif lx == 30 or ly == 30:
				f *= 0.93
			elif lx == 0 or ly == 0:
				f *= 1.04
			v[y * N + x] = f
	for i in 6:  # hairline cracks wandering in from a slab's edge
		var p := Vector2(r.randi_range(0, 3) * 32 + r.randi_range(4, 27), r.randi_range(0, 3) * 32)
		var dir := Vector2(r.randf_range(-0.6, 0.6), 1.0).normalized()
		if r.randf() < 0.5:
			p = Vector2(p.y, p.x)
			dir = Vector2(dir.y, dir.x)
		for step in r.randi_range(10, 24):
			v[posmod(int(p.y), N) * N + posmod(int(p.x), N)] *= 0.8
			dir = dir.rotated(r.randf_range(-0.5, 0.5))
			p += dir
	for i in 3:  # a drip of oil or a rust bloom, soft at its rim
		var c := Vector2(r.randf_range(0, N), r.randf_range(0, N))
		var rad := r.randf_range(3.0, 6.0)
		for y in range(int(c.y - rad - 1), int(c.y + rad + 2)):
			for x in range(int(c.x - rad - 1), int(c.x + rad + 2)):
				var d := Vector2(x, y).distance_to(c) / rad
				if d < 1.0:
					v[posmod(y, N) * N + posmod(x, N)] *= lerpf(0.84, 1.0, d * d)
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	for y in N:
		for x in N:
			var f := minf(v[y * N + x], 1.06)
			img.set_pixel(x, y, Color(minf(base.r * f, 1.0), minf(base.g * f, 1.0), minf(base.b * f, 1.0)))
	img.generate_mipmaps()
	slabs_m = mat(Color.WHITE, ImageTexture.create_from_image(img))
	slabs_m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return slabs_m


## The set's street for a 32 m repeat across its whole 8 m width (uv x/8, z/8, scaled to a quarter along x), 16 px a
## metre: fine aggregate, stones a shade lighter in the binder and a few pits dark, grime smeared in faint streaks along
## the lanes, both lanes' wheel paths worn darker and smoother with a drip line between them blotched with oil, dust
## along each kerb, two utility cuts patched in fresher tarmac behind a sealed seam, and a few cracks.
func tarmac() -> StandardMaterial3D:
	if tarmac_m:
		return tarmac_m
	const W := 512
	const H := 128
	var r := RandomNumberGenerator.new()
	r.seed = 41
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var patches := [Rect2(80, 100, 112, 14), Rect2(300, 20, 24, 26)]  # pixels; rows 64-127 are the far lane (z < 0)
	var noise := FastNoiseLite.new()
	noise.seed = 43
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var drips := noise.get_seamless_image(W, H)
	noise.seed = 41
	noise.frequency = 1.0
	for py in H:
		var z := (py + 0.5) / 16.0
		if z >= 4.0:
			z -= 8.0
		var lane_z := absf(absf(z) - 1.7)
		var path := 1.0 - smoothstep(0.18, 0.36, absf(lane_z - 0.62))
		for px in W:
			var grain := r.randf()
			# polished smoother in the wheel paths: fewer stones stand proud and fewer pits stay open
			var v := r.randf_range(0.96, 1.02)
			if grain > 0.9 - 0.06 * path:
				v = r.randf_range(1.05, 1.1) * lerpf(1.0, 0.97, path)
			elif grain < 0.05 * (1.0 - path):
				v = r.randf_range(0.84, 0.9)
			var c := ASPHALT
			# grime smeared along the lanes by the traffic: noise read round a cylinder so it wraps every 32 m, about
			# 8 m long to 1.5 m across
			var a := TAU * px / W
			var g := noise.get_noise_3d(cos(a) * 0.61, sin(a) * 0.61, z * 0.6) * 0.5 + 0.5
			v *= lerpf(0.95, 1.04, smoothstep(0.2, 0.8, g))
			if g < 0.36:
				c = c.lerp(Color("3d4250"), (0.36 - g) * 0.8)
			v = lerpf(v, 0.87, path * 0.75)
			if lane_z < 0.22 and absf(z) < 3.3:  # the drip line between the wheel paths, blotched with oil
				var d := drips.get_pixel(px, py).r
				if d > 0.56 or r.randf() < 0.2:
					v *= 0.9
				if d > 0.62:
					c = c.lerp(Color("262932"), clampf((d - 0.62) * 3.0, 0.0, 0.35))
			if absf(z) > 3.3:
				c = c.lerp(Color("8d8577"), (absf(z) - 3.3) * 0.5)
			var out := Color(c.r * v, c.g * v, c.b * v)
			for i in patches.size():
				if patches[i].grow(3).has_point(Vector2(px, py)):
					out = patched(out, Vector2(px + 0.5, py + 0.5), patches[i], [0.5, 0.0][i], r)
			img.set_pixel(px, py, out)
	for k in 5:  # hairline cracks, wandering across a lane
		var at := Vector2i(r.randi_range(0, W - 1), r.randi_range(0, H - 1))
		for s in r.randi_range(12, 28):
			img.set_pixelv(at, img.get_pixelv(at).darkened(0.32))
			at = Vector2i(posmod(at.x + r.randi_range(0, 2) - (1 if k % 2 else 0), W), posmod(at.y + r.randi_range(-1, 1), H))
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.texture_repeat = true
	m.uv1_scale = Vector3(0.25, 1, 1)
	tarmac_m = m
	return m


## A manhole in the street, 1 m across at 48 px a metre: a seal of dark tar round a steel frame worn bright at its lip,
## the gap, and a cast-iron lid with a rim band, a tread of raised diamonds lit along one edge and a sakura crest at its
## centre, polished paler where the tyres run over it. Cut out round its seal.
func manhole() -> StandardMaterial3D:
	if manhole_m:
		return manhole_m
	var r := RandomNumberGenerator.new()
	r.seed = 23
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	var iron := Color("5c6068")
	for py in 48:
		for px in 48:
			var d := Vector2(px - 23.5, py - 23.5)
			var rr := d.length()
			var c := Color(0, 0, 0, 0)
			if rr < 23.5:
				if rr >= 21.5:
					c = ASPHALT.darkened(0.42)
				elif rr >= 19.0:
					c = Color("85878b").lerp(Color("b8b9b5"), clampf(20.5 - rr, 0.0, 1.0))
				elif rr >= 18.0:
					c = Color("26282c")
				elif rr >= 16.0:
					c = iron.lightened(0.12 if rr < 17.0 else 0.04)
				elif rr >= 15.0:
					c = iron.darkened(0.3)
				elif rr >= 7.0:
					c = iron
					var u := posmod(px + py, 8)
					var w := posmod(px - py, 8)
					if u == 0 or w == 0:
						c = iron.darkened(0.32)
					elif u == 1 or w == 1:
						c = iron.lightened(0.2)
				elif rr >= 6.0:
					c = iron.lightened(0.25)
				else:
					c = iron.darkened(0.12)
					if rr > 1.0 and rr < 5.5 and cos(5.0 * d.angle()) > 0.6 - rr * 0.16:
						c = Color("a99ca1")
				if rr < 21.5:
					var wear := clampf(1.0 - absf(d.y + 3.0) / 14.0, 0.0, 1.0) * 0.18
					c = c.lerp(Color("a7a9aa"), wear + r.randf_range(-0.03, 0.04))
				c.a = 1.0
			img.set_pixel(px, py, c)
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.texture_repeat = false
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	manhole_m = m
	return m


## A street tree's pit in the sidewalk, 1.2 x 0.9 m at 40 px a metre: a kerb of granite setts, each a shade off with
## a lit inner lip and a grimy joint, round a cast-iron grate in two halves, its bars ringing the trunk's opening
## between radial ribs, each bar lit on its sunward edge over the dark soil showing through the slots, rust bled
## into a few, a sprig of weeds at the gap and leaf litter on the soil round the trunk.
func tree_pit() -> StandardMaterial3D:
	if tree_pit_m:
		return tree_pit_m
	var r := RandomNumberGenerator.new()
	r.seed = 41
	const W := 48
	const H := 36
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	var iron := Color("62666e")
	var soil := Color("3a2e26")
	var stone := Color("b9b4aa")
	var setts := []
	for i in 12:
		setts.append(r.randf_range(-0.06, 0.05))
	for py in H:
		for px in W:
			var edge := mini(mini(px, W - 1 - px), mini(py, H - 1 - py))
			var c: Color
			if edge < 4:  # the setts, 8 px long, joints between them
				var along := px if (py < 4 or py > H - 5) else py
				var k := posmod(floori(along / 8.0) + (0 if py < 4 else (3 if py > H - 5 else (6 if px < 4 else 9))), 12)
				c = stone.lightened(setts[k]) if posmod(along, 8) != 0 else stone.darkened(0.28)
				if edge == 0:
					c = c.darkened(0.22)
				elif edge == 3:
					c = c.lightened(0.12)
				c = c.lerp(Color("8f8a80"), r.randf_range(0.0, 0.12))
			elif edge == 4:
				c = Color("26282c")
			else:
				var d := Vector2((px - (W - 1) / 2.0) / 1.25, py - (H - 1) / 2.0)
				var rr := d.length()
				var ang := absf(fmod(d.angle() + TAU, PI / 4) - PI / 8)
				if rr < 5.5:  # the soil round the trunk, strewn with leaves
					c = soil.lerp(Color("4a3a2e"), r.randf() * 0.5)
					if r.randf() < 0.18:
						c = [Color("8a7a3c"), Color("a5683a"), Color("6f7a3a")][r.randi() % 3]
				elif rr < 7.0:  # the opening's rim
					c = iron.lightened(0.18 if d.y < 0.0 else 0.0)
				elif px == 24 or px == 23:  # the seam between the two halves
					c = iron.darkened(0.45) if px == 24 else iron.lightened(0.1)
				elif ang > PI / 8 - 0.12 or edge < 7:  # radial ribs and the outer frame
					c = iron.lightened(0.06 if edge == 6 or edge == 5 else 0.0)
				else:
					var ring := fmod(rr - 7.0, 3.0)
					if ring < 1.2:
						c = soil.darkened(0.35)
						if r.randf() < 0.1:
							c = Color("8a5a3a").darkened(0.2)
					else:
						c = iron.lightened(0.24) if ring < 1.9 else iron
						if r.randf() < 0.06:
							c = c.lerp(Color("8a5a3a"), 0.45)
				c = c.lerp(Color("8c8f94"), clampf(0.25 - rr / 60.0, 0.0, 0.25) * (1.0 if c.v > 0.25 else 0.0))
				if edge == 5 and r.randf() < 0.2:
					c = Color("6c8f45").lightened(r.randf_range(-0.1, 0.1))
			img.set_pixel(px, py, c)
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.texture_repeat = false
	tree_pit_m = m
	return m


## Your car park across its whole 7.1 x 8.8 m (uv 0-1 over Rect2(-3.4, -16, 7.1, 8.8)), 16 px a metre: the street's
## coarse grain a shade paler, tyre paths polished darker into each bay and scuffed across the aisle, an oil stain
## where each car's engine stands and dust along the kerbs. Its bay lines and arrow are laid over it in road paint.
func car_park() -> StandardMaterial3D:
	if car_park_m:
		return car_park_m
	const PX := 16.0
	var r := RandomNumberGenerator.new()
	r.seed = 53
	var img := Image.create(114, 141, false, Image.FORMAT_RGB8)
	var base := ASPHALT.lightened(0.08)
	var noise := FastNoiseLite.new()
	noise.seed = 53
	noise.frequency = 0.9
	for py in img.get_height():
		var z := -16.0 + (py + 0.5) / PX
		for px in img.get_width():
			var x := -3.4 + (px + 0.5) / PX
			var g := r.randf()  # the grain at the street's 16 px a metre
			var v := r.randf_range(0.96, 1.02) if g < 0.9 else (r.randf_range(1.05, 1.09) if g < 0.95 else r.randf_range(0.85, 0.91))
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
			img.set_pixel(px, py, Color(c.r * v, c.g * v, c.b * v))
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	car_park_m = m
	return m


## The set's road markings for an 8 m repeat (uv x/8, z/8), 16 px a metre: the paint a shade apart and dulled with
## grime, thinned in broad patches and worn through to the street's grain where its wheel paths cross, dusty at
## the kerbs like the tarmac under it.
func road_paint() -> StandardMaterial3D:
	if road_paint_m:
		return road_paint_m
	var r := RandomNumberGenerator.new()
	r.seed = 67
	var noise := FastNoiseLite.new()
	noise.seed = 67
	noise.frequency = 0.08
	var chips := FastNoiseLite.new()
	chips.seed = 71
	chips.frequency = 0.16
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var paint := Color("ebe7dc")
	for py in 128:
		var z := (py + 0.5) / 16.0
		if z >= 4.0:
			z -= 8.0
		var lane_z := absf(absf(z) - 1.7)
		for px in 128:
			var g := r.randf()  # the tarmac's grain, at its own 16 px a metre
			var v := r.randf_range(0.96, 1.02) if g < 0.9 else (r.randf_range(1.05, 1.1) if g < 0.95 else r.randf_range(0.84, 0.9))
			var under := ASPHALT
			var p := paint * r.randf_range(0.95, 1.01)
			if absf(z) > 3.3:
				under = under.lerp(Color("8d8577"), (absf(z) - 3.3) * 0.5)
				p = p.lerp(Color("bdb4a2"), 0.25)
			var path := 1.0 - smoothstep(0.18, 0.36, absf(lane_z - 0.62))
			if absf(z) < 3.3:
				v = lerpf(v, 0.87, path * 0.75)
			var n := noise.get_noise_2d(px, py) * 0.5 + 0.5
			var wear := 0.03 + 0.2 * smoothstep(0.55, 0.85, n) + 0.3 * path
			var col := p.lerp(Color(0.62, 0.62, 0.6), wear * 0.4)
			# the paint flakes off in patches, its rim thinned to a film the grain shows through
			var c := (chips.get_noise_2d(px, py) * 0.5 + 0.5) * 0.92 + r.randf() * 0.08
			var bare := Color(under.r * v, under.g * v, under.b * v).lerp(p, 0.3 * (1.0 - path) + 0.1)
			if c < wear:
				col = bare
			elif c < wear + 0.07:
				col = col.lerp(bare, 0.55)
			img.set_pixel(px, py, col)
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	road_paint_m = m
	return m


## The city's side streets and avenues for a 16 m repeat in world uv (x/16, z/16), 16 px a metre: the set street's
## fine grain, mottled with grime, a few utility cuts patched in darker tarmac behind a sealed seam and hairline
## cracks; mipmapped so whole streets of it stay calm from the city view.
func side_tarmac() -> StandardMaterial3D:
	if side_tar_m:
		return side_tar_m
	const N := 256
	var r := RandomNumberGenerator.new()
	r.seed = 83
	var noise := FastNoiseLite.new()
	noise.seed = 83
	noise.frequency = 0.02
	var mottle := noise.get_seamless_image(N, N)
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	var patches := [Rect2(36, 140, 60, 12), Rect2(184, 40, 18, 22), Rect2(120, 216, 12, 28)]
	for py in N:
		for px in N:
			var v := road_grain(r) * lerpf(0.94, 1.04, mottle.get_pixel(px, py).r)
			var out := Color(ASPHALT.r * v, ASPHALT.g * v, ASPHALT.b * v)
			for i in patches.size():
				if patches[i].grow(3).has_point(Vector2(px, py)):
					out = patched(out, Vector2(px + 0.5, py + 0.5), patches[i], [0.5, 0.0, 0.3][i], r)
			img.set_pixel(px, py, out)
	for k in 7:
		var at := Vector2i(r.randi_range(0, N - 1), r.randi_range(0, N - 1))
		var dir := Vector2i(1, 0) if k % 2 else Vector2i(0, 1)
		for s in r.randi_range(16, 36):
			img.set_pixelv(at, img.get_pixelv(at).darkened(0.32))
			at = Vector2i(posmod(at.x + dir.x + (r.randi_range(-1, 1) if dir.y else 0), N), posmod(at.y + dir.y + (r.randi_range(-1, 1) if dir.x else 0), N))
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	side_tar_m = m
	return m


## A leafy block's ground for a 16 m repeat in world uv (x/16, z/16), 16 px a metre, white so the district's colour
## tints it: fine gravel in stones of a few pixels, each a shade off, lit on its upper edge with a dark gap under it,
## mottled with damp in broad patches; grass grown over it in drifts, clumped light and dark with lit blade tips
## along their far edge, a shadow cast on the gravel under their near one, and a margin of bare earth round each
## drift where tufts stray out onto the stones.
func leafy_ground() -> ImageTexture:
	const N := 256
	const TH := 0.52  # turf above this, earth just under it
	var r := RandomNumberGenerator.new()
	r.seed = 71
	var fn := FastNoiseLite.new()
	fn.seed = 71
	fn.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	fn.frequency = 0.016
	fn.fractal_octaves = 3
	var mottle := fn.get_seamless_image(N, N).get_data()
	fn.seed = 73
	fn.frequency = 0.024
	fn.fractal_octaves = 5
	var turf := fn.get_seamless_image(N, N).get_data()
	fn.seed = 79
	fn.frequency = 0.08
	fn.fractal_octaves = 2
	var clump := fn.get_seamless_image(N, N).get_data()
	var blade := Color(0.7, 0.9, 0.52)
	var tip := Color(0.86, 0.98, 0.7)
	var stone := Color(1.0, 0.9, 0.95)  # off the district's green, so the gravel reads as gravel
	var earth := Color(0.84, 0.74, 0.7)
	# the stones: 2 x 2 px in rows set a random pixel along, each a shade off, lit at its top left and its gap
	# under one of its lower corners, so no joint lines up into paving
	var shade := PackedFloat32Array()
	shade.resize(N * N)
	for sy in N / 2:
		var off := r.randi_range(0, 1)
		for sx in N / 2:
			var v := r.randf_range(0.93, 1.02) if r.randf() < 0.8 else r.randf_range(0.84, 0.9)
			var gap := r.randi_range(1, 4)  # 4: no gap, the stone butts its neighbour
			for k in 4:
				var x := posmod(sx * 2 + (k & 1) + off, N)
				var y := sy * 2 + (k >> 1)
				shade[y * N + x] = v * (1.05 if k == 0 else (0.8 if k == gap else 1.0))
	var edge := int(TH * 255.0)
	var img := Image.create(N, N, false, Image.FORMAT_RGB8)
	for y in N:
		var up := posmod(y - 1, N) * N
		var up2 := posmod(y - 2, N) * N
		var dn := posmod(y + 1, N) * N
		for x in N:
			var i := y * N + x
			var damp := lerpf(0.88, 1.0, mottle[i] / 255.0)
			var t := turf[i] / 255.0
			var c: Color
			if t > TH:
				var g := r.randf()
				var k := lerpf(0.84, 1.06, clump[i] / 255.0) * lerpf(0.94, 1.03, smoothstep(TH, TH + 0.25, t))
				c = blade * k * (0.8 if g < 0.2 else 1.0)
				if g > 0.93 or turf[up + x] <= edge:
					c = tip * k  # a blade tip, and the whole far edge catching the light
				elif turf[dn + x] <= edge:
					c = blade.darkened(0.22) * k  # the drift's near edge, its blades' shaded side
			else:
				c = stone * damp * shade[i]
				var near := smoothstep(TH - 0.08, TH, t)
				c = c.lerp(earth * damp * lerpf(0.9, 1.0, shade[i]), near * 0.75)
				if near > 0.0 and r.randf() < near * 0.3:
					c = blade * r.randf_range(0.85, 1.0)  # a stray tuft
				elif turf[up + x] > edge or turf[up2 + x] > edge:
					c = c.darkened(0.2)  # the drift's shadow on the stones
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## A utility cut's reinstatement over the tarmac pixel at q (col, the street there with its grain): fresher, blacker
## binder with fewer pale stones that keeps a trace of the street's wear and grime under it, sealed at its sawn edge
## by overbanding that wanders 1-3 px wide (a few cm), glossy along the lip facing the sun. age greys an older patch, and its
## seal, toward the street round it.
static func patched(col: Color, q: Vector2, p: Rect2, age: float, r: RandomNumberGenerator) -> Color:
	var e := minf(minf(q.x - p.position.x, p.end.x - q.x), minf(q.y - p.position.y, p.end.y - q.y))
	var along := q.x + q.y
	var w := 1.0 + 0.2 * sin(along * 0.7) + 0.35 * sin(along * 0.23 + 1.7)
	if e < -w:
		return col
	if e < w:
		var seal := Color("20232b").lerp(col, 0.2 + 0.45 * age) * r.randf_range(0.97, 1.03)
		var sunward := q.x - p.position.x < w or p.end.y - q.y < w
		if sunward and e < 0.0:
			seal = seal.lerp(Color("7d8599"), r.randf_range(0.3, 0.5) * (1.0 - age))
		return seal
	var fresh := ASPHALT.darkened(0.24).lerp(Color(0.2, 0.22, 0.27), 0.15)
	var v := r.randf_range(0.97, 1.02)
	var g := r.randf()
	if g > 0.965:
		v = r.randf_range(1.06, 1.1)
	elif g < 0.02:
		v = 0.88
	var c := fresh.lerp(col, 0.12 + 0.6 * age)
	return Color(c.r * v, c.g * v, c.b * v)


## One pixel of the street's coarse grain, as a brightness: mostly even, a tenth paler stones, a tenth darker.
static func road_grain(r: RandomNumberGenerator) -> float:
	var g := r.randf()
	return r.randf_range(0.96, 1.02) if g < 0.9 else (r.randf_range(1.05, 1.1) if g < 0.95 else r.randf_range(0.84, 0.9))


## A side street's marking paint, w x h px with the first `on` columns painted: dulled with grime, a shade apart and
## chipped through (`chips` of it) to the tarmac's grain, which fills the gaps so they sit on the street like the
## tarmac round them.
func worn_paint(paint: Color, w: int, h: int, on: int, chips: float, seed_: int) -> StandardMaterial3D:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var noise := FastNoiseLite.new()
	noise.seed = seed_
	noise.frequency = 0.3
	var flake := noise.get_seamless_image(w, h)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			var v := road_grain(r)
			var col := Color(ASPHALT.r * v, ASPHALT.g * v, ASPHALT.b * v)
			if x < on:
				# flaked off in patches (`chips` of it), the rim round each thinned to a film over the grain
				var p := (paint * r.randf_range(0.93, 1.0)).lerp(Color(0.62, 0.62, 0.6), r.randf_range(0.05, 0.15))
				var c := flake.get_pixel(x, y).r
				var bare := col.lerp(p, 0.25)
				col = bare if c < chips else (p.lerp(bare, 0.5) if c < chips + 0.08 else p)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.texture_repeat = true
	return m


## The shop floor, 0.5 m vinyl tiles each a shade off the next under bevelled grout, polished to a sheen under the
## ceiling lights over each aisle, scuffed grey where the traffic runs (in at the door, along the queue and the cross
## aisle) and shaded where it meets the walls and the counter.
func shop_floor(zl: float, a: Color, b: Color, feet: Array) -> ImageTexture:
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
			for f: Rect2 in feet:
				var fd := Vector2(x - clampf(x, f.position.x, f.end.x), z - clampf(z, f.position.y, f.end.y)).length()
				if fd < 0.5:
					c = c.darkened(0.36 * pow(1.0 - fd / 0.5, 1.6))
			img.set_pixel(px, py, c)
	return ImageTexture.create_from_image(img)



## Store mode frames the focused street; city mode frames the whole city. Drag pans, wheel zooms.
func set_mode(m: String) -> void:
	mode = m
	if road_lights:
		road_lights.visible = m == "city"
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


## Your chain's pole-sign face in pixels at 64 a metre: a roundel in the stripes' colors and "24" for open all hours, in
## strokes whose edges are blended by coverage, so the face stays clean when the camera zooms in, over the stripes, the
## whole sheet lit unevenly by the three tubes behind it and shading off toward the bezel.
func sign_face() -> ImageTexture:
	if sign_tex:
		return sign_tex
	var paper := Color("fbfaf5")
	var img := Image.create(104, 88, false, Image.FORMAT_RGB8)
	var segs: Array = []  # the digits as strokes: a 2 of an arc, a diagonal and a foot, a 4 of a diagonal, bar and stem
	var prev := Vector2.ZERO
	for i in 9:
		var t := deg_to_rad(165.0 - i * 25.0)
		var q := Vector2(60.5 + 7.5 * cos(t), 17.5 - 7.5 * sin(t))
		if i > 0:
			segs.append([prev, q])
		prev = q
	segs.append_array([[prev, Vector2(52.5, 37.0)], [Vector2(52.5, 37.0), Vector2(69.5, 37.0)],
		[Vector2(86.5, 10.5), Vector2(76.0, 30.0)], [Vector2(76.0, 30.0), Vector2(92.5, 30.0)], [Vector2(86.5, 10.5), Vector2(86.5, 38.0)]])
	for y in 88:
		for x in 104:
			var p := Vector2(x - 3.5, y - 3.5)
			var c: Color = LAYOUT.stripe[0] if y >= 56 and y < 68 else LAYOUT.stripe[1] if y >= 68 and y < 80 else paper
			var d := p.distance_to(Vector2(24, 24))
			c = c.lerp(LAYOUT.stripe[0], clampf(21.5 - d, 0.0, 1.0) * clampf(d - 12.5, 0.0, 1.0))
			c = c.lerp(LAYOUT.stripe[1], clampf(8.5 - d, 0.0, 1.0))
			if p.x > 45 and p.y < 46:
				var near := 99.0
				for sg in segs:
					near = minf(near, p.distance_to(Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1])))
				c = c.lerp(LAYOUT.stripe[1], clampf(3.3 - near, 0.0, 1.0))
			var u := (x + 0.5) / 104.0
			var v := (y + 0.5) / 88.0
			var edge := minf(minf(u, 1.0 - u) * 1.64, minf(v, 1.0 - v) * 1.38)
			var k := 0.95 + 0.04 * sin(v * PI) + 0.035 * pow(maxf(0.0, cos((u - 0.5) * 3.0 * TAU)), 6.0) - 0.08 * (1.0 - smoothstep(0.0, 0.08, edge))
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k))
	img.generate_mipmaps()
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


## The bills on the vacant unit's shutter at 64 px a metre, paper sun-faded and taped at the corners: 0 the agent's to-let
## notice (a red band reading テナント募集 over its terms, a phone number and the agent's mark), 1 a yellow matsuri flyer
## peeling at a corner, 2 a lessons notice with tear-off tabs along its foot, two of them taken.
func shutter_bill(kind: int) -> ImageTexture:
	var sz: Vector2i = [Vector2i(60, 42), Vector2i(28, 38), Vector2i(24, 33)][kind]
	var img := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	var paper: Color = [Color("f6f3ea"), Color("efd98a"), Color("f2c4cb")][kind]
	var ink := Color("3d3a36")
	var rr := RandomNumberGenerator.new()
	rr.seed = 11 + kind
	img.fill(paper)
	for x in sz.x:
		for y in sz.y:
			var f := 1.0 - 0.025 * rr.randf() - (0.06 if x == 0 or y == 0 or x == sz.x - 1 or y == sz.y - 1 else 0.0)
			img.set_pixel(x, y, Color(paper.r * f, paper.g * f, paper.b * f))
	var scrawl := func(x0: int, y0: int, w: int, h: int, c: Color) -> void:  # a line of print as words of ink
		var x := x0
		while x < x0 + w - 1:
			var wl := rr.randi_range(2, 6)
			img.fill_rect(Rect2i(x, y0, mini(wl, x0 + w - x), h), c)
			x += wl + 1
	var glyphs := func(rows: Array, x0: int, y0: int, c: Color) -> void:
		for y in rows.size():
			for x in rows[y].length():
				if rows[y][x] == "#":
					img.set_pixel(x0 + x, y0 + y, c)
	if kind == 0:
		var red := Color("d23f33")
		for e in [Rect2i(1, 1, sz.x - 2, 1), Rect2i(1, sz.y - 2, sz.x - 2, 1), Rect2i(1, 1, 1, sz.y - 2), Rect2i(sz.x - 2, 1, 1, sz.y - 2)]:
			img.fill_rect(e, red)
		img.fill_rect(Rect2i(2, 2, sz.x - 4, 10), red)
		var kana := [["#####", ".....", "#####", "..#..", "..#..", ".#..."], ["..#..", "#####", "..#..", "..#..", ".#...", "#...."],
			["#....", ".#..#", "....#", "...#.", "..#..", "##..."], [".#...", ".#...", ".###.", ".#...", ".#...", ".#..."],
			["#####", ".#.#.", "#####", "#.#.#", "#####", "#..#."], [".#.#.", "#####", ".###.", "#####", "..#..", "#.#.#"]]
		for i in kana.size():
			glyphs.call(kana[i], 13 + i * 6, 4, Color("fbfaf5"))
		scrawl.call(5, 15, 36, 2, ink)
		scrawl.call(5, 19, 30, 2, ink.lerp(paper, 0.3))
		img.fill_rect(Rect2i(44, 14, 12, 9), Color("9a948a"))  # the floor plan
		img.fill_rect(Rect2i(45, 15, 10, 7), paper)
		img.fill_rect(Rect2i(50, 15, 1, 4), Color("9a948a"))
		var digits := {"0": ["###", "#.#", "#.#", "#.#", "###"], "3": ["###", "..#", "###", "..#", "###"], "5": ["###", "#..", "###", "..#", "###"],
			"8": ["###", "#.#", "###", "#.#", "###"], "2": ["###", "..#", "###", "#..", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
			"4": ["#.#", "#.#", "###", "..#", "..#"], "6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
			"-": ["...", "...", "###", "...", "..."]}
		var x := 6
		for ch in "03-5821-4467":
			glyphs.call(digits[ch], x, 26, red.darkened(0.2))
			x += 4
		img.fill_rect(Rect2i(2, 34, sz.x - 4, 1), Color("c9c3b6"))
		img.fill_rect(Rect2i(5, 36, 4, 4), Color("2f8f5b"))  # the agent's mark and name
		scrawl.call(11, 37, 22, 2, Color("2f8f5b"))
	elif kind == 1:
		var head := Color("b8352a")
		scrawl.call(3, 3, 22, 3, head)
		scrawl.call(5, 7, 18, 3, head)
		img.fill_rect(Rect2i(3, 12, 22, 12), Color("2c4a7a"))  # a night sky over the festival
		for i in 5:
			img.fill_rect(Rect2i(4 + i * 4, 15 + (i % 2), 3, 3), Color("f08a3c"))
			img.set_pixel(5 + i * 4, 14 + (i % 2), ink)
		img.fill_rect(Rect2i(3, 21, 22, 3), Color("1d2f4f"))
		for k in 2:
			scrawl.call(3, 27 + k * 4, 22 - k * 6, 2, ink)
		for k in 7:  # the top corner come unstuck and curled forward: the paper gone, its back showing on the flap
			for j in 7 - k:
				img.set_pixel(sz.x - 1 - j, k, Color(0, 0, 0, 0))
		for k in 6:
			for j in 6 - k:
				img.set_pixel(sz.x - 7 + j, k + 1 + j, paper.lightened(0.35) if j + k < 5 else paper.darkened(0.25))
	else:
		img.fill_rect(Rect2i(3, 3, 8, 8), Color("8fa3ae"))  # the teacher's photo
		img.fill_rect(Rect2i(5, 5, 4, 3), Color("e9c9a5"))
		img.fill_rect(Rect2i(4, 8, 6, 3), Color("4d5f7a"))
		scrawl.call(13, 4, 8, 2, Color("2a5d8f"))
		scrawl.call(13, 8, 8, 2, ink)
		for k in 2:
			scrawl.call(3, 13 + k * 4, 18 - k * 5, 2, ink)
		img.fill_rect(Rect2i(1, 22, sz.x - 2, 1), Color("b78a92"))  # the tabs cut up to a dashed line
		for t in 5:
			var tx := 1 + t * 4 + (t + 1) / 2
			for y in range(23, sz.y):
				img.set_pixel(tx + 3, y, Color(0, 0, 0, 0))
				if t in [1, 3]:
					img.fill_rect(Rect2i(tx, y, 3, 1), Color(0, 0, 0, 0))
			if not t in [1, 3]:
				img.fill_rect(Rect2i(tx + 1, 24, 1, 7), ink.lerp(paper, 0.35))
		img.fill_rect(Rect2i(sz.x - 1, 23, 1, sz.y - 23), Color(0, 0, 0, 0))
	var tape := Color("e6dcc0")  # strips of tape over the corners
	var corners := [Vector2i(0, 0), Vector2i(sz.x - 5, 0)] if kind == 1 else [Vector2i(0, 0), Vector2i(sz.x - 5, 0), Vector2i(0, sz.y - 3), Vector2i(sz.x - 5, sz.y - 3)]
	if kind == 2:
		corners = [Vector2i(0, 0), Vector2i(sz.x - 5, 0), Vector2i(sz.x / 2 - 2, 20)]
	for c: Vector2i in corners:
		img.fill_rect(Rect2i(c.x, c.y, 5, 3), tape)
		img.fill_rect(Rect2i(c.x, c.y + 2, 5, 1), tape.darkened(0.08))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


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
## point; u runs along the strip at u_scale per unit, or world_uv > 0 maps x, z. Only segments first..last-1 are emitted.
func ribbon(st: SurfaceTool, pts: PackedVector3Array, a: float, b: float, dy := 0.0, u_scale := 0.0, first := 0, last := -1, world_uv := 0.0) -> void:
	last = pts.size() - 1 if last < 0 else last
	var u := 0.0
	for i in range(first, last):
		var l0 := left_of(pts, i)
		var l1 := left_of(pts, i + 1)
		var up := Vector3(0, dy, 0)
		var u1 := u + pts[i].distance_to(pts[i + 1]) * u_scale
		var q := [pts[i] + l0 * a + up, pts[i + 1] + l1 * a + up, pts[i + 1] + l1 * b + up, pts[i] + l0 * b + up]
		var uv := [Vector2(u, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u, 1)]
		if world_uv > 0.0:
			uv = q.map(func(p): return Vector2(p.x, p.z) * world_uv)
		add_quad(st, q, uv)
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
## every road, river, park and plot (C.bounds grown by 120 holds them all) only the sea and the radial routes and the
## river running on out of town are in the way.
func country(r: Rect2, edge: float) -> bool:
	var p := r.get_center()
	for k in _farm_cells(r):
		for y in farm_yards.get(k, []):
			if y.intersects(r):
				return false
	if not C.run_off.all(func(ro): return Sim.City.seg_rect_dist(ro[0], ro[1], r) > ro[2] + 2.0):
		return false
	if not C.bounds.grow(120.0).intersects(r):
		for q in [p, r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
			if Geometry2D.is_point_in_polygon(q, C.bay) or Geometry2D.is_point_in_polygon(q, bay_mouth):
				return false
		return true
	return not _near_built(r.grow(edge)) and not Sim.City.blocked(C, r)


func _near_built(r: Rect2) -> bool:
	for k in _farm_cells(r):
		for q in built.get(k, []):
			if q.intersects(r):
				return true
	return false


func _farm_cells(r: Rect2) -> Array:
	var out := []
	for cx in range(floori(r.position.x / 64.0), floori(r.end.x / 64.0) + 1):
		for cy in range(floori(r.position.y / 64.0), floori(r.end.y / 64.0) + 1):
			out.append(Vector2i(cx, cy))
	return out


## Farmsteads over the fields round the city, thick at the built-up edge and thinning out into the country, so the
## town frays into farmland instead of stopping at its last block: two to four houses and a tin shed round a gravel
## yard, and often a row of plastic greenhouses beside it. Each is a yard in farm_yards and buildings in farms.
func plan_farms() -> void:
	farms.clear()
	farm_grounds.clear()
	farm_yards.clear()
	built.clear()
	var foots: Array = C.blocks.map(func(bl): return bl.rect) + Sim.City.buildings().map(func(bd): return bd.rect)
	foots += C.landmarks.map(func(L): return Rect2(L.pos - Vector2.ONE * L.size / 2, Vector2.ONE * L.size))
	for r in foots:
		for k in _farm_cells(r):
			if not built.has(k):
				built[k] = []
			built[k].append(r)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var taken := []
	var b: Rect2 = C.bounds.grow(180.0)  # inside the ground shadows' reach
	var y := b.position.y
	while y < b.end.y:
		var x := b.position.x
		while x < b.end.x:
			var p := Vector2(x, y) + Vector2(rng.randf_range(-18.0, 18.0), rng.randf_range(-18.0, 18.0))
			var yard := Rect2(p, Vector2(rng.randf_range(22.0, 32.0), rng.randf_range(18.0, 26.0)))
			var gh := Rect2()
			if rng.randf() < 0.35:
				var n := rng.randi_range(2, 4)
				var l := rng.randf_range(16.0, 24.0)
				var ws := n * 5.0 + (n - 1) * 1.6
				gh = Rect2(yard.end.x + 3.0, yard.position.y, l, ws) if rng.randf() < 0.5 else Rect2(yard.position.x, yard.end.y + 3.0, ws, l)
			var whole := yard.merge(gh) if gh.has_area() else yard
			var odds := 0.0  # by how far the nearest of the town lies
			for band in [[30.0, 0.85], [60.0, 0.55], [100.0, 0.3], [160.0, 0.12]]:
				if _near_built(whole.grow(band[0])):
					odds = band[1]
					break
			if odds > 0.0 and b.encloses(whole) and rng.randf() < odds and country(whole.grow(3.0), 8.0) \
					and not taken.any(func(q): return q.intersects(whole.grow(10.0))):
				taken.append(whole)
				_farmstead(rng, yard, gh)
			x += 36.0
		y += 36.0
	for r in taken:
		for k in _farm_cells(r.grow(2.0)):
			if not farm_yards.has(k):
				farm_yards[k] = []
			farm_yards[k].append(r.grow(2.0))


func _farmstead(rng: RandomNumberGenerator, yard: Rect2, gh: Rect2) -> void:
	farm_grounds.append([yard, true])
	if gh.has_area():
		farm_grounds.append([gh.grow(0.8), false])
	var placed := []
	var inner := yard.grow(-1.5)
	var count := rng.randi_range(3, 5)
	for i in 40:
		if placed.size() >= count:
			break
		var shed := placed.size() == 2
		var sz := Vector2(rng.randf_range(5.0, 7.0), rng.randf_range(4.0, 6.0)) if shed else Vector2(rng.randf_range(7.0, 11.0), rng.randf_range(7.0, 9.0))
		if rng.randf() < 0.5:
			sz = Vector2(sz.y, sz.x)
		var fp := Rect2(inner.position + (inner.size - sz) * Vector2(rng.randf(), rng.randf()), sz)
		if sz.x > inner.size.x or sz.y > inner.size.y or placed.any(func(q): return q.grow(2.0).intersects(fp)):
			continue
		placed.append(fp)
		var style: int = Sim.City.WAREHOUSE if shed else (Sim.City.WOOD if rng.randf() < 0.4 else Sim.City.HOUSE)
		farms.append(Sim.City._building(rng, style, fp, 1 if shed else rng.randi_range(1, 2)))
	if gh.has_area():
		var along := gh.size.x > gh.size.y
		var n := roundi(((gh.size.y if along else gh.size.x) + 1.6) / 6.6)
		for i in n:
			var o := i * 6.6
			var fp := Rect2(gh.position + (Vector2(0, o) if along else Vector2(o, 0)), Vector2(gh.size.x, 5.0) if along else Vector2(5.0, gh.size.y))
			farms.append({"rect": fp, "center": fp.get_center(), "size": fp.size, "greenhouse": true})


## Builds the fixed city once: ground, water, parks, streets, avenues, the expressway and the Yamanote, buildings,
## trees and landmarks. Lot contents (stores, empty plots) are built by build_lots.
func build_static() -> void:
	C = Sim.City.get_city()
	for c in city.get_children():
		c.free()
	plan_farms()
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
	# farm blocks between gravel lanes, each cut into strips one way and the strips into fields, furrowed down the
	# strip, so no seam runs on across the whole countryside
	const LANE := 2.4
	var lane := Color("cbbd96", 0.5)
	var fy := fb.position.y
	while fy < fb.end.y:
		var bh := fr.randf_range(70.0, 130.0)
		var fx := fb.position.x - fr.randf_range(0.0, 120.0)
		while fx < fb.end.x:
			var bw := fr.randf_range(80.0, 170.0)
			for ln in [Rect2(fx, fy, bw, LANE), Rect2(fx, fy, LANE, bh)]:
				if country(ln.grow(5.0), 6.0):
					fs.set_color(lane.darkened(fr.randf_range(0.0, 0.05)))
					rect_quad(fs, ln, -0.155)
			var blk := Rect2(fx + LANE, fy + LANE, bw - LANE, bh - LANE)
			var along := fr.randf() < 0.5  # strips run along x
			var across := blk.size.x if not along else blk.size.y
			var length := blk.size.y if not along else blk.size.x
			var s0 := 0.0
			while s0 < across - 4.0:
				var sw := minf(fr.randf_range(14.0, 28.0), across - s0)
				if across - s0 - sw < 10.0:
					sw = across - s0
				var t0 := 0.0
				while t0 < length - 4.0:
					var fl := minf(fr.randf_range(24.0, 60.0), length - t0)
					if length - t0 - fl < 16.0:
						fl = length - t0
					var r := Rect2(blk.position + (Vector2(t0, s0) if along else Vector2(s0, t0)), Vector2(fl, sw) if along else Vector2(sw, fl)).grow(-0.9)
					if country(r.grow(5.0), 6.0):
						var at := r.get_center() + Vector2(fr.randf_range(-40.0, 40.0), fr.randf_range(-40.0, 40.0))
						var cell := Vector2i((at / 110.0).floor())
						if not crops.has(cell):
							crops[cell] = fr.rand_weighted(fw8)
						var crop: int = crops[cell] if fr.randf() < 0.75 else fr.rand_weighted(fw8)
						var shade := fr.randf_range(-0.06, 0.06)
						var fc := Color(FIELDS[crop])
						fs.set_color(fc.lightened(shade) if shade > 0.0 else fc.darkened(-shade))
						rect_quad(fs, r, -0.155, (r.size.y if along else r.size.x) / 3.0, along)
					t0 += fl
				s0 += sw
			fx += bw
		fy += bh
	commit([fs], city)
	# built-up ground, coloured by what the district is: paving slabs in town, gravel grown over with grass where it's leafy
	var paved := surface(ground_mat(paving()))
	var gravel := surface(ground_mat(leafy_ground()))
	for bl in C.blocks:
		var dt: String = C.districts[bl.d].type
		var leafy: bool = dt in Sim.City.LEAFY
		var gs: SurfaceTool = gravel if leafy else paved
		gs.set_color(Color(Sim.City.GROUND[dt]))
		rect_quad(gs, bl.rect.grow(0.2), -0.15, 0.0, false, 0.0625 if leafy else 0.25)
	for fg in farm_grounds:  # the farmsteads' packed gravel yards, and bare soil under the greenhouses
		gravel.set_color(Color("cdb88e") if fg[1] else Color("8a7056"))
		rect_quad(gravel, fg[0], -0.15, 0.0, false, 0.0625)
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
	swell_mat.set_shader_parameter("night", night)
	var tr: Rect2 = C.bounds.grow(80.0)
	var town := Image.create(256, 256, false, Image.FORMAT_L8)
	for bl in C.blocks:
		var r: Rect2 = bl.rect
		town.fill_rect(Rect2i(Vector2i((r.position - tr.position) / tr.size * 256.0), Vector2i((r.size / tr.size * 256.0).ceil())), Color.WHITE)
	town.resize(40, 40, Image.INTERPOLATE_TRILINEAR)
	swell_mat.set_shader_parameter("town", ImageTexture.create_from_image(town))
	swell_mat.set_shader_parameter("town_rect", Vector4(tr.position.x, tr.position.y, tr.size.x, tr.size.y))
	swell_mat.set_shader_parameter("deep", Vector3(SEA_DEEP.r, SEA_DEEP.g, SEA_DEEP.b))
	swell_depth()
	var ws := surface(swell_mat)
	poly_fill(ws, C.bay, -0.14)
	poly_fill(ws, bay_mouth, -0.14)
	for poly in C.river:
		poly_fill(ws, poly, -0.14)
	# out of town the river runs between levees: a reedy margin at the water, a broad grassy bank, a gravel path along
	# the dike's crest and its outer slope down to the fields
	var rw := Sim.City.RIVER_W / 2
	var river3 := flat3(C.river_off, -0.14)
	ribbon(ws, river3, -rw, rw, 0.0, 0.0, 0, -1, 0.125)
	var bank := surface(ground_mat(speckle([Color("ffffff"), Color("f0f4ea"), Color("e4ead8"), Color("f8fbf2")])))
	var dike := flat3(C.river_off, -0.148)
	for side in [-1.0, 1.0]:
		for e in [[0.0, 1.4, "5e9a46"], [1.4, 6.4, "90c062"], [6.4, 7.8, "d4c69e"], [7.8, Sim.City.LEVEE, "78ae52"]]:
			bank.set_color(Color(e[2]))
			var a: float = side * (rw + e[0])
			var c: float = side * (rw + e[1])
			ribbon(bank, dike, minf(a, c), maxf(a, c), 0.0, 0.0, 0, -1, 0.25)
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
	commit([ws, land, ps, bank], city)
	build_shore()
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


## The sea's depth for the swell shader: each cell of the bay and the open sea south of it holds its distance from the
## nearest land, islands included (two-pass chamfer), reaching 1 a few hundred metres out.
func swell_depth() -> void:
	const N := 128
	var r := Rect2(Vector2(-1300, 0), Vector2(2750, 2800))
	var cell := r.size / N
	var far := 1e6
	var d := PackedFloat32Array()
	d.resize(N * N)
	for y in N:
		for x in N:
			var q := r.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			var wet: bool = Geometry2D.is_point_in_polygon(q, bay_mouth) or (Geometry2D.is_point_in_polygon(q, C.bay) and C.islands.all(func(isl): return not Geometry2D.is_point_in_polygon(q, isl)))
			d[y * N + x] = far if wet else 0.0
	var dg := cell.length()
	for pass_i in 2:
		var s := 1 if pass_i == 0 else -1
		for yi in N:
			var y := yi if s > 0 else N - 1 - yi
			for xi in N:
				var x := xi if s > 0 else N - 1 - xi
				var v := d[y * N + x]
				if v == 0.0:
					continue
				if x - s >= 0 and x - s < N:
					v = minf(v, d[y * N + x - s] + cell.x)
				if y - s >= 0 and y - s < N:
					v = minf(v, d[(y - s) * N + x] + cell.y)
					if x - s >= 0 and x - s < N:
						v = minf(v, d[(y - s) * N + x - s] + dg)
					if x + s >= 0 and x + s < N:
						v = minf(v, d[(y - s) * N + x + s] + dg)
				d[y * N + x] = v
	var img := Image.create(N, N, false, Image.FORMAT_L8)
	for y in N:
		for x in N:
			img.set_pixel(x, y, Color.from_hsv(0, 0, clampf(d[y * N + x] / 320.0, 0.0, 1.0)))
	swell_mat.set_shader_parameter("depth", ImageTexture.create_from_image(img))
	swell_mat.set_shader_parameter("depth_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))


## Where the bay meets open country: a beach along the shore, wet sand at the water's edge and dry sand up the shore
## in a width that swells and narrows, with a line of foam and a band of paler shallows out over the water. It tapers
## out where the shore reaches the city's quays, rivers and roads.
func build_shore() -> void:
	# the coast as one line, the open sea's west shore north into the city's bay and out down its east shore
	var coast := PackedVector2Array()
	coast.append_array(bay_mouth.slice(7))
	coast.append_array(C.bay)
	coast.append_array(bay_mouth.slice(2, 5))
	var pts := PackedVector2Array()
	for i in coast.size() - 1:
		var n := ceili(coast[i].distance_to(coast[i + 1]) / 5.0)
		for k in n:
			pts.append(coast[i].lerp(coast[i + 1], float(k) / n))
	pts.append(coast[coast.size() - 1])
	var norms := PackedVector2Array()
	var keep := PackedFloat32Array()
	var land := PackedFloat32Array()
	var near: Rect2 = C.bounds.grow(120.0)
	for i in pts.size():
		var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var n := Vector2(t.y, -t.x)  # left of the way the coast runs: the land
		norms.append(n)
		var q := pts[i] + n * 9.0
		var dry := not Sim.City.is_water(C, q) and not Geometry2D.is_point_in_polygon(q, bay_mouth)
		land.append(1.0 if dry else 0.0)
		keep.append(1.0 if dry and (not near.has_point(q) or Sim.City.nearest(C, q)[1] > Sim.City.URBAN + 6.0 and not Sim.City.blocked(C, Rect2(q - Vector2(6, 6), Vector2(12, 12)))) else 0.0)
	# each beach tapers in over its first and last 30 m rather than stopping square
	var fade := keep.duplicate()
	for i in pts.size():
		if keep[i] > 0.0:
			var d := 0
			while d < 6 and i - d - 1 >= 0 and i + d + 1 < pts.size() and keep[i - d - 1] > 0.0 and keep[i + d + 1] > 0.0:
				d += 1
			fade[i] = smoothstep(0.0, 6.0, float(d))
	var sand := surface(ground_mat(speckle([Color(1, 1, 1), Color(0.96, 0.95, 0.92), Color(1.0, 0.99, 0.96), Color(0.92, 0.91, 0.87)])))
	var sm := mat(Color.WHITE)
	sm.vertex_color_use_as_albedo = true
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = sea_mat.albedo_color
	shore_mat = sm
	var surf := surface(sm)
	var r := RandomNumberGenerator.new()
	r.seed = 19
	var reach := PackedFloat32Array()
	var s := 0.0
	for i in pts.size():
		if i > 0:
			s += pts[i].distance_to(pts[i - 1])
		reach.append((9.0 + 3.5 * sin(s / 37.0) + 2.0 * sin(s / 11.0 + 2.0) + r.randf_range(-0.6, 0.6)) * fade[i])
	var wet := Color("c2ab7e")
	var dry := Color("e8d8ac")
	var shallow := Color("8fd6d4")
	var foam := Color("f4fbfb")
	for i in pts.size() - 1:
		if fade[i] <= 0.0 and fade[i + 1] <= 0.0:
			continue
		var a := pts[i]
		var b := pts[i + 1]
		var na := norms[i]
		var nb := norms[i + 1]
		var fa := fade[i]
		var fb := fade[i + 1]
		# sand, set a metre under the water's edge so no seam shows, wet up to 2.2 m and dry beyond
		var bands := [[-1.0, -1.0, wet], [2.2 * fa, 2.2 * fb, wet.lerp(dry, 0.3)], [reach[i], reach[i + 1], dry]]
		for k in 2:
			var o0: Array = bands[k]
			var o1: Array = bands[k + 1]
			var v := [a + na * o0[0], b + nb * o0[1], b + nb * o1[1], a + na * o1[0]]
			var c := [o0[2], o0[2], o1[2], o1[2]]
			for j in [0, 1, 2, 0, 2, 3]:
				sand.set_color(c[j])
				sand.set_uv(v[j] * 0.25)
				sand.add_vertex(Vector3(v[j].x, -0.145, v[j].y))
		# out over the water: foam at the edge, then shallows fading into the sea
		for w in [[0.0, -1.4, foam, 0.85, 0.4], [-1.4, -20.0, shallow, 0.5, 0.0]]:
			var v := [a + na * w[0] * fa, b + nb * w[0] * fb, b + nb * w[1] * fb, a + na * w[1] * fa]
			var al := [w[3] * fa, w[3] * fb, w[4] * fb, w[4] * fa]
			for j in [0, 1, 2, 0, 2, 3]:
				var c: Color = w[2]
				surf.set_color(Color(c, al[j]))
				surf.add_vertex(Vector3(v[j].x, -0.12, v[j].y))
	# the built-up shore between the beaches, and the landfill islands all round, are quays
	var cope := surface(ground_mat(paving()))
	var lap := surface(sm)
	for i in pts.size():
		land[i] *= 1.0 - fade[i]
	seawall(cope, lap, pts, norms, land)
	for isl in C.islands:
		var ring := PackedVector2Array()
		for i in isl.size():
			var n := ceili(isl[i].distance_to(isl[(i + 1) % isl.size()]) / 4.0)
			for k in n:
				ring.append(isl[i].lerp(isl[(i + 1) % isl.size()], float(k) / n))
		ring.append(ring[0])
		var inward := PackedVector2Array()
		var all := PackedFloat32Array()
		for i in ring.size():
			var t := (ring[(i + 1) % (ring.size() - 1)] - ring[(i - 1 + ring.size() - 1) % (ring.size() - 1)]).normalized()
			var n := Vector2(t.y, -t.x)
			inward.append(n if Geometry2D.is_point_in_polygon(ring[i] + n * 2.0, isl) else -n)
			all.append(1.0)
		seawall(cope, lap, ring, inward, all)
	commit([sand, surf, cope, lap], city)


## A seawall along pts (n: unit normals toward the land, w: 0..1 how much of one stands there): a stone coping along the
## edge, its lip darker, and out over the water the wall's wet foot, a lap of foam along it and paler water fading off
## it. Water bands fade out where the ground beyond them isn't water, so they never tint another shore across a channel.
func seawall(cope: SurfaceTool, lap: SurfaceTool, pts: PackedVector2Array, n: PackedVector2Array, w: PackedFloat32Array) -> void:
	var lip := Color("8e8b84")
	var stone := Color("d8d4ca")
	var wall := Color("3e5a66")
	var foam := Color("f4fbfb")
	var shallow := Color("8fd6d4")
	for i in pts.size() - 1:
		var wa := w[i]
		var wb := w[i + 1]
		if wa <= 0.0 and wb <= 0.0:
			continue
		var a := pts[i]
		var b := pts[i + 1]
		for c in [[0.0, 0.35, lip], [0.35, 1.6, stone]]:
			var v := [a + n[i] * c[0] * wa, b + n[i + 1] * c[0] * wb, b + n[i + 1] * c[1] * wb, a + n[i] * c[1] * wa]
			for j in [0, 1, 2, 0, 2, 3]:
				cope.set_color(c[2])
				cope.set_uv(v[j] * 0.25)
				cope.add_vertex(Vector3(v[j].x, -0.13, v[j].y))
		for c in [[0.0, -0.45, wall, 0.7, 0.7], [-0.45, -1.4, foam, 0.75, 0.15], [-1.4, -8.0, shallow, 0.38, 0.0]]:
			var v := [a + n[i] * c[0] * wa, b + n[i + 1] * c[0] * wb, b + n[i + 1] * c[1] * wb, a + n[i] * c[1] * wa]
			var al := [c[3] * wa, c[3] * wb, c[4] * wb, c[4] * wa]
			for j in [0, 1, 2, 0, 2, 3]:
				var wet: bool = Sim.City.is_water(C, (a if j in [0, 3] else b) + (n[i] if j in [0, 3] else n[i + 1]) * -9.0)
				lap.set_color(Color(c[2], al[j] if wet else 0.0))
				lap.add_vertex(Vector3(v[j].x, -0.125, v[j].y))


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
	var tar := surface(side_tarmac())
	var mouth := surface(side_tarmac())
	var dash := surface(worn_paint(Color("e8e2c8"), 32, 4, 16, 0.02, 89))
	var solid := surface(worn_paint(Color("e8e2c8"), 16, 16, 16, 0.02, 97))
	var zebra := surface(worn_paint(Color("ece7d8"), 16, 16, 8, 0.1, 101))
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
		rect_quad(tar, srect(s, a0, a1, SW, s.w - SW), -0.11, 0.0, false, 0.0625)
		var len_: float = d1 - d0
		if s.w > Sim.City.ROAD:
			rect_quad(solid, srect(s, d0, d1, s.w / 2 - 0.12, s.w / 2 + 0.12), -0.1, 0.0, false, 0.5)
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
			rect_quad(mouth, srect(s, minf(at_, at_ + dir * s.j[e]), maxf(at_, at_ + dir * s.j[e]), SW, s.w - SW), -0.095, 0.0, false, 0.0625)
			rect_quad(zebra, srect(s, minf(at_ - dir * 0.6, at_ - dir * 2.6), maxf(at_ - dir * 0.6, at_ - dir * 2.6), SW, s.w - SW), -0.09, (s.w - 2 * SW) / 0.9, not along_z)
	for av in C.avenues:
		var pts := flat3(av.pts)
		var half: float = av.w / 2
		ribbon(walkway, pts, half, -half, -0.12, 0.5)
		ribbon(tar, pts, half - SW, SW - half, -0.11, 0.0, 0, -1, 0.0625)
		if av.w <= Sim.City.ROAD:  # a park's road: two lanes, as a side street
			ribbon(dash, pts, 0.08, -0.08, -0.1, 0.5)
		elif av.shuto == "":
			ribbon(solid, pts, 0.12, -0.12, -0.1, 0.0, 0, -1, 0.5)
			var mid_lane: float = (half - SW) / 2
			ribbon(dash, pts, mid_lane + 0.07, mid_lane - 0.07, -0.1, 0.5)
			ribbon(dash, pts, -mid_lane + 0.07, -mid_lane - 0.07, -0.1, 0.5)
		else:
			ribbon(solid, pts, 0.6, -0.6, -0.1, 0.0, 0, -1, 0.5)  # the expressway's pillars stand on this median
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
	build_road_lights()
	rail_node = commit([], city)
	rail_sig = Rect2(1, 1, -1, -1)
	build_rails([])


## The map's streetlights: a hot spot under each lamp along every street and avenue, its pool and the kerbs warm,
## and along the expressway's decks in sodium orange; lit after dark.
func build_road_lights() -> void:
	road_light_mats = []
	for t in [[LAMP, 0.06], [Color(1.0, 0.56, 0.22), 0.025]]:
		var m := ShaderMaterial.new()
		m.shader = Shader.new()
		m.shader.code = ROAD_LIGHT_SHADER
		m.set_shader_parameter("tint", Vector3(t[0].r, t[0].g, t[0].b))
		m.set_shader_parameter("wash", t[1])
		m.set_shader_parameter("glow", maxf(night, 0.0))
		road_light_mats.append(m)
	var S := 24.0
	var SW := Sim.City.SIDEWALK
	var road := surface(road_light_mats[0])
	for s in C.streets:
		var a0: float = s.from + (0.0 if s.quay[0] else (SW if s.j[0] < 0.0 else -SW))
		var a1: float = s.to - (0.0 if s.quay[1] else (SW if s.j[1] < 0.0 else -SW))
		road.set_color(Color((s.w - 2 * SW) / 40.0, 0, 0))
		rect_quad(road, srect(s, a0, a1, SW, s.w - SW), -0.085, (a1 - a0) / S, s.axis == "v")
	for av in C.avenues:
		road.set_color(Color((av.w - 2 * SW) / 40.0, 0, 0))
		ribbon(road, flat3(av.pts), av.w / 2 - SW, SW - av.w / 2, -0.085, 1.0 / S)
	var deck := surface(road_light_mats[1])
	for e in Sim.City.elevated(C):
		deck.set_color(Color(e.w / 40.0, 0, 0))
		ribbon(deck, lifted(e.pts), e.w / 2, -e.w / 2, 0.03, 1.0 / S)
	road_lights = commit([road, deck], city)
	road_lights.visible = mode == "city"


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


## The Shuto expressway, its ramps and the Yamanote viaduct, in short pieces; pillars below. The expressway's deck is
## laid in the streets' tarmac on a steel box girder, between cast parapets under a coping, with a median barrier.
func build_elevated() -> void:
	var lines := mat(Color("e8e2c8"))
	var dm := mat(Color.WHITE, stripes(ASPHALT, Color("e8e2c8"), 8, 1, 3))
	dm.texture_repeat = true
	var cast := mat(Color.WHITE, shuto_tex())  # its girder stops 0.3 m over the trains on the viaduct below
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
			var top := surface(side_tarmac())
			var side := surface(cast)
			ribbon(top, part, half, -half, 0.0, 0.0, i - lo, j - lo, 1.0 / 16.0)
			for sd in [half, -half]:
				band(side, part, sd, sd, 0.0, -1.1, 16, 42, e.cum[i] / 10.0, i - lo, j - lo, 56)
			elevated.append(commit([top, side], city))
			i = j
		# parapets, edge lines, the median barrier and lane lines, left out where another carriageway runs into this one
		var walls := surface(cast)
		var mark := surface(lines)
		var extra := surface(dm)
		var specs := [[half, walls], [-half, walls], [half - 0.5, mark], [0.5 - half, mark]]
		if not e.ramp:
			specs += [[0.0, walls], [half / 2, extra], [-half / 2, extra]]
		for sp in specs:
			for run in Sim.City.line_runs(C, ri, sp[0]):
				var sub := sub_line(e, pts, run[0], run[1])
				var u0: float = run[0] / 10.0
				if sp[1] != walls:
					ribbon(sp[1], sub[0], sp[0] + 0.07, sp[0] - 0.07, 0.02, 0.5 if sp[1] == extra else 0.0, sub[1], sub[2])
				elif sp[0] == 0.0:
					for m in [0.15, -0.15]:
						band(walls, sub[0], m, m, 0.8, 0.0, 42, 52, u0, sub[1], sub[2], 56)
					band(walls, sub[0], 0.15, -0.15, 0.8, 0.8, 52, 56, u0, sub[1], sub[2], 56)
				else:
					var n: float = -signf(sp[0]) * 0.22
					band(walls, sub[0], sp[0], sp[0], 1.0, 0.0, 0, 16, u0, sub[1], sub[2], 56)
					band(walls, sub[0], sp[0] + n, sp[0] + n, 1.0, 0.0, 42, 52, u0, sub[1], sub[2], 56)
					band(walls, sub[0], sp[0], sp[0] + n, 1.0, 1.0, 52, 56, u0, sub[1], sub[2], 56)
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


## The Yamanote viaduct: two tracks on a ballasted deck between cast parapets under a coping, the line's green stripe
## along their outer face and cable-trough lids along their foot, an island platform under a canopy at each station; a
## column and cap beam under it at each pier.
func build_rail(pillars: Array) -> void:
	var CT := Sim.City
	var ballast := tiled(speckle([Color("847e76"), Color("958e84"), Color("736c64"), Color("a19a90"), Color("665f58")]), Vector2(4, CT.RAIL_W / 0.8))
	var bed := mat(Color.WHITE, sleepers())
	var steel := mat(Color("e4e6e6"))  # the heads worn bright by the wheels
	var web := mat(Color("6b4a38"))  # their sides rusted
	var fascia := mat(Color("c3bfb6"))
	var cast := mat(Color.WHITE, parapet_tex())
	var slab := mat(Color("d6d2c6"))
	var edge := mat(Color("e8c84a"))
	var roof := mat(Color("8f979b"))
	var post := mat(Color("6d7378"))
	var half: float = CT.RAIL_W / 2
	var y: float = CT.RAIL_DECK
	var loop: PackedVector3Array = flat3(C.rail_loop, y)
	var cum := PackedFloat32Array([0.0])  # arc length round the loop, so the parapets' panels run on across pieces
	for k in range(1, loop.size()):
		cum.append(cum[k - 1] + loop[k - 1].distance_to(loop[k]))
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
		var side := surface(cast)
		var f := 1
		var l := part.size() - 2
		ribbon(top, part, half, -half, 0.3, 1.0 / 3.2, f, l)
		for t in [CT.TRACK, -CT.TRACK]:
			ribbon(beds, part, t + 1.3, t - 1.3, 0.31, 1.0 / 2.4, f, l)
			for g in [0.6, -0.6]:
				ribbon(rails, part, t + g + 0.06, t + g - 0.06, 0.37, 0.0, f, l)
				for e in [0.05, -0.05]:
					wall(webs, part, t + g + e * 1.2, 0.31, 0.37, f, l)
		var u0: float = cum[i] / 10.0
		for s in [half, -half]:
			var n: float = -signf(s)
			band(side, part, s, s, 0.9, -0.6, 0, 24, u0, f, l)
			band(side, part, s + n * 0.18, s + n * 0.18, 0.9, 0.3, 24, 34, u0, f, l)
			band(side, part, s, s + n * 0.18, 0.9, 0.9, 34, 38, u0, f, l)
			band(side, part, s + n * 0.18, s + n * 0.46, 0.38, 0.38, 38, 42, u0, f, l)
		elevated.append(commit([top, beds, webs, rails, side], city))
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


## A strip along pts from lateral offset a at height y0 to b at y1 (a wall when a == b, a deck when y0 == y1), its
## texture rows r0..r1 of a parapet texture `rows` high across it and 10 m of it along, starting u0 in.
func band(st: SurfaceTool, pts: PackedVector3Array, a: float, b: float, y0: float, y1: float, r0: int, r1: int, u0: float, first: int, last: int, rows := 42) -> void:
	var v0 := (r0 + 0.25) / rows
	var v1 := (r1 - 0.25) / rows
	var u := u0
	for i in range(first, last):
		var l0 := left_of(pts, i)
		var l1 := left_of(pts, i + 1)
		var u1 := u + pts[i].distance_to(pts[i + 1]) / 10.0
		var q := [pts[i] + l0 * a + Vector3(0, y0, 0), pts[i + 1] + l1 * a + Vector3(0, y0, 0), pts[i + 1] + l1 * b + Vector3(0, y1, 0), pts[i] + l0 * b + Vector3(0, y1, 0)]
		add_quad(st, q, [Vector2(u, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u, v1)])
		u = u1


## The viaduct's parapet, 10 m along at 16 px a metre, in four bands: its outer face (rows 0-23, 0.9 m above the deck
## to 0.6 below: the coping's lit lip over its shadow, precast panels butted every 2.5 m each a shade off with tie
## holes and rain streaks run down from the coping, the green stripe, a drip groove and the deck slab's edge), its
## inner face (24-33, dusty toward the ballast), the coping's top (34-37) and the cable-trough lids (38-41).
func parapet_tex() -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 23
	var img := Image.create(160, 42, false, Image.FORMAT_RGB8)
	var base := Color("c3bfb6")
	var tint: Array = []
	for k in 4:
		tint.append(1.0 + r.randf_range(-0.06, 0.05))
	var streak: Array = []
	for x in 160:
		streak.append(r.randi_range(2, 13) if r.randf() < 0.3 else 0)
	var grain := func() -> float: return r.randf_range(-0.025, 0.025)
	for x in 160:
		var t: float = tint[floori(x / 40.0)]
		var joint := x % 40 == 0
		var lit := x % 40 == 1
		img.set_pixel(x, 0, Color("e6e2d8"))
		img.set_pixel(x, 1, Color("d6d2c8").darkened(0.12 if joint else 0.0))
		img.set_pixel(x, 2, Color("cbc7bd").darkened(0.12 if joint else 0.0))
		img.set_pixel(x, 3, Color("8d887e"))
		for y in range(4, 19):
			var c: Color = base * (t + grain.call())
			if y >= 7 and y <= 10:
				c = Color("93d052") if y == 7 else Color("6aa836") if y == 10 else Color("7fc241")
			if y - 4 < streak[x]:
				c = c.darkened(0.12 * (1.0 - float(y - 4) / streak[x]))
			if (y == 5 or y == 16) and x % 10 == 5:
				c = c.darkened(0.25)
			if joint:
				c = c.darkened(0.3)
			elif lit:
				c = c.lightened(0.08)
			c.a = 1.0
			img.set_pixel(x, y, c)
		img.set_pixel(x, 19, Color("6f6a62"))
		for y in range(20, 24):
			var c: Color = base * (0.86 + grain.call() - (0.1 if y == 23 else 0.0))
			c.a = 1.0
			img.set_pixel(x, y, c)
		img.set_pixel(x, 24, Color("d6d2c8"))
		img.set_pixel(x, 25, Color("9d988e"))
		for y in range(26, 34):
			var c: Color = (base * (t * 0.93 + grain.call())).lerp(Color("8a8174"), float(y - 26) / 8.0 * 0.55)
			if joint:
				c = c.darkened(0.25)
			c.a = 1.0
			img.set_pixel(x, y, c)
		for y in range(34, 38):
			var c: Color = Color("dcd8ce") * (1.0 + grain.call() - (0.08 if y == 37 else 0.0))
			if x % 20 == 0:
				c = c.darkened(0.25)
			c.a = 1.0
			img.set_pixel(x, y, c)
		for y in range(38, 42):
			var c: Color = Color("a29d93") * (1.0 + grain.call())
			if y == 38:
				c = c.lightened(0.12)
			if y == 41 or x % 8 == 0:
				c = c.darkened(0.3)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## The expressway's side, 10 m along at 16 px a metre: its outer face (rows 0-41, 1 m above the deck to 1.1 below: the
## coping's lit lip over its shadow, precast parapet panels every 2.5 m each a shade off with rain streaks and tie
## holes, a drip groove at the deck, the slab's edge, then the box girder's web painted Shuto's pale grey-green with a
## stiffener every 1.25 m, rust weeping down from a few bolts and the shade deepening to its bottom flange), the
## parapet's inner face (42-51, sooted toward the tarmac) and the coping's top (52-55).
func shuto_tex() -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 29
	var img := Image.create(160, 56, false, Image.FORMAT_RGB8)
	var base := Color("c3bfb6")
	var paint := Color("a7b5ad")
	var tint: Array = []
	for k in 4:
		tint.append(1.0 + r.randf_range(-0.06, 0.05))
	var streak: Array = []
	var rust: Array = []
	for x in 160:
		streak.append(r.randi_range(2, 9) if r.randf() < 0.3 else 0)
		rust.append(r.randi_range(4, 14) if x % 20 == 10 and r.randf() < 0.35 else 0)
	var grain := func() -> float: return r.randf_range(-0.025, 0.025)
	var put := func(x: int, y: int, c: Color) -> void:
		c.a = 1.0
		img.set_pixel(x, y, c)
	for x in 160:
		var t: float = tint[floori(x / 40.0)]
		var joint := x % 40 == 0
		put.call(x, 0, Color("e6e2d8"))
		put.call(x, 1, Color("d6d2c8").darkened(0.12 if joint else 0.0))
		put.call(x, 2, Color("8d887e"))
		for y in range(3, 15):
			var c: Color = base * (t + grain.call())
			if y - 3 < streak[x]:
				c = c.darkened(0.1 * (1.0 - float(y - 3) / streak[x]))
			if (y == 5 or y == 12) and x % 10 == 5:
				c = c.darkened(0.25)
			if joint:
				c = c.darkened(0.3)
			elif x % 40 == 1:
				c = c.lightened(0.08)
			put.call(x, y, c)
		put.call(x, 15, Color("6f6a62"))
		for y in range(16, 21):
			put.call(x, y, base * (0.9 + grain.call()))
		put.call(x, 21, Color("5d5a55"))
		for y in range(22, 41):
			var f := float(y - 22) / 18.0
			var c: Color = paint * (1.0 - 0.22 * f + grain.call())
			if x % 20 == 0:
				c = c.lightened(0.14)
			elif x % 20 == 1:
				c = c.darkened(0.18)
			if y == 23 or y == 39:
				c = c.darkened(0.1)
			if rust[x] > 0 and y - 23 < rust[x] and y > 23:
				c = c.lerp(Color("8a5a3c"), 0.45 * (1.0 - float(y - 23) / rust[x]))
			put.call(x, y, c)
		put.call(x, 41, Color("5f6862"))
		put.call(x, 42, Color("d6d2c8"))
		put.call(x, 43, Color("9d988e"))
		for y in range(44, 52):
			var c: Color = (base * (t * 0.9 + grain.call())).lerp(ASPHALT.darkened(0.2), float(y - 44) / 8.0 * 0.5)
			if joint:
				c = c.darkened(0.25)
			put.call(x, y, c)
		for y in range(52, 56):
			var c: Color = Color("dcd8ce") * (1.0 + grain.call() - (0.08 if y == 55 else 0.0))
			if x % 40 == 0:
				c = c.darkened(0.25)
			put.call(x, y, c)
	return ImageTexture.create_from_image(img)


## Four sleepers on their ballast bed, u along the track (2.4 m a texture width), v across it, 20 px a metre: granite
## ballast speckled grey and brown, rust-stained under each rail, each concrete tie a shade off with its lit near edge
## and a shadow on its far side, a steel tie plate and two clips where each rail sits on it.
func sleepers() -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 23
	var stones := [Color("8d877e"), Color("9c958b"), Color("7a736a"), Color("a8a196"), Color("6c665e")]
	var img := Image.create(48, 52, false, Image.FORMAT_RGB8)
	for x in 48:
		for y in 52:
			var c: Color = stones[0] if r.randf() < 0.4 else stones[r.randi() % stones.size()]
			if absi(y - 14) < 3 or absi(y - 37) < 3:
				c = c.lerp(Color("7a5a44"), 0.35)
			if y < 2 or y > 49:
				c = c.darkened(0.12)  # the shoulders fall away
			img.set_pixel(x, y, c)
	for k in 4:
		var x0 := k * 12 + 3
		var tone := r.randf_range(0.94, 1.05)
		for y in range(2, 50):
			for dx in 5:
				var c := Color("bcb6aa") * tone
				if dx == 0:
					c = c.lightened(0.12)
				elif dx == 4:
					c = c.darkened(0.14)
				if r.randf() < 0.12:
					c = c.darkened(0.06)
				img.set_pixel(x0 + dx, y, c)
			for dx in 2:
				var under := img.get_pixel(x0 + 5 + dx, y)
				img.set_pixel(x0 + 5 + dx, y, under.darkened(0.4 - dx * 0.18))
		for ry in [14, 37]:
			for y in range(ry - 3, ry + 4):
				for dx in range(1, 4):
					img.set_pixel(x0 + dx, y, Color("4f4a46") if absi(y - ry) < 3 else Color("3a3633"))
			for y in [ry - 3, ry + 3]:
				img.set_pixel(x0 + 2, y, Color("8f8a80"))  # the clips
	return ImageTexture.create_from_image(img)


## A box from corner p0 to p1 into a vertex-coloured surface, each face in the house's three tones of col.
## world_uv > 0 lays a texture on every face at that many repeats a metre, so neighbouring boxes run on unbroken.
func box_into(st: SurfaceTool, p0: Vector3, p1: Vector3, col: Color, world_uv := 0.0) -> void:
	var c := (p0 + p1) / 2
	var h := (p1 - p0).abs() / 2
	for fc in [[Vector3.UP, 1.0], [Vector3.BACK, 0.9], [Vector3.LEFT, 0.9], [Vector3.RIGHT, 0.75], [Vector3.FORWARD, 0.75]]:
		var fn: Vector3 = fc[0]
		var u := Vector3.UP if absf(fn.y) < 0.5 else Vector3.RIGHT
		var v := fn.cross(u)
		var ctr := c + fn * absf(fn.dot(h))
		var hu := u * absf(u.dot(h))
		var hv := v * absf(v.dot(h))
		var q := [ctr - hu - hv, ctr + hu - hv, ctr + hu + hv, ctr - hu + hv]
		var uv := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
		if world_uv > 0.0:
			uv = q.map(func(p): return Vector2(p.dot(v.abs()), -p.dot(u)) * world_uv)
		st.set_color(Color(col.r * fc[1], col.g * fc[1], col.b * fc[1]))
		add_quad(st, q, uv)


## An upright drum standing on `at`, radius r and height h, into a vertex-coloured surface: its side shaded round
## from the walls' lit 0.9 toward the sun to their 0.75 away, with a sheen where it turns most to the sun, its top full.
func drum_into(st: SurfaceTool, at: Vector3, r: float, h: float, col: Color, segs := 16) -> void:
	var sun := Vector3(-1, 0, 1).normalized()
	var tone := func(a: float) -> Color:
		var d := Vector3(cos(a), 0, sin(a)).dot(sun)
		var t := 0.825 + 0.1 * d + 0.07 * pow(maxf(d, 0.0), 6.0)
		return Color(col.r * t, col.g * t, col.b * t)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var p0 := at + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := at + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var up := Vector3(0, h, 0)
		for v in [[p0 + up, a0], [p1 + up, a1], [p1, a1], [p0 + up, a0], [p1, a1], [p0, a0]]:
			st.set_color(tone.call(v[1]))
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v[0])
		st.set_color(col)
		for v in [at + up, p1 + up, p0 + up]:
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v)


## A capped tube of radius r from a to b into a vertex-coloured surface, shaded round by where each strip faces as
## box_into shades its faces, with a sheen along its sunlit top.
func pipe_into(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color, segs := 10) -> void:
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := u.cross(ax)
	var tone := func(n: Vector3) -> Color:
		var side := 0.9 if n.z - n.x > 0.0 else 0.75
		var t := lerpf(side, 1.0, n.y) if n.y > 0.0 else lerpf(side, 0.6, -n.y)
		t += 0.12 * pow(maxf(n.dot(Vector3(-0.3, 1.0, 0.3).normalized()), 0.0), 8.0)
		return Color(col.r * t, col.g * t, col.b * t)
	for i in segs:
		var n0 := (u * cos(TAU * i / segs) + v * sin(TAU * i / segs))
		var n1 := (u * cos(TAU * (i + 1) / segs) + v * sin(TAU * (i + 1) / segs))
		for e in [[a, n0], [b, n0], [b, n1], [a, n0], [b, n1], [a, n1]]:
			st.set_color(tone.call(e[1]))
			st.set_uv(Vector2.ZERO)
			st.add_vertex(e[0] + e[1] * r)
		for end in [[a, -ax], [b, ax]]:
			var c: Vector3 = end[0]
			st.set_color(tone.call(end[1]))
			for p in [c, c + n0 * r, c + n1 * r]:
				st.set_uv(Vector2.ZERO)
				st.add_vertex(p)


## A unit box under xf into a vertex-coloured surface, each face in the house's tones by where it ends up facing.
func turned_box_into(st: SurfaceTool, xf: Transform3D, col: Color) -> void:
	for n: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]:
		var u := Vector3.UP if absf(n.y) < 0.5 else Vector3.RIGHT
		var v := n.cross(u)
		var wn := (xf.basis.orthonormalized() * n)
		var side := 0.9 if wn.z - wn.x > 0.0 else 0.75
		var t := lerpf(side, 1.0, wn.y) if wn.y > 0.0 else lerpf(side, 0.7, -wn.y)
		st.set_color(Color(col.r * t, col.g * t, col.b * t))
		add_quad(st, [n - u - v, n + u - v, n + u + v, n - u + v].map(func(o): return xf * (o * 0.5)), [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])


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
	var all: Array = Sim.City.buildings() + farms
	var boxes := []
	var roofs := []
	brecs.clear()
	for bd in all:
		var r: Rect2 = bd.rect
		var c: Vector2 = bd.center
		var sz: Vector2 = bd.size
		if bd.has("greenhouse"):  # low film walls under a pitched film roof, milky white over the crops
			var film := Color(0.9, 0.94, 0.93, 0.5 / 8.0)
			brecs.append({"foot": r, "h": 2.6, "box": [boxes.size()], "roof": [roofs.size()], "hidden": STANDING})
			boxes.append([Vector3(sz.x, 1.5, sz.y), Vector3(c.x, 0.75, c.y), film.darkened(0.06), -1.0, 0.0])
			roofs.append([c, sz, 1.5, 1.1, Color(0.95, 0.97, 0.96), 0.0, sz.x > sz.y])
			continue
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
			rec.box.append(boxes.size())
			boxes.append(kit_box(r, h, bd.kit) + [0.0])
		brecs.append(rec)
	# landmarks with a traced model join the city's boxes and roofs on their square, one record each, so they cast
	# shadows, light up and clear for the street set like any building, but go whole
	lm_trees.clear()
	for L in C.landmarks:
		var key := "%s:%d" % C.districts[L.d].lm
		if not Models.MODELS.has(key):
			continue
		var k: float = L.size / 22.0  # models are traced on a 22 m square; a smaller square gets a smaller landmark
		var rec := {"foot": Rect2(L.pos - Vector2.ONE * L.size / 2, Vector2.ONE * L.size), "h": 0.0, "box": [], "roof": [], "hidden": STANDING, "lm": true, "cut": INF}
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
				if q[8] >= 0 and q[5] * k < 0.5:  # rooms on the ground, or on a kerb-high plinth
					rec.cut = minf(rec.cut, q[5] * k + LOW)
			else:
				rec.roof.append(roofs.size())
				roofs.append([at_, sz, q[5] * k, q[6] * k, Color(q[7]), 0.0, q[0] == 1])
				rec.h = maxf(rec.h, (q[5] + q[6]) * k)
		if rec.cut == INF:  # no rooms on the ground: a hall up on its platform shows its widest footing as a plan of its rooms
			var wide := 0.0
			for i in rec.box:
				if boxes[i][3] >= 0.0:
					rec.style = boxes[i][3]
			for i in rec.box if rec.has("style") else []:
				var e: Array = boxes[i]
				if e[1].y - e[0].y / 2 < 0.5 and e[0].x * e[0].z > wide and e[4] == 0.0:
					wide = e[0].x * e[0].z
					rec.plan = i
					rec.plan_a = e[3]
			if not rec.has("plan") and not grounds.is_empty():  # and a park keeps what lies below them, its lawns, paths and ponds
				rec.cut = LOW
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
	# past the sun's view the radial routes running on out of town lay their deck's and pillars' shadows as flat bands
	run_off_shadow_mat = StandardMaterial3D.new()
	run_off_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	run_off_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	run_off_shadow_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	run_off_shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := surface(run_off_shadow_mat)
	var lay := Vector2(-SUN.x, -SUN.z) / SUN.y  # ground offset per metre of height
	var inside := b.grow(200.0)
	var y := -0.05
	for sh in C.shuto:
		if not sh.has("mid"):
			continue
		var pts: PackedVector3Array = sh.pts
		var k := pts.size() - 1
		while k > 0 and not inside.has_point(Vector2(pts[k - 1].x, pts[k - 1].z) + lay * (Sim.City.DECK - 0.4)):
			k -= 1
		var a := Vector2(pts[k - 1].x, pts[k - 1].z)
		var dir := Vector2(pts[k].x, pts[k].z) - a
		var t := 0.0
		while inside.has_point(a + dir * t + lay * (Sim.City.DECK - 0.4)):
			t += 0.02
		var band := PackedVector3Array()
		for q in [a + dir * t, Vector2(pts[-1].x, pts[-1].z)]:
			var g: Vector2 = q + lay * (Sim.City.DECK - 0.4)
			band.append(Vector3(g.x, y, g.y))
		ribbon(st, band, Sim.City.EXPRESS_W / 2 + 0.2, -Sim.City.EXPRESS_W / 2 - 0.2)
	for dp in Sim.City.deck_pillars(C):
		var foot := Vector2(dp[2].x, dp[2].z)
		if not inside.has_point(foot):
			var top: Vector2 = foot + lay * dp[2].y
			ribbon(st, PackedVector3Array([Vector3(foot.x, y, foot.y), Vector3(top.x, y, top.y)]), dp[3] / 2, -dp[3] / 2)
	commit([st], city)


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
			# a sliding window: two sashes in an aluminium frame in a shaded reveal, the sky caught across the glass, a
			# curtain drawn across one sash (lit with the room after dark), a rail across the lower panes, a sill
			var sash := func(x: int, y: int, w: int, h: int, left: bool, rail: bool) -> void:
				var mid := x + int(w / 2.0)
				r.call(x - 1, y, w + 2, h + 1, wall_px(0.78))
				r.call(x, y, w, h, fixed("c4c9cc"))
				r.call(x + 1, y + 1, w - 2, h - 2, glass2)
				r.call(mid, y + 1, 1, h - 2, fixed("c4c9cc"))
				r.call(x + 1, y + 1, mid - x - 1, 1, fixed("6f8fa8"))
				for i in mini(3, mid - x - 1):
					r.call(x + 1 + i, y + 4 - i, 1, 1, fixed("6f8fa8"))
					r.call(mid + 1 + i, y + h - 4 - i, 1, 1, fixed("6f8fa8"))
				var cw := mini(3, mid - x - 1)
				var cx := x + 1 if left else x + w - 1 - cw
				r.call(cx, y + 1, cw, h - 2, fixed("e6dcc6"))
				r.call(cx + cw - 1 if left else cx, y + 1, 1, h - 2, fixed("cbbfa6"))
				if rail:
					var ry := y + int(h / 2.0)
					r.call(x + 1, ry, w - 2, 1, fixed("5a6068"))
					r.call(x + 1, y + h - 3, w - 2, 1, fixed("5a6068"))
					for rx in [x + 1, mid, x + w - 2]:
						r.call(rx, ry, 1, y + h - 2 - ry, fixed("5a6068"))
				r.call(x - 1, y + h, w + 2, 1, fixed("e2e4e2"))
				r.call(x - 1, y + h + 1, w + 2, 1, wall_px(0.6))
			# an office lobby behind full-height glass in an aluminium frame, lit all night: pale stone under a row of
			# downlights, a planter, a desk where the bay is wide enough, a pair of sliding doors, the sky across the panes
			var lobby := func(x: int, y: int, w: int, h: int, frame: Color) -> void:
				var lit := func(lx: int, ly: int, lw: int, lh: int, c: Color) -> void:
					r.call(lx, ly, lw, lh, c)
					mask.fill_rect(Rect2i(s * 32 + lx, row * 32 + ly, lw, lh), Color(0, 0, 1))
				r.call(x, y, w, h, frame)
				var gx := x + 1
				var gy := y + 1
				var gw := w - 2
				var gh := h - 2
				var fy := gy + gh - 4
				lit.call(gx, gy, gw, gh, fixed("c9ccc4"))
				lit.call(gx, gy, gw, 2, fixed("9ea6a8"))
				for lx in range(gx + 2, gx + gw - 1, 4):
					lit.call(lx, gy + 1, 2, 1, fixed("fff6dc"))
				lit.call(gx, fy, gw, 4, fixed("aeb2aa"))
				lit.call(gx, fy, gw, 1, fixed("848a88"))
				lit.call(gx + 2, fy - 3, 3, 3, fixed("5a5f66"))
				lit.call(gx + 1, fy - 8, 5, 5, fixed("4f8a4a"))
				lit.call(gx + 2, fy - 9, 2, 3, fixed("6aa65a"))
				var dx := gx + gw - 12
				if dx - gx > 14:
					lit.call(gx + 8, fy - 4, dx - gx - 10, 4, fixed("5c4c40"))
					lit.call(gx + 8, fy - 4, dx - gx - 10, 1, fixed("e8e2d6"))
					lit.call(gx + 10, fy - 6, 2, 2, fixed("3a3f48"))
				r.call(dx, gy, 1, gh, frame)
				r.call(dx + 6, gy + 3, 1, gh - 3, frame)
				r.call(dx, gy + 3, gw - (dx - gx), 1, frame)
				r.call(dx + 4, fy - 6, 1, 3, fixed("d8d8d0"))
				r.call(dx + 8, fy - 6, 1, 3, fixed("d8d8d0"))
				lit.call(dx + 1, fy + 1, 11, 2, fixed("6a6460"))
				for k in [[gx + 4, 8], [gx + 11, 4], [dx + 3, 6]]:
					for i in k[1]:
						for j in 3:
							var px := Vector2i(s * 32 + k[0] + i + j, row * 32 + fy - 2 - i * 2)
							if px.x < s * 32 + gx + gw and px.y > row * 32 + gy + 1:
								img.set_pixel(px.x, px.y, img.get_pixel(px.x, px.y).lerp(Color(0.92, 0.97, 1.0, 0), 0.5))
			match s:
				0:  # glass curtain wall
					if up:
						r.call(1, 1, 30, 28, glass)
						r.call(1, 2, 30, 5, fixed("5d7f9c"))
						r.call(15, 1, 2, 28, wall_px(0.95))
						r.call(0, 29, 32, 3, wall_px(0.85))
					else:  # the lobby under a canopy's soffit, edged in the building's colour, on a granite step
						r.call(0, 0, 32, 3, wall_px(0.9))
						r.call(0, 3, 32, 1, accent(0.9))
						r.call(0, 4, 32, 1, wall_px(0.55))
						lobby.call(0, 5, 32, 25, fixed("8c959e"))
						r.call(0, 30, 32, 2, fixed("8a8a84"))
				1:  # concrete office, ribbon windows
					if up:  # a band of panes in aluminium frames under the slab's shadow: the sky across the top of the glass, a
						# glint across each pane, office blinds let down part way in some (lit with the room after dark), a sill
						r.call(0, 8, 32, 1, wall_px(0.62))
						r.call(0, 9, 32, 13, fixed("c4c9cc"))
						for x0 in [0, 8, 16, 24]:
							r.call(x0, 10, 7, 11, glass)
							r.call(x0, 10, 7, 2, fixed("5d7f9c"))
							r.call(x0, 10, 7, 1, fixed("6f8fa8"))
							for i in 5:
								r.call(x0 + 1 + i, 19 - i, 2, 1, glass2)
						for b in [[8, 4], [24, 6]]:
							r.call(b[0], 10, 7, b[1], fixed("e6dcc6"))
							r.call(b[0], 10 + b[1], 7, 1, fixed("ece6d2"))
							for y in range(12, 10 + b[1], 3):
								r.call(b[0], y, 7, 1, fixed("cbbfa6"))
						r.call(0, 21, 32, 1, fixed("8a9096"))
						r.call(0, 22, 32, 1, fixed("e2e4e2"))
						r.call(0, 23, 32, 1, wall_px(0.6))
					else:  # the lobby set into the wall under a steel canopy, up a step
						r.call(0, 8, 32, 2, fixed("b8bcc0"))
						r.call(0, 10, 32, 1, fixed("5a6068"))
						r.call(2, 10, 28, 20, wall_px(0.7))
						lobby.call(3, 11, 26, 19, fixed("6a7078"))
						r.call(2, 30, 28, 2, wall_px(0.62))
				2:  # apartments with balconies
					if up:
						sash.call(3, 6, 14, 12, true, false)
						sash.call(20, 6, 8, 14, false, false)  # the balcony's sliding door
						r.call(0, 20, 32, 2, wall_px(0.75))
						r.call(1, 22, 30, 6, fixed("c8ccd0"))
						for x in range(2, 31, 3):
							r.call(x, 22, 1, 6, fixed("9aa0a6"))
					else:  # the entrance: a glazed door pair under a concrete hood and its downlight, the hall behind it
						# (mailboxes over a pale floor) lit all night, up a granite step
						sash.call(3, 10, 10, 9, false, false)
						var hall := func(x: int, y: int, w: int, h: int, c: Color) -> void:
							r.call(x, y, w, h, c)
							mask.fill_rect(Rect2i(s * 32 + x, row * 32 + y, w, h), Color(0, 0, 1))
						r.call(14, 7, 16, 2, fixed("b8bcc0"))
						r.call(14, 9, 16, 1, wall_px(0.55))
						hall.call(21, 9, 2, 1, fixed("fff6dc"))
						r.call(15, 10, 14, 20, wall_px(0.66))
						r.call(16, 10, 12, 20, fixed("8a8f96"))
						hall.call(17, 11, 10, 19, fixed("cfc8b6"))
						hall.call(17, 11, 10, 1, fixed("fff6dc"))
						for my in [14, 16, 18]:
							hall.call(17, my, 4, 1, fixed("8a9096"))
							hall.call(17, my + 1, 4, 1, fixed("b4b8bc"))
						hall.call(24, 15, 3, 5, fixed("7f9a7a"))
						hall.call(17, 25, 10, 5, fixed("aeb2aa"))
						hall.call(17, 25, 10, 1, fixed("8f938c"))
						r.call(21, 11, 2, 19, fixed("8a8f96"))
						r.call(20, 17, 1, 4, fixed("e2e4e2"))
						r.call(23, 17, 1, 4, fixed("e2e4e2"))
						r.call(17, 28, 10, 2, fixed("6a7078"))
						for i in 8:
							for j in 2:
								var px := Vector2i(s * 32 + 18 + i + j, row * 32 + 27 - i * 2)
								if px.x != s * 32 + 21 and px.x != s * 32 + 22:
									img.set_pixel(px.x, px.y, img.get_pixel(px.x, px.y).lerp(Color(0.92, 0.97, 1.0, 0), 0.45))
						r.call(14, 30, 16, 2, fixed("8a8a84"))
						r.call(14, 30, 16, 1, fixed("a9a9a2"))
				3:  # shops below, flats above
					if up:  # two sliding windows, each with a curtain drawn across one sash, a rail and a sill
						sash.call(3, 6, 11, 13, true, true)
						sash.call(18, 6, 11, 13, false, true)
						r.call(0, 21, 32, 2, wall_px(0.8))
						r.call(0, 30, 32, 2, wall_px(0.88))
					else:  # a shopfront: striped awning, shelves behind mullioned glass, a glazed door, lit after dark
						r.call(0, 0, 32, 2, wall_px(0.82))
						r.call(0, 2, 32, 1, wall_px(0.5))
						r.call(0, 10, 32, 1, fixed("3a3f46"))
						# the awning in canvas stripes, the shop's colour and cream: its slope lit toward the front fold, the
						# valance a shade darker below, each stripe ending in a scallop over the shadow it casts on the glass
						# (the cream lights with the shop after dark, as the colour does)
						var cream := fixed("f2ecdc")
						for x in range(0, 32, 8):
							for k in 2:
								var sx := x + k * 4
								var put := func(y: int, w: int, v: float) -> void:
									var c := accent(v) if k == 0 else Color(cream.darkened(1.0 - v), 0.0)
									r.call(sx + ((4 - w) >> 1), y, w, 1, c)
									if k == 1:
										mask.fill_rect(Rect2i(s * 32 + sx + ((4 - w) >> 1), row * 32 + y, w, 1), Color(0, 0, 1))
								for y in range(3, 7):
									put.call(y, 4, 0.84 + (y - 3) * 0.04)
								put.call(7, 4, 1.0)
								put.call(8, 4, 0.8)
								put.call(9, 4, 0.76)
								put.call(10, 2, 0.68)
						r.call(1, 11, 21, 18, fixed("4a525a"))
						r.call(2, 12, 19, 16, fixed(SHOP_GLASS))
						r.call(11, 12, 1, 16, fixed("4a525a"))
						# a strip light under the ceiling, then three shelves stocked edge to edge in runs of facings, each
						# pack a shade apart with a paler lid, a gap where one has sold, a plinth at the foot
						for x0 in [3, 13]:
							r.call(x0, 12, 7, 1, fixed("eef0e8"))
						var goods := ["e0a040", "d05050", "60a060", "5a8fd0", "e8e0c8", "f0cf5a", "c0628e", "3f8f8a", "8a5a3a"]
						var gr := RandomNumberGenerator.new()
						gr.seed = 23
						for shelf in [[17, 3], [22, 4], [27, 4]]:
							var sy: int = shelf[0]
							r.call(2, sy, 19, 1, fixed("b9bdb8") if sy < 27 else fixed("7d8288"))
							var x := 2
							while x < 21:
								var run := gr.randi_range(2, 4)
								var gc := Color(goods[gr.randi() % goods.size()])
								var gh := gr.randi_range(2, shelf[1] - 1)
								for i in run:
									if x >= 21:
										break
									if x != 11 and gr.randf() > 0.08:
										var c := gc.darkened(0.08) if i % 2 else gc
										r.call(x, sy - gh, 1, gh, Color(c, 0.0))
										r.call(x, sy - gh, 1, 1, Color(c.lightened(0.25), 0.0))
									x += 1
								x += 1 if gr.randf() < 0.3 else 0
						r.call(3, 13, 4, 3, fixed("f4f1e6"))  # a sale poster taped inside the glass
						r.call(3, 13, 4, 1, fixed("d8493a"))
						r.call(4, 15, 2, 1, fixed("d8493a"))
						r.call(1, 29, 21, 3, wall_px(0.68))
						r.call(23, 11, 8, 21, fixed("4a525a"))
						r.call(24, 12, 6, 19, fixed(SHOP_GLASS))
						r.call(24, 12, 6, 3, accent(0.9))
						r.call(25, 21, 1, 3, fixed("d8d8d0"))
						r.call(25, 16, 4, 3, fixed("f4f1e6"))  # the open sign hung in the door
						r.call(25, 17, 4, 1, fixed("d8493a"))
						r.call(23, 31, 8, 1, fixed("8a8a84"))
						# the shop inside the glass (shelves, goods, the door's pane) lights up after dark in its own colours
						for win in [Rect2i(2, 12, 19, 16), Rect2i(24, 15, 6, 16)]:
							for y in range(win.position.y, win.end.y):
								for x in range(win.position.x, win.end.x):
									var px := img.get_pixel(s * 32 + x, y).to_html(false)
									if px != "4a525a":
										mask.set_pixel(s * 32 + x, y, Color(0, 1 if px == SHOP_GLASS else 0, 1))
				4:  # neon-sign buildings: a bar on every floor, each with its panel in the blade sign up the front
					# pixels that glow after dark in their own colours: sign lettering, a bar's room through its glass
					var lit := func(x: int, y: int, w: int, h: int, c: Color) -> void:
						r.call(x, y, w, h, c)
						mask.fill_rect(Rect2i(s * 32 + x, row * 32 + y, w, h), Color(0, 0, 1))
					var frame := fixed("4a525a")
					var ink := fixed("f6efd8")
					var glyph := func(x: int, y: int, k: int, h := 6) -> void:  # a made-up character, 4 px wide
						var rows: Array = GLYPHS[k % GLYPHS.size()]
						for gy in mini(h, rows.size()):
							for gx in 4:
								if rows[gy][gx] == "#":
									lit.call(x + gx, y + gy, 1, 1, ink)
					if up:  # a tenant's window in a deep frame, the sky across its glass, its name on the pane; an AC unit
						r.call(0, 0, 32, 2, wall_px(0.92))
						r.call(0, 2, 32, 1, wall_px(0.7))
						r.call(1, 6, 18, 18, wall_px(0.74))
						r.call(2, 6, 16, 17, fixed("c4c9cc"))
						r.call(3, 7, 14, 15, fixed("2c3644"))
						r.call(3, 7, 14, 4, fixed("4f6f8c"))
						r.call(2, 11, 16, 1, fixed("c4c9cc"))
						r.call(10, 7, 1, 15, fixed("c4c9cc"))
						for i in 4:
							r.call(4 + i, 21 - i, 1, 1, fixed("5d7f9c"))
							r.call(12 + i, 21 - i, 1, 1, fixed("5d7f9c"))
						for x in [4, 7, 12, 15]:
							r.call(x, 16, 2, 1, fixed("e8d9a0"))
						r.call(4, 18, 5, 1, fixed("e8d9a0"))
						r.call(1, 23, 18, 1, fixed("e2e4e2"))
						r.call(1, 24, 18, 1, wall_px(0.6))
						r.call(4, 26, 8, 4, fixed("d6d8d4"))
						r.call(5, 27, 3, 2, fixed("8e9398"))
						r.call(9, 27, 2, 1, fixed("aeb2b4"))
						r.call(4, 30, 8, 1, wall_px(0.62))
						r.call(12, 25, 1, 3, fixed("c8c4b8"))
						# the blade sign, one tenant's panel a floor: lettering stacked down a lit face in a dark box
						r.call(19, 5, 2, 1, frame)
						r.call(19, 25, 2, 1, frame)
						r.call(21, 0, 9, 32, fixed("3a3f48"))
						r.call(22, 1, 7, 28, accent(1.0))
						r.call(27, 1, 1, 28, accent(0.8))
						r.call(22, 1, 7, 1, accent(0.72))
						r.call(22, 29, 7, 1, accent(0.6))
						for i in 3:
							glyph.call(23, 4 + i * 8, i)
						lit.call(23, 27, 1, 1, ink)
						lit.call(25, 27, 1, 1, ink)
					else:  # a lightbox fascia lettered in the bar's name over its glazed front and a door hung with noren
						r.call(0, 0, 32, 2, wall_px(0.85))
						r.call(0, 2, 32, 7, fixed("3a3f48"))
						r.call(1, 3, 30, 5, accent(1.0))
						r.call(1, 7, 30, 1, accent(0.75))
						for i in 4:
							glyph.call(4 + i * 6, 3, 3 + i, 5)
						r.call(0, 9, 32, 1, wall_px(0.55))
						r.call(1, 11, 21, 18, frame)
						lit.call(2, 12, 19, 16, fixed("d9c08a"))
						lit.call(2, 12, 19, 2, fixed("b89a64"))
						for x in [5, 13, 18]:
							lit.call(x, 14, 1, 2, fixed("6a5a48"))
							lit.call(x - 1, 16, 3, 1, fixed("fff1c0"))
						lit.call(2, 21, 19, 1, fixed("a86a3e"))
						lit.call(2, 22, 19, 3, fixed("7a4a2e"))
						for x in [4, 8, 14, 18]:
							lit.call(x, 25, 2, 1, fixed("c0392b"))
							lit.call(x, 26, 1, 2, fixed("3a3030"))
						r.call(11, 12, 1, 16, frame)
						r.call(1, 29, 21, 3, wall_px(0.66))
						r.call(23, 11, 8, 21, frame)
						lit.call(24, 12, 6, 19, fixed("e0c48c"))
						for x in [24, 26, 28]:
							r.call(x, 12, 2, 6, accent(0.85 if x == 26 else 0.95))
						r.call(24, 18, 6, 1, accent(0.6))
						r.call(25, 22, 1, 3, fixed("d8d8d0"))
						r.call(23, 31, 8, 1, fixed("8a8a84"))
				5:  # wooden machiya
					for x in range(1, 32, 4):
						r.call(x, 0, 1, 32, wall_px(0.84))
					if up:  # a plastered panel pierced by mushiko-mado, plaster ribs over a dark room that lights after dark
						r.call(0, 0, 32, 3, wall_px(0.55))
						r.call(3, 7, 26, 17, fixed("dcd2bc"))
						r.call(3, 7, 26, 1, fixed("eee6d4"))
						r.call(3, 23, 26, 1, fixed("b4aa94"))
						for x0 in [6, 18]:
							r.call(x0 - 1, 10, 10, 12, fixed("b4aa94"))
							r.call(x0, 11, 8, 10, fixed("26313e"))
							for x in range(x0 + 1, x0 + 8, 2):
								r.call(x, 11, 1, 10, fixed("d4cab4"))
							r.call(x0 - 1, 21, 10, 1, fixed("eee6d4"))
					else:
						# a pent roof of kawara along the top, its lip lit over the shadow it casts on the wall
						r.call(0, 0, 32, 4, fixed("4c525c"))
						for x in range(0, 32, 3):
							r.call(x, 0, 1, 4, fixed("3a3f48"))
							r.call(x + 1, 0, 1, 3, fixed("5e6570"))
						r.call(0, 4, 32, 1, fixed("7a828e"))
						r.call(0, 5, 32, 2, wall_px(0.5))
						# koshi: fine slats on a dark frame over paper screens, which light with the room after dark
						r.call(1, 8, 19, 20, wall_px(0.42))
						r.call(2, 9, 17, 18, fixed("e8e0c8"))
						for x in range(2, 19, 2):
							r.call(x, 9, 1, 18, wall_px(0.6))
						r.call(2, 13, 17, 1, wall_px(0.5))
						# inu-yarai: a bamboo fence bowed out along the foot of the lattice
						r.call(1, 28, 19, 4, wall_px(0.38))
						for x in range(2, 19, 2):
							r.call(x, 29, 1, 3, fixed("a88c58"))
						r.call(1, 27, 19, 1, fixed("c8ac70"))
						r.call(1, 28, 19, 1, fixed("b09660"))
						# a latticed sliding door under a noren of three panels in the accent colour, a ringed crest across it
						r.call(21, 7, 10, 25, wall_px(0.42))
						r.call(22, 8, 8, 23, fixed("e6dcc6"))
						for x in range(22, 30, 2):
							r.call(x, 8, 1, 23, wall_px(0.6))
						for y in [19, 25]:
							r.call(22, y, 8, 1, wall_px(0.6))
						r.call(22, 8, 8, 9, accent(0.95))
						r.call(22, 8, 8, 1, accent(0.6))
						for x in [24, 27]:
							r.call(x, 9, 1, 8, accent(0.68))
						for c in [Rect2i(25, 11, 2, 1), Rect2i(25, 14, 2, 1), Rect2i(24, 12, 1, 2), Rect2i(27, 12, 1, 2)]:
							r.call(c.position.x, c.position.y, c.size.x, c.size.y, fixed("f4ecd8"))
						r.call(21, 31, 10, 1, fixed("8a8a84"))
				6:  # house in lapped siding, each board's lip a shade over the one below
					for y in range(3, 32, 4):
						r.call(0, y, 32, 1, wall_px(0.93))
					var shutter_box := func(x: int, y: int, h: int) -> void:  # the storm shutters' case beside a window
						r.call(x, y, 3, h, fixed("b4b9be"))
						r.call(x, y, 3, 1, fixed("d4d8db"))
						r.call(x + 2, y + 1, 1, h - 1, fixed("8f949a"))
					if up:  # a sliding window beside its shutter case, a vent hood, the belly band at the floor line
						sash.call(7, 8, 14, 13, true, true)
						shutter_box.call(22, 7, 15)
						r.call(26, 3, 3, 2, fixed("d6d8d4"))
						r.call(26, 5, 3, 1, fixed("5a6068"))
						r.call(0, 29, 32, 2, wall_px(0.84))
						r.call(0, 29, 32, 1, wall_px(0.98))
					else:
						# the front door under a hood with a lamp beside it: grained wood with a bar handle in a dark frame,
						# a frosted sidelight that lights with the hall after dark, up a step
						var hall := func(x: int, y: int, w: int, h: int, c: Color) -> void:
							r.call(x, y, w, h, c)
							mask.fill_rect(Rect2i(s * 32 + x, row * 32 + y, w, h), Color(0, 0, 1))
						r.call(1, 7, 14, 2, fixed("c8ccd0"))
						r.call(1, 9, 14, 1, wall_px(0.55))
						r.call(2, 10, 12, 18, fixed("4e4a46"))
						hall.call(3, 11, 2, 16, fixed("dcd6c6"))
						r.call(6, 11, 7, 17, fixed("8a6446"))
						for x in [7, 9, 12]:
							r.call(x, 11, 1, 17, fixed("7a5638"))
						r.call(6, 11, 7, 1, fixed("a07a58"))
						r.call(7, 16, 1, 6, fixed("cfcfc8"))
						hall.call(15, 12, 1, 2, fixed("fff1c0"))
						r.call(1, 28, 14, 1, fixed("c9c5bb"))
						r.call(1, 29, 14, 1, fixed("a29e95"))
						# a window behind a grille of bars beside its shutter case
						sash.call(17, 11, 10, 10, false, false)
						for x in range(18, 27, 2):
							r.call(x, 11, 1, 10, fixed("8a8f96"))
						r.call(17, 11, 10, 1, fixed("8a8f96"))
						r.call(17, 20, 10, 1, fixed("8a8f96"))
						shutter_box.call(28, 10, 13)
						# the concrete foundation along the foot, an underfloor vent let into it
						r.call(15, 28, 17, 4, fixed("a7a59e"))
						r.call(15, 28, 17, 1, fixed("bdbbb3"))
						r.call(0, 30, 15, 2, fixed("a7a59e"))
						r.call(21, 29, 5, 2, fixed("5a6068"))
						for x in [22, 24]:
							r.call(x, 29, 1, 2, fixed("8a8f96"))
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


const GLYPHS := [
	["####", "...#", "####", "...#", "..#.", ".#.."],
	["####", "#..#", "#..#", "####", "....", "...."],
	[".#..", "####", ".#..", "##.#", ".#..", ".##."],
	["#.#.", "####", "#.#.", "....", "....", "...."],
	["####", ".#..", ".##.", ".#..", "....", "...."],
	[".##.", "#..#", ".##.", "#..#", "....", "...."],
	["#..#", "####", "#..#", "#..#", "....", "...."],
]
const SHOP_GLASS := "a9cdd6"  # a shop window's pane: the back of the shop, glowing after dark
const WINDOWS := ["3d5a78", "4f6f8c", "26313e", "5d7f9c", "2c3644", "e8d9a0", "8fb3c0", "ece6d2", "e8e0c8", "c9b98a", "39475a", "e8dcb0", "6f8fa8", "e6dcc6"]


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
	for k in 420:  # woods out in the country, clear of the roads: stands of cedar or broadleaf, crowns touching,
		# taller toward the middle and ringed by bushes, so each reads as one wood rather than a scatter of trees
		var g := Vector2(r.randf_range(b.position.x, b.end.x), r.randf_range(b.position.y, b.end.y))
		var rad := Vector2(r.randf_range(8.0, 24.0), r.randf_range(8.0, 24.0))
		var kinds: Array = [3, 3, 3, 1] if r.randf() < 0.45 else [1, 1, 1, 1, 3]
		for j in int(rad.x * rad.y * 0.16) + 3:
			var u := sqrt(r.randf())
			var p := g + Vector2.from_angle(r.randf() * TAU) * rad * u
			if country(Rect2(p - Vector2(2, 2), Vector2(4, 4)), 8.0):
				if u > 0.85 and r.randf() < 0.5:
					add.call(4, p, r.randf_range(1.8, 2.3))
				else:
					add.call(kinds[r.randi() % kinds.size()], p, r.randf_range(1.5, 1.8) + 0.5 * (1.0 - u))
	tree_mms.clear()
	var d := Vector2(-SUN.x, -SUN.z) / SUN.y
	var dn := d.normalized()
	tree_shadow_mat = ShaderMaterial.new()
	tree_shadow_mat.shader = Shader.new()
	tree_shadow_mat.shader.code = TREE_SHADOW_SHADER
	tree_shadow_mat.set_shader_parameter("blob", soft_mat.albedo_texture)
	tree_shadow_mat.set_shader_parameter("dir", dn)
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
		var st := SurfaceTool.new()  # its shadows: the patch round its foot, then its crown's as outdoor_cast lays it
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var f := 0.3 * qs.y
		var quads := [[Vector2(-f, -f), Vector2(f, -f), Vector2(f, f), Vector2(-f, f), 1.0]]
		for c in OUTDOOR_CAST[id]:
			if c.size() > 3:
				var near: Vector2 = dn * c[0] * qs.y * d.length()
				var far: Vector2 = dn * c[1] * qs.y * d.length()
				var w: Vector2 = dn.orthogonal() * c[2] * qs.y / 2
				quads.append([near - w, near + w, far + w, far - w, 0.0])
		for qd in quads:
			st.set_color(Color(qd[4], 0, 0))
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_uv([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)][k])
				st.add_vertex(Vector3(qd[k].x, -0.03, qd[k].y))
		var list: Array = spots[id]
		var mm := multimesh(q, list.size())
		var sh := multimesh(st.commit(), list.size())
		var base := []
		for k in list.size():
			var tf := Transform3D(Basis.from_scale(Vector3.ONE * list[k][1]), list[k][0])
			mm.set_instance_transform(k, tf)
			sh.set_instance_transform(k, tf)
			base.append(tf)
		mm_node(sh, tree_shadow_mat, city)
		mm_node(mm, m, city)
		tree_mms.append([mm, base, qs.y, sh])


## Plots, and in city mode every branch's storefront with its rival beside it (the focused one is the street set).
func build_lots() -> void:
	for c in lots_node.get_children():
		c.free()
	lot_nodes.clear()
	lot_feet.clear()
	var plot := surface(vacant_plot())
	for i in sim.lots.size():
		var L: Dictionary = sim.lots[i]
		var r := Rect2(L.x0, L.front - Sim.City.LOT_D, Sim.City.LOT_W, Sim.City.LOT_D)
		var u := [0.0, 1.0] if i % 2 == 0 else [1.0, 0.0]  # every other lot mirrored, its tracks and weeds the other way
		add_quad(plot, [Vector3(r.position.x, -0.08, r.position.y), Vector3(r.end.x, -0.08, r.position.y), Vector3(r.end.x, -0.08, r.end.y), Vector3(r.position.x, -0.08, r.end.y)],
			[Vector2(u[0], 0), Vector2(u[1], 0), Vector2(u[1], 1), Vector2(u[0], 1)])
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


## A vacant lot, 22 x 10 m at 8 px a metre, its front (the street) at the bottom: rolled gravel mottled and flecked,
## a concrete kerb round it shading the gravel inside on the sides away from the sun, open at a dropped kerb where
## two tyre tracks worn darker run in, and weeds clumped along the kerbs and in the corners the cars never reach.
func vacant_plot() -> StandardMaterial3D:
	if plot_m:
		return plot_m
	const W := 176
	const H := 80
	var r := RandomNumberGenerator.new()
	r.seed = 43
	var fn := FastNoiseLite.new()
	fn.seed = 43
	fn.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	fn.frequency = 0.06
	fn.fractal_octaves = 3
	var gravel := Color("a69e8d")
	var kerb := Color("d6d1c4")
	var weed := [Color("6f8f45"), Color("88a854"), Color("a9c46c")]
	var gap := Vector2(54, 98)  # the dropped kerb's x span on the front
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			var f := lerpf(0.9, 1.06, fn.get_noise_2d(x, y) * 0.5 + 0.5)
			var g := r.randf()
			f *= 1.1 if g < 0.12 else (0.86 if g < 0.2 else r.randf_range(0.97, 1.02))
			for tx in [64.0, 88.0]:  # the tracks bend in from the gap and fade toward the back
				var cx: float = tx + 6.0 * sin(y / 30.0)
				var d := absf(x - cx)
				if d < 4.0:
					f *= lerpf(0.86, 1.0, d / 4.0) + (1.0 - lerpf(0.86, 1.0, d / 4.0)) * (1.0 - y / float(H)) * 0.7
			var c := gravel * f
			var edge := mini(mini(x, W - 1 - x), mini(y, H - 1 - y))
			var in_gap := y >= H - 2 and x >= gap.x and x <= gap.y
			if edge == 0 and not in_gap:
				c = kerb * r.randf_range(0.95, 1.03)
			elif edge == 1 and not in_gap:
				c = kerb.darkened(0.12) if (y == H - 2 or x == 1) else kerb.darkened(0.05)
			elif (x <= 3 or y >= H - 4) and not (y >= H - 4 and x > gap.x - 2 and x < gap.y + 2):
				c = c.darkened(0.16 if (x == 2 or y == H - 3) else 0.08)  # the kerb's shadow, cast away from the sun
			img.set_pixel(x, y, Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0)))
	for i in 46:  # weed clumps hugging the kerbs, thickest in the corners
		var p := Vector2(r.randf_range(2, W - 3), r.randf_range(2, H - 3))
		match r.randi() % 4:
			0: p.x = r.randf_range(2, 7)
			1: p.x = r.randf_range(W - 8, W - 3)
			2: p.y = r.randf_range(2, 6)
			3: p.y = r.randf_range(H - 7, H - 3)
		if p.y > H - 8 and p.x > gap.x - 4 and p.x < gap.y + 4:
			continue
		var rad := r.randf_range(1.2, 3.2) * (1.4 if (p.x < 10 or p.x > W - 11) and (p.y < 9 or p.y > H - 10) else 1.0)
		for y in range(int(p.y - rad), int(p.y + rad) + 1):
			for x in range(int(p.x - rad * 1.4), int(p.x + rad * 1.4) + 1):
				if x < 2 or y < 2 or x > W - 3 or y > H - 3:
					continue
				var d := Vector2((x - p.x) / 1.4, y - p.y).length() / rad
				if d < 1.0 and r.randf() < 1.1 - d * 0.6:
					img.set_pixel(x, y, weed[2] if (y < p.y - rad * 0.3 and r.randf() < 0.5) else weed[r.randi() % 2])
				elif d < 1.3 and y == int(p.y + rad) + 0:
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.12))  # the clump's shadow on the gravel
	img.generate_mipmaps()
	plot_m = mat(Color.WHITE, ImageTexture.create_from_image(img))
	plot_m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	plot_m.texture_repeat = false
	return plot_m


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
		var back := INF
		if lot_feet.any(func(q): return f.intersects(q)):
			state = GONE
		elif on:
			if set_feet.any(func(q): return f.intersects(q)) or (f.intersects(front) and f.get_center().y < front.position.y + 7.2):
				state = GONE
				# one that only reaches into the set from behind is cut back to clear it, full height, so the block
				# behind your shop stays built up rather than a bare lot
				var kept := Rect2(f.position, Vector2(f.size.x, set_feet[0].position.y - f.position.y)) if set_feet else Rect2()
				if kept.size.y >= 4.0 and not rec.has("lm") and box_base[rec.box[0]].basis.x.z == 0.0 and not kept.intersects(front) and not set_feet.any(func(q): return kept.intersects(q)):
					state = STANDING
					back = kept.end.y
			elif f.intersects(front) or (f.end.x + f.end.y > depth and foot_rect(f, rec.h).intersects(scr)):
				state = maxf(f.position.y, edge)
				if f.end.y - state < 2.0 or (rec.get("cut", 0.0) == INF and not rec.has("plan")) or (not rec.has("lm") and state > f.position.y and box_base[rec.box[0]].basis.x.z != 0.0):  # too thin, turned, or nothing low to keep
					state = GONE
		if state == rec.hidden and back == rec.get("back", INF):
			continue
		rec.hidden = state
		rec.back = back
		dirty[box_mm] = true
		for i in rec.box.size():
			var k: int = rec.box[i]
			var t: Transform3D = box_base[k]
			var sz := t.basis.get_scale()
			var cd := box_mm.get_instance_custom_data(k)
			if back < INF:
				var z0 := t.origin.z - sz.z / 2
				var z1 := minf(back, t.origin.z + sz.z / 2)
				if i > 0 and z1 < t.origin.z + sz.z / 2:  # roof kit that would be sliced through
					box_mm.set_instance_transform(k, away)
				else:
					box_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(sz.x, sz.y, z1 - z0)), Vector3(t.origin.x, t.origin.y, (z0 + z1) / 2)))
					box_mm.set_instance_custom_data(k, Color(cd.r, sz.y, z1 - z0, cd.a))
			elif state == STANDING:
				box_mm.set_instance_transform(k, t)
				box_mm.set_instance_custom_data(k, Color(cd.r, sz.y, sz.z, rec.plan_a if k == rec.get("plan", -1) else cd.a))
			elif state == GONE or (i > 0 and not rec.has("lm")):
				box_mm.set_instance_transform(k, away)
			elif rec.has("plan"):
				var z0 := maxf(state, t.origin.z - sz.z / 2)
				var z1 := t.origin.z + sz.z / 2
				if k != rec.plan or z1 - z0 < 2.0:
					box_mm.set_instance_transform(k, away)
				else:
					box_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(sz.x, LOW, z1 - z0)), Vector3(t.origin.x, LOW / 2, (z0 + z1) / 2)))
					box_mm.set_instance_custom_data(k, Color(cd.r, LOW, z1 - z0, rec.style))
			elif rec.has("lm"):
				# a landmark with rooms on the ground is cut down to them: its plinth and paving stay, its halls show
				# their floor plans and posts and towers go, so its square isn't left as bare paving
				var z0 := maxf(state, t.origin.z - sz.z / 2)
				var z1 := t.origin.z + sz.z / 2
				var y0 := t.origin.y - sz.y / 2
				var y1 := t.origin.y + sz.y / 2
				var sliced: bool = y1 > rec.cut
				if sliced:
					y1 = rec.cut + 0.004 * (i % 8)  # stepped apart a hair where cut parts overlap
				if y0 >= rec.cut or (sliced and cd.a < 0.0) or z1 - z0 < 0.5 or (z0 > t.origin.z - sz.z / 2 and t.basis.x.z != 0.0):
					box_mm.set_instance_transform(k, away)
				else:
					box_mm.set_instance_transform(k, Transform3D(t.basis.orthonormalized() * Basis.from_scale(Vector3(sz.x, y1 - y0, z1 - z0)), Vector3(t.origin.x, (y0 + y1) / 2, (z0 + z1) / 2)))
					box_mm.set_instance_custom_data(k, Color(cd.r, y1 - y0, z1 - z0, cd.a))
			else:
				var z0 := maxf(state, t.origin.z - sz.z / 2)
				var z1 := t.origin.z + sz.z / 2
				box_mm.set_instance_transform(k, Transform3D(t.basis.orthonormalized() * Basis.from_scale(Vector3(sz.x, LOW, z1 - z0)), Vector3(t.origin.x, LOW / 2, (z0 + z1) / 2)))
				box_mm.set_instance_custom_data(k, Color(cd.r, LOW, z1 - z0, cd.a))
		for k in rec.roof:
			var rt: Transform3D = roof_base[k] if state == STANDING else away
			if back < INF:  # squeezed back along z, keeping its pitch when the ridge runs across the cut
				var rz0 := rt.origin.z - (absf(rt.basis.x.z) + absf(rt.basis.z.z)) / 2
				var s := (back - rz0) / (rt.origin.z - rz0) / 2
				var sy := s if absf(rt.basis.x.z) > 0.5 else 1.0
				var y0 := rt.origin.y - rt.basis.y.y / 2
				rt = Transform3D(Basis.from_scale(Vector3(1, sy, s)), Vector3(0, y0 * (1 - sy), rz0 * (1 - s))) * rt
			roof_mm.set_instance_transform(k, rt)
			dirty[roof_mm] = true
		for n in rec.get("shapes", []):
			n.visible = state == STANDING or (state != GONE and not n is MultiMeshInstance3D)  # a cut-down landmark keeps its pools and lawns
	for tm in tree_mms:
		for k in tm[1].size():
			var p: Vector3 = tm[1][k].origin
			var cut: bool = taken.call(Rect2(p.x - 1.5, p.z - 1.5, 3, 3)) or lot_feet.any(func(q): return q.has_point(Vector2(p.x, p.z))) or (on and p.x + p.z > depth and foot_rect(Rect2(p.x - 1.5, p.z - 1.5, 3, 3), tm[2]).intersects(scr))
			if tm[0].get_instance_transform(k) != (away if cut else tm[1][k]):
				tm[0].set_instance_transform(k, away if cut else tm[1][k])
				tm[3].set_instance_transform(k, away if cut else tm[1][k])
				dirty[tm[0]] = true
				dirty[tm[3]] = true
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
				elif tm[3] == mm:
					tm[3] = fresh
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
## red, low beams thrown down the road ahead after dark and the tail lamps glowing red behind.
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
			pm.size = Vector2(7.0, 2.6 if kv != 3 else 1.6)
			beam.mesh = pm
			beam.material_override = headlight_mat
			beam.position = Vector3(BEAM_AHEAD * dir, 0.03 - y, 0)
			beam.rotation.y = 0.0 if dir > 0.0 else PI
			var tail := MeshInstance3D.new()
			var tm := PlaneMesh.new()
			tm.size = Vector2(2.0, 2.4 if kv != 3 else 1.2)
			tail.mesh = tm
			tail.material_override = tail_glow_mat
			tail.position = Vector3(-BEAM_AHEAD - 1.2, 0.0, 0)
			beam.add_child(tail)
			node.add_child(beam)
			node.add_child(car_lamps())
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
			beam.position = Vector3(t.x * BEAM_AHEAD, beam.position.y, t.z * BEAM_AHEAD)
			beam.rotation.y = atan2(-t.z, t.x)
			shine(o.node)
			lamps_on(o.node)
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
		lamps_on(o.node)
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


const BEAM_AHEAD := 4.3  # from a car's centre to the middle of its low beams' throw


## Spots in a vehicles.png cell where a lamp is drawn, by frame: [x, y, radius in px, kind] with h a headlight, t a
## tail lamp and s a taxi's roof sign.
const CAR_LAMPS := [
	[[116, 57, 4, "h"], [81, 68, 4, "h"]], [[82, 65, 4, "t"], [119, 52, 3, "t"]],
	[[90, 75, 4, "h"], [118, 64, 3, "h"], [64, 23, 5, "s"]], [[82, 75, 4, "t"], [119, 63, 3, "t"], [64, 21, 5, "s"]],
	[[88, 69, 4, "h"], [119, 58, 3, "h"]], [[84, 78, 3, "t"], [113, 66, 3, "t"]],
	[[87, 44, 4, "h"]], [[91, 66, 3, "t"]],
]
const CAR_LAMP_TINT := {"h": Color(1.0, 0.9, 0.62), "t": Color(1.0, 0.16, 0.1), "s": Color(1.0, 0.78, 0.32)}


## A moving vehicle's lamps after dark: a quad over its sprite adding each lamp's face lit and a soft glow round it,
## slid toward the camera so it draws over the car without moving on screen.
func car_lamps() -> MeshInstance3D:
	if not car_lamp_tex:
		var img := Image.create(VEHICLE_CELL.x * CAR_LAMPS.size(), VEHICLE_CELL.y, false, Image.FORMAT_RGBA8)
		for f in CAR_LAMPS.size():
			for l in CAR_LAMPS[f]:
				var tint: Color = CAR_LAMP_TINT[l[3]]
				var r: float = l[2]
				var k: float = {"h": 1.5, "t": 1.0, "s": 0.8}[l[3]]  # headlights throw a wider glare than the roof sign
				for y in range(maxi(l[1] - r * k * 6, 0), mini(l[1] + r * k * 6 + 1, VEHICLE_CELL.y)):
					for x in range(maxi(l[0] - r * k * 6, 0), mini(l[0] + r * k * 6 + 1, VEHICLE_CELL.x)):
						var d := Vector2(x - l[0], y - l[1]).length() / r
						var g := d / k
						var a := maxf(smoothstep(1.4, 0.8, d), 0.8 * exp(-0.25 * g * g) + 0.15 * smoothstep(6.0, 1.5, g))
						var c := tint.lerp(Color.WHITE, (0.6 if l[3] == "h" else 0.3) * smoothstep(1.0, 0.0, d))  # a hotter core
						var px := f * VEHICLE_CELL.x + x
						if a > img.get_pixel(px, y).a:
							img.set_pixel(px, y, Color(c, a))
		car_lamp_tex = ImageTexture.create_from_image(img)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(VEHICLE_CELL) * VEHICLE_PX
	q.mesh = qm
	var m := pool_mat.duplicate() as StandardMaterial3D
	m.albedo_texture = car_lamp_tex
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	q.material_override = m
	q.position = to_eye() * 0.4
	q.visible = false
	return q


## Keeps a vehicle's lamps on its frame and lit as the night deepens.
func lamps_on(node: Sprite3D) -> void:
	var q: MeshInstance3D = node.get_child(2)
	q.visible = night > 0.02
	if q.visible:
		var m: StandardMaterial3D = q.material_override
		var n := float(CAR_LAMPS.size())
		var f := node.region_rect.position.x / VEHICLE_CELL.x
		m.uv1_scale = Vector3(-1.0 / n if node.flip_h else 1.0 / n, 1, 1)
		m.uv1_offset = Vector3((f + (1.0 if node.flip_h else 0.0)) / n, 0, 0)
		m.albedo_color = Color(1, 1, 1, minf(night * 2.0, 1.0))


## Settled snow for an 8 m repeat at 32 px a metre: drifts on seamless noise, each mounded up from a thin rim to a
## rounded body, lit on the slopes that face the sun and cool blue on those turned away, thinning to a translucent rim
## with the ground showing through, round it a margin of wet, darkened ground flecked with powder, and the odd glint.
## Given a size and `lie` (metres across and down the texture to a bias), it lays one shaped patch instead of a tile:
## snow heaped where the bias is up, trodden or ploughed down to wet ground where it is down.
func snow_patches(w := 256, h := 256, lie := Callable()) -> ImageTexture:
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
	var lies := lie.is_valid()
	var vals := PackedFloat32Array()
	vals.resize(w * h)
	var height := PackedFloat32Array()
	height.resize(w * h)
	for y in h:
		for x in w:
			var v := drifts[y % N * N + x % N] / 255.0
			if lies:
				v += lie.call((x + 0.5) / 32.0, (y + 0.5) / 32.0)
			vals[y * w + x] = v
			height[y * w + x] = sqrt(clampf((v - 0.5) / 0.14, 0.0, 1.0)) + 0.8 * v
	var sun := Vector2(SUN.x, SUN.z).normalized()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var yu := (y + 2) % h if not lies else mini(y + 2, h - 1)
		var yd := (y + h - 2) % h if not lies else maxi(y - 2, 0)
		for x in w:
			var v := vals[y * w + x]
			var g := grain[y % N * N + x % N] / 255.0 - 0.5
			var c := Color(1, 1, 1, 0)
			if v > 0.5:
				var dx := height[y * w + (x + 2) % w] - height[y * w + (x + w - 2) % w]
				var dz := height[yu * w + x] - height[yd * w + x]
				var lit := clampf(-(dx * sun.x + dz * sun.y) * 6.0, -1.0, 1.0)
				c = Color(0.93, 0.95, 0.99).lerp(Color(1.0, 1.0, 0.98), lit) if lit > 0.0 else Color(0.93, 0.95, 0.99).lerp(Color(0.72, 0.79, 0.92), -lit)
				c = c.darkened(0.03 * g)
				var rim := clampf((v - 0.5) / 0.035, 0.0, 1.0)  # thin at the edge: the ground shows through, slushy and grey
				c = Color(0.8, 0.84, 0.92).lerp(c, rim)
				c.a = lerpf(0.62, 0.97, rim)
				if g > 0.44 and lit > 0.2:
					c = Color(1, 1, 1, 1)  # a glint in the crust
			elif v > 0.43:
				var wet := (v - 0.43) / 0.07  # meltwater darkening the ground round the drift
				c = Color(0.16, 0.2, 0.3, 0.36 * wet)
				if g > 0.4 and v > 0.465:
					c = Color(0.9, 0.93, 0.99, 0.85)  # powder blown off the drift
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Snow lying on the set: on each sidewalk a ridge shovelled up along the kerb and a drift against the walls either
## side of a trodden path of wet paving, the car park ploughed into heaps round its edges, and on the road a dusting
## along the kerbs and between the wheel tracks, which stay dark. Hidden until a cold snap.
func settled_snow(far_gaps: Array, near_gaps: Array) -> MeshInstance3D:
	var deep := surface(mat(Color(1, 1, 1, 0.999), snow_tex))
	var thin := surface(mat(Color(1, 1, 1, 0.6), snow_tex))
	var walk := surface(mat(Color(1, 1, 1, 0.999), snow_walk_tex))
	for sd in [[far_gaps, -7.2, 0.0], [near_gaps, 3.7, 1.0]]:  # v runs from the wall (0) to the kerb (1)
		for o in open_spans(sd[0]):
			var z0: float = sd[1]
			add_quad(walk, [Vector3(o.x, -0.034, z0), Vector3(o.y, -0.034, z0), Vector3(o.y, -0.034, z0 + 3.5), Vector3(o.x, -0.034, z0 + 3.5)],
					[Vector2(o.x / 8.0, sd[2]), Vector2(o.y / 8.0, sd[2]), Vector2(o.y / 8.0, 1.0 - sd[2]), Vector2(o.x / 8.0, 1.0 - sd[2])])
	var lot := surface(mat(Color(1, 1, 1, 0.999), snow_lot_tex))
	add_quad(lot, [Vector3(-3.4, -0.034, -16.0), Vector3(3.7, -0.034, -16.0), Vector3(3.7, -0.034, -7.2), Vector3(-3.4, -0.034, -7.2)],
			[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var span := rival_span(branch.rival)
	rect_quad(deep, Rect2(3.7, -20.2, span.x - 3.7, 13.0), -0.034, 0.0, false, 0.125)
	rect_quad(deep, Rect2(-16.5, -20.2, 20.2, 3.95), -0.034, 0.0, false, 0.125)
	rect_quad(deep, Rect2(span.x + 0.2, -16.0, span.y - span.x - 0.4, 8.6), 4.27, 0.0, false, 0.125)  # the rival's roof, round its kit
	for band in [Vector2(-3.7, -3.05), Vector2(-2.25, -1.55), Vector2(-0.45, 0.45), Vector2(1.55, 2.25), Vector2(3.05, 3.7)]:
		rect_quad(thin, Rect2(street_x.x, band.x, street_x.y - street_x.x, band.y - band.x), -0.034, 0.0, false, 0.125)
	var mi := commit([deep, thin, walk, lot], set_node)
	mi.visible = false
	return mi


## A unit step toward the store camera along its line of sight: a glow slid this way clears the body it lights.
func to_eye() -> Vector3:
	var p := deg_to_rad(PITCH)
	return Vector3(sin(PI / 4) * cos(p), sin(p), cos(PI / 4) * cos(p))


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
	var pm := multimesh(PlaneMesh.new(), spots.size())
	for i in spots.size():
		var at: Vector3 = spots[i]
		bm.set_instance_transform(i, Transform3D(Basis(), at))
		bm.set_instance_color(i, Color("d6402e") if i % 3 != 2 else Color("f4ead6"))
		for c in 2:
			cm.set_instance_transform(i * 2 + c, Transform3D(Basis().scaled(Vector3(0.21, 0.06, 0.21)), at + Vector3(0, 0.24 if c == 0 else -0.24, 0)))
			cm.set_instance_color(i * 2 + c, Color("2e2523"))
		gm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(2.0, 2.0, 2.0)), at + to_eye() * 0.3))
		pm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.5, 1.0, 1.25)), Vector3(at.x, -0.032, at.z)))
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
	mm_node(pm, lantern_pool_mat, node)
	yatai(node, paper)
	return node


## A yakisoba yatai in your free bay, its counter to the street: a wooden frame under a red and white canvas pitched over a ridge, a
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
		box_into(st, Vector3(c.x, 0, c.y) + Vector3(-0.05, 0, -0.05), Vector3(c.x, 0, c.y) + Vector3(0.05, 2.34, 0.05), wood)
	box_into(st, Vector3(X0, 0.05, ZB), Vector3(X1, 0.85, ZB + 0.06), wood.darkened(0.15))  # the back board
	# the counter, skirted in red and white stripes on the faces you see
	box_into(st, Vector3(X0 + 0.05, 0.05, ZF - 0.5), Vector3(X1 - 0.05, 0.9, ZF), Color("b8955a"))
	# each stripe a pleat, its far half a fold in shade, under the shadow the counter's lip casts down it
	var n := 8
	var sw := (X1 - X0 - 0.1) / n
	for k in n:
		var x := lerpf(X0 + 0.05, X1 - 0.05, float(k) / n)
		var c := red if k % 2 == 0 else cream
		box_into(st, Vector3(x, 0.08, ZF), Vector3(x + sw * 0.55, 0.76, ZF + 0.03), c)
		box_into(st, Vector3(x + sw * 0.55, 0.08, ZF), Vector3(x + sw, 0.76, ZF + 0.02), c.darkened(0.12))
		box_into(st, Vector3(x, 0.76, ZF), Vector3(x + sw, 0.88, ZF + 0.02), c.darkened(0.38))
	var dz := (ZF - ZB - 0.06) / 6
	for k in 6:
		var z := lerpf(ZB + 0.06, ZF, float(k) / 6)
		var c := cream if k % 2 == 0 else red
		box_into(st, Vector3(X1, 0.08, z), Vector3(X1 + 0.03, 0.76, z + dz * 0.55), c)
		box_into(st, Vector3(X1, 0.08, z + dz * 0.55), Vector3(X1 + 0.02, 0.76, z + dz), c.darkened(0.12))
		box_into(st, Vector3(X1, 0.76, z), Vector3(X1 + 0.02, 0.88, z + dz), c.darkened(0.38))
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
	# the canopy: canvas pitched over a ridge, striped down its slopes and sagging a little between ridge and eave, the
	# front slope lit toward its fold and the back one in shade, red gable ends, and a valance round the eaves whose
	# stripes each end in a scallop; then the noren hung inside its front edge
	const CX0 := X0 - 0.15
	const CX1 := X1 + 0.15
	const CZB := ZB - 0.2
	const CZF := ZF + 0.35
	const EAVE := 2.32
	const RIDGE := 2.64
	const VAL := 0.13
	var cz := (CZB + CZF) / 2
	var quad := func(into: SurfaceTool, v: Array, cols: Array) -> void:
		for i in [0, 1, 2, 0, 2, 3]:
			into.set_color(cols[i])
			into.set_uv(Vector2.ZERO)
			into.add_vertex(v[i])
	var tone := func(c: Color, v: float) -> Color: return Color(c.r * v, c.g * v, c.b * v)
	var scallop := func(into: SurfaceTool, a: Vector3, b: Vector3, y: float, c: Color) -> void:  # a tongue below a..b at y
		var prev := a
		for i in range(1, 7):
			var t := i / 6.0
			var p := a.lerp(b, t) + Vector3(0, -0.055 * sin(t * PI), 0)
			quad.call(into, [a.lerp(b, 0.5) + Vector3(0, y - a.y, 0), prev + Vector3(0, y - a.y, 0), p + Vector3(0, y - a.y, 0), a.lerp(b, 0.5) + Vector3(0, y - a.y, 0)], [c, c, c, c, c, c])
			prev = p
	var m := 6
	var bw := (CX1 - CX0) / m
	for k in m:
		var xa := CX0 + k * bw
		var xb := xa + bw
		var c := red if k % 2 == 0 else cream
		for side in [[CZF, 0.86, 1.0], [CZB, 0.74, 0.8]]:
			var ze: float = side[0]
			for j in 2:  # ridge to eave in two runs, dipping at the middle
				var t0 := j * 0.5
				var t1 := t0 + 0.5
				var y0 := lerpf(RIDGE, EAVE, t0) - 0.03 * sin(t0 * PI)
				var y1 := lerpf(RIDGE, EAVE, t1) - 0.03 * sin(t1 * PI)
				var z0 := lerpf(cz, ze, t0)
				var z1 := lerpf(cz, ze, t1)
				var c0: Color = tone.call(c, lerpf(side[1], side[2], t0))
				var c1: Color = tone.call(c, lerpf(side[1], side[2], t1))
				quad.call(st, [Vector3(xa, y0, z0), Vector3(xb, y0, z0), Vector3(xb, y1, z1), Vector3(xa, y1, z1)], [c0, c0, c1, c0, c1, c1])
			var vc: Color = tone.call(c, 0.84 if ze == CZF else 0.7)
			var vs: SurfaceTool = lt if ze == CZF else st  # the lanterns light the front one
			quad.call(vs, [Vector3(xa, EAVE, ze), Vector3(xb, EAVE, ze), Vector3(xb, EAVE - VAL, ze), Vector3(xa, EAVE - VAL, ze)], [vc, vc, vc, vc, vc, vc])
			scallop.call(vs, Vector3(xa, EAVE, ze), Vector3(xb, EAVE, ze), EAVE - VAL, vc)
	var dzc := (CZF - CZB) / m
	for gx in [[CX0, 0.86], [CX1, 0.72]]:  # gable ends, and the side valances striped along them
		var gc: Color = tone.call(red.darkened(0.08), gx[1])
		var x: float = gx[0]
		quad.call(st, [Vector3(x, EAVE, CZB), Vector3(x, RIDGE, cz), Vector3(x, RIDGE, cz), Vector3(x, EAVE, CZF)], [gc, gc, gc, gc, gc, gc])
		for k in m:
			var c: Color = tone.call(cream if k % 2 == 0 else red, gx[1] - 0.04)
			var a := Vector3(x, EAVE, CZB + k * dzc)
			var b := a + Vector3(0, 0, dzc)
			quad.call(st, [a, b, b - Vector3(0, VAL, 0), a - Vector3(0, VAL, 0)], [c, c, c, c, c, c])
			scallop.call(st, a, b, EAVE - VAL, c)
	box_into(st, Vector3(CX0 - 0.02, RIDGE - 0.01, cz - 0.03), Vector3(CX1 + 0.02, RIDGE + 0.03, cz + 0.03), Color("e8dcc4"))  # the ridge seam
	box_into(st, Vector3(X0 - 0.04, EAVE - 0.06, ZF - 0.04), Vector3(X1 + 0.04, EAVE - 0.02, ZF + 0.04), wood.darkened(0.2))  # the beam the canopy sits on
	for k in 3:
		var x := lerpf(X0 + 0.02, X1 - 0.02, float(k) / 3)
		box_into(lt, Vector3(x + 0.02, 1.72, ZF + 0.22), Vector3(x + (X1 - X0 - 0.04) / 3 - 0.02, 2.18, ZF + 0.25), cream)
		box_into(lt, Vector3(x + 0.02, 2.06, ZF + 0.25), Vector3(x + (X1 - X0 - 0.04) / 3 - 0.02, 2.12, ZF + 0.26), red)
		box_into(lt, Vector3(x + 0.2, 1.84, ZF + 0.25), Vector3(x + (X1 - X0 - 0.04) / 3 - 0.2, 1.98, ZF + 0.26), Color("8f2a22"))
	box_into(st, Vector3((X0 + X1) / 2 - 0.01, 1.98, ZF - 0.6), Vector3((X0 + X1) / 2 + 0.01, 2.5, ZF - 0.58), Color("3b2f2b"))
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
		gm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.4, 1.4, 1.4)), hung[i] + to_eye() * 0.28))
	gm.set_instance_transform(hung.size(), Transform3D(Basis().scaled(Vector3(1.6, 1.6, 1.6)), bulb))
	mm_node(gm, lantern_glow_mat, node)
	plane(node, Vector2(4.4, 4.4), Vector3((X0 + X1) / 2, -0.031, ZF + 0.4), stall_glow_mat)
	plane(node, Vector2(2.4, 2.4), Vector3((X0 + X1) / 2, -0.03, ZF - 0.4), stall_glow_mat)
	cast(node, Vector2((X0 + X1) / 2, (ZB + ZF) / 2), 0.0, 2.64, 2.1)
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
	# the dug lane: steel road plates each a shade off, lit along their near edge with a lifting hole at the corner; a
	# trench left open, sawn clean through the tarmac, its far wall of earth lit over a dark floor where the main they
	# dug for runs, its spoil heaped on the last plate; and a patch of fresh black tarmac sealed round its edge
	for k in 4:
		var px := x0 + 0.9 + k * 0.925
		var pc := plate.darkened(0.06 * (k % 3)).lightened(0.04 * int(k == 1))
		box_into(st, Vector3(px, -0.045, 2.75), Vector3(px + 0.905, -0.02, 3.5), pc)
		box_into(st, Vector3(px, -0.045, 3.47), Vector3(px + 0.905, -0.017, 3.5), pc.lightened(0.22))
		box_into(st, Vector3(px + 0.905, -0.045, 2.75), Vector3(px + 0.925, -0.016, 3.5), plate.darkened(0.45))
		box_into(st, Vector3(px + 0.08, -0.045, 3.33), Vector3(px + 0.14, -0.015, 3.39), plate.darkened(0.5))
	# the spoil: a lumpy mound of earth faceted over a grid, each facet shaded by the way it faces, damp and dark at its
	# foot and drying paler toward a peak pushed off centre, clods and broken tarmac rolled out round it and a shovel
	# driven into its crown
	var heap := Vector3(x0 + 4.05, -0.02, 3.1)
	var hr := RandomNumberGenerator.new()
	hr.seed = 5281
	var peak := Vector2(-0.06, -0.03)
	var lumps: Array = []
	for i in 5:
		lumps.append(Vector3(hr.randf_range(-0.6, 0.6), hr.randf_range(-0.6, 0.6), hr.randf_range(-0.05, 0.06)))
	var mound := func(u: float, v: float) -> Vector3:  # u, v across the heap's footprint in -1..1
		var r2 := u * u + v * v
		var y := 0.0
		if r2 < 1.0:
			var q := Vector2(u, v) - peak
			y = 0.36 * pow(1.0 - r2, 0.9) * (1.0 - 0.25 * q.length())
			for l in lumps:
				y += l.z * exp(-(Vector2(u, v) - Vector2(l.x, l.y)).length_squared() * 9.0) * (1.0 - r2)
		return heap + Vector3(u * 0.44, maxf(y, 0.0), v * 0.34)
	const N := 8
	for j in N:
		for i in N:
			var u0 := -1.0 + 2.0 * i / N
			var u1 := -1.0 + 2.0 * (i + 1) / N
			var v0 := -1.0 + 2.0 * j / N
			var v1 := -1.0 + 2.0 * (j + 1) / N
			var q: Array = [mound.call(u0, v1), mound.call(u1, v1), mound.call(u1, v0), mound.call(u0, v0)]
			var hy: float = ((q[0] + q[1] + q[2] + q[3]) / 4.0).y - heap.y
			if hy < 0.003:
				continue
			var n: Vector3 = (q[2] - q[0]).cross(q[1] - q[3]).normalized()
			if n.y < 0.0:
				n = -n
			var side := 0.9 if n.z - n.x > 0.0 else 0.75
			var t := lerpf(side, 1.0, n.y)
			var col := Color("5a402c").lerp(Color("9c7a52"), clampf(hy / 0.3, 0.0, 1.0)).lightened(hr.randf_range(0.0, 0.05))
			st.set_color(Color(col.r * t, col.g * t, col.b * t))
			add_quad(st, q, [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	for i in 9:
		var a := TAU * i / 9.0 + hr.randf_range(-0.3, 0.3)
		var p := heap + Vector3(cos(a) * hr.randf_range(0.36, 0.5), 0, sin(a) * hr.randf_range(0.28, 0.4))
		var s := hr.randf_range(0.025, 0.05)
		var tarmac := i % 3 == 0
		box_into(st, p - Vector3(s, 0, s * 0.8), p + Vector3(s, s * (0.7 if tarmac else 1.0), s * 0.8), Color("34363a") if tarmac else Color("6b4d34").lightened(hr.randf_range(0.0, 0.12)))
	var top: Vector3 = mound.call(peak.x + 0.1, peak.y) - Vector3(0, 0.03, 0)
	turned_box_into(st, Transform3D(Basis(Vector3.BACK, -0.3) * Basis.from_scale(Vector3(0.025, 0.95, 0.025)), top + Vector3(0.14, 0.42, 0)), Color("b08a5a"))  # the handle
	turned_box_into(st, Transform3D(Basis(Vector3.BACK, -0.3) * Basis.from_scale(Vector3(0.11, 0.035, 0.035)), top + Vector3(0.28, 0.87, 0)), Color("2b2a2c"))  # its grip
	turned_box_into(st, Transform3D(Basis(Vector3.BACK, -0.3) * Basis.from_scale(Vector3(0.02, 0.16, 0.2)), top + Vector3(0.0, -0.02, 0)), Color("8c9298"))  # the blade, half buried
	# the trench, sawn clean through the road: its far wall shows the cut through the surface course, the grey crushed
	# stone under it and the earth darkening down toward a floor puddled over the main they dug for, its end wall in
	# shade and a shadow cast in from the near lip
	box_into(st, Vector3(x0 + 4.6, -0.045, 2.75), Vector3(x0 + 5.7, -0.03, 3.5), Color("8d9095"))  # the sawn edge
	box_into(st, Vector3(x0 + 4.64, -0.045, 2.79), Vector3(x0 + 5.66, -0.027, 3.46), Color("2a1d15"))
	for w in [[2.79, 2.815, "5e6065"], [2.815, 2.85, "323337"], [2.85, 2.9, "8e8a82"], [2.9, 2.96, "7a5a3b"], [2.96, 3.02, "614631"], [3.02, 3.06, "4a3424"]]:
		box_into(st, Vector3(x0 + 4.64, -0.045, w[0]), Vector3(x0 + 5.66, -0.025, w[1]), Color(w[2]))
	for i in 14:  # the crushed stone's chips
		var sx := x0 + 4.68 + i * 0.07 + hr.randf_range(0.0, 0.03)
		box_into(st, Vector3(sx, -0.045, 2.86 + hr.randf_range(0.0, 0.025)), Vector3(sx + 0.02, -0.0245, 2.875 + hr.randf_range(0.0, 0.02)), Color("b4aea3") if i % 2 == 0 else Color("6a6660"))
	box_into(st, Vector3(x0 + 4.64, -0.045, 2.85), Vector3(x0 + 4.72, -0.025, 3.46), Color("4e3828"))  # the end wall
	box_into(st, Vector3(x0 + 4.64, -0.045, 2.79), Vector3(x0 + 4.72, -0.0245, 2.85), Color("4a4b50"))
	box_into(st, Vector3(x0 + 4.64, -0.045, 3.1), Vector3(x0 + 5.66, -0.022, 3.22), Color("5d7686"))  # the main
	box_into(st, Vector3(x0 + 4.64, -0.045, 3.1), Vector3(x0 + 5.66, -0.021, 3.13), Color("8fa6b3"))
	for jx in [x0 + 4.95, x0 + 5.4]:
		box_into(st, Vector3(jx - 0.05, -0.045, 3.08), Vector3(jx + 0.05, -0.019, 3.24), Color("4d6170"))
	box_into(st, Vector3(x0 + 5.0, -0.045, 3.26), Vector3(x0 + 5.5, -0.0265, 3.36), Color("3b4248"))  # a puddle
	box_into(st, Vector3(x0 + 5.08, -0.045, 3.28), Vector3(x0 + 5.3, -0.026, 3.3), Color("6d7f8c"))
	box_into(st, Vector3(x0 + 4.64, -0.045, 3.38), Vector3(x0 + 5.66, -0.0262, 3.46), Color("1d140e"))  # under the near lip
	# the patch already laid: fresh tarmac black and still glossy, rolled in passes along the lane, its joint with the
	# old road sealed in a band of shiny tar
	box_into(st, Vector3(x0 + 5.7, -0.045, 2.7), Vector3(x1 - 0.8, -0.03, 3.52), Color("17181b"))
	box_into(st, Vector3(x0 + 5.74, -0.045, 2.74), Vector3(x1 - 0.84, -0.028, 3.48), Color("2f3135"))
	for k in 4:
		var z := 2.76 + k * 0.18
		box_into(st, Vector3(x0 + 5.76, -0.045, z), Vector3(x1 - 0.86, -0.0275, z + 0.07), Color("383a3f") if k % 2 == 0 else Color("292b2f"))
	box_into(st, Vector3(x0 + 5.74, -0.045, 2.74), Vector3(x1 - 0.84, -0.0272, 2.765), Color("4a4d54"))
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
	# the arrow board on its trailer: a yellow chassis on two wheels, a drawbar to a jockey wheel and a jack at the
	# back; a mast up to the board's housing under a hood, a hazard band below the face and a solar panel on top
	var ab := x1 + 0.9
	var yel := Color("e8c440")
	box_into(st, Vector3(ab - 0.45, 0.22, 2.9), Vector3(ab + 0.35, 0.4, 3.34), yel)
	box_into(st, Vector3(ab - 0.45, 0.4, 2.9), Vector3(ab + 0.35, 0.42, 3.34), yel.lightened(0.2))
	box_into(st, Vector3(ab - 0.4, 0.12, 2.94), Vector3(ab + 0.3, 0.22, 3.3), Color("3a3a3e"))
	for wz: float in [2.83, 3.41]:  # a tyre either side, rounded off in steps, its hub on the outer face
		var o := 1.0 if wz > 3.12 else -1.0
		var za := minf(wz - o * 0.06, wz + o * 0.06)
		var zb := maxf(wz - o * 0.06, wz + o * 0.06)
		box_into(st, Vector3(ab - 0.2, 0.05, za), Vector3(ab + 0.2, 0.35, zb), Color("232326"))
		box_into(st, Vector3(ab - 0.15, 0.0, za), Vector3(ab + 0.15, 0.4, zb), Color("232326"))
		var hz := wz + o * 0.062
		box_into(st, Vector3(ab - 0.08, 0.12, hz - 0.006), Vector3(ab + 0.08, 0.28, hz + 0.006), Color("b9bcc0"))
		box_into(st, Vector3(ab - 0.03, 0.17, hz - 0.01 + o * 0.006), Vector3(ab + 0.03, 0.23, hz + 0.01 + o * 0.006), Color("55585e"))
		box_into(st, Vector3(ab - 0.24, 0.4, za), Vector3(ab + 0.24, 0.44, zb), yel.darkened(0.1))  # the mudguard
	for k: float in [-1.0, 1.0]:  # the drawbar's two arms meeting at the hitch
		turned_box_into(st, Transform3D(Basis(Vector3.UP, 0.32 * k) * Basis.from_scale(Vector3(0.62, 0.06, 0.06)), Vector3(ab + 0.62, 0.3, 3.12 + 0.1 * k)), yel.darkened(0.08))
	box_into(st, Vector3(ab + 0.88, 0.26, 3.07), Vector3(ab + 1.0, 0.34, 3.17), Color("5a5d63"))
	box_into(st, Vector3(ab + 0.82, 0.08, 3.09), Vector3(ab + 0.86, 0.3, 3.15), Color("9aa0a6"))
	box_into(st, Vector3(ab + 0.79, 0.0, 3.07), Vector3(ab + 0.89, 0.1, 3.17), Color("232326"))
	for jz: float in [2.95, 3.29]:  # the back jacks wound down onto pads
		box_into(st, Vector3(ab - 0.43, 0.02, jz - 0.025), Vector3(ab - 0.38, 0.22, jz + 0.025), Color("9aa0a6"))
		box_into(st, Vector3(ab - 0.47, -0.04, jz - 0.06), Vector3(ab - 0.34, 0.02, jz + 0.06), Color("5a5d63"))
	box_into(st, Vector3(ab - 0.2, 0.42, 3.07), Vector3(ab - 0.12, 1.12, 3.17), Color("9aa0a6"))  # the mast
	box_into(st, Vector3(ab - 0.23, 0.42, 3.04), Vector3(ab - 0.09, 0.5, 3.2), Color("5a5d63"))
	box_into(st, Vector3(ab - 0.14, 1.06, 2.6), Vector3(ab + 0.02, 2.14, 3.64), Color("b8bcc0"))  # the housing
	box_into(st, Vector3(ab + 0.02, 1.08, 2.62), Vector3(ab + 0.06, 2.12, 3.62), Color("2b2a2c"))
	box_into(st, Vector3(ab - 0.14, 2.14, 2.58), Vector3(ab + 0.16, 2.18, 3.66), Color("8a8f95"))  # its hood
	box_into(st, Vector3(ab + 0.12, 2.04, 2.58), Vector3(ab + 0.16, 2.14, 3.66), Color("6c7177"))
	bar.call(Vector3(ab + 0.08, 1.13, 2.65), Vector3(ab + 0.08, 1.13, 3.59), 0.08, 0.12)
	box_into(st, Vector3(ab - 0.08, 2.18, 3.08), Vector3(ab - 0.04, 2.34, 3.16), Color("9aa0a6"))
	turned_box_into(st, Transform3D(Basis(Vector3.BACK, 0.5) * Basis.from_scale(Vector3(0.62, 0.035, 0.84)), Vector3(ab - 0.06, 2.4, 3.12)), Color("2e4f86"))
	turned_box_into(st, Transform3D(Basis(Vector3.BACK, 0.5) * Basis.from_scale(Vector3(0.66, 0.025, 0.88)), Vector3(ab - 0.065, 2.39, 3.12)), Color("c9cdd1"))
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
	# the board's face: a matrix of amber LEDs on black drawing an arrow that turns traffic away from the kerb, the dark
	# LEDs left as dim dots, lit like a sign
	var img := Image.create(96, 96, false, Image.FORMAT_RGB8)
	img.fill(Color("141316"))
	for j in 12:
		for i in 12:
			var on := (j >= 5 and j <= 6 and i >= 1 and i <= 6) or (i >= 6 and i <= 10 and absi(2 * j - 11) <= 2 * (10 - i) + 1)
			for y in 8:
				for x in 8:
					var d := Vector2(x - 3.5, y - 3.5).length()
					if d < 3.7:
						img.set_pixel(i * 8 + x, j * 8 + y, Color("ffb52e").lerp(Color("fff0c0"), 0.6 * clampf(1.6 - d, 0.0, 1.0)) if on else Color("2c2622"))
	img.generate_mipmaps()
	var face := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(0.94, 0.9)
	face.mesh = fq
	var fm := mat(Color.WHITE, ImageTexture.create_from_image(img))
	light_up(fm, 1.0)
	face.material_override = fm
	face.rotation.y = PI / 2
	face.position = Vector3(ab + 0.065, 1.64, 3.12)
	node.add_child(face)
	var gm := multimesh(QuadMesh.new(), lamps.size() + 1)
	for i in lamps.size():
		gm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1.2, 1.2, 1.2)), lamps[i]))
	gm.set_instance_transform(lamps.size(), Transform3D(Basis().scaled(Vector3(2.2, 2.2, 2.2)), Vector3(ab + 0.2, 1.64, 3.12)))
	mm_node(gm, works_glow_mat, node)
	cast(node, Vector2(ab, 3.12), 0.0, 0.44, 0.6)
	cast(node, Vector2(ab - 0.1, 3.12), 1.06, 2.18, 1.0)
	for b in [x0 + 0.35, x1 - 0.35]:
		cast(node, Vector2(b, 3.05), 0.3, 0.9, 0.9)
	for c in cones:
		cast(node, Vector2(c.x, c.z), 0.0, 0.7, 0.22)
	cast(node, Vector2(heap.x, heap.z), 0.0, 0.3, 0.6)
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
	van_wheels(st, -1.85, -0.15, [-14.4, -12.0], 0.275, 0.3)
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
	van_nose(st, -1.85, -0.15, -11.05, 0.8, 0.26, Rect2(-1.75, 1.18, 1.5, 0.7), -11.57)
	for z in [-12.5, -14.3]:  # the cab door's and the slide door's shut lines, each with its handle
		box_into(st, Vector3(-0.15, 0.32, z - 0.015), Vector3(-0.14, 1.98, z + 0.015), body.darkened(0.35))
		box_into(st, Vector3(-0.15, 1.12, z - 0.22), Vector3(-0.13, 1.16, z - 0.08), Color("9aa0a6"))
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
	dish_into(st, Vector3(-0.75, 2.42, -14.1), Vector3(0.4, 0.75, 0.5).normalized())
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


## A satellite dish on a post rising from `foot`, its bowl aimed along d: the inside shaded by how each ring faces the
## sky, so its far wall catches the light and its near wall falls into shade under a bright rim lip, a darker shell
## behind, and a feed arm from the bottom of the rim holding the LNB at the focus.
func dish_into(st: SurfaceTool, foot: Vector3, d: Vector3, r := 0.5, depth := 0.18, segs := 16, rings := 4) -> void:
	var u := d.cross(Vector3.UP).normalized()
	var v := u.cross(d)
	var c := foot + Vector3(0, 0.2, 0) + d * 0.08
	var sky := Vector3(-0.8, 0.9, 0.3).normalized()
	var face := Color("e2e1da")
	var shell := Color("b4b5b2")
	var at := func(k: float, a: float, back: float) -> Vector3:
		return c + (u * cos(a) + v * sin(a)) * r * k + d * (depth * k * k - back)
	var tone := func(k: float, a: float, col: Color, inside: bool) -> Color:
		var n := (d - (u * cos(a) + v * sin(a)) * 2.0 * depth * k / r).normalized()
		if not inside:
			n = -n
		var t := 0.64 + 0.4 * maxf(n.dot(sky), 0.0) - (0.05 * (1.0 - k) if inside else 0.0)
		return Color(col.r * t, col.g * t, col.b * t)
	for i in rings:
		var k0 := float(i) / rings
		var k1 := float(i + 1) / rings
		for j in segs:
			var a0 := TAU * j / segs
			var a1 := TAU * (j + 1) / segs
			for side in [[face, true, 0.0], [shell, false, 0.025]]:
				var q := [[k0, a0], [k1, a0], [k1, a1], [k0, a1]]
				for e in [q[0], q[1], q[2], q[0], q[2], q[3]]:
					st.set_color(tone.call(e[0], e[1], side[0], side[1]))
					st.set_uv(Vector2.ZERO)
					st.add_vertex(at.call(e[0], e[1], side[2]))
	for j in segs:  # the rim's rolled lip, lit all round
		var a0 := TAU * j / segs
		var a1 := TAU * (j + 1) / segs
		var lip := Color("f4f3ee") if sin((a0 + a1) / 2) > -0.3 else Color("d0cfc8")
		st.set_color(lip)
		for e in [[1.0, a0, 0.0], [1.07, a0, 0.0], [1.07, a1, 0.0], [1.0, a0, 0.0], [1.07, a1, 0.0], [1.0, a1, 0.0]]:
			st.set_uv(Vector2.ZERO)
			st.add_vertex(at.call(e[0], e[1], e[2]) - d * 0.012 * (e[0] - 1.0) / 0.07)
	pipe_into(st, foot, c - d * 0.05, 0.035, Color("7d8187"), 8)
	box_into(st, c - d * 0.09 - Vector3(0.07, 0.07, 0.07), c - d * 0.02 + Vector3(0.07, 0.07, 0.07), Color("8e9196"))
	var focus := c + d * r * 0.62
	pipe_into(st, at.call(1.0, -PI / 2, 0.0), focus - d * 0.04, 0.014, Color("9aa0a6"), 6)
	pipe_into(st, focus - d * 0.06, focus + d * 0.06, 0.035, Color("4a4b50"), 8)
	pipe_into(st, focus + d * 0.06, focus + d * 0.08, 0.045, Color("2b2c30"), 8)


## A van's running gear (body from x0 to x1, its floor at y): the chassis dark between the axles, and at each end of
## each axle a tyre rounded off in steps, a silver hub with its nut on the outer face, sat in a dark wheel arch.
func van_wheels(st: SurfaceTool, x0: float, x1: float, axles: Array, r: float, y: float) -> void:
	var tyre := Color("232326")
	box_into(st, Vector3(x0 + 0.2, 0.14, axles.min() - 0.4), Vector3(x1 - 0.2, y, axles.max() + 0.4), Color("1d1d20"))
	for z: float in axles:
		box_into(st, Vector3(x0 - 0.008, y - 0.01, z - r - 0.1), Vector3(x1 + 0.008, 2 * r + 0.1, z + r + 0.1), Color("29292c"))
		for side in [-1.0, 1.0]:
			var out: float = (x1 if side > 0 else x0) + side * 0.02
			var a := minf(out, out - side * 0.26)
			var b := maxf(out, out - side * 0.26)
			box_into(st, Vector3(a, 0.05, z - r), Vector3(b, 2 * r - 0.05, z + r), tyre)
			box_into(st, Vector3(a, 0.0, z - r + 0.09), Vector3(b, 2 * r, z + r - 0.09), tyre)
			var hub := Vector3(out + side * 0.006, r, z)
			box_into(st, hub - Vector3(0.006, r * 0.42, r * 0.6), hub + Vector3(0.006, r * 0.42, r * 0.6), Color("b9bcc0"))
			box_into(st, hub - Vector3(0.006, r * 0.6, r * 0.42), hub + Vector3(0.006, r * 0.6, r * 0.42), Color("b9bcc0"))
			box_into(st, hub + Vector3(side * 0.006, 0, 0) - Vector3(0.006, r * 0.16, r * 0.16), hub + Vector3(side * 0.006, 0, 0) + Vector3(0.006, r * 0.16, r * 0.16), Color("55585e"))


## A van's face (body x0 to x1, its nose at zf): a grille between the lamps at lamp_y with an indicator outside each,
## the number plate on the bumper at bumper_y, and over the windscreen g (x, y, width, height, its glass at zg) the
## sky caught along its top, two wipers parked at its foot and a mirror out on each door.
func van_nose(st: SurfaceTool, x0: float, x1: float, zf: float, lamp_y: float, bumper_y: float, g: Rect2, zg: float) -> void:
	box_into(st, Vector3(x0 + 0.5, lamp_y - 0.02, zf - 0.02), Vector3(x1 - 0.5, lamp_y + 0.13, zf + 0.025), Color("3a3c41"))
	for k in 3:
		box_into(st, Vector3(x0 + 0.52, lamp_y + 0.01 + k * 0.04, zf + 0.025), Vector3(x1 - 0.52, lamp_y + 0.025 + k * 0.04, zf + 0.03), Color("6c7077"))
	for x in [x0 + 0.08, x1 - 0.24]:
		box_into(st, Vector3(x, lamp_y - 0.09, zf - 0.02), Vector3(x + 0.16, lamp_y - 0.03, zf + 0.035), Color("f0a03a"))
	var mid := (x0 + x1) / 2
	box_into(st, Vector3(mid - 0.2, bumper_y + 0.03, zf + 0.09), Vector3(mid + 0.2, bumper_y + 0.15, zf + 0.105), Color("f4f2e8"))
	box_into(st, Vector3(mid - 0.14, bumper_y + 0.06, zf + 0.105), Vector3(mid + 0.14, bumper_y + 0.08, zf + 0.11), Color("2e6b48"))
	box_into(st, Vector3(mid - 0.17, bumper_y + 0.1, zf + 0.105), Vector3(mid - 0.02, bumper_y + 0.12, zf + 0.11), Color("2e6b48"))
	box_into(st, Vector3(g.position.x, g.end.y - g.size.y * 0.28, zg - 0.01), Vector3(g.end.x, g.end.y, zg + 0.005), Color("6f8aa0"))
	box_into(st, Vector3(g.position.x + g.size.x * 0.12, g.end.y - g.size.y * 0.42, zg - 0.01), Vector3(g.position.x + g.size.x * 0.3, g.end.y - g.size.y * 0.28, zg + 0.005), Color("536b80"))
	for x in [g.position.x + 0.08, mid + 0.04]:
		box_into(st, Vector3(x, g.position.y + 0.02, zg), Vector3(x + g.size.x * 0.4, g.position.y + 0.045, zg + 0.03), Color("1d1d20"))
	for side in [-1.0, 1.0]:
		var x: float = x1 if side > 0 else x0
		box_into(st, Vector3(minf(x, x + side * 0.16), g.position.y + 0.02, zg - 0.32), Vector3(maxf(x, x + side * 0.16), g.position.y + 0.06, zg - 0.26), Color("2b2c30"))
		box_into(st, Vector3(minf(x + side * 0.1, x + side * 0.18), g.position.y + 0.02, zg - 0.3), Vector3(maxf(x + side * 0.1, x + side * 0.18), g.position.y + 0.24, zg - 0.22), Color("2b2c30"))


## A car body lofted along z about x = cx into a vertex-coloured surface. Each section is [z, PackedVector2Array of
## (half-width, height) up its side from the sill to the roof edge]; between sections i and i + 1 the strips up its
## sides take cols[i] (one colour a strip) and its top tops[i], so a bonnet, a raked windscreen and a roof narrowing
## over the doors fall out of how the sections step. caps[0] and caps[1] colour the nose's and the tail's strips.
## Every face takes the house's tones by where it faces, as turned_box_into shades them.
func hull_into(st: SurfaceTool, cx: float, secs: Array, cols: Array, tops: Array, caps: Array) -> void:
	var at := func(sec: Array, k: int, side: float) -> Vector3:
		var pt: Vector2 = sec[1][k]
		return Vector3(cx + pt.x * side, pt.y, sec[0])
	var face := func(q: Array, col: Color, out: Vector3) -> void:
		var n: Vector3 = (q[1] - q[0]).cross(q[2] - q[0])
		if n.length() < 1e-6:
			n = (q[2] - q[0]).cross(q[3] - q[0])
		if n.length() < 1e-6:
			return
		n = n.normalized()
		if n.dot(out) < 0.0:
			n = -n
		var side := 0.9 if n.z - n.x > 0.0 else 0.75
		var t := lerpf(side, 1.0, n.y) if n.y > 0.0 else lerpf(side, 0.7, -n.y)
		st.set_color(Color(col.r * t, col.g * t, col.b * t))
		add_quad(st, q, [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var m: int = secs[0][1].size()
	for i in secs.size() - 1:
		var a: Array = secs[i]
		var b: Array = secs[i + 1]
		for side in [-1.0, 1.0]:
			for k in m - 1:
				var q := [at.call(a, k, side), at.call(b, k, side), at.call(b, k + 1, side), at.call(a, k + 1, side)]
				face.call(q, cols[i][k], Vector3(side, 0.2, 0))
		face.call([at.call(a, m - 1, -1.0), at.call(b, m - 1, -1.0), at.call(b, m - 1, 1.0), at.call(a, m - 1, 1.0)], tops[i], Vector3.UP)
	for e in [[secs[0], caps[0]], [secs[-1], caps[1]]]:
		var sec: Array = e[0]
		var out := Vector3(0, 0, signf(sec[0] - secs[secs.size() / 2][0]))
		for k in m - 1:
			face.call([at.call(sec, k, -1.0), at.call(sec, k, 1.0), at.call(sec, k + 1, 1.0), at.call(sec, k + 1, -1.0)], e[1][k], out)


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
	var glass := Color("394c62")
	var sky := Color("7593ab")
	var trim := Color("9aa0a6")
	var cowl := Color("3a3c41")
	# a compact wagon, nose to the street: a rounded nose under a short bonnet, the windscreen raked back to a roof
	# narrowing over the side glass, a tailgate leaning in, the band along its sides at the bumpers' height
	van_wheels(st, -1.7, -0.3, [-14.4, -12.1], 0.25, 0.26)
	var sec := func(z: float, belt: float, glass_top: float, roof: float, inset := 0.0) -> Array:
		var w := 0.7 - inset
		return [z, PackedVector2Array([Vector2(w - 0.02, 0.24), Vector2(w, 0.58), Vector2(w, 0.72), Vector2(w - 0.03, belt),
				Vector2(lerpf(w - 0.04, 0.59, (glass_top - belt) / 0.4), glass_top), Vector2(lerpf(w - 0.04, 0.58, (roof - belt) / 0.5), roof),
				Vector2(lerpf(w - 0.04, 0.55, (roof - belt) / 0.5), roof + (0.06 if roof > belt else 0.0))])]
	var secs := [sec.call(-11.33, 0.8, 0.8, 0.8, 0.06), sec.call(-11.5, 0.89, 0.89, 0.89), sec.call(-12.18, 0.95, 0.95, 0.95),
			sec.call(-12.26, 0.95, 0.97, 0.97), sec.call(-12.82, 0.95, 1.34, 1.42), sec.call(-12.95, 0.95, 1.36, 1.44),
			sec.call(-13.05, 0.95, 1.36, 1.44), sec.call(-13.58, 0.95, 1.36, 1.44), sec.call(-13.68, 0.95, 1.36, 1.44),
			sec.call(-14.45, 0.95, 1.36, 1.44), sec.call(-14.78, 0.95, 1.36, 1.44), sec.call(-14.93, 0.93, 1.3, 1.38, 0.02)]
	var lower := [body, green, body]
	var pane := lower + [glass, sky, body]
	var pillar := lower + [body, body, body]
	var cols := [[trim, body, body, body, body, body], pillar, pillar, pillar, pillar, pillar, pane, pillar, pane, pillar, pillar]
	var tops := [body, body, cowl, glass, sky, body, body, body, body, body, glass]
	hull_into(st, -1.0, secs, cols, tops, [[trim, body, body, body, body, body], [trim, green, body, glass, glass, body]])
	box_into(st, Vector3(-1.69, 0.2, -11.4), Vector3(-0.31, 0.38, -11.28), trim)  # the bumpers, wrapped round the corners
	box_into(st, Vector3(-1.69, 0.22, -15.0), Vector3(-0.31, 0.4, -14.88), trim)
	# its face: lamps swept round the corners, a grille between them, indicators below, the plate on the bumper
	for side in [-1.0, 1.0]:
		var x: float = -1.0 + side * 0.5
		box_into(st, Vector3(x - 0.15, 0.63, -11.43), Vector3(x + 0.15, 0.77, -11.34), cowl)
		box_into(st, Vector3(x - 0.13, 0.65, -11.42), Vector3(x + 0.13, 0.75, -11.32), Color("fff3c4"))
		box_into(st, Vector3(x - side * 0.13, 0.67, -11.42), Vector3(x - side * 0.04, 0.73, -11.315), Color("e8edf0"))
		box_into(st, Vector3(x - 0.1, 0.5, -11.38), Vector3(x + 0.1, 0.56, -11.32), Color("f0a03a"))
		box_into(st, Vector3(-1.0 + side * 0.665 - 0.005, 0.62, -11.85), Vector3(-1.0 + side * 0.665 + 0.005, 0.66, -11.6), Color("f0a03a"))
		box_into(st, Vector3(x - 0.12, 0.66, -14.96), Vector3(x + 0.12, 0.9, -14.9), Color("c8322b"))  # tail lamps
		# a mirror out on each door at the windscreen's foot
		box_into(st, Vector3(-1.0 + side * 0.66 - 0.04, 0.95, -12.42), Vector3(-1.0 + side * 0.66 + 0.04, 0.99, -12.36), cowl)
		box_into(st, Vector3(minf(-1.0 + side * 0.7, -1.0 + side * 0.8), 0.94, -12.43), Vector3(maxf(-1.0 + side * 0.7, -1.0 + side * 0.8), 1.08, -12.37), cowl)
	box_into(st, Vector3(-1.32, 0.56, -11.36), Vector3(-0.68, 0.62, -11.31), cowl)
	box_into(st, Vector3(-1.2, 0.27, -11.29), Vector3(-0.8, 0.37, -11.27), Color("f4f2e8"))
	box_into(st, Vector3(-1.14, 0.3, -11.27), Vector3(-0.86, 0.32, -11.26), Color("2e6b48"))
	for x in [-1.48, -0.98]:  # wipers parked along the windscreen's foot
		box_into(st, Vector3(x, 0.97, -12.31), Vector3(x + 0.44, 0.99, -12.27), Color("1d1d20"))
	for z in [-13.6, -12.27]:  # the doors' shut lines below the glass, each with its handle
		box_into(st, Vector3(-0.3, 0.3, z - 0.015), Vector3(-0.29, 0.94, z - 0.0), body.darkened(0.35))
		box_into(st, Vector3(-0.31, 0.82, z - 0.24), Vector3(-0.28, 0.86, z - 0.1), trim)
	box_into(st, Vector3(-0.3, 0.76, -13.3), Vector3(-0.27, 0.9, -12.95), Color("fbfaf5"))  # the centre's badge
	box_into(st, Vector3(-0.27, 0.8, -13.18), Vector3(-0.26, 0.86, -13.07), green)
	for x in [-1.42, -0.58]:  # roof rails
		box_into(st, Vector3(x - 0.03, 1.5, -14.6), Vector3(x + 0.03, 1.55, -13.1), Color("8e9196"))
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


## The block's garbage station: a green cage on a kerbed slab, its fine net walls and netted lid showing the night's
## bags heaped inside, the ward's collection-day board on a post at the sidewalk end and a crate of empties beside it.
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
	# the bags heaped inside, each a lumpy sack bellied over its shaded foot with its neck tied off in two ears; one
	# half-full bag slumped on the heap, the yellow one printed with the ward's mark
	for bag in [[Vector3(-0.12, 0, -0.45), 0.5, Color("e9edf0")], [Vector3(0.13, 0, -0.38), 0.42, Color("d6e4ec")],
			[Vector3(-0.08, 0, 0.05), 0.46, Color("f1efe6")], [Vector3(0.14, 0, 0.42), 0.38, Color("e9edf0")], [Vector3(-0.15, 0, 0.5), 0.3, Color("efe3b4")],
			[Vector3(0.1, 0.3, -0.12), 0.3, Color("dfe9ef")]]:
		var bc: Vector3 = gs + bag[0] + Vector3(0, 0.07, 0)
		var r: float = bag[1] / 2
		var bcol: Color = bag[2]
		box_into(st, bc + Vector3(-r * 0.85, 0, -r * 0.85), bc + Vector3(r * 0.85, r * 0.3, r * 0.85), bcol.darkened(0.1))
		box_into(st, bc + Vector3(-r, r * 0.3, -r), bc + Vector3(r, r * 1.2, r), bcol)
		box_into(st, bc + Vector3(-r * 0.75, r * 1.2, -r * 0.75), bc + Vector3(r * 0.75, r * 1.55, r * 0.75), bcol.lightened(0.06))
		box_into(st, bc + Vector3(-r * 0.4, r * 1.55, -r * 0.4), bc + Vector3(r * 0.4, r * 1.7, r * 0.4), bcol.darkened(0.04))
		box_into(st, bc + Vector3(-0.03, r * 1.7, -0.03), bc + Vector3(0.03, r * 1.7 + 0.06, 0.03), bcol.darkened(0.2))
		for e in [-1, 1]:
			box_into(st, bc + Vector3(e * 0.03 - 0.02, r * 1.7 + 0.04, -0.015), bc + Vector3(e * 0.07 + 0.02, r * 1.7 + 0.09, 0.015), bcol.darkened(0.12))
		if bcol == Color("efe3b4"):
			box_into(st, bc + Vector3(-r * 0.45, r * 0.6, r + 0.002), bc + Vector3(r * 0.45, r * 0.95, r + 0.006), Color("3f6fb8"))
	# the lid: a lipped steel frame netted over, the bags showing through it, hinged along the back on two knuckles,
	# braced across its middle, with a grab bar on the sidewalk end
	var lid := Color("4f8a5c")
	for z in [-1, 1]:
		box_into(st, gs + Vector3(-h.x - 0.04, 0.9, z * (h.z + 0.04) - 0.03), gs + Vector3(h.x + 0.04, 0.95, z * (h.z + 0.04) + 0.03), lid)
	for x in [-1, 1]:
		box_into(st, gs + Vector3(x * (h.x + 0.04) - 0.03, 0.9, -h.z - 0.01), gs + Vector3(x * (h.x + 0.04) + 0.03, 0.95, h.z + 0.01), lid)
	box_into(st, gs + Vector3(-h.x, 0.91, -0.02), gs + Vector3(h.x, 0.94, 0.02), lid.darkened(0.12))
	for z in [-0.45, 0.45]:
		box_into(st, gs + Vector3(-h.x - 0.09, 0.88, z - 0.06), gs + Vector3(-h.x - 0.04, 0.95, z + 0.06), frame.darkened(0.2))
	box_into(st, gs + Vector3(-0.2, 0.86, h.z + 0.07), gs + Vector3(0.2, 0.9, h.z + 0.11), Color("c9c6be"))
	box_into(st, gs + Vector3(-0.2, 0.9, h.z + 0.07), gs + Vector3(-0.17, 0.95, h.z + 0.11), Color("c9c6be"))
	box_into(st, gs + Vector3(0.17, 0.9, h.z + 0.07), gs + Vector3(0.2, 0.95, h.z + 0.11), Color("c9c6be"))
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
	# the net: a fine diamond mesh, see-through, on all four sides and across the lid
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		for x in 12:
			if (x + y) % 12 == 0 or (x - y + 12) % 12 == 0:
				img.set_pixel(x, y, Color("3f7550") if (x + y) % 12 == 0 else Color("335f40"))
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
		var len_ := (b - a).length() / 0.26
		net.set_color(Color(f[2], f[2], f[2]))
		add_quad(net, [a, b, b + Vector3(0, 0.78, 0), a + Vector3(0, 0.78, 0)], [Vector2(0, 3.0), Vector2(len_, 3.0), Vector2(len_, 0), Vector2.ZERO])
	net.set_color(Color(1.08, 1.08, 1.08))
	add_quad(net, [gs + Vector3(-h.x, 0.935, -h.z), gs + Vector3(h.x, 0.935, -h.z), gs + Vector3(h.x, 0.935, h.z), gs + Vector3(-h.x, 0.935, h.z)],
			[Vector2.ZERO, Vector2(h.x * 2 / 0.26, 0), Vector2(h.x * 2 / 0.26, h.z * 2 / 0.26), Vector2(0, h.z * 2 / 0.26)])
	commit([st, net], set_node)
	cast(set_node, Vector2(gs.x, gs.z), 0.0, 0.96, 0.8)
	cast(set_node, Vector2(sp.x, sp.z), 0.0, 1.24, 0.1)
	blob(set_node, Vector2(gs.x, gs.z - 0.3), 1.0)


## The A-board by your door, turned `turn` toward the street: two slanted boards hinged at the top under a cap, each
## framed in grained wood round a chalkboard lettered オススメ in yellow over a pink underline, an onigiri and a coffee
## cup chalked beside their prices, smudged where the last menu was wiped off, with a chain between its legs.
func a_board(at: Vector2, turn: float) -> void:
	const W := 0.54
	const H := 0.9
	const S := 0.2
	const PX := 64.0
	var ln := Vector2(S - 0.02, H).length()
	var iw := roundi(W * PX)
	var ih := roundi(ln * PX)
	var r := RandomNumberGenerator.new()
	r.seed = 29
	var noise := FastNoiseLite.new()
	noise.seed = 29
	noise.frequency = 0.12
	var wood := Color("8a5a34")
	var board := Color("2b3833")
	var img := Image.create(iw, ih, false, Image.FORMAT_RGB8)
	for y in ih:
		var grain := r.randf_range(0.92, 1.06)
		for x in iw:
			var edge := mini(mini(x, iw - 1 - x), mini(y, ih - 1 - y))
			var c: Color
			if edge < 3:
				c = wood * (grain * r.randf_range(0.96, 1.03) * (1.12 if edge == 0 and y == 0 else (0.82 if edge == 2 else 1.0)))
			else:
				var smear := smoothstep(0.35, 0.8, noise.get_noise_2d(x * 1.6, y) * 0.5 + 0.5)
				c = board.lerp(Color("5f6c66"), smear * 0.3) * r.randf_range(0.95, 1.04)
			img.set_pixel(x, y, Color(c.r, c.g, c.b))
	var chalk := func(x: int, y: int, col: Color) -> void:
		if x >= 3 and x < iw - 3 and y >= 3 and y < ih - 3 and r.randf() < 0.9:
			img.set_pixel(x, y, col.lerp(img.get_pixel(x, y), r.randf_range(0.0, 0.2)))
	var glyphs := {"o": ["...#.", "#####", "..##.", ".#.#.", "#..#."], "s": ["####.", "...#.", "..#..", ".#.#.", "#...#"],
		"m": ["....#", ".#.#.", "..#..", ".#.#.", "#...."],
		"1": [".#.", "##.", ".#.", ".#.", "###"], "2": ["##.", "..#", ".#.", "#..", "###"], "0": ["###", "#.#", "#.#", "#.#", "###"],
		"5": ["###", "#..", "##.", "..#", "##."]}
	var write := func(text: String, x0: int, y0: int, col: Color) -> void:
		for ch in text:
			var g: Array = glyphs[ch]
			for gy in g.size():
				for gx in g[gy].length():
					if g[gy][gx] == "#":
						chalk.call(x0 + gx, y0 + gy, col)
			x0 += g[0].length() + 1
	var yellow := Color("f3d873")
	var pink := Color("f29bb4")
	var white := Color("eef0e8")
	write.call("ossm", 4, 5, yellow)
	for x in range(4, iw - 4):  # the underline, wavering
		chalk.call(x, 12 + (1 if posmod(x, 6) < 3 else 0), pink)
	var oc := Vector2(9.5, 22.0)  # the onigiri: a chalk triangle filled in, its nori band left dark and outlined
	for y in range(15, 27):
		for x in range(3, 17):
			var half := (y - 15) * 0.55 + 0.5
			if absf(x - oc.x) < half:
				var nori := y >= 22 and absf(x - oc.x) < 2.5
				if absf(absf(x - oc.x) - half) < 1.0 or y == 26 or (nori and (absf(absf(x - oc.x) - 2.5) < 1.0 or y == 22)):
					chalk.call(x, y, white)
				elif not nori and r.randf() < 0.45:
					chalk.call(x, y, white.lerp(board, 0.4))
	write.call("120", 17, 19, pink)
	for y in range(33, 41):  # the coffee cup, its handle and a curl of steam
		for x in range(5, 13):
			if x == 5 or x == 11 or y == 40 or y == 33:
				chalk.call(x, y, white)
		if y >= 35 and y <= 37:
			chalk.call(13, y, white)
	for y in range(28, 32):
		chalk.call(7 + (y % 2), y, white.lerp(board, 0.3))
		chalk.call(10 - (y % 2), y, white.lerp(board, 0.3))
	write.call("150", 17, 35, yellow)
	for k in 3:  # scrawled lines of small print below
		for x in range(5, iw - 6 - k * 4):
			if posmod(x * 7 + k * 3, 5) != 0:
				chalk.call(x, 46 + k * 3 + (1 if x % 3 == 2 else 0), white.lerp(board, 0.25))
	img.generate_mipmaps()
	var face := mat(Color.WHITE, ImageTexture.create_from_image(img))
	face.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	face.texture_repeat = false
	var kit := mat(Color.WHITE)
	kit.vertex_color_use_as_albedo = true
	kit.vertex_color_is_srgb = true
	var fs := surface(face)
	var st := surface(kit)
	var b := Basis(Vector3.UP, turn)
	var o := Vector3(at.x, 0, at.y)
	for side: float in [1.0, -1.0]:
		var foot := Vector3(0, 0, S * side)
		var head := Vector3(0, H, 0.02 * side)
		var n := Vector3(0, S - 0.02, H).normalized() * Vector3(1, 1, side) * 0.025  # the board's thickness, inward
		var hx := Vector3(W / 2, 0, 0)
		var q := [foot + hx, head + hx, head - hx, foot - hx].map(func(p): return o + b * p)
		add_quad(fs, q, [Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Vector2(0, 1)] if side > 0 else [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
		for e: float in [1.0, -1.0]:  # the frame's edge along each side, lit on the sun's side
			var ex := hx * e
			var shade := 0.9 if e * side > 0 else 0.75
			st.set_color(Color(wood.r * shade, wood.g * shade, wood.b * shade))
			add_quad(st, [foot + ex, head + ex, head + ex - n, foot + ex - n].map(func(p): return o + b * p), [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
		st.set_color(wood * 0.7)
		add_quad(st, [foot + hx - n, head + hx - n, head - hx - n, foot - hx - n].map(func(p): return o + b * p), [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var cap := [Vector3(-W / 2 - 0.01, H - 0.02, -0.05), Vector3(W / 2 + 0.01, H + 0.03, 0.05)]
	st.set_color(wood.darkened(0.2))
	for p in [[Vector3(-1, 0, 0), 0.9], [Vector3(0, 0, 1), 0.9], [Vector3(0, 1, 0), 1.0], [Vector3(0, 0, -1), 0.75], [Vector3(1, 0, 0), 0.75]]:
		var fn: Vector3 = p[0]
		var u := Vector3.UP if absf(fn.y) < 0.5 else Vector3.RIGHT
		var v := fn.cross(u)
		var c: Vector3 = (cap[0] + cap[1]) / 2
		var h: Vector3 = (cap[1] - cap[0]) / 2
		var ctr := c + fn * absf(fn.dot(h))
		var hu := u * absf(u.dot(h))
		var hv := v * absf(v.dot(h))
		st.set_color(wood.darkened(0.2) * p[1])
		add_quad(st, [ctr - hu - hv, ctr + hu - hv, ctr + hu + hv, ctr - hu + hv].map(func(q): return o + b * q), [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	for e: float in [1.0, -1.0]:  # the chain holding the legs apart
		var ex := Vector3(W / 2 - 0.03, 0, 0) * e
		var a := Vector3(0, 0.32, (S - 0.02) * (1.0 - 0.32 / H) + 0.02 - 0.03)
		var a2 := Vector3(a.x, a.y, -a.z)
		st.set_color(Color("9a9c9c"))
		add_quad(st, [a + ex, a2 + ex, a2 + ex + Vector3(0, 0.012, 0), a + ex + Vector3(0, 0.012, 0)].map(func(p): return o + b * p), [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	commit([fs, st], set_node)


## The car park's furniture in one surface: wheel stops banded in yellow, and a low planter along the back below the
## till's sight line, a coped concrete trough holding a clipped hedge of lumpy shrubs with a few azaleas in flower,
## their foliage leafed in leaf_tex and each lump bellying out over a shaded waist.
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
	var fm := mat(Color.WHITE, leaf_tex())
	fm.vertex_color_use_as_albedo = true
	fm.vertex_color_is_srgb = true
	var fol := surface(fm)
	var leaf := Color("5f9e50")  # the leaf texture averages about 0.8, so this lands on the old 4f8a43
	box_into(fol, Vector3(p0.x + 0.08, 0.31, p0.z + 0.08), Vector3(p1.x - 0.08, 0.42, p1.z - 0.08), leaf.darkened(0.22), 3.0)
	var x := p0.x + 0.08
	while x < p1.x - 0.12:  # the clipped top rises and dips in soft lumps, each lit a shade on its crown
		var x1 := minf(x + r.randf_range(0.3, 0.42), p1.x - 0.08)
		var top := r.randf_range(0.49, 0.58)
		var g: Color = leaf.lightened(r.randf_range(-0.06, 0.08))
		var z0 := p0.z + r.randf_range(0.06, 0.1)
		var z1 := p1.z - r.randf_range(0.06, 0.1)
		var ix := (x1 - x) * 0.18
		box_into(fol, Vector3(x + 0.03, 0.36, z0 + 0.03), Vector3(x1 - 0.03, 0.44, z1 - 0.03), g.darkened(0.14), 3.0)
		box_into(fol, Vector3(x, 0.44, z0), Vector3(x1, top - 0.03, z1), g, 3.0)
		box_into(fol, Vector3(x + ix * 0.5, top - 0.03, z0 + 0.025), Vector3(x1 - ix * 0.5, top, z1 - 0.025), g.lightened(0.08), 3.0)
		box_into(fol, Vector3(x + ix, top, z0 + 0.06), Vector3(x1 - ix, top + 0.025, z1 - 0.06), g.lightened(0.2), 3.0)
		if r.randf() < 0.45:  # an azalea in flower poking through the clipped face
			var fx := r.randf_range(x + 0.04, x1 - 0.1)
			var fy := r.randf_range(0.36, top - 0.06)
			var fz := maxf(z1, p1.z - 0.08)
			box_into(st, Vector3(fx, fy, fz), Vector3(fx + 0.06, fy + 0.05, fz + 0.03), Color("e86a9a") if r.randf() < 0.6 else Color("f4f0ec"))
		if x1 >= p1.x - 0.08:
			break
		x = x1 - r.randf_range(0.08, 0.14)
	commit([st, fol], set_node)


## Clipped foliage in grey: leaf tips lit on top over a darker underside, dark gaps between, around 0.8 on average.
func leaf_tex() -> ImageTexture:
	var r := RandomNumberGenerator.new()
	r.seed = 12
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(Color(0.74, 0.74, 0.74))
	for i in 34:
		var lx := r.randi() % 16
		var ly := r.randi() % 16
		img.set_pixel((lx + 1) % 16, (ly + 1) % 16, Color(0.56, 0.58, 0.6))
		img.set_pixel(lx, (ly + 1) % 16, Color(0.66, 0.67, 0.68))
		img.set_pixel(lx, ly, Color(0.86, 0.86, 0.82))
		img.set_pixel((lx + 1) % 16, ly, Color(0.96, 0.97, 0.9) if r.randf() < 0.5 else Color(0.86, 0.86, 0.82))
	for i in 10:
		img.set_pixel(r.randi() % 16, r.randi() % 16, Color(0.42, 0.44, 0.46))
	return ImageTexture.create_from_image(img)


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
	var tar := surface(side_tarmac())
	var road := surface(tarmac())
	rect_quad(road, Rect2(street_x.x, -3.7, street_x.y - street_x.x, 7.4), -0.045, 0.0, false, 0.125)
	var kerb := surface(mat(Color("8f8b84")))
	var kerb_m := mat(Color.WHITE)
	kerb_m.vertex_color_use_as_albedo = true
	kerb_m.vertex_color_is_srgb = true
	var kerbs := surface(kerb_m)
	var tactile := surface(tactile())  # the yellow guide strip down each sidewalk
	# a raised kerb along each sidewalk, dropped flush at the crossing and, on your side, across the car park's mouth
	for sd in [[far_gaps, -7.2, -3.8, -5.4, Vector2(-3.4, Sim.CROSS_X + 1.7)], [near_gaps, 3.7, 3.6, 5.0, Vector2(Sim.CROSS_X - 1.7, Sim.CROSS_X + 1.7)]]:
		var drop: Vector2 = sd[4]
		for o in open_spans(sd[0]):
			rect_quad(walk, Rect2(o.x, sd[1], o.y - o.x, 3.5), -0.045, 0.0, false, 0.5)
			rect_quad(kerb, Rect2(o.x, sd[2], o.y - o.x, 0.2), -0.04)
			# warning tiles where the strip meets a side road and across the crossing, a guide spur out to a row of
			# them along the kerb
			var warn := []
			if o.x > street_x.x:
				warn.append(Vector2(o.x, floorf(o.x / 0.32 + 1.0) * 0.32))
			if o.y < street_x.y:
				warn.append(Vector2(ceilf(o.y / 0.32 - 1.0) * 0.32, o.y))
			var cx := floorf(Sim.CROSS_X / 0.32) * 0.32
			if cx - 0.32 > o.x and cx + 0.64 < o.y:
				warn.append(Vector2(cx - 0.32, cx + 0.64))
				var kz: float = sd[2] + 0.22 if sd[2] > 0.0 else sd[2] - 0.02
				var sz: float = sd[3] if sd[2] > 0.0 else sd[3] + 0.32
				tactile_run(tactile, Rect2(cx - 1.28, minf(kz, kz + 0.32 * signf(sd[2])), 2.88, 0.32), -0.042, true)
				var spur := Vector2(kz + 0.32, sz) if sd[2] > 0.0 else Vector2(sz, kz - 0.32)
				tactile_run(tactile, Rect2(cx, spur.x, 0.32, spur.y - spur.x), -0.042, false, true)
			warn.sort_custom(func(a, b): return a.x < b.x)
			var tx: float = o.x
			for w in warn:
				if w.x > tx:
					tactile_run(tactile, Rect2(tx, sd[3], w.x - tx, 0.32), -0.042)
				if w.y > maxf(w.x, tx):
					tactile_run(tactile, Rect2(maxf(w.x, tx), sd[3], w.y - maxf(w.x, tx), 0.32), -0.042, true)
				tx = maxf(tx, w.y)
			if o.y > tx:
				tactile_run(tactile, Rect2(tx, sd[3], o.y - tx, 0.32), -0.042)
			for seg in [Vector2(o.x, minf(o.y, drop.x)), Vector2(maxf(o.x, drop.y), o.y)]:
				if seg.y - seg.x > 0.3:
					box_into(kerbs, Vector3(seg.x, -0.045, sd[2]), Vector3(seg.y, 0.09, sd[2] + 0.2), Color("bdb7ab"))
		for g in sd[0]:  # a side road's mouth: the asphalt runs through the sidewalk, the kerb turning the corners
			rect_quad(tar, Rect2(g.x, sd[1], g.y - g.x, 3.5), -0.045, 0.0, false, 0.0625)
			for ex in [g.x - 0.2, g.y]:
				if ex > street_x.x and ex + 0.2 < street_x.y:
					box_into(kerbs, Vector3(ex, -0.045, sd[1]), Vector3(ex + 0.2, 0.09, sd[1] + 3.5), Color("bdb7ab"))
	var paint := surface(road_paint())
	var x := SET.position.x
	while x < SET.end.x:
		if x >= street_x.x and x + 2.0 <= street_x.y and (x + 2.0 < Sim.CROSS_X - 2.0 or x > Sim.CROSS_X + 2.0):
			rect_quad(paint, Rect2(x, -0.08, 2.0, 0.16), -0.04, 0.0, false, 0.125)
		x += 4.0
	var z := -3.3
	while z < 3.4:
		rect_quad(paint, Rect2(Sim.CROSS_X - 1.5, z, 3.0, 0.42), -0.04, 0.0, false, 0.125)
		z += 0.84
	# edge lines inside the kerbs, broken at the crossing and at side roads; a zebra across each side road's mouth
	for sd in [[far_gaps, -3.42, -6.95], [near_gaps, 3.3, 4.05]]:
		for o in open_spans(sd[0]):
			for seg in [Vector2(o.x, minf(o.y, Sim.CROSS_X - 1.7)), Vector2(maxf(o.x, Sim.CROSS_X + 1.7), o.y)]:
				if seg.y - seg.x > 0.5:
					rect_quad(paint, Rect2(seg.x, sd[1], seg.y - seg.x, 0.12), -0.04, 0.0, false, 0.125)
		for g in sd[0]:
			var zx: float = g.x + 0.5
			while zx + 0.45 < g.y - 0.4:
				rect_quad(paint, Rect2(zx, sd[2], 0.45, 2.9), -0.04, 0.0, false, 0.125)
				zx += 0.9
	# your parking: bays and bicycles between your shop and the alley, nothing tall to hide the till
	var bay := surface(car_park())
	rect_quad(bay, Rect2(-3.4, -16.0, 7.1, 8.8), -0.042, 1.0)
	# its bay lines and the arrow leading drivers in off the street, laid in the street's paint as geometry so they
	# stay whole at every zoom; uv runs along each line through a band of the paint clear of the lanes' wheel paths
	for bx in [-2.2, 0.2, 2.6]:
		add_quad(paint, [Vector3(bx, -0.04, -15.6), Vector3(bx + 0.13, -0.04, -15.6), Vector3(bx + 0.13, -0.04, -11.0), Vector3(bx, -0.04, -11.0)],
			[Vector2(-1.95, 0.03), Vector2(-1.95, 0.046), Vector2(-1.375, 0.046), Vector2(-1.375, 0.03)])
	add_quad(paint, [Vector3(-2.2, -0.04, -15.6), Vector3(2.73, -0.04, -15.6), Vector3(2.73, -0.04, -15.47), Vector3(-2.2, -0.04, -15.47)],
		[Vector2(-0.275, 0.06), Vector2(0.341, 0.06), Vector2(0.341, 0.076), Vector2(-0.275, 0.076)])
	poly_fill(paint, PackedVector2Array([Vector2(0.95, -8.1), Vector2(0.95, -9.55), Vector2(0.55, -9.55), Vector2(1.07, -10.35), Vector2(1.59, -9.55), Vector2(1.19, -9.55), Vector2(1.19, -8.1)]), -0.04)
	for kb in [Rect2(-3.4, -16.25, 7.1, 0.25), Rect2(3.45, -16.25, 0.25, 9.05)]:  # kerb round the back and side
		rect_quad(kerb, kb, -0.036)
	var hatch := surface(mat(Color("e2c048")))
	# the strip along your wall kept clear for bicycles: a yellow box, closed all round, hatched at 45 degrees inside
	var hb := Rect2(-3.22, -15.52, 0.76, 4.34)
	for hr in [Rect2(-3.3, -15.6, 0.92, 0.08), Rect2(-3.3, -11.18, 0.92, 0.08), Rect2(-3.3, -15.6, 0.08, 4.5), Rect2(-2.46, -15.6, 0.08, 4.5)]:
		rect_quad(hatch, hr, -0.038)
	var hc := hb.position.y - hb.end.x + 0.25
	while hc < hb.end.y - hb.position.x:  # each stripe the band between z = x + c and z = x + c + 0.12, cut to the box
		var ends: Array[Vector3] = []
		for e: float in [hc, hc + 0.12]:
			var xa := maxf(hb.position.x, hb.position.y - e)
			var xb := minf(hb.end.x, hb.end.y - e)
			ends.append(Vector3(xa, xb, e))
		if ends[0].x < ends[0].y and ends[1].x < ends[1].y:
			add_quad(hatch, [Vector3(ends[0].x, -0.038, ends[0].x + hc), Vector3(ends[0].y, -0.038, ends[0].y + hc),
				Vector3(ends[1].y, -0.038, ends[1].y + hc + 0.12), Vector3(ends[1].x, -0.038, ends[1].x + hc + 0.12)], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		hc += 0.5
	# the yard round the back of the car park and on to the rival, where the set's lots meet: poured concrete scored
	# into slabs, with a drain grating along the sidewalk, rather than the bare district ground the set cleared
	var yard := surface(slabs())
	rect_quad(yard, Rect2(3.7, -20.2, span.x - 3.7, 13.0), -0.043, 0.0, false, 1.0 / 7.2)
	rect_quad(yard, Rect2(-16.5, -20.2, 20.2, 3.95), -0.043, 0.0, false, 1.0 / 7.2)
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
		var lid := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1.0, 1.0)
		lid.mesh = pm
		lid.material_override = manhole()
		lid.position = Vector3(mh.x, -0.038, mh.y)
		lid.rotation.y = mh.x * 0.7  # each lid set down its own way round
		set_node.add_child(lid)
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
			var axis := Vector3(cx, cy - 0.2, 6.65)
			for hx in [-0.22, 0.22]:  # hangers up to the cable
				box_into(closures, axis + Vector3(hx - 0.012, 0.08, -0.012), Vector3(cx + hx + 0.012, cy + 0.01, 6.662), Color("2a2b2f"))
			pipe_into(closures, axis + Vector3(-0.32, 0, 0), axis + Vector3(0.32, 0, 0), 0.1, Color("80838a"))
			for rx in [-0.16, 0.0, 0.16]:
				pipe_into(closures, axis + Vector3(rx - 0.015, 0, 0), axis + Vector3(rx + 0.015, 0, 0), 0.108, Color("676a71"))
			for ex in [-1.0, 1.0]:  # end caps on clamp rings, the cable spliced in through each
				pipe_into(closures, axis + Vector3(0.3 * ex, 0, 0), axis + Vector3(0.36 * ex, 0, 0), 0.115, Color("4c4e54"))
				pipe_into(closures, axis + Vector3(0.36 * ex, 0, 0), axis + Vector3(0.4 * ex, 0, 0), 0.075, Color("3a3c41"))
				pipe_into(closures, axis + Vector3(0.4 * ex, 0, 0), Vector3(cx + 0.62 * ex, cy - 0.02, 6.65), 0.028, Color("34343a"))
			box_into(closures, axis + Vector3(-0.06, -0.2, 0.04), axis + Vector3(0.06, -0.1, 0.05), Color("eeeae0"))  # its route tag
			box_into(closures, axis + Vector3(-0.004, -0.1, 0.044), axis + Vector3(0.004, -0.08, 0.046), Color("34343a"))
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
	back_row(SET.position.x, SET.end.x, -20.5, [11.0, 8.0, 5.0], mix, r, boxes, roofs, roads + overhead)
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
		# its roof: a weathered membrane laid in strips with a drain, an old water tank on a frame, two tired AC units
		# and a vent stack, all kept low so nothing rises over your shop
		var xl := vx - vw / 2
		plane(set_node, Vector2(vw - 0.4, 8.4), Vector3(vx, 3.63, -11.75), vacant_roof(xl, vw))
		block(set_node, Vector3(0.3, 0.05, 0.3), Vector3(xl + 0.45, 3.63, -7.95), Color("4d4a44"))
		var drift := surface(mat(Color(1, 1, 1, 0.999), snow_tex))
		rect_quad(drift, Rect2(xl + 0.2, -15.95, vw - 0.4, 8.4), 3.665, 0.0, false, 0.125)
		commit([drift], snow_cover)
		var kit := surface(km)
		var faces := surface(condenser())
		# the parapet, its walls under a coping in your unit's brown trim that overhangs them both ways
		for pr in [[xl, -7.42, xl + vw, -7.2], [xl, -16.2, xl + vw, -15.98], [xl, -16.2, xl + 0.22, -7.2], [xl + vw - 0.22, -16.2, xl + vw, -7.2]]:
			box_into(kit, Vector3(pr[0], 3.6, pr[1]), Vector3(pr[2], 3.88, pr[3]), Color("e3ddcf"))
			box_into(kit, Vector3(pr[0] - 0.04, 3.88, pr[1] - 0.04), Vector3(pr[2] + 0.04, 3.95, pr[3] + 0.04), Color("5b4632"))
		# the tank: a frame of angle legs braced across under a deck, the FRP drum on it ringed by two hoops, a lid with its
		# manhole hatch, a vent cap, a sight gauge down its sunny side and the supply pipe dropping down a leg to the roof
		var tank := Vector3(xl + 1.0, 3.6, -14.9)
		var steel := Color("6e737d")
		for lg in [Vector2(-0.45, -0.45), Vector2(0.45, -0.45), Vector2(-0.45, 0.45), Vector2(0.45, 0.45)]:
			box_into(kit, tank + Vector3(lg.x - 0.04, 0, lg.y - 0.04), tank + Vector3(lg.x + 0.04, 0.5, lg.y + 0.04), steel)
			box_into(kit, tank + Vector3(lg.x - 0.07, 0, lg.y - 0.07), tank + Vector3(lg.x + 0.07, 0.03, lg.y + 0.07), Color("8e8d88"))
		for dz in [-0.45, 0.45]:
			box_into(kit, tank + Vector3(-0.45, 0.2, dz - 0.02), tank + Vector3(0.45, 0.24, dz + 0.02), steel.darkened(0.1))
		for dx in [-0.45, 0.45]:
			box_into(kit, tank + Vector3(dx - 0.02, 0.2, -0.45), tank + Vector3(dx + 0.02, 0.24, 0.45), steel.darkened(0.1))
		box_into(kit, tank + Vector3(-0.525, 0.48, -0.525), tank + Vector3(0.525, 0.56, 0.525), steel)
		var frp := Color("9fc0cc")
		drum_into(kit, tank + Vector3(0, 0.56, 0), 0.5, 0.85, frp)
		for hy in [0.72, 1.14]:
			drum_into(kit, tank + Vector3(0, hy, 0), 0.515, 0.05, frp.darkened(0.14))
		drum_into(kit, tank + Vector3(0, 1.41, 0), 0.47, 0.04, frp.lightened(0.1))
		drum_into(kit, tank + Vector3(0, 1.45, 0), 0.19, 0.1, Color("b9cdd5"))
		drum_into(kit, tank + Vector3(0, 1.55, 0), 0.21, 0.025, Color("7d9ba8"))
		box_into(kit, tank + Vector3(0.24, 1.45, -0.26), tank + Vector3(0.28, 1.62, -0.22), Color("d8dcd8"))
		box_into(kit, tank + Vector3(0.2, 1.62, -0.3), tank + Vector3(0.32, 1.66, -0.18), Color("d8dcd8"))
		box_into(kit, tank + Vector3(-0.36, 0.64, 0.33), tank + Vector3(-0.32, 1.33, 0.37), Color("e9eef0"))
		box_into(kit, tank + Vector3(-0.355, 0.8, 0.355), tank + Vector3(-0.325, 1.0, 0.375), Color("3f6f8c"))
		box_into(kit, tank + Vector3(0.4, 0.0, 0.4), tank + Vector3(0.46, 0.56, 0.46), Color("bdb8ad"))
		box_into(kit, tank + Vector3(0.4, 0.03, 0.46), tank + Vector3(0.46, 0.09, 1.2), Color("bdb8ad"))
		for k in 2:
			var ac := Vector3(xl + 0.9 + k * 1.4, 3.6, -11.6)
			box_into(kit, ac + Vector3(-0.55, 0, -0.4), ac + Vector3(0.55, 0.1, 0.4), Color("8e8d88"))
			condenser_into(kit, faces, ac + Vector3(0, 0.1, 0), Vector3(0.95, 0.55, 0.65))
		box_into(kit, Vector3(xl + 2.25, 3.63, -14.85), Vector3(xl + 2.35, 3.73, -11.75), Color("bdb8ad"))  # their pipe to the back
		var vent := Vector3(vx + vw / 2 - 0.7, 3.6, -9.2)
		drum_into(kit, vent, 0.13, 0.08, Color("8e8d88"), 12)  # the stack on its flashing, under a rain cowl
		drum_into(kit, vent, 0.08, 0.66, Color("9aa0a6"), 12)
		drum_into(kit, vent + Vector3(0, 0.66, 0), 0.17, 0.06, steel, 12)
		drum_into(kit, vent + Vector3(0, 0.72, 0), 0.1, 0.04, steel.lightened(0.15), 12)
		commit([kit, faces], set_node)
		block(set_node, Vector3(vw - 0.3, 0.55, 0.12), Vector3(vx, 3.1, -7.16), Color("cfc7b6"))
		block(set_node, Vector3(vw - 1.1, 0.4, 0.06), Vector3(vx, 3.1, -7.08), Color("e9e4d8"))  # where the old sign hung
		# its ghost: paint unfaded where the board sat, grime caught round its edge and rust bled from its screw holes
		var gw := maxi(8, roundi((vw - 1.1) * 32.0))
		var ghost := Image.create(gw, 13, false, Image.FORMAT_RGB8)
		for px in gw:
			for y in 13:
				var c := Color("e9e4d8")
				var edge := mini(mini(px, gw - 1 - px), mini(y, 12 - y))
				if edge == 1:
					c = Color("b9b1a1")
				elif edge >= 2:
					c = Color("f1ede3")
				ghost.set_pixel(px, y, c)
		for hx in [3, gw / 2, gw - 4]:
			for hy in [3, 9]:
				ghost.set_pixel(hx, hy, Color("4a443c"))
				for k in (hx + hy) % 3 + 1:
					ghost.set_pixel(hx, hy + 1 + k, Color("e9e4d8").lerp(Color("94603e"), 0.6 - k * 0.2))
		var gq := MeshInstance3D.new()
		var gm := QuadMesh.new()
		gm.size = Vector2(vw - 1.1, 0.4)
		gq.mesh = gm
		gq.material_override = mat(Color(0.9, 0.9, 0.9), ImageTexture.create_from_image(ghost))
		gq.position = Vector3(vx, 3.1, -7.047)
		set_node.add_child(gq)
		# the shutter box: a pressed steel case, its top lit, a seam along its face and an end cap at each side
		block(set_node, Vector3(vw - 0.5, 0.3, 0.32), Vector3(vx, 2.62, -7.05), Color("9aa0a6"))
		block(set_node, Vector3(vw - 0.5, 0.025, 0.33), Vector3(vx, 2.78, -7.05), Color("c3c8cc"))
		block(set_node, Vector3(vw - 0.5, 0.02, 0.01), Vector3(vx, 2.6, -6.885), Color("6e737a"))
		for side in [-1, 1]:
			block(set_node, Vector3(0.05, 0.33, 0.35), Vector3(vx + side * (vw - 0.5) / 2, 2.62, -7.05), Color("7d8389"))
		# the shutter at 32 px a metre: slats 15 cm deep, each a lit lip over its face, a shaded underside and a dark
		# groove, a shade apart; two vented slats under the box, a few dents, road grime climbing from the foot in
		# blotches, rust run down from the box, and a bottom bar with its handle
		var sw := vw - 0.8
		var sh := 78
		var slats := Image.create(maxi(8, roundi(sw * 32.0)), sh, false, Image.FORMAT_RGB8)
		var sx := slats.get_width()
		var rr := RandomNumberGenerator.new()
		rr.seed = 7
		var gn := FastNoiseLite.new()
		gn.seed = 7
		gn.frequency = 0.07
		var runs := {}
		for k in roundi(sw * 1.4):
			runs[rr.randi_range(1, sx - 2)] = rr.randi_range(12, 44)
		var tone := []
		for k in sh / 5 + 1:
			tone.append(rr.randf_range(0.96, 1.03))
		var dents := []
		for k in 3:
			dents.append(Vector3i(rr.randi_range(4, sx - 14), rr.randi_range(6, 13) * 5, rr.randi_range(6, 11)))
		var face := [Color("e8ebec"), Color("d3d7d9"), Color("cdd1d4"), Color("aeb3b7"), Color("7a8086")]
		for px in sx:
			for y in sh:
				var c: Color
				if y >= sh - 5:  # the bottom bar
					c = [Color("cfd3d6"), Color("9aa0a6"), Color("969ca2"), Color("8f959b"), Color("575d64")][y - (sh - 5)]
					if absi(px - sx / 2) <= 6 and y > sh - 5 and y < sh - 1:
						c = Color("3d4248") if y > sh - 4 else Color("b5babe")
				else:
					var row := y % 5
					c = face[row] * tone[y / 5]
					if y / 5 in [1, 2] and row in [1, 2] and posmod(px, 10) in [2, 3, 4, 5, 6, 7]:
						c = Color("3a3f45") if row == 1 else Color("50565c")
					for d: Vector3i in dents:
						if y - row == d.y and px >= d.x and px < d.x + d.z and row in [1, 2]:
							c = c.darkened(0.14) if row == 1 else c.lightened(0.1)
				var g := pow(clampf((y - 30.0) / 48.0, 0.0, 1.0), 1.3) * (0.55 + 0.45 * (gn.get_noise_2d(px, y * 2.0) * 0.5 + 0.5))
				c = c.lerp(Color("6f6658"), 0.85 * g)
				if y > sh - 16 and rr.randf() < 0.07:
					c = c.darkened(0.18)
				if runs.has(px) and y < runs[px]:
					c = c.lerp(Color("8a5a3a"), 0.65 * (1.0 - float(y) / runs[px]))
				slats.set_pixel(px, y, c)
		var shutter := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(sw, 2.45)
		shutter.mesh = q
		slats.generate_mipmaps()
		var sm := mat(Color(0.9, 0.9, 0.9), ImageTexture.create_from_image(slats))
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		shutter.material_override = sm
		shutter.position = Vector3(vx, 1.235, -7.17)
		set_node.add_child(shutter)
		block(set_node, Vector3(vw - 0.7, 0.1, 0.1), Vector3(vx, 0.05, -7.13), Color("7d8389"))
		for side in [-1, 1]:
			block(set_node, Vector3(0.12, 2.5, 0.14), Vector3(vx + side * (sw / 2 + 0.02), 1.25, -7.13), Color("7d8389"))  # guide rails
			block(set_node, Vector3(0.07, 0.1, 0.05), Vector3(vx + side * (sw / 2 - 0.45), 0.13, -7.06), Color("c9a24a"))  # padlocked to the kerb
		# the agent's to-let bill and old flyers taped up and peeling, and the post nobody collects heaped at the foot
		for bl in [[shutter_bill(0), Vector2(1.1, 0.77), Vector3(0.4, 1.52, -7.14)], [shutter_bill(1), Vector2(0.44, 0.6), Vector3(0.45 - sw / 2, 1.3, -7.15)],
				[shutter_bill(2), Vector2(0.38, 0.52), Vector3(0.92 - sw / 2, 1.0, -7.152)]]:
			var bill := MeshInstance3D.new()
			var sheet := QuadMesh.new()
			sheet.size = bl[1]
			bill.mesh = sheet
			var bill_m := mat(Color(0.92, 0.92, 0.92), bl[0])
			bill_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			bill_m.texture_repeat = false
			bill.material_override = bill_m
			bill.position = Vector3(vx, 0, 0) + bl[2]
			set_node.add_child(bill)
		for m in [[Vector3(0.42, 0.04, 0.24), Vector3(-0.3, 0.02, -6.98), Color("f2efe6")], [Vector3(0.3, 0.03, 0.2), Vector3(-0.05, 0.045, -6.95), Color("e7c9a0")], [Vector3(0.26, 0.03, 0.18), Vector3(-0.45, 0.05, -6.92), Color("d9e4ee")]]:
			block(set_node, m[0], Vector3(vx, 0, 0) + m[1], m[2])
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
		[1, Vector2(-30.0, 6.0)], [2, Vector2(-14.0, 6.0)], [1, Vector2(12.0, 6.0)], [0, Vector2(26.0, 6.0)], [1, Vector2(42.0, 6.0)],
		[6, Vector2(-6.0, 4.3)], [6, Vector2(20.0, 4.3)], [7, Vector2(-1.6, -4.6)], [10, Vector2(-22.6, -6.6)],
		[8, Vector2(-2.75, -12.3)], [8, Vector2(-2.75, -13.5)], [4, Vector2(3.3, -15.2)]]
	if b.quirk == "busStop":
		props_at.append([11, Vector2(-24.5, -4.4)])
	wall_bikes = Node3D.new()
	set_node.add_child(wall_bikes)
	for p in props_at:
		if p[1].x < street_x.x + 0.5 or p[1].x > street_x.y - 0.5 or in_gaps(p[1].x, far_gaps if p[1].y < 0.0 else near_gaps) or in_gaps(p[1].x, under[0] if p[1].y < 0.0 else under[1]):
			continue
		if p[0] == 6:
			street_lamp(Vector3(p[1].x, 0, p[1].y))
			continue
		if p[0] <= 2:  # a tree stands in its pit, the grate's long side along the kerb, its trunk's foot drawn a little in
			plane(set_node, Vector2(1.2, 0.9), Vector3(p[1].x, -0.041, p[1].y - 0.2), tree_pit())
		var host: Node3D = wall_bikes if p[0] == 8 else set_node
		var s := sprite("outdoor", Rect2(p[0] * OUTDOOR, 0, OUTDOOR, OUTDOOR), OUTDOOR_PX * OUTDOOR_SCALE[p[0]] * 0.55)
		s.position = Vector3(p[1].x, OUTDOOR / 2.0 * OUTDOOR_PX * OUTDOOR_SCALE[p[0]] * 0.55 - 0.05, p[1].y)
		host.add_child(s)
		lit_sprites.append(s)
		blob(host, p[1], PROP_BLOB.get(p[0], OUTDOOR_SCALE[p[0]] * 1.5))
		outdoor_cast(host, p[0], p[1], OUTDOOR_SCALE[p[0]] * 0.55)
	shop_spill_mat.albedo_texture = shop_spill_tex(zl)
	spill(set_node, Sim.ORIGIN.x + (zl + 6.6) / 2, 8.6 - zl, Sim.ORIGIN.y + 4.7, shop_spill_mat)  # your shop's open front
	a_board(Vector2(-8.3, -6.2), 0.35)
	blob(set_node, Vector2(-8.3, -6.2), 0.45)
	cast(set_node, Vector2(-8.3, -6.2), 0.0, 0.9, 0.44)
	for d in [[0, Vector2(-6.7, -6.75), 0.6], [0, Vector2(-4.1, -6.75), 0.6]]:
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
	head.scale = Vector3(0.3, 0.1, 0.52)  # the bowl sags below the housing so its sides show from above
	head.position = at + Vector3(0, ay - 0.1, 1.02 * out)
	head.material_override = lamp_mat
	set_node.add_child(head)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	halo.mesh = q
	halo.material_override = halo_mat
	halo.position = at + Vector3(0, 4.2, 1.02 * out)  # below the head, so its housing doesn't hide the bright core
	set_node.add_child(halo)
	var glare := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(1.2, 1.2)
	glare.mesh = gq
	glare.material_override = glare_mat
	# on the lens, slid toward the camera along its line of sight so the housing can't hide it
	var p := deg_to_rad(PITCH)
	glare.position = at + Vector3(0, ay - 0.2, 1.02 * out) + Vector3(sin(PI / 4) * cos(p), sin(p), cos(PI / 4) * cos(p)) * 1.2
	set_node.add_child(glare)
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
	pool(set_node, at + Vector3(0, 0, 1.3 * out), Vector2(10.0, 6.6), street_pool_mat)  # thrown along the street


func set_row(x0: float, x1: float, zf: float, max_depth: float, mix: Array, r: RandomNumberGenerator, boxes: Array, roofs: Array, tall: float, roads: Array) -> void:
	for run in free_runs(x0, x1, zf - max_depth, zf, roads):
		fill_row(run.x, run.y, zf, max_depth, mix, r, boxes, roofs, tall)


## The row behind the street, from x0 to x1, fronting z = zf: where a road or the water behind only cuts into the back
## of it, shallower buildings fill in again (down to the last of `depths`), so the block behind your shop stays built
## up rather than opening onto a bare lot.
func back_row(x0: float, x1: float, zf: float, depths: Array, mix: Array, r: RandomNumberGenerator, boxes: Array, roofs: Array, roads: Array) -> void:
	var gaps := [Vector2(x0, x1)]
	for dep in depths:
		var left := []
		for g in gaps:
			var x: float = g.x
			for run in free_runs(g.x, g.y, zf - dep, zf, roads):
				fill_row(run.x, run.y, zf, dep, mix, r, boxes, roofs, 1.0)
				if run.x > x:
					left.append(Vector2(x, run.x))
				x = run.y
			if g.y > x:
				left.append(Vector2(x, g.y))
		gaps = left


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
		elif bd.floors >= 3 and fp.size.x > 6.0 and fp.size.y > 6.0:
			boxes.append(kit_box(fp, h, bd.kit))
		pos += w


## The plant room on a flat roof of three floors or more, placed by the building's kit (0-1); BUILDING_SHADER finds it
## the same way to lay its shadow. [size, centre, tint, style] as the building boxes.
func kit_box(r: Rect2, h: float, k: float) -> Array:
	var ks := Vector3(1.6 + 1.6 * k, 1.2, 1.4 + 1.8 * (1.0 - k))
	return [ks, Vector3(r.position.x + 1.0 + ks.x / 2 + (r.size.x - ks.x - 2.0) * k, h + 0.6, r.position.y + 1.0 + ks.z / 2 + (r.size.y - ks.z - 2.0) * (1.0 - k)), Color("c9c7c0"), Sim.City.PLAIN]


## The one-floor shops between your car park and the rival, seen from above: a parapet with a coping round a membrane
## laid in strips, its drain, AC condensers on pads piped to the edge, a vent stack and a roof hatch, all low, each laying
## its shadow on the membrane (see shop_roof_tex).
func shop_roofs(list: Array) -> void:
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var kit := surface(km)
	var faces := surface(condenser())
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
		var drain: Vector3 = at.call(long_ - 0.5, -minf(sz.x, sz.z) / 2 + 0.45)
		var casts := []  # footprint, shadow offset (street frame)
		rect_quad(drift, Rect2(x0 + 0.15, z0 + 0.15, sz.x - 0.3, sz.z - 0.3), y + 0.06, 0.0, false, 0.125)
		var units := 1 if long_ < 5.0 else 2
		for k in units:
			var ac: Vector3 = at.call(long_ * 0.3 + k * 1.25, r.randf_range(-0.2, 0.2))
			box_into(kit, ac + Vector3(-0.55, 0, -0.4), ac + Vector3(0.55, 0.1, 0.4), Color("8e8d88"))
			condenser_into(kit, faces, ac + Vector3(0, 0.1, 0), Vector3(0.94, 0.52, 0.64))
			casts.append([Rect2(ac.x - 0.55, ac.z - 0.4, 1.1, 0.8), Vector2(0.24, -0.4)])
		var pipe: Vector3 = at.call(long_ * 0.3, 0.0)  # their pipes run along the roof to drop down the back
		var end_: Vector3 = at.call(long_ - 0.15, 0.0)
		var off := Vector3(0.62, 0, 0) if along_z else Vector3(0, 0, 0.5)
		box_into(kit, pipe + off - Vector3(0.05, 0, 0.05), end_ + off + Vector3(0.05, 0.1, 0.05), Color("bdb8ad"))
		var pa := Vector2(minf(pipe.x, end_.x) + off.x - 0.05, minf(pipe.z, end_.z) + off.z - 0.05)
		casts.append([Rect2(pa, Vector2(absf(end_.x - pipe.x), absf(end_.z - pipe.z)) + Vector2(0.1, 0.1)), Vector2(0.05, -0.08)])
		# the hatch: a plastered kerb with the membrane turned up its foot under a galvanised lid that overhangs it, its
		# top a raised panel pressed with a cross, a hinge along the back, a grab handle and padlocked hasp at the front
		var hatch: Vector3 = at.call(long_ * 0.72, -0.1)
		var v3 := func(x: float, y: float, z: float) -> Vector3: return hatch + Vector3(x, y, z)
		box_into(kit, v3.call(-0.44, 0, -0.44), v3.call(0.44, 0.08, 0.44), skin.darkened(0.12))
		box_into(kit, v3.call(-0.4, 0.08, -0.4), v3.call(0.4, 0.24, 0.4), Color("b8b2a6"))
		box_into(kit, v3.call(-0.47, 0.2, -0.47), v3.call(0.47, 0.27, 0.47), Color("8e979f"))
		box_into(kit, v3.call(-0.39, 0.27, -0.39), v3.call(0.39, 0.29, 0.39), Color("a6afb6"))
		box_into(kit, v3.call(-0.37, 0.29, -0.025), v3.call(0.37, 0.3, 0.025), Color("9aa3ab"))
		box_into(kit, v3.call(-0.025, 0.29, -0.37), v3.call(0.025, 0.3, 0.37), Color("9aa3ab"))
		var fwd := Vector3(0, 0, 1) if along_z else Vector3(1, 0, 0)
		var side := Vector3(1, 0, 0) if along_z else Vector3(0, 0, 1)
		var bar := func(c: Vector3, along: float, across: float, h0: float, h1: float, col: Color) -> void:  # a box centred on c, `along` wide across the hatch's front, `across` deep
			var hw: Vector3 = (side * along + fwd * across).abs() / 2
			box_into(kit, c - hw + Vector3(0, h0, 0), c + hw + Vector3(0, h1, 0), col)
		bar.call(hatch + fwd * 0.335, 0.6, 0.05, 0.29, 0.295, Color("d4dade"))  # sheen down the front of the panel
		bar.call(hatch - fwd * 0.475, 0.8, 0.05, 0.26, 0.3, Color("6d747b"))
		for k in [-1.0, 1.0]:
			bar.call(hatch + fwd * 0.43 + side * k * 0.12, 0.03, 0.03, 0.27, 0.33, Color("3f4349"))
		bar.call(hatch + fwd * 0.43, 0.27, 0.03, 0.32, 0.345, Color("3f4349"))
		bar.call(hatch + fwd * 0.41 + side * 0.25, 0.07, 0.07, 0.11, 0.21, Color("c9a24a"))
		# the vent stack: a pipe out of a flashing boot, under a rain cap on three straps that throws a shadow ring
		var vent: Vector3 = at.call(0.9 + r.randf_range(0.0, 0.5), minf(sz.x, sz.z) / 2 - 0.55)
		drum_into(kit, vent, 0.16, 0.05, skin.darkened(0.15), 10)
		drum_into(kit, vent + Vector3(0, 0.05, 0), 0.11, 0.08, Color("8a9097"), 10)
		drum_into(kit, vent + Vector3(0, 0.13, 0), 0.075, 0.47, Color("b9bec3"), 10)
		drum_into(kit, vent + Vector3(0, 0.56, 0), 0.085, 0.03, Color("9aa0a6"), 10)
		for k in 3:
			var a := TAU * k / 3.0 + 0.5
			var sp := vent + Vector3(cos(a) * 0.09, 0.59, sin(a) * 0.09)
			box_into(kit, sp - Vector3(0.012, 0, 0.012), sp + Vector3(0.012, 0.07, 0.012), Color("6e737d"))
		drum_into(kit, vent + Vector3(0, 0.66, 0), 0.19, 0.03, Color("767c85"), 12)
		drum_into(kit, vent + Vector3(0, 0.69, 0), 0.13, 0.03, Color("8a9098"), 12)
		casts.append([Rect2(hatch.x - 0.47, hatch.z - 0.47, 0.94, 0.94), Vector2(0.14, -0.24)])
		casts.append([Rect2(vent.x - 0.08, vent.z - 0.08, 0.16, 0.16), Vector2(0.3, -0.5)])
		casts.append([Rect2(vent.x - 0.19, vent.z - 0.19, 0.38, 0.38), Vector2(0.36, -0.6)])
		plane(set_node, Vector2(sz.x - 0.3, sz.z - 0.3), Vector3(e[1].x, y + 0.035, e[1].z),
				roof_mat(shop_roof_tex(Rect2(x0 + 0.15, z0 + 0.15, sz.x - 0.3, sz.z - 0.3), along_z, skin, Vector2(drain.x, drain.z), casts, branch.lot * 977 + int(e[1].x * 10.0))))
	commit([kit, faces], set_node)
	commit([drift], snow_cover)


## A rooftop AC condenser standing on `at`, size w x h x d, into a vertex-coloured kit surface and a surface of
## condenser(): an ivory casing under an overhanging lid, the round fan grille on its street side and the coil's
## fins behind a wire guard down its right side.
func condenser_into(kit: SurfaceTool, faces: SurfaceTool, at: Vector3, size_: Vector3) -> void:
	var hw := size_.x / 2
	var hd := size_.z / 2
	box_into(kit, at + Vector3(-hw + 0.04, 0, -hd + 0.04), at + Vector3(hw - 0.04, 0.05, hd - 0.04), Color("5f6166"))  # its feet
	box_into(kit, at + Vector3(-hw, 0.05, -hd), at + Vector3(hw, size_.y, hd), Color("d6d2c7"))
	box_into(kit, at + Vector3(-hw - 0.02, size_.y, -hd - 0.02), at + Vector3(hw + 0.02, size_.y + 0.03, hd + 0.02), Color("e4e1d8"))
	var y0 := at.y + 0.05
	var y1 := at.y + size_.y
	var zf := at.z + hd + 0.004
	add_quad(faces, [Vector3(at.x - hw, y1, zf), Vector3(at.x + hw, y1, zf), Vector3(at.x + hw, y0, zf), Vector3(at.x - hw, y0, zf)],
			[Vector2(0, 0), Vector2(0.625, 0), Vector2(0.625, 1), Vector2(0, 1)])
	var xs := at.x + hw + 0.004
	add_quad(faces, [Vector3(xs, y1, at.z + hd), Vector3(xs, y1, at.z - hd), Vector3(xs, y0, at.z - hd), Vector3(xs, y0, at.z + hd)],
			[Vector2(0.6667, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0.6667, 1)])


## The condenser's faces at 64 px a metre, in the tones box_into gives them: its front (u 0-0.625) a casing round a
## recessed fan grille of wire rings and spokes over the blades and hub, a badge and the valve cover beside it, rain
## run down from the lid; its side (u 0.667-1) the coil's fins behind a wire guard in a casing frame.
func condenser() -> StandardMaterial3D:
	if condenser_m:
		return condenser_m
	var r := RandomNumberGenerator.new()
	r.seed = 29
	var img := Image.create(96, 40, false, Image.FORMAT_RGB8)
	var cas := Color("d6d2c7")
	for py in 40:
		for px in 64:
			var c := cas
			var d := Vector2(px - 22.5, py - 20.5)
			var rr := d.length()
			if rr < 15.5:
				c = Color("2a2e34")
				if sin(3.0 * d.angle() + rr * 0.22) > 0.35 and rr > 4.0:
					c = Color("3e444b")  # the blades behind
				if rr < 3.5:
					c = Color("767c84") if d.x + d.y < 0.0 else Color("5c6168")
				elif fmod(rr, 3.0) < 0.9 or absi(px - 22) == 0 or absi(py - 20) == 0:
					c = Color("8d939a") if d.x + d.y < 4.0 else Color("737980")
			elif rr < 17.0:
				c = cas.darkened(0.22 if d.x + d.y > 0.0 else 0.08)  # the bezel recess, shaded on its lower right
			elif rr < 18.0 and d.x + d.y < 0.0:
				c = cas.lightened(0.18)
			else:
				if px >= 45 and px <= 58 and py >= 7 and py <= 10:
					c = Color("5d7088") if py > 7 else Color("7a8ca3")  # the maker's badge
				elif px >= 44 and px <= 60 and py >= 26 and py <= 36:
					c = cas.darkened(0.1)
					if px == 44 or py == 26:
						c = cas.darkened(0.24)
					elif px == 60 or py == 36:
						c = cas.lightened(0.1)
					elif px >= 49 and px <= 55 and (py == 30 or py == 32):
						c = Color("8a8b88")  # slots in the valve cover
				if py == 23 and px > 40:
					c = c.darkened(0.12)
				var streak := smoothstep(14.0, 39.0, py) * (0.1 if posmod(px * 7 + 3, 11) < 3 else 0.03)
				c = c.darkened(streak + r.randf_range(0.0, 0.025))
			if py < 2:
				c = c.darkened(0.3 - py * 0.12)  # the lid's shadow
			elif px == 0 or py == 39:
				c = c.darkened(0.2)
			elif px == 63:
				c = c.darkened(0.1)
			img.set_pixel(px, py, c * 0.9)
		for px in 32:
			var c := cas
			if px > 1 and px < 30 and py > 3 and py < 37:
				c = Color("7c8783") if px % 2 == 0 else Color("94a09c")  # the coil's fins
				c = c.darkened(smoothstep(4.0, 36.0, py) * 0.15)
				if py % 5 == 0:
					c = Color("b6babb")  # the guard's wires
				elif py % 5 == 1:
					c = c.darkened(0.25)
			elif py < 2:
				c = c.darkened(0.3 - py * 0.12)
			elif px <= 1 or py >= 37:
				c = c.darkened(0.08)
			img.set_pixel(64 + px, py, c * 0.75)
	img.generate_mipmaps()
	var m := mat(Color.WHITE, ImageTexture.create_from_image(img))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.texture_repeat = false
	condenser_m = m
	return m


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


## Where the made ground meets open water: a concrete quay wall with its coping, left open where a road runs on over a
## bridge. At its foot the water darkens with the wall's reflection, laps in a broken line of foam and pales off into
## the open water, as the city's seawalls do.
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
	var lap := surface(shore_mat)
	var box := func(p0: Vector3, p1: Vector3, col: Color) -> void: box_into(wall_, p0, p1, col)
	const T := 0.3  # the wall's thickness, inside the made ground's edge
	const TOP := 0.34
	const CAP := TOP - 0.07  # the coping's underside
	var rr := RandomNumberGenerator.new()
	rr.seed = 53
	for e in edges:
		var n: Vector2 = e[2]
		var lo := Vector2(minf(e[0].x, e[1].x), minf(e[0].y, e[1].y))
		var hi := Vector2(maxf(e[0].x, e[1].x), maxf(e[0].y, e[1].y))
		var d := (hi - lo).normalized()
		var L := lo.distance_to(hi)
		# the lap: bands out from the wall's face, the foam broken along it, each fading out short of other ground
		var cuts := maxi(1, roundi(L / 0.35))
		var froth := PackedFloat32Array()
		for k in cuts + 1:
			froth.append(maxf(0.0, rr.randf_range(-0.35, 0.95)))
		for band in [[0.0, 0.26, Color("2c4a56"), 0.85, 0.35], [0.26, 3.2, Color("8fd6d4"), 0.4, 0.0], [0.2, 0.42, Color("f4fbfb"), 1.0, 0.1]]:
			for k in cuts:
				var s := [L * k / cuts, L * (k + 1) / cuts]
				var v := []
				var al := []
				for j in 4:
					var sj: float = s[1 if j in [1, 2] else 0]
					var w: float = band[1 if j >= 2 else 0]
					var p := lo + d * sj + n * w
					v.append(Vector3(p.x, -0.135, p.y))
					var a: float = band[4 if j >= 2 else 3] * (froth[k + (1 if j in [1, 2] else 0)] if band[2] == Color("f4fbfb") else 1.0)
					al.append(a if open_water.call(lo + d * sj + n * (band[1] + 0.3)) else 0.0)
				for j in [0, 1, 2, 0, 2, 3]:
					lap.set_color(Color(band[2], al[j]))
					lap.add_vertex(v[j])
		# a box from s0 to s1 along the edge, w0 to w1 out toward the water (the wall's face at 0), y0 to y1
		var qb := func(s0: float, s1: float, w0: float, w1: float, y0: float, y1: float, col: Color) -> void:
			var a := lo + d * s0 + n * w0
			var b := lo + d * s1 + n * w1
			box.call(Vector3(minf(a.x, b.x), y0, minf(a.y, b.y)), Vector3(maxf(a.x, b.x), y1, maxf(a.y, b.y)), col)
		# the wall cast in 2 m bays, each a shade off, butted at a dark joint, weed-green above the wet tide line and
		# streaked where rain runs off the coping
		var bays := maxi(1, roundi(L / 2.0))
		for k in bays:
			var s0 := L * k / bays
			var s1 := L * (k + 1) / bays
			var tone := Color("c4bfb3").darkened(rr.randf_range(-0.03, 0.05))
			qb.call(s0, s1, -T, 0.0, -0.14, CAP, tone)
			if k > 0:
				qb.call(s0 - 0.012, s0 + 0.012, 0.0, 0.006, -0.14, CAP, tone.darkened(0.3))
			qb.call(s0, s1, 0.0, 0.008, 0.0, 0.05 + rr.randf_range(0.0, 0.05), tone.lerp(Color("6f7c5a"), 0.45))
			for j in rr.randi_range(1, 2):
				var sx := rr.randf_range(s0 + 0.2, s1 - 0.25)
				qb.call(sx, sx + rr.randf_range(0.04, 0.09), 0.0, 0.01, CAP - rr.randf_range(0.08, 0.2), CAP, tone.darkened(0.12))
		qb.call(0.0, L, -0.02, 0.02, -0.14, 0.0, Color("6c7069"))  # the wet tide line along its foot
		qb.call(0.0, L, 0.0, 0.012, CAP - 0.03, CAP, Color("8f8a80"))  # in the coping's shadow
		# the coping: precast 1 m blocks lipped out over the water, each a shade off, on grouted joints
		var blocks := maxi(1, roundi(L))
		for k in blocks:
			var s0 := L * k / blocks
			var s1 := L * (k + 1) / blocks
			qb.call(s0 + 0.008, s1 - 0.008, -T - 0.02, 0.04, CAP, TOP, Color("d8d3c8").darkened(rr.randf_range(-0.02, 0.05)))
			qb.call(s0 - 0.008, s0 + 0.008, -T - 0.01, 0.03, CAP, TOP - 0.012, Color("8a857b"))
		# the railing on the coping: posts every 2 m on base plates, a handrail over a foot rail and slim balusters
		var mid := -T / 2 - 0.01
		var posts := maxi(1, roundi(L / 2.0))
		for i in posts + 1:
			var s := clampf(L * i / posts, 0.04, L - 0.04)
			qb.call(s - 0.08, s + 0.08, mid - 0.08, mid + 0.08, TOP, TOP + 0.02, Color("4b5759"))
			qb.call(s - 0.035, s + 0.035, mid - 0.035, mid + 0.035, TOP, TOP + 0.84, Color("526466"))
		for k in floori(L / 0.2):
			var s := 0.1 + k * 0.2
			qb.call(s - 0.01, s + 0.01, mid - 0.01, mid + 0.01, TOP + 0.1, TOP + 0.78, Color("5b6e70"))
		qb.call(0.0, L, mid - 0.022, mid + 0.022, TOP + 0.08, TOP + 0.12, Color("526466"))
		qb.call(0.0, L, mid - 0.04, mid + 0.04, TOP + 0.78, TOP + 0.85, Color("93a3a5"))
		# a life ring in orange and white hung on long runs, on the railing's side toward the camera
		if L > 9.0:
			var s := L * floorf(posts / 2.0) / posts + 1.0
			var w := mid + 0.11 if n.dot(Vector2.ONE) > 0.0 else mid - 0.06
			for side in [[-0.22, -0.14, -0.22, 0.22], [0.14, 0.22, -0.22, 0.22], [-0.14, 0.14, -0.22, -0.14], [-0.14, 0.14, 0.14, 0.22]]:
				qb.call(s + side[0], s + side[1], w - 0.05, w, TOP + 0.45 + side[2], TOP + 0.45 + side[3], Color("ea6a2a"))
			for c in [Vector2(-0.18, 0.0), Vector2(0.18, 0.0), Vector2(0.0, -0.18), Vector2(0.0, 0.18)]:
				qb.call(s + c.x - 0.045, s + c.x + 0.045, w - 0.055, w + 0.005, TOP + 0.45 + c.y - 0.045, TOP + 0.45 + c.y + 0.045, Color("f4f1e8"))
	commit([lap, wall_], set_node)


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


## Water in the band z0..z1 between x0 and x1 (street frame), as runs 1 m deep on a 1 m grid. A cell counts as water
## if its middle or any corner is, so a shore running slant across a cell isn't left as a wedge of sea in the paving.
static func water_runs(town: Dictionary, o: Vector2, z0: float, z1: float, x0: float = SET.position.x, x1: float = SET.end.x) -> Array:
	var out := []
	var corners := func(zc: float) -> Array:
		var row := []
		var xc := x0
		while xc < x1 + 1.0:
			row.append(Sim.City.is_water(town, o + Vector2(minf(xc, x1), zc)))
			xc += 1.0
		return row
	var top: Array = corners.call(z0)
	var z := z0
	while z < z1:
		var h := minf(1.0, z1 - z)
		var bottom: Array = corners.call(z + h)
		var start := INF
		var x := x0
		var i := 0
		while x < x1:
			var wet: bool = top[i] or top[i + 1] or bottom[i] or bottom[i + 1] or Sim.City.is_water(town, o + Vector2(x + 0.5, z + h / 2))
			if wet and start == INF:
				start = x
			elif not wet and start < INF:
				out.append(Rect2(start, z, x - start, h))
				start = INF
			x += 1.0
			i += 1
		if start < INF:
			out.append(Rect2(start, z, x1 - start, h))
		top = bottom
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
	stair_house(parent, Vector3(span.x + 1.4, 4.2, -14.9), not rv.defeated)
	skylights(parent, [span.x + 3.2, span.x + 5.8], not rv.defeated)
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var kit := surface(km)
	var faces := surface(condenser())
	# the parapet, its walls under a pale coping that overhangs them both ways
	for pr in [[span.x, -7.4, span.y, -7.2], [span.x, -16.2, span.y, -16.0], [span.x, -16.2, span.x + 0.2, -7.2], [span.y - 0.2, -16.2, span.y, -7.2]]:
		box_into(kit, Vector3(pr[0], 4.2, pr[1]), Vector3(pr[2], 4.48, pr[3]), Color("e6e2d8"))
		box_into(kit, Vector3(pr[0] - 0.03, 4.48, pr[1] - 0.03), Vector3(pr[2] + 0.03, 4.55, pr[3] + 0.03), Color("f6f3ec"))
	for k in 3:
		var ac := Vector3(span.x + 4.2 + k * 1.6, 4.25, -14.4)
		box_into(kit, ac + Vector3(-0.625, 0, -0.525), ac + Vector3(0.625, 0.1, 0.525), Color("8e8d88"))
		condenser_into(kit, faces, ac + Vector3(0, 0.1, 0), Vector3(1.05, 0.6, 0.85))
		box_into(kit, ac + Vector3(0.25, 0.05, -0.425), ac + Vector3(0.35, 0.15, -1.175), Color("c9c6bd"))
	commit([kit, faces], parent)
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
	if parent == set_node:
		rival_canopy(parent, rv, w, cx, c)
		sale = null if rv.defeated else sale_display(rv, span)
	else:
		var awning := block(parent, Vector3(w, 0.12, 0.9), Vector3(cx, 2.85, -6.7), c.lightened(0.15))
		if not rv.defeated:
			light_up(awning, 0.5)
	if not rv.defeated and parent == set_node:
		var mull: Array[float] = [rv.x - 0.72, rv.x, rv.x + 0.72]
		var mx := span.x + 0.4
		while mx < span.y - 0.3:
			if absf(mx - rv.x) > 0.8:
				mull.append(mx)
			mx += 2.0
		rival_spill_mat.albedo_texture = front_spill_tex(span.x + 0.4, span.y - 0.4, span.x - 0.8, w + 1.6, rv.x, mull, 0.25)
		spill(parent, cx, w + 1.6, -7.05, rival_spill_mat)
	elif not rv.defeated:
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


## The stair house on the rival's roof, footprint 1.8 x 1.6 m from `at` on the membrane, in one mesh: plastered walls
## jointed in panels over the membrane turned up their foot under a metal bar, grimed under an overhanging slab whose
## lip throws a shadow line; a steel door in a frame with a louvre, kick plate, lever and staff-only plate, up a step
## under a hood and a bulkhead lamp that lights after dark; a louvred vent and a downpipe down the sunny side.
func stair_house(parent: Node3D, at: Vector3, lit: bool) -> void:
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var st := surface(km)
	var b := func(p0: Vector3, p1: Vector3, col: Color) -> void:
		box_into(st, at + p0, at + p1, col)
	var wall := Color("dedad0")
	var skin := Color(Sim.City.FLAT_ROOFS[4]).darkened(0.12)
	b.call(Vector3(-0.9, 0, -0.8), Vector3(0.9, 1.2, 0.8), wall)
	b.call(Vector3(-0.905, 1.04, -0.805), Vector3(0.905, 1.2, 0.805), wall.darkened(0.1))  # grime under the slab
	b.call(Vector3(-0.93, 0, -0.83), Vector3(0.93, 0.16, 0.83), skin)
	b.call(Vector3(-0.935, 0.16, -0.835), Vector3(0.935, 0.185, 0.835), Color("c3c7ca"))
	for z in [-0.28, 0.26]:
		b.call(Vector3(0.9, 0.19, z - 0.012), Vector3(0.907, 1.04, z + 0.012), wall.darkened(0.16))
	b.call(Vector3(-0.462, 0.19, 0.8), Vector3(-0.438, 1.04, 0.807), wall.darkened(0.16))
	b.call(Vector3(-0.96, 1.17, -0.86), Vector3(0.96, 1.2, 0.86), Color("6f6c66"))  # the shadow line under its lip
	b.call(Vector3(-0.98, 1.2, -0.88), Vector3(0.98, 1.3, 0.88), Color("cfcbc1"))
	b.call(Vector3(-0.94, 1.3, -0.84), Vector3(0.94, 1.31, 0.84), skin.lightened(0.08))  # coated like the roof below
	for x in [-0.32, 0.32]:
		b.call(Vector3(x - 0.012, 1.31, -0.84), Vector3(x + 0.012, 1.315, 0.84), skin.darkened(0.12))
	b.call(Vector3(-0.98, 1.3, -0.88), Vector3(0.98, 1.34, -0.84), Color("cfcbc1"))
	b.call(Vector3(-0.98, 1.3, -0.88), Vector3(-0.94, 1.34, 0.88), Color("cfcbc1"))
	b.call(Vector3(-0.98, 1.3, 0.84), Vector3(0.98, 1.34, 0.88), Color("ebe7dd"))  # its upturned lip, lit
	b.call(Vector3(0.94, 1.3, -0.88), Vector3(0.98, 1.34, 0.88), Color("e4e0d6"))
	b.call(Vector3(-0.6, 1.31, -0.5), Vector3(-0.38, 1.52, -0.28), Color("9aa0a6"))  # a vent cowl
	b.call(Vector3(-0.64, 1.52, -0.54), Vector3(-0.34, 1.56, -0.24), Color("6e737d"))
	b.call(Vector3(-0.38, 1.31, -0.5), Vector3(-0.2, 1.312, -0.28), skin.darkened(0.25))  # and its shadow
	# the door: frame, leaf lit along its closing edge, a louvre and kick plate, lever, a staff-only plate
	b.call(Vector3(-0.08, 0.185, 0.8), Vector3(0.68, 1.06, 0.83), Color("5e6670"))
	b.call(Vector3(-0.03, 0.185, 0.8), Vector3(0.63, 1.01, 0.845), Color("8c95a0"))
	b.call(Vector3(-0.03, 0.185, 0.845), Vector3(0.0, 1.01, 0.848), Color("a9b1ba"))
	b.call(Vector3(0.02, 0.185, 0.845), Vector3(0.61, 0.28, 0.852), Color("b4bbc2"))
	for k in 4:
		var y := 0.36 + k * 0.055
		b.call(Vector3(0.12, y, 0.845), Vector3(0.48, y + 0.03, 0.858), Color("6c747e"))
	b.call(Vector3(0.02, 0.6, 0.845), Vector3(0.06, 0.66, 0.86), Color("b9b6ae"))
	b.call(Vector3(0.02, 0.62, 0.86), Vector3(0.17, 0.645, 0.885), Color("e2dfd8"))
	b.call(Vector3(0.18, 0.74, 0.845), Vector3(0.48, 0.88, 0.85), Color("f4f1e8"))
	b.call(Vector3(0.18, 0.845, 0.85), Vector3(0.48, 0.88, 0.852), Color("c8423a"))
	b.call(Vector3(-0.12, 1.06, 0.8), Vector3(0.72, 1.1, 1.08), Color("b9b5ab"))  # its hood
	b.call(Vector3(-0.12, 1.1, 1.05), Vector3(0.72, 1.12, 1.08), Color("d6d2c8"))
	b.call(Vector3(-0.12, 0, 0.83), Vector3(0.72, 0.12, 1.14), Color("b8b3a8"))  # the step, lit along its nose
	b.call(Vector3(-0.12, 0.12, 1.1), Vector3(0.72, 0.125, 1.14), Color("d7d2c6"))
	b.call(Vector3(-0.38, 0.86, 0.8), Vector3(-0.2, 1.0, 0.83), Color("8f8c85"))
	# the sunny side: a louvred vent and a downpipe from the slab to a shoe on the membrane
	b.call(Vector3(0.9, 0.62, -0.62), Vector3(0.915, 0.98, -0.02), Color("9aa0a6"))
	for k in 5:
		var y := 0.66 + k * 0.064
		b.call(Vector3(0.915, y, -0.58), Vector3(0.935, y + 0.032, -0.06), Color("70767f"))
	b.call(Vector3(0.91, 0.16, 0.6), Vector3(0.98, 1.2, 0.67), Color("b4b1a9"))
	b.call(Vector3(0.91, 0.04, 0.58), Vector3(1.1, 0.1, 0.69), Color("a19e96"))
	commit([st], parent)
	var lens := block(parent, Vector3(0.16, 0.11, 0.06), at + Vector3(-0.29, 0.93, 0.86), Color("fff3cf"))
	if lit:
		light_up(lens, 1.0)
		if parent == set_node:
			plane(parent, Vector2(2.0, 2.0), at + Vector3(-0.1, 0.07, 1.4), pool_mat)


## A price war's dressing on the rival's front: nobori, tall cloth banners on poles in weighted bases, in red and yellow
## turn about with SALE down each, stood along the glass either side of the door, and a SALE poster on the glass
## beside the door each way, lit from behind after dark.
func sale_display(rv: Dictionary, span: Vector2) -> Node3D:
	var node := Node3D.new()
	node.visible = false
	set_node.add_child(node)
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var st := surface(km)
	var red := Color("dd3a2c")
	var yellow := Color("f6cf3c")
	var font: Font = bold if bold else get_theme_default_font()
	var words := func(text: String, at: Vector3, ink: Color, px: float) -> void:
		var l := Label3D.new()
		l.text = text
		l.font = font
		l.font_size = 64
		l.outline_size = 0
		l.pixel_size = px
		l.line_spacing = -14.0
		l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		l.position = at
		l.modulate = ink * light
		lit_mats.append([weakref(l), ink, 0.0])
		node.add_child(l)
	const Z := -6.45
	var k := 0
	var x := span.x + 1.1
	while x < span.y - 0.8:
		if absf(x - rv.x) > 1.4:
			var cloth := red if k % 2 == 0 else yellow
			var ink := yellow if k % 2 == 0 else red
			box_into(st, Vector3(x - 0.2, 0, Z - 0.2), Vector3(x + 0.2, 0.16, Z + 0.2), Color("4a4b50"))  # the base, filled with water
			box_into(st, Vector3(x - 0.14, 0.16, Z - 0.14), Vector3(x + 0.14, 0.2, Z + 0.14), Color("5c5d62"))
			box_into(st, Vector3(x - 0.02, 0.2, Z - 0.02), Vector3(x + 0.02, 2.42, Z + 0.02), Color("d9d6cf"))
			box_into(st, Vector3(x, 2.33, Z - 0.015), Vector3(x + 0.62, 2.36, Z + 0.015), Color("d9d6cf"))  # the bar it hangs from
			box_into(st, Vector3(x + 0.03, 0.55, Z - 0.005), Vector3(x + 0.6, 2.33, Z + 0.005), cloth)
			box_into(st, Vector3(x + 0.03, 0.55, Z + 0.005), Vector3(x + 0.08, 2.33, Z + 0.008), cloth.darkened(0.2))  # the loops round the pole
			box_into(st, Vector3(x + 0.08, 2.14, Z + 0.005), Vector3(x + 0.6, 2.24, Z + 0.008), Color("fbfaf5"))
			box_into(st, Vector3(x + 0.08, 0.62, Z + 0.005), Vector3(x + 0.6, 0.68, Z + 0.008), Color("fbfaf5"))
			words.call("S\nA\nL\nE", Vector3(x + 0.34, 1.4, Z + 0.012), ink, 0.0052)
			cast(node, Vector2(x + 0.3, Z), 0.55, 2.33, 0.57)
			blob(node, Vector2(x, Z), 0.22)
			k += 1
		x += 2.1
	commit([st], node)
	# a poster on the glass either side of the door
	for dx in [-1.75, 1.75]:
		var px: float = rv.x + dx
		if px - 0.5 < span.x + 0.3 or px + 0.5 > span.y - 0.3:
			continue
		var paper := Image.create(1, 12, false, Image.FORMAT_RGB8)
		paper.fill(red)
		for y in [0, 11]:
			paper.set_pixel(0, y, yellow)
		var pm := art_panel(node, paper, Vector2(1.0, 0.62), Vector3(px, 1.62, -6.985), Color.WHITE, 1.0, false)
		light_up(pm, 0.9)
		words.call("SALE", Vector3(px, 1.62, -6.98), Color.WHITE, 0.0058)
		lit_mats[-1][2] = 1.0
	return node


## The canopy over the rival's glass, 20 px a metre: standing-seam sheet in the chain's colour, each pan a shade off
## with its rib lit on the sun's side, grime along the wall; a gutter lip at the front with a white pinstripe that
## lights after dark over a dark drip edge; and its sun shadow down the top of the glazing.
func rival_canopy(parent: Node3D, rv: Dictionary, w: float, cx: float, c: Color) -> void:
	block(parent, Vector3(w, 0.1, 0.9), Vector3(cx, 2.85, -6.7), c.darkened(0.15))
	var pw := int(w * 20)
	var sheet := Image.create(pw, 16, false, Image.FORMAT_RGB8)
	var base := c.lightened(0.1)
	for x in pw:
		var tone := base.darkened(0.03 * ((floori(x / 8.0) * 7 + int(rv.x)) % 3))
		for y in 16:
			var px := tone
			if x % 8 == 0:
				px = base.lightened(0.35)
			elif x % 8 == 1:
				px = base.darkened(0.25)
			if y < 2:
				px = px.darkened(0.2 - 0.08 * y)
			elif y == 15:
				px = px.darkened(0.1)
			sheet.set_pixel(x, y, px)
	sheet.generate_mipmaps()
	var top := mat(Color.WHITE, ImageTexture.create_from_image(sheet))
	top.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	top.texture_repeat = false
	plane(parent, Vector2(w, 0.8), Vector3(cx, 2.902, -6.74), top)
	if not rv.defeated:
		light_up(top, 0.45)
	block(parent, Vector3(w + 0.04, 0.3, 0.08), Vector3(cx, 2.9, -6.25), c)
	var band := Image.create(1, 9, false, Image.FORMAT_RGB8)
	band.fill(c)
	band.set_pixel(0, 0, c.lightened(0.3))
	for y in [3, 4]:
		band.set_pixel(0, y, Color.WHITE)
	band.set_pixel(0, 8, c.darkened(0.45))
	var face := art_panel(parent, band, Vector2(w + 0.04, 0.3), Vector3(cx, 2.9, -6.208), Color.WHITE, 1.0, false)
	if not rv.defeated:
		light_up(face, 1.0)
	var sh := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w - 0.6, 1.6)
	sh.mesh = q
	sh.material_override = awning_mat
	sh.position = Vector3(cx + 0.2, 1.99, -6.955)
	parent.add_child(sh)


## The chain's lightbox on its fascia: an aluminium cabinet standing proud of the fascia, its returns and a top cap
## catching the light round a frame banded in the chain's colour at its foot, the face a cream sheet lit unevenly by
## the tubes behind it, with its mascot's head in a roundel ringed in the chain's colour and its name beside it. After
## dark the face glows and spills white onto the fascia round it; a beaten chain's goes grey and dark.
func rival_sign(parent: Node3D, rv: Dictionary, cx: float, c: Color) -> void:
	var font: Font = bold if bold else get_theme_default_font()
	var label := Label3D.new()
	label.text = Sim.RIVALS[rv.id].name
	label.font = font
	label.font_size = 128
	label.outline_size = 0
	label.pixel_size = 0.0036
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tw := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 128).x * label.pixel_size
	var pw := tw + 1.7
	var x0 := cx - pw / 2
	var x1 := x0 + pw
	var cream := Color("cfccc4") if rv.defeated else Color("fbfaf5")
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var kit := surface(km)
	var alu := Color("c9cdd1")
	box_into(kit, Vector3(x0 - 0.05, 3.25, -7.1), Vector3(x1 + 0.05, 4.03, -6.93), Color("9da2a8"))  # the cabinet, its returns
	box_into(kit, Vector3(x0 - 0.07, 4.0, -7.1), Vector3(x1 + 0.07, 4.05, -6.9), alu.lightened(0.15))  # the top cap
	box_into(kit, Vector3(x0 - 0.05, 3.95, -6.93), Vector3(x1 + 0.05, 4.0, -6.885), alu)
	for sx: float in [x0 - 0.05, x1 - 0.01]:
		box_into(kit, Vector3(sx, 3.31, -6.93), Vector3(sx + 0.06, 3.95, -6.885), alu.darkened(0.06))
	box_into(kit, Vector3(x0 - 0.06, 3.25, -6.93), Vector3(x1 + 0.06, 3.31, -6.88), c.darkened(0.2))  # the chain's band at its foot
	box_into(kit, Vector3(x0 - 0.04, 3.2, -7.1), Vector3(x1 + 0.04, 3.25, -7.0), c.darkened(0.5))  # its shadow line on the fascia
	commit([kit], parent)
	var sheet := Image.create(128, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		var v := (y + 0.5) / 32.0
		var tubes := 0.035 * pow(maxf(0.0, cos((v - 0.5) * 3.0 * TAU)), 6.0)  # three tubes behind the face
		for x in 128:
			var u := (x + 0.5) / 128.0
			var edge := minf(minf(u, 1.0 - u) * pw, minf(v, 1.0 - v) * 0.64)
			var k := 0.96 + 0.04 * sin(v * PI) + tubes - 0.07 * (1.0 - smoothstep(0.0, 0.07, edge))
			sheet.set_pixel(x, y, Color(cream.r * k, cream.g * k, cream.b * k))
	var plate := art_panel(parent, sheet, Vector2(pw, 0.64), Vector3(cx, 3.63, -6.906), Color.WHITE, 1.0, false)
	var face: Image = (load("res://art/walk.png") as Texture2D).get_image().get_region(
			Rect2i(4, (WALK_ROW.mascot + Sim.RIVALS.keys().find(rv.id)) * PERSON.y, 64, 54))
	face.convert(Image.FORMAT_RGBA8)
	face.resize(96, 80, Image.INTERPOLATE_LANCZOS)
	var disc := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(64, 64))
			var px := cream.lerp(c, clampf(62.5 - d, 0.0, 1.0)).lerp(cream.lightened(0.3), clampf(53.5 - d, 0.0, 1.0))
			if d < 54.0 and x >= 16 and x < 112 and y >= 24 and y < 104:
				var f := face.get_pixel(x - 16, y - 24)
				if rv.defeated:
					f = Color(f.get_luminance(), f.get_luminance(), f.get_luminance(), f.a)
				px = px.lerp(Color(f.r, f.g, f.b), f.a)
			disc.set_pixel(x, y, px)
	var roundel := art_panel(parent, disc, Vector2(0.6, 0.6), Vector3(x0 + 0.52, 3.63, -6.9), Color.WHITE, 1.0, false)
	label.position = Vector3(x0 + 1.05 + tw / 2, 3.62, -6.895)
	parent.add_child(label)
	var ink := c.darkened(0.15)
	label.modulate = ink * light
	lit_mats.append([weakref(label), ink, 0.0])
	if not rv.defeated:
		light_up(plate, 1.3)  # past 1 so the plate reads white before full night
		light_up(roundel, 1.3)
		lit_mats[-1][2] = 1.3
		var gm := sign_glow_mat.duplicate()
		gm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		gm.albedo_texture = fascia_glow_tex
		gm.albedo_color = Color(0, 0, 0, 0)
		fascia_glows.append([weakref(gm), Color(1.0, 0.97, 0.88, 0.85)])
		var glow := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(pw * 1.45 + 0.4, 2.4)
		glow.mesh = q
		glow.material_override = gm
		glow.position = Vector3(cx, 3.62, -6.97)
		parent.add_child(glow)


## The rival's two skylights over the shop floor, in one mesh: a kerb upstand with the membrane turned up its foot under
## an aluminium frame, and a hipped lantern of glass on it, each slope a tone apart, its hips and ridge capped in
## aluminium. After dark (unless the chain is beaten) the shop's light glows up through it.
func skylights(parent: Node3D, xs: Array, lit: bool) -> void:
	var km := mat(Color.WHITE)
	km.vertex_color_use_as_albedo = true
	km.vertex_color_is_srgb = true
	var kit := surface(km)
	var sm := skylight_mats()
	var glass := surface(sm[0 if lit else 2])
	var alu := Color("c9ced2")
	var bar := func(a: Vector3, b: Vector3) -> void:
		var side := (b - a).cross(Vector3.UP).normalized() * 0.022
		if side.length() < 0.01:
			side = Vector3(0.022, 0, 0)
		kit.set_color(alu)
		add_quad(kit, [a - side, a + side, b + side, b - side].map(func(v): return v + Vector3(0, 0.012, 0)), [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	for sx: float in xs:
		var c := Vector3(sx, 0, -10.0)
		box_into(kit, c + Vector3(-0.98, 4.24, -0.68), c + Vector3(0.98, 4.3, 0.68), Color("aeaba2"))
		box_into(kit, c + Vector3(-0.95, 4.24, -0.65), c + Vector3(0.95, 4.5, 0.65), Color("d6d3ca"))
		box_into(kit, c + Vector3(-0.93, 4.5, -0.63), c + Vector3(0.93, 4.56, 0.63), alu)
		var e := 4.56
		var r := 4.86
		var hx := 0.86
		var hz := 0.56
		var rx := 0.3
		var p := [c + Vector3(-hx, e, hz), c + Vector3(hx, e, hz), c + Vector3(hx, e, -hz), c + Vector3(-hx, e, -hz)]
		var q := [c + Vector3(-rx, r, 0), c + Vector3(rx, r, 0)]
		var u0 := (hx - rx) / (2 * hx)
		glass.set_color(Color(0.96, 0.96, 0.96))  # toward the street, catching the sky
		add_quad(glass, [p[0], p[1], q[1], q[0]], [Vector2(0, 1), Vector2(1, 1), Vector2(1 - u0, 0), Vector2(u0, 0)])
		glass.set_color(Color(0.72, 0.72, 0.72))
		add_quad(glass, [p[2], p[3], q[0], q[1]], [Vector2(0, 1), Vector2(1, 1), Vector2(1 - u0, 0), Vector2(u0, 0)])
		glass.set_color(Color(0.88, 0.88, 0.88))  # the hip ends, the sunny one lighter
		add_quad(glass, [p[3], p[0], q[0], q[0]], [Vector2(0.18, 1), Vector2(0.82, 1), Vector2(0.5, 0), Vector2(0.5, 0)])
		glass.set_color(Color(0.66, 0.66, 0.66))
		add_quad(glass, [p[1], p[2], q[1], q[1]], [Vector2(0.18, 1), Vector2(0.82, 1), Vector2(0.5, 0), Vector2(0.5, 0)])
		for k in 4:
			bar.call(p[k], q[0] if k == 0 or k == 3 else q[1])
		box_into(kit, q[0] + Vector3(-0.03, -0.01, -0.035), q[1] + Vector3(0.03, 0.035, 0.035), alu)
		if lit:
			plane(parent, Vector2(3.0, 2.4), c + Vector3(0, 4.58, 0), sm[1])
	commit([kit, glass], parent)


## The skylight glass, 40 px a metre across a slope (the glow 8): [panes between glazing bars running up the slope, the
## sky reflected darker toward the eaves with a sheen across them, lit from below after dark; the shop's cool light
## glowing out round the kerb].
func skylight_mats() -> Array:
	if skylight_pair.size() == 3 and skylight_pair.all(func(w): return w.get_ref() != null):
		return skylight_pair.map(func(w): return w.get_ref())
	var glass := Image.create(64, 24, false, Image.FORMAT_RGB8)
	for y in 24:
		for x in 64:
			var c := Color("a9c8d8").lerp(Color("4f7890"), y / 23.0)
			var s := posmod(x - 2 * y, 40)
			if s < 6:
				c = c.lerp(Color("e4f1f6"), 0.45 if s > 1 and s < 5 else 0.25)
			if x % 16 == 0:
				c = Color("b8bec2")
			elif x % 16 == 1:
				c = c.darkened(0.25)  # the bar's shadow on the pane
			glass.set_pixel(x, y, c)
	glass.generate_mipmaps()
	var gt := ImageTexture.create_from_image(glass)
	var gms := []
	for k in 2:  # lit from below, and a beaten chain's left dark
		var gm := mat(Color.WHITE, gt)
		gm.vertex_color_use_as_albedo = true
		gm.vertex_color_is_srgb = true
		gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		gm.texture_repeat = false
		if k == 0:
			light_up(gm, 1.0)
		gms.append(gm)
	var mask := Image.create(24, 18, false, Image.FORMAT_RGBA8)
	for y in 18:
		for x in 24:
			var d := Vector2(maxf(absf(x - 11.5) - 7.5, 0), maxf(absf(y - 8.5) - 4.5, 0)).length()
			mask.set_pixel(x, y, Color(1, 1, 1, 0.8 * pow(clampf(1.0 - d / 4.0, 0.0, 1.0), 2.0)))
	var lm: StandardMaterial3D = sign_glow_mat.duplicate()
	lm.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	lm.albedo_texture = ImageTexture.create_from_image(mask)
	lm.albedo_color = SHOP_LIGHT * Color(1, 1, 1, 0.85 * night)
	fascia_glows.append([weakref(lm), SHOP_LIGHT])
	skylight_pair = [weakref(gms[0]), weakref(lm), weakref(gms[1])]
	return [gms[0], lm, gms[1]]


## The rival's roof as the city's flat roofs are drawn, kept tidier than the vacant unit's: a coating in strips across its
## depth, each a shade off with a grit speckle, faint grime and rain streaks running down to the drain in the front corner
## with a damp stain round it, the parapets' shadow along its sunny sides, a walkway of concrete pads each a shade apart,
## a dark seam round the hatch, skylights and AC units and each one's shadow away from the sun. 10 px a metre, street frame.
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
		casts.append([Rect2(span.x + 2.25 + k * 2.6, -10.65, 1.9, 1.3), Vector2(0.22, -0.38)])
	for k in 3:
		casts.append([Rect2(span.x + 3.575 + k * 1.6, -14.925, 1.25, 1.05), Vector2(0.25, -0.42)])
	var walk := Rect2(span.x + 1.6, -13.8, span.y - span.x - 2.2, 0.8)
	var pads := []
	for k in int(walk.size.x / 0.6) + 1:
		pads.append(r.randf_range(0.92, 1.06))
	var gw := int(iw / 10.0) + 2
	var grime := []
	for k in gw * 10:
		grime.append(r.randf())
	var streaks := []  # rain runs toward the front, every 0.1 m a strength
	for k in iw:
		streaks.append(r.randf() if r.randf() < 0.3 else 0.0)
	var drain := Vector2(span.y - 0.8, -7.95)
	var base := Color(Sim.City.FLAT_ROOFS[4])  # a teal coating
	var pad := Color("c9c6bd")
	var img := Image.create(iw, ih, false, Image.FORMAT_RGB8)
	for j in ih:
		var z := -16.0 + (j + 0.5) / 10.0
		var u := (j + 0.5) / 12.0
		var lane: float = lanes[int(u) % lanes.size()] * (0.8 if j % 12 == 0 else (1.09 if j % 12 == 1 else 1.0))  # each lap's lip lit
		for i in iw:
			var x := x0 + (i + 0.5) / 10.0
			var gx := x - x0
			var gz := z + 16.0
			var cx := int(gx)
			var cz := int(gz)
			var tx := smoothstep(0.0, 1.0, gx - cx)
			var tz := smoothstep(0.0, 1.0, gz - cz)
			var g := lerpf(lerpf(grime[(cz % 10) * gw + cx], grime[(cz % 10) * gw + cx + 1], tx),
					lerpf(grime[((cz + 1) % 10) * gw + cx], grime[((cz + 1) % 10) * gw + cx + 1], tx), tz)
			var f: float = lane * lerpf(0.93, 1.03, g) * (1.0 - streaks[i] * 0.12 * smoothstep(0.0, 8.6, gz))
			var h := r.randf()
			if h < 0.04:
				f *= 0.9
			elif h < 0.07:
				f *= 1.06
			var col := base
			if walk.has_point(Vector2(x, z)):
				var wi := int((x - walk.position.x) / 0.6)
				var wu := fmod(x - walk.position.x, 0.6)
				col = pad
				f = pads[wi] * lerpf(0.95, 1.02, g) * (0.9 if h < 0.04 else 1.0)
				if wu < 0.1 or z - walk.position.y < 0.1:
					f *= 0.72  # the gap between pads, and the shade along its far edge
				elif walk.end.y - z < 0.1:
					f *= 1.08
			# the parapet: dimming the membrane toward its foot all round, its shadow a soft band along the sunny sides
			var rx := iw / 10.0 - gx
			var rz := 8.6 - gz
			for d in [gx, rx, gz, rz]:
				f *= lerpf(0.8, 1.0, smoothstep(0.0, 0.9, d))
			f *= lerpf(0.62, 1.0, minf(smoothstep(0.1, 0.26, gx), smoothstep(0.18, 0.38, rz)))
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
			img.set_pixel(i, j, Color(col.r * f, col.g * f, col.b * f))
	img.generate_mipmaps()
	roof_texs[iw] = ImageTexture.create_from_image(img)
	return roof_mat(roof_texs[iw])


## The vacant unit's roof, left to weather: membrane strips lapped every 1.4 m, each a shade off and mottled with grime,
## tide-marked stains where rain has ponded, a patch of newer membrane, dimming toward the parapet's foot all round under
## its shadow along the sunny sides, a dark seam round the tank's legs, AC units and vent stack and each one's shadow away
## from the sun. 10 px a metre, street frame.
func vacant_roof(xl: float, vw: float) -> StandardMaterial3D:
	var iw := roundi((vw - 0.4) * 10.0)
	if -iw in roof_texs:
		return roof_mat(roof_texs[-iw])
	var ih := 84
	var x0 := xl + 0.2
	var r := RandomNumberGenerator.new()
	r.seed = 17
	var gw := int(vw) + 2
	var grime := []
	for k in gw * 10:
		grime.append(r.randf())
	var lanes := []
	for k in 7:
		lanes.append(r.randf_range(0.9, 1.03))
	var casts := []  # footprint, shadow offset (street frame), round
	for lg in [Vector2(-0.45, -0.45), Vector2(0.45, -0.45), Vector2(-0.45, 0.45), Vector2(0.45, 0.45)]:
		casts.append([Rect2(xl + 1.0 + lg.x - 0.04, -14.9 + lg.y - 0.04, 0.08, 0.08), Vector2.ZERO, false])
	casts.append([Rect2(xl + 0.5, -15.4, 1.0, 1.0), Vector2(0.62, -1.05), true])  # the tank, up on its frame
	for k in 2:
		casts.append([Rect2(xl + 0.35 + k * 1.4, -12.0, 1.1, 0.8), Vector2(0.24, -0.4), false])
	casts.append([Rect2(xl + vw - 0.79, -9.29, 0.18, 0.18), Vector2(0.3, -0.5), false])  # the vent stack
	casts.append([Rect2(xl + 2.25, -14.85, 0.1, 3.1), Vector2(0.05, -0.08), false])  # their pipe
	var ponds := [[Vector2(x0 + (vw - 0.4) * 0.62, -10.4), 0.9], [Vector2(x0 + (vw - 0.4) * 0.35, -8.6), 0.6]]
	var patch := Rect2(x0 + (vw - 0.4) * 0.5, -14.6, 1.6, 1.1)
	var base := Color(Sim.City.FLAT_ROOFS[2])
	var img := Image.create(iw, ih, false, Image.FORMAT_RGB8)
	for j in ih:
		var z := -15.95 + (j + 0.5) / 10.0
		var u := (j + 0.5) / 14.0
		var f0: float = lanes[int(u) % lanes.size()]
		if j % 14 == 0:
			f0 *= 0.8  # the lap
		elif j % 14 == 1:
			f0 *= 1.06
		for i in iw:
			var x := x0 + (i + 0.5) / 10.0
			var gx := x - x0
			var gz := z + 15.95
			var cx := int(gx)
			var cz := int(gz)
			var tx := smoothstep(0.0, 1.0, gx - cx)
			var tz := smoothstep(0.0, 1.0, gz - cz)
			var g := lerpf(lerpf(grime[(cz % 10) * gw + cx], grime[(cz % 10) * gw + cx + 1], tx),
					lerpf(grime[((cz + 1) % 10) * gw + cx], grime[((cz + 1) % 10) * gw + cx + 1], tx), tz)
			var f := f0 * lerpf(0.9, 1.02, g)
			if posmod(i * 7 + j * 13, 23) == 0:
				f *= 0.93
			if patch.has_point(Vector2(x, z)):
				f = f0 * (0.82 if patch.grow(-0.1).has_point(Vector2(x, z)) else 0.72)
			for pd in ponds:
				var d: float = Vector2((x - pd[0].x) * 0.8, z - pd[0].y).length() / pd[1] * lerpf(0.85, 1.15, g)
				if d < 0.88:
					f *= lerpf(0.9, 0.96, smoothstep(0.0, 0.88, d))  # darkest where it pooled deepest
				elif d < 1.0:
					f *= 0.88  # a tide mark round its rim
				elif d < 1.15:
					f *= 1.03
			# the parapet: dimming the membrane toward its foot all round, its shadow a soft band along the sunny sides
			var rx := iw / 10.0 - gx
			var rz := ih / 10.0 - gz
			for d in [gx, rx, gz, rz]:
				f *= lerpf(0.8, 1.0, smoothstep(0.0, 0.9, d))
			f *= lerpf(0.62, 1.0, minf(smoothstep(0.1, 0.26, gx), smoothstep(0.18, 0.38, rz)))
			for c in casts:
				var at: Rect2 = c[0]
				var p: Vector2 = Vector2(x, z) - c[1]
				var hit: bool = (p.distance_to(at.get_center()) < at.size.x / 2 - 0.05) if c[2] else at.grow(-0.03).has_point(p)
				if hit:
					f *= 0.72
					break
				var out := Vector2(maxf(maxf(at.position.x - x, x - at.end.x), 0.0), maxf(maxf(at.position.y - z, z - at.end.y), 0.0))
				if not c[2] and out.length() < 0.2:
					f *= lerpf(0.78, 1.0, out.length() / 0.2)
					break
			img.set_pixel(i, j, Color(base.r * f, base.g * f, base.b * f))
	img.generate_mipmaps()
	roof_texs[-iw] = ImageTexture.create_from_image(img)
	return roof_mat(roof_texs[-iw])


## A one-floor shop's membrane, rect in the street frame: strips 1 m wide across its length lapped at each seam, each a
## shade off and mottled with grime, rain streaking toward the drain with a damp stain round it, a tide-marked pond, the
## parapets' shadow along its sunny sides, and a dark seam round each fitting and its shadow away from the sun. 10 px a metre.
func shop_roof_tex(rect: Rect2, along_z: bool, base: Color, drain: Vector2, casts: Array, sd: int) -> ImageTexture:
	var iw := roundi(rect.size.x * 10.0)
	var ih := roundi(rect.size.y * 10.0)
	var r := RandomNumberGenerator.new()
	r.seed = sd
	var lanes := []
	for k in 16:
		lanes.append(r.randf_range(0.9, 1.04))
	var gw := int(iw / 10.0) + 2
	var gh := int(ih / 10.0) + 2
	var grime := []
	for k in gw * gh:
		grime.append(r.randf())
	var streaks := []  # rain runs down the strips, every 0.1 m across them a strength
	for k in maxi(iw, ih):
		streaks.append(r.randf() if r.randf() < 0.3 else 0.0)
	var pond := rect.position + rect.size * Vector2(r.randf_range(0.3, 0.7), r.randf_range(0.3, 0.7))
	var pr := r.randf_range(0.5, 0.8)
	var img := Image.create(iw, ih, false, Image.FORMAT_RGB8)
	for j in ih:
		var z := rect.position.y + (j + 0.5) / 10.0
		for i in iw:
			var x := rect.position.x + (i + 0.5) / 10.0
			var t := (ih - 1 - j) if along_z else i  # px from the street end, along the roof
			var across := i if along_z else j
			var f: float = lanes[int(t / 10.0) % lanes.size()]
			if t % 10 == 0:
				f *= 0.8  # the lap
			elif t % 10 == 1:
				f *= 1.06
			var gx := (i + 0.5) / 10.0
			var gz := (j + 0.5) / 10.0
			var cx := int(gx)
			var cz := int(gz)
			var tx := smoothstep(0.0, 1.0, gx - cx)
			var tz := smoothstep(0.0, 1.0, gz - cz)
			var g := lerpf(lerpf(grime[cz * gw + cx], grime[cz * gw + cx + 1], tx),
					lerpf(grime[(cz + 1) * gw + cx], grime[(cz + 1) * gw + cx + 1], tx), tz)
			f *= lerpf(0.9, 1.03, g) * (1.0 - streaks[across] * 0.1 * smoothstep(0.0, 6.0, t / 10.0))
			var h := r.randf()
			if h < 0.04:
				f *= 0.91
			elif h < 0.06:
				f *= 1.06
			var pd := Vector2(x - pond.x, (z - pond.y) * 0.8).length() / pr * lerpf(0.8, 1.2, g)
			if pd < 1.0:
				f *= 0.93 if pd < 0.86 else 0.85  # a tide mark round its rim
			var d := Vector2(x, z).distance_to(drain)
			if d < 0.13:
				f = 0.42 if d < 0.08 else 0.6
			elif d < 1.0:
				f *= lerpf(0.84, 1.0, d / 1.0)
			if i < 2 or j >= ih - 3:
				f *= 0.76  # the parapets' shadow on the sunny sides
			elif i >= iw - 1 or j < 1:
				f *= 0.88
			for c in casts:
				var at: Rect2 = c[0]
				if at.grow(-0.04).has_point(Vector2(x, z) - c[1]):
					f *= 0.72
					break
				var out := Vector2(maxf(maxf(at.position.x - x, x - at.end.x), 0.0), maxf(maxf(at.position.y - z, z - at.end.y), 0.0))
				if out.length() < 0.2:  # a dark seam where each fitting meets the roof
					f *= lerpf(0.78, 1.0, out.length() / 0.2)
					break
			img.set_pixel(i, j, Color(base.r * f, base.g * f, base.b * f))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func roof_mat(t: ImageTexture) -> StandardMaterial3D:
	var m := mat(Color.WHITE, t)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m


## Your pole sign in the back corner of the car park, clear of the shop, lit like the shop after dark (street frame): a
## lightbox in an aluminium cabinet under a top cap, its sheet set back in a bezel, with a glow spilling round it and a
## pair of floodlights under it washing the bays in shop light.
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
	var alu := Color("c9cdd1")
	box_into(kit, ps + Vector3(-0.9, 5.6, -0.14), ps + Vector3(0.9, 7.16, 0.14), Color("9da2a8"))  # the lightbox's cabinet
	box_into(kit, ps + Vector3(-0.94, 7.16, -0.19), ps + Vector3(0.94, 7.22, 0.19), alu.lightened(0.15))  # its top cap
	box_into(kit, ps + Vector3(-0.92, 5.56, -0.18), ps + Vector3(0.92, 5.6, 0.18), alu.darkened(0.25))  # the pan
	for sz: float in [1.0, -1.0]:  # a bezel round each face, standing proud of the sheet
		var z0 := 0.14 * sz
		var z1 := 0.19 * sz
		box_into(kit, ps + Vector3(-0.9, 7.08, minf(z0, z1)), ps + Vector3(0.9, 7.16, maxf(z0, z1)), alu)
		box_into(kit, ps + Vector3(-0.9, 5.6, minf(z0, z1)), ps + Vector3(0.9, 5.7, maxf(z0, z1)), alu.darkened(0.12))
		for sx in [-1.0, 1.0]:
			box_into(kit, ps + Vector3(0.86 * sx - 0.04, 5.7, minf(z0, z1)), ps + Vector3(0.86 * sx + 0.04, 7.08, maxf(z0, z1)), alu.darkened(0.06))
	commit([kit], parent)
	var face := PlaneMesh.new()
	face.orientation = PlaneMesh.FACE_Z
	face.size = Vector2(1.64, 1.38)
	for side in [1.0, -1.0]:  # the sheet on both faces of the lightbox, set back in its bezel
		var lf := MeshInstance3D.new()
		lf.mesh = face
		lf.material_override = mat(Color.WHITE, sign_face(), true)
		lf.material_override.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		if parent == set_node:
			set_sign_mats.append(lf.material_override)
		lf.position = ps + Vector3(0, 6.39, 0.17 * side)
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
	var glow := MeshInstance3D.new()  # behind the bezel, so the light spills round the cabinet rather than over its face
	var q := QuadMesh.new()
	q.size = Vector2(3.3, 2.9)
	glow.mesh = q
	glow.material_override = sign_glow_mat
	glow.position = ps + Vector3(0, 6.39, 0.155)
	parent.add_child(glow)
	var fk := surface(km)
	box_into(fk, ps + Vector3(-0.13, 4.98, -0.13), ps + Vector3(0.13, 5.22, 0.13), frame)  # the floodlights' collar
	for a: Vector3 in [Vector3.LEFT, Vector3.BACK]:  # an LED flood on each bracket, tipped down into the bays
		var s := Vector3(a.z, 0, -a.x)
		box_into(fk, ps + a * 0.12 - s * 0.03 + Vector3(0, 5.12, 0), ps + a * 0.64 + s * 0.03 + Vector3(0, 5.19, 0), steel)
		var strut := ps + a * 0.3 + Vector3(0, 4.98, 0)
		turned_box_into(fk, Transform3D(Basis(s, -0.62) * Basis(s, Vector3.UP, a) * Basis.from_scale(Vector3(0.04, 0.04, 0.4)), strut), steel)
		for k: float in [-1.0, 1.0]:  # the yoke's arms either side of the housing
			box_into(fk, ps + a * 0.6 + s * (0.2 * k - 0.014) + Vector3(0, 4.94, 0), ps + a * 0.66 + s * (0.2 * k + 0.014) + Vector3(0, 5.19, 0), frame)
		var b := Basis(s, -0.9 - 0.25 * a.z) * Basis(s, Vector3.UP, a)
		var c := ps + a * 0.68 + Vector3(0, 4.98, 0)
		turned_box_into(fk, Transform3D(b * Basis.from_scale(Vector3(0.36, 0.1, 0.3)), c), Color("c4c8cc"))
		for fx: float in [-0.12, -0.04, 0.04, 0.12]:  # heat-sink fins down its back
			turned_box_into(fk, Transform3D(b * Basis.from_scale(Vector3(0.022, 0.05, 0.26)), c + b * Vector3(fx, 0.07, 0)), Color("9ea4aa"))
		turned_box_into(fk, Transform3D(b * Basis.from_scale(Vector3(0.33, 0.02, 0.27)), c + b * Vector3(0, -0.055, 0)), Color("585d65"))  # the bezel
	commit([fk], parent)
	var lens := QuadMesh.new()
	lens.size = Vector2(0.29, 0.23)
	for a: Vector3 in [Vector3.LEFT, Vector3.BACK]:  # each flood's lens, facing out of its bezel
		var s := Vector3(a.z, 0, -a.x)
		var b := Basis(s, -0.9 - 0.25 * a.z) * Basis(s, Vector3.UP, a)
		var head := MeshInstance3D.new()
		head.mesh = lens
		head.transform = Transform3D(b * Basis(Vector3.RIGHT, PI / 2), ps + a * 0.68 + Vector3(0, 4.98, 0) + b * Vector3(0, -0.068, 0))
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
	var feet := []  # the fixtures' footprints, each standing in its own soft shadow on the tiles
	for pid in st.products:
		var slot: String = Sim.PRODUCTS[pid].slot
		if FIXTURES.has(slot_kind(slot)):
			var p: Vector2 = Sim.SLOTS[slot].pos
			feet.append(Rect2(p.x - FIXTURE_W / 2 - 0.05, p.y - 0.44, FIXTURE_W + 0.1, 0.88))
	feet.sort_custom(func(a, b): return a.position < b.position)
	var fk := str(zl, feet)
	if not floor_tex.has(fk):
		floor_tex[fk] = shop_floor(zl, L.floor[0], L.floor[1], feet)
	plane(room, Vector2(w, 9.0), Vector3(cx, 0.002, 0.0), mat(Color.WHITE, floor_tex[fk], true))
	if sun_in_mat:
		if not sun_gate_tex.has(zl):
			sun_gate_tex[zl] = sun_gate(zl)
		sun_in_mat.set_shader_parameter("gate", sun_gate_tex[zl])
		sun_in_mat.set_shader_parameter("size", Vector2(w, 9.0))
		sun_in_mat.set_shader_parameter("span", Vector2(zl - cx, 6.6 - zl))  # the glazing, in the floor plane's own x
		plane(room, Vector2(w, 9.0), Vector3(cx, 0.004, 0.0), sun_in_mat)
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
	entrance_mat(Sim.DOOR_IN.x)
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


## The sliding door's floor track between its jambs and the entrance mat inside it (shop-local, centred on x dx), in
## one mesh: a track lit along its lip over two dark guide grooves, and a mat sunk in an aluminium well, its rubber
## ribbed across the way in, each rib a shade off, worn pale down the middle where feet tread and dusty toward the
## door, inside a dark binding with the chain's stripes woven across its inner end.
func entrance_mat(dx: float) -> void:
	var m := mat(Color.WHITE, null, true)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var s := surface(m)
	box_into(s, Vector3(dx - 0.8, 0.0, 4.53), Vector3(dx + 0.8, 0.012, 4.67), Color("8b96a1"))
	for z in [4.565, 4.62]:
		box_into(s, Vector3(dx - 0.8, 0.0, z), Vector3(dx + 0.8, 0.014, z + 0.015), Color("3a4047"))
	box_into(s, Vector3(dx - 0.8, 0.0, 4.655), Vector3(dx + 0.8, 0.015, 4.67), Color("c4cdd5"))
	box_into(s, Vector3(dx - 0.77, 0.0, 3.455), Vector3(dx + 0.77, 0.012, 4.445), Color("b3bcc5"))
	box_into(s, Vector3(dx - 0.72, 0.0, 3.505), Vector3(dx + 0.72, 0.016, 4.395), Color("1f2327"))
	const SEG := 12
	var sw := 1.32 / SEG
	for k in 2:  # the stripes woven across the inner end, worn through a little where the feet go
		var z0 := 3.56 + k * 0.075
		for i in SEG:
			var x0 := dx - 0.66 + i * sw
			var wear := exp(-pow((x0 + sw / 2 - dx) / 0.36, 2.0))
			box_into(s, Vector3(x0, 0.0, z0), Vector3(x0 + sw, 0.022, z0 + 0.06), LAYOUT.stripe[k].lerp(Color("9a9690"), 0.4 * wear))
	var rib := Color("5a616a")
	var z := 3.73
	var row := 0
	while z < 4.3:
		var dust := clampf((z - 3.95) / 0.4, 0.0, 1.0)
		for i in SEG:
			var x0 := dx - 0.66 + i * sw
			var wear := exp(-pow((x0 + sw / 2 - dx) / 0.36, 2.0))
			var n := fposmod(sin(row * 12.9898 + i * 78.233) * 43758.5453, 1.0)
			var c := rib.lightened(0.08 * n).lerp(Color("a3a6a8"), 0.6 * wear)
			c = c.lerp(Color("7a6f5e"), 0.45 * dust * (0.6 + 0.4 * n))
			box_into(s, Vector3(x0, 0.0, z), Vector3(x0 + sw, 0.022, z + 0.085), c)
		z += 0.125
		row += 1
	commit([s], room)


## The glass front cut away at knee height from x0 to x1 (shop-local, z = 4.6), in one mesh: an aluminium sill lit
## along its outer lip, black gaskets at the glass's foot, the chain's stripes as a film on the glass, the glass's
## sea-green cut edge, and box-section mullion stubs every bay and at each end, their hollow showing at the cut;
## the glass itself clear enough to see the floor through, with a sheen across it.
func glass_front(x0: float, x1: float) -> void:
	var w := x1 - x0
	if w <= 0.1:
		return
	var cx := (x0 + x1) / 2
	var m := mat(Color.WHITE, null, true)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var s := surface(m)
	box_into(s, Vector3(x0, 0.0, 4.47), Vector3(x1, 0.1, 4.73), Color("59626c"))
	box_into(s, Vector3(x0, 0.1, 4.47), Vector3(x1, 0.115, 4.66), Color("8d97a1"))
	box_into(s, Vector3(x0, 0.1, 4.66), Vector3(x1, 0.12, 4.73), Color("c4cdd5"))
	for z in [4.553, 4.632]:
		box_into(s, Vector3(x0, 0.11, z), Vector3(x1, 0.145, z + 0.015), Color("2b3036"))
	box_into(s, Vector3(x0, 0.165, 4.631), Vector3(x1, 0.2, 4.635), LAYOUT.stripe[1])
	box_into(s, Vector3(x0, 0.208, 4.631), Vector3(x1, 0.243, 4.635), LAYOUT.stripe[0])
	box_into(s, Vector3(x0, 0.415, 4.57), Vector3(x1, 0.435, 4.63), Color("7cc4b0"))
	box_into(s, Vector3(x0, 0.435, 4.592), Vector3(x1, 0.438, 4.608), Color("e4f7f1"))
	var bays := maxi(1, roundi(w / 1.6))
	for k in bays + 1:
		var mx := x0 + 0.045 + (w - 0.09) * k / bays
		box_into(s, Vector3(mx - 0.045, 0.0, 4.53), Vector3(mx + 0.045, 0.47, 4.67), Color("737c86"))
		box_into(s, Vector3(mx - 0.045, 0.47, 4.53), Vector3(mx + 0.045, 0.48, 4.67), Color("cfd6dc"))
		box_into(s, Vector3(mx - 0.028, 0.47, 4.55), Vector3(mx + 0.028, 0.482, 4.65), Color("30353b"))
		box_into(s, Vector3(mx - 0.046, 0.0, 4.664), Vector3(mx - 0.03, 0.47, 4.671), Color("a9b2bb"))
	commit([s], room)
	block(room, Vector3(w, 0.27, 0.05), Vector3(cx, 0.28, 4.6), Color(0.58, 0.8, 0.84, 0.3))
	if not glass_sheen:
		var img := Image.create(32, 8, false, Image.FORMAT_RGBA8)
		for y in 8:
			for x in 32:
				var d := posmod(x + y, 32)
				img.set_pixel(x, y, Color(1, 1, 1, 0.38 if d < 3 else (0.2 if d >= 6 and d < 8 else 0.0)))
		glass_sheen = mat(Color.WHITE, ImageTexture.create_from_image(img), true)
		glass_sheen.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var sheen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, 0.27)
	sheen.mesh = q
	var sm: StandardMaterial3D = glass_sheen.duplicate()
	sm.uv1_scale = Vector3(w / 1.1, 1, 1)
	sheen.material_override = sm
	sheen.position = Vector3(cx, 0.28, 4.627)
	room.add_child(sheen)


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
	wall_kit(zl)


## The left wall's plaster as painted panels butted every 1.5 m, each a shade off and lit from the ceiling, fading
## toward the skirting, with a clock in the aisle and an extinguisher under its red sign in the front corner, in one
## mesh.
func wall_kit(zl: float) -> void:
	var m := mat(Color.WHITE, null, true)
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	var s := surface(m)
	var plaster := Color("efe6d2")
	var x := zl + 0.003
	const Y0 := 0.12
	const Y1 := 2.5
	for k in 6:
		var z0 := -4.5 + k * 1.5
		var t := 0.75 + (0.012 if k % 2 == 0 else -0.01)
		var lo := Color(plaster.r * (t - 0.08), plaster.g * (t - 0.085), plaster.b * (t - 0.09))
		var hi := Color(plaster.r * (t + 0.03), plaster.g * (t + 0.03), plaster.b * (t + 0.02))
		var v := [Vector3(x, Y0, z0), Vector3(x, Y0, z0 + 1.5), Vector3(x, Y1, z0 + 1.5), Vector3(x, Y1, z0)]
		var c := [lo, lo, hi, hi]
		for i in [0, 1, 2, 0, 2, 3]:
			s.set_color(c[i])
			s.set_uv(Vector2.ZERO)
			s.add_vertex(v[i])
		if k > 0:
			box_into(s, Vector3(zl, Y0, z0 - 0.012), Vector3(zl + 0.006, Y1, z0 + 0.012), plaster * Color(0.88, 0.86, 0.83))
	box_into(s, Vector3(zl, Y1, -4.5), Vector3(zl + 0.02, Y1 + 0.03, 4.5), Color("d9d4c8"))  # a capping rail under the stripes
	# the clock, an octagon of boxes: dark rim, white face, quarter ticks and its hands at ten to two
	var cc := Vector3(zl, 2.12, 0.65)
	for r: Vector2 in [Vector2(0.36, 0.15), Vector2(0.15, 0.36), Vector2(0.3, 0.3)]:
		box_into(s, cc + Vector3(0.01, -r.y / 2, -r.x / 2), cc + Vector3(0.06, r.y / 2, r.x / 2), Color("3a3f47"))
	for r: Vector2 in [Vector2(0.3, 0.12), Vector2(0.12, 0.3), Vector2(0.24, 0.24)]:
		box_into(s, cc + Vector3(0.06, -r.y / 2, -r.x / 2), cc + Vector3(0.065, r.y / 2, r.x / 2), Color("fbfaf5"))
	for o: Vector2 in [Vector2(0, 0.12), Vector2(0, -0.12), Vector2(0.12, 0), Vector2(-0.12, 0)]:
		box_into(s, cc + Vector3(0.065, o.y - 0.012, o.x - 0.012), cc + Vector3(0.07, o.y + 0.012, o.x + 0.012), Color("3a3f47"))
	box_into(s, cc + Vector3(0.068, 0.0, -0.01), cc + Vector3(0.075, 0.1, 0.01), Color("2b2d33"))
	box_into(s, cc + Vector3(0.068, -0.01, -0.01), cc + Vector3(0.075, 0.01, 0.075), Color("2b2d33"))
	box_into(s, cc + Vector3(0.07, -0.018, -0.018), cc + Vector3(0.08, 0.018, 0.018), Color("d8452f"))
	# the extinguisher on its stand by the glass, its red sign over it
	var ez := 4.12
	box_into(s, Vector3(zl + 0.01, 0.0, ez - 0.13), Vector3(zl + 0.24, 0.04, ez + 0.13), Color("5e6670"))
	box_into(s, Vector3(zl + 0.05, 0.04, ez - 0.08), Vector3(zl + 0.21, 0.46, ez + 0.08), Color("d8312a"))
	box_into(s, Vector3(zl + 0.05, 0.22, ez - 0.081), Vector3(zl + 0.211, 0.31, ez + 0.081), Color("f2efe6"))  # its label
	box_into(s, Vector3(zl + 0.09, 0.46, ez - 0.035), Vector3(zl + 0.17, 0.52, ez + 0.035), Color("2b2d33"))
	box_into(s, Vector3(zl + 0.17, 0.2, ez + 0.06), Vector3(zl + 0.2, 0.5, ez + 0.09), Color("2b2d33"))  # the hose
	box_into(s, Vector3(zl + 0.01, 0.74, ez - 0.17), Vector3(zl + 0.025, 0.88, ez + 0.17), Color("d8312a"))
	box_into(s, Vector3(zl + 0.025, 0.78, ez - 0.13), Vector3(zl + 0.03, 0.84, ez + 0.13), Color("fbf3ea"))
	commit([s], room)


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
			pop_card(Vector3(p.x + w / 2, h - 0.32, p.y), pid)
		"fridge":
			var body := Color("e3ebf0")
			var frame := Color("4a5058")
			var top: float = f.rows[-1][1]  # the header's underside
			var x0 := p.x - w / 2
			var x1 := p.x + w / 2
			var zb := p.y - 0.4
			var zf := p.y + 0.37  # the door frames' back
			var m := mat(Color.WHITE, null, true)
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			var s := surface(m)
			box_into(s, Vector3(x0, 0, zb), Vector3(x1, h, zb + 0.06), Color("e4f1f8"))  # the lit back
			for dx in [-1.09, -0.365, 0.365, 1.09]:  # an LED strip down each door's edge
				box_into(s, Vector3(p.x + dx - 0.015, deck, zb + 0.06), Vector3(p.x + dx + 0.015, top, zb + 0.065), Color("ffffff"))
			for e in [x0, x1 - 0.06]:
				box_into(s, Vector3(e, 0, zb), Vector3(e + 0.06, h, zf), body)
			box_into(s, Vector3(x1, 0, zf - 0.08), Vector3(x1 + 0.01, h, zf + 0.04), frame)  # the frame wrapped round the end
			box_into(s, Vector3(x0, 0, zb), Vector3(x1, deck, zf), body)
			box_into(s, Vector3(x0, top, zb), Vector3(x1, h, zf), body)
			box_into(s, Vector3(x0 - 0.01, h, zb - 0.01), Vector3(x1 + 0.01, h + 0.02, zf + 0.05), body.darkened(0.06))  # the lid
			box_into(s, Vector3(x0 + 0.2, h + 0.02, zb + 0.06), Vector3(x1 - 0.2, h + 0.06, zb + 0.34), Color("6d737b"))  # the condenser's grille on top
			for k in 9:
				var gx := x0 + 0.26 + k * (w - 0.52) / 8
				box_into(s, Vector3(gx - 0.012, h + 0.06, zb + 0.08), Vector3(gx + 0.012, h + 0.065, zb + 0.32), Color("a3a9b0"))
			# the header: a white fascia banded in the stripes, a light strip under it washing the doors
			box_into(s, Vector3(x0, top, zf), Vector3(x1, h, zf + 0.04), Color("fbfaf5"))
			box_into(s, Vector3(x0, top + 0.03, zf + 0.04), Vector3(x1, top + 0.07, zf + 0.045), LAYOUT.stripe[0])
			box_into(s, Vector3(x0, top + 0.08, zf + 0.04), Vector3(x1, top + 0.17, zf + 0.045), LAYOUT.stripe[1])
			box_into(s, Vector3(x0 + 0.06, top - 0.025, zf - 0.08), Vector3(x1 - 0.06, top, zf - 0.02), Color("ffffff"))
			# the kick plate: a dark grille slotted across under the doors
			box_into(s, Vector3(x0, 0, zf), Vector3(x1, deck, zf + 0.04), Color("3a3f46"))
			for y in [0.035, 0.06, 0.085]:
				box_into(s, Vector3(x0 + 0.1, y - 0.006, zf + 0.04), Vector3(x1 - 0.1, y + 0.006, zf + 0.045), Color("1f2328"))
			for r in f.rows.slice(1):  # wire shelves, a price strip on each
				box_into(s, Vector3(p.x - w / 2 + 0.06, r[0] - 0.02, p.y - 0.34), Vector3(p.x + w / 2 - 0.06, r[0], p.y + 0.28), trim)
				box_into(s, Vector3(p.x - w / 2 + 0.06, r[0] - 0.03, p.y + 0.28), Vector3(p.x + w / 2 - 0.06, r[0], p.y + 0.29), Color("fbf7ee"))
			# the door frames: stiles, mullions and rails in graphite, a steel bar handle on each door's closing edge
			for dx in [[-1.09, -1.05], [-0.395, -0.335], [0.335, 0.395], [1.05, 1.09]]:
				box_into(s, Vector3(p.x + dx[0], deck, zf), Vector3(p.x + dx[1], top, zf + 0.04), frame)
			for y in [[deck, deck + 0.04], [top - 0.04, top]]:
				box_into(s, Vector3(p.x - 1.09, y[0], zf), Vector3(p.x + 1.09, y[1], zf + 0.04), frame)
			for hx in [-0.45, 0.28, 0.45]:
				box_into(s, Vector3(p.x + hx - 0.012, 0.66, zf + 0.04), Vector3(p.x + hx + 0.012, 1.32, zf + 0.075), Color("8e969e"))
				for hy in [0.7, 1.28]:
					box_into(s, Vector3(p.x + hx - 0.01, hy - 0.012, zf + 0.04), Vector3(p.x + hx + 0.01, hy + 0.012, zf + 0.06), Color("6b727a"))
			# the glass, faintly blue, with a sheen down each pane
			var g := surface(mat(Color(0.78, 0.9, 0.96, 0.16), null, true))
			var sh := surface(mat(Color(1, 1, 1, 0.28), null, true))
			for d in [[-1.05, -0.395], [-0.335, 0.335], [0.395, 1.05]]:
				box_into(g, Vector3(p.x + d[0], deck + 0.04, zf + 0.015), Vector3(p.x + d[1], top - 0.04, zf + 0.025), Color.WHITE)
				for k in 2:
					var sx: float = p.x + d[0] + 0.1 + k * 0.08
					box_into(sh, Vector3(sx, deck + 0.04, zf + 0.026), Vector3(sx + 0.05 - k * 0.03, top - 0.04, zf + 0.03), Color.WHITE)
			commit([s, g, sh], room)
			pop_card(Vector3(x1 + 0.01, 1.1, p.y - 0.05), pid)
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


## A POP card on a fixture's end panel at `at` (its face to +x): the line's pack over its price, framed in the stripes.
func pop_card(at: Vector3, pid: String) -> void:
	block(room, Vector3(0.02, 0.5, 0.56), at + Vector3(0.01, 0, 0), LAYOUT.stripe[1])
	block(room, Vector3(0.02, 0.42, 0.48), at + Vector3(0.02, 0, 0), Color("fffaf0"))
	block(room, Vector3(0.02, 0.09, 0.36), at + Vector3(0.03, -0.13, 0), Color("fff3c4"))  # the price flash
	block(room, Vector3(0.02, 0.025, 0.2), at + Vector3(0.04, -0.13, 0), LAYOUT.stripe[0])
	var ic: Array = Sim.PRODUCTS[pid].icon
	var cell: int = {"products": ITEM, "perks": 80, "decor": DECOR}[ic[0]]
	var s := sprite(ic[0], Rect2(ic[1] * cell, 0, cell, cell), 0.28 / cell, false)
	s.rotation.y = PI / 2
	s.position = at + Vector3(0.04, 0.05, 0)
	room.add_child(s)


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
	for e in threat_nodes.values():
		mats.append_array(e.get("dim", []))
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
				trash_bag(mi, t.get("spot", 0))
			"spill":
				e.dim = spill_patch(mi, t.id)
			"breaker":
				breaker_board(mi)
		e.node = mi
	actors.add_child(e.node)
	e.node.position = Vector3(t.x, e.node.position.y, t.z)
	return e


## A dumped bin bag, `spot` picking which: a translucent sack bellied over its shaded foot and tied off in two ears,
## the rubbish pressing pale through its film, slumped against a second smaller one or ringed with loose litter, and
## caught in your shop's light after dark.
func trash_bag(mi: MeshInstance3D, spot: int) -> void:
	var kit := mat(Color.WHITE)
	kit.vertex_color_use_as_albedo = true
	kit.vertex_color_is_srgb = true
	var st := surface(kit)
	var bags: Array = [[[Vector3.ZERO, 0.3, Color("c3d2de")], [Vector3(0.26, 0, 0.22), 0.18, Color("cfdbe4")]],
		[[Vector3.ZERO, 0.32, Color("b9cad8")]], [[Vector3.ZERO, 0.28, Color("e8d58e")], [Vector3(-0.22, 0, 0.24), 0.16, Color("c3d2de")]]][spot % 3]
	for bag in bags:
		var bc: Vector3 = bag[0]
		var r: float = bag[1]
		var c: Color = bag[2]
		# a sack in octagonal tiers on a rounded profile, bellied low and gathered up to the neck
		for k in 7:
			var y0 := r * 1.5 * k / 7.0
			var y1 := r * 1.5 * (k + 1) / 7.0
			var w := r * sqrt(maxf(0.08, 1.0 - pow((k + 0.5) / 7.0 * 2.0 - 0.75, 2) / 1.6))
			var tc := c.darkened(0.18 * (1.0 - k / 6.0)).lightened(0.06 * k / 6.0)
			box_into(st, bc + Vector3(-w, y0, -w * 0.62), bc + Vector3(w, y1, w * 0.62), tc)
			box_into(st, bc + Vector3(-w * 0.62, y0, -w), bc + Vector3(w * 0.62, y1, w), tc)
		# the rubbish showing through the film on the street faces, and the film's sheen down the sun side
		for k in 3:
			var at := bc + Vector3(-r * 0.4 + k * r * 0.4, r * (0.4 + 0.25 * (k % 2)), r * 0.95 + 0.004)
			box_into(st, at + Vector3(-r * 0.16, -r * 0.1, 0), at + Vector3(r * 0.16, r * 0.1, 0.004), [Color("c9a46a"), Color("d98c7a"), Color("9fb4c2")][k].lerp(c, 0.55))
		box_into(st, bc + Vector3(r * 0.95 + 0.002, r * 0.45, -r * 0.5), bc + Vector3(r * 0.95 + 0.006, r * 0.95, r * 0.05), c.lerp(Color.WHITE, 0.65))
		box_into(st, bc + Vector3(-r * 0.5, r * 0.5, r * 0.95 + 0.006), bc + Vector3(-r * 0.36, r * 1.0, r * 0.95 + 0.01), c.lerp(Color.WHITE, 0.65))
		box_into(st, bc + Vector3(-0.03, r * 1.5, -0.03), bc + Vector3(0.03, r * 1.5 + 0.06, 0.03), c.darkened(0.25))
		for e in [-1, 1]:
			box_into(st, bc + Vector3(e * 0.03 - 0.02, r * 1.5 + 0.04, -0.015), bc + Vector3(e * 0.08 + 0.02, r * 1.5 + 0.1, 0.015), c.darkened(0.14))
		if c == Color("e8d58e"):  # the ward's printed mark on a burnables bag
			box_into(st, bc + Vector3(-r * 0.4, r * 0.5, r * 0.95 + 0.01), bc + Vector3(r * 0.1, r * 0.85, r * 0.95 + 0.014), Color("3f6fb8"))
	if spot % 3 == 1:  # litter spilled out round it: a crushed can, a cup on its side and a scrap of paper
		box_into(st, Vector3(0.36, 0, 0.12), Vector3(0.48, 0.06, 0.18), Color("c8463c"))
		box_into(st, Vector3(0.36, 0.055, 0.12), Vector3(0.48, 0.065, 0.18), Color("c9ccd0"))
		box_into(st, Vector3(-0.2, 0, 0.38), Vector3(-0.08, 0.07, 0.46), Color("f4f1ea"))
		box_into(st, Vector3(-0.08, 0.005, 0.385), Vector3(-0.06, 0.065, 0.455), Color("3a8a5c"))
		box_into(st, Vector3(0.1, 0, 0.4), Vector3(0.26, 0.008, 0.5), Color("ece6d6"))
	commit([st], mi)
	light_up(kit, 0.35)  # they lie in your shop's light after dark
	kit.albedo_color = light.lerp(Color.WHITE, 0.35 * clampf(night, 0.0, 1.0))
	var sh := foot(0.9)  # a walker's shadow fits a sack's: a contact patch and its cast away from the sun
	sh.position.y = 0.04
	mi.add_child(sh)


## A spill on your shop's floor: a wet patch the tiles show through, edged by a darker meniscus with its lip catching
## the ceiling lights, a glint across it and a few splashes, and the bottle it came out of on its side by it. Lit by the
## shop like the floor it lies on; returns its materials for a blackout to dim.
func spill_patch(mi: MeshInstance3D, id: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = id * 7919 + 13
	var n := 64
	var blobs := [[Vector2(32, 32), 18.0]]
	for k in 4:
		var a := rng.randf() * TAU
		blobs.append([Vector2(32, 32) + Vector2(cos(a), sin(a)) * rng.randf_range(8, 14), rng.randf_range(7, 12)])
	for k in 5:
		var a := rng.randf() * TAU
		blobs.append([Vector2(32, 32) + Vector2(cos(a), sin(a)) * rng.randf_range(25, 30), rng.randf_range(1.4, 2.6)])
	var field := func(x: float, y: float) -> float:
		var f := -1.0
		for b in blobs:
			f = maxf(f, 1.0 - Vector2(x, y).distance_to(b[0]) / b[1])
		return f
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var glint := Vector2(rng.randf_range(24, 30), rng.randf_range(24, 30))
	for y in n:
		for x in n:
			var f: float = field.call(x + 0.5, y + 0.5)
			if f <= 0.0:
				continue
			var c := Color(0.42, 0.56, 0.68, 0.55)
			if f < 0.16:
				# the edge facing the lights (up the screen) catches them; the rest is the dark meniscus
				c = Color(0.97, 0.99, 1.0, 0.85) if field.call(x - 1.5, y - 1.5) <= 0.0 else Color(0.28, 0.4, 0.52, 0.75)
			var g := Vector2(x, y) - glint
			if absf(g.x - g.y) < 1.8 and absf(g.x + g.y) < 12.0:
				c = Color(1, 1, 1, 0.8)
			img.set_pixel(x, y, c)
	var pm := mat(Color.WHITE, ImageTexture.create_from_image(img), true)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.texture_repeat = false
	plane(mi, Vector2(1.3, 1.3), Vector3.ZERO, pm)
	mi.position.y = 0.012
	var kit := mat(Color.WHITE, null, true)
	kit.vertex_color_use_as_albedo = true
	kit.vertex_color_is_srgb = true
	var st := surface(kit)
	var ang := rng.randf() * TAU
	var at := Vector3(cos(ang), 0, sin(ang)) * 0.5
	var along := absf(cos(ang)) > absf(sin(ang))  # lying out from the puddle, its neck toward it
	var lc: Color = [Color("e4572e"), Color("3a8fd0"), Color("f2b630")][id % 3]
	var hl := Vector3(0.14, 0.05, 0.05) if along else Vector3(0.05, 0.05, 0.14)
	box_into(st, at - Vector3(hl.x, 0, hl.z), at + hl, Color("dfeef4"))
	box_into(st, at - Vector3(hl.x, -0.012, hl.z) * 0.7, at + Vector3(hl.x * 0.7, 0.062, hl.z * 0.7), lc)
	var neck := at - Vector3(signf(at.x) * (hl.x + 0.05), 0, 0) if along else at - Vector3(0, 0, signf(at.z) * (hl.z + 0.05))
	box_into(st, neck - Vector3(0.03, 0, 0.03), neck + Vector3(0.03, 0.04, 0.03), Color("dfeef4"))
	commit([st], mi)
	var ms := [pm, kit]
	for m: StandardMaterial3D in ms:
		m.set_meta("own", m.albedo_color)
		m.albedo_color *= room_dim
	return ms


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
		var lit: Array = pools.slice(0, 64) if mode == "store" else []
		if lit != foot_lamps:
			foot_lamps = lit
			foot_mat.set_shader_parameter("lamps", PackedVector3Array(lit + range(64 - lit.size()).map(func(_i): return Vector3.ZERO)))
			foot_mat.set_shader_parameter("lamp_count", lit.size())
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
		if sale:
			sale.visible = branch.rival.price_war > 0.0
		if wall_bikes:
			wall_bikes.visible = branch.event == null or not branch.event.id in ["festival", "tv", "inspector", "heatwave"]
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
	var hot: bool = mode == "store" and not branch.is_empty() and branch.event != null and branch.event.id == "heatwave" and night < 0.99
	if screen_rect.material != (heat_mat if hot else null):
		screen_rect.material = heat_mat if hot else null
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
		draw_heat(look[0], r)
		return
	var snowing: bool = look[4] == 0.0
	# snow goes with the light: its pale veil thins after dark and takes the hour's tint, the flakes too, except where
	# they fall through a lamp's or a shop window's light
	var veil: Color = look[0] * light if snowing else look[0]
	veil.a = look[0].a * (lerpf(0.3, 1.0, 1.0 - night) if snowing else 1.0)
	overlay.draw_rect(Rect2(Vector2.ZERO, size), veil)
	var flake := Color.WHITE.lerp(light, 0.75 * night).lerp(light, 0.3)
	var lit := []  # [screen centre, screen radius] of the light pools after dark, at the height the flakes fall through
	if snowing and night > 0.0:
		for q in pools:
			var c := screen_world(Vector3(q.x, 1.6, q.y))
			lit.append([c, c.distance_to(screen_world(Vector3(q.x + q.z, 1.6, q.y))) * 1.3])
	var span := size.y + 40.0
	var lines := PackedVector2Array()
	for i in look[1]:
		var d := r.randf()  # snow falls at three depths: near flakes bigger, faster and swaying wider
		var y := fposmod(r.randf() * span + now * look[3] * r.randf_range(0.8, 1.2) * (lerpf(0.5, 1.7, d) if snowing else 1.0), span) - 20.0
		var x := fposmod(r.randf() * size.x + y * look[2], size.x)
		var p := Vector2(x + (sin(now * 1.4 + i) * lerpf(3.0, 10.0, d) if snowing else 0.0), y)
		if inside.size() > 2 and Geometry2D.is_point_in_polygon(p, inside):
			continue
		if snowing:
			var px := 2.0 if d < 0.45 else (3.0 if d < 0.85 else 4.0)
			var k := 0.0
			for e in lit:
				k = maxf(k, 1.0 - p.distance_to(e[0]) / e[1])
			var glow := clampf(k * 1.6, 0.0, 1.0) * night
			var c := flake.lerp(Color(1.0, 0.95, 0.84), glow)
			if glow > 0.0:  # a flake lit up out of the dark glints, a soft rim round it
				overlay.draw_rect(Rect2(p - Vector2(px + 4, px + 4) / 2, Vector2(px + 4, px + 4)), Color(c, 0.14 * glow))
			if px == 4.0 or glow > 0.0:
				overlay.draw_rect(Rect2(p - Vector2(px + 2, px + 2) / 2, Vector2(px + 2, px + 2)), Color(c, 0.25 + 0.2 * glow))
			overlay.draw_rect(Rect2(p - Vector2(px, px) / 2, Vector2(px, px)), Color(c, lerpf(0.5, 0.95, d)))
		else:
			lines.append_array([p, p + Vector2(look[2], 1.0).normalized() * look[4]])
	if not lines.is_empty():
		overlay.draw_multiline(lines, Color(0.86, 0.9, 1.0, 0.5))


## A heatwave goes with the sun: a warm haze (eased off in the already amber golden hour), glare washing down from the
## sky, and over the street the air wavers and mirages shine (HEAT_SHADER), never inside your air-conditioned shop;
## after dark only a faint warmth is left.
func draw_heat(tint: Color, r: RandomNumberGenerator) -> void:
	var day := 1.0 - night
	overlay.draw_rect(Rect2(Vector2.ZERO, size), tint * Color(1, 1, 1, lerpf(0.25, 1.0, day) * (1.0 - 0.5 * golden_at(sim.hour()))))
	if day <= 0.01:
		return
	var glare := Color(1.0, 0.88, 0.58)
	var low := size.y * 0.6
	overlay.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, low * 0.6), Vector2(0, low)]),
		PackedColorArray([glare * Color(1, 1, 1, 0.42 * day), glare * Color(1, 1, 1, 0.22 * day), Color(glare, 0.0), Color(glare, 0.0)]))
	# the stretch of the street on screen, where its centre line crosses the view's edges
	var s0 := screen(Vector3.ZERO)
	var step := screen(Vector3(10, 0, 0)) - s0
	var xs := Vector2(maxf(street_x.x, -s0.x / step.x * 10.0), minf(street_x.y, minf((size.x - s0.x) / step.x, (size.y - s0.y) / step.y) * 10.0))
	if not heat_mat:
		heat_mat = ShaderMaterial.new()
		heat_mat.shader = Shader.new()
		heat_mat.shader.code = HEAT_SHADER
	var to_ground := Transform2D(step / 10.0, screen(Vector3(0, 0, 1)) - s0, s0).affine_inverse()
	heat_mat.set_shader_parameter("view_size", size)
	heat_mat.set_shader_parameter("ground_x", to_ground.x)
	heat_mat.set_shader_parameter("ground_z", to_ground.y)
	heat_mat.set_shader_parameter("ground_o", to_ground.origin)
	heat_mat.set_shader_parameter("reach", Vector2(street_x.x, street_x.y))
	heat_mat.set_shader_parameter("day", day)
	heat_mat.set_shader_parameter("sky", Color(0.7, 0.84, 1.0) * light)
	var sheens := PackedVector4Array()
	for i in 6:
		sheens.append(Vector4(r.randf_range(xs.x + 3.0, xs.y - 3.0), r.randf_range(-2.4, 2.4), r.randf_range(3.0, 6.0), i * 2.1))
	heat_mat.set_shader_parameter("sheens", sheens)


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


## A rival chain's mascot head in a cream roundel ringed in the chain's colour, as on its lightbox sign.
func rival_face(id: String) -> ImageTexture:
	if not faces.has(id):
		var c := Color(Sim.RIVALS[id].color)
		var cream := Color(1.0, 0.98, 0.92)
		var face: Image = tex["walk"].get_image().get_region(Rect2i(4, (WALK_ROW.mascot + Sim.RIVALS.keys().find(id)) * PERSON.y, 64, 54))
		face.convert(Image.FORMAT_RGBA8)
		face.resize(58, 49, Image.INTERPOLATE_LANCZOS)
		var disc := Image.create(80, 80, false, Image.FORMAT_RGBA8)
		for y in 80:
			for x in 80:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(40, 40))
				var px := Color(cream, clampf(40.0 - d, 0.0, 1.0)).lerp(c, clampf(37.0 - d, 0.0, 1.0)).lerp(cream.lightened(0.4), clampf(32.0 - d, 0.0, 1.0))
				px = px.lerp(cream.darkened(0.08), clampf(32.0 - d, 0.0, 1.0) * clampf((y - 40.0) / 32.0, 0.0, 1.0))
				if d < 32.0 and x >= 11 and x < 69 and y >= 18 and y < 67:
					var f := face.get_pixel(x - 11, y - 18)
					px = px.lerp(Color(f.r, f.g, f.b), f.a)
				disc.set_pixel(x, y, px)
		disc.generate_mipmaps()
		faces[id] = ImageTexture.create_from_image(disc)
	return faces[id]


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
	var font: Font = bold if bold else get_theme_default_font()
	var asc := font.get_ascent(13)
	var nw := font.get_string_size(def.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 14
	var bw := maxf(nw, 96.0)
	var ph := asc + font.get_descent(13) + 28
	var stem_to := sign_at
	# a tall store card (an event, more products) would cover the plate: it drops below the card, or failing that
	# slides out to its left, and the stem leans over to it
	var reach := Rect2(sign_at + Vector2(-(bw + 50) / 2 - 20, 12 - ph), Vector2(bw + 76, ph + 12))  # plate, roundel, shadow
	# a narrow window can put the roof near or past an edge: the plate slides back on screen and the stem leans out to it
	var inside := Rect2(Vector2.ZERO, overlay.size).grow(-10)
	var slide := Vector2(maxf(0.0, inside.position.x - reach.position.x) - maxf(0.0, reach.end.x - inside.end.x),
			maxf(0.0, inside.position.y - reach.position.y))
	sign_at += slide
	reach.position += slide
	if reach.intersects(hud_card):
		sign_at.y = minf(maxf(sign_at.y, hud_card.end.y + ph - 12), roof_at.y - 22)
		reach.position.y = sign_at.y + 12 - ph
		if reach.intersects(hud_card):
			sign_at.x -= reach.end.x - hud_card.position.x
	if sign_at != roof_at + Vector2(0, -58):
		stem_to = Vector2(clampf(roof_at.x, sign_at.x - (bw + 50) / 2 + 14, sign_at.x + (bw + 38) / 2), sign_at.y)
	overlay.draw_line(roof_at + Vector2(1, 0), stem_to + Vector2(1, 0), Color(0, 0, 0, 0.3), 3.0)
	overlay.draw_line(roof_at, stem_to, Color.WHITE, 2.0)
	overlay.draw_circle(roof_at + Vector2(0, 1.5), 5.5, Color(0, 0, 0, 0.3))
	overlay.draw_circle(roof_at, 5.0, Color.WHITE)
	overlay.draw_circle(roof_at, 3.6, Color("8a8780") if rv.defeated else Color(def.color))
	if not rv.defeated:
		# name and takings on one cream plate, so the bar never sits on the chain's own fascia color
		# its mascot in a roundel that breaks the plate's left edge, the name over a gauge of the same width
		var plate := Rect2(sign_at + Vector2(-(bw + 50) / 2 + 6, 18 - ph), Vector2(bw + 44, ph))
		overlay.draw_style_box(round_box(Color(0.42, 0.3, 0.15, 0.25), 12), Rect2(plate.position + Vector2(0, 3), plate.size))
		overlay.draw_style_box(round_box(Color(1.0, 0.98, 0.92, 0.96), 12), plate)
		var disc := Vector2(plate.position.x, plate.get_center().y)
		overlay.draw_circle(disc + Vector2(0, 2.5), 20.0, Color(0.42, 0.3, 0.15, 0.3))
		overlay.draw_texture_rect(rival_face(rv.id), Rect2(disc - Vector2(20, 20), Vector2(40, 40)), false)
		var tx := plate.position.x + 30
		pill(Vector2(tx + nw / 2, plate.position.y + 8 + asc), def.name, 13, Color(def.color).darkened(0.1))
		var gauge := Rect2(Vector2(tx, plate.end.y - 13), Vector2(bw, 7))
		var f := clampf(rv.hp / rv.max_hp, 0.0, 1.0)
		bar(gauge, f, Color(def.color), Color(0.42, 0.3, 0.15, 0.3))
		if f > 0.0:  # a gloss along the fill's top, and a notch at each quarter so a full gauge still reads as one
			var fw := maxf(gauge.size.y, gauge.size.x * f)
			overlay.draw_style_box(round_box(Color(1, 1, 1, 0.35), 1.5), Rect2(gauge.position + Vector2(3, 1), Vector2(fw - 6, 2)))
		for q in [0.25, 0.5, 0.75]:
			overlay.draw_rect(Rect2(gauge.position + Vector2(roundf(gauge.size.x * q) - 0.5, 1), Vector2(1, gauge.size.y - 2)), Color(0.3, 0.2, 0.1, 0.35))
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
	# threats: name and clicks left, each tag lifted clear of the ones below it on a stem back to its own threat
	var tags: Array = []
	for t in b.threats:
		if t.fleeing:
			continue
		var at := screen(threat_point(t))
		var label: String = {"flyer": "Flyers", "mascot": "Mascot", "trash": "Trash", "review": "1★ review", "shoplifter": "Thief!", "breaker": "Breaker", "suit": "Suit", "spill": "Spill"}[t.type]
		var top := at + Vector2(0, -26 if t.type in ["flyer", "shoplifter", "suit", "review"] else (-36 if t.type == "mascot" else (-30 if t.type == "breaker" else -12)))
		var w := maxf(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 14, t.max_clicks * 9.0 + 2 if t.max_clicks > 1 else 0.0)
		var below := 13.0 if t.max_clicks > 1 or t.type == "review" else font.get_descent(11) + 2
		tags.append({"t": t, "label": label, "home": top, "box": Rect2(top.x - w / 2, top.y - font.get_ascent(11) - 2, w, font.get_ascent(11) + 2 + below)})
	tags.sort_custom(func(p, q): return p.home.y > q.home.y or (p.home.y == q.home.y and p.t.id < q.t.id))
	var placed: Array = hud_dock.duplicate()
	for g in tags:
		var box: Rect2 = g.box
		var moved := true
		while moved:
			moved = false
			for o in placed:
				if box.grow(2.0).intersects(o):
					box.position.y = o.position.y - box.size.y - 3.0
					moved = true
		placed.append(box)
		g.top = g.home + Vector2(0, box.position.y - g.box.position.y)
		if g.top.y < g.home.y - 1.0:  # stems first, so no tag's stem crosses another tag
			var foot := Vector2(g.top.x, box.end.y)
			overlay.draw_line(foot + Vector2(1, 0), g.home + Vector2(1, 2), Color(0, 0, 0, 0.3), 2.5)
			overlay.draw_line(foot, g.home + Vector2(0, 2), Color.WHITE, 1.5)
			overlay.draw_circle(g.home + Vector2(0, 2), 3.0, Color.WHITE)
			overlay.draw_circle(g.home + Vector2(0, 2), 2.0, Color("e05a4e") if g.t.type != "spill" else Color("3a9bd9"))
	for g in tags:
		var t: Dictionary = g.t
		var top: Vector2 = g.top
		pill(top, g.label, 11, Color("e05a4e") if t.type != "spill" else Color("3a9bd9"))
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
	var taken: Array = hud_keep + [Rect2(8, 8, 196, 82)]  # rects already filled, the clock's first: a label that would overlap one is left out
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
		taken.append(Rect2(ground + Vector2(-40, -52), Vector2(80, 56)))
		if not b.rival.defeated:
			taken.append(Rect2(screen_world(frame_origin(b.lot) + Vector3(rival_span(b.rival).x + 4.0, 0.0, -7.2)) + Vector2(-13, -29), Vector2(26, 34)))
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
		# a street's name on a cream tag laid along it, a Shuto route's number on a green plate ringed by a white rule,
		# each left out unless it sits wholly on screen
		var view := Rect2(Vector2.ZERO, size).grow(-4.0)
		for av in C.avenues:
			if av.name == "":
				continue
			var pts: PackedVector2Array = av.pts
			var i: int = av.get("third", int(pts.size() / 3.0))
			var at := screen_world(Vector3(pts[i].x, 0, pts[i].y))
			var a: Vector2 = pts[maxi(i - 1, 0)]
			var z: Vector2 = pts[mini(i + 1, pts.size() - 1)]
			var ang := wrapf((screen_world(Vector3(z.x, 0, z.y)) - screen_world(Vector3(a.x, 0, a.y))).angle(), -PI / 2, PI / 2)
			var w := font.get_string_size(av.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x + 10
			var h := font.get_ascent(9) + font.get_descent(9) + 3
			var ext := Vector2(absf(w * cos(ang)) + absf(h * sin(ang)), absf(w * sin(ang)) + absf(h * cos(ang)))
			var box := Rect2(at - ext / 2, ext)
			if not view.encloses(box) or not room_for.call(box):
				continue
			overlay.draw_set_transform(at, ang)
			overlay.draw_style_box(round_box(Color(0.42, 0.3, 0.15, 0.28), h / 2), Rect2(-w / 2, -h / 2 + 1.5, w, h))
			overlay.draw_style_box(round_box(Color(1.0, 0.98, 0.92, 0.92), h / 2), Rect2(-w / 2, -h / 2, w, h))
			overlay.draw_string(font, Vector2(-w / 2, (font.get_ascent(9) - font.get_descent(9)) / 2), av.name, HORIZONTAL_ALIGNMENT_CENTER, w, 9, Color("4f5562"))
			overlay.draw_set_transform(Vector2.ZERO)
		for sh in C.shuto:
			var pts: PackedVector3Array = sh.pts
			var at := screen_world(pts[sh.get("mid", int(pts.size() / 2.0))] + Vector3(0, 1.5, 0))
			var w := maxf(22.0, bf.get_string_size(sh.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 12)
			var r := Rect2(at - Vector2(w / 2, 9), Vector2(w, 17))
			if not view.encloses(r) or not room_for.call(r):
				continue
			overlay.draw_style_box(round_box(Color(0.12, 0.16, 0.12, 0.3), 4), Rect2(r.position + Vector2(0, 2), r.size))
			overlay.draw_style_box(round_box(Color("1f6f43"), 4), r)
			overlay.draw_style_box(round_box(Color("f4f6f0"), 3), r.grow(-1.5))
			overlay.draw_style_box(round_box(Color("23794a"), 2), r.grow(-2.5))
			overlay.draw_string(bf, Vector2(r.position.x, at.y + (bf.get_ascent(10) - bf.get_descent(10)) / 2 - 0.5), sh.name, HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color.WHITE)
	var offered := {}
	if pick == "listing" and sim.choice != null and sim.choice.source == "listing":
		for k in sim.choice.options.size():
			offered[sim.choice.options[k].lot] = k
	for li in sim.lots.size():
		var mark := Color(0, 0, 0, 0)
		if offered.has(li):
			mark = Color("3fae49")
		elif sim.lots[li].use == "free" and pick == "":
			mark = Color(light.lerp(Color.WHITE, 0.25), 0.35)  # takes the hour's light, not a white line over the night
		if li == hover_lot and (offered.has(li) or sim.branch_on(li) != null):
			mark = Color.WHITE
		if mark.a > 0.0:
			overlay.draw_polyline(lot_poly(li), mark, 2.0)
		if offered.has(li):
			var p2: Vector2 = Sim.lot_pos(sim.lots[li])
			var at := screen_world(Vector3(p2.x, 3.0, p2.y))
			overlay.draw_circle(at, 10.0, Color("3fae49"))
			overlay.draw_string(font, at + Vector2(-10, 5), str(offered[li] + 1), HORIZONTAL_ALIGNMENT_CENTER, 20, 13, Color.WHITE)
	# each branch as a map pin: its number and name on a pill whose tail drops a stem to a disc on the lot, and the
	# rival's mascot in a roundel beside it, its ring a gauge of the rival's takings
	var font_b: Font = bold if bold else font
	var shade := Color(0.42, 0.3, 0.15, 0.3)
	var cream := Color(1.0, 0.98, 0.92)
	for e in pins:
		var ground: Vector2 = e[0]
		var b: Dictionary = e[1]
		if not Rect2(Vector2.ZERO, size).grow(40).has_point(ground):
			continue
		var c := Color("e98a1d") if is_same(b, branch) else Color("c46a14")
		if not b.rival.defeated:
			var rc := Color(Sim.RIVALS[b.rival.id].color)
			var rat := screen_world(frame_origin(b.lot) + Vector3(rival_span(b.rival).x + 4.0, 0.0, -7.2))
			var top := rat + Vector2(0, -15)
			ground_disc(rat, 4.0, rc, shade)
			overlay.draw_line(rat, top, Color.WHITE, 1.5)
			overlay.draw_circle(top + Vector2(0, 2), 12.0, shade)
			overlay.draw_texture_rect(rival_face(b.rival.id), Rect2(top - Vector2(12, 12), Vector2(24, 24)), false)
			var f := clampf(b.rival.hp / b.rival.max_hp, 0.0, 1.0)
			if f < 1.0:  # the roundel's ring is the gauge: what's gone of its takings shows cream, from the top round
				overlay.draw_arc(top, 10.35, -PI / 2 + TAU * f, 1.5 * PI, maxi(4, roundi(32 * (1.0 - f))), cream.darkened(0.12), 2.0, true)
		var asc := font_b.get_ascent(11)
		var h := asc + font_b.get_descent(11) + 6
		var w := font_b.get_string_size(b.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + h + 10
		var r := Rect2(ground.x - w / 2, ground.y - 30 - h, w, h)
		var tip := Vector2(ground.x, r.end.y + 5)
		overlay.draw_line(ground + Vector2(1, 0), tip + Vector2(1, 0), shade, 3.0)
		overlay.draw_line(ground, tip, Color.WHITE, 2.0)
		ground_disc(ground, 5.0, c, shade)
		overlay.draw_style_box(round_box(Color(0.42, 0.3, 0.15, 0.25), h / 2), Rect2(r.position + Vector2(0, 2), r.size))
		overlay.draw_colored_polygon(PackedVector2Array([tip + Vector2(-5, -6), tip + Vector2(5, -6), tip]), c)
		overlay.draw_style_box(round_box(c, h / 2), r)
		var bc := r.position + Vector2(h / 2, h / 2)
		overlay.draw_circle(bc, h / 2 - 2.5, cream)
		overlay.draw_string(font_b, Vector2(bc.x - h / 2, bc.y + (font_b.get_ascent(10) - font_b.get_descent(10)) / 2), str(sim.branches.find(b) + 1), HORIZONTAL_ALIGNMENT_CENTER, h, 10, c.darkened(0.25))
		overlay.draw_string(font_b, Vector2(r.position.x + h + 3, r.position.y + 3 + asc), b.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)


## A map pin's foot: a disc in c, ringed white, laid flat on the ground at p over its soft shadow.
func ground_disc(p: Vector2, r: float, c: Color, shade: Color) -> void:
	overlay.draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
	overlay.draw_circle(Vector2(0.5, 3.0), r + 3.0, shade)
	overlay.draw_circle(Vector2.ZERO, r + 1.5, Color.WHITE)
	overlay.draw_circle(Vector2.ZERO, r, c)
	overlay.draw_set_transform(Vector2.ZERO)
