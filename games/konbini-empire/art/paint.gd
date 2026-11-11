extends RefCounted
## A pixel-art canvas for the sprite sheets the game paints in code (art/sheets.gd). Shapes go down at the art's own
## pixel grid, flat or shaded in bands lit from the top left, `outline` rims what was painted, and `doubled` scales it
## to the sheet's texels (every sheet is cut at twice its pixel grid). `iso` projects metres through the 2:1 view the
## store and city cameras share (yaw 45°, pitch 30°), for art drawn in that view.

const LIGHT := Vector3(-0.5, -0.6, 0.62)  # toward the light in canvas space: x right, y down, z out of the picture
const WARM := Color(1.0, 0.97, 0.84)
const COOL := Color(0.12, 0.11, 0.25)

var img: Image
var w: int
var h: int


func _init(w_: int, h_: int) -> void:
	w = w_
	h = h_
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)


## c lit (k > 0, toward a warm highlight) or shaded (k < 0, toward a cool shadow), keeping its alpha.
static func shade(c: Color, k: float) -> Color:
	var t := WARM if k >= 0.0 else COOL
	var o := c.lerp(t, absf(k))
	o.a = c.a
	return o


## A house-style face tone: c with its rgb scaled by t (top 1.0, walls to the sun 0.9, away 0.75).
static func toned(c: Color, t: float) -> Color:
	return Color(c.r * t, c.g * t, c.b * t, c.a)


## Where p (metres: x east, y up, z south) lands through the 2:1 camera, in metres on screen: x right, y down.
static func iso(p: Vector3) -> Vector2:
	return Vector2(0.70711 * (p.x - p.z), 0.35355 * (p.x + p.z) - 0.86603 * p.y)


func px(x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= w or y >= h or c.a <= 0.0:
		return
	img.set_pixel(x, y, c if c.a >= 1.0 else img.get_pixel(x, y).blend(c))


func get_px(x: int, y: int) -> Color:
	if x < 0 or y < 0 or x >= w or y >= h:
		return Color(0, 0, 0, 0)
	return img.get_pixel(x, y)


## Row y from x0 to x1, both inclusive.
func span(y: int, x0: int, x1: int, c: Color) -> void:
	if y < 0 or y >= h:
		return
	x0 = maxi(x0, 0)
	x1 = mini(x1, w - 1)
	if x1 < x0:
		return
	if c.a >= 1.0:
		img.fill_rect(Rect2i(x0, y, x1 - x0 + 1, 1), c)
	else:
		for x in range(x0, x1 + 1):
			px(x, y, c)


func rect(x: int, y: int, rw: int, rh: int, c: Color) -> void:
	for yy in range(y, y + rh):
		span(yy, x, x + rw - 1, c)


## A filled ellipse centred on (cx, cy) in canvas pixels (pixel centres sit at +0.5).
func ellipse(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		var dy := (y + 0.5 - cy) / ry
		if absf(dy) > 1.0:
			continue
		var hw := rx * sqrt(1.0 - dy * dy)
		span(y, ceili(cx - hw - 0.5), floori(cx + hw - 0.5), c)


## A filled polygon (any winding, may be concave), scanned at pixel centres.
func poly(pts: PackedVector2Array, c: Color) -> void:
	var n := pts.size()
	if n < 3:
		return
	var y0 := INF
	var y1 := -INF
	for p in pts:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	for y in range(maxi(floori(y0), 0), mini(ceili(y1), h)):
		var yc := y + 0.5
		var xs: Array[float] = []
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			if (a.y <= yc) != (b.y <= yc):
				xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			span(y, ceili(xs[k] - 0.5), floori(xs[k + 1] - 0.5), c)


## A line `width` pixels thick (1 gives a clean single-pixel stroke).
func line(a: Vector2, b: Vector2, c: Color, width := 1.0) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
	var r := (width - 1.0) / 2.0
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		if r <= 0.0:
			px(floori(p.x), floori(p.y), c)
		else:
			ellipse(p.x, p.y, r + 0.5, r + 0.5, c)


## An ellipse shaded as a ball lit from the top left in four bands: highlight, base, shade, deep shade. `soft` widens
## the lit side (leafy crowns); `rim` > 0 lifts the far lower edge with bounced light.
func ball(cx: float, cy: float, rx: float, ry: float, c: Color, soft := 0.0, rim := 0.0) -> void:
	var l := LIGHT.normalized()
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d2 := dx * dx + dy * dy
			if d2 > 1.0:
				continue
			var lit := Vector3(dx, dy, sqrt(1.0 - d2)).dot(l) + soft
			var k := 0.28 if lit > 0.78 else (0.0 if lit > 0.3 else (-0.2 if lit > -0.05 else -0.36))
			if rim > 0.0 and d2 > 0.7 and dx + dy > 0.6:
				k += rim
			px(x, y, shade(c, k))


## A vertical cylinder's face from x0 to x1 (inclusive) between rows y0 and y1, banded across its width: a highlight
## a quarter of the way in, the base, then shade toward the right.
func barrel(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var wd := maxf(1.0, x1 - x0 + 1)
	for x in range(x0, x1 + 1):
		var u := (x - x0 + 0.5) / wd
		var k := 0.26 if u > 0.18 and u < 0.36 else (0.0 if u < 0.62 else (-0.18 if u < 0.84 else -0.34))
		for y in range(y0, y1 + 1):
			px(x, y, shade(c, k))


## Rims every painted shape: each empty pixel touching one (4-neighbours) takes `ink`, or with no ink given, its
## darkest painted neighbour pushed most of the way into deep shade, a selective outline.
func outline(ink := Color(0, 0, 0, 0)) -> void:
	var src: Image = img.duplicate()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			var best := Color(0, 0, 0, 0)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + d
				if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h:
					continue
				var n := src.get_pixel(q.x, q.y)
				if n.a > 0.5 and (best.a == 0.0 or n.get_luminance() < best.get_luminance()):
					best = n
			if best.a > 0.0:
				img.set_pixel(x, y, ink if ink.a > 0.0 else shade(best, -0.72))


## Darkens painted pixels that border empty space on their lower right, a one-pixel inner shadow line.
func inner_shade(k := -0.25) -> void:
	var src: Image = img.duplicate()
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			if c.a == 0.0:
				continue
			if (x + 1 < w and src.get_pixel(x + 1, y).a == 0.0) or (y + 1 < h and src.get_pixel(x, y + 1).a == 0.0):
				img.set_pixel(x, y, shade(c, k))


func flip() -> void:
	img.flip_x()


## The canvas at the sheet's resolution: every pixel doubled.
func doubled() -> Image:
	var o: Image = img.duplicate()
	o.resize(w * 2, h * 2, Image.INTERPOLATE_NEAREST)
	return o


## Copies the doubled canvas onto sheet `dst` with its top left at `at` (sheet texels).
func stamp(dst: Image, at: Vector2i) -> void:
	var d := doubled()
	dst.blend_rect(d, Rect2i(Vector2i.ZERO, d.get_size()), at)


## Projects metres p through the 2:1 view to the canvas: `o` is where the origin lands, k canvas pixels per metre.
func iso_pt(p: Vector3, o: Vector2, k: float) -> Vector2:
	return o + iso(p) * k


## A flat face of 3D corners `pts` (metres) through the 2:1 view.
func iso_face(pts: Array, c: Color, o: Vector2, k: float) -> void:
	var q := PackedVector2Array()
	for p in pts:
		q.append(iso_pt(p, o, k))
	poly(q, c)


## A box from a to b (metres) through the 2:1 view in the house's three tones: its top full, the +z wall (on screen
## left, turned to the sun) 0.9, the +x wall (right, away) 0.75. Paint far boxes first.
func iso_box(a: Vector3, b: Vector3, c: Color, o: Vector2, k: float) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	iso_face([Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], toned(c, 0.9), o, k)
	iso_face([Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z)], toned(c, 0.75), o, k)
	iso_face([Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)], c, o, k)
