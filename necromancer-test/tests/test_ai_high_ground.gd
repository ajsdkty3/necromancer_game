extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Policy = preload("res://scripts/ai/HeuristicPolicy.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr(message)
func fixture():
	var e = Rules.new(42,1)
	e.heights = {"4,3":1}
	e.obstacles = {}
	for u in e.units:
		u.alive = u.id in ["archer","vampire"]
	e.unit("archer").position = [2,3]
	e.unit("vampire").position = [6,3]
	e.faction = "human"
	e.human_index = e.humans().find(e.unit("archer"))
	return e
func choose(e):
	return Policy.new().choose_action(e.get_observation(),e.enumerate_legal_actions("archer"))
func _init():
	var e = fixture()
	var action = choose(e)
	check(action.kind=="MOVE" and action.target_cell==[3,3],"climb to a useful firing position")
	e.execute_action(action)
	check(choose(e).kind=="OVERHEAD_STRIKE","attack downhill after climbing")
	e = fixture()
	e.unit("archer").ap = 3
	check(choose(e).kind=="SHOOT","retain attack when climbing leaves insufficient AP")
	e = fixture()
	e.unit("vampire").hp = 1
	check(choose(e).kind=="MOVE","climb before attacking even when normal attack can kill")
	e = fixture()
	e.unit("archer").ap = 4
	e.unit("vampire").hp = 3
	action = choose(e)
	check(action.kind=="MOVE","with only one move and one attack available climb first")
	e.execute_action(action)
	check(e.unit("archer").ap==2 and choose(e).kind=="OVERHEAD_STRIKE","reserved AP is used for special attack")
	e = fixture()
	e.unit("archer").alive = false
	e.unit("spear_a").alive = true
	e.unit("spear_a").position = [2,3]
	e.unit("spear_a").ap = 5
	e.unit("vampire").position = [4,3]
	e.unit("vampire").hp = 3
	e.human_index = e.humans().find(e.unit("spear_a"))
	action = Policy.new().choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a"))
	check(action.kind=="MOVE","spearman climbs to unlock height restricted special")
	e.execute_action(action)
	action = Policy.new().choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a"))
	check(action.kind=="KNOCKBACK","spearman uses knockback after gaining height advantage")
	e = fixture()
	e.unit("vampire").position = [3,2]
	check(choose(e).kind=="SHOOT","avoid reaction damage for optional climb")
	e = fixture()
	e.unit("vampire").position = [8,3]
	action = choose(e)
	check(action.kind=="MOVE" and action.target_cell==[3,3],"prefer elevated approach before entering range")
	print("HIGH GROUND AI RESULT: %d failures" % failures)
	quit(1 if failures else 0)
