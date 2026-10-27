extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")

static func landing(actor: Vector2i, target: Vector2i, board: Dictionary, units: Array) -> Dictionary:
	var away = (Hex.center(target)-Hex.center(actor)).normalized()
	var direction = Hex.DIRECTIONS[0]
	var best = -2.0
	for candidate in Hex.DIRECTIONS:
		var score = away.dot((Hex.center(target+candidate)-Hex.center(target)).normalized())
		if score > best+0.00001:
			best = score
			direction = candidate
	var destination = target+direction
	var heights = board.get("heights",{})
	var blocked = not Hex.inside(destination,int(board.width),int(board.height)) or Terrain.blocked(board.get("obstacles",{}),destination) or Terrain.height_at(heights,destination)>Terrain.height_at(heights,target)
	blocked = blocked or units.any(func(u): return u.alive and Hex.decode(u.position)==destination)
	return {"cell":destination,"blocked":blocked,"fall":0 if blocked else 2*maxi(0,Terrain.height_at(heights,target)-Terrain.height_at(heights,destination))}
