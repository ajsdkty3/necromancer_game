extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Board = preload("res://scripts/ui/HexBoardView.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr(message)
func _init():
	var e = Rules.new(42)
	e.obstacles = {}
	e.heights = {"3,0":1}
	e.unit("vampire").position = [0,0]
	var before = e.get_observation()
	var events = e.execute_action({"actor_id":"vampire","kind":"MOVE","target_cell":[3,0]})
	var board = Board.new()
	board.observation = e.get_observation()
	board.play_events(events,before)
	check(board.is_playing() and board.effect.type=="move","pure movement starts playback")
	check(board.visual_unit("vampire").position==[0,0],"visual starts at old cell")
	board._process(board.MOVE_STEP_DURATION*0.5)
	check(board.unit_offset("vampire").is_equal_approx((board.surface_center(Vector2i(1,0))-board.surface_center(Vector2i.ZERO))*0.5),"half-step interpolates")
	board._process(board.MOVE_STEP_DURATION*0.5)
	check(board.visual_unit("vampire").position==[1,0] and board.effect.to==[2,0],"advances one path cell at a time")
	board._process(board.MOVE_STEP_DURATION*1.5)
	check(board.effect.to==[3,0] and board.unit_offset("vampire").y<0,"uphill animation follows raised surface")
	board._process(1.0)
	check(not board.is_playing() and e.unit("vampire").position==[3,0],"finishes at engine destination")
	board.play_events(events,before)
	board.stop_playback()
	check(not board.is_playing() and board.effect.is_empty(),"restart clears movement")
	# The rule engine supplies reactions before a surviving move, or death without a move.
	e = Rules.new(42)
	e.obstacles = {}
	e.heights = {}
	e.unit("vampire").position = [0,0]
	e.unit("spear_a").position = [1,0]
	before = e.get_observation()
	events = e.execute_action({"actor_id":"vampire","kind":"MOVE","target_cell":[0,1]})
	board.observation = e.get_observation()
	board.play_events(events,before)
	check(board.effect.type=="reaction" and board.visual_unit("vampire").position==[0,0],"reaction plays at old cell")
	board._process(0.22)
	check(board.effect.type=="damage","hit plays before moving")
	board._process(0.24)
	check(board.effect.type=="move" and board.visual_unit("vampire").position==[0,0],"survivor moves after hit")
	board.stop_playback()
	e.unit("vampire").position = [0,0]
	e.unit("vampire").hp = 1
	e.unit("spear_a").reaction_ready = true
	before = e.get_observation()
	events = e.execute_action({"actor_id":"vampire","kind":"MOVE","target_cell":[0,1]})
	board.observation = e.get_observation()
	board.play_events(events,before)
	board._process(1.0)
	check(not board.is_playing() and not e.unit("vampire").alive and e.unit("vampire").position==[0,0],"lethal reaction never animates unfinished step")
	board.free()
	print("MOVE ANIMATION RESULT: %d failures" % failures)
	quit(1 if failures else 0)
