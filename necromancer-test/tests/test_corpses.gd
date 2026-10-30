extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Board = preload("res://scripts/ui/HexBoardView.gd")
var failures = 0
var checks = 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL CORPSE: "+label)

func _init():
	var e = Rules.new(42,1)
	e.unit("vampire").position = [2,3]
	e.unit("spear_a").position = [3,3]
	var events = e.apply_damage("vampire","spear_a",100,"test")
	var corpse = e.unit("spear_a_corpse")
	check(not corpse.is_empty() and corpse.hp == 10 and corpse.max_hp == 10,"human leaves ten HP corpse")
	check(not e.unit("spear_a").alive and e.occupant(Vector2i(3,3)).id == corpse.id,"corpse occupies death cell")
	check(events.any(func(ev): return ev.type == "corpse_created"),"creation event")
	check(e.enumerate_legal_actions(corpse.id).is_empty() and e.get_reachable_cells(corpse.id).is_empty(),"corpse cannot act")
	check(not e.get_reachable_cells("vampire").has(Vector2i(3,3)),"corpse blocks walking")
	check(not e.validate_action({"actor_id":"vampire","kind":"TELEPORT","target_cell":[3,3]}).valid,"corpse blocks teleport landing")
	e.apply_stun(corpse)
	e.resolve_knockback(e.unit("vampire"),corpse)
	check(not corpse.stunned and corpse.position == [3,3],"corpse immune to stun and displacement")
	check(e.get_zone_controllers(Vector2i(2,3),"undead").all(func(u): return u.id != corpse.id),"corpse has no reactions")
	var attack = {"actor_id":"vampire","kind":"MELEE_ATTACK","target_unit_id":corpse.id}
	check(e.validate_action(attack).valid,"corpse targetable with ordinary attack")
	e.execute_action(attack)
	check(corpse.hp < 10 and corpse.hp > 0,"attack damages corpse")
	var deaths = e.human_deaths
	var domination = e.domination
	events = e.apply_damage("vampire",corpse.id,100,"test")
	check(not corpse.alive and e.occupant(Vector2i(3,3)).is_empty(),"destroying corpse frees cell")
	check(e.human_deaths == deaths and e.domination == domination,"destruction grants no death effects")
	check(events.any(func(ev): return ev.type == "corpse_destroyed") and not events.any(func(ev): return ev.type in ["death","corpse_created","morale_loss"]),"destruction not another death")
	e.apply_damage("spear_b","zombie_a",100,"test")
	check(e.unit("zombie_a_corpse").is_empty(),"undead leave no corpse")
	check(JSON.parse_string(JSON.stringify(e.get_observation())) != null,"corpse observation serializable")
	e = Rules.new(42,1)
	e.unit("spear_a").position = [3,3]
	e.unit("spear_b").position = [2,3]
	e.unit("vampire").position = [4,3]
	var before = e.get_observation()
	events = e.apply_damage("vampire","spear_a",100,"test")
	corpse = e.unit("spear_a_corpse")
	check(e.attack_targets(e.unit("spear_b"),e.unit("vampire")).has(corpse.id),"spear area includes corpse")
	var board = Board.new()
	board.play_events(events,before)
	check(board.visual_unit(corpse.id).is_empty(),"corpse appears after fatal hit animation")
	# Leave a final hit pending so the intermediate visual snapshot stays available.
	board.pending_events.append({"type":"damage","source":"vampire","target":corpse.id,"hp":9,"amount":1})
	board.advance_effect()
	check(board.visual_unit(corpse.id).alive and not board.visual_unit("spear_a").alive,"death animation replaced by corpse")
	board.stop_playback()
	board.free()
	e = Rules.new(42,1)
	for u in e.humans():
		e.apply_damage("vampire",u.id,100,"test")
	check(e.winner == "undead" and e.units.filter(func(u): return u.alive and u.get("is_corpse",false)).size() == 3,"corpses do not prevent victory")
	print("Corpse checks: %d, failures: %d" % [checks,failures])
	quit(failures)
