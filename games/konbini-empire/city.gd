extends RefCounted
## Tokyo as a city-builder map. Districts sit at their real relative places; the bay, the Sumida and the parks
## are carved out; blocks come from splitting the city again and again (so side streets meet in T-junctions and
## never line up into one grid); curved avenues, the elevated Shuto expressway over some of them (with ramps down
## to the avenue below) and the Yamanote loop cut across. Built once and cached: Tokyo never changes, only who
## holds which lot. Node-free; buildings() is only for the view.

const ROAD := 9.2  # sidewalk, two lanes, sidewalk: the street the shop view draws
const SIDEWALK := 2.2
const AVENUE := 13.0
const CARRIER := 17.0  # an avenue with the expressway above it
const EXPRESS_W := 9.0
const RAMP_W := 4.0
const DECK := 6.0
const RAIL_DECK := 3.4
const FLOOR := 3.0
const LOT_W := 22.0
const LOT_D := 10.0
const URBAN := 92.0  # built-up land reaches this far from the nearest district centre
const MOAT := 6.0
const RIVER_W := 16.0
const RAMP_L := 46.0

# [name, profile, x, z, landmark sheet, frame (-1: none), shop lots]. x east, z south; ~40 units a kilometre.
const DISTRICTS := [
	["Imperial Palace", "palace", 0, 0, "tokyo", 8, 0],
	["Tokyo Station", "hub", 55, 8, "tokyo", 3, 2],
	["Nihonbashi", "office", 72, -22, "", -1, 1],
	["Ginza", "luxury", 66, 50, "tokyo", 6, 2],
	["Shimbashi", "nightlife", 38, 82, "landmarks", 0, 1],
	["Tsukiji", "market", 92, 70, "", -1, 1],
	["Tsukishima", "oldtown", 140, 84, "", -1, 1],
	["Toyosu", "market", 200, 124, "", -1, 1],
	["Odaiba", "tourist", 115, 192, "tokyo", 10, 1],
	["Shiba", "tourist", 8, 118, "tokyo", 0, 1],
	["Azabu", "luxury", -36, 132, "", -1, 1],
	["Roppongi", "nightlife", -64, 96, "tokyo", 11, 1],
	["Akasaka", "office", -54, 38, "", -1, 1],
	["Shinagawa", "hub", -18, 232, "landmarks", 0, 2],
	["Ebisu", "nightlife", -122, 156, "", -1, 1],
	["Meguro", "homes", -118, 210, "", -1, 1],
	["Nakameguro", "youth", -172, 178, "", -1, 1],
	["Jiyugaoka", "luxury", -232, 246, "landmarks", 6, 1],
	["Setagaya", "homes", -280, 156, "", -1, 1],
	["Shimokitazawa", "youth", -246, 92, "landmarks", 6, 1],
	["Shibuya", "hub", -150, 116, "tokyo", 5, 2],
	["Harajuku", "youth", -122, 66, "landmarks", 6, 1],
	["Yoyogi", "park", -170, 52, "tokyo", 9, 1],
	["Shinjuku", "hub", -172, -14, "landmarks", 0, 2],
	["Nishi-Shinjuku", "office", -214, -26, "tokyo", 4, 1],
	["Nakano", "homes", -278, -40, "", -1, 1],
	["Koenji", "youth", -334, -46, "landmarks", 6, 1],
	["Suginami", "homes", -366, 12, "", -1, 1],
	["Ikebukuro", "hub", -160, -172, "landmarks", 0, 2],
	["Nerima", "homes", -292, -212, "", -1, 1],
	["Itabashi", "homes", -212, -258, "", -1, 1],
	["Kita", "homes", -56, -272, "", -1, 1],
	["Komagome", "oldtown", -60, -200, "landmarks", 3, 1],
	["Sugamo", "oldtown", -104, -150, "landmarks", 6, 1],
	["Kagurazaka", "luxury", -78, -70, "landmarks", 3, 1],
	["Jimbocho", "university", 8, -48, "landmarks", 2, 1],
	["Akihabara", "otaku", 62, -66, "tokyo", 7, 1],
	["Ueno", "hub", 64, -122, "landmarks", 0, 2],
	["Ueno Park", "park", 30, -146, "landmarks", 4, 1],
	["Yanaka", "oldtown", 16, -196, "landmarks", 3, 1],
	["Nippori", "oldtown", 44, -226, "landmarks", 0, 1],
	["Minowa", "homes", 100, -236, "", -1, 1],
	["Asakusa", "tourist", 124, -136, "tokyo", 2, 1],
	["Oshiage", "tourist", 200, -130, "tokyo", 1, 1],
	["Kuramae", "oldtown", 104, -92, "", -1, 1],
	["Ryogoku", "homes", 154, -46, "", -1, 1],
	["Kiyosumi", "homes", 156, 10, "landmarks", 4, 1],
	["Kameido", "homes", 236, -54, "landmarks", 6, 1],
]
# Yamanote Line stations in running order: the elevated loop runs through them.
const YAMANOTE := ["Ikebukuro", "Sugamo", "Nippori", "Ueno", "Akihabara", "Tokyo Station", "Shimbashi", "Shinagawa", "Ebisu", "Shibuya", "Harajuku", "Shinjuku"]
const BAY := [Vector2(-140, 480), Vector2(-70, 330), Vector2(2, 268), Vector2(26, 205), Vector2(42, 152), Vector2(56, 114), Vector2(76, 100), Vector2(100, 100), Vector2(112, 92), Vector2(122, 52), Vector2(175, 44), Vector2(260, 38), Vector2(460, 30), Vector2(460, 480)]
const ISLANDS := [
	[Vector2(126, 60), Vector2(160, 56), Vector2(166, 100), Vector2(148, 112), Vector2(128, 108)],
	[Vector2(178, 96), Vector2(224, 92), Vector2(230, 150), Vector2(184, 156), Vector2(174, 128)],
	[Vector2(80, 172), Vector2(144, 164), Vector2(152, 214), Vector2(92, 224)],
]
const SUMIDA := [Vector2(30, -420), Vector2(88, -285), Vector2(138, -215), Vector2(155, -160), Vector2(146, -112), Vector2(130, -78), Vector2(122, -30), Vector2(120, 25), Vector2(114, 68), Vector2(108, 110)]
# [name, x, z, rx, rz]
const PARKS := [
	["Imperial Palace", 0, 0, 44, 36],
	["Ueno Park", 30, -146, 24, 20],
	["Yoyogi Park", -170, 52, 26, 24],
	["Shinjuku Gyoen", -120, 0, 16, 10],
	["Shiba Park", 8, 118, 14, 12],
	["Hibiya Park", 26, 34, 11, 9],
	["Kiyosumi Garden", 156, 10, 11, 10],
]
# Shuto C1, the inner loop round the palace; the radial routes ride above the avenues marked with "shuto".
const C1 := [Vector2(-50, -50), Vector2(-10, -66), Vector2(46, -58), Vector2(84, -24), Vector2(88, 32), Vector2(58, 84), Vector2(6, 92), Vector2(-44, 66), Vector2(-66, 18)]
const RAINBOW := [Vector2(40, 128), Vector2(70, 150), Vector2(100, 172), Vector2(124, 190), Vector2(140, 196)]
const AVENUES := [
	{"name": "Shinjuku-dori", "w": CARRIER, "shuto": "4", "pts": [Vector2(-66, 18), Vector2(-100, 20), Vector2(-138, 20), Vector2(-176, 8), Vector2(-220, 0), Vector2(-280, -8), Vector2(-360, -18), Vector2(-480, -26)]},
	{"name": "Aoyama-dori", "w": CARRIER, "shuto": "3", "pts": [Vector2(-44, 66), Vector2(-80, 78), Vector2(-112, 92), Vector2(-148, 98), Vector2(-190, 116), Vector2(-230, 128), Vector2(-282, 128), Vector2(-360, 140), Vector2(-480, 160)]},
	{"name": "Kasuga-dori", "w": CARRIER, "shuto": "5", "pts": [Vector2(-50, -50), Vector2(-82, -96), Vector2(-112, -124), Vector2(-138, -158), Vector2(-178, -208), Vector2(-232, -262), Vector2(-300, -350), Vector2(-340, -420)]},
	{"name": "Sumida-dori", "w": CARRIER, "shuto": "6", "pts": [Vector2(84, -24), Vector2(106, -40), Vector2(128, -56), Vector2(152, -80), Vector2(170, -112), Vector2(178, -160), Vector2(168, -215), Vector2(130, -280), Vector2(100, -420)]},
	{"name": "Keiyo-doro", "w": CARRIER, "shuto": "7", "pts": [Vector2(152, -80), Vector2(196, -84), Vector2(250, -92), Vector2(330, -100), Vector2(460, -108)]},
	{"name": "Daiichi Keihin", "w": CARRIER, "shuto": "1", "pts": [Vector2(58, 84), Vector2(44, 118), Vector2(32, 156), Vector2(16, 196), Vector2(2, 236), Vector2(-30, 280), Vector2(-100, 340), Vector2(-150, 440)]},
	{"name": "Meiji-dori", "w": AVENUE, "pts": [Vector2(-128, -240), Vector2(-140, -180), Vector2(-150, -120), Vector2(-150, -60), Vector2(-146, -10), Vector2(-138, 34), Vector2(-128, 84), Vector2(-112, 130), Vector2(-100, 168), Vector2(-60, 180), Vector2(-24, 170), Vector2(8, 150), Vector2(40, 142)]},
	{"name": "Yasukuni-dori", "w": AVENUE, "pts": [Vector2(-212, -52), Vector2(-170, -42), Vector2(-120, -40), Vector2(-90, -40), Vector2(-40, -58), Vector2(0, -66), Vector2(40, -78), Vector2(80, -84), Vector2(110, -74), Vector2(152, -80)]},
	{"name": "Chuo-dori", "w": AVENUE, "pts": [Vector2(80, -196), Vector2(84, -150), Vector2(86, -100), Vector2(80, -48), Vector2(70, 0), Vector2(74, 40), Vector2(70, 88), Vector2(52, 112)]},
	{"name": "Harumi-dori", "w": AVENUE, "pts": [Vector2(40, 24), Vector2(64, 36), Vector2(94, 56), Vector2(122, 72), Vector2(150, 82), Vector2(176, 104), Vector2(202, 120), Vector2(228, 126)]},
]

static var _city: Dictionary = {}
static var _buildings: Array = []


static func get_city() -> Dictionary:
	if _city.is_empty():
		_city = _build()
	return _city


# ---------- geometry helpers ----------

## Catmull-Rom through the control points, a point every `step` units. Closed loops don't repeat the first point.
static func smooth(ctrl: Array, closed := false, step := 5.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	for i in (n if closed else n - 1):
		var p0: Vector2 = ctrl[(i - 1 + n) % n] if closed or i > 0 else ctrl[0]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % n]
		var p3: Vector2 = ctrl[(i + 2) % n] if closed or i + 2 < n else ctrl[n - 1]
		var k := maxi(1, ceili(p1.distance_to(p2) / step))
		for j in k:
			out.append(p1.cubic_interpolate(p2, p0, p3, float(j) / k))
	if not closed:
		out.append(ctrl[n - 1])
	return out


static func cumulative(pts: PackedVector2Array, closed := false) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for i in range(1, pts.size() + (1 if closed else 0)):
		out.append(out[-1] + pts[i - 1].distance_to(pts[i % pts.size()]))
	return out


## [point, unit tangent] at arc length s along an open polyline.
static func at(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Array:
	s = clampf(s, 0.0, cum[-1])
	for i in range(1, pts.size()):
		if cum[i] >= s or i == pts.size() - 1:
			var seg := cum[i] - cum[i - 1]
			var t := (s - cum[i - 1]) / seg if seg > 0.0 else 0.0
			return [pts[i - 1].lerp(pts[i], t), (pts[i] - pts[i - 1]).normalized()]
	return [pts[0], Vector2.RIGHT]


static func in_ellipse(p: Vector2, c: Vector2, r: Vector2) -> bool:
	var d := (p - c) / r
	return d.length_squared() < 1.0


static func ellipse(c: Vector2, r: Vector2, n := 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	return out


static func is_water(C: Dictionary, p: Vector2) -> bool:
	if Geometry2D.is_point_in_polygon(p, C.bay):
		for isl in C.islands:
			if Geometry2D.is_point_in_polygon(p, isl):
				return false
		return true
	for poly in C.river:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	var pk: Dictionary = C.parks[0]  # the palace moat
	return in_ellipse(p, pk.center, pk.radii + Vector2(MOAT, MOAT)) and not in_ellipse(p, pk.center, pk.radii)


static func in_park(C: Dictionary, p: Vector2) -> bool:
	for pk in C.parks:
		if in_ellipse(p, pk.center, pk.radii + (Vector2(MOAT, MOAT) if pk.name == "Imperial Palace" else Vector2.ZERO)):
			return true
	return false


## [district index, distance] of the nearest district centre.
static func nearest(C: Dictionary, p: Vector2) -> Array:
	var best := 0
	var bd := INF
	for i in C.districts.size():
		var d: float = p.distance_squared_to(C.districts[i].center)
		if d < bd:
			bd = d
			best = i
	return [best, sqrt(bd)]


static func seg_rect_dist(a: Vector2, b: Vector2, r: Rect2) -> float:
	if r.has_point(a) or r.has_point(b):
		return 0.0
	var c := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	var best := INF
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return 0.0
		var cp := Geometry2D.get_closest_points_between_segments(a, b, c[i], c[(i + 1) % 4])
		best = minf(best, cp[0].distance_to(cp[1]))
	return best


static func _bucket_keys(r: Rect2) -> Array:
	var out := []
	for bx in range(floori(r.position.x / 24.0), floori(r.end.x / 24.0) + 1):
		for bz in range(floori(r.position.y / 24.0), floori(r.end.y / 24.0) + 1):
			out.append(Vector2i(bx, bz))
	return out


static func _add_corridor(C: Dictionary, pts: PackedVector2Array, half: float, closed := false) -> void:
	for i in pts.size() - (0 if closed else 1):
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		var box := Rect2(a, Vector2.ZERO).expand(b).grow(half)
		for k in _bucket_keys(box):
			if not C.corridors.has(k):
				C.corridors[k] = []
			C.corridors[k].append([a, b, half])


static func reserve(C: Dictionary, r: Rect2) -> void:
	for k in _bucket_keys(r):
		if not C.reserved.has(k):
			C.reserved[k] = []
		C.reserved[k].append(r)


## True when a footprint would sit on a road corridor, water, a park, or a reserved lot or landmark.
static func blocked(C: Dictionary, r: Rect2) -> bool:
	for k in _bucket_keys(r):
		for s in C.corridors.get(k, []):
			if seg_rect_dist(s[0], s[1], r) < s[2]:
				return true
		for q in C.reserved.get(k, []):
			if q.intersects(r):
				return true
	for fx in [0.0, 0.5, 1.0]:
		for fz in [0.0, 0.5, 1.0]:
			var p := r.position + r.size * Vector2(fx, fz)
			if is_water(C, p) or in_park(C, p):
				return true
	return false


# ---------- the build ----------

static func _build() -> Dictionary:
	var C := {"districts": [], "corridors": {}, "reserved": {}}
	for row in DISTRICTS:
		C.districts.append({"name": row[0], "type": row[1], "center": Vector2(row[2], row[3]), "lm": [row[4], row[5]], "lots": row[6]})
	C.bay = PackedVector2Array(BAY)
	C.islands = ISLANDS.map(func(p): return PackedVector2Array(p))
	C.river_line = smooth(SUMIDA, false, 4.0)
	C.river = Geometry2D.offset_polyline(C.river_line, RIVER_W / 2, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)
	C.parks = PARKS.map(func(p): return {"name": p[0], "center": Vector2(p[1], p[2]), "radii": Vector2(p[3], p[4])})
	# avenues, the expressway above the carriers, ramps from the deck down to the avenue
	C.avenues = []
	C.shuto = [{"name": "C1", "pts": _deck(smooth(C1, true), DECK), "closed": true}]
	C.ramps = []
	for av in AVENUES:
		var pts := smooth(av.pts)
		C.avenues.append({"name": av.name, "w": av.w, "pts": pts, "shuto": av.get("shuto", "")})
		_add_corridor(C, pts, av.w / 2 + 0.6)
		if av.has("shuto"):
			C.shuto.append({"name": av.shuto, "pts": _deck(pts, DECK), "closed": false})
			var cum := cumulative(pts)
			var s0: float = cum[-1] * 0.42
			for side in [1.0, -1.0]:
				C.ramps.append(_ramp(pts, cum, s0, side, side > 0))
				C.ramps.append(_ramp(pts, cum, s0 + RAMP_L + 24.0, side, side < 0))
	var rainbow := smooth(RAINBOW)
	var rb := _deck(rainbow, DECK)
	var rcum := cumulative(rainbow)
	for i in rb.size():
		var p := rb[i]
		p.y = DECK * clampf((rcum[-1] - rcum[i]) / 40.0, 0.0, 1.0)  # comes down onto Odaiba
		rb[i] = p
	C.shuto.append({"name": "11", "pts": rb, "closed": false})
	for sh in C.shuto:
		if sh.name in ["C1", "11"]:
			_add_corridor(C, _flat(sh.pts), EXPRESS_W / 2 + 1.5, sh.closed)
	for rp in C.ramps:
		_add_corridor(C, _flat(rp), RAMP_W / 2 + 1.0)
	# the Yamanote loop, pulled a little inside its stations so it skirts their landmarks
	var stations := []
	for stn in YAMANOTE:
		for d in C.districts:
			if d.name == stn:
				stations.append(d.center)
	var mid: Vector2 = stations.reduce(func(a, b): return a + b, Vector2.ZERO) / stations.size()
	C.rail = smooth(stations.map(func(p): return p + (mid - p).normalized() * 14.0), true)
	_add_corridor(C, C.rail, 3.0, true)
	# blocks and side streets
	var rng := RandomNumberGenerator.new()
	rng.seed = 1964
	var raw := []
	var leaves := []
	_split(C, Rect2(-480, -420, 960, 840), 0, [0.0, 0.0, 0.0, 0.0], rng, raw, leaves)
	C.streets = []
	for s in raw:
		C.streets.append_array(_clip_street(C, s))
	C.blocks = []
	var bounds := Rect2()
	for r in leaves:
		var c: Vector2 = r.get_center()
		var n := nearest(C, c)
		if n[1] < URBAN and r.size.x > 12.0 and r.size.y > 12.0 and not is_water(C, c) and not in_park(C, c):
			C.blocks.append({"rect": r, "d": n[0]})
			bounds = r if bounds.size == Vector2.ZERO else bounds.merge(r)
	C.bounds = bounds.grow(20.0)
	_place_landmarks(C)
	_place_lots(C)
	return C


static func _deck(pts: PackedVector2Array, y: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in pts:
		out.append(Vector3(p.x, y, p.y))
	return out


static func _flat(pts: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x, p.z))
	return out


## A ramp beside the deck between s0 and s0 + RAMP_L: on `side` (+1 left of the avenue's direction), coming down
## (or going up) between the deck's edge and the avenue's outer lane.
static func _ramp(pts: PackedVector2Array, cum: PackedFloat32Array, s0: float, side: float, down: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := 12
	for k in n + 1:
		var f := float(k) / n
		var y := DECK * ((1.0 - f) if down else f)
		var pt: Array = at(pts, cum, s0 + RAMP_L * f)
		var left := Vector2(pt[1].y, -pt[1].x)
		var p: Vector2 = pt[0] + left * side * lerpf(CARRIER / 2 - SIDEWALK - RAMP_W / 2, EXPRESS_W / 2 + RAMP_W / 2 + 0.4, y / DECK)
		out.append(Vector3(p.x, y, p.y))
	return out


## kd-style split: cut the rectangle with a street across it until blocks are about the local block size.
## `edge` = widths of the streets on its [left, right, top, bottom] sides (0: none), so streets know their junctions.
static func _split(C: Dictionary, r: Rect2, depth: int, edge: Array, rng: RandomNumberGenerator, streets: Array, leaves: Array) -> void:
	var far := INF
	for d in C.districts:
		far = minf(far, d.center.distance_to(d.center.clamp(r.position, r.end)))
	if far > URBAN + 10.0:
		return
	var n := nearest(C, r.get_center())
	var spread := clampf((r.get_center().length() - 60.0) / 280.0, 0.0, 1.0)
	var target := 30.0 + 14.0 * spread + (6.0 if C.districts[n[0]].type in ["homes", "park", "university", "market"] else 0.0)
	var w := AVENUE if depth < 2 else ROAD
	var min_x := maxf(target * 0.6, LOT_W + 4.0)  # every block can take a shop lot
	var min_z := maxf(target * 0.5, LOT_D + 6.0)
	var can_v := r.size.x >= 2.0 * min_x + w
	var can_h := r.size.y >= 2.0 * min_z + w
	var want_v := can_v and r.size.x > target * 1.3
	var want_h := can_h and r.size.y > target * 1.05
	if not want_v and not want_h:
		leaves.append(r)
		return
	var vertical := want_v and (not want_h or r.size.x / 1.3 > r.size.y / 1.05)
	var size := r.size.x if vertical else r.size.y
	var lo := maxf(0.34, ((min_x if vertical else min_z) + w / 2) / size)
	var at_ := (r.position.x if vertical else r.position.y) + size * rng.randf_range(lo, 1.0 - lo)
	if vertical:
		streets.append({"axis": "v", "line": at_ - w / 2, "from": r.position.y, "to": r.end.y, "w": w, "j": [edge[2], edge[3]]})
		_split(C, Rect2(r.position.x, r.position.y, at_ - w / 2 - r.position.x, r.size.y), depth + 1, [edge[0], w, edge[2], edge[3]], rng, streets, leaves)
		_split(C, Rect2(at_ + w / 2, r.position.y, r.end.x - at_ - w / 2, r.size.y), depth + 1, [w, edge[1], edge[2], edge[3]], rng, streets, leaves)
	else:
		streets.append({"axis": "h", "line": at_ - w / 2, "from": r.position.x, "to": r.end.x, "w": w, "j": [edge[0], edge[1]]})
		_split(C, Rect2(r.position.x, r.position.y, r.size.x, at_ - w / 2 - r.position.y), depth + 1, [edge[0], edge[1], edge[2], w], rng, streets, leaves)
		_split(C, Rect2(r.position.x, at_ + w / 2, r.size.x, r.end.y - at_ - w / 2), depth + 1, [edge[0], edge[1], w, edge[3]], rng, streets, leaves)


## The pieces of a street that run through the built-up city on dry land, outside the parks.
static func _clip_street(C: Dictionary, s: Dictionary) -> Array:
	var runs := []
	var start := -INF
	var last := 0.0
	var x: float = s.from
	while true:
		var c: Vector2 = Vector2(x, s.line + s.w / 2) if s.axis == "h" else Vector2(s.line + s.w / 2, x)
		if nearest(C, c)[1] < URBAN + 4.0 and not is_water(C, c) and not in_park(C, c):
			if start == -INF:
				start = x
			last = x
		elif start != -INF:
			runs.append([start, last])
			start = -INF
		if x >= s.to:
			break
		x = minf(x + 2.0, s.to)
	if start != -INF:
		runs.append([start, last])
	var out := []
	for rn in runs:
		if rn[1] - rn[0] >= 8.0:
			out.append({"axis": s.axis, "line": s.line, "from": rn[0], "to": rn[1], "w": s.w, "j": [s.j[0] if rn[0] == s.from else 0.0, s.j[1] if rn[1] == s.to else 0.0]})
	return out


## A landmark on the park it names, else on a free square in the block nearest its district centre.
static func _place_landmarks(C: Dictionary) -> void:
	C.landmarks = []
	for di in C.districts.size():
		var d: Dictionary = C.districts[di]
		if d.lm[1] < 0:
			continue
		var pos := Vector2.INF
		if in_park(C, d.center):
			pos = d.center
		else:
			var ranked: Array = C.blocks.filter(func(b): return b.rect.get_center().distance_to(d.center) < 70.0)
			ranked.sort_custom(func(a, b): return a.rect.get_center().distance_to(d.center) < b.rect.get_center().distance_to(d.center))
			for b in ranked:
				var sq := Rect2(b.rect.get_center() - Vector2(11, 11), Vector2(22, 22))
				if b.rect.encloses(sq) and not blocked(C, sq):
					pos = sq.get_center()
					reserve(C, sq)
					break
		if pos != Vector2.INF:
			C.landmarks.append({"d": di, "pos": pos})


## Shop lots: 22 x 10 on the north side of an east-west street, as near each district centre as they fit. The
## district's shoppers set out from its first lot (`origin`): round the hubs the nearest free frontage can be a
## block or two from the station itself.
static func _place_lots(C: Dictionary) -> void:
	var south := {}  # side streets by the z of their top edge
	for s in C.streets:
		if s.axis == "h":
			var k := roundi(s.line * 10.0)
			if not south.has(k):
				south[k] = []
			south[k].append(s)
	C.lots = []
	for di in C.districts.size():
		var d: Dictionary = C.districts[di]
		var cands := []
		for b in C.blocks:
			var r: Rect2 = b.rect
			if r.size.y < LOT_D + 1.0 or r.get_center().distance_to(d.center) > 110.0:
				continue
			var x0 := r.position.x + 1.0
			while x0 + LOT_W <= r.end.x - 1.0:
				var lot := Rect2(x0, r.end.y - LOT_D, LOT_W, LOT_D)
				var fronted: bool = south.get(roundi(r.end.y * 10.0), []).any(func(s): return s.from <= x0 and s.to >= x0 + LOT_W)
				if fronted:
					cands.append([lot.get_center().distance_to(d.center), lot])
				x0 += 3.0
		cands.sort_custom(func(a, b): return a[0] < b[0])
		var placed := 0
		d.origin = d.center
		for c in cands:
			if placed >= d.lots:
				break
			var lot: Rect2 = c[1]
			if C.lots.any(func(L): return Vector2(L.x0 + LOT_W / 2, L.front - LOT_D / 2).distance_to(lot.get_center()) < 26.0) or blocked(C, lot):
				continue
			C.lots.append({"block": di, "x0": lot.position.x, "front": lot.end.y})
			reserve(C, lot)
			if placed == 0:
				d.origin = lot.get_center() - Vector2(0, LOT_D)
			placed += 1


# ---------- buildings (view only) ----------

enum { GLASS, CONCRETE, APARTMENT, SHOPS, NEON, WOOD, HOUSE, WAREHOUSE, STONE, PLAIN }
const STYLE_COUNT := 10
const TINTS := [
	["c9cfd6", "e6e8ea", "9aa3ad", "b7c2cc"],
	["d9cfbd", "c8c2b5", "e3dccd", "b9b2a6", "d6c6a8"],
	["efe9dc", "e8dcc6", "f2efe8", "d9d2c3", "e6d3bf"],
	["f0e6d2", "e8d8c0", "d8e2e6", "f2dccf", "e0e4d0", "ddd5e8"],
	["5a5e6b", "6b6460", "4f5866", "726a7a"],
	["8a6a4a", "7a5c40", "96734f", "6e5038"],
	["f2efe6", "ede3cf", "e2e6e8", "f0e0d0", "e6e2cf"],
	["a8b0b8", "9aa6a0", "b8b2a4", "8f9aa8"],
	["e8dfcc", "d8ccb4", "cfc8bc", "efe8da"],
	["b8b8b4"],
]
const ROOFS := ["4a5568", "5b4a42", "a0523a", "3d4650", "6b7a4a"]
# per district profile: [weight, style, floors min, max, width min, max, depth min, max]
const MIX := {
	"hub": [[3, SHOPS, 3, 7, 6, 11, 10, 14], [3, NEON, 4, 9, 6, 10, 10, 14], [2, CONCRETE, 5, 10, 12, 18, 12, 16], [2, GLASS, 6, 14, 14, 20, 14, 18]],
	"office": [[4, GLASS, 6, 16, 14, 22, 14, 20], [4, CONCRETE, 5, 11, 12, 18, 12, 16], [1, SHOPS, 2, 5, 6, 10, 10, 14]],
	"luxury": [[4, STONE, 4, 9, 10, 16, 12, 16], [3, GLASS, 5, 11, 12, 18, 12, 18], [2, SHOPS, 3, 6, 7, 11, 10, 14]],
	"nightlife": [[5, NEON, 3, 8, 6, 10, 10, 14], [3, SHOPS, 2, 6, 6, 10, 10, 14], [1, CONCRETE, 5, 9, 12, 16, 12, 16]],
	"youth": [[5, SHOPS, 2, 5, 6, 10, 9, 13], [2, NEON, 3, 6, 6, 9, 9, 13], [2, APARTMENT, 3, 6, 10, 14, 10, 14]],
	"otaku": [[4, NEON, 4, 8, 7, 11, 10, 14], [4, SHOPS, 3, 6, 6, 10, 10, 14], [1, CONCRETE, 5, 9, 12, 16, 12, 16]],
	"tourist": [[4, SHOPS, 2, 5, 6, 10, 9, 13], [2, WOOD, 1, 2, 7, 10, 8, 11], [2, CONCRETE, 3, 7, 12, 16, 12, 16]],
	"university": [[4, CONCRETE, 3, 6, 14, 22, 12, 16], [3, APARTMENT, 3, 6, 10, 14, 10, 14], [2, SHOPS, 2, 4, 6, 10, 9, 13]],
	"homes": [[5, HOUSE, 1, 2, 7, 10, 7, 10], [3, APARTMENT, 3, 6, 10, 16, 10, 14], [1, SHOPS, 2, 3, 6, 9, 8, 12], [1, WOOD, 1, 2, 7, 9, 7, 9]],
	"oldtown": [[6, WOOD, 1, 2, 6, 9, 7, 10], [3, HOUSE, 1, 2, 6, 9, 7, 10], [2, SHOPS, 2, 3, 5, 8, 8, 12]],
	"park": [[3, HOUSE, 1, 2, 7, 10, 7, 10], [2, APARTMENT, 3, 5, 10, 14, 10, 14], [1, SHOPS, 2, 3, 6, 9, 8, 12]],
	"market": [[5, WAREHOUSE, 1, 3, 14, 24, 14, 20], [2, CONCRETE, 3, 5, 12, 16, 12, 16], [1, SHOPS, 2, 3, 6, 10, 9, 12]],
}


## Every building in Tokyo: {rect, floors, style, tint, accent, roof: "" | gable roof colour}. Fixed seed, cached.
static func buildings() -> Array:
	if not _buildings.is_empty():
		return _buildings
	var C := get_city()
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for b in C.blocks:
		_fill_block(C, b, rng, _buildings)
	return _buildings


static func _fill_block(C: Dictionary, b: Dictionary, rng: RandomNumberGenerator, out: Array) -> void:
	var r: Rect2 = b.rect
	var d: Dictionary = C.districts[b.d]
	var type: String = "office" if d.type == "palace" else d.type
	var near: float = r.get_center().distance_to(d.center)
	if type in ["hub", "office"] and near < 34.0 and rng.randf() < 0.75:
		# the station core: one tower per block standing in its plaza
		var t := Rect2(r.get_center() - (r.size - Vector2(6, 6)).min(Vector2(26, 26)) / 2, (r.size - Vector2(6, 6)).min(Vector2(26, 26)))
		if not blocked(C, t):
			out.append(_building(rng, GLASS if rng.randf() < 0.7 else CONCRETE, t, int(rng.randi_range(12, 24) * (1.0 - near / 80.0))))
			return
	var dn := minf(r.size.y / 2.0, 15.0)
	var dw := minf(r.size.x / 2.0, 15.0)
	_row(C, rng, out, type, near, 0, Vector2(r.position.x, r.position.y), r.size.x, dn)
	_row(C, rng, out, type, near, 1, Vector2(r.position.x, r.end.y), r.size.x, dn)
	_row(C, rng, out, type, near, 2, Vector2(r.position.x, r.position.y + dn), r.size.y - 2 * dn, dw)
	_row(C, rng, out, type, near, 3, Vector2(r.end.x, r.position.y + dn), r.size.y - 2 * dn, dw)
	var inner := Rect2(r.position + Vector2(dw, dn), r.size - Vector2(dw, dn) * 2).grow(-1.0)
	if inner.size.x > 5.0 and inner.size.y > 5.0 and not blocked(C, inner):
		out.append(_building(rng, PLAIN if type in ["hub", "office"] else HOUSE, inner, rng.randi_range(1, 2)))


## Buildings shoulder to shoulder along one side of a block (0 north, 1 south, 2 west, 3 east), fronts on the street.
static func _row(C: Dictionary, rng: RandomNumberGenerator, out: Array, type: String, near: float, side: int, from: Vector2, length: float, max_depth: float) -> void:
	var mix: Array = MIX[type]
	var w8 := PackedFloat32Array(mix.map(func(m): return float(m[0])))
	var pos := 0.0
	while length - pos > 4.0:
		var m: Array = mix[rng.rand_weighted(w8)]
		var w := minf(rng.randf_range(m[4], m[5]), length - pos)
		if length - pos - w < 4.0:
			w = length - pos
		var dep := clampf(rng.randf_range(m[6], m[7]), max_depth * 0.7, max_depth)  # back to back with the row behind
		var fp := Rect2()
		for f in [Vector2(1, 1), Vector2(1, 0.5), Vector2(0.5, 0.5)]:  # squeeze in a smaller one beside a road
			var fw: float = w * f.x
			var fd: float = dep * f.y
			match side:
				0: fp = Rect2(from.x + pos, from.y, fw, fd)
				1: fp = Rect2(from.x + pos, from.y - fd, fw, fd)
				2: fp = Rect2(from.x, from.y + pos, fd, fw)
				_: fp = Rect2(from.x - fd, from.y + pos, fd, fw)
			fp = fp.grow(-0.35)
			if fp.size.x >= 3.0 and fp.size.y >= 3.0 and not blocked(C, fp):
				break
			fp = Rect2()
		pos += w
		if fp.size == Vector2.ZERO:
			continue
		var floors := maxi(1, roundi(rng.randf_range(m[2], m[3] + 0.99) * lerpf(1.0, 0.55, clampf(near / 90.0, 0.0, 1.0))))
		out.append(_building(rng, m[1], fp, floors))


static func _building(rng: RandomNumberGenerator, style: int, fp: Rect2, floors: int) -> Dictionary:
	var tints: Array = TINTS[style]
	var gable := style in [HOUSE, WOOD] and floors <= 2
	return {"rect": fp, "floors": maxi(1, floors), "style": style, "tint": Color(tints[rng.randi() % tints.size()]) * rng.randf_range(0.94, 1.04), "accent": rng.randi() % 8, "roof": ROOFS[rng.randi() % ROOFS.size()] if gable else "", "kit": rng.randf()}
