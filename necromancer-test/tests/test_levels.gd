extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		printerr(message)
func _init():
	for level in range(1,14):
		var e = Rules.new(42,level)
		check(e.units.size()==(4 if level in [12,13] else (16 if level==7 else (2 if level==8 else (9 if level==9 else 6)))),"unit count in level %d" % level)
		var occupied = {}
		if level == 12:
			check(e.units.map(func(u): return u.archetype)==["undead_knight","archer","archer","archer"],"undead knight versus three archers")
		if level == 13:
			check(e.units.map(func(u): return u.archetype)==["zombie","zombie","zombie","knight"],"three zombies versus knight")
		if level == 11:
			check(e.units.map(func(u): return u.archetype)==["undead_knight","vampire","zombie","knight","spearman","spearman"],"knight level roster")
			check(e.unit("knight").hp==20 and e.unit("knight").ap==12 and e.unit("undead_knight").hp==10,"knight level stats")
		if level == 10:
			check(e.units.map(func(u): return u.archetype)==["undead_spearman","undead_archer","undead_shieldman","spearman","archer","shieldman"],"undead counterpart roster")
			check(e.heights.is_empty() and e.obstacles.is_empty(),"counterpart level flat terrain")
			check(e.units.map(func(u): return u.hp)==[7,7,15,14,10,30],"counterpart HP")
		for u in e.units:
			check(not occupied.has(e.pos(u)) and not Terrain.blocked(e.obstacles,e.pos(u)),"valid deployment")
			occupied[e.pos(u)] = true
		if level in [1,2,3]:
			check(e.heights.is_empty() and e.obstacles.is_empty(),"first three levels use clear flat terrain")
		if level in [4,5]:
			check(e.humans().map(func(u): return u.archetype)==["spearman","spearman","archer"],"new spear/archer roster")
		if level == 6:
			check(e.humans().map(func(u): return u.archetype)==["spearman","shieldman","shieldman"],"two independent shields and one spear")
			check(e.heights==Rules.new(42,5).heights,"levels five and six share canyon")
		if level == 7:
			check(e.board_width==20 and e.board_height==10 and e.heights.is_empty() and e.obstacles.is_empty(),"shortened clear plain")
			for archetype in ["vampire","zombie","spearman","archer","shieldman"]:
				var expected = {"vampire":2,"zombie":6,"spearman":4,"archer":2,"shieldman":2}
				check(e.units.filter(func(u): return u.archetype==archetype).size()==expected[archetype],"large map roster "+archetype)
		# Terrain alone must connect every deployment; occupancy is temporary.
		if level == 9:
			check(e.board_width==40 and e.board_height==10,"encirclement map extended to the right")
			check(e.units.filter(func(u): return u.archetype=="zombie").size()==8 and e.humans().size()==1 and e.humans()[0].archetype=="shieldman","encirclement test roster")
			check(e.heights.is_empty() and e.obstacles.is_empty(),"encirclement test flat clear terrain")
			var center = e.pos(e.unit("shield"))
			var ids = ["zombie_a","zombie_b","zombie_c","zombie_d","zombie_e","zombie_f"]
			for index in 6:
				var action = {"actor_id":ids[index],"kind":"MOVE","target_cell":Hex.encode(center+Hex.DIRECTIONS[index])}
				check(e.validate_action(action).valid,"one step to surround from each direction")
				e.execute_action(action)
				check(e.unit("shield").morale==[100,100,80,80,60,20][index],"test level exposes each encirclement threshold")
			check(e.enumerate_legal_actions("zombie_a").any(func(a): return a.kind=="OVERHEAD_STRIKE" and a.target_unit_id=="shield"),"flat encirclement enables advantage action")
		if level == 8:
			check(e.units.map(func(u): return u.archetype)==["vampire","spearman"],"test level roster")
			check(Hex.distance(e.pos(e.unit("vampire")),e.pos(e.unit("spear_a")))==1,"test units start adjacent")
			e.execute_action({"kind":"END_TURN"})
			var action = {"actor_id":"spear_a","kind":"KNOCKBACK","target_unit_id":"vampire"}
			check(e.validate_action(action).valid,"opening shove available")
			var hits = e.execute_action(action).filter(func(v): return v.type=="damage")
			check(hits.size()==2 and hits[0].amount==2 and hits[1].amount==4,"opening shove demonstrates two-level fall")
		var queue = [e.pos(e.units[0])]
		var visited = {queue[0]:true}
		var head = 0
		while head<queue.size():
			var cell = queue[head]
			head += 1
			for direction in Hex.DIRECTIONS:
				var next = cell+direction
				if not visited.has(next) and not Terrain.blocked(e.obstacles,next) and Terrain.step_cost(e.heights,cell,next,1,e.board_width,e.board_height)>0:
					visited[next] = true
					queue.append(next)
		for u in e.units:
			check(visited.has(e.pos(u)),"all deployments connected by walking")
	print("LEVEL RESULT: %d failures" % failures)
	quit(1 if failures else 0)
