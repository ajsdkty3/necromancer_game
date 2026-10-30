extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")

static func damage_bonus(source: Dictionary, units: Array) -> int:
	if source.is_empty() or not source.alive or source.get("is_corpse",false):
		return 0
	var count = 0
	for ally in units:
		if source.team == "human" and ally.alive and ally.team == "human" and ally.id != source.id and Hex.distance(Hex.decode(ally.position),Hex.decode(source.position)) == 1:
			count += 1
	for ally in units:
		if ally.alive and ally.team == source.team and ally.id != source.id and ally.get("battle_order",false) and not ally.get("fleeing",false) and Hex.distance(Hex.decode(ally.position),Hex.decode(source.position)) == 1:
			count += 1
			break
	return count
