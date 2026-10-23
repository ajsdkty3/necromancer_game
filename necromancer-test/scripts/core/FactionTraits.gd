extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")

static func damage_bonus(source: Dictionary, units: Array) -> int:
	if source.is_empty() or not source.alive or source.team != "human":
		return 0
	var count = 0
	for ally in units:
		if ally.alive and ally.team == "human" and ally.id != source.id and Hex.distance(Hex.decode(ally.position),Hex.decode(source.position)) == 1:
			count += 1
	return count
