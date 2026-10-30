extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr("FAIL: "+label)
func _initialize():
	call_deferred("run")
func run():
	var e = Rules.new(42)
	e.apply_damage("vampire","spear_a",100,"test")
	e.apply_damage("vampire","spear_a_corpse",4,"test")
	var cell = e.unit("spear_a_corpse").position.duplicate()
	e.execute_action({"kind":"SUMMON_ZOMBIE","target_unit_id":"spear_a_corpse"})
	var z = e.units.back()
	check(z.archetype == "zombie" and z.hp == 6 and z.max_hp == 10 and z.position == cell,"summon preserves corpse HP and location")
	check(e.domination == 0 and not e.unit("spear_a_corpse").alive,"cost and consume corpse")
	check(e.enumerate_necromancer_actions().any(func(a): return a.kind == "SACRIFICE"),"free sacrifice remains available after summon")
	e.execute_action({"kind":"END_TURN"})
	check(e.enumerate_necromancer_actions().is_empty(),"cannot cast human turn")
	while e.faction == "human":
		e.execute_action({"kind":"END_UNIT","actor_id":e.active_human()})
	check(not e.validate_action({"kind":"FLESH_SHAPING","target_unit_id":z.id}).valid,"ten domination insufficient")
	e.domination = 20
	e.execute_action({"kind":"FLESH_SHAPING","target_unit_id":z.id})
	check(z.hp == 16 and z.max_hp == 20 and e.domination == 0,"shape increases current and max HP by ten")
	e = Rules.new(42,7)
	var shaping = {"kind":"FLESH_SHAPING","target_unit_id":e.units[0].id}
	var initial_hp = e.units[0].hp
	for i in 3:
		e.execute_action(shaping)
	check(e.units[0].hp == initial_hp+30 and e.units[0].max_hp == initial_hp+30 and e.domination == 0,"three consecutive casts stack and cost sixty")
	check(not e.validate_action(shaping).valid,"resource constraint remains after repeated casts")
	e = Rules.new(42)
	e.domination = 0
	e.unit("zombie_a").hp = 10
	e.execute_action({"kind":"SACRIFICE","target_unit_id":"zombie_a"})
	check(e.domination == 15 and not e.unit("zombie_a").alive,"sacrifice adds current HP plus soul return")
	check(e.unit("zombie_a_corpse").is_empty(),"sacrifice undead leaves no corpse")
	e = Rules.new(42)
	check(not e.validate_action({"kind":"SACRIFICE","target_unit_id":"spear_a"}).valid,"cannot sacrifice enemy")
	e.execute_action({"kind":"SACRIFICE","target_unit_id":"zombie_a"})
	check(e.domination == 20,"recovery capped")
	var replay = Rules.new(42)
	for a in e.history:
		replay.execute_action(a)
	check(JSON.stringify(e.get_observation()) == JSON.stringify(replay.get_observation()),"deterministic replay")
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	await process_frame
	battle.select_necromancer_skill(1)
	check(battle.mode == "FLESH_SHAPING" and not battle.board.highlighted.is_empty(),"skill menu targets undead")
	battle.try_target(battle.engine.pos(battle.engine.unit("vampire")),"FLESH_SHAPING")
	check(battle.engine.unit("vampire").max_hp == 30 and not battle.necromancer_menu.disabled,"UI keeps skill menu available after use")
	check(battle.necromancer_menu.get_popup().is_item_disabled(1) and not battle.necromancer_menu.get_popup().is_item_disabled(2),"paid skill disabled for resources but sacrifice available")
	battle.queue_free()
	await process_frame
	print("Necromancer failures: ",failures)
	quit(failures)
