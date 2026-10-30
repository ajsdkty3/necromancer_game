extends SceneTree
const Hex = preload("res://scripts/core/HexGrid.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr(message)
func _initialize():
	call_deferred("run")
func run():
	var scene = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.engine.unit("vampire").position = [0,0]
	scene.engine.heights = {"1,0":1}
	scene.selected = "vampire"
	scene.refresh()
	check(scene.movement_hint_at(Vector2i(1,0))=="2支配力","uphill preview uses weighted cost")
	check(scene.movement_hint_at(Vector2i.ZERO).is_empty(),"occupied cell has no move hint")
	var p = scene.board.get_global_transform_with_canvas()*scene.board.surface_center(Vector2i(1,0))
	scene.update_move_hint(p)
	check(scene.move_hint.visible and scene.move_hint.text=="2支配力","hint displays immediately without timer")
	check(scene.actions.get_child(2).text.contains("造成6伤害"),"vampire displays current kiss damage")
	check(scene.board.move_hover_cell==Vector2i(1,0),"only hovered reachable destination is selected for blue fill")
	check(not scene.board.movement_boundary_edges().is_empty(),"movement range has blue exterior edges")
	scene.update_move_hint(scene.board.get_global_transform_with_canvas()*scene.board.surface_center(Vector2i.ZERO))
	check(scene.board.move_hover_cell==Vector2i(-999,-999),"occupied hover clears destination fill")
	scene.mode = "OVERHEAD_STRIKE"
	scene.refresh()
	check(scene.movement_hint_at(Vector2i(1,0)).is_empty(),"attack mode hides move cost")
	check(scene.board.movement_boundary_edges().is_empty() and scene.board.move_hover_cell==Vector2i(-999,-999),"attack mode clears movement rendering")
	scene.mode = "DEFAULT"
	scene.engine.unit("spear_a").position = [2,0]
	scene.selected = "spear_a"
	scene.refresh()
	check(scene.movement_hint_at(Vector2i(1,0))=="2AP","human inspection uses AP")
	scene.selected = "vampire"
	scene.engine.domination = 1
	scene.refresh()
	check(scene.movement_hint_at(Vector2i(1,0))=="不可到达 / 资源不足","insufficient resource not shown as reachable")
	scene.update_move_hint(p)
	check(scene.board.move_hover_cell==Vector2i(-999,-999),"unreachable destination has no blue fill")
	scene.selected = ""
	scene.refresh()
	check(scene.movement_hint_at(Vector2i(1,0)).is_empty(),"deselect clears hover")
	scene.queue_free()
	await process_frame
	print("MOVE HINT RESULT: %d failures" % failures)
	quit(1 if failures else 0)
