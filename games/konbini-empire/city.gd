extends RefCounted
## Tokyo as a city-builder map. Districts sit at their real relative places; the bay, the Sumida and the parks
## are carved out; blocks come from splitting the city again and again (so side streets meet in T-junctions and
## never line up into one grid), bridging the river, stopping at quays on the bay and ending on a road round every
## park; curved avenues and the elevated Shuto expressway over some of them (with ramps down to the avenue below) cut
## across. Every road ends on another road, at a quay or off the map, and every ramp and expressway end on its deck or its road. The Yamanote's viaduct is laid last, through the
## landmarks and lots, on curves no tighter than RAIL_R and clear of the parks, with a station by each of its
## districts; what it cannot keep off is placed again round it. Built once and cached: Tokyo never changes, only who
## holds which lot. Node-free; buildings() is only for the view.

const ROAD := 9.2  # sidewalk, two lanes, sidewalk: the street the shop view draws
const SIDEWALK := 2.2
const AVENUE := 13.0
const CARRIER := 17.0  # an avenue with the expressway above it
const EXPRESS_W := 9.0
const RAMP_W := 4.0
const RAIL_DECK := 3.4
const CAR_H := 2.8  # a train car, rail to roof
const DECK := RAIL_DECK + 0.3 + CAR_H + 0.5 + 0.6  # the expressway's slab clears a train on the viaduct under it
const FLOOR := 3.0
const LOT_W := 22.0
const LOT_D := 10.0
const SET_PARTS := [  # the shop view's set round a lot, from the lot's (x0, front): [footprint, how tall]
	[Rect2(1.4, 0.0, 2.6, 0.8), 1.9],  # the vending machine and gacha row on the sidewalk
	[Rect2(4.5, -9.2, 13.1, 9.4), 4.7],  # your shop's unit, the water tank on its roof
	[Rect2(17.6, -9.05, 7.1, 9.05), 1.6],  # the car park, a car in its bay
	[Rect2(23.8, -9.5, 0.4, 0.4), 7.15],  # the pole sign
	[Rect2(33.05, -9.0, 16.7, 9.95), 5.6],  # the rival at MEGAMART's width, its stair hatch, its awning
]
const SET_SEEN := Rect2(1.4, -9.2, 16.2, 12.7)  # what the shop view looks at: your shop and the sidewalk at its door
const URBAN := 92.0  # built-up land reaches this far from the nearest district centre
const MOAT := 6.0
const RIVER_W := 16.0
const RAMP_L := 46.0 * DECK / 6.0  # a 1:7.7 grade up to the deck
const MERGE_L := 20.0  # a ramp's level top, easing into the deck's outer lanes
const BRIDGE := 30.0  # the longest water a side street bridges (the Sumida at a slant); longer, it stops at a quay
# the Yamanote: a double-track viaduct, straight between its stations and round every corner on a RAIL_R curve; one
# width all the way, the tracks spaced for an island platform between them at each station
const RAIL_R := 30.0  # the tightest curve: a car's middle sits CAR_L^2 / 8 R = 0.2 m off the track
const CAR_L := 7.0
const CAR_W := 2.6
const PLATFORM_W := 1.8
const TRACK := PLATFORM_W / 2 + CAR_W / 2  # each track's offset from the viaduct's centre line
const RAIL_W := 2.0 * (TRACK + CAR_W / 2 + 0.3)
const RAIL_CLEAR := RAIL_W / 2 + 1.2  # what buildings, lots and landmarks keep off its centre line
const PLATFORM_L := 34.0
const STATION_OFF := 11.0 + RAIL_CLEAR + 0.5  # a 22 m landmark square at the district centre stays clear of it
const STATION_OFFS := [STATION_OFF, STATION_OFF + 4.0, STATION_OFF + 8.0]  # further out where that runs clearer
const PIER_GAP := 12.0  # a pier about this often, slid off the roads under the viaduct
const MAX_SPAN := 42.0  # the longest girder between piers: over an avenue it crosses at a slant, or an expressway junction
const DECK_SPAN := 45.0  # the expressway's longest, where its pillars step aside for the viaduct under it
const RUN_OFF := 28.0  # the pillar spacing where a radial route runs off over the country
const CAR_GAP := 0.6
const CARS := 4  # a train
const TRAINS := 3  # a track
const TRAIN_V := 14.0
const TRAIN_A := 2.5
const DWELL := 5.0

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
const BAY := [Vector2(-380, 1000), Vector2(-140, 480),Vector2(-70, 330), Vector2(2, 268), Vector2(26, 205), Vector2(42, 152), Vector2(56, 114), Vector2(76, 100), Vector2(100, 100), Vector2(112, 92), Vector2(122, 52), Vector2(175, 44), Vector2(260, 38), Vector2(460, 30), Vector2(520, 480), Vector2(640, 1000)]  # open to the south
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
	if pts.size() < 2:
		return [pts[0], Vector2.RIGHT]
	s = clampf(s, 0.0, cum[-1])
	var i := clampi(cum.bsearch(s), 1, pts.size() - 1)
	var seg := cum[i] - cum[i - 1]
	var t := (s - cum[i - 1]) / seg if seg > 0.0 else 0.0
	return [pts[i - 1].lerp(pts[i], t), (pts[i] - pts[i - 1]).normalized()]


## [point, unit tangent] at s along the Yamanote, any s (it is a loop).
static func rail_at(C: Dictionary, s: float) -> Array:
	return at(C.rail_loop, C.rail_cum, fposmod(s, C.rail_cum[-1]))


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


## Distance from p to the nearest park with a road round it (0 in one), by the usual ellipse estimate; the
## palace's edge is its moat, water.
static func park_dist(C: Dictionary, p: Vector2) -> float:
	var d := INF
	for pk in C.parks:
		if pk.name == "Imperial Palace":
			continue
		var r: Vector2 = pk.radii
		var q: Vector2 = (p - pk.center).abs()
		var k0 := (q / r).length()
		d = minf(d, 0.0 if k0 <= 1.0 else k0 * (k0 - 1.0) / (q / (r * r)).length())
	return d


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


static func unreserve(C: Dictionary, r: Rect2) -> void:
	for k in _bucket_keys(r):
		C.reserved.get(k, []).erase(r)


## Distance from p to the Yamanote's centre line (INF beyond 24 m).
static func rail_dist(C: Dictionary, p: Vector2) -> float:
	if not C.has("rail_buckets"):
		C.rail_buckets = {}
		for i in C.rail.size():
			var a: Vector2 = C.rail[i]
			var b: Vector2 = C.rail[(i + 1) % C.rail.size()]
			for key in _bucket_keys(Rect2(a, Vector2.ZERO).expand(b).grow(24.0)):
				if not C.rail_buckets.has(key):
					C.rail_buckets[key] = []
				C.rail_buckets[key].append([a, b])
	var d := INF
	for sg in C.rail_buckets.get(Vector2i(floori(p.x / 24.0), floori(p.y / 24.0)), []):
		d = minf(d, Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1]).distance_to(p))
	return d


## True when a footprint comes within RAIL_CLEAR of the Yamanote's centre line.
static func _on_rail(C: Dictionary, r: Rect2) -> bool:
	var reach := r.size.length() / 2 + RAIL_CLEAR + 4.0
	for i in C.rail.size():
		if C.rail[i].distance_to(r.get_center()) < reach and seg_rect_dist(C.rail[i], C.rail[(i + 1) % C.rail.size()], r) < RAIL_CLEAR:
			return true
	return false


## True when p is in a part of the shop view's set round any lot (a pier or pillar steps out of it).
static func in_set(C: Dictionary, p: Vector2) -> bool:
	for L in C.lots:
		if p.distance_to(Vector2(L.x0, L.front)) < 60.0:
			for pt in SET_PARTS:
				if Rect2(Vector2(L.x0, L.front) + pt[0].position, pt[0].size).grow(1.0).has_point(p):
					return true
	return false


## True when a deck comes down on the shop view's set round a lot: a part of it reaches the underside of the viaduct
## (RAIL_CLEAR off its centre line) or of an expressway or ramp over it, or a pier of the viaduct stands in it, or a
## deck stands in front of your shop where the shop view would see it over the shop (SET_SEEN).
static func under_deck(C: Dictionary, x0: float, front: float) -> bool:
	var lot := Vector2(x0, front)
	var decks: Array = C.shuto.map(func(sh): return [sh.pts, sh.closed, EXPRESS_W]) + C.get("ramps", []).map(func(rp): return [rp.pts, false, RAMP_W])
	if C.has("rail"):
		if not C.has("rail3"):
			C.rail3 = PackedVector3Array(Array(C.rail).map(func(p): return Vector3(p.x, RAIL_DECK, p.y)))
		if _hides([C.rail3, true, RAIL_W], Rect2(lot + SET_SEEN.position, SET_SEEN.size)):
			return true
	for pt in SET_PARTS:
		var q := Rect2(lot + pt[0].position, pt[0].size)
		if C.has("rail") and ((pt[1] > RAIL_DECK - 0.6 and _on_rail(C, q)) or C.get("piers", []).any(func(pr): return q.grow(1.0).has_point(pr[1]))):
			return true
		for dk in decks:
			if _deck_over(dk, q, pt[1]):
				return true
	return decks.any(func(dk): return _hides(dk, Rect2(lot + SET_SEEN.position, SET_SEEN.size)))


## True when deck dk [pts (y its top), closed, width] stands in front of the ground r and hides some of it, slab to
## parapet, as the shop view sees it: looking down 30 degrees from the south-east (x + z grows toward it), on a 1 m grid.
static func _hides(dk: Array, r: Rect2) -> bool:
	var iso := func(p: Vector3) -> Vector2: return Vector2((p.x - p.z) * 0.7071, (p.x + p.z) * 0.3536 - p.y * 0.866)
	var box: Rect2 = Rect2(iso.call(Vector3(r.position.x, 0, r.end.y)), Vector2.ZERO).expand(iso.call(Vector3(r.end.x, 0, r.position.y))).expand(iso.call(Vector3(r.position.x, 0, r.position.y))).expand(iso.call(Vector3(r.end.x, 0, r.end.y)))
	var pts: PackedVector3Array = dk[0]
	var n := pts.size()
	for i in range(1, n + (1 if dk[1] else 0)):
		var a := pts[i - 1]
		var b := pts[i % n]
		if maxf(a.y, b.y) <= 1.5 or Vector2(a.x, a.z).distance_to(r.get_center()) > 40.0:
			continue
		var side: Vector3 = Vector3(b.z - a.z, 0, a.x - b.x).normalized() * dk[2] / 2
		var hull := PackedVector2Array()
		for e in [a, b]:
			for sd in [side, -side]:
				for y in [-0.6, 0.9]:
					hull.append(iso.call(e + sd + Vector3(0, y, 0)))
		hull = Geometry2D.convex_hull(hull)
		var hb := Rect2(hull[0], Vector2.ZERO)
		for h in hull:
			hb = hb.expand(h)
		if not hb.intersects(box):
			continue
		var depth := (a.x + a.z + b.x + b.z) / 2
		for gx in ceili(r.size.x) + 1:
			for gz in ceili(r.size.y) + 1:
				var q := r.position + Vector2(minf(gx, r.size.x), minf(gz, r.size.y))
				if depth > q.x + q.y + 1.0 and Geometry2D.is_point_in_polygon(iso.call(Vector3(q.x, 0, q.y)), hull):
					return true
	return false


## True when deck dk [pts, closed, width] passes over r with its underside lower than `top`.
static func _deck_over(dk: Array, r: Rect2, top: float) -> bool:
	var pts: PackedVector3Array = dk[0]
	var n := pts.size()
	for i in range(1, n + (1 if dk[1] else 0)):
		var a := pts[i - 1]
		var b := pts[i % n]
		if maxf(a.y, b.y) > 1.5 and minf(a.y, b.y) - 0.6 < top and seg_rect_dist(Vector2(a.x, a.z), Vector2(b.x, b.z), r) < dk[2] / 2 + 0.5:
			return true  # (at 1.5 m or lower it is down on the avenue it runs on: road, not deck)
	return false


## True when a footprint would sit on a road corridor, water (unless `wet`), a park, or a reserved lot or landmark.
static func blocked(C: Dictionary, r: Rect2, wet := false) -> bool:
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
			if (not wet and is_water(C, p)) or in_park(C, p):
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
	for av in AVENUES:
		var pts := smooth(av.pts)
		C.avenues.append({"name": av.name, "w": av.w, "pts": pts, "shuto": av.get("shuto", "")})
		if av.has("shuto"):
			C.shuto.append({"name": av.shuto, "pts": _deck(pts, DECK), "closed": false})
	C.shuto.append({"name": "11", "pts": _deck(smooth(RAINBOW), DECK), "closed": false, "lands": true})  # comes down onto Odaiba
	_add_corridor(C, _flat(C.shuto[0].pts), EXPRESS_W / 2 + 1.5, true)
	# blocks and side streets
	var rng := RandomNumberGenerator.new()
	rng.seed = 1964
	var raw := []
	var leaves := []
	_split(C, Rect2(-480, -420, 960, 840), 0, rng, raw, leaves)
	C.blocks = []
	var bounds := Rect2()
	for r in leaves:
		var c: Vector2 = r.get_center()
		var n := nearest(C, c)
		if n[1] < URBAN and r.size.x > 12.0 and r.size.y > 12.0 and not is_water(C, c) and not in_park(C, c):
			C.blocks.append({"rect": r, "d": n[0]})
			bounds = r if bounds.size == Vector2.ZERO else bounds.merge(r)
	C.bounds = bounds.grow(20.0)
	C.streets = _streets(C, raw)
	_land(C)
	_trim_avenues(C)
	C.avenues.append_array(_edge_roads(C))
	for av in C.avenues:
		_add_corridor(C, av.pts, av.w / 2 + 0.6)
	_place_landmarks(C)
	_place_lots(C)
	_place_landmarks_late(C)
	_yamanote(C)
	_ramps(C)
	C.piers = _piers(C)
	# what the line could not keep off is placed again, by its own rule, round it
	for L in C.landmarks.duplicate():
		var sq := Rect2(L.pos - Vector2.ONE * L.size / 2, Vector2.ONE * L.size)
		if not in_park(C, L.pos) and _on_rail(C, sq):
			C.landmarks.erase(L)
			unreserve(C, sq)
	var lost := {}  # districts whose lots the line, or a deck over the shop view's set, took
	for L in C.lots.duplicate():
		var r := Rect2(L.x0, L.front - LOT_D, LOT_W, LOT_D)
		if _on_rail(C, r) or under_deck(C, L.x0, L.front):
			C.lots.erase(L)
			unreserve(C, r)
			lost[L.block] = true
	_place_lots(C, lost.keys())
	_place_landmarks_late(C)
	_run_off(C)
	return C


## The radial routes and the avenues under them run on straight out over the country past the ground's edge
## (C.bounds grown by 1300), a point and a pillar every RUN_OFF m, so none stops dead in a field. Done last: the city
## round them is already laid out. C.run_off keeps each stretch [from, to, half the avenue's width] for the farmland.
static func _run_off(C: Dictionary) -> void:
	var edge: Rect2 = C.bounds.grow(1300.0)
	C.run_off = []
	for sh in C.shuto:
		if sh.closed or sh.get("lands", false):
			continue
		var pts: PackedVector3Array = sh.pts
		var n := pts.size()
		sh.mid = int(n / 2.0)
		var dir := (pts[-1] - pts[-2]).normalized()
		var from := Vector2(pts[-1].x, pts[-1].z)
		while edge.has_point(Vector2(pts[-1].x, pts[-1].z)):
			pts.append(pts[-1] + dir * RUN_OFF)
		sh.pts = pts
		for av in C.avenues:
			if av.shuto == sh.name and av.pts[-1].distance_to(from) < 1.0:
				av.third = int(av.pts.size() / 3.0)
				for k in range(n, pts.size()):
					av.pts.append(Vector2(pts[k].x, pts[k].z))
				C.run_off.append([from, av.pts[-1], av.w / 2])


## A route that comes down to the ground ends on a road: the last side street it crosses on land before the end it was
## drawn to, at least 2 m inside the street, coming down to it over the 1:7.7 grade of a ramp.
static func _land(C: Dictionary) -> void:
	for sh in C.shuto:
		if not sh.get("lands", false):
			continue
		var flat := _flat(sh.pts)
		var cum := cumulative(flat)
		var end := cum[-1]
		while end > 0.0:
			var q: Vector2 = at(flat, cum, end)[0]
			if is_water(C, q):
				break
			if C.streets.any(func(st): return absf(q[1 if st.axis == "h" else 0] - st.line - st.w / 2) < st.w / 2 - 2.0 and q[0 if st.axis == "h" else 1] > st.from + 2.0 and q[0 if st.axis == "h" else 1] < st.to - 2.0):
				break
			end -= 0.5
		var pts := PackedVector3Array()
		for i in cum.size():
			if cum[i] < end - 0.5:
				pts.append(sh.pts[i])
		var tip: Vector2 = at(flat, cum, end)[0]
		pts.append(Vector3(tip.x, 0.0, tip.y))
		var lcum := cumulative(_flat(pts))
		for i in pts.size():
			pts[i].y = DECK * clampf((lcum[-1] - lcum[i]) / RAMP_L, 0.0, 1.0)
		sh.pts = pts
		_add_corridor(C, _flat(pts), EXPRESS_W / 2 + 1.5)


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


## The ramps between each expressway and the avenue under it: for each direction of traffic (keeping left) an
## off-ramp and then an on-ramp, from 42% of the way along, or the nearest spot to that where all four keep clear of
## the Yamanote's viaduct (they rise through its height) and of the shop view's sets round the lots. They stay inside
## the avenue's width.
static func _ramps(C: Dictionary) -> void:
	C.ramps = []  # {pts, av: the avenue below, s0: where its slope starts along it, side: +1 left of its direction, span: s along it at pts[0] and pts[-1]}
	for ai in C.avenues.size():
		var av: Dictionary = C.avenues[ai]
		if av.shuto == "":
			continue
		var pts: PackedVector2Array = av.pts
		var cum := cumulative(pts)
		var span := RAMP_L * 2.0 + 24.0
		var set_ := []
		for k in 80:  # 42%, then 4 m further each way in turn
			var s0: float = cum[-1] * 0.42 + 4.0 * ceili(k / 2.0) * (1 if k % 2 == 0 else -1)
			if s0 - MERGE_L < 0.0 or s0 + span + MERGE_L > cum[-1]:
				continue
			set_ = []
			for side in [1.0, -1.0]:
				for s in [s0, s0 + RAMP_L + 24.0]:
					var rp := _ramp(pts, cum, s, side, s == s0)  # the tops at the outer ends: off the deck first, on again after
					rp.av = ai
					rp.side = side
					set_.append(rp)
			if set_.all(func(rp): return Array(_flat(rp.pts)).all(func(p): return rail_dist(C, p) > RAIL_W / 2 + RAMP_W / 2 + 0.5) and not C.lots.any(func(L): return SET_PARTS.any(func(pt): return _deck_over([rp.pts, false, RAMP_W], Rect2(Vector2(L.x0, L.front) + pt[0].position, pt[0].size), pt[1])))):
				break
		C.ramps.append_array(set_)
	for rp in C.ramps:
		_add_corridor(C, _flat(rp.pts), RAMP_W / 2 + 1.0)


## A ramp whose slope runs from s0 to s0 + RAMP_L on `side` (+1 left of the avenue's direction), coming down (or going
## up) from flush against the deck's edge to the avenue's outer lane. At the top it runs on level for MERGE_L, easing
## in over the deck's outer lanes until its outer edge is the deck's (before s0 when it comes down, after the slope
## when it goes up), so its lane carries on into the deck's: {pts, s0, span}.
static func _ramp(pts: PackedVector2Array, cum: PackedFloat32Array, s0: float, side: float, down: bool) -> Dictionary:
	var ground := CARRIER / 2 - SIDEWALK - RAMP_W / 2
	var flush := EXPRESS_W / 2 + RAMP_W / 2
	var inside := EXPRESS_W / 2 - RAMP_W / 2
	var rows := []  # [s along the avenue, height, offset from its centre line]
	var n := 12
	for k in n + 1:
		var f := float(k) / n
		var y := DECK * ((1.0 - f) if down else f)
		rows.append([s0 + RAMP_L * f, y, lerpf(ground, flush, y / DECK)])
	for k in range(1, 7):
		var g := k / 6.0
		var row := [s0 - MERGE_L * g if down else s0 + RAMP_L + MERGE_L * g, DECK, lerpf(flush, inside, smoothstep(0.0, 1.0, g))]
		if down:
			rows.push_front(row)
		else:
			rows.append(row)
	var out := PackedVector3Array()
	for r in rows:
		var pt: Array = at(pts, cum, r[0])
		var p: Vector2 = pt[0] + Vector2(pt[1].y, -pt[1].x) * side * r[2]
		out.append(Vector3(p.x, r[1], p.y))
	return {"pts": out, "s0": s0, "span": Vector2(rows[0][0], rows[-1][0])}


## Every elevated carriageway, the expressway's routes and then the ramps, as {pts (a loop's first point repeated at its
## end), cum (arc length at each point), w, closed, ramp}; with a grid of their segments for line_runs.
static func elevated(C: Dictionary) -> Array:
	if C.has("elevated"):
		return C.elevated
	C.elevated = []
	for sh in C.shuto:
		var pts: PackedVector3Array = sh.pts.duplicate()
		if sh.closed:
			pts.append(pts[0])
		C.elevated.append({"pts": pts, "w": EXPRESS_W, "closed": sh.closed, "ramp": false})
	for rp in C.ramps:
		C.elevated.append({"pts": rp.pts, "w": RAMP_W, "closed": false, "ramp": true})
	C.deck_grid = {}
	C.line_cache = {}
	for ri in C.elevated.size():
		var e: Dictionary = C.elevated[ri]
		e.cum = cumulative(_flat(e.pts))
		for k in e.pts.size() - 1:
			for key in _cells(Rect2(Vector2(e.pts[k].x, e.pts[k].z), Vector2.ZERO).expand(Vector2(e.pts[k + 1].x, e.pts[k + 1].z)).grow(e.w / 2)):
				if not C.deck_grid.has(key):
					C.deck_grid[key] = []
				C.deck_grid[key].append([ri, k])
	return C.elevated


static func _cells(r: Rect2) -> Array:
	var out := []
	for bx in range(floori(r.position.x / 8.0), floori(r.end.x / 8.0) + 1):
		for bz in range(floori(r.position.y / 8.0), floori(r.end.y / 8.0) + 1):
			out.append(Vector2i(bx, bz))
	return out


## Whether p lies inside an elevated carriageway other than ri, on its surface (within 5 cm of its height).
static func _in_other(C: Dictionary, ri: int, p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	for hit in C.deck_grid.get(Vector2i(floori(q.x / 8.0), floori(q.y / 8.0)), []):
		if hit[0] == ri:
			continue
		var e: Dictionary = C.elevated[hit[0]]
		var a: Vector3 = e.pts[hit[1]]
		var b: Vector3 = e.pts[hit[1] + 1]
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var c := Geometry2D.get_closest_point_to_segment(q, a2, b2)
		var t := 0.0 if a2 == b2 else clampf((c - a2).dot(b2 - a2) / a2.distance_squared_to(b2), 0.0, 1.0)
		if c.distance_to(q) < e.w / 2 - 0.05 and absf(lerpf(a.y, b.y, t) - p.y) < 0.05:
			return true
	return false


## Where a parapet or a painted line at lateral offset `off` (left of the points' direction positive) stands along
## elevated carriageway ri, as [from, to] arc lengths: everywhere but inside another carriageway on the same level, so
## a ramp's level top and the deck it eases into, or two routes at a junction, open into each other instead of
## walling each other off. Sampled every half metre near other carriageways.
static func line_runs(C: Dictionary, ri: int, off: float) -> Array:
	var e: Dictionary = elevated(C)[ri]
	var key := "%d:%.2f" % [ri, off]
	if C.line_cache.has(key):
		return C.line_cache[key]
	var runs := []
	var pts: PackedVector3Array = e.pts
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var d := Vector2(b.x - a.x, b.z - a.z)
		var len_ := d.length()
		if len_ <= 0.0:
			continue
		var left := Vector3(d.y, 0, -d.x) / len_
		var near := false
		for cell in _cells(Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(absf(off) + 0.5)):
			if C.deck_grid.get(cell, []).any(func(hit): return hit[0] != ri):
				near = true
				break
		var n := ceili(len_ / 0.5) if near else 1
		for j in n:
			if near and _in_other(C, ri, a.lerp(b, (j + 0.5) / n) + left * off):
				continue
			var s0: float = e.cum[k] + len_ * j / n
			var s1: float = e.cum[k] + len_ * (j + 1) / n
			if not runs.is_empty() and absf(runs[-1][1] - s0) < 0.001:
				runs[-1][1] = s1
			else:
				runs.append([s0, s1])
	C.line_cache[key] = runs
	return runs


## The Yamanote, laid through the city's landmarks and lots: a loop past its stations, straight between
## them and round each corner on a RAIL_R curve, so no curve is tighter. It passes STATION_OFF to one side of each
## station's district centre (a station on a corner has its corner set out so the curve does), which leaves the
## centre's 22 m square to the district's landmark beside the station: each station takes the side, toward the
## loop's middle or away, where the straights either side of it run least over parks and landmarks. Where the
## viaduct, its full width, would still run over a park, its ring road or the palace moat, a corner is added on the
## far side of that margin (or the one added for it moved further out) until it runs clear. Each station stands on
## the line where it passes nearest its district centre: C.stations [{d, s, pos}], s along C.rail, the loop's points
## (C.rail_loop repeats the first at the end).
static func _yamanote(C: Dictionary) -> void:
	var cs := []
	var di_of := []
	for stn in YAMANOTE:
		for di in C.districts.size():
			if C.districts[di].name == stn:
				cs.append(C.districts[di].center)
				di_of.append(di)
	var keep := []  # [centre, radii]
	for pk in C.parks:
		var m: float = (MOAT if pk.name == "Imperial Palace" else ROAD) + RAIL_W / 2 + 1.0
		keep.append([pk.center, pk.radii + Vector2(m, m)])
	# [footprint grown by RAIL_CLEAR, weight]: the landmarks, the lots, and each district's centre square
	var squares: Array = C.landmarks.map(func(L): return [Rect2(L.pos - Vector2.ONE * L.size / 2, Vector2.ONE * L.size).grow(RAIL_CLEAR), 10.0])
	squares.append_array(C.lots.map(func(L): return [Rect2(L.x0, L.front - LOT_D, LOT_W, LOT_D).grow(RAIL_CLEAR), 10.0]))
	for d in C.districts:
		if not in_park(C, d.center):
			squares.append([Rect2(d.center - Vector2(11, 11), Vector2(22, 22)).grow(RAIL_CLEAR), 1.0])
	var sq_at := {}  # bucket -> the squares over it
	for q in squares:
		for key in _bucket_keys(q[0]):
			if not sq_at.has(key):
				sq_at[key] = []
			sq_at[key].append(q)
	var decks := {}  # bucket -> expressway segments: the viaduct may pass under one, not run along under it
	for sh in C.shuto:
		var fl := _flat(sh.pts)
		for k in fl.size() - (0 if sh.closed else 1):
			var sg := [fl[k], fl[(k + 1) % fl.size()]]
			for key in _bucket_keys(Rect2(sg[0], Vector2.ZERO).expand(sg[1]).grow(EXPRESS_W + RAIL_W)):
				if not decks.has(key):
					decks[key] = []
				decks[key].append(sg)
	var over := func(p: Vector2) -> float:  # how far p runs into parks' margins and footprints, metres by weight
		var d := 0.0
		for e in keep:
			d += maxf(0.0, 1.0 - ((p - e[0]) / e[1]).length()) * minf(e[1].x, e[1].y) * 10.0
		var under := 0.0
		for sg in decks.get(Vector2i(floori(p.x / 24.0), floori(p.y / 24.0)), []):
			under = maxf(under, EXPRESS_W / 2 + RAIL_W / 2 + 0.5 - Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1]).distance_to(p))
		d += under * 4.0
		for q in sq_at.get(Vector2i(floori(p.x / 24.0), floori(p.y / 24.0)), []):
			var r: Rect2 = q[0]
			if r.has_point(p):
				d += minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y)) * q[1]
		return d
	var sides := {}  # station -> its two corners: the line passing STATION_OFF to the left of its centre, or right
	for i in cs.size():
		var d0: Vector2 = (cs[i] - cs[i - 1]).normalized()
		var d1: Vector2 = (cs[(i + 1) % cs.size()] - cs[i]).normalized()
		var th := d0.angle_to(d1)
		var cut := RAIL_R * (1.0 / cos(th / 2.0) - 1.0)  # how far the curve passes inside its corner
		var inside: Vector2 = (d0 + d1).normalized().rotated(signf(th) * PI / 2.0) if absf(th) > 0.01 else d0.orthogonal()
		var left: Vector2 = (d0 + d1).normalized().orthogonal()
		sides[i] = []
		for off in STATION_OFFS:
			for n in [left, -left]:
				sides[i].append([cs[i] + n * off - inside * cut, off])
	var V: Array = cs.map(func(c): return c)
	for i in cs.size():
		V[i] = sides[i][0][0]
	for sweep in 3:
		for i in cs.size():
			var best := INF
			var pick: Vector2 = V[i]
			for cand in sides[i]:
				V[i] = cand[0]
				var f: Array = _fillet(V)
				var score: float = (cand[1] - STATION_OFF) * 2.0  # nearer its centre is better
				for k in f[0].size():
					if f[2][k] == i or f[2][k] == (i - 1 + cs.size()) % cs.size():
						score += over.call(f[0][k])
				for e in range(i - 2, i + 2):  # curves that overlap kink the line: never, if there is a choice
					score += 1e6 * f[3][posmod(e, cs.size())]
				if score < best - 0.01:
					best = score
					pick = cand[0]
			V[i] = pick
	var own := []  # per corner: -1 a station, else the margin it was added to clear
	own.resize(V.size())
	own.fill(-1)
	var line: Array = []
	for pass_ in 32:
		line = _fillet(V)
		var worst := 0.0
		var at_ := -1
		var o_ := -1
		for i in line[0].size():
			for o in keep.size():
				var k: float = ((line[0][i] - keep[o][0]) / keep[o][1]).length()
				if 1.0 - k > worst:
					worst = 1.0 - k
					at_ = i
					o_ = o
		if at_ < 0:
			break
		var c: Vector2 = keep[o_][0]
		var v: int = line[1][at_]
		var e: int = line[2][at_]
		if v < 0 or own[v] != o_:  # on a straight: either end's corner, if it was added for this park
			v = e if own[e] == o_ else ((e + 1) % V.size() if own[(e + 1) % V.size()] == o_ else -1)
		if v >= 0:
			V[v] = c + (V[v] - c) * (1.0 + worst + 0.02)
		else:  # a corner on the park's margin, where (of a dozen places round it) the whole line runs clearest
			var out: Vector2 = (line[0][at_] - c) / (1.0 - worst) * 1.02
			var r: Vector2 = keep[o_][1] * 1.02
			var best := INF
			var pick := Vector2.ZERO
			var round_ := [c + out, c - out]
			for a in 12:
				round_.append(c + Vector2(cos(TAU * a / 12.0), sin(TAU * a / 12.0)) * r)
			for w in round_:
				V.insert(e + 1, w)
				var f: Array = _fillet(V)
				var score := 0.0
				for k in f[0].size():
					score += over.call(f[0][k])
				for lap in f[3]:
					score += 1e6 * lap
				if score < best:
					best = score
					pick = w
				V.remove_at(e + 1)
			V.insert(e + 1, pick)
			own.insert(e + 1, o_)
	C.rail = line[0]
	C.rail_loop = C.rail.duplicate()
	C.rail_loop.append(C.rail[0])
	C.rail_cum = cumulative(C.rail_loop)
	C.stations = []  # each where the line passes nearest its district centre with its platform out from under the expressway
	var covered := func(i: int) -> bool:  # rail point i's platform would be under an expressway deck
		for k in range(-int(PLATFORM_L / 4.0) - 1, int(PLATFORM_L / 4.0) + 2):
			var p: Vector2 = C.rail[posmod(i + k, C.rail.size())]
			for sg in decks.get(Vector2i(floori(p.x / 24.0), floori(p.y / 24.0)), []):
				if Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1]).distance_to(p) < EXPRESS_W / 2 + RAIL_W / 2 + 1.0:
					return true
		return false
	for di in di_of:
		var c: Vector2 = C.districts[di].center
		var order := range(C.rail.size())
		order.sort_custom(func(a, b): return C.rail[a].distance_squared_to(c) < C.rail[b].distance_squared_to(c))
		var best: int = order[0]
		for i in order:
			if not covered.call(i):
				best = i
				break
		C.stations.append({"d": di, "s": C.rail_cum[best], "pos": C.rail[best]})
	_add_corridor(C, C.rail, RAIL_CLEAR, true)
	C.timetable = [_timetable(C, 1), _timetable(C, -1)]


## A closed railway alignment through corners V: straight between them, an arc of RAIL_R round each. Returns [the
## points, about every 2 m; per point the corner whose arc it is on (-1 on a straight); per point the straight it is
## on or nearest, from corner e to e + 1; per straight how far its two curves overlap]. Two curves too close to fit
## (a straight shorter than nothing) show as a kink, which the rules test catches as a curve tighter than RAIL_R.
static func _fillet(V: Array) -> Array:
	var n := V.size()
	var arcs := []
	for i in n:
		var d0: Vector2 = (V[i] - V[(i - 1 + n) % n]).normalized()
		var d1: Vector2 = (V[(i + 1) % n] - V[i]).normalized()
		var th := d0.angle_to(d1)
		var t := RAIL_R * tan(absf(th) / 2.0)
		var p0: Vector2 = V[i] - d0 * t
		arcs.append({"p0": p0, "p1": V[i] + d1 * t, "th": th, "c": p0 + d0.rotated(signf(th) * PI / 2.0) * RAIL_R})
	var pts := PackedVector2Array()
	var vx := PackedInt32Array()
	var ed := PackedInt32Array()
	var lap := PackedFloat32Array()
	for i in n:
		lap.append(maxf(0.0, arcs[i].p1.distance_to(V[i]) + arcs[(i + 1) % n].p0.distance_to(V[(i + 1) % n]) - V[i].distance_to(V[(i + 1) % n])))
	for i in n:
		var A: Dictionary = arcs[i]
		var m := maxi(1, ceili(absf(A.th) * RAIL_R / 2.0))
		for j in m:
			pts.append(A.c + (A.p0 - A.c).rotated(A.th * j / m))
			vx.append(i)
			ed.append((i - 1 + n) % n if j * 2 < m else i)
		var B: Dictionary = arcs[(i + 1) % n]
		var m2 := maxi(1, ceili(A.p1.distance_to(B.p0) / 2.0))
		for j in m2:
			pts.append(A.p1.lerp(B.p0, float(j) / m2))
			vx.append(-1)
			ed.append(i)
	return [pts, vx, ed, lap]


## Where the viaduct's piers stand: about every PIER_GAP along it, each one column under the deck, slid (up to half a
## gap along, or out under either side) to the nearest spot off every carriageway (a sidewalk will do) and the water,
## or onto an avenue's median as the expressway's are. [s, column point, unit tangent] each.
static func _piers(C: Dictionary) -> Array:
	var L: float = C.rail_cum[-1]
	var n := floori(L / PIER_GAP)
	var out := []
	for k in n:
		var hit := false
		for dd in range(0, int(PIER_GAP / 2) + 1):
			for sgn in ([1.0] if dd == 0 else [1.0, -1.0]):
				var s := fposmod(L * k / n + dd * sgn, L)
				var pt := rail_at(C, s)
				for f in [0.0, 1.0, -1.0, 2.0, -2.0]:
					var p: Vector2 = pt[0] + Vector2(pt[1].y, -pt[1].x) * f * (RAIL_W / 2 - 0.8) / 2.0
					if pier_ok(C, p) and not in_set(C, p):
						out.append([s, p, pt[1]])
						hit = true
						break
				if hit:
					break
			if hit:
				break
	return out


## Where the expressway's and its ramps' pillars stand, as [route (C.shuto, then C.ramps), point index]: about every
## 14 m where the deck is high enough to need one (a ramp's level top is the deck widened, on the deck's own), each slid along its deck (up to two points either way) off the
## Yamanote's viaduct where that passes under, and out of the shop view's sets. A loop's points run on past its start,
## as the view draws it.
static func deck_pillars(C: Dictionary) -> Array:
	var out := []
	var routes: Array = C.shuto.map(func(sh): return [sh.pts, sh.closed, 1.5, INF]) + C.ramps.map(func(rp): return [rp.pts, false, 1.0, DECK - 0.01])
	for ri in routes.size():
		var pts: PackedVector3Array = routes[ri][0].duplicate()
		if routes[ri][1]:
			pts.append(pts[0])
			pts.append(pts[1])
		var walked := 14.0
		for k in range(1, pts.size()):
			walked += pts[k - 1].distance_to(pts[k])
			if walked >= 14.0 and pts[k].y > 1.5 and pts[k].y < routes[ri][3]:
				walked = 0.0
				for dk in [0, 1, -1, 2, -2]:
					var q: int = k + dk
					var foot := Vector2(pts[q].x, pts[q].z) if q >= 0 and q < pts.size() else Vector2.INF
					if foot != Vector2.INF and pts[q].y > 1.5 and pts[q].y < routes[ri][3] and rail_dist(C, foot) > RAIL_W / 2 + routes[ri][2] / 2 + 0.4 and not in_set(C, foot):
						out.append([ri, q, pts[q], routes[ri][2]])
						break
	return out


## True where a 1.2 m column can stand: not in water, nor in any road's lanes, unless on the median of an avenue that
## carries no expressway.
static func pier_ok(C: Dictionary, p: Vector2) -> bool:
	if not C.has("ground"):
		var roads := {}  # bucket -> [a, b, half the lanes, median]: every street and avenue at ground level
		var segs := []
		for st in C.streets:
			var c: float = st.line + st.w / 2
			segs.append([Vector2(st.from, c), Vector2(st.to, c), st.w / 2 - SIDEWALK, false] if st.axis == "h" else [Vector2(c, st.from), Vector2(c, st.to), st.w / 2 - SIDEWALK, false])
		for av in C.avenues:
			for k in av.pts.size() - 1:
				segs.append([av.pts[k], av.pts[k + 1], av.w / 2 - SIDEWALK, av.w >= AVENUE and av.shuto == ""])  # a carrier's median is the expressway's
		for sg in segs:
			for key in _bucket_keys(Rect2(sg[0], Vector2.ZERO).expand(sg[1]).grow(sg[2] + 1.0)):
				if not roads.has(key):
					roads[key] = []
				roads[key].append(sg)
		C.ground = roads
	if is_water(C, p):
		return false
	var on_median := false
	var in_lanes := false
	for sg in C.ground.get(Vector2i(floori(p.x / 24.0), floori(p.y / 24.0)), []):
		var d := Geometry2D.get_closest_point_to_segment(p, sg[0], sg[1]).distance_to(p)
		if sg[3] and d < 0.8:
			on_median = true
		elif d < sg[2] + 0.6:
			in_lanes = true
	return on_median or not in_lanes


## The timetable of the trains running the loop forward (dir 1) or back (-1): {period, legs [[u, length, run
## seconds]]}, u measured along the way they run. A leg is DWELL at a station, then a run at TRAIN_A up to TRAIN_V
## (if it has room) and down to the next.
static func _timetable(C: Dictionary, dir: int) -> Dictionary:
	var L: float = C.rail_cum[-1]
	var us: Array = C.stations.map(func(st): return st.s if dir > 0 else fposmod(L - st.s, L))
	us.sort()
	var legs := []
	var period := 0.0
	for i in us.size():
		var D: float = fposmod(us[(i + 1) % us.size()] - us[i], L)
		var T := 2.0 * sqrt(D / TRAIN_A) if D < TRAIN_V * TRAIN_V / TRAIN_A else D / TRAIN_V + TRAIN_V / TRAIN_A
		legs.append([us[i], D, T])
		period += DWELL + T
	return {"period": period, "legs": legs}


## Where along C.rail (s) the middle of train k on track `dir` is at time t (seconds): the trains on a track keep one
## timetable a third of its period apart, so they never close up.
static func train_s(C: Dictionary, dir: int, k: int, t: float) -> float:
	var tt: Dictionary = C.timetable[0 if dir > 0 else 1]
	var L: float = C.rail_cum[-1]
	t = fposmod(t + tt.period * k / TRAINS, tt.period)
	for leg in tt.legs:
		if t < DWELL + leg[2]:
			var tau := maxf(t - DWELL, 0.0)
			var D: float = leg[1]
			var T: float = leg[2]
			var ta := minf(TRAIN_V / TRAIN_A, T / 2.0)
			var v := TRAIN_A * ta
			var u: float
			if tau < ta:
				u = 0.5 * TRAIN_A * tau * tau
			elif tau > T - ta:
				u = D - 0.5 * TRAIN_A * (T - tau) * (T - tau)
			else:
				u = 0.5 * v * ta + v * (tau - ta)
			u += leg[0]
			return fposmod(u if dir > 0 else L - u, L)
		t -= DWELL + leg[2]
	return fposmod(tt.legs[0][0] if dir > 0 else L - tt.legs[0][0], L)


## kd-style split: cut the rectangle with a street across it until blocks are about the local block size.
static func _split(C: Dictionary, r: Rect2, depth: int, rng: RandomNumberGenerator, streets: Array, leaves: Array) -> void:
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
		streets.append({"axis": "v", "line": at_ - w / 2, "from": r.position.y, "to": r.end.y, "w": w})
		_split(C, Rect2(r.position.x, r.position.y, at_ - w / 2 - r.position.x, r.size.y), depth + 1, rng, streets, leaves)
		_split(C, Rect2(at_ + w / 2, r.position.y, r.end.x - at_ - w / 2, r.size.y), depth + 1, rng, streets, leaves)
	else:
		streets.append({"axis": "h", "line": at_ - w / 2, "from": r.position.x, "to": r.end.x, "w": w})
		_split(C, Rect2(r.position.x, r.position.y, r.size.x, at_ - w / 2 - r.position.y), depth + 1, rng, streets, leaves)
		_split(C, Rect2(r.position.x, at_ + w / 2, r.size.x, r.end.y - at_ - w / 2), depth + 1, rng, streets, leaves)


## The streets: each split line runs exactly where it bounds a block, so every end is a block's corner, where the
## street round that block's side meets it. That street either goes on across the end (a T: `j` is its width, the
## mouth the view paints) or stops there too (a corner: both run across each other and `j` is minus the width
## crossed, so the view turns the sidewalk round the outside). It bridges the river (`bridges`, from-to along it)
## and stops at a quay where it runs into the bay or along the water (`quay`), and stops on the road round a park
## where it reaches one (`j` 0 at both). No street ends anywhere else.
static func _streets(C: Dictionary, raw: Array) -> Array:
	# per split line, [from, to, end at from, end at to, bridges]: where blocks bound it, joined across the streets
	# between them, less the water and parks it would cross (an end "" is a block's corner)
	var runs := []
	for s in raw:
		var spans := []
		for b in C.blocks:
			var r: Rect2 = b.rect
			var lo: float = r.position.x if s.axis == "h" else r.position.y
			var hi: float = r.end.x if s.axis == "h" else r.end.y
			var before: float = r.end.y if s.axis == "h" else r.end.x  # the side of a block before the street
			var after: float = r.position.y if s.axis == "h" else r.position.x
			if (absf(before - s.line) < 0.01 or absf(after - s.line - s.w) < 0.01) and lo < s.to and hi > s.from:
				spans.append([maxf(lo, s.from), minf(hi, s.to)])
		spans.sort()
		var joined := []
		for sp in spans:
			if not joined.is_empty() and sp[0] - joined[-1][1] <= AVENUE + 1.0:
				joined[-1][1] = maxf(joined[-1][1], sp[1])
			else:
				joined.append(sp)
		var pieces := []
		for rn in joined:
			pieces.append_array(_cut(C, s, rn[0], rn[1]))
		runs.append(pieces)
	var out := []
	for i in raw.size():
		var s: Dictionary = raw[i]
		for rn in runs[i]:
			var st := {"axis": s.axis, "line": s.line, "from": rn[0], "to": rn[1], "w": s.w, "j": [0.0, 0.0], "quay": [rn[2] == "quay", rn[3] == "quay"], "bridges": rn[4]}
			for e in 2:
				if rn[2 + e] != "":
					continue
				var dir := 1.0 if e == 1 else -1.0
				for k in raw.size():
					var x: Dictionary = raw[k]
					if x.axis == s.axis or absf((x.line + x.w if e == 0 else x.line) - rn[e]) > 0.01 or x.from > s.line + s.w + 0.01 or x.to < s.line - 0.01:
						continue
					var meets: Array = runs[k].filter(func(q): return q[0] <= s.line + s.w + 0.01 and q[1] >= s.line - 0.01)
					if meets.any(func(q): return q[0] <= s.line + 0.01 and q[1] >= s.line + s.w - 0.01):
						st.j[e] = x.w
					elif not meets.is_empty():
						st.j[e] = -x.w
						st[["from", "to"][e]] = rn[e] + dir * x.w
					else:
						# the street round the corner stopped at the water short of this one: run on to the quay
						var at_: float = rn[e]
						var c: float = s.line + s.w / 2
						while absf(at_ - rn[e]) < x.w + 6.0 and not is_water(C, Vector2(at_ + dir, c) if s.axis == "h" else Vector2(c, at_ + dir)):
							at_ += dir
						st[["from", "to"][e]] = at_
						st.quay[e] = true
					break
			out.append(st)
	return out


## A street's run from a to b, less what it can't cross: it bridges water up to BRIDGE across with land beyond, and
## otherwise stops at a quay half a metre short of it; at a park it stops where its centre reaches the lanes of the
## road round it, and only grazes that road where it never gets that close. [from, to, end at from, end at to,
## bridges], an end "quay", "park" or "" (where the run itself ends).
static func _cut(C: Dictionary, s: Dictionary, a: float, b: float) -> Array:
	var n := maxi(1, ceili(b - a))
	var xs := []
	var wet := []
	var near := []  # 0 clear of parks, 1 its lanes run into the park road's, 2 its centre is on the park road's lanes
	for k in n + 1:
		var x := lerpf(a, b, float(k) / n)
		var p := Vector2(x, s.line + s.w / 2) if s.axis == "h" else Vector2(s.line + s.w / 2, x)
		var d := park_dist(C, p)
		xs.append(x)
		wet.append(is_water(C, p) or (in_park(C, p) and d > 0.0))  # the palace grounds count as the moat round them
		near.append(2 if d <= ROAD - SIDEWALK else (1 if d < ROAD + s.w / 2 - 2.0 * SIDEWALK else 0))
	var gone := []  # [from, to, end before, end after], in order
	var bridges := []
	var k := 0
	while k <= n:
		if wet[k]:
			var k0 := k
			while k <= n and wet[k]:
				k += 1
			if k0 > 0 and k <= n and xs[k] - xs[k0 - 1] <= BRIDGE and near[k] == 0 and not in_park(C, Vector2(xs[k], s.line + s.w / 2) if s.axis == "h" else Vector2(s.line + s.w / 2, xs[k])):
				bridges.append([xs[k0 - 1], xs[k]])
			else:
				gone.append([xs[k0 - 1] - 0.5 if k0 > 0 else a, xs[k] + 0.5 if k <= n else b, "quay", "quay"])
		elif near[k] > 0:
			var on := []
			while k <= n and near[k] > 0 and not wet[k]:
				if near[k] == 2:
					on.append(k)
				k += 1
			if not on.is_empty():
				gone.append([xs[on[0]], xs[on[-1]], "park", "park"])
		else:
			k += 1
	var out := []
	var start := a
	var end0 := ""
	for g in gone:
		if g[0] - start > 2.0:
			out.append([start, g[0], end0, g[2], bridges.filter(func(br): return br[0] >= start and br[1] <= g[0])])
		start = maxf(start, g[1])
		end0 = g[3]
	if b - start > 2.0:
		out.append([start, b, end0, "", bridges.filter(func(br): return br[0] >= start)])
	return out


## Roads round the parks, a street's width off them, so the streets that reach a park end on one (the palace's edge
## is its moat, where they stop at quays). Each is cut where it runs onto another park's road, the water or an
## avenue, ending just on it (and only grazes an avenue whose lanes it touches without reaching it); a loop that
## meets none stays closed, its first point repeated.
static func _edge_roads(C: Dictionary) -> Array:
	var loops := []
	for pk in C.parks:
		if pk.name != "Imperial Palace":
			loops.append(ellipse(pk.center, pk.radii + Vector2.ONE * ROAD / 2, 64))
	var out := []
	for lp in loops:
		var pts := PackedVector2Array()
		for i in lp.size():
			var a: Vector2 = lp[i]
			var b: Vector2 = lp[(i + 1) % lp.size()]
			var m := maxi(1, ceili(a.distance_to(b) / 2.0))
			for t in m:
				pts.append(a.lerp(b, float(t) / m))
		# 0 clear, 1 its lanes run into an avenue's, 2 on what it runs into
		var state := Array(pts).map(func(q):
			if is_water(C, q) or in_park(C, q) or park_dist(C, q) < ROAD / 2 - 1.0 or C.avenues.any(func(av): return _poly_dist(av.pts, q) < av.w / 2):
				return 2
			return 1 if C.avenues.any(func(av): return _poly_dist(av.pts, q) < av.w / 2 + ROAD / 2 - 2.0 * SIDEWALK) else 0)
		var first: int = state.find(2)
		if first < 0:
			pts.append(pts[0])
			out.append({"name": "", "w": ROAD, "pts": pts, "shuto": ""})
			continue
		var n := pts.size()
		var lab := []
		var ring := []
		for k in n + 1:  # from a point on what it runs into, round to it again
			lab.append(state[(first + k) % n])
			ring.append(pts[(first + k) % n])
		var k := 0
		while k <= n:
			var k0 := k
			while k <= n and lab[k] == 1:
				k += 1
			if k > k0 and lab[k0 - 1] == 0 and lab[k] == 0:
				for q in range(k0, k):
					lab[q] = 0
			k = maxi(k, k0 + 1)
		var last := 0
		for k2 in range(1, n + 1):
			if lab[k2] == 2:
				if k2 - last > 3:
					out.append({"name": "", "w": ROAD, "pts": PackedVector2Array(ring.slice(last, k2 + 1)), "shuto": ""})
				last = k2
	return out


static func _poly_dist(pts: PackedVector2Array, p: Vector2) -> float:
	var d := INF
	for k in pts.size() - 1:
		d = minf(d, Geometry2D.get_closest_point_to_segment(p, pts[k], pts[k + 1]).distance_to(p))
	return d


## An avenue end that meets no road runs on to the next road ahead (up to 60 m), or where it stops in the moat or the
## sea is cut back to the last road it crosses. Ends under the inner expressway loop, or off the map, are left.
static func _trim_avenues(C: Dictionary) -> void:
	var c1 := _flat(C.shuto[0].pts)
	for i in AVENUES.size():
		var av: Dictionary = C.avenues[i]
		var on_road := func(p: Vector2) -> bool:
			if not C.bounds.has_point(p) or is_water(C, p) or in_park(C, p):
				return not C.bounds.has_point(p)
			for k in c1.size():
				if Geometry2D.get_closest_point_to_segment(p, c1[k], c1[(k + 1) % c1.size()]).distance_to(p) < EXPRESS_W / 2 + 1.0:
					return true
			for st in C.streets:
				var c: float = st.line + st.w / 2
				var a := Vector2(st.from, c) if st.axis == "h" else Vector2(c, st.from)
				var b := Vector2(st.to, c) if st.axis == "h" else Vector2(c, st.to)
				if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < st.w / 2:
					return true
			for k in C.avenues.size():
				var o: PackedVector2Array = C.avenues[k].pts
				if k != i:
					for m in o.size() - 1:
						if Geometry2D.get_closest_point_to_segment(p, o[m], o[m + 1]).distance_to(p) < C.avenues[k].w / 2:
							return true
			return false
		var pts: PackedVector2Array = av.pts
		for e in 2:  # each end in turn, at the front
			if not on_road.call(pts[0]):
				var ahead := PackedVector2Array()
				var dir := (pts[0] - pts[1]).normalized()
				var q := pts[0]
				while ahead.size() < 30 and not is_water(C, q) and not in_park(C, q):
					q += dir * 2.0
					ahead.append(q)
					if on_road.call(q):
						break
				if not ahead.is_empty() and on_road.call(ahead[-1]):
					ahead.reverse()
					pts = ahead + pts
				else:
					var lo := 0
					while lo < pts.size() - 2 and not on_road.call(pts[lo]):
						lo += 1
					pts = pts.slice(lo)
			pts.reverse()
		av.pts = pts


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
			C.landmarks.append({"d": di, "pos": pos, "size": 22.0})


## Districts whose landmark found no free 22 m square at a block's centre (the dense centre and the old town, cut up
## by avenues, rail and the expressway) get one after the lots are placed: anywhere inside one of the district's own
## blocks, the biggest square from 22 m down to 14 m that fits, nearest the district centre (failing that, any block
## within 60 m: the centre's own blocks can all be cut by rail and the expressway; failing that, a square of its own
## blocks that reaches out over the water from the shore, as Odaiba's waterfront does). Its art is drawn to that size.
static func _place_landmarks_late(C: Dictionary) -> void:
	var placed := {}
	for L in C.landmarks:
		placed[L.d] = true
	# every district's own blocks first, so one's fallback doesn't take another's spot; within a pass, the district
	# with the fewest squares to choose from goes first
	for pass_ in ["own", "near", "shore"]:
		while true:
			var pick := []  # [how many squares it had, district, the nearest, its size]
			for di in C.districts.size():
				if C.districts[di].lm[1] >= 0 and not placed.has(di):
					var found := _late_squares(C, di, pass_)
					if found[0] > 0 and (pick.is_empty() or found[0] < pick[0]):
						pick = [found[0], di, found[1], found[2]]
			if pick.is_empty():
				break
			reserve(C, pick[2])
			C.landmarks.append({"d": pick[1], "pos": pick[2].get_center(), "size": pick[3]})
			placed[pick[1]] = true


## [how many free squares of any size, the one nearest the district centre of the biggest size that has one, its
## size].
static func _late_squares(C: Dictionary, di: int, pass_: String) -> Array:
	var d: Dictionary = C.districts[di]
	var near: Array = C.blocks.filter(func(b): return b.rect.get_center().distance_to(d.center) < 60.0 if pass_ == "near" else b.d == di)
	var out := [0, Rect2(), 0.0]
	for size in ([18.0, 14.0] if pass_ != "own" else [22.0, 18.0, 14.0]):
		var best := Rect2()
		var best_d := INF
		var n := 0
		for b in near:
			var r: Rect2 = b.rect
			var x := r.position.x
			while x + size <= r.end.x:
				var z := r.position.y
				while z + size <= r.end.y:
					var sq := Rect2(x, z, size, size)
					if not blocked(C, sq) if pass_ != "shore" else not is_water(C, sq.get_center()) and not blocked(C, sq, true):
						n += 1
						var dd := sq.get_center().distance_to(d.center)
						if dd < best_d:
							best = sq
							best_d = dd
					z += 2.0
				x += 2.0
		if n > 0 and out[0] == 0:
			out = [0, best, size]
		out[0] += n
	return out


## Shop lots: 22 x 10 on the north side of an east-west street, as near each district centre as they fit (a
## district short of its lots gets the rest; only those in `only`, if given). The district's shoppers set out from
## its first lot (`origin`): round the hubs the nearest free frontage can be a block or two from the station itself.
static func _place_lots(C: Dictionary, only: Array = []) -> void:
	var south := {}  # side streets by the z of their top edge
	for s in C.streets:
		if s.axis == "h":
			var k := roundi(s.line * 10.0)
			if not south.has(k):
				south[k] = []
			south[k].append(s)
	if not C.has("lots"):
		C.lots = []
	for di in C.districts.size():
		var d: Dictionary = C.districts[di]
		var placed: int = C.lots.filter(func(L): return L.block == di).size()
		if placed >= d.lots or (not only.is_empty() and not only.has(di)):
			continue
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
		for c in cands:
			if placed >= d.lots:
				break
			var lot: Rect2 = c[1]
			if C.lots.any(func(L): return Vector2(L.x0 + LOT_W / 2, L.front - LOT_D / 2).distance_to(lot.get_center()) < 26.0) or blocked(C, lot) or under_deck(C, lot.position.x, lot.end.y):
				continue
			C.lots.append({"block": di, "x0": lot.position.x, "front": lot.end.y})
			reserve(C, lot)
			placed += 1
	var by := []  # district by district, each in the order its lots were placed
	for di in C.districts.size():
		var own: Array = C.lots.filter(func(L): return L.block == di)
		by.append_array(own)
		C.districts[di].origin = Vector2(own[0].x0 + LOT_W / 2, own[0].front - LOT_D * 1.5) if not own.is_empty() else C.districts[di].center
	C.lots = by


# ---------- buildings (view only) ----------

enum { GLASS, CONCRETE, APARTMENT, SHOPS, NEON, WOOD, HOUSE, WAREHOUSE, STONE, PLAIN, BRICK }
const STYLE_COUNT := 11
# wall tints per style, each a family of hues rather than shades of beige: towers in sky and aqua, offices in sand and
# terracotta, flats, shops and houses in pastels, jewel-toned neon blocks, red-brown and ochre timber, painted tin sheds
const TINTS := [
	["bcd9e8", "b4e0d4", "c4ccf0", "a8cce0", "e2eef4"],
	["e8d0a8", "e0bca8", "b0d4c0", "f0dcb8", "dcb498"],
	["f8e6c0", "f6ccbc", "bce4b8", "c0d8f2", "f4e4a0", "dcc4f0"],
	["fcdcb4", "f8c4d8", "b8e8d0", "cce0f8", "f6eaa4", "d8bef2"],
	["3c4a80", "6c3c62", "2c626a", "7c4638", "4a3c70"],
	["a06a40", "8e4630", "b07c48", "74482e"],
	["ffe8c8", "f8cce0", "bfe8c4", "c4dcf8", "f8e8b0", "e0c8f4"],
	["88b4cc", "98c49c", "cc9a78", "dcd0b0", "78a8aa"],
	["ecd8b4", "e0c098", "ece2cc", "e4c8b8"],
	["dcd0b8", "b8d8c4", "e4ccc0"],
]
# gable tiles: glazed blue and green kawara, terracotta, oxblood, amber, silver
const ROOFS := ["3c6aa4", "b85a38", "4c8a58", "8e3834", "5c6878", "2c8a86", "b08030"]
# flat roofs, by the building's accent: green and teal coatings, light membranes, terracotta pavers
const FLAT_ROOFS := ["7cae88", "a8b8c8", "ccb890", "c47e5c", "6ca8a8", "c0c0b8", "b4a48c", "9cc0dc"]
# a block's ground by its district's type, on paving (or gravel where it's leafy)
const GROUND := {"hub": "e0c8ac", "office": "dccac0", "luxury": "e8d6b4", "nightlife": "d0bcd0", "youth": "eac4ba",
	"otaku": "d4c4e8", "tourist": "e4c49c", "university": "d8d0a8", "homes": "c4d8a0", "oldtown": "dcc898",
	"park": "b8d898", "market": "ccb498", "palace": "e0d4b4"}
const LEAFY := ["homes", "oldtown", "park"]
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


## Every building in Tokyo: {rect (bounding box), center, size, angle, floors, style, tint, accent, roof: "" | gable
## roof colour}. Fixed seed, cached.
static func buildings() -> Array:
	if not _buildings.is_empty():
		return _buildings
	var C := get_city()
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for b in C.blocks:
		_fill_block(C, b, rng, _buildings)
	_line_avenues(C, rng, _buildings)
	return _buildings


## Buildings turned to face the curved avenues, filling what the square blocks leave beside them.
static func _line_avenues(C: Dictionary, rng: RandomNumberGenerator, out: Array) -> void:
	for st in C.streets:  # the side streets join the corridors now that every lot is placed
		var c: float = st.line + st.w / 2
		var a := Vector2(st.from, c) if st.axis == "h" else Vector2(c, st.from)
		var b := Vector2(st.to, c) if st.axis == "h" else Vector2(c, st.to)
		_add_corridor(C, PackedVector2Array([a, b]), st.w / 2)
	var placed := {}  # bucket -> footprints already standing
	for bd in out:
		_add_poly(placed, _corners(bd.center, bd.size, 0.0))
	for av in C.avenues:
		var pts: PackedVector2Array = av.pts
		var cum := cumulative(pts)
		for side in [1.0, -1.0]:
			var s := 3.0
			while s < cum[-1] - 16.0:
				var n := nearest(C, at(pts, cum, s)[0])
				var d: Dictionary = C.districts[n[0]]
				var far: float = (n[1] - URBAN) / 80.0  # past the built-up edge homes still line the road, thinning out
				if far > 0.0 and rng.randf() < far:
					s += 14.0
					continue
				var mix: Array = MIX["homes" if far > 0.0 else ("office" if d.type == "palace" else d.type)]
				var m: Array = mix[rng.rand_weighted(PackedFloat32Array(mix.map(func(x): return float(x[0]))))]
				var full := Vector2(rng.randf_range(m[4], minf(m[5], 14.0)), rng.randf_range(m[6], minf(m[7], 13.0)))
				var step := 2.0  # side streets cut the frontage into wedges: slide on and squeeze in smaller ones
				for size in [full, full * Vector2(0.6, 0.7), Vector2(5.0, 6.0)]:
					var mid: Array = at(pts, cum, s + size.x / 2)
					var dir: Vector2 = mid[1]
					var c: Vector2 = mid[0] + Vector2(dir.y, -dir.x) * side * (av.w / 2 + 1.0 + size.y / 2)
					var ang := atan2(-dir.y, dir.x)
					var poly := _corners(c, size, ang)
					if not _obb_blocked(C, placed, poly, c, ang, size):
						var near: float = c.distance_to(d.center)
						var floors := maxi(1, roundi(rng.randf_range(m[2], m[3] + 0.99) * lerpf(1.0, 0.55, clampf(near / 90.0, 0.0, 1.0))))
						var bd := _building(rng, m[1], _bounds(poly), floors)
						bd.center = c
						bd.size = size
						bd.angle = ang
						out.append(bd)
						_add_poly(placed, poly)
						step = size.x + 0.7
						break
				s += step


## Corners of a size.x by size.y footprint centred on c, its x side along (cos ang, -sin ang).
static func _corners(c: Vector2, size: Vector2, ang: float) -> PackedVector2Array:
	var ex := Vector2(cos(ang), -sin(ang)) * size.x / 2
	var ez := Vector2(sin(ang), cos(ang)) * size.y / 2
	return PackedVector2Array([c - ex - ez, c + ex - ez, c + ex + ez, c - ex + ez])


static func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		r = r.expand(q)
	return r


static func _add_poly(placed: Dictionary, poly: PackedVector2Array) -> void:
	for k in _bucket_keys(_bounds(poly)):
		if not placed.has(k):
			placed[k] = []
		placed[k].append(poly)


## blocked() for a turned footprint: roads in its own frame, lots and other buildings as polygons, water and parks.
static func _obb_blocked(C: Dictionary, placed: Dictionary, poly: PackedVector2Array, c: Vector2, ang: float, size: Vector2) -> bool:
	var ex := Vector2(cos(ang), -sin(ang))
	var ez := Vector2(sin(ang), cos(ang))
	var local := Rect2(-size / 2, size)
	for k in _bucket_keys(_bounds(poly)):
		for sg in C.corridors.get(k, []):
			var a: Vector2 = sg[0] - c
			var b: Vector2 = sg[1] - c
			if seg_rect_dist(Vector2(a.dot(ex), a.dot(ez)), Vector2(b.dot(ex), b.dot(ez)), local) < sg[2]:
				return true
		for q in C.reserved.get(k, []):
			if not Geometry2D.intersect_polygons(poly, PackedVector2Array([q.position, Vector2(q.end.x, q.position.y), q.end, Vector2(q.position.x, q.end.y)])).is_empty():
				return true
		for other in placed.get(k, []):
			if not Geometry2D.intersect_polygons(poly, other).is_empty():
				return true
	for q in Array(poly) + [c]:
		if is_water(C, q) or in_park(C, q):
			return true
	return false


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
	return {"rect": fp, "center": fp.get_center(), "size": fp.size, "angle": 0.0, "floors": maxi(1, floors), "style": style, "tint": Color(tints[rng.randi() % tints.size()]) * rng.randf_range(0.94, 1.04), "accent": rng.randi() % 8, "roof": ROOFS[rng.randi() % ROOFS.size()] if gable else "", "kit": rng.randf()}
