extends SceneTree
const Morale = preload("res://scripts/core/MoraleRules.gd")
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const AI = preload("res://scripts/ai/AIController.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func _init():
	var u = {"team":"human","hp":10,"max_hp":10,"morale_base":100}
	check(Morale.value(u,8,0)==100,"initial morale")
	u.hp = 2
	check(Morale.value(u,8,4)==80,"exactly twenty percent HP incurs penalty; exactly half losses do not")
	u.hp = 3
	check(Morale.value(u,8,4)==100,"above twenty percent HP clears penalty")
	u.hp = 1
	check(Morale.value(u,8,4)==80,"low HP penalty")
	check(Morale.value(u,8,5)==60,"low HP and majority losses stack")
	check(Morale.value(u,8,5)==60,"rechecking state does not accumulate penalty")
	u.hp = 3
	check(Morale.value(u,8,5)==80,"healing clears low HP penalty")
	u.morale_base -= 40
	check(Morale.value(u,8,5)==40,"two nearby deaths remain cumulative")
	var e = Rules.new(42,7)
	check(not e.unit("vampire").has("morale") and e.humans().all(func(h): return h.morale==100),"humans only start with morale")
	e.unit("spear_a").position = [0,0]
	e.unit("spear_b").position = [1,0]
	e.apply_damage("vampire","spear_b",100,"test")
	check(e.human_deaths==1 and e.unit("spear_a").morale==80,"nearby death permanently costs twenty")
	e.refresh_morale()
	check(e.unit("spear_a").morale==80,"death does not trigger twice")
	e.unit("spear_a").hp = 1
	e.refresh_morale()
	check(e.unit("spear_a").morale==60,"low health state added")
	e.unit("spear_a").hp = 10
	e.refresh_morale()
	check(e.unit("spear_a").morale==80,"healed state removed but death loss retained")
	# A blocked right edge forces both fleeing turns to elapse.
	e = Rules.new(42,8)
	e.heights = {}
	e.obstacles = {}
	for row in 10:
		e.obstacles["19,%d" % row] = true
	e.unit("spear_a").hp = 1
	e.unit("spear_a").morale_base = 20
	e.unit("spear_a").guarding = true
	e.refresh_morale()
	check(e.unit("spear_a").fleeing and not e.unit("spear_a").guarding and not e.unit("spear_a").reaction_ready,"panic clears guard and reaction")
	for turn in 2:
		e.execute_action({"kind":"END_TURN"})
		var choices = e.enumerate_legal_actions("spear_a")
		check(choices.size()==1 and choices[0].kind=="END_UNIT","no reachable exit means no attacks")
		e.execute_action(choices[0])
		check(e.unit("spear_a").fleeing==(turn<1),"flee expires after exactly two human phases")
	check(e.unit("spear_a").morale==60,"rally base eighty minus low health penalty")
	e.unit("spear_a").hp = 10
	e.refresh_morale()
	check(e.unit("spear_a").morale==80,"healing restores morale to rally base eighty")
	for low_hp in [false,true]:
		for majority_lost in [false,true]:
			var recovered = Rules.new(42,7)
			var soldier = recovered.unit("spear_a")
			soldier.hp = 1 if low_hp else 10
			recovered.human_deaths = 5 if majority_lost else 0
			soldier.morale_base = 0
			soldier.morale = 0
			soldier.fleeing = true
			soldier.flee_until_round = recovered.round_number
			recovered.finish_flee_round()
			var expected = 80-(20 if low_hp else 0)-(20 if majority_lost else 0)
			check(soldier.morale==expected and soldier.morale_base==80,"rally state penalty combinations yield eighty sixty or forty")
			recovered.refresh_morale()
			check(soldier.morale==expected,"rally penalties not applied twice on refresh")
	# Escaping is not a death and clears the last enemy from the field.
	e = Rules.new(42,8)
	e.heights = {}
	e.obstacles = {}
	e.unit("spear_a").position = Hex.encode(Hex.from_offset(18,4))
	e.unit("spear_a").morale_base = 0
	e.refresh_morale()
	var goal = e.unit("spear_a").flee_target.duplicate()
	e.refresh_morale()
	check(e.unit("spear_a").flee_target==goal,"random exit remains stable across repeated observations")
	e.execute_action({"kind":"END_TURN"})
	var ai = AI.new()
	var calls = 0
	while not e.is_terminal() and e.faction=="human" and calls<20:
		var action = ai.choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a"))
		check(action.kind in ["MOVE","END_UNIT"],"flee AI only moves or ends")
		e.execute_action(action)
		calls += 1
	check(e.unit("spear_a").escaped and e.human_deaths==0 and e.winner=="undead","right edge escape produces victory without death")
	e = Rules.new(42,7)
	for h in e.humans():
		h.position = [5,3]
	for id in ["spear_b","spear_c","spear_d","archer","archer_b"]:
		e.apply_damage("vampire",id,100,"test")
	check(e.human_deaths==5 and e.unit("spear_a").morale==0 and e.unit("spear_a").fleeing,"actual nearby deaths trigger panic and majority state")
	var rng_before = e.rng.state
	e.get_observation()
	e.get_observation()
	check(e.rng.state==rng_before,"reading observations does not reroll escape destinations")
	# The extended test map allows a living unit to flee and then resume combat.
	e = Rules.new(42,9)
	e.unit("shield").morale_base = 0
	e.refresh_morale()
	for turn in 2:
		e.execute_action({"kind":"END_TURN"})
		var decisions = 0
		while e.faction=="human" and not e.is_terminal() and decisions<20:
			e.execute_action(ai.choose_action(e.get_observation(),e.enumerate_legal_actions("shield")))
			decisions += 1
	check(e.unit("shield").alive and not e.unit("shield").escaped and not e.unit("shield").fleeing,"extended map lets fleeing shield rally before exit")
	check(e.unit("shield").morale==80,"unpenalized shield rallies at eighty")
	print("MORALE RESULT: %d failures" % failures)
	quit(1 if failures else 0)
