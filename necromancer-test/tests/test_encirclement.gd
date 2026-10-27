extends SceneTree
const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Morale = preload("res://scripts/core/MoraleRules.gd")
const Board = preload("res://scripts/ui/HexBoardView.gd")
var failures = 0
func check(ok: bool, label: String):
	if not ok:
		failures += 1
		printerr(label)
func _init():
	var e = Rules.new(42,7)
	var center = Vector2i(6,4)
	e.unit("spear_a").position = Hex.encode(center)
	var undead = e.units.filter(func(u): return u.team=="undead")
	for u in undead:
		u.position = [0,0]
	for count in range(7):
		if count>0:
			undead[count-1].position = Hex.encode(center+Hex.DIRECTIONS[count-1])
		e.refresh_morale()
		var expected = [100,100,100,80,80,60,20][count]
		check(e.unit("spear_a").morale==expected,"adjacent enemy threshold %d" % count)
		e.refresh_morale()
		check(e.unit("spear_a").morale==expected,"encirclement is not cumulative")
	undead[5].position = [0,0]
	e.refresh_morale()
	check(e.unit("spear_a").morale==60,"partial escape removes full encirclement penalty")
	undead[4].alive = false
	e.refresh_morale()
	check(e.unit("spear_a").morale==80,"dead enemies do not surround")
	undead[4].alive = true
	undead[5].position = Hex.encode(center+Hex.DIRECTIONS[5])
	e.unit("spear_a").hp = 1
	e.refresh_morale()
	check(e.unit("spear_a").morale==0 and e.unit("spear_a").fleeing,"full surround plus low HP starts flight")
	var b = Board.new()
	check(b.unit_background(e.unit("spear_a"))==Color(1,1,1,0.45),"panicked human uses translucent white background")
	check(b.unit_background(e.unit("vampire"))!=Color(1,1,1,0.45),"undead background unchanged")
	e.unit("spear_a").fleeing = false
	e.unit("spear_a").morale = 80
	check(b.unit_background(e.unit("spear_a"))!=Color(1,1,1,0.45),"rallied human restores normal background")
	b.free()
	print("ENCIRCLEMENT RESULT: %d failures" % failures)
	quit(1 if failures else 0)
