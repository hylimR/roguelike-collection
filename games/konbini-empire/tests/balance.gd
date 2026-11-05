extends SceneTree
## Headless check of the rules: the spec's RNG vectors, curves and starting state, invariants while a bot plays a
## few days on two seeds, and a same-seed replay.
## godot --headless --path games/konbini-empire --script res://tests/balance.gd

const Sim := preload("res://sim.gd")
const DAYS := 8
const SEEDS := [1000, 1077]

var fails := []


func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)


func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


func _init() -> void:
	vectors()
	curves()
	start_state()
	roads()
	decks()
	railway()
	shelves()
	var t0 := Time.get_ticks_msec()
	var a := {}
	for s in SEEDS:
		a = play(s)
	var b := play(SEEDS[-1], false)
	check(a.sig == b.sig, "same seed replays identically (%s vs %s)" % [a.sig, b.sig])
	print("bot runs took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RULES OK" if fails.is_empty() else "RULES FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)


## The shop as the shop view builds it with every line in: each fixture's packs, measured by the art they draw, stand
## on its boards inside its shell and under the next board, every board holds some, and nothing stands on a
## fixture's top; the magazine racks stand on the floor.
func shelves() -> void:
	var s := Sim.new()
	s.create_run(42)
	var st: Dictionary = s.branches[0].store
	st.size = 3
	for pid in Sim.PRODUCTS:
		if not st.products.has(pid):
			s.add_line(st, pid)
	var SV = load("res://store_view.gd")
	var v = SV.new()
	for n in ["products", "perks", "decor", "bg_konbini", "props"]:
		v.tex[n] = load("res://art/%s.png" % n)
	v.room = Node3D.new()
	v.branch = s.branches[0]
	v.build_room()
	var drawn := func(t: Texture2D, cell: Rect2i) -> Rect2i: return t.get_image().get_region(cell).get_used_rect()
	var bad := []
	var tops := {}  # a fixture's footprint -> the height nothing may stand above
	for mmi in v.room.get_children().filter(func(c): return c is MultiMeshInstance3D):
		var pid = v.slot_goods.find_key(mmi.multimesh)
		if pid == null:
			continue
		var kind: String = SV.slot_kind(Sim.PRODUCTS[pid].slot)
		var f: Dictionary = SV.FIXTURES[kind]
		var p: Vector2 = Sim.SLOTS[Sim.PRODUCTS[pid].slot].pos
		var q: QuadMesh = mmi.multimesh.mesh
		var m: StandardMaterial3D = mmi.material_override
		var t: Texture2D = m.albedo_texture
		var cell := Rect2i(roundi(m.uv1_offset.x * t.get_width()), 0, roundi(m.uv1_scale.x * t.get_width()), roundi(m.uv1_scale.y * t.get_height()))
		var u: Rect2i = drawn.call(t, cell)
		var k := q.size.x / cell.size.x
		var x0: float = -q.size.x / 2 + q.center_offset.x
		var y0: float = q.size.y / 2 + q.center_offset.y
		var used := {}
		# a headless run keeps no instance data, so the packs' places come from the rule that fills the multimesh
		var at: Array = SV.facings(kind, p, Vector2(u.size) * k)
		if at.size() != mmi.multimesh.instance_count:
			bad.append("%s has %d packs, its rule %d" % [pid, mmi.multimesh.instance_count, at.size()])
		for i in at.size():
			var tr: Transform3D = at[i]
			var c := []
			for cx in [u.position.x, u.end.x]:
				for cy in [u.position.y, u.end.y]:
					c.append(tr * Vector3(x0 + cx * k, y0 - cy * k, 0) - Vector3(p.x, 0, p.y))
			var lo: float = c.map(func(w): return w.y).min()
			var hi: float = c.map(func(w): return w.y).max()
			var row := -1  # the board it stands on: at its foot's height, the nearest row of those
			for j in f.rows.size():
				if absf(lo - f.rows[j][0]) < 0.005 and hi <= f.rows[j][1] + 0.005 and (row < 0 or absf(tr.origin.z - p.y - f.rows[j][2]) < absf(tr.origin.z - p.y - f.rows[row][2])):
					row = j
			if row < 0 or not c.all(func(w): return f.inner.grow(0.005).has_point(Vector2(w.x, w.z))):
				bad.append("%s pack %d at %s..%s m (not on a board, under the next, inside the shell)" % [pid, i, lo, hi])
				break
			used[row] = true
		if used.size() < f.rows.size():
			bad.append("%s fills %d of %d boards" % [pid, used.size(), f.rows.size()])
		tops[Rect2(p.x - SV.FIXTURE_W / 2 + 0.05, p.y - 0.35, SV.FIXTURE_W - 0.1, 0.7)] = f.h + 0.1
	check(tops.size() == st.products.keys().filter(func(pid): return SV.FIXTURES.has(SV.slot_kind(Sim.PRODUCTS[pid].slot))).size(), "every shelf, fridge and freezer line has its packs")
	for c in v.room.get_children():
		var box: AABB
		if c is Sprite3D:
			var u: Rect2i = drawn.call(c.texture, Rect2i(c.region_rect))
			var px: float = c.pixel_size
			var foot: float = c.position.y - (u.end.y - c.region_rect.size.y / 2) * px
			box = AABB(c.position - Vector3(u.size.x * px / 2, c.position.y - foot, u.size.x * px / 2), Vector3(u.size.x * px, u.size.y * px, u.size.x * px))
			if c in v.slot_icons.get("manga", []) and absf(foot) > 0.005:
				bad.append("a magazine rack's foot %.2f m off the floor" % foot)
		elif c is MeshInstance3D:
			box = c.transform * c.get_aabb()
		else:
			continue
		for r in tops:
			if Rect2(box.position.x, box.position.z, box.size.x, box.size.z).intersects(r) and box.end.y > tops[r] + 0.001:
				bad.append("%s %.2f m tall over the fixture at %s" % [c.get_class(), box.end.y, r.get_center()])
	check(bad.is_empty(), "every pack stands on its fixture's boards and nothing on a fixture's top (%s)" % [bad])
	v.room.free()
	v.free()


## Every road ends on another road, at a quay or off the map: a side street at a T or a corner on another street, on
## the road round a park, or at a railing over the water; an avenue or a park's road on another road.
func roads() -> void:
	var City = Sim.City
	var C: Dictionary = City.get_city()
	var band := func(s: Dictionary) -> Rect2: return Rect2(s.from, s.line, s.to - s.from, s.w) if s.axis == "h" else Rect2(s.line, s.from, s.w, s.to - s.from)
	var on_avenue := func(p: Vector2, skip: int) -> bool:
		for k in C.avenues.size():
			if k != skip and City._poly_dist(C.avenues[k].pts, p) < C.avenues[k].w / 2 + 1.0:
				return true
		return false
	var dead := []
	for i in C.streets.size():
		var s: Dictionary = C.streets[i]
		var c: float = s.line + s.w / 2
		for e in 2:
			var at: float = s.from if e == 0 else s.to
			var dir := 1.0 if e == 1 else -1.0
			var probe := Rect2(at - 1.5, s.line + 0.5, 3.0, s.w - 1.0) if s.axis == "h" else Rect2(s.line + 0.5, at - 1.5, s.w - 1.0, 3.0)
			var tip := Vector2(at + dir, c) if s.axis == "h" else Vector2(c, at + dir)
			var over := Vector2(at + dir * 2.5, c) if s.axis == "h" else Vector2(c, at + dir * 2.5)
			var crossed := range(C.streets.size()).any(func(k): return k != i and band.call(C.streets[k]).intersects(probe))
			if not (crossed or on_avenue.call(tip, -1) or (s.quay[e] and City.is_water(C, over))):
				dead.append(tip)
	var c1: PackedVector2Array = City._flat(C.shuto[0].pts)
	c1.append(c1[0])
	for k in C.avenues.size():
		var pts: PackedVector2Array = C.avenues[k].pts
		if pts[0] == pts[-1]:
			continue  # a loop round a park
		for p in [pts[0], pts[-1]]:
			var on_street: bool = C.streets.any(func(s): return band.call(s).grow(0.5).has_point(p))
			var ring_in_water: bool = k >= City.AVENUES.size() and City.is_water(C, p)
			if not (not C.bounds.has_point(p) or on_street or ring_in_water or on_avenue.call(p, k) or City._poly_dist(c1, p) < City.EXPRESS_W / 2 + 1.0):
				dead.append(p)
	check(dead.is_empty(), "every road ends on another road, at a quay or off the map (%d don't, e.g. %s)" % [dead.size(), dead.slice(0, 4)])


## The elevated roads join what they meet: every ramp lands in its avenue's carriageway and at the top runs level into
## its deck, never parting from the deck's edge and ending inside its width; every route's end is on another deck, at
## grade on a road or off the map; and no parapet or painted line of one carriageway stands inside another on the same
## level, nor is one left out where nothing runs into it.
func decks() -> void:
	var City = Sim.City
	var C: Dictionary = City.get_city()
	var t0 := Time.get_ticks_msec()
	var routes: Array = City.elevated(C)
	var bad := []
	var on_road := func(q: Vector2) -> bool:
		return C.avenues.any(func(av): return City._poly_dist(av.pts, q) < av.w / 2) or C.streets.any(func(st): return (Rect2(st.from, st.line, st.to - st.from, st.w) if st.axis == "h" else Rect2(st.line, st.from, st.w, st.to - st.from)).has_point(q))
	for rp in C.ramps:
		var av: Dictionary = C.avenues[rp.av]
		var deck: PackedVector2Array = City._flat(C.shuto.filter(func(sh): return sh.name == av.shuto)[0].pts)
		for k in rp.pts.size():
			var p: Vector3 = rp.pts[k]
			var q := Vector2(p.x, p.z)
			var off_deck: float = City._poly_dist(deck, q)
			if near(p.y, City.DECK) and off_deck - City.RAMP_W / 2 > City.EXPRESS_W / 2 + 0.01:
				bad.append("ramp at %s parts from its deck by %.2f m" % [q.round(), off_deck - City.RAMP_W / 2 - City.EXPRESS_W / 2])
			if k == 0 or k == rp.pts.size() - 1:
				if near(p.y, 0.0) and City._poly_dist(av.pts, q) + City.RAMP_W / 2 > City.CARRIER / 2 - City.SIDEWALK + 0.01:
					bad.append("ramp foot at %s off its avenue's lanes" % [q.round()])
				elif near(p.y, City.DECK) and off_deck + City.RAMP_W / 2 > City.EXPRESS_W / 2 + 0.01:
					bad.append("ramp top at %s ends %.2f m outside its deck" % [q.round(), off_deck + City.RAMP_W / 2 - City.EXPRESS_W / 2])
				elif not near(p.y, 0.0) and not near(p.y, City.DECK):
					bad.append("ramp end at %s in mid-air (%.1f m)" % [q.round(), p.y])
	# brute force, apart from the city's grid: is p within `margin` of the inside of a carriageway other than ri, level with it
	var boxes := routes.map(func(e): return Array(e.pts).reduce(func(r, v): return r.expand(Vector2(v.x, v.z)), Rect2(Vector2(e.pts[0].x, e.pts[0].z), Vector2.ZERO)).grow(e.w))
	var inside := func(ri: int, p: Vector3, margin: float) -> bool:
		var q := Vector2(p.x, p.z)
		for rj in routes.size():
			if rj == ri or not boxes[rj].has_point(q):
				continue
			var e: Dictionary = routes[rj]
			for k in e.pts.size() - 1:
				var a2 := Vector2(e.pts[k].x, e.pts[k].z)
				var b2 := Vector2(e.pts[k + 1].x, e.pts[k + 1].z)
				var c := Geometry2D.get_closest_point_to_segment(q, a2, b2)
				var t := 0.0 if a2 == b2 else (c - a2).length() / a2.distance_to(b2)
				if c.distance_to(q) < e.w / 2 + margin and absf(lerpf(e.pts[k].y, e.pts[k + 1].y, t) - p.y) < 0.05:
					return true
		return false
	for ri in routes.size():
		var e: Dictionary = routes[ri]
		if not e.closed:
			for p in [e.pts[0], e.pts[-1]]:
				var q := Vector2(p.x, p.z)
				if not (not C.bounds.has_point(q) or inside.call(ri, p, 0.0) or (near(p.y, 0.0) and on_road.call(q))):
					bad.append("deck end at %s meets nothing (%.1f m up)" % [q.round(), p.y])
		var half: float = e.w / 2
		var offs := [half, -half, half - 0.5, 0.5 - half] + ([] if e.ramp else [0.0, half / 2, -half / 2])
		for off in offs:
			var runs: Array = City.line_runs(C, ri, off)
			var stands := func(x: float) -> bool: return runs.any(func(r): return x >= r[0] and x <= r[1])
			var x := 0.5
			while x < e.cum[-1]:
				var k := clampi(e.cum.bsearch(x), 1, e.pts.size() - 1)
				var a: Vector3 = e.pts[k - 1]
				var b: Vector3 = e.pts[k]
				var d := Vector2(b.x - a.x, b.z - a.z).normalized()
				var p: Vector3 = a.lerp(b, (x - e.cum[k - 1]) / (e.cum[k] - e.cum[k - 1])) + Vector3(d.y, 0, -d.x) * off
				if stands.call(x) and inside.call(ri, p, -0.3):
					bad.append("a line at %.1f m stands inside another carriageway at %s" % [off, Vector2(p.x, p.z).round()])
				elif not stands.call(x) and not inside.call(ri, p, 0.3):
					bad.append("a line at %.1f m is left out at %s with nothing running in" % [off, Vector2(p.x, p.z).round()])
				x += 1.0
	print("decks checked in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	check(bad.is_empty(), "every ramp runs into its deck and lands in its avenue, every deck end meets a road, and no parapet or line walls one carriageway off from another (%d: %s)" % [bad.size(), bad.slice(0, 4)])


## The Yamanote: no curve tighter than RAIL_R; its viaduct off every park, ring road, moat and the water; every station
## on it near its district; nothing built on it; piers off the roads' lanes and never too far apart; the expressway
## high enough over it, its pillars never through it and its ramps never in it; the trains on each track never closing up, and stopping at
## every station.
func railway() -> void:
	var City = Sim.City
	var C: Dictionary = City.get_city()
	var pts: PackedVector2Array = C.rail
	var n := pts.size()
	var tight := []
	var off := []
	for i in n:
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var c: Vector2 = pts[(i + 1) % n]
		var area := absf((b - a).cross(c - a)) / 2.0
		if (b - a).dot(c - b) <= 0.0 or (area > 1e-6 and a.distance_to(b) * b.distance_to(c) * a.distance_to(c) / (4.0 * area) < City.RAIL_R - 0.5):
			tight.append(b)
		var t: Vector2 = (c - a).normalized()
		for e in [0.0, 1.0, -1.0]:
			var p: Vector2 = b + Vector2(t.y, -t.x) * e * City.RAIL_W / 2
			if City.in_park(C, p) or City.is_water(C, p) or City.park_dist(C, p) < City.ROAD:
				off.append(p)
	check(tight.is_empty(), "no Yamanote curve tighter than %d m (%d points are, e.g. %s)" % [City.RAIL_R, tight.size(), tight.slice(0, 3)])
	check(off.is_empty(), "the viaduct keeps off parks, their ring roads, the moat and the water (%d points don't, e.g. %s)" % [off.size(), off.slice(0, 3)])
	var far := []
	for stn in City.YAMANOTE:
		var st: Array = C.stations.filter(func(q): return C.districts[q.d].name == stn)
		var c: Vector2 = C.districts[st[0].d].center if st.size() == 1 else Vector2.INF
		if st.size() != 1 or st[0].pos.distance_to(c) > 45.0 or C.stations.any(func(q): return q != st[0] and q.pos.distance_to(c) < st[0].pos.distance_to(c)):
			far.append(stn)
	check(far.is_empty() and C.stations.size() == City.YAMANOTE.size(), "every Yamanote station is on the line, its district's nearest and within 45 m (not: %s)" % [far])
	var roofed := []
	for st in C.stations:
		for k in range(-int(City.PLATFORM_L / 2), int(City.PLATFORM_L / 2) + 1, 2):
			var p: Vector2 = City.rail_at(C, st.s + k)[0]
			for sh in C.shuto:
				if City._poly_dist(City._flat(sh.pts), p) < City.EXPRESS_W / 2 + City.RAIL_W / 2 and not roofed.has(C.districts[st.d].name):
					roofed.append(C.districts[st.d].name)
	check(roofed.is_empty(), "no station platform is under the expressway (%s)" % [roofed])
	var on := []
	for L in C.landmarks:
		if not City.in_park(C, L.pos) and City._on_rail(C, Rect2(L.pos - Vector2.ONE * L.size / 2, Vector2.ONE * L.size)):
			on.append(C.districts[L.d].name)
	for L in C.lots:
		if City._on_rail(C, Rect2(L.x0, L.front - City.LOT_D, City.LOT_W, City.LOT_D)):
			on.append("a lot of " + C.districts[L.block].name)
	for bd in City.buildings():
		if City.rail_dist(C, bd.center) < City.RAIL_W / 2 + maxf(bd.size.x, bd.size.y) * 0.5 and City._on_rail(C, bd.rect.grow(-1.2)):
			on.append("a building at %s" % bd.center)
	check(on.is_empty(), "no landmark, lot or building stands on the viaduct (%s)" % [on.slice(0, 4)])
	var wanted: int = C.districts.filter(func(d): return d.lm[1] >= 0).size()
	check(C.landmarks.size() == wanted, "all %d landmarks stand (%d do)" % [wanted, C.landmarks.size()])
	# the shop view's set round every lot stands clear of the decks: none over its parts lower than they stand, no pier
	# or pillar in them, and (drawn as the shop view sees it) no deck's parapet in front of your shop
	var covered := []
	var decks: Array = C.shuto.map(func(sh): return [sh.pts, sh.closed, City.EXPRESS_W]) + C.ramps.map(func(rp): return [rp.pts, false, City.RAMP_W])
	var rail3 := PackedVector3Array()
	for p in C.rail_loop:
		rail3.append(Vector3(p.x, City.RAIL_DECK, p.y))
	decks.append([rail3, false, City.RAIL_W])
	var iso := func(p: Vector3) -> Vector2: return Vector2((p.x - p.z) * 0.7071, (p.x + p.z) * 0.3536 - p.y * 0.866)
	var pil: Array = City.deck_pillars(C).map(func(dp): return Vector2(dp[2].x, dp[2].z)) + C.piers.map(func(q): return q[1])
	for L in C.lots:
		var at := Vector2(L.x0, L.front)
		var name: String = C.districts[L.block].name
		var parts: Array = City.SET_PARTS.map(func(pt): return [Rect2(at + pt[0].position, pt[0].size), pt[1]])
		if pil.any(func(q): return parts.any(func(pt): return pt[0].has_point(q))):
			covered.append(name + " (a pier or pillar in it)")
			continue
		var seen := Rect2(at + City.SET_SEEN.position, City.SET_SEEN.size)
		var qs := []
		for gx in 17:
			for gz in 14:
				qs.append(Vector3(seen.position.x + gx * seen.size.x / 16, 0.0, seen.position.y + gz * seen.size.y / 13))
		var hid := 0
		var through := []
		for dk in decks:
			var dp: PackedVector3Array = dk[0]
			for k in range(1, dp.size()):
				var a: Vector3 = dp[k - 1]
				var b: Vector3 = dp[k]
				if maxf(a.y, b.y) <= 1.5 or Vector2(a.x, a.z).distance_to(seen.get_center()) > 60.0:
					continue
				for pt in parts:  # the deck's slab, its full width, down into a part of the set
					if minf(a.y, b.y) - 0.6 < pt[1] and City.seg_rect_dist(Vector2(a.x, a.z), Vector2(b.x, b.z), pt[0]) < dk[2] / 2 and not through.has(pt[1]):
						through.append(pt[1])
				var nrm: Vector3 = Vector3(b.z - a.z, 0, a.x - b.x).normalized() * dk[2] / 2
				var corners := PackedVector2Array()
				for e in [a, b]:
					for sd in [nrm, -nrm]:
						for y in [-0.6, 0.9]:
							corners.append(iso.call(e + sd + Vector3(0, y, 0)))
				var hull := Geometry2D.convex_hull(corners)
				for q in qs:
					if (a.x + a.z + b.x + b.z) / 2 > q.x + q.z + 1.0 and Geometry2D.is_point_in_polygon(iso.call(q), hull):
						hid += 1
		if hid > 0 or not through.is_empty():
			covered.append("%s (%d of %d points hidden, a deck through parts %s m tall)" % [name, hid, qs.size(), through])
	check(covered.is_empty(), "every shop's street set stands clear of the decks and in view (%s)" % [covered])
	var short := []
	for d in C.districts:
		if C.lots.filter(func(L): return C.districts[L.block] == d).size() < d.lots:
			short.append(d.name)
	# map-forced: Nihonbashi's and Azabu's only lots have the viaduct through the rival next door, Tsukiji's the
	# Rainbow Bridge approach; the others never had room
	check(C.lots.size() == 44, "the city has 44 shop lots (%d; short: %s)" % [C.lots.size(), short])
	var SV = load("res://store_view.gd")
	var fit: bool = Sim.ZONE_LEFT.all(func(zl): return City.SET_PARTS[1][0].position.x <= 21.0 + Sim.ORIGIN.x + zl) and City.SET_PARTS[3][0].has_point(Vector2(24.0, -9.3))
	for id in Sim.RIVALS:
		var sp: Vector2 = SV.rival_span({"x": Sim.RIVALS[id].door, "width": Sim.RIVALS[id].width})
		fit = fit and City.SET_PARTS[4][0].position.x <= 21.0 + sp.x and City.SET_PARTS[4][0].end.x >= 21.0 + sp.y
	fit = fit and [Sim.VENDING_X, Sim.GACHA_X].all(func(x): return City.SET_PARTS[0][0].has_point(Vector2(21.0 + x, 0.4)))
	check(fit, "City.SET_PARTS covers the shop view's shop at every size, every rival, the pole sign and vending machines")
	var bad := []
	var ss: Array = C.piers.map(func(q): return q[0])
	ss.sort()
	var span := 0.0
	for i in ss.size():
		span = maxf(span, fposmod(ss[(i + 1) % ss.size()] - ss[i], C.rail_cum[-1]))
	for q in C.piers:
		if not City.pier_ok(C, q[1]) or City.rail_dist(C, q[1]) > City.RAIL_W / 2:
			bad.append(q[1])
	check(bad.is_empty() and span <= City.MAX_SPAN, "the viaduct's piers stand off the lanes, under it, at most %d m apart (longest %.1f, %d misplaced)" % [City.MAX_SPAN, span, bad.size()])
	var low := []
	for sh in C.shuto:
		for p3 in sh.pts:
			if City.rail_dist(C, Vector2(p3.x, p3.z)) < City.EXPRESS_W / 2 + City.RAIL_W / 2 and p3.y - 0.6 < City.RAIL_DECK + 0.3 + City.CAR_H + 0.3:
				low.append(Vector2(p3.x, p3.z))
	for rp in C.ramps:
		for p3 in rp.pts:
			if City.rail_dist(C, Vector2(p3.x, p3.z)) < City.RAIL_W / 2 + City.RAMP_W / 2 and p3.y > 0.8:
				low.append(Vector2(p3.x, p3.z))
	check(low.is_empty(), "the expressway clears a train on the viaduct and its ramps keep out of it (%s)" % [low.slice(0, 3)])
	var pierced := []
	var gap := 0.0
	var last := {}
	for dp in City.deck_pillars(C):
		if City.rail_dist(C, Vector2(dp[2].x, dp[2].z)) < City.RAIL_W / 2 + dp[3] / 2:
			pierced.append(dp[2])
		if last.has(dp[0]):
			gap = maxf(gap, Vector2(dp[2].x, dp[2].z).distance_to(last[dp[0]]))
		last[dp[0]] = Vector2(dp[2].x, dp[2].z)
	check(pierced.is_empty() and gap <= City.DECK_SPAN, "no expressway pillar stands in the viaduct, and none are more than %d m apart (%d do, widest %.1f)" % [City.DECK_SPAN, pierced.size(), gap])
	var train: float = City.CARS * City.CAR_L + (City.CARS - 1) * City.CAR_GAP
	var close := INF
	var stops := {}
	for dir in [1, -1]:
		var period: float = C.timetable[0 if dir > 0 else 1].period
		var prev: float = City.train_s(C, dir, 0, -0.25)
		var t := 0.0
		while t < period:
			var s0: float = City.train_s(C, dir, 0, t)
			for k in range(1, City.TRAINS):
				close = minf(close, fposmod((s0 - City.train_s(C, dir, k, t)) * dir, C.rail_cum[-1]))
			if absf(s0 - prev) < 0.001:
				for st in C.stations:
					if absf(st.s - s0) < 0.01:
						stops[[dir, st.d]] = true
			prev = s0
			t += 0.25
	check(close >= train + 4.0, "the trains on a track stay a train and more apart (closest %.1f m)" % close)
	check(stops.size() == 2 * C.stations.size(), "every train stops at every station both ways (%d of %d)" % [stops.size(), 2 * C.stations.size()])
	check(2.0 * City.TRACK >= City.CAR_W + 1.0 and City.TRACK - City.CAR_W / 2 >= City.PLATFORM_W / 2, "trains pass each other and the platform")


func vectors() -> void:
	var r := Sim.Rng.new(12345)
	var want := [0.9797282677609473, 0.3067522644996643, 0.484205421525985, 0.817934412509203, 0.5094283693470061]
	for w in want:
		check(near(r.next(), w, 1e-15), "mulberry32(12345) -> %s" % w)
	check(r.s == 567906818, "mulberry32(12345) seed after 5 draws is %d" % r.s)
	r = Sim.Rng.new(0)
	for w in [0.26642920868471265, 0.0003297457005828619, 0.2232720274478197]:
		check(near(r.next(), w, 1e-15), "mulberry32(0) -> %s" % w)
	check(Sim.rnd(2.5) == 3 and Sim.rnd(-2.5) == -2 and Sim.rnd(87.5) == 88, "round halves toward +inf")


func curves() -> void:
	var xp := []
	for L in range(1, 11):
		xp.append(Sim.xp_for_level(L))
	check(xp == [70, 91, 118, 154, 200, 260, 338, 439, 571, 742], "xp curve %s" % [xp])
	var ex := []
	for n in 9:
		ex.append(Sim.expansion_cost({"expansions": n}))
	check(ex == [900, 1242, 1714, 2365, 3264, 4504, 6216, 8578, 11838], "expansion costs %s" % [ex])
	var s := Sim.new()
	s.create_run(42)
	var rr := []
	for n in 7:
		s.player.rerolls = n
		rr.append(s.reroll_cost())
	check(rr == [200, 320, 512, 819, 1311, 2097, 3355], "reroll costs %s" % [rr])
	var sc := []
	for n in range(1, 7):
		s.run_stats.stores_opened = n
		sc.append(s.store_cost())
	check(sc == [7000, 11900, 20230, 34391, 58465, 99390], "store costs %s" % [sc])
	var b: Dictionary = s.branches[0]
	var ages := []
	for d in [0, 5, 10, 15, 19, 30]:
		s.day = b.opened + d
		ages.append(snappedf(s.rent(b) / 1300.0, 0.001))
	s.day = 1
	check(ages == [1.0, 1.276, 1.629, 2.079, 2.5, 2.5], "rent age multipliers %s" % [ages])
	var hp := []
	for t in range(3, 7):
		hp.append(int(s.create_rival("mega", t).max_hp))
	check(hp == [85000, 136000, 217600, 348160], "MEGAMART HP by tier %s" % [hp])
	var ap := []
	for stars in [0.5, 3.0, 5.0]:
		b.store.rating = stars
		ap.append(snappedf(s.player_appeal(b), 0.01))
	b.store.rating = 3.0
	check(near(ap[0], 5.61) and near(ap[1], 11.17) and near(ap[2], 15.61), "player appeal %s" % [ap])
	var price := func(stores: int, d: String) -> int:
		s.run_stats.stores_opened = stores
		return Sim.rnd(s.store_cost() * Sim.DISTRICTS[d].cost / 100.0) * 100
	var second := Sim.DISTRICTS.keys().map(func(d): return price.call(1, d))
	var third := Sim.DISTRICTS.keys().map(func(d): return price.call(2, d))
	check(second == [7000, 7700, 8800, 10200, 13300], "second-store listing prices %s" % [second])
	check(third == [11900, 13100, 14900, 17300, 22600], "third-store listing prices %s" % [third])


func start_state() -> void:
	var s := Sim.new()
	s.create_run(42)
	var b: Dictionary = s.branches[0]
	var hana: Dictionary = b.store.crew[0]
	check(s.rng_seed == 42 and s.phase == "intro" and s.player.cash == 2200 and s.day == 1, "createRun(42) basics")
	check(b.district == "sakura" and b.quirk == "plain" and b.rival.id == "tanuki" and b.rival.max_hp == 3600.0 and b.rival.attack_timer == 28.0, "Sakura vs Tanuki Mart")
	check(hana.id == 1 and hana.name == "Hana" and hana.trait_id == "steady" and hana.wage >= 230 and hana.wage <= 290 and hana.wage % 10 == 0, "Hana, steady, wage %d" % hana.wage)
	check(b.store.applicants.size() == 10 and b.store.applicants[0].id == 100, "ten applicants from id 100")
	check(s.bills_due() == 1300 + hana.wage, "first night's bills")
	check(near(s.player_appeal(b), 11.1667, 0.001) and near(s.rival_appeal(b), 10.0), "day-1 appeal: you 11.17, Tanuki 10")
	var r := Sim.Rng.new(7)
	var n := {"player": 0, "rival": 0, "none": 0}
	s.rng = r
	for k in 20000:
		n[s.choose_target(b, "drink")] += 1
	check(near(n.player / 20000.0, 0.44, 0.015) and near(n.rival / 20000.0, 0.40, 0.015), "day-1 choice split %s" % [n])
	# a rejected action leaves the seed alone
	s.act({"type": "start"})
	var before := s.rng_seed
	s.act({"type": "ringUp", "register": 0})
	check(s.rng_seed == before, "rejected action keeps the seed")


## A bot with ~0.7 skill: rings up, clicks threats, restocks keeping 1.3 days of bills, hires, buys expansions,
## takes the first card of every pick, opens a store when it can afford one with a cushion.
func play(seed_: int, verbose := true) -> Dictionary:
	var s := Sim.new()
	s.create_run(seed_)
	s.act({"type": "start"})
	var r := Sim.Rng.new(seed_ * 7 + 1)
	var lines := []
	var think := 0.0
	var fails0 := fails.size()
	while s.phase != "gameOver" and s.day <= DAYS:
		if s.phase == "choice":
			var c: Dictionary = s.choice
			var ok := false
			for k in c.options.size():
				if s.act({"type": "pickChoice", "id": c.options[k] if c.source != "listing" else k}):
					ok = true
					break
			if not ok:
				s.act({"type": "closeChoice"})
			continue
		var day := s.day
		s.tick(0.1)
		invariants(s)
		if fails.size() > fails0:
			break
		if s.day != day and s.report != null:
			var rep: Dictionary = s.report
			lines.append("  d%d cash ¥%d bills ¥%d lvl %d rivals %d | %s" % [rep.day, rep.cash_after, rep.bills, s.player.level, s.run_stats.rivals_defeated,
				" ".join(rep.rows.map(func(w): return "%s:%d/%d%s" % [w.name.get_slice(" ", 0), w.stats.revenue, w.rent + w.wages, "✓" if w.defeated else "(%d%%)" % roundi(100.0 * w.rival_hp / w.rival_max)]))])
		think += 0.1
		if think < 0.5:
			continue
		think = 0.0
		bot_turn(s, r)
	if verbose:
		print("seed %d: %s after %d days, %d store(s)" % [seed_, "bankrupt" if s.phase == "gameOver" else "alive", s.run_stats.days, s.branches.size()])
		for l in lines:
			print(l)
	check(s.run_stats.days >= 3, "seed %d survives three nights" % seed_)
	var sig := "%d/%d/%.3f/%d" % [s.player.cash, s.day, s.player.xp, s.run_stats.revenue]
	for b in s.branches:
		sig += "/%.2f" % b.rival.hp
	return {"sig": sig}


func bot_turn(s, r) -> void:
	var skill := 0.7
	for i in s.branches.size():
		s.act({"type": "switchStore", "index": i})
		var b: Dictionary = s.branches[i]
		for reg in b.store.registers:
			if r.chance(skill):
				s.act({"type": "ringUp", "register": reg.id})
		for t in b.threats.duplicate():
			if r.chance(skill):
				s.act({"type": "clickThreat", "id": t.id})
		var reserve := int(s.bills_due() * 1.3)
		for pid in b.store.products:
			var p: Dictionary = b.store.products[pid]
			if p.stock < p.capacity * 0.5 and s.player.cash > reserve + 300:
				s.act({"type": "restock", "product": pid})
		for id in s.player.abilities:
			s.act({"type": "useAbility", "id": id})
		if s.player.cash > reserve + 1500:
			for role in ["stocker", "cleaner", "guard"]:
				var ap: Array = b.store.applicants.filter(func(a): return a.role == role)
				if not ap.is_empty() and b.store.crew.filter(func(m): return m.role == role).size() < 1:
					s.act({"type": "hire", "id": ap[0].id})
		if s.player.cash > reserve + Sim.expansion_cost(b.store) + 500:
			s.act({"type": "openExpansion"})
			if s.phase == "choice":
				return
	if not s.pending.is_empty():
		s.act({"type": "openPick"})
		return
	if s.branches.size() < 3 and s.player.cash > s.store_cost() * 1.9 + s.bills_due() * 2:
		s.act({"type": "openListings"})


func invariants(s) -> void:
	for b in s.branches:
		check(b.agents.size() <= Sim.MAX_PEDS, "at most 120 pedestrians")
		check(b.store.rating >= 0.5 and b.store.rating <= 5.0, "rating in range")
		for pid in b.store.products:
			var p: Dictionary = b.store.products[pid]
			check(p.stock >= 0 and p.stock <= p.capacity, "stock in range")
		for reg in b.store.registers:
			check(reg.queue.size() <= Sim.MAX_QUEUE[reg.id], "queue within its cap")
		check(b.rival.hp >= 0.0 or not b.rival.defeated, "rival hp")
	check(typeof(s.player.cash) == TYPE_INT, "cash stays an integer")
