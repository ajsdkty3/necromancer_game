extends RefCounted

const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const Guard = preload("res://scripts/core/GuardRules.gd")
const Traits = preload("res://scripts/core/FactionTraits.gd")
var heights: Dictionary = {}
var obstacles: Dictionary = {}
var definitions: Dictionary
var setup: Dictionary
var units: Array = []
var round_number = 1
var faction = "undead"
var domination = 20
var domination_cap = 20
var domination_regen = 10
var winner = ""
var human_index = 0
var history: Array = []
var rng = RandomNumberGenerator.new()
var initial_seed: int
var events: Array = []
var board_width = 20
var board_height = 10
var level_id = 1
var level_name = ""

func _init(seed_override: int = -1, requested_level: int = 1):
	definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json"))
	setup = JSON.parse_string(FileAccess.get_file_as_string("res://data/battle_setup.json"))
	var levels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))
	level_id = requested_level if levels.has(str(requested_level)) else 1
	var level: Dictionary = levels[str(level_id)]
	level_name = level.name
	domination_cap = int(level.get("domination_cap",20))
	domination_regen = int(level.get("domination_regen",10))
	domination = int(level.get("initial_domination",domination_cap))
	board_width = int(level.get("width",20))
	board_height = int(level.get("height",10))
	var terrain = JSON.parse_string(FileAccess.get_file_as_string(level.get("terrain","res://data/terrain.json")))
	heights = terrain.heights
	obstacles = terrain.get("obstacles",{})
	initial_seed = int(setup.seed) if seed_override < 0 else seed_override
	rng.seed = initial_seed
	for entry_id in level.unit_ids:
		var entry = setup.units.filter(func(u): return u.id == entry_id)[0]
		var d = definitions[entry.archetype]
		var offset = level.get("offset_overrides",{}).get(entry.id,entry.offset)
		units.append({"id":entry.id,"name":entry.name,"team":entry.team,"archetype":entry.archetype,
			"position":Hex.encode(Hex.from_offset(int(offset[0]),int(offset[1]))),
			"hp":int(d.hp),"max_hp":int(d.hp),"ap":6 if entry.team == "human" else 0,
			"max_ap":6 if entry.team == "human" else 0,"alive":true,"guarding":false,"reaction_ready":true})

func unit(id: String) -> Dictionary:
	for u in units:
		if u.id == id:
			return u
	return {}

func pos(u: Dictionary) -> Vector2i:
	return Hex.decode(u.position)

func occupant(cell: Vector2i) -> Dictionary:
	for u in units:
		if u.alive and pos(u) == cell:
			return u
	return {}

func resource(u: Dictionary) -> int:
	return domination if u.team == "undead" else int(u.ap)

func is_terminal() -> bool:
	return winner != ""

func humans() -> Array:
	return units.filter(func(u): return u.team == "human")

func active_human() -> String:
	var list = humans()
	return list[human_index].id if human_index < list.size() else ""

func can_act(u: Dictionary) -> bool:
	return not u.is_empty() and u.alive and not is_terminal() and u.team == faction and (faction == "undead" or active_human() == u.id)

func get_zone_controllers(cell: Vector2i, mover_team: String) -> Array:
	var result = []
	for u in units:
		var radius = int(definitions[u.archetype].zoc)
		if u.alive and u.reaction_ready and u.team != mover_team and radius > 0 and Hex.distance(pos(u),cell) <= radius and Terrain.attack_height_allowed(heights,pos(u),cell,definitions[u.archetype].kind):
			result.append(u.id)
	return result

# Weighted shortest paths: resource cost first, reaction count second.
func path_tree(actor_id: String) -> Dictionary:
	var u = unit(actor_id)
	if u.is_empty() or not u.alive:
		return {}
	var start = pos(u)
	var budget = resource(u)
	var tree = {start: {"steps":0,"risk":0,"path":[]}}
	var queue = [start]
	var head = 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		var info = tree[current]
		if info.steps >= budget:
			continue
		var risk = info.risk + get_zone_controllers(current,u.team).size()
		for direction in Hex.DIRECTIONS:
			var next: Vector2i = current + direction
			if not Hex.inside(next,board_width,board_height) or Terrain.blocked(obstacles,next) or not occupant(next).is_empty():
				continue
			var step = Terrain.step_cost(heights,current,next,int(definitions[u.archetype].move_cost),board_width,board_height)
			if step < 0 or info.steps + step > budget:
				continue
			var steps = info.steps + step
			if tree.has(next) and (tree[next].steps < steps or (tree[next].steps == steps and tree[next].risk <= risk)):
				continue
			var path = info.path.duplicate()
			path.append(next)
			tree[next] = {"steps":steps,"risk":risk,"path":path}
			queue.append(next)
	return tree

func get_reachable_cells(actor_id: String) -> Array:
	var tree = path_tree(actor_id)
	var u = unit(actor_id)
	if not u.is_empty():
		tree.erase(pos(u))
	return tree.keys()

func find_path(actor_id: String, destination: Vector2i) -> Array:
	return path_tree(actor_id).get(destination,{}).get("path",[])

func attack_targets(actor: Dictionary, target: Dictionary) -> Array:
	var d = definitions[actor.archetype]
	if not Terrain.attack_height_allowed(heights,pos(actor),pos(target),d.kind):
		return []
	if d.target_shape == "spear":
		for direction in Hex.DIRECTIONS:
			for length in [1,2]:
				if pos(actor) + direction * length == pos(target):
					var hits = []
					for step in [1,2]:
						var hit = occupant(pos(actor) + direction * step)
						if not hit.is_empty() and Terrain.attack_height_allowed(heights,pos(actor),pos(hit),d.kind):
							hits.append(hit.id)
					return hits
	return [target.id]

func enumerate_legal_actions(actor_id: String) -> Array:
	var u = unit(actor_id)
	if not can_act(u):
		return []
	var result = []
	var d = definitions[u.archetype]
	for cell in get_reachable_cells(actor_id):
		result.append({"actor_id":actor_id,"kind":"MOVE","target_cell":Hex.encode(cell)})
	if resource(u) >= int(d.cost):
		for target in units:
			if target.alive and target.id != actor_id and Hex.distance(pos(u),pos(target)) <= int(d.range) and Terrain.attack_height_allowed(heights,pos(u),pos(target),d.kind):
				result.append({"actor_id":actor_id,"kind":d.kind,"target_unit_id":target.id})
				if Terrain.height_at(heights,pos(u)) > Terrain.height_at(heights,pos(target)):
					result.append({"actor_id":actor_id,"kind":"OVERHEAD_STRIKE","target_unit_id":target.id})
	if d.has("teleport_range") and resource(u) >= int(d.teleport_cost):
		for cell in Hex.cells(board_width,board_height):
			if not Terrain.blocked(obstacles,cell) and occupant(cell).is_empty() and Hex.distance(pos(u),cell) <= int(d.teleport_range):
				result.append({"actor_id":actor_id,"kind":"TELEPORT","target_cell":Hex.encode(cell)})
	if d.has("guard_cost") and not u.guarding and resource(u) >= int(d.guard_cost):
		result.append({"actor_id":actor_id,"kind":"GUARD"})
	result.append({"actor_id":actor_id,"kind":"END_UNIT" if faction == "human" else "END_TURN"})
	return result

func validate_action(action: Dictionary) -> Dictionary:
	if is_terminal():
		return {"valid":false,"reason":"战斗已经结束"}
	if action.get("kind","") == "END_TURN" and faction == "undead":
		return {"valid":true,"reason":""}
	var u = unit(str(action.get("actor_id","")))
	if not can_act(u):
		return {"valid":false,"reason":"当前单位不能行动"}
	for legal in enumerate_legal_actions(u.id):
		if legal == action:
			return {"valid":true,"reason":""}
	return {"valid":false,"reason":"目标非法、不可到达或资源不足"}

func emit(type: String, message: String, data: Dictionary = {}):
	var event = data.duplicate(true)
	event["type"] = type
	event["message"] = message
	events.append(event)

func spend(u: Dictionary, cost: int):
	if u.team == "undead":
		domination -= cost
	else:
		u.ap -= cost
	emit("resource","%s 花费 %d，剩余 %d" % [u.name,cost,resource(u)],{"actor_id":u.id,"cost":cost,"remaining":resource(u)})

func apply_damage(source: String, target_id: String, amount: int, reason: String, multiplier: int = 1) -> Array:
	var begin = events.size()
	var target = unit(target_id)
	if is_terminal() or target.is_empty() or not target.alive:
		return []
	var raw_amount = amount
	var bonus = Traits.damage_bonus(unit(source),units)
	amount = maxi(0,amount+bonus)*multiplier
	if bonus > 0:
		emit("damage_bonus","%s 众志成城：相邻%d名人类友军，伤害 %d → %d" % [unit(source).name,bonus,raw_amount,amount],
			{"source":source,"target":target_id,"raw_amount":raw_amount,"bonus":bonus,"amount":amount})
	var guardian = Guard.protector(target,units,definitions)
	if not guardian.is_empty():
		emit("protected","%s 受守护免伤，%d 伤害转移给 %s" % [target.name,amount,guardian.name],
			{"source":source,"target":target_id,"guardian_id":guardian.id,"amount":amount})
		target = guardian
		target_id = guardian.id
	target.hp = maxi(0,int(target.hp)-amount)
	emit("damage","%s → %s：%d 伤害（%s），HP %d" % [unit(source).name,target.name,amount,reason,target.hp],
		{"source":source,"target":target_id,"amount":amount,"raw_amount":raw_amount,"bonus":bonus,"hp":target.hp})
	if target.hp == 0:
		target.alive = false
		target.guarding = false
		emit("death",target.name + " 死亡",{"unit_id":target_id,"position":target.position.duplicate()})
		if target.team == "undead":
			var old_domination = domination
			domination = mini(domination_cap,domination+5)
			emit("resource","%s 魂归主宰：恢复%d支配力，当前%d/%d" % [target.name,domination-old_domination,domination,domination_cap],
				{"actor_id":target.id,"trait":"SOUL_RETURN","gain":domination-old_domination,"remaining":domination})
	check_winner()
	return events.slice(begin)

func check_winner():
	var undead = units.any(func(u): return u.alive and u.team == "undead")
	var human = units.any(func(u): return u.alive and u.team == "human")
	if not human:
		winner = "undead"
	elif not undead:
		winner = "human"
	if winner != "":
		emit("victory","胜利！人类全灭" if winner == "undead" else "失败：亡灵全灭",{"winner":winner})

func attack(actor: Dictionary, target: Dictionary, reaction: bool, overhead: bool = false):
	var d = definitions[actor.archetype]
	if reaction:
		if not actor.reaction_ready:
			return
		actor.reaction_ready = false
	var label = "当头猛击" if overhead else d.label
	emit("reaction" if reaction else "attack",actor.name + (" 借机攻击 " if reaction else " " + label + " → ") + target.name,
		{"actor_id":actor.id,"target_id":target.id})
	var hits = attack_targets(actor,target)
	for target_id in hits:
		if is_terminal():
			break
		if reaction and unit(target_id).team == actor.team:
			continue
		if overhead and Terrain.height_at(heights,pos(actor)) <= Terrain.height_at(heights,pos(unit(target_id))):
			continue
		apply_damage(actor.id,target_id,rng.randi_range(int(d.damage_min),int(d.damage_max)),"借机攻击" if reaction else label,2 if overhead else 1)

func advance_human():
	var list = humans()
	while human_index < list.size() and not list[human_index].alive:
		human_index += 1
	if human_index >= list.size() and not is_terminal():
		faction = "undead"
		reset_reactions("undead")
		round_number += 1
		domination = mini(domination_cap,domination+domination_regen)
		emit("turn","第 %d 轮 · 亡灵回合，支配力 %d/%d" % [round_number,domination,domination_cap])

func reset_reactions(team: String):
	for u in units:
		if u.alive and u.team == team:
			u.reaction_ready = true
	emit("reaction_reset","%s阵营借机攻击次数恢复" % team,{"team":team})

func execute_action(action: Dictionary) -> Array:
	events = []
	var validation = validate_action(action)
	if not validation.valid:
		emit("invalid",validation.reason)
		return events.duplicate(true)
	history.append(action.duplicate(true))
	var kind = action.kind
	var actor = unit(str(action.get("actor_id","")))
	if kind == "END_TURN":
		faction = "human"
		reset_reactions("human")
		human_index = 0
		for u in humans():
			u.ap = 6
			if u.guarding:
				u.guarding = false
				emit("guard_expired",u.name + " 守护结束",{"actor_id":u.id})
		emit("turn","人类回合 · 各单位恢复至 6 AP")
		advance_human()
	elif kind == "GUARD":
		spend(actor,int(definitions[actor.archetype].guard_cost))
		actor.guarding = true
		emit("guard",actor.name + " 开启守护，持续至下次人类回合开始",{"actor_id":actor.id})
	elif kind == "END_UNIT":
		emit("end_unit",actor.name + " 结束行动")
		human_index += 1
		advance_human()
	elif kind == "MOVE":
		var path = find_path(actor.id,Hex.decode(action.target_cell))
		emit("path",actor.name + " 规划路径：" + str(path),{"actor_id":actor.id,"path":path.map(func(c): return Hex.encode(c))})
		for cell in path:
			for controller_id in get_zone_controllers(pos(actor),actor.team):
				if not actor.alive or is_terminal():
					break
				var controller = unit(controller_id)
				if controller.alive:
					attack(controller,actor,true)
			if not actor.alive or is_terminal():
				break
			var old = actor.position.duplicate()
			var cost = Terrain.step_cost(heights,pos(actor),cell,int(definitions[actor.archetype].move_cost),board_width,board_height)
			actor.position = Hex.encode(cell)
			spend(actor,cost)
			emit("move",actor.name + " 移至 " + str(cell),{"actor_id":actor.id,"from":old,"to":actor.position.duplicate()})
	elif kind == "TELEPORT":
		spend(actor,int(definitions[actor.archetype].teleport_cost))
		actor.position = action.target_cell.duplicate()
		emit("teleport",actor.name + " 瞬移至 " + str(actor.position),{"actor_id":actor.id,"to":actor.position.duplicate()})
	else:
		spend(actor,int(definitions[actor.archetype].cost))
		attack(actor,unit(action.target_unit_id),false,kind == "OVERHEAD_STRIKE")
	if faction == "human":
		advance_human()
	return events.duplicate(true)

func get_observation(_team: String = "") -> Dictionary:
	var zones = {}
	var legal_actions = {}
	for u in units:
		if u.alive:
			var radius = int(definitions[u.archetype].zoc)
			zones[u.id] = []
			if radius > 0 and u.reaction_ready:
				for cell in Hex.cells(board_width,board_height):
					if cell != pos(u) and Hex.distance(pos(u),cell) <= radius and Terrain.attack_height_allowed(heights,pos(u),cell,definitions[u.archetype].kind):
						zones[u.id].append(Hex.encode(cell))
		if can_act(u):
			legal_actions[u.id] = enumerate_legal_actions(u.id)
	return {"level_id":level_id,"level_name":level_name,"round":round_number,"phase":"finished" if is_terminal() else "battle","current_faction":faction,
		"undead_domination":domination,"domination_cap":domination_cap,"domination_regen":domination_regen,
		"board":{"width":board_width,"height":board_height,"hex_layout":setup.layout,"heights":heights.duplicate(true),"obstacles":obstacles.duplicate(true)},"units":units.duplicate(true),
		"definitions":definitions.duplicate(true),"zones":zones,"legal_actions":legal_actions,"winner":winner,"active_human":active_human(),
		"human_index":human_index,"rng_seed":initial_seed,"rng_state":str(rng.state),"action_history":history.duplicate(true)}
