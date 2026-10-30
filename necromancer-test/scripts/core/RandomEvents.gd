extends RefCounted
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const Morale = preload("res://scripts/core/MoraleRules.gd")
const NAMES = {"REINFORCEMENTS":"援兵","AWAKENING":"意外苏醒","SOUL_RAMPAGE":"灵魂暴走","BACKLASH":"魔力失控","SURGE":"魔力涌动"}

static func empty_cells(e) -> Array:
	return Hex.cells(e.board_width,e.board_height).filter(func(c): return e.occupant(c).is_empty() and not Terrain.blocked(e.obstacles,c))

static func candidates(e) -> Dictionary:
	var empty = empty_cells(e)
	var edge = empty.filter(func(c): return Hex.to_offset(c).x == e.board_width-1)
	var undead = e.units.filter(func(u): return u.alive and u.team == "undead")
	var awakening = []
	for u in undead:
		var cells = empty.filter(func(c): return Hex.distance(e.pos(u),c)==1)
		if not cells.is_empty():
			awakening.append({"actor":u,"cells":cells})
	var result = {"BACKLASH":[],"SURGE":[]}
	if not edge.is_empty():
		result.REINFORCEMENTS = edge
	if not awakening.is_empty():
		result.AWAKENING = awakening
	if not undead.is_empty():
		result.SOUL_RAMPAGE = undead
	return result

static func pick(e, values: Array):
	return values[e.rng.randi_range(0,values.size()-1)]

static func roll(e):
	if e.is_terminal() or e.random_event_used or e.round_number < 4 or e.random_event_checked_round == e.round_number:
		return
	e.random_event_checked_round = e.round_number
	if e.rng.randf() >= 0.5:
		return
	# Sampling eligible events is equivalent to redrawing impossible events.
	var options = candidates(e)
	apply(e,pick(e,options.keys()),options)

static func spawn(e, archetype: String, team: String, cell: Vector2i):
	var d = e.definitions[archetype]
	var u = {"id":"event_"+archetype,"name":d.name+"（增援）","team":team,"archetype":archetype,"position":Hex.encode(cell),"hp":int(d.hp),"max_hp":int(d.hp),"ap":int(d.get("max_ap",6)) if team=="human" else 0,"max_ap":int(d.get("max_ap",6)) if team=="human" else 0,"alive":true,"guarding":false,"reaction_ready":true,"stunned":false,"stun_skip_active":false}
	if team == "human":
		u.merge({"morale_base":100,"morale":100,"max_morale":100,"fleeing":false,"flee_trapped":false,"flee_until_round":0,"flee_target":[],"escaped":false})
		e.initial_human_count += 1
	e.units.append(u)
	e.emit("unit_created",u.name+" 出现在 "+str(cell),{"unit":u.duplicate(true)})

static func apply(e, kind: String, options: Dictionary):
	if e.random_event_used or e.is_terminal() or not options.has(kind):
		return
	e.random_event_used = true
	e.random_event_kind = kind
	e.emit("random_event","随机事件："+NAMES[kind]+"（本局仅一次）",{"kind":kind})
	match kind:
		"REINFORCEMENTS":
			spawn(e,"knight","human",pick(e,options[kind]))
			for u in e.humans():
				if not u.alive:
					continue
				u.max_morale = int(u.get("max_morale",100))+20
				var desired = mini(int(u.max_morale),int(u.morale)+20)
				u.morale_base = desired+Morale.penalties(u,e.initial_human_count,e.human_deaths,e.units)
				u.morale = desired
				u.fleeing = false
				u.flee_trapped = false
				u.flee_until_round = 0
				u.flee_target = []
				e.emit("rally",u.name+" 援兵鼓舞：士气+20，上限+20，停止溃逃",{"unit_id":u.id,"morale":desired,"max_morale":u.max_morale})
		"AWAKENING":
			var choice = pick(e,options[kind])
			spawn(e,"zombie","undead",pick(e,choice.cells))
		"SOUL_RAMPAGE":
			var target = pick(e,options[kind])
			e.domination_cap += 20
			var hp = int(target.hp)
			target.hp = 0
			e.emit("damage","灵魂暴走："+target.name+" 立即阵亡",{"source":target.id,"target":target.id,"amount":hp,"hp":0})
			e.resolve_death(target)
			e.domination = mini(e.domination_cap,e.domination+20)
		"BACKLASH":
			e.domination = 0
		"SURGE":
			e.domination_cap += 10
			e.domination = mini(e.domination_cap,e.domination+10)
	e.emit("resource","事件结算：支配力%d/%d" % [e.domination,e.domination_cap],{"remaining":e.domination,"cap":e.domination_cap})
	e.refresh_morale()
	e.check_winner()
