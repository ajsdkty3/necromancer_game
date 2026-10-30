extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Board = preload("res://scripts/ui/HexBoardView.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func _init():
	var e = Rules.new(42)
	e.unit("spear_a").position = [3,3]
	e.unit("vampire").position = [4,3]
	e.unit("zombie_a").position = [5,3]
	e.faction = "human"
	var before = e.get_observation()
	var events = e.execute_action({"actor_id":"spear_a","kind":"SPEAR_THRUST","target_unit_id":"vampire"})
	var board = Board.new()
	board.observation = before
	board.play_events(events,before)
	check(board.enemy_attack_cells.has(Vector2i(4,3)) and board.enemy_attack_cells.has(Vector2i(5,3)),"enemy spear shows both hit cells during windup")
	board.advance_effect()
	check(board.enemy_attack_cells.size() == 2,"highlight persists through damage feedback")
	while board.is_playing():
		board.advance_effect()
	check(board.enemy_attack_cells.is_empty(),"highlight cleared after playback")
	e.events.clear()
	before = e.get_observation()
	e.attack(e.unit("spear_a"),e.unit("vampire"),true)
	board.play_events(e.events,before)
	check(board.enemy_attack_cells == [Vector2i(4,3)],"reaction remains single target")
	board.stop_playback()
	e.events.clear()
	before = e.get_observation()
	e.attack(e.unit("vampire"),e.unit("spear_a"),false)
	board.play_events(e.events,before)
	check(board.enemy_attack_cells.is_empty(),"player attack not marked as enemy attack")
	board.stop_playback()
	board.free()
	print("Enemy attack highlight failures: ",failures)
	quit(failures)
