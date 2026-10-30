extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Traits = preload("res://scripts/core/FactionTraits.gd")
const Policy = preload("res://scripts/ai/AIController.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr("FAIL COMMANDER: "+label)
func _initialize():
	call_deferred("run")
func fixture():
	var e = Rules.new(42,14)
	e.domination = 20 # Fixed skill-cost fixture, independent of level starting resources.
	# Isolate geometry without altering deployment order or unit count.
	e.unit("l14_undead_5").position = [5,4]
	e.unit("l14_undead_1").position = [4,4]
	e.unit("l14_undead_2").position = [5,3]
	e.unit("l14_human_4").position = [6,4]
	e.heights = {}
	return e
func run():
	var e = fixture()
	var c = e.unit("l14_undead_5")
	check(c.hp == 5 and e.unit("l14_human_0").hp == 10 and e.unit("l14_human_0").ap == 6,"commander stats")
	check(e.units.size() == 20 and e.units.filter(func(u): return u.team=="undead").size() == 10,"level fourteen rosters")
	var order = {"actor_id":c.id,"kind":"BATTLE_ORDER"}
	check(e.validate_action(order).valid,"order legal")
	e.execute_action(order)
	check(e.domination == 14 and c.battle_order,"order costs six")
	check(Traits.damage_bonus(e.unit("l14_undead_1"),e.units)==1 and Traits.damage_bonus(c,e.units)==0,"adjacent ally gains one, caster excluded")
	check(not e.validate_action(order).valid,"active order cannot be repeatedly cast")
	var other = c.duplicate(true)
	other.id = "second_commander"
	other.position = [4,3]
	e.units.append(other)
	check(Traits.damage_bonus(e.unit("l14_undead_1"),e.units)==1,"multiple orders do not stack")
	other.alive = false
	c.position = [8,4]
	check(Traits.damage_bonus(e.unit("l14_undead_1"),e.units)==0,"aura follows caster")
	c.position = [5,4]
	var mark = {"actor_id":c.id,"kind":"OVERHEAD_STRIKE","target_unit_id":"l14_human_4"}
	check(not e.validate_action(mark).valid,"mark requires advantage")
	e.heights["7,4"] = 1 # axial 5,4 -> offset 7,4
	check(e.validate_action(mark).valid,"height enables mark")
	var target = e.unit("l14_human_4")
	var hp = target.hp
	e.execute_action(mark)
	check(target.hp == hp-1 and target.vulnerable and e.domination == 8,"first damage precedes vulnerability; costs six")
	e.apply_damage(c.id,target.id,3,"fall",1,false)
	check(target.hp == hp-6,"all damage increased fifty percent rounded upward")
	e.apply_damage(c.id,target.id,2,"test",1,false)
	check(target.hp == hp-9,"even damage exact fifty percent")
	e.execute_action({"kind":"END_TURN"})
	check(c.battle_order and target.vulnerable,"undead effects survive human turn start")
	while e.faction == "human":
		e.execute_action({"actor_id":e.active_human(),"kind":"END_UNIT"})
	check(not c.battle_order and not target.vulnerable,"effects expire at caster faction start")
	e = fixture()
	c = e.unit("l14_undead_5")
	target = e.unit("l14_human_4")
	var shield = e.unit("l14_human_2")
	shield.position = [6,3]
	shield.guarding = true
	target.vulnerable = true
	shield.vulnerable = true
	e.apply_damage(c.id,target.id,3,"test",1,false)
	check(shield.hp == 25 and target.hp == 14,"guard recipient vulnerability applies once, no double multiplier")
	e.apply_damage(c.id,shield.id,100,"test",1,false)
	var corpse = e.unit(shield.id+"_corpse")
	check(not corpse.get("vulnerable",false),"corpse does not inherit vulnerability")
	check(e.get_zone_controllers(e.pos(c)+Vector2i(1,0),"human").all(func(id): return id != c.id),"commander has no control zone")
	e = fixture()
	c = e.unit("l14_undead_5")
	e.heights["7,4"] = 1
	mark.actor_id = c.id
	e.execute_action(mark)
	e.execute_action(mark)
	target = e.unit(mark.target_unit_id)
	check(target.hp == 11,"repeated mark damage uses existing vulnerability without stacking")
	e.apply_damage(c.id,target.id,2,"test",1,false)
	check(target.hp == 8,"repeated vulnerability remains fifty percent")
	e = fixture()
	e.execute_action({"kind":"END_TURN"})
	while e.active_human() != "l14_human_0":
		e.execute_action({"actor_id":e.active_human(),"kind":"END_UNIT"})
	var human = e.unit(e.active_human())
	var choice = Policy.new().choose_action(e.get_observation(),e.enumerate_legal_actions(human.id))
	check(choice.kind == "BATTLE_ORDER","AI uses support order")
	e.execute_action(choice)
	check(human.ap == 0 and human.battle_order,"human order uses six AP")
	e = fixture()
	e.execute_action({"kind":"END_TURN"})
	while e.active_human() != "l14_human_0":
		e.execute_action({"actor_id":e.active_human(),"kind":"END_UNIT"})
	human = e.unit(e.active_human())
	human.position = [5,4]
	e.unit("l14_undead_1").position = [0,0]
	e.unit("l14_undead_2").position = [1,0]
	e.unit("l14_undead_5").position = [6,4]
	e.unit("l14_human_4").position = [12,4]
	# No combat ally needs support in this isolated offensive-choice case.
	for id in ["l14_human_4","l14_human_5","l14_human_6","l14_human_7","l14_human_8","l14_human_9"]:
		e.unit(id).alive = false
	e.heights["7,4"] = 1
	choice = Policy.new().choose_action(e.get_observation(),e.enumerate_legal_actions(human.id))
	check(choice.kind == "OVERHEAD_STRIKE" and choice.target_unit_id == "l14_undead_5","AI marks an enemy when advantage is available")
	e.execute_action(choice)
	check(e.unit("l14_undead_5").get("vulnerable",false),"human mark applied")
	while e.faction == "human":
		e.execute_action({"actor_id":e.active_human(),"kind":"END_UNIT"})
	check(e.unit("l14_undead_5").get("vulnerable",false),"human mark persists during undead phase")
	e.execute_action({"kind":"END_TURN"})
	check(not e.unit("l14_undead_5").get("vulnerable",false),"human mark expires next human phase")
	var replay = Rules.new(42,14)
	var original = Rules.new(42,14)
	original.execute_action({"actor_id":"l14_undead_5","kind":"BATTLE_ORDER"})
	for action in original.history:
		replay.execute_action(action)
	check(JSON.stringify(original.get_observation()) == JSON.stringify(replay.get_observation()),"effects replay")
	var battle = load("res://scenes/Battle.tscn").instantiate()
	root.add_child(battle)
	await process_frame
	battle.select_level(14)
	battle.selected = "l14_undead_5"
	battle.refresh()
	battle.actions.get_child(1).pressed.emit()
	check(battle.engine.unit(battle.selected).get("battle_order",false),"UI activates order directly")
	check(battle.board.guard_zones(true).size() == 1,"persistent colored aura")
	battle.queue_free()
	await process_frame
	print("Commander failures: ",failures)
	quit(failures)
