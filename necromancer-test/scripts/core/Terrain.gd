extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const LIFT = 16.0

static func blocked(obstacles: Dictionary, cell: Vector2i) -> bool:
	var o = Hex.to_offset(cell)
	return bool(obstacles.get("%d,%d" % [o.x,o.y],false))

static func height_at(heights: Dictionary, cell: Vector2i) -> int:
	var o = Hex.to_offset(cell)
	return int(heights.get("%d,%d" % [o.x,o.y],0))

static func step_cost(heights: Dictionary, from: Vector2i, to: Vector2i, base: int = 1, width: int = 20, height: int = 10) -> int:
	if not Hex.inside(to,width,height) or Hex.distance(from,to) != 1:
		return -1
	var difference = absi(height_at(heights,from)-height_at(heights,to))
	return -1 if difference > 1 else base + difference

static func center(heights: Dictionary, cell: Vector2i) -> Vector2:
	return Hex.center(cell) - Vector2(0,height_at(heights,cell)*LIFT)

static func attack_height_allowed(heights: Dictionary, from: Vector2i, to: Vector2i, kind: String, obstacles: Dictionary = {}) -> bool:
	if kind == "SHOOT":
		return height_at(heights,to)-height_at(heights,from)<=2
	if kind == "SPEAR_THRUST":
		if blocked(obstacles,to):
			return false
		if Hex.distance(from,to) == 2:
			var clear = false
			# Straight attacks have one intermediate cell. Off-axis targets have
			# two shortest routes; either unblocked route permits the single hit.
			for direction in Hex.DIRECTIONS:
				var middle = from+direction
				if Hex.distance(middle,to) == 1 and not blocked(obstacles,middle) and height_at(heights,middle) <= height_at(heights,from):
					clear = true
			if not clear:
				return false
	return absi(height_at(heights,from)-height_at(heights,to)) <= 1
