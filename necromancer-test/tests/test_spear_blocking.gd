extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func _init():
	for direction in Hex.DIRECTIONS:
		var e = Rules.new(42)
		e.faction = "human"
		var actor = e.unit("spear_a")
		actor.position = [6,4]
		var middle = e.pos(actor)+direction
		var end = middle+direction
		e.unit("vampire").position = Hex.encode(end)
		e.unit("zombie_a").position = Hex.encode(middle)
		var offset = Hex.to_offset(middle)
		var key = "%d,%d" % [offset.x,offset.y]
		var action = {"actor_id":actor.id,"kind":"SPEAR_THRUST","target_unit_id":"vampire"}
		check(e.validate_action(action).valid,"units do not obstruct spear")
		e.heights[key] = 1
		check(not e.validate_action(action).valid,"higher intermediate cell blocks rear target")
		check(e.attack_targets(actor,e.unit("zombie_a")) == ["zombie_a"],"front target can be hit without piercing raised cell")
		e.heights.clear()
		e.obstacles[key] = true
		check(not e.validate_action(action).valid,"rock blocks rear target")
		e.obstacles.clear()
		e.unit("zombie_a").alive = false
		e.create_corpse({"id":"fixture","name":"test","position":Hex.encode(middle)})
		check(e.validate_action(action).valid and e.attack_targets(actor,e.unit("vampire")).size()==2,"corpse can be pierced and hit")
	check(Terrain.attack_height_allowed({},Vector2i(0,0),Vector2i(1,1),"SPEAR_THRUST",{"1,0":true}),"off-axis target has alternate clear route")
	check(not Terrain.attack_height_allowed({},Vector2i(0,0),Vector2i(1,1),"SPEAR_THRUST",{"1,0":true,"0,1":true}),"both off-axis routes blocked")
	print("Spear blocking failures: ",failures)
	quit(failures)
