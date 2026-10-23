extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const Board = preload("res://scripts/ui/HexBoardView.gd")
var failures = 0
var checks = 0
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr(message)
func fixture():
	var e = Rules.new(42)
	e.heights = {"3,3":1,"4,3":2,"5,3":0}
	for u in e.units:
		u.position = Hex.encode(Hex.from_offset(18,8))
	e.unit("vampire").position = Hex.encode(Hex.from_offset(2,3))
	return e
func _init():
	var e = fixture()
	var low = Hex.from_offset(2,3)
	var high = Hex.from_offset(3,3)
	check(Terrain.step_cost(e.heights,low,high)==2,"up costs 2")
	check(Terrain.step_cost(e.heights,high,low)==2,"down costs 2")
	check(Terrain.step_cost(e.heights,Hex.from_offset(4,3),Hex.from_offset(5,3))==-1,"cliff blocked")
	e.domination = 1
	check(high not in e.get_reachable_cells("vampire"),"insufficient climbing resource")
	e.domination = 2
	e.execute_action({"actor_id":"vampire","kind":"MOVE","target_cell":Hex.encode(high)})
	check(e.domination==0 and e.pos(e.unit("vampire"))==high,"uphill actual spend")
	e = fixture()
	e.domination = 6
	e.execute_action({"actor_id":"vampire","kind":"TELEPORT","target_cell":Hex.encode(Hex.from_offset(4,3))})
	check(e.domination==0 and e.pos(e.unit("vampire"))==Hex.from_offset(4,3),"teleport bypasses elevation")
	e = fixture()
	e.heights = {"3,3":2}
	var path = e.find_path("vampire",Hex.from_offset(4,3))
	check(path.size()>2 and high not in path,"path detours cliff")
	var previous = low
	for cell in path:
		check(Terrain.step_cost(e.heights,previous,cell)>0,"all route steps legal")
		previous = cell
	e = fixture()
	e.faction = "human"
	e.unit("spear_a").position = Hex.encode(low)
	e.unit("vampire").position = Hex.encode(Hex.from_offset(0,0))
	e.execute_action({"actor_id":"spear_a","kind":"MOVE","target_cell":Hex.encode(high)})
	check(e.unit("spear_a").ap==4,"human climbing costs 2 AP")
	var board = Board.new()
	board.observation = Rules.new().get_observation()
	for cell in Hex.cells():
		check(board.cell_at_point(board.surface_center(cell))==cell,"raised top center picking")
	board.free()
	print("TERRAIN RESULT: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
