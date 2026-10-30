extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Morale = preload("res://scripts/core/MoraleRules.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func _init():
	var e = Rules.new(42)
	e.unit("spear_a").position = [5,4]
	e.unit("spear_b").position = [6,4]
	e.apply_damage("vampire","spear_b",100,"test")
	var u = e.unit("spear_a")
	check(u.morale == 60,"nearby death -20 plus adjacent corpse -20")
	e.refresh_morale()
	check(u.morale == 60,"corpse penalty does not accumulate")
	e.apply_damage("vampire","spear_b_corpse",100,"test")
	check(u.morale == 80,"destruction removes only corpse penalty")
	e.create_corpse({"id":"fixture1","name":"test","position":[6,4]})
	e.create_corpse({"id":"fixture2","name":"test","position":[5,5]})
	e.refresh_morale()
	check(u.morale == 40,"two adjacent corpses stack")
	check(Morale.penalties(e.unit("vampire"),3,1,e.units) == 0,"undead immune")
	u.position = [3,4]
	e.refresh_morale()
	check(u.morale == 80,"moving away removes corpse penalty")
	u.position = [5,4]
	e.execute_action({"kind":"SUMMON_ZOMBIE","target_unit_id":"fixture1_corpse"})
	check(u.morale == 60,"summoning consumes corpse and removes its penalty")
	u.morale_base = 20
	e.refresh_morale()
	check(u.morale == 0 and u.fleeing,"corpse penalty can trigger fleeing")
	check(not u.flee_trapped,"corpses do not count as enemy encirclement")
	print("Corpse morale failures: ",failures)
	quit(failures)
