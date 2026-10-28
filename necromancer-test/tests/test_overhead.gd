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
	for id in ["vampire","zombie_a","shield","archer"]:
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
				if id=="vampire":
					check(damage==6,"kiss deals fixed four damage")
				elif id=="archer":
					check(damage==9,"vital shot deals five damage")
				elif id=="shield":
					check(damage==1 and e.unit(target).stunned,"strong shield damage and stun")
				elif id=="zombie_a":
					var hits = events.filter(func(v): return v.type=="damage")
					check(hits.size()==3 and hits.all(func(v): return v.amount in [2,3,4]),"frenzy deals three independent small hits")
				else:
					check(damage>=d.damage_min*2 and damage<=d.damage_max*2 and damage%2==0,"double damage "+id)
				check(e.resource(e.unit(id))==resource-int(d.get("advantage_cost",d.cost)),"ordinary cost "+id)
			else:
				check(e.resource(e.unit(id))==resource and e.unit(target).hp==100,"invalid action unchanged")
	var e = fixture("spear_a",1)
	for initial_hp in [8,13,15]:
		var kiss = fixture("vampire",1)
		kiss.unit("vampire").hp = initial_hp
		kiss.execute_action({"actor_id":"vampire","kind":"OVERHEAD_STRIKE","target_unit_id":"spear_a"})
		check(kiss.unit("vampire").hp==mini(20,initial_hp+6),"kiss restores four capped at maximum")
		check(kiss.domination==12,"kiss retains eight domination cost")
	var frenzy = fixture("zombie_a",1)
	frenzy.unit("spear_a").hp = 1
	var frenzy_events = frenzy.execute_action({"actor_id":"zombie_a","kind":"OVERHEAD_STRIKE","target_unit_id":"spear_a"})
	check(frenzy_events.filter(func(v): return v.type=="damage").size()==1,"frenzy stops when target dies")
	check(frenzy.domination==14,"frenzy spends four domination once")
	e.unit("zombie_a").position = [2,0]
	e.heights["2,0"] = 1
	var events = e.execute_action({"actor_id":"spear_a","kind":"OVERHEAD_STRIKE","target_unit_id":"vampire"})
	check(e.unit("zombie_a").hp==10 and e.unit("vampire").hp==100 and e.unit("spear_a").ap==6,"removed spear overhead rejected without side effects")
	e = fixture("archer",1)
	e.unit("shield").position = [0,1]
	var policy = Policy.new()
	var action = policy.choose_action(e.get_observation(),e.enumerate_legal_actions("archer"))
	check(action.kind=="OVERHEAD_STRIKE","AI prefers double damage at same cost")
	events = e.execute_action(action)
	var damage = 100-e.unit("vampire").hp
	check(damage==10,"human bonus adds to vital shot without doubling")
	print("OVERHEAD RESULT: %d failures" % failures)
	quit(1 if failures else 0)
