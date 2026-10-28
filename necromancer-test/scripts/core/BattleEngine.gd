extends RefCounted

const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const Guard = preload("res://scripts/core/GuardRules.gd")
const Traits = preload("res://scripts/core/FactionTraits.gd")
const Advantage = preload("res://scripts/core/AdvantageRules.gd")
const Knockback = preload("res://scripts/core/KnockbackRules.gd")
const Morale = preload("res://scripts/core/MoraleRules.gd")
const FleePaths = preload("res://scripts/core/FleePaths.gd")
const Charge = preload("res://scripts/core/ChargeRules.gd")
var initial_human_count = 0
var human_deaths = 0
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
			"hp":int(d.hp),"max_hp":int(d.hp),"ap":int(d.get("max_ap",6)) if entry.team == "human" else 0,
			"max_ap":int(d.get("max_ap",6)) if entry.team == "human" else 0,"alive":true,"guarding":false,"reaction_ready":true,"stunned":false,"stun_skip_active":false})
		if entry.team == "human":
			initial_human_count += 1
			units.back().merge({"morale_base":100,"morale":100,"fleeing":false,"flee_trapped":false,"flee_until_round":0,"flee_target":[],"escaped":false})

func board_data() -> Dictionary:
	return {"width":board_width,"height":board_height,"heights":heights,"obstacles":obstacles}

func flee_tree(u: Dictionary) -> Dictionary:
	return FleePaths.tree(pos(u),board_data(),units,u.id,int(definitions[u.archetype].move_cost))

func choose_flee_target(u: Dictionary):
	var tree = flee_tree(u)
	if not u.flee_target.is_empty() and tree.has(Hex.decode(u.flee_target)):
		return
	var exits = tree.keys().filter(func(cell): return Hex.to_offset(cell).x==board_width-1)
	u.flee_target = [] if exits.is_empty() else Hex.encode(exits[rng.randi_range(0,exits.size()-1)])

func escape_if_at_edge(u: Dictionary):
	if u.alive and u.get("fleeing",false) and Hex.to_offset(pos(u)).x==board_width-1:
		u.alive = false
		u.escaped = true
		u.guarding = false
		u.reaction_ready = false
		emit("escape",u.name+" 溃逃离开战场",{"unit_id":u.id})
		check_winner()

func refresh_morale():
	for u in humans():
		if not u.alive:
			continue
		var previous = int(u.morale)
		u.morale = 0 if u.fleeing else Morale.value(u,initial_human_count,human_deaths,units)
		if u.morale==0 and not u.fleeing:
			u.fleeing = true
			u.flee_until_round = round_number+1
			u.guarding = false
			u.reaction_ready = false
			emit("flee",u.name+" 士气崩溃，开始溃逃2回合",{"unit_id":u.id})
		if previous!=u.morale:
			emit("morale",u.name+" 士气："+str(u.morale),{"unit_id":u.id,"morale":u.morale})
		if u.fleeing:
			if Morale.adjacent_enemies(u,units)>=6:
				if not u.flee_trapped:
					emit("flee_trapped",u.name+" 完全被围，士气保持0；突围后重新计算2回合",{"unit_id":u.id})
				u.flee_trapped = true
				u.flee_until_round = -1
				u.flee_target = []
				continue
			if u.flee_trapped:
				u.flee_trapped = false
				u.flee_until_round = round_number+1
				emit("flee_released",u.name+" 包围解除，重新开始溃逃2回合",{"unit_id":u.id})
			escape_if_at_edge(u)
			if u.alive:
				choose_flee_target(u)

func finish_flee_round():
	for u in humans():
		if u.alive and u.fleeing and not u.flee_trapped and Morale.adjacent_enemies(u,units)<6 and round_number>=int(u.flee_until_round):
			u.fleeing = false
			u.flee_target = []
			u.morale_base = 80
			u.morale = Morale.value(u,initial_human_count,human_deaths,units)
			emit("rally",u.name+" 溃逃结束，基础士气恢复80，当前士气%d" % u.morale,{"unit_id":u.id,"morale":u.morale})

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
		if u.alive and not u.get("stunned",false) and not u.get("fleeing",false) and u.reaction_ready and u.team != mover_team and radius > 0 and Hex.distance(pos(u),cell) <= radius and Terrain.attack_height_allowed(heights,pos(u),cell,definitions[u.archetype].kind):
			result.append(u.id)
	return result

# Weighted shortest paths: resource cost first, reaction count second.
func path_tree(actor_id: String) -> Dictionary:
	var u = unit(actor_id)
	if u.is_empty() or not u.alive or u.get("stunned",false):
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
	if u.get("stunned",false):
		return [{"actor_id":actor_id,"kind":"END_UNIT" if faction=="human" else "END_TURN"}]
	if u.get("fleeing",false):
		if u.flee_trapped or Morale.adjacent_enemies(u,units)>=6:
			return [{"actor_id":actor_id,"kind":"END_UNIT"}]
		var tree = flee_tree(u)
		var goal = Hex.decode(u.flee_target) if not u.flee_target.is_empty() else pos(u)
		var path = tree.get(goal,{}).get("path",[])
		if not path.is_empty() and Terrain.step_cost(heights,pos(u),path[0],int(d.move_cost),board_width,board_height)<=resource(u):
			result.append({"actor_id":actor_id,"kind":"MOVE","target_cell":Hex.encode(path[0])})
		result.append({"actor_id":actor_id,"kind":"END_UNIT"})
		return result
	for cell in get_reachable_cells(actor_id):
		result.append({"actor_id":actor_id,"kind":"MOVE","target_cell":Hex.encode(cell)})
	if d.has("charge_range"):
		if resource(u)>=int(d.cost):
			for cell in Charge.paths(u,board_data(),units,int(d.charge_range)):
				result.append({"actor_id":actor_id,"kind":"CHARGE","target_cell":Hex.encode(cell)})
		if resource(u)>=int(d.stomp_cost):
			for target in units:
				if target.alive and target.id!=u.id and Hex.distance(pos(u),pos(target))<=int(d.stomp_range) and Terrain.attack_height_allowed(heights,pos(u),pos(target),d.kind) and Advantage.qualifies(u,target,pos(u),heights,units):
					result.append({"actor_id":actor_id,"kind":"WAR_STOMP","target_unit_id":target.id})
	else:
		for target in units:
			if target.alive and target.id != actor_id and Hex.distance(pos(u),pos(target)) <= int(d.range) and Terrain.attack_height_allowed(heights,pos(u),pos(target),d.kind):
				if resource(u)>=int(d.cost):
					result.append({"actor_id":actor_id,"kind":d.kind,"target_unit_id":target.id})
				if d.has("knockback_cost") and resource(u)>=int(d.knockback_cost) and Hex.distance(pos(u),pos(target))<=int(d.knockback_range) and Advantage.qualifies(u,target,pos(u),heights,units):
					result.append({"actor_id":actor_id,"kind":"KNOCKBACK","target_unit_id":target.id})
				elif not d.has("knockback_cost") and resource(u)>=int(d.get("advantage_cost",d.cost)) and Advantage.qualifies(u,target,pos(u),heights,units):
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

func charge_targets(actor: Dictionary, start: Vector2i) -> Array:
	if not actor.alive or actor.get("stunned",false) or actor.get("fleeing",false):
		return []
	return Charge.targets(actor,start,pos(actor),board_data(),units)

func resolve_knockback(actor: Dictionary, target: Dictionary):
	if not target.alive or is_terminal():
		return
	var landing = Knockback.landing(pos(actor),pos(target),board_data(),units)
	if landing.blocked:
		emit("knockback_blocked",target.name+" 后方受阻，无法击退")
	else:
		var old = target.position.duplicate()
		target.position = Hex.encode(landing.cell)
		emit("move",target.name+" 被击退一格",{"actor_id":target.id,"from":old,"to":target.position.duplicate(),"forced":true})
		if landing.fall>0:
			var fall_damage = int(landing.fall / 2) * int(definitions[actor.archetype].get("fall_damage_per_height",2))
			apply_damage(actor.id,target.id,fall_damage,"坠落",1,false)

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

func apply_damage(source: String, target_id: String, amount: int, reason: String, multiplier: int = 1, apply_trait: bool = true) -> Array:
	var begin = events.size()
	var target = unit(target_id)
	if is_terminal() or target.is_empty() or not target.alive:
		return []
	var raw_amount = amount
	var bonus = Traits.damage_bonus(unit(source),units) if apply_trait else 0
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
		if target.team == "human":
			human_deaths += 1
			for ally in humans():
				if ally.alive and Hex.distance(pos(ally),pos(target))<=2:
					ally.morale_base = maxi(0,int(ally.morale_base)-20)
					emit("morale_loss",ally.name+" 附近友军阵亡，士气损失20",{"unit_id":ally.id,"amount":20})
		if target.team == "undead":
			var old_domination = domination
			domination = mini(domination_cap,domination+5)
			emit("resource","%s 魂归主宰：恢复%d支配力，当前%d/%d" % [target.name,domination-old_domination,domination,domination_cap],
				{"actor_id":target.id,"trait":"SOUL_RETURN","gain":domination-old_domination,"remaining":domination})
	refresh_morale()
	check_winner()
	return events.slice(begin)

func check_winner():
	if is_terminal():
		return
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
		if not actor.reaction_ready or actor.get("fleeing",false) or actor.get("stunned",false):
			return
		actor.reaction_ready = false
	var label = "当头猛击" if overhead else d.label
	if overhead:
		label = d.get("advantage_label",label)
	if overhead and d.has("advantage_hits"):
		for hit_index in int(d.advantage_hits):
			if is_terminal() or not actor.alive or not target.alive:
				break
			emit("attack",actor.name+" "+d.advantage_label+" → "+target.name+"（第%d击）" % (hit_index+1),
				{"actor_id":actor.id,"target_id":target.id})
			apply_damage(actor.id,target.id,rng.randi_range(int(d.advantage_damage_min),int(d.advantage_damage_max)),d.advantage_label)
		return
	emit("reaction" if reaction else "attack",actor.name + (" 借机攻击 " if reaction else " " + label + " → ") + target.name,
		{"actor_id":actor.id,"target_id":target.id})
	var hits = [target.id] if reaction else attack_targets(actor,target)
	for target_id in hits:
		if is_terminal() or actor.get("fleeing",false):
			break
		if reaction and unit(target_id).team == actor.team:
			continue
		if overhead and not Advantage.qualifies(actor,unit(target_id),pos(actor),heights,units):
			continue
		if overhead and d.has("overhead_damage"):
			apply_damage(actor.id,target_id,int(d.overhead_damage),label)
		else:
			apply_damage(actor.id,target_id,rng.randi_range(int(d.damage_min),int(d.damage_max)),"借机攻击" if reaction else label,2 if overhead else 1)
		if not reaction:
			if overhead and d.get("advantage_stun",false):
				apply_stun(unit(target_id))
			elif not overhead and d.get("ordinary_knockback",false):
				resolve_knockback(actor,unit(target_id))
	if overhead and d.has("advantage_heal") and actor.alive:
		var previous_hp = int(actor.hp)
		actor.hp = mini(int(actor.max_hp),previous_hp+int(d.advantage_heal))
		emit("heal","%s %s：恢复%d生命，HP %d/%d" % [actor.name,label,actor.hp-previous_hp,actor.hp,actor.max_hp],
			{"unit_id":actor.id,"amount":actor.hp-previous_hp,"hp":actor.hp})

func advance_human():
	var list = humans()
	while human_index < list.size() and not list[human_index].alive:
		human_index += 1
	if human_index >= list.size() and not is_terminal():
		finish_stuns("human")
		finish_flee_round()
		faction = "undead"
		begin_stuns("undead")
		for u in units:
			if u.team == "undead" and u.guarding:
				u.guarding = false
				emit("guard_expired",u.name + " 守护结束",{"actor_id":u.id})
		reset_reactions("undead")
		round_number += 1
		domination = mini(domination_cap,domination+domination_regen)
		emit("turn","第 %d 轮 · 亡灵回合，支配力 %d/%d" % [round_number,domination,domination_cap])

func reset_reactions(team: String):
	for u in units:
		if u.alive and u.team == team and not u.get("fleeing",false):
			u.reaction_ready = true
	emit("reaction_reset","%s阵营借机攻击次数恢复" % team,{"team":team})

func begin_stuns(team: String):
	for u in units:
		if u.alive and u.team==team and u.get("stunned",false):
			u.stun_skip_active = true

func finish_stuns(team: String):
	for u in units:
		if u.team==team and u.get("stun_skip_active",false):
			u.stunned = false
			u.stun_skip_active = false
			emit("stun_expired",u.name+" 眩晕结束",{"unit_id":u.id})

func apply_stun(target: Dictionary):
	if target.alive and not is_terminal() and not target.get("stunned",false):
		target.stunned = true
		target.stun_skip_active = false
		emit("stun",target.name+" 眩晕：下个所属阵营回合无法行动",{"unit_id":target.id})

func execute_action(action: Dictionary) -> Array:
	events = []
	var validation = validate_action(action)
	if not validation.valid:
		emit("invalid",validation.reason)
		return events.duplicate(true)
	history.append(action.duplicate(true))
	refresh_morale()
	var kind = action.kind
	var actor = unit(str(action.get("actor_id","")))
	if kind == "END_TURN":
		finish_stuns("undead")
		faction = "human"
		begin_stuns("human")
		reset_reactions("human")
		human_index = 0
		for u in humans():
			u.ap = u.max_ap
			if u.guarding:
				u.guarding = false
				emit("guard_expired",u.name + " 守护结束",{"actor_id":u.id})
		emit("turn","人类回合 · 各单位AP恢复至自身上限")
		advance_human()
	elif kind == "CHARGE":
		var d = definitions[actor.archetype]
		var start = actor.position.duplicate()
		var path = Charge.paths(actor,board_data(),units,int(d.charge_range))[Hex.decode(action.target_cell)]
		spend(actor,int(d.cost))
		emit("path",actor.name+" 沿直线冲锋",{"actor_id":actor.id,"path":path.map(func(c): return Hex.encode(c))})
		for cell in path:
			var old = actor.position.duplicate()
			actor.position = Hex.encode(cell)
			emit("move",actor.name+" 冲锋",{"actor_id":actor.id,"from":old,"to":actor.position.duplicate(),"charge":true})
			refresh_morale()
			if is_terminal() or not actor.alive or actor.get("fleeing",false):
				break
		# Snapshot target IDs before knockbacks so each covered unit is hit once.
		var hits = charge_targets(actor,Hex.decode(start)).map(func(u): return u.id)
		if not hits.is_empty() and not is_terminal():
			emit("attack",actor.name+" 冲锋范围攻击",{"actor_id":actor.id,"target_id":hits[0]})
		for target_id in hits:
			if is_terminal() or not actor.alive or actor.get("fleeing",false):
				break
			var target = unit(target_id)
			apply_damage(actor.id,target.id,int(d.damage_min),"骑士冲锋")
			resolve_knockback(actor,target)
		emit("charge_end",actor.name+" 冲锋结束",{"actor_id":actor.id})
	elif kind == "WAR_STOMP":
		var d = definitions[actor.archetype]
		var target = unit(action.target_unit_id)
		spend(actor,int(d.stomp_cost))
		emit("attack",actor.name+" 战争践踏 → "+target.name,{"actor_id":actor.id,"target_id":target.id})
		var target_cell = pos(target)
		apply_damage(actor.id,target.id,rng.randi_range(int(d.stomp_damage_min),int(d.stomp_damage_max)),"战争践踏")
		resolve_knockback(actor,target)
		if actor.alive and occupant(target_cell).is_empty() and (not target.alive or pos(target)!=target_cell):
			var old = actor.position.duplicate()
			actor.position = Hex.encode(target_cell)
			emit("move",actor.name+" 践踏跟进",{"actor_id":actor.id,"from":old,"to":actor.position.duplicate(),"forced":true})
	elif kind == "GUARD":
		spend(actor,int(definitions[actor.archetype].guard_cost))
		actor.guarding = true
		emit("guard",actor.name + " 开启守护，持续至下次所属阵营回合开始",{"actor_id":actor.id})
	elif kind == "END_UNIT":
		emit("end_unit",actor.name + " 结束行动")
		human_index += 1
		advance_human()
	elif kind == "MOVE":
		var was_fleeing = actor.get("fleeing",false)
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
			if not was_fleeing and actor.get("fleeing",false):
				break # Cancel the old movement request once panic takes control.
			var old = actor.position.duplicate()
			var cost = Terrain.step_cost(heights,pos(actor),cell,int(definitions[actor.archetype].move_cost),board_width,board_height)
			actor.position = Hex.encode(cell)
			spend(actor,cost)
			emit("move",actor.name + " 移至 " + str(cell),{"actor_id":actor.id,"from":old,"to":actor.position.duplicate()})
			refresh_morale()
			if not actor.alive or is_terminal() or (not was_fleeing and actor.get("fleeing",false)):
				break
	elif kind == "KNOCKBACK":
		spend(actor,int(definitions[actor.archetype].knockback_cost))
		var target = unit(action.target_unit_id)
		emit("attack",actor.name+" 击退 → "+target.name,{"actor_id":actor.id,"target_id":target.id})
		apply_damage(actor.id,target.id,int(definitions[actor.archetype].knockback_damage),"击退")
		resolve_knockback(actor,target)
	elif kind == "TELEPORT":
		spend(actor,int(definitions[actor.archetype].teleport_cost))
		actor.position = action.target_cell.duplicate()
		emit("teleport",actor.name + " 瞬移至 " + str(actor.position),{"actor_id":actor.id,"to":actor.position.duplicate()})
	else:
		var d = definitions[actor.archetype]
		spend(actor,int(d.get("advantage_cost",d.cost)) if kind=="OVERHEAD_STRIKE" else int(d.cost))
		attack(actor,unit(action.target_unit_id),false,kind == "OVERHEAD_STRIKE")
	refresh_morale()
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
			if radius > 0 and u.reaction_ready and not u.get("stunned",false) and not u.get("fleeing",false):
				for cell in Hex.cells(board_width,board_height):
					if cell != pos(u) and Hex.distance(pos(u),cell) <= radius and Terrain.attack_height_allowed(heights,pos(u),cell,definitions[u.archetype].kind):
						zones[u.id].append(Hex.encode(cell))
		if can_act(u):
			legal_actions[u.id] = enumerate_legal_actions(u.id)
	return {"level_id":level_id,"level_name":level_name,"round":round_number,"phase":"finished" if is_terminal() else "battle","current_faction":faction,
		"undead_domination":domination,"domination_cap":domination_cap,"domination_regen":domination_regen,
		"board":{"width":board_width,"height":board_height,"hex_layout":setup.layout,"heights":heights.duplicate(true),"obstacles":obstacles.duplicate(true)},"units":units.duplicate(true),
		"definitions":definitions.duplicate(true),"zones":zones,"legal_actions":legal_actions,"winner":winner,"active_human":active_human(),
		"human_index":human_index,"initial_human_count":initial_human_count,"human_deaths":human_deaths,"rng_seed":initial_seed,"rng_state":str(rng.state),"action_history":history.duplicate(true)}
