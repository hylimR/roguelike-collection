extends RefCounted
## The people on the street, painted in art/walk.png's layout: a row of store_view's PERSON cells per character in
## WALK_ROW's order (the seven customers, each staff role and threat, then a flyer girl and a costume mascot per rival
## chain in Sim.RIVALS' order), each a standing frame then four of a walk cycle, all facing right (the game flips
## them). A figure is put together from parts (a head with its hair, hat and face, a torso in its outfit, limbs posed
## per frame, what they carry) painted at the art's own grid, half the cell's texels, in bands lit from the top left;
## each layer is rimmed in a dark selective outline over the layers behind it, then the cell is doubled.

const Paint := preload("res://art/paint.gd")
const Sim := preload("res://sim.gd")

## A cell at the art's own grid, half store_view's PERSON cell.
const W := 36
const H := 48
const FULL := Rect2i(0, 0, W, H)
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
## Toward the light in the canvas' plane, for shading limbs round their length.
const LIT := Vector2(-0.6, -0.8)
## What an outline's colour is pulled toward: the part it rims, darkened, then mostly this plum.
const INK := Color(0.1, 0.02, 0.1, 0.62)
## Per frame: how far the body sits down, the near foot's reach and lift from under its hip, the far foot's, and the
## near hand's swing (the far hand swings opposite): standing, contact, passing, contact, passing.
const GAIT := [[0, 1.5, 0.0, -1.5, 0.0, 0.0], [1, 6.0, 0.0, -6.0, 0.0, -6.5], [0, 1.0, 0.0, -1.5, 2.5, -2.0],
		[1, -6.0, 0.0, 6.0, 0.0, 6.5], [0, -1.5, 2.5, 1.0, 0.0, 2.0]]
## The usual skin tone, and the white of collars, cuffs and buttons.
const SKIN := "f6c8a0"
const WHITE := "f3f1ea"
## The seven customers, then each staff role and threat: build, skin, hair and hat [style, colour, accent], face
## extras, top [style, colour, accent] and its stripes, sleeves, legs [style, colour], socks, shoes [style, colour],
## gloves, and what they carry in hand or on their back.
const CAST := [
	{"hair": ["short", "222838"], "top": ["suit", "2b375e", "c0642e"], "legs": ["trousers", "232b48"], "shoes": ["shoe", "3b2a23"], "item": "briefcase"},
	{"build": "slim", "hair": ["pony", "8c4f2c"], "face": ["blush"], "top": ["blouse", "f3eee6"], "legs": ["skirt", "6c6872"], "shoes": ["heel", "2a2229"], "item": "shoulderbag"},
	{"build": "slim", "hair": ["bob", "28335f"], "face": ["blush"], "top": ["sailor", "283462", "c83a30"], "legs": ["skirt", "283462"], "socks": "1f2645", "shoes": ["shoe", "6b3b24"], "item": "schoolbag"},
	{"build": "old", "hair": ["bun", "a9a6a3"], "face": ["smile"], "top": ["cardigan", "a9617f", "f3eee6"], "legs": ["trousers", "6b4b32"], "shoes": ["shoe", "4a3529"], "item": "plasticbag"},
	{"skin": "e9b088", "hair": ["short", "2a2421"], "hat": ["hardhat", "f3f1e9", "3a9a5c"], "top": ["vest", "7da892", "f27a1f"], "legs": ["trousers", "6f9a85"], "shoes": ["boot", "2b2724"], "hands": "f5f4ee"},
	{"skin": "f7cba8", "hair": ["messy", "dca354"], "top": ["tee", "9fcde8"], "sleeve": "short", "legs": ["shorts", "c9a978"], "socks": "5b7f63", "shoes": ["boot", "7a4b2b"], "pack": "hiker", "item": "camera"},
	{"build": "kid", "hair": ["short", "2a2421"], "hat": ["kidhat", "f5c51a"], "top": ["tee", "f6f6f4"], "sleeve": "short", "legs": ["shorts", "3b6cc9"], "socks": "f6f6f4", "shoes": ["sneaker", "3b6cc9"], "pack": "randoseru"},
	{"hair": ["pony", "8c4f2c"], "face": ["blush"], "top": ["konbini", "2a9b4c", "f4f4ee"], "legs": ["trousers", "2a2a35"], "shoes": ["sneaker", "f2f1ec"]},
	{"hair": ["short", "2a2421"], "hat": ["peaked", "1f2b52", "d8b040"], "top": ["police", "27335f", "a9c9e9"], "legs": ["trousers", "27335f"], "shoes": ["shoe", "221e22"], "hands": "f5f4ee"},
	{"hair": ["bob", "6b5b51"], "hat": ["scarf", "f4f4f1"], "face": ["blush"], "top": ["apron", "5fae7c", "8b8a91"], "legs": ["trousers", "8b8a91"], "shoes": ["shoe", "6a6a72"], "hands": "f2c21e", "item": "mop"},
	{"hair": ["spiky", "1e2029"], "hat": ["hachimaki", "f4f3ee"], "top": ["happi", "2a9b4c", "f4f4ee"], "stripes": true, "legs": ["trousers", "2a2a3b"], "shoes": ["sneaker", "f2f1ec"], "item": "flyers"},
	{"hair": ["short", "1e2029"], "hat": ["cap", "2a9b4c"], "top": ["konbini", "2a9b4c", "f4f4ee"], "legs": ["trousers", "2a2a3b"], "shoes": ["sneaker", "f2f1ec"], "item": "box"},
	{"hair": ["short", "3a3a3e"], "hat": ["hood", "3d3b4b", "17171c"], "face": ["mask"], "top": ["hoodie", "3d3b4b"], "legs": ["trousers", "2b3b5c"], "shoes": ["sneaker", "d9d8d0"], "pack": "daypack"},
	{"hair": ["slick", "1b1b20"], "face": ["shades"], "top": ["suit", "24242c", "1b1b20"], "legs": ["trousers", "1f1f26"], "shoes": ["shoe", "151519"], "item": "attache"},
	{"hair": ["long", "8c4f2c"], "hat": ["beanie", "ede5d1"], "face": ["frown"], "top": ["coat", "d5b98d"], "legs": ["trousers", "2f2a2b"], "shoes": ["boot", "5b3b29"], "item": "phone"},
]
## A rival chain's flyer girl; her coat and headband take the chain's colour.
const FLYER := {"build": "slim", "hair": ["pony", "7b4a2b"], "face": ["blush"], "legs": ["shorts", "1f1f26"], "shoes": ["sneaker", "f2f1ec"], "item": "flyers"}
## Each chain's costume mascot: fur, its paler belly or muzzle, a dark tone, and the costume's trim.
const MASCOT := {
	"tanuki": {"fur": "a9693d", "pale": "f2d09a", "dark": "4b2d1f", "trim": "d9412e"},
	"kappa": {"fur": "8fc640", "pale": "ece48e", "dark": "3e7b2b", "trim": "f3c31d"},
	"usagi": {"fur": "f8f4f6", "pale": "f29ab4", "dark": "c9b8c4", "trim": "3a79c9"},
	"kitsune": {"fur": "f27b2b", "pale": "fcefe1", "dark": "3b2317", "trim": "5b2e6f"},
	"oni": {"fur": "e44b2d", "pale": "f1dfb4", "dark": "3b2941", "trim": "f1b928"},
	"mega": {"fur": "5b616f", "pale": "bcc2cc", "dark": "272b35", "trim": "f7d33b"},
}

## INK as a cell-sized fill, made once.
static var tint: Image


## The whole sheet: a row per character, each frame painted at the art's own grid and doubled into its cell.
static func walk() -> Image:
	var rows: Array = CAST.duplicate()
	for id: String in Sim.RIVALS:
		var f: Dictionary = FLYER.duplicate()
		f.top = ["happi", Sim.RIVALS[id].color, "f6f2e8"]
		f.hat = ["band", Sim.RIVALS[id].color]
		rows.append(f)
	for id: String in Sim.RIVALS:
		rows.append({"mascot": id})
	var sheet := Image.create(W * 2 * GAIT.size(), H * 2 * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		var c: Dictionary = rows[r]
		var k := build(c)
		var top := mascot_head(c.mascot) if c.has("mascot") else head(c, k)
		for f in GAIT.size():
			var p := mascot(c.mascot, f, top) if c.has("mascot") else person(c, k, f, top)
			p.stamp(sheet, Vector2i(f * W * 2, r * H * 2))
	return sheet


## Where a figure's parts sit: head centre and radius, shoulder line, hips, torso half width, leg and arm sizes.
static func build(c: Dictionary) -> Dictionary:
	match c.get("build", ""):
		"kid":
			return {"cx": 18.0, "hx": 18.0, "hy": 20.5, "r": 7.4, "sy": 28.0, "hip": 37.0, "tw": 4.4, "leg": 1.7, "arm": 3.9, "reach": 0.7}
		"old":
			return {"cx": 18.0, "hx": 19.5, "hy": 15.0, "r": 8.0, "sy": 24.5, "hip": 35.0, "tw": 6.0, "leg": 2.0, "arm": 4.5, "reach": 0.7, "hunch": 1.0}
		"slim":
			return {"cx": 18.0, "hx": 18.0, "hy": 12.5, "r": 8.2, "sy": 22.0, "hip": 34.0, "tw": 5.2, "leg": 2.2, "arm": 4.8, "reach": 1.0}
	return {"cx": 18.0, "hx": 18.0, "hy": 12.5, "r": 8.2, "sy": 22.0, "hip": 34.0, "tw": 6.0, "leg": 2.3, "arm": 4.8, "reach": 1.0}


## A person's frame `f`, back to front: the far leg and arm in shade, a backpack, the near leg under the torso, the
## head, what they carry, then the near arm.
static func person(c: Dictionary, k: Dictionary, f: int, top: Image) -> Paint:
	var g: Array = GAIT[f]
	var b: float = g[0]
	var p := Paint.new(W, H)
	var l := Paint.new(W, H)
	leg(l, c, k, b, g[3], g[4], false)
	arm(l, c, k, b, -g[5], false)
	stick(p, l)
	if c.has("pack"):
		l = Paint.new(W, H)
		pack(l, c, k, b)
		stick(p, l)
	l = Paint.new(W, H)
	leg(l, c, k, b, g[1], g[2], true)
	torso(l, c, k, b)
	stick(p, l)
	p.img.blend_rect(top, FULL, Vector2i(0, int(b)))
	if c.has("item"):
		l = Paint.new(W, H)
		item(l, c, k, b, g[5])
		stick(p, l)
	l = Paint.new(W, H)
	arm(l, c, k, b, g[5], true)
	stick(p, l)
	return p


## Rims what `l` holds in its outline and lays both over `dst`.
static func stick(dst: Paint, l: Paint) -> void:
	dst.img.blend_rect(rimmed(l.img), FULL, Vector2i.ZERO)


## The layer over its outline: every empty pixel beside a painted one takes that neighbour, darkened and pulled to INK.
static func rimmed(src: Image) -> Image:
	if tint == null:
		tint = Image.create(W, H, false, Image.FORMAT_RGBA8)
		tint.fill(INK)
	var ink: Image = src.duplicate()
	ink.adjust_bcs(0.22, 1.0, 1.0)
	ink.blend_rect_mask(tint, src, FULL, Vector2i.ZERO)
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for d in SIDES:
		out.blit_rect_mask(ink, src, FULL, d)
	out.blend_rect(src, FULL, Vector2i.ZERO)
	return out


## c lit (k > 0: brighter and a touch warm, keeping its hue, so dark cloth and hair don't go grey) or shaded as
## Paint.shade does (k < 0).
static func tone(c: Color, k: float) -> Color:
	if k <= 0.0:
		return Paint.shade(c, k)
	var o := Color.from_hsv(c.h, c.s * (1.0 - 0.3 * k), minf(1.0, c.v + k * (0.3 + 0.7 * (1.0 - c.v))), c.a)
	return o.lerp(Paint.WARM, k * 0.3)


## A palette colour from its hex, lit or shaded by k.
static func col(hex: String, k := 0.0) -> Color:
	return tone(Color(hex), k)


## A ball lit from the top left in four bands (as Paint.ball, its light keeping the hue), cut off at row `cut`, the cut
## dropping `tilt` rows a pixel behind x `back`.
static func orb(p: Paint, cx: float, cy: float, rx: float, ry: float, c: Color, cut := H, back := 0.0, tilt := 0.0) -> void:
	var l := Paint.LIGHT.normalized()
	var tones := [tone(c, 0.24), c, tone(c, -0.18), tone(c, -0.34)]
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			if y >= cut + maxf(0.0, back - x - 0.5) * tilt:
				continue
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d2 := dx * dx + dy * dy
			if d2 > 1.0:
				continue
			var lit := Vector3(dx, dy, sqrt(1.0 - d2)).dot(l)
			p.px(x, y, tones[0 if lit > 0.8 else (1 if lit > 0.3 else (2 if lit > -0.05 else 3))])


## A limb from a to b, r thick, shaded round its length: lit edge, base, shaded edge.
static func limb(p: Paint, a: Vector2, b: Vector2, r: float, c: Color) -> void:
	var tones := [tone(c, 0.2), c, tone(c, -0.2)]
	var ab := b - a
	var l2 := maxf(ab.length_squared(), 0.0001)
	var n := LIT.normalized()
	for y in range(floori(minf(a.y, b.y) - r), ceili(maxf(a.y, b.y) + r) + 1):
		for x in range(floori(minf(a.x, b.x) - r), ceili(maxf(a.x, b.x) + r) + 1):
			var q := Vector2(x + 0.5, y + 0.5)
			var d := q - (a + ab * clampf((q - a).dot(ab) / l2, 0.0, 1.0))
			if d.length_squared() > r * r:
				continue
			var lit := (d / r).dot(n)
			p.px(x, y, tones[0 if lit > 0.3 else (1 if lit > -0.3 else 2)])


## Scanline spans of a polygon: [y, x0, x1] for each run inside it.
static func spans(pts: PackedVector2Array) -> Array:
	var out := []
	var y0 := INF
	var y1 := -INF
	for q in pts:
		y0 = minf(y0, q.y)
		y1 = maxf(y1, q.y)
	for y in range(maxi(floori(y0), 0), mini(ceili(y1), H)):
		var yc := y + 0.5
		var xs: Array[float] = []
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			if (a.y <= yc) != (b.y <= yc):
				xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for j in range(0, xs.size() - 1, 2):
			var x0 := ceili(xs[j] - 0.5)
			var x1 := floori(xs[j + 1] - 0.5)
			if x1 >= x0:
				out.append([y, x0, x1])
	return out


## Cloth in bands across each row: its lit back edge, the base, then shade toward the front; the top row lit.
static func cloth(p: Paint, pts: PackedVector2Array, c: Color) -> void:
	var hi := tone(c, 0.18)
	var lo := tone(c, -0.18)
	var first := -1
	for s: Array in spans(pts):
		var y: int = s[0]
		var x0: int = s[1]
		var x1: int = s[2]
		if first < 0:
			first = y
		p.span(y, x0, x1, hi if y == first else c)
		if x1 - x0 >= 2:
			p.px(x0, y, hi)
		if x1 - x0 >= 6:
			p.span(y, x1 - 1, x1, lo)
		elif x1 > x0:
			p.px(x1, y, lo)


## A polygon in one colour.
static func flat(p: Paint, pts: PackedVector2Array, c: Color) -> void:
	for s: Array in spans(pts):
		p.span(s[0], s[1], s[2], c)


## Points from a flat list of coordinates.
static func pv(a: Array) -> PackedVector2Array:
	var o := PackedVector2Array()
	for i in range(0, a.size(), 2):
		o.append(Vector2(a[i], a[i + 1]))
	return o


## Where a knee bends forward between hip h and ankle a, both thigh and shin l long.
static func knee(h: Vector2, a: Vector2, l: float) -> Vector2:
	var d := a - h
	var n := d.length()
	if n >= 2.0 * l:
		return h + d * 0.5
	return h + d * 0.5 + Vector2(d.y, -d.x).normalized() * sqrt(l * l - n * n / 4.0)


## A leg from the hip to a foot `reach` ahead and `lift` off the ground: trousers, or bare under a skirt or shorts,
## socks and a shoe; the far one in shade.
static func leg(p: Paint, c: Dictionary, k: Dictionary, b: float, reach: float, lift: float, near: bool) -> void:
	var shade := 0.0 if near else -0.22
	var hip := Vector2(k.cx + (0.5 if near else -1.0), k.hip + b)
	var ank := Vector2(hip.x + reach * k.reach, H - 5.0 - lift)
	var kn := knee(hip, ank, (H - 5.0 - k.hip) / 2.0 + 0.3)
	var lg: Array = c.legs
	var skin := col(c.get("skin", SKIN), shade)
	var cc := col(lg[1], shade)
	var r: float = k.leg
	if lg[0] == "trousers":
		limb(p, hip, kn, r, cc)
		limb(p, kn, ank, r - 0.2, cc)
	else:
		limb(p, hip, kn, r - 0.5, skin)
		limb(p, kn, ank, r - 0.65, skin)
		if lg[0] == "shorts":
			limb(p, hip, hip.lerp(kn, 0.8), r + 0.1, cc)
	if c.has("socks"):
		limb(p, kn.lerp(ank, 0.3 if lg[0] == "skirt" else 0.6), ank, r - 0.5, col(c.socks, shade))
	shoe(p, ank, c.shoes, shade)


## A shoe at ankle a, toe forward: a court shoe on its heel, a boot, a sneaker on a grey sole, or a plain shoe.
static func shoe(p: Paint, a: Vector2, s: Array, shade: float) -> void:
	var c := col(s[1], shade)
	var x := floori(a.x) - 1
	var y := floori(a.y)
	match s[0]:
		"heel":
			p.rect(x + 1, y + 1, 4, 1, c)
			p.rect(x + 2, y + 2, 3, 1, c)
			p.px(x, y + 2, c)
			p.px(x + 1, y + 1, tone(c, 0.25))
		"boot":
			p.rect(x, y - 1, 4, 3, c)
			p.rect(x + 4, y + 1, 1, 2, c)
			p.span(y - 1, x, x + 3, tone(c, 0.25))
			p.span(y + 2, x, x + 4, tone(c, -0.3))
		"sneaker":
			p.rect(x, y, 4, 2, c)
			p.rect(x + 4, y + 1, 1, 1, c)
			p.span(y, x, x + 2, tone(c, 0.2))
			p.span(y + 2, x, x + 4, col("8f8b86", shade))
		_:
			p.rect(x, y + 1, 4, 2, c)
			p.px(x + 4, y + 2, c)
			p.span(y + 1, x, x + 2, tone(c, 0.25))
			p.span(y + 2, x, x + 4, tone(c, -0.25))


## How each arm is held for what the figure carries: swinging, holding something before the chest, or carrying a
## bag at the side.
static func pose(c: Dictionary, near: bool) -> String:
	match c.get("item", ""):
		"camera", "box", "phone":
			return "hold"
		"flyers", "mop":
			return "hold" if near else "swing"
		"briefcase", "attache", "plasticbag":
			return "carry" if near else "swing"
	return "swing"


## Shoulder, elbow and hand of an arm.
static func joints(c: Dictionary, k: Dictionary, b: float, swing: float, near: bool) -> Array[Vector2]:
	var l: float = k.arm
	var s := Vector2(k.cx + (0.0 if near else -1.2), k.sy + 2.0 + b)
	match pose(c, near):
		"hold":
			return [s, s + Vector2(-0.6, l), s + Vector2(l * 1.15, l * 1.3)]
		"carry":
			var dx := swing * 0.15 + (2.5 if c.item == "plasticbag" else -1.0)
			return [s, s + Vector2(dx * 0.4, l), s + Vector2(dx, l * 1.9)]
	var hx: float = swing * k.reach * (1.25 if swing > 0.0 else 1.0)
	return [s, s + Vector2(hx * 0.45, l * 0.95), s + Vector2(hx, l * 1.95 - absf(hx) * 0.3 - maxf(hx, 0.0) * 0.25)]


## An arm in its sleeve (short sleeves bare the forearm) ending in a hand or glove; the far one in shade.
static func arm(p: Paint, c: Dictionary, k: Dictionary, b: float, swing: float, near: bool) -> void:
	var j := joints(c, k, b, swing, near)
	var shade := 0.0 if near else -0.22
	var sleeve := col(c.legs[1] if c.top[0] == "vest" else c.top[1], shade)
	var skin := col(c.get("skin", SKIN), shade)
	var r := 1.9 if k.r > 8.0 else 1.5
	if c.get("sleeve", "long") == "short":
		limb(p, j[0], j[1], r - 0.2, skin)
		limb(p, j[1], j[2], r - 0.25, skin)
		limb(p, j[0], j[0].lerp(j[1], 0.65), r + 0.15, sleeve)
	else:
		limb(p, j[0], j[1], r, sleeve)
		limb(p, j[1], j[2], r - 0.1, sleeve)
		if c.top[0] == "sailor":
			limb(p, j[1].lerp(j[2], 0.72), j[1].lerp(j[2], 0.82), r, col(WHITE, shade))
	orb(p, j[2].x, j[2].y + 0.4, 1.7, 1.6, col(c.get("hands", c.get("skin", SKIN)), shade))


## The neck and torso in its outfit, with a skirt or shorts over the hips: a suit's shirt and tie, a sailor collar
## and ribbon, a hi-vis vest's bands, the konbini stripes, a guard's buttons and belt, an apron, a happi's collar, a
## hoodie's pocket, a trench coat's belt.
static func torso(p: Paint, c: Dictionary, k: Dictionary, b: float) -> void:
	var t: Array = c.top
	var style: String = t[0]
	var cc := Color(t[1])
	var acc := Color(t[2]) if t.size() > 2 else Color.WHITE
	var cx: float = k.cx
	var sy: float = k.sy + b
	var hip: float = k.hip + b
	var tw: float = k.tw
	var ix := int(cx)
	var iy := int(sy)
	var iw := int(tw)
	var ih := int(hip)
	var skin := col(c.get("skin", SKIN))
	limb(p, Vector2(cx + 0.5, sy - 2.5), Vector2(cx + 0.5, sy + 0.5), 1.8, tone(skin, -0.14))
	var hem: float = hip + {"suit": 1.0, "coat": 6.0, "cardigan": 1.5, "happi": 1.5, "hoodie": 1.0, "police": 0.5}.get(style, 0.0)
	if c.legs[0] == "skirt":
		var sk := Color(c.legs[1])
		cloth(p, pv([cx - tw, hip - 2.5, cx + tw - 0.3, hip - 2.5, cx + tw + 1.4, hip + 3.5, cx - tw - 1.4, hip + 3.5]), sk)
		for x in range(ix - iw, ix + iw + 2, 2):
			p.px(x, ih + 1, tone(sk, -0.25))
			p.px(x, ih + 2, tone(sk, -0.25))
		hem = hip - 2.0
	elif c.legs[0] == "shorts":
		cloth(p, pv([cx - tw + 0.3, hip - 1.5, cx + tw - 0.3, hip - 1.5, cx + tw, hip + 2.5, cx - tw, hip + 2.5]), Color(c.legs[1]))
	var body := pv([cx - tw + 1, sy, cx + tw - 1.5, sy, cx + tw, sy + 2, cx + tw + 0.3, sy + 6, cx + tw - 0.2, hem,
			cx - tw - 0.2, hem, cx - tw - 0.4, sy + 6, cx - tw, sy + 2])
	if k.has("hunch"):
		body = pv([cx - tw + 1, sy - 0.5, cx + tw - 1.5, sy, cx + tw, sy + 2, cx + tw + 0.5, sy + 6, cx + tw, hem,
				cx - tw - 0.3, hem, cx - tw - 1.2, sy + 5, cx - tw - 0.8, sy + 1.5])
	cloth(p, body, cc)
	var lo := tone(cc, -0.3)
	var white := col(WHITE)
	match style:
		"suit":
			for q: Vector2i in [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(3, 1), Vector2i(5, 1), Vector2i(5, 2)]:
				p.px(ix + q.x, iy + q.y, white)
			for y in range(1, 6):
				p.px(ix + 4, iy + y, acc if y < 5 else tone(acc, -0.3))
			p.px(ix + 2, iy + 1, lo)
			p.px(ix + 3, iy + 2, lo)
			p.px(ix + 3, iy + 3, lo)
			p.px(ix + 4, iy + 8, tone(cc, 0.3))
		"blouse":
			p.px(ix + 3, iy, tone(cc, -0.2))
			p.px(ix + 4, iy + 1, tone(cc, -0.2))
			p.span(ih - 3, ix - iw + 1, ix + iw - 1, tone(cc, -0.12))
		"sailor":
			p.span(iy + 4, ix - iw, ix - 2, white)
			p.px(ix - 2, iy + 3, white)
			p.px(ix - 1, iy + 2, white)
			p.px(ix + 1, iy, white)
			p.px(ix + 2, iy + 1, white)
			p.px(ix + 3, iy + 2, white)
			p.rect(ix + 4, iy + 2, 2, 2, acc)
			p.px(ix + 5, iy + 4, tone(acc, -0.25))
		"cardigan":
			p.rect(ix + 1, iy, 3, 1, acc)
			p.px(ix + 3, iy + 1, acc)
			for y in range(iy + 2, int(hem)):
				p.px(ix + iw - 1, y, lo)
			for y: int in [iy + 4, iy + 7, iy + 10]:
				p.px(ix + iw, y, tone(cc, 0.3))
		"vest":
			cloth(p, pv([cx - tw + 1.5, sy + 1, cx + tw - 1, sy + 1, cx + tw + 0.3, sy + 4, cx + tw, hip - 0.5, cx - tw + 0.2, hip - 0.5, cx - tw, sy + 4]), acc)
			var band := col("f7f0c4")
			p.span(iy + 6, ix - iw + 1, ix + iw, band)
			p.span(iy + 9, ix - iw + 1, ix + iw, band)
			p.rect(ix + 1, iy, 3, 1, tone(cc, 0.15))
		"tee":
			p.rect(ix + 1, iy, 3, 1, tone(cc, -0.25))
		"konbini":
			for y in range(iy + 1, int(hem)):
				p.px(ix - 2, y, acc)
				p.px(ix + 2, y, acc)
			p.rect(ix + 1, iy, 3, 1, acc)
			p.span(ih - 1, ix - iw, ix + iw, tone(cc, -0.3))
		"police":
			p.rect(ix + 1, iy, 4, 1, acc)
			p.px(ix + 3, iy + 1, acc)
			p.px(ix + 4, iy + 1, tone(cc, -0.35))
			p.px(ix + 4, iy + 2, tone(cc, -0.35))
			var gold := col("d8b040")
			p.px(ix + 5, iy + 5, gold)
			p.px(ix + 5, iy + 8, gold)
			p.px(ix + 1, iy + 4, gold)
			p.span(ih - 1, ix - iw, ix + iw, col("1b1b20"))
			p.px(ix + 4, ih - 1, col("c9ccd1"))
			p.rect(ix + 2, iy + 3, 2, 3, col("1d1d22"))
		"apron":
			for y in range(iy, int(hem)):
				for x in range(ix - iw, ix + iw + 1, 2):
					if p.get_px(x, y).a > 0.0:
						p.px(x, y, col("f2f4ee"))
			cloth(p, pv([cx - 0.5, sy + 3, cx + tw + 0.4, sy + 3, cx + tw + 0.8, hip + 3, cx - tw - 0.2, hip + 3, cx - tw - 0.2, hip - 3, cx - 1.5, hip - 3]), acc)
			p.px(ix + 3, iy, acc)
			p.px(ix + 3, iy + 1, acc)
			p.px(ix + 3, iy + 2, acc)
			p.span(ih, ix + 1, ix + 4, tone(acc, -0.25))
		"happi":
			for y in range(0, 9):
				p.px(ix + 1 + int(y * 0.5), iy + y, acc)
				p.px(ix + 2 + int(y * 0.5), iy + y, acc)
			p.span(int(hem) - 1, ix - iw, ix + iw, acc)
			if c.get("stripes", false):
				for y in range(iy + 2, int(hem) - 1):
					p.px(ix - 3, y, acc)
		"hoodie":
			p.rect(ix + 1, ih - 4, 4, 3, lo)
			p.px(ix + 3, iy + 1, col("e9e7e2"))
			p.px(ix + 3, iy + 2, col("e9e7e2"))
		"coat":
			p.span(ih - 2, ix - iw, ix + iw, tone(cc, -0.28))
			p.px(ix + 3, ih - 2, col("8a6a3a"))
			p.rect(ix + 1, iy, 3, 2, tone(cc, -0.22))
			for y: int in [iy + 4, iy + 7, ih + 1]:
				p.px(ix + 3, y, tone(cc, -0.35))
			for y in range(ih, int(hem)):
				p.px(ix + iw - 1, y, lo)


## What hangs on the back: a hiker's big pack under its bedroll, a randoseru, a daypack.
static func pack(p: Paint, c: Dictionary, k: Dictionary, b: float) -> void:
	var cx: float = k.cx
	var sy: float = k.sy + b
	var ix := int(cx)
	var iy := int(sy)
	match c.pack:
		"hiker":
			var g := col("3f7b47")
			orb(p, cx - 8.5, sy + 5.5, 5.6, 8.5, g)
			orb(p, cx - 12.0, sy + 8.0, 2.0, 4.0, tone(g, -0.12))
			orb(p, cx - 8.5, sy - 3.0, 4.8, 2.4, tone(g, -0.18))
			p.span(iy - 3, ix - 12, ix - 5, tone(g, -0.4))
			p.span(iy + 2, ix - 13, ix - 4, tone(g, -0.32))
			p.rect(ix - 11, iy + 3, 3, 3, tone(g, 0.12))
		"randoseru":
			var n := col("2c3c6c")
			p.rect(ix - 9, iy, 5, 9, n)
			p.span(iy, ix - 9, ix - 5, tone(n, 0.25))
			p.rect(ix - 9, iy + 1, 1, 7, tone(n, 0.2))
			p.px(ix - 8, iy + 5, col("e1c35a"))
		"daypack":
			var d := col("2a2d33")
			orb(p, cx - 7.0, sy + 6.0, 3.5, 5.5, d)
			p.span(iy + 7, ix - 10, ix - 5, tone(d, 0.25))
			p.line(Vector2(cx - 4.5, sy + 0.5), Vector2(cx + 1.0, sy + 0.5), tone(d, 0.3))


## What the near hand holds or the near shoulder carries, placed by the hand.
static func item(p: Paint, c: Dictionary, k: Dictionary, b: float, swing: float) -> void:
	var cx: float = k.cx
	var sy: float = k.sy + b
	var hand := joints(c, k, b, swing, true)[2]
	var hx := int(hand.x)
	var hy := int(hand.y)
	match c.item:
		"briefcase", "attache":
			var cc := col("3d2b24" if c.item == "briefcase" else "b3b7bc")
			var w := 10 if c.item == "briefcase" else 9
			p.rect(hx - w + 2, hy + 1, w, 7, cc)
			p.span(hy + 1, hx - w + 2, hx + 1, tone(cc, 0.22))
			p.span(hy + 7, hx - w + 2, hx + 1, tone(cc, -0.25))
			p.rect(hx - w + 2, hy + 2, 1, 5, tone(cc, 0.12))
			p.rect(hx - 1, hy, 2, 1, tone(cc, -0.3))
			p.px(hx - (w >> 1) + 2, hy + 3, col("d8b040") if c.item == "briefcase" else col("4a4d52"))
		"shoulderbag", "schoolbag":
			var cc := col("d8808f" if c.item == "shoulderbag" else "3e5c94")
			p.line(Vector2(cx + 2.5, sy + 0.5), Vector2(cx - 4.0, sy + 8.0), tone(cc, -0.3))
			orb(p, cx - 5.5, sy + 10.0, 3.5, 3.0, cc)
		"plasticbag":
			var wb := col("f2f2ee")
			p.line(Vector2(hand.x + 2.5, hand.y + 2.0), Vector2(hand.x + 4.5, hand.y - 3.5), col("4f9e3e"), 2.0)
			p.line(Vector2(hand.x + 2.0, hand.y + 2.5), Vector2(hand.x + 3.0, hand.y - 0.5), col("eef0dc"))
			orb(p, hand.x + 1.0, hand.y + 4.8, 3.5, 3.8, wb)
			p.px(hx, hy + 2, tone(wb, -0.25))
			p.px(hx + 2, hy + 2, tone(wb, -0.25))
		"camera":
			var bk := col("2b2b30")
			p.line(Vector2(cx + 1.5, sy + 0.5), Vector2(hand.x - 1.0, hand.y - 1.5), bk)
			p.rect(hx - 1, hy - 2, 5, 3, bk)
			p.px(hx + 4, hy - 1, col("5c6068"))
			p.px(hx + 4, hy, col("5c6068"))
			p.span(hy - 2, hx - 1, hx + 2, col("4a4a52"))
			p.px(hx + 1, hy - 3, bk)
		"mop":
			p.line(Vector2(hand.x + 0.5, hand.y - 6.0), Vector2(hand.x + 1.5, H - 3.5), col("8b6b41"))
			var m := col("d9d8cf")
			p.rect(hx - 1, H - 6, 5, 3, m)
			for x in range(hx - 1, hx + 4, 2):
				p.px(x, H - 4, tone(m, -0.25))
			p.span(H - 6, hx - 1, hx + 3, tone(m, 0.2))
		"flyers":
			var wp := col("fbfaf4")
			p.rect(hx, hy - 4, 3, 4, wp)
			p.rect(hx + 1, hy - 5, 3, 4, wp)
			p.px(hx + 2, hy - 3, col("c9c6bc"))
			p.px(hx + 2, hy - 2, col("e0574b"))
		"box":
			var bx := col("c99459")
			p.rect(hx - 6, hy - 5, 9, 7, bx)
			p.span(hy - 5, hx - 6, hx + 2, tone(bx, 0.22))
			p.rect(hx - 2, hy - 5, 1, 3, col("e5d2a8"))
			p.rect(hx + 2, hy - 4, 1, 6, tone(bx, -0.25))
		"phone":
			p.rect(hx, hy - 5, 3, 5, col("2a2a31"))
			p.rect(hx + 1, hy - 4, 1, 3, col("8fc4e8"))


## The head, done once per character and laid over each frame: hair hanging behind (outlined apart, so a ponytail or
## bun reads), the face, the hair over it in strands, ear, features, hat and anything worn on the face, rimmed.
static func head(c: Dictionary, k: Dictionary) -> Image:
	var p := Paint.new(W, H)
	var back := Paint.new(W, H)
	var hx: float = k.hx
	var hy: float = k.hy
	var r: float = k.r
	var ix := floori(hx)
	var iy := floori(hy)
	var skin := col(c.get("skin", SKIN))
	var hair: Array = c.hair
	var style: String = hair[0]
	var hc := Color(hair[1])
	var hat: Array = c.get("hat", [""])
	match style:
		"pony":
			cloth(back, pv([hx - r + 1.5, hy - 7.0, hx - r - 2.0, hy - 6.5, hx - r - 4.6, hy - 3.5, hx - r - 4.8, hy + 1.5,
					hx - r - 3.4, hy + 6.5, hx - r - 2.6, hy + 8.0, hx - r - 2.2, hy + 4.0, hx - r - 1.4, hy - 1.0, hx - r + 1.0, hy - 3.5]), hc)
			back.rect(ix - int(r) - 1, iy - 7, 2, 2, col("d8504a"))
		"bun":
			orb(back, hx - r - 1.8, hy - 4.5, 3.2, 3.0, hc)
			back.px(ix - int(r) - 3, iy - 6, tone(hc, 0.35))
		"long":
			cloth(back, pv([hx - r - 1.0, hy - 2, hx + 0.5, hy - 2, hx + 1.0, hy + r + 4, hx - 2.0, hy + r + 9, hx - r, hy + r + 8, hx - r - 1.8, hy + r + 3]), hc)
		"bob":
			cloth(back, pv([hx - r - 1.4, hy - 2, hx + 1.8, hy - 2, hx + 2.2, hy + r + 1.5, hx - 1.0, hy + r + 2.5, hx - r, hy + r + 2.0, hx - r - 1.8, hy + r]), hc)
	var shell := Vector4(hx - 0.5, hy - 0.4, r + 0.9, r + 0.2)
	if style in ["bob", "long"]:
		shell = Vector4(hx - 0.6, hy - 0.4, r + 1.5, r + 0.2)
	elif style == "spiky":
		shell = Vector4(hx - 0.6, hy + 0.4, r + 1.0, r - 0.6)
	for t in tuft_pts(style, shell):
		flat(p, t, tone(hc, -0.1))
	if style == "messy":
		for a: float in [188.0, 214.0, 242.0, 272.0, 304.0]:
			var d := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a)))
			orb(p, shell.x + d.x * shell.z * 0.92, shell.y + d.y * shell.w * 0.92, 2.3, 2.0, hc)
		flat(p, pv([hx + 3.0, hy - r + 0.5, hx + r + 2.0, hy - r - 0.5, hx + r - 0.5, hy - r + 3.0]), hc)
	var kind := {}
	for y in range(floori(hy - r - 3), ceili(hy + r + 2)):
		for x in range(floori(hx - r - 3), ceili(hx + r + 3)):
			var u := x + 0.5 - hx
			var v := y + 0.5 - hy
			var face := pow(u / (r + 0.1), 2) + pow(v / (r - 0.1), 2) <= 1.0 or pow((u - 2.4) / 4.9, 2) + pow((v - 4.6) / 4.0, 2) <= 1.0
			var sh := pow((x + 0.5 - shell.x) / shell.z, 2) + pow((y + 0.5 - shell.y) / shell.w, 2) <= 1.0
			if (sh or face) and not bare(style, u, v):
				kind[Vector2i(x, y)] = 2
			elif face:
				kind[Vector2i(x, y)] = 1
	var lit3 := Paint.LIGHT.normalized()
	var hair_tones := [tone(hc, 0.22), hc, tone(hc, -0.2), tone(hc, -0.36), tone(hc, -0.36)]
	var skin_lo := tone(skin, -0.16)
	var crown := Vector2(hx - 1.5, hy - r * 0.7)
	for q: Vector2i in kind:
		if kind[q] == 2:
			var n := Vector2((q.x + 0.5 - shell.x) / shell.z, (q.y + 0.5 - shell.y) / shell.w)
			var lit := Vector3(n.x, n.y, sqrt(maxf(0.0, 1.0 - n.length_squared()))).dot(lit3)
			var band := 0 if lit > 0.92 else (1 if lit > 0.25 else (2 if lit > -0.15 else 3))
			var d := Vector2(q.x + 0.5, q.y + 0.5) - crown
			if d.length() > 2.5 and fposmod(d.angle() * 7.0 / PI, 1.0) < (0.24 if hc.v < 0.6 else 0.12):
				band += 1
			p.px(q.x, q.y, hair_tones[band])
		else:
			var under: bool = kind.get(q + Vector2i(0, -1), 0) == 2
			var bottom := not kind.has(q + Vector2i(0, 1))
			p.px(q.x, q.y, skin_lo if under or bottom else skin)
	var shine := tone(hc, 0.42)
	for x in range(ix - 6, ix + 1):
		var y := iy - int(r * 0.62) + int(absf(x - ix + 3.0) * 0.45)
		if kind.get(Vector2i(x, y), 0) == 2 and (x + y) % 3 != 0:
			p.px(x, y, shine)
	if not style in ["bob", "long"] and hat[0] != "hood":
		p.rect(ix - 3, iy + 1, 2, 3, skin)
		p.px(ix - 2, iy + 2, tone(skin, -0.28))
		p.px(ix - 3, iy + 3, skin_lo)
	var ex := ix + int(r * 0.42)
	var ey := iy + 1
	var nose := front(kind, ey + 2) + 1
	p.px(nose, ey + 2, skin)
	p.px(nose, ey + 3, skin_lo)
	var extras: Array = c.get("face", [])
	face(p, extras, skin, hc, Vector2i(ex, ey), front(kind, ey + 1) - 1, front(kind, ey + 6) - 1)
	hat_on(p, back, hat, hx, hy, r)
	if "shades" in extras:
		var g := col("121216")
		var fe := front(kind, ey + 1)
		p.rect(ex - 2, ey, 4, 3, g)
		p.rect(fe - 2, ey, 3, 3, g)
		p.span(ey, ex + 1, fe, g)
		p.span(ey, ix - 2, ex - 2, g)
		p.px(ex - 1, ey, col("7a8494"))
		p.px(fe - 1, ey, col("5a6474"))
	if "mask" in extras:
		var m := col("f4f4f2")
		flat(p, pv([hx + 0.5, hy + 4.0, hx + r + 1.0, hy + 3.5, hx + r + 0.3, hy + 7.0, hx + 3.0, hy + 8.6, hx, hy + 7.0]), m)
		p.span(iy + 7, ix + 1, ix + int(r) - 1, tone(m, -0.2))
		p.line(Vector2(ix + 0.5, iy + 4.5), Vector2(ix - 2.0, iy + 2.5), tone(m, -0.3))
	var out := rimmed(back.img)
	out.blend_rect(rimmed(p.img), FULL, Vector2i.ZERO)
	return out


## Locks standing out of a hair style's outline (`shell`: centre and radii), as polygons swept back.
static func tuft_pts(style: String, shell: Vector4) -> Array:
	var angles := []
	var reach := 2.2
	match style:
		"short", "pony", "bun":
			angles = [196.0, 238.0]
			reach = 1.4
		"slick":
			angles = [186.0, 210.0, 236.0]
			reach = 1.8
		"spiky":
			angles = [195.0, 222.0, 249.0, 276.0, 303.0, 330.0]
			reach = 1.5
		"messy":
			angles = [200.0, 262.0]
			reach = 2.0
	var out := []
	for a: float in angles:
		var ra := deg_to_rad(a)
		var o := Vector2(shell.x, shell.y)
		var e := Vector2(shell.z, shell.w)
		out.append(PackedVector2Array([o + e * Vector2(cos(ra - 0.24), sin(ra - 0.24)) * 0.9,
				o + e * Vector2(cos(ra - 0.12), sin(ra - 0.12)) + Vector2(cos(ra - 0.6), sin(ra - 0.6)) * reach,
				o + e * Vector2(cos(ra + 0.2), sin(ra + 0.2)) * 0.9]))
	return out


## A three-quarter face turned toward the camera: the near eye big under its lash with a glint (at e), the far eye
## just showing inside the cheek's edge (column `far`), a brow over each, a small mouth (column `mouth`); girls blush,
## grandma squints in a smile, the reviewer scowls; behind sunglasses only the mouth shows.
static func face(p: Paint, extras: Array, skin: Color, hc: Color, e: Vector2i, far: int, mouth: int) -> void:
	if "shades" in extras:
		p.px(mouth, e.y + 6, tone(skin, -0.4))
		return
	var dark := col("2a1d22")
	var iris := col("70483a")
	var lip := tone(skin, -0.4)
	var brow := tone(hc, -0.3) if hc.v > 0.35 else tone(hc, 0.1)
	if "smile" in extras:
		for q: Vector2i in [Vector2i(-1, 2), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 2)]:
			p.px(e.x + q.x, e.y + q.y, dark)
		p.px(far, e.y + 1, dark)
		p.px(far - 1, e.y + 2, dark)
		p.px(e.x - 1, e.y + 3, tone(skin, -0.22))
	else:
		p.span(e.y, e.x - 1, e.x + 1, dark)
		p.rect(e.x, e.y + 1, 2, 2, dark)
		p.px(e.x + 1, e.y + 1, col("fbfbf8"))
		p.px(e.x, e.y + 3, iris)
		p.px(e.x + 1, e.y + 3, tone(iris, 0.25))
		p.px(far, e.y, dark)
		p.px(far, e.y + 1, dark)
		p.px(far, e.y + 2, iris)
	if "frown" in extras:
		p.px(e.x - 1, e.y - 3, brow)
		p.px(e.x, e.y - 2, brow)
		p.px(e.x + 1, e.y - 2, brow)
		p.px(far - 1, e.y - 2, brow)
		p.px(far, e.y - 3, brow)
		p.px(mouth - 1, e.y + 6, lip)
		p.px(mouth, e.y + 6, lip)
	else:
		p.px(e.x, e.y - 2, brow)
		p.px(e.x + 1, e.y - 2, brow)
		p.px(far, e.y - 2, brow)
		p.px(mouth, e.y + 6, lip)
		if "smile" in extras:
			p.px(mouth - 1, e.y + 5, lip)
	if "blush" in extras:
		var pink := skin.lerp(Color("f07c84"), 0.5)
		p.px(e.x - 1, e.y + 4, pink)
		p.px(e.x, e.y + 4, pink)
		p.px(far - 1, e.y + 4, pink)


## The face's front-most pixel on row y.
static func front(kind: Dictionary, y: int) -> int:
	var x := 0
	for q: Vector2i in kind:
		if q.y == y and kind[q] == 1:
			x = maxi(x, q.x)
	return x


## Whether (u, v) from the head's centre shows the face (or nothing) rather than hair, for each hair style: the
## fringe over the forehead with two locks hanging from it, the hairline slanting back over the temple to the ear,
## and the hair behind the ear tapering to the nape.
static func bare(style: String, u: float, v: float) -> bool:
	var lock := 1.3 if (u > 1.4 and u < 2.8) or (u > 5.0 and u < 6.2) else 0.0
	match style:
		"bob", "long":
			return u > 0.0 and v > -2.2 + lock
		"slick":
			return u > -2.3 - maxf(0.0, v - 3.0) * 0.9 and v > -4.0 + maxf(0.0, 1.0 - u) * 0.9
	var back := -2.9 - maxf(0.0, v - 3.0) * 0.9
	return u > back and v > -2.8 + maxf(0.0, 2.5 - u) * 0.5 + lock


## Headwear over the hair (a knot or tails hanging behind go on `back`).
static func hat_on(p: Paint, back: Paint, hat: Array, hx: float, hy: float, r: float) -> void:
	if hat[0] == "":
		return
	var hc := Color(hat[1])
	var acc := Color(hat[2]) if hat.size() > 2 else hc
	var ix := floori(hx)
	var iy := floori(hy)
	var ir := int(r)
	match hat[0]:
		"hardhat", "kidhat":
			orb(p, hx - 0.3, hy - 2.4, r + 1.8, r - 0.1 if hat[0] == "hardhat" else r, hc, iy - 2)
			p.span(iy - 2, ix - ir - 2, ix + ir + 2, tone(hc, -0.22))
			p.span(iy - 3, ix + ir - 1, ix + ir + 3, tone(hc, -0.08))
			p.px(ix + ir + 3, iy - 2, tone(hc, -0.22))
			if hat[0] == "hardhat":
				p.span(iy - 5, ix - ir - 1, ix + ir + 1, acc)
				p.line(Vector2(ix - 1.5, iy - 1.5), Vector2(ix + 0.5, iy + 8.5), col("5a463c"))
		"peaked":
			cloth(p, pv([hx - r - 0.8, hy - 3, hx - r - 1.5, hy - 6.5, hx - 3, hy - 8.8, hx + 6, hy - 8.8, hx + r + 2.5, hy - 6.8,
					hx + r + 1.5, hy - 4.5, hx + r, hy - 3]), hc)
			p.span(iy - 4, ix - ir, ix + ir, tone(hc, -0.4))
			p.span(iy - 3, ix - ir, ix + ir, tone(hc, -0.4))
			p.span(iy - 5, ix + 1, ix + ir, tone(acc, -0.1))
			flat(p, pv([hx + 2, hy - 3.4, hx + r + 3.5, hy - 2.8, hx + r + 2.5, hy - 1.6, hx + 2, hy - 2.2]), col("15151b"))
			p.rect(ix + 4, iy - 8, 2, 2, acc)
			p.px(ix + 4, iy - 8, tone(acc, 0.3))
		"cap":
			orb(p, hx - 0.6, hy - 0.4, r + 1.4, r + 0.4, hc, iy - 2)
			flat(p, pv([hx + 3, hy - 3.4, hx + r + 4.5, hy - 2.6, hx + r + 4, hy - 1.6, hx + 3, hy - 2]), tone(hc, -0.22))
			p.span(iy - 3, ix - ir, ix + 2, tone(hc, -0.15))
		"scarf":
			orb(p, hx - 0.6, hy - 0.3, r + 1.5, r + 0.3, hc, iy - 2, hx - 1.0, 0.4)
			cloth(back, pv([hx - r, hy - 3.0, hx - r - 4.6, hy - 5.0, hx - r - 4.4, hy - 1.5, hx - r - 4.6, hy + 1.5, hx - r - 2.2, hy + 2.6, hx - r + 0.5, hy - 0.5]), tone(hc, -0.06))
			orb(p, hx - r - 0.6, hy - 2.2, 1.8, 1.7, tone(hc, -0.04))
			for x in range(ix - ir - 1, ix + ir + 2):
				var y := iy - 3 + int(maxf(0.0, ix - 1 - x) * 0.4)
				if p.get_px(x, y).a > 0.0:
					p.px(x, y, tone(hc, -0.2))
			p.px(ix - 1, iy - 6, tone(hc, -0.16))
			p.px(ix, iy - 5, tone(hc, -0.16))
		"band", "hachimaki":
			for y: int in [iy - 4, iy - 3]:
				for x in range(ix - ir - 2, ix + ir + 2):
					if p.get_px(x, y).a > 0.0:
						p.px(x, y, tone(hc, 0.15 if y == iy - 4 else -0.1))
			if hat[0] == "hachimaki":
				back.rect(ix - ir - 3, iy - 4, 2, 2, hc)
				back.px(ix - ir - 4, iy - 2, hc)
				back.px(ix - ir - 4, iy - 1, tone(hc, -0.15))
		"beanie":
			orb(p, hx - 0.4, hy - 0.4, r + 1.6, r + 0.4, hc, iy - 1)
			var lo := tone(hc, -0.2)
			p.span(iy - 2, ix - ir - 1, ix + ir + 1, lo)
			p.span(iy - 3, ix - ir - 1, ix + ir + 1, tone(hc, 0.1))
			for x in range(ix - ir, ix + ir + 1, 2):
				p.px(x, iy - 2, tone(hc, -0.32))
			for x in range(ix - 5, ix + 6, 2):
				p.px(x, iy - 7, lo)
		"hood":
			var keep := Rect2i(ix + 1, iy - 3, ir + 4, ir + 6)
			var face: Image = p.img.get_region(keep)
			orb(p, hx - 3.5, hy + 6.0, r - 1.8, 4.2, tone(hc, -0.08))
			orb(p, hx - 0.8, hy - 0.2, r + 2.2, r + 0.5, hc)
			p.img.blit_rect(face, Rect2i(Vector2i.ZERO, keep.size), keep.position)
			var rim := tone(hc, -0.42)
			for y in range(iy - 3, iy + ir + 1):
				p.px(ix + 1, y, rim)
			p.span(iy - 4, ix + 1, ix + ir, tone(hc, 0.12))
			p.span(iy - 3, ix + 2, ix + ir, acc)
			flat(p, pv([hx + 3.0, hy - 3.6, hx + r + 4.0, hy - 3.0, hx + r + 3.5, hy - 2.0, hx + 3.0, hy - 2.2]), acc)

## A costume mascot's big head, done once per chain and laid over each frame, rimmed: turned three-quarters to the
## camera, centred where the rival's sign crops its roundel, with a big near eye and the far eye by the cheek: the
## tanuki's dark mask band over a pale muzzle, the kappa's dish, leafy fringe and beak, the rabbit's tall pink-lined
## ears, the fox's pointed ears and white cheeks round an open grin, the ogre's horns through its afro over a toothy
## grin, the robot's visor with two glowing eyes under its antenna.
static func mascot_head(id: String) -> Image:
	var p := Paint.new(W, H)
	var m: Dictionary = MASCOT[id]
	var fur := Color(m.fur)
	var pale := Color(m.pale)
	var dark := Color(m.dark)
	var trim := Color(m.trim)
	var ink := col("23161c")
	match id:
		"tanuki":
			for e: Vector2 in [Vector2(10.5, 8.0), Vector2(23.0, 7.0)]:
				orb(p, e.x, e.y, 3.1, 3.0, fur)
				orb(p, e.x + 0.2, e.y + 0.5, 1.5, 1.5, dark)
			orb(p, 17.5, 15.0, 10.5, 9.2, fur)
			orb(p, 15.0, 9.8, 4.5, 2.2, tone(fur, 0.14))
			orb(p, 23.5, 19.4, 5.4, 3.5, pale)
			flat(p, pv([8.5, 15.0, 12.0, 11.8, 18.5, 11.0, 25.5, 11.0, 28.5, 13.2, 28.2, 15.8, 24.0, 16.8, 20.5, 16.4, 15.5, 17.6, 10.5, 18.0]), dark)
			eye(p, Vector2(20.5, 14.0), 2.3, 2.4, col("f8efd6"), ink)
			eye(p, Vector2(26.0, 14.0), 1.4, 2.0, col("f8efd6"), ink)
			orb(p, 27.8, 18.2, 1.7, 1.3, ink)
			for q: Vector2i in [Vector2i(22, 20), Vector2i(23, 21), Vector2i(24, 21), Vector2i(25, 21), Vector2i(26, 20)]:
				p.px(q.x, q.y, tone(pale, -0.45))
		"kappa":
			orb(p, 17.5, 15.0, 10.0, 9.2, fur)
			var leaf := tone(fur, -0.32)
			for y in range(5, 13):
				for x in range(7, 29):
					if p.get_px(x, y).a > 0.0 and y < 10 + (1 if x % 3 == 0 else 0) - (1 if x % 3 == 1 else 0):
						p.px(x, y, leaf if (x + y) % 4 else tone(leaf, 0.25))
			orb(p, 17.5, 6.6, 6.8, 2.2, pale.lerp(Color("d6dcc8"), 0.7))
			p.span(8, 12, 23, col("a9b39a"))
			eye(p, Vector2(20.5, 13.2), 1.9, 2.4, col("fbfbf8"), ink)
			eye(p, Vector2(25.6, 13.2), 1.2, 2.0, col("fbfbf8"), ink)
			p.rect(18, 17, 2, 1, col("f29a9a"))
			flat(p, pv([23.5, 16.2, 29.5, 15.4, 31.4, 17.0, 29.6, 19.8, 24.0, 20.6]), trim)
			p.span(18, 25, 30, tone(trim, -0.5))
			p.span(19, 25, 29, tone(trim, -0.22))
			p.span(16, 25, 28, tone(trim, 0.25))
		"usagi":
			for e: Vector2 in [Vector2(14.5, 9.6), Vector2(20.0, 9.2)]:
				orb(p, e.x, e.y, 2.5, 5.8, fur)
				orb(p, e.x + 0.3, e.y + 0.8, 1.1, 4.2, pale)
			orb(p, 17.5, 17.5, 8.5, 7.2, fur)
			eye(p, Vector2(20.0, 16.6), 1.5, 2.0, col("fbfbf8"), ink)
			eye(p, Vector2(24.2, 16.6), 1.0, 1.8, col("fbfbf8"), ink)
			p.px(25, 18, pale)
			p.px(26, 18, pale)
			p.px(24, 20, tone(dark, -0.35))
			p.px(25, 20, tone(dark, -0.35))
			p.px(19, 19, pale.lerp(fur, 0.45))
			p.px(18, 19, pale.lerp(fur, 0.45))
		"kitsune":
			for e: Array in [[Vector2(8.5, 12.5), Vector2(10.5, 4.2), Vector2(15.5, 8.5)], [Vector2(19.5, 7.5), Vector2(24.5, 4.2), Vector2(26.5, 11.5)]]:
				cloth(p, PackedVector2Array(e), fur)
				var c0: Vector2 = (e[0] + e[1] + e[2]) / 3.0
				flat(p, PackedVector2Array([c0.lerp(e[0], 0.5), c0.lerp(e[1], 0.6), c0.lerp(e[2], 0.5)]), pale)
			orb(p, 17.5, 15.5, 10.0, 8.8, fur)
			orb(p, 22.5, 19.2, 7.0, 4.6, pale)
			eye(p, Vector2(19.8, 13.8), 1.9, 2.4, col("fbfbf8"), ink)
			eye(p, Vector2(25.2, 13.8), 1.1, 2.0, col("fbfbf8"), ink)
			orb(p, 29.0, 17.2, 1.5, 1.2, ink)
			flat(p, pv([23.0, 19.5, 28.0, 19.0, 27.0, 23.0, 24.0, 23.0]), tone(dark, 0.1))
			p.rect(24, 21, 2, 2, col("f07a8a"))
		"oni":
			var afro := Paint.new(W, H)
			orb(afro, 16.0, 13.8, 10.5, 8.3, dark)
			for o: Vector3 in [Vector3(6.5, 15.0, 3.0), Vector3(7.5, 19.5, 3.0), Vector3(12.0, 21.0, 3.0), Vector3(6.5, 10.5, 2.6)]:
				orb(afro, o.x, o.y, o.z, o.z, dark)
			for y in H:
				for x in W:
					if afro.get_px(x, y).a > 0.0 and (x * 3 + y * 5) % 7 < 2 and (x + y) % 2 == 0:
						afro.px(x, y, tone(afro.get_px(x, y), 0.2))
			p.img.blend_rect(afro.img, FULL, Vector2i.ZERO)
			for h: Array in [[10.0, 8.8, 12.5, 3.8, 15.0, 7.8], [19.5, 7.5, 22.0, 3.8, 24.5, 8.5]]:
				cloth(p, pv(h), pale)
				p.span(int(h[1]) - 1, int(h[0]) + 1, int(h[4]) - 1, tone(pale, -0.3))
			orb(p, 21.5, 17.5, 7.2, 6.8, fur)
			for o: Vector3 in [Vector3(17.5, 11.0, 3.2), Vector3(22.0, 10.4, 3.0), Vector3(26.0, 11.4, 2.2)]:
				orb(p, o.x, o.y, o.z, o.z, dark)
			p.span(13, 18, 21, ink)
			p.span(13, 24, 26, ink)
			eye(p, Vector2(20.0, 15.6), 1.4, 1.7, col("fbfbf8"), ink)
			eye(p, Vector2(25.2, 15.6), 1.0, 1.6, col("fbfbf8"), ink)
			p.span(18, 19, 28, ink)
			p.span(19, 20, 27, col("fbfbf8"))
			p.span(20, 21, 26, col("fbfbf8"))
			p.px(19, 19, ink)
			p.px(28, 19, ink)
			p.px(20, 20, ink)
			p.px(27, 20, ink)
			p.span(21, 21, 26, ink)
			for x: int in [22, 24, 26]:
				p.px(x, 19, col("d8d2c8"))
		"mega":
			p.rect(17, 6, 1, 3, dark)
			orb(p, 17.6, 5.2, 1.6, 1.5, trim)
			orb(p, 17.5, 16.0, 10.0, 8.6, pale)
			orb(p, 9.5, 16.5, 3.0, 3.2, tone(pale, 0.12))
			orb(p, 9.3, 16.5, 1.5, 1.6, tone(pale, -0.3))
			flat(p, pv([15.5, 11.0, 25.5, 11.0, 27.6, 13.5, 27.4, 19.5, 25.5, 21.8, 16.0, 21.8, 14.2, 19.5, 14.2, 13.0]), dark)
			p.span(11, 16, 24, tone(dark, 0.32))
			p.px(15, 12, tone(dark, 0.32))
			var glow := Color(trim).lerp(dark, 0.55)
			for e: Rect2i in [Rect2i(18, 14, 2, 4), Rect2i(23, 14, 2, 4)]:
				p.rect(e.position.x - 1, e.position.y - 1, e.size.x + 2, e.size.y + 2, glow)
				p.rect(e.position.x, e.position.y, e.size.x, e.size.y, trim)
				p.px(e.position.x, e.position.y, tone(trim, 0.45))
	return rimmed(p.img)


## A cartoon eye: a round white (or fur-coloured) eye at c with a dark pupil toward the front and a glint.
static func eye(p: Paint, c: Vector2, rx: float, ry: float, white: Color, ink: Color) -> void:
	orb(p, c.x, c.y, rx, ry, white)
	var px := floori(c.x + rx * 0.2)
	var top := floori(c.y - ry * 0.55)
	var h := maxi(2, roundi(ry * 1.3))
	p.rect(px - (1 if rx > 1.8 else 0), top, 2 if rx > 1.1 else 1, h, ink)
	p.px(px - (1 if rx > 1.8 else 0), top, col("fbfbf8"))


## A mascot's frame: its tail or shell behind, the far leg and arm, the stout body in its costume, belly to the
## camera (the tanuki's open red vest, the rabbit's polo shirt, the fox's bandana, the ogre's tiger-skin loincloth,
## the robot's chest panel), the head, and the near arm raised in a wave at its side, clear of the face.
static func mascot(id: String, f: int, top: Image) -> Paint:
	var m: Dictionary = MASCOT[id]
	var g: Array = GAIT[f]
	var b: float = g[0]
	var fur := Color(m.fur)
	var pale := Color(m.pale)
	var dark := Color(m.dark)
	var trim := Color(m.trim)
	var limbs := tone(fur, -0.25) if id == "tanuki" else fur
	var p := Paint.new(W, H)
	var l := Paint.new(W, H)
	var iyb := int(b)
	match id:
		"tanuki":
			orb(l, 6.0, 33.0 + b, 5.0, 6.5, fur)
			orb(l, 4.5, 38.5 + b, 2.6, 2.4, dark)
			for y in range(26, 40):
				if (y - 26) % 5 >= 3:
					for x in range(0, 12):
						if l.get_px(x, y + iyb).a > 0.0:
							l.px(x, y + iyb, tone(dark, 0.15 if (y - 26) % 5 == 3 else 0.0))
		"kitsune":
			orb(l, 6.5, 34.5 + b, 5.0, 7.0, fur)
			orb(l, 4.0, 40.0 + b, 3.0, 2.6, pale)
		"usagi":
			orb(l, 9.5, 36.0 + b, 2.4, 2.4, fur)
	if not l.img.is_invisible():
		stick(p, l)
	l = Paint.new(W, H)
	stub(l, g[3], g[4], b, false, limbs)
	limb(l, Vector2(14.0, 27.0 + b), Vector2(12.0 - g[5] * 0.25, 34.5 + b), 2.2, tone(limbs, -0.22))
	orb(l, 12.0 - g[5] * 0.25, 35.0 + b, 2.2, 2.2, tone(dark if id == "tanuki" else limbs, -0.22))
	if id == "kappa":
		orb(l, 10.0, 32.0 + b, 5.2, 8.0, dark)
		for y: int in [28, 32, 36]:
			l.span(y + iyb, 6, 13, tone(dark, 0.35))
		for x: int in [8, 11]:
			for y in range(26, 39):
				if l.get_px(x, y + iyb).a > 0.0 and (y + x) % 4 != 0:
					l.px(x, y + iyb, tone(dark, 0.35))
	stick(p, l)
	l = Paint.new(W, H)
	stub(l, g[1], g[2], b, true, limbs)
	var by := 32.0 + b
	match id:
		"tanuki":
			orb(l, 17.5, by, 7.8, 8.5, fur)
			for y in range(25, 38):
				for x in range(9, 27):
					if l.get_px(x, y + iyb).a > 0.0 and (x < 14 or x > 24):
						l.px(x, y + iyb, tone(trim, 0.15 if x < 11 else (-0.2 if x > 25 else 0.0)))
			orb(l, 19.5, by + 1.0, 5.0, 6.4, pale)
			for y in range(38, 41):
				for x in range(9, 27):
					if l.get_px(x, y + iyb).a > 0.0:
						l.px(x, y + iyb, tone(fur, -0.1 if y == 38 else -0.2))
		"kappa":
			orb(l, 17.5, by, 7.8, 8.5, fur)
			orb(l, 20.0, by + 0.5, 4.6, 6.5, pale)
			for y: int in [30, 33, 36]:
				for x in range(16, 26):
					if pow((x + 0.5 - 20.0) / 4.2, 2) + pow((y + 0.5 - by - 0.5) / 6.0, 2) < 1.0:
						l.px(x, y + iyb, tone(pale, -0.22))
		"usagi":
			orb(l, 17.5, by, 7.5, 8.5, fur)
			for y in range(25, 36):
				for x in range(9, 27):
					if l.get_px(x, y + iyb).a > 0.0:
						l.px(x, y + iyb, tone(trim, 0.15 if x < 12 else (-0.2 if x > 23 else 0.0)))
			l.rect(19, 25 + iyb, 5, 1, col(WHITE))
			l.px(21, 26 + iyb, col(WHITE))
			l.px(22, 28 + iyb, col(WHITE))
			l.px(22, 31 + iyb, col(WHITE))
		"kitsune":
			orb(l, 17.5, by, 7.8, 8.5, fur)
			orb(l, 20.0, by + 1.5, 4.8, 6.0, pale)
			flat(l, pv([10.5, 24.0 + b, 26.5, 24.0 + b, 19.0, 33.5 + b]), trim)
			l.span(24 + iyb, 12, 25, tone(trim, 0.25))
			for q: Vector2i in [Vector2i(15, 27), Vector2i(19, 26), Vector2i(22, 28), Vector2i(18, 30)]:
				l.px(q.x, q.y + iyb, tone(trim, 0.4))
		"oni":
			orb(l, 17.5, by, 7.8, 8.5, fur)
			var lo := tone(fur, -0.25)
			l.span(28 + iyb, 18, 23, lo)
			l.px(20, 31 + iyb, lo)
			l.px(20, 33 + iyb, lo)
			for y in range(35, 41):
				for x in range(8, 28):
					if l.get_px(x, y + iyb).a > 0.0 or (y == 40 and x % 2 == 0 and x > 9 and x < 26):
						l.px(x, y + iyb, col("23161c") if (x + y) % 4 == 0 else tone(trim, 0.15 if x < 12 else 0.0))
		"mega":
			orb(l, 17.5, by, 7.8, 8.5, fur)
			l.rect(17, 27 + iyb, 6, 6, tone(fur, 0.3))
			l.rect(18, 28 + iyb, 2, 2, trim)
			l.px(21, 31 + iyb, col("e05a4e"))
			l.span(37 + iyb, 10, 25, tone(fur, -0.3))
	stick(p, l)
	p.img.blend_rect(top, FULL, Vector2i(0, iyb))
	l = Paint.new(W, H)
	var wob: float = [0.0, 0.6, 0.0, -0.6, 0.0][f]
	var s := Vector2(21.5, 27.5 + b)
	var e := Vector2(26.5, 30.5 + b)
	var hnd := Vector2(31.0 + wob, 23.2 + b)
	limb(l, s, e, 2.1, limbs)
	limb(l, e, hnd, 1.8, limbs)
	if id == "usagi":
		limb(l, s, s.lerp(e, 0.6), 2.5, trim)
	if id == "mega":
		orb(l, e.x, e.y, 1.6, 1.6, dark)
	orb(l, hnd.x, hnd.y, 2.2, 2.1, dark if id == "tanuki" else limbs)
	stick(p, l)
	return p


## A mascot's stubby leg and foot.
static func stub(p: Paint, reach: float, lift: float, b: float, near: bool, c: Color) -> void:
	var shade := 0.0 if near else -0.22
	var hip := Vector2(17.5 + (2.5 if near else -2.5), 37.0 + b)
	var foot := Vector2(hip.x + reach * 0.55, H - 5.5 - lift * 0.8)
	limb(p, hip, foot, 2.8, tone(c, shade))
	orb(p, foot.x + 1.0, foot.y + 1.6, 3.4, 1.9, tone(c, shade - 0.08))
