extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const Charge = preload("res://scripts/core/ChargeRules.gd")

static func charge_score(o: Dictionary, actor: Dictionary, start: Vector2i, endpoint: Vector2i) -> float:
	var hits = Charge.targets(actor,start,endpoint,o.board,o.units)
	var enemies = hits.filter(func(u): return not u.get("is_corpse",false) and u.team!=actor.team)
	var friends = hits.filter(func(u): return u.team==actor.team).size()
	if enemies.size()<=friends:
		return -INF
	if o.has("focus_target_id") and not enemies.any(func(u): return u.id==o.focus_target_id):
		return -INF
	return 100.0*(enemies.size()-friends)+10.0*enemies.size()

static func choose(o: Dictionary, legal: Array, actor: Dictionary) -> Dictionary:
	var start = Hex.decode(actor.position)
	var best = {}
	var score = -INF
	for action in legal:
		if action.kind=="CHARGE":
			var value = charge_score(o,actor,start,Hex.decode(action.target_cell))
			if value>score:
				score = value
				best = action
	if not best.is_empty():
		return best.duplicate(true)
	# When repositioning out of an active control zone, charge instead of walking.
	var escape = choose_escape_charge(o,legal,actor)
	if not escape.is_empty():
		return escape
	# Find an angle using ordinary movement; execute only the first step.
	var moves = {}
	for action in legal:
		if action.kind=="MOVE":
			moves[Hex.decode(action.target_cell)] = action
	var d = o.definitions[actor.archetype]
	var budget = int(actor.ap)
	var tree = {start:{"cost":0,"risk":0,"first":start}}
	var queue = [start]
	var head = 0
	while head<queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		var route = tree[cell]
		var risk = int(route.risk)
		for enemy in o.units:
			var ed = o.definitions[enemy.archetype]
			if enemy.alive and enemy.team!=actor.team and enemy.get("reaction_ready",true) and not enemy.get("stunned",false) and not enemy.get("fleeing",false) and int(ed.zoc)>0 and Hex.distance(cell,Hex.decode(enemy.position))<=int(ed.zoc) and Terrain.attack_height_allowed(o.board.heights,Hex.decode(enemy.position),cell,ed.kind):
				risk += int(ed.get("reaction_damage",ed.damage_max))
		if risk>=int(actor.hp):
			continue
		for direction in Hex.DIRECTIONS:
			var next = cell+direction
			if not moves.has(next):
				continue
			var step = Terrain.step_cost(o.board.heights,cell,next,int(d.move_cost),int(o.board.width),int(o.board.height))
			var cost = int(route.cost)+step
			if step<0 or cost>budget:
				continue
			if tree.has(next) and (tree[next].risk<risk or (tree[next].risk==risk and tree[next].cost<=cost)):
				continue
			tree[next] = {"cost":cost,"risk":risk,"first":next if cell==start else route.first}
			queue.append(next)
	for cell in tree:
		if cell==start:
			continue
		var preview = actor.duplicate(true)
		preview.position = Hex.encode(cell)
		for endpoint in Charge.paths(preview,o.board,o.units,int(d.charge_range)):
			var value = charge_score(o,actor,cell,endpoint)
			if value==-INF:
				continue
			var route = tree[cell]
			value += (1000.0 if budget-int(route.cost)>=int(d.cost) else 0.0)-20.0*route.risk-route.cost
			if value>score:
				score = value
				best = moves[route.first]
	return best.duplicate(true)

static func reaction_threat(o: Dictionary, actor: Dictionary, cell: Vector2i) -> bool:
	for enemy in o.units:
		if not enemy.alive or enemy.team==actor.team or not enemy.get("reaction_ready",true) or enemy.get("stunned",false) or enemy.get("fleeing",false):
			continue
		var d = o.definitions[enemy.archetype]
		if int(d.zoc)>0 and Hex.distance(cell,Hex.decode(enemy.position))<=int(d.zoc) and Terrain.attack_height_allowed(o.board.heights,Hex.decode(enemy.position),cell,d.kind):
			return true
	return false

static func choose_escape_charge(o: Dictionary, legal: Array, actor: Dictionary) -> Dictionary:
	var start = Hex.decode(actor.position)
	if not reaction_threat(o,actor,start):
		return {}
	var best = {}
	var best_score = -INF
	for action in legal:
		if action.kind!="CHARGE":
			continue
		var endpoint = Hex.decode(action.target_cell)
		if reaction_threat(o,actor,endpoint):
			continue
		var hits = Charge.targets(actor,start,endpoint,o.board,o.units)
		var enemies_hit = hits.filter(func(u): return not u.get("is_corpse",false) and u.team!=actor.team).size()
		var friends_hit = hits.filter(func(u): return u.team==actor.team).size()
		# Empty ground is a valid escape; do not escape by harming mostly allies.
		if friends_hit>0 and enemies_hit<=friends_hit:
			continue
		var nearest = 999
		for enemy in o.units:
			if enemy.alive and not enemy.get("is_corpse",false) and enemy.team!=actor.team:
				nearest = mini(nearest,Hex.distance(endpoint,Hex.decode(enemy.position)))
		var score = 100.0*(enemies_hit-friends_hit)-nearest
		if score>best_score:
			best_score = score
			best = action
	return best.duplicate(true)
