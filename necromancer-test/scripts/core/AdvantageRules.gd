extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")

# The acting unit counts as an ally surrounding an enemy. A hypothetical
# position replaces its current cell when evaluating AI movement candidates.
static func qualifies(actor: Dictionary, target: Dictionary, from: Vector2i, heights: Dictionary, units: Array) -> bool:
	var target_cell = Hex.decode(target.position)
	if Terrain.height_at(heights,from)>Terrain.height_at(heights,target_cell):
		return true
	if target.team==actor.team:
		return false
	var count = 0
	for ally in units:
		if not ally.alive or ally.team!=actor.team:
			continue
		var cell = from if ally.id==actor.id else Hex.decode(ally.position)
		if Hex.distance(cell,target_cell)==1:
			count += 1
	return count>=3
