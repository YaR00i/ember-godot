extends Node3D
## A disposable composition stage, explicitly requested separately from main-map work.

@onready var rig = $ShotRig
@onready var actors: Array[Node3D] = [$ActorA, $ActorB]
var _target := 0
var _moving := false
var _time := 0.0
var _status: Label
var _preview_state: EmberExploreState
var _mechanism_history: UndoRedo
var _mechanism_actions: RefCounted
var _mechanism: Node3D
var _mechanism_state: EmberExploreState
var _mechanism_label: Label
var _shell_status: Label
var _shell_visuals: Dictionary = {}
var _tea_status: Label
var _tea_shop: EmberInteract
var _quest_status: Label


func _ready() -> void:
	# Never route a presentation preview into the author's real save/quest state.
	_preview_state = EmberExploreState.new()
	_preview_state.persistence_enabled = false
	_preview_state.restore_enabled = false
	$DialogueLayer/InteractionUi.economy_state = _preview_state
	$QuestLayer/InteractionUi.economy_state = _preview_state
	_tea_shop = EmberInteract.new()
	_tea_shop.kind = "shop"
	_tea_shop.shop_id = "story_tea_shop"
	add_child(_tea_shop)
	_seed_quest_trial()
	_build_ui()
	$StoryPreview.attach_ui()


func _exit_tree() -> void:
	if is_instance_valid(_mechanism_history):
		_mechanism_history.clear_history()
		_mechanism_history.free()
	if is_instance_valid(_mechanism_state): _mechanism_state.free()
	if is_instance_valid(_preview_state):
		_preview_state.free()


func stop_background_motion() -> void:
	_moving = false


func _process(delta: float) -> void:
	if is_instance_valid(_mechanism_label) and is_instance_valid(_mechanism):
		_mechanism_label.text = _mechanism.status() + "\nРакушек найдено: %d" % int(_mechanism_state.inventory.get("shore_shell", 0))
	_time += delta
	if _moving and not $StoryPreview.active:
		actors[1].position.z = sin(_time) * 0.7
	_status.text = rig.status + "   ·   цель: " + ["А", "Б"][_target]
	if _quest_status:
		_quest_status.text = "Доставка уже выполнена\n%s · монет: %d" % ["Завершено" if bool(_preview_state.flags.get("harbor_cargo_reward", false)) else "Вернуться за наградой", int(_preview_state.inventory.get("coin", 0))]

	if _tea_status:
		var quest := EmberQuestCatalog.projection(EmberQuestCatalog.definition("story_tea_errand"), _preview_state.flags)
		_tea_status.text = "Куплено: %d/2 · монет: %d\n%s" % [int(_preview_state.flags.get("story_tea_bought", 0)), int(_preview_state.inventory.get("coin", 0)), "Возьми поручение" if quest.status == "available" else "Выполнено" if quest.status == "done" else "Купи чай и вернись к смотрителю"]

	if _shell_status:
		var delivered := bool(_preview_state.flags.get("story_shell_delivered", false))
		_shell_status.text = "В сумке: %d/3 · монет: %d\n%s" % [int(_preview_state.inventory.get("shore_shell", 0)), int(_preview_state.inventory.get("coin", 0)), "Передано · выполнено" if delivered else "Собери и передай смотрителю"]


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode
	if is_instance_valid(_mechanism):
		if key == KEY_ESCAPE: stop_mechanism_trial()
		return
	if $QuestLayer/InteractionUi.is_open():
		if key == KEY_F:
			$QuestLayer/InteractionUi.advance()
			get_viewport().set_input_as_handled()
		return
	if $StoryPreview.active:
		return
	if key >= KEY_1 and key <= KEY_6:
		rig.shot = key - KEY_1
	elif key == KEY_TAB:
		_set_target(1 - _target)
	elif key == KEY_SPACE:
		_moving = not _moving
	elif key == KEY_R:
		_reset()
	elif key == KEY_H:
		$Controls/Panel.visible = not $Controls/Panel.visible


func _set_target(index: int) -> void:
	_target = index
	rig.primary_anchor = NodePath("../" + ["ActorA", "ActorB"][index] + "/Anchor")
	rig.secondary_anchor = NodePath("../" + ["ActorB", "ActorA"][index] + "/Anchor")
	rig.axis_side = 1 if index == 0 else -1


func _reset() -> void:
	$QuestLayer/InteractionUi.close()
	$StoryPreview.restore()
	_moving = false
	actors[0].position = Vector3(-1.2, 0, 0)
	actors[1].position = Vector3(1.2, 0, 0)
	$Item.position = Vector3(0, 0.88, 0.9)
	$Item.rotation = Vector3.ZERO
	$StoryText/Caption.text = ""
	rig.distance_scale = 1.0
	rig.lens_fov = 38.0
	rig.height_offset = 0.0
	rig.transition_seconds = 0.6
	rig.axis_side = 1
	rig.shot = 0
	_set_target(0)
	# Rebuild only the small lab panel to reflect the restored values.
	$Controls.free()
	_build_ui()


func _seed_quest_trial() -> void:
	_preview_state.flags = {"harbor_cargo_status": "active", "harbor_cargo_meet": true, "harbor_cargo_visit": true, "harbor_cargo_place": true}
	_preview_state.inventory.clear()


func start_quest_trial() -> String:
	if $StoryPreview.active or $QuestLayer/InteractionUi.is_open():
		return "Сначала заверши текущий показ"
	return $QuestLayer/InteractionUi.activate($QuestGiver)


func reset_quest_trial() -> void:
	_reset()
	_seed_quest_trial()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Controls"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size.x = 290
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var title := Label.new()
	title.text = "КАМЕРА · ПРОБА РАКУРСОВ"
	column.add_child(title)
	for i in rig.TITLES.size():
		var button := Button.new()
		button.text = "%d  %s" % [i + 1, rig.TITLES[i]]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func(): rig.shot = i)
		column.add_child(button)
	var target_button := Button.new()
	target_button.text = "Tab · поменять А ↔ Б"
	target_button.focus_mode = Control.FOCUS_NONE
	target_button.pressed.connect(func(): _set_target(1 - _target))
	column.add_child(target_button)
	_slider(column, "Дистанция", 0.4, 2.5, 0.05, rig.distance_scale, func(v): rig.distance_scale = v)
	_slider(column, "Угол обзора", 20.0, 80.0, 1.0, rig.lens_fov, func(v): rig.lens_fov = v)
	_slider(column, "Высота камеры", -0.6, 0.8, 0.05, rig.height_offset, func(v): rig.height_offset = v)
	_slider(column, "Переход, секунды", 0.0, 2.0, 0.05, rig.transition_seconds, func(v): rig.transition_seconds = v)
	var motion := Button.new()
	motion.text = "Пробел · движение Б"
	motion.focus_mode = Control.FOCUS_NONE
	motion.pressed.connect(func(): _moving = not _moving)
	column.add_child(motion)
	var reset := Button.new()
	reset.text = "R · сброс"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_reset)
	column.add_child(reset)
	var note := Label.new()
	note.text = "H · скрыть панель для просмотра\nСлайдеры — до перезапуска.\nПривязки/стартовые значения: ShotRig."
	note.add_theme_font_size_override("font_size", 13)
	column.add_child(note)
	_status = Label.new()
	_status.position = Vector2(330, 20)
	_status.add_theme_color_override("font_color", Color(1, 0.9, 0.65))
	layer.add_child(_status)
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "Место под диалог · здесь будет реплика персонажа"
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle.offset_top = -70
	subtitle.offset_bottom = -28
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	layer.add_child(subtitle)
	var quest_panel := PanelContainer.new()
	quest_panel.name = "QuestTrial"
	quest_panel.anchor_left = 1.0
	quest_panel.anchor_right = 1.0
	quest_panel.offset_left = -340
	quest_panel.offset_right = -16
	quest_panel.offset_top = 16
	layer.add_child(quest_panel)
	var quest_column := VBoxContainer.new()
	quest_panel.add_child(quest_column)
	var quest_title := Label.new()
	quest_title.text = "Груз у берега · финал квеста"
	quest_column.add_child(quest_title)
	_quest_status = Label.new()
	quest_column.add_child(_quest_status)
	for spec in [["Поговорить со смотрителем", start_quest_trial], ["Сбросить пробу квеста", reset_quest_trial]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(spec[1])
		quest_column.add_child(button)

	var tea_title := Label.new()
	tea_title.text = "ПОКУПКА · ЧАЙ ДЛЯ СМОТРИТЕЛЯ"
	quest_column.add_child(tea_title)
	_tea_status = Label.new()
	quest_column.add_child(_tea_status)
	for spec in [["Начать / сбросить чай · 30 монет", reset_tea_trial], ["Чай · поговорить со смотрителем", start_tea_trial], ["Открыть лавку у причала", open_tea_shop]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(spec[1])
		quest_column.add_child(button)

	var shell_title := Label.new()
	shell_title.text = "СОБРАТЬ И ПЕРЕДАТЬ · РАКУШКИ"
	quest_column.add_child(shell_title)
	_shell_status = Label.new()
	quest_column.add_child(_shell_status)
	for spec in [["Начать / сбросить ракушки", reset_shell_trial], ["Ракушки · поговорить со смотрителем", start_shell_trial], ["Подобрать одну ракушку", pickup_shell_trial], ["Выбросить одну ракушку", drop_shell_trial]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(spec[1])
		quest_column.add_child(button)

	var mechanism_button := Button.new()
	mechanism_button.name = "StartPressureGateTrial"
	mechanism_button.text = "ИГРАТЬ · ящик, плита, проход"
	mechanism_button.pressed.connect(start_mechanism_trial)
	quest_column.add_child(mechanism_button)


func start_mechanism_trial() -> void:
	if $StoryPreview.active or $QuestLayer/InteractionUi.is_open(): return
	stop_mechanism_trial()
	_mechanism_state = EmberExploreState.new()
	_mechanism_state.persistence_enabled = false
	_mechanism_state.restore_enabled = false
	_mechanism_state.reset_new_game()
	_mechanism_state.inventory.clear()
	_mechanism = preload("res://addons/ember_import/ember_pressure_gate_builder.gd").build_workshop("camera_preset_study")
	_mechanism.position = Vector3(250, 0, 0)
	_mechanism.progress_state = _mechanism_state
	for body in _mechanism.get_children():
		if body is RigidBody3D: body.progress_state = _mechanism_state
	_mechanism_history = UndoRedo.new()
	_mechanism_actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd").new()
	_mechanism_actions.configure(_mechanism_history)
	add_child(_mechanism)
	var player := EmberPlayer.new()
	player.name = "TrialPlayer"
	player.progress_state = _mechanism_state
	player.position = Vector3(-40, 0.2, 52)
	_mechanism.add_child(player)
	var follow := EmberFollowCamera.new()
	follow.name = "TrialCamera"
	follow.target = player
	follow.yaw = 0.0
	follow.polar_angle = 0.65
	follow.follow_distance = 240.0
	follow.fov = 50.0
	player.camera_rig = follow
	_mechanism.add_child(follow)
	var layer := CanvasLayer.new()
	layer.name = "TrialControls"
	layer.layer = 40
	_mechanism.add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(16, 16)
	layer.add_child(column)
	var help := Label.new()
	help.text = "WASD · ходьба | F · взять / поставить / подобрать\nПоставь оба ящика на плиты → дверь. Любой рычаг → лампа. Схему можно переподключить."
	column.add_child(help)
	_mechanism_label = Label.new()
	column.add_child(_mechanism_label)
	var prompt := Label.new()
	column.add_child(prompt)
	player.interact_hud = prompt
	var graph_button := Button.new()
	graph_button.text = "Схема механизма · провода"
	graph_button.name = "OpenMechanismGraph"
	graph_button.pressed.connect(open_mechanism_graph, CONNECT_DEFERRED)
	column.add_child(graph_button)
	var reset := Button.new()
	reset.name = "RestartTrial"
	reset.text = "Заново"
	reset.pressed.connect(start_mechanism_trial, CONNECT_DEFERRED)
	column.add_child(reset)
	var back := Button.new()
	back.name = "LeaveTrial"
	back.text = "Esc · вернуться к камерам и квестам"
	back.pressed.connect(stop_mechanism_trial, CONNECT_DEFERRED)
	column.add_child(back)
	$Controls.hide()
	if $StoryPreview.has_node("StoryControls"): $StoryPreview.get_node("StoryControls").hide()
	$StoryPreview.enable_preview_shortcuts = false


func open_mechanism_graph() -> void:
	if not is_instance_valid(_mechanism): return
	var window := _mechanism.get_node_or_null("MechanismWindow") as Window
	if window == null:
		window = preload("res://addons/ember_import/ember_mechanism_workspace.gd").new()
		window.name = "MechanismWindow"
		_mechanism.add_child(window)
		window.setup(self, _mechanism_actions)
		var actor := _mechanism.get_node("TrialPlayer") as EmberPlayer
		window.visibility_changed.connect(func():
			if is_instance_valid(actor):
				actor.velocity = Vector3.ZERO
				actor.set_physics_process(not window.visible)
		)
	window.popup_centered_clamped(Vector2i(1420, 900), 0.95)


func stop_mechanism_trial() -> void:
	if is_instance_valid(_mechanism_history):
		_mechanism_history.clear_history()
		_mechanism_history.free()
	_mechanism_history = null
	_mechanism_actions = null
	if is_instance_valid(_mechanism):
		remove_child(_mechanism)
		_mechanism.free()
	_mechanism = null
	_mechanism_label = null
	if is_instance_valid(_mechanism_state): _mechanism_state.free()
	_mechanism_state = null
	if is_inside_tree() and has_node("Controls"):
		$Controls.show()
		if $StoryPreview.has_node("StoryControls"): $StoryPreview.get_node("StoryControls").show()
		$StoryPreview.enable_preview_shortcuts = true
		$ShotRig/Camera3D.make_current()


func start_shell_trial() -> String:
	if $StoryPreview.active or $QuestLayer/InteractionUi.is_open():
		return "Сначала заверши текущий показ"
	return $QuestLayer/InteractionUi.activate($ShellGiver)


func reset_shell_trial() -> void:
	$QuestLayer/InteractionUi.close()
	for key in ["story_shell_status", "story_shell_meet", "story_shell_delivered"]:
		_preview_state.flags.erase(key)
	_preview_state.inventory.clear()
	_preview_state.world_items.clear()
	for index in 3:
		_preview_state.ensure_authored_item("shell_trial_%d" % index, "shore_shell", "camera_preset_study", Transform3D(Basis.IDENTITY, Vector3(0.64 + index * 0.16, 0.755, 0.9)))
	_refresh_shell_visuals()


func pickup_shell_trial() -> void:
	if $QuestLayer/InteractionUi.is_open(): return
	for id in _preview_state.world_items:
		var row: Dictionary = _preview_state.world_items[id]
		if str(row.get("itemId", "")) == "shore_shell" and int(row.get("count", 0)) > 0:
			_preview_state.pickup_world_item(str(id), false)
			break
	_refresh_shell_visuals()


func drop_shell_trial() -> void:
	if $QuestLayer/InteractionUi.is_open(): return
	_preview_state.drop_inventory_item("shore_shell", "camera_preset_study", Vector3(0.8, 0.755, 0.9), false)
	_refresh_shell_visuals()


func _refresh_shell_visuals() -> void:
	for visual in _shell_visuals.values():
		if is_instance_valid(visual): visual.queue_free()
	_shell_visuals.clear()
	for id in _preview_state.world_items:
		var row: Dictionary = _preview_state.world_items[id]
		if str(row.get("itemId", "")) != "shore_shell" or int(row.get("count", 0)) <= 0: continue
		var visual: Node3D = load("res://prefabs/items/shore_shell.tscn").instantiate()
		add_child(visual)
		var at: Array = row.position
		visual.position = Vector3(float(at[0]), float(at[1]), float(at[2]))
		visual.scale = Vector3.ONE * 0.6
		_shell_visuals[id] = visual


func start_tea_trial() -> String:
	if $StoryPreview.active or $QuestLayer/InteractionUi.is_open():
		return "Сначала заверши текущий показ"
	return $QuestLayer/InteractionUi.activate($TeaGiver)


func open_tea_shop() -> String:
	if $StoryPreview.active or $QuestLayer/InteractionUi.is_open():
		return "Сначала заверши текущий показ"
	return $QuestLayer/InteractionUi.activate(_tea_shop)


func reset_tea_trial() -> void:
	$QuestLayer/InteractionUi.close()
	for key in ["story_tea_status", "story_tea_meet", "story_tea_bought", "story_tea_reward"]:
		_preview_state.flags.erase(key)
	_preview_state.shop_stock.erase("story_tea_shop")
	_preview_state.inventory = {"coin": 30}


func _slider(parent: Control, caption: String, low: float, high: float, step: float, initial: float, changed: Callable) -> void:
	var label := Label.new()
	label.text = "%s: %.2f" % [caption, initial]
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = initial
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value):
		label.text = "%s: %.2f" % [caption, value]
		changed.call(value))
	parent.add_child(slider)
