extends Node2D

const Rules = preload("res://scripts/core/BattleEngine.gd")
const Hex = preload("res://scripts/core/HexGrid.gd")
const Board = preload("res://scripts/ui/HexBoardView.gd")
const AI = preload("res://scripts/ai/AIController.gd")
const AI_MOVE_DELAY = 0.10
const AI_ACTION_DELAY = 0.38
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
	level_menu.get_popup().add_radio_check_item("第一关",1)
	level_menu.get_popup().add_radio_check_item("第二关",2)
	level_menu.get_popup().add_radio_check_item("第三关",3)
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
	hint.text = "左键选中 · 右键移动\n数字键按动作栏顺序选择动作\n左键选目标 · Esc取消\nWASD / 中键拖动平移视角\n同高1点 · 上下台阶2点 · 落差>1不可走"
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
	append_log("第 1 轮 · 亡灵先手 · 支配力 20/20")
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
	board.observation = observation
	board.selected_id = selected
	board.targeting = mode
	board.highlighted = []
	board.danger_cells = []
	board.danger_zones = []
	if not u.is_empty() and u.team == "undead" and observation.current_faction == "undead" and observation.winner == "" and mode in ["DEFAULT","MOVE"]:
		for enemy in observation.units:
			if enemy.alive and enemy.team != u.team:
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
	board.queue_redraw()
	level_menu.text = "菜单 · %s ▾" % observation.level_name
	for index in level_menu.get_popup().item_count:
		if level_menu.get_popup().is_item_radio_checkable(index):
			level_menu.get_popup().set_item_checked(index,level_menu.get_popup().get_item_id(index) == current_level)
	var human_total = observation.units.filter(func(unit): return unit.team == "human").size()
	status.text = "第 %d 轮 · %s\n支配力 %d / 20\n人类进度 %d / %d" % [observation.round,
		"亡灵回合" if observation.current_faction == "undead" else "人类回合",
		observation.undead_domination,mini(human_total,observation.human_index),human_total]
	end_button.disabled = observation.current_faction != "undead" or observation.winner != "" or board.is_playing()
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	if u.is_empty():
		details.text = "单位详情\n\n左键选择单位\n绿色：亡灵  ·  金色：人类"
	else:
		var d = observation.definitions[u.archetype]
		var resource_text = "全队支配力 %d/20" % observation.undead_domination if u.team == "undead" else "AP %d/6" % u.ap
		details.text = "%s · %s\n阵营：%s\nHP %d / %d\n%s" % [u.name,d.role,"亡灵" if u.team == "undead" else "人类",u.hp,u.max_hp,resource_text]
		details.text += "\n魂归主宰：死亡恢复5支配力" if u.team == "undead" else "\n众志成城：每相邻人类友军伤害+1"
		if u.get("guarding",false):
			details.text += "\n守护中：至下次人类回合开始"
		add_action("MOVE","移动：同高%d %s · 跨级+1" % [d.move_cost,"支配力" if u.team == "undead" else "AP"])
		add_action(d.kind,"%s：%d点 · 范围%d · 伤害%d–%d" % [d.label,d.cost,d.range,d.damage_min,d.damage_max])
		if d.has("teleport_range"):
			add_action("TELEPORT","瞬移：%d支配力 · 范围%d" % [d.teleport_cost,d.teleport_range])
		if d.has("guard_cost"):
			add_action("GUARD","守护：%d AP · 相邻6格 · 1回合" % d.guard_cost)
		var cancel = Button.new()
		cancel.text = "[%d] 取消" % (actions.get_child_count() + 1)
		cancel.pressed.connect(func(): mode = "DEFAULT"; refresh())
		actions.add_child(cancel)
	result_panel.visible = observation.winner != "" and not board.is_playing()
	result_label.text = "胜利 · 人类全灭" if observation.winner == "undead" else "失败 · 亡灵全灭"

func add_action(kind: String, label: String):
	var button = Button.new()
	if kind == "MOVE":
		button.tooltip_text = "蓝色底色：可达格；红色边框：敌方借机攻击范围。\n走入不触发，从红框格继续移动或离开时触发。"
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

func select_level(id: int):
	if id in [1,2,3]:
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
	append_log("第 1 轮 · 亡灵先手 · 支配力 20/20")
	refresh()

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
	board.position += direction.normalized() * 500 * delta
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
	var old_faction = observation.current_faction
	var events = engine.execute_action(action)
	board.play_events(events,observation)
	for event in events:
		append_log(event.message)
	if engine.faction != old_faction:
		selected = ""
		mode = "DEFAULT"
	refresh()

func _input(event: InputEvent):
	# Release remains visible even if the pointer finishes over a UI panel.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		dragging = false
	if event is InputEventMouseMotion and dragging:
		board.position += event.relative
		get_viewport().set_input_as_handled()

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
		mode = "DEFAULT"
		refresh()
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
	if not Hex.inside(cell):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if mode in ["DEFAULT","MOVE"]:
			try_target(cell,"MOVE")
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if mode != "DEFAULT":
		try_target(cell,mode)
		return
	for u in observation.units:
		if u.alive and Hex.decode(u.position) == cell:
			selected = u.id
			refresh()
			return

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
