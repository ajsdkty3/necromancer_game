extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Policy = preload("res://scripts/ai/HeuristicPolicy.gd")
var failures = 0
var checks = 0
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr(message)
func fixture():
	var e = Rules.new(42,3)
	e.heights = {}
	for u in e.units:
		u.alive = false
	return e
func place(e, id: String, col: int, row: int, height: int):
	var u = e.unit(id)
	u.alive = true
	u.position = Hex.encode(Hex.from_offset(col,row))
	e.heights["%d,%d" % [col,row]] = height
func _init():
	for id in ["vampire","zombie_a","spear_a","shield","archer"]:
		for heights in [[0,2],[2,0],[0,1],[1,0],[2,2]]:
			var e = fixture()
			var target = "vampire" if e.unit(id).team == "human" else "spear_a"
			place(e,id,3,3,heights[0])
			place(e,target,4,3,heights[1])
			e.faction = e.unit(id).team
			if e.faction == "human":
				e.human_index = e.humans().find(e.unit(id))
			var permitted = id == "archer" or absi(heights[0]-heights[1])<=1
			var action = {"actor_id":id,"kind":e.definitions[e.unit(id).archetype].kind,"target_unit_id":target}
			check(e.validate_action(action).valid == permitted,"attack eligibility %s %s" % [id,heights])
			var hp = e.unit(target).hp
			var resource = e.resource(e.unit(id))
			e.execute_action(action)
			check((e.unit(target).hp<hp)==permitted,"actual hit %s" % id)
			if not permitted:
				check(e.resource(e.unit(id))==resource,"illegal attack costs nothing")
			if id != "archer":
				check((id in e.get_zone_controllers(e.pos(e.unit(target)),e.unit(target).team))==permitted,"reaction zone height")
	var e = fixture()
	place(e,"spear_a",3,3,0)
	place(e,"vampire",4,3,1)
	place(e,"zombie_a",5,3,2)
	e.faction = "human"
	check(e.attack_targets(e.unit("spear_a"),e.unit("vampire"))==["vampire"],"spear secondary target too high excluded")
	e.attack(e.unit("spear_a"),e.unit("vampire"),true)
	check(e.unit("zombie_a").hp==8,"reaction area respects each target height")
	e = fixture()
	place(e,"spear_a",3,3,0)
	place(e,"vampire",4,3,2)
	e.heights["5,3"] = 1
	e.faction = "human"
	var obs = e.get_observation()
	check(Hex.encode(e.pos(e.unit("vampire"))) not in obs.zones.spear_a,"display zone excludes unreachable height")
	var policy = Policy.new()
	check(not policy.has_clean_attack(obs,e.unit("spear_a"),e.pos(e.unit("spear_a"))),"AI cannot attack cliff")
	check(policy.choose_action(obs,e.enumerate_legal_actions("spear_a")).kind=="MOVE","AI repositions instead of holding impossible attack range")
	print("ATTACK HEIGHT RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
