extends SceneTree
## Headless check of the rules: the spec's RNG vectors, curves and starting state, invariants while a bot plays a
## few days on two seeds, and a same-seed replay.
## godot --headless --path games/konbini-empire --script res://tests/balance.gd

const Sim := preload("res://sim.gd")
const DAYS := 8
const SEEDS := [1000, 1077]

var fails := []


func check(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)
		print("FAIL ", what)


func near(a: float, b: float, eps := 0.001) -> bool:
	return absf(a - b) <= eps


func _init() -> void:
	vectors()
	curves()
	start_state()
	var t0 := Time.get_ticks_msec()
	var a := {}
	for s in SEEDS:
		a = play(s)
	var b := play(SEEDS[-1], false)
	check(a.sig == b.sig, "same seed replays identically (%s vs %s)" % [a.sig, b.sig])
	print("bot runs took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RULES OK" if fails.is_empty() else "RULES FAIL (%d)" % fails.size())
	quit(0 if fails.is_empty() else 1)


func vectors() -> void:
	var r := Sim.Rng.new(12345)
	var want := [0.9797282677609473, 0.3067522644996643, 0.484205421525985, 0.817934412509203, 0.5094283693470061]
	for w in want:
		check(near(r.next(), w, 1e-15), "mulberry32(12345) -> %s" % w)
	check(r.s == 567906818, "mulberry32(12345) seed after 5 draws is %d" % r.s)
	r = Sim.Rng.new(0)
	for w in [0.26642920868471265, 0.0003297457005828619, 0.2232720274478197]:
		check(near(r.next(), w, 1e-15), "mulberry32(0) -> %s" % w)
	check(Sim.rnd(2.5) == 3 and Sim.rnd(-2.5) == -2 and Sim.rnd(87.5) == 88, "round halves toward +inf")


func curves() -> void:
	var xp := []
	for L in range(1, 11):
		xp.append(Sim.xp_for_level(L))
	check(xp == [70, 91, 118, 154, 200, 260, 338, 439, 571, 742], "xp curve %s" % [xp])
	var ex := []
	for n in 9:
		ex.append(Sim.expansion_cost({"expansions": n}))
	check(ex == [900, 1242, 1714, 2365, 3264, 4504, 6216, 8578, 11838], "expansion costs %s" % [ex])
	var s := Sim.new()
	s.create_run(42)
	var rr := []
	for n in 7:
		s.player.rerolls = n
		rr.append(s.reroll_cost())
	check(rr == [200, 320, 512, 819, 1311, 2097, 3355], "reroll costs %s" % [rr])
	var sc := []
	for n in range(1, 7):
		s.run_stats.stores_opened = n
		sc.append(s.store_cost())
	check(sc == [7000, 11900, 20230, 34391, 58465, 99390], "store costs %s" % [sc])
	var b: Dictionary = s.branches[0]
	var ages := []
	for d in [0, 5, 10, 15, 19, 30]:
		s.day = b.opened + d
		ages.append(snappedf(s.rent(b) / 1300.0, 0.001))
	s.day = 1
	check(ages == [1.0, 1.276, 1.629, 2.079, 2.5, 2.5], "rent age multipliers %s" % [ages])
	var hp := []
	for t in range(3, 7):
		hp.append(int(s.create_rival("mega", t).max_hp))
	check(hp == [85000, 136000, 217600, 348160], "MEGAMART HP by tier %s" % [hp])
	var ap := []
	for stars in [0.5, 3.0, 5.0]:
		b.store.rating = stars
		ap.append(snappedf(s.player_appeal(b), 0.01))
	b.store.rating = 3.0
	check(near(ap[0], 5.61) and near(ap[1], 11.17) and near(ap[2], 15.61), "player appeal %s" % [ap])
	var price := func(stores: int, d: String) -> int:
		s.run_stats.stores_opened = stores
		return Sim.rnd(s.store_cost() * Sim.DISTRICTS[d].cost / 100.0) * 100
	var second := Sim.DISTRICTS.keys().map(func(d): return price.call(1, d))
	var third := Sim.DISTRICTS.keys().map(func(d): return price.call(2, d))
	check(second == [7000, 7700, 8800, 10200, 13300], "second-store listing prices %s" % [second])
	check(third == [11900, 13100, 14900, 17300, 22600], "third-store listing prices %s" % [third])


func start_state() -> void:
	var s := Sim.new()
	s.create_run(42)
	var b: Dictionary = s.branches[0]
	var hana: Dictionary = b.store.crew[0]
	check(s.rng_seed == 42 and s.phase == "intro" and s.player.cash == 2200 and s.day == 1, "createRun(42) basics")
	check(b.district == "sakura" and b.quirk == "plain" and b.rival.id == "tanuki" and b.rival.max_hp == 3600.0 and b.rival.attack_timer == 28.0, "Sakura vs Tanuki Mart")
	check(hana.id == 1 and hana.name == "Hana" and hana.trait_id == "steady" and hana.wage >= 230 and hana.wage <= 290 and hana.wage % 10 == 0, "Hana, steady, wage %d" % hana.wage)
	check(b.store.applicants.size() == 10 and b.store.applicants[0].id == 100, "ten applicants from id 100")
	check(s.bills_due() == 1300 + hana.wage, "first night's bills")
	check(near(s.player_appeal(b), 11.1667, 0.001) and near(s.rival_appeal(b), 10.0), "day-1 appeal: you 11.17, Tanuki 10")
	var r := Sim.Rng.new(7)
	var n := {"player": 0, "rival": 0, "none": 0}
	s.rng = r
	for k in 20000:
		n[s.choose_target(b, "drink")] += 1
	check(near(n.player / 20000.0, 0.44, 0.015) and near(n.rival / 20000.0, 0.40, 0.015), "day-1 choice split %s" % [n])
	# a rejected action leaves the seed alone
	s.act({"type": "start"})
	var before := s.rng_seed
	s.act({"type": "ringUp", "register": 0})
	check(s.rng_seed == before, "rejected action keeps the seed")


## A bot with ~0.7 skill: rings up, clicks threats, restocks keeping 1.3 days of bills, hires, buys expansions,
## takes the first card of every pick, opens a store when it can afford one with a cushion.
func play(seed_: int, verbose := true) -> Dictionary:
	var s := Sim.new()
	s.create_run(seed_)
	s.act({"type": "start"})
	var r := Sim.Rng.new(seed_ * 7 + 1)
	var lines := []
	var think := 0.0
	var fails0 := fails.size()
	while s.phase != "gameOver" and s.day <= DAYS:
		if s.phase == "choice":
			var c: Dictionary = s.choice
			var ok := false
			for k in c.options.size():
				if s.act({"type": "pickChoice", "id": c.options[k] if c.source != "listing" else k}):
					ok = true
					break
			if not ok:
				s.act({"type": "closeChoice"})
			continue
		var day := s.day
		s.tick(0.1)
		invariants(s)
		if fails.size() > fails0:
			break
		if s.day != day and s.report != null:
			var rep: Dictionary = s.report
			lines.append("  d%d cash ¥%d bills ¥%d lvl %d rivals %d | %s" % [rep.day, rep.cash_after, rep.bills, s.player.level, s.run_stats.rivals_defeated,
				" ".join(rep.rows.map(func(w): return "%s:%d/%d%s" % [w.name.get_slice(" ", 0), w.stats.revenue, w.rent + w.wages, "✓" if w.defeated else "(%d%%)" % roundi(100.0 * w.rival_hp / w.rival_max)]))])
		think += 0.1
		if think < 0.5:
			continue
		think = 0.0
		bot_turn(s, r)
	if verbose:
		print("seed %d: %s after %d days, %d store(s)" % [seed_, "bankrupt" if s.phase == "gameOver" else "alive", s.run_stats.days, s.branches.size()])
		for l in lines:
			print(l)
	check(s.run_stats.days >= 3, "seed %d survives three nights" % seed_)
	var sig := "%d/%d/%.3f/%d" % [s.player.cash, s.day, s.player.xp, s.run_stats.revenue]
	for b in s.branches:
		sig += "/%.2f" % b.rival.hp
	return {"sig": sig}


func bot_turn(s, r) -> void:
	var skill := 0.7
	for i in s.branches.size():
		s.act({"type": "switchStore", "index": i})
		var b: Dictionary = s.branches[i]
		for reg in b.store.registers:
			if r.chance(skill):
				s.act({"type": "ringUp", "register": reg.id})
		for t in b.threats.duplicate():
			if r.chance(skill):
				s.act({"type": "clickThreat", "id": t.id})
		var reserve := int(s.bills_due() * 1.3)
		for pid in b.store.products:
			var p: Dictionary = b.store.products[pid]
			if p.stock < p.capacity * 0.5 and s.player.cash > reserve + 300:
				s.act({"type": "restock", "product": pid})
		for id in s.player.abilities:
			s.act({"type": "useAbility", "id": id})
		if s.player.cash > reserve + 1500:
			for role in ["stocker", "cleaner", "guard"]:
				var ap: Array = b.store.applicants.filter(func(a): return a.role == role)
				if not ap.is_empty() and b.store.crew.filter(func(m): return m.role == role).size() < 1:
					s.act({"type": "hire", "id": ap[0].id})
		if s.player.cash > reserve + Sim.expansion_cost(b.store) + 500:
			s.act({"type": "openExpansion"})
			if s.phase == "choice":
				return
	if not s.pending.is_empty():
		s.act({"type": "openPick"})
		return
	if s.branches.size() < 3 and s.player.cash > s.store_cost() * 1.9 + s.bills_due() * 2:
		s.act({"type": "openListings"})


func invariants(s) -> void:
	for b in s.branches:
		check(b.agents.size() <= Sim.MAX_PEDS, "at most 120 pedestrians")
		check(b.store.rating >= 0.5 and b.store.rating <= 5.0, "rating in range")
		for pid in b.store.products:
			var p: Dictionary = b.store.products[pid]
			check(p.stock >= 0 and p.stock <= p.capacity, "stock in range")
		for reg in b.store.registers:
			check(reg.queue.size() <= Sim.MAX_QUEUE[reg.id], "queue within its cap")
		check(b.rival.hp >= 0.0 or not b.rival.defeated, "rival hp")
	check(typeof(s.player.cash) == TYPE_INT, "cash stays an integer")
