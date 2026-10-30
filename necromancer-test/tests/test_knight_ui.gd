extends SceneTree
const Hex = preload("res://scripts/core/HexGrid.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func _initialize():
	call_deferred("run")
func run():
	var scene = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.select_level(11)
	scene.engine.unit("undead_knight").position = [2,4]
	scene.engine.unit("knight").position = [6,4]
	scene.selected = "undead_knight"
	scene.refresh()
	check(scene.details.text.contains("仆役"),"undead knight is servant")
	scene.actions.get_child(1).pressed.emit()
	check(scene.mode=="CHARGE" and scene.board.highlighted.has(Vector2i(5,4)),"charge button highlights eligible endpoints")
	check(scene.board.highlighted.has(Vector2i(5,1)),"endpoint highlighted even without nearby enemy")
	check(scene.board.charge_path_cells.has(Vector2i(3,4)) and scene.board.charge_path_cells.has(Vector2i(5,4)),"full legal path and endpoint are highlighted")
	var preview = scene.charge_preview_at(Vector2i(3,4))
	check(preview.size()==1 and preview.has(Vector2i(6,4)),"hover intermediate path previews forward single cell")
	check(scene.charge_preview_at(Vector2i(5,4))==preview,"endpoint and its path show same attack area")
	check(scene.charge_preview_at(Vector2i(3,5)).is_empty(),"off-path hover clears attack preview")
	scene.update_charge_preview(scene.board.get_global_transform_with_canvas()*scene.board.surface_center(Vector2i(3,4)))
	check(scene.board.charge_attack_preview==preview,"mouse preview updates immediately")
	scene.cancel_action()
	check(scene.board.charge_attack_preview.is_empty(),"cancel clears charge overlay")
	scene.actions.get_child(1).pressed.emit()
	scene.try_target(Vector2i(5,4),"CHARGE")
	check(scene.mode=="DEFAULT" and scene.engine.domination==14 and scene.engine.unit("knight").hp==12,"charge automatically strikes after arrival")
	check(scene.board.is_playing(),"charge animates movement and attack")
	scene.board.stop_playback()
	scene.selected = "knight"
	scene.refresh()
	check(scene.details.text.contains("12/12"),"human knight displays own AP cap")
	scene.engine.apply_stun(scene.engine.unit("undead_knight"))
	scene.selected = "undead_knight"
	scene.refresh()
	check(scene.details.text.contains("眩晕"),"stun shown in details")
	for i in range(scene.actions.get_child_count()-1):
		check(scene.actions.get_child(i).disabled,"stun disables combat buttons")
	scene.select_level(11)
	check(not scene.engine.unit("undead_knight").stunned,"restart clears stun")
	scene.selected = "undead_knight"
	scene.mode = "CHARGE"
	scene.refresh()
	var destination = Hex.decode(scene.legal.filter(func(a): return a.kind=="CHARGE" and a.target_cell!=scene.engine.unit("undead_knight").position)[0].target_cell)
	scene.try_target(destination,"CHARGE")
	check(scene.mode=="DEFAULT" and scene.engine.domination==14,"charge with no enemies auto-finishes")
	scene.board.stop_playback()
	scene.select_level(12)
	scene.selected = "undead_knight"
	scene.mode = "CHARGE"
	scene.refresh()
	check(scene.engine.obstacles.size()==8,"level twelve has obstacles")
	var start = Hex.decode(scene.engine.unit("undead_knight").position)
	var blocked_end = start+Vector2i(3,0)
	check(not scene.board.highlighted.has(blocked_end),"obstacle blocks whole charge endpoint")
	check(not scene.board.charge_path_cells.has(start+Vector2i(1,0)),"blocked ray has no partial path highlight")
	for step in range(1,4):
		check(scene.board.blocked_charge_cells.has(start+Vector2i(step,0)),"entire blocked ray is gray including endpoint")
	check(scene.charge_preview_at(start+Vector2i(1,0)).is_empty(),"blocked path has no attack preview")
	check(not scene.board.highlighted.is_empty(),"other directions remain available")
	var before = scene.engine.domination
	scene.try_target(blocked_end,"CHARGE")
	check(scene.engine.domination==before and Hex.decode(scene.engine.unit("undead_knight").position)==start,"blocked charge cannot execute")
	scene.cancel_action()
	check(scene.board.charge_path_cells.is_empty(),"cancel clears charge path")
	check(scene.board.blocked_charge_cells.is_empty(),"cancel clears blocked path")
	scene.queue_free()
	await process_frame
	print("KNIGHT UI RESULT: %d failures" % failures)
	quit(1 if failures else 0)
