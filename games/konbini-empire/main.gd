extends Control
## Konbini Empire UI: builds every control in code, runs the sim in real time (pausing for cards and reports) and
## turns clicks and keys into sim actions.

const Sim := preload("res://sim.gd")
const StoreView := preload("res://store_view.gd")
const Audio := preload("res://audio.gd")

# island-life palette: cream bubbles, cocoa text, mint tags, a yellow highlight under the pointer
const INK := Color("6b5236")
const PAPER := Color("fffaea")
const GROUND := Color("f3e9cc")
const LINE := Color("e6d7b0")
const GREEN := Color("3f9e4a")
const ORANGE := Color("e98a1d")
const RED := Color("e05a4e")
const BLUE := Color("1f9e8e")
const MUTED := Color("a08c69")
const MINT := Color("4fc4ab")
const YELLOW := Color("fbe27c")
const SHADOW := Color(0.42, 0.3, 0.15, 0.25)
const RARITY_COLOR := {"common": Color("a08c69"), "rare": Color("3a9bd9"), "epic": Color("a36fd6"), "legendary": Color("e8a317")}
const DISTRICT_COLOR := {"sakura": Color("d9708f"), "campus": Color("3a9bd9"), "onsen": Color("e0903a"), "ekimae": Color("1f9e8e"), "neon": Color("8a5cc8")}
const ABILITY_KEYS := ["flyer", "timeSale", "counter", "influencer", "truck"]
const ABILITY_ICON := {"flyer": 1, "timeSale": 11, "counter": 4, "influencer": 9, "truck": 7}  # perks.png frames
const CARD_ICON := {  # [sheet, frame] for each card's picture; product lines use their product, abilities their key
	"charm": ["perks", 0], "premium": ["perks", 8], "swift": ["perks", 10], "learner": ["decor", 8], "spirit": ["perks", 1],
	"bulk": ["perks", 7], "bow": ["perks", 0], "impulse": ["perks", 0], "maneki": ["perks", 9], "nightOwl": ["decor", 9],
	"earlyBird": ["perks", 3], "upsell": ["perks", 11], "pointCard": ["perks", 4], "comboMaster": ["perks", 10], "thickSkin": ["perks", 6],
	"hotStreak": ["perks", 5], "negotiator": ["perks", 11], "hr": ["perks", 0], "teamSpirit": ["perks", 0], "spotless": ["decor", 0],
	"investor": ["perks", 11], "goldenHour": ["decor", 4], "omotenashi": ["perks", 0], "cat": ["perks", 9],
	"floor": ["decor", 7], "neon": ["perks", 8], "register2": ["perks", 10], "bigShelves": ["perks", 2], "vending": ["decor", 2],
	"gacha": ["decor", 3], "atm": ["decor", 6], "bench": ["decor", 1], "camera": ["perks", 6], "delivery": ["perks", 7],
	"r_franchise": ["perks", 8], "r_warchest": ["perks", 11], "r_killer": ["decor", 5], "r_express": ["perks", 10], "r_scholar": ["decor", 8],
	"r_hq": ["perks", 0], "r_logistics": ["perks", 7], "r_brand": ["perks", 1], "r_academy": ["perks", 0],
}
const ROLE_ICON := {"cashier": "TILL", "stocker": "STOCK", "cleaner": "CLEAN", "guard": "GUARD", "promoter": "PROMO"}
const ROLE_COLOR := {"cashier": Color("e98a1d"), "stocker": Color("3f9e4a"), "cleaner": Color("3a9bd9"), "guard": Color("7a68c8"), "promoter": Color("e0609a")}
const CARD_W := 232  # the store card in the top-right corner

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
var audio: Audio
var sound_btn: Button
var bold: FontVariation
var toasts: Array = []  # [text, color, seconds left]
var ui_t := 0.0
var shelf_sig := ""

var lbl_cash: Label
var lbl_level: Label
var xp_bar: ProgressBar
var lbl_rating: Label
var lbl_bills: Label
var bills_chip: PanelContainer
var speed_btn: Button
var pause_btn: Button
var seed_btn: Button
var tabs: HBoxContainer
var ability_row: HBoxContainer
var pick_btn: Button
var pick_badge: Label
var info: Label
var info_lines: Array = []
var head: Label
var kind_chip: PanelContainer
var kind_lbl: Label
var quirk_lbl: Label
var card_stats := {}  # stat name -> its row on the store card's well
var event_tag: PanelContainer
var event_lbl: Label
var rival_chip: PanelContainer
var rival_name: Label
var rival_tier: Label
var rival_lbl: Label
var rival_bar: ProgressBar
var shelf_box: GridContainer
var store_card: PanelContainer
var staff_btn: Button
var grow_btn: Button
var store_btn: Button
var city_btn: Button
var banner: Label
var dev_js: JavaScriptObject  # keeps the web build's dev hook alive


func _ready() -> void:
	for n in ["products", "perks", "decor", "outdoor", "vehicles", "walk", "storefronts", "landmarks", "tokyo", "bg_konbini", "props"]:
		tex[n] = load("res://art/%s.png" % n)
	theme = make_theme()
	best.load("user://best.cfg")
	audio = Audio.new()
	add_child(audio)
	build()
	new_run("")
	if OS.has_feature("web") and "dev" in str(JavaScriptBridge.eval("location.search")):
		dev_js = JavaScriptBridge.create_callback(dev_eval)
		JavaScriptBridge.get_interface("window").konbiniEval = dev_js


## Web build opened with ?dev: window.konbiniEval(code) runs GDScript as the body of
## func run(main) and leaves its return value, as a string, in window.konbiniResult.
func dev_eval(args: Array) -> void:
	var s := GDScript.new()
	s.source_code = "extends RefCounted\nfunc run(main):\n\t" + str(args[0]).replace("\n", "\n\t")
	var out = "compile error"
	if s.reload() == OK:
		out = s.new().run(self)
	JavaScriptBridge.get_interface("window").konbiniResult = str(out)


# ---------- theme & widget helpers ----------

## A rounded bubble: `lip` darkens the bottom edge like a pressable key, `shadow` lifts it off the page.
func box(bg: Color, radius := 12, pad := 6, lip := 0, shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.border_width_bottom = lip
	s.border_color = bg.darkened(0.16)
	s.shadow_size = shadow
	s.shadow_offset = Vector2(0, shadow / 2.0)
	s.shadow_color = SHADOW
	return s


func pill_box(bg: Color, lip := 3, shadow := 2) -> StyleBoxFlat:
	var s := box(bg, 14, 4, lip, shadow)
	s.content_margin_left = 12
	s.content_margin_right = 12
	return s


func make_theme() -> Theme:
	var th := Theme.new()
	var f: FontFile = load("res://fonts/Nunito.ttf")
	f.fallbacks = [load("res://fonts/NotoSans-Regular.ttf"), load("res://fonts/NotoSansMath-Symbols.ttf")]  # ō ū ∞, then ★ ♪ ▾ (no system fonts on the web)
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")  # a "wght" string key is ignored
	var regular := FontVariation.new()
	regular.base_font = f
	regular.variation_opentype = {wght: 700}
	bold = FontVariation.new()
	bold.base_font = f
	bold.variation_opentype = {wght: 900}
	th.default_font = regular
	th.default_font_size = 13
	th.set_font("font", "Button", bold)
	th.set_stylebox("normal", "Button", pill_box(PAPER))
	th.set_stylebox("hover", "Button", pill_box(YELLOW))
	th.set_stylebox("pressed", "Button", pill_box(YELLOW.darkened(0.06), 1, 1))
	th.set_stylebox("disabled", "Button", pill_box(Color("f1e8d2"), 0, 0))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		th.set_color(c, "Button", INK)
	th.set_color("font_disabled_color", "Button", Color("cdbd9a"))
	th.set_color("icon_disabled_color", "Button", Color(1, 1, 1, 0.35))
	th.set_stylebox("panel", "PanelContainer", box(PAPER, 20, 12, 0, 5))
	th.set_color("font_color", "Label", INK)
	th.set_constant("line_spacing", "Label", -2)  # Nunito's own line gap is already loose; Godot's +3 made wrapped text read double-spaced
	var field := box(Color.WHITE, 14, 8)
	field.set_border_width_all(2)
	field.border_color = LINE
	th.set_stylebox("normal", "LineEdit", field)
	var focus: StyleBoxFlat = field.duplicate()
	focus.border_color = MINT
	th.set_stylebox("focus", "LineEdit", focus)
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", MUTED)
	th.set_stylebox("panel", "TooltipPanel", box(INK, 10, 6))
	th.set_color("font_color", "TooltipLabel", PAPER)
	th.set_stylebox("background", "ProgressBar", box(Color("ece0c0"), 4, 0))
	th.set_stylebox("fill", "ProgressBar", box(MINT, 4, 0))
	th.set_stylebox("scroll", "VScrollBar", box(Color("f1e8d2"), 4, 0))
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		th.set_stylebox(k, "VScrollBar", box(LINE.darkened(0.1), 4, 0))
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
	b.pressed.connect(audio.play.bind("click"))
	b.pressed.connect(cb)
	return b


func progress(color: Color, h := 8) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size.y = h
	p.max_value = 1.0
	p.add_theme_stylebox_override("fill", box(color, roundi(h / 2.0), 0))
	p.add_theme_stylebox_override("background", box(Color("ece0c0"), roundi(h / 2.0), 0))
	return p


## A cream tag holding a few widgets, for the floating HUD.
func chip(parts: Array, bg := PAPER) -> PanelContainer:
	var p := PanelContainer.new()
	var s := pill_box(bg, 0, 3)
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in parts:
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(c)
	p.add_child(h)
	return p


## A name tag: a label on a colored pill, tilted a little.
func tag(l: Label, bg: Color) -> PanelContainer:
	var p := chip([l], bg)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.rotation = deg_to_rad(-2.5)
	return p


func frame(sheet: String, i: int, cell: int) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = tex[sheet]
	t.region = Rect2(i * cell, 0, cell, cell)
	return t


## The pending-card key's picture: three cards fanned out from their foot, cream with an amber band, the front one starred.
func card_fan() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var bands := [MINT, ORANGE, Color("e57fa4")]
	for y in n:
		for x in n:
			var c := Color(0, 0, 0, 0)
			for i in [0, 2, 1]:  # the middle card last, in front
				var a := deg_to_rad((i - 1) * 20.0)
				var q := Vector2(x + 0.5 - 32, y + 0.5 - 58).rotated(-a) + Vector2(0, 26)  # the card's own frame, its centre at 0
				var d := Vector2(absf(q.x) - 11, absf(q.y) - 17)
				var sd := Vector2(maxf(d.x, 0), maxf(d.y, 0)).length() + minf(maxf(d.x, d.y), 0.0) - 3.0  # rounded box, r 3
				var cov := clampf(0.5 - sd, 0.0, 1.0)
				if cov <= 0.0:
					continue
				var f: Color = INK if sd > -2.0 else (bands[i] if q.y < -8 else PAPER)
				if i == 1 and q.y >= -8 and sd <= -2.0 and absf(q.x) + absf(q.y - 6) * 0.9 < 6:
					f = ORANGE
				c = c.blend(Color(f, cov))
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## A key with its icon over a short caption: cream for abilities and shelves, colored (white caption) for the app dock.
func key_button(cb: Callable, tip: String, ic: Texture2D, w: int, h: int, radius: int, c := PAPER) -> Button:
	var b := button("", cb, tip)
	b.custom_minimum_size = Vector2(w, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_END
	b.icon = ic
	b.expand_icon = true  # otherwise the 80 px frame sets the key's height
	b.add_theme_constant_override("icon_max_width", 26)
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 11)
	for k in ["normal", "hover", "pressed", "disabled"]:
		var s: StyleBoxFlat = theme.get_stylebox(k, "Button").duplicate()
		if c != PAPER:
			if k == "disabled":  # a faded, flat key in its own color, so the dock keeps its colors
				s = box(c.lerp(Color("f1e8d2"), 0.55), radius, 4, 2, 0)
			else:
				s = box(c.lightened(0.15) if k == "hover" else c, radius, 4, 1 if k == "pressed" else 3, 1 if k == "pressed" else 2)
		s.set_corner_radius_all(radius)
		s.set_content_margin_all(4)
		b.add_theme_stylebox_override(k, s)
	if c != PAPER:
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, Color.WHITE)
		b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.85))
		b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.6))
	return b


## A locked ability key sinks into a well with its art pressed in one tone; one cooling down keeps its art and counts down
## in orange under the wipe, so the two no longer look the same.
func ability_look(a: Button, state: String) -> void:
	if a.get_meta("look", "") == state:
		return
	a.set_meta("look", state)
	if not a.has_meta("art"):
		a.set_meta("art", a.icon)
		a.set_meta("shape", silhouette(a.icon))
	var off: StyleBoxFlat
	if state == "locked":
		off = box(Color("eee1bd"), 27, 4)
		off.border_width_top = 4  # the well's lip shades its top inside, so it reads pressed into the HUD
		off.border_width_left = 1
		off.border_width_right = 1
		off.border_color = Color("d3bd8a")
		off.corner_detail = 16
		a.icon = a.get_meta("shape")
		a.add_theme_color_override("icon_disabled_color", Color("dcc797"))
		a.add_theme_color_override("font_disabled_color", Color("a99062"))
	else:
		off = box(PAPER, 27, 4, 1, 1)
		a.icon = a.get_meta("art")
		a.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.8))
		a.add_theme_color_override("font_disabled_color", ORANGE if state == "cooling" else MUTED)
	a.add_theme_stylebox_override("disabled", off)


## The art in one tone, its shading kept as light and dark of white for a modulate to tint, its soft halo cut off.
func silhouette(t: AtlasTexture) -> ImageTexture:
	var img := t.atlas.get_image().get_region(Rect2i(t.region))
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var v := lerpf(0.7, 1.0, c.get_luminance())
			img.set_pixel(x, y, Color(v, v, v, smoothstep(0.35, 0.65, c.a)))
	return ImageTexture.create_from_image(img)


## Anchors a HUD group to a screen edge or corner; `o` holds the left, top, right and bottom offsets.
func pin(c: Control, preset: Control.LayoutPreset, o: Rect2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = o.position.x
	c.offset_top = o.position.y
	c.offset_right = o.size.x
	c.offset_bottom = o.size.y
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if c.anchor_left == 1.0 else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if c.anchor_top == 1.0 else Control.GROW_DIRECTION_END


func picture(sheet: String, i: int, cell: int, min_size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = frame(sheet, i, cell)
	r.custom_minimum_size = min_size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return r


func product_frame(pid: String) -> AtlasTexture:
	var ic: Array = Sim.PRODUCTS[pid].icon
	return frame(ic[0], ic[1], {"products": 64, "perks": 80, "decor": 96}[ic[0]])


func icon(pid: String, px: float) -> TextureRect:
	var r := picture("products", 0, 64, Vector2(px, px))
	r.texture = product_frame(pid)
	return r


func yen(v: int) -> String:
	return ("-¥" if v < 0 else "¥") + Sim.money(absi(v))


func stars(r: float) -> String:
	return "%.1f★" % r


# ---------- layout ----------

## The street fills the screen and the HUD floats over it in bubbles: money and level up top, a small store card
## under them, store tabs, abilities, a speech bubble and the app dock at the bottom. The view draws the clock.
func build() -> void:
	var bg := ColorRect.new()
	bg.color = GROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	view = StoreView.new()
	view.tex = tex
	view.bold = bold
	view.set_anchors_preset(Control.PRESET_FULL_RECT)  # wider or taller windows see more street
	view.clip_contents = true
	view.sim = sim
	view.act_requested.connect(do_act)
	view.lot_clicked.connect(on_lot)
	add_child(view)

	var top := HBoxContainer.new()
	pin(top, Control.PRESET_TOP_WIDE, Rect2(214, 8, -8, 38))
	top.alignment = BoxContainer.ALIGNMENT_END
	top.add_theme_constant_override("separation", 6)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	lbl_cash = label("", INK, 16)
	lbl_level = label("", INK, 15)
	xp_bar = progress(MINT)
	xp_bar.custom_minimum_size.x = 56
	lbl_rating = label("", INK, 15)
	lbl_bills = label("", INK)
	bills_chip = chip([lbl_bills])
	for c in [chip([picture("perks", 11, 80, Vector2(22, 22)), lbl_cash]), chip([lbl_level, xp_bar]), chip([lbl_rating]), bills_chip]:
		top.add_child(c)
	var clock_row := HBoxContainer.new()  # under the clock the view draws
	clock_row.position = Vector2(16, 92)
	clock_row.add_theme_constant_override("separation", 6)
	clock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clock_row)
	pause_btn = button("II", toggle_hold, "Pause  [Space]")
	speed_btn = button("1x", cycle_speed, "Game speed  [F]")
	sound_btn = button("", cycle_sound, "Sound: on, music off, muted  [V]")
	seed_btn = button("", show_new_run, "Start a new run (you can type a seed)")
	seed_btn.add_theme_font_size_override("font_size", 11)
	seed_btn.add_theme_color_override("font_color", MUTED)
	for b in [pause_btn, speed_btn, sound_btn, seed_btn]:
		b.custom_minimum_size = Vector2(40, 28)
		clock_row.add_child(b)
	cycle_sound(best.get_value("settings", "sound", 0))
	banner = label("", PAPER, 15)
	banner.add_theme_stylebox_override("normal", pill_box(INK, 0, 3))
	banner.position.y = 48
	add_child(banner)

	var bottom := VBoxContainer.new()
	pin(bottom, Control.PRESET_BOTTOM_WIDE, Rect2(10, -140, -10, -10))  # contents sit at its bottom, 10 px off the edge
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(tabs)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(row)
	ability_row = HBoxContainer.new()
	ability_row.add_theme_constant_override("separation", 6)
	ability_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ability_row)
	var disc := Image.create(54, 54, false, Image.FORMAT_RGBA8)
	for y in 54:
		for x in 54:
			disc.set_pixel(x, y, Color(INK, 0.3 * clampf(26.5 - Vector2(x - 26.5, y - 26.5).length(), 0.0, 1.0)))
	var wipe_tex := ImageTexture.create_from_image(disc)
	for i in ABILITY_KEYS.size():
		var k := key_button(do_act.bind({"type": "useAbility", "id": ABILITY_KEYS[i]}), "", frame("perks", ABILITY_ICON[ABILITY_KEYS[i]], 80), 54, 54, 27)
		var wipe := TextureProgressBar.new()  # the cooldown still to run, shrinking round the key like a clock hand
		wipe.texture_progress = wipe_tex
		wipe.fill_mode = TextureProgressBar.FILL_COUNTER_CLOCKWISE
		wipe.step = 0.0
		wipe.nine_patch_stretch = true
		wipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wipe.set_anchors_preset(Control.PRESET_FULL_RECT)
		k.add_child(wipe)
		ability_row.add_child(k)
	pick_btn = key_button(open_pick, "Choose your level-up skill or reward  [P]", card_fan(), 70, 54, 18, Color("ffc94a"))
	pick_btn.add_theme_constant_override("icon_max_width", 32)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		pick_btn.add_theme_color_override(k, Color("6b4512"))
	pick_btn.text = "New card"
	pick_badge = label("", Color.WHITE, 11)
	pick_badge.add_theme_font_override("font", bold)
	pick_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bs := box(RED, 10, 0, 0, 2)
	bs.set_border_width_all(2)
	bs.border_color = PAPER
	pick_badge.add_theme_stylebox_override("normal", bs)
	pick_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pick_badge.set_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE)
	pick_badge.offset_left = -14
	pick_badge.offset_right = 7
	pick_badge.offset_top = -7
	pick_badge.offset_bottom = 14
	pick_btn.add_child(pick_badge)
	row.add_child(pick_btn)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", box(PAPER, 20, 8, 0, 4))
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bubble.size_flags_vertical = Control.SIZE_SHRINK_END
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bubble)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(bh)
	bh.add_child(picture("perks", 0, 80, Vector2(38, 38)))
	info = label("", INK)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.max_lines_visible = 3
	info.add_theme_font_size_override("font_size", 11)
	info.add_theme_constant_override("line_spacing", -3)
	bh.add_child(info)
	info.text = "\n\n"
	info.custom_minimum_size = Vector2(150, info.get_minimum_size().y)  # always three lines tall, so the tabs above never jump
	info.resized.connect(fit_info)
	var dock := HBoxContainer.new()
	dock.add_theme_constant_override("separation", 6)
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dock)
	staff_btn = key_button(show_staff, "", frame("perks", 0, 80), 62, 54, 18, Color("ee9234"))
	grow_btn = key_button(act_open.bind("openExpansion"), "", frame("perks", 2, 80), 62, 54, 18, Color("5aae55"))
	store_btn = key_button(act_open.bind("openListings"), "", frame("perks", 10, 80), 62, 54, 18, Color("4a9fdc"))
	city_btn = key_button(toggle_city, "Tokyo map: your branches and their rivals  [M]", frame("outdoor", 2, 128), 62, 54, 18, Color("e57fa4"))
	staff_btn.text = "Staff"
	grow_btn.text = "Expand"
	store_btn.text = "Store"
	for b in [staff_btn, grow_btn, store_btn, city_btn]:
		dock.add_child(b)

	# the store card: only as tall as its content, so the street keeps the rest of the screen
	store_card = PanelContainer.new()
	store_card.add_theme_stylebox_override("panel", box(PAPER, 20, 10, 0, 5))
	pin(store_card, Control.PRESET_TOP_RIGHT, Rect2(-8 - CARD_W, 46, -8, 46))
	add_child(store_card)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	store_card.add_child(sv)
	head = label("", Color.WHITE, 16)
	# the day's event rides beside the branch's name, amber like the clock's rush tag, wrapping under it when both don't fit
	var heads := HFlowContainer.new()
	heads.add_theme_constant_override("h_separation", 6)
	heads.add_theme_constant_override("v_separation", 4)
	heads.add_child(tag(head, MINT))
	event_lbl = label("", Color("6b4512"), 12)
	event_lbl.add_theme_font_override("font", bold)
	event_tag = tag(event_lbl, Color("ffc94a"))
	event_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heads.add_child(event_tag)
	sv.add_child(heads)
	# the lot's neighbourhood and quirk as tags, like its card in the listings, over a well of the day's numbers
	var kinds := HFlowContainer.new()
	kinds.add_theme_constant_override("h_separation", 6)
	kinds.add_theme_constant_override("v_separation", 4)
	kind_lbl = label("", Color.WHITE, 11)
	kind_chip = chip([kind_lbl])
	kinds.add_child(kind_chip)
	quirk_lbl = label("", INK, 11)
	kinds.add_child(chip([quirk_lbl], GROUND))
	for c in kinds.get_children():
		var cs: StyleBoxFlat = c.get_theme_stylebox("panel")
		cs.content_margin_left = 8
		cs.content_margin_right = 8
	sv.add_child(kinds)
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 14)
	stats.add_theme_constant_override("v_separation", -2)
	for k in ["Rent", "Served", "Wages", "Lost", "Regulars"]:
		var r := roll_line(k, "", INK, 11)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_stats[k] = r
		stats.add_child(r)
	var well := sunken(stats)
	var ws: StyleBoxFlat = well.get_theme_stylebox("panel")
	ws.set_corner_radius_all(12)
	ws.content_margin_left = 10
	ws.content_margin_right = 10
	ws.content_margin_top = 4
	ws.content_margin_bottom = 4
	sv.add_child(well)
	rival_name = label("", Color.WHITE, 12)
	rival_tier = label("", Color(1, 1, 1, 0.8), 11)
	rival_chip = chip([rival_name, rival_tier], RED)
	rival_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sv.add_child(rival_chip)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 6)
	rival_bar = progress(RED, 8)
	rival_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rival_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rrow.add_child(rival_bar)
	rival_lbl = label("", MUTED, 11)
	rival_lbl.size_flags_horizontal = Control.SIZE_SHRINK_END
	rrow.add_child(rival_lbl)
	sv.add_child(rrow)
	shelf_box = GridContainer.new()
	shelf_box.columns = 4
	shelf_box.add_theme_constant_override("h_separation", 4)
	shelf_box.add_theme_constant_override("v_separation", 4)
	sv.add_child(shelf_box)


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
	view.hud_card = Rect2(store_card.global_position - view.global_position, store_card.size) if store_card.visible else Rect2()
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
		sound(e, where == "")
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


## An event's sound: street noise only from the store on screen, good and bad news from any of them.
func sound(e: Dictionary, here: bool) -> void:
	match e.type:
		"sale":
			if here and not e.passive:
				audio.play("sale", randf_range(0.94, 1.08), 0.09)
		"enter":
			if here:
				audio.play("door", 1.0, 0.6)
		"combo":
			if here:
				audio.play("scan", 1.0 + 0.06 * mini(e.count - 1, 8), 0.0)
		"threatHit":
			audio.play("shoo")
		"repelled", "cleaned":
			audio.play("poof")
		"telegraph":
			if here:
				audio.play("alert")
		"attack":
			if here:
				audio.play("attack")
		"restock":
			if here:
				audio.play("restock", 1.0, 0.2)
		"ability":
			audio.play("ability")
		"levelUp":
			audio.play("levelup")
		"rivalDefeated", "milestone", "storeOpened":
			audio.play("fanfare")
		"hired", "reroll":
			audio.play("card")
		"poached":
			if here:
				audio.play("bad", 1.0, 1.5)
		"cantAfford", "reviewPosted", "stolen", "takeoverHit":
			if here:
				audio.play("bad")
		"cantAffordHire", "cantAffordStore", "cantAffordExpansion", "roleFull", "storeCap", "foreclosed":
			audio.play("bad")


func cycle_sound(m := -1) -> void:
	audio.set_mode((audio.mode + 1) % 3 if m < 0 else m)
	sound_btn.text = ["♪", "♪ sfx", "mute"][audio.mode]
	sound_btn.tooltip_text = "%s  [V]" % Audio.MODES[audio.mode]
	best.set_value("settings", "sound", audio.mode)
	best.save("user://best.cfg")


## Fits the bubble's three lines: older toasts drop off first, then the type shrinks, so the newest line is never cut off.
func fit_info() -> void:
	var lines := info_lines.slice(maxi(0, info_lines.size() - 3))
	info.add_theme_font_size_override("font_size", 11)
	info.text = info_text(lines, 11)
	while lines.size() > 1 and info.get_line_count() > 3:
		lines.pop_front()
		info.text = info_text(lines, 11)
	for px in [10, 9]:
		if info.get_line_count() <= 3:
			break
		info.add_theme_font_size_override("font_size", px)
		info.text = info_text(lines, px)


## The bubble's lines at px, each key hint like "[P]" that would wrap onto a line of its own taking the word before it along.
func info_text(lines: Array, px: int) -> String:
	var out := []
	for line: String in lines:
		var at := line.rfind("  [")
		if at > 0:
			var p := TextParagraph.new()
			p.add_string(line, info.get_theme_font("font"), px)
			p.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
			p.width = info.size.x
			var cut := line.rfind(" ", at - 1)
			if p.get_line_count() > 1 and p.get_line_range(p.get_line_count() - 1).x > at and cut > 0:
				line = line.substr(0, cut) + "\n" + line.substr(cut + 1)
		out.append(line)
	return "\n".join(out)


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
		audio.play("card")
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
	if audio:
		audio.set_focused(focused)


# ---------- HUD ----------

func refresh_ui() -> void:
	if sim.branches.is_empty():
		return
	var b: Dictionary = sim.branches[sim.active]
	var st: Dictionary = b.store
	if sim.phase != "gameOver":
		audio.follow(Sim.band(sim.hour()).name)
	lbl_cash.text = yen(sim.player.cash)
	lbl_level.text = "Lv %d" % sim.player.level
	xp_bar.value = sim.player.xp / sim.player.xp_next
	lbl_rating.text = stars(st.rating)
	var bills := sim.bills_due()
	var short: bool = sim.player.cash < bills
	lbl_bills.text = "Bills tonight %s" % yen(bills)
	lbl_bills.add_theme_color_override("font_color", Color.WHITE if short else INK)
	(bills_chip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = RED if short else PAPER
	seed_btn.text = "Seed %s  ·  new run" % sim.seed_text
	speed_btn.text = "%dx" % speed
	pause_btn.text = ">" if held else "II"
	banner.text = "Paused  [Space]" if held else ("Click a numbered lot  ·  Esc to go back" if view.pick == "listing" and view.mode == "city" else "")
	banner.visible = banner.text != ""
	banner.reset_size()
	banner.position.x = (size.x - banner.size.x) / 2.0

	if tabs.get_child_count() != sim.branches.size():
		for c in tabs.get_children():
			c.queue_free()
		for i in sim.branches.size():
			var t := button("", select_store.bind(i), "Switch store  [Tab]")
			t.custom_minimum_size.y = 26
			tabs.add_child(t)
	for i in sim.branches.size():
		var o: Dictionary = sim.branches[i]
		var t: Button = tabs.get_child(i)
		var alert := ""
		if o.threats.any(func(x): return x.type != "spill") or o.rival.telegraph != "":
			alert = " !"
		if o.store.products.values().any(func(p): return float(p.stock) / p.capacity < Sim.LOW_STOCK):
			alert += " ▾"
		t.text = "%d  %s%s" % [i + 1, o.name, alert]
		t.add_theme_stylebox_override("normal", pill_box(MINT if i == sim.active else PAPER))
		t.add_theme_color_override("font_color", Color.WHITE if i == sim.active else (RED if alert != "" else INK))

	for i in ABILITY_KEYS.size():
		var id: String = ABILITY_KEYS[i]
		var a: Button = ability_row.get_child(i)
		var ab = sim.player.abilities.get(id)
		var def: Dictionary = Sim.ABILITIES[id]
		var wipe: TextureProgressBar = a.get_child(0)
		if ab == null:
			a.text = "%d" % (i + 1)
			a.disabled = true
			a.tooltip_text = "%s: unlock it from a level-up card." % def.name
			wipe.value = 0.0
		else:
			a.text = "%d · %s" % [i + 1, "I".repeat(ab.level)] if ab.cd <= 0.0 else "%ds" % ceili(ab.cd)
			a.disabled = ab.cd > 0.0 or sim.phase != "playing"
			a.tooltip_text = "%s (level %d)  [%d]" % [def.name, ab.level, i + 1]
			wipe.max_value = def.cd[ab.level - 1]
			wipe.value = ab.cd
		ability_look(a, "locked" if ab == null else ("cooling" if ab.cd > 0.0 else "ready"))
	pick_btn.visible = not sim.pending.is_empty()
	pick_badge.text = str(sim.pending.size())
	var lines := toasts.map(func(t): return t[0])
	if lines.is_empty():
		lines = [hint(b)]
	if lines != info_lines:
		info_lines = lines
		fit_info()
	info.add_theme_color_override("font_color", toasts[-1][1] if not toasts.is_empty() else INK)

	head.text = b.name
	var d: Dictionary = Sim.DISTRICTS[b.district]
	event_tag.visible = b.event != null
	if b.event != null:
		event_lbl.text = Sim.EVENTS[b.event.id].name
	kind_lbl.text = d.name
	(kind_chip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = DISTRICT_COLOR[b.district]
	quirk_lbl.text = Sim.QUIRKS[b.quirk].name
	card_stat("Rent", yen(sim.rent(b)), INK)
	card_stat("Wages", yen(sim.wages(b)), INK)
	card_stat("Served", str(b.day_stats.customers), GREEN if b.day_stats.customers > 0 else INK)
	card_stat("Lost", str(b.day_stats.lost), RED if b.day_stats.lost > 0 else INK)
	card_stat("Regulars", "%d due" % b.regulars, BLUE)
	card_stats.Regulars.visible = b.regulars > 0
	var rv: Dictionary = b.rival
	var chain := Color(Sim.RIVALS[rv.id].color)
	rival_name.text = Sim.RIVALS[rv.id].name
	(rival_chip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Color("a99f8c") if rv.defeated else chain.darkened(0.1)
	rival_bar.visible = not rv.defeated
	if rv.defeated:
		rival_tier.text = "closed"
		rival_lbl.text = "new rival %s" % ("tomorrow" if 2 - rv.closed_days == 1 else "in %d days" % (2 - rv.closed_days))
	else:
		rival_tier.text = "Tier %d" % rv.tier
		rival_lbl.text = "%s / %s" % [Sim.money(ceili(rv.hp)), Sim.money(int(rv.max_hp))]
		rival_bar.value = rv.hp / rv.max_hp
		(rival_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = chain
	refresh_shelves(b)
	store_card.visible = view.mode == "store"  # the map gets the whole screen
	store_card.size = Vector2(CARD_W, 0)  # shrinks back to its content when a store has fewer lines
	var crew: Array = st.crew.map(func(m): return "%s %s" % [ROLE_ICON[m.role], m.name])
	staff_btn.tooltip_text = "Hire and fire at this store  [S]\nCrew: " + (", ".join(crew) if not crew.is_empty() else "just you")
	var exp_ok := not sim.eligible("expansion", st).is_empty()
	grow_btn.tooltip_text = "Expand this store: %s  [G]" % yen(Sim.expansion_cost(st)) if exp_ok else "Every expansion is built here"
	grow_btn.disabled = not exp_ok or sim.phase != "playing"
	store_btn.disabled = sim.branches.size() >= Sim.MAX_STORES or sim.phase != "playing"
	store_btn.tooltip_text = "Open another branch: from %s  [N]" % yen(sim.store_cost())
	staff_btn.disabled = sim.phase != "playing"
	city_btn.text = "Shop" if view.mode == "city" else "City"


func card_stat(k: String, value: String, color: Color) -> void:
	var a: Label = card_stats[k].get_child(1)
	a.text = value
	a.add_theme_color_override("font_color", color)


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
			shelf_box.remove_child(c)
			c.queue_free()
		# one key per product: its icon, the restock price, and a stock bar along the bottom
		for pid in st.products:
			var k := key_button(do_act.bind({"type": "restock", "product": pid}), "", product_frame(pid), 50, 52, 14)
			k.add_theme_font_size_override("font_size", 10)
			k.add_theme_constant_override("icon_max_width", 24)
			var bar := progress(MINT, 4)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			bar.offset_left = 7
			bar.offset_right = -7
			bar.offset_top = -9
			bar.offset_bottom = -5
			k.add_child(bar)
			shelf_box.add_child(k)
	var i := 0
	for pid in st.products:
		var p: Dictionary = st.products[pid]
		var k: Button = shelf_box.get_child(i)
		var bar: ProgressBar = k.get_child(0)
		var frac: float = float(p.stock) / p.capacity
		bar.value = frac
		(bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = RED if frac < Sim.LOW_STOCK else MINT
		var missing: int = p.capacity - p.stock
		var cost := Sim.rnd(missing * Sim.PRODUCTS[pid].cost * sim.mods().restock)
		k.text = "+%s" % yen(cost) if missing > 0 else "Full"
		k.tooltip_text = "%s  %d/%d  ·  %s" % [Sim.PRODUCTS[pid].name, p.stock, p.capacity, "click to restock for %s" % yen(cost) if missing > 0 else "full"]
		k.disabled = missing == 0 or sim.phase != "playing"
		if not k.has_meta("full") or k.get_meta("full") != (missing == 0):
			k.set_meta("full", missing == 0)
			# a full shelf reads as stocked (pale mint tile, icon in color, green caption), not as a dead key
			var off: StyleBoxFlat = theme.get_stylebox("disabled", "Button").duplicate() if missing > 0 else box(MINT.lerp(PAPER, 0.8), 14, 4)
			off.set_content_margin_all(4)
			k.add_theme_stylebox_override("disabled", off)
			k.add_theme_color_override("font_disabled_color", GREEN if missing == 0 else Color("cdbd9a"))
			k.add_theme_color_override("icon_disabled_color", Color.WHITE if missing == 0 else Color(1, 1, 1, 0.35))
		i += 1


# ---------- modals ----------

func open_modal(title: String, body: Control, keys := {}, kind := "", color := MINT) -> void:
	close_modal()
	modal = Control.new()
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.32, 0.23, 0.1, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box(PAPER, 26, 20, 0, 10))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(tag(label(title, Color.WHITE, 22), color))
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
	var rv: Dictionary = Sim.RIVALS[b.rival.id]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var vs := HBoxContainer.new()
	vs.add_theme_constant_override("separation", 8)
	vs.add_child(chip([label(b.name, Color.WHITE, 15), label(Sim.DISTRICTS[b.district].name, Color(1, 1, 1, 0.85), 11)], DISTRICT_COLOR[b.district]))
	vs.add_child(label("vs", MUTED, 15))
	vs.add_child(chip([label(rv.name, Color.WHITE, 15), label("next door", Color(1, 1, 1, 0.85), 11)], Color(rv.color).darkened(0.1)))
	v.add_child(vs)
	v.add_child(para("Your first konbini opens in %s, and %s wants your customers. Every sale you make hits its takings; drive it out of business and a bigger chain moves in." % [b.name, rv.name], INK, 560))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	for t in [
		[picture("perks", 10, 80, Vector2(40, 40)), "Ring up", "Click the till when someone waits. Fast ring-ups build a combo."],
		[picture("perks", 1, 80, Vector2(40, 40)), "Chase off", "Click the flyers, trash, mascots and thieves the rival sends."],
		[icon("onigiri", 40), "Restock", "Click a shelf before it runs dry."],
		[picture("perks", 0, 80, Vector2(40, 40)), "Grow", "Hire staff, buy expansions, pick a card at every level."],
		[intro_shop(), "Branch out", "Open more stores on lots across Tokyo."],
		[picture("perks", 11, 80, Vector2(40, 40)), "Pay the bills", "Rent and wages are due at midnight. Run dry and it's over."],
	]:
		g.add_child(intro_tile(t[0], t[1], t[2]))
	v.add_child(g)
	var keys := HFlowContainer.new()
	keys.custom_minimum_size.x = 560
	keys.add_theme_constant_override("h_separation", 12)
	keys.add_theme_constant_override("v_separation", 6)
	for k in [["Space", "pause"], ["F", "speed"], ["R", "ring up"], ["1-5", "abilities"], ["P", "pick"], ["S", "staff"], ["G", "expand"], ["N", "new store"], ["M", "map"], ["Tab", "next store"], ["V", "sound"]]:
		var cap := PanelContainer.new()
		var s := box(Color.WHITE, 7, 0, 2)
		s.border_color = LINE
		s.content_margin_left = 7
		s.content_margin_right = 7
		cap.add_theme_stylebox_override("panel", s)
		var kl := label(k[0], INK, 11)
		kl.add_theme_font_override("font", bold)
		cap.add_child(kl)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		h.add_child(cap)
		h.add_child(label(k[1], MUTED, 12))
		keys.add_child(h)
	v.add_child(keys)
	var go := func():
		close_modal()
		sim.act({"type": "start"})
	v.add_child(button("Open the shop!  [Space]", go))
	open_modal("Konbini Empire", v, {KEY_SPACE: go, KEY_ENTER: go}, "intro")


func intro_shop() -> TextureRect:
	var r := picture("storefronts", 0, 256, Vector2(40, 40))
	r.texture.region = Rect2(58, 66, 132, 124)  # your konbini in the first storefront frame
	return r


## One way to play on a sunken tile: its picture on a mint plate, a name and a line.
func intro_tile(pic: Control, what: String, line: String) -> PanelContainer:
	var plate := PanelContainer.new()
	var ps := box(MINT.lerp(PAPER, 0.75), 12, 4)
	ps.border_width_bottom = 2
	ps.border_color = MINT.lerp(PAPER, 0.5)
	plate.add_theme_stylebox_override("panel", ps)
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	plate.add_child(pic)
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 0)
	c.add_child(label(what, INK, 15))
	var l := para(line, MUTED, 124)
	l.add_theme_font_size_override("font_size", 11)
	c.add_child(l)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(plate)
	h.add_child(c)
	var p := sunken(h)
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_left = 8
	st.content_margin_right = 10
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	return p


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
		var rarity: String = "" if c.source == "listing" else Sim.UPGRADES[c.options[i]].rarity
		card.add_theme_stylebox_override("panel", card_frame(DISTRICT_COLOR[c.options[i].district] if rarity == "" else RARITY_COLOR[rarity], rarity != "" and rarity != "common"))
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(250 if c.source == "listing" else 190, 0)  # room for the longest pair of listing tags
		col.add_theme_constant_override("separation", 6)
		card.add_child(col)
		if c.source == "listing":
			listing_card(col, c.options[i])
		else:
			var u: Dictionary = Sim.UPGRADES[c.options[i]]
			var pips := label("★".repeat(RARITY_COLOR.keys().find(u.rarity) + 1), Color(1, 1, 1, 0.9), 11)
			var r := chip([label(u.rarity.capitalize(), Color.WHITE, 11), pips], RARITY_COLOR[u.rarity])
			(r.get_child(0) as HBoxContainer).add_theme_constant_override("separation", 4)
			r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			col.add_child(r)
			col.add_child(card_picture(c.options[i], u))
			col.add_child(label(u.name, INK, 16))
			var n: int = (sim.branches[sim.active].store.taken if c.source == "expansion" else sim.player.taken).get(c.options[i], 0)
			col.add_child(para(u.desc + ("" if n == 0 else "  (have %d)" % n), MUTED, 190))
		var take := func(): pick(c.options[i] if c.source != "listing" else i)
		var b := button("Take  [%d]" % (i + 1), take)
		if c.source == "listing":
			b.text = "Open for %s  [%d]" % [yen(c.options[i].cost), i + 1]
			b.disabled = sim.player.cash < c.options[i].cost
		elif c.source == "expansion":
			b.disabled = sim.player.cash < c.cost
		b.add_theme_color_override("font_disabled_color", MUTED)  # the price you can't meet yet stays readable
		var gap := Control.new()  # keeps every card's button on one line
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(gap)
		col.add_child(b)
		h.add_child(card)
		keys[KEY_1 + i] = take
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var title := "Pick a skill"
	match c.source:
		"reward":
			title = "Reward!"
			v.add_child(label(c.reason, GREEN))
		"expansion":
			title = "Expand %s" % sim.branches[sim.active].name
			v.add_child(label("Costs %s. Cash %s." % [yen(c.cost), yen(sim.player.cash)], MUTED))
		"listing":
			title = "New store"
			v.add_child(label("Three lots on offer. Cash %s; bills tonight %s." % [yen(sim.player.cash), yen(sim.bills_due())], MUTED))
	v.add_child(h)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var rc := sim.reroll_cost()
	var spare: int = sim.player.cash - (c.cost if c.source == "expansion" else 0)
	var rr := button("Reroll %s  [R]" % yen(rc), reroll)
	rr.disabled = spare < rc
	row.add_child(rr)
	if c.source == "listing":
		row.add_child(button("See on map", see_listings))
	row.add_child(button("Later  [Esc]", later))
	v.add_child(row)
	keys[KEY_R] = reroll
	keys[KEY_ESCAPE] = later
	open_modal(title, v, keys, "choice", {"reward": RARITY_COLOR.legendary, "expansion": Color("5aae55"), "listing": Color("4a9fdc")}.get(c.source, MINT))


func listing_card(v: VBoxContainer, L: Dictionary) -> void:
	var tokyo: String = sim.districts[sim.lots[L.lot].block].name
	var d: Dictionary = Sim.DISTRICTS[L.district]
	var q: Dictionary = Sim.QUIRKS[L.quirk]
	var rv: Dictionary = Sim.RIVALS[L.rival]
	v.add_child(lot_picture(L))
	v.add_child(label(tokyo, INK, 16))
	var kinds := HBoxContainer.new()
	kinds.add_theme_constant_override("separation", 6)
	kinds.add_child(chip([label(d.name, Color.WHITE, 11)], DISTRICT_COLOR[L.district]))
	kinds.add_child(chip([label(q.name, INK, 11)], GROUND))
	v.add_child(kinds)
	var traffic: float = d.traffic * q.get("traffic", 1.0)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 0)
	stats.add_child(roll_line("Foot traffic", "x%.2f" % traffic, GREEN if traffic > 1.0 else INK))
	stats.add_child(roll_line("Rent a night", "about " + yen(Sim.rnd(d.rent * q.get("rent", 1.0))), INK))
	v.add_child(sunken(stats))
	var buys := HBoxContainer.new()  # always a row of the icons' height, so every card's rival sits on one line
	buys.add_theme_constant_override("separation", 2)
	buys.custom_minimum_size.y = 30
	buys.add_child(label("Locals buy", MUTED))
	for k in d.demand:
		var ic := icon(k, 30)
		ic.tooltip_text = Sim.PRODUCTS[k].name
		buys.add_child(ic)
	if d.demand.is_empty():
		buys.add_theme_constant_override("separation", 6)
		buys.add_child(label("a bit of everything", INK))
	for c in buys.get_children():
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(buys)
	var rival := chip([label(rv.name, Color.WHITE, 12), label("Tier %d" % L.tier, Color(1, 1, 1, 0.8), 11)], Color(rv.color).darkened(0.1))
	rival.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var next := HBoxContainer.new()
	next.add_theme_constant_override("separation", 8)
	next.add_child(label("Next door", MUTED))
	next.add_child(rival)
	v.add_child(next)


## The lot's picture on a plate in its district's colour: your konbini beside the rival chain's shopfront.
func lot_picture(L: Dictionary) -> PanelContainer:
	var tint: Color = DISTRICT_COLOR[L.district]
	var front: int = Sim.RIVALS[L.rival].front
	var theirs := picture("storefronts", front, 256, Vector2(96, 56))
	theirs.texture.region = Rect2(front * 256 + 16, 42, 226, 144) if front % 2 == 1 else Rect2(front * 256 + 58, 66, 132, 124)  # odd frames are the big shops
	var ours := intro_shop()
	ours.custom_minimum_size = Vector2(60, 56)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	h.add_child(ours)
	var vs := label("vs", tint.darkened(0.25), 13)
	vs.add_theme_font_override("font", bold)
	h.add_child(vs)
	h.add_child(theirs)
	var plate := PanelContainer.new()
	var s := box(tint.lerp(PAPER, 0.8), 14, 8)
	s.border_width_bottom = 2
	s.border_color = tint.lerp(PAPER, 0.55)
	plate.add_theme_stylebox_override("panel", s)
	plate.add_child(h)
	return plate


## A pick card's face, edged all round in its rarity's colour (a listing's in its district's) over a deeper lip,
## the rarer cards lifted off the page on a glow of that colour.
func card_frame(tint: Color, glow: bool) -> StyleBoxFlat:
	var s := box(Color("fffdf5"), 18, 12, 0, 2)
	s.set_border_width_all(2)
	s.border_width_bottom = 5
	s.border_color = tint.lerp(PAPER, 0.35)
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	if glow:
		s.shadow_color = Color(tint, 0.4)
		s.shadow_size = 9
		s.shadow_offset = Vector2(0, 2)
	return s


## The card's picture on a plate tinted by its rarity, lit from behind by a soft spot of light (rays fanning out from it
## on the rarer cards), the art standing over its own shadow.
func card_picture(id: String, u: Dictionary) -> PanelContainer:
	var pic: TextureRect
	if u.has("product"):
		pic = icon(u.product, 60)
	elif u.has("ability"):
		pic = picture("perks", ABILITY_ICON[u.ability], 80, Vector2(60, 60))
	else:
		var ic: Array = CARD_ICON.get(id, ["perks", 11])
		pic = picture(ic[0], ic[1], {"perks": 80, "decor": 96}[ic[0]], Vector2(60, 60))
	var stage := TextureRect.new()
	stage.texture = card_stage(u.rarity)
	stage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stage.stretch_mode = TextureRect.STRETCH_SCALE
	stage.custom_minimum_size = Vector2(0, 76)
	if not tex.has("card_shade"):
		tex.card_shade = soft_oval(Color(INK.darkened(0.3), 0.3))
	var shade := TextureRect.new()
	shade.texture = tex.card_shade
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	shade.offset_left = -27
	shade.offset_right = 27
	shade.offset_top = -13
	shade.offset_bottom = -3
	stage.add_child(shade)
	pic.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	pic.offset_left = -31
	pic.offset_right = 31
	pic.offset_top = -35
	pic.offset_bottom = 27
	stage.add_child(pic)
	var plate := PanelContainer.new()
	var s := box(Color(RARITY_COLOR[u.rarity]).lerp(PAPER, 0.8), 14, 4)
	s.border_width_bottom = 2
	s.border_color = Color(RARITY_COLOR[u.rarity]).lerp(PAPER, 0.55)
	plate.add_theme_stylebox_override("panel", s)
	plate.add_child(stage)
	return plate


## The light behind a card's art, clear at its rim so it melts into the plate: a pale spot, and for rare cards and up
## rays in the rarity's colour, more of them the rarer the card.
func card_stage(rarity: String) -> Texture2D:
	var k := "stage_" + rarity
	if tex.has(k):
		return tex[k]
	var w := 256
	var h := 72
	var tint: Color = RARITY_COLOR[rarity]
	var rays: int = [0, 8, 12, 16][RARITY_COLOR.keys().find(rarity)]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var q := Vector2((x + 0.5 - w * 0.5) / (w * 0.5), (y + 0.5 - h * 0.45) / (h * 0.55))
			var d := q.length()
			var c := Color(1, 1, 1, 0)
			var spot := pow(clampf(1.0 - d / 0.75, 0.0, 1.0), 1.6)
			c = c.blend(Color(Color("fffdf5"), 0.95 * spot))
			if rays > 0:
				var a := atan2(q.y, q.x * 2.6)  # the fan reads round although the plate is wide
				var beam := smoothstep(0.35, 0.9, cos(a * rays))
				var fade := smoothstep(0.0, 0.3, d) * (1.0 - smoothstep(0.55, 0.98, d))
				c = c.blend(Color(tint.lerp(Color.WHITE, 0.35), 0.3 * beam * fade))
			img.set_pixel(x, y, c)
	tex[k] = ImageTexture.create_from_image(img)
	return tex[k]


## A soft oval of `c`, densest at its centre: a shadow to stand art on.
func soft_oval(c: Color) -> ImageTexture:
	var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 64:
			var d := Vector2((x + 0.5 - 32) / 32.0, (y + 0.5 - 8) / 8.0).length()
			img.set_pixel(x, y, Color(c, c.a * pow(clampf(1.0 - d, 0.0, 1.0), 1.4)))
	return ImageTexture.create_from_image(img)


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
	cols.add_theme_constant_override("separation", 22)
	v.add_child(cols)
	var crew := VBoxContainer.new()
	crew.custom_minimum_size.x = 250
	crew.add_theme_constant_override("separation", 4)
	crew.add_child(label("Crew", INK, 15))
	var rows := staff_grid()
	for m in st.crew:
		rows.add_child(role_tag(m.role))
		member_cells(rows, m, 100)
		rows.add_child(small_button("Fire", staff_act.bind("fire", m.id)))
	crew.add_child(staff_well(rows if st.crew.size() > 0 else label("No crew yet: you ring up alone.", MUTED, 12)))
	var key := VBoxContainer.new()
	key.add_theme_constant_override("separation", 4)
	key.add_child(label("Who does what", INK, 15))
	var roles := GridContainer.new()
	roles.columns = 3
	roles.add_theme_constant_override("h_separation", 10)
	roles.add_theme_constant_override("v_separation", 4)
	for r in [["cashier", "Runs a till of their own."], ["stocker", "Refills low shelves, but keeps tonight's bills in the till."],
			["cleaner", "Mops spills and bags trash."], ["guard", "Sees off flyers, mascots, thieves, suits and blackouts."], ["promoter", "Pulls walkers in off the street."]]:
		roles.add_child(role_plate(r[0]))
		roles.add_child(role_tag(r[0]))
		var l := para(r[1], MUTED, 196)
		l.add_theme_font_size_override("font_size", 11)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		roles.add_child(l)
	key.add_child(staff_well(roles))
	cols.add_child(crew)
	var apps := staff_grid()
	for role in Sim.ROLES:
		var have: int = st.crew.filter(func(m): return m.role == role).size()
		var cap := sim.role_cap(st, role)
		var first := true
		for a in st.applicants.filter(func(x): return x.role == role):
			var lead := HBoxContainer.new()
			lead.add_theme_constant_override("separation", 6)
			if first:
				lead.add_child(role_tag(role))
				lead.add_child(label("%d/%d" % [have, cap], GREEN if have < cap else MUTED, 11))
			first = false
			apps.add_child(lead)
			member_cells(apps, a, 200)
			var fee := Sim.rnd(a.wage * sim.mods().wage)
			if have >= cap:
				for c in apps.get_children().slice(-2):
					c.modulate.a = 0.5
				var full := small_button("Full", func(): pass)
				full.disabled = true
				apps.add_child(full)
				continue
			var hb := small_button("Hire %s" % yen(fee), staff_act.bind("hire", a.id))
			hb.disabled = sim.player.cash < fee
			apps.add_child(hb)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.add_child(label("Applicants today", INK, 15))
	right.add_child(staff_well(apps))
	cols.add_child(right)
	(crew if st.crew.size() <= st.applicants.size() else right).add_child(key)  # under the shorter list
	v.add_child(button("Close  [Esc]", close_staff))
	open_modal("Staff  ·  %s" % b.name, v, {KEY_ESCAPE: close_staff, KEY_S: close_staff}, "staff")


func staff_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 3)
	return g


## A sunken well for one of the staff panel's lists.
func staff_well(c: Control) -> PanelContainer:
	var p := sunken(c)
	var s: StyleBoxFlat = p.get_theme_stylebox("panel")
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return p


## A role's short name on a pill in its color.
func role_tag(role: String) -> PanelContainer:
	var l := label(ROLE_ICON[role], Color.WHITE, 10)
	l.add_theme_font_override("font", bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 38
	var p := chip([l], ROLE_COLOR[role])
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## The staffer as they walk the street, standing on a plate tinted their role's color.
func role_plate(role: String) -> PanelContainer:
	var r := picture("walk", 0, 72, Vector2(18, 24))
	r.texture.region = Rect2(0, StoreView.WALK_ROW[role] * StoreView.PERSON.y, StoreView.PERSON.x, StoreView.PERSON.y)
	var plate := PanelContainer.new()
	var ps := box(ROLE_COLOR[role].lerp(PAPER, 0.82), 8, 2)
	ps.border_width_bottom = 2
	ps.border_color = ROLE_COLOR[role].lerp(PAPER, 0.6)
	plate.add_theme_stylebox_override("panel", ps)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(r)
	return plate


func small_button(text: String, cb: Callable) -> Button:
	var b := button(text, cb)
	b.add_theme_font_size_override("font_size", 11)
	b.custom_minimum_size = Vector2(76, 24)
	for k in ["normal", "hover", "pressed", "disabled"]:
		var s: StyleBoxFlat = theme.get_stylebox(k, "Button").duplicate()
		s.content_margin_top = 2
		s.content_margin_bottom = 2
		if k == "disabled":  # the theme's off pill vanishes on a staff well
			s.bg_color = LINE.lerp(GROUND, 0.3)
		b.add_theme_stylebox_override(k, s)
	b.add_theme_color_override("font_disabled_color", MUTED)
	return b


## A staffer's name and trait (teal for a special, else green if quicker than steady, red if slower), then the wage.
func member_cells(g: GridContainer, m: Dictionary, w: int) -> void:
	var t: Dictionary = Sim.TRAITS[m.trait_id]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.custom_minimum_size.x = w
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var n := label(m.name, INK, 12)
	n.add_theme_font_override("font", bold)
	h.add_child(n)
	var tl := label(t.name + ((" · " + t.desc) if t.has("desc") else ""), BLUE if t.has("desc") else (GREEN if t.speed > 1.0 else (RED if t.speed < 1.0 else MUTED)), 11)
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.tooltip_text = tl.text
	tl.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(tl)
	g.add_child(h)
	var wl := label("%s/day" % yen(Sim.rnd(m.wage * sim.mods().wage)), MUTED, 11)
	wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.add_child(wl)


func staff_act(type: String, id: int) -> void:
	sim.act({"type": type, "id": id})
	drain()
	show_staff()


func close_staff() -> void:
	close_modal()
	ui_t = 0.0


## The day's receipt: a table per store on a sunken card, then the till roll from midnight cash to what's left.
func show_report(r: Dictionary) -> void:
	audio.play("closing")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var g := GridContainer.new()
	g.columns = 8
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 6)
	for k in 8:
		var hl := report_cell(["Store", "Sales", "Served", "Lost", "Stock", "Rent+wages", "Net", "Rival"][k].to_upper(), MUTED, 10, k in [0, 7])
		hl.add_theme_font_override("font", bold)
		g.add_child(hl)
	for i in r.rows.size():
		var row: Dictionary = r.rows[i]
		var s: Dictionary = row.stats
		var stock: int = s.restock + s.fines
		g.add_child(store_cell(i, row))
		g.add_child(report_cell(yen(s.revenue), INK if s.revenue > 0 else MUTED))
		g.add_child(report_cell(str(s.customers), INK if s.customers > 0 else MUTED))
		g.add_child(report_cell(str(s.lost), RED if s.lost > 0 else MUTED))
		g.add_child(report_cell(yen(-stock) if stock > 0 else "–", INK if stock > 0 else MUTED))
		g.add_child(report_cell(yen(-row.rent - row.wages) if row.rent + row.wages > 0 else "–", INK if row.rent + row.wages > 0 else MUTED))
		var net := report_cell(("+" if row.net > 0 else "") + yen(row.net), GREEN if row.net > 0 else (RED if row.net < 0 else MUTED))
		net.add_theme_font_override("font", bold)
		g.add_child(net)
		g.add_child(rival_cell(row))
	v.add_child(sunken(g))
	var roll := VBoxContainer.new()
	roll.add_theme_constant_override("separation", 3)
	roll.add_child(roll_line("Cash at midnight", yen(r.cash_before), INK))
	if r.interest > 0:
		roll.add_child(roll_line("Interest", "+" + yen(r.interest), GREEN))
	roll.add_child(roll_line("Rent and wages paid", yen(-r.bills), RED))
	if r.foreclosed != null:
		roll.add_child(roll_line("Bank paid for %s" % r.foreclosed.name, "+" + yen(r.foreclosed.value), GREEN))
	var rule := ColorRect.new()
	rule.color = LINE.darkened(0.08)
	rule.custom_minimum_size.y = 2
	roll.add_child(rule)
	var left := roll_line("Cash now", yen(r.cash_after), INK if r.cash_after >= 0 else RED, 22)
	var delta: int = r.cash_after - r.cash_before
	var dl := label(("+" if delta > 0 else "") + yen(delta), Color.WHITE, 12)
	dl.add_theme_font_override("font", bold)
	var dc := chip([dl], GREEN if delta >= 0 else RED)
	dc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_child(dc)
	left.move_child(dc, 1)
	roll.add_child(left)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	var till := sunken(roll)
	till.custom_minimum_size.x = 340
	foot.add_child(till)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if r.foreclosed != null:
		side.add_child(para("You ran short: the bank took %s." % r.foreclosed.name, RED, 200))
	var due := sim.bills_due()
	var ok: bool = due <= sim.player.cash
	var bt := stat_tile(picture("perks", 11, 80, Vector2(40, 40)), "Tomorrow's bills", "about %s" % yen(due), "You can pay them." if ok else "Earn %s more by midnight." % yen(due - sim.player.cash), GREEN if ok else RED, GREEN if ok else RED)
	bt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(bt)
	foot.add_child(side)
	v.add_child(foot)
	var go := func():
		close_modal()
		view.show_branch(sim.active)
		ui_t = 0.0
	v.add_child(button("Next day  [Space]", go))
	open_modal("Day %d closed" % r.day, v, {KEY_SPACE: go, KEY_ENTER: go}, "report", ORANGE)


func report_cell(text: String, color: Color, px := 12, left := false) -> Label:
	var l := label(text, color, px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left else HORIZONTAL_ALIGNMENT_RIGHT
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## The store as its tab reads in the dock, its number and name on a pill in its district's colour.
func store_cell(i: int, row: Dictionary) -> Control:
	var num := label(str(i + 1), Color(1, 1, 1, 0.8), 11)
	num.add_theme_font_override("font", bold)
	var n := label(row.name, Color.WHITE, 13)
	n.add_theme_font_override("font", bold)
	var b = sim.branches.filter(func(o): return o.id == row.branch)
	var p := chip([num, n], DISTRICT_COLOR[b[0].district] if not b.is_empty() else MUTED)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## How much of its takings the rival kept: its mascot's roundel by a short bar in its color, or a green tag once it has closed.
func rival_cell(row: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var face := TextureRect.new()
	face.texture = view.rival_face(row.rival)
	face.custom_minimum_size = Vector2(28, 28)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(face)
	if row.defeated:
		face.modulate = Color(1, 1, 1, 0.55)
		var c := label("CLOSED", Color.WHITE, 10)
		c.add_theme_font_override("font", bold)
		var p := chip([c], GREEN)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(p)
		return h
	var b := progress(Color(Sim.RIVALS[row.rival].color), 8)
	b.custom_minimum_size.x = 56
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.value = row.rival_hp / row.rival_max
	h.add_child(b)
	h.add_child(report_cell("%d%%" % roundi(100.0 * row.rival_hp / row.rival_max), MUTED, 11))
	return h


## A line of the till roll: what on the left, the amount on the right.
func roll_line(what: String, amount: String, color: Color, px := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var w := label(what, INK if px > 12 else MUTED, px)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(w)
	var a := label(amount, color, px)
	a.add_theme_font_override("font", bold)
	h.add_child(a)
	return h


## A panel set into the card, a shade darker, for tables and totals.
func sunken(c: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var s := box(GROUND, 16, 12)
	s.content_margin_left = 16
	s.content_margin_right = 16
	p.add_theme_stylebox_override("panel", s)
	p.add_child(c)
	return p


func show_over() -> void:
	audio.stop_music()
	audio.play("bankrupt")
	var rs: Dictionary = sim.run_stats
	var score: int = rs.days * 5000 + rs.revenue
	var prev: int = best.get_value("best", "score", 0)
	if score > prev:
		best.set_value("best", "score", score)
		best.save("user://best.cfg")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(para("Midnight bills of %s bounced. The landlord changed the locks." % yen(sim.summary.bills), RED, 470))
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	for t in [
		[picture("decor", 9, 96, Vector2(40, 40)), "Days survived", str(rs.days), ""],
		[picture("perks", 11, 80, Vector2(40, 40)), "Revenue", yen(rs.revenue), ""],
		[picture("perks", 10, 80, Vector2(40, 40)), "Customers", Sim.money(rs.customers), ""],
		[rival_shop(), "Rivals closed", str(rs.rivals_defeated), ""],
		[picture("perks", 1, 80, Vector2(40, 40)), "Threats repelled", str(rs.threats_repelled), ""],
		[intro_shop(), "Stores opened", str(rs.stores_opened), "peak %d at once%s" % [rs.peak_stores, "" if rs.foreclosed == 0 else ", %d foreclosed" % rs.foreclosed]],
	]:
		g.add_child(stat_tile(t[0], t[1], t[2], t[3]))
	v.add_child(g)
	var total := roll_line("Score", Sim.money(score), INK, 22)
	var bl := label("New best!" if score > prev else "best %s" % Sim.money(prev), Color.WHITE if score > prev else MUTED, 12)
	bl.add_theme_font_override("font", bold)
	var bc: Control = chip([bl], GREEN) if score > prev else bl
	bc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	total.add_child(bc)
	total.move_child(bc, 1)
	v.add_child(sunken(total))
	v.add_child(label("Level %d  ·  Seed %s" % [sim.player.level, sim.seed_text], MUTED, 11))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var again := func(): new_run(sim.seed_text)
	var fresh := func(): new_run("")
	h.add_child(button("Retry seed", again))
	h.add_child(button("New run  [Space]", fresh))
	v.add_child(h)
	open_modal("Bankrupt", v, {KEY_SPACE: fresh, KEY_ENTER: fresh}, "over", RED)


func rival_shop() -> TextureRect:
	var r := picture("storefronts", 4, 256, Vector2(40, 40))
	r.texture.region = Rect2(4 * 256 + 58, 66, 132, 124)  # a rival chain's konbini in the fifth storefront frame
	return r


## One number on its own sunken tile: its picture on a plate tinted like the card, its caption above it.
func stat_tile(pic: Control, what: String, value: String, note: String, tint := RED, note_color := MUTED) -> PanelContainer:
	var plate := PanelContainer.new()
	var ps := box(tint.lerp(PAPER, 0.86), 12, 4)
	ps.border_width_bottom = 2
	ps.border_color = tint.lerp(PAPER, 0.7)
	plate.add_theme_stylebox_override("panel", ps)
	plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plate.add_child(pic)
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 0)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var w := label(what.to_upper(), MUTED, 10)
	w.add_theme_font_override("font", bold)
	c.add_child(w)
	c.add_child(label(value, INK, 22))
	if note != "":
		c.add_child(label(note, note_color, 11))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.custom_minimum_size.x = 176
	h.add_child(plate)
	h.add_child(c)
	var p := sunken(h)
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_left = 8
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	return p


func show_new_run() -> void:
	if modal_kind in ["report", "over"]:
		return
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.add_child(para("Same seed, same street, same rivals and cards. Leave it blank for a random run.", INK, 440))
	var edit := LineEdit.new()
	edit.placeholder_text = "random"
	edit.max_length = 24
	edit.add_theme_font_override("font", bold)
	edit.add_theme_font_size_override("font_size", 18)
	edit.add_theme_color_override("font_placeholder_color", LINE.darkened(0.12))
	var start := func(): new_run(edit.text)
	edit.text_submitted.connect(func(_t): start.call())
	var go := button("Start  [Enter]", start)
	for k in ["normal", "hover", "pressed"]:
		go.add_theme_stylebox_override(k, pill_box(MINT.lightened(0.12) if k == "hover" else MINT, 1 if k == "pressed" else 3, 1 if k == "pressed" else 2))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		go.add_theme_color_override(k, Color.WHITE)
	var seed_now := label(sim.seed_text, INK, 22)
	seed_now.custom_minimum_size.y = edit.get_minimum_size().y
	seed_now.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	tiles.add_child(seed_tile(intro_shop(), "This run", seed_now, "Day %d  ·  Level %d" % [sim.day, sim.player.level], button("Replay", func(): new_run(sim.seed_text))))
	tiles.add_child(seed_tile(picture("decor", 3, 96, Vector2(40, 40)), "New run", edit, "Type a seed to share a street", go))
	v.add_child(tiles)
	var prev := modal_kind
	var cancel := func():
		close_modal()
		if prev == "intro":
			show_intro()
		elif sim.phase == "choice":
			show_choice()
	v.add_child(button("Cancel  [Esc]", cancel))
	edit.gui_input.connect(func(e):  # the field would only drop focus on the first Esc
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			edit.accept_event()
			cancel.call())
	open_modal("New run", v, {KEY_ESCAPE: cancel}, "seed")
	edit.grab_focus.call_deferred()


## A seed on its own sunken tile: its picture on a mint plate, caption, the seed (or a field for one), a note and the
## button that starts it.
func seed_tile(pic: Control, what: String, value: Control, note: String, b: Button) -> PanelContainer:
	var plate := PanelContainer.new()
	var ps := box(MINT.lerp(PAPER, 0.75), 12, 4)
	ps.border_width_bottom = 2
	ps.border_color = MINT.lerp(PAPER, 0.5)
	plate.add_theme_stylebox_override("panel", ps)
	plate.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	plate.add_child(pic)
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 4)
	c.custom_minimum_size.x = 208
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var w := label(what.to_upper(), MUTED, 10)
	w.add_theme_font_override("font", bold)
	c.add_child(w)
	c.add_child(value)
	c.add_child(label(note, MUTED, 11))
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	c.add_child(b)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.add_child(plate)
	h.add_child(c)
	var p := sunken(h)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_top = 10
	st.content_margin_bottom = 12
	return p


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
		KEY_V:
			cycle_sound()
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
