extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const Traits = preload("res://scripts/core/FactionTraits.gd")
const VALUES = {"vampire":10,"zombie":3}

# Rebuild from the remaining team each decision. Conservative minimum damage
# avoids promising a kill that requires lucky rolls. No rule state is modified.
func plan(observation: Dictionary) -> Dictionary:
	var humans = observation.units.filter(func(u): return u.team == "human")
	var best = {}
	for target in observation.units:
		if not target.alive or target.team == "human":
			continue
		var total = 0
		var contributors = {}
		for index in range(int(observation.human_index),humans.size()):
			var actor = humans[index]
			if not actor.alive or actor.get("guarding",false):
				continue
			var damage = potential_damage(observation,actor,target)
			if damage > 0:
				contributors[actor.id] = damage
				total += damage
		if total < int(target.hp):
			continue
		var value = int(VALUES.get(target.archetype,1))
		if best.is_empty() or value > best.value or (value == best.value and int(target.hp) < best.hp):
			best = {"target_id":target.id,"value":value,"hp":int(target.hp),"damage":total,"contributors":contributors}
	return best

func potential_damage(o: Dictionary, actor: Dictionary, target: Dictionary) -> int:
	var d = o.definitions[actor.archetype]
	var budget = int(actor.ap)-int(d.cost)
	if budget < 0:
		return 0
	var start = Hex.decode(actor.position)
	var target_cell = Hex.decode(target.position)
	var heights = o.board.get("heights",{})
	var occupied = {}
	for u in o.units:
		if u.alive and u.id != actor.id:
			occupied[Hex.decode(u.position)] = true
	var costs = {start:0}
	var queue = [start]
	var head = 0
	var best = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if Hex.distance(cell,target_cell) <= int(d.range) and Terrain.attack_height_allowed(heights,cell,target_cell,d.kind):
			var overhead = Terrain.height_at(heights,cell)>Terrain.height_at(heights,target_cell)
			if clean_shot(o,actor,cell,target_cell,overhead):
				var preview = o.units.duplicate(true)
				var moved = actor.duplicate(true)
				moved.position = Hex.encode(cell)
				for u in preview:
					if u.id == actor.id:
						u.position = moved.position
				var damage = (int(d.damage_min)+Traits.damage_bonus(moved,preview))*(2 if overhead else 1)
				best = maxi(best,int((int(actor.ap)-costs[cell])/int(d.cost))*damage)
		# Do not budget a route that requires taking reaction damage.
		var threatened = false
		for enemy in o.units:
			var ed = o.definitions[enemy.archetype]
			if enemy.alive and enemy.team != actor.team and enemy.get("reaction_ready",true) and int(ed.zoc)>0 and Hex.distance(cell,Hex.decode(enemy.position))<=int(ed.zoc) and Terrain.attack_height_allowed(heights,Hex.decode(enemy.position),cell,ed.kind):
				threatened = true
		if threatened:
			continue
		for direction in Hex.DIRECTIONS:
			var next = cell+direction
			var cost = Terrain.step_cost(heights,cell,next,int(d.move_cost),int(o.board.width),int(o.board.height))
			if cost<0 or occupied.has(next) or Terrain.blocked(o.board.get("obstacles",{}),next):
				continue
			var total = costs[cell]+cost
			if total<=budget and (not costs.has(next) or total<costs[next]):
				costs[next] = total
				queue.append(next)
	return best

func clean_shot(o: Dictionary, actor: Dictionary, cell: Vector2i, target: Vector2i, overhead: bool) -> bool:
	var d = o.definitions[actor.archetype]
	if d.target_shape != "spear":
		return true
	var heights = o.board.get("heights",{})
	for direction in Hex.DIRECTIONS:
		if target not in [cell+direction,cell+direction*2]:
			continue
		for ally in o.units:
			var position = Hex.decode(ally.position)
			if ally.alive and ally.team==actor.team and ally.id!=actor.id and position in [cell+direction,cell+direction*2] and Terrain.attack_height_allowed(heights,cell,position,d.kind) and (not overhead or Terrain.height_at(heights,cell)>Terrain.height_at(heights,position)):
				return false
	return true
