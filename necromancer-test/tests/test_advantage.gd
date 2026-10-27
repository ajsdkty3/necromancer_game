extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Policy = preload("res://scripts/ai/HeuristicPolicy.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func fixture():
	var e = Rules.new(42,7)
	for u in e.units:
		u.position = [15,0]
	e.unit("vampire").position = [4,4]
	e.unit("spear_a").position = [5,4]
	e.unit("zombie_a").position = [5,3]
	e.unit("zombie_b").position = [6,3]
	return e
func _init():
	var e = fixture()
	var action = {"actor_id":"vampire","kind":"OVERHEAD_STRIKE","target_unit_id":"spear_a"}
	check(e.validate_action(action).valid,"three allies including actor unlock flat-ground advantage")
	e.unit("zombie_b").alive = false
	check(not e.validate_action(action).valid,"two living allies insufficient")
	e.unit("zombie_b").alive = true
	e.heights["7,4"] = 2 # target axial (5,4)
	check(not e.validate_action(action).valid,"encirclement does not bypass melee height limit")
	e.heights["7,4"] = 1
	check(e.validate_action(action).valid,"surrounded higher target within melee height limit")
	e.heights = {}
	e.execute_action(action)
	check(e.unit("spear_a").hp==0,"flat-ground advantage deals multiplied damage")
	e = fixture()
	e.unit("spear_a").position = [4,4]
	e.unit("vampire").position = [5,4]
	e.unit("spear_b").position = [5,3]
	e.unit("spear_c").position = [6,3]
	e.faction = "human"
	var shove = {"actor_id":"spear_a","kind":"KNOCKBACK","target_unit_id":"vampire"}
	check(e.validate_action(shove).valid,"surrounded enemy unlocks flat-ground shove")
	check(Policy.new().choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a")).kind=="KNOCKBACK","AI uses encirclement advantage")
	e.unit("spear_c").position = [15,0]
	check(not e.validate_action(shove).valid,"advantage updates when ally leaves")
	print("ADVANTAGE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
