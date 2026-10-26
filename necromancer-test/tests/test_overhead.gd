extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Policy = preload("res://scripts/ai/HeuristicPolicy.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr(message)
func fixture(id: String, height: int):
	var e = Rules.new(42,3)
	e.obstacles = {}
	e.heights = {"0,0":height}
	for u in e.units:
		u.position = [15,0]
	e.unit(id).position = [0,0]
	var target = "vampire" if e.unit(id).team=="human" else "spear_a"
	e.unit(target).position = [1,0]
	e.unit(target).hp = 100
	e.faction = e.unit(id).team
	if e.faction=="human":
		e.human_index = e.humans().find(e.unit(id))
	return e
func _init():
	for id in ["vampire","zombie_a","spear_a","shield","archer"]:
		for height in [0,1,2]:
			var e = fixture(id,height)
			var target = "vampire" if e.unit(id).team=="human" else "spear_a"
			var d = e.definitions[e.unit(id).archetype]
			var action = {"actor_id":id,"kind":"OVERHEAD_STRIKE","target_unit_id":target}
			var allowed = height==1 or (height==2 and id=="archer")
			check(e.validate_action(action).valid==allowed,"height eligibility "+id)
			var resource = e.resource(e.unit(id))
			var events = e.execute_action(action)
			if allowed:
				var damage = 100-e.unit(target).hp
				check(damage>=d.damage_min*2 and damage<=d.damage_max*2 and damage%2==0,"double damage "+id)
				check(e.resource(e.unit(id))==resource-int(d.cost),"ordinary cost "+id)
			else:
				check(e.resource(e.unit(id))==resource and e.unit(target).hp==100,"invalid action unchanged")
	var e = fixture("spear_a",1)
	e.unit("zombie_a").position = [2,0]
	e.heights["2,0"] = 1
	var events = e.execute_action({"actor_id":"spear_a","kind":"OVERHEAD_STRIKE","target_unit_id":"vampire"})
	check(e.unit("zombie_a").hp==8,"spear secondary same-height target excluded")
	e = fixture("archer",1)
	e.unit("shield").position = [0,1]
	var policy = Policy.new()
	var action = policy.choose_action(e.get_observation(),e.enumerate_legal_actions("archer"))
	check(action.kind=="OVERHEAD_STRIKE","AI prefers double damage at same cost")
	events = e.execute_action(action)
	var damage = 100-e.unit("vampire").hp
	check(damage in [4,6,8],"human bonus included before doubling")
	print("OVERHEAD RESULT: %d failures" % failures)
	quit(1 if failures else 0)
