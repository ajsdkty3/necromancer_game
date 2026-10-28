extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Policy = preload("res://scripts/ai/AIController.gd")
var checks = 0
var failures = 0

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + label)

func arrange(placements: Dictionary):
	var e = Rules.new(42)
	# Hand-authored rule fixtures are independent of the demonstration map.
	e.obstacles = {}
	for u in e.units:
		u.alive = placements.has(u.id)
		if u.alive:
			u.position = placements[u.id]
	return e

func move(id: String, q: int, r: int) -> Dictionary:
	return {"actor_id":id,"kind":"MOVE","target_cell":[q,r]}

func count(events: Array, kind: String) -> int:
	return events.filter(func(event): return event.type == kind).size()

func _init():
	test_hex()
	test_resources()
	test_combat()
	test_reactions()
	test_pathfinding()
	test_ai_and_replay()
	test_full_battles()
	print("RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func test_hex():
	check(Hex.cells().size() == 200,"200 hexes")
	for cell in Hex.cells():
		var o = Hex.to_offset(cell)
		check(Hex.from_offset(o.x,o.y) == cell,"offset round trip")
		check(Hex.at_point(Hex.center(cell)) == cell,"pixel round trip")
		for direction in Hex.DIRECTIONS:
			check(Hex.distance(cell,cell+direction) == 1,"six neighbors")
	check(Hex.distance(Vector2i.ZERO,Vector2i(1,1)) == 2,"axial diagonal")

func test_resources():
	var e = Rules.new()
	check(e.domination == 20 and e.round_number == 1,"initial resources")
	for u in e.units:
		check(u.hp == e.definitions[u.archetype].hp,"initial hp")
		if u.team == "human":
			check(u.ap == 6,"initial ap")
	e.domination = 8
	e.execute_action({"kind":"END_TURN"})
	for id in ["spear_a","spear_b","archer"]:
		e.execute_action({"actor_id":id,"kind":"END_UNIT"})
	check(e.domination == 18 and e.round_number == 2,"carry over plus ten")
	for id in ["zombie_a","vampire"]:
		e = arrange({id:[0,0],"archer":[15,0]})
		e.execute_action(move(id,3,0))
		check(e.domination == 17,"movement costs")
	e = arrange({"zombie_a":[0,0],"archer":[15,0]})
	check(Vector2i(7,0) in e.get_reachable_cells("zombie_a"),"walk beyond six allowed")
	e.domination = 2
	check(not e.validate_action(move("zombie_a",3,0)).valid,"no partial move")
	check(e.unit("zombie_a").position == [0,0],"validation is read only")
	e = arrange({"vampire":[0,0],"spear_a":[1,0],"archer":[15,0]})
	check(not e.validate_action({"actor_id":"vampire","kind":"TELEPORT","target_cell":[7,0]}).valid,"teleport max six")
	check(not e.validate_action({"actor_id":"vampire","kind":"TELEPORT","target_cell":[1,0]}).valid,"teleport occupied")
	var events = e.execute_action({"actor_id":"vampire","kind":"TELEPORT","target_cell":[6,0]})
	check(e.domination == 14 and count(events,"reaction") == 0 and e.unit("vampire").position == [6,0],"teleport bypasses blockers and reactions")

func test_combat():
	var e = arrange({"spear_a":[3,3],"zombie_a":[4,3],"spear_b":[5,3],"archer":[15,0]})
	e.faction = "human"
	var events = e.execute_action({"actor_id":"spear_a","kind":"SPEAR_THRUST","target_unit_id":"zombie_a"})
	check(count(events,"damage") == 2 and e.unit("spear_b").hp < 14,"spear friendly fire")
	check(e.unit("spear_a").ap == 3,"spear costs three")
	e.execute_action({"actor_id":"spear_a","kind":"SPEAR_THRUST","target_unit_id":"zombie_a"})
	check(e.unit("spear_a").ap == 0,"repeat attacks")
	e = arrange({"spear_a":[3,3],"zombie_a":[4,4],"spear_b":[4,3]})
	e.faction = "human"
	events = e.execute_action({"actor_id":"spear_a","kind":"SPEAR_THRUST","target_unit_id":"zombie_a"})
	check(count(events,"damage") == 1 and e.unit("spear_b").hp == 14,"off-axis spear single target")
	e = arrange({"archer":[0,0],"spear_a":[1,0],"zombie_a":[3,0]})
	e.faction = "human"
	e.human_index = 2
	events = e.execute_action({"actor_id":"archer","kind":"SHOOT","target_unit_id":"zombie_a"})
	check(count(events,"damage") == 1 and e.unit("spear_a").hp == 14,"archer ignores intermediate unit")
	e = arrange({"vampire":[0,0],"zombie_a":[1,0],"archer":[15,0]})
	events = e.execute_action({"actor_id":"vampire","kind":"MELEE_ATTACK","target_unit_id":"zombie_a"})
	check(e.domination == 12 and e.unit("zombie_a").hp < 10,"explicit friendly attack")
	e = arrange({"vampire":[0,0],"archer":[1,0]})
	e.unit("archer").hp = 1
	events = e.execute_action({"actor_id":"vampire","kind":"MELEE_ATTACK","target_unit_id":"archer"})
	check(e.winner == "undead" and count(events,"victory") == 1,"immediate victory")
	check(not e.validate_action(move("vampire",0,1)).valid,"terminal actions rejected")
	e = arrange({"vampire":[0,0],"zombie_a":[1,0],"archer":[3,0]})
	e.apply_damage("archer","vampire",20,"test")
	check(not e.is_terminal(),"vampire death is not defeat")
	e.apply_damage("archer","zombie_a",10,"test")
	check(e.winner == "human","all undead dead")
	e = arrange({"spear_a":[0,0],"zombie_a":[1,0],"spear_b":[2,0]})
	e.faction = "human"
	e.unit("zombie_a").hp = 1
	e.execute_action({"actor_id":"spear_a","kind":"SPEAR_THRUST","target_unit_id":"zombie_a"})
	check(e.winner == "human" and e.unit("spear_b").hp == 14,"near first and stop remaining hits at victory")

func test_reactions():
	var e = arrange({"zombie_a":[0,0],"spear_a":[3,0]})
	var events = e.execute_action(move("zombie_a",2,0))
	check(count(events,"reaction") == 0,"enter zoc no reaction")
	events = e.execute_action(move("zombie_a",0,0))
	check(count(events,"reaction") == 1 and e.unit("spear_a").ap == 6,"leave zoc free reaction")
	e = arrange({"zombie_a":[3,3],"spear_a":[4,3],"spear_b":[3,4]})
	e.unit("zombie_a").hp = 100
	events = e.execute_action(move("zombie_a",2,3))
	check(count(events,"reaction") == 2,"multiple controllers")
	e = arrange({"zombie_a":[3,3],"spear_a":[4,3]})
	e.unit("zombie_a").hp = 100
	var expected_reactions = 1
	for destination in [[3,4],[3,3],[3,4]]:
		events = e.execute_action(move("zombie_a",destination[0],destination[1]))
		check(count(events,"reaction") == expected_reactions,"reaction only once before reset")
		expected_reactions = 0
	check(e.unit("spear_a").ap == 6,"reactions do not cost ap")
	check(e.get_observation().zones.spear_a.is_empty(),"spent reaction hides zone")
	e.unit("zombie_a").reaction_ready = false
	e.execute_action({"kind":"END_TURN"})
	check(e.unit("spear_a").reaction_ready and not e.unit("zombie_a").reaction_ready,"only humans reset at human turn start")
	e.execute_action({"actor_id":"spear_a","kind":"END_UNIT"})
	check(e.unit("zombie_a").reaction_ready,"undead reset at undead turn start")
	e = arrange({"zombie_a":[4,4],"spear_a":[3,3],"zombie_b":[4,3]})
	events = e.execute_action(move("zombie_a",5,4))
	check(count(events,"damage") == 0 and e.unit("zombie_b").hp == 10,"distance two off-axis cell outside reaction range")
	e = arrange({"zombie_a":[0,0],"spear_a":[2,1]})
	e.unit("zombie_a").hp = 1
	events = e.execute_action(move("zombie_a",3,0))
	check(e.unit("zombie_a").position == [2,0] and not e.unit("zombie_a").alive,"death at old cell mid path")
	check(e.domination == 20 and count(events,"move") == 2 and count(events,"resource") == 3,"only completed steps charged then death restores domination to cap")
	check(e.occupant(Vector2i(2,0)).is_empty(),"death clears occupancy")
	e = arrange({"zombie_a":[1,0],"spear_a":[0,0],"spear_b":[2,0],"vampire":[10,0]})
	e.unit("spear_b").hp = 1
	e.unit("zombie_a").hp = 100
	events = e.execute_action(move("zombie_a",1,1))
	check(count(events,"reaction") == 2 and e.unit("spear_b").alive and e.unit("spear_b").hp == 1,"reaction skips friendly unit and both controllers still attack")
	check(count(events,"damage") == 2,"no friendly damage event from reactions")
	e = arrange({"spear_a":[0,0],"archer":[1,0],"zombie_a":[2,0]})
	events = e.execute_action(move("zombie_a",2,1))
	check(count(events,"damage") == 0 and e.unit("archer").hp == 10 and e.unit("zombie_a").hp == 10,"far enemy outside one-cell reaction range")
	e = arrange({"spear_a":[0,0],"zombie_a":[1,0],"zombie_b":[2,0]})
	events = e.execute_action(move("zombie_a",1,1))
	check(count(events,"damage") == 1 and e.unit("zombie_a").hp < 10 and e.unit("zombie_b").hp == 10,"reaction hits only near triggering enemy")
	e = arrange({"spear_a":[0,0],"zombie_a":[1,0],"zombie_b":[2,0]})
	events = e.execute_action(move("zombie_b",2,1))
	check(count(events,"damage") == 0 and e.unit("zombie_a").hp == 10 and e.unit("zombie_b").hp == 10,"moving far enemy does not trigger reaction on near enemy")

func test_pathfinding():
	var e = arrange({"zombie_a":[0,0],"zombie_b":[1,0],"archer":[15,0]})
	var path = e.find_path("zombie_a",Vector2i(2,0))
	check(path.size() == 3 and not Vector2i(1,0) in path,"cannot cross friends")
	check(not Vector2i(1,0) in e.get_reachable_cells("zombie_a"),"occupied destination not highlighted")
	e = arrange({"zombie_a":[3,3],"spear_a":[5,2]})
	path = e.find_path("zombie_a",Vector2i(4,4))
	check(path.size() == 2 and path[0] == Vector2i(3,4),"equal distance safer route")
	var observation = e.get_observation()
	observation.units[0].hp = 999
	check(e.units[0].hp != 999,"observation cannot mutate engine")
	check(JSON.parse_string(JSON.stringify(e.get_observation())) is Dictionary,"state JSON serializable")

func test_ai_and_replay():
	var e = Rules.new(7)
	var policy = Policy.new()
	var calls = 0
	e.execute_action({"kind":"END_TURN"})
	while e.faction == "human" and not e.is_terminal() and calls < 60:
		var choices = e.enumerate_legal_actions(e.active_human())
		var action = policy.choose_action(e.get_observation(),choices)
		check(e.validate_action(action).valid,"AI returns legal action")
		e.execute_action(action)
		calls += 1
	check(e.faction == "undead" and calls < 60,"AI turn terminates")
	var replay = Rules.new(7)
	for action in e.history:
		replay.execute_action(action)
	check(JSON.stringify(e.get_observation()) == JSON.stringify(replay.get_observation()),"seed plus history deterministic replay")
	var a = arrange({"spear_a":[3,3],"zombie_a":[4,3],"spear_b":[5,3]})
	a.faction = "human"
	var selected = policy.choose_action(a.get_observation(),a.enumerate_legal_actions("spear_a"))
	check(selected.kind != "SPEAR_THRUST","AI penalizes friendly fire")
	check(selected.kind == "MOVE","without height advantage spear repositions to avoid friendly fire")
	a.execute_action(selected)
	var adjusted = policy.choose_action(a.get_observation(),a.enumerate_legal_actions("spear_a"))
	check(adjusted.kind == "SPEAR_THRUST","ordinary attack after safe reposition")
	check(a.unit("spear_b").hp==14,"blocked shove does not damage blocking friend")
	# Ally stands between the rear spearman and the enemy, matching the reported case.
	a = arrange({"spear_a":[3,3],"spear_b":[4,3],"vampire":[5,3]})
	a.faction = "human"
	a.unit("spear_a").ap = 3
	check(policy.choose_action(a.get_observation(),a.enumerate_legal_actions("spear_a")).kind == "END_UNIT","no height special or budget to reposition")
	a.unit("spear_a").ap = 6
	selected = policy.choose_action(a.get_observation(),a.enumerate_legal_actions("spear_a"))
	check(selected.kind == "MOVE","rear spearman repositions without height advantage")
	a.execute_action(selected)
	adjusted = policy.choose_action(a.get_observation(),a.enumerate_legal_actions("spear_a"))
	check(a.validate_action(adjusted).valid and a.unit("spear_b").hp==14,"reassess after shove without hurting friend")
	for actor_id in ["archer","spear_a"]:
		var targeting = arrange({actor_id:[3,3],"vampire":[4,3],"zombie_a":[3,4]})
		targeting.faction = "human"
		targeting.human_index = 2 if actor_id == "archer" else 0
		targeting.unit("vampire").hp = 6
		targeting.unit("zombie_a").hp = 5
		var choices = targeting.enumerate_legal_actions(actor_id)
		for reverse_order in [false,true]:
			if reverse_order:
				choices.reverse()
			var choice = policy.choose_action(targeting.get_observation(),choices)
			check(choice.get("target_unit_id","") == "zombie_a","single hit prefers 5/8 over 6/15 regardless of action order")
		targeting.unit("vampire").hp = 4
		var updated = policy.choose_action(targeting.get_observation(),targeting.enumerate_legal_actions(actor_id))
		check(updated.get("target_unit_id","") == "vampire","single hit reevaluates current HP")
	var area = arrange({"spear_a":[3,3],"vampire":[4,3],"zombie_a":[5,3],"zombie_b":[3,4]})
	area.faction = "human"
	area.unit("zombie_b").hp = 100
	var area_choice = policy.choose_action(area.get_observation(),area.enumerate_legal_actions("spear_a"))
	check(area_choice.kind=="SPEAR_THRUST" and area_choice.target_unit_id in ["vampire","zombie_a"],"flat ground uses ordinary area attack")
	for spec in [["archer",5,4,"SHOOT"],["spear_a",2,3,"SPEAR_THRUST"]]:
		var actor_id: String = spec[0]
		var radius: int = spec[1]
		var cost: int = spec[2]
		var battle = arrange({actor_id:[0,0],"zombie_a":[radius+1,0]})
		# Exercise the ordinary-attack fallback with the special unavailable.
		battle.definitions.spearman.erase("knockback_cost")
		battle.faction = "human"
		battle.human_index = 2 if actor_id == "archer" else 0
		var first = policy.choose_action(battle.get_observation(),battle.enumerate_legal_actions(actor_id))
		check(first.kind == "MOVE","AI approaches from outside attack range")
		battle.execute_action(first)
		var stopping_position = battle.unit(actor_id).position.duplicate()
		check(Hex.distance(battle.pos(battle.unit(actor_id)),battle.pos(battle.unit("zombie_a"))) == radius,"AI reaches outer edge of attack range")
		var next = policy.choose_action(battle.get_observation(),battle.enumerate_legal_actions(actor_id))
		check(next.kind == spec[3],"AI attacks at range instead of moving closer")
		battle.execute_action(next)
		battle.unit(actor_id).ap = cost-1
		next = policy.choose_action(battle.get_observation(),battle.enumerate_legal_actions(actor_id))
		check(next.kind == "END_UNIT","AI holds range with insufficient attack AP")
		battle.execute_action(next)
		check(battle.unit(actor_id).position == stopping_position,"AI stays at firing position")

func test_full_battles():
	for configuration in [[1,1],[7,1],[42,1],[1,2],[7,2],[1,3],[1,4],[1,5],[1,6]]:
		var seed_value: int = configuration[0]
		var level: int = configuration[1]
		var e = Rules.new(seed_value,level)
		var policy = Policy.new()
		var decisions = 0
		while not e.is_terminal() and decisions < 600:
			var action = {}
			if e.faction == "human":
				action = policy.choose_action(e.get_observation(),e.enumerate_legal_actions(e.active_human()))
			else:
				var best_score = -1000.0
				for u in e.units:
					if not u.alive or u.team != "undead":
						continue
					var nearest = 999
					for enemy in e.humans():
						if enemy.alive:
							nearest = mini(nearest,Hex.distance(e.pos(u),e.pos(enemy)))
					for candidate in e.enumerate_legal_actions(u.id):
						var score = -1000.0
						if candidate.has("target_unit_id") and e.unit(candidate.target_unit_id).team == "human":
							score = 100.0
						elif candidate.kind in ["MOVE","TELEPORT"]:
							var destination = Hex.decode(candidate.target_cell)
							var remaining = 999
							for enemy in e.humans():
								if enemy.alive:
									remaining = mini(remaining,Hex.distance(destination,e.pos(enemy)))
							score = float(nearest-remaining)
						if score > best_score and score > 0:
							best_score = score
							action = candidate
				if action.is_empty():
					action = {"kind":"END_TURN"}
			check(e.validate_action(action).valid,"full battle legal decision")
			e.execute_action(action)
			for u in e.units:
				check(u.hp >= 0 and u.ap >= 0,"nonnegative unit resources")
			check(e.domination >= 0 and e.domination <= 20,"domination invariant")
			decisions += 1
		check(e.is_terminal(),"full battle reaches result")
		var replay = Rules.new(seed_value,level)
		for action in e.history:
			replay.execute_action(action)
		check(JSON.stringify(e.get_observation()) == JSON.stringify(replay.get_observation()),"combat replay including damage and deaths")
		print("Battle level %d seed %d: %s, %d decisions, round %d" % [level,seed_value,e.winner,decisions,e.round_number])
