extends RefCounted
## Konbini Empire rules and state. No nodes, no rendering, so tests/balance.gd can run it headless.

const P := [
	{"id": "onigiri", "name": "Onigiri", "cost": 60, "price": 130, "perish": true, "tier": 0, "cat": "food"},
	{"id": "bento", "name": "Bento", "cost": 260, "price": 520, "perish": true, "tier": 0, "cat": "food"},
	{"id": "sando", "name": "Egg Sando", "cost": 120, "price": 260, "perish": true, "tier": 0, "cat": "food"},
	{"id": "coffee", "name": "Can Coffee", "cost": 55, "price": 130, "perish": false, "tier": 0, "cat": "drink"},
	{"id": "tea", "name": "Green Tea", "cost": 60, "price": 150, "perish": false, "tier": 0, "cat": "drink"},
	{"id": "energy", "name": "Energy Drink", "cost": 110, "price": 240, "perish": false, "tier": 0, "cat": "drink"},
	{"id": "chips", "name": "Potato Chips", "cost": 70, "price": 160, "perish": false, "tier": 0, "cat": "snack"},
	{"id": "choco", "name": "Choco Bar", "cost": 55, "price": 130, "perish": false, "tier": 0, "cat": "snack"},
	{"id": "noodle", "name": "Cup Noodle", "cost": 90, "price": 210, "perish": false, "tier": 0, "cat": "food"},
	{"id": "icebar", "name": "Ice Bar", "cost": 60, "price": 150, "perish": false, "tier": 0, "cat": "snack"},
	{"id": "umbrella", "name": "Umbrella", "cost": 250, "price": 650, "perish": false, "tier": 0, "cat": "home"},
	{"id": "news", "name": "Newspaper", "cost": 80, "price": 160, "perish": true, "tier": 0, "cat": "home"},
	{"id": "fish", "name": "Mackerel", "cost": 220, "price": 480, "perish": true, "tier": 1, "cat": "fresh"},
	{"id": "steak", "name": "Wagyu Pack", "cost": 900, "price": 1800, "perish": true, "tier": 1, "cat": "fresh"},
	{"id": "cabbage", "name": "Cabbage", "cost": 90, "price": 200, "perish": false, "tier": 1, "cat": "fresh"},
	{"id": "apple", "name": "Apple", "cost": 70, "price": 160, "perish": false, "tier": 1, "cat": "fresh"},
	{"id": "eggs", "name": "Eggs", "cost": 140, "price": 260, "perish": false, "tier": 1, "cat": "fresh"},
	{"id": "milk", "name": "Milk", "cost": 120, "price": 230, "perish": true, "tier": 1, "cat": "drink"},
	{"id": "bread", "name": "Bread", "cost": 120, "price": 250, "perish": true, "tier": 1, "cat": "food"},
	{"id": "rice", "name": "Rice 5kg", "cost": 1400, "price": 2600, "perish": false, "tier": 1, "cat": "home"},
	{"id": "tissue", "name": "Toilet Roll", "cost": 280, "price": 520, "perish": false, "tier": 1, "cat": "home"},
	{"id": "soap", "name": "Detergent", "cost": 240, "price": 460, "perish": false, "tier": 1, "cat": "home"},
	{"id": "sake", "name": "Sake", "cost": 800, "price": 1600, "perish": false, "tier": 1, "cat": "drink"},
	{"id": "flowers", "name": "Bouquet", "cost": 450, "price": 1000, "perish": true, "tier": 1, "cat": "home"},
]

# Frame index in art/people.png. hours = weight per time block.
const A := [
	{"name": "Salaryman", "sens": 0.3, "hours": [4, 2, 1, 3, 3, 1], "wants": {"coffee": 5, "onigiri": 3, "bento": 3, "energy": 2, "news": 3, "noodle": 1, "sake": 1, "steak": 0.5, "umbrella": 0.3}},
	{"name": "Office worker", "sens": 0.45, "hours": [2, 4, 1, 3, 1, 0], "wants": {"sando": 4, "tea": 4, "choco": 2, "bento": 2, "icebar": 1, "bread": 2, "milk": 1, "eggs": 1, "apple": 1, "flowers": 1, "umbrella": 0.3}},
	{"name": "Student", "sens": 0.75, "hours": [2, 1, 4, 3, 1, 0], "wants": {"chips": 4, "energy": 2, "icebar": 3, "noodle": 3, "choco": 3, "onigiri": 2, "tea": 1, "umbrella": 0.3}},
	{"name": "Grandma", "sens": 0.85, "hours": [4, 2, 3, 1, 0, 0], "wants": {"cabbage": 4, "fish": 3, "eggs": 3, "apple": 3, "milk": 2, "bread": 2, "rice": 1, "tissue": 1, "soap": 1, "news": 2, "tea": 1, "umbrella": 0.3}},
	{"name": "Builder", "sens": 0.4, "hours": [4, 4, 1, 1, 0, 1], "wants": {"bento": 5, "onigiri": 4, "coffee": 3, "energy": 3, "noodle": 2, "tea": 2, "rice": 0.5, "umbrella": 0.3}},
	{"name": "Tourist", "sens": 0.15, "hours": [1, 2, 3, 2, 1, 0], "wants": {"onigiri": 3, "icebar": 3, "tea": 2, "sando": 2, "choco": 2, "sake": 2, "flowers": 0.5, "umbrella": 0.5}},
	{"name": "Kid", "sens": 0.95, "hours": [0, 0, 4, 2, 0, 0], "wants": {"icebar": 5, "choco": 4, "chips": 4, "milk": 1}},
]
const BLOCKS := ["Morning", "Lunch", "Afternoon", "Evening", "Night", "Late"]
const BLOCK_W := [3.0, 4.0, 2.0, 4.0, 2.0, 1.0]

# mix scales each archetype's chance to visit; frame = art/stores.png
const STORE := {
	"konbini": {"name": "Konbini", "frame": 0, "slots": 6, "rows": 2, "cap": 30, "traffic": 110, "checkout": 140, "upkeep": 4000, "rent": 20000, "tier": 0, "wants": [1, 2], "mix": [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]},
	"super": {"name": "Supermarket", "frame": 1, "slots": 12, "rows": 3, "cap": 60, "traffic": 220, "checkout": 300, "upkeep": 14000, "rent": 60000, "tier": 1, "wants": [2, 4], "mix": [1.0, 1.6, 0.6, 2.5, 0.8, 1.0, 1.0]},
}

const WEATHER := [
	{"id": "sunny", "name": "Sunny", "w": 40, "traffic": 1.0, "mult": {}},
	{"id": "hot", "name": "Heatwave", "w": 15, "traffic": 1.0, "mult": {"icebar": 3.0, "tea": 1.8, "energy": 1.4, "noodle": 0.5}},
	{"id": "rain", "name": "Rain", "w": 25, "traffic": 0.85, "mult": {"umbrella": 14.0, "noodle": 1.5}},
	{"id": "cold", "name": "Cold snap", "w": 15, "traffic": 0.95, "mult": {"noodle": 2.5, "coffee": 1.8, "icebar": 0.3}},
	{"id": "typhoon", "name": "Typhoon", "w": 5, "traffic": 0.5, "mult": {"umbrella": 10.0, "noodle": 2.5, "rice": 3.0, "tissue": 3.0, "bread": 2.0}},
]

const EVENTS := [
	{"id": "none", "name": "", "desc": "", "w": 45},
	{"id": "festival", "name": "Street festival", "desc": "+50% customers, food sells fast", "w": 8},
	{"id": "school", "name": "School trip in town", "desc": "Students and kids everywhere", "w": 8},
	{"id": "tv", "name": "Local TV feature", "desc": "+30% customers, +8 reputation", "w": 5},
	{"id": "payday", "name": "Payday", "desc": "Customers ignore prices", "w": 7},
	{"id": "viral", "name": "Viral product", "desc": "%s is trending (x4 demand)", "w": 7},
	{"id": "sale", "name": "Supplier sale", "desc": "%s 30%% off wholesale", "w": 8},
	{"id": "rival", "name": "Rival opened nearby", "desc": "-25% customers for 3 days", "w": 6, "bad": true},
	{"id": "thief", "name": "Shoplifter", "desc": "Snacks and drinks went missing", "w": 6, "bad": true},
	{"id": "outage", "name": "Power cut tonight", "desc": "Chilled stock spoils at close", "w": 5, "bad": true},
	{"id": "inspector", "name": "Health inspector", "desc": "Fines stores that binned food yesterday", "w": 6, "bad": true},
	{"id": "spike", "name": "Price spike", "desc": "%s +40%% wholesale", "w": 6, "bad": true},
]

# frame = art/perks.png
const PERKS := [
	{"id": "parttimer", "name": "Part-timer", "desc": "+50 checkout per store. Wage ¥2,500/day per store.", "frame": 0, "max": 3},
	{"id": "poster", "name": "Ad posters", "desc": "+12% customers.", "frame": 1, "max": 3},
	{"id": "fridge", "name": "Drinks fridge", "desc": "Drink demand x1.4.", "frame": 2, "max": 1},
	{"id": "coffee", "name": "Coffee machine", "desc": "Half of workers add a fresh coffee (+¥110 each).", "frame": 3, "max": 1},
	{"id": "loyalty", "name": "Point card", "desc": "Reputation losses halved. +6% customers.", "frame": 4, "max": 1},
	{"id": "fryer", "name": "Hot snack fryer", "desc": "1 in 4 customers adds karaage (+¥130 each).", "frame": 5, "max": 1},
	{"id": "camera", "name": "Security camera", "desc": "Stops shoplifters. +4 reputation.", "frame": 6, "max": 1},
	{"id": "truck", "name": "Own truck", "desc": "Wholesale prices -10%.", "frame": 7, "max": 1},
	{"id": "neon", "name": "Neon sign", "desc": "Konbini night and late customers x2.", "frame": 8, "max": 1},
	{"id": "cat", "name": "Lucky cat", "desc": "Bad events half as likely. 4 upgrade choices.", "frame": 9, "max": 1},
	{"id": "register", "name": "Self-checkout", "desc": "+80 checkout per store, no wage.", "frame": 10, "max": 3},
	{"id": "investor", "name": "Investor", "desc": "Take ¥%s cash now.", "frame": 11, "max": 99},
]

# Floor plan grid: x across, z from the back wall (0) forward. Row z = GRID.y is the front walkway: never built on.
const GRID := {"konbini": Vector2i(14, 7), "super": Vector2i(18, 8)}
const FOOT := {"gondola": Vector2i(2, 1), "counter": Vector2i(3, 1), "decor": Vector2i(1, 1)}
const NO_CELL := Vector2i(-1, -1)

# frame = index in art/decor.png. appeal: +2% customers each. arch: visit mix per archetype. prod: demand. income: yen a day.
const DECOR := [
	{"name": "Potted plant", "cost": 3000, "appeal": 1, "desc": "+2% customers."},
	{"name": "Bench", "cost": 6000, "appeal": 1, "arch": {3: 1.4}, "desc": "+2% customers. Grandmas stop by."},
	{"name": "Vending machine", "cost": 25000, "appeal": 0, "income": 1500, "desc": "Sells drinks all night: +¥1,500 a day."},
	{"name": "Gachapon", "cost": 15000, "appeal": 1, "arch": {2: 1.3, 6: 1.6}, "desc": "+2% customers. Kids and students drop in."},
	{"name": "Sakura tree", "cost": 20000, "appeal": 4, "desc": "+8% customers."},
	{"name": "Chalkboard sign", "cost": 8000, "appeal": 2, "desc": "+4% customers."},
	{"name": "ATM", "cost": 40000, "appeal": 3, "arch": {0: 1.25, 5: 1.25}, "desc": "+6% customers. Salarymen and tourists."},
	{"name": "Ice freezer", "cost": 18000, "appeal": 0, "prod": {"icebar": 1.6}, "desc": "Ice bar demand x1.6."},
	{"name": "Magazine rack", "cost": 10000, "appeal": 1, "arch": {0: 1.3}, "prod": {"news": 1.5}, "desc": "+2% customers. Papers sell better."},
	{"name": "Paper lantern", "cost": 5000, "appeal": 1, "desc": "+2% customers."},
	{"name": "Aquarium", "cost": 30000, "appeal": 6, "desc": "+12% customers."},
	{"name": "Claw machine", "cost": 35000, "appeal": 2, "arch": {2: 1.3, 5: 1.5}, "income": 1000, "desc": "+4% customers, +¥1,000 a day."},
]
const APPEAL_CAP := 25

const CHILLED := ["icebar", "milk", "fish", "steak"]
const CATS := ["food", "drink", "snack", "fresh", "home"]
const TIER_MULT := [0.85, 1.0, 1.25]
const TIER_NAME := ["LOW", "STD", "HIGH"]
const START_CASH := 50000
const FLAGSHIP_COST := 2000000

var rng := RandomNumberGenerator.new()
var idx := {}
var seed_text := ""
var day := 1
var cash := 0
var rep := 50.0
var stores: Array = []
var perks := {}
var weather: Dictionary
var event: Dictionary
var event_arg := ""
var wholesale: Array = []
var rent_mult := 1.0
var rival_days := 0
var last_waste := 0
var spent_today := 0
var morning_note := ""
var over := false
var won := false
var draft: Array = []
var misses := {}
var stats := {}


func _init() -> void:
	for i in P.size():
		idx[P[i].id] = i


static func money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if v < 0 else "") + s + out


func start(seed_str: String) -> void:
	seed_text = seed_str
	rng.seed = hash(seed_str)
	day = 1
	cash = START_CASH
	rep = 50.0
	perks = {}
	rent_mult = 1.0
	rival_days = 0
	last_waste = 0
	over = false
	won = false
	misses = {}
	draft = []
	stats = {"served": 0, "peak": START_CASH, "sales": 0}
	stores = [new_store("konbini")]
	begin_day()


func new_store(kind: String) -> Dictionary:
	var s := {"kind": kind, "slots": [], "objects": default_objects(kind)}
	for i in STORE[kind].slots:
		s.slots.append(empty_slot())
	return s


static func default_objects(kind: String) -> Array:
	var out := []
	for g in STORE[kind].slots / STORE[kind].rows:
		out.append({"type": "gondola", "cell": Vector2i(2 + g * 3, 3)})
	out.append({"type": "counter", "cell": Vector2i(GRID[kind].x - 4, 1)})
	return out


static func cells_of(o: Dictionary) -> Array:
	var out := []
	var f: Vector2i = FOOT[o.type]
	for x in f.x:
		for z in f.y:
			out.append(o.cell + Vector2i(x, z))
	return out


static func entry_cell(kind: String) -> Vector2i:
	return Vector2i(1, GRID[kind].y)


static func exit_cell(kind: String) -> Vector2i:
	return Vector2i(GRID[kind].x - 2, GRID[kind].y)


static func nav(store: Dictionary) -> AStarGrid2D:
	var g: Vector2i = GRID[store.kind]
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, g.x, g.y + 1)
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.update()
	for o in store.objects:
		for c in cells_of(o):
			if a.is_in_boundsv(c):
				a.set_point_solid(c)
	return a


## A free cell in front of (else behind) the object that customers can reach, or NO_CELL.
static func access(store: Dictionary, a: AStarGrid2D, o: Dictionary) -> Vector2i:
	var from := entry_cell(store.kind)
	for dz in ([1] if o.type == "counter" else [1, -1]):
		for c in cells_of(o):
			var n: Vector2i = c + Vector2i(0, dz)
			if a.is_in_boundsv(n) and not a.is_point_solid(n) and a.get_id_path(from, n).size() > 0:
				return n
	return NO_CELL


## Would the store still work with object idx moved to cell (or obj added there when idx < 0)?
static func placement_ok(store: Dictionary, oi: int, cell: Vector2i, obj := {}) -> bool:
	var objs: Array = store.objects.duplicate(true)
	if oi >= 0:
		objs[oi].cell = cell
	else:
		obj = obj.duplicate()
		obj.cell = cell
		objs.append(obj)
	var g: Vector2i = GRID[store.kind]
	var seen := {}
	for o in objs:
		for c in cells_of(o):
			if c.x < 0 or c.y < 0 or c.x >= g.x or c.y >= g.y or seen.has(c):
				return false
			seen[c] = true
	var test := {"kind": store.kind, "objects": objs}
	var a := nav(test)
	for o in objs:
		if o.type != "decor" and access(test, a, o) == NO_CELL:
			return false
	return true


static func object_at(store: Dictionary, cell: Vector2i) -> int:
	for i in store.objects.size():
		if cell in cells_of(store.objects[i]):
			return i
	return -1


static func appeal(store: Dictionary) -> int:
	var n := 0
	for o in store.objects:
		if o.type == "decor":
			n += DECOR[o.id].appeal
	return mini(n, APPEAL_CAP)


func move_object(si: int, oi: int, cell: Vector2i) -> bool:
	if not placement_ok(stores[si], oi, cell):
		return false
	stores[si].objects[oi].cell = cell
	return true


func buy_decor(si: int, id: int, cell: Vector2i) -> bool:
	var o := {"type": "decor", "id": id}
	if cash < DECOR[id].cost or not placement_ok(stores[si], -1, cell, o):
		return false
	cash -= DECOR[id].cost
	o.cell = cell
	stores[si].objects.append(o)
	return true


func sell_decor(si: int, oi: int) -> void:
	var o: Dictionary = stores[si].objects[oi]
	if o.type == "decor":
		cash += DECOR[o.id].cost / 2
		stores[si].objects.remove_at(oi)


func empty_slot() -> Dictionary:
	return {"pid": -1, "qty": 0, "tier": 1, "sold": 0}


func has(perk: String) -> int:
	return perks.get(perk, 0)


func max_tier() -> int:
	var t := 0
	for s in stores:
		t = maxi(t, STORE[s.kind].tier)
	return t


func products_for(tier: int) -> Array:
	return range(P.size()).filter(func(i): return P[i].tier <= tier)


func weekly_rent() -> int:
	var r := 0
	for s in stores:
		r += STORE[s.kind].rent
	return int(r * rent_mult)


func days_to_rent() -> int:
	return (7 - day % 7) % 7


func pick(table: Array, bad_scale := 1.0) -> Dictionary:
	var w := PackedFloat32Array()
	for e in table:
		w.append(e.w * (bad_scale if e.get("bad", false) else 1.0))
	return table[rng.rand_weighted(w)]


func shuffled(a: Array) -> Array:
	a = a.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
	return a


func begin_day() -> void:
	spent_today = 0
	weather = pick(WEATHER)
	event = pick(EVENTS, 0.5 if has("cat") else 1.0)
	event_arg = ""
	var notes := []
	match event.id:
		"viral":
			var pool := products_for(max_tier())
			event_arg = P[pool[rng.randi() % pool.size()]].id
		"sale", "spike":
			event_arg = CATS[rng.randi() % CATS.size()]
		"rival":
			rival_days = 3
		"tv":
			rep = minf(100.0, rep + 8.0)
		"inspector":
			if last_waste > 0:
				var fine := 5000 * stores.size()
				cash -= fine
				notes.append("Fined ¥%s for binned food." % money(fine))
			else:
				rep = minf(100.0, rep + 5.0)
				notes.append("Clean shelves: +5 reputation.")
		"thief":
			notes.append("Your camera scared the thief off." if has("camera") else steal())
	wholesale = []
	for p in P:
		var m := rng.randf_range(0.85, 1.15)
		if event.id == "sale" and p.cat == event_arg:
			m *= 0.7
		if event.id == "spike" and p.cat == event_arg:
			m *= 1.4
		if has("truck"):
			m *= 0.9
		wholesale.append(maxi(1, roundi(p.cost * m)))
	morning_note = " ".join(notes)


func steal() -> String:
	var lost := 0
	for st in stores:
		for s in st.slots:
			if s.pid >= 0 and P[s.pid].cat in ["snack", "drink"] and s.qty > 0:
				var n := ceili(s.qty * 0.3)
				s.qty -= n
				lost += n
	return "Lost %d snacks and drinks." % lost if lost else "Nothing worth stealing was on the shelves."


func event_text() -> String:
	if event.id == "none":
		return ""
	var arg := event_arg
	if event.id == "viral":
		arg = P[idx[event_arg]].name
	return "%s: %s" % [event.name, event.desc % arg if "%s" in event.desc else event.desc]


func price_of(pid: int, tier: int) -> int:
	return roundi(P[pid].price * TIER_MULT[tier] / 10.0) * 10


func cap_of(si: int) -> int:
	return STORE[stores[si].kind].cap


func can_stock(si: int, pid: int) -> bool:
	return P[pid].tier <= STORE[stores[si].kind].tier


func buy(si: int, slot: int, pid: int, qty: int) -> int:
	var s: Dictionary = stores[si].slots[slot]
	if (s.pid != -1 and s.pid != pid) or not can_stock(si, pid):
		return 0
	qty = mini(mini(qty, cap_of(si) - s.qty), cash / wholesale[pid])
	if qty <= 0:
		return 0
	s.pid = pid
	s.qty += qty
	cash -= qty * wholesale[pid]
	spent_today += qty * wholesale[pid]
	return qty


func clear_slot(si: int, slot: int) -> void:
	stores[si].slots[slot] = empty_slot()


func cycle_tier(si: int, slot: int) -> void:
	var s: Dictionary = stores[si].slots[slot]
	s.tier = (s.tier + 1) % 3


func buy_prob(sens: float, tier: int) -> float:
	match tier:
		0: return 0.98
		1: return 0.9 - 0.15 * sens
	return 0.85 - 0.6 * sens


func want_tables(tier: int, prod: Dictionary) -> Array:
	var out := []
	for a in A:
		var ids := []
		var w := PackedFloat32Array()
		for id in a.wants:
			var pid: int = idx[id]
			if P[pid].tier > tier:
				continue
			var x: float = a.wants[id] * weather.mult.get(id, 1.0) * prod.get(id, 1.0)
			if event.id == "viral" and id == event_arg:
				x *= 4.0
			if event.id == "festival" and P[pid].cat == "food":
				x *= 1.3
			if has("fridge") and P[pid].cat == "drink":
				x *= 1.4
			ids.append(pid)
			w.append(x)
		out.append([ids, w])
	return out


func find_slot(st: Dictionary, pid: int) -> int:
	for i in st.slots.size():
		if st.slots[i].pid == pid and st.slots[i].qty > 0:
			return i
	return -1


## Runs one trading day for every store and closes it. Returns the report the UI animates and shows.
func simulate_day() -> Dictionary:
	var rep_before := rep
	var r := {"day": day, "weather": weather.name, "stores": [], "sales": 0, "extras": 0, "waste": 0, "upkeep": 0, "rent": 0, "customers": 0, "walkouts": 0, "misses": {}, "spent": spent_today, "rep_delta": 0.0, "net": 0, "cash": 0}
	var wanted := 0.0
	var got := 0.0
	for st in stores:
		var def: Dictionary = STORE[st.kind]
		var arch := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
		var prod := {}
		for o in st.objects:
			if o.type != "decor":
				continue
			var d: Dictionary = DECOR[o.id]
			for ai in d.get("arch", {}):
				arch[ai] *= d.arch[ai]
			for id in d.get("prod", {}):
				prod[id] = prod.get(id, 1.0) * d.prod[id]
			r.extras += d.get("income", 0)
		var tables := want_tables(def.tier, prod)
		for s in st.slots:
			s.sold = 0
		var bw := PackedFloat32Array(BLOCK_W)
		if has("neon") and st.kind == "konbini":
			bw[4] *= 2.0
			bw[5] *= 2.0
		var bw_sum := 0.0
		for x in bw:
			bw_sum += x
		var traffic: float = def.traffic * (0.6 + rep / 125.0) * weather.traffic * bw_sum / 16.0
		traffic *= 1.0 + 0.12 * has("poster") + (0.06 if has("loyalty") else 0.0) + 0.02 * appeal(st)
		if event.id == "festival":
			traffic *= 1.5
		elif event.id == "tv":
			traffic *= 1.3
		if rival_days > 0:
			traffic *= 0.75
		var n := int(traffic * rng.randf_range(0.9, 1.1))
		var checkout: float = def.checkout + 50 * has("parttimer") + 80 * has("register")
		var block_cap := []
		for b in 6:
			block_cap.append(ceili(checkout * bw[b] / bw_sum * 1.3))
		var custs := []
		for c in n:
			var blk := rng.rand_weighted(bw)
			var aw := PackedFloat32Array()
			for ai in A.size():
				var w: float = A[ai].hours[blk] * def.mix[ai] * arch[ai]
				if event.id == "school" and (ai == 2 or ai == 6):
					w *= 3.0
				aw.append(w)
			custs.append({"t": (blk + rng.randf()) / 6.0, "blk": blk, "a": rng.rand_weighted(aw), "slot": -1, "buy": [], "miss": [], "spent": 0, "walkout": false})
		custs.sort_custom(func(x, y): return x.t < y.t)
		var sr := {"kind": st.kind, "customers": n, "walkouts": 0, "sales": 0, "events": custs}
		for cu in custs:
			if block_cap[cu.blk] <= 0:
				cu.walkout = true
				sr.walkouts += 1
				wanted += 1.0
				continue
			block_cap[cu.blk] -= 1
			var ai: int = cu.a
			var sens: float = A[ai].sens * (0.2 if event.id == "payday" else 1.0)
			for j in rng.randi_range(def.wants[0], def.wants[1]):
				var tb: Array = tables[ai]
				if tb[0].is_empty():
					break
				var pid: int = tb[0][rng.rand_weighted(tb[1])]
				wanted += 1.0
				var si := find_slot(st, pid)
				if si < 0:
					cu.miss.append(pid)
					r.misses[pid] = r.misses.get(pid, 0) + 1
					continue
				var s: Dictionary = st.slots[si]
				if cu.slot < 0:
					cu.slot = si
				if rng.randf() < buy_prob(sens, s.tier):
					s.qty -= 1
					s.sold += 1
					got += 1.0
					var pr := price_of(pid, s.tier)
					cu.buy.append(pid)
					cu.spent += pr
					sr.sales += pr
				else:
					got += 0.5
			if has("coffee") and ai in [0, 1, 4] and rng.randf() < 0.5:
				cu.spent += 150
				r.extras += 110
			if has("fryer") and rng.randf() < 0.25:
				cu.spent += 220
				r.extras += 130
		sr.left = st.slots.map(func(s): return s.qty)
		r.stores.append(sr)
		r.sales += sr.sales
		r.customers += n
		r.walkouts += sr.walkouts
		r.upkeep += def.upkeep + 2500 * has("parttimer")
	for st in stores:
		for s in st.slots:
			if s.pid >= 0 and (P[s.pid].perish or (event.id == "outage" and P[s.pid].id in CHILLED)):
				r.waste += s.qty * P[s.pid].cost
				s.qty = 0
	if day % 7 == 0:
		r.rent = weekly_rent()
		rent_mult *= 1.1
	cash += r.sales + r.extras - r.upkeep - r.rent
	last_waste = r.waste
	rival_days = maxi(0, rival_days - 1)
	var delta := (got / maxf(1.0, wanted) - 0.6) * 15.0
	if delta < 0 and has("loyalty"):
		delta *= 0.5
	rep = clampf(rep + delta, 0.0, 100.0)
	r.rep_delta = rep - rep_before
	r.net = r.sales + r.extras - r.upkeep - r.rent - r.spent
	r.cash = cash
	misses = r.misses
	stats.served += r.customers - r.walkouts
	stats.sales += r.sales
	stats.peak = maxi(stats.peak, cash)
	if cash < 0:
		over = true
	else:
		roll_draft()
	return r


func roll_draft() -> void:
	var pool := PERKS.filter(func(p): return has(p.id) < p.max)
	draft = shuffled(pool).slice(0, 4 if has("cat") else 3)


func investor_cash() -> int:
	return 20000 * (1 + (day - 1) / 7)


func perk_desc(p: Dictionary) -> String:
	return p.desc % money(investor_cash()) if p.id == "investor" else p.desc


## Takes draft option i and starts the next morning.
func next_day(i: int) -> void:
	var p: Dictionary = draft[clampi(i, 0, draft.size() - 1)]
	perks[p.id] = has(p.id) + 1
	if p.id == "investor":
		cash += investor_cash()
	elif p.id == "camera":
		rep = minf(100.0, rep + 4.0)
	draft = []
	day += 1
	begin_day()


func expansions() -> Array:
	var out := []
	if stores[0].kind == "konbini":
		out.append({"id": "super0", "name": "Renovate into a supermarket", "desc": "12 shelves, fresh food, twice the shoppers. Rent ¥60,000/week.", "cost": 150000, "frame": 1})
	if stores.size() < 3:
		out.append({"id": "branch", "name": "Open branch konbini #%d" % (stores.size() + 1), "desc": "A second till across town. Rent ¥20,000/week.", "cost": 90000 * stores.size(), "frame": 0})
	for i in range(1, stores.size()):
		if stores[i].kind == "konbini":
			out.append({"id": "super%d" % i, "name": "Renovate branch #%d" % (i + 1), "desc": "Turn this branch into a supermarket.", "cost": 150000, "frame": 1})
	out.append({"id": "flagship", "name": "Build the flagship hypermarket", "desc": "Needs 3 stores. Builds your empire and wins the run.", "cost": FLAGSHIP_COST, "frame": 2, "locked": stores.size() < 3})
	return out


func expand(id: String) -> bool:
	for e in expansions():
		if e.id != id or e.get("locked", false) or cash < e.cost:
			continue
		cash -= e.cost
		if id == "branch":
			stores.append(new_store("konbini"))
		elif id == "flagship":
			won = true
			over = true
		else:
			var st: Dictionary = stores[int(id.substr(5))]
			st.kind = "super"
			while st.slots.size() < STORE["super"].slots:
				st.slots.append(empty_slot())
			var decor: Array = st.objects.filter(func(o): return o.type == "decor")
			st.objects = default_objects("super")
			for o in decor:
				if placement_ok(st, -1, o.cell, o):
					st.objects.append(o)
				else:
					cash += DECOR[o.id].cost  # no room after the refit: refunded
		return true
	return false
