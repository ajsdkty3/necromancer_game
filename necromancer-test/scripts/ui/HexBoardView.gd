extends Node2D
const Terrain = preload("res://scripts/core/Terrain.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
var observation: Dictionary = {}
var highlighted: Array = []
var charge_path_cells: Array = []
var blocked_charge_cells: Array = []
var charge_attack_preview: Array = []
var danger_cells: Array = []
var danger_zones: Array = []
const ZONE_COLOR = Color("#ff354f")
const ZONE_FILL = Color(0.72,0.08,0.15,0.28)

func danger_layer_count(cell: Vector2i) -> int:
	var count = 0
	for zone in danger_zones:
		if cell in zone.cells:
			count += 1
	return count

func terrain_heights() -> Dictionary:
	return observation.get("board",{}).get("heights",{})

func surface_center(cell: Vector2i) -> Vector2:
	return Terrain.center(terrain_heights(),cell)

func top_polygon(cell: Vector2i) -> PackedVector2Array:
	var points = PackedVector2Array()
	for i in 6:
		points.append(surface_center(cell)+Vector2.from_angle(deg_to_rad(60*i-30))*(Hex.SIZE-1))
	return points

func cell_at_point(point: Vector2) -> Vector2i:
	# The subtle marker remains selectable even when terrain hides the unit.
	for u in display_units():
		if u.alive and point.distance_to(surface_center(Hex.decode(u.position))+unit_offset(u.id)) <= 25 and unit_is_occluded(u):
			return Hex.decode(u.position)
	var cells = board_cells()
	cells.reverse()
	for cell in cells:
		if Geometry2D.is_point_in_polygon(point,top_polygon(cell)):
			return cell
	return Vector2i(-999,-999)

func zone_edges(cells: Array) -> Array:
	var edges = []
	for cell in cells:
		for direction_index in 6:
			if cell + Hex.DIRECTIONS[direction_index] in cells:
				continue
			var edge_index = (6-direction_index) % 6
			var center = surface_center(cell)
			var a = center + Vector2.from_angle(deg_to_rad(60*edge_index-30)) * Hex.SIZE
			var b = center + Vector2.from_angle(deg_to_rad(60*(edge_index+1)-30)) * Hex.SIZE
			edges.append([a,b])
	return edges

func draw_zone_boundaries():
	for index in danger_zones.size():
		var zone = danger_zones[index]
		var color: Color = ZONE_COLOR
		var origin = surface_center(zone.center)
		# A tiny visual offset separates coincident contours of different owners.
		var outline_scale = 0.985 if index % 2 == 0 else 1.015
		for edge in zone_edges(zone.cells):
			var a: Vector2 = origin + (edge[0]-origin)*outline_scale
			var b: Vector2 = origin + (edge[1]-origin)*outline_scale
			draw_line(a,b,Color(color,0.10),10.0,true)
			draw_line(a,b,Color(color,0.24),6.0,true)
			draw_line(a,b,color,2.5,true)
			draw_line(a,b,color.lightened(0.45),0.8,true)
var selected_id = ""
var targeting = "DEFAULT"
var font: Font
signal playback_finished
var visual_units: Array = []
var pending_events: Array = []
var effect: Dictionary = {}
var effect_time = 0.0
var effect_duration = 0.0
const MOVE_STEP_DURATION = 0.10
const SHOT_WINDUP = 0.08
const SHOT_FLIGHT = 0.20

func is_ranged_shot() -> bool:
	if effect.get("type","") != "attack":
		return false
	var actor = visual_unit(effect.actor_id)
	return not actor.is_empty() and observation.definitions[actor.archetype].kind == "SHOOT"

func projectile_state() -> Dictionary:
	if not is_ranged_shot() or effect_time < SHOT_WINDUP:
		return {}
	var start = surface_center(Hex.decode(visual_unit(effect.actor_id).position))
	var finish = surface_center(Hex.decode(visual_unit(effect.target_id).position))
	var progress = clampf((effect_time-SHOT_WINDUP)/SHOT_FLIGHT,0.0,1.0)
	return {"head":start.lerp(finish,progress),"direction":(finish-start).normalized()}

func draw_projectile():
	var shot = projectile_state()
	if shot.is_empty():
		return
	var head: Vector2 = shot.head
	var direction: Vector2 = shot.direction
	var side = direction.orthogonal()
	draw_line(head-direction*38,head,Color(1.0,0.85,0.45,0.20),5.0,true)
	draw_line(head-direction*24,head,Color("#ffe6a0"),2.0,true)
	draw_colored_polygon(PackedVector2Array([head+direction*5,head-direction*5+side*4,head-direction*5-side*4]),Color("#ffffff"))
	draw_line(head-direction*23,head-direction*29+side*4,Color("#d7c5a0"),2.0,true)
	draw_line(head-direction*23,head-direction*29-side*4,Color("#d7c5a0"),2.0,true)

func guard_zones() -> Array:
	var result = []
	if observation.is_empty():
		return result
	var displayed_units = visual_units if is_playing() else observation.units
	for u in displayed_units:
		if not u.alive or not u.get("guarding",false):
			continue
		var radius = int(observation.definitions[u.archetype].get("guard_range",0))
		if radius <= 0:
			continue
		var center = Hex.decode(u.position)
		var cells = []
		for cell in board_cells():
			if Hex.distance(center,cell) <= radius:
				cells.append(cell)
		result.append({"owner_id":u.id,"center":center,"cells":cells})
	return result

func draw_guard_boundaries():
	# Guard is a persistent status, independent of movement/attack selection.
	for zone in guard_zones():
		var origin = surface_center(zone.center)
		for edge in zone_edges(zone.cells):
			# Keep white status contours just inside red opportunity contours.
			var a: Vector2 = origin+(edge[0]-origin)*0.94
			var b: Vector2 = origin+(edge[1]-origin)*0.94
			draw_line(a,b,Color(1,1,1,0.08),9.0,true)
			draw_line(a,b,Color(1,1,1,0.20),5.0,true)
			draw_line(a,b,Color.WHITE,2.0,true)

func is_playing() -> bool:
	return not visual_units.is_empty()

func stop_playback():
	visual_units = []
	pending_events = []
	effect = {}
	queue_redraw()

func play_events(events: Array, before: Dictionary):
	stop_playback()
	if not events.any(func(e): return e.type in ["attack","reaction","damage","protected","guard"] or (e.type == "move" and before.units.any(func(u): return u.id == e.actor_id and u.team == "undead"))):
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
			"heal":
				visual_unit(event.unit_id).hp = event.hp
			"move":
				if visual_unit(event.actor_id).team == "undead" or event.get("forced",false) or event.get("charge",false):
					effect = event
					effect_time = 0.0
					effect_duration = MOVE_STEP_DURATION
					return
				visual_unit(event.actor_id).position = event.to.duplicate()
			"teleport":
				visual_unit(event.actor_id).position = event.to.duplicate()
			"death":
				visual_unit(event.unit_id).alive = false
				visual_unit(event.unit_id).guarding = false
			"escape":
				visual_unit(event.unit_id).alive = false
			"flee":
				visual_unit(event.unit_id).fleeing = true
				visual_unit(event.unit_id).guarding = false
			"morale","rally":
				visual_unit(event.unit_id).morale = event.morale
				if event.type == "rally":
					visual_unit(event.unit_id).fleeing = false
			"guard_expired":
				visual_unit(event.actor_id).guarding = false
			"stun","stun_expired":
				visual_unit(event.unit_id).stunned = event.type=="stun"
			"attack","reaction","damage","protected","guard":
				effect = event
				effect_time = 0.0
				effect_duration = 0.24 if event.type == "damage" else 0.22
				if is_ranged_shot():
					effect_duration = SHOT_WINDUP + SHOT_FLIGHT
				if event.type == "damage":
					visual_unit(event.target).hp = event.hp
				elif event.type == "protected":
					effect_duration = 0.30
				elif event.type == "guard":
					visual_unit(event.actor_id).guarding = true
					effect_duration = 0.25
				return
	stop_playback()
	playback_finished.emit()

var last_hover_position = Vector2.INF

func _process(delta: float):
	if is_inside_tree():
		var hover = get_local_mouse_position()
		if hover != last_hover_position:
			last_hover_position = hover
			queue_redraw()
	if not is_playing():
		return
	effect_time += delta
	while is_playing() and effect_time >= effect_duration:
		var remainder = effect_time-effect_duration
		if effect.type == "move":
			visual_unit(effect.actor_id).position = effect.to.duplicate()
		advance_effect()
		if is_playing():
			effect_time = remainder
	queue_redraw()

func unit_offset(id: String) -> Vector2:
	if effect.is_empty():
		return Vector2.ZERO
	var t = clampf(effect_time / effect_duration,0.0,1.0)
	if effect.type == "move" and effect.actor_id == id:
		return (surface_center(Hex.decode(effect.to))-surface_center(Hex.decode(effect.from)))*t
	if effect.type == "protected" and effect.target == id:
		return Vector2(sin(t*TAU*3.0)*2.5*(1.0-t),0) if t < 0.4 else Vector2.ZERO
	if effect.type == "damage" and effect.target == id:
		return Vector2(sin(t * TAU * 3.0) * 7.0 * (1.0-t),-sin(t*PI)*3.0)
	if effect.type in ["attack","reaction"] and effect.actor_id == id:
		var actor = visual_unit(id)
		var target = visual_unit(effect.target_id)
		var direction = (surface_center(Hex.decode(target.position))-surface_center(Hex.decode(actor.position))).normalized()
		if is_ranged_shot():
			# Brief draw/recoil instead of the melee raise-and-slam.
			return -direction*4.0*sin(t*PI)
		var raised = Vector2(0,-10)-direction*3
		var impact = direction*10+Vector2(0,3)
		if t < 0.4:
			return Vector2.ZERO.lerp(raised,t/0.4)
		if t < 0.65:
			return raised.lerp(impact,(t-0.4)/0.25)
		return impact.lerp(Vector2.ZERO,(t-0.65)/0.35)
	return Vector2.ZERO

func display_units() -> Array:
	return visual_units if is_playing() else observation.get("units",[])

func unit_ground_position(u: Dictionary) -> Vector2:
	var ground = Hex.center(Hex.decode(u.position))
	if not effect.is_empty() and effect.type == "move" and effect.actor_id == u.id:
		ground = Hex.center(Hex.decode(effect.from)).lerp(Hex.center(Hex.decode(effect.to)),clampf(effect_time/effect_duration,0.0,1.0))
	return ground

func depth_items() -> Array:
	var items = []
	for cell in board_cells():
		items.append({"kind":"terrain","cell":cell,"depth":Hex.center(cell).y,"layer":0})
	for u in display_units():
		if u.alive:
			items.append({"kind":"unit","unit":u,"depth":unit_ground_position(u).y,"layer":1})
	items.sort_custom(func(a,b): return a.depth < b.depth if a.depth != b.depth else a.layer < b.layer)
	return items

func terrain_polygons(cell: Vector2i) -> Array:
	var top = top_polygon(cell)
	var polygons = [top]
	var drop = Vector2(0,Terrain.height_at(terrain_heights(),cell)*Terrain.LIFT)
	if drop.y > 0:
		for edge in [0,1,2]:
			polygons.append(PackedVector2Array([top[edge],top[edge+1],top[edge+1]+drop,top[edge]+drop]))
	return polygons

func unit_is_occluded(u: Dictionary) -> bool:
	var p = surface_center(Hex.decode(u.position))+unit_offset(u.id)
	var body = PackedVector2Array()
	for index in 16:
		body.append(p+Vector2.from_angle(TAU*index/16.0)*23.0)
	var ground_y = unit_ground_position(u).y
	for cell in board_cells():
		if Hex.center(cell).y <= ground_y or absf(surface_center(cell).x-p.x)>Hex.SIZE+23:
			continue
		for polygon in terrain_polygons(cell):
			if not Geometry2D.intersect_polygons(body,polygon).is_empty():
				return true
	return false

func draw_occluded_marker(u: Dictionary):
	var p = surface_center(Hex.decode(u.position))+unit_offset(u.id)
	var color = Color("#98ead0") if u.team == "undead" else Color("#ffcc88")
	draw_arc(p,24,0,TAU,40,Color(color,0.28),1.5,true)
	if u.id == selected_id:
		draw_arc(p,29,0,TAU,40,Color(Color("#fff3bd"),0.65),2.0,true)
	if get_local_mouse_position().distance_to(p) <= 25:
		var text = "%s  %d/%d" % [u.name,u.hp,u.max_hp]
		var width = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
		var label_position = p+Vector2(-width*0.5,-36)
		draw_style_box(hover_label_style(),Rect2(label_position+Vector2(-5,-17),Vector2(width+10,25)))
		draw_string(font,label_position,text,HORIZONTAL_ALIGNMENT_LEFT,-1,15,color)

func hover_label_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#132029")
	return style

func _draw():
	if font == null:
		font = ThemeDB.fallback_font
	for item in depth_items():
		if item.kind == "terrain":
			draw_terrain_cell(item.cell)
			if not observation.is_empty():
				draw_obstacle(item.cell)
		else:
			draw_unit(item.unit)
	draw_zone_boundaries()
	draw_guard_boundaries()
	for u in display_units():
		if u.alive and unit_is_occluded(u):
			draw_occluded_marker(u)
	draw_projectile()

func draw_terrain_cell(cell: Vector2i):
	var center = surface_center(cell)
	var points = top_polygon(cell)
	var height = Terrain.height_at(terrain_heights(),cell)
	# Front faces join the raised top to its base; back-to-front row drawing
	# keeps the next row's ground in front of the cliff foot.
	if height > 0:
		for edge in [0,1,2]:
			var a = points[edge]
			var b = points[edge+1]
			var drop = Vector2(0,height*Terrain.LIFT)
			draw_colored_polygon(PackedVector2Array([a,b,b+drop,a+drop]),Color("#66513b") if edge == 1 else Color("#473c30"))
			for tier in height:
				draw_line(a+Vector2(0,(tier+1)*Terrain.LIFT),b+Vector2(0,(tier+1)*Terrain.LIFT),Color("#302c26"),1.0,true)
	var fill = [Color("#243b35"),Color("#526548"),Color("#7b8457"),Color("#92946b"),Color("#aaa68a"),Color("#c4bfaa")][mini(height,5)]
	if cell in highlighted:
		fill = Color("#315965").lightened(height*0.10) if targeting in ["DEFAULT","MOVE","CHARGE"] else Color("#74483e").lightened(height*0.08)
		if targeting == "TELEPORT":
			fill = Color("#74483e")
	if targeting == "CHARGE" and cell in blocked_charge_cells:
		fill = Color("#666b73")
	if targeting == "CHARGE" and (cell in charge_path_cells or cell in highlighted):
		fill = Color("#83cce8") if cell in highlighted else Color("#245b9c")
	draw_colored_polygon(points,fill)
	if cell in charge_attack_preview:
		draw_colored_polygon(points,Color(1.0,0.12,0.20,0.58))
		var outline = points.duplicate()
		outline.append(outline[0])
		draw_polyline(outline,Color("#ff5269"),2.5,true)
	# Blend once per controller, including overlaps with reachable cells.
	# Draw on the terrain surface before units so labels remain readable.
	for layer in danger_layer_count(cell):
		draw_colored_polygon(points,ZONE_FILL)
	points.append(points[0])
	draw_polyline(points,Color("#879575") if height > 0 else Color("#47615a"),1.0,true)
	if height > 0:
		draw_string(font,center+Vector2(15,-16),str(height),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#e6e4ba"))

func draw_obstacle(cell: Vector2i):
	if Terrain.blocked(observation.board.get("obstacles",{}),cell):
		var p = surface_center(cell)
		draw_circle(p+Vector2(0,7),24,Color(0,0,0,0.35))
		var rock = PackedVector2Array([p+Vector2(-23,7),p+Vector2(-17,-13),p+Vector2(-2,-23),p+Vector2(17,-14),p+Vector2(24,7),p+Vector2(9,17),p+Vector2(-13,16)])
		draw_colored_polygon(rock,Color("#696e73"))
		draw_colored_polygon(PackedVector2Array([rock[0],rock[1],rock[2],p+Vector2(1,-2)]),Color("#9b9c94"))
		draw_colored_polygon(PackedVector2Array([p+Vector2(1,-2),rock[3],rock[4],rock[5]]),Color("#444b52"))
		rock.append(rock[0])
		draw_polyline(rock,Color("#c2bca1"),1.2,true)
		draw_string(font,p+Vector2(-14,8),"障碍",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)

func draw_unit(u: Dictionary):
	var p = surface_center(Hex.decode(u.position)) + unit_offset(u.id)
	var color = Color("#98ead0") if u.team == "undead" else Color("#ffcc88")
	var hit = not effect.is_empty() and effect.type == "damage" and effect.target == u.id
	var protected_hit = not effect.is_empty() and effect.type == "protected" and effect.target == u.id
	if hit:
		color = Color("#ff7777")
	if u.id == selected_id:
		draw_arc(p,29,0,TAU,32,Color("#fff3bd"),2.5,true)
	draw_circle(p,23,unit_background(u,hit))
	if u.get("stunned",false):
		draw_arc(p,26,0,TAU,32,Color("#e6c6ff"),2.0,true)
		draw_string(font,p+Vector2(-14,-31),"眩晕",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#e6c6ff"))
	if u.get("guarding",false):
		draw_arc(p,27,0,TAU,40,Color("#dceeff"),2.0,true)
		draw_string(font,p+Vector2(-14,-31),"守护",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#dceeff"))
	if protected_hit:
		var progress = clampf(effect_time/effect_duration,0.0,1.0)
		var flash = sin(clampf((progress-0.3)/0.7,0.0,1.0)*PI)
		draw_circle(p,25,Color(1,1,1,flash*0.85))
		draw_arc(p,28+flash*5,0,TAU,40,Color(1,1,1,flash),3.0,true)
		draw_string(font,p+Vector2(-14,-32),"免伤",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
	for index in danger_zones.size():
		if danger_zones[index].owner_id == u.id:
			draw_arc(p,25,0,TAU,40,ZONE_COLOR,2.0,true)
	if hit:
		draw_string(font,p+Vector2(-10,-30-effect_time*25),"-%d" % effect.amount,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("#ffaaaa"))
	var width = font.get_string_size(u.name,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x
	draw_string(font,p+Vector2(-width/2,-1),u.name,HORIZONTAL_ALIGNMENT_LEFT,-1,15,color)
	var hp = "%d/%d" % [u.hp,u.max_hp]
	width = font.get_string_size(hp,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	draw_string(font,p+Vector2(-width/2,17),hp,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)

func unit_background(u: Dictionary, hit: bool = false) -> Color:
	if u.team == "human" and (u.get("fleeing",false) or int(u.get("morale",100))==0):
		return Color(1,1,1,0.45)
	return Color("#702b35") if hit else Color("#132029")

func board_cells() -> Array:
	var dimensions = observation.get("board",{})
	return Hex.cells(int(dimensions.get("width",20)),int(dimensions.get("height",10)))
