extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var scene = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(scene)
	root.size = Vector2i(1600,900)
	await process_frame
	for level in [4,5,6]:
		scene.select_level(level)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tests/level_%d_preview.png" % level)
	quit()
