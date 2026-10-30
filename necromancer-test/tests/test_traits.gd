extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
var checks = 0
var failures = 0
func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL TRAIT: "+label)
func fixture():
	var e = Rules.new(42,2)
	# Fixed fixture HP isolates trait arithmetic from unit balance changes.
	for id in {"vampire":15,"zombie_a":8,"zombie_b":8,"spear_a":10,"spear_b":10,"shield":20}:
		var hp = {"vampire":15,"zombie_a":8,"zombie_b":8,"spear_a":10,"spear_b":10,"shield":20}[id]
		e.unit(id).hp = hp
		e.unit(id).max_hp = hp
	e.unit("vampire").position = [2,3]
	e.unit("zombie_a").position = [0,0]
	e.unit("zombie_b").position = [1,0]
	e.unit("spear_a").position = [3,3]
	e.unit("spear_b").position = [4,3]
	e.unit("shield").position = [3,4]
	return e
func _init():
	var e = fixture()
	var events = e.apply_damage("spear_a","vampire",3,"test")
	check(e.unit("vampire").hp == 10,"two adjacent humans add two damage")
	check(events.back().amount == 5 and events.back().raw_amount == 3 and events.back().bonus == 2,"damage event reports base plus bonus")
	e.apply_damage("vampire","spear_a",4,"test")
	check(e.unit("spear_a").hp == 6,"human no longer reduces incoming damage")
	e.unit("spear_b").alive = false
	e.apply_damage("spear_a","vampire",1,"test")
	check(e.unit("vampire").hp == 8,"dead ally no longer grants bonus")
	e.unit("shield").position = [10,4]
	e.apply_damage("spear_a","vampire",1,"test")
	check(e.unit("vampire").hp == 7,"distant human and nearby undead grant no bonus")
	e = fixture()
	e.unit("shield").guarding = true
	e.apply_damage("vampire","spear_a",5,"test")
	check(e.unit("spear_a").hp == 10 and e.unit("shield").hp == 15,"guard transfer no longer reduces damage")
	e = fixture()
	e.unit("shield").guarding = true
	e.apply_damage("spear_b","spear_a",3,"friendly fire")
	check(e.unit("spear_a").hp == 10 and e.unit("shield").hp == 15,"guard transfer applies source two-ally bonus once")
	e = fixture()
	e.unit("spear_b").alive = false
	e.unit("zombie_a").position = [4,3]
	e.unit("zombie_b").position = [5,3]
	e.faction = "human"
	events = e.execute_action({"actor_id":"spear_a","kind":"SPEAR_THRUST","target_unit_id":"zombie_a"})
	var hits = events.filter(func(event): return event.type == "damage")
	check(hits.size() == 2 and hits.all(func(event): return event.bonus == 1 and event.amount == event.raw_amount+1),"area damage adds bonus per target")
	e.faction = "undead"
	events = e.execute_action({"actor_id":"zombie_a","kind":"MOVE","target_cell":[4,2]})
	hits = events.filter(func(event): return event.type == "damage")
	check(hits.size() > 0 and hits.all(func(event): return event.bonus == 1),"opportunity attacks also gain adjacent ally damage")
	e = fixture()
	e.domination = 7
	e.apply_damage("spear_a","zombie_a",8,"test")
	check(e.domination == 12,"undead death restores five")
	e.apply_damage("spear_a","zombie_a",8,"test")
	check(e.domination == 12,"dead unit does not restore twice")
	e.domination = 18
	e.apply_damage("vampire","zombie_b",8,"friendly fire")
	check(e.domination == 20,"friendly fire death also restores subject to cap")
	e.domination = 0
	var last_events = e.apply_damage("spear_a","vampire",15,"test")
	check(e.domination == 5 and e.winner == "human","last undead death restores before defeat")
	check(last_events.back().type == "victory","victory follows death trait")
	e = fixture()
	e.domination = 0
	e.apply_damage("vampire","shield",100,"test")
	check(e.domination == 0,"human death gives no domination")
	# Human friendly fire uses the attacker's outgoing bonus too.
	e = fixture()
	e.apply_damage("spear_b","spear_a",3,"friendly fire")
	check(e.unit("spear_a").hp == 5,"trait adds damage to friendly attacks")
	print("TRAIT RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
