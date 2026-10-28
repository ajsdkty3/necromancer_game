extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Knight = preload("res://scripts/ai/KnightPolicy.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const AI = preload("res://scripts/ai/AIController.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func _init():
	var e = Rules.new(42,11)
	e.unit("knight").position = [5,4]
	e.unit("vampire").position = [6,4]
	e.unit("undead_knight").position = [0,0]
	e.unit("zombie_a").position = [0,1]
	e.unit("spear_a").position = [15,0]
	e.unit("spear_b").position = [16,0]
	e.execute_action({"kind":"END_TURN"})
	var actor = e.unit("knight")
	var legal = e.enumerate_legal_actions("knight")
	var choice = AI.new().choose_action(e.get_observation(),legal)
	check(choice.kind=="CHARGE","knight charges out of active enemy zone instead of walking")
	if choice.kind=="CHARGE":
		check(not Knight.reaction_threat(e.get_observation(),actor,Hex.decode(choice.target_cell)),"escape ends outside active enemy zones")
		var hp = actor.hp
		var events = e.execute_action(choice)
		check(actor.hp==hp and not events.any(func(v): return v.type=="reaction"),"escape does not trigger opportunity attack")
		check(actor.ap==7,"escape spends five AP")
	actor.position = [5,4]
	e.unit("vampire").reaction_ready = false
	check(Knight.choose_escape_charge(e.get_observation(),e.enumerate_legal_actions("knight"),actor).is_empty(),"spent reaction does not request escape")
	e.unit("vampire").reaction_ready = true
	actor.ap = 4
	check(Knight.choose_escape_charge(e.get_observation(),e.enumerate_legal_actions("knight"),actor).is_empty(),"cannot escape charge without sufficient AP")
	actor.ap = 12
	for direction in Hex.DIRECTIONS:
		var offset = Hex.to_offset(Hex.decode(actor.position)+direction)
		e.obstacles["%d,%d" % [offset.x,offset.y]] = true
	check(Knight.choose_escape_charge(e.get_observation(),e.enumerate_legal_actions("knight"),actor).is_empty(),"blocked rays never selected for escape")
	print("KNIGHT ESCAPE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
