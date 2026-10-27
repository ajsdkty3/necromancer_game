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
	e.heights = {"0,0":1}
	e.obstacles = {}
	for u in e.units:
		u.position = [15,0]
	e.unit("spear_a").position = [0,0]
	e.unit("vampire").position = [1,0]
	e.faction = "human"
	return e
func shove(e):
	return e.execute_action({"actor_id":"spear_a","kind":"KNOCKBACK","target_unit_id":"vampire"})
func _init():
	var e = fixture()
	var events = shove(e)
	check(e.unit("vampire").position==[2,0] and e.unit("vampire").hp==13 and e.unit("spear_a").ap==3,"single target damage displacement cost")
	check(not events.any(func(v): return v.type=="reaction"),"forced move causes no reactions")
	for block in ["rock","ally","enemy","higher","edge"]:
		e = fixture()
		match block:
			"rock": e.obstacles["2,0"] = true
			"ally": e.unit("spear_b").position = [2,0]
			"enemy": e.unit("zombie_a").position = [2,0]
			"higher": e.heights["2,0"] = 1
			"edge":
				e.heights = {"18,0":1}
				e.unit("spear_a").position = [18,0]
				e.unit("vampire").position = [19,0]
		var before = e.unit("vampire").position.duplicate()
		shove(e)
		check(e.unit("vampire").position==before and e.unit("vampire").hp==13,"blocked still does two damage: "+block)
		check(e.unit("zombie_a").hp==8 and e.unit("spear_b").hp==10,"shove never damages units behind target: "+block)
	e = fixture()
	e.heights = {"0,0":4,"1,0":3,"2,0":1}
	events = shove(e)
	var hits = events.filter(func(v): return v.type=="damage")
	check(hits.size()==2 and hits[0].amount==2 and hits[1].amount==4 and e.unit("vampire").hp==9,"fall damage separate by height difference")
	e = fixture()
	e.heights = {"0,0":2,"1,0":1}
	e.unit("spear_b").position = [0,1]
	events = shove(e)
	hits = events.filter(func(v): return v.type=="damage")
	check(hits.size()==2 and hits[0].amount==3 and hits[1].amount==2,"human trait applies to shove only, not fall")
	e = fixture()
	e.unit("vampire").position = [1,0]
	e.heights = {"1,0":2}
	check(not e.validate_action({"actor_id":"spear_a","kind":"KNOCKBACK","target_unit_id":"vampire"}).valid,"melee height restriction preserved")
	e = fixture()
	e.unit("vampire").hp = 2
	events = shove(e)
	check(not e.unit("vampire").alive and not events.any(func(v): return v.type=="move"),"lethal initial hit stops displacement")
	e = fixture()
	var actions = e.enumerate_legal_actions("spear_a")
	check(not actions.any(func(a): return a.kind=="OVERHEAD_STRIKE"),"spear special replaces overhead")
	check(Policy.new().choose_action(e.get_observation(),actions).kind=="KNOCKBACK","AI always prefers available shove")
	e.unit("vampire").position = [1,1]
	events = shove(e)
	check(e.unit("vampire").position==[1,1] and e.unit("spear_a").ap==6,"distance two off-axis target rejected")
	e.unit("vampire").position = [2,0]
	check(not e.validate_action({"actor_id":"spear_a","kind":"KNOCKBACK","target_unit_id":"vampire"}).valid,"distance two straight target rejected")
	check(e.validate_action({"actor_id":"spear_a","kind":"SPEAR_THRUST","target_unit_id":"vampire"}).valid,"ordinary spear range remains two")
	for target_height in [0,1,2,3]:
		e = fixture()
		e.heights = {"0,0":2,"1,0":target_height}
		var action = {"actor_id":"spear_a","kind":"KNOCKBACK","target_unit_id":"vampire"}
		check(e.validate_action(action).valid==(target_height==1),"shove requires exactly one level advantage")
		if target_height!=1:
			e.execute_action(action)
			check(e.unit("spear_a").ap==6 and e.unit("vampire").hp==15,"invalid height cannot spend AP or deal damage")
	print("KNOCKBACK RESULT: %d failures" % failures)
	quit(1 if failures else 0)
