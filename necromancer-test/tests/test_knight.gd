extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Charge = preload("res://scripts/core/ChargeRules.gd")
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
	e.unit("vampire").position = [0,0]
	e.unit("zombie_a").position = [0,1]
	e.unit("spear_a").position = [15,0]
	e.unit("spear_b").position = [16,0]
	return e
func finish_humans(e):
	var count = 0
	while e.faction=="human" and count<10:
		e.execute_action({"actor_id":e.active_human(),"kind":"END_UNIT"})
		count += 1
func _init():
	var e = fixture()
	# All six axial rays use the same blocking and range rules.
	for direction in Hex.DIRECTIONS:
		var ray = fixture()
		ray.unit("undead_knight").position = [5,4]
		for u in ray.units:
			if u.id!="undead_knight":
				u.alive = false
		var ray_paths = Charge.paths(ray.unit("undead_knight"),ray.board_data(),ray.units,3)
		check(ray_paths.has(Vector2i(5,4)+direction*3),"straight charge supported in each of six directions")
	var action = {"actor_id":"undead_knight","kind":"CHARGE","target_cell":[7,4]}
	for distance in range(0,7):
		var request = {"actor_id":"undead_knight","kind":"CHARGE","target_cell":[4+distance,4]}
		check(e.validate_action(request).valid==(distance==3),"only exact three-cell charge accepted")
	for direction in Hex.DIRECTIONS:
		var start = Vector2i(5,4)
		var endpoint = start+direction*2
		for adjacent in Hex.DIRECTIONS:
			var forward = (Hex.center(endpoint+adjacent)-Hex.center(endpoint)).dot(Hex.center(endpoint)-Hex.center(start))>0
			check(Charge.target_in_direction(start,endpoint,endpoint+adjacent)==forward,"front three neighbors allowed for each charge direction")
	# A rear enemy does not prevent charging, but cannot be struck on arrival.
	e.unit("knight").position = [6,5]
	e.execute_action(action)
	check(e.domination==15 and e.unit("undead_knight").position==[7,4] and e.unit("knight").hp==20,"charge without forward target ends after movement")
	e = fixture()
	check(e.validate_action(action).valid,"exact three-cell charge legal")
	var events = e.execute_action(action)
	check(e.domination==15 and e.unit("undead_knight").position==[7,4],"charge only costs five domination")
	check(events.filter(func(v): return v.type=="move" and v.get("charge",false )).size()==3,"charge emits every movement step")
	check(e.unit("knight").hp==15 and e.unit("knight").position==[9,4],"automatic charge damage and push")
	check(not events.any(func(v): return v.type=="reaction"),"charge never triggers reactions")
	e.domination = 4
	check(not e.enumerate_legal_actions("undead_knight").any(func(a): return a.kind=="CHARGE"),"insufficient resource cannot charge")
	e = fixture()
	var paths = Charge.paths(e.unit("undead_knight"),e.board_data(),e.units,3)
	check(not paths.has(Vector2i(2,5)) and not paths.has(Vector2i(8,4)),"no bent or over-range charge")
	e.obstacles["7,4"] = true
	check(not e.validate_action(action).valid and e.domination==20,"obstacle blocks full charge")
	e.obstacles = {}
	e.heights["7,4"] = 2
	check(not e.validate_action(action).valid,"two-level cliff blocks charge")
	e.heights["7,4"] = 1
	check(e.validate_action(action).valid,"one-level terrain can be crossed")
	e.unit("vampire").position = [5,4]
	check(not e.validate_action(action).valid,"friendly unit blocks charge")
	e.unit("vampire").position = [0,0]
	e.unit("spear_a").position = [5,4]
	check(not e.validate_action(action).valid,"enemy unit blocks charge")
	e = fixture()
	e.unit("spear_a").position = [4,3]
	events = e.execute_action(action)
	check(not events.any(func(v): return v.type=="reaction") and e.unit("spear_a").reaction_ready,"cross enemy zone without spending reaction")
	# Human AP and AI can use the charge from range, twice if resource permits.
	e = fixture()
	e.execute_action({"kind":"END_TURN"})
	check(e.unit("knight").ap==12,"human knight resets to twelve AP")
	var ai = AI.new()
	var chosen = ai.choose_action(e.get_observation(),e.enumerate_legal_actions("knight"))
	check(chosen.kind=="CHARGE" and e.validate_action(chosen).valid,"AI uses legal charge")
	e.execute_action(chosen)
	check(e.unit("knight").ap==7,"human charge costs five AP")
	# Advantage gate and stunned human skips exactly its next faction phase.
	e = fixture()
	e.unit("undead_knight").position = [7,4]
	var stomp = {"actor_id":"undead_knight","kind":"WAR_STOMP","target_unit_id":"knight"}
	check(not e.validate_action(stomp).valid,"flat duel cannot stomp without advantage")
	e.heights["9,4"] = 1
	check(e.validate_action(stomp).valid,"higher knight can stomp")
	events = e.execute_action(stomp)
	check(not e.unit("knight").stunned and e.unit("knight").hp==12,"stomp damage without stun")
	e.apply_stun(e.unit("knight"))
	e.execute_action({"kind":"END_TURN"})
	check(e.unit("knight").stun_skip_active and e.enumerate_legal_actions("knight").size()==1 and e.enumerate_legal_actions("knight")[0].kind=="END_UNIT","human cannot act while stunned")
	e.apply_stun(e.unit("knight"))
	check(e.unit("knight").stun_skip_active,"repeat stun does not restart timer")
	finish_humans(e)
	check(not e.unit("knight").stunned,"stun expires after skipped human phase")
	# Human stomp on undead, with same nonstacking recovery.
	e = fixture()
	e.unit("undead_knight").position = [7,4]
	e.heights["10,4"] = 1
	e.execute_action({"kind":"END_TURN"})
	stomp = {"actor_id":"knight","kind":"WAR_STOMP","target_unit_id":"undead_knight"}
	check(e.validate_action(stomp).valid,"human stomp legal")

	e.execute_action(stomp)
	e.apply_stun(e.unit("undead_knight"))
	finish_humans(e)
	check(e.unit("undead_knight").stunned and e.get_reachable_cells("undead_knight").is_empty(),"undead stunned movement disabled")
	check(e.enumerate_legal_actions("undead_knight").all(func(a): return a.kind=="END_TURN"),"undead all actions disabled")
	check(e.get_zone_controllers(Vector2i(8,4),"human").is_empty(),"stunned knight cannot react")
	e.apply_stun(e.unit("undead_knight"))
	e.execute_action({"kind":"END_TURN"})
	check(not e.unit("undead_knight").stunned,"undead recovers after skipped turn")
	# Lethal stomp does not leave a status on a dead target.
	e = fixture()
	e.unit("undead_knight").position = [7,4]
	e.heights["9,4"] = 1
	e.unit("knight").hp = 1
	e.execute_action({"actor_id":"undead_knight","kind":"WAR_STOMP","target_unit_id":"knight"})
	check(not e.unit("knight").alive and not e.unit("knight").stunned,"lethal stomp does not stun dead unit")
	print("KNIGHT RESULT: %d failures" % failures)
	quit(1 if failures else 0)
