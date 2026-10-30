extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const Support = preload("res://scripts/ai/SupportPolicy.gd")

static func choose(o: Dictionary, actions: Array, actor: Dictionary) -> Dictionary:
	var support = Support.choose(o,actions,actor,true)
	if not support.is_empty():
		return support
	var best = actions.back()
	var best_score = 0.0
	var start = Hex.decode(actor.position)
	var allies = o.units.filter(func(u): return Support.is_recipient(o,actor,u))
	var enemies = o.units.filter(func(u): return u.alive and u.team != actor.team and not u.get("is_corpse",false))
	for action in actions:
		var score = -INF
		if action.kind == "OVERHEAD_STRIKE":
			for target in enemies:
				if target.id == action.target_unit_id:
					score = 90.0 if not target.get("vulnerable",false) else 5.0
		elif action.kind == "BATTLE_ORDER":
			score = 30.0 * Support.coverage(o,actor,start,true)
		elif action.kind == "MOVE":
			var cell = Hex.decode(action.target_cell)
			if Hex.distance(start,cell) != 1:
				continue
			var cost = Terrain.step_cost(o.board.heights,start,cell,1,int(o.board.width),int(o.board.height))
			if not actor.get("battle_order",false) and actor.ap-cost < int(o.definitions[actor.archetype].cost):
				continue
			score = support_score(cell,allies)-support_score(start,allies)-0.1
			for enemy in enemies:
				var d = o.definitions[enemy.archetype]
				if enemy.get("reaction_ready",false) and not enemy.get("stunned",false) and not enemy.get("fleeing",false) and int(d.zoc)>0 and Hex.distance(start,Hex.decode(enemy.position)) <= int(d.zoc) and Terrain.attack_height_allowed(o.board.heights,Hex.decode(enemy.position),start,d.kind):
					score -= 50.0
		if score > best_score:
			best = action
			best_score = score
	return best.duplicate(true)

static func support_score(cell: Vector2i, allies: Array) -> float:
	var score = 0.0
	for ally in allies:
		var distance = Hex.distance(cell,Hex.decode(ally.position))
		score += (12.0 if distance == 1 else 0.0)-distance
	return score
