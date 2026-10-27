extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")

static func tree(start: Vector2i, board: Dictionary, units: Array, actor_id: String, move_cost: int) -> Dictionary:
	var occupied = {}
	for u in units:
		if u.alive and u.id != actor_id:
			occupied[Hex.decode(u.position)] = true
	var result = {start:{"cost":0,"path":[]}}
	var queue = [start]
	var head = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for direction in Hex.DIRECTIONS:
			var next = cell+direction
			var cost = Terrain.step_cost(board.heights,cell,next,move_cost,int(board.width),int(board.height))
			if cost < 0 or occupied.has(next) or Terrain.blocked(board.obstacles,next):
				continue
			var total = result[cell].cost+cost
			if result.has(next) and result[next].cost<=total:
				continue
			var path = result[cell].path.duplicate()
			path.append(next)
			result[next] = {"cost":total,"path":path}
			queue.append(next)
	return result
