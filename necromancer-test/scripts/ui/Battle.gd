extends Node2D

const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Board = preload("res://scripts/ui/HexBoardView.gd")
const AI = preload("res://scripts/ai/AIController.gd")
const Traits = preload("res://scripts/core/FactionTraits.gd")
const Charge = preload("res://scripts/core/ChargeRules.gd")
const Terrain = preload("res://scripts/core/Terrain.gd")
const AI_MOVE_DELAY = 0.10
const AI_ACTION_DELAY = 0.38
const EDGE_PAN_MARGIN = 24.0
var engine = Rules.new()
var ai = AI.new()
var board: Node2D
var selected = ""
var mode = "DEFAULT"
var legal: Array = []
var observation: Dictionary
var log_view: RichTextLabel
var details: Label
var actions: VBoxContainer
var status: Label
var end_button: Button
var result_panel: PanelContainer
var result_label: Label
var dragging = false
var ai_delay = 0.0
var ai_calls = 0
var font: SystemFont
var hint: Label
var current_level = 1
var level_menu: MenuButton
var move_hint: Label
var move_preview: Dictionary = {}
var map_bounds = Rect2()
const CAMERA_EDGE_PADDING = 40.0

func _ready():
	DisplayServer.window_set_title("亡灵法师战棋 · 单场战斗 MVP")
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","SimHei"])
	board = Board.new()
	board.font = font
	add_child(board)
	board.playback_finished.connect(refresh)
	board.position = Vector2(365,290)
	var canvas = CanvasLayer.new()
	add_child(canvas)
	var root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_hint = Label.new()
	move_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	move_hint.z_index = 100
	move_hint.add_theme_color_override("font_color",Color("#fff3bd"))
	move_hint.add_theme_color_override("font_outline_color",Color("#081015"))
	move_hint.add_theme_constant_override("outline_size",8)
	move_hint.visible = false
	root.add_child(move_hint)
	var theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	root.theme = theme
	canvas.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	level_menu = MenuButton.new()
	root.add_child(level_menu)
	level_menu.set_anchors_preset(Control.PRESET_CENTER_TOP)
	level_menu.offset_left = -105
	level_menu.offset_right = 105
	level_menu.offset_top = 16
	level_menu.offset_bottom = 58
	var levels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))
	for id in levels:
		level_menu.get_popup().add_radio_check_item(levels[id].name,int(id))
	level_menu.get_popup().add_separator()
	level_menu.get_popup().add_item("重新开始",100)
	level_menu.get_popup().id_pressed.connect(select_level)
	var log_panel = panel(root,Vector2(16,16),Vector2(310,305))
	var log_box = VBoxContainer.new()
	log_panel.add_child(log_box)
	var title = Label.new()
	title.text = "战斗记录"
	log_box.add_child(title)
	log_view = RichTextLabel.new()
	log_view.custom_minimum_size = Vector2(286,255)
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_box.add_child(log_view)
	var detail_panel = panel(root,Vector2(16,365),Vector2(310,390))
	detail_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	detail_panel.offset_left = 16
	detail_panel.offset_right = 326
	detail_panel.offset_top = -405
	detail_panel.offset_bottom = -15
	var detail_box = VBoxContainer.new()
	detail_panel.add_child(detail_box)
	details = Label.new()
	details.custom_minimum_size = Vector2(286,120)
	detail_box.add_child(details)
	actions = VBoxContainer.new()
	detail_box.add_child(actions)
	var top = panel(root,Vector2.ZERO,Vector2(300,180))
	top.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top.offset_left = -316
	top.offset_right = -16
	top.offset_top = 16
	top.offset_bottom = 196
	var top_box = VBoxContainer.new()
	top.add_child(top_box)
	status = Label.new()
	top_box.add_child(status)
	end_button = Button.new()
	end_button.text = "结束亡灵回合"
	end_button.pressed.connect(func(): perform({"kind":"END_TURN"}))
	root.add_child(end_button)
	end_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	end_button.offset_left = -236
	end_button.offset_right = -16
	end_button.offset_top = -76
	end_button.offset_bottom = -16
	hint = Label.new()
	hint.text = "左键选中 · 右键移动\n数字键按动作栏顺序选择动作\n左键选目标 · Esc取消\nWASD / 中键拖动 / 鼠标贴边平移\n同高1点 · 上下台阶2点 · 落差>1不可走"
	top_box.add_child(hint)
	result_panel = panel(root,Vector2.ZERO,Vector2(350,150))
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.offset_left = -175
	result_panel.offset_right = 175
	result_panel.offset_top = -75
	result_panel.offset_bottom = 75
	var result_box = VBoxContainer.new()
	result_panel.add_child(result_box)
	result_label = Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size",28)
	result_box.add_child(result_label)
	var again = Label.new()
	again.text = "顶部菜单可重新开始或切换关卡"
	again.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_box.add_child(again)
	append_log("第 1 轮 · 亡灵先手 · 支配力 %d/%d" % [engine.domination,engine.domination_cap])
	refresh()

func panel(parent: Control, location: Vector2, dimensions: Vector2) -> PanelContainer:
	var p = PanelContainer.new()
	p.position = location
	p.custom_minimum_size = dimensions
	p.size = dimensions
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#101c27")
	style.border_color = Color("#486675")
	style.set_border_width_all(1)
	style.set_content_margin_all(12)
	style.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel",style)
	parent.add_child(p)
	return p

func append_log(message: String):
	log_view.append_text(message + "\n")

func selected_unit() -> Dictionary:
	for u in observation.units:
		if u.id == selected:
			return u
	return {}

func refresh():
	observation = engine.get_observation()
	var u = selected_unit()
	if not u.is_empty() and not u.alive:
		selected = ""
		mode = "DEFAULT"
		u = {}
	legal = engine.enumerate_legal_actions(selected) if not selected.is_empty() else []
	move_preview = engine.path_tree(selected) if not u.is_empty() and u.alive else {}
	move_hint.visible = false
	board.observation = observation
	update_map_bounds()
	clamp_board_position()
	board.selected_id = selected
	board.targeting = mode
	board.highlighted = []
	board.charge_path_cells = []
	board.blocked_charge_cells = []
	board.charge_attack_preview = []
	board.danger_cells = []
	board.danger_zones = []
	var zone_owners = []
	if not u.is_empty() and observation.winner == "":
		if u.team == "human":
			zone_owners = [u]
		elif observation.current_faction == "undead" and mode in ["DEFAULT","MOVE"]:
			zone_owners = observation.units.filter(func(other): return other.team != u.team)
	for enemy in zone_owners:
		if enemy.alive:
			var region = [Hex.decode(enemy.position)]
			for encoded_cell in observation.zones.get(enemy.id,[]):
				var cell = Hex.decode(encoded_cell)
				region.append(cell)
				if cell not in board.danger_cells:
					board.danger_cells.append(cell)
			if region.size() > 1:
				board.danger_zones.append({"owner_id":enemy.id,"center":Hex.decode(enemy.position),"cells":region})
	var wanted = "MOVE" if mode == "DEFAULT" else mode
	for action in legal:
		if action.kind != wanted:
			continue
		if action.has("target_cell"):
			board.highlighted.append(Hex.decode(action.target_cell))
		elif action.has("target_unit_id"):
			for target in observation.units:
				if target.id == action.target_unit_id:
					board.highlighted.append(Hex.decode(target.position))
	if mode == "CHARGE" and not u.is_empty():
		var charge_paths = Charge.paths(u,observation.board,observation.units,int(observation.definitions[u.archetype].charge_range))
		var charge_start = Hex.decode(u.position)
		var charge_range = int(observation.definitions[u.archetype].charge_range)
		for direction in Hex.DIRECTIONS:
			if charge_start+direction*charge_range in board.highlighted:
				continue
			for distance in range(1,charge_range+1):
				var path_cell = charge_start+direction*distance
				if Hex.inside(path_cell,int(observation.board.width),int(observation.board.height)):
					board.blocked_charge_cells.append(path_cell)
		for endpoint in board.highlighted:
			for path_cell in charge_paths.get(endpoint,[]):
				if path_cell not in board.charge_path_cells:
					board.charge_path_cells.append(path_cell)
	board.queue_redraw()
	update_charge_preview()
	level_menu.text = "菜单 · %s ▾" % observation.level_name
	for index in level_menu.get_popup().item_count:
		if level_menu.get_popup().is_item_radio_checkable(index):
			level_menu.get_popup().set_item_checked(index,level_menu.get_popup().get_item_id(index) == current_level)
	var human_total = observation.units.filter(func(unit): return unit.team == "human").size()
	status.text = "第 %d 轮 · %s\n支配力 %d / %d\n人类进度 %d / %d" % [observation.round,
		"亡灵回合" if observation.current_faction == "undead" else "人类回合",
		observation.undead_domination,observation.domination_cap,mini(human_total,observation.human_index),human_total]
	end_button.disabled = observation.current_faction != "undead" or observation.winner != "" or board.is_playing()
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	if u.is_empty():
		details.text = "单位详情\n\n左键选择单位\n绿色：亡灵  ·  金色：人类"
	else:
		var d = observation.definitions[u.archetype]
		var resource_text = "全队支配力 %d/%d" % [observation.undead_domination,observation.domination_cap] if u.team == "undead" else "AP %d/%d" % [u.ap,u.max_ap]
		details.text = "%s · %s\n阵营：%s\nHP %d / %d\n%s" % [u.name,d.role,"亡灵" if u.team == "undead" else "人类",u.hp,u.max_hp,resource_text]
		details.text += "\n魂归主宰：死亡恢复5支配力" if u.team == "undead" else "\n众志成城：每相邻人类友军伤害+1"
		if int(d.zoc) > 0:
			details.text += "\n借机攻击：%s / 1（己方回合开始恢复）" % ("1" if u.reaction_ready else "0")
		if u.get("guarding",false):
			details.text += "\n守护中：至下次所属阵营回合开始"
		if u.get("stunned",false):
			details.text += "\n眩晕：本回合无法行动" if u.get("stun_skip_active",false) else "\n眩晕：下个所属阵营回合无法行动"
		if mode == "CHARGE":
			details.text += "\n直线冲锋3格，移动不触发借机攻击\n到达自动攻击前方3格，含友伤并击退"
		if u.team == "human":
			details.text += "\n士气：%d / 100" % u.get("morale",100)
			if u.get("fleeing",false):
				if u.get("flee_trapped",false):
					details.text += "\n完全被围：无法移动或恢复士气\n解除后重新溃逃2回合"
				else:
					details.text += " · 溃逃剩余%d回合" % maxi(0,int(u.flee_until_round)-int(observation.round)+1)
		add_action("MOVE","移动：同高%d %s · 跨级+1" % [d.move_cost,"支配力" if u.team == "undead" else "AP"])
		var damage_text = str(int(d.damage_min)) if d.damage_min == d.damage_max else "%d–%d" % [d.damage_min,d.damage_max]
		add_action(d.kind,"%s：%d点 · %s · 伤害%s" % [d.label,d.cost,"直线冲锋恰好%d格" % d.charge_range if d.kind=="CHARGE" else "范围%d" % d.range,damage_text])
		if d.kind=="CHARGE":
			actions.get_child(actions.get_child_count()-1).text += "\n前方3格含友伤 · 击退1格\n冲锋移动不触发借机攻击"
		if d.get("ordinary_knockback",false):
			actions.get_child(actions.get_child_count()-1).text += "\n击退1格；受阻不位移，下降另算坠落伤害"
		if d.kind=="SHOOT":
			actions.get_child(actions.get_child_count()-1).text += "\n向上高差≤2，向下不限；中间单位不阻挡"
		if d.has("guard_cost"):
			add_action("GUARD","守护：%d%s · 相邻6格 · 1回合" % [d.guard_cost,"支配力" if u.team == "undead" else "AP"])
		var bonus = Traits.damage_bonus(u,observation.units)
		var heavy_damage = str((int(d.damage_min)+bonus)*2) if d.damage_min == d.damage_max else "%d–%d" % [(int(d.damage_min)+bonus)*2,(int(d.damage_max)+bonus)*2]
		if d.has("overhead_damage"):
			heavy_damage = str(int(d.overhead_damage)+bonus)
		if d.has("stomp_cost"):
			add_action("WAR_STOMP","优势动作·战争践踏：%d点 · 范围%d\n伤害%d–%d · 击退1格，击退或击杀后跟进" % [d.stomp_cost,d.stomp_range,d.stomp_damage_min,d.stomp_damage_max])
		elif d.has("knockback_cost"):
			add_action("KNOCKBACK","优势动作·击退：%d%s · 范围%d\n伤害%d，后退1格；坠落每级另受%d伤害" % [d.knockback_cost,"支配力" if u.team == "undead" else "AP",d.knockback_range,d.knockback_damage,d.get("fall_damage_per_height",2)])
		else:
			if d.has("advantage_heal"):
				add_action("OVERHEAD_STRIKE","优势动作·%s：%d点\n造成%d伤害，恢复自身%d生命（不超过上限）" % [d.advantage_label,d.get("advantage_cost",d.cost),d.overhead_damage,d.advantage_heal])
			elif d.has("advantage_hits"):
				add_action("OVERHEAD_STRIKE","优势动作·%s：%d点\n连续%d次，每次%d–%d伤害 · 高处或包围目标" % [d.advantage_label,d.get("advantage_cost",d.cost),d.advantage_hits,d.advantage_damage_min,d.advantage_damage_max])
			else:
				add_action("OVERHEAD_STRIKE","优势动作·%s：%d点\n伤害%s · 范围%d · 高处或包围目标" % [d.get("advantage_label","当头猛击"),d.get("advantage_cost",d.cost),heavy_damage,d.range])
		if d.get("advantage_stun",false):
			actions.get_child(actions.get_child_count()-1).text += "\n眩晕：下个所属阵营回合无法行动，不叠加"
		if d.has("teleport_range"):
			add_action("TELEPORT","瞬移：%d支配力 · 范围%d" % [d.teleport_cost,d.teleport_range])
		var cancel = Button.new()
		cancel.text = "[%d] 取消" % (actions.get_child_count() + 1)
		cancel.disabled = board.is_playing()
		cancel.pressed.connect(cancel_action)
		actions.add_child(cancel)
	result_panel.visible = observation.winner != "" and not board.is_playing()
	result_label.text = "胜利 · 人类全灭" if observation.winner == "undead" else "失败 · 亡灵全灭"

func add_action(kind: String, label: String):
	var button = Button.new()
	if kind in ["KNOCKBACK","OVERHEAD_STRIKE","WAR_STOMP"]:
		button.tooltip_text = "优势动作：自身高于目标，或敌方目标相邻六格内有至少3名存活己方单位（包括行动者）。\n仍需满足范围、资源和近战高度差不超过1级的限制。"
	if kind == "MOVE":
		button.tooltip_text = "蓝色底色：可达格；半透明红色与红边：敌方借机攻击范围，重叠处红色更深。\n走入不触发，从红色区域继续移动或离开时触发。"
	if kind == "CHARGE":
		button.tooltip_text = "消耗5点，直线移动恰好3格；冲锋移动不触发借机攻击。\n到达自动攻击正前方、左右前方3格中的所有单位（含友军），每个目标基础5伤害并向远离骑士方向击退1格。\n后方障碍、单位、更高地形或越界会阻止击退；伤害照常结算。向下击退另结算每级2点坠落伤害。"
	var available = legal.any(func(a): return a.kind == kind)
	var reason = ""
	if not available:
		reason = "（无合法目标 / 资源不足）"
		var u = selected_unit()
		if observation.winner != "":
			reason = "（战斗已结束）"
		elif observation.current_faction != "undead":
			reason = "（AI行动中）"
		elif u.team != "undead":
			reason = "（敌方单位）"
		elif u.get("stunned",false):
			reason = "（眩晕中）"
	button.text = "[%d] %s" % [actions.get_child_count() + 1,label] + ("\n" + reason if reason != "" else "")
	button.disabled = not available or observation.current_faction != "undead" or board.is_playing()
	button.pressed.connect(func():
		if kind == "GUARD":
			perform({"actor_id":selected,"kind":"GUARD"})
		else:
			mode = kind
			refresh())
	actions.add_child(button)

func perform(action: Dictionary):
	if board.is_playing() or observation.winner != "" or observation.current_faction != "undead":
		return
	var previous = observation.current_faction
	var events = engine.execute_action(action)
	board.play_events(events,observation)
	for event in events:
		append_log(event.message)
	mode = "DEFAULT"
	if engine.faction != previous:
		selected = ""
		ai_calls = 0
	refresh()

func cancel_action():
	if board.is_playing():
		return
	mode = "DEFAULT"
	refresh()

func select_level(id: int):
	if JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json")).has(str(id)):
		current_level = id
	elif id != 100:
		return
	level_menu.get_popup().hide()
	restart_battle()

func restart_battle():
	board.stop_playback()
	engine = Rules.new(-1,current_level)
	selected = ""
	mode = "DEFAULT"
	ai_calls = 0
	ai_delay = 0.0
	log_view.clear()
	append_log(engine.level_name)
	append_log("第 1 轮 · 亡灵先手 · 支配力 %d/%d" % [engine.domination,engine.domination_cap])
	refresh()
	var level_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))[str(current_level)]
	if level_config.has("camera_focus_offset"):
		var focus = level_config.camera_focus_offset
		board.position = get_viewport_rect().size*0.5-board.surface_center(Hex.from_offset(int(focus[0]),int(focus[1])))
		clamp_board_position()

func _process(delta: float):
	var direction = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		direction.y += 1
	if Input.is_physical_key_pressed(KEY_S):
		direction.y -= 1
	if Input.is_physical_key_pressed(KEY_A):
		direction.x += 1
	if Input.is_physical_key_pressed(KEY_D):
		direction.x -= 1
	if not dragging and DisplayServer.get_name() != "headless" and get_window().has_focus() and get_viewport().gui_get_hovered_control() == null and not level_menu.get_popup().visible:
		direction += edge_pan_direction(get_viewport().get_mouse_position(),get_viewport_rect().size)
	board.position += direction.normalized() * 500 * delta
	clamp_board_position()
	update_move_hint()
	update_charge_preview()
	if board.is_playing() or observation.current_faction != "human" or observation.winner != "":
		return
	ai_delay -= delta
	if ai_delay > 0:
		return
	var actor_id = observation.active_human
	var choices = engine.enumerate_legal_actions(actor_id)
	var action = ai.choose_action(observation,choices)
	ai_calls += 1
	if ai_calls > 60 or action.is_empty() or not engine.validate_action(action).valid:
		action = {"actor_id":actor_id,"kind":"END_UNIT"}
	ai_delay = AI_MOVE_DELAY if action.kind == "MOVE" else AI_ACTION_DELAY
	append_log("AI 决策：%s · %s" % [actor_id,action.kind])
	if not ai.focus_plan.is_empty():
		append_log("AI 集火：%s · 价值%d · 预计剩余输出%d / 目标HP%d" % [engine.unit(ai.focus_plan.target_id).name,ai.focus_plan.value,ai.focus_plan.damage,ai.focus_plan.hp])
	var old_faction = observation.current_faction
	var events = engine.execute_action(action)
	board.play_events(events,observation)
	for event in events:
		append_log(event.message)
	if engine.faction != old_faction:
		selected = ""
		mode = "DEFAULT"
	refresh()

func edge_pan_direction(pointer: Vector2, viewport_size: Vector2) -> Vector2:
	if not Rect2(Vector2.ZERO,viewport_size).has_point(pointer):
		return Vector2.ZERO
	var direction = Vector2.ZERO
	if pointer.x < EDGE_PAN_MARGIN:
		direction.x = 1
	elif pointer.x > viewport_size.x-EDGE_PAN_MARGIN:
		direction.x = -1
	if pointer.y < EDGE_PAN_MARGIN:
		direction.y = 1
	elif pointer.y > viewport_size.y-EDGE_PAN_MARGIN:
		direction.y = -1
	return direction.normalized()

func update_map_bounds():
	var cells = board.board_cells()
	if cells.is_empty():
		map_bounds = Rect2()
		return
	map_bounds = Rect2(board.surface_center(cells[0]),Vector2.ZERO)
	for cell in cells:
		# Include both elevated tops and the bottom of cliff faces.
		for center in [board.surface_center(cell),Hex.center(cell)]:
			map_bounds = map_bounds.expand(center-Vector2.ONE*Hex.SIZE)
			map_bounds = map_bounds.expand(center+Vector2.ONE*Hex.SIZE)

func clamp_board_position():
	board.position = bounded_board_position(board.position,get_viewport_rect().size)

func bounded_board_position(desired: Vector2, viewport_size: Vector2) -> Vector2:
	if not map_bounds.has_area():
		return desired
	# Keep map edges reachable outside the fixed left and right HUD panels.
	var inset_x = minf(342.0,viewport_size.x*0.28)
	var view_start = Vector2(inset_x,76.0)
	var view_end = Vector2(viewport_size.x-inset_x,viewport_size.y-90.0)
	var result = desired
	for axis in 2:
		var lower = view_end[axis]-CAMERA_EDGE_PADDING-map_bounds.end[axis]
		var upper = view_start[axis]+CAMERA_EDGE_PADDING-map_bounds.position[axis]
		if lower > upper:
			result[axis] = (view_start[axis]+view_end[axis]-map_bounds.position[axis]-map_bounds.end[axis])*0.5
		else:
			result[axis] = clampf(desired[axis],lower,upper)
	return result

func _input(event: InputEvent):
	if event is InputEventMouseMotion:
		update_move_hint(event.position)
		update_charge_preview(event.position)
	# Release remains visible even if the pointer finishes over a UI panel.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		dragging = false
	if event is InputEventMouseMotion and dragging:
		board.position += event.relative
		clamp_board_position()
		get_viewport().set_input_as_handled()

func movement_hint_at(cell: Vector2i) -> String:
	var u = selected_unit()
	if u.is_empty() or not u.alive or board.is_playing() or observation.winner != "" or observation.current_faction != "undead" or mode not in ["DEFAULT","MOVE"]:
		return ""
	if not Hex.inside(cell,int(observation.board.width),int(observation.board.height)) or not engine.occupant(cell).is_empty():
		return ""
	if not move_preview.has(cell):
		return "不可到达 / 资源不足"
	return "%d%s" % [move_preview[cell].steps,"支配力" if u.team == "undead" else "AP"]

func update_move_hint(pointer: Vector2 = get_viewport().get_mouse_position()):
	if not is_instance_valid(move_hint):
		return
	move_hint.visible = false
	if get_viewport().gui_get_hovered_control() != null or level_menu.get_popup().visible:
		return
	var cell = board.cell_at_point(board.get_global_transform_with_canvas().affine_inverse()*pointer)
	var text = movement_hint_at(cell)
	if text.is_empty():
		return
	move_hint.text = text
	move_hint.size = move_hint.get_minimum_size()
	move_hint.position = (pointer+Vector2(18,-32)).clamp(Vector2.ZERO,get_viewport_rect().size-move_hint.size)
	move_hint.visible = true

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and not event.shift_pressed:
		var index = -1
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			index = event.keycode - KEY_1
		elif event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9:
			index = event.keycode - KEY_KP_1
		if index >= 0:
			if not board.is_playing() and observation.winner == "" and observation.current_faction == "undead" and index < actions.get_child_count():
				var button = actions.get_child(index) as Button
				if not button.disabled:
					button.pressed.emit()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_action()
		get_viewport().set_input_as_handled()
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		dragging = true
		return
	if board.is_playing():
		return
	if observation.winner != "" or observation.current_faction != "undead":
		return
	var cell = board.cell_at_point(board.get_global_transform_with_canvas().affine_inverse() * event.position)
	if not Hex.inside(cell,int(observation.board.width),int(observation.board.height)):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if mode in ["DEFAULT","MOVE"]:
			try_target(cell,"MOVE")
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if mode == "CHARGE":
		try_target(cell,mode)
		return
	for u in observation.units:
		if u.alive and u.id == selected and Hex.decode(u.position) == cell:
			selected = ""
			mode = "DEFAULT"
			refresh()
			get_viewport().set_input_as_handled()
			return
	if mode != "DEFAULT":
		try_target(cell,mode)
		return
	for u in observation.units:
		if u.alive and Hex.decode(u.position) == cell:
			selected = u.id
			refresh()
			return

func charge_preview_at(cell: Vector2i) -> Array:
	var actor = selected_unit()
	if mode!="CHARGE" or actor.is_empty() or board.is_playing() or observation.current_faction!="undead" or observation.winner!="":
		return []
	var paths = Charge.paths(actor,observation.board,observation.units,int(observation.definitions[actor.archetype].charge_range))
	for action in legal:
		if action.kind!="CHARGE":
			continue
		var endpoint = Hex.decode(action.target_cell)
		if cell not in paths.get(endpoint,[]):
			continue
		var result = []
		for direction in Hex.DIRECTIONS:
			var target = endpoint+direction
			if Hex.inside(target,int(observation.board.width),int(observation.board.height)) and Charge.target_in_direction(Hex.decode(actor.position),endpoint,target) and Terrain.attack_height_allowed(observation.board.heights,endpoint,target,"CHARGE"):
				result.append(target)
		return result
	return []

func update_charge_preview(pointer: Vector2 = Vector2.INF):
	if not is_instance_valid(board) or observation.is_empty():
		return
	if pointer==Vector2.INF:
		pointer = get_viewport().get_mouse_position()
	var preview = []
	if mode=="CHARGE" and get_viewport().gui_get_hovered_control()==null and not level_menu.get_popup().visible:
		var local = board.get_global_transform_with_canvas().affine_inverse()*pointer
		preview = charge_preview_at(board.cell_at_point(local))
	if board.charge_attack_preview!=preview:
		board.charge_attack_preview = preview
		board.queue_redraw()

func try_target(cell: Vector2i, kind: String):
	for action in legal:
		if action.kind != kind:
			continue
		if action.has("target_cell") and Hex.decode(action.target_cell) == cell:
			perform(action)
			return
		if action.has("target_unit_id"):
			for u in observation.units:
				if u.id == action.target_unit_id and Hex.decode(u.position) == cell:
					perform(action)
					return
	append_log("目标非法、不可到达或资源不足")
