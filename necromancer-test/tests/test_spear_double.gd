extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Policy = preload("res://scripts/ai/HeuristicPolicy.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func fixture():
	var e = Rules.new(42,1)
	e.faction = "human"
	e.unit("spear_a").position = [4,4]
	e.unit("vampire").position = [6,4]
	e.unit("zombie_a").position = [7,4]
	e.unit("zombie_b").position = [0,0]
	return e
func choice(e):
	return Policy.new().choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a"))
func _init():
	var e = fixture()
	check(e.unit("spear_a").ap==6 and e.attack_targets(e.unit("spear_a"),e.unit("vampire")).size()==1,"start can afford two single-target attacks")
	var action = choice(e)
	check(action.kind=="MOVE" and action.target_cell==[5,4],"safe move takes priority over current single attack")
	var events = e.execute_action(action)
	check(e.unit("spear_a").ap==5,"move leaves budget for only one attack")
	check(not events.any(func(v): return v.type=="reaction"),"entering zone is safe")
	action = choice(e)
	check(action.kind=="SPEAR_THRUST","attack after reposition without wandering")
	events = e.execute_action(action)
	check(events.filter(func(v): return v.type=="damage").size()==2,"both enemies hit")
	check(e.unit("spear_a").ap==2,"double-target attack consumes three AP after moving")
	e = fixture()
	e.unit("spear_a").ap = 3
	check(choice(e).kind=="SPEAR_THRUST","reserve attack AP")
	e = fixture()
	e.unit("zombie_b").position = [4,3]
	check(Policy.new().choose_spear_reposition(e.get_observation(),e.enumerate_legal_actions("spear_a"),e.unit("spear_a"),true).is_empty(),"no departure from active zone")
	e.unit("zombie_b").reaction_ready = false
	check(choice(e).kind=="MOVE","spent reaction permits reposition")
	e = fixture()
	e.unit("zombie_a").position = [0,1]
	e.unit("spear_b").position = [7,4]
	check(Policy.new().spear_double_target(e.get_observation(),e.unit("spear_a"),Vector2i(5,4))=="","friendly second target not a double attack")
	e = fixture()
	e.heights = {"9,4":2}
	check(Policy.new().spear_double_target(e.get_observation(),e.unit("spear_a"),Vector2i(5,4))=="","height-invalid second target excluded")
	e = fixture()
	var obs = e.get_observation()
	obs.focus_target_id = "vampire"
	check(Policy.new().choose_action(obs,e.enumerate_legal_actions("spear_a")).kind=="MOVE","focus target can be included in double attack")
	print("Spear double attack: %d failures" % failures)
	quit(1 if failures else 0)
