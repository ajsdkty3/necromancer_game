extends SceneTree
const Hex = preload("res://scripts/core/HexGrid.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures+=1
		printerr(label)
func _initialize():
	call_deferred("run")
func run():
	var scene = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.select_level(10)
	scene.engine.unit("undead_spearman").position=[4,4]
	scene.engine.unit("spear_a").position=[5,4]
	scene.selected="undead_spearman"
	scene.mode="SPEAR_THRUST"
	scene.refresh()
	check(scene.board.attack_range_cells.size()==18,"radius two includes eighteen cells")
	check(scene.board.attack_boundary_edges().size()==30,"radius two draws only thirty exterior edges, no internal hex borders")
	for direction in Hex.DIRECTIONS:
		var near=Vector2i(4,4)+direction
		var far=Vector2i(4,4)+direction*2
		check(scene.attack_preview_at(near)==[near,far],"near hover shows both piercing cells")
		check(scene.attack_preview_at(far)==[near,far],"far hover shows both piercing cells")
	check(scene.attack_preview_at(Vector2i(5,5))==[Vector2i(5,5)],"off-axis hover is single target")
	check(scene.attack_preview_at(Vector2i(4,4)).is_empty() and scene.attack_preview_at(Vector2i(9,4)).is_empty(),"self and out of range excluded")
	scene.update_charge_preview(scene.board.get_global_transform_with_canvas()*scene.board.surface_center(Vector2i(6,4)))
	check(scene.board.attack_hover_cells==[Vector2i(5,4),Vector2i(6,4)],"hover updates immediately")
	var before=scene.engine.history.size()
	scene.try_target(Vector2i(6,4),"SPEAR_THRUST")
	check(scene.engine.history.size()==before,"empty preview cell cannot execute attack")
	scene.engine.heights={"8,4":2}
	scene.refresh()
	check(scene.attack_preview_at(Vector2i(5,4))==[Vector2i(5,4)],"illegal high secondary cell excluded")
	check(scene.attack_preview_at(Vector2i(6,4)).is_empty(),"illegal high hovered target excluded")
	scene.cancel_action()
	check(scene.board.attack_range_cells.is_empty() and scene.board.attack_hover_cells.is_empty(),"cancel clears range and preview")
	for spec in [["vampire","MELEE_ATTACK",1],["zombie","BITE",1],["undead_shieldman","SHIELD_BASH",1],["undead_archer","SHOOT",5],["undead_spearman","KNOCKBACK",1],["undead_knight","WAR_STOMP",1]]:
		scene.engine.heights={}
		scene.engine.unit("undead_spearman").archetype=spec[0]
		scene.mode=spec[1]
		scene.refresh()
		var expected=[]
		for cell in Hex.cells(20,10):
			if cell!=Vector2i(4,4) and Hex.distance(Vector2i(4,4),cell)<=spec[2]:
				expected.append(cell)
		check(scene.board.attack_range_cells.size()==expected.size(),"attack range for "+spec[0])
		if spec[2]==1:
			check(scene.board.attack_boundary_edges().size()==18,"adjacent attack only outer boundary")
		if spec[1] not in ["KNOCKBACK","WAR_STOMP"]:
			check(scene.attack_preview_at(Vector2i(5,4))==[Vector2i(5,4)],"single target preview for "+spec[0])
	scene.mode="TELEPORT"
	scene.refresh()
	check(scene.board.attack_boundary_edges().is_empty(),"nonattack clears red contour")
	scene.queue_free()
	await process_frame
	print("SPEAR PREVIEW RESULT: %d failures" % failures)
	quit(1 if failures else 0)
