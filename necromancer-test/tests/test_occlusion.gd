extends SceneTree
const Board = preload("res://scripts/ui/HexBoardView.gd")
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func _init():
	var e = Rules.new(42,8)
	e.heights = {}
	e.obstacles = {}
	e.unit("spear_a").position = Hex.encode(Hex.from_offset(10,4))
	var b = Board.new()
	b.observation = e.get_observation()
	check(not b.unit_is_occluded(e.unit("spear_a")),"flat foreground does not cover stationary unit")
	e.heights["10,5"] = 4
	b.observation = e.get_observation()
	check(b.unit_is_occluded(e.unit("spear_a")),"foreground high ground covers rear low unit")
	check(b.cell_at_point(b.surface_center(e.pos(e.unit("spear_a"))))==e.pos(e.unit("spear_a")),"occluded marker remains selectable")
	var items = b.depth_items()
	var unit_index = -1
	var terrain_index = -1
	for index in items.size():
		if items[index].kind=="unit" and items[index].unit.id=="spear_a":
			unit_index = index
		if items[index].kind=="terrain" and items[index].cell==Hex.from_offset(10,5):
			terrain_index = index
	check(unit_index>=0 and terrain_index>unit_index,"foreground terrain drawn after rear unit")
	e.heights = {"10,3":4}
	b.observation = e.get_observation()
	check(not b.unit_is_occluded(e.unit("spear_a")),"background mountain does not obscure foreground unit")
	b.free()
	print("OCCLUSION RESULT: %d failures" % failures)
	quit(1 if failures else 0)
