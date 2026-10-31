extends Node
## Playback controls for the isolated native AnimationPlayer study.
## No quest progression or dialogue traversal lives on this visual timeline.
signal finished(outcome: String)
const DialogueCue = preload("res://scripts/ember_story_dialogue_cue.gd")
@export var presentation_id := "cargo_delivery"
@export var presentation_name := "Передача посылки"

@export var clip_name: StringName = &"story_example"
@export_group("Разговоры по времени")
@export var dialogue_cues: Array[DialogueCue] = []
@export_group("Одиночный разговор — прежняя проба")
@export var dialogue: EmberDialogueResource
@export_range(0.0, 120.0, 0.1) var dialogue_time := 2.2
@export_group("Проба управления")
@export var enable_preview_shortcuts := false
@onready var player: AnimationPlayer = $"../AnimationPlayer"
@onready var dialogue_ui: EmberInteractionUi = $"../DialogueLayer/InteractionUi"
var active := false
var paused := false
var status := "P · посмотреть сценку"
var _baseline: Array[Dictionary] = []
var _panel_was_visible := true
var _time_slider: HSlider
var _status_label: Label
var _display_time := 0.0
var _waiting_dialogue := false
var _run_cues: Array[Dictionary] = []
var _next_cue := 0
var _finish_after_dialogue := false
var _caption_was_visible := true
var _action_driven := false
var _previous_economy: EmberExploreState
var _previous_session: EmberDialogueSession
var _previous_camera: WeakRef
var _previous_camera_input_owner: WeakRef
var _previous_camera_input_enabled := false


func start_for_action(action_ui: EmberInteractionUi) -> String:
	if active or dialogue_ui.is_open():
		return "Сценка уже запущена"
	if not _baseline.is_empty():
		restore()
	_previous_economy = dialogue_ui.economy_state
	_previous_session = dialogue_ui.conversation_session()
	dialogue_ui.economy_state = action_ui.economy_state
	dialogue_ui.set_conversation_session(action_ui.conversation_session())
	_action_driven = true
	if not start():
		_release_action_context()
		return status
	return ""


func advance_dialogue() -> void:
	if _waiting_dialogue:
		dialogue_ui.advance()


func _ready() -> void:
	dialogue_ui.dialogue_closed.connect(_on_dialogue_closed)
	player.animation_finished.connect(func(name: StringName):
		if name == clip_name and active:
			if _next_cue < _run_cues.size():
				skip()
			else:
				_finish("completed"))


func start() -> bool:
	if active:
		return false
	for other in get_tree().get_nodes_in_group("ember_active_story_presentations"):
		if other != self and other.get_viewport() == get_viewport():
			status = "Сначала заверши другую сценку"
			return false
	if not _baseline.is_empty():
		restore()
	if not player.has_animation(clip_name):
		status = "Не найдена анимация: " + str(clip_name)
		return false
	var rig := get_parent().get_node("ShotRig")
	for path in [rig.primary_anchor, rig.secondary_anchor, rig.detail_anchor]:
		if not path.is_empty() and rig.get_node_or_null(path) == null:
			status = "Не найден участник/предмет сценки: " + str(path)
			return false
	var animation := player.get_animation(clip_name)
	_run_cues.clear()
	if dialogue_cues.is_empty():
		if dialogue != null:
			_run_cues.append({"time": dialogue_time, "dialogue": dialogue})
	else:
		for cue in dialogue_cues:
			if cue == null or cue.dialogue == null:
				status = "У разговорной остановки не выбран диалог"
				return false
			_run_cues.append({"time": cue.time, "dialogue": cue.dialogue})
	_run_cues.sort_custom(func(a, b): return a.time < b.time)
	var previous_time := -1.0
	for cue in _run_cues:
		if not is_finite(cue.time) or cue.time < 0.0 or cue.time >= animation.length or is_equal_approx(cue.time, previous_time):
			status = "Разговоры должны быть в разные моменты внутри анимации"
			return false
		previous_time = cue.time
	if not _run_cues.is_empty() and dialogue_ui.is_open():
		status = "Сначала заверши текущий разговор"
		return false
	if animation.loop_mode != Animation.LOOP_NONE:
		status = "Для сценки выключи зацикливание анимации"
		return false
	var tracks: Array[Dictionary] = []
	var animation_root := player.get_node(player.root_node)
	for index in animation.get_track_count():
		if not animation.track_is_enabled(index):
			continue
		var path := animation.track_get_path(index)
		var node := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
		if node == null:
			status = "Не найдена привязка дорожки: " + str(path)
			return false
		var property_path := NodePath(path.get_concatenated_subnames())
		match animation.track_get_type(index):
			Animation.TYPE_VALUE:
				if property_path.is_empty():
					status = "У дорожки не указано свойство: " + str(path)
					return false
			Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D:
				property_path = NodePath("transform")
			_:
				status = "В этой пробе поддержаны свойства и3D-transform; вызовы/клипы/звук — позже"
				return false
		tracks.append({"node": weakref(node), "property": property_path, "value": node.get_indexed(property_path)})
	_baseline = tracks
	if get_parent().has_method("stop_background_motion"):
		get_parent().stop_background_motion()
	var panel := get_parent().get_node_or_null("Controls/Panel") as Control
	if panel:
		_panel_was_visible = panel.visible
		panel.hide()
	var subtitle := get_parent().get_node_or_null("Controls/Subtitle") as Control
	if subtitle:
		subtitle.hide()
	var current := get_viewport().get_camera_3d()
	var story_camera := get_parent().get_node("ShotRig/Camera3D") as Camera3D
	_previous_camera = weakref(current) if current != null and current != story_camera else null
	if current != null and current.get_parent() is EmberFollowCamera:
		var camera_owner := current.get_parent()
		_previous_camera_input_owner = weakref(camera_owner)
		_previous_camera_input_enabled = camera_owner.is_processing_unhandled_input()
		camera_owner.set_process_unhandled_input(false)
	story_camera.make_current()
	active = true
	add_to_group("ember_active_story_presentations")
	paused = false
	_next_cue = 0
	_waiting_dialogue = false
	_finish_after_dialogue = false
	_display_time = 0.0
	status = "Показ · P пауза · Esc вернуть исходное"
	player.play(clip_name)
	player.advance(0.0)
	return true


func toggle_pause() -> void:
	if _waiting_dialogue:
		return
	if not active:
		start()
		return
	paused = not paused
	if paused:
		player.pause()
	else:
		player.play()
	status = "Пауза · можно двигать ползунок времени" if paused else "Показ · P пауза · Esc вернуть исходное"


func scrub(seconds: float) -> void:
	if _waiting_dialogue or _action_driven:
		return
	if not active and not start():
		return
	player.pause()
	paused = true
	player.seek(clampf(seconds, 0.0, player.current_animation_length), true)
	get_parent().get_node("ShotRig").snap()
	status = "Просмотр по времени · P продолжить · Esc вернуть исходное"


func skip() -> void:
	if not active:
		return
	if _waiting_dialogue:
		status = "Сначала заверши разговор — выбор ответа не пропускается"
		return
	if _next_cue < _run_cues.size():
		_finish_after_dialogue = true
		player.seek(_run_cues[_next_cue].time, true)
		get_parent().get_node("ShotRig").snap()
		_present_dialogue()
		return
	# seek(end) does not emit animation_finished. Complete explicitly, once.
	player.seek(player.current_animation_length, true)
	get_parent().get_node("ShotRig").snap()
	_finish("skipped")


func restore() -> void:
	var was_active := active
	active = false
	remove_from_group("ember_active_story_presentations")
	_end_dialogue_preview()
	paused = false
	_display_time = 0.0
	player.stop(true)
	_restore_properties()
	get_parent().get_node("ShotRig").snap()
	_restore_panel()
	_release_action_context()
	_restore_camera()
	status = "Исходное состояние · P повторить"
	if was_active:
		finished.emit("cancelled")


func _finish(outcome: String) -> void:
	var action_finished := _action_driven
	_display_time = player.current_animation_position
	active = false
	remove_from_group("ember_active_story_presentations")
	paused = false
	player.stop(true)
	if _action_driven:
		# Commit visual poses for this run, but return the shot to its prior settings.
		var rig := get_parent().get_node("ShotRig")
		for entry in _baseline:
			var node: Node = entry.node.get_ref()
			if node == rig or node == get_parent().get_node("StoryText/Caption"):
				node.set_indexed(entry.property, entry.value)
		rig.snap()
		_baseline.clear()
	_restore_panel()
	_release_action_context()
	_restore_camera()
	status = "Сценка завершена · результат передан квесту" if action_finished else "Финальный кадр · P повторить · Esc вернуть исходное"
	finished.emit(outcome)


func _restore_properties() -> void:
	for entry in _baseline:
		var node: Node = entry.node.get_ref()
		if node != null:
			node.set_indexed(entry.property, entry.value)
	_baseline.clear()


func _restore_panel() -> void:
	var panel := get_parent().get_node_or_null("Controls/Panel") as Control
	if panel:
		panel.visible = _panel_was_visible
	var subtitle := get_parent().get_node_or_null("Controls/Subtitle") as Control
	if subtitle:
		subtitle.visible = _baseline.is_empty()


func _exit_tree() -> void:
	# Restore preview mutations even when the author closes/replaces the scene.
	var cancel_action := _action_driven and active
	active = false
	remove_from_group("ember_active_story_presentations")
	_end_dialogue_preview()
	player.stop(true)
	_restore_properties()
	_release_action_context()
	_restore_camera()
	if cancel_action:
		finished.emit("cancelled")


func _release_action_context() -> void:
	if not _action_driven:
		return
	_action_driven = false
	if is_instance_valid(dialogue_ui):
		dialogue_ui.economy_state = _previous_economy
		dialogue_ui.set_conversation_session(_previous_session)
	_previous_economy = null
	_previous_session = null


func _restore_camera() -> void:
	var input_owner := _previous_camera_input_owner.get_ref() as Node if _previous_camera_input_owner != null else null
	_previous_camera_input_owner = null
	if input_owner != null:
		input_owner.set_process_unhandled_input(_previous_camera_input_enabled)
	var previous := _previous_camera.get_ref() as Camera3D if _previous_camera != null else null
	_previous_camera = null
	if previous != null and previous.is_inside_tree():
		previous.make_current()


func _unhandled_key_input(event: InputEvent) -> void:
	if not enable_preview_shortcuts and not _action_driven:
		return
	if not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode
	if _waiting_dialogue:
		# Main-map F belongs to Player; the isolated stage has no Player.
		if key == KEY_F and not _action_driven:
			dialogue_ui.advance()
			get_viewport().set_input_as_handled()
		return
	if key == KEY_P:
		toggle_pause()
	elif key == KEY_ESCAPE:
		restore()
	elif key == KEY_END:
		skip()


func _process(_delta: float) -> void:
	if active:
		for entry in _baseline:
			var node: Node = entry.node.get_ref()
			if node == null or not node.is_inside_tree():
				restore()
				status = "Объект сценки исчез — показ отменён"
				return
	if active and not paused and not _waiting_dialogue and _next_cue < _run_cues.size() and player.current_animation_position >= _run_cues[_next_cue].time:
		_present_dialogue()
	if _time_slider:
		_time_slider.set_value_no_signal(player.current_animation_position if active else _display_time)
	if _status_label:
		_status_label.text = status


func _present_dialogue() -> void:
	player.pause()
	paused = true
	_waiting_dialogue = true
	var cue := _run_cues[_next_cue]
	_next_cue += 1
	var caption_layer := get_parent().get_node("StoryText") as CanvasLayer
	_caption_was_visible = caption_layer.visible
	caption_layer.hide()
	status = "Разговор · F / Enter или кнопки · H история · Esc отмена"
	var error := dialogue_ui.activate_dialogue(cue.dialogue.dialogue_id)
	if not error.is_empty():
		restore()
		status = error


func _on_dialogue_closed(completed: bool) -> void:
	if not active or not _waiting_dialogue:
		return
	_waiting_dialogue = false
	get_parent().get_node("StoryText").visible = _caption_was_visible
	if not completed:
		restore()
		return
	paused = false
	if _finish_after_dialogue:
		skip()
	else:
		player.play()
		status = "Разговор завершён · сценка продолжается"


func _end_dialogue_preview() -> void:
	if not _waiting_dialogue:
		return
	_waiting_dialogue = false
	if is_instance_valid(dialogue_ui):
		dialogue_ui.close()
	var caption_layer := get_parent().get_node_or_null("StoryText") as CanvasLayer
	if caption_layer:
		caption_layer.visible = _caption_was_visible


func attach_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "StoryControls"
	add_child(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(350, 60)
	column.custom_minimum_size.x = 560
	layer.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	for spec in [["P · запуск/пауза", toggle_pause], ["End · финал", skip], ["Esc · вернуть", restore]]:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(spec[1])
		row.add_child(button)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = player.get_animation(clip_name).length if player.has_animation(clip_name) else 1.0
	_time_slider.step = 0.01
	_time_slider.focus_mode = Control.FOCUS_NONE
	_time_slider.value_changed.connect(scrub)
	column.add_child(_time_slider)
	_status_label = Label.new()
	column.add_child(_status_label)
