extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Events = preload("res://scripts/core/RandomEvents.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func trigger(e,kind):
	Events.apply(e,kind,Events.candidates(e))
func _init():
	var e = Rules.new(42)
	var u = e.unit("spear_a")
	u.hp = 1
	u.morale_base = 0
	e.refresh_morale()
	check(u.fleeing,"fixture fleeing")
	trigger(e,"REINFORCEMENTS")
	check(e.units.back().archetype == "knight" and e.units.back().hp == 16 and Hex.to_offset(e.pos(e.units.back())).x == 19,"cavalry on right edge")
	check(u.morale == 20 and u.max_morale == 120 and not u.fleeing,"reinforcement rallies while preserving low HP penalty")
	check(e.unit("spear_b").morale == 120 and e.units.back().morale == 120,"all humans including cavalry gain morale")
	e.refresh_morale()
	check(u.morale == 20 and not u.fleeing,"rally survives recomputation")
	check(e.initial_human_count == 4,"reinforcement counts toward human total")
	var size = e.units.size()
	trigger(e,"SURGE")
	check(e.units.size() == size and e.domination_cap == 20,"only one event in battle")
	e = Rules.new(42)
	for r in 10:
		e.obstacles["19,%d" % r] = true
	check(not Events.candidates(e).has("REINFORCEMENTS"),"blocked edge excludes reinforcement")
	for c in Hex.cells(20,10):
		var offset = Hex.to_offset(c)
		e.obstacles["%d,%d" % [offset.x,offset.y]] = true
	check(not Events.candidates(e).has("AWAKENING"),"no empty neighbor excludes awakening")
	e = Rules.new(42)
	trigger(e,"AWAKENING")
	var zombie = e.units.back()
	check(zombie.team == "undead" and zombie.archetype == "zombie" and zombie.hp == 10,"awakening creates full HP zombie")
	check(e.units.any(func(ally): return ally.id != zombie.id and ally.alive and ally.team == "undead" and Hex.distance(e.pos(ally),e.pos(zombie)) == 1),"awakening next to undead")
	e = Rules.new(42)
	e.domination = 0
	trigger(e,"SOUL_RAMPAGE")
	check(e.domination_cap == 40 and e.domination == 25,"rampage cap plus twenty recovery plus soul five")
	check(e.units.filter(func(ally): return ally.team == "undead" and not ally.alive).size() == 1,"exactly one undead killed")
	e = Rules.new(42)
	e.unit("zombie_a").alive = false
	e.unit("zombie_b").alive = false
	trigger(e,"SOUL_RAMPAGE")
	check(e.winner == "human" and not e.unit("vampire").alive,"last undead lost ends battle immediately")
	e = Rules.new(42)
	trigger(e,"BACKLASH")
	check(e.domination == 0 and e.domination_cap == 20,"backlash clears current only")
	e = Rules.new(42)
	trigger(e,"SURGE")
	check(e.domination == 30 and e.domination_cap == 30,"surge raises cap and current")
	var triggered = 0
	for seed_value in 100:
		e = Rules.new(seed_value)
		Events.roll(e)
		check(not e.random_event_used and e.random_event_checked_round == 0,"no early event")
		e.round_number = 4
		Events.roll(e)
		if e.random_event_used:
			triggered += 1
		var rng_state = e.rng.state
		Events.roll(e)
		check(e.rng.state == rng_state,"only one check per round")
	check(triggered > 25 and triggered < 75,"fifty percent seeded sampling")
	e = Rules.new(7)
	for round_index in 8:
		e.execute_action({"kind":"END_TURN"})
		while e.faction == "human" and not e.is_terminal():
			e.execute_action({"actor_id":e.active_human(),"kind":"END_UNIT"})
	var replay = Rules.new(7)
	for action in e.history:
		replay.execute_action(action)
	check(JSON.stringify(e.get_observation()) == JSON.stringify(replay.get_observation()),"events deterministic under action replay")
	check(Rules.new(7).random_event_used == false,"restart clears event state")
	print("Random event failures: ",failures)
	quit(failures)
