extends SceneTree
const Battle = preload("res://scripts/ui/Battle.gd")
const Board = preload("res://scripts/ui/HexBoardView.gd")
const Rules = preload("res://scripts/core/BattleEngine.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr(message)
func _init():
	var battle = Battle.new()
	battle.board = Board.new()
	for level in range(1,8):
		battle.board.observation = Rules.new(42,level).get_observation()
		battle.update_map_bounds()
		for size in [Vector2(1280,800),Vector2(1920,1080),Vector2(4000,2400)]:
			var low = battle.bounded_board_position(Vector2(-100000,-100000),size)
			var high = battle.bounded_board_position(Vector2(100000,100000),size)
			check(low.x<=high.x and low.y<=high.y,"valid limits on each level and window size")
			check(battle.bounded_board_position(low-Vector2.ONE*500,size).is_equal_approx(low),"cannot pan beyond lower boundary")
			check(battle.bounded_board_position(high+Vector2.ONE*500,size).is_equal_approx(high),"cannot pan beyond upper boundary")
			var middle = (low+high)*0.5
			check(battle.bounded_board_position(middle,size).is_equal_approx(middle),"movement inside boundaries retained")
			if size.x==4000:
				check(low.is_equal_approx(high),"small map centered in oversized viewport")
	battle.board.free()
	battle.free()
	print("CAMERA BOUNDS RESULT: %d failures" % failures)
	quit(1 if failures else 0)
