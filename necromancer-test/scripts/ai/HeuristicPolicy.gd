extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")

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
	var enemy_in_range = nearest <= int(observation.definitions[actor.archetype].range)
	for action in legal_actions:
		var score = -1000.0
		var single_hp = -1
		if action.kind == "MOVE":
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
			score = float(nearest-next_distance) * 5.0 - 0.1
			for enemy in enemies:
				var radius = int(observation.definitions[enemy.archetype].zoc)
				if radius > 0 and Hex.distance(start,Hex.decode(enemy.position)) <= radius:
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
						hits = observation.units.filter(func(u): return u.alive and Hex.decode(u.position) in [start+direction,start+direction*2])
						break
			score = 0.0
			if hits.size() == 1 and target.team != actor.team:
				single_hp = int(target.hp)
			for hit in hits:
				if hit.team == actor.team:
					score -= 100.0
				else:
					score += 20.0
					if hit.hp <= d.damage_min:
						score += 70.0
					elif hit.hp <= d.damage_max:
						score += 15.0
		# Fixed damage makes kill tiers monotonic in HP; break single-hit ties by
		# current absolute HP, never percentage. Area/friendly-fire scores stay intact.
		var lower_single_hp = score == best_score and single_hp >= 0 and best_single_hp >= 0 and single_hp < best_single_hp
		if score > best_score or lower_single_hp:
			best_score = score
			best_single_hp = single_hp
			best = action
	return best.duplicate(true)
