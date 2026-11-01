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
	# determinism: same seed, same run
	assert(play("same").day == play("same").day and play("same").cash == play("same").cash)
	var ok: bool = supers.size() > RUNS * 0.5 and won.size() > RUNS * 0.2 and bust.size() > 0
	print("BALANCE OK" if ok else "BALANCE FAIL")
	quit(0 if ok else 1)


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
