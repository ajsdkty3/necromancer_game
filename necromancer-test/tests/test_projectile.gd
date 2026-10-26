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
	e.faction = "human"
	e.human_index = 2
	e.unit("archer").position = [0,0]
	e.unit("vampire").position = [4,0]
	e.heights = {"4,0":2}
	var before = e.get_observation()
	var events = e.execute_action({"actor_id":"archer","kind":"SHOOT","target_unit_id":"vampire"})
	var b = Board.new()
	b.observation = e.get_observation()
	b.play_events(events,before)
	check(b.is_ranged_shot() and b.projectile_state().is_empty(),"shot winds up before launching")
	b._process(b.SHOT_WINDUP+b.SHOT_FLIGHT*0.5)
	var midpoint = b.surface_center(Vector2i.ZERO).lerp(b.surface_center(Vector2i(4,0)),0.5)
	check(b.projectile_state().head.is_equal_approx(midpoint),"arrow flies toward elevated target")
	check(b.visual_unit("vampire").hp==15,"visual damage waits for arrow arrival")
	b._process(b.SHOT_FLIGHT*0.5+0.001)
	check(b.effect.type=="damage" and b.projectile_state().is_empty(),"impact starts after flight and clears arrow")
	check(b.visual_unit("vampire").hp==e.unit("vampire").hp,"impact displays actual resolved damage")
	b.stop_playback()
	check(b.projectile_state().is_empty(),"restart clears projectile")
	b.free()
	print("PROJECTILE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
