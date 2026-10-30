extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr(message)
func fixture(archetype: String):
	var e = Rules.new(42,1)
	var actor = e.unit("vampire")
	actor.archetype = archetype
	actor.hp = int(e.definitions[archetype].hp)
	actor.max_hp = actor.hp
	actor.position = [4,4]
	e.unit("spear_a").position = [5,4]
	e.heights = {"6,4":1}
	return e
func _init():
	for row in [["undead_spearman",7],["undead_archer",7],["undead_shieldman",15]]:
		var e = fixture(row[0])
		var actor = e.unit("vampire")
		check(actor.hp==row[1] and not actor.has("morale"),"undead HP and no morale")
		var d = e.definitions[row[0]]
		var original = e.definitions[row[0].trim_prefix("undead_")]
		check(d.damage_min==original.damage_min and d.damage_max==original.damage_max,"original human damage range")
		var expected_rng = RandomNumberGenerator.new()
		expected_rng.seed = 42
		var expected_damage = expected_rng.randi_range(int(original.damage_min),int(original.damage_max))
		var before = e.domination
		e.execute_action({"actor_id":actor.id,"kind":d.kind,"target_unit_id":"spear_a"})
		check(e.unit("spear_a").hp==14-expected_damage,"ordinary damage retains original roll")
		check(e.domination==before-int(d.cost),"uses shared domination")
		e = fixture(row[0])
		var special = "KNOCKBACK" if row[0]=="undead_spearman" else "OVERHEAD_STRIKE"
		var action = {"actor_id":"vampire","kind":special,"target_unit_id":"spear_a"}
		check(e.validate_action(action).valid,"advantage available on high ground")
		e.execute_action(action)
		check(e.unit("spear_a").hp==14-(2 if row[0]=="undead_spearman" else (6 if row[0]=="undead_archer" else 1)),"original special damage")
		e = fixture(row[0])
		e.attack(e.unit("vampire"),e.unit("spear_a"),true)
		check(e.unit("spear_a").hp==14-expected_damage,"reaction retains original roll")
	var e = fixture("undead_spearman")
	e.heights = {"6,4":2,"7,4":1}
	var events = e.execute_action({"actor_id":"vampire","kind":"KNOCKBACK","target_unit_id":"spear_a"})
	check(e.unit("spear_a").hp==10,"two shove plus two fall damage")
	check(events.filter(func(event): return event.type=="damage").size()==2,"fall is separate hit")
	e = fixture("undead_shieldman")
	e.unit("zombie_a").position = [4,3]
	e.execute_action({"actor_id":"vampire","kind":"GUARD"})
	e.apply_damage("spear_a","zombie_a",3,"test")
	check(e.unit("zombie_a").hp==10 and e.unit("vampire").hp==12,"undead guardian transfers full incoming damage")
	e.execute_action({"kind":"END_TURN"})
	check(e.unit("vampire").guarding,"undead guard survives enemy turn start")
	while e.faction=="human":
		e.execute_action({"actor_id":e.active_human(),"kind":"END_UNIT"})
	check(not e.unit("vampire").guarding,"undead guard expires at own next turn")
	print("Undead variants: %d failures" % failures)
	quit(1 if failures else 0)
