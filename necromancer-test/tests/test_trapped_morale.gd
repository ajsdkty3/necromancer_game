extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func pass_round(e):
	e.execute_action({"kind":"END_TURN"})
	e.execute_action({"actor_id":"shield","kind":"END_UNIT"})
func _init():
	var e = Rules.new(42,9)
	var target = e.unit("shield")
	var center = e.pos(target)
	var zombies = e.units.filter(func(u): return u.archetype=="zombie")
	for index in 6:
		zombies[index].position = Hex.encode(center+Hex.DIRECTIONS[index])
	target.hp = 4
	e.refresh_morale()
	check(target.morale==0 and target.fleeing and target.flee_trapped,"complete encirclement traps demoralized unit")
	for round_index in 4:
		e.execute_action({"kind":"END_TURN"})
		check(e.enumerate_legal_actions("shield")==[{"actor_id":"shield","kind":"END_UNIT"}],"trapped unit cannot move or attack")
		e.execute_action({"actor_id":"shield","kind":"END_UNIT"})
		check(target.morale==0 and target.flee_trapped,"waiting cannot restore morale while surrounded")
	var occupied = zombies[0].position.duplicate()
	zombies[0].position = [0,0]
	e.refresh_morale()
	check(not target.flee_trapped and target.flee_until_round==e.round_number+1,"release starts fresh two-turn timer")
	pass_round(e)
	check(target.fleeing and target.morale==0,"first untrapped round does not rally")
	zombies[0].position = occupied
	e.refresh_morale()
	check(target.flee_trapped and target.flee_until_round==-1,"recapture discards previous escape progress")
	pass_round(e)
	check(target.morale==0,"old deadline cannot rally recaptured unit")
	zombies[0].position = [0,0]
	e.refresh_morale()
	pass_round(e)
	check(target.fleeing,"second release requires a fresh first round")
	pass_round(e)
	check(not target.fleeing and target.morale==20,"second release rallies after two rounds with five-enemy and low-HP penalties")
	print("TRAPPED MORALE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
