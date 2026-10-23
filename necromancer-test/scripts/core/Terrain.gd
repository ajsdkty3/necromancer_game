extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const LIFT = 16.0

static func height_at(heights: Dictionary, cell: Vector2i) -> int:
	var o = Hex.to_offset(cell)
	return int(heights.get("%d,%d" % [o.x,o.y],0))

static func step_cost(heights: Dictionary, from: Vector2i, to: Vector2i, base: int = 1) -> int:
	if not Hex.inside(to) or Hex.distance(from,to) != 1:
		return -1
	var difference = absi(height_at(heights,from)-height_at(heights,to))
	return -1 if difference > 1 else base + difference

static func center(heights: Dictionary, cell: Vector2i) -> Vector2:
	return Hex.center(cell) - Vector2(0,height_at(heights,cell)*LIFT)

static func attack_height_allowed(heights: Dictionary, from: Vector2i, to: Vector2i, kind: String) -> bool:
	return kind == "SHOOT" or absi(height_at(heights,from)-height_at(heights,to)) <= 1
