extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")

static func adjacent_enemies(unit: Dictionary, units: Array) -> int:
	if not unit.has("position"):
		return 0
	var count = 0
	for other in units:
		if other.alive and other.team != unit.team and Hex.distance(Hex.decode(unit.position),Hex.decode(other.position))==1:
			count += 1
	return count

# State penalties are recomputed, not accumulated on repeated checks.
static func penalties(unit: Dictionary, initial_count: int, deaths: int, units: Array = []) -> int:
	if unit.team != "human":
		return 0
	var loss = 20 if int(unit.hp)*5 <= int(unit.max_hp) else 0
	if deaths*2 > initial_count:
		loss += 20
	var enemies = adjacent_enemies(unit,units)
	if enemies >= 3:
		loss += 20
	if enemies >= 5:
		loss += 20
	if enemies >= 6:
		loss += 40
	return loss

static func value(unit: Dictionary, initial_count: int, deaths: int, units: Array = []) -> int:
	return clampi(int(unit.get("morale_base",100))-penalties(unit,initial_count,deaths,units),0,100)
