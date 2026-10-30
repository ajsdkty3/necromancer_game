extends SceneTree
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr(message)
func _initialize():
	call_deferred("run")
func run():
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	await process_frame
	var e = battle.engine
	e.unit("zombie_a").position = [4,4]
	e.unit("vampire").position = [5,3]
	e.unit("zombie_b").position = [6,3]
	e.unit("spear_a").position = [5,4]
	e.apply_damage("vampire","spear_a",100,"test")
	battle.selected = "zombie_a"
	battle.refresh()
	var button = battle.actions.get_child(2)
	check(button.disabled,"surrounded corpse must not unlock advantage")
	button.pressed.emit()
	check(battle.mode == "DEFAULT","disabled button cannot enter targeting")
	var key = InputEventKey.new()
	key.keycode = KEY_3
	key.pressed = true
	battle._unhandled_input(key)
	check(battle.mode == "DEFAULT","disabled shortcut cannot enter targeting")
	e.apply_damage("vampire","spear_a_corpse",100,"test")
	e.unit("spear_b").position = [5,4]
	battle.refresh()
	check(not battle.actions.get_child(2).disabled,"surrounded living enemy unlocks advantage")
	e.domination = 0
	battle.refresh()
	check(battle.actions.get_child(2).disabled,"insufficient resources disable advantage")
	battle.queue_free()
	await process_frame
	print("Advantage disabled failures: ",failures)
	quit(failures)
