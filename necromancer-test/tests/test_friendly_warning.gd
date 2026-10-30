extends SceneTree
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures+=1
		printerr(label)
func _initialize():
	call_deferred("run")
func run():
	var scene=load("res://scenes/Battle.tscn").instantiate()
	scene.settings_path="user://friendly_warning_test.cfg"
	root.add_child(scene)
	await process_frame
	scene.skip_friendly_fire_warning=false
	scene.engine.unit("vampire").position=[4,4]
	scene.engine.unit("zombie_a").position=[5,4]
	scene.refresh()
	var action={"actor_id":"vampire","kind":"MELEE_ATTACK","target_unit_id":"zombie_a"}
	scene.perform(action)
	check(scene.friendly_fire_dialog.visible and not scene.pending_friendly_action.is_empty(),"direct friendly target opens confirmation")
	check(scene.engine.domination==20 and scene.engine.unit("zombie_a").hp==10,"opening warning does not spend or damage")
	scene.perform({"kind":"END_TURN"})
	check(scene.engine.faction=="undead","pending confirmation blocks other commands")
	scene.cancel_friendly_fire()
	check(scene.engine.history.is_empty(),"cancel leaves battle unchanged")
	scene.engine.heights={"6,4":1}
	scene.refresh()
	check(scene.friendly_fire_targets({"actor_id":"vampire","kind":"OVERHEAD_STRIKE","target_unit_id":"zombie_a"}).size()==1,"advantage attack also warns for friendly target")
	scene.engine.heights={}
	scene.refresh()
	scene.perform(action)
	scene.confirm_friendly_fire()
	check(scene.engine.domination==12 and scene.engine.unit("zombie_a").hp<10,"confirm executes once")
	scene.confirm_friendly_fire()
	check(scene.engine.history.size()==1,"duplicate confirmation does not repeat attack")
	scene.board.stop_playback()
	scene.select_level(10)
	scene.engine.unit("undead_spearman").position=[4,4]
	scene.engine.unit("spear_a").position=[5,4]
	scene.engine.unit("undead_archer").position=[6,4]
	scene.refresh()
	action={"actor_id":"undead_spearman","kind":"SPEAR_THRUST","target_unit_id":"spear_a"}
	scene.perform(action)
	check(scene.friendly_fire_dialog.visible and scene.friendly_fire_targets(action).size()==1,"enemy target with friendly area victim warns")
	scene.cancel_friendly_fire()
	scene.engine.unit("undead_archer").position=[0,0]
	scene.refresh()
	check(scene.friendly_fire_targets(action).is_empty(),"clean enemy attack has no warning")
	scene.select_level(11)
	scene.engine.unit("undead_knight").position=[4,4]
	scene.engine.unit("vampire").position=[8,4]
	scene.refresh()
	action={"actor_id":"undead_knight","kind":"CHARGE","target_cell":[7,4]}
	scene.perform(action)
	check(scene.friendly_fire_dialog.visible and scene.engine.unit("undead_knight").position==[4,4],"charge warns before moving or spending")
	scene.friendly_fire_opt_out.button_pressed=true
	scene.confirm_friendly_fire()
	check(scene.skip_friendly_fire_warning and scene.engine.domination==14,"opt out stored on confirm")
	var prefs=ConfigFile.new()
	check(prefs.load(scene.settings_path)==OK and prefs.get_value("combat","skip_friendly_fire_warning",false),"preference persists to disk")
	scene.board.stop_playback()
	scene.restart_battle()
	scene.engine.unit("vampire").position=[4,4]
	scene.engine.unit("zombie_a").position=[5,4]
	scene.refresh()
	scene.perform({"actor_id":"vampire","kind":"MELEE_ATTACK","target_unit_id":"zombie_a"})
	check(not scene.friendly_fire_dialog.visible and scene.engine.domination==12,"opt out survives restart and skips warning")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scene.settings_path))
	scene.queue_free()
	await process_frame
	print("FRIENDLY WARNING RESULT: %d failures" % failures)
	quit(1 if failures else 0)
