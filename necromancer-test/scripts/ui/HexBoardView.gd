extends Node2D
const Hex = preload("res://scripts/core/HexGrid.gd")
var observation: Dictionary = {}
var highlighted: Array = []
var danger_cells: Array = []
var selected_id = ""
var targeting = "DEFAULT"
var font: Font
signal playback_finished
var visual_units: Array = []
var pending_events: Array = []
var effect: Dictionary = {}
var effect_time = 0.0
var effect_duration = 0.0

func is_playing() -> bool:
	return not visual_units.is_empty()

func stop_playback():
	visual_units = []
	pending_events = []
	effect = {}
	queue_redraw()

func play_events(events: Array, before: Dictionary):
	stop_playback()
	if not events.any(func(e): return e.type in ["attack","reaction","damage"]):
		return
	visual_units = before.units.duplicate(true)
	pending_events = events.duplicate(true)
	advance_effect()

func visual_unit(id: String) -> Dictionary:
	for u in visual_units:
		if u.id == id:
			return u
	return {}

func advance_effect():
	effect = {}
	while not pending_events.is_empty():
		var event = pending_events.pop_front()
		match event.type:
			"move","teleport":
				visual_unit(event.actor_id).position = event.to.duplicate()
			"death":
				visual_unit(event.unit_id).alive = false
			"attack","reaction","damage":
				effect = event
				effect_time = 0.0
				effect_duration = 0.24 if event.type == "damage" else 0.22
				if event.type == "damage":
					visual_unit(event.target).hp = event.hp
				return
	stop_playback()
	playback_finished.emit()

func _process(delta: float):
	if not is_playing():
		return
	effect_time += delta
	if effect_time >= effect_duration:
		advance_effect()
	queue_redraw()

func unit_offset(id: String) -> Vector2:
	if effect.is_empty():
		return Vector2.ZERO
	var t = clampf(effect_time / effect_duration,0.0,1.0)
	if effect.type == "damage" and effect.target == id:
		return Vector2(sin(t * TAU * 3.0) * 7.0 * (1.0-t),-sin(t*PI)*3.0)
	if effect.type in ["attack","reaction"] and effect.actor_id == id:
		var actor = visual_unit(id)
		var target = visual_unit(effect.target_id)
		var direction = (Hex.center(Hex.decode(target.position))-Hex.center(Hex.decode(actor.position))).normalized()
		var raised = Vector2(0,-10)-direction*3
		var impact = direction*10+Vector2(0,3)
		if t < 0.4:
			return Vector2.ZERO.lerp(raised,t/0.4)
		if t < 0.65:
			return raised.lerp(impact,(t-0.4)/0.25)
		return impact.lerp(Vector2.ZERO,(t-0.65)/0.35)
	return Vector2.ZERO

func _draw():
	if font == null:
		font = ThemeDB.fallback_font
	for cell in Hex.cells():
		var center = Hex.center(cell)
		var points = PackedVector2Array()
		for i in 6:
			points.append(center + Vector2.from_angle(deg_to_rad(60*i-30)) * (Hex.SIZE-1))
		var fill = Color("#182b30")
		if cell in highlighted:
			fill = Color("#315965") if targeting in ["DEFAULT","MOVE"] else Color("#74483e")
		elif cell in danger_cells:
			fill = Color("#50272d")
		draw_colored_polygon(points,fill)
		points.append(points[0])
		draw_polyline(points,Color("#47616a"),1.0,true)
		if cell in danger_cells:
			# Inset red border stays visible without covering the blue reachable fill.
			var danger_outline = PackedVector2Array()
			for i in 7:
				danger_outline.append(center + Vector2.from_angle(deg_to_rad(60*i-30)) * (Hex.SIZE-5))
			draw_polyline(danger_outline,Color("#ff626b"),2.0,true)
	if observation.is_empty():
		return
	for u in (visual_units if is_playing() else observation.units):
		if not u.alive:
			continue
		var p = Hex.center(Hex.decode(u.position)) + unit_offset(u.id)
		var color = Color("#98ead0") if u.team == "undead" else Color("#ffcc88")
		var hit = not effect.is_empty() and effect.type == "damage" and effect.target == u.id
		if hit:
			color = Color("#ff7777")
		if u.id == selected_id:
			draw_arc(p,29,0,TAU,32,Color("#fff3bd"),2.5,true)
		draw_circle(p,23,Color("#702b35") if hit else Color("#132029"))
		if hit:
			draw_string(font,p+Vector2(-10,-30-effect_time*25),"-%d" % effect.amount,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#ffaaaa"))
		var width = font.get_string_size(u.name,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
		draw_string(font,p+Vector2(-width/2,-1),u.name,HORIZONTAL_ALIGNMENT_LEFT,-1,15,color)
		var hp = "%d/%d" % [u.hp,u.max_hp]
		width = font.get_string_size(hp,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
		draw_string(font,p+Vector2(-width/2,17),hp,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
