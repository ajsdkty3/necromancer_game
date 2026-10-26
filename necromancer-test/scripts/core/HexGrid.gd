extends RefCounted

const DIRECTIONS = [Vector2i(1,0), Vector2i(1,-1), Vector2i(0,-1), Vector2i(-1,0), Vector2i(-1,1), Vector2i(0,1)]
const SIZE = 34.0

static func from_offset(col: int, row: int) -> Vector2i:
	return Vector2i(col - (row - (row & 1)) / 2, row)

static func to_offset(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x + (cell.y - (cell.y & 1)) / 2, cell.y)

static func inside(cell: Vector2i, width: int = 20, height: int = 10) -> bool:
	var o = to_offset(cell)
	return o.x >= 0 and o.x < width and o.y >= 0 and o.y < height

static func cells(width: int = 20, height: int = 10) -> Array:
	var result = []
	for row in height:
		for col in width:
			result.append(from_offset(col, row))
	return result

static func distance(a: Vector2i, b: Vector2i) -> int:
	var d = a - b
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2

static func center(cell: Vector2i) -> Vector2:
	return Vector2(sqrt(3.0) * SIZE * (cell.x + cell.y * 0.5), SIZE * 1.5 * cell.y)

static func at_point(point: Vector2) -> Vector2i:
	var q = (sqrt(3.0) / 3.0 * point.x - point.y / 3.0) / SIZE
	var r = point.y * 2.0 / 3.0 / SIZE
	var x = roundi(q)
	var z = roundi(r)
	var y = roundi(-q-r)
	if abs(x-q) > abs(y+q+r) and abs(x-q) > abs(z-r):
		x = -y-z
	elif abs(z-r) > abs(y+q+r):
		z = -x-y
	return Vector2i(x,z)

static func encode(cell: Vector2i) -> Array:
	return [cell.x, cell.y]

static func decode(value) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))
