extends Control
## Draws one store as a 640x360 side-view stage and replays a simulated day's customers over it.

signal finished

const Sim := preload("res://sim.gd")
const DUR := 10.0
const SPEED := 230.0
const FEET := 352.0
const MAX_SHOWN := 20
const PACE := 0.7  # share of DUR over which the day's customers arrive
const LAYOUT := {
	"konbini": {"bg": "bg_konbini", "gondolas": [190, 290, 390], "rows": [244, 280], "top": 236, "counter": 515, "clerk": 572, "clerk_y": 133},
	"super": {"bg": "bg_super", "gondolas": [150, 245, 340, 435], "rows": [214, 250, 286], "top": 206, "counter": 490, "clerk": 585, "clerk_y": 190},
}

var tex := {}
var kind := "konbini"
var slots: Array = []
var stock0: Array = []
var stock1: Array = []
var queue: Array = []
var people: Array = []
var floaters: Array = []
var t := 0.0
var playing := false
var paused := false


func show_store(store: Dictionary) -> void:
	kind = store.kind
	slots = store.slots
	stock0 = []
	playing = false
	people.clear()
	floaters.clear()
	queue_redraw()


func slot_pos(i: int) -> Vector2:
	var L: Dictionary = LAYOUT[kind]
	var rows: int = L.rows.size()
	return Vector2(L.gondolas[i / rows], L.rows[i % rows])


func play(events: Array, pre_stock: Array, post_stock: Array) -> void:
	stock0 = pre_stock
	stock1 = post_stock
	t = 0.0
	people.clear()
	floaters.clear()
	var step := maxi(1, ceili(events.size() / float(MAX_SHOWN)))
	queue = []
	for i in range(0, events.size(), step):
		queue.append(events[i])
	playing = true


func skip() -> void:
	if playing:
		playing = false
		people.clear()
		queue.clear()
		stock0 = []
		queue_redraw()
		finished.emit()


func spawn(cu: Dictionary) -> void:
	var L: Dictionary = LAYOUT[kind]
	var path := []
	if cu.walkout:
		path = [[110.0 + randf() * 40.0, 0.8, "queue"], [-50.0, 0.0, ""]]
	else:
		var gx: float = slot_pos(cu.slot).x if cu.slot >= 0 else L.gondolas.pick_random()
		var bub := ""
		if cu.buy.size():
			bub = "buy"
		elif cu.miss.size():
			bub = "miss"
		path.append([gx + randf_range(-18, 18), 0.6, bub])
		if cu.spent > 0:
			path.append([float(L.counter) + randf_range(-10, 10), 0.45, "pay"])
		path.append([-50.0, 0.0, ""])
	people.append({"cu": cu, "x": -40.0, "path": path, "wait": -1.0, "flip": false, "bob": randf() * 6.0})


func _process(delta: float) -> void:
	if not playing or paused:
		return
	t += delta
	while queue.size() and queue[0].t * DUR * PACE <= t:
		spawn(queue.pop_front())
	for p in people:
		var step: Array = p.path[0]
		if p.wait >= 0.0:
			p.wait -= delta
			if p.wait < 0.0:
				p.path.pop_front()
			continue
		var dx: float = step[0] - p.x
		p.flip = dx < 0
		p.bob += delta * 12.0
		var v := SPEED * (2.0 if p.path.size() == 1 else 1.0)
		if absf(dx) <= v * delta:
			p.x = step[0]
			p.wait = step[1]
			if step[2] == "pay":
				floaters.append({"text": "+¥" + Sim.money(p.cu.spent), "x": p.x, "y": FEET - 110.0, "life": 1.2})
			if step[1] <= 0.0:
				p.path.pop_front()
				p.wait = -1.0
		else:
			p.x += signf(dx) * v * delta
	people = people.filter(func(p): return p.path.size() > 0)
	for f in floaters:
		f.y -= 30.0 * delta
		f.life -= delta
	floaters = floaters.filter(func(f): return f.life > 0.0)
	if queue.is_empty() and people.is_empty() and t > 1.0:
		playing = false
		stock0 = []
		finished.emit()
	queue_redraw()


func progress() -> float:
	return clampf(t / (DUR * PACE), 0.0, 1.0) if playing else 0.0


func shown_qty(i: int) -> int:
	if stock0.is_empty():
		return slots[i].qty
	return roundi(lerpf(stock0[i], stock1[i], progress()))


func _draw() -> void:
	var L: Dictionary = LAYOUT[kind]
	var font := get_theme_default_font()
	draw_texture_rect(tex[L.bg], Rect2(0, 0, 640, 360), false)
	# gondolas
	var rows: int = L.rows.size()
	for g in L.gondolas.size():
		var cx: float = L.gondolas[g]
		draw_rect(Rect2(cx - 46, L.top - 4, 92, 326 - L.top), Color("3b3f52"))
		draw_rect(Rect2(cx - 42, L.top, 84, 318 - L.top), Color("e9e4d6"))
		for r in rows:
			var i: int = g * rows + r
			var y: float = L.rows[r]
			draw_rect(Rect2(cx - 42, y + 32, 84, 4), Color("8d8a80"))
			if i >= slots.size() or slots[i].pid < 0:
				continue
			var q := shown_qty(i)
			var src := Rect2(slots[i].pid * 32, 0, 32, 32)
			var n := mini(3, ceili(q / 10.0))
			for k in n:
				draw_texture_rect_region(tex.products, Rect2(cx - 40 + k * 26, y, 32, 32), src)
			if q == 0:
				draw_texture_rect_region(tex.products, Rect2(cx - 16, y, 32, 32), src, Color(1, 1, 1, 0.25))
				draw_string(font, Vector2(cx - 42, y + 21), "EMPTY", HORIZONTAL_ALIGNMENT_CENTER, 84, 12, Color("d64545"))
		draw_rect(Rect2(cx - 46, 318, 92, 8), Color("3b3f52"))
	# clerk (upper body only, behind the counter)
	sprite(Rect2(7 * 36, 0, 36, 30), L.clerk, L.clerk_y, Vector2(72, 60), true)
	# customers
	for p in people:
		var a: int = p.cu.a
		var by := 0.0 if p.wait >= 0.0 else absf(sin(p.bob)) * -3.0
		sprite(Rect2(a * 36, 0, 36, 48), p.x, FEET - 96 + by, Vector2(72, 96), p.flip)
		if p.wait >= 0.0:
			bubble(p, font)
	for f in floaters:
		draw_string_outline(font, Vector2(f.x - 30, f.y), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.WHITE)
		draw_string(font, Vector2(f.x - 30, f.y), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("2f9e5b"))
	# time of day
	var hour := 6.0 + progress() * 24.0
	var night := clampf((hour - 18.0) / 4.0, 0.0, 1.0) * (1.0 - clampf((hour - 28.0) / 2.0, 0.0, 1.0))
	if night > 0.0:
		draw_rect(Rect2(0, 0, 640, 360), Color(0.06, 0.07, 0.25, 0.38 * night))
	if playing:
		var clock := "%02d:00  %s" % [int(hour) % 24, Sim.BLOCKS[mini(5, int(progress() * 6.0))]]
		draw_rect(Rect2(8, 8, 150, 24), Color(0.17, 0.18, 0.26, 0.85))
		draw_string(font, Vector2(16, 26), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func sprite(src: Rect2, cx: float, top: float, sz: Vector2, flip: bool) -> void:
	draw_set_transform(Vector2(cx, 0), 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	draw_texture_rect_region(tex.people, Rect2(-sz.x / 2, top, sz.x, sz.y), src)
	draw_set_transform(Vector2.ZERO)


func bubble(p: Dictionary, font: Font) -> void:
	var step: Array = p.path[0]
	var kind_b: String = step[2]
	if kind_b == "" or kind_b == "pay":
		return
	var r := Rect2(p.x - 20, FEET - 140, 40, 38)
	var edge := Color("d64545") if kind_b != "buy" else Color("2f9e5b")
	draw_rect(r, Color.WHITE)
	draw_rect(r, edge, false, 2.0)
	if kind_b == "queue":
		draw_string(font, r.position + Vector2(8, 26), "...", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, edge)
		return
	var pid: int = p.cu.buy[0] if kind_b == "buy" else p.cu.miss[0]
	draw_texture_rect_region(tex.products, Rect2(r.position + Vector2(4, 3), Vector2(32, 32)), Rect2(pid * 32, 0, 32, 32), Color(1, 1, 1, 1.0 if kind_b == "buy" else 0.55))
	if kind_b == "miss":
		draw_string_outline(font, r.position + Vector2(26, 34), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.WHITE)
		draw_string(font, r.position + Vector2(26, 34), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, edge)
