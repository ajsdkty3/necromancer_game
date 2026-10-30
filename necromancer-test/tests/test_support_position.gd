extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const AI = preload("res://scripts/ai/AIController.gd")
const Support = preload("res://scripts/ai/SupportPolicy.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func _init():
	var e = Rules.new(42,14)
	var ids = e.humans().map(func(u): return u.id)
	check(ids.slice(-4) == ["l14_human_0","l14_human_1","l14_human_2","l14_human_3"],"commanders then shields act last")
	check(e.units[10].id == "l14_human_0","deployment order preserved")
	e.heights = {}
	e.faction = "human"
	e.human_index = 6
	var c = e.unit("l14_human_0")
	c.ap = 9 # Extra fixture AP tests repositioning while reserving the six-point order.
	c.position = [5,4]
	e.unit("l14_human_4").position = [6,3]
	e.unit("l14_human_5").position = [7,4]
	e.unit("l14_human_6").position = [6,5]
	var ai = AI.new()
	var first = ai.choose_action(e.get_observation(),e.enumerate_legal_actions(c.id))
	check(first.kind == "MOVE","move toward three allies before ordering beside one")
	var calls = 0
	while not c.get("battle_order",false) and calls < 5:
		var action = ai.choose_action(e.get_observation(),e.enumerate_legal_actions(c.id))
		check(e.validate_action(action).valid,"support action legal")
		e.execute_action(action)
		calls += 1
	check(c.get("battle_order",false) and Support.coverage(e.get_observation(),c,e.pos(c),true) >= 3,"cast after maximizing coverage")
	check(c.ap >= 0,"reserve cast AP")
	e.human_index = 8
	var shield = e.unit("l14_human_2")
	shield.position = [5,4]
	c.position = [0,0]
	shield.ap = 6
	var choice = ai.choose_action(e.get_observation(),e.enumerate_legal_actions(shield.id))
	check(choice.kind == "GUARD","six AP shield reserves entire guard cost")
	shield.ap = 8
	choice = ai.choose_action(e.get_observation(),e.enumerate_legal_actions(shield.id))
	check(choice.kind == "MOVE","shield repositions first when AP permits both")
	# Support units must leave a support-only cluster to help combat units.
	for actor_id in ["l14_human_0","l14_human_2"]:
		e = Rules.new(42,14)
		e.heights = {}
		e.faction = "human"
		e.human_index = e.humans().map(func(u): return u.id).find(actor_id)
		var actor = e.unit(actor_id)
		actor.position = [5,4]
		for u in e.humans():
			if u.id != actor_id:
				u.alive = false
		var helper = e.unit("l14_human_1")
		helper.alive = true
		helper.position = [5,3]
		var fighter = e.unit("l14_human_4")
		fighter.alive = true
		fighter.position = [9,4]
		var order = actor.archetype == "commander"
		check(Support.coverage(e.get_observation(),actor,e.pos(actor),order)==0,"support-only neighbor gives no AI coverage score")
		choice = ai.choose_action(e.get_observation(),e.enumerate_legal_actions(actor_id))
		check(choice.kind == "MOVE","leave support-only cluster toward combat ally")
		fighter.alive = false
		choice = ai.choose_action(e.get_observation(),e.enumerate_legal_actions(actor_id))
		check(choice.kind not in ["GUARD","BATTLE_ORDER"],"do not cast only for another support unit")
	print("Support positioning failures: ",failures)
	quit(failures)
