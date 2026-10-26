extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Board = preload("res://scripts/ui/HexBoardView.gd")
const Policy = preload("res://scripts/ai/HeuristicPolicy.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr(message)
func _init():
	var e = Rules.new(42,7)
	check(e.domination==60 and e.domination_cap==60 and e.humans().all(func(u): return u.ap==6),"level seven has sixty shared domination and six AP per human")
	e.unit("vampire").position = Hex.encode(Hex.from_offset(0,0))
	var destination = Hex.from_offset(3,0)
	check(destination in e.get_reachable_cells("vampire"),"reachable on shortened battlefield")
	e.execute_action({"actor_id":"vampire","kind":"MOVE","target_cell":Hex.encode(destination)})
	check(e.pos(e.unit("vampire"))==destination and e.domination==57,"walking on shortened battlefield charges exact cost")
	e.execute_action({"actor_id":"vampire","kind":"TELEPORT","target_cell":Hex.encode(Hex.from_offset(9,0))})
	check(e.pos(e.unit("vampire"))==Hex.from_offset(9,0) and e.domination==51,"teleport works on shortened battlefield")
	check(not e.validate_action({"actor_id":"vampire","kind":"MOVE","target_cell":Hex.encode(Hex.from_offset(20,0))}).valid,"new outer boundary enforced")
	var b = Board.new()
	b.observation = e.get_observation()
	check(b.board_cells().size()==200,"render enumerates all 200 cells")
	for cell in b.board_cells():
		check(b.cell_at_point(b.surface_center(cell))==cell,"shortened board picking")
	b.free()
	e.execute_action({"kind":"END_TURN"})
	var policy = Policy.new()
	var calls = 0
	while e.faction=="human" and calls<80:
		var action = policy.choose_action(e.get_observation(),e.enumerate_legal_actions(e.active_human()))
		check(e.validate_action(action).valid,"AI legal on shortened battlefield")
		e.execute_action(action)
		calls += 1
	check(e.faction=="undead" and e.round_number==2,"all eight human units complete turn")
	check(e.domination==60,"turn regeneration respects level cap")
	e.domination = 58
	e.apply_damage("archer","zombie_f",100,"test")
	check(e.domination==60,"death regeneration capped at sixty")
	check(Rules.new(42,1).domination==20 and Rules.new(42,7).domination==60,"level-specific initial resource on restart")
	check(Rules.new(42,1).board_width==20,"separate engines retain independent map sizes")
	for level_id in range(1,8):
		var regen_engine = Rules.new(42,level_id)
		var expected_regen = 30 if level_id==7 else 10
		check(regen_engine.get_observation().domination_regen==expected_regen,"observation reports level regeneration")
		regen_engine.domination = 8
		regen_engine.execute_action({"kind":"END_TURN"})
		while regen_engine.faction=="human":
			regen_engine.execute_action({"actor_id":regen_engine.active_human(),"kind":"END_UNIT"})
		check(regen_engine.domination==8+expected_regen,"turn restores level-specific amount")
	print("LARGE MAP RESULT: %d failures" % failures)
	quit(1 if failures else 0)
