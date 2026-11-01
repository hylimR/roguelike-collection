extends Control
## Konbini Empire UI: builds every control in code and drives Sim through prep -> day -> report -> draft.

const Sim := preload("res://sim.gd")
const StoreView := preload("res://store_view.gd")

const INK := Color("2b2d42")
const PAPER := Color("f7f3e8")
const GROUND := Color("e8e1cf")
const LINE := Color("cfc8b4")
const GREEN := Color("2f9e5b")
const ORANGE := Color("e07b1a")
const RED := Color("d64545")
const MUTED := Color("7d7768")
const WEEKDAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const TIER_COLOR := [Color("2f7fd6"), INK, Color("c2410c")]

var sim := Sim.new()
var tex := {}
var view: StoreView
var cur := 0
var phase := "prep"
var report := {}
var modal: Control
var modal_keys := {}
var best := ConfigFile.new()

var lbl_day: Label
var lbl_weather: Label
var lbl_cash: Label
var lbl_rep: Label
var lbl_rent: Label
var seed_btn: Button
var shelf_title: Label
var slot_box: VBoxContainer
var tabs: HBoxContainer
var info: Label
var perk_row: HBoxContainer
var open_btn: Button
var grow_btn: Button
var arrange_btn: Button
var foot: Label
var arranging := false


func _ready() -> void:
	for n in ["products", "people", "perks", "stores", "decor", "bg_konbini", "bg_super"]:
		tex[n] = load("res://art/%s.png" % n)
	theme = make_theme()
	best.load("user://best.cfg")
	build()
	new_run("")


# ---------- theme & widget helpers ----------

func box(bg: Color, border: Color, bw := 2, pad := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(pad)
	return s


func make_theme() -> Theme:
	var th := Theme.new()
	var f: FontFile = load("res://fonts/kenpixel.ttf")
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var jp := SystemFont.new()  # the pixel font has no yen sign
	jp.font_names = PackedStringArray(["MS Gothic", "Yu Gothic", "Noto Sans CJK JP", "DejaVu Sans"])
	jp.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var fb: Array[Font] = [jp]
	f.fallbacks = fb
	th.default_font = f
	th.default_font_size = 12
	th.set_stylebox("normal", "Button", box(PAPER, INK))
	th.set_stylebox("hover", "Button", box(Color("e3f3e8"), INK))
	th.set_stylebox("pressed", "Button", box(Color("c5e6d0"), INK))
	th.set_stylebox("disabled", "Button", box(Color("ebe6da"), LINE))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		th.set_color(c, "Button", INK)
	th.set_color("font_disabled_color", "Button", Color("a39d8e"))
	th.set_stylebox("panel", "PanelContainer", box(PAPER, INK, 2, 10))
	th.set_color("font_color", "Label", INK)
	th.set_stylebox("normal", "LineEdit", box(Color.WHITE, INK))
	th.set_stylebox("focus", "LineEdit", box(Color.WHITE, GREEN))
	th.set_color("font_color", "LineEdit", INK)
	th.set_stylebox("panel", "TooltipPanel", box(INK, INK, 1, 6))
	th.set_color("font_color", "TooltipLabel", PAPER)
	return th


func label(text: String, color := INK, px := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if px > 0:
		l.add_theme_font_size_override("font_size", px)
	return l


func button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func atlas(sheet: String, i: int, cell: Vector2i) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = tex[sheet]
	t.region = Rect2(i * cell.x, 0, cell.x, cell.y)
	return t


func picture(sheet: String, i: int, cell: Vector2i, min_size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = atlas(sheet, i, cell)
	r.custom_minimum_size = min_size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


func yen(v: int) -> String:
	return "¥" + Sim.money(v)


# ---------- layout ----------

func build() -> void:
	var bg := ColorRect.new()
	bg.color = GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var bar := ColorRect.new()
	bar.color = INK
	bar.position = Vector2.ZERO
	bar.size = Vector2(960, 32)
	add_child(bar)
	var hb := HBoxContainer.new()
	hb.position = Vector2(10, 0)
	hb.size = Vector2(940, 32)
	hb.add_theme_constant_override("separation", 22)
	bar.add_child(hb)
	lbl_day = label("", PAPER, 16)
	lbl_weather = label("", Color("9fd8ff"), 16)
	lbl_cash = label("", Color("ffd36b"), 16)
	lbl_rep = label("", Color("b8f2c9"), 16)
	lbl_rent = label("", PAPER, 16)
	for l in [lbl_day, lbl_weather, lbl_cash, lbl_rep, lbl_rent]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	seed_btn = button("", show_new_run, "Start a new run (you can type a seed)")
	seed_btn.custom_minimum_size.y = 26
	seed_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(seed_btn)

	view = StoreView.new()
	view.tex = tex
	view.position = Vector2(0, 32)
	view.size = Vector2(640, 360)
	view.clip_contents = true
	view.sim = sim
	view.finished.connect(show_report)
	view.changed.connect(refresh_ui)
	add_child(view)

	var bottom := VBoxContainer.new()
	bottom.position = Vector2(10, 400)
	bottom.size = Vector2(620, 132)
	bottom.add_theme_constant_override("separation", 6)
	add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	bottom.add_child(row)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tabs)
	perk_row = HBoxContainer.new()
	perk_row.add_theme_constant_override("separation", 2)
	row.add_child(perk_row)
	arrange_btn = button("ARRANGE", toggle_arrange, "Move shelves and the counter, buy decorations  [E]")
	row.add_child(arrange_btn)
	grow_btn = button("EXPAND", show_grow, "Renovate, open branches, build the flagship  [G]")
	row.add_child(grow_btn)
	open_btn = button("  OPEN SHOP  >  ", open_shop, "Run today's trading  [Space]")
	open_btn.add_theme_stylebox_override("normal", box(Color("ffe7c2"), INK))
	open_btn.add_theme_stylebox_override("hover", box(Color("ffd89a"), INK))
	row.add_child(open_btn)
	info = label("")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(620, 56)
	bottom.add_child(info)

	var side := PanelContainer.new()
	side.position = Vector2(640, 32)
	side.size = Vector2(320, 508)
	side.add_theme_stylebox_override("panel", box(PAPER, INK, 2, 8))
	add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	side.add_child(sv)
	shelf_title = label("", INK, 16)
	sv.add_child(shelf_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	slot_box = VBoxContainer.new()
	slot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_box.add_theme_constant_override("separation", 4)
	scroll.add_child(slot_box)
	foot = label("", MUTED)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.custom_minimum_size.x = 296
	sv.add_child(foot)


# ---------- run flow ----------

func new_run(seed_str: String) -> void:
	seed_str = seed_str.strip_edges()
	if seed_str == "":
		const CH := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
		for i in 6:
			seed_str += CH[randi() % CH.length()]
	sim.start(seed_str)
	cur = 0
	phase = "prep"
	arranging = false
	view.edit = false
	close_modal()
	refresh()


func refresh() -> void:
	refresh_ui()
	view.show_store(sim.stores[cur], cur)


func refresh_ui() -> void:
	var prep := phase == "prep"
	lbl_day.text = "DAY %d  %s" % [sim.day, WEEKDAYS[(sim.day - 1) % 7]]
	lbl_weather.text = sim.weather.name.to_upper()
	lbl_cash.text = yen(sim.cash)
	lbl_rep.text = "REP %d" % roundi(sim.rep)
	var dr := sim.days_to_rent()
	lbl_rent.text = "RENT %s %s" % [yen(sim.weekly_rent()), "TONIGHT" if dr == 0 else "IN %dD" % dr]
	lbl_rent.add_theme_color_override("font_color", RED.lightened(0.3) if dr <= 1 and sim.cash < sim.weekly_rent() + 20000 else PAPER)
	seed_btn.text = "SEED %s" % sim.seed_text

	for c in tabs.get_children():
		c.queue_free()
	for i in sim.stores.size():
		var si: Dictionary = sim.stores[i]
		var b := button("%d %s" % [i + 1, Sim.STORE[si.kind].name.to_upper()], select_store.bind(i), "Switch store  [Tab]")
		if i == cur:
			b.add_theme_stylebox_override("normal", box(Color("c5e6d0"), INK))
		tabs.add_child(b)
	grow_btn.disabled = not prep or arranging
	open_btn.disabled = not prep
	arrange_btn.disabled = not prep
	arrange_btn.text = "DONE" if arranging else "ARRANGE"

	var st: Dictionary = sim.stores[cur]
	var def: Dictionary = Sim.STORE[st.kind]
	for c in slot_box.get_children():
		c.queue_free()
	if arranging:
		arrange_panel(st)
	else:
		shelf_title.text = "%s #%d  -  %d SHELVES" % [def.name.to_upper(), cur + 1, def.slots]
		foot.text = "Tap a price tag to change it. Items marked * spoil: leftovers are binned at close."
		for i in st.slots.size():
			slot_box.add_child(slot_row(i, st.slots[i], prep))

	var lines := ["%s. %s" % [sim.weather.name, weather_hint()]]
	if sim.day == 1:
		lines.push_front("Stock the shelves, then open the shop. Pay rent every Sunday or the run ends. Grow: supermarket, branches, flagship.")
	if sim.event.id != "none":
		lines.append(sim.event_text())
	if sim.morning_note != "":
		lines.append(sim.morning_note)
	if sim.misses.size():
		lines.append("Yesterday customers asked for: " + top_misses(sim.misses, 4))
	info.text = "\n".join(lines)

	for c in perk_row.get_children():
		c.queue_free()
	for p in Sim.PERKS:
		var n := sim.has(p.id)
		if n == 0:
			continue
		var pic := picture("perks", p.frame, Vector2i(40, 40), Vector2(28, 28))
		pic.tooltip_text = "%s x%d: %s" % [p.name, n, sim.perk_desc(p)]
		pic.mouse_filter = Control.MOUSE_FILTER_PASS
		perk_row.add_child(pic)


func arrange_panel(st: Dictionary) -> void:
	var ap := Sim.appeal(st)
	shelf_title.text = "ARRANGE #%d  -  APPEAL %d (+%d%%)" % [cur + 1, ap, ap * 2]
	foot.text = "Right-click or Esc cancels. Customers need a path to every shelf and the till: blocked spots show red. Selling refunds half."
	var ct: String = view.carried_type()
	var msg := "Click a shelf, the counter or a decoration to pick it up."
	if ct == "new":
		msg = "Placing a %s: click a free floor tile." % Sim.DECOR[view.carry.new].name.to_lower()
	elif ct != "":
		msg = "Moving the %s: click where it goes." % ("shelf unit" if ct == "gondola" else ct)
	var m := label(msg, INK)
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.custom_minimum_size.x = 290
	slot_box.add_child(m)
	if ct != "":
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		h.add_child(button("CANCEL  [Esc]", view.cancel_carry))
		if ct == "decor":
			var o: Dictionary = st.objects[view.carry.idx]
			h.add_child(button("SELL  +" + yen(Sim.DECOR[o.id].cost / 2), view.sell_carried))
		slot_box.add_child(h)
	for i in Sim.DECOR.size():
		var d: Dictionary = Sim.DECOR[i]
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", box(Color.WHITE, LINE, 1, 4))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		panel.add_child(h)
		h.add_child(picture("decor", i, Vector2i(48, 48), Vector2(40, 40)))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		h.add_child(v)
		v.add_child(label(d.name, INK, 14))
		var dl := label(d.desc, MUTED)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size.x = 160
		v.add_child(dl)
		var b := button("BUY\n" + yen(d.cost), view.carry_new.bind(i))
		b.custom_minimum_size.x = 70
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = sim.cash < d.cost
		h.add_child(b)
		slot_box.add_child(panel)


func toggle_arrange() -> void:
	if phase != "prep" or modal:
		return
	arranging = not arranging
	view.set_edit(arranging)
	refresh_ui()


func weather_hint() -> String:
	var m: Dictionary = sim.weather.mult
	if m.is_empty():
		return "A normal day."
	var up := []
	for id in m:
		if m[id] > 1.0:
			up.append(Sim.P[sim.idx[id]].name)
	return "Selling well: " + ", ".join(up) + "."


func top_misses(m: Dictionary, n: int) -> String:
	var keys := m.keys()
	keys.sort_custom(func(a, b): return m[a] > m[b])
	return ", ".join(keys.slice(0, n).map(func(k): return "%s x%d" % [Sim.P[k].name, m[k]]))


func slot_row(i: int, s: Dictionary, prep: bool) -> Control:
	if s.pid < 0:
		var b := button("+  STOCK SHELF %d" % (i + 1), show_picker.bind(i))
		b.custom_minimum_size.y = 44
		b.disabled = not prep
		return b
	var p: Dictionary = Sim.P[s.pid]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(Color.WHITE, LINE, 1, 4))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	panel.add_child(h)
	h.add_child(picture("products", s.pid, Vector2i(32, 32), Vector2(32, 32)))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	var nm := label(p.name + (" *" if p.perish else ""), INK, 14)
	nm.clip_text = true
	v.add_child(nm)
	var cap := sim.cap_of(cur)
	var stock := label("%d/%d  sold %d" % [s.qty, cap, s.sold], RED if s.qty == 0 else MUTED)
	stock.clip_text = true
	v.add_child(stock)
	var tier := button("%s\n%s" % [Sim.TIER_NAME[s.tier], yen(sim.price_of(s.pid, s.tier))], on_tier.bind(i), "Price: LOW sells to everyone, HIGH earns more from relaxed shoppers")
	tier.add_theme_color_override("font_color", TIER_COLOR[s.tier])
	tier.add_theme_color_override("font_hover_color", TIER_COLOR[s.tier])
	tier.custom_minimum_size.x = 46
	tier.disabled = not prep
	h.add_child(tier)
	var unit: int = sim.wholesale[s.pid]
	var add := button("+10", on_buy.bind(i, s.pid, 10), "Buy 10 at %s each (%s)" % [yen(unit), yen(unit * mini(10, cap - s.qty))])
	add.disabled = not prep or s.qty >= cap or sim.cash < unit
	h.add_child(add)
	var fill := button("FILL", on_buy.bind(i, s.pid, cap), "Fill to %d at %s each (%s)" % [cap, yen(unit), yen(unit * (cap - s.qty))])
	fill.disabled = add.disabled
	h.add_child(fill)
	var x := button("X", on_clear.bind(i), "Clear this shelf (stock is thrown away)")
	x.disabled = not prep
	h.add_child(x)
	return panel


func select_store(i: int) -> void:
	if phase != "prep":
		return
	cur = i
	refresh()


func on_tier(i: int) -> void:
	if phase != "prep":
		return
	sim.cycle_tier(cur, i)
	refresh()


func on_buy(i: int, pid: int, qty: int) -> void:
	if phase != "prep":
		return
	sim.buy(cur, i, pid, qty)
	refresh()


func on_clear(i: int) -> void:
	if phase != "prep":
		return
	sim.clear_slot(cur, i)
	refresh()


func open_shop() -> void:
	if phase != "prep" or modal:
		return
	if arranging:
		arranging = false
		view.set_edit(false)
	var pre: Array = sim.stores[cur].slots.map(func(s): return s.qty)
	report = sim.simulate_day()
	phase = "day"
	open_btn.disabled = true
	grow_btn.disabled = true
	arrange_btn.disabled = true
	view.play(report.stores[cur].events, pre, report.stores[cur].left)


func _notification(what: int) -> void:
	if view == null:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		view.paused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		view.paused = false


# ---------- modals ----------

func open_modal(title: String, body: Control, keys := {}) -> void:
	close_modal()
	modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.1, 0.16, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(PAPER, INK, 3, 16))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(label(title, INK, 32))
	v.add_child(body)
	add_child(modal)
	modal_keys = keys


func close_modal() -> void:
	if modal:
		modal.queue_free()
		modal = null
	modal_keys = {}


func show_picker(slot: int) -> void:
	if phase != "prep":
		return
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for pid in Sim.P.size():
		var p: Dictionary = Sim.P[pid]
		var tags := []
		if sim.weather.mult.get(p.id, 1.0) > 1.0 or (sim.event.id == "viral" and sim.event_arg == p.id):
			tags.append("HOT")
		if sim.misses.has(pid):
			tags.append("ASKED x%d" % sim.misses[pid])
		if p.perish:
			tags.append("FRESH")
		var ok := sim.can_stock(cur, pid)
		var t := "%s\n%s > %s\n%s" % [p.name, yen(sim.wholesale[pid]), yen(p.price), " ".join(tags) if ok else "SUPERMARKET"]
		var b := button(t, pick_product.bind(slot, pid))
		b.icon = atlas("products", pid, Vector2i(32, 32))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(168, 54)
		b.clip_text = true
		b.disabled = not ok
		g.add_child(b)
	var v := VBoxContainer.new()
	v.add_child(label("Wholesale today > shelf price. FRESH items are binned at close.", MUTED))
	v.add_child(g)
	v.add_child(button("CANCEL  [Esc]", close_modal))
	open_modal("STOCK SHELF %d" % (slot + 1), v, {KEY_ESCAPE: close_modal})


func pick_product(slot: int, pid: int) -> void:
	sim.buy(cur, slot, pid, 10)
	if sim.stores[cur].slots[slot].pid < 0:  # couldn't afford any: still assign the shelf
		sim.stores[cur].slots[slot].pid = pid
	close_modal()
	refresh()


func show_report() -> void:
	var r := report
	phase = "modal"
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var lines := [
		["Customers", "%d" % r.customers + ("  (%d walked out: add checkouts)" % r.walkouts if r.walkouts else "")],
		["Sales", yen(r.sales)],
	]
	if r.extras:
		lines.append(["Coffee & hot snacks", yen(r.extras)])
	lines.append(["Stock bought this morning", "-" + yen(r.spent)])
	lines.append(["Wages & power", "-" + yen(r.upkeep)])
	if r.rent:
		lines.append(["Weekly rent", "-" + yen(r.rent)])
	if r.waste:
		lines.append(["Stock binned at close (at cost)", yen(r.waste)])
	for l in lines:
		var h := HBoxContainer.new()
		var a := label(l[0])
		a.custom_minimum_size.x = 260
		h.add_child(a)
		h.add_child(label(l[1], RED if l[1].begins_with("-") else INK))
		v.add_child(h)
	if r.stores.size() > 1:
		v.add_child(label("  ".join(r.stores.map(func(s): return "%s %s" % [Sim.STORE[s.kind].name, yen(s.sales)])), MUTED))
	var net_h := HBoxContainer.new()
	var na := label("Cash flow today", INK, 24)
	na.custom_minimum_size.x = 260
	net_h.add_child(na)
	net_h.add_child(label(yen(r.net), GREEN if r.net >= 0 else RED, 24))
	v.add_child(net_h)
	v.add_child(label("Cash %s    Reputation %d (%s%d)" % [yen(r.cash), roundi(sim.rep), "+" if r.rep_delta >= 0 else "", roundi(r.rep_delta)]))
	if r.misses.size():
		v.add_child(label("Asked for but not on the shelf: " + top_misses(r.misses, 4), ORANGE))
	var go := func():
		if sim.over:
			show_over()
		else:
			show_draft()
	v.add_child(button("CONTINUE  [Space]", go))
	open_modal("DAY %d CLOSED" % r.day, v, {KEY_SPACE: go, KEY_ENTER: go})


func show_draft() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var keys := {}
	for i in sim.draft.size():
		var p: Dictionary = sim.draft[i]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", box(Color.WHITE, INK, 2, 10))
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(170, 0)
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		v.add_child(picture("perks", p.frame, Vector2i(40, 40), Vector2(80, 80)))
		var n := label(p.name.to_upper())
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
		var d := label(sim.perk_desc(p), MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(170, 64)
		v.add_child(d)
		v.add_child(button("TAKE  [%d]" % (i + 1), take.bind(i)))
		h.add_child(card)
		keys[KEY_1 + i] = take.bind(i)
	open_modal("PICK AN UPGRADE", h, keys)


func take(i: int) -> void:
	sim.next_day(i)
	phase = "prep"
	close_modal()
	refresh()


func show_grow() -> void:
	if phase != "prep":
		return
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(label("Konbini  >  Supermarket  >  three stores  >  Flagship hypermarket wins the run.", MUTED))
	for e in sim.expansions():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(picture("stores", e.frame, Vector2i(160, 128), Vector2(100, 80)))
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 330
		col.add_child(label(e.name.to_upper()))
		var d := label(e.desc, MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(d)
		row.add_child(col)
		var b := button("BUILD\n" + yen(e.cost), build_it.bind(e.id))
		b.custom_minimum_size = Vector2(110, 52)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = e.get("locked", false) or sim.cash < e.cost
		row.add_child(b)
		v.add_child(row)
	v.add_child(button("CLOSE  [Esc]", close_modal))
	open_modal("EXPAND", v, {KEY_ESCAPE: close_modal, KEY_G: close_modal})


func build_it(id: String) -> void:
	if not sim.expand(id):
		return
	if sim.won:
		show_over()
		return
	close_modal()
	if id == "branch":
		cur = sim.stores.size() - 1
	refresh()


func show_over() -> void:
	phase = "over"
	var key := "win_day" if sim.won else "max_day"
	var prev: int = best.get_value("best", key, 0)
	var better := prev == 0 or (sim.day < prev if sim.won else sim.day > prev)
	if better:
		best.set_value("best", key, sim.day)
		best.save("user://best.cfg")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(label("Your flagship opens. The empire is yours." if sim.won else "Rent bounced. The landlord changed the locks.", GREEN if sim.won else RED))
	for l in [
		"Days: %d" % sim.day,
		"Stores: %s" % ", ".join(sim.stores.map(func(s): return Sim.STORE[s.kind].name)),
		"Customers served: %s" % Sim.money(sim.stats.served),
		"Total sales: %s" % yen(sim.stats.sales),
		"Peak cash: %s" % yen(sim.stats.peak),
		"Upgrades: %d" % sim.perks.values().reduce(func(a, b): return a + b, 0),
		"Seed: %s" % sim.seed_text,
	]:
		v.add_child(label(l))
	var w: int = best.get_value("best", "win_day", 0)
	var m: int = best.get_value("best", "max_day", 0)
	v.add_child(label(("Best: flagship on day %d" % w) if w else ("Longest run: day %d" % m), MUTED))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var again := func(): new_run(sim.seed_text)
	var fresh := func(): new_run("")
	h.add_child(button("RETRY SEED", again))
	h.add_child(button("NEW RUN  [Space]", fresh))
	v.add_child(h)
	open_modal("EMPIRE BUILT" if sim.won else "BANKRUPT", v, {KEY_SPACE: fresh, KEY_ENTER: fresh})


func show_new_run() -> void:
	if phase == "day" or phase == "modal":
		return
	var v := VBoxContainer.new()
	v.add_child(label("Same seed, same weather, events and upgrades. Leave blank for a random run.", MUTED))
	var edit := LineEdit.new()
	edit.placeholder_text = "seed"
	edit.custom_minimum_size.x = 300
	v.add_child(edit)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var start := func(): new_run(edit.text)
	edit.text_submitted.connect(func(_t): start.call())
	h.add_child(button("START", start))
	var cancel := func():
		if sim.over:
			show_over()
		else:
			close_modal()
	h.add_child(button("CANCEL", cancel))
	v.add_child(h)
	open_modal("NEW RUN", v, {KEY_ESCAPE: cancel})
	edit.grab_focus.call_deferred()


func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var k: int = e.keycode
	if modal:
		if modal_keys.has(k):
			modal_keys[k].call()
			get_viewport().set_input_as_handled()
		return
	match phase:
		"prep":
			if k == KEY_SPACE or k == KEY_ENTER:
				open_shop()
			elif k == KEY_TAB:
				select_store((cur + 1) % sim.stores.size())
			elif k == KEY_G and not arranging:
				show_grow()
			elif k == KEY_E:
				toggle_arrange()
			elif k == KEY_ESCAPE and arranging:
				if view.carry.is_empty():
					toggle_arrange()
				else:
					view.cancel_carry()
		"day":
			if k == KEY_SPACE or k == KEY_ENTER:
				view.skip()
