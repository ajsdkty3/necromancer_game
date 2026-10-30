extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const Guard = preload("res://scripts/core/GuardRules.gd")

static func is_recipient(o: Dictionary, actor: Dictionary, ally: Dictionary) -> bool:
	var d = o.definitions[ally.archetype]
	return ally.alive and ally.id != actor.id and ally.team == actor.team and not ally.get("is_corpse",false) and not d.has("order_range") and not d.has("guard_range")

static func coverage(o: Dictionary, actor: Dictionary, cell: Vector2i, order: bool) -> int:
	var preview = o.units.duplicate(true)
	for u in preview:
		if u.id == actor.id:
			u.position = Hex.encode(cell)
			if not order:
				u.guarding = true
	var count = 0
	for ally in preview:
		if not is_recipient(o,actor,ally) or Hex.distance(cell,Hex.decode(ally.position)) != 1:
			continue
		if order:
			var covered = preview.any(func(u): return u.alive and u.id != actor.id and u.id != ally.id and u.team == actor.team and u.get("battle_order",false) and not u.get("fleeing",false) and Hex.distance(Hex.decode(u.position),Hex.decode(ally.position)) == 1)
			if not covered:
				count += 1
		else:
			var protector = Guard.protector(ally,preview,o.definitions)
			if not protector.is_empty() and protector.id == actor.id:
				count += 1
	return count

static func choose(o: Dictionary, actions: Array, actor: Dictionary, order: bool) -> Dictionary:
	var d = o.definitions[actor.archetype]
	var active = actor.get("battle_order" if order else "guarding",false)
	var budget = int(actor.ap) - (0 if active else int(d.cost if order else d.guard_cost))
	var start = Hex.decode(actor.position)
	var moves = {}
	for a in actions:
		if a.kind == "MOVE":
			moves[Hex.decode(a.target_cell)] = a
	var tree = {start:{"cost":0,"first":start}}
	var queue = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		# Do not sacrifice the support unit to reactions while repositioning.
		var dangerous = o.units.any(func(u): return u.alive and u.team != actor.team and u.get("reaction_ready",false) and not u.get("fleeing",false) and not u.get("stunned",false) and int(o.definitions[u.archetype].zoc)>0 and Hex.distance(cell,Hex.decode(u.position))<=int(o.definitions[u.archetype].zoc) and Terrain.attack_height_allowed(o.board.heights,Hex.decode(u.position),cell,o.definitions[u.archetype].kind))
		if dangerous:
			continue
		for direction in Hex.DIRECTIONS:
			var next = cell+direction
			if not moves.has(next):
				continue
			var step = Terrain.step_cost(o.board.heights,cell,next,int(d.move_cost),int(o.board.width),int(o.board.height))
			var cost = tree[cell].cost+step
			if step < 0 or cost > int(actor.ap) or (tree.has(next) and tree[next].cost <= cost):
				continue
			tree[next] = {"cost":cost,"first":next if cell == start else tree[cell].first}
			queue.append(next)
	var best_cell = start
	var best_count = coverage(o,actor,start,order)
	for cell in tree:
		if tree[cell].cost > budget:
			continue
		var count = coverage(o,actor,cell,order)
		if count > best_count or (count == best_count and tree[cell].cost < tree[best_cell].cost):
			best_cell = cell
			best_count = count
	if best_cell != start:
		return moves[tree[best_cell].first].duplicate(true)
	if not active and best_count > 0:
		for a in actions:
			if a.kind == ("BATTLE_ORDER" if order else "GUARD"):
				return a.duplicate(true)
	# With no combat ally in range, advance toward one even if casting must
	# wait until next turn (notably six-AP shields with a six-AP guard).
	if best_count == 0:
		var allies = o.units.filter(func(u): return is_recipient(o,actor,u))
		var nearest = func(cell):
			var distance = 999
			for ally in allies:
				distance = mini(distance,Hex.distance(cell,Hex.decode(ally.position)))
			return distance
		var best_distance = nearest.call(start)
		best_cell = start
		for cell in tree:
			var distance = nearest.call(cell)
			if distance < best_distance or (distance == best_distance and tree[cell].cost < tree[best_cell].cost):
				best_distance = distance
				best_cell = cell
		if best_cell != start:
			return moves[tree[best_cell].first].duplicate(true)
	return {}
