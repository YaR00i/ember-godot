class_name EmberExplorePauseMenu
extends Control
## Shared exploration menu for every map driven by fan_town.gd.
## It owns presentation and SceneTree pause only; EmberExploreState remains the
## save owner, and modal explore UIs keep first refusal on Escape.

var progress_state: EmberExploreState
var map_display_name := "Локация"
var blockers: Array[Control] = []

var _overlay: ColorRect
var _resume_button: Button
var _feedback: Label
var _slot_labels: Array[Label] = []
var _slot_load_buttons: Array[Button] = []
var _slot_delete_buttons: Array[Button] = []
var _autosave_label: Label
var _autosave_delete_button: Button
var _armed_delete_key := ""
var _armed_delete_until_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shortcut_button()
	_build_overlay()


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and get_tree() != null and get_tree().paused:
		get_tree().paused = false


func is_open() -> bool:
	return _overlay != null and _overlay.visible


func blocks_movement() -> bool:
	return is_open()


func open_menu() -> void:
	if is_open() or _has_open_blocker():
		return
	_armed_delete_key = ""
	_armed_delete_until_ms = 0
	_overlay.visible = true
	_feedback.text = ""
	_refresh_save_metadata()
	get_tree().paused = true
	_resume_button.call_deferred("grab_focus")


func close_menu() -> void:
	if _overlay == null:
		return
	_armed_delete_key = ""
	_armed_delete_until_ms = 0
	_overlay.visible = false
	get_tree().paused = false


func _save_game(slot := -1) -> void:
	var state := _progress()
	var target_slot := state.active_slot if state != null and int(slot) < 0 else int(slot)
	_feedback.text = (
		"Игра сохранена в слот %d." % (target_slot + 1)
		if state != null and state.save_slot(target_slot)
		else "Не удалось сохранить игру."
	)
	_refresh_save_metadata()


func _load_game(slot: int) -> void:
	var state := _progress()
	if state == null or not state.load_slot(slot):
		_feedback.text = "Не удалось загрузить слот %d." % (slot + 1)
		return
	var target_path := state.resume_scene_path()
	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		_feedback.text = "Сохранённая локация пока недоступна."
		return
	get_tree().paused = false
	_overlay.visible = false
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == target_path:
		get_tree().reload_current_scene()
	else:
		get_tree().change_scene_to_file(target_path)


func _request_delete_slot(slot: int) -> void:
	var key := "manual_%d" % slot
	if not _delete_is_confirmed(key):
		_arm_delete(key, "Слот %d: нажмите «Удалить?» ещё раз." % (slot + 1))
		return
	var state := _progress()
	var result := state.delete_slot(slot) if state != null else {"ok": false}
	_finish_delete(result, "Слот %d удалён; резервная копия сохранена." % (slot + 1))


func _request_delete_autosave() -> void:
	var key := "autosave"
	if not _delete_is_confirmed(key):
		_arm_delete(key, "Автосейв: нажмите «Удалить?» ещё раз.")
		return
	var state := _progress()
	var result := state.delete_autosave() if state != null else {"ok": false}
	_finish_delete(result, "Автосейв удалён; новый появится после следующего автосохранения.")


func _delete_is_confirmed(key: String) -> bool:
	return _armed_delete_key == key and Time.get_ticks_msec() <= _armed_delete_until_ms


func _arm_delete(key: String, message: String) -> void:
	_armed_delete_key = key
	_armed_delete_until_ms = Time.get_ticks_msec() + 5000
	_feedback.text = message
	_refresh_save_metadata()


func _finish_delete(result: Dictionary, success_message: String) -> void:
	_armed_delete_key = ""
	_armed_delete_until_ms = 0
	_feedback.text = success_message if bool(result.get("ok", false)) else "Не удалось удалить сохранение."
	_refresh_save_metadata()


func _quit_game() -> void:
	var state := _progress()
	if state != null:
		state.save_autosave()
	get_tree().paused = false
	get_tree().quit()


func _progress() -> EmberExploreState:
	if is_instance_valid(progress_state):
		return progress_state
	return get_node_or_null("/root/EmberExploreProgress") as EmberExploreState


func _has_open_blocker() -> bool:
	for blocker in blockers:
		if is_instance_valid(blocker) and blocker.has_method("is_open") and bool(blocker.call("is_open")):
			return true
	return false


func _build_shortcut_button() -> void:
	var button := Button.new()
	button.name = "ExploreMenuButton"
	button.text = "Меню · Esc"
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -154
	button.offset_top = 18
	button.offset_right = -18
	button.offset_bottom = 60
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(open_menu)
	add_child(button)


func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "ExplorePauseOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.015, 0.025, 0.045, 0.86)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "ExplorePausePanel"
	panel.custom_minimum_size = Vector2(900, 640)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("182234")
	panel_style.border_color = Color("65cfe1")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 30)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var title := Label.new()
	title.text = "МЕНЮ ИГРЫ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("ffc85a"))
	content.add_child(title)
	var location := Label.new()
	location.text = map_display_name
	location.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	location.add_theme_color_override("font_color", Color("91a0b8"))
	content.add_child(location)
	var controls := Label.new()
	controls.text = "WASD — движение   ·   Tab — герой   ·   F — действие\nI — сумка (Q/E герой)   ·   Q — задания   ·   T — строй   ·   RMB — камера"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_color_override("font_color", Color("a9b8d0"))
	content.add_child(controls)
	var save_title := Label.new()
	save_title.text = "РУЧНЫЕ СОХРАНЕНИЯ"
	save_title.add_theme_color_override("font_color", Color("ffc85a"))
	content.add_child(save_title)
	for slot in EmberExploreState.MANUAL_SLOT_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		content.add_child(row)
		var label := Label.new()
		label.name = "ExploreSaveSlot%dLabel" % (slot + 1)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.custom_minimum_size = Vector2(0, 42)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		_slot_labels.append(label)
		var save_button := Button.new()
		save_button.name = "ExploreSaveSlot%d" % (slot + 1)
		save_button.text = "Сохранить"
		save_button.pressed.connect(_save_game.bind(slot))
		row.add_child(save_button)
		var load_button := Button.new()
		load_button.name = "ExploreLoadSlot%d" % (slot + 1)
		load_button.text = "Загрузить"
		load_button.pressed.connect(_load_game.bind(slot))
		row.add_child(load_button)
		_slot_load_buttons.append(load_button)
		var delete_button := Button.new()
		delete_button.name = "ExploreDeleteSlot%d" % (slot + 1)
		delete_button.text = "Удалить"
		delete_button.pressed.connect(_request_delete_slot.bind(slot))
		row.add_child(delete_button)
		_slot_delete_buttons.append(delete_button)
	var autosave_row := HBoxContainer.new()
	autosave_row.add_theme_constant_override("separation", 10)
	content.add_child(autosave_row)
	_autosave_label = Label.new()
	_autosave_label.name = "ExploreAutosaveLabel"
	_autosave_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_autosave_label.add_theme_color_override("font_color", Color("91a0b8"))
	autosave_row.add_child(_autosave_label)
	_autosave_delete_button = Button.new()
	_autosave_delete_button.name = "ExploreDeleteAutosave"
	_autosave_delete_button.text = "Удалить"
	_autosave_delete_button.pressed.connect(_request_delete_autosave)
	autosave_row.add_child(_autosave_delete_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	_resume_button = Button.new()
	_resume_button.name = "ExplorePauseResume"
	_resume_button.text = "Продолжить"
	_resume_button.custom_minimum_size = Vector2(0, 50)
	_resume_button.pressed.connect(close_menu)
	content.add_child(_resume_button)
	var quit_button := Button.new()
	quit_button.name = "ExplorePauseQuit"
	quit_button.text = "Сохранить и закрыть игру"
	quit_button.custom_minimum_size = Vector2(0, 50)
	quit_button.pressed.connect(_quit_game)
	content.add_child(quit_button)
	_feedback = Label.new()
	_feedback.name = "ExplorePauseFeedback"
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_color_override("font_color", Color("86ddaa"))
	content.add_child(_feedback)
	_refresh_save_metadata()


func _refresh_save_metadata() -> void:
	var state := _progress()
	if state == null or _slot_labels.is_empty():
		return
	for slot in mini(_slot_labels.size(), EmberExploreState.MANUAL_SLOT_COUNT):
		var meta := state.slot_metadata(slot)
		_slot_labels[slot].text = "Слот %d · %s" % [slot + 1, _metadata_text(meta)]
		_slot_load_buttons[slot].disabled = not bool(meta.get("exists", false))
		_slot_delete_buttons[slot].disabled = not bool(meta.get("exists", false))
		_slot_delete_buttons[slot].text = "Удалить?" if _armed_delete_key == "manual_%d" % slot else "Удалить"
	if _autosave_label != null:
		var auto_meta := state.autosave_metadata()
		_autosave_label.text = "Автосейв · %s" % _metadata_text(auto_meta)
		_autosave_delete_button.disabled = not bool(auto_meta.get("exists", false))
		_autosave_delete_button.text = "Удалить?" if _armed_delete_key == "autosave" else "Удалить"


func _metadata_text(meta: Dictionary) -> String:
	if not bool(meta.get("exists", false)):
		return "пусто"
	var seconds := maxi(0, roundi(float(meta.get("playtimeSeconds", 0.0))))
	var hours := floori(float(seconds) / 3600.0)
	var minutes := floori(float(seconds % 3600) / 60.0)
	var migration := " · будет обновлён с v1" if bool(meta.get("migrationPending", false)) else ""
	var saved_at := str(meta.get("savedAtText", "")).replace("T", " ")
	if saved_at.length() > 16:
		saved_at = saved_at.left(16)
	return "%s · %02d:%02d · герои %d/%d · %s%s" % [
		str(meta.get("mapId", "локация")),
		hours,
		minutes,
		int(meta.get("aliveCount", 0)),
		int(meta.get("partyCount", 0)),
		saved_at,
		migration,
	]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.physical_keycode != KEY_ESCAPE:
		return
	if is_open():
		close_menu()
		get_viewport().set_input_as_handled()
		return
	if _has_open_blocker():
		return
	open_menu()
	get_viewport().set_input_as_handled()
