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
	for level in range(1,8):
		var e = Rules.new(42,level)
		check(e.units.size()==(16 if level==7 else 6),"unit count in level %d" % level)
		var occupied = {}
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
