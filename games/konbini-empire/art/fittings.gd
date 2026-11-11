extends RefCounted
## The shop fittings, the storefront pictures and the two shops' back walls, painted in code (art/sheets.gd). Each
## fitting is blocked out at real size in boxes through the store camera's 2:1 view, far parts first, then its detail
## and an outline, as `prop()` in store_view.gd stands it on its billboard.

const Paint := preload("res://art/paint.gd")
const Sim := preload("res://sim.gd")
const PROP := Vector2i(128, 176)
const FOOT := Vector2(32, 75)  # a props cell's footprint centre on the canvas (texel (64, 150) on the sheet)
const STRIPE := [Color("f05a28"), Color("1f9d55")]  # your chain's stripes, as store_view's LAYOUT
const STEEL := Color("b9bec4")
const ROOF := Color("7cae88")  # your shop's roof coating, as City.FLAT_ROOFS[0]
const INK := Color("2a2430")  # the storefronts' outline, dark enough to hold them together small
const CAT_INK := Color("4a302c")  # the cat's, warm like its coat


## Paints through the 2:1 view onto a canvas: metres from the origin `o` (canvas pixels), k pixels per metre.
class Pen:
	var p: Paint
	var o: Vector2
	var k: float

	func _init(p_: Paint, o_: Vector2, k_: float) -> void:
		p = p_
		o = o_
		k = k_

	func pt(v: Vector3) -> Vector2:
		return o + Paint.iso(v) * k

	func face(pts: Array, c: Color) -> void:
		p.iso_face(pts, c, o, k)

	## A box in the house's three tones with a lit rim along its top's near edges and down its near corner.
	func box(a: Vector3, b: Vector3, c: Color, rim := 0.2) -> void:
		p.iso_box(a, b, c, o, k)
		if rim <= 0.0:
			return
		var lo := a.min(b)
		var hi := a.max(b)
		var ty := 1.0 / (0.866 * k)
		face([Vector3(lo.x, hi.y - ty, hi.z), Vector3(hi.x, hi.y - ty, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], Paint.shade(Paint.toned(c, 0.9), rim))
		face([Vector3(hi.x, hi.y - ty, hi.z), Vector3(hi.x, hi.y - ty, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z)], Paint.shade(Paint.toned(c, 0.75), rim))
		front(hi.z, hi.x - 1.0 / (0.707 * k), hi.x, lo.y, hi.y, Paint.shade(Paint.toned(c, 0.9), rim * 0.6))

	## The rectangle x0..x1 by y0..y1 on the wall at z, turned to +z (screen left), snapped to whole pixels: every
	## column the same height, stepping down the wall's 2:1 slope, so small detail keeps its size.
	func front(z: float, x0: float, x1: float, y0: float, y1: float, c: Color) -> void:
		wall(pt(Vector3(x0, y1, z)), pt(Vector3(x1, y1, z)), (y1 - y0) * 0.866 * k, c)

	## The rectangle z0..z1 by y0..y1 on the wall at x, turned to +x (screen right), snapped the same way.
	func side(x: float, z0: float, z1: float, y0: float, y1: float, c: Color) -> void:
		wall(pt(Vector3(x, y1, z1)), pt(Vector3(x, y1, z0)), (y1 - y0) * 0.866 * k, c)

	func wall(a: Vector2, b: Vector2, hpx: float, c: Color) -> void:
		var c0 := roundi(a.x)
		var n := maxi(1, roundi(b.x - a.x))
		var hh := maxi(1, roundi(hpx))
		for i in n:
			var yt := lerpf(a.y, b.y, (i + 0.5) / n)
			p.rect(c0 + i, ceili(yt - 0.5), 1, hh, c)

	## A w x h block of pixels on a wall, u columns right of and v rows below where `at` lands, following the wall's
	## slope: down to the right on a front (+z), up on a side (+x).
	func fpx(at: Vector3, u: int, v: int, w: int, h: int, c: Color, on_side := false) -> void:
		var s := -0.5 if on_side else 0.5
		var a := pt(at) + Vector2(u, v + u * s)
		wall(a, a + Vector2(w, w * s), h, c)

	## The pixel u columns right of and v rows below where `at` lands, following its wall's slope as fpx does: the
	## foot of something upright standing on that wall's face.
	func on_wall(at: Vector3, u: int, v: int, on_side := false) -> Vector2i:
		var a := pt(at)
		var s := -0.5 if on_side else 0.5
		return Vector2i(roundi(a.x) + u, ceili(a.y + (u + 0.5) * s - 0.5) + v)

	## The rectangle x0..x1 by z0..z1 on the plane y, facing up.
	func top(y: float, x0: float, x1: float, z0: float, z1: float, c: Color) -> void:
		face([Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)], c)

	## A w x h block of pixels centred on where v lands.
	func dot(v: Vector3, c: Color, w := 1, h := 1) -> void:
		var q := pt(v)
		p.rect(roundi(q.x - w / 2.0), roundi(q.y - h / 2.0), w, h, c)


# ---------- props: 9 cells of 128 x 176 ----------

static func props() -> Image:
	var sheet := Image.create(PROP.x * 9, PROP.y, false, Image.FORMAT_RGBA8)
	var painters := [till, coffee, atm, vending, gacha, bench, cat, karaage, oden]
	for i in painters.size():
		var p := Paint.new(PROP.x / 2, PROP.y / 2)
		painters[i].call(p)
		p.outline(CAT_INK if painters[i] == cat else Color(0, 0, 0, 0))
		p.stamp(sheet, Vector2i(i * PROP.x, 0))
	return sheet


## The till on the counter, drawer, keys and screen to the clerk (+x): a cash drawer under a terminal whose keyboard
## slopes down to the clerk, the display on a pole at its back.
static func till(p: Paint) -> void:
	var q := Pen.new(p, FOOT, 1.0 / 0.015)
	var cream := Color("ece2c8")
	q.box(Vector3(-0.17, 0, -0.22), Vector3(0.17, 0.08, 0.22), cream)
	var drawer := Vector3(0.17, 0.08, 0.22)
	q.fpx(drawer, 1, 1, 19, 1, Paint.toned(cream, 0.6), true)
	q.fpx(drawer, 5, 3, 11, 2, Color("4a3c30"), true)
	q.fpx(drawer, 2, 3, 2, 2, Color("8d8270"), true)
	var hb := 0.21
	var hf := 0.12
	var xf := 0.13
	var at := func(x: float, z: float) -> Vector3: return Vector3(x, lerpf(hb, hf, (x + 0.17) / (xf + 0.17)), z)
	q.face([Vector3(-0.17, 0.08, 0.2), Vector3(xf, 0.08, 0.2), Vector3(xf, hf, 0.2), Vector3(-0.17, hb, 0.2)], Paint.toned(cream, 0.9))
	q.face([Vector3(xf, 0.08, 0.2), Vector3(xf, 0.08, -0.2), Vector3(xf, hf, -0.2), Vector3(xf, hf, 0.2)], Paint.toned(cream, 0.75))
	q.face([at.call(-0.17, -0.2), at.call(-0.17, 0.2), at.call(xf, 0.2), at.call(xf, -0.2)], Paint.shade(cream, 0.1))
	q.face([at.call(-0.09, -0.17), at.call(-0.09, 0.16), at.call(0.1, 0.16), at.call(0.1, -0.17)], Color("a7adb4"))
	# keys in rows down the slope, the coloured function keys at the far end of each
	var k0 := q.pt(at.call(-0.06, 0.12)).round()
	for r in 3:
		for c in 3:
			var kp := k0 + Vector2(r * 2 + c * 4, r * 2 - c * 2)
			p.rect(int(kp.x), int(kp.y), 2, 1, Color("eef0f2"))
	var fk := [[Vector2(12, -5), Color("e8493c")], [Vector2(15, -6), Color("3f86e6")], [Vector2(14, -2), Color("48b04f")], [Vector2(17, -3), Color("f4c531")]]
	for e in fk:
		p.rect(int(k0.x + e[0].x), int(k0.y + e[0].y), 2, 2, e[1])
	# the display on its pole, screen to the clerk
	q.box(Vector3(-0.15, hb - 0.02, 0.02), Vector3(-0.12, 0.34, 0.05), Color("d8cdb2"), 0.0)
	var d0 := Vector3(-0.16, 0.33, -0.07)
	var d1 := Vector3(-0.12, 0.45, 0.14)
	q.box(d0, d1, Color("e2d8be"))
	q.fpx(d1, 1, 1, 8, 5, Color("2f3f36"), true)
	q.fpx(d1, 2, 2, 4, 1, Color("a6e2b0"), true)
	q.fpx(d1, 2, 4, 5, 1, Color("6fae7a"), true)


## The coffee machine at the counter, its front to the street (+z): a charcoal cabinet under a lid, the menu screen,
## a red band, and a cup under the spout in its lit bay over the drip tray.
static func coffee(p: Paint) -> void:
	var q := Pen.new(p, FOOT, 1.0 / 0.015)
	var body := Color("3b3539")
	var z := 0.2
	q.box(Vector3(-0.21, 0, -0.21), Vector3(0.21, 0.6, z), body)
	q.box(Vector3(-0.215, 0.6, -0.225), Vector3(0.215, 0.69, z + 0.015), Color("4d454a"))
	# menu screen with three cups
	q.front(z, -0.165, 0.115, 0.43, 0.56, Color("1a181d"))
	q.front(z, -0.15, 0.1, 0.445, 0.545, Color("8fd6f2"))
	for i in 3:
		var x := -0.13 + i * 0.08
		q.front(z, x, x + 0.045, 0.465, 0.51, Color("fbf6ea"))
		q.front(z, x, x + 0.045, 0.495, 0.51, Color("8a5a36"))
	q.front(z, -0.21, 0.21, 0.365, 0.4, Color("e2412f"))
	q.side(0.21, -0.21, z, 0.365, 0.4, Paint.toned(Color("e2412f"), 0.75))
	# the bay: dark, lit from its roof, the spout, a paper cup on the grille of the drip tray
	q.front(z, -0.15, 0.11, 0.06, 0.33, Color("141317"))
	q.front(z, -0.135, 0.095, 0.075, 0.31, Color("35313a"))
	q.front(z, -0.135, 0.095, 0.29, 0.31, Color("d8cfbe"))
	q.box(Vector3(-0.045, 0.255, z - 0.07), Vector3(0.0, 0.29, z - 0.03), Color("a7adb3"), 0.0)
	var c := q.pt(Vector3(-0.02, 0.08, z - 0.03))
	var cx := roundi(c.x)
	var cy := roundi(c.y)
	p.barrel(cx - 2, cy - 6, cx + 2, cy - 1, Color("f6f1e6"))
	p.span(cy - 7, cx - 2, cx + 2, Color("e6dfd2"))
	p.span(cy - 4, cx - 2, cx + 2, Color("b4733f"))
	q.box(Vector3(-0.16, 0.045, z - 0.03), Vector3(0.12, 0.075, z + 0.05), Color("8b9096"))
	for i in 5:
		q.dot(Vector3(-0.13 + i * 0.055, 0.075, z + 0.01), Color("5d6268"), 2, 1)


## The ATM in the shop's front corner, its face to the street (+z): a pale cabinet under a blue fascia, the screen in
## its bezel, the keypad on a shelf, the card slot and a panel below.
static func atm(p: Paint) -> void:
	var q := Pen.new(p, FOOT, 1.0 / 0.028)
	var body := Color("e4e7ea")
	var blue := Color("1f7fe3")
	var z := 0.4
	q.box(Vector3(-0.35, 0, -0.4), Vector3(0.35, 1.45, z), body)
	q.box(Vector3(-0.35, 1.22, z - 0.02), Vector3(0.35, 1.42, z + 0.05), blue)
	q.front(z + 0.05, -0.22, 0.12, 1.28, 1.35, Color("f2f7ff"))
	# the screen sunk in its bezel
	q.front(z, -0.27, 0.2, 0.84, 1.14, Color("59636d"))
	q.front(z, -0.23, 0.16, 0.88, 1.1, Color("2f9ce9"))
	q.front(z, -0.19, 0.12, 1.03, 1.07, Color("c6eaff"))
	q.front(z, -0.19, -0.03, 0.92, 0.97, Color("86cdfb"))
	q.front(z, 0.0, 0.12, 0.92, 0.97, Color("86cdfb"))
	q.front(z, 0.23, 0.31, 0.96, 1.0, Color("2c3138"))
	# the keypad shelf
	q.box(Vector3(-0.3, 0.72, z - 0.01), Vector3(0.27, 0.78, z + 0.15), Color("c3c8ce"))
	for r in 2:
		for c in 4:
			q.dot(Vector3(-0.22 + c * 0.12, 0.78, z + 0.045 + r * 0.06), Color("6f777f"), 2, 1)
	# the lower panel
	q.front(z, -0.27, 0.27, 0.1, 0.64, Paint.toned(body, 0.8))
	q.front(z, -0.25, 0.25, 0.13, 0.61, Paint.toned(body, 0.92))
	q.front(z, -0.07, 0.07, 0.5, 0.53, Color("8b939b"))


## The vending machine on the sidewalk, its window of drinks to the street (+z): red, the lit window in three shelves
## of bottles and cans with a button under each, the coin panel beside it and the flap below.
static func vending(p: Paint) -> void:
	var q := Pen.new(p, FOOT, 1.0 / 0.028)
	var red := Color("e0312b")
	var z := 0.375
	q.box(Vector3(-0.5, 0, -0.375), Vector3(0.5, 0.07, z + 0.01), Color("3a3236"), 0.0)
	q.box(Vector3(-0.5, 0.07, -0.375), Vector3(0.5, 1.8, z), red)
	# the window: three shelves of drinks, a button under each
	var win := Vector3(-0.44, 1.73, z)
	q.fpx(win, 0, 0, 18, 29, Color("2a2a32"))
	q.fpx(win, 1, 1, 16, 27, Color("e6f5ff"))
	var cols := [Color("e8483c"), Color("f29a2e"), Color("3fa64a"), Color("2f7fd6"), Color("f2d03a"), Color("8a4fc2"), Color("ece6d6")]
	for row in 3:
		var v0 := 2 + row * 9
		q.fpx(win, 1, v0 + 6, 16, 1, Color("9eabb6"))
		for i in 4:
			var u := 2 + i * 4
			var c: Color = cols[(i * 3 + row * 2) % cols.size()]
			var f := q.on_wall(win, u + 1, v0 + 6)
			if (i + row) % 3 == 1:  # a can
				p.rect(f.x - 1, f.y - 4, 3, 4, c)
				p.rect(f.x - 1, f.y - 4, 3, 1, Paint.shade(c, 0.45))
			else:  # a bottle
				p.rect(f.x, f.y - 6, 1, 1, Color("fbfbf8"))
				p.rect(f.x, f.y - 5, 1, 1, Paint.shade(c, 0.3))
				p.rect(f.x - 1, f.y - 4, 3, 4, c)
			p.rect(f.x - 1, f.y - 3, 1, 2, Paint.shade(c, 0.5))
			p.rect(f.x + 1, f.y - 4, 1, 4, Paint.shade(c, -0.2))
			var b := q.on_wall(win, u + 1, v0 + 8)
			p.rect(b.x, b.y, 1, 1, Color("e8483c") if (i + row) % 2 == 0 else Color("3a3a40"))
	q.fpx(win, 1, 1, 1, 3, Color(1, 1, 1, 0.85))
	# the coin panel, the flap
	q.fpx(win, 19, 6, 4, 12, Color("34343a"))
	q.fpx(win, 20, 7, 2, 1, Color("d6dade"))
	q.fpx(win, 20, 10, 2, 2, Color("101014"))
	q.fpx(win, 20, 14, 2, 2, Color("8c939a"))
	q.fpx(win, 1, 37, 15, 8, Color("2c2b31"))
	q.fpx(win, 2, 38, 13, 2, Color("4c4b53"))
	q.fpx(win, 0, -2, 18, 1, Paint.shade(red, 0.35))


## The gacha row by the vending machine: three capsule machines, red, blue and yellow, on a steel plinth, each a coin
## knob and a chute under a glass case heaped with capsules and a coloured lid.
static func gacha(p: Paint) -> void:
	var q := Pen.new(p, FOOT, 1.0 / 0.028)
	var plinth := Color("b5b9bf")
	q.box(Vector3(-0.75, 0, -0.25), Vector3(0.75, 0.42, 0.25), plinth)
	for c in [Vector3(-0.69, 0.36, 0.25), Vector3(0.67, 0.36, 0.25), Vector3(-0.69, 0.07, 0.25), Vector3(0.67, 0.07, 0.25)]:
		q.dot(c, Color("7c828a"))
	var tones := [Color("e8413a"), Color("2f7fe0"), Color("f2c12e")]
	var caps := [Color("e8413a"), Color("2f7fe0"), Color("f2c12e"), Color("48b04f"), Color("ee74b4"), Color("9a5fd0"), Color("f29a2e")]
	for m in 3:
		var x0 := -0.72 + m * 0.49
		var x1 := x0 + 0.45
		var z0 := -0.2
		var z1 := 0.2 + (m - 1) * 0.025
		var c: Color = tones[m]
		q.box(Vector3(x0, 0.42, z0), Vector3(x1, 0.8, z1), c)
		var face := Vector3(x0, 0.8, z1)
		var kc := q.on_wall(face, 4, 6)
		p.ellipse(kc.x + 0.5, kc.y + 0.5, 2.6, 2.6, Color("e4e7ea"))
		p.rect(kc.x - 1, kc.y, 3, 1, Color("6e747b"))
		q.fpx(face, 8, 3, 3, 5, Paint.shade(c, -0.5))
		q.fpx(face, 8, 4, 3, 2, Color("1a181d"))
		# the case: its far panes in shade, a heap of capsules, the near panes' glare
		q.face([Vector3(x0, 0.8, z0), Vector3(x1, 0.8, z0), Vector3(x1, 1.22, z0), Vector3(x0, 1.22, z0)], Color("a7cadd"))
		q.face([Vector3(x0, 0.8, z0), Vector3(x0, 0.8, z1), Vector3(x0, 1.22, z1), Vector3(x0, 1.22, z0)], Color("94b9cf"))
		var heap := [[2, 3], [6, 3], [10, 3], [4, 7], [8, 7], [14, 2], [17, 1], [12, 6], [16, 5]]
		var base := Vector3(x0, 0.8, z1)
		for i in heap.size():
			var e: Array = heap[i]
			var s := q.on_wall(base, e[0], -e[1], e[0] > 11)
			if e[0] > 11:
				s = q.on_wall(Vector3(x1, 0.8, z1), e[0] - 11, -e[1], true)
			capsule(p, Vector2(s), caps[(i * 3 + m * 2) % caps.size()])
		q.front(z1, x0, x1, 0.8, 1.22, Color(0.85, 0.95, 1.0, 0.12))
		q.side(x1, z0, z1, 0.8, 1.22, Color(0.8, 0.9, 1.0, 0.2))
		q.fpx(Vector3(x0, 1.22, z1), 2, 2, 1, 4, Color(1, 1, 1, 0.85))
		q.fpx(Vector3(x0, 1.22, z1), 4, 2, 1, 2, Color(1, 1, 1, 0.6))
		q.box(Vector3(x0 - 0.01, 1.22, z0 - 0.01), Vector3(x1 + 0.01, 1.31, z1 + 0.01), Paint.shade(c, 0.1))


## A gacha capsule about 4 px across centred on s, lit from the top left.
static func capsule(p: Paint, s: Vector2, c: Color) -> void:
	var x := roundi(s.x)
	var y := roundi(s.y)
	p.span(y - 2, x - 1, x + 1, c)
	p.span(y - 1, x - 2, x + 2, c)
	p.span(y, x - 2, x + 2, Paint.shade(c, -0.18))
	p.span(y + 1, x - 1, x + 1, Paint.shade(c, -0.32))
	p.px(x - 1, y - 1, Color(1, 1, 1, 0.9))
	p.px(x, y - 2, Paint.shade(c, 0.35))


## The bench outside the shop: a top of three slats along x on two slab legs.
static func bench(p: Paint) -> void:
	var q := Pen.new(p, FOOT, 1.0 / 0.028)
	var leg := Color("a6642c")
	var wood := Color("d48c46")
	for x in [-0.62, 0.52]:
		q.box(Vector3(x, 0, -0.16), Vector3(x + 0.09, 0.4, 0.16), leg)
		q.fpx(Vector3(x, 0.4, 0.16), 1, 3, 1, 7, Paint.toned(leg, 0.78))
	q.box(Vector3(-0.66, 0.34, -0.1), Vector3(0.66, 0.4, 0.1), Paint.toned(leg, 0.85), 0.0)
	q.box(Vector3(-0.75, 0.4, -0.2), Vector3(0.75, 0.46, 0.2), wood)
	for zz in [-0.065, 0.07]:
		q.wall(q.pt(Vector3(-0.75, 0.46, zz)), q.pt(Vector3(0.75, 0.46, zz)), 1.0, Paint.shade(wood, -0.32))
	q.fpx(Vector3(-0.75, 0.46, 0.2), 0, 1, 37, 1, Paint.shade(Paint.toned(wood, 0.9), -0.15))


## The shop cat, front on, walking right: a calico, white with orange and black patches, tail held up in a curl.
static func cat(p: Paint) -> void:
	var white := Color("f8f2e6")
	var orange := Color("ee8a36")
	var black := Color("3d3434")
	var f := int(FOOT.y)  # paws stand on row f - 1
	var far := Paint.shade(white, -0.24)
	# far legs, the tail, the body and its patches, the near legs, the head
	p.rect(22, f - 6, 2, 5, far)
	p.rect(29, f - 6, 2, 5, far)
	p.rect(22, f - 1, 3, 1, Paint.shade(far, -0.1))
	p.rect(29, f - 1, 3, 1, Paint.shade(far, -0.1))
	var tail := [Vector2(16.5, f - 11), Vector2(13, f - 14), Vector2(11.5, f - 18), Vector2(12, f - 22), Vector2(14, f - 25), Vector2(16.5, f - 25)]
	for i in tail.size() - 1:
		p.line(tail[i], tail[i + 1], white if i == 0 else (orange if i < 3 else black), 3.0)
	p.ball(26.0, f - 9.5, 10.5, 5.5, white, 0.2)
	mask_ellipse(p, 25.0, f - 13.5, 5.0, 3.5, black)
	mask_ellipse(p, 17.0, f - 10.5, 3.5, 4.5, orange)
	mask_ellipse(p, 32.5, f - 13.5, 3.0, 2.0, orange)
	for x in [18, 33]:
		p.rect(x, f - 6, 2, 5, white)
		p.rect(x, f - 1, 3, 1, Paint.shade(white, -0.14))
	var hx := 38.5
	var hy := f - 17.0
	p.poly(PackedVector2Array([Vector2(hx - 6, hy - 1), Vector2(hx - 5, hy - 9), Vector2(hx - 1, hy - 4)]), black)
	p.poly(PackedVector2Array([Vector2(hx + 1, hy - 4), Vector2(hx + 4.5, hy - 9), Vector2(hx + 6, hy - 1)]), orange)
	p.ball(hx, hy, 6.0, 5.2, white, 0.2)
	mask_ellipse(p, hx - 3.5, hy - 3.5, 3.0, 2.5, black)
	mask_ellipse(p, hx + 3.5, hy - 3.5, 2.5, 2.0, orange)
	p.px(int(hx) - 4, int(hy) - 6, Color("e89aa0"))
	p.px(int(hx) + 3, int(hy) - 6, Color("e89aa0"))
	p.rect(int(hx) + 1, int(hy) - 1, 1, 2, Color("2a2424"))
	p.rect(int(hx) + 4, int(hy) - 1, 1, 2, Color("2a2424"))
	p.px(int(hx) + 6, int(hy) + 1, Color("e07a86"))
	p.px(int(hx) + 5, int(hy) + 2, Color("c4bbae"))


## Paints an ellipse only over what is already painted, keeping its shading (a patch on a coat).
static func mask_ellipse(p: Paint, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var o := p.get_px(x, y)
			if dx * dx + dy * dy <= 1.0 and o.a > 0.0:
				p.px(x, y, Paint.shade(c, clampf((o.get_luminance() - 0.88) * 2.2, -0.45, 0.2)))


## The karaage warmer on the counter: glass all round between a steel base and lid, lit warm inside by its lamps,
## fried chicken heaped on its tray, the door on the clerk's side (+x).
static func karaage(p: Paint) -> void:
	var q := Pen.new(p, FOOT, 1.0 / 0.015)
	var x0 := -0.235
	var x1 := 0.235
	var z0 := -0.26
	var z1 := 0.26
	var y0 := 0.06
	var y1 := 0.35
	q.box(Vector3(x0, 0, z0), Vector3(x1, y0, z1), STEEL)
	# the lit inside: far walls, the tray, lamps
	q.face([Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0)], Color("fb9c26"))
	q.face([Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0)], Color("ee841e"))
	q.top(y0, x0, x1, z0, z1, Color("b8621e"))
	q.top(y0, x0 + 0.03, x1 - 0.03, z0 + 0.03, z1 - 0.03, Color("d8a272"))
	q.fpx(Vector3(x0, y1, z0), 3, 1, 16, 1, Color("fff4c4"))
	q.fpx(Vector3(x0, y1, z1), 3, 1, 16, 1, Color("ffeaa8"), true)
	# the heap: back rows higher
	var golds := [Color("e8a03a"), Color("cf7a22"), Color("f0b04a")]
	var i := 0
	for r in 4:
		for c in 4 - (r % 2):
			var u := (c + 0.5 * (r % 2) + 0.5) / 4.0
			var zz := lerpf(z0 + 0.09, z1 - 0.08, (3 - r) / 3.0)
			var s := q.pt(Vector3(lerpf(x0 + 0.05, x1 - 0.05, u), y0 + 0.035 + (3 - r) * 0.012, zz))
			nugget(p, s, golds[(i * 2 + r) % 3])
			i += 1
	# the glass: a glare down each pane, steel posts at the corners, the door's handle, the lid with its label
	q.side(x1, z0, z1, y0, y1, Color(1.0, 0.94, 0.85, 0.1))
	q.fpx(Vector3(x0, y1, z1), 3, 3, 1, 12, Color(1, 1, 1, 0.65))
	q.fpx(Vector3(x0, y1, z1), 5, 4, 1, 6, Color(1, 1, 1, 0.45))
	q.fpx(Vector3(x1, y1, z1), 3, 3, 1, 9, Color(1, 1, 1, 0.5), true)
	q.fpx(Vector3(x1, y1, z1), 12, 0, 1, 20, Paint.toned(STEEL, 0.7), true)
	q.fpx(Vector3(x1, y1, z1), 14, 7, 1, 4, Color("5f666f"), true)
	for c in [Vector3(x0, 0, z1), Vector3(x1, 0, z0), Vector3(x1, 0, z1)]:
		q.box(c - Vector3(0.012, 0, 0.012), c + Vector3(0.012, y1, 0.012), STEEL, 0.0)
	q.box(Vector3(x0 - 0.012, y1, z0 - 0.012), Vector3(x1 + 0.012, y1 + 0.05, z1 + 0.012), Color("ccd0d6"))
	q.fpx(Vector3(x0 - 0.012, y1 + 0.05, z1 + 0.012), 3, 1, 10, 1, Color("e2412f"))


## A piece of karaage centred on s: a golden lump shaded from the top left, ringed darker where it meets the next.
static func nugget(p: Paint, s: Vector2, c: Color) -> void:
	p.ellipse(s.x + 0.4, s.y + 0.6, 3.0, 2.4, Color("8a4814"))
	p.ball(s.x, s.y, 2.5, 2.0, c, 0.1)
	p.px(roundi(s.x) - 1, roundi(s.y) - 1, Color("f8d27a"))


## The oden pot on the counter: a steel well in six compartments of broth, daikon, eggs, konnyaku, chikuwa and fried
## tofu simmering in them, steam rising.
static func oden(p: Paint) -> void:
	var q := Pen.new(p, FOOT, 1.0 / 0.015)
	var x0 := -0.2
	var x1 := 0.2
	var z0 := -0.275
	var z1 := 0.275
	var h := 0.15
	q.box(Vector3(x0, 0, z0), Vector3(x1, h, z1), STEEL)
	q.fpx(Vector3(x0, h, z1), 2, 6, 15, 1, Paint.toned(STEEL, 0.7))
	q.fpx(Vector3(x1, h, z1), 2, 6, 21, 1, Paint.toned(STEEL, 0.56), true)
	# the well inside the rim: its far walls in shade, the broth, the dividers, what simmers
	var r := 0.02
	q.top(h, x0 + r, x1 - r, z0 + r, z1 - r, Color("5a3e1c"))
	q.top(h, x0 + r + 0.025, x1 - r, z0 + r + 0.03, z1 - r, Color("b87a2c"))
	var xs := [x0 + r, 0.0, x1 - r]
	var zs := [z0 + r, -0.085, 0.085, z1 - r]
	for zi in 3:
		for xi in 2:
			oden_item(p, q.pt(Vector3((xs[xi] + xs[xi + 1]) / 2.0 + 0.008, h, (zs[zi] + zs[zi + 1]) / 2.0 + 0.008)), xi * 3 + zi)
	var steel := Color("e4e8ec")
	q.wall(q.pt(Vector3(0.0, h, z1 - r)), q.pt(Vector3(0.0, h, z0 + r)), 1.0, steel)
	for z in [-0.085, 0.085]:
		q.wall(q.pt(Vector3(x0 + r, h, z)), q.pt(Vector3(x1 - r, h, z)), 1.0, steel)
	for s in 2:
		var base := q.pt(Vector3(-0.09 + s * 0.14, h + 0.06, -0.06 + s * 0.1))
		for i in 6:
			p.px(floori(base.x + sin(i * 1.2 + s * 2.0) * 1.4), floori(base.y) - i - s * 3, Color(1, 1, 1, 0.9))


## What simmers in one compartment, centred on s: daikon, eggs, konnyaku, chikuwa or fried tofu by `kind`.
static func oden_item(p: Paint, s: Vector2, kind: int) -> void:
	var x := roundi(s.x)
	var y := roundi(s.y)
	match kind:
		0, 4:  # daikon
			p.ellipse(x + 0.5, y + 1.0, 3.5, 2.0, Color("c29a55"))
			p.ellipse(x + 0.5, y + 0.5, 3.0, 1.6, Color("f4e8c4"))
			p.span(y, x - 1, x, Color("fffaea"))
		1:  # eggs
			p.ball(x - 1.0, y + 0.5, 2.0, 1.6, Color("8e5626"))
			p.ball(x + 2.5, y + 1.0, 2.0, 1.6, Color("8e5626"))
		2:  # konnyaku
			p.poly(PackedVector2Array([Vector2(x - 3, y + 2), Vector2(x + 0.5, y - 2), Vector2(x + 4, y + 2)]), Color("6e6862"))
			p.px(x, y, Color("8e877f"))
		3:  # chikuwa
			p.rect(x - 3, y, 6, 2, Color("e2b46a"))
			p.rect(x - 2, y, 1, 2, Color("a8662a"))
			p.rect(x + 1, y, 1, 2, Color("a8662a"))
			p.px(x + 3, y, Color("f6e6c4"))
		5:  # fried tofu
			p.ball(x + 0.5, y + 0.5, 2.6, 1.9, Color("b47a3a"))


# ---------- storefronts: 10 cells of 256 x 192 ----------

## Each storefront cell's colour, in pairs of a small shop then a large one: yours in your stripes, then each rival
## chain's in the cell its RIVALS `front` names, a cell no chain names taking its pair's.
static func storefront_colors() -> Array:
	var out := [STRIPE[0], STRIPE[0], null, null, null, null, null, null, null, null]
	for id in Sim.RIVALS:
		out[Sim.RIVALS[id].front] = Color(Sim.RIVALS[id].color)
	for i in out.size():
		if out[i] == null:
			out[i] = out[i ^ 1]
	return out


static func storefronts() -> Image:
	var sheet := Image.create(2560, 192, false, Image.FORMAT_RGBA8)
	var colors := storefront_colors()
	for i in 10:
		var small := i % 2 == 0
		var at := Vector2i(56, 64) if small else Vector2i(14, 38)  # just round the shop, inside the cards' crops
		var p := Paint.new(68, 64) if small else Paint.new(116, 76)
		shopfront(p, colors[i], small, i < 2, Vector2(at) / 2.0)
		p.outline(INK)
		p.stamp(sheet, Vector2i(i * 256, 0) + at)
	return sheet


## A konbini as the street builds one, through the 2:1 view: a white box, its glass front (+z) and side windows framed
## dark with shelves of goods behind, the fascia in the chain's stripes round the front and the side, a lightbox sign
## over the door, a parapet round the roof with AC units on it; an awning and the recycling bins at a small shop's
## door, carts by a large one's. `at` is where the canvas's corner sits in its cell, on the cell's pixel grid.
static func shopfront(p: Paint, c: Color, small: bool, yours: bool, at: Vector2) -> void:
	var w := 6.0 if small else 18.0
	var d := 4.2 if small else 4.4
	var h := 4.0 if small else 5.4
	var k := 8.0 if small else 5.4
	var q := Pen.new(p, (Vector2(63, 79) if small else Vector2(66, 71)) - at, k)
	var x0 := -w / 2
	var x1 := w / 2
	var z0 := -d / 2
	var z1 := d / 2
	var wall := Color("f7f5ee") if yours else Color("f1eee6")
	q.box(Vector3(x0, 0, z0), Vector3(x1, h, z1), wall, 0.0)
	var front := Vector3(x0, h, z1)
	var side := Vector3(x1, h, z1)
	var fw := roundi(q.pt(Vector3(x1, h, z1)).x) - roundi(q.pt(front).x)
	var sw := roundi(q.pt(Vector3(x1, h, z0)).x) - roundi(q.pt(side).x)
	var rows := roundi(h * 0.866 * k)
	# the fascia's stripes, and its shadow on the wall below
	var bands := [[1, 2, STRIPE[0]], [3, 1, Color.WHITE], [4, 2, STRIPE[1]]] if yours else [[1, 3, c], [4, 1, Color.WHITE], [5, 2, c.darkened(0.3)]]
	for bd in bands:
		q.fpx(front, 0, bd[0], fw, bd[1], Paint.toned(bd[2], 0.9))
		q.fpx(side, 0, bd[0], sw, bd[1], Paint.toned(bd[2], 0.75), true)
	q.fpx(front, 0, 7, fw, 1, Paint.toned(wall, 0.74))
	q.fpx(side, 0, 7, sw, 1, Paint.toned(wall, 0.62), true)
	# glass in dark frames down to a kick plate: the front's run with its door, the side's windows between piers
	var door := 12 if small else 26
	windows(q, front, [[2, door - 1], [door + 11, fw - 2]], 9, rows - 1, door, false)
	var runs := [[3, 14], [17, sw - 2]] if small else [[3, sw - 2]]
	windows(q, side, runs, 9, rows - 1, -1, true)
	q.fpx(front, 0, rows - 1, fw, 1, Paint.toned(Color("a3a6a9"), 0.9))
	q.fpx(side, 0, rows - 1, sw, 1, Paint.toned(Color("a3a6a9"), 0.75), true)
	# the roof inside its parapet, the far parapets' inner faces in shade, the AC units, the near parapets
	var pt := 0.3
	var ph := 0.4
	var roof := ROOF.darkened(0.22) if yours else Color("7f807c")
	q.top(h, x0, x1, z0, z1, roof)
	for i in 7:
		var a := q.pt(Vector3(lerpf(x0 + 0.8, x1 - 0.9, (i * 5 % 7) / 6.0), h, lerpf(z0 + 0.6, z1 - 0.6, (i * 2 % 3) / 2.0)))
		p.rect(roundi(a.x), roundi(a.y), 2, 1, Paint.shade(roof, -0.1))
	q.top(h, x0 + pt, x1 - pt, z0 + pt, z0 + pt + 0.35, Paint.shade(roof, -0.16))
	q.top(h, x0 + pt, x0 + pt + 0.25, z0 + pt, z1 - pt, Paint.shade(roof, -0.16))
	q.side(x0 + pt, z0 + pt, z1 - pt, h, h + ph, Paint.toned(wall, 0.6))
	q.front(z0 + pt, x0 + pt, x1 - pt, h, h + ph, Paint.toned(wall, 0.68))
	q.box(Vector3(x0, h, z0), Vector3(x1, h + ph, z0 + pt), Color("ece9e1"), 0.0)
	q.box(Vector3(x0, h, z0), Vector3(x0 + pt, h + ph, z1), Color("ece9e1"), 0.0)
	var acs := [Vector3(1.2, h, -0.5)] if small else [Vector3(3.0, h, -0.4), Vector3(6.4, h, 0.1)]
	for ac in acs:
		q.box(ac - Vector3(0.6, 0, 0.5), ac + Vector3(0.6, 0.8, 0.5), Color("d6d6d0"), 0.3)
		var g := q.on_wall(ac + Vector3(-0.6, 0.8, 0.5), 1, 1)
		p.ellipse(g.x + 2.0, g.y + 3.0, 2.0, 2.0, Color("6c7076"))
		p.px(g.x + 1, g.y + 2, Color("9a9ea4"))
	q.box(Vector3(x0, h, z1 - pt), Vector3(x1, h + ph, z1), Color("f6f4ee"), 0.25)
	q.box(Vector3(x1 - pt, h, z0), Vector3(x1, h + ph, z1), Color("f6f4ee"), 0.25)
	# the lightbox over the door, standing proud of the fascia and up past the parapet
	var dx := x0 + (door + 4.5) / (0.707 * k)
	var hw := 1.4 if small else 2.8
	var s0 := Vector3(dx - hw, h - 1.15, z1)
	var s1 := Vector3(dx + hw, h + (0.6 if small else 0.9), z1 + 0.35)
	q.box(s0, s1, c, 0.3)
	var face := Vector3(s0.x, s1.y, s1.z)
	var sfw := roundi(q.pt(Vector3(s1.x, s1.y, s1.z)).x) - roundi(q.pt(face).x)
	var sfh := roundi((s1.y - s0.y) * 0.866 * k)
	q.fpx(face, 1, 1, sfw - 2, sfh - 2, Color("fdfcf6"))
	var mid := q.on_wall(face, 5, sfh / 2 - 1)
	var ink := Color("4a4a50") if yours else c.darkened(0.25)
	if yours:
		p.ellipse(mid.x + 0.5, mid.y + 0.5, 2.5, 2.5, STRIPE[0])
		p.ellipse(mid.x + 0.5, mid.y + 0.5, 1.2, 1.2, STRIPE[1])
	else:
		p.ellipse(mid.x + 0.5, mid.y + 0.5, 2.5, 2.5, c)
		p.px(mid.x - 1, mid.y, Color.WHITE)
		p.px(mid.x + 1, mid.y, Color.WHITE)
	q.fpx(face, 9, sfh / 2 - 2, sfw - 12, 1, ink)
	q.fpx(face, 9, sfh / 2, sfw - 14, 1, Paint.shade(ink, 0.35))
	if small:
		# a striped awning over the door, the recycling bins beside it
		var a0 := x0 + (door - 1.5) / (0.707 * k)
		var a1 := x0 + (door + 11.5) / (0.707 * k)
		var ay := h - 1.35
		for i in 6:
			var u0 := lerpf(a0, a1, i / 6.0)
			var u1 := lerpf(a0, a1, (i + 1) / 6.0)
			var col := c if i % 2 == 0 else Color.WHITE
			q.face([Vector3(u0, ay, z1), Vector3(u1, ay, z1), Vector3(u1, ay - 0.45, z1 + 0.8), Vector3(u0, ay - 0.45, z1 + 0.8)], col)
			q.front(z1 + 0.8, u0, u1, ay - 0.7, ay - 0.45, Paint.toned(col, 0.85))
		var b0 := Vector3(x0 + 0.3, 0, z1 + 0.15)
		q.box(b0, b0 + Vector3(0.85, 1.05, 0.7), Color("f0eee8"), 0.25)
		q.fpx(Vector3(b0.x, 1.05, b0.z + 0.7), 1, 1, 4, 1, c)
		q.fpx(Vector3(b0.x, 1.05, b0.z + 0.7), 1, 3, 4, 1, Color("4a4a50"))
	else:
		for i in 3:
			var cx := x1 - 4.6 + i * 0.4
			var cz := z1 + 0.5
			q.box(Vector3(cx, 0.15, cz), Vector3(cx + 0.9, 0.95, cz + 0.6), Color("c9ccd0"), 0.0)
			q.front(cz + 0.6, cx + 0.1, cx + 0.8, 0.25, 0.85, Color("8d9197"))
			q.front(cz + 0.6, cx, cx + 0.9, 0.85, 0.95, c)


## Runs of windows on a wall, each [first column, last column] of `at` (see Pen.fpx) from row v0 to v1: a dark
## frame, panes of glass with mullions every 7 px and a glint, the shop's lights and shelves of goods behind; a double
## door from column `door`.
static func windows(q: Pen, at: Vector3, runs: Array, v0: int, v1: int, door: int, on_side: bool) -> void:
	var t := 0.75 if on_side else 0.9
	var frame := Paint.toned(Color("4f5862"), t)
	var glass := Paint.toned(Color("86c1e6"), t)
	var goods := [Color("e8483c"), Color("f2c12e"), Color("3fa64a"), Color("2f7fd6"), Color("f29a2e"), Color("ee74b4")]
	for r in runs:
		var u0: int = r[0]
		var u1: int = r[1]
		q.fpx(at, u0, v0, u1 - u0, v1 - v0, frame, on_side)
		q.fpx(at, u0 + 1, v0 + 1, u1 - u0 - 2, v1 - v0 - 2, glass, on_side)
		q.fpx(at, u0 + 1, v0 + 1, u1 - u0 - 2, 2, Paint.toned(Color("d6eefa"), t), on_side)
		for s in [v0 + 7, v0 + 11]:
			if s >= v1 - 2:
				continue
			q.fpx(at, u0 + 1, s, u1 - u0 - 2, 1, Paint.toned(Color("e6ecef"), t), on_side)
			for u in range(u0 + 1, u1 - 1):
				if (u * 7 + s * 3) % 5 < 3:
					q.fpx(at, u, s - 2, 1, 2, Paint.toned(goods[(u * 3 + s) % goods.size()], t), on_side)
		var u := u0 + 7
		while u < u1 - 3:
			if door < 0 or u < door - 1 or u > door + 10:
				q.fpx(at, u, v0 + 1, 1, v1 - v0 - 2, frame, on_side)
			u += 7
		for g in range(u0 + 2, u1 - 3, 7):
			q.fpx(at, g, v0 + 4, 1, 2, Color(1, 1, 1, 0.7), on_side)
			q.fpx(at, g + 1, v0 + 3, 1, 2, Color(1, 1, 1, 0.7), on_side)
	if door >= 0:
		q.fpx(at, door, v0 - 1, 10, v1 - v0 + 1, frame)
		q.fpx(at, door + 1, v0, 4, v1 - v0 - 1, Paint.toned(Color("b4dcf2"), t))
		q.fpx(at, door + 5, v0, 4, v1 - v0 - 1, Paint.toned(Color("b4dcf2"), t))
		q.fpx(at, door + 4, v0 + 6, 1, 3, Color("e6e8ea"))
		q.fpx(at, door + 5, v0 + 6, 1, 3, Color("e6e8ea"))
		q.fpx(at, door + 1, v0 + 3, 1, 3, Color(1, 1, 1, 0.8))
		q.fpx(at, door + 2, v0 + 2, 1, 2, Color(1, 1, 1, 0.8))


# ---------- the back walls ----------

## Your shop's back wall seen from the floor, 316 x 201 (3 m high, 4.7 m wide), tiled left to right along the
## cutaway's back wall and seen through the closed shop's glass. It carries on the side wall in the tone of a wall
## turned to the sun: plaster panels butted every 1.5 m, each a shade off, lit from the ceiling and fading toward the
## skirting, a capping rail under your stripes (level with the side wall's, at 0.927 and 0.866 of its height), and a
## poster on each panel at the side wall's posters' height, over the fridges' tops.
static func konbini_wall() -> Image:
	var p := Paint.new(158, 101)
	var plaster := Color("efe6d2")
	var px_m := 101 / 3.0
	var row := func(y: float) -> int: return roundi((3.0 - y) * px_m)
	p.rect(0, 0, 158, 101, Paint.toned(plaster, 0.9))
	p.rect(0, 0, 158, 1, Paint.toned(plaster, 0.78))
	p.rect(0, row.call(2.855), 158, 5, Paint.toned(STRIPE[0], 0.9))
	p.rect(0, row.call(2.673), 158, 5, Paint.toned(STRIPE[1], 0.9))
	var r0: int = row.call(2.53)
	var r1: int = row.call(0.12)
	var joints := [0, 53, 105, 158]
	for i in 3:
		var t: float = 0.9 + [0.012, -0.01, 0.004][i]
		for y in range(r0, r1):
			var u := float(y - r0) / (r1 - r0)
			var k := lerpf(t + 0.03, t - 0.08, u)
			p.span(y, joints[i], joints[i + 1] - 1, Color(plaster.r * k, plaster.g * k, plaster.b * (k - 0.01 * u)))
		p.rect(joints[i], r0, 1, r1 - r0, Paint.toned(plaster * Color(0.88, 0.86, 0.83), 0.9))
		wall_poster(p, (joints[i] + joints[i + 1]) / 2, row.call(2.43), i)
	p.rect(0, r0, 158, 1, Paint.toned(Color("d9d4c8"), 0.9))
	p.rect(0, r0 + 1, 158, 1, Paint.toned(plaster, 0.8))
	p.rect(0, r1, 158, 101 - r1, Paint.toned(Color("a08a68"), 0.9))
	p.rect(0, r1, 158, 1, Paint.toned(Color("b8a07c"), 0.9))
	return p.doubled().get_region(Rect2i(0, 0, 316, 201))


## A poster as the side wall hangs them, 29 x 30 px centred on column cx from row top, toned as its wall: a frame,
## the paper printed with a product (onigiri, a hot coffee, karaage in its cup) on a ground of its colour, a tag in
## the corner and the price flash under it.
static func wall_poster(p: Paint, cx: int, top: int, kind: int) -> void:
	var looks := [[STRIPE[0], Color("fde2c6")], [STRIPE[1], Color("dff0d6")], [Color("e8a92a"), Color("fbe2a4")]]
	var frame: Color = looks[kind][0]
	var x0 := cx - 14
	var t := func(c: Color) -> Color: return Paint.toned(c, 0.9)
	p.rect(x0 + 1, top + 1, 29, 30, Color(0, 0, 0, 0.1))
	p.rect(x0, top, 29, 30, t.call(frame))
	p.rect(x0, top, 29, 1, t.call(Paint.shade(frame, 0.25)))
	p.rect(x0 + 2, top + 2, 25, 20, t.call(Color("fffaf0")))
	p.rect(x0 + 3, top + 6, 23, 15, t.call(looks[kind][1]))
	p.rect(x0 + 3, top + 3, 9, 2, t.call(Color("d8452f") if kind != 1 else STRIPE[1]))
	p.rect(x0 + 14, top + 3, 9, 1, t.call(Color("8a857a")))
	p.rect(x0 + 7, top + 24, 15, 3, t.call(Color("fff3c4")))
	p.rect(x0 + 9, top + 25, 7, 1, t.call(Color("d8452f")))
	var c := Vector2(cx + 0.5, top + 14.5)
	match kind:
		0:  # an onigiri in its nori
			p.poly(PackedVector2Array([c + Vector2(-8, 6), c + Vector2(0, -7), c + Vector2(8, 6)]), t.call(Color("cfc6b4")))
			p.poly(PackedVector2Array([c + Vector2(-6.5, 5), c + Vector2(0, -5.5), c + Vector2(6.5, 5)]), t.call(Color("fdfdf8")))
			p.rect(cx - 3, top + 15, 7, 6, t.call(Color("2f3a33")))
			p.rect(cx - 3, top + 15, 7, 1, t.call(Color("52645a")))
		1:  # a hot coffee
			p.rect(cx - 5, top + 9, 10, 2, t.call(Color("e2dbcc")))
			p.rect(cx - 4, top + 11, 8, 9, t.call(Color("fbf7ee")))
			p.rect(cx - 4, top + 13, 8, 4, t.call(Color("9a5c32")))
			p.rect(cx - 4, top + 11, 1, 9, t.call(Color("ffffff")))
			for i in 3:
				p.rect(cx - 3 + i * 2, top + 7 - (i % 2), 1, 1, t.call(Color("a89e90")))
		2:  # karaage in a red paper cup
			for j in 5:
				var s := c + Vector2(-4.5 + (j % 3) * 4.5 + (j / 3) * 2.2, -2.5 - (j / 3) * 3.5)
				p.ellipse(s.x + 0.3, s.y + 0.5, 2.8, 2.3, t.call(Color("9a5418")))
				p.ball(s.x, s.y, 2.3, 1.9, t.call(Color("e09a38")))
			p.poly(PackedVector2Array([c + Vector2(-7, -1), c + Vector2(7, -1), c + Vector2(5, 6), c + Vector2(-5, 6)]), t.call(Color("d8392e")))
			p.rect(cx - 6, top + 14, 14, 1, t.call(Color("f4f0e6")))


## A supermarket's floor seen through the rival's glass front, 560 x 119 (tinted cool by its caller): two produce
## cases packed with vegetables and fruit under green canopies, the fish counter on ice under blue and the meat counter
## under red, lamps hanging over each, a stack of baskets and two checkouts.
static func super_shelves() -> Image:
	var p := Paint.new(280, 60)
	p.rect(0, 0, 280, 60, Color("f0e4c8"))
	p.rect(0, 2, 280, 2, Color("3fa25e"))
	for x in range(18, 280, 46):
		p.rect(x, 0, 2, 8, Color("d8c8a4"))
	p.rect(0, 52, 280, 8, Color("e9d8b2"))
	p.rect(0, 52, 280, 1, Color("c9b48a"))
	for x in range(6, 280, 14):
		p.rect(x, 53, 1, 7, Color("dcc9a2"))
	var g := Paint.new(280, 60)  # the goods, on a layer of their own so an outline parts them
	case_front(p, g, 0, 66, Color("1f9d55"), 0)
	case_front(p, g, 68, 134, Color("1f9d55"), 1)
	case_front(p, g, 136, 204, Color("2f6fd6"), 2)
	case_front(p, g, 206, 262, Color("d8343a"), 3)
	g.outline(Color("23202a"))
	p.img.blend_rect(g.img, Rect2i(0, 0, 280, 60), Vector2i.ZERO)
	for i in 4:
		p.rect(2, 44 - i * 3, 12, 3, Color("d8343a"))
		p.rect(2, 44 - i * 3, 12, 1, Color("f06a6a"))
		p.rect(3, 45 - i * 3, 10, 1, Color("9a2028"))
	for i in 2:
		var x := 238 + i * 21
		p.rect(x, 40, 16, 12, Color("9aa3ad"))
		p.rect(x, 40, 16, 1, Color("c9d0d8"))
		p.rect(x + 2, 43, 12, 6, Color("3f8f5a"))
		p.rect(x + 9, 31, 6, 6, Color("3b4048"))
		p.rect(x + 10, 32, 4, 3, Color("6fc0d0"))
		p.rect(x + 11, 37, 2, 3, Color("6b7380"))
	return p.doubled().get_region(Rect2i(0, 0, 560, 119))


## A refrigerated case from x0 to x1: its canopy and lamps, two tiers of goods in the dark behind the glass (the goods
## onto layer g), the base.
static func case_front(p: Paint, g: Paint, x0: int, x1: int, canopy: Color, kind: int) -> void:
	var w := x1 - x0
	p.rect(x0, 7, w, 5, canopy)
	p.rect(x0, 7, w, 1, Paint.shade(canopy, 0.35))
	p.rect(x0, 11, w, 1, Paint.shade(canopy, -0.35))
	p.rect(x0, 12, w, 30, Color("3c4658"))
	p.rect(x0, 12, w, 2, Color("e8f0f4"))
	p.rect(x0, 12, 1, 30, Color("8a96a2"))
	p.rect(x1 - 1, 12, 1, 30, Color("8a96a2"))
	if kind >= 2:
		for lx in range(x0 + 8, x1 - 4, 16):
			p.rect(lx - 3, 14, 6, 2, Paint.shade(canopy, -0.15))
			p.rect(lx - 2, 16, 4, 1, Color("fff6c8"))
	for tier in 2:
		var y := 26 + tier * 13  # the tier's front edge
		var bed := Color("d8eef8") if kind == 2 else (Color("f4f0ea") if kind == 3 else Color("7a5434"))
		if kind >= 2:
			p.rect(x0 + 1, y - 6, w - 2, 6, bed)
			p.rect(x0 + 1, y - 6, w - 2, 1, Paint.shade(bed, -0.15))
		var x := x0 + 2
		var i := 0
		while x < x1 - 7:
			match kind:
				0, 1:
					x += produce(p, g, x, y, (i * 5 + tier * 3 + kind * 2) % 8)
				2:
					x += seafood(g, x, y, (i + tier) % 3)
				3:
					x += cut(g, x, y, (i + tier * 2) % 3)
			i += 1
		p.rect(x0 + 1, y, w - 2, 1, Color("f6f6f2"))
		for tx in range(x0 + 4, x1 - 3, 9):
			p.px(tx, y, Color("e8483c"))
		p.rect(x0 + 1, y + 1, w - 2, 1, Color("8e9aa6"))
	p.rect(x0, 42, w, 10, Color("4c566b"))
	p.rect(x0, 42, w, 1, Color("a4afc0"))
	p.rect(x0 + 3, 46, w - 6, 3, Color("38404f"))
	for i in range(0, w - 10, 16):
		p.rect(x0 + 6 + i, 47, 5, 1, Color("6c778a"))


## A crate of one kind of produce at column x, its front edge on row y: the crate onto p, the produce heaped in it
## onto g, a pixel apart so its outline parts them; returns its width.
static func produce(p: Paint, g: Paint, x: int, y: int, kind: int) -> int:
	p.rect(x, y - 2, 10, 2, Color("8a5a32"))
	p.rect(x, y - 2, 10, 1, Color("a8754a"))
	match kind:
		0:  # cabbages
			for j in 2:
				g.ball(x + 2.5 + j * 5.0, y - 4.5, 2.1, 2.1, Color("8cc84a"), 0.1)
			g.ball(x + 5.0, y - 8.0, 2.1, 2.1, Color("9ad458"), 0.1)
		1, 5:  # tomatoes, oranges
			var c := Color("e43a30") if kind == 1 else Color("f6a02a")
			for r in 3:
				for j in 3 - r:
					g.ball(x + 1.5 + j * 4.0 + r * 2.0, y - 4.0 - r * 3.0, 1.5, 1.5, c)
		2:  # daikon
			for j in 3:
				g.rect(x + 1, y - 4 - j * 3, 8, 2, Color("f6f2e2"))
				g.rect(x + 1, y - 3 - j * 3, 8, 1, Color("d8d2bc"))
				g.rect(x + 8, y - 4 - j * 3, 1, 2, Color("8cc84a"))
		3:  # carrots
			for j in 3:
				g.rect(x + 1 + j * 3, y - 8, 2, 6, Color("f2832a"))
				g.px(x + 1 + j * 3, y - 8, Color("f8a85a"))
				g.rect(x + 1 + j * 3, y - 10, 1, 2, Color("4caf50"))
		4:  # eggplant
			for j in 2:
				g.ball(x + 2.5 + j * 5.0, y - 4.5, 1.8, 2.5, Color("6a3a9a"))
				g.px(x + 2 + j * 5, y - 7, Color("4c8a3a"))
		6:  # leeks
			for j in 3:
				g.rect(x + 1 + j * 3, y - 10, 2, 3, Color("3e9a3e"))
				g.rect(x + 1 + j * 3, y - 7, 2, 5, Color("f0f2e2"))
		7:  # corn
			for j in 3:
				g.rect(x + 1 + j * 3, y - 8, 2, 6, Color("f2c83a"))
				g.rect(x + 1 + j * 3, y - 9, 2, 1, Color("8cc84a"))
	return 11


## A column of the fish counter on its ice at column x, front edge on row y: whole fish, salmon steaks or prawns.
static func seafood(g: Paint, x: int, y: int, kind: int) -> int:
	for r in 2:
		var yy := y - 2 - r * 3
		var xx := x + (1 - r) * 2
		match kind:
			0:
				g.ellipse(xx + 3.5, yy, 3.5, 1.5, Color("a9b4c2"))
				g.rect(xx + 1, yy - 1, 5, 1, Color("dbe3ec"))
				g.rect(xx + 7, yy - 1, 1, 2, Color("8692a2"))
				g.px(xx + 1, yy, Color("1e2430"))
			1:
				g.rect(xx + 1, yy - 1, 5, 2, Color("f08a6a"))
				g.px(xx + 2, yy - 1, Color("fbd8c8"))
				g.px(xx + 4, yy, Color("fbd8c8"))
			2:
				for j in 2:
					g.rect(xx + 1 + j * 3, yy - 1, 2, 2, Color("f2907a"))
					g.px(xx + 1 + j * 3, yy - 1, Color("fbc4b0"))
	return 10


## A column of the meat counter at column x, front edge on row y: steaks, mince or sausages.
static func cut(g: Paint, x: int, y: int, kind: int) -> int:
	for r in 2:
		var yy := y - 2 - r * 3
		var xx := x + (1 - r) * 2
		match kind:
			0:
				g.ellipse(xx + 3.5, yy, 3.5, 1.5, Color("f2dcd2"))
				g.ellipse(xx + 3.2, yy - 0.2, 2.6, 1.2, Color("b8222c"))
				g.px(xx + 2, yy - 1, Color("dc4a50"))
			1:
				g.rect(xx + 1, yy - 1, 5, 2, Color("d8545a"))
				g.px(xx + 2, yy - 1, Color("f09a98"))
				g.px(xx + 4, yy, Color("f09a98"))
			2:
				g.rect(xx + 1, yy - 1, 5, 1, Color("e88a8a"))
				g.rect(xx + 1, yy, 5, 1, Color("cc6464"))
	return 9
