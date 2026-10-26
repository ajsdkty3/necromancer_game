extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const Policy = preload("res://scripts/ai/HeuristicPolicy.gd")
var failures = 0
var checks = 0
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr(message)
func _init():
	var e = Rules.new(42)
	e.heights = {}
	e.obstacles = {"4,4":true}
	var start = Hex.from_offset(3,4)
	var rock = Hex.from_offset(4,4)
	var destination = Hex.from_offset(5,4)
	e.unit("vampire").position = Hex.encode(start)
	check(rock not in e.get_reachable_cells("vampire"),"rock not reachable")
	var path = e.find_path("vampire",destination)
	check(path.size()>2 and rock not in path,"route detours around rock")
	for kind in ["MOVE","TELEPORT"]:
		var action = {"actor_id":"vampire","kind":kind,"target_cell":Hex.encode(rock)}
		check(not e.validate_action(action).valid,"cannot enter rock with "+kind)
		e.execute_action(action)
		check(e.domination==20 and e.pos(e.unit("vampire"))==start,"invalid action preserves resources and position")
	e.execute_action({"actor_id":"vampire","kind":"TELEPORT","target_cell":Hex.encode(destination)})
	check(e.domination==14 and e.pos(e.unit("vampire"))==destination,"teleport crosses rock to empty cell")
	var obs = e.get_observation()
	obs.board.obstacles.clear()
	check(Terrain.blocked(e.obstacles,rock),"observation cannot mutate obstacles")
	e.unit("vampire").position = Hex.encode(start)
	e.obstacles = {}
	for direction in Hex.DIRECTIONS:
		var offset = Hex.to_offset(start+direction)
		e.obstacles["%d,%d" % [offset.x,offset.y]] = true
	check(e.get_reachable_cells("vampire").is_empty(),"surrounded unit cannot walk through wall")
	e = Rules.new(42)
	e.heights = {}
	e.obstacles = {"4,4":true}
	e.faction = "human"
	e.unit("spear_a").position = Hex.encode(start)
	e.unit("vampire").position = Hex.encode(Hex.from_offset(7,4))
	e.unit("zombie_a").alive = false
	e.unit("zombie_b").alive = false
	var policy = Policy.new()
	var costs = policy.approach_costs(e.get_observation(),e.unit("spear_a"),[e.unit("vampire")])
	check(not costs.has(rock) and costs.has(start),"AI approach field excludes rock and finds detour")
	var action = policy.choose_action(e.get_observation(),e.enumerate_legal_actions("spear_a"))
	check(action.kind=="MOVE" and Hex.decode(action.target_cell)!=rock,"AI selects legal detour")
	for level in [1,2,3]:
		var initial = Rules.new(42,level)
		for u in initial.units:
			check(not Terrain.blocked(initial.obstacles,initial.pos(u)),"deployment not blocked")
	print("OBSTACLE RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
