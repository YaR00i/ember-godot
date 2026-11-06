class_name EmberExplorePauseMenu
extends Control
## Shared exploration menu for every map driven by ember_explore_scene.gd.
## It owns presentation and SceneTree pause only; EmberExploreState remains the
## save owner, and modal explore UIs keep first refusal on Escape.

var progress_state: EmberExploreState
var player: EmberPlayer
var map_loader: EmberMapLoader
var map_display_name := "Локация"
var blockers: Array[Control] = []

var _overlay: ColorRect
var _resume_button: Button
var _quit_button: Button
var _save_title: Label
var _feedback: Label
var _slot_labels: Array[Label] = []
var _slot_load_buttons: Array[Button] = []
var _slot_delete_buttons: Array[Button] = []
var _autosave_label: Label
var _autosave_delete_button: Button
var _armed_delete_key := ""
var _armed_delete_until_ms := 0
var _mira_model: OptionButton
var _test_panel: VBoxContainer
var _test_destinations: OptionButton


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
	_test_panel.visible = EmberMapTransition.test_mode(_progress())
	if is_instance_valid(player):
		_mira_model.select(0 if player.mira_outfit_selected() and player.mira_outfit_available() else 1)
		_mira_model.set_item_disabled(0, not player.mira_outfit_available())
	_refresh_save_metadata()
	get_tree().paused = true
	_focus_resume.call_deferred()

func _focus_resume() -> void:
	if is_inside_tree() and is_open(): _resume_button.grab_focus()



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
	if state == null:
		_feedback.text = "Не удалось загрузить слот %d." % (slot + 1)
		return
	# Validate with the same detached save owner as combat before changing live
	# progress; arm restore before scene removal and roll back on transition error.
	var staged := EmberExploreState.new()
	staged.active_slot = state.active_slot
	staged.storage_root = state.storage_root
	staged.legacy_storage_root = state.legacy_storage_root
	staged.persistence_enabled = state.persistence_enabled
	staged.restore_enabled = state.restore_enabled
	if not staged.load_slot(slot):
		staged.free()
		_feedback.text = "Не удалось загрузить слот %d." % (slot + 1)
		return
	var target_path := staged.resume_scene_path()
	if target_path.is_empty() or not ResourceLoader.exists(target_path):
		staged.free()
		_feedback.text = "Сохранённая локация пока недоступна."
		return
	var target := ResourceLoader.load(target_path) as PackedScene
	if target == null or not target.can_instantiate():
		staged.free()
		_feedback.text = "Не удалось открыть сохранённую локацию."
		return
	var tree := get_tree()
	var previous := EmberExploreState.new()
	previous.adopt_loaded_save(state)
	var previous_leader := state.exploration_leader_id
	# SceneTree removes the outgoing scene during change_scene_to_packed, so
	# arm pending restore first: its exit autosave must not overwrite loaded data.
	state.adopt_loaded_save(staged)
	var error := tree.change_scene_to_packed(target)
	staged.free()
	if error != OK:
		state.adopt_loaded_save(previous)
		state.set_exploration_leader(previous_leader)
		previous.free()
		_feedback.text = "Не удалось открыть сохранённую локацию."
		return
	previous.free()
	tree.paused = false
	_overlay.visible = false


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
	_save_title = Label.new()
	_save_title.text = "РУЧНЫЕ СОХРАНЕНИЯ"
	_save_title.add_theme_color_override("font_color", Color("ffc85a"))
	content.add_child(_save_title)
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
	var appearance := HBoxContainer.new()
	content.add_child(appearance)
	var appearance_label := Label.new()
	appearance_label.text = "Модель Миры"
	appearance.add_child(appearance_label)
	_mira_model = OptionButton.new()
	_mira_model.add_item("Камира · текущий костюм")
	_mira_model.add_item("Хоши · пробный облик")
	_mira_model.item_selected.connect(func(index: int) -> void:
		if is_instance_valid(player):
			player.set_mira_outfit(index == 0)
	)
	appearance.add_child(_mira_model)
	_build_location_test(content)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)

	_resume_button = Button.new()
	_resume_button.name = "ExplorePauseResume"
	_resume_button.text = "Продолжить"
	_resume_button.custom_minimum_size = Vector2(0, 50)
	_resume_button.pressed.connect(close_menu)
	content.add_child(_resume_button)
	_quit_button = Button.new()
	_quit_button.name = "ExplorePauseQuit"
	_quit_button.custom_minimum_size = Vector2(0, 50)
	_quit_button.pressed.connect(_quit_game)
	content.add_child(_quit_button)
	_feedback = Label.new()
	_feedback.name = "ExplorePauseFeedback"
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.add_theme_color_override("font_color", Color("86ddaa"))
	content.add_child(_feedback)
	_refresh_save_metadata()

func _build_location_test(content: VBoxContainer) -> void:
	var toggle := Button.new()
	toggle.text = "Проверка локаций"
	content.add_child(toggle)
	_test_panel = VBoxContainer.new()
	_test_panel.visible = false
	content.add_child(_test_panel)
	toggle.pressed.connect(func() -> void: _test_panel.visible = not _test_panel.visible)
	var note := Label.new()
	note.text = "После перехода сохранения отключены до выхода из игры."
	note.add_theme_color_override("font_color", Color("a9b8d0"))
	_test_panel.add_child(note)
	var row := HBoxContainer.new()
	_test_panel.add_child(row)
	_test_destinations = OptionButton.new()
	_test_destinations.name = "ExploreTestLocations"
	_test_destinations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_test_destinations)
	_test_destinations.add_item("Выбери локацию")
	for category: String in EmberMapTransition.TEST_DESTINATIONS:
		_test_destinations.add_separator(category)
		var locations: Dictionary = EmberMapTransition.TEST_DESTINATIONS[category]
		for map_id: String in locations:
			_test_destinations.add_item(locations[map_id])
			var index := _test_destinations.item_count - 1
			_test_destinations.set_item_metadata(index, map_id)
			_test_destinations.set_item_disabled(index, not ResourceLoader.exists(EmberMapTransition.scene_path(map_id)))
	var visit := Button.new()
	visit.name = "ExploreVisitTestLocation"
	visit.text = "Перейти"
	visit.disabled = true
	_test_destinations.item_selected.connect(func(index: int) -> void: visit.disabled = index == 0)
	visit.pressed.connect(_visit_test_location)
	row.add_child(visit)
	var compare := CheckButton.new()
	compare.text = "Камера сравнения из общего пресета"
	compare.button_pressed = EmberFollowCamera.comparison_enabled
	compare.toggled.connect(func(enabled: bool):
		EmberFollowCamera.comparison_enabled = enabled
		if is_instance_valid(player) and is_instance_valid(player.camera_rig) and is_instance_valid(map_loader):
			player.camera_rig.apply_exploration_framing(map_loader.camera_fov, map_loader.camera_distance, map_loader.camera_polar, map_loader.imported_tile_size))
	_test_panel.add_child(compare)
	var reset := Button.new()
	reset.name = "ExploreResetNotSave"
	reset.text = "Reset · начать заново без сохранения"
	_test_panel.add_child(reset)
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "Начать тест заново"
	confirmation.dialog_text = "Сбросить задания, сумку и состояние мира и вернуться ко входу в текущую локацию? Обычные сохранения останутся на диске."
	confirmation.ok_button_text = "Начать заново"
	add_child(confirmation)
	reset.pressed.connect(func() -> void: confirmation.popup_centered())
	confirmation.confirmed.connect(_restart_test_session)

func _visit_test_location() -> void:
	var index := _test_destinations.selected
	if index <= 0 or _test_destinations.is_item_disabled(index):
		return
	var tree := get_tree()
	var map_id := str(_test_destinations.get_item_metadata(index))
	if EmberMapTransition.visit_test_location(tree, _progress(), map_id) == OK:
		tree.paused = false
	else:
		_feedback.text = "Не удалось открыть тестовую локацию."

func _restart_test_session() -> void:
	var tree := get_tree()
	if EmberMapTransition.restart_test_session(tree, _progress()) == OK:
		tree.paused = false
	else:
		_feedback.text = "Не удалось начать тест заново."

func _refresh_save_metadata() -> void:
	var state := _progress()
	if state == null or _slot_labels.is_empty():
		return
	var testing := EmberMapTransition.test_mode(state)
	_save_title.visible = not testing
	_quit_button.text = "Закрыть проверку" if testing else "Сохранить и закрыть игру"
	for slot in mini(_slot_labels.size(), EmberExploreState.MANUAL_SLOT_COUNT):
		_slot_labels[slot].get_parent().visible = not testing
		if testing:
			continue
		var meta := state.slot_metadata(slot)
		_slot_labels[slot].text = "Слот %d · %s" % [slot + 1, _metadata_text(meta)]
		_slot_load_buttons[slot].disabled = not bool(meta.get("exists", false))
		_slot_delete_buttons[slot].disabled = not bool(meta.get("exists", false))
		_slot_delete_buttons[slot].text = "Удалить?" if _armed_delete_key == "manual_%d" % slot else "Удалить"
	if _autosave_label != null:
		_autosave_label.get_parent().visible = not testing
		if testing:
			return
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
