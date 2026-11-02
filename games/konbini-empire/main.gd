extends Control
## Konbini Empire UI: builds every control in code, runs the sim in real time (pausing for cards and reports) and
## turns clicks and keys into sim actions.

const Sim := preload("res://sim.gd")
const StoreView := preload("res://store_view.gd")

const INK := Color("2b2d42")
const PAPER := Color("f7f3e8")
const GROUND := Color("e8e1cf")
const LINE := Color("cfc8b4")
const GREEN := Color("2f9e5b")
const ORANGE := Color("e07b1a")
const RED := Color("d64545")
const BLUE := Color("2f6fd6")
const MUTED := Color("7d7768")
const RARITY_COLOR := {"common": Color("7d7768"), "rare": Color("2f6fd6"), "epic": Color("9b4dca"), "legendary": Color("d99a0b")}
const ABILITY_KEYS := ["flyer", "timeSale", "counter", "influencer", "truck"]
const ROLE_ICON := {"cashier": "TILL", "stocker": "STOCK", "cleaner": "CLEAN", "guard": "GUARD", "promoter": "PROMO"}

var sim := Sim.new()
var tex := {}
var view: StoreView
var speed := 1
var held := false  # paused with Space
var focused := true
var modal: Control
var modal_keys := {}
var modal_kind := ""
var best := ConfigFile.new()
var bold: FontVariation
var toasts: Array = []  # [text, color, seconds left]
var ui_t := 0.0
var shelf_sig := ""

var lbl_day: Label
var lbl_cash: Label
var lbl_level: Label
var xp_bar: ProgressBar
var lbl_rating: Label
var lbl_bills: Label
var speed_btn: Button
var pause_btn: Button
var seed_btn: Button
var tabs: HBoxContainer
var ability_row: HBoxContainer
var pick_btn: Button
var info: Label
var head: Label
var sub: Label
var rival_lbl: Label
var rival_bar: ProgressBar
var shelf_box: VBoxContainer
var crew_lbl: Label
var staff_btn: Button
var grow_btn: Button
var store_btn: Button
var city_btn: Button
var banner: Label


func _ready() -> void:
	for n in ["products", "perks", "decor", "outdoor", "vehicles", "walk", "storefronts", "landmarks", "tokyo", "train", "bg_konbini"]:
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
	var f: FontFile = load("res://fonts/NotoSans-Regular.ttf")
	bold = FontVariation.new()
	bold.base_font = f
	bold.variation_embolden = 0.7
	th.default_font = f
	th.default_font_size = 13
	th.set_font("font", "Button", bold)
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
	th.set_stylebox("background", "ProgressBar", box(Color("ddd6c4"), Color("ddd6c4"), 0, 0))
	th.set_stylebox("fill", "ProgressBar", box(GREEN, GREEN, 0, 0))
	return th


func label(text: String, color := INK, px := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if px > 0:
		l.add_theme_font_size_override("font_size", px)
	if px >= 15:
		l.add_theme_font_override("font", bold)
	return l


func para(text: String, color := MUTED, w := 270) -> Label:
	var l := label(text, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = w
	return l


func button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.pressed.connect(cb)
	return b


func progress(color: Color, h := 8) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size.y = h
	p.max_value = 1.0
	p.add_theme_stylebox_override("fill", box(color, color, 0, 0))
	return p


func picture(sheet: String, i: int, cell: int, min_size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	var t := AtlasTexture.new()
	t.atlas = tex[sheet]
	t.region = Rect2(i * cell, 0, cell, cell)
	r.texture = t
	r.custom_minimum_size = min_size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return r


func icon(pid: String, px: float) -> TextureRect:
	var ic: Array = Sim.PRODUCTS[pid].icon
	return picture(ic[0], ic[1], {"products": 64, "perks": 80, "decor": 96}[ic[0]], Vector2(px, px))


func yen(v: int) -> String:
	return ("-¥" if v < 0 else "¥") + Sim.money(absi(v))


func stars(r: float) -> String:
	return "%.1f★" % r


# ---------- layout ----------

func build() -> void:
	var bg := ColorRect.new()
	bg.color = GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var bar := ColorRect.new()
	bar.color = INK
	bar.size = Vector2(960, 32)
	add_child(bar)
	var hb := HBoxContainer.new()
	hb.position = Vector2(10, 0)
	hb.size = Vector2(940, 32)
	hb.add_theme_constant_override("separation", 16)
	bar.add_child(hb)
	lbl_day = label("", PAPER, 16)
	lbl_cash = label("", Color("ffd36b"), 16)
	lbl_level = label("", Color("b8d8ff"), 16)
	lbl_rating = label("", Color("b8f2c9"), 16)
	lbl_bills = label("", PAPER, 14)
	for l in [lbl_day, lbl_cash, lbl_level]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
	xp_bar = progress(Color("6aa8ff"), 6)
	xp_bar.custom_minimum_size.x = 60
	xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(xp_bar)
	for l in [lbl_rating, lbl_bills]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(sp)
	pause_btn = button("II", toggle_hold, "Pause  [Space]")
	speed_btn = button("1x", cycle_speed, "Game speed  [F]")
	seed_btn = button("", show_new_run, "Start a new run (you can type a seed)")
	for b in [pause_btn, speed_btn, seed_btn]:
		b.custom_minimum_size.y = 26
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(b)

	view = StoreView.new()
	view.tex = tex
	view.position = Vector2(0, 32)
	view.size = Vector2(700, 420)
	view.clip_contents = true
	view.sim = sim
	view.act_requested.connect(do_act)
	view.lot_clicked.connect(on_lot)
	add_child(view)
	banner = label("", Color.WHITE, 15)
	banner.position = Vector2(220, 40)
	banner.size = Vector2(470, 24)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	banner.add_theme_constant_override("outline_size", 6)
	banner.add_theme_color_override("font_outline_color", INK)
	add_child(banner)

	var bottom := VBoxContainer.new()
	bottom.position = Vector2(8, 456)
	bottom.size = Vector2(686, 80)
	bottom.add_theme_constant_override("separation", 4)
	add_child(bottom)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	bottom.add_child(tabs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	bottom.add_child(row)
	ability_row = HBoxContainer.new()
	ability_row.add_theme_constant_override("separation", 4)
	row.add_child(ability_row)
	pick_btn = button("", open_pick, "Choose your level-up skill or reward  [P]")
	pick_btn.custom_minimum_size = Vector2(110, 40)
	pick_btn.add_theme_stylebox_override("normal", box(Color("ffe7c2"), INK))
	row.add_child(pick_btn)
	info = label("", INK)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(150, 40)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.max_lines_visible = 3
	info.add_theme_font_size_override("font_size", 11)
	row.add_child(info)

	var side := PanelContainer.new()
	side.position = Vector2(700, 32)
	side.size = Vector2(260, 508)
	side.add_theme_stylebox_override("panel", box(PAPER, INK, 2, 8))
	add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	side.add_child(sv)
	head = label("", INK, 16)
	head.clip_text = true
	sv.add_child(head)
	sub = para("", MUTED, 240)
	sub.add_theme_font_size_override("font_size", 11)
	sv.add_child(sub)
	rival_lbl = label("", INK)
	rival_lbl.clip_text = true
	sv.add_child(rival_lbl)
	rival_bar = progress(RED)
	sv.add_child(rival_bar)
	sv.add_child(label("SHELVES  (click a shelf or +)", MUTED))
	shelf_box = VBoxContainer.new()
	shelf_box.add_theme_constant_override("separation", 2)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(shelf_box)
	shelf_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(scroll)
	crew_lbl = para("", INK, 240)
	crew_lbl.add_theme_font_size_override("font_size", 11)
	sv.add_child(crew_lbl)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	sv.add_child(g)
	staff_btn = button("STAFF", show_staff, "Hire and fire at this store  [S]")
	grow_btn = button("EXPAND", act_open.bind("openExpansion"), "Buy an expansion for this store  [G]")
	store_btn = button("NEW STORE", act_open.bind("openListings"), "Open another branch  [N]")
	city_btn = button("CITY", toggle_city, "Tokyo map: your branches and their rivals  [M]")
	for b in [staff_btn, grow_btn, store_btn, city_btn]:
		b.custom_minimum_size = Vector2(118, 30)
		b.clip_text = true
		g.add_child(b)


# ---------- run flow ----------

func new_run(seed_str: String) -> void:
	seed_str = seed_str.strip_edges()
	if seed_str == "":
		const CH := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
		for i in 6:
			seed_str += CH[randi() % CH.length()]
	sim.start(seed_str)
	held = false
	speed = 1
	toasts.clear()
	shelf_sig = ""
	close_modal()
	view.set_mode("store")
	view.show_branch(0)
	refresh_ui()
	show_intro()


## The host loop: real time, x1-x3, halted by cards, reports, the staff panel, Space and losing focus.
func _process(delta: float) -> void:
	var running := sim.phase == "playing" and modal == null and not held and focused
	if running:
		sim.tick(minf(0.05, delta) * speed)
	drain()
	for t in toasts:
		t[2] -= delta
	toasts = toasts.filter(func(t): return t[2] > 0.0)
	ui_t -= delta
	if ui_t <= 0.0:
		ui_t = 0.1
		refresh_ui()


func drain() -> void:
	if sim.events.is_empty():
		return
	var evs: Array = sim.events
	sim.events = []
	view.add_events(evs)
	var mine: int = sim.branches[sim.active].id if sim.active < sim.branches.size() else -1
	var day_end = null
	for e in evs:
		var where := ""
		for b in sim.branches:
			if b.id == e.get("branch", -1) and b.id != mine:
				where = b.name + ": "
		match e.type:
			"levelUp":
				toast("Level %d! Pick a skill  [P]" % e.level, BLUE)
			"rivalDefeated":
				toast("%s%s closed for good! Reward waiting  [P]" % [where, Sim.RIVALS[e.rival].name], GREEN)
			"rivalArrives":
				toast("%s%s moved in next door (tier %d)." % [where, Sim.RIVALS[e.rival].name, e.tier], RED)
			"attack":
				if e.attack == "priceWar" or where == "":
					toast("%s%s!" % [where, Sim.ATTACKS[e.attack].name], RED)
			"blocked":
				toast(where + "The camera blocked a fake review.", GREEN)
			"caught":
				toast(where + "The camera caught a shoplifter: +¥200.", GREEN)
			"streetEvent":
				toast("%s%s today: %s" % [where, Sim.EVENTS[e.event].name, Sim.EVENTS[e.event].desc], ORANGE)
			"inspection":
				toast(where + ("Health inspection passed: +0.2★." if e.passed else "Health inspection: fined ¥%s for mess." % Sim.money(e.fine)), GREEN if e.passed else RED)
			"milestone":
				toast("Milestone: %s! Reward waiting  [P]" % Sim.MILESTONES[e.id].name, GREEN)
			"storeOpened":
				toast("%s opened. %s is next door." % [e.name, Sim.RIVALS[e.rival].name], GREEN)
			"foreclosed":
				toast("The bank took %s (paid back %s)." % [e.name, yen(e.value)], RED)
			"hired":
				toast("Hired %s (%s) for %s." % [e.name, Sim.ROLES[e.role].name, yen(e.fee)], GREEN)
			"roleFull":
				toast("No room for another %s." % Sim.ROLES[e.role].name.to_lower(), RED)
			"cantAffordHire", "cantAffordStore", "cantAffordExpansion":
				toast("Need %s more." % yen(e.short), RED)
			"cantAfford":
				if where == "":
					toast("Can't afford to restock %s." % Sim.PRODUCTS[e.product].name, RED)
			"pickPayout":
				toast("Nothing left to pick: +%s instead." % yen(e.amount), GREEN)
			"storeCap":
				toast("Six stores is the most you can run.", RED)
			"takeoverHit":
				toast("%sA suit took %s!" % [where, yen(e.amount)], RED)
			"reviewPosted":
				toast(where + "A fake review went up: -0.35★.", RED)
			"dayEnd":
				day_end = e
	if day_end != null:
		if day_end.bankrupt:
			show_over()
		else:
			show_report(day_end.report)


func toast(text: String, color := INK) -> void:
	toasts.append([text, color, 6.0])
	if toasts.size() > 3:
		toasts.pop_front()


func do_act(a: Dictionary) -> void:
	if modal != null:
		return
	sim.act(a)
	drain()
	if sim.phase == "choice":
		show_choice()
	ui_t = 0.0


func act_open(type: String) -> void:
	if view.mode == "city":
		toggle_city()
	do_act({"type": type})


func open_pick() -> void:
	act_open("openPick")


func toggle_hold() -> void:
	held = not held
	ui_t = 0.0


func cycle_speed() -> void:
	speed = speed % 3 + 1
	ui_t = 0.0


func select_store(i: int) -> void:
	if modal != null:
		return
	sim.act({"type": "switchStore", "index": i})
	drain()
	view.show_branch(sim.active)
	shelf_sig = ""
	ui_t = 0.0


func toggle_city() -> void:
	if modal != null:
		return
	if view.mode == "city":
		if sim.phase == "choice":
			sim.act({"type": "closeChoice"})
		view.set_mode("store")
		view.show_branch(sim.active)
	else:
		view.set_mode("city")
	ui_t = 0.0


func on_lot(li: int) -> void:
	if sim.phase == "choice" and sim.choice.source == "listing":
		for k in sim.choice.options.size():
			if sim.choice.options[k].lot == li:
				show_choice()
				return
	var b = sim.branch_on(li)
	if b != null:
		view.set_mode("store")
		select_store(sim.branches.find(b))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
	if view:
		view.paused = not focused


# ---------- HUD ----------

func refresh_ui() -> void:
	if sim.branches.is_empty():
		return
	var b: Dictionary = sim.branches[sim.active]
	var st: Dictionary = b.store
	lbl_day.text = "DAY %d" % sim.day
	lbl_cash.text = yen(sim.player.cash)
	lbl_level.text = "LV %d" % sim.player.level
	xp_bar.value = sim.player.xp / sim.player.xp_next
	lbl_rating.text = stars(st.rating)
	var bills := sim.bills_due()
	lbl_bills.text = "BILLS TONIGHT %s" % yen(bills)
	lbl_bills.add_theme_color_override("font_color", Color("ff9b8a") if sim.player.cash < bills else PAPER)
	seed_btn.text = "SEED %s" % sim.seed_text
	speed_btn.text = "%dx" % speed
	pause_btn.text = ">" if held else "II"
	banner.text = "PAUSED  [Space]" if held else ("CLICK A NUMBERED LOT  ·  Esc to go back" if view.pick == "listing" and view.mode == "city" else "")

	if tabs.get_child_count() != sim.branches.size():
		for c in tabs.get_children():
			c.queue_free()
		for i in sim.branches.size():
			var t := button("", select_store.bind(i), "Switch store  [Tab]")
			t.custom_minimum_size.y = 24
			tabs.add_child(t)
	for i in sim.branches.size():
		var o: Dictionary = sim.branches[i]
		var t: Button = tabs.get_child(i)
		var alert := ""
		if o.threats.any(func(x): return x.type != "spill") or o.rival.telegraph != "":
			alert = " !"
		if o.store.products.values().any(func(p): return float(p.stock) / p.capacity < Sim.LOW_STOCK):
			alert += " ▾"
		t.text = "%d %s%s" % [i + 1, o.name.to_upper(), alert]
		t.add_theme_stylebox_override("normal", box(Color("c5e6d0") if i == sim.active else PAPER, INK))
		t.add_theme_color_override("font_color", RED if alert != "" and i != sim.active else INK)

	if ability_row.get_child_count() == 0:
		for i in ABILITY_KEYS.size():
			var a := button("", do_act.bind({"type": "useAbility", "id": ABILITY_KEYS[i]}))
			a.custom_minimum_size = Vector2(78, 40)
			a.clip_text = true
			a.add_theme_font_size_override("font_size", 11)
			ability_row.add_child(a)
	for i in ABILITY_KEYS.size():
		var id: String = ABILITY_KEYS[i]
		var a: Button = ability_row.get_child(i)
		var ab = sim.player.abilities.get(id)
		var def: Dictionary = Sim.ABILITIES[id]
		if ab == null:
			a.text = "%d  —\nlocked" % (i + 1)
			a.disabled = true
			a.tooltip_text = "%s: unlock it from a level-up card." % def.name
		else:
			a.text = "%d %s %s\n%s" % [i + 1, def.name.get_slice(" ", 0).to_upper(), "I".repeat(ab.level), "READY" if ab.cd <= 0.0 else "%ds" % ceili(ab.cd)]
			a.disabled = ab.cd > 0.0 or sim.phase != "playing"
			a.tooltip_text = "%s (level %d)  [%d]" % [def.name, ab.level, i + 1]
	pick_btn.visible = not sim.pending.is_empty()
	pick_btn.text = "PICK  (%d)\n[P]" % sim.pending.size()
	var lines := toasts.map(func(t): return t[0])
	if lines.is_empty():
		lines = [hint(b)]
	info.text = "\n".join(lines.slice(maxi(0, lines.size() - 3)))
	info.add_theme_color_override("font_color", toasts[-1][1] if not toasts.is_empty() else MUTED)

	head.text = b.name.to_upper()
	var d: Dictionary = Sim.DISTRICTS[b.district]
	var ev: String = "" if b.event == null else "  ·  " + Sim.EVENTS[b.event.id].name
	sub.text = "%s, %s%s\n%s  ·  rent %s + wages %s  ·  %d served, %d lost" % [d.name, Sim.QUIRKS[b.quirk].name.to_lower(), ev, stars(st.rating), yen(sim.rent(b)), yen(sim.wages(b)), b.day_stats.customers, b.day_stats.lost]
	var rv: Dictionary = b.rival
	if rv.defeated:
		rival_lbl.text = "%s CLOSED  ·  new rival in %d day%s" % [Sim.RIVALS[rv.id].name.to_upper(), 2 - rv.closed_days, "" if 2 - rv.closed_days == 1 else "s"]
		rival_bar.value = 0.0
	else:
		rival_lbl.text = "%s  T%d  %s / %s" % [Sim.RIVALS[rv.id].name.to_upper(), rv.tier, Sim.money(ceili(rv.hp)), Sim.money(int(rv.max_hp))]
		rival_bar.value = rv.hp / rv.max_hp
	refresh_shelves(b)
	var crew: Array = st.crew.map(func(m): return "%s %s" % [ROLE_ICON[m.role], m.name])
	crew_lbl.text = "CREW  " + ", ".join(crew) + ("" if b.regulars == 0 else "\n%d regulars on the way" % b.regulars)
	var exp_ok := not sim.eligible("expansion", st).is_empty()
	grow_btn.text = "EXPAND %s" % yen(Sim.expansion_cost(st)) if exp_ok else "EXPAND (all)"
	grow_btn.disabled = not exp_ok or sim.phase != "playing"
	store_btn.text = "NEW STORE"
	store_btn.disabled = sim.branches.size() >= Sim.MAX_STORES or sim.phase != "playing"
	store_btn.tooltip_text = "Open another branch: from %s  [N]" % yen(sim.store_cost())
	staff_btn.disabled = sim.phase != "playing"
	city_btn.text = "SHOP" if view.mode == "city" else "CITY"


func hint(b: Dictionary) -> String:
	if sim.day == 1 and sim.time < 40.0:
		return "Click the till to ring customers up (combos earn XP), click threats to chase them off, click shelves to restock. Every sale hurts the rival next door."
	if b.store.registers.any(func(r): return r.active and r.queue.size() >= 4):
		return "The queue is long: ring up at the till [R] or hire a cashier."
	return "Bills are paid at midnight. Run out of cash and the run ends."


func refresh_shelves(b: Dictionary) -> void:
	var st: Dictionary = b.store
	var sig := "%d:%s" % [b.id, ",".join(st.products.keys())]
	if sig != shelf_sig:
		shelf_sig = sig
		for c in shelf_box.get_children():
			c.queue_free()
		for pid in st.products:
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 4)
			h.add_child(icon(pid, 26))
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_theme_constant_override("separation", 0)
			var nm := label(Sim.PRODUCTS[pid].name)
			nm.clip_text = true
			nm.add_theme_font_size_override("font_size", 11)
			v.add_child(nm)
			v.add_child(progress(GREEN, 6))
			h.add_child(v)
			var r := button("", do_act.bind({"type": "restock", "product": pid}))
			r.custom_minimum_size = Vector2(84, 28)
			r.add_theme_font_size_override("font_size", 11)
			h.add_child(r)
			shelf_box.add_child(h)
	var i := 0
	for pid in st.products:
		if i >= shelf_box.get_child_count():
			break
		var p: Dictionary = st.products[pid]
		var row: HBoxContainer = shelf_box.get_child(i)
		var bar: ProgressBar = row.get_child(1).get_child(1)
		var frac: float = float(p.stock) / p.capacity
		bar.value = frac
		bar.add_theme_stylebox_override("fill", box(RED if frac < Sim.LOW_STOCK else GREEN, RED if frac < Sim.LOW_STOCK else GREEN, 0, 0))
		var missing: int = p.capacity - p.stock
		var cost := Sim.rnd(missing * Sim.PRODUCTS[pid].cost * sim.mods().restock)
		var btn: Button = row.get_child(2)
		btn.text = "%d/%d  +%s" % [p.stock, p.capacity, yen(cost)] if missing > 0 else "%d/%d  FULL" % [p.stock, p.capacity]
		btn.disabled = missing == 0 or sim.phase != "playing"
		i += 1


# ---------- modals ----------

func open_modal(title: String, body: Control, keys := {}, kind := "") -> void:
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
	v.add_child(label(title, INK, 28))
	v.add_child(body)
	add_child(modal)
	modal_keys = keys
	modal_kind = kind


func close_modal() -> void:
	if modal:
		modal.queue_free()
		modal = null
	modal_keys = {}
	modal_kind = ""


func show_intro() -> void:
	var b: Dictionary = sim.branches[0]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(para("Your first konbini opens in %s. %s is next door and wants your customers. Every sale you make hits its takings; drive it out of business and a bigger chain moves in." % [b.name, Sim.RIVALS[b.rival.id].name], INK, 520))
	v.add_child(para("Click the till when a customer is waiting (fast ring-ups build combos), click threats the rival sends (flyers, trash, mascots, thieves...), click a shelf to restock it. Hire staff, buy expansions, pick a card at every level, open more branches across Tokyo. Rent and wages are due every midnight; run out of cash and it's over.", MUTED, 520))
	v.add_child(para("Keys: Space pause, F speed, R ring up, 1-5 abilities, P pick, S staff, G expand, N new store, M map, Tab next store.", MUTED, 520))
	var go := func():
		close_modal()
		sim.act({"type": "start"})
	v.add_child(button("OPEN THE SHOP  [Space]", go))
	open_modal("KONBINI EMPIRE", v, {KEY_SPACE: go, KEY_ENTER: go}, "intro")


## Whatever pick card the sim has open: level-up skills, rewards, expansions or new-store listings.
func show_choice() -> void:
	if sim.choice == null:
		return
	var c: Dictionary = sim.choice
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var keys := {}
	for i in c.options.size():
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", box(Color.WHITE, INK, 2, 10))
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(190, 0)
		col.add_theme_constant_override("separation", 6)
		card.add_child(col)
		if c.source == "listing":
			listing_card(col, c.options[i])
		else:
			var u: Dictionary = Sim.UPGRADES[c.options[i]]
			col.add_child(label(u.rarity.to_upper(), RARITY_COLOR[u.rarity]))
			if u.has("product"):
				col.add_child(icon(u.product, 56))
			col.add_child(label(u.name.to_upper(), INK, 15))
			var n: int = (sim.branches[sim.active].store.taken if c.source == "expansion" else sim.player.taken).get(c.options[i], 0)
			col.add_child(para(u.desc + ("" if n == 0 else "  (have %d)" % n), MUTED, 190))
		var take := func(): pick(c.options[i] if c.source != "listing" else i)
		var b := button("TAKE  [%d]" % (i + 1), take)
		if c.source == "listing":
			b.text = "OPEN %s  [%d]" % [yen(c.options[i].cost), i + 1]
			b.disabled = sim.player.cash < c.options[i].cost
		elif c.source == "expansion":
			b.disabled = sim.player.cash < c.cost
		col.add_child(b)
		h.add_child(card)
		keys[KEY_1 + i] = take
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var title := "PICK A SKILL"
	match c.source:
		"reward":
			title = "REWARD"
			v.add_child(label(c.reason, GREEN))
		"expansion":
			title = "EXPAND %s" % sim.branches[sim.active].name.to_upper()
			v.add_child(label("Costs %s. Cash %s." % [yen(c.cost), yen(sim.player.cash)], MUTED))
		"listing":
			title = "NEW STORE"
			v.add_child(label("Three lots on offer. Cash %s; bills tonight %s." % [yen(sim.player.cash), yen(sim.bills_due())], MUTED))
	v.add_child(h)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var rc := sim.reroll_cost()
	var spare: int = sim.player.cash - (c.cost if c.source == "expansion" else 0)
	var rr := button("REROLL %s  [R]" % yen(rc), reroll)
	rr.disabled = spare < rc
	row.add_child(rr)
	if c.source == "listing":
		row.add_child(button("SEE ON MAP", see_listings))
	row.add_child(button("LATER  [Esc]", later))
	v.add_child(row)
	keys[KEY_R] = reroll
	keys[KEY_ESCAPE] = later
	open_modal(title, v, keys, "choice")


func listing_card(v: VBoxContainer, L: Dictionary) -> void:
	var tokyo: String = sim.districts[sim.lots[L.lot].block].name
	var d: Dictionary = Sim.DISTRICTS[L.district]
	var q: Dictionary = Sim.QUIRKS[L.quirk]
	var rv: Dictionary = Sim.RIVALS[L.rival]
	v.add_child(label(tokyo.to_upper(), INK, 15))
	v.add_child(label(d.name, MUTED))
	var quirk: String = q.name
	v.add_child(para("%s. Foot traffic x%.2f, rent about %s a night." % [quirk, d.traffic * q.get("traffic", 1.0), yen(Sim.rnd(d.rent * q.get("rent", 1.0)))], INK, 190))
	if not d.demand.is_empty():
		v.add_child(para("Locals buy: " + ", ".join(d.demand.keys().map(func(k): return Sim.PRODUCTS[k].name.to_lower())), MUTED, 190))
	v.add_child(label("Rival: %s (tier %d)" % [rv.name, L.tier], Color(rv.color).darkened(0.2)))


func pick(id) -> void:
	sim.act({"type": "pickChoice", "id": id})
	drain()
	if sim.phase == "choice":
		show_choice()
		return
	close_modal()
	if view.mode == "city":
		view.set_mode("store")
	view.show_branch(sim.active)
	shelf_sig = ""
	ui_t = 0.0


func reroll() -> void:
	sim.act({"type": "reroll"})
	drain()
	show_choice()


func later() -> void:
	sim.act({"type": "closeChoice"})
	close_modal()
	ui_t = 0.0


func see_listings() -> void:
	close_modal()
	view.pick = "listing"
	view.set_mode("city")
	view.pick = "listing"
	ui_t = 0.0


func show_staff() -> void:
	if sim.phase != "playing":
		return
	var b: Dictionary = sim.branches[sim.active]
	var st: Dictionary = b.store
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.add_child(label("Cash %s. Hiring costs a day's wage now; wages are paid every midnight." % yen(sim.player.cash), MUTED))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 18)
	v.add_child(cols)
	var crew := VBoxContainer.new()
	crew.custom_minimum_size.x = 250
	crew.add_theme_constant_override("separation", 2)
	crew.add_child(label("CREW", INK, 15))
	for m in st.crew:
		var h := HBoxContainer.new()
		h.add_child(member_label(m, 190))
		h.add_child(small_button("FIRE", staff_act.bind("fire", m.id)))
		crew.add_child(h)
	crew.add_child(para("Cashiers run a till each. Stock clerks refill low shelves but keep tonight's bills in the till. Cleaners mop spills and bag trash. A guard sees off flyers, mascots, thieves, suits and blackouts. A promoter pulls in walkers.", MUTED, 240))
	cols.add_child(crew)
	var apps := GridContainer.new()
	apps.columns = 3
	apps.add_theme_constant_override("h_separation", 8)
	apps.add_theme_constant_override("v_separation", 2)
	for role in Sim.ROLES:
		var have: int = st.crew.filter(func(m): return m.role == role).size()
		var cap := sim.role_cap(st, role)
		for a in st.applicants.filter(func(x): return x.role == role):
			apps.add_child(label("%s %d/%d" % [ROLE_ICON[role], have, cap], MUTED))
			apps.add_child(member_label(a, 280, false))
			var fee := Sim.rnd(a.wage * sim.mods().wage)
			var hb := small_button("HIRE %s" % yen(fee), staff_act.bind("hire", a.id))
			hb.disabled = have >= cap or sim.player.cash < fee
			apps.add_child(hb)
	var right := VBoxContainer.new()
	right.add_child(label("APPLICANTS TODAY", INK, 15))
	right.add_child(apps)
	cols.add_child(right)
	v.add_child(button("CLOSE  [Esc]", close_staff))
	open_modal("STAFF  ·  %s" % b.name.to_upper(), v, {KEY_ESCAPE: close_staff, KEY_S: close_staff}, "staff")


func small_button(text: String, cb: Callable) -> Button:
	var b := button(text, cb)
	b.add_theme_font_size_override("font_size", 11)
	b.custom_minimum_size = Vector2(76, 24)
	b.add_theme_stylebox_override("normal", box(PAPER, INK, 2, 2))
	b.add_theme_stylebox_override("hover", box(Color("e3f3e8"), INK, 2, 2))
	b.add_theme_stylebox_override("disabled", box(Color("ebe6da"), LINE, 2, 2))
	return b


func member_label(m: Dictionary, w: int, role := true) -> Label:
	var trait_def: Dictionary = Sim.TRAITS[m.trait_id]
	var l := label("%s%s, %s%s  %s/day" % [(ROLE_ICON[m.role] + "  ") if role else "", m.name, trait_def.name, (" (%s)" % trait_def.desc) if trait_def.has("desc") else "", yen(Sim.rnd(m.wage * sim.mods().wage))])
	l.custom_minimum_size.x = w
	l.clip_text = true
	l.tooltip_text = l.text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.add_theme_font_size_override("font_size", 11)
	return l


func staff_act(type: String, id: int) -> void:
	sim.act({"type": type, "id": id})
	drain()
	show_staff()


func close_staff() -> void:
	close_modal()
	ui_t = 0.0


func show_report(r: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var g := GridContainer.new()
	g.columns = 8
	g.add_theme_constant_override("h_separation", 14)
	for h in ["STORE", "SALES", "SERVED", "LOST", "STOCK", "RENT+WAGES", "NET", "RIVAL"]:
		g.add_child(label(h, MUTED))
	for row in r.rows:
		var s: Dictionary = row.stats
		var cells := [row.name, yen(s.revenue), str(s.customers), str(s.lost), "-" + yen(s.restock + s.fines), "-" + yen(row.rent + row.wages), yen(row.net), "closed" if row.defeated else "%d%%" % roundi(100.0 * row.rival_hp / row.rival_max)]
		for k in cells.size():
			g.add_child(label(cells[k], (GREEN if row.net >= 0 else RED) if k == 6 else INK))
	v.add_child(g)
	if r.interest > 0:
		v.add_child(label("Interest +%s" % yen(r.interest), GREEN))
	v.add_child(label("Bills paid %s" % yen(r.bills), INK))
	var h := HBoxContainer.new()
	var a := label("Cash", INK, 24)
	a.custom_minimum_size.x = 120
	h.add_child(a)
	h.add_child(label("%s  >  %s" % [yen(r.cash_before), yen(r.cash_after)], GREEN if r.cash_after >= r.cash_before else RED, 24))
	v.add_child(h)
	if r.foreclosed != null:
		v.add_child(label("You ran short: the bank took %s and paid back %s." % [r.foreclosed.name, yen(r.foreclosed.value)], RED))
	v.add_child(label("Tomorrow's bills: about %s." % yen(sim.bills_due()), MUTED))
	var go := func():
		close_modal()
		view.show_branch(sim.active)
		ui_t = 0.0
	v.add_child(button("NEXT DAY  [Space]", go))
	open_modal("DAY %d CLOSED" % r.day, v, {KEY_SPACE: go, KEY_ENTER: go}, "report")


func show_over() -> void:
	var rs: Dictionary = sim.run_stats
	var score: int = rs.days * 5000 + rs.revenue
	var prev: int = best.get_value("best", "score", 0)
	if score > prev:
		best.set_value("best", "score", score)
		best.save("user://best.cfg")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(label("Midnight bills of %s bounced. The landlord changed the locks." % yen(sim.summary.bills), RED))
	for l in [
		"Days survived: %d" % rs.days,
		"Revenue: %s from %s customers" % [yen(rs.revenue), Sim.money(rs.customers)],
		"Rivals closed: %d    Threats repelled: %d" % [rs.rivals_defeated, rs.threats_repelled],
		"Stores opened: %d (peak %d at once)%s" % [rs.stores_opened, rs.peak_stores, "" if rs.foreclosed == 0 else ", %d foreclosed" % rs.foreclosed],
		"Level %d    Seed %s" % [sim.player.level, sim.seed_text],
	]:
		v.add_child(label(l))
	v.add_child(label("Score %s%s" % [Sim.money(score), "  NEW BEST" if score > prev else "  (best %s)" % Sim.money(prev)], GREEN if score > prev else MUTED, 16))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var again := func(): new_run(sim.seed_text)
	var fresh := func(): new_run("")
	h.add_child(button("RETRY SEED", again))
	h.add_child(button("NEW RUN  [Space]", fresh))
	v.add_child(h)
	open_modal("BANKRUPT", v, {KEY_SPACE: fresh, KEY_ENTER: fresh}, "over")


func show_new_run() -> void:
	if modal_kind in ["report", "over"]:
		return
	var v := VBoxContainer.new()
	v.add_child(label("Same seed, same street, same rivals and cards. Leave blank for a random run.", MUTED))
	var edit := LineEdit.new()
	edit.placeholder_text = "seed"
	edit.custom_minimum_size.x = 300
	v.add_child(edit)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var start := func(): new_run(edit.text)
	edit.text_submitted.connect(func(_t): start.call())
	h.add_child(button("START", start))
	var prev := modal_kind
	var cancel := func():
		close_modal()
		if prev == "intro":
			show_intro()
		elif sim.phase == "choice":
			show_choice()
	h.add_child(button("CANCEL", cancel))
	v.add_child(h)
	open_modal("NEW RUN", v, {KEY_ESCAPE: cancel}, "seed")
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
	if view.mode == "city" and k == KEY_ESCAPE:
		toggle_city()
		return
	match k:
		KEY_SPACE:
			toggle_hold()
		KEY_F:
			cycle_speed()
		KEY_TAB:
			select_store((sim.active + 1) % sim.branches.size())
		KEY_M:
			toggle_city()
		KEY_S:
			show_staff()
		KEY_G:
			act_open("openExpansion")
		KEY_N:
			act_open("openListings")
		KEY_P:
			open_pick()
		KEY_R:
			var b: Dictionary = sim.branches[sim.active]
			for reg in b.store.registers:
				if reg.active and not reg.queue.is_empty():
					var a = sim.agent_by_id(b, reg.queue[0])
					if a != null and a.at_head:
						do_act({"type": "ringUp", "register": reg.id})
						break
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			do_act({"type": "useAbility", "id": ABILITY_KEYS[k - KEY_1]})
