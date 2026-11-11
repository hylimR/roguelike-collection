extends RefCounted
## The icon sheets, painted in code: products (25 cells of 64 texels), perks (13 of 80) and decor (12 of 96). Each
## icon is painted at its own pixel grid, half its cell, in chunky shapes banded as lit from the top left under a dark
## selective outline, then doubled into its cell, standing as big in it as the shelves and HUD measure it.

const Paint := preload("res://art/paint.gd")
const W := Color.WHITE
const CLEAR := Color(0, 0, 0, 0)


## The products sheet: 25 cells of 64 texels in the order sim.gd and main.gd index them, onigiri to oden.
static func products() -> Image:
	var img := Image.create(1600, 64, false, Image.FORMAT_RGBA8)
	for i in 25:
		var p := Paint.new(32, 32)
		match i:
			0: onigiri(p)
			1: bento(p)
			2: sandwich(p)
			3: coffee_can(p)
			4: tea_bottle(p)
			5: energy_can(p)
			6: crisps(p)
			7: chocolate(p)
			8: cup_noodle(p)
			9: ice_cream(p)
			10: umbrella(p)
			11: newspaper(p)
			12: fish(p)
			13: meat_tray(p)
			14: cabbage(p)
			15: apple(p)
			16: egg_carton(p)
			17: milk_carton(p)
			18: bread(p)
			19: rice_sack(p)
			20: toilet_rolls(p)
			21: detergent(p)
			22: sake(p)
			23: bouquet(p)
			24: oden(p)
		finish(p, img, i * 64)
	return img


## The perks sheet: 13 cells of 80 texels, the staff girl to the coin stacks, then the City key's cherry tree.
static func perks() -> Image:
	var img := Image.create(1040, 80, false, Image.FORMAT_RGBA8)
	for i in 13:
		var p := Paint.new(40, 40)
		match i:
			0: staff(p)
			1: flyer(p)
			2: fridge(p)
			3: espresso(p)
			4: point_card(p)
			5: fry_basket(p)
			6: cctv(p)
			7: truck(p)
			8: neon_frame(p)
			9: maneki(p)
			10: register(p)
			11: coins(p)
			12: cherry_tree(p)
		finish(p, img, i * 80)
	return img


## The decor sheet: 12 cells of 96 texels, each standing on its cell's foot, the potted plant to the claw machine.
static func decor() -> Image:
	var img := Image.create(1152, 96, false, Image.FORMAT_RGBA8)
	for i in 12:
		var p := Paint.new(48, 48)
		match i:
			0: potted_plant(p)
			1: bench(p)
			2: vending(p)
			3: gacha(p)
			4: bonsai(p)
			5: chalkboard(p)
			6: atm(p)
			7: freezer(p)
			8: magazine_rack(p)
			9: lantern(p)
			10: aquarium(p)
			11: claw_machine(p)
		finish(p, img, i * 96)
	return img


## Rims p's icon in its outline and doubles it into the sheet at texel x.
static func finish(p: Paint, img: Image, x: int) -> void:
	rim(p)
	p.stamp(img, Vector2i(x, 0))


## Rims every painted shape in a dark selective outline: each empty pixel touching one (4-neighbours) takes its
## darkest painted neighbour pushed deep into shade, darker than Paint.outline so pale icons hold on the cream HUD.
static func rim(p: Paint) -> void:
	var src: Image = p.img.duplicate()
	for y in p.h:
		for x in p.w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			var best := CLEAR
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + d
				if q.x < 0 or q.y < 0 or q.x >= p.w or q.y >= p.h:
					continue
				var n := src.get_pixel(q.x, q.y)
				if n.a > 0.5 and (best.a == 0.0 or n.get_luminance() < best.get_luminance()):
					best = n
			if best.a > 0.0:
				p.img.set_pixel(x, y, Paint.shade(best, -0.86))


# ---------- painting helpers ----------

## Flat [x0, y0, x1, y1, ...] as points.
static func pv(a: Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for i in range(0, a.size(), 2):
		o.append(Vector2(a[i], a[i + 1]))
	return o


## A deterministic value in [0, 1) for pixel (x, y), for speckled textures.
static func noise(x: int, y: int, s: int) -> float:
	var n := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n >> 8) & 0xffff) / 65536.0


## The corners of the rectangle a0..a1 along u and b0..b1 along v from o.
static func quad(o: Vector2, u: Vector2, v: Vector2, a0: float, a1: float, b0: float, b1: float) -> PackedVector2Array:
	return PackedVector2Array([o + u * a0 + v * b0, o + u * a1 + v * b0, o + u * a1 + v * b1, o + u * a0 + v * b1])


## The same rectangle with its corners rounded to radius r.
static func rrect(o: Vector2, u: Vector2, v: Vector2, a0: float, a1: float, b0: float, b1: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [[a1 - r, b0 + r, -PI / 2], [a1 - r, b1 - r, 0.0], [a0 + r, b1 - r, PI / 2], [a0 + r, b0 + r, PI]]
	for c: Array in corners:
		for k in 4:
			var t: float = c[2] + k * PI / 6
			pts.append(o + u * (c[0] + cos(t) * r) + v * (c[1] + sin(t) * r))
	return pts


## An empty mask the size of p: any Paint call on it marks pixels.
static func mask(p: Paint) -> Paint:
	return Paint.new(p.w, p.h)


## The pixels of mask a that are also in mask b.
static func both(a: Paint, b: Paint) -> Paint:
	var m := mask(a)
	m.img.blit_rect_mask(a.img, b.img, Rect2i(0, 0, a.w, a.h), Vector2i.ZERO)
	return m


## Mask m cut to rows y0..y1.
static func rows(m: Paint, y0: int, y1: int) -> Paint:
	var o := mask(m)
	o.img.blit_rect(m.img, Rect2i(0, y0, m.w, y1 - y0 + 1), Vector2i(0, y0))
	return o


## Mask m as bytes with a two-pixel empty border, (w + 4) a row, so neighbours need no bounds checks.
static func cells(m: Paint, r: Rect2i) -> PackedByteArray:
	var d := m.img.get_data()
	var pw := m.w + 4
	var o := PackedByteArray()
	o.resize(pw * (m.h + 4))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if d[(y * m.w + x) * 4 + 3] > 0:
				o[(y + 2) * pw + x + 2] = 1
	return o


## Paints mask m onto p in c, banded as lit from the top left: two bands of highlight along its upper-left rim (hi)
## and two of shade along its lower-right rim (lo).
static func fill(p: Paint, m: Paint, c: Color, hi := 0.2, lo := -0.22) -> void:
	var r := m.img.get_used_rect()
	var o := cells(m, r)
	var pw := m.w + 4
	var tones := [Paint.shade(c, lo), Paint.shade(c, hi), Paint.shade(c, lo * 0.45), Paint.shade(c, hi * 0.45), c]
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := (y + 2) * pw + x + 2
			if o[i] == 0:
				continue
			var t := 4
			if o[i + 1] == 0 or o[i + pw] == 0:
				t = 0
			elif o[i - 1] == 0 or o[i - pw] == 0:
				t = 1
			elif o[i + 2] == 0 or o[i + 2 * pw] == 0 or o[i + pw + 1] == 0:
				t = 2
			elif o[i - 2] == 0 or o[i - 2 * pw] == 0:
				t = 3
			p.px(x, y, tones[t])


## The band of an upright cylinder at u across its width: a highlight a quarter of the way in, shade to the right.
static func band(u: float) -> float:
	return 0.26 if u > 0.18 and u < 0.36 else (0.0 if u < 0.62 else (-0.18 if u < 0.84 else -0.34))


## Paints mask m onto p in c as an upright cylinder, banded across its width.
static func fill_barrel(p: Paint, m: Paint, c: Color) -> void:
	var r := m.img.get_used_rect()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if m.img.get_pixel(x, y).a > 0.0:
				p.px(x, y, Paint.shade(c, band((x - r.position.x + 0.5) / r.size.x)))


## Paints mask m onto p in c as a ball filling its extent, in Paint.ball's four bands.
static func fill_ball(p: Paint, m: Paint, c: Color, soft := 0.0) -> void:
	var r := m.img.get_used_rect()
	var l := Paint.LIGHT.normalized()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if m.img.get_pixel(x, y).a == 0.0:
				continue
			var dx := (x + 0.5 - r.position.x) / r.size.x * 2.0 - 1.0
			var dy := (y + 0.5 - r.position.y) / r.size.y * 2.0 - 1.0
			var d2 := minf(dx * dx + dy * dy, 0.98)
			var lit := Vector3(dx, dy, sqrt(1.0 - d2)).dot(l) + soft
			p.px(x, y, Paint.shade(c, 0.28 if lit > 0.78 else (0.0 if lit > 0.3 else (-0.2 if lit > -0.05 else -0.36))))


## Fills polygon a (points, or flat [x0, y0, ...]) on p through `fill`, returning its mask.
static func lit_poly(p: Paint, a: Variant, c: Color, hi := 0.2, lo := -0.22) -> Paint:
	var m := mask(p)
	m.poly(a if a is PackedVector2Array else pv(a), W)
	fill(p, m, c, hi, lo)
	return m


## Fills the rectangle (x, y, w, h) on p through `fill`, returning its mask.
static func lit_rect(p: Paint, x: int, y: int, w: int, h: int, c: Color, hi := 0.2, lo := -0.22) -> Paint:
	var m := mask(p)
	m.rect(x, y, w, h, W)
	fill(p, m, c, hi, lo)
	return m


## Fills the ellipse round (cx, cy) on p through `fill`, returning its mask.
static func lit_ellipse(p: Paint, cx: float, cy: float, rx: float, ry: float, c: Color, hi := 0.2, lo := -0.22) -> Paint:
	var m := mask(p)
	m.ellipse(cx, cy, rx, ry, W)
	fill(p, m, c, hi, lo)
	return m


## Shades p's pixels under mask m by k where the pixel's noise falls under `density`, a grain.
static func speckle(p: Paint, m: Paint, k: float, density: float, s: int) -> void:
	var r := m.img.get_used_rect()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if m.img.get_pixel(x, y).a > 0.0 and noise(x, y, s) < density:
				p.img.set_pixel(x, y, Paint.shade(p.img.get_pixel(x, y), k))


## Dots c over mask m where the pixel's noise falls under `density`.
static func dots(p: Paint, m: Paint, c: Color, density: float, s: int) -> void:
	var r := m.img.get_used_rect()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if m.img.get_pixel(x, y).a > 0.0 and noise(x, y, s) < density:
				p.px(x, y, c)


## Clears mask m's pixels from p, a hole the outline then rims from inside.
static func erase(p: Paint, m: Paint) -> void:
	var r := m.img.get_used_rect()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if m.img.get_pixel(x, y).a > 0.0:
				p.img.set_pixel(x, y, CLEAR)


## A stroke through points pts.
static func path(p: Paint, pts: PackedVector2Array, c: Color, width := 1.0) -> void:
	for i in pts.size() - 1:
		p.line(pts[i], pts[i + 1], c, width)


## A stroke along the ellipse round (cx, cy) from angle d0 to d1 (degrees, clockwise from +x on screen).
static func arc(p: Paint, cx: float, cy: float, rx: float, ry: float, d0: float, d1: float, c: Color, width := 1.0) -> void:
	var pts := PackedVector2Array()
	var n := maxi(3, ceili(absf(d1 - d0) / 12.0))
	for k in n + 1:
		var t := deg_to_rad(lerpf(d0, d1, float(k) / n))
		pts.append(Vector2(cx + cos(t) * rx, cy + sin(t) * ry))
	path(p, pts, c, width)


## A box seen from the front and a little above and to the left: its front face (x, y, w, h), its top going back
## (dx, -dy) and its right side, the top lit and the side shaded.
static func box3(p: Paint, x: float, y: float, w: float, h: float, dx: float, dy: float, c: Color, hi := 0.16, lo := -0.2) -> void:
	lit_poly(p, [x, y, x + w, y, x + w + dx, y - dy, x + dx, y - dy], Paint.shade(c, 0.16), hi * 0.6, lo * 0.4)
	lit_poly(p, [x + w, y, x + w + dx, y - dy, x + w + dx, y + h - dy, x + w, y + h], Paint.shade(c, -0.22), hi * 0.4, lo * 0.6)
	lit_poly(p, [x, y, x + w, y, x + w, y + h, x, y + h], c, hi, lo)


## A can over columns x0..x1 and rows y0..y1: an aluminium lid and foot round a body banded across its width, printed
## in `bands` of [first row, colour] from the top down.
static func can(p: Paint, x0: int, x1: int, y0: int, y1: int, bands: Array) -> void:
	var steel := Color("c3c9d2")
	for i in bands.size():
		var b: Array = bands[i]
		var to: int = (bands[i + 1][0] - 1) if i + 1 < bands.size() else y1 - 2
		p.barrel(x0, b[0], x1, to, b[1])
	p.barrel(x0, y0 + 2, x1, y0 + 3, steel)
	p.barrel(x0, y1 - 1, x1, y1, steel)
	p.img.set_pixel(x0, y1, CLEAR)
	p.img.set_pixel(x1, y1, CLEAR)
	var cx := (x0 + x1 + 1) / 2.0
	var rx := (x1 - x0 + 1) / 2.0
	p.ellipse(cx, y0 + 2.0, rx, 2.0, Paint.shade(steel, 0.2))
	p.ellipse(cx, y0 + 2.0, rx - 1.6, 1.1, Paint.shade(steel, -0.18))
	p.span(y0 + 1, floori(cx) - 1, floori(cx) + 1, Paint.shade(steel, 0.35))


## A leaf from base to tip, wd at its widest, its midrib lit; `rimmed` sets it off from the leaves behind in a dark edge.
static func leaf(p: Paint, base: Vector2, tip: Vector2, wd: float, c: Color, rimmed := false) -> void:
	var d := tip - base
	var n := Vector2(-d.y, d.x).normalized() * wd
	var pts := PackedVector2Array([base, base + d * 0.2 + n * 0.6, base + d * 0.5 + n, base + d * 0.8 + n * 0.7, tip,
		base + d * 0.8 - n * 0.7, base + d * 0.5 - n, base + d * 0.2 - n * 0.6])
	if rimmed:
		var mid := base + d * 0.5
		var edge := PackedVector2Array()
		for q in pts:
			edge.append(q + (q - mid).normalized() * 1.0)
		p.poly(edge, Paint.shade(c, -0.6))
	lit_poly(p, pts, c, 0.22, -0.28)
	p.line(base + d * 0.1, base + d * 0.8, Paint.shade(c, 0.3))


## A five-petalled blossom of radius r round (cx, cy) on a dark rim that shows between its petals, its heart in `heart`.
static func blossom(p: Paint, cx: float, cy: float, r: float, c: Color, heart: Color) -> void:
	p.ellipse(cx + 0.3, cy + 0.4, r * 0.78, r * 0.78, Paint.shade(c, -0.58))
	for k in 5:
		var t := -PI / 2 + k * TAU / 5
		p.ball(cx + cos(t) * r * 0.6, cy + sin(t) * r * 0.6, r * 0.42, r * 0.42, c, 0.15)
	p.ellipse(cx, cy, 1.1, 1.1, heart)


## A five-pointed star round (cx, cy), r to its points.
static func star(cx: float, cy: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var t := -PI / 2 + k * PI / 5
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(Vector2(cx + cos(t) * rr, cy + sin(t) * rr))
	return pts


# ---------- products: 32 px a cell ----------

static func onigiri(p: Paint) -> void:
	var rice := lit_poly(p, [12.5, 5, 15.5, 2.5, 18.5, 5, 28.5, 24, 27.5, 28.5, 3.5, 28.5, 2.5, 24], Color("f6f3ea"), 0.12, -0.3)
	speckle(p, rice, -0.1, 0.2, 1)
	var nori := lit_poly(p, [11.5, 9.5, 20, 9.5, 26, 24, 24.5, 28.5, 7, 28.5, 5.5, 24], Color("24432a"), 0.14, -0.25)
	speckle(p, nori, 0.2, 0.16, 2)
	p.line(Vector2(18.5, 10.5), Vector2(22.5, 27.5), Color("9aae92"))


static func bento(p: Paint) -> void:
	lit_rect(p, 2, 6, 28, 16, Color("34343e"), 0.3, -0.2)
	lit_rect(p, 2, 21, 28, 5, Color("1f1f27"), 0.1, -0.15)
	p.rect(4, 8, 24, 12, Color("18181e"))
	var rice := lit_rect(p, 4, 8, 10, 12, Color("f6f3ea"), 0.1, -0.22)
	speckle(p, rice, -0.1, 0.22, 3)
	p.ball(8.5, 13, 2.2, 2.2, Color("d8322b"))
	lit_rect(p, 15, 8, 7, 4, Color("f5c845"), 0.25, -0.25)
	p.line(Vector2(18, 8), Vector2(18, 11), Color("d8a134"))
	p.ball(24, 9.5, 2.2, 2.0, Color("5bb84a"), 0.2)
	p.ball(26.5, 10, 1.6, 1.8, Color("4aa63e"), 0.2)
	for k: Array in [[18, 15, 2.6], [23.5, 14.8, 2.6], [20.5, 18, 2.5], [25.8, 18, 2.3], [16.2, 18.2, 1.8]]:
		p.ball(k[0], k[1], k[2], k[2] * 0.9, Color("c9792c"), 0.1)


static func sandwich(p: Paint) -> void:
	lit_poly(p, [14, 3, 18.5, 2.5, 27, 26.5, 25.5, 29.5, 17, 29.5], Color("e6cf9c"), 0.12, -0.3)
	var face := mask(p)
	face.poly(pv([15.5, 3, 19.5, 29.5, 4, 29.5]), W)
	for c: Array in [[0.0, 2.6, Color("f7ecd0")], [2.6, 4.4, Color("5fb83a")], [4.4, 11.0, Color("f6cc3a")], [11.0, 16.0, Color("f7ecd0")]]:
		var b := mask(p)
		b.poly(pv([15.5 + c[0], 3, 15.5 + c[1], 3, 4 + c[1], 29.5, 4 + c[0], 29.5]), W)
		fill(p, both(face, b), c[2], 0.18, -0.2)
	p.line(Vector2(5.2, 27.5), Vector2(14.6, 4.5), Color(1, 1, 1))
	p.line(Vector2(19.6, 6), Vector2(25.6, 25), Color("faf4e6"))
	lit_rect(p, 14, 3, 5, 3, Color("f6f2ea"), 0.1, -0.15)
	p.span(4, 15, 16, Color("e0483c"))
	p.px(17, 4, Color("e0483c"))


static func coffee_can(p: Paint) -> void:
	can(p, 9, 22, 2, 29, [[4, Color("dba43c")], [10, Color("5b3219")], [16, Color("dba43c")]])
	for b: Array in [[13.5, 21.5], [18.2, 23.5]]:
		p.ellipse(b[0], b[1], 2.2, 2.8, Color("6a3a1c"))
		p.line(Vector2(b[0] - 0.6, b[1] - 2), Vector2(b[0] + 0.6, b[1] + 2), Color("3b1d0c"))
	p.span(15, 9, 22, Color("8d5a28"))


static func tea_bottle(p: Paint) -> void:
	var bottle := mask(p)
	bottle.rect(14, 5, 3, 3, W)
	bottle.poly(pv([13.5, 8, 17.5, 8, 21, 11.5, 21, 29.5, 10, 29.5, 10, 11.5]), W)
	bottle.img.set_pixel(10, 29, CLEAR)
	bottle.img.set_pixel(20, 29, CLEAR)
	fill_barrel(p, bottle, Color("8cc63f"))
	fill_barrel(p, rows(bottle, 5, 9), Color("cfe7a6"))
	fill_barrel(p, rows(bottle, 15, 23), Color("4f9330"))
	for y in [13, 25, 27]:
		p.span(y, 11, 19, Color("6aa832"))
	leaf(p, Vector2(12.5, 21), Vector2(17.5, 16.5), 1.6, Color("b8e27a"))
	p.barrel(13, 2, 17, 4, Color("f2f2ee"))


static func energy_can(p: Paint) -> void:
	can(p, 10, 21, 2, 29, [[4, Color("1f4fbe")]])
	lit_poly(p, [18, 8.5, 13, 18, 16, 18, 13.5, 26, 19.5, 15.5, 16.5, 15.5, 19, 8.5], Color("ffd23c"), 0.2, -0.2)


static func crisps(p: Paint) -> void:
	var red := Color("e3362a")
	lit_poly(p, [4, 4.5, 28, 5.5, 28.5, 26.5, 3.5, 26], red, 0.28, -0.32)
	var crimp := Paint.shade(red, -0.16)
	for y0 in [2.5, 25.8]:
		lit_poly(p, [3, y0, 29, y0 + 1.5, 29, y0 + 4.2, 3, y0 + 2.7], crimp, 0.15, -0.2)
		for x in range(4, 29, 2):
			p.line(Vector2(x, y0 + (x - 3) * 0.06 + 0.6), Vector2(x, y0 + (x - 3) * 0.06 + 2.0), Paint.shade(red, -0.32))
	for c: Array in [[11, 12.5, 4.5, 3.6], [19.5, 11, 4.5, 3.6], [14.5, 18.5, 4.6, 3.6], [22.5, 18, 4.0, 3.6], [8.5, 21.5, 3.6, 2.8], [19.5, 23, 4.2, 2.4]]:
		p.ellipse(c[0] + 0.4, c[1] + 0.5, c[2] + 0.7, c[3] + 0.7, Color("a8461e"))
		p.ball(c[0], c[1], c[2], c[3], Color("f6c94c"), 0.15)
	p.line(Vector2(5, 8), Vector2(5, 18), Paint.shade(red, 0.45))


static func chocolate(p: Paint) -> void:
	var o := Vector2(16.5, 15.5)
	var u := Vector2(cos(-0.47), sin(-0.47))
	var v := Vector2(-u.y, u.x)
	var choc := Color("7a462c")
	lit_poly(p, quad(o, u, v, -1.5, 11.5, 3.8, 5.6), Paint.shade(choc, -0.36), 0.0, -0.1)
	p.poly(quad(o, u, v, -1.5, 11.5, -5.4, 3.8), Paint.shade(choc, -0.4))
	for a: Array in [[0.2, 3.5], [4.5, 7.5], [8.5, 11.4]]:
		for b: Array in [[-5.4, -1.3], [-0.3, 3.8]]:
			lit_poly(p, quad(o, u, v, a[0], a[1], b[0], b[1]), choc, 0.3, -0.16)
	lit_poly(p, quad(o, u, v, -12.5, 0.2, -5.8, 6.2), Color("d9302a"), 0.28, -0.28)
	lit_poly(p, quad(o, u, v, -12.5, 0.2, 4.6, 6.2), Color("a61f1d"), 0.05, -0.15)
	var foil := Color("ccd0d8")
	lit_poly(p, PackedVector2Array([o + u * -2.0 + v * -6.0, o + u * 1.4 + v * -6.0, o + u * 0.4 + v * -3.0, o + u * 1.6 + v * 0.0,
		o + u * 0.4 + v * 3.0, o + u * 1.6 + v * 6.4, o + u * -2.0 + v * 6.4]), foil, 0.25, -0.3)
	p.line(o + u * -11.0 + v * -4.4, o + u * -4.0 + v * -4.4, Color("f08070"))


static func cup_noodle(p: Paint) -> void:
	var cup := mask(p)
	cup.poly(pv([4, 7, 28, 7, 25, 29.5, 7, 29.5]), W)
	fill_barrel(p, cup, Color("f5f2ec"))
	for b: Array in [[12, 13], [15, 15], [24, 25]]:
		fill_barrel(p, both(rows(cup, b[0], b[1]), cup), Color("e2342b"))
	lit_ellipse(p, 16, 6.5, 12.5, 3.8, Color("f8f6f0"), 0.15, -0.25)
	lit_ellipse(p, 16, 6.5, 10.5, 2.6, Color("e4a73f"), -0.2, 0.18)
	for d: Array in [[11, 6, "4caf3a"], [12, 7, "4caf3a"], [17, 5, "f6dd6a"], [18, 6, "f6dd6a"], [20, 7, "8a4f26"], [21, 7, "8a4f26"], [14, 8, "f08a6a"]]:
		p.px(d[0], d[1], Color(d[2]))


static func ice_cream(p: Paint) -> void:
	var o := Vector2(17, 13.5)
	var u := Vector2(0.42, -0.91)
	var v := Vector2(0.91, 0.42)
	lit_poly(p, rrect(o, u, v, -16, -8, -1.5, 1.5, 0.8), Color("e8c07a"), 0.2, -0.28)
	var bar := lit_poly(p, rrect(o, u, v, -10, 9.5, -5, 5, 2.6), Color("7b3f1f"), 0.18, -0.24)
	dots(p, bar, Color("f0a845"), 0.1, 5)


static func umbrella(p: Paint) -> void:
	var t := Vector2(6, 28.5)
	var u := Vector2(0.5, -0.866)
	var v := Vector2(0.866, 0.5)
	var ink := Color("33333f")
	p.line(t + u * 20.5, t + u * 23.5, ink, 1.6)
	arc(p, 21.4, 5.4, 2.6, 2.6, 175, 360, ink, 1.6)
	p.line(Vector2(24, 5.5), Vector2(24, 8.5), ink, 1.6)
	var prof := func(a: float) -> float: return 3.4 * pow(sin(PI * clampf((a - 2.0) / 20.0, 0.0, 1.0)), 0.55) + 0.3
	var side_l := PackedVector2Array()
	var side_r := PackedVector2Array()
	for k in 12:
		var a := lerpf(2.5, 21.0, k / 11.0)
		side_l.append(t + u * a - v * prof.call(a))
		side_r.append(t + u * a + v * prof.call(a))
	side_r.reverse()
	lit_poly(p, side_l + side_r, Color("e2e9f2"), 0.2, -0.32)
	for f in [-0.45, 0.2]:
		var fold := PackedVector2Array()
		for k in 9:
			var a := lerpf(3.5, 20.0, k / 8.0)
			fold.append(t + u * a + v * (f * prof.call(a)))
		path(p, fold, Color("97a9c0"))
	lit_poly(p, quad(t, u, v, 9.5, 11, -3.9, 3.9), Color("4d5d7c"), 0.2, -0.2)
	p.line(t, t + u * 3.0, ink, 1.6)


static func newspaper(p: Paint) -> void:
	var a := Vector2(5.5, 4)
	var b := Vector2(29.5, 8)
	var d := Vector2(2.5, 20.5)
	var c := b + d - a
	var pages := Color("d9d6cf")
	lit_poly(p, PackedVector2Array([d, c, c + Vector2(0, 3), d + Vector2(0, 3)]), pages, 0.0, -0.2)
	lit_poly(p, PackedVector2Array([c, b, b + Vector2(0, 3), c + Vector2(0, 3)]), Paint.shade(pages, -0.15), 0.0, -0.15)
	p.line(d + Vector2(1, 1.5), c + Vector2(-1, 1.5), Paint.shade(pages, -0.25))
	lit_poly(p, PackedVector2Array([a, b, c, d]), Color("eeede8"), 0.15, -0.22)
	var at := func(s: float, t: float) -> Vector2: return a + (b - a) * s + (d - a) * t
	var ink := Color("54545c")
	var grey := Color("b4b2ac")
	p.poly(PackedVector2Array([at.call(0.08, 0.08), at.call(0.55, 0.08), at.call(0.55, 0.17), at.call(0.08, 0.17)]), ink)
	lit_poly(p, PackedVector2Array([at.call(0.08, 0.28), at.call(0.38, 0.28), at.call(0.38, 0.55), at.call(0.08, 0.55)]), Color("85858c"), 0.1, -0.1)
	lit_poly(p, PackedVector2Array([at.call(0.6, 0.6), at.call(0.92, 0.6), at.call(0.92, 0.88), at.call(0.6, 0.88)]), Color("85858c"), 0.1, -0.1)
	for t in [0.3, 0.42, 0.54]:
		p.line(at.call(0.45, t), at.call(0.92, t), grey)
	for t in [0.66, 0.78, 0.9]:
		p.line(at.call(0.08, t), at.call(0.52, t), grey)
	for t in [0.1, 0.18]:
		p.line(at.call(0.64, t), at.call(0.92, t), grey)


static func fish(p: Paint) -> void:
	lit_poly(p, [22.5, 15, 28.5, 9.5, 27.5, 15, 28.5, 21], Color("8a8f7c"), 0.2, -0.25)
	lit_poly(p, [15, 10.5, 17.5, 8.5, 19.5, 11], Color("8a8f7c"), 0.2, -0.2)
	lit_poly(p, [12, 19.5, 14, 21.5, 15.5, 19.5], Color("8a8f7c"), 0.2, -0.2)
	var body := mask(p)
	body.poly(pv([2.5, 15, 5.5, 11.5, 12, 10, 19, 10.5, 23.5, 13.5, 25, 15, 23.5, 16.5, 19, 19.5, 12, 20.5, 5.5, 18.5]), W)
	fill(p, body, Color("e6eaee"), 0.2, -0.28)
	fill(p, rows(body, 0, 14), Color("2f5fa8"), 0.22, -0.1)
	p.span(15, 5, 22, Color("8fb0d4"))
	for x in [9, 12, 15, 18, 21]:
		p.line(Vector2(x, 11), Vector2(x + 1.5, 13.5), Color("1c3a6e"))
	arc(p, 8, 15, 1.6, 3.6, -80, 80, Color("a9b4c0"))
	p.ellipse(5.5, 13.6, 1.3, 1.3, Color("f4e6b8"))
	p.px(5, 13, Color("1a1a22"))


static func meat_tray(p: Paint) -> void:
	var o := Vector2(16, 15.5)
	var u := Vector2(0.99, -0.139)
	var v := Vector2(0.139, 0.99)
	lit_poly(p, rrect(o, u, v, -12.6, 12.6, -8.2, 8.6, 2.0), Color("f2f2ee"), 0.15, -0.3)
	lit_poly(p, rrect(o, u, v, -10.6, 10.6, -6.2, 6.0, 1.2), Color("d6d9dd"), -0.15, 0.1)
	var meat := lit_poly(p, rrect(o, u, v, -9.6, 9.8, -5.4, 5.0, 1.6), Color("d8323a"), 0.22, -0.25)
	speckle(p, meat, 0.32, 0.16, 6)
	var fat := Color("f8c4c0")
	for l: Array in [[-7.0, -2.5, -3.0, -1.0], [-1.0, 1.5, 4.0, 0.0], [2.0, -3.6, 7.5, -2.0], [-6.0, 2.6, -2.5, 3.4]]:
		var line := PackedVector2Array()
		for k in 5:
			var s := k / 4.0
			line.append(o + u * lerpf(l[0], l[2], s) + v * (lerpf(l[1], l[3], s) + sin(s * PI) * 0.8))
		path(p, line, fat)


static func cabbage(p: Paint) -> void:
	p.ball(16, 15.8, 13.6, 12.8, Color("86c540"), 0.12)
	var vein := Color("dff2a8")
	path(p, pv([14, 27.5, 13, 21, 12, 15, 11, 9, 12.5, 5]), vein)
	path(p, pv([13, 20, 8, 16, 5, 15]), vein)
	path(p, pv([12, 14, 8, 10, 6, 9]), vein)
	path(p, pv([13.5, 23, 18, 20, 21, 19]), vein)
	var edge := Color("4f9228")
	arc(p, 9, 16, 18, 14, -62, 20, edge)
	arc(p, 23, 17, 16, 13, 160, 230, edge)
	arc(p, 16, 15.8, 13.6, 12.8, 20, 70, Color("aee070"))


static func apple(p: Paint) -> void:
	var m := mask(p)
	m.ellipse(15.5, 17.5, 12.6, 11.8, W)
	m.ellipse(10.5, 11, 7.5, 6.5, W)
	m.ellipse(20.5, 11, 7.5, 6.5, W)
	fill_ball(p, m, Color("dc2f22"), 0.05)
	speckle(p, m, 0.18, 0.06, 7)
	arc(p, 15.5, 4.4, 3.2, 2.4, 40, 140, Color("9e1d16"))
	p.line(Vector2(15.8, 6.5), Vector2(17.2, 3.0), Color("6b3d1f"), 1.6)
	p.rect(8, 11, 2, 1, Color("ffd9cf"))
	p.px(10, 13, Color("ffd9cf"))


static func egg_carton(p: Paint) -> void:
	var pulp := Color("d6ccb4")
	lit_poly(p, [7, 10.5, 29, 10.5, 30, 4.5, 9, 5.5], Paint.shade(pulp, -0.12), 0.15, -0.25)
	lit_poly(p, [9, 9.5, 28, 9.5, 28.8, 5.7, 10.2, 6.5], Paint.shade(pulp, 0.1), -0.12, 0.08)
	for x in [13.5, 19, 24.5]:
		p.ellipse(x, 8, 2.2, 1.1, Paint.shade(pulp, -0.06))
	lit_poly(p, [3, 20.5, 7, 11, 29, 11, 25, 20.5], Paint.shade(pulp, -0.3), 0.1, -0.2)
	for e: Array in [[10.5, 12.2], [17.5, 12.2], [24.2, 12.2], [7.2, 17.4], [14.2, 17.4], [21.2, 17.4]]:
		p.ellipse(e[0] + 0.2, e[1] + 0.3, 3.8, 3.5, Paint.shade(pulp, -0.6))
		p.ball(e[0], e[1], 3.1, 2.9, Color("e8e2d6"), 0.0)
	var front := lit_poly(p, [3, 20.5, 25, 20.5, 25, 25.5, 3, 25.5], pulp, 0.18, -0.25)
	lit_poly(p, [25, 20.5, 29, 11, 29, 19, 25, 25.5], Paint.shade(pulp, -0.2), 0.05, -0.15)
	for x in [3.5, 10.6, 17.6]:
		var cup := mask(p)
		cup.ellipse(x + 3.6, 25.7, 3.0, 1.5, W)
		erase(p, both(cup, front))
	for x in [10.5, 17.5]:
		p.line(Vector2(x, 21.5), Vector2(x, 23.5), Paint.shade(pulp, -0.22))


static func milk_carton(p: Paint) -> void:
	var white := Color("f6f8fb")
	var blue := Color("2378dc")
	lit_poly(p, [19, 10.5, 23, 8.5, 23, 27.5, 19, 29.5], Paint.shade(white, -0.2), 0.05, -0.15)
	lit_poly(p, [8, 10.5, 19, 10.5, 19, 29.5, 8, 29.5], white, 0.15, -0.2)
	var front := mask(p)
	front.poly(pv([8, 17, 11, 15.5, 15, 17.5, 19, 15.5, 19, 23, 15, 25, 11, 22.5, 8, 24]), W)
	fill(p, front, blue, 0.15, -0.2)
	lit_poly(p, [19, 15.5, 23, 13.5, 23, 20.5, 19, 23], Paint.shade(blue, -0.25), 0.0, -0.1)
	lit_poly(p, [8, 10.5, 19, 10.5, 21, 5, 10, 5], blue, 0.25, -0.15)
	lit_poly(p, [19, 10.5, 23, 8.5, 21, 5], Paint.shade(white, -0.08), 0.1, -0.15)
	lit_poly(p, [10, 3, 21, 3, 21, 5, 10, 5], Paint.shade(white, -0.04), 0.1, -0.15)


static func bread(p: Paint) -> void:
	var slice := mask(p)
	slice.rect(6, 16, 13, 13, W)
	slice.ellipse(12.5, 15.5, 7.4, 6.2, W)
	var loaf := mask(p)
	for k in range(5, -1, -1):
		loaf.img.blend_rect(slice.img, Rect2i(0, 0, 32, 32), Vector2i(k, -roundi(k * 0.8)))
	var film := mask(p)
	for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		film.img.blend_rect(loaf.img, Rect2i(0, 0, 32, 32), d)
	fill(p, film, Color("e4ecf4"), 0.15, -0.2)
	var crust := Color("d08a30")
	fill(p, loaf, Paint.shade(crust, -0.1), 0.26, -0.28)
	fill(p, slice, Color("e6a648"), 0.22, -0.25)
	var inner := mask(p)
	inner.rect(7, 17, 11, 11, W)
	inner.ellipse(12.5, 15.6, 6.3, 5.1, W)
	fill(p, both(inner, slice), Color("fbe8b4"), 0.1, -0.12)
	speckle(p, both(inner, slice), -0.1, 0.12, 9)
	p.line(Vector2(5, 17), Vector2(5, 27), Color(1, 1, 1))
	lit_poly(p, [13, 2.5, 21, 2.5, 18, 5.5, 16, 5.5], Color("e4ecf4"), 0.2, -0.25)
	p.line(Vector2(15, 3), Vector2(16.5, 5), Color("b8c4d2"))
	lit_rect(p, 15, 5, 4, 2, Color("e5482a"), 0.25, -0.2)


static func rice_sack(p: Paint) -> void:
	var cloth := Color("ece0c2")
	var sack := mask(p)
	sack.poly(pv([12, 6.5, 19, 6.5, 23, 11, 25.5, 21, 26.5, 29, 5, 29, 6, 21, 8, 11]), W)
	fill(p, sack, cloth, 0.2, -0.3)
	speckle(p, sack, -0.12, 0.22, 10)
	speckle(p, sack, 0.15, 0.1, 11)
	for f: Array in [[13, 8, 10, 20], [18, 8, 21, 18], [15.5, 8, 15, 14]]:
		p.line(Vector2(f[0], f[1]), Vector2(f[2], f[3]), Paint.shade(cloth, -0.2))
	lit_poly(p, [13, 4, 18, 4, 19.5, 7.5, 11.5, 7.5], Paint.shade(cloth, -0.06), 0.2, -0.2)
	p.ball(13, 3.6, 2.2, 1.6, cloth, 0.2)
	p.ball(18.5, 3.6, 2.2, 1.6, cloth, 0.2)
	p.span(6, 12, 19, Color("b39466"))


static func toilet_rolls(p: Paint) -> void:
	var paper := Color("f7f8fa")
	var hole := Color("a2a9b6")
	for c: Array in [[10.5, 6.5], [22.5, 6.5]]:
		var r := mask(p)
		r.rect(c[0] - 5, c[1], 12, 6, W)
		fill_barrel(p, r, Paint.shade(paper, -0.06))
		p.ellipse(c[0] + 1, c[1], 6, 2.6, Paint.shade(paper, 0.1))
		p.ellipse(c[0] + 1, c[1], 1.7, 0.9, hole)
	for col in [3, 15]:
		var r := mask(p)
		r.rect(col, 11, 12, 18, W)
		r.img.set_pixel(col, 28, CLEAR)
		r.img.set_pixel(col + 11, 28, CLEAR)
		fill_barrel(p, r, paper)
		p.span(19, col + 1, col + 10, Paint.shade(paper, -0.22))
		p.span(20, col, col + 11, Paint.shade(paper, -0.08))
		p.ellipse(col + 6, 11, 6, 2.6, Paint.shade(paper, 0.12))
		p.ellipse(col + 6, 11, 1.7, 0.9, hole)
	var film := Color("7fbcec")
	p.line(Vector2(27, 9), Vector2(27, 27), film)
	p.line(Vector2(28, 7), Vector2(28, 25), Paint.shade(film, -0.15))
	p.line(Vector2(15, 13), Vector2(15, 27), Color("cfe4f6"))
	p.line(Vector2(4, 27), Vector2(13, 27), Color("cfe4f4"))
	p.line(Vector2(16, 27), Vector2(25, 27), Color("cfe4f4"))


static func detergent(p: Paint) -> void:
	var body := mask(p)
	body.poly(rrect(Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, 6, 25.5, 9, 29.5, 4.0), W)
	body.poly(pv([8, 10, 12, 6.5, 17, 6.5, 24, 10]), W)
	fill_ball(p, body, Color("f2f5f8"), 0.35)
	var hole := mask(p)
	hole.ellipse(21.5, 15.5, 1.8, 4.2, W)
	erase(p, hole)
	lit_ellipse(p, 12.5, 21.5, 5.6, 6.2, Color("3a8de6"), 0.25, -0.2)
	p.ellipse(11, 19, 1.6, 1.8, Color("bfe0ff"))
	p.barrel(11, 2, 17, 6, Color("2a74d8"))
	for x in [12, 14, 16]:
		p.line(Vector2(x, 3), Vector2(x, 5), Color("1c56a8"))
	p.span(2, 12, 16, Color("6aa8f0"))


static func sake(p: Paint) -> void:
	var glass := Color("2f7f36")
	var b := mask(p)
	b.rect(14, 4, 4, 8, W)
	b.poly(pv([14, 11, 18, 11, 20, 15, 20, 29.5, 12, 29.5, 12, 15]), W)
	b.img.set_pixel(12, 29, CLEAR)
	b.img.set_pixel(19, 29, CLEAR)
	fill_barrel(p, b, glass)
	fill_barrel(p, rows(b, 18, 26), Color("efe6c4"))
	p.span(19, 12, 19, Color("c8372c"))
	p.barrel(14, 2, 17, 4, Color("2a2a30"))


static func bouquet(p: Paint) -> void:
	var paper := Color("f7c4cf")
	lit_poly(p, [7.5, 12, 13.5, 3.5, 27.5, 14, 25, 20], Paint.shade(paper, -0.14), 0.12, -0.2)
	for l: Array in [[13, 12, 5.5, 7.5], [22, 12, 28.5, 10], [18, 8, 22.5, 2.5], [10, 9, 7.5, 3.5], [21, 17, 27, 19.5]]:
		leaf(p, Vector2(l[0], l[1]), Vector2(l[2], l[3]), 2.0, Color("3f9a3a"))
	for f: Array in [[11.5, 8.5, 4.6, "f48fb0", "f7d24a"], [18, 6.5, 4.6, "e3302c", "f7d24a"], [23.5, 11.5, 4.2, "f8f8f2", "f2b42a"],
			[16.5, 13, 4.6, "f8c630", "e2781c"], [22, 17, 3.8, "e3302c", "f7d24a"]]:
		blossom(p, f[0], f[1], f[2], Color(f[3]), Color(f[4]))
	lit_poly(p, [8.5, 28.5, 3.5, 15, 9, 13, 22.5, 19.5, 21, 22], paper, 0.22, -0.28)
	p.line(Vector2(5.5, 16), Vector2(8.5, 26), Paint.shade(paper, 0.35))
	p.line(Vector2(9.5, 14.5), Vector2(20.5, 20.5), Paint.shade(paper, -0.2))
	var ribbon := Color("e2302c")
	lit_ellipse(p, 7, 22.5, 2.8, 2.0, ribbon, 0.25, -0.25)
	lit_ellipse(p, 13.2, 23, 2.8, 2.0, ribbon, 0.25, -0.25)
	lit_poly(p, [9, 23.5, 6, 28.5, 8, 28.5, 10.5, 25, 12, 28.5, 14, 28, 11, 23.5], Paint.shade(ribbon, -0.08), 0.2, -0.2)
	p.ball(10.2, 23, 1.7, 1.7, ribbon)


static func oden(p: Paint) -> void:
	var steel := Color("b9bec6")
	lit_rect(p, 2, 9, 2, 5, Paint.shade(steel, -0.1), 0.2, -0.2)
	lit_rect(p, 27, 9, 2, 5, Paint.shade(steel, -0.15), 0.2, -0.2)
	lit_rect(p, 3, 4, 25, 26, steel, 0.3, -0.3)
	lit_rect(p, 4, 22, 23, 7, Paint.shade(steel, -0.14), 0.05, -0.15)
	p.line(Vector2(6, 25), Vector2(13, 25), Paint.shade(steel, 0.35))
	var broth := Color("b06c26")
	lit_rect(p, 5, 6, 21, 16, broth, -0.3, 0.14)
	var dark := Paint.shade(broth, -0.5)
	p.ellipse(11, 11.7, 5.3, 4.5, dark)
	lit_ellipse(p, 10.5, 11, 4.9, 4.1, Color("f3e6c2"), 0.15, -0.25)
	p.line(Vector2(8, 11), Vector2(13, 11), Color("dfca9a"))
	p.line(Vector2(10.5, 8.5), Vector2(10.5, 13.5), Color("dfca9a"))
	p.ellipse(20.4, 11.6, 4.4, 4.0, dark)
	p.ball(19.9, 11, 4.0, 3.6, Color("c4844a"), 0.1)
	p.poly(pv([5.5, 21.5, 7.5, 15, 15, 21.5]), dark)
	var konnyaku := lit_poly(p, [5.5, 21, 7.5, 14.5, 14.5, 21], Color("8f8f96"), 0.2, -0.2)
	speckle(p, konnyaku, -0.32, 0.25, 13)
	p.ellipse(21, 18.9, 5.0, 3.1, dark)
	p.ball(20.5, 18.3, 4.6, 2.7, Color("ecc68c"), 0.1)
	p.line(Vector2(18, 17), Vector2(18, 20), Color("a8662a"))
	p.line(Vector2(22.5, 17), Vector2(22.5, 20), Color("a8662a"))
	p.ellipse(16.7, 18.5, 0.9, 1.4, Color("6a4020"))


# ---------- perks: 40 px a cell ----------

static func staff(p: Paint) -> void:
	var hair := Color("6e3b1e")
	var skin := Color("fcd5b2")
	var red := Color("dc3229")
	lit_ellipse(p, 32, 27, 3.4, 5.5, hair, 0.2, -0.25)
	lit_ellipse(p, 20, 21, 13, 12.5, hair, 0.2, -0.3)
	lit_poly(p, [7, 38, 9, 32.5, 15, 30, 25, 30, 31, 32.5, 33, 38], red, 0.22, -0.25)
	lit_poly(p, [15.5, 30, 20, 35, 24.5, 30], Color("f6f2ea"), 0.1, -0.2)
	p.line(Vector2(12.5, 32), Vector2(11.5, 37), Color("f6f2ea"))
	p.line(Vector2(27.5, 32), Vector2(28.5, 37), Color("f6f2ea"))
	lit_rect(p, 17, 27, 6, 4, Paint.shade(skin, -0.15), 0.0, -0.1)
	lit_ellipse(p, 10.5, 22.5, 1.8, 2.4, skin, 0.1, -0.2)
	lit_ellipse(p, 29.5, 22.5, 1.8, 2.4, skin, 0.1, -0.2)
	lit_ellipse(p, 20, 21.5, 9.6, 9.2, skin, 0.15, -0.2)
	lit_poly(p, [9.5, 19, 11, 13, 29, 13, 30.5, 19, 27.5, 16, 24.5, 18.5, 21.5, 15.5, 18, 18.5, 14.5, 15.5, 11.5, 19.5], hair, 0.2, -0.25)
	var crown := mask(p)
	crown.ellipse(20, 13, 12, 10, W)
	var cap := rows(crown, 0, 13)
	fill(p, cap, red, 0.2, -0.25)
	var panel := mask(p)
	panel.ellipse(18.5, 9.5, 6.5, 6, W)
	fill(p, both(panel, rows(cap, 0, 12)), Color("f8f4ec"), 0.15, -0.15)
	lit_poly(p, [3.5, 16, 7, 12.5, 23, 12.5, 26, 14, 21, 17, 6, 17.5], Paint.shade(red, -0.08), 0.25, -0.3)
	p.ellipse(20, 3.5, 1.2, 0.8, Paint.shade(red, 0.2))
	for x in [13, 24]:
		p.rect(x, 20, 3, 4, Color("3b2416"))
		p.span(23, x, x + 2, Color("7a4a2a"))
		p.px(x, 20, Color(1, 1, 1))
		p.line(Vector2(x - 1, 18), Vector2(x + 3, 18), hair)
	p.rect(11, 25, 2, 1, Color("f4a3a0"))
	p.rect(27, 25, 2, 1, Color("f4a3a0"))
	p.px(20, 24, Paint.shade(skin, -0.2))
	p.span(26, 18, 21, Color("a8282a"))
	p.span(27, 18, 21, Color("e05a5a"))
	p.span(28, 19, 20, Color("e05a5a"))


static func flyer(p: Paint) -> void:
	var paper := Color("f6f0e0")
	lit_poly(p, [10, 3.5, 32, 2.5, 32.5, 34.5, 11, 36], paper, 0.15, -0.25)
	p.ball(22, 12, 4.8, 4.8, Color("f7c02c"), 0.1)
	lit_poly(p, [13, 26, 19, 16.5, 25, 26], Color("5a7aa8"), 0.2, -0.15)
	lit_poly(p, [20, 25, 25.5, 18, 31, 25], Color("6a8cba"), 0.2, -0.15)
	lit_poly(p, [12.5, 31, 31, 26.5, 31, 31, 12.5, 33], Color("f08a3e"), 0.2, -0.15)
	lit_ellipse(p, 10.5, 33.5, 3.4, 3.4, Color("8ea8c8"), 0.25, -0.25)
	arc(p, 10.5, 33.5, 1.6, 1.6, 0, 300, Color("4a6a90"))
	lit_ellipse(p, 10.2, 4.6, 2.2, 2.0, Color("6a92c4"), 0.25, -0.2)


static func fridge(p: Paint) -> void:
	var body := Color("40454e")
	box3(p, 8, 4.5, 22, 30, 2, 2, body)
	p.rect(10, 35, 3, 2, Color("26282e"))
	p.rect(25, 35, 3, 2, Color("26282e"))
	var shelves := [[8, 12, ["d8402e", "f08a2a", "d8402e"], ["e8a23a", "d8402e", "f08a2a"]], [15, 20, ["6a5040", "4a5a48", "6a5040"], ["4a5a48", "6a5040", "4a5a48"]],
		[23, 30, ["2f7fe0", "4aa0f0", "2f7fe0"], ["f0a030", "e88a1a", "f0a030"]]]
	for door in 2:
		var x0 := 10 + door * 10
		lit_rect(p, x0, 6, 9, 27, Color("bfe4f2"), 0.15, -0.2)
		for r: Array in shelves:
			var cols: Array = r[2 + door]
			for k in 3:
				var bx := x0 + 1 + k * 3
				p.barrel(bx, r[0], bx + 1, r[1], Color(cols[k]))
				p.px(bx, r[0] - 1, Color(cols[k]).lightened(0.3))
			p.span(r[1] + 1, x0, x0 + 8, Color("8aa8b8"))
		p.line(Vector2(x0 + 1, 31), Vector2(x0 + 6, 7), Color(1, 1, 1, 0.45))
	p.line(Vector2(18.5, 15), Vector2(18.5, 22), Color("cfd4da"))
	p.line(Vector2(21.5, 15), Vector2(21.5, 22), Color("cfd4da"))


static func espresso(p: Paint) -> void:
	var metal := Color("50545d")
	lit_poly(p, [35.5, 15, 22, 15, 22, 18, 35.5, 18.5], Color("2a2a2f"), 0.2, -0.2)
	lit_rect(p, 13, 15, 18, 16, Paint.shade(metal, -0.3), -0.1, 0.1)
	box3(p, 5, 30.5, 27, 5, 3, 2, Paint.shade(metal, 0.08))
	for x in range(9, 31, 3):
		p.line(Vector2(x, 29), Vector2(x + 2, 29), Paint.shade(metal, -0.3))
	lit_rect(p, 5, 15, 9, 16, metal, 0.18, -0.25)
	box3(p, 5, 5.5, 27, 10, 3, 3, metal)
	for b: Array in [[9, "e03a30"], [15, "8a8e96"], [21, "f0a028"]]:
		lit_rect(p, b[0], 8, 3, 4, Color(b[1]), 0.25, -0.2)
	lit_rect(p, 18, 15, 6, 3, Paint.shade(metal, -0.2), 0.15, -0.2)
	var cup := mask(p)
	cup.poly(pv([15, 23, 26, 23, 25, 30.5, 16, 30.5]), W)
	fill_barrel(p, cup, Color("f6f3ee"))
	arc(p, 26.5, 26, 2.2, 2.2, -80, 90, Color("f0ece6"), 1.4)
	p.ellipse(20.5, 23.3, 5.2, 1.3, Color("6b3a1e"))
	var steam := Color("c4c8d0")
	for x0 in [17, 22]:
		for s: Array in [[1, 21], [0, 20], [0, 19], [1, 18], [1, 17], [0, 16]]:
			p.px(x0 + s[0], s[1], steam)


static func point_card(p: Paint) -> void:
	var o := Vector2(20, 19.5)
	var u := Vector2(0.978, -0.208)
	var v := Vector2(0.208, 0.978)
	var card := lit_poly(p, rrect(o, u, v, -16, 16, -10, 10, 2.2), Color("f3f5f9"), 0.15, -0.25)
	var stripe := mask(p)
	stripe.poly(PackedVector2Array([o + u * -17 + v * 4, o + u * 17 + v * -2, o + u * 17 + v * 11, o + u * -17 + v * 11]), W)
	var sheen := mask(p)
	sheen.poly(PackedVector2Array([o + u * 3 + v * -11, o + u * 8 + v * -11, o + u * 1 + v * 11, o + u * -4 + v * 11]), W)
	fill(p, both(sheen, card), Color("d4e8f8"), 0.1, -0.1)
	fill(p, both(stripe, card), Color("2f6ddc"), 0.25, -0.25)
	lit_poly(p, star(o.x - 8, o.y - 1.5, 6.6), Color("f8b820"), 0.25, -0.25)


static func fry_basket(p: Paint) -> void:
	var wire := Color("d4d8de")
	p.line(Vector2(27, 15), Vector2(31, 9.5), wire)
	p.line(Vector2(29, 15.5), Vector2(32.5, 10), wire)
	p.line(Vector2(31, 9.5), Vector2(37, 5.5), Color("2a2a30"), 2.6)
	p.line(Vector2(7, 14.5), Vector2(31, 12.5), Paint.shade(wire, -0.2))
	for k: Array in [[12.5, 13.5, 5.2, 4.0], [26, 14.5, 4.6, 3.6], [19.5, 11.5, 5.6, 4.2]]:
		p.ellipse(k[0] + 0.4, k[1] + 0.6, k[2] + 0.7, k[3] + 0.7, Color("6a3412"))
		var m := lit_ellipse(p, k[0], k[1], k[2], k[3], Color("cc7e2e"), 0.28, -0.25)
		speckle(p, m, 0.22, 0.18, 14)
		speckle(p, m, -0.22, 0.12, 15)
	var face := lit_poly(p, [5, 17.5, 33, 15.5, 29.5, 32.5, 8.5, 33.5], Color("8a4a1c"), 0.1, -0.1)
	var grid := mask(p)
	for x in range(6, 34, 3):
		grid.line(Vector2(x, 15), Vector2(x - (x - 19) * 0.12, 34), W)
	for y in range(19, 34, 3):
		grid.span(y, 0, 39, W)
	fill(p, both(grid, face), wire, 0.0, -0.15)
	p.line(Vector2(4, 17), Vector2(34, 15), wire, 2.0)


static func cctv(p: Paint) -> void:
	var white := Color("efede6")
	var grey := Color("c4c6cc")
	lit_poly(p, rrect(Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, 30, 36.5, 17, 34.5, 1.5), Color("d8d9de"), 0.2, -0.25)
	p.px(33, 20, Paint.shade(grey, -0.3))
	p.px(33, 31, Paint.shade(grey, -0.3))
	lit_poly(p, [19, 21, 31, 23, 31, 26.5, 19, 25], grey, 0.2, -0.25)
	p.ball(19.5, 22.5, 3, 3, grey)
	var o := Vector2(20, 13.5)
	var u := Vector2(0.94, -0.342)
	var v := Vector2(0.342, 0.94)
	lit_poly(p, rrect(o, u, v, -11, 14, -4, 5, 2.0), white, 0.18, -0.28)
	lit_poly(p, rrect(o, u, v, -10, 13.5, 2.2, 5, 1.2), Paint.shade(white, -0.18), 0.05, -0.2)
	lit_poly(p, rrect(o, u, v, -13.5, 14.5, -6, -2.4, 1.2), Paint.shade(white, 0.12), 0.2, -0.25)
	lit_poly(p, rrect(o, u, v, -16.5, -7.5, -3.2, 5.6, 2.0), Color("3a3d46"), 0.2, -0.2)
	var lens := o + u * -12.5 + v * 1.2
	p.ball(lens.x, lens.y, 2.3, 2.3, Color("2c7ae2"))
	p.px(floori(lens.x), floori(lens.y), Color("123a7a"))
	p.px(floori(lens.x) - 1, floori(lens.y) - 1, Color("cfe8ff"))


static func truck(p: Paint) -> void:
	var blue := Color("2264d8")
	box3(p, 3, 9.5, 20, 15, 3, 2, Color("efefec"))
	lit_rect(p, 3, 20, 20, 4, blue, 0.2, -0.2)
	p.rect(5, 25, 29, 3, Color("2e3038"))
	lit_poly(p, [23, 12, 31.5, 12, 36.5, 18.5, 36.5, 27, 23, 27], blue, 0.25, -0.28)
	lit_poly(p, [24.5, 13.5, 29.5, 13.5, 30.5, 19, 24.5, 19], Color("2a3a5a"), 0.15, -0.1)
	lit_poly(p, [31, 13.5, 35.5, 19, 31.5, 19, 30.5, 13.5], Color("a8daf2"), 0.2, -0.15)
	p.line(Vector2(25.5, 18), Vector2(28.5, 14.5), Color("6a8ab8"))
	p.line(Vector2(30.5, 20), Vector2(30.5, 26), Paint.shade(blue, -0.3))
	lit_rect(p, 34, 21, 3, 2, Color("ffd04a"), 0.2, -0.1)
	lit_rect(p, 29, 25, 8, 2, Color("b8bcc4"), 0.2, -0.2)
	for x in [9.5, 29.0]:
		p.ball(x, 27.5, 3.6, 3.6, Color("2a2b31"))
		p.ball(x, 27.5, 1.6, 1.6, Color("aab0ba"))


static func neon_frame(p: Paint) -> void:
	lit_rect(p, 10, 8, 2, 3, Color("2a3a8a"), 0.2, -0.2)
	lit_rect(p, 28, 8, 2, 3, Color("2a3a8a"), 0.2, -0.2)
	var outer := lit_poly(p, rrect(Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, 2, 38, 10, 31, 5), Color("1c2a80"), 0.2, -0.25)
	var tube := mask(p)
	tube.poly(rrect(Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, 3.5, 36.5, 11.5, 29.5, 4.2), W)
	var hole := mask(p)
	hole.poly(rrect(Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, 6, 34, 14, 27, 2.6), W)
	erase(tube, hole)
	fill(p, both(tube, outer), Color("3a8cff"), 0.3, -0.1)
	var core := mask(p)
	core.poly(rrect(Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, 4.5, 35.5, 12.5, 28.5, 3.4), W)
	var inside := mask(p)
	inside.poly(rrect(Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, 5.5, 34.5, 13.5, 27.5, 2.8), W)
	erase(core, inside)
	fill(p, core, Color("aef6ff"), 0.3, 0.0)
	erase(p, hole)


static func maneki(p: Paint) -> void:
	var fur := Color("fbf6ec")
	var spot := Color("f0a03a")
	var pink := Color("e8606a")
	var arm := lit_poly(p, [26, 25, 26.5, 11, 27.5, 7.5, 30, 5.8, 32.5, 7.5, 33.5, 11, 33, 22, 30.5, 25], fur, 0.15, -0.25)
	var mark := mask(p)
	mark.ellipse(32, 16, 2.4, 3, W)
	fill(p, both(mark, arm), spot, 0.2, -0.2)
	for x in [28.5, 30.5, 32.5]:
		p.line(Vector2(x, 6.8), Vector2(x, 8), pink)
	lit_ellipse(p, 19, 29, 11, 8.6, fur, 0.15, -0.28)
	lit_ellipse(p, 27, 31, 2.2, 2.6, spot, 0.2, -0.2)
	lit_ellipse(p, 12.5, 36, 3, 1.8, fur, 0.15, -0.25)
	lit_ellipse(p, 24.5, 36, 3, 1.8, fur, 0.15, -0.25)
	lit_poly(p, [8.5, 11, 10, 2.5, 16.5, 7.5], fur, 0.15, -0.25)
	lit_poly(p, [21, 7.5, 27, 2.5, 28.5, 11], fur, 0.15, -0.25)
	var head := lit_ellipse(p, 18.5, 14.5, 11, 9.4, fur, 0.15, -0.25)
	var patch := mask(p)
	patch.ellipse(12, 8, 4.5, 3.6, W)
	fill(p, both(patch, head), spot, 0.2, -0.15)
	lit_poly(p, [9, 11, 10, 2.5, 16.5, 7.5, 12, 9], spot, 0.2, -0.2)
	lit_poly(p, [11, 8, 11.5, 5, 14.5, 7.5], pink, 0.1, -0.1)
	lit_poly(p, [23, 7.5, 26.5, 5, 26.8, 8.5], pink, 0.1, -0.1)
	var ink := Color("3a2a26")
	for x in [12, 22]:
		p.px(x, 15, ink)
		p.px(x + 1, 14, ink)
		p.px(x + 2, 14, ink)
		p.px(x + 3, 15, ink)
	p.px(19, 17, pink)
	p.px(18, 18, ink)
	p.px(19, 19, ink)
	p.px(20, 18, ink)
	for w: Array in [[9.5, 17, 6, 16.5], [9.5, 19, 6, 19.5], [27.5, 17, 25.5, 16.8], [27.5, 19, 25.5, 19.2]]:
		p.line(Vector2(w[0], w[1]), Vector2(w[2], w[3]), Color("b8b0a6"))
	lit_poly(p, [10, 22, 28, 22, 27, 24.5, 11, 24.5], Color("d8302a"), 0.2, -0.2)
	p.ball(19, 25.5, 2.4, 2.4, Color("f4c02a"))
	p.ellipse(13.9, 31, 4.6, 6.4, Color("a8641a"))
	lit_ellipse(p, 13.5, 30.5, 4, 5.8, Color("f2b52a"), 0.3, -0.25)
	for y in [28, 30, 32]:
		p.line(Vector2(12, y), Vector2(15, y), Color("c8861a"))
	lit_ellipse(p, 16.5, 27, 2.6, 2.0, fur, 0.15, -0.2)


static func register(p: Paint) -> void:
	var cream := Color("ebe5d5")
	box3(p, 13, 4.5, 15, 7, 1.5, 1.5, cream)
	lit_rect(p, 15, 6, 11, 4, Color("39414a"), -0.1, 0.1)
	lit_rect(p, 19, 11, 4, 3, Paint.shade(cream, -0.15), 0.1, -0.2)
	lit_poly(p, [6, 14, 34, 14, 37, 23, 3, 23], cream, 0.22, -0.2)
	for r in 2:
		for c in 5:
			lit_rect(p, 8 + c * 3, 16 + r * 3, 2, 2, Color("a6a8ae"), 0.25, -0.2)
	for k: Array in [[25, 16, "e0402e"], [28, 16, "2f78d8"], [25, 19, "2f78d8"], [28, 19, "f0a028"]]:
		lit_rect(p, k[0], k[1], 2, 2, Color(k[2]), 0.25, -0.2)
	lit_rect(p, 3, 23, 34, 11, Paint.shade(cream, -0.08), 0.2, -0.28)
	p.span(26, 4, 35, Paint.shade(cream, -0.25))
	p.ball(20, 30, 1.6, 1.6, Color("6a6e76"))
	p.rect(5, 34, 4, 2, Color("3a3a40"))
	p.rect(31, 34, 4, 2, Color("3a3a40"))


## A stack of n coins over (cx, foot), rx wide, banded as one cylinder with each coin's edge and the top face lit.
static func coin_stack(p: Paint, cx: float, foot: float, n: int, rx: float) -> void:
	var gold := Color("f8b92a")
	var m := mask(p)
	var top := foot - n * 2.6
	m.rect(roundi(cx - rx), roundi(top), roundi(rx * 2), roundi(foot - top), W)
	m.ellipse(cx, foot, rx, 2.2, W)
	fill_barrel(p, m, gold)
	for k in n:
		arc(p, cx, foot - k * 2.6, rx - 0.5, 2.0, 15, 165, Paint.shade(gold, -0.35))
	lit_ellipse(p, cx, top, rx, 2.4, Paint.shade(gold, 0.2), 0.3, -0.15)
	p.span(roundi(top) - 1, roundi(cx - rx * 0.5), roundi(cx), Color("fff2b8"))


static func coins(p: Paint) -> void:
	coin_stack(p, 24, 22, 6, 6.6)
	coin_stack(p, 10, 30.5, 6, 6.6)
	coin_stack(p, 30.5, 30.5, 5, 6.0)
	coin_stack(p, 20, 33, 3, 6.6)


static func cherry_tree(p: Paint) -> void:
	var bark := Color("7a4a2c")
	var pink := Color("f4a3be")
	for b: Array in [[20, 26, 11, 17], [20, 25, 29, 16], [20, 24, 20, 12]]:
		p.line(Vector2(b[0], b[1]), Vector2(b[2], b[3]), bark, 1.6)
	for c: Array in [[20, 8.5, 8, 6], [11, 13, 7, 6], [28.5, 13, 7, 6], [20, 15, 8, 6.5], [8, 21, 6, 5], [31.5, 21, 5.8, 5], [15, 23, 7, 5], [25.5, 23, 7, 5]]:
		p.ellipse(c[0] + 0.4, c[1] + 0.6, c[2] + 0.6, c[3] + 0.6, Paint.shade(pink, -0.45))
		var m := mask(p)
		m.ellipse(c[0], c[1], c[2], c[3], W)
		fill_ball(p, m, pink, 0.2)
		speckle(p, m, 0.35, 0.12, 16)
		speckle(p, m, -0.15, 0.1, 17)
	lit_poly(p, [17.5, 38, 18.5, 30, 17.5, 26, 20, 24, 22.5, 26, 21.5, 30, 22.5, 38], bark, 0.2, -0.25)
	lit_poly(p, [14, 38.5, 26, 38.5, 23, 35, 17, 35], Paint.shade(bark, -0.08), 0.15, -0.25)
	p.line(Vector2(17, 27), Vector2(13, 25), bark, 1.4)
	p.line(Vector2(22.5, 27), Vector2(27, 25), bark, 1.4)


# ---------- decor: 48 px a cell ----------

static func potted_plant(p: Paint) -> void:
	var greens := [Color("3e9a3a"), Color("348c36"), Color("4aa842")]
	var leaves := [[24, 30, 17, 6, 4.4], [24, 30, 30.5, 5.5, 4.4], [24, 31, 10, 13, 4.8], [24, 31, 38, 13.5, 4.8],
		[24, 33, 9, 25, 4.4], [24, 33, 39, 25.5, 4.4], [24, 31, 22.5, 9, 4.0], [24, 32, 15.5, 19, 4.2], [24, 32, 32.5, 19.5, 4.2]]
	for i in leaves.size():
		var l: Array = leaves[i]
		leaf(p, Vector2(l[0], l[1]), Vector2(l[2], l[3]), l[4], greens[i % 3], true)
	var pot := mask(p)
	pot.poly(pv([16, 34, 32, 34, 30.5, 46, 17.5, 46]), W)
	fill_barrel(p, pot, Color("efede8"))
	p.span(38, 17, 31, Color("cfccc4"))
	lit_ellipse(p, 24, 34, 8.6, 2.4, Color("f8f6f2"), 0.15, -0.2)
	lit_ellipse(p, 24, 34, 6.8, 1.4, Color("6b4423"), -0.2, 0.1)


static func bench(p: Paint) -> void:
	var wood := Color("c98242")
	lit_rect(p, 38, 27, 3, 12, Paint.shade(wood, -0.25), 0.1, -0.2)
	lit_rect(p, 16, 27, 2, 8, Paint.shade(wood, -0.3), 0.1, -0.2)
	lit_poly(p, [32, 39, 39, 34.5, 39, 36.5, 32, 41], Paint.shade(wood, -0.25), 0.1, -0.2)
	lit_poly(p, [33, 30, 42, 24, 42, 27, 33, 33], Paint.shade(wood, -0.28), 0.1, -0.2)
	lit_poly(p, [5, 30, 33, 30, 42, 24, 14, 24], Paint.shade(wood, 0.1), 0.2, -0.15)
	for k in [1, 2]:
		var y: int = 30 - k * 2
		p.line(Vector2(5 + k * 3, y), Vector2(33 + k * 3, y), Paint.shade(wood, -0.3))
	for g: Array in [[10, 29, 15, 29], [20, 27, 25, 27], [28, 25, 33, 25], [17, 29, 21, 29]]:
		p.line(Vector2(g[0], g[1]), Vector2(g[2], g[3]), Paint.shade(wood, -0.08))
	lit_rect(p, 5, 30, 28, 3, wood, 0.15, -0.25)
	lit_rect(p, 7, 33, 3, 12, Paint.shade(wood, -0.05), 0.2, -0.25)
	lit_rect(p, 29, 33, 3, 12, Paint.shade(wood, -0.1), 0.2, -0.25)
	lit_rect(p, 10, 39, 19, 2, Paint.shade(wood, -0.2), 0.1, -0.2)


static func vending(p: Paint) -> void:
	var red := Color("d92b26")
	box3(p, 10, 7, 21, 37, 6, 4, red)
	p.rect(11, 44, 3, 2, Color("26272c"))
	p.rect(27, 44, 3, 2, Color("26272c"))
	lit_rect(p, 12, 9, 14, 20, Color("e6f0f6"), -0.1, 0.1)
	var shelves := [["3a7ee0", "f4f4f0", "f0902a", "f2c83a"], ["e0402e", "f2c83a", "4cae4a", "3a7ee0"], ["e0402e", "f39ab8", "f0902a", "f4f4f0"]]
	for r in 3:
		var y0 := 10 + r * 6
		for k in 4:
			var c := Color(shelves[r][k])
			p.barrel(13 + k * 3, y0 + 1, 14 + k * 3, y0 + 4, c)
			p.px(13 + k * 3, y0, c.lightened(0.35))
		p.span(y0 + 5, 12, 25, Color("9aa8b4"))
		for k in 4:
			p.px(13 + k * 3, y0 + 5, Color("3a7ee0") if (r + k) % 2 == 0 else Color("f4f4f0"))
	lit_rect(p, 27, 11, 3, 16, Paint.shade(red, -0.2), 0.1, -0.15)
	p.rect(28, 13, 1, 3, Color("2a2a30"))
	for y in [18, 21]:
		lit_rect(p, 27, y, 3, 2, Color("f0f0ec"), 0.1, -0.2)
	lit_rect(p, 12, 32, 14, 6, Color("2a2b31"), 0.12, -0.1)
	p.span(33, 13, 24, Color("4a4c54"))
	p.rect(27, 33, 2, 3, Color("2a2b31"))


static func gacha(p: Paint) -> void:
	var steel := Color("cdd1d8")
	lit_rect(p, 40, 33, 2, 10, Paint.shade(steel, -0.25), 0.1, -0.2)
	for m: Array in [[6, "e2342c", 0], [18, "2f74dc", 1], [30, "f2b628", 2]]:
		var x0: int = m[0]
		var c := Color(m[1])
		box3(p, x0, 10, 10, 24, 2, 2, c)
		lit_ellipse(p, x0 + 5, 18, 4.8, 5.4, Color("dceef8"), 0.25, -0.3)
		var palette := ["f2d23a", "e04a8a", "4cae4a", "3a8ee6", "f08a2a", "e2342c", "a06ad0"]
		var spots := [[2.4, 21.2], [5.0, 21.8], [7.6, 21.0], [3.6, 19.0], [6.4, 18.8], [8.2, 18.2], [2.4, 18.0]]
		for k in spots.size():
			var s: Array = spots[k]
			p.ball(x0 + s[0], s[1], 1.4, 1.4, Color(palette[(k + 2 * m[2]) % palette.size()]))
		p.line(Vector2(x0 + 2, 15), Vector2(x0 + 3, 14), Color(1, 1, 1))
		p.ball(x0 + 5, 27, 2.3, 2.3, steel)
		p.line(Vector2(x0 + 4, 27), Vector2(x0 + 6, 27), Paint.shade(steel, -0.4))
		p.rect(x0 + 3, 30, 4, 2, Color("2a2b31"))
	lit_poly(p, [5, 34, 41, 34, 43, 32, 7, 32], Paint.shade(steel, 0.1), 0.2, -0.1)
	lit_rect(p, 5, 34, 36, 2, steel, 0.2, -0.25)
	lit_rect(p, 6, 36, 2, 8, Paint.shade(steel, -0.08), 0.2, -0.25)
	lit_rect(p, 37, 36, 2, 8, Paint.shade(steel, -0.12), 0.2, -0.25)
	p.line(Vector2(8, 41), Vector2(37, 41), Paint.shade(steel, -0.2))
	for x in [7.0, 38.0]:
		p.ball(x, 44.5, 1.6, 1.4, Color("2a2b31"))
	p.ball(41, 42.5, 1.4, 1.2, Color("2a2b31"))



static func bonsai(p: Paint) -> void:
	var bark := Color("6e4126")
	var pink := Color("f5a8c2")
	for b: Array in [[22, 24, 11, 19], [24, 21, 35, 17], [23, 20, 24, 10], [22, 25, 14, 27], [26, 24, 33, 26]]:
		p.line(Vector2(b[0], b[1]), Vector2(b[2], b[3]), bark, 1.6)
	for f: Array in [[12, 18, 4.8], [18, 12, 4.8], [25, 8, 4.8], [32, 11, 4.8], [37, 18, 4.6], [16, 21, 4.4], [28, 18, 4.8],
			[21, 16, 4.4], [9, 25, 4.2], [34, 24.5, 4.2], [24, 23, 4.0]]:
		blossom(p, f[0], f[1], f[2], pink, Color("e05a8a"))
	lit_poly(p, [21, 38, 22, 32, 19.5, 27, 21.5, 22, 24, 20, 25.5, 23, 23.5, 27.5, 26.5, 32, 27.5, 38], bark, 0.2, -0.25)
	var pot := mask(p)
	pot.poly(pv([13, 37, 35, 37, 32, 46, 16, 46]), W)
	fill_barrel(p, pot, Color("efede8"))
	lit_ellipse(p, 24, 37, 11, 2.6, Color("f8f6f2"), 0.15, -0.2)
	lit_ellipse(p, 24, 37, 9, 1.5, Color("6b4423"), -0.2, 0.1)


static func chalkboard(p: Paint) -> void:
	var wood := Color("b8722e")
	var slate := Color("2e3842")
	lit_poly(p, [29, 10, 32, 10, 38.5, 45.5, 35.5, 45.5], Paint.shade(wood, -0.3), 0.1, -0.2)
	p.poly(pv([29.5, 12, 31.5, 12, 36, 41, 33.5, 41]), Paint.shade(slate, -0.2))
	var frame := lit_poly(p, [13, 9, 30, 9, 34.5, 45.5, 8.5, 45.5], wood, 0.25, -0.28)
	lit_poly(p, [15.5, 12, 27.5, 12, 30.5, 40, 12.5, 40], slate, -0.15, 0.1)
	var gap := mask(p)
	gap.poly(pv([12.5, 42.5, 30.5, 42.5, 31.5, 46, 11.5, 46]), W)
	erase(p, both(gap, frame))
	var chalk := Color("c8ccd0")
	p.line(Vector2(16.5, 17), Vector2(25.5, 17), chalk)
	p.line(Vector2(16, 22), Vector2(23, 22), chalk)
	p.line(Vector2(15, 27), Vector2(26, 27), Color("e8a0b0"))
	p.line(Vector2(14.5, 32), Vector2(21, 32), chalk)


static func atm(p: Paint) -> void:
	var grey := Color("b8bcc4")
	box3(p, 11, 6, 20, 38, 5, 4, grey)
	p.rect(11, 43, 21, 2, Color("3a3d45"))
	lit_rect(p, 14, 7, 14, 3, Color("2f7fd8"), 0.25, -0.2)
	lit_rect(p, 13, 12, 16, 11, Color("50545c"), -0.1, 0.15)
	lit_rect(p, 15, 13, 12, 8, Color("3a8ef0"), 0.3, -0.15)
	lit_poly(p, [12, 24, 30, 24, 31, 28.5, 11, 28.5], Paint.shade(grey, 0.15), 0.2, -0.25)
	for r in 2:
		for c in 3:
			p.rect(14 + c * 2, 25 + r * 2, 1, 1, Color("4a4e56"))
	lit_rect(p, 25, 25, 3, 2, Color("4ad06a"), 0.2, -0.1)
	p.rect(14, 31, 9, 2, Color("3a3d45"))
	lit_rect(p, 12, 35, 18, 8, Paint.shade(grey, -0.12), 0.12, -0.2)
	p.line(Vector2(25, 37), Vector2(25, 40), Color("5a5e66"))


static func freezer(p: Paint) -> void:
	var white := Color("eeeeea")
	box3(p, 2, 21, 34, 21, 9, 9, white)
	lit_poly(p, [5, 19.5, 34, 19.5, 41, 13.5, 12, 13.5], Color("bcdcec"), -0.1, 0.15)
	var at := func(s: float, t: float) -> Vector2: return Vector2(5 + s * 29 + t * 7, 19.5 - t * 6)
	var boxes := [[0.08, 0.15, "8a5a3a"], [0.22, 0.2, "f39ab8"], [0.12, 0.55, "f8f0e0"], [0.58, 0.15, "3a8ee6"], [0.74, 0.18, "f2c83a"],
		[0.6, 0.55, "f39ab8"], [0.78, 0.6, "f2c83a"], [0.34, 0.6, "8a5a3a"]]
	for b: Array in boxes:
		var a: Vector2 = at.call(b[0], b[1])
		lit_poly(p, PackedVector2Array([a, a + Vector2(4.5, 0), a + Vector2(5.8, -2.4), a + Vector2(1.3, -2.4)]), Color(b[2]), 0.2, -0.2)
	p.line(at.call(0.5, 0.0), at.call(0.5, 1.0), Color("e8eef2"))
	p.line(at.call(0.02, 0.9), at.call(0.45, 0.9), Color(1, 1, 1))
	for y in [36, 38, 40]:
		p.line(Vector2(27, y), Vector2(33, y), Color("b0b4ba"))
	for x in [4, 32]:
		p.rect(x, 42, 3, 2, Color("2a2b31"))
	p.rect(41, 36, 2, 2, Color("2a2b31"))


## A magazine cover leaning in a rack, its foot at (x, y): `c` the cover, a title band and a picture.
static func magazine(p: Paint, x: float, y: float, c: Color, title: Color, pic: Color) -> void:
	lit_poly(p, [x, y, x + 9, y, x + 10, y - 15, x + 1, y - 15], c, 0.2, -0.25)
	lit_poly(p, [x + 1.8, y - 11.5, x + 8.6, y - 11.5, x + 8.9, y - 14, x + 2.1, y - 14], title, 0.1, -0.1)
	p.ball(x + 5.2, y - 6.5, 2.6, 2.8, pic)


static func magazine_rack(p: Paint) -> void:
	var steel := Color("c9cdd4")
	var covers := [["f07aa0", "f8f4ee", "f8c09a"], ["5cc06a", "f2d23a", "f39a3a"], ["3a8ee6", "f8f4ee", "f8c09a"],
		["f2d23a", "e0402e", "6ab0f0"], ["f39a3a", "f8f4ee", "f8c09a"], ["a06ad0", "f2d23a", "f8c09a"]]
	p.line(Vector2(39, 14), Vector2(39, 36), Paint.shade(steel, -0.3), 1.2)
	for tier in [2, 1, 0]:
		var x0: float = 8 + tier * 1.5
		var y0: float = 38 - tier * 9.5
		for k in 2:
			var c: Array = covers[tier * 2 + k]
			magazine(p, x0 + k * 12, y0, Color(c[0]), Color(c[1]), Color(c[2]))
		p.line(Vector2(x0 - 2, y0 - 3.5), Vector2(x0 + 25, y0 - 3.5), steel, 1.4)
		p.line(Vector2(x0 + 25, y0 - 3.5), Vector2(x0 + 30, y0 - 6), Paint.shade(steel, -0.2))
	p.line(Vector2(6, 41), Vector2(6, 22), steel, 1.4)
	p.line(Vector2(6, 22), Vector2(10, 7), steel, 1.2)
	p.line(Vector2(34, 41), Vector2(34, 22), steel, 1.4)
	p.line(Vector2(34, 22), Vector2(37, 7), Paint.shade(steel, -0.1), 1.2)
	p.line(Vector2(5, 41), Vector2(35, 41), steel, 1.6)
	p.line(Vector2(35, 41), Vector2(40, 37), Paint.shade(steel, -0.15), 1.4)
	for w: Array in [[7, 43.8], [33, 43.8], [40, 39]]:
		p.ball(w[0], w[1], 1.9, 1.9, Color("2a2b31"))



static func lantern(p: Paint) -> void:
	var wood := Color("a8642e")
	box3(p, 14, 41, 20, 3, 2, 2, wood)
	p.rect(15, 44, 3, 2, Paint.shade(wood, -0.3))
	p.rect(30, 44, 3, 2, Paint.shade(wood, -0.3))
	var post := mask(p)
	post.rect(29, 4, 3, 38, W)
	fill_barrel(p, post, wood)
	lit_rect(p, 16, 3, 17, 3, Paint.shade(wood, 0.05), 0.25, -0.25)
	p.line(Vector2(19.5, 6), Vector2(19.5, 9), Color("3a3a40"))
	lit_rect(p, 16, 9, 8, 2, Color("2a2a30"), 0.2, -0.1)
	var red := Color("dd3328")
	var body := mask(p)
	body.ellipse(20, 21, 7.6, 11, W)
	fill_ball(p, body, red, 0.1)
	var glow := mask(p)
	glow.ellipse(19, 20, 3.4, 7.5, W)
	fill(p, both(glow, body), Color("f8a040"), 0.3, -0.1)
	for y in range(13, 31, 2):
		var hw := 7.6 * sqrt(maxf(0.0, 1.0 - pow((y + 0.5 - 21) / 11.0, 2.0)))
		p.line(Vector2(20 - hw + 0.5, y), Vector2(20 + hw - 0.5, y), Paint.shade(red, -0.32))
	lit_rect(p, 16, 31, 8, 2, Color("2a2a30"), 0.2, -0.1)


static func aquarium(p: Paint) -> void:
	var wood := Color("9a5a2a")
	box3(p, 9, 28, 26, 15, 4, 2, wood)
	p.line(Vector2(22, 30), Vector2(22, 41), Paint.shade(wood, -0.35))
	p.rect(20, 32, 1, 4, Color("2a2420"))
	p.rect(23, 32, 1, 4, Color("2a2420"))
	for x in [10, 31]:
		p.rect(x, 43, 3, 2, Paint.shade(wood, -0.45))
	var water := Color("3d9de6")
	lit_poly(p, [36, 9, 40, 6, 40, 23, 36, 26], Paint.shade(water, -0.25), 0.1, -0.15)
	lit_rect(p, 8, 9, 28, 17, water, 0.2, -0.2)
	p.rect(9, 10, 26, 3, Paint.shade(water, 0.18))
	var gravel := lit_rect(p, 9, 22, 26, 3, Color("d8c8a0"), 0.1, -0.15)
	speckle(p, gravel, -0.25, 0.3, 18)
	p.ball(18, 22, 3, 2.2, Color("8a8e96"))
	p.ball(27.5, 22.5, 2.4, 1.8, Color("9a9ea6"))
	for l: Array in [[11, 23, 10, 12], [13, 23, 15, 14], [31, 23, 33, 13], [33, 23, 30, 15]]:
		leaf(p, Vector2(l[0], l[1]), Vector2(l[2], l[3]), 1.6, Color("4caa3e"))
	for f: Array in [[23, 14, 1], [16, 18, -1]]:
		var fx: float = f[0]
		var dir: float = f[2]
		lit_poly(p, [fx - dir * 2.5, f[1], fx - dir * 4.5, f[1] - 1.8, fx - dir * 4.5, f[1] + 1.8], Color("f8b040"), 0.2, -0.1)
		p.ball(fx, f[1], 2.6, 1.7, Color("f0702a"))
		p.px(floori(fx + dir * 1.2), floori(f[1]) - 1, Color("1a1a22"))
	p.line(Vector2(10, 14), Vector2(13, 10.5), Color("c8ecff"))
	box3(p, 8, 6.5, 28, 3, 4, 3, Color("2e3036"))


static func claw_machine(p: Paint) -> void:
	var pink := Color("f27aa6")
	var white := Color("f4f0ee")
	box3(p, 8, 6, 26, 38, 5, 4, white)
	lit_poly(p, [8, 6, 34, 6, 39, 2, 13, 2], Paint.shade(pink, 0.15), 0.2, -0.15)
	lit_poly(p, [34, 6, 39, 2, 39, 7, 34, 11], Paint.shade(pink, -0.22), 0.1, -0.15)
	lit_rect(p, 8, 6, 26, 5, pink, 0.25, -0.25)
	lit_poly(p, [34, 11, 39, 7, 39, 24, 34, 28], Color("c8d8e6"), 0.1, -0.1)
	lit_rect(p, 9, 11, 24, 17, Color("e2eef8"), 0.12, -0.15)
	var claw := Color("8a8e96")
	p.line(Vector2(20.5, 11), Vector2(20.5, 13), claw)
	lit_rect(p, 18, 13, 6, 2, Color("a6aab2"), 0.25, -0.2)
	for pr: Array in [[18.5, 15, 17, 18], [21, 15, 21, 18.5], [23.5, 15, 25, 18]]:
		p.line(Vector2(pr[0], pr[1]), Vector2(pr[2], pr[3]), claw)
	var eyes := Color("2a1a14")
	p.ball(28, 21.5, 3.2, 3.0, Color("f29cc0"))
	p.ball(25.5, 18.8, 1.3, 1.3, Color("f29cc0"))
	p.ball(30.5, 18.8, 1.3, 1.3, Color("f29cc0"))
	p.px(27, 21, eyes)
	p.px(29, 21, eyes)
	lit_ellipse(p, 19.2, 18.5, 1.0, 2.6, Color("f8f8f4"), 0.1, -0.2)
	lit_ellipse(p, 22.4, 18.5, 1.0, 2.6, Color("f8f8f4"), 0.1, -0.2)
	p.ball(20.8, 23.5, 3.4, 3.1, Color("f8f8f4"))
	p.px(19, 23, eyes)
	p.px(22, 23, eyes)
	p.ball(13.5, 23.5, 3.8, 3.4, Color("b8743a"))
	p.ball(10.8, 20.2, 1.5, 1.5, Color("b8743a"))
	p.ball(16.2, 20.2, 1.5, 1.5, Color("b8743a"))
	p.px(12, 23, eyes)
	p.px(15, 23, eyes)
	p.ellipse(13.5, 25, 1.4, 1, Color("e8c8a0"))
	p.ball(28.5, 25.5, 3.0, 2.6, Color("f6d23a"))
	p.px(28, 25, eyes)
	p.px(30, 26, Color("f08a2a"))
	lit_poly(p, [7, 31.5, 35, 31.5, 34, 28, 8, 28], pink, 0.25, -0.2)
	p.line(Vector2(15.5, 29), Vector2(15.5, 27), Color("3a3a40"))
	p.ball(15.5, 26.5, 1.6, 1.6, Color("e0302a"))
	p.ball(25, 29.5, 1.2, 1.0, Color("3a8ee6"))
	lit_rect(p, 8, 32, 26, 2, Paint.shade(pink, -0.1), 0.15, -0.15)
	lit_rect(p, 11, 35, 6, 6, Color("5a5e66"), -0.1, 0.1)
	p.rect(25, 35, 3, 2, Color("3a3a40"))
	for x in [9, 31]:
		p.rect(x, 44, 3, 2, Color("3a3d45"))
