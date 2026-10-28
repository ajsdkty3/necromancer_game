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
	check(scene.edge_pan_direction(Vector2(2,450),Vector2(1600,900))==Vector2.RIGHT,"left edge pans view left")
	check(scene.edge_pan_direction(Vector2(1598,450),Vector2(1600,900))==Vector2.LEFT,"right edge pans view right")
	check(scene.edge_pan_direction(Vector2(800,2),Vector2(1600,900))==Vector2.DOWN,"top edge pans view up")
	check(scene.edge_pan_direction(Vector2(800,898),Vector2(1600,900))==Vector2.UP,"bottom edge pans view down")
	check(scene.edge_pan_direction(Vector2(800,450),Vector2(1600,900))==Vector2.ZERO,"center stops edge pan")
	check(scene.edge_pan_direction(Vector2(-2,450),Vector2(1600,900))==Vector2.ZERO,"outside window stops edge pan")
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
	var end_rect = scene.end_button.get_global_rect()
	check(end_rect.position.x > 1200 and end_rect.position.y > 800,"end turn anchored bottom right")
	await click(screen_point,MOUSE_BUTTON_LEFT)
	check(scene.selected == "zombie_a","left click selects unit")
	await click(screen_point,MOUSE_BUTTON_LEFT)
	check(scene.selected == "" and scene.mode == "DEFAULT" and scene.board.highlighted.is_empty() and scene.board.danger_cells.is_empty(),"click selected ally clears selection and highlights")
	await click(screen_point,MOUSE_BUTTON_LEFT)
	await press_key(KEY_1)
	var toggle_history = scene.engine.history.size()
	await click(screen_point,MOUSE_BUTTON_LEFT)
	check(scene.selected == "" and scene.mode == "DEFAULT" and scene.engine.history.size() == toggle_history,"click self in targeting cancels selection without action")
	await click(screen_point,MOUSE_BUTTON_LEFT)
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
	scene.board._process(1.0)
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
	scene.board._process(1.0)
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
	check(scene.actions.get_child(2).text.contains("猩红之吻") and scene.actions.get_child(3).text.contains("瞬移"),"vampire special third and teleport fourth")
	await press_key(KEY_KP_4)
	check(scene.mode == "TELEPORT","keypad four selects teleport")
	check(scene.board.danger_cells.is_empty(),"teleport does not show reaction danger")
	check(scene.engine.domination == 20 and scene.engine.history.is_empty(),"shortcut selects without executing")
	await press_key(KEY_5)
	check(scene.mode == "DEFAULT","five cancels vampire targeting")
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
	scene.level_menu.get_popup().id_pressed.emit(2)
	check(scene.current_level == 2 and scene.engine.units.size() == 6,"menu selects second level")
	check(scene.engine.humans().size() == 3 and scene.engine.unit("archer").is_empty() and scene.engine.unit("shield").hp == 30,"second level has two spearmen and shieldman")
	check(not scene.board.is_playing() and scene.engine.domination == 20,"level switch resets animation and resources")
	check(scene.status.text.contains("/ 3"),"second level progress uses three enemies")
	check(scene.level_menu.text.contains("第二关"),"menu shows current level")
	scene.engine.unit("vampire").position = [2,3]
	scene.engine.unit("spear_a").position = [3,3]
	scene.engine.unit("shield").position = [4,3]
	scene.engine.unit("shield").guarding = true
	scene.selected = ""
	scene.refresh()
	check(scene.board.guard_zones().size() == 1,"guard outline visible without selection")
	var guard_zone = scene.board.guard_zones()[0]
	check(guard_zone.cells.size() == 7 and scene.board.zone_edges(guard_zone.cells).size() == 18,"guard contour encloses adjacent six cells")
	for targeting_mode in ["MOVE","MELEE_ATTACK","TELEPORT"]:
		scene.mode = targeting_mode
		scene.refresh()
		check(scene.board.guard_zones().size() == 1,"guard outline persists across targeting modes")
	scene.mode = "DEFAULT"
	scene.engine.faction = "human"
	scene.refresh()
	check(scene.board.guard_zones().size() == 1,"guard visible during AI turn")
	scene.engine.faction = "undead"
	scene.engine.unit("shield").guarding = false
	scene.refresh()
	check(scene.board.guard_zones().is_empty(),"expired guard outline disappears")
	scene.engine.unit("shield").guarding = true
	scene.engine.unit("shield").alive = false
	scene.refresh()
	check(scene.board.guard_zones().is_empty(),"dead guardian has no outline")
	scene.engine.unit("shield").alive = true
	scene.selected = "shield"
	scene.refresh()
	check(scene.details.text.contains("守护中") and scene.actions.get_child(2).text.contains("守护"),"shield details expose guard action and status")
	scene.selected = "vampire"
	scene.refresh()
	scene.perform({"actor_id":"vampire","kind":"MELEE_ATTACK","target_unit_id":"spear_a"})
	scene.board._process(0.23)
	check(scene.board.effect.type == "protected","protected unit plays immunity animation")
	scene.board._process(0.03)
	check(scene.board.unit_offset("spear_a") != Vector2.ZERO,"protected unit trembles slightly")
	scene.board._process(0.15)
	check(scene.board.visual_unit("spear_a").hp == 14,"protected animation keeps ally HP")
	if DisplayServer.get_name() != "headless":
		scene.board.set_process(false)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/guard_preview.png")
		scene.board.set_process(true)
	scene.board._process(0.2)
	check(scene.board.effect.type == "damage" and scene.board.effect.target == "shield","guardian takes subsequent damage animation")
	var menu_rect = scene.level_menu.get_global_rect()
	check(absf(menu_rect.get_center().x-800) < 2 and menu_rect.position.y < 60,"menu at top center")
	scene.engine.domination = 3
	scene.level_menu.get_popup().id_pressed.emit(100)
	check(scene.current_level == 2 and scene.engine.units.size() == 6 and scene.engine.domination == 20,"menu restart resets current level")
	scene.engine.execute_action({"kind":"END_TURN"})
	for id in ["spear_a","spear_b","shield"]:
		scene.engine.execute_action({"actor_id":id,"kind":"END_UNIT"})
	check(scene.engine.faction == "undead" and scene.engine.round_number == 2,"second level completes human turn after three units")
	scene.level_menu.get_popup().id_pressed.emit(1)
	check(scene.engine.units.size() == 6 and scene.engine.unit("archer").alive,"first level restores archer")
	scene.level_menu.get_popup().id_pressed.emit(3)
	check(scene.current_level == 3 and scene.engine.units.size() == 6,"third level selected from menu")
	var occupied = {}
	for u in scene.engine.units:
		check(not occupied.has(str(u.position)),"third level deployment has no overlapping units")
		occupied[str(u.position)] = true
	check(scene.engine.humans().map(func(u): return u.archetype) == ["spearman","archer","shieldman"],"third level has spear archer shield in action order")
	check(scene.engine.unit("vampire").hp == 20 and scene.engine.unit("zombie_a").hp == 10 and scene.engine.unit("zombie_b").hp == 10,"third level preserves undead roster")
	scene.level_menu.get_popup().id_pressed.emit(100)
	check(scene.current_level == 3 and scene.engine.level_id == 3,"restart keeps third level")
	scene.engine.execute_action({"kind":"END_TURN"})
	for id in ["spear_a","archer","shield"]:
		check(scene.engine.active_human() == id,"third level human order")
		scene.engine.execute_action({"actor_id":id,"kind":"END_UNIT"})
	check(scene.engine.faction == "undead","third level returns to undead turn")
	for level in [4,5,6,7]:
		scene.level_menu.get_popup().id_pressed.emit(level)
		check(scene.current_level==level and scene.engine.level_id==level,"new level selectable from menu")
		scene.level_menu.get_popup().id_pressed.emit(100)
		check(scene.engine.level_id==level and scene.engine.humans().size()==(8 if level==7 else 3),"restart preserves new level")
	scene.level_menu.get_popup().id_pressed.emit(1)
	scene.restart_battle()
	scene.perform({"kind":"END_TURN"})
	scene.ai_delay = 0
	scene._process(0)
	check(scene.engine.history.back().kind == "MOVE" and is_equal_approx(scene.ai_delay,0.10),"AI walking interval is one tenth second")
	scene.restart_battle()
	check(not scene.board.is_playing() and scene.board.effect.is_empty(),"restart clears animation queue")
	scene.engine.unit("spear_a").position = [10,3]
	scene.engine.unit("spear_b").position = [9,5]
	scene.selected = "vampire"
	scene.refresh()
	check(scene.board.danger_zones.size() == 2,"each spearman keeps independent boundary")
	for zone in scene.board.danger_zones:
		var expected = scene.engine.get_observation().zones[zone.owner_id].map(func(c): return Vector2i(int(c[0]),int(c[1])))
		check(expected.all(func(c): return hex.distance(c,zone.center)<=1),"spear red zone restricted to one hex")
		expected.append(zone.center)
		check(zone.cells.size() == expected.size() and expected.all(func(c): return c in zone.cells),"boundary uses height-filtered zone and includes owner")
		var perimeter = 0
		for cell in zone.cells:
			for direction in [Vector2i(1,0),Vector2i(1,-1),Vector2i(0,-1),Vector2i(-1,0),Vector2i(-1,1),Vector2i(0,1)]:
				if cell+direction not in zone.cells:
					perimeter += 1
		check(scene.board.zone_edges(zone.cells).size() == perimeter,"height-clipped zone draws only perimeter edges")
	check(scene.board.danger_zones[0].cells.any(func(cell): return cell in scene.board.danger_zones[1].cells),"preview includes overlapping zones")
	var overlap_cell = scene.board.danger_zones[0].cells.filter(func(cell): return cell in scene.board.danger_zones[1].cells)[0]
	check(scene.board.danger_layer_count(overlap_cell)==2,"overlap receives two translucent red layers")
	scene.engine.unit("spear_a").reaction_ready = false
	scene.refresh()
	check(scene.board.danger_zones.size() == 1 and scene.board.danger_zones[0].owner_id == "spear_b","spent unit outline disappears while other remains")
	check(scene.board.danger_layer_count(overlap_cell)==1,"spent reaction removes its fill layer")
	scene.engine.unit("spear_a").reaction_ready = true
	scene.refresh()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/battle_preview.png")
	scene.selected = "spear_a"
	scene.mode = "DEFAULT"
	scene.refresh()
	check(scene.board.danger_zones.size()==1 and scene.board.danger_zones[0].owner_id=="spear_a","inspected enemy shows only its own control zone")
	check(scene.board.danger_cells.size()==6 and scene.board.highlighted.is_empty(),"enemy inspection shows adjacent control cells without movement highlights")
	scene.board.position = Vector2(800,450)-scene.board.surface_center(hex.decode(scene.engine.unit("spear_a").position))
	scene.clamp_board_position()
	var enemy_point = scene.board.to_global(scene.board.surface_center(hex.decode(scene.engine.unit("spear_a").position)))
	await click(enemy_point,MOUSE_BUTTON_LEFT)
	check(scene.selected=="" and scene.mode=="DEFAULT" and scene.board.danger_zones.is_empty() and scene.board.danger_cells.is_empty(),"second click on enemy clears selection and control zone")
	await click(enemy_point,MOUSE_BUTTON_LEFT)
	check(scene.selected=="spear_a" and scene.board.danger_zones.size()==1,"enemy can be selected again after toggling off")
	scene.engine.unit("spear_a").reaction_ready = false
	scene.refresh()
	check(scene.board.danger_zones.is_empty(),"inspected spent enemy shows no zone")
	scene.engine.unit("spear_a").reaction_ready = true
	scene.engine.unit("spear_a").fleeing = true
	scene.refresh()
	check(scene.board.danger_zones.is_empty(),"inspected fleeing enemy shows no zone")
	scene.selected = "archer"
	scene.refresh()
	check(scene.board.danger_zones.is_empty(),"archer has no control zone")
	print("UI RESULT: %d failures" % failures)
	quit(1 if failures else 0)
