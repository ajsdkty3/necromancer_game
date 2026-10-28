extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Knight = preload("res://scripts/ai/KnightPolicy.gd")
const AI = preload("res://scripts/ai/AIController.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func fixture():
	var e = Rules.new(42,11)
	e.unit("undead_knight").position = [4,4]
	e.unit("knight").position = [8,4]
	e.unit("vampire").position = [8,3]
	e.unit("spear_a").position = [7,5]
	e.unit("zombie_a").position = [0,0]
	e.unit("spear_b").position = [15,0]
	return e
func _init():
	var e = fixture()
	var action = {"actor_id":"undead_knight","kind":"CHARGE","target_cell":[7,4]}
	var events = e.execute_action(action)
	check(e.unit("knight").hp==15 and e.unit("vampire").hp==15 and e.unit("spear_a").hp==9,"three hits including friendly damage are each five")
	check(e.unit("knight").position==[9,4] and e.unit("vampire").position==[9,2] and e.unit("spear_a").position==[7,6],"each target pushed away from impact origin")
	check(events.filter(func(v): return v.type=="damage").size()==3 and e.domination==15,"each target hit once with one charge fee")
	check(not events.any(func(v): return v.type=="reaction"),"neither charge nor pushes trigger reactions")
	for blocker in ["rock","unit","higher","edge"]:
		e = fixture()
		if blocker=="rock":
			e.obstacles["11,4"] = true
		elif blocker=="unit":
			e.unit("spear_b").position = [9,4]
		elif blocker=="higher":
			e.heights["11,4"] = 1
		else:
			e.board_width = 11
		e.execute_action(action)
		check(e.unit("knight").hp==15 and e.unit("knight").position==[8,4],"blocked push still deals damage: "+blocker)
	e = fixture()
	e.heights = {"9,4":1,"10,4":1}
	events = e.execute_action(action)
	var hits = events.filter(func(v): return v.type=="damage" and v.target=="knight")
	check(hits.size()==2 and hits[0].amount==5 and hits[1].amount==2,"fall separately resolves after charge damage")
	e = fixture()
	e.unit("spear_a").archetype = "shieldman"
	e.unit("spear_a").hp = 20
	e.unit("spear_a").max_hp = 20
	e.unit("spear_a").guarding = true
	e.execute_action(action)
	check(e.unit("knight").hp==20 and e.unit("spear_a").hp==10,"guardian receives both transferred and direct area damage")
	e = fixture()
	e.unit("knight").hp = 1
	e.unit("spear_a").alive = false
	e.unit("spear_b").alive = false
	e.execute_action(action)
	# Deployment order places the friendly vampire before the last human target.
	check(e.winner=="undead" and not e.unit("knight").alive,"terminal charge hit ends combat")
	# Human knight: two enemies and one ally qualifies; one each does not.
	e = fixture()
	e.unit("knight").position = [4,4]
	e.unit("undead_knight").position = [8,4]
	e.unit("spear_a").position = [8,3]
	e.unit("vampire").position = [7,5]
	e.execute_action({"kind":"END_TURN"})
	var ai = AI.new()
	var choice = ai.choose_action(e.get_observation(),e.enumerate_legal_actions("knight"))
	check(choice.kind=="CHARGE" and choice.target_cell==[7,4],"AI charges when enemies outnumber friendly hits")
	e.unit("vampire").position = [0,1]
	var score = Knight.charge_score(e.get_observation(),e.unit("knight"),Vector2i(4,4),Vector2i(7,4))
	check(score==-INF,"equal enemy and friendly hits forbids AI charge")
	choice = ai.choose_action(e.get_observation(),e.enumerate_legal_actions("knight"))
	check(choice.kind=="MOVE" and e.validate_action(choice).valid,"AI repositions to find better charge angle")
	var found = false
	for step in 12:
		choice = ai.choose_action(e.get_observation(),e.enumerate_legal_actions("knight"))
		if choice.kind=="CHARGE":
			found = true
			break
		if choice.kind!="MOVE":
			break
		e.execute_action(choice)
	check(found,"repositioning reaches a favorable charge angle without looping")
	print("CHARGE AREA RESULT: %d failures" % failures)
	quit(1 if failures else 0)
