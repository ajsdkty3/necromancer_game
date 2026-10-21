extends SceneTree

var failures = 0

func check(condition: bool, label: String):
	if not condition:
		failures += 1
		printerr("FAIL UI: " + label)

func click(position: Vector2, button: MouseButton):
	var event = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _initialize():
	call_deferred("run")

func press_key(code: Key):
	var event = InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	Input.parse_input_event(event)
	await process_frame

func run():
	var scene = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	# Input coordinates use the viewport; bypass window stretch by fixing the test viewport.
	root.size = Vector2i(1600,900)
	await process_frame
	var hex = load("res://scripts/core/HexGrid.gd")
	var unit_cell = hex.decode(scene.engine.unit("zombie_a").position)
	var screen_point = scene.board.to_global(hex.center(unit_cell))
	check(scene.status.get_global_rect().position.x > 1000,"status anchored at right")
	check(scene.details.get_global_rect().position.y > 400,"details anchored at bottom")
	await click(screen_point,MOUSE_BUTTON_LEFT)
	check(scene.selected == "zombie_a","left click selects unit")
	check(not scene.board.highlighted.is_empty(),"selection displays reachable cells")
	var expected_danger = {}
	for enemy_id in ["spear_a","spear_b"]:
		for cell in scene.observation.zones[enemy_id]:
			expected_danger[hex.decode(cell)] = true
	check(scene.board.danger_cells.size() == expected_danger.size(),"movement shows enemy melee zones only")
	for cell in expected_danger:
		check(cell in scene.board.danger_cells,"all enemy control cells marked red")
	var target = unit_cell + Vector2i(1,0)
	await click(scene.board.to_global(hex.center(target)),MOUSE_BUTTON_RIGHT)
	check(scene.engine.unit("zombie_a").position == hex.encode(target),"right click moves")
	check(scene.engine.domination == 19,"single click executes exactly once")
	check(scene.selected == "zombie_a","selection survives movement")
	scene.mode = "BITE"
	scene.refresh()
	check(scene.board.danger_cells.is_empty(),"attack targeting clears movement danger overlay")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	check(scene.mode == "DEFAULT" and not scene.board.highlighted.is_empty(),"escape restores move highlights")
	check(not scene.board.danger_cells.is_empty(),"escape restores danger overlay")
	check(scene.actions.get_child_count() > 0,"actions visible")
	if scene.actions.get_child_count() > 0:
		check(scene.actions.get_child(scene.actions.get_child_count()-1).text.ends_with("取消"),"cancel is last action")
	var before = scene.engine.domination
	await click(Vector2(80,80),MOUSE_BUTTON_RIGHT)
	check(scene.engine.domination == before,"log panel blocks board input")
	scene.mode = "MOVE"
	scene.refresh()
	target += Vector2i(1,0)
	await click(scene.board.to_global(hex.center(target)),MOUSE_BUTTON_LEFT)
	check(scene.engine.unit("zombie_a").position == hex.encode(target),"move targeting supports left click")
	scene.perform({"kind":"END_TURN"})
	var history_size = scene.engine.history.size()
	scene.perform({"actor_id":"zombie_a","kind":"MOVE","target_cell":[0,0]})
	check(scene.engine.history.size() == history_size,"player actions blocked in AI phase")
	scene.restart_battle()
	check(scene.engine.domination == 20 and scene.engine.round_number == 1 and scene.selected == "","restart resets state")
	await press_key(KEY_1)
	check(scene.mode == "DEFAULT","number without selection does nothing")
	await click(scene.board.to_global(hex.center(hex.decode(scene.engine.unit("vampire").position))),MOUSE_BUTTON_LEFT)
	await press_key(KEY_1)
	check(scene.mode == "MOVE","one selects movement")
	await press_key(KEY_2)
	check(scene.mode == "MOVE","disabled attack cannot be selected by key")
	await press_key(KEY_KP_3)
	check(scene.mode == "TELEPORT","keypad three selects teleport")
	check(scene.board.danger_cells.is_empty(),"teleport does not show reaction danger")
	check(scene.engine.domination == 20 and scene.engine.history.is_empty(),"shortcut selects without executing")
	await press_key(KEY_4)
	check(scene.mode == "DEFAULT","four cancels vampire targeting")
	# The second action is enabled when a friendly target is adjacent.
	scene.engine.unit("zombie_a").position = hex.encode(hex.decode(scene.engine.unit("vampire").position) + Vector2i(1,0))
	scene.refresh()
	scene.actions.get_child(0).grab_focus()
	await press_key(KEY_2)
	check(scene.mode == "MELEE_ATTACK","two selects attack even with button focus")
	await press_key(KEY_ESCAPE)
	check(scene.mode == "DEFAULT","escape still cancels")
	scene.perform({"kind":"END_TURN"})
	scene.ai_delay = 100.0
	await press_key(KEY_1)
	check(scene.mode == "DEFAULT","numbers cannot act during AI turn")
	scene.restart_battle()
	scene.engine.unit("zombie_a").position = hex.encode(hex.decode(scene.engine.unit("vampire").position) + Vector2i(1,0))
	scene.engine.unit("zombie_a").hp = 1
	scene.refresh()
	scene.perform({"actor_id":"vampire","kind":"MELEE_ATTACK","target_unit_id":"zombie_a"})
	check(scene.board.is_playing() and scene.board.effect.type == "attack","attack starts visual playback")
	var attack_history_size = scene.engine.history.size()
	scene.perform({"kind":"END_TURN"})
	check(scene.engine.history.size() == attack_history_size,"actions blocked during animation")
	scene.board._process(0.1)
	check(scene.board.unit_offset("vampire") != Vector2.ZERO,"attacker raises before striking")
	scene.board._process(0.2)
	check(scene.board.effect.type == "damage","hit follows attack")
	check(scene.board.visual_unit("zombie_a").alive,"lethal target visible during hit")
	scene.board._process(0.05)
	check(scene.board.unit_offset("zombie_a") != Vector2.ZERO,"hit target shakes")
	if DisplayServer.get_name() != "headless":
		scene.board.set_process(false)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/attack_preview.png")
		scene.board.set_process(true)
	scene.board._process(0.3)
	check(not scene.board.is_playing() and not scene.engine.unit("zombie_a").alive,"death removes target after animation")
	scene.engine.unit("zombie_b").position = hex.encode(hex.decode(scene.engine.unit("vampire").position) + Vector2i(0,1))
	scene.refresh()
	scene.perform({"actor_id":"vampire","kind":"MELEE_ATTACK","target_unit_id":"zombie_b"})
	check(scene.board.is_playing(),"next attack can animate")
	scene.restart_battle()
	check(not scene.board.is_playing() and scene.board.effect.is_empty(),"restart clears animation queue")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/battle_preview.png")
	print("UI RESULT: %d failures" % failures)
	quit(1 if failures else 0)
