extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")

static func targets(actor: Dictionary, start: Vector2i, endpoint: Vector2i, board: Dictionary, units: Array) -> Array:
	return units.filter(func(u): return u.alive and u.id!=actor.id and target_in_direction(start,endpoint,Hex.decode(u.position)) and Terrain.attack_height_allowed(board.heights,endpoint,Hex.decode(u.position),"CHARGE"))

static func target_in_direction(start: Vector2i, endpoint: Vector2i, target: Vector2i) -> bool:
	if start == endpoint:
		return Hex.distance(start,target)==1
	for index in Hex.DIRECTIONS.size():
		var direction = Hex.DIRECTIONS[index]
		for distance in range(1,Hex.distance(start,endpoint)+1):
			if endpoint==start+direction*distance:
				return target-endpoint in [direction,Hex.DIRECTIONS[(index+1)%6],Hex.DIRECTIONS[(index+5)%6]]
	return false

# Every endpoint has one straight, unobstructed path. No resource or state mutation.
static func paths(actor: Dictionary, board: Dictionary, units: Array, radius: int) -> Dictionary:
	var start = Hex.decode(actor.position)
	var result = {}
	for direction in Hex.DIRECTIONS:
		var path = []
		var previous = start
		for distance in range(1,radius+1):
			var cell = start+direction*distance
			if Terrain.step_cost(board.heights,previous,cell,1,int(board.width),int(board.height))<0 or Terrain.blocked(board.obstacles,cell):
				break
			if units.any(func(u): return u.alive and u.id!=actor.id and Hex.decode(u.position)==cell):
				break
			path.append(cell)
			if distance == radius:
				result[cell] = path.duplicate()
			previous = cell
	return result
