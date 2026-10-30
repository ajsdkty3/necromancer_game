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
	e.unit("vampire").position = [8,3]
	e.unit("zombie_a").position = [7,5]
	e.unit("spear_a").position = [15,0]
	e.unit("spear_b").position = [16,0]
	return e
func _init():
	var e = fixture()
	check(e.unit("knight").hp==16 and e.unit("undead_knight").hp==8,"new cavalry health")
	check(e.definitions.undead_knight.role=="仆役" and e.definitions.vampire.role=="冠军","undead roles")
	for direction in Hex.DIRECTIONS:
		var start = Vector2i(5,4)
		var endpoint = start+direction*3
		for adjacent in Hex.DIRECTIONS:
			check(Charge.target_in_direction(start,endpoint,endpoint+adjacent)==(adjacent==direction),"only forward target in all six orientations")
	var action = {"actor_id":"undead_knight","kind":"CHARGE","target_cell":[7,4]}
	e.domination=5
	check(not e.validate_action(action).valid,"five domination insufficient")
	e.domination=20
	var events = e.execute_action(action)
	check(e.domination==14 and e.unit("knight").hp==12 and e.unit("knight").position==[9,4],"six cost four damage and push")
	check(e.unit("vampire").hp==20 and e.unit("zombie_a").hp==10,"side cells remain untouched")
	check(events.filter(func(v): return v.type=="damage").size()==1,"single damage target")
	check(not events.any(func(v): return v.type=="reaction"),"charge and push do not trigger reactions")
	e=fixture()
	e.unit("knight").position=[15,3]
	e.unit("vampire").position=[8,4]
	e.execute_action(action)
	check(e.unit("vampire").hp==16 and e.unit("vampire").position==[9,4],"friendly forward target takes damage and push")
	e=fixture()
	e.obstacles["11,4"]=true
	e.execute_action(action)
	check(e.unit("knight").hp==12 and e.unit("knight").position==[8,4],"blocked push still damages")
	e=fixture()
	e.heights={"9,4":1,"10,4":1}
	events=e.execute_action(action)
	var hits=events.filter(func(v): return v.type=="damage")
	check(hits.size()==2 and hits[0].amount==4 and hits[1].amount==2,"fall remains separate")
	e=fixture()
	e.attack(e.unit("undead_knight"),e.unit("knight"),true)
	check(e.unit("knight").hp==11 and e.unit("knight").position==[8,4],"reaction remains five and does not push")
	e=fixture()
	e.unit("vampire").position=[0,0]
	e.unit("zombie_a").position=[0,1]
	e.execute_action({"kind":"END_TURN"})
	var chosen=AI.new().choose_action(e.get_observation(),e.enumerate_legal_actions("knight"))
	check(chosen.kind=="CHARGE","human AI chooses forward enemy charge")
	e.execute_action(chosen)
	check(e.unit("knight").ap==6 and e.unit("undead_knight").hp==4,"human six AP charge and four damage")
	print("CAVALRY RESULT: %d failures" % failures)
	quit(1 if failures else 0)
