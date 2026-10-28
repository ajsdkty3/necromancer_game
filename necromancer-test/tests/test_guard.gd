extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Policy = preload("res://scripts/ai/AIController.gd")
var failures = 0
var checks = 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL GUARD: " + label)

func fixture():
	var e = Rules.new(42,2)
	for u in e.units:
		u.alive = u.id in ["vampire","spear_a","shield"]
	e.unit("vampire").position = [2,3]
	e.unit("spear_a").position = [3,3]
	e.unit("shield").position = [4,3]
	return e

func activate(e):
	e.execute_action({"kind":"END_TURN"})
	e.execute_action({"actor_id":"spear_a","kind":"END_UNIT"})
	return e.execute_action({"actor_id":"shield","kind":"GUARD"})

func _init():
	var e = fixture()
	check(e.unit("shield").hp == 30 and e.unit("shield").ap == 6,"shield base stats")
	activate(e)
	check(e.unit("shield").guarding and e.unit("shield").ap == 0,"guard costs six")
	check(not e.validate_action({"actor_id":"shield","kind":"GUARD"}).valid,"guard cannot stack or refresh in same turn")
	e.execute_action({"actor_id":"shield","kind":"END_UNIT"})
	check(e.unit("shield").guarding,"guard persists through undead turn")
	var events = e.apply_damage("vampire","spear_a",4,"test")
	check(e.unit("spear_a").hp == 14 and e.unit("shield").hp == 26,"all damage redirects")
	check(events[0].type == "protected" and events[1].target == "shield","protected visual precedes guardian hit")
	e.execute_action({"kind":"END_TURN"})
	check(not e.unit("shield").guarding and e.unit("shield").ap == 6,"expires at next human start")
	e.apply_damage("vampire","spear_a",2,"test")
	check(e.unit("spear_a").hp == 12,"expired guard does not protect")

	e = fixture()
	e.unit("shield").guarding = true
	var other = e.unit("shield").duplicate(true)
	other.id = "shield_b"
	other.name = "盾兵乙"
	other.position = [4,2]
	e.units.append(other)
	e.apply_damage("vampire","shield",3,"test")
	check(e.unit("shield").hp == 27 and other.hp == 30,"active guardians do not guard each other")
	e.apply_damage("vampire","shield_b",2,"test")
	check(e.unit("shield").hp == 27 and other.hp == 28,"mutual exclusion is symmetric")
	e.apply_damage("vampire","spear_a",2,"test")
	check(e.unit("shield").hp == 25 and other.hp == 28,"multiple guardians use deployment order once")
	other.guarding = false
	e.apply_damage("vampire","shield_b",2,"test")
	check(e.unit("shield").hp == 23 and other.hp == 28,"active guard protects inactive shield")
	e.unit("shield").hp = 1
	e.apply_damage("vampire","spear_a",4,"test")
	check(not e.unit("shield").alive and e.unit("spear_a").hp == 14,"guardian dies without spillback")
	e.apply_damage("vampire","spear_a",2,"test")
	check(e.unit("spear_a").hp == 12,"dead guardian no longer protects")
	other.guarding = true
	e.apply_damage("vampire","spear_a",2,"test")
	check(e.unit("spear_a").hp == 12 and other.hp == 26,"next living guardian can protect")
	other.position = [12,3]
	e.apply_damage("vampire","spear_a",2,"test")
	check(e.unit("spear_a").hp == 10,"only adjacent six cells protected")

	# Real spear area: first target is protected; second hit is the guardian itself.
	e = fixture()
	e.unit("spear_a").position = [2,3]
	e.unit("vampire").position = [3,3]
	e.unit("shield").team = "undead"
	e.unit("shield").guarding = true
	e.faction = "human"
	var before = e.unit("shield").hp
	events = e.execute_action({"actor_id":"spear_a","kind":"SPEAR_THRUST","target_unit_id":"vampire"})
	var damage = events.filter(func(event): return event.type == "damage")
	check(damage.size() == 2,"area hits guardian twice")
	check(damage.all(func(event): return event.target == "shield"),"both area damage instances land on guardian")
	check(e.unit("shield").hp == before-damage[0].amount-damage[1].amount and e.unit("vampire").hp == 20,"area damage sums independent rolls")
	# Reactions also use the same redirection.
	e.faction = "undead"
	events = e.execute_action({"actor_id":"vampire","kind":"MOVE","target_cell":[3,4]})
	check(events.any(func(event): return event.type == "protected"),"opportunity damage redirects")

	e = fixture()
	activate(e)
	e.unit("shield").guarding = false
	e.unit("shield").ap = 2
	check(not e.validate_action({"actor_id":"shield","kind":"GUARD"}).valid,"guard rejects insufficient AP")
	e.unit("shield").ap = 6
	var policy = Policy.new()
	var action = policy.choose_action(e.get_observation(),e.enumerate_legal_actions("shield"))
	check(action.kind == "GUARD","AI guards threatened adjacent ally")
	e.execute_action(action)
	check(policy.choose_action(e.get_observation(),e.enumerate_legal_actions("shield")).kind != "GUARD","AI does not repeat active guard")
	e.unit("vampire").position = [4,4]
	var bash = {"actor_id":"shield","kind":"SHIELD_BASH","target_unit_id":"vampire"}
	e.unit("shield").ap = 6
	events = e.execute_action(bash)
	check(e.unit("shield").ap == 0 and e.unit("vampire").hp == 18,"shield bash base one to two plus adjacent ally bonus")

	var replay_source = Rules.new(7,2)
	# Active guard prioritizes protecting two allies even over a guaranteed kill.
	var support = fixture()
	support.faction = "human"
	support.human_index = 2
	support.unit("shield").position = [3,3]
	support.unit("shield").guarding = true
	support.unit("shield").ap = 3
	support.unit("vampire").position = [2,3]
	support.unit("vampire").hp = 1
	support.unit("spear_a").position = [5,3]
	support.unit("spear_b").alive = true
	support.unit("spear_b").position = [4,4]
	var support_action = policy.choose_action(support.get_observation(),support.enumerate_legal_actions("shield"))
	check(support_action.kind == "MOVE","guard coverage outranks adjacent guaranteed kill")
	support.execute_action(support_action)
	var support_policy = policy.policy
	check(support_policy.guard_coverage(support.get_observation(),support.unit("shield"),support.pos(support.unit("shield"))) == 2,"guard moves to protect both allies")
	support.unit("shield").ap = 3
	support_action = policy.choose_action(support.get_observation(),support.enumerate_legal_actions("shield"))
	check(support_action.kind == "END_UNIT","guard holds best coverage instead of chasing enemy")
	support.unit("shield").position = [1,3]
	support.unit("shield").ap = 3
	support.unit("vampire").position = [0,0]
	support_action = policy.choose_action(support.get_observation(),support.enumerate_legal_actions("shield"))
	check(support_action.kind == "MOVE","guard plans toward allies beyond immediate neighboring step")
	replay_source.execute_action({"kind":"END_TURN"})
	replay_source.execute_action({"actor_id":"spear_a","kind":"END_UNIT"})
	replay_source.execute_action({"actor_id":"spear_b","kind":"END_UNIT"})
	replay_source.execute_action({"actor_id":"shield","kind":"GUARD"})
	replay_source.execute_action({"actor_id":"shield","kind":"END_UNIT"})
	var replay = Rules.new(7,2)
	for action_item in replay_source.history:
		replay.execute_action(action_item)
	check(JSON.stringify(replay.get_observation()) == JSON.stringify(replay_source.get_observation()),"guard state deterministic JSON replay")
	print("GUARD RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
