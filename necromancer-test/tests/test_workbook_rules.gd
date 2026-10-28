extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func fixture(archetype: String):
	var e = Rules.new(42,11)
	for u in e.units:
		u.alive = u.id in ["vampire","knight","spear_a"]
	e.unit("vampire").archetype = archetype
	e.unit("vampire").position = [4,4]
	e.unit("knight").position = [5,4]
	e.unit("spear_a").position = [15,0]
	e.heights = {"6,4":1}
	e.obstacles = {}
	return e
func action(kind: String):
	return {"actor_id":"vampire","kind":kind,"target_unit_id":"knight"}
func _init():
	for archetype in ["vampire","zombie","undead_archer","undead_shieldman"]:
		var e = fixture(archetype)
		var expected_cost = 8 if archetype=="vampire" else 6
		e.domination = expected_cost-1
		check(not e.validate_action(action("OVERHEAD_STRIKE")).valid,"independent special cost "+archetype)
		e.domination = 20
		e.unit("vampire").hp = 10
		var events = e.execute_action(action("OVERHEAD_STRIKE"))
		var hits = events.filter(func(v): return v.type=="damage")
		check(e.domination==20-expected_cost,"cost charged once "+archetype)
		if archetype=="zombie":
			check(hits.size()==3 and hits.all(func(v): return v.amount in [2,3,4]),"frenzy three rolls 2-4")
		else:
			check(hits.size()==1 and hits[0].amount=={"vampire":6,"undead_archer":9,"undead_shieldman":1}[archetype],"fixed advantage damage "+archetype)
		if archetype=="vampire":
			check(e.unit("vampire").hp==16,"kiss heals six")
		if archetype=="undead_shieldman":
			check(e.unit("knight").stunned and e.unit("knight").position==[5,4],"strong shield stuns without ordinary shove")
	var e = fixture("undead_shieldman")
	var events = e.execute_action(action("SHIELD_BASH"))
	check(e.unit("knight").position==[6,4] and e.unit("knight").hp==19,"ordinary shield hits one and pushes")
	e = fixture("undead_shieldman")
	e.attack(e.unit("vampire"),e.unit("knight"),true)
	check(e.unit("knight").position==[5,4] and e.unit("knight").hp==19,"reaction only copies damage without push")
	for blocked in [false,true]:
		e = fixture("undead_knight")
		if blocked:
			e.obstacles["8,4"] = true
		events = e.execute_action(action("WAR_STOMP"))
		check(e.unit("knight").hp==12 and not e.unit("knight").stunned,"stomp eight damage no stun")
		check(e.unit("vampire").position==([4,4] if blocked else [5,4]),"stomp follows only successful push")
		check(not events.any(func(v): return v.type=="reaction"),"stomp forced movement no reaction")
	e = fixture("undead_knight")
	e.unit("knight").hp = 1
	e.execute_action(action("WAR_STOMP"))
	check(e.unit("vampire").position==[5,4],"stomp follows killed target")
	e = fixture("undead_knight")
	e.unit("knight").team = "undead"
	check(e.validate_action(action("WAR_STOMP")).valid,"stomp can target friendly unit with advantage")
	e.execute_action(action("WAR_STOMP"))
	check(e.unit("knight").hp==12,"friendly stomp damage")
	check(Terrain.attack_height_allowed({"1,0":2},Vector2i(0,0),Vector2i(1,0),"SHOOT"),"bow shoots up two")
	check(not Terrain.attack_height_allowed({"1,0":3},Vector2i(0,0),Vector2i(1,0),"SHOOT"),"bow cannot shoot up three")
	check(Terrain.attack_height_allowed({"0,0":5},Vector2i(0,0),Vector2i(1,0),"SHOOT"),"bow shoots down unlimited")
	for archetype in ["archer","shieldman"]:
		e = fixture("vampire")
		var human = e.unit("knight")
		human.archetype = archetype
		e.faction = "human"
		e.human_index = e.humans().find(human)
		e.heights = {"7,4":1}
		human.ap = 5
		var special = {"actor_id":"knight","kind":"OVERHEAD_STRIKE","target_unit_id":"vampire"}
		check(not e.validate_action(special).valid,"human special needs six AP "+archetype)
		human.ap = 6
		events = e.execute_action(special)
		check(human.ap==0 and events.any(func(v): return v.type=="damage" and v.amount==(9 if archetype=="archer" else 1)),"human counterpart special damage and cost "+archetype)
		check(e.unit("vampire").stunned==(archetype=="shieldman"),"only strong shield stuns")
	e = fixture("zombie")
	e.unit("spear_a").position = [6,4]
	e.unit("spear_a").archetype = "shieldman"
	e.unit("spear_a").guarding = true
	e.unit("spear_a").hp = 1
	events = e.execute_action(action("OVERHEAD_STRIKE"))
	check(events.filter(func(v): return v.type=="damage").size()==3 and not e.unit("spear_a").alive and e.unit("knight").hp<20,"frenzy reevaluates guardian after each hit")
	print("WORKBOOK RULES RESULT: %d failures" % failures)
	quit(1 if failures else 0)
