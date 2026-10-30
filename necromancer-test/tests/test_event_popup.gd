extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Events = preload("res://scripts/core/RandomEvents.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func _initialize():
	call_deferred("run")
func run():
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	await process_frame
	for kind in Events.NAMES:
		battle.engine = Rules.new(42)
		battle.refresh()
		var before = battle.observation
		Events.apply(battle.engine,kind,Events.candidates(battle.engine))
		battle.queue_random_event(battle.engine.events)
		battle.board.play_events(battle.engine.events,before)
		battle.refresh()
		if battle.board.is_playing():
			check(not battle.random_event_dialog.visible,"wait for animations before popup")
			while battle.board.is_playing():
				battle.board.advance_effect()
		check(battle.random_event_dialog.visible and Events.NAMES[kind] in battle.random_event_dialog.dialog_text,"event name shown")
		var count = battle.engine.history.size()
		battle.perform({"kind":"END_TURN"})
		check(battle.engine.history.size()==count,"modal blocks combat actions")
		battle.random_event_dialog.confirmed.emit()
		check(battle.pending_random_event.is_empty() and not battle.random_event_dialog.visible,"confirm resumes battle")
	battle.queue_random_event([{"type":"random_event","kind":"SURGE","message":"test"}])
	battle.refresh()
	battle.restart_battle()
	check(battle.pending_random_event.is_empty() and not battle.random_event_dialog.visible,"restart clears popup")
	battle.queue_free()
	await process_frame
	print("Event popup failures: ",failures)
	quit(failures)
