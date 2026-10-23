extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const Guard = preload("res://scripts/core/GuardRules.gd")
const Traits = preload("res://scripts/core/FactionTraits.gd")

func choose_action(observation: Dictionary, legal_actions: Array) -> Dictionary:
	if legal_actions.is_empty():
		return {}
	var actor = {}
	for u in observation.units:
		if u.id == legal_actions[0].actor_id:
			actor = u
	var enemies = observation.units.filter(func(u): return u.alive and u.team != actor.team)
	var best = legal_actions.back()
	var best_score = 0.0
	var best_single_hp = -1
	var start = Hex.decode(actor.position)
	var nearest = 999
	for enemy in enemies:
		nearest = mini(nearest,Hex.distance(start,Hex.decode(enemy.position)))
	var enemy_in_range = enemies.any(func(e): return Hex.distance(start,Hex.decode(e.position)) <= int(observation.definitions[actor.archetype].range) and height_allowed(observation,actor,start,Hex.decode(e.position)))
	var approach = approach_costs(observation,actor,enemies) if not enemy_in_range else {}
	var guard_range = int(observation.definitions[actor.archetype].get("guard_range",0))
	if guard_range > 0 and actor.get("guarding",false):
		var support_move = choose_guard_move(observation,legal_actions,actor)
		if not support_move.is_empty():
			return support_move
	if observation.definitions[actor.archetype].target_shape == "spear" and enemy_in_range:
		if not has_clean_attack(observation,actor,start):
			var reposition = choose_spear_reposition(observation,legal_actions,actor)
			if not reposition.is_empty():
				return reposition
	for action in legal_actions:
		var score = -1000.0
		var single_hp = -1
		if action.kind == "GUARD":
			score = 0.0
			for ally in observation.units:
				if not ally.alive or ally.id == actor.id or ally.team != actor.team or ally.get("guarding",false):
					continue
				if Hex.distance(start,Hex.decode(ally.position)) > guard_range:
					continue
				if not Guard.protector(ally,observation.units,observation.definitions).is_empty():
					continue
				var threatened = enemies.any(func(enemy): return Hex.distance(Hex.decode(enemy.position),Hex.decode(ally.position)) <= int(observation.definitions[enemy.archetype].range)+3)
				if threatened:
					score += 35.0
			score = minf(score,65.0)
		elif action.kind == "MOVE":
			if actor.get("guarding",false):
				continue
			# Hold attack range even when remaining AP cannot pay for another attack.
			if enemy_in_range:
				continue
			var destination = Hex.decode(action.target_cell)
			var next_distance = 999
			for enemy in enemies:
				next_distance = mini(next_distance,Hex.distance(destination,Hex.decode(enemy.position)))
			# One adjacent step per decision allows a fresh observation after every move.
			if Hex.distance(start,destination) != 1:
				continue
			if Terrain.step_cost(observation.board.get("heights",{}),start,destination,int(observation.definitions[actor.archetype].move_cost)) < 0:
				continue
			if not approach.has(start) or not approach.has(destination):
				continue
			score = float(approach[start]-approach[destination]) * 5.0 - 0.1
			if guard_range > 0 and not actor.get("guarding",false):
				for ally in observation.units:
					if ally.alive and ally.team == actor.team and ally.id != actor.id and not ally.get("guarding",false):
						if Hex.distance(destination,Hex.decode(ally.position)) <= guard_range:
							score += 1.5
			for enemy in enemies:
				var radius = int(observation.definitions[enemy.archetype].zoc)
				if radius > 0 and Hex.distance(start,Hex.decode(enemy.position)) <= radius and height_allowed(observation,enemy,Hex.decode(enemy.position),start):
					score -= 12.0
		elif action.has("target_unit_id"):
			var target = {}
			for u in observation.units:
				if u.id == action.target_unit_id:
					target = u
			var d = observation.definitions[actor.archetype]
			var hits = [target]
			if d.target_shape == "spear":
				for direction in Hex.DIRECTIONS:
					if Hex.decode(target.position) in [start+direction,start+direction*2]:
						hits = observation.units.filter(func(u): return u.alive and Hex.decode(u.position) in [start+direction,start+direction*2] and height_allowed(observation,actor,start,Hex.decode(u.position)))
						break
			score = 0.0
			if hits.size() == 1 and target.team != actor.team:
				single_hp = int(target.hp)
			for hit in hits:
				var guardian = Guard.protector(hit,observation.units,observation.definitions)
				var receiver = hit if guardian.is_empty() else guardian
				var bonus = Traits.damage_bonus(actor,observation.units)
				if hit.team == actor.team:
					score -= 100.0
				else:
					score += 20.0
					if receiver.hp <= int(d.damage_min)+bonus:
						score += 70.0
					elif receiver.hp <= int(d.damage_max)+bonus:
						score += 15.0
		# Fixed damage makes kill tiers monotonic in HP; break single-hit ties by
		# current absolute HP, never percentage. Area/friendly-fire scores stay intact.
		var lower_single_hp = score == best_score and single_hp >= 0 and best_single_hp >= 0 and single_hp < best_single_hp
		if score > best_score or lower_single_hp:
			best_score = score
			best_single_hp = single_hp
			best = action
	return best.duplicate(true)

# Distance to an empty firing position, including terrain costs and occupied cells.
func approach_costs(observation: Dictionary, actor: Dictionary, enemies: Array) -> Dictionary:
	var blocked = {}
	for u in observation.units:
		if u.alive and u.id != actor.id:
			blocked[Hex.decode(u.position)] = true
	var distances = {}
	var queue = []
	var radius = int(observation.definitions[actor.archetype].range)
	for cell in Hex.cells():
		if not blocked.has(cell) and enemies.any(func(e): return Hex.distance(cell,Hex.decode(e.position)) <= radius and height_allowed(observation,actor,cell,Hex.decode(e.position))):
			distances[cell] = 0
			queue.append(cell)
	var head = 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for direction in Hex.DIRECTIONS:
			var next: Vector2i = cell+direction
			var cost = Terrain.step_cost(observation.board.get("heights",{}),cell,next,int(observation.definitions[actor.archetype].move_cost))
			if cost < 0 or blocked.has(next):
				continue
			var total = distances[cell]+cost
			if not distances.has(next) or total < distances[next]:
				distances[next] = total
				queue.append(next)
	return distances

func has_clean_attack(observation: Dictionary, actor: Dictionary, cell: Vector2i) -> bool:
	var d = observation.definitions[actor.archetype]
	for enemy in observation.units:
		if not enemy.alive or enemy.team == actor.team or Hex.distance(cell,Hex.decode(enemy.position)) > int(d.range) or not height_allowed(observation,actor,cell,Hex.decode(enemy.position)):
			continue
		var friendly_fire = false
		for direction in Hex.DIRECTIONS:
			if Hex.decode(enemy.position) in [cell+direction,cell+direction*2]:
				friendly_fire = observation.units.any(func(u): return u.alive and u.team == actor.team and u.id != actor.id and Hex.decode(u.position) in [cell+direction,cell+direction*2] and height_allowed(observation,actor,cell,Hex.decode(u.position)))
				break
		if not friendly_fire:
			return true
	return false

func choose_spear_reposition(observation: Dictionary, legal_actions: Array, actor: Dictionary) -> Dictionary:
	var d = observation.definitions[actor.archetype]
	var budget = int(actor.ap)-int(d.cost)
	if budget < 1:
		return {}
	var moves = {}
	for action in legal_actions:
		if action.kind == "MOVE":
			moves[Hex.decode(action.target_cell)] = action
	var start = Hex.decode(actor.position)
	var tree = {start:{"steps":0,"risk":0,"first":start}}
	var queue = [start]
	var head = 0
	var best = {}
	var best_risk = 999
	var best_steps = 999
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var route = tree[cell]
		if cell != start and has_clean_attack(observation,actor,cell):
			if route.risk < best_risk or (route.risk == best_risk and route.steps < best_steps):
				best = moves[route.first]
				best_risk = route.risk
				best_steps = route.steps
		if route.steps >= budget:
			continue
		var risk = route.risk
		for enemy in observation.units:
			var definition = observation.definitions[enemy.archetype]
			if enemy.alive and enemy.team != actor.team and int(definition.zoc) > 0 and Hex.distance(cell,Hex.decode(enemy.position)) <= int(definition.zoc) and height_allowed(observation,enemy,Hex.decode(enemy.position),cell):
				risk += int(definition.damage_max)+Traits.damage_bonus(enemy,observation.units)
		if risk >= int(actor.hp):
			continue
		for direction in Hex.DIRECTIONS:
			var next: Vector2i = cell+direction
			if not moves.has(next):
				continue
			var cost = Terrain.step_cost(observation.board.get("heights",{}),cell,next,int(observation.definitions[actor.archetype].move_cost))
			if cost < 0 or route.steps+cost > budget:
				continue
			var steps = route.steps+cost
			if tree.has(next) and (tree[next].steps < steps or (tree[next].steps == steps and tree[next].risk <= risk)):
				continue
			tree[next] = {"steps":steps,"risk":risk,"first":next if cell == start else route.first}
			queue.append(next)
	return best.duplicate(true)

func guard_coverage(observation: Dictionary, actor: Dictionary, destination: Vector2i) -> int:
	var preview = observation.units.duplicate(true)
	for u in preview:
		if u.id == actor.id:
			u.position = Hex.encode(destination)
	var count = 0
	for ally in preview:
		var guardian = Guard.protector(ally,preview,observation.definitions)
		if not guardian.is_empty() and guardian.id == actor.id:
			count += 1
	return count

# Score reachable support positions, but execute only the first step and observe again.
func choose_guard_move(observation: Dictionary, legal_actions: Array, actor: Dictionary) -> Dictionary:
	var moves = {}
	for action in legal_actions:
		if action.kind == "MOVE":
			moves[Hex.decode(action.target_cell)] = action
	var start = Hex.decode(actor.position)
	var current_coverage = guard_coverage(observation,actor,start)
	var tree = {start:{"steps":0,"risk":0,"first":start}}
	var queue = [start]
	var head = 0
	var budget = int(actor.ap)
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var info = tree[cell]
		if info.steps >= budget:
			continue
		var risk = info.risk
		for enemy in observation.units:
			var radius = int(observation.definitions[enemy.archetype].zoc)
			if enemy.alive and enemy.team != actor.team and radius > 0 and Hex.distance(cell,Hex.decode(enemy.position)) <= radius and height_allowed(observation,enemy,Hex.decode(enemy.position),cell):
				risk += 1
		for direction in Hex.DIRECTIONS:
			var next: Vector2i = cell+direction
			if not moves.has(next):
				continue
			var cost = Terrain.step_cost(observation.board.get("heights",{}),cell,next,int(observation.definitions[actor.archetype].move_cost))
			if cost < 0 or info.steps+cost > budget:
				continue
			var steps = info.steps+cost
			if tree.has(next) and (tree[next].steps < steps or (tree[next].steps == steps and tree[next].risk <= risk)):
				continue
			tree[next] = {"steps":steps,"risk":risk,"first":next if cell == start else info.first}
			queue.append(next)
	var best = {}
	var best_coverage = current_coverage
	var best_steps = 999
	var best_risk = 999
	for destination in moves:
		if not tree.has(destination):
			continue
		var coverage = guard_coverage(observation,actor,destination)
		if coverage <= current_coverage:
			continue
		var route = tree[destination]
		if coverage > best_coverage or (coverage == best_coverage and (route.risk < best_risk or (route.risk == best_risk and route.steps < best_steps))):
			best_coverage = coverage
			best_risk = route.risk
			best_steps = route.steps
			best = moves[route.first]
	return best.duplicate(true)

func height_allowed(observation: Dictionary, actor: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	return Terrain.attack_height_allowed(observation.board.get("heights",{}),from,to,observation.definitions[actor.archetype].kind)
