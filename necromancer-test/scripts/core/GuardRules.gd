extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")

# One recipient per hit. Active guardians cannot themselves be protected.
static func protector(target: Dictionary, units: Array, definitions: Dictionary) -> Dictionary:
	if not target.alive or target.get("guarding",false):
		return {}
	for guardian in units:
		if not guardian.alive or guardian.id == target.id or guardian.team != target.team:
			continue
		var radius = int(definitions[guardian.archetype].get("guard_range",0))
		if guardian.get("guarding",false) and radius > 0 and Hex.distance(Hex.decode(guardian.position),Hex.decode(target.position)) <= radius:
			return guardian
	return {}
