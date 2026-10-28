extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Controller = preload("res://scripts/ai/AIController.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr(message)
func fixture():
	var e = Rules.new(42,1)
	e.heights = {}
	e.obstacles = {}
	for u in e.units:
		u.alive = u.id in ["spear_a","spear_b","vampire","zombie_a"]
	e.unit("spear_a").position = [3,3]
	e.unit("spear_b").position = [3,5]
	e.unit("vampire").position = [5,3]
	e.unit("vampire").hp = 4
	e.unit("zombie_a").position = [5,4]
	e.unit("zombie_a").hp = 1
	e.faction = "human"
	e.human_index = 0
	return e
func _init():
	var e = fixture()
	var ai = Controller.new()
	var action = ai.choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a"))
	check(ai.focus_plan.target_id=="vampire" and ai.focus_plan.value==10,"high value target beats low HP zombie")
	check(ai.focus_plan.contributors.size()==2 and ai.focus_plan.damage>=4,"combined team damage enables focus")
	var steps = 0
	while action.kind=="MOVE" and steps<3:
		var events = e.execute_action(action)
		check(not events.any(func(event): return event.type=="reaction"),"focus reposition avoids reactions")
		steps += 1
		action = ai.choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a"))
	check(action.kind=="SPEAR_THRUST" and e.attack_targets(e.unit("spear_a"),e.unit(action.get("target_unit_id",""))).has("vampire"),"repositioned attack still hits original focus target")
	e = fixture()
	e.unit("vampire").hp = 100
	ai.choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a"))
	check(ai.focus_plan.target_id=="zombie_a" and ai.focus_plan.value==3,"unreachable kill budget falls back to killable zombie")
	e = fixture()
	e.human_index = 1
	e.unit("vampire").hp = 6
	ai.choose_action(e.get_observation(),e.enumerate_legal_actions("spear_b"))
	check(ai.focus_plan.target_id=="zombie_a","already finished actors excluded from remaining budget")
	e = fixture()
	e.unit("vampire").alive = false
	action = ai.choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a"))
	check(ai.focus_plan.target_id=="zombie_a" and e.validate_action(action).valid,"dead focus target replaced with legal action")
	e.unit("spear_a").ap = 0
	e.unit("spear_b").ap = 0
	ai.choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a"))
	check(ai.focus_plan.is_empty(),"no AP means no promised output")
	print("FOCUS AI RESULT: %d failures" % failures)
	quit(1 if failures else 0)
