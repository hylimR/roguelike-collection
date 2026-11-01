extends SceneTree
## Headless check: a greedy bot plays many seeds; asserts the progression is reachable and runs can be lost.
## godot --headless --path games/konbini-empire --script res://tests/balance.gd

const Sim := preload("res://sim.gd")
const RUNS := 120
const MAX_DAY := 90
const PERK_ORDER := ["register", "parttimer", "coffee", "fryer", "truck", "loyalty", "poster", "fridge", "investor", "cat", "neon", "camera"]


func _init() -> void:
	var res := []
	for i in RUNS:
		res.append(play("bot%d" % i))
	var won := res.filter(func(r): return r.won)
	var bust := res.filter(func(r): return not r.won and r.over)
	var supers := res.filter(func(r): return r.super > 0).map(func(r): return r.super)
	var wins := won.map(func(r): return r.day)
	supers.sort()
	wins.sort()
	print("runs %d  won %d  bankrupt %d  stalled %d" % [RUNS, won.size(), bust.size(), RUNS - won.size() - bust.size()])
	print("bankrupt days: ", bust.map(func(r): return r.day))
	print("supermarket day median %s  (n=%d)" % [med(supers), supers.size()])
	print("win day median %s  min %s" % [med(wins), wins[0] if wins.size() else "-"])
	var a := play("same")
	var b := play("same")
	var same: bool = a.day == b.day and a.cash == b.cash
	var layout := layout_ok()
	print("deterministic %s  layout rules %s" % [same, layout])
	var ok: bool = supers.size() > RUNS * 0.5 and won.size() > RUNS * 0.2 and bust.size() > 0 and same and layout
	print("BALANCE OK" if ok else "BALANCE FAIL")
	quit(0 if ok else 1)


## Default plans are valid; overlaps and walling a shelf in are refused; decor buys, sells and survives a refit.
func layout_ok() -> bool:
	var s := Sim.new()
	s.start("layout")
	var st: Dictionary = s.stores[0]
	for i in st.objects.size():
		if not Sim.placement_ok(st, i, st.objects[i].cell):
			return false
	var overlap: bool = s.move_object(0, 1, Vector2i(2, 3))
	# shelf 0 sits on (2,3)-(3,3): three tiles around it are fine, the fourth would wall it in
	var fenced: bool = s.buy_decor(0, 0, Vector2i(2, 4)) and s.buy_decor(0, 0, Vector2i(3, 4)) and s.buy_decor(0, 0, Vector2i(2, 2))
	var walled: bool = s.buy_decor(0, 0, Vector2i(3, 2))
	var cash: int = s.cash
	s.sell_decor(0, st.objects.size() - 1)
	var refund: bool = s.cash == cash + Sim.DECOR[0].cost / 2
	s.cash = 1000000
	s.expand("super0")
	var kept: int = s.stores[0].objects.filter(func(o): return o.type == "decor").size()
	return not overlap and fenced and not walled and refund and kept == 2 and Sim.appeal(s.stores[0]) == 2


func med(a: Array):
	return a[a.size() / 2] if a.size() else "-"


func play(seed_str: String) -> Dictionary:
	var s := Sim.new()
	s.start(seed_str)
	var first_super := -1
	while not s.over and s.day <= MAX_DAY:
		s.event_text()  # formatting smoke test: every event text is built at least once
		prep(s)
		if s.over:
			break
		s.simulate_day()
		if s.over:
			break
		if first_super < 0 and s.stores[0].kind == "super":
			first_super = s.day
		var best := 0
		for i in s.draft.size():
			if PERK_ORDER.find(s.draft[i].id) < PERK_ORDER.find(s.draft[best].id):
				best = i
		s.next_day(best)
	return {"day": s.day, "won": s.won, "over": s.over, "super": first_super, "cash": s.cash}


func value(s, pid: int, kind: String) -> float:
	var d := 0.0
	for ai in Sim.A.size():
		d += Sim.A[ai].wants.get(Sim.P[pid].id, 0.0) * Sim.STORE[kind].mix[ai]
	return d * (Sim.P[pid].price - s.wholesale[pid])


func prep(s) -> void:
	var reserve: int = s.weekly_rent() + 30000
	for e in s.expansions():
		if not e.get("locked", false) and s.cash > e.cost + reserve:
			s.expand(e.id)
			break
	for si in s.stores.size():
		var st: Dictionary = s.stores[si]
		var kind: String = st.kind
		var ranked: Array = s.products_for(Sim.STORE[kind].tier)
		ranked.sort_custom(func(a, b): return value(s, a, kind) > value(s, b, kind))
		var used := []
		for slot in st.slots:
			if slot.pid >= 0:
				used.append(slot.pid)
		for i in st.slots.size():
			var slot: Dictionary = st.slots[i]
			if slot.pid < 0:
				for pid in ranked:
					if pid not in used and s.can_stock(si, pid):
						used.append(pid)
						slot.pid = pid
						break
			var target: int = s.cap_of(si)
			if Sim.P[slot.pid].perish:
				target = mini(target, slot.sold + 4 if slot.sold > 0 else target / 2)
			s.buy(si, i, slot.pid, target - slot.qty)
