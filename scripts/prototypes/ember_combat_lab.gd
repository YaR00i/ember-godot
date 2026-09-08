extends Control
## Playable D1 laboratory for E1 "Wet Conductor".
## This script is the CanvasLayer HUD/controller. In combat_lab.tscn it projects
## into a scene-owned Node3D world; without an external path it keeps the old
## embedded adapter for isolated UI diagnostics.

@export var external_3d_world_path: NodePath
@export var request_fullscreen := true

const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
const GridView = preload("res://scripts/prototypes/ember_combat_grid_view.gd")
const Grid3DView = preload("res://scripts/prototypes/ember_combat_grid_3d_view.gd")
const EncounterCatalog = preload("res://scripts/prototypes/ember_encounter_catalog.gd")
const CombatResult = preload("res://scripts/prototypes/ember_combat_result.gd")
const ItemCatalog = preload("res://scripts/ember_item_catalog.gd")
const ItemVisuals = preload("res://scripts/ember_item_visuals.gd")

const COLOR_BG := Color("111522")
const COLOR_PANEL := Color("1d2433")
const COLOR_TEXT := Color("e8edf8")
const COLOR_MUTED := Color("91a0b8")
const COLOR_HERO := Color("65cfe1")
const COLOR_ENEMY := Color("f07883")
const COLOR_ACCENT := Color("ffc85a")
const CAMERA_MENU_OVERVIEW := 0
const CAMERA_MENU_INVERT_VERTICAL := 1
const CAMERA_MENU_STEP_ROTATION := 2
const CAMERA_MENU_LOCK_HORIZONTAL := 3
const CAMERA_MENU_LOCK_VERTICAL := 4

var _state: Dictionary
var _encounter_mode := "grid"
var _authored_encounter: EmberEncounterResource
var _party_snapshot: Dictionary = {}
var _inventory_snapshot: Dictionary = {}
var _field_view_mode := "3d"
var _selected_action := ""
var _selected_target := ""
var _selected_target_cell := Combat.INVALID_CELL
var _selected_secondary_cell := Combat.INVALID_CELL
var _lifted_target_id := ""
var _lift_choice := ""
var _current_preview: Dictionary = {}
var _action_plan: Dictionary = {}
var _locked_lift_plan: Dictionary = {}
var _plan_contexts: Dictionary = {}
var _hover_cell := Combat.INVALID_CELL
var _canceling_lift := false
var _lift_menu_ready := false
var _plan_cache_key := ""
var _manual_move_selected := false
var _pending_cell := Vector2i(-1, -1)
var _pending_actor_id := ""
var _move_mode := false
var _radial_targeting := false
var _radial_page := "root"
var _radial_actor_id := ""
var _selection_actor_id := ""
var _browsed_command_id := ""
var _selection_origin_page := "root"
var _selection_origin_action := ""
var _hovered_unit_id := ""
var _pair_hover_action := ""
var _console_messages: Array[String] = []
var _action_target_cache: Dictionary = {}
var _action_target_cell_cache: Dictionary = {}

var _title_label: Label
var _subtitle_label: Label
var _mode_picker: OptionButton
var _view_picker: OptionButton
var _camera_menu: MenuButton
var _timeline_row: VBoxContainer
var _field_row: HBoxContainer
var _turn_label: Label
var _action_list: VBoxContainer
var _target_hint: Label
var _preview_caption: Label
var _preview_label: RichTextLabel
var _predicted_label: Label
var _confirm_button: Button
var _lift_choice_row: HBoxContainer
var _lift_throw_button: Button
var _lift_hold_button: Button
var _log_label: RichTextLabel
var _console_input: LineEdit
var _outcome_label: Label
var _return_button: Button
var _reset_button: Button
var _scope_label: Label
var _movement_row: HBoxContainer
var _move_button: Button
var _cancel_move_button: Button
var _field_heading: Label
var _source_note: Label
var _footer: Label
var _background: ColorRect
var _field_panel: PanelContainer
var _external_3d_world: Node3D
var _command_panel: PanelContainer
var _timeline_panel: PanelContainer
var _console_panel: PanelContainer
var _radial_menu: Control
var _radial_ring: Panel
var _radial_confirm: Button
var _command_drawer: PanelContainer
var _command_drawer_title: Label
var _command_drawer_list: VBoxContainer
var _command_drawer_close: Button
var _command_drawer_side := "right"
var _ability_info_panel: PanelContainer
var _ability_info_label: RichTextLabel
var _enemy_info_panel: PanelContainer
var _enemy_info_label: RichTextLabel
var _result_overlay: ColorRect
var _result_title: Label
var _result_body: Label
var _result_continue: Button
var _result_retry: Button
var _result_return: Button
var _fade_overlay: ColorRect
var _pause_overlay: ColorRect
var _pause_resume: Button
var _transition_in_progress := false
var _battle_seed_serial := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	if (
		request_fullscreen
		and not Engine.is_editor_hint()
		and not Engine.is_embedded_in_editor()
		and DisplayServer.get_name() != "headless"
	):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_authored_encounter = EmberCombatTransition.consume_encounter()
	_party_snapshot = EmberCombatTransition.active_party_snapshot()
	_inventory_snapshot = EmberCombatTransition.active_inventory_snapshot()
	if not external_3d_world_path.is_empty():
		_external_3d_world = get_node_or_null(external_3d_world_path) as Node3D
		if (
			_external_3d_world != null
			and _external_3d_world.has_signal("cell_chosen")
			and not _external_3d_world.is_connected("cell_chosen", _on_grid_cell_chosen)
		):
			_external_3d_world.connect("cell_chosen", _on_grid_cell_chosen)
		if _external_3d_world != null and not _external_3d_world.is_connected("cell_hovered", _on_grid_cell_hovered):
			_external_3d_world.connect("cell_hovered", _on_grid_cell_hovered)
		if (
			_external_3d_world != null
			and _external_3d_world.has_signal("lift_presentation_finished")
			and not _external_3d_world.is_connected(
				"lift_presentation_finished", _on_lift_presentation_finished
			)
		):
			_external_3d_world.connect(
				"lift_presentation_finished", _on_lift_presentation_finished
			)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if _authored_encounter != null:
		_encounter_mode = "encounter"
		_select_mode_metadata("encounter:%s" % _authored_encounter.encounter_id)
		_mode_picker.disabled = true
	else:
		_mode_picker.select(1)
	_reset_lab()
	call_deferred("_fade_in")


func _process(_delta: float) -> void:
	if _radial_menu != null and _radial_menu.visible:
		_position_radial_menu()


func state_snapshot() -> Dictionary:
	return _state.duplicate(true)


func _build_ui() -> void:
	_background = ColorRect.new()
	_background.color = Color(COLOR_BG, 0.0) if _external_3d_world != null else COLOR_BG
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_field_panel = _build_field_panel() as PanelContainer
	_field_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_field_panel)

	var header_panel := PanelContainer.new()
	header_panel.name = "CombatHeaderPanel"
	header_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header_panel.offset_left = 14
	header_panel.offset_top = 12
	header_panel.offset_right = -14
	header_panel.offset_bottom = 84
	header_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.07, 0.12, 0.88), Color(0.24, 0.31, 0.43, 0.8)))
	var header_margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		header_margin.add_theme_constant_override(side, 10)
	header_panel.add_child(header_margin)
	header_margin.add_child(_build_header())
	add_child(header_panel)

	_timeline_panel = _build_timeline() as PanelContainer
	_timeline_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_timeline_panel.offset_left = 16
	_timeline_panel.offset_top = 96
	_timeline_panel.offset_right = 236
	_timeline_panel.offset_bottom = 574
	add_child(_timeline_panel)

	_console_panel = _build_console_panel()
	_console_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_console_panel.offset_left = 16
	_console_panel.offset_top = -220
	_console_panel.offset_right = 650
	_console_panel.offset_bottom = -18
	add_child(_console_panel)

	_command_panel = _build_command_panel() as PanelContainer
	_command_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_command_panel.offset_left = -450
	_command_panel.offset_top = -356
	_command_panel.offset_right = -16
	_command_panel.offset_bottom = -18
	add_child(_command_panel)

	_build_ability_info_panel()
	_build_enemy_info_panel()

	_footer = Label.new()
	_footer.modulate = COLOR_MUTED
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.offset_left = 665
	_footer.offset_top = -42
	_footer.offset_right = -470
	_footer.offset_bottom = -16
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer)
	_build_radial_menu()
	_build_result_overlay()
	_build_pause_overlay()
	_build_fade_overlay()


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	var title_box := VBoxContainer.new()
	title_box.custom_minimum_size.x = 360.0
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	_title_label = Label.new()
	_title_label.text = "EMBER COMBAT LAB · E1"
	_title_label.clip_text = true
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title_label.add_theme_font_size_override("font_size", 25)
	_title_label.modulate = COLOR_ACCENT
	title_box.add_child(_title_label)
	_subtitle_label = Label.new()
	_subtitle_label.text = "Мокрый проводник · D1, не production battle/save schema"
	_subtitle_label.clip_text = true
	_subtitle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_subtitle_label.modulate = COLOR_MUTED
	title_box.add_child(_subtitle_label)
	_mode_picker = OptionButton.new()
	_mode_picker.name = "CombatEncounterMode"
	_mode_picker.fit_to_longest_item = false
	_mode_picker.custom_minimum_size.x = 270.0
	_mode_picker.add_item("E1 · Области")
	_mode_picker.set_item_metadata(0, "zones")
	_mode_picker.add_item("E2 · Сетка 7×5")
	_mode_picker.set_item_metadata(1, "grid")
	_mode_picker.add_item("E3 · Хранитель оттепели")
	_mode_picker.set_item_metadata(2, "terrain")
	_mode_picker.add_item("E4 · Вертикаль 10×8")
	_mode_picker.set_item_metadata(3, "vertical")
	_mode_picker.add_item("E5 · Нагрузка 16×12")
	_mode_picker.set_item_metadata(4, "stress")
	for encounter_id in EncounterCatalog.ids():
		var encounter := EncounterCatalog.definition(encounter_id)
		if encounter == null:
			continue
		_mode_picker.add_item("Встреча · %s" % encounter.display_name)
		_mode_picker.set_item_metadata(_mode_picker.item_count - 1, "encounter:%s" % encounter_id)
	_mode_picker.item_selected.connect(_select_encounter_mode)
	header.add_child(_mode_picker)
	_view_picker = OptionButton.new()
	_view_picker.name = "CombatFieldViewMode"
	_view_picker.fit_to_longest_item = false
	_view_picker.custom_minimum_size.x = 150.0
	_view_picker.add_item("Вид · 3D")
	_view_picker.set_item_metadata(0, "3d")
	_view_picker.add_item("Вид · 2D диагностика")
	_view_picker.set_item_metadata(1, "2d")
	_view_picker.item_selected.connect(_select_field_view_mode)
	header.add_child(_view_picker)
	_camera_menu = MenuButton.new()
	_camera_menu.name = "CombatCameraMenu"
	_camera_menu.text = "Камера ▾"
	_camera_menu.tooltip_text = "Обзор, плавные стороны, инверсия и отдельная блокировка каждой оси"
	var camera_popup := _camera_menu.get_popup()
	camera_popup.add_item("Весь план", CAMERA_MENU_OVERVIEW)
	camera_popup.add_separator()
	camera_popup.add_check_item("Инверсия по вертикали", CAMERA_MENU_INVERT_VERTICAL)
	camera_popup.add_check_item("Поворот по сторонам · плавно", CAMERA_MENU_STEP_ROTATION)
	camera_popup.add_separator()
	camera_popup.add_check_item("Блокировать горизонтальный поворот", CAMERA_MENU_LOCK_HORIZONTAL)
	camera_popup.add_check_item("Блокировать вертикальный наклон", CAMERA_MENU_LOCK_VERTICAL)
	camera_popup.id_pressed.connect(_on_camera_menu_pressed)
	header.add_child(_camera_menu)
	_outcome_label = Label.new()
	_outcome_label.add_theme_font_size_override("font_size", 18)
	_outcome_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_outcome_label)
	_return_button = Button.new()
	_return_button.name = "CombatReturn"
	_return_button.text = "Вернуться в локацию"
	_return_button.visible = false
	_return_button.pressed.connect(_return_from_encounter)
	header.add_child(_return_button)
	var pause_button := Button.new()
	pause_button.name = "CombatPauseButton"
	pause_button.text = "Меню · Esc"
	pause_button.pressed.connect(_open_pause_menu)
	header.add_child(pause_button)
	_reset_button = Button.new()
	_reset_button.text = "Сбросить · R"
	_reset_button.pressed.connect(_reset_lab)
	header.add_child(_reset_button)
	return header


func _build_timeline() -> Control:
	var panel := PanelContainer.new()
	panel.name = "CombatTimelinePanel"
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.09, 0.15, 0.86), Color("38445d")))
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	margin.add_child(content)
	var caption := Label.new()
	caption.text = "ОЧЕРЕДЬ ХОДОВ"
	caption.modulate = COLOR_MUTED
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(caption)
	_timeline_row = VBoxContainer.new()
	_timeline_row.name = "CombatTimeline"
	_timeline_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline_row.add_theme_constant_override("separation", 5)
	content.add_child(_timeline_row)
	return panel


func _build_field_panel() -> Control:
	var panel := PanelContainer.new()
	_field_panel = panel
	panel.name = "CombatFieldPanel"
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0)))
	_field_row = HBoxContainer.new()
	_field_row.name = "CombatZoneField"
	_field_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_field_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _external_3d_world != null:
		_field_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_field_row.add_theme_constant_override("separation", 9)
	panel.add_child(_field_row)
	return panel


func _build_console_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "CombatConsolePanel"
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.045, 0.075, 0.88), Color(0.22, 0.36, 0.52, 0.82)))
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	margin.add_child(content)
	_field_heading = Label.new()
	_field_heading.modulate = COLOR_ACCENT
	_field_heading.add_theme_font_size_override("font_size", 15)
	content.add_child(_field_heading)
	_source_note = Label.new()
	_source_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_source_note.modulate = Color("8ea0bb")
	_source_note.max_lines_visible = 2
	content.add_child(_source_note)
	_log_label = RichTextLabel.new()
	_log_label.name = "CombatLog"
	_log_label.bbcode_enabled = true
	_log_label.fit_content = false
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.custom_minimum_size = Vector2(0, 80)
	_log_label.scroll_active = true
	_log_label.add_theme_font_size_override("normal_font_size", 14)
	content.add_child(_log_label)
	_console_input = LineEdit.new()
	_console_input.name = "CombatConsoleInput"
	_console_input.placeholder_text = "~ команда…  help — список команд"
	_console_input.clear_button_enabled = true
	_console_input.text_submitted.connect(_submit_console_command)
	content.add_child(_console_input)
	return panel


func _build_command_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "CombatCommandPanel"
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.09, 0.15, 0.9), Color("44516b")))
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	panel.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	_turn_label = Label.new()
	_turn_label.name = "CombatTurnLabel"
	_turn_label.add_theme_font_size_override("font_size", 21)
	content.add_child(_turn_label)
	_movement_row = HBoxContainer.new()
	_movement_row.name = "CombatMovementRow"
	_movement_row.add_theme_constant_override("separation", 6)
	content.add_child(_movement_row)
	_move_button = Button.new()
	_move_button.name = "CombatMoveMode"
	_move_button.text = "Перемещение по клеткам · M"
	_move_button.toggle_mode = true
	_move_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_move_button.pressed.connect(_toggle_move_mode)
	_movement_row.add_child(_move_button)
	_cancel_move_button = Button.new()
	_cancel_move_button.name = "CombatCancelMove"
	_cancel_move_button.text = "Вернуть"
	_cancel_move_button.pressed.connect(_cancel_pending_move)
	_movement_row.add_child(_cancel_move_button)
	var action_caption := Label.new()
	action_caption.text = "ДЕЙСТВИЯ"
	action_caption.modulate = COLOR_MUTED
	content.add_child(action_caption)
	_action_list = VBoxContainer.new()
	_action_list.name = "CombatActions"
	_action_list.add_theme_constant_override("separation", 6)
	content.add_child(_action_list)
	_target_hint = Label.new()
	_target_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_hint.modulate = COLOR_MUTED
	content.add_child(_target_hint)
	_preview_caption = Label.new()
	_preview_caption.name = "CombatPreviewCaption"
	_preview_caption.text = "УСЛОВИЯ И ЭФФЕКТ"
	_preview_caption.modulate = COLOR_ACCENT
	content.add_child(_preview_caption)
	_preview_label = RichTextLabel.new()
	_preview_label.name = "CombatPreview"
	_preview_label.bbcode_enabled = true
	_preview_label.fit_content = true
	_preview_label.custom_minimum_size = Vector2(0, 92)
	_preview_label.add_theme_stylebox_override("normal", _panel_style(Color("151b27"), Color("49566e")))
	content.add_child(_preview_label)
	_predicted_label = Label.new()
	_predicted_label.name = "CombatPredictedTimeline"
	_predicted_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_predicted_label.modulate = Color("a9b8d0")
	content.add_child(_predicted_label)
	_confirm_button = Button.new()
	_confirm_button.name = "CombatConfirm"
	_confirm_button.text = "Действие выполняется после выбора цели"
	_confirm_button.custom_minimum_size = Vector2(0, 44)
	_confirm_button.pressed.connect(_confirm_action)
	_confirm_button.visible = false
	content.add_child(_confirm_button)
	_lift_choice_row = HBoxContainer.new()
	_lift_choice_row.name = "CombatLiftChoice"
	_lift_choice_row.add_theme_constant_override("separation", 8)
	_lift_choice_row.visible = false
	content.add_child(_lift_choice_row)
	_lift_throw_button = Button.new()
	_lift_throw_button.name = "CombatLiftThrowNow"
	_lift_throw_button.text = "Бросить"
	_lift_throw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lift_throw_button.pressed.connect(_choose_lift_throw)
	_lift_choice_row.add_child(_lift_throw_button)
	_lift_hold_button = Button.new()
	_lift_hold_button.name = "CombatLiftKeepHeld"
	_lift_hold_button.text = "Удерживать\nи защищаться"
	_lift_hold_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lift_hold_button.pressed.connect(_choose_lift_hold)
	_lift_choice_row.add_child(_lift_hold_button)
	var lower := Button.new()
	lower.name = "CombatLiftLower"
	lower.text = "Опустить"
	lower.pressed.connect(_choose_lift_lower)
	_lift_choice_row.add_child(lower)
	_scope_label = Label.new()
	_scope_label.text = "Лаборатория не сохраняет прогресс и не создаёт battle Resources. Здесь проверяются только решения D1."
	_scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scope_label.modulate = Color("77869f")
	_scope_label.visible = false
	content.add_child(_scope_label)
	return panel


func _build_ability_info_panel() -> void:
	_ability_info_panel = PanelContainer.new()
	_ability_info_panel.name = "CombatAbilityInfoPanel"
	_ability_info_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_ability_info_panel.offset_left = 665
	_ability_info_panel.offset_top = -218
	_ability_info_panel.offset_right = -470
	_ability_info_panel.offset_bottom = -52
	_ability_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ability_info_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.035, 0.055, 0.09, 0.94), Color("44516b"))
	)
	add_child(_ability_info_panel)
	_ability_info_label = RichTextLabel.new()
	_ability_info_label.name = "CombatAbilityInfo"
	_ability_info_label.bbcode_enabled = true
	_ability_info_label.fit_content = false
	_ability_info_label.scroll_active = true
	_ability_info_label.add_theme_font_size_override("normal_font_size", 14)
	_ability_info_panel.add_child(_ability_info_label)


func _build_enemy_info_panel() -> void:
	_enemy_info_panel = PanelContainer.new()
	_enemy_info_panel.name = "CombatEnemyInfoPanel"
	_enemy_info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_info_panel.offset_left = -430
	_enemy_info_panel.offset_top = 96
	_enemy_info_panel.offset_right = -16
	_enemy_info_panel.offset_bottom = 392
	_enemy_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_info_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.045, 0.055, 0.085, 0.96), Color(COLOR_ENEMY, 0.8))
	)
	_enemy_info_panel.visible = false
	add_child(_enemy_info_panel)
	_enemy_info_label = RichTextLabel.new()
	_enemy_info_label.name = "CombatEnemyInfo"
	_enemy_info_label.bbcode_enabled = true
	_enemy_info_label.fit_content = false
	_enemy_info_label.scroll_active = true
	_enemy_info_label.add_theme_font_size_override("normal_font_size", 14)
	_enemy_info_panel.add_child(_enemy_info_label)


func _build_radial_menu() -> void:
	_radial_menu = Control.new()
	_radial_menu.name = "CombatRadialMenu"
	_radial_menu.custom_minimum_size = Vector2(360, 360)
	_radial_menu.size = Vector2(360, 360)
	_radial_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radial_menu.visible = false
	add_child(_radial_menu)

	_radial_ring = Panel.new()
	_radial_ring.name = "CombatRadialRing"
	_radial_ring.position = Vector2(87, 87)
	_radial_ring.size = Vector2(186, 186)
	_radial_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Color(0.04, 0.07, 0.12, 0.32)
	ring_style.border_color = Color(COLOR_HERO, 0.8)
	ring_style.set_border_width_all(3)
	ring_style.set_corner_radius_all(96)
	_radial_ring.add_theme_stylebox_override("panel", ring_style)
	_radial_menu.add_child(_radial_ring)

	_radial_confirm = Button.new()
	_radial_confirm.name = "CombatRadialConfirm"
	_radial_confirm.position = Vector2(119, 184)
	_radial_confirm.size = Vector2(122, 36)
	_radial_confirm.text = "ВЫПОЛНЯЕТСЯ ПО ЦЕЛИ"
	_radial_confirm.visible = false
	_radial_menu.add_child(_radial_confirm)

	_command_drawer = PanelContainer.new()
	_command_drawer.name = "CombatCommandDrawer"
	_command_drawer.custom_minimum_size = Vector2(330, 300)
	_command_drawer.size = Vector2(330, 300)
	_command_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	_command_drawer.visible = false
	_command_drawer.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.025, 0.045, 0.075, 0.98), Color("536886"))
	)
	add_child(_command_drawer)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	_command_drawer.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	content.add_child(header)
	_command_drawer_title = Label.new()
	_command_drawer_title.name = "CombatCommandDrawerTitle"
	_command_drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_drawer_title.add_theme_color_override("font_color", COLOR_ACCENT)
	_command_drawer_title.add_theme_font_size_override("font_size", 16)
	header.add_child(_command_drawer_title)
	_command_drawer_close = Button.new()
	_command_drawer_close.name = "CombatCommandDrawerClose"
	_command_drawer_close.text = "Назад · Esc"
	_command_drawer_close.pressed.connect(_open_radial_page.bind("root"))
	header.add_child(_command_drawer_close)
	var scroll := ScrollContainer.new()
	scroll.name = "CombatCommandDrawerScroll"
	scroll.custom_minimum_size = Vector2(0, 238)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_command_drawer_list = VBoxContainer.new()
	_command_drawer_list.name = "CombatCommandDrawerList"
	_command_drawer_list.custom_minimum_size = Vector2(300, 0)
	_command_drawer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_command_drawer_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_command_drawer_list)


func _build_result_overlay() -> void:
	_result_overlay = ColorRect.new()
	_result_overlay.name = "CombatResultOverlay"
	_result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.color = Color(0.025, 0.035, 0.06, 0.82)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_overlay.visible = false
	add_child(_result_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "CombatResultPanel"
	panel.custom_minimum_size = Vector2(560, 330)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("182234"), COLOR_ACCENT))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	margin.add_child(content)
	_result_title = Label.new()
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_font_size_override("font_size", 34)
	_result_title.modulate = COLOR_ACCENT
	content.add_child(_result_title)
	_result_body = Label.new()
	_result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_body.add_theme_font_size_override("font_size", 18)
	_result_body.modulate = COLOR_TEXT
	content.add_child(_result_body)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	_result_retry = Button.new()
	_result_retry.name = "CombatResultRetry"
	_result_retry.text = "Повторить · R"
	_result_retry.custom_minimum_size = Vector2(155, 48)
	_result_retry.pressed.connect(_retry_encounter)
	buttons.add_child(_result_retry)
	_result_return = Button.new()
	_result_return.name = "CombatResultReturn"
	_result_return.text = "Вернуться"
	_result_return.custom_minimum_size = Vector2(155, 48)
	_result_return.pressed.connect(_return_from_encounter)
	buttons.add_child(_result_return)
	_result_continue = Button.new()
	_result_continue.name = "CombatResultContinue"
	_result_continue.text = "Продолжить · Enter"
	_result_continue.custom_minimum_size = Vector2(190, 48)
	_result_continue.pressed.connect(_return_from_encounter)
	buttons.add_child(_result_continue)


func _build_pause_overlay() -> void:
	_pause_overlay = ColorRect.new()
	_pause_overlay.name = "CombatPauseOverlay"
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.color = Color(0.015, 0.025, 0.045, 0.86)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "CombatPausePanel"
	panel.custom_minimum_size = Vector2(430, 360)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("182234"), COLOR_HERO))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 30)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	var title := Label.new()
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.modulate = COLOR_ACCENT
	content.add_child(title)
	var hint := Label.new()
	hint.text = "Бой остановлен. Esc — продолжить."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = COLOR_MUTED
	content.add_child(hint)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(spacer)
	_pause_resume = Button.new()
	_pause_resume.name = "CombatPauseResume"
	_pause_resume.text = "Продолжить"
	_pause_resume.custom_minimum_size = Vector2(0, 50)
	_pause_resume.pressed.connect(_close_pause_menu)
	content.add_child(_pause_resume)
	var retry := Button.new()
	retry.name = "CombatPauseRetry"
	retry.text = "Повторить бой"
	retry.custom_minimum_size = Vector2(0, 50)
	retry.pressed.connect(_restart_from_pause)
	content.add_child(retry)
	var quit := Button.new()
	quit.name = "CombatPauseQuit"
	quit.text = "Закрыть игру"
	quit.custom_minimum_size = Vector2(0, 50)
	quit.pressed.connect(_quit_game)
	content.add_child(quit)


func _build_fade_overlay() -> void:
	_fade_overlay = ColorRect.new()
	_fade_overlay.name = "CombatFadeOverlay"
	_fade_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_overlay.color = Color.BLACK
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_fade_overlay)


func _reset_lab() -> void:
	_canceling_lift = false
	_lift_menu_ready = false
	if _external_3d_world != null:
		_external_3d_world.call("finish_lift_presentation")
	_refresh_mode_copy()
	var laboratory_field := _field_for_mode()
	_battle_seed_serial += 1
	var battle_seed := int(Time.get_ticks_usec()) ^ (_battle_seed_serial * 7919)
	_state = (
		_authored_encounter.initial_state(_party_snapshot, battle_seed)
		if _authored_encounter != null
		else (Grid.field_mutation_state(null, battle_seed)
		if _encounter_mode == "terrain"
		else (Grid.initial_state(laboratory_field, battle_seed) if _is_grid_mode() else Combat.initial_state(battle_seed)))
	)
	if _authored_encounter == null and _is_grid_mode():
		_add_lab_effect_actions("mira", ["earth_raise", "earth_wall", "wind_spread"])
	var battle_inventory := (
		_inventory_snapshot
		if _authored_encounter != null
		else {"herb": 2, "qingxin_tea": 1, "revival_spark": 1}
	)
	_state = Combat.with_inventory(
		_state, battle_inventory, _combat_item_definitions(battle_inventory)
	)
	if _external_3d_world != null:
		if _external_3d_world.has_method("request_camera_overview"):
			_external_3d_world.call("request_camera_overview")
		_external_3d_world.set(
			"battlefield",
			_authored_encounter.battlefield if _authored_encounter != null else laboratory_field,
		)
	_selected_action = ""
	_selected_target = ""
	_selected_target_cell = Combat.INVALID_CELL
	_selected_secondary_cell = Combat.INVALID_CELL
	_lifted_target_id = ""
	_current_preview = {}
	_move_mode = false
	_radial_targeting = false
	_radial_page = "root"
	_radial_actor_id = ""
	_selection_actor_id = ""
	_browsed_command_id = ""
	_selection_origin_page = "root"
	_selection_origin_action = ""
	_hovered_unit_id = ""
	_pending_actor_id = ""
	_manual_move_selected = false
	_pending_cell = Vector2i(-1, -1)
	_transition_in_progress = false
	_refresh()


func _add_lab_effect_actions(unit_id: String, action_ids: Array[String]) -> void:
	## Standalone laboratory convenience only. Canonical hero Resources keep the
	## approved roles until the player assigns a candidate through the editor.
	var units: Dictionary = _state.get("units", {})
	if not units.has(unit_id):
		return
	var unit: Dictionary = units[unit_id]
	var actions: Array = unit.get("actions", []).duplicate()
	for action_id in action_ids:
		if action_id not in actions:
			actions.append(action_id)
	unit["actions"] = actions
	units[unit_id] = unit
	_state["units"] = units


func _refresh() -> void:
	_invalidate_plan_cache()
	_ensure_selection()
	_invalidate_plan_cache()
	_refresh_timeline()
	_refresh_commands()
	_refresh_field()
	_refresh_log()
	_refresh_radial_actions()
	_refresh_ability_info()
	_refresh_enemy_info()
	_refresh_result_overlay()
	_sync_camera_controls()


func _invalidate_plan_cache() -> void:
	var key := "%s|%s|%s" % [hash(_state), _pending_cell, _manual_move_selected]
	if key == _plan_cache_key:
		return
	_plan_cache_key = key
	_action_target_cache.clear()
	_action_target_cell_cache.clear()
	_plan_contexts.clear()
	_hover_cell = Combat.INVALID_CELL


func _ensure_selection() -> void:
	if Combat.outcome(_state) != "active":
		_clear_selected_action_state()
		_browsed_command_id = ""
		return
	var actor_id := Combat.current_unit_id(_state)
	var actor := Combat.unit_definition(_state, actor_id)
	if actor_id != _selection_actor_id:
		_selection_actor_id = actor_id
		_clear_selected_action_state()
		_browsed_command_id = ""
		_selection_origin_page = "root"
		_selection_origin_action = ""
	if _is_grid_mode():
		var reachable := Grid.reachable_cells(_state, actor_id)
		if _pending_actor_id != actor_id or _pending_cell not in reachable:
			_pending_actor_id = actor_id
			_pending_cell = actor.get("cell", Vector2i.ZERO)
			_move_mode = false
	if str(actor.get("team", "")) != "hero":
		_clear_selected_action_state()
		_browsed_command_id = ""
		return
	var selection_state := _selection_state()
	var actions: Array[String] = Combat.command_ids_for_current_actor(selection_state, false)
	var item_commands: Array[String] = []
	if Combat.held_target_id(selection_state, actor_id).is_empty():
		item_commands = Combat.combat_item_ids(selection_state)
	if (
		not _browsed_command_id.is_empty()
		and not _browsed_command_id.begins_with("__")
		and _browsed_command_id not in actions
		and _browsed_command_id not in item_commands
	):
		_browsed_command_id = ""
	if _selected_action.is_empty():
		_selected_target = ""
		_selected_target_cell = Combat.INVALID_CELL
		_selected_secondary_cell = Combat.INVALID_CELL
		_lifted_target_id = ""
		_lift_choice = ""
		return
	var command_owned := (
		_selected_action in actions
		or _selected_action in item_commands
	)
	if not command_owned or not _action_has_valid_target(_selected_action):
		_clear_selected_action_state()
		return
	var selected_definition := Combat.command_definition(selection_state, _selected_action)
	if str(selected_definition.get("target", "")) == "cell":
		_selected_target = ""
		var valid_cells := _action_target_cells(_selected_action)
		if _selected_target_cell not in valid_cells:
			_selected_target_cell = Combat.INVALID_CELL
	else:
		_selected_target_cell = Combat.INVALID_CELL
	var targets := _action_target_ids(_selected_action)
	if (
		str(Combat.command_definition(selection_state, _selected_action).get("effect", "")) != "lift_throw"
		or _lifted_target_id not in targets
	):
		_lifted_target_id = ""
	if _selected_target not in targets:
		_selected_target = (
			""
			if _radial_targeting and str(Combat.command_definition(selection_state, _selected_action).get("target", "")) != "self"
			else (targets[0] if not targets.is_empty() else "")
		)
	var valid_secondary_cells := (
		Grid.approach_secondary_cells(
			_state, _selected_action, _selected_target, _pending_cell
		)
		if _is_grid_mode()
		else Combat.valid_secondary_cells(
			selection_state, _selected_action, _selected_target
		)
	)
	if (
		str(Combat.command_definition(selection_state, _selected_action).get("effect", "")) != "lift_throw"
		or _selected_target.is_empty()
		or _selected_secondary_cell not in valid_secondary_cells
	):
		_selected_secondary_cell = Combat.INVALID_CELL


func _refresh_timeline() -> void:
	_clear(_timeline_row)
	var entries := Combat.timeline(_state, 8)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var unit := Combat.unit_definition(_state, str(entry.get("unitId", "")))
		var badge := PanelContainer.new()
		badge.custom_minimum_size = Vector2(0, 42)
		badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var team_color := _unit_color(unit)
		badge.add_theme_stylebox_override(
			"panel",
			_panel_style(team_color.darkened(0.72), team_color if index == 0 else team_color.darkened(0.25)),
		)
		var label := Label.new()
		label.text = "%d · %s" % [index + 1, str(unit.get("name", "?"))]
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.tooltip_text = "%s · speed %d · t %.1f" % [
			str(unit.get("name", "?")), int(unit.get("speed", 0)), float(entry.get("at", 0.0)),
		]
		badge.add_child(label)
		_timeline_row.add_child(badge)


func _refresh_field() -> void:
	var field_action := _field_preview_action()
	var field_target := _selected_target if field_action == _selected_action else ""
	var field_move_mode := _field_preview_move_mode()
	if _external_3d_world != null:
		var show_standard_world := _is_grid_mode() and _field_view_mode == "3d"
		_external_3d_world.visible = show_standard_world
		if show_standard_world:
			_clear(_field_row)
			var input_surface := Control.new()
			input_surface.name = "CombatFieldInputSurface"
			input_surface.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			input_surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
			input_surface.mouse_filter = Control.MOUSE_FILTER_STOP
			input_surface.gui_input.connect(_on_external_field_gui_input.bind(input_surface))
			_field_row.add_child(input_surface)
			_external_3d_world.call(
				"configure",
				_state,
				field_action,
				field_target,
				_pending_cell,
				field_move_mode,
				_public_field_preview(field_action),
				_selected_secondary_cell,
				_lifted_target_id,
				_selected_target_cell,
			)
			_sync_pair_context_visual()
			return
	if _is_grid_mode():
		var desired_name := "CombatGrid3DField" if _field_view_mode == "3d" else "CombatGridField"
		var grid_view = null
		if _field_row.get_child_count() == 1 and _field_row.get_child(0).name == desired_name:
			grid_view = _field_row.get_child(0) as Control
		else:
			_clear(_field_row)
			grid_view = Grid3DView.new() if _field_view_mode == "3d" else GridView.new()
			grid_view.name = desired_name
			grid_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
			grid_view.cell_chosen.connect(_on_grid_cell_chosen)
			grid_view.cell_hovered.connect(_on_grid_cell_hovered)
			_field_row.add_child(grid_view)
		grid_view.configure(
			_state, field_action, field_target, _pending_cell, field_move_mode,
			_public_field_preview(field_action), _selected_secondary_cell, _selected_target_cell
		)
		if grid_view.has_method("set_pair_context_action"):
			grid_view.call("set_pair_context_action", _active_pair_context_action())
		return
	_clear(_field_row)
	var zones: Array = _state.get("zones", [])
	for zone_index in zones.size():
		var zone: Dictionary = zones[zone_index]
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(180, 300)
		var zone_color: Color = zone.get("color", Color("384052"))
		card.add_theme_stylebox_override("panel", _panel_style(zone_color.darkened(0.35), zone_color.lightened(0.18)))
		var margin := MarginContainer.new()
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			margin.add_theme_constant_override(side, 10)
		card.add_child(margin)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 7)
		margin.add_child(column)
		var name := Label.new()
		name.text = str(zone.get("name", "Область"))
		name.add_theme_font_size_override("font_size", 17)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(name)
		var rule := Label.new()
		rule.text = str(zone.get("subtitle", ""))
		rule.modulate = Color("9ed9ea") if "wet" in zone.get("tags", []) else COLOR_MUTED
		rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(rule)
		var separator := HSeparator.new()
		column.add_child(separator)
		for raw_id in _state.get("units", {}):
			var unit_id := str(raw_id)
			var unit := Combat.unit_definition(_state, unit_id)
			if int(unit.get("zone", -1)) != zone_index:
				continue
			column.add_child(_build_unit_button(unit_id, unit))
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(spacer)
		_field_row.add_child(card)


func _field_preview_action() -> String:
	if not _selected_action.is_empty():
		return _selected_action
	return "" if _browsed_command_id.begins_with("__") else _browsed_command_id


func _field_preview_move_mode() -> bool:
	return _move_mode or (
		_selected_action.is_empty() and _browsed_command_id == "__move"
	)


func _public_field_preview(field_action: String) -> Dictionary:
	# Cell/state deltas in the internal preview depend on the hidden hit result.
	# Sending them to either field projection would reveal that result visually.
	var result := {}
	if not field_action.is_empty():
		var context := _plan_context(field_action)
		result["movementCells"] = context.get("movementCells", [])
		result["castCells"] = context.get("castCells", [])
		if field_action == _selected_action or _move_mode:
			for key in ["applicationCell", "effectCell", "footprint", "ok", "reason", "commitRule"]:
				result[key] = _action_plan.get(key)
	for key in [
		"requestedActionId",
		"approachTargetId",
		"approachTargetCell",
		"approachDestination",
		"approachAttackPosition",
		"approachPath",
		"approachWillExecute",
		"approachFallbackDefend",
	]:
		if _current_preview.has(key):
			result[key] = _current_preview[key]
	var action := Combat.command_definition(_selection_state(), field_action)
	if str(action.get("target", "")) == "cell":
		result["validTargetCells"] = _action_target_cells(field_action)
	elif not field_action.is_empty():
		result["validTargetIds"] = _action_target_ids(field_action)
	if not result.has("validTargetIds"):
		result["validTargetIds"] = []
	if not result.has("validTargetCells"):
		result["validTargetCells"] = []
	result["secondaryCells"] = []
	if str(action.get("effect", "")) == "lift_throw" and not _lifted_target_id.is_empty():
		var context := _plan_context(field_action)
		if not context.has("secondaryCells"):
			context["secondaryCells"] = Grid.approach_secondary_cells(_state, field_action, _lifted_target_id, _pending_cell)
		result["secondaryCells"] = context["secondaryCells"]

	return result


func _approach_intent_copy(preview: Dictionary) -> String:
	if not preview.has("approachDestination"):
		return ""
	var destination: Vector2i = preview.get("approachDestination", Combat.INVALID_CELL)
	if destination == Combat.INVALID_CELL:
		return ""
	var labels := PackedStringArray()
	for raw_cell in preview.get("approachPath", []):
		if raw_cell is Vector2i:
			labels.append(Grid.cell_label(raw_cell))
	var route_copy := "Маршрут: %s" % " → ".join(labels) if labels.size() > 1 else "Без перемещения"
	if bool(preview.get("approachFallbackDefend", false)):
		return "%s\nОстановка: %s · ◆ ЗАЩИТА\nВыбранная команда не достанет цель и не расходует ресурсы." % [
			route_copy, Grid.cell_label(destination),
		]
	var requested_action := str(preview.get("requestedActionId", preview.get("actionId", "")))
	var action_name := str(Combat.command_definition(_state, requested_action).get("name", requested_action))
	return "%s\nОстановка: %s · затем %s" % [
		route_copy, Grid.cell_label(destination), action_name,
	]


func _on_external_field_gui_input(event: InputEvent, surface: Control) -> void:
	if _external_3d_world == null:
		return
	if bool(_external_3d_world.call("handle_camera_input", event)):
		surface.accept_event()
		return
	if event is InputEventMouseMotion:
		_inspect_unit_at(event.global_position)
		_preview_target_at(event.global_position)
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	if bool(_external_3d_world.call("choose_cell_at", event.global_position)):
		surface.accept_event()


func _inspect_unit_at(screen_position: Vector2) -> void:
	if _external_3d_world == null:
		_set_inspected_enemy("")
		return
	var cell := _external_3d_world.call("pick_cell_at", screen_position) as Vector2i
	var unit_id := ""
	if Grid.is_inside(_state, cell):
		unit_id = str(_external_3d_world.call("projected_occupant_at", cell))
	var unit := Combat.unit_definition(_state, unit_id)
	if unit.is_empty() or str(unit.get("team", "")) != "enemy":
		unit_id = ""
	_set_inspected_enemy(unit_id)


func _set_inspected_enemy(unit_id: String) -> void:
	if unit_id == _hovered_unit_id:
		return
	_hovered_unit_id = unit_id
	_refresh_enemy_info()


func _clear_inspected_enemy(unit_id: String) -> void:
	if unit_id == _hovered_unit_id:
		_set_inspected_enemy("")


func _preview_target_at(screen_position: Vector2) -> void:
	if _external_3d_world != null:
		_external_3d_world.call("hover_cell_at", screen_position)


func _plan_context(action_id: String) -> Dictionary:
	if not _plan_contexts.has(action_id):
		_plan_contexts[action_id] = Grid.action_plan_context(_state, action_id, _pending_cell, _manual_move_selected)
	return _plan_contexts[action_id]


func _rebuild_action_plan() -> void:
	if not _locked_lift_plan.is_empty() and _locked_lift_plan.get("stateHash") != hash(_state):
		_current_preview = {"ok": false, "error": "Состояние боя изменилось. Отмените подъём и выберите действие заново."}
		_action_plan = {"ok": false, "reason": _current_preview.error}
		return
	var cell := _selected_target_cell
	if not _selected_target.is_empty():
		cell = Combat.unit_definition(_selection_state(), _selected_target).get("cell", Combat.INVALID_CELL)
	var destination := _pending_cell
	var context := _plan_context(_selected_action)
	if not _locked_lift_plan.is_empty():
		cell = _locked_lift_plan.applicationCell
		destination = _locked_lift_plan.destination
		context = {
			"stateHash": hash(_state), "actionId": _selected_action, "destination": destination, "fixedDestination": true,
			"eligibleIds": [_locked_lift_plan.occupantId], "eligibleCells": [],
		}
	_action_plan = Grid.action_plan(
		_state, _selected_action, cell, destination, _selected_secondary_cell,
		"hold" if _lift_choice.is_empty() else _lift_choice, context,
	)
	_current_preview = _action_plan.get("resolved", {})
	if _current_preview.is_empty():
		_current_preview = {"ok": false, "error": _action_plan.get("reason", ""), "summary": _action_plan.get("reason", "")}


func _on_grid_cell_hovered(cell: Vector2i) -> void:
	if _canceling_lift or not _radial_targeting or (not _move_mode and _selected_action.is_empty()) or cell == _hover_cell:
		return
	_hover_cell = cell
	if _move_mode:
		_action_plan = Grid.action_plan(_state, "__move", cell, _pending_cell, Combat.INVALID_CELL, "hold", _plan_context("__move"))
		_current_preview = _action_plan.get("resolved", {})
		_preview_label.text = _approach_intent_copy(_current_preview) + str(_action_plan.get("reason", ""))
		_target_hint.text = _preview_label.text
		_update_hover_projection(_public_field_preview("__move"))
		return
	if _lift_choice == "throw" and not _lifted_target_id.is_empty():
		_selected_secondary_cell = cell
	else:
		_selected_target_cell = cell
		_selected_target = Grid.action_occupant_id(_selection_state(), _selected_action, cell)
	_rebuild_action_plan()
	_preview_label.text = Combat.describe_intent(_state, _selected_action, _selected_target, _pending_cell, _selection_state(), _selected_target_cell)
	_preview_label.text += "\n" + _approach_intent_copy(_current_preview)
	if not bool(_action_plan.get("ok", false)):
		_preview_label.text += "\n" + str(_action_plan.get("reason", ""))
	var center: Vector2i = _action_plan.get("effectCell", cell)
	_target_hint.text = "Клетка применения: %s\n%s" % [Grid.cell_label(center) if Grid.is_inside(_state, center) else "—", _approach_intent_copy(_current_preview)]
	if not bool(_action_plan.get("ok", false)):
		_target_hint.text += "\n" + str(_action_plan.get("reason", ""))
	_refresh_predicted_timeline()
	_update_hover_projection(_public_field_preview(_selected_action))


func _update_hover_projection(projection: Dictionary) -> void:
	if _external_3d_world != null:
		_external_3d_world.call("update_action_preview", projection, _selected_target, _selected_target_cell, _selected_secondary_cell)
	elif _field_row.get_child_count() == 1:
		var view := _field_row.get_child(0)
		if view.has_method("update_action_preview"):
			view.call("update_action_preview", projection, _selected_target, _selected_target_cell, _selected_secondary_cell)


func _build_unit_button(unit_id: String, unit: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 72)
	var status_text := _status_text(unit)
	var field_action := _field_preview_action()
	var valid_targets := _action_target_ids(field_action)
	var preview_candidate := (
		_selected_action.is_empty()
		and not field_action.is_empty()
		and unit_id in valid_targets
	)
	button.text = "%s%s\nHP %d/%d · MP %d/%d%s" % [
		("▶ " if unit_id == _selected_target else ("◇ " if preview_candidate else "")),
		str(unit.get("name", unit_id)),
		int(unit.get("hp", 0)), int(unit.get("maxHp", 0)),
		int(unit.get("mp", 0)), int(unit.get("maxMp", 0)),
		" · %s" % status_text if not status_text.is_empty() else "",
	]
	var team_color := _unit_color(unit)
	button.modulate = team_color if int(unit.get("hp", 0)) > 0 else Color(0.45, 0.45, 0.5, 0.65)
	button.disabled = (
		int(unit.get("hp", 0)) <= 0
		or not _radial_targeting
		or _selected_action.is_empty()
		or unit_id not in valid_targets
	)
	button.tooltip_text = "%s\nОбласть: %s\nСтатусы: %s" % [
		str(unit.get("name", unit_id)),
		Combat.zone_name(_state, int(unit.get("zone", -1))),
		status_text if not status_text.is_empty() else "нет",
	]
	button.pressed.connect(_select_target.bind(unit_id))
	if str(unit.get("team", "")) == "enemy":
		button.mouse_entered.connect(_set_inspected_enemy.bind(unit_id))
		button.mouse_exited.connect(_clear_inspected_enemy.bind(unit_id))
		button.focus_entered.connect(_set_inspected_enemy.bind(unit_id))
		button.focus_exited.connect(_clear_inspected_enemy.bind(unit_id))
	return button


func _refresh_enemy_info() -> void:
	if _enemy_info_panel == null or _enemy_info_label == null:
		return
	var unit := Combat.unit_definition(_state, _hovered_unit_id)
	if unit.is_empty() or str(unit.get("team", "")) != "enemy":
		_enemy_info_panel.visible = false
		_enemy_info_label.text = ""
		return
	var resistances := unit.get("resistances", {}) as Dictionary
	var status_resistances := unit.get("statusResistances", {}) as Dictionary
	var status_copy := _status_icon_text(unit)
	_enemy_info_label.text = (
		"[color=#f07883]ИЗУЧЕНИЕ ПРОТИВНИКА[/color]\n"
		+ "[b]%s[/b] · уровень %d\n" % [
			str(unit.get("name", _hovered_unit_id)), int(unit.get("level", 1)),
		]
		+ "%s\n" % str(unit.get("description", "Описание пока не задано."))
		+ "HP [b]%d/%d[/b] · MP %d/%d\n" % [
			int(unit.get("hp", 0)), int(unit.get("maxHp", 0)),
			int(unit.get("mp", 0)), int(unit.get("maxMp", 0)),
		]
		+ "Тип: %s · размер: %s\n" % [
			str(unit.get("creatureTypeLabel", "Иное")), str(unit.get("sizeLabel", "?")),
		]
		+ "\n[color=#ffc85a]СТИХИИ[/color]\n"
		+ "Огонь: %s · Вода: %s\n" % [
			_resistance_copy(int(resistances.get("fire", 0))),
			_resistance_copy(int(resistances.get("water", 0))),
		]
		+ "Холод: %s · Молния: %s\n" % [
			_resistance_copy(int(resistances.get("cold", 0))),
			_resistance_copy(int(resistances.get("lightning", 0))),
		]
		+ "Воздух: %s · Земля: %s\n" % [
			_resistance_copy(int(resistances.get("air", 0))),
			_resistance_copy(int(resistances.get("earth", 0))),
		]
		+ "\n[color=#ffc85a]ЭФФЕКТЫ[/color]\n"
		+ "Wet: %s · Frozen: %s · Burning: %s\n" % [
			_status_resistance_copy(int(status_resistances.get("wet", 0))),
			_status_resistance_copy(int(status_resistances.get("frozen", 0))),
			_status_resistance_copy(int(status_resistances.get("burning", 0))),
		]
		+ "Стойкость к толчку: %s\n" % _push_resistance_copy(
			int(unit.get("pushResistance", 0))
		)
		+ "Активно: %s" % (status_copy if not status_copy.is_empty() else "—")
	)
	_enemy_info_panel.visible = true


func _resistance_copy(value: int) -> String:
	if value >= 100:
		return "иммунитет"
	if value > 0:
		return "сопр. %d%%" % value
	if value < 0:
		return "слабость %d%%" % absi(value)
	return "обычно"


func _status_resistance_copy(value: int) -> String:
	if value <= 0:
		return "обычно"
	return "сокр. на %d %s" % [value, "ход" if value == 1 else "хода"]


func _push_resistance_copy(value: int) -> String:
	if value <= 0:
		return "нет"
	return "%d · блокирует силу ≤ %d" % [value, value]


func _status_icon_text(unit: Dictionary) -> String:
	var entries: Array[String] = []
	for raw_status in unit.get("statuses", {}):
		var duration := int((unit.get("statuses", {}) as Dictionary).get(raw_status, 0))
		if duration <= 0:
			continue
		var definition := Combat.status_definition(str(raw_status))
		entries.append("%s %s %d" % [
			str(definition.get("icon", "●")), str(definition.get("name", raw_status)), duration,
		])
	return " · ".join(entries)


func _refresh_ability_info() -> void:
	if _ability_info_panel == null or _ability_info_label == null:
		return
	var actor := Combat.unit_definition(_state, Combat.current_unit_id(_state))
	_ability_info_panel.visible = (
		Combat.outcome(_state) == "active" and str(actor.get("team", "")) == "hero"
	)
	if not _ability_info_panel.visible:
		_pair_hover_action = ""
		_sync_pair_context_visual()
		return
	if not _selected_action.is_empty():
		_show_radial_entry_help({"id": _selected_action})
		return
	if not _browsed_command_id.is_empty():
		_show_radial_entry_help({"id": _browsed_command_id})
		return
	if _radial_page == "skill":
		_show_radial_entry_help({"id": "__skills"})
		return
	if _radial_page == "magic":
		_show_radial_entry_help({"id": "__magic"})
		return
	if _radial_page == "item":
		_show_radial_entry_help({"id": "__items"})
		return
	_pair_hover_action = ""
	_sync_pair_context_visual()
	_ability_info_label.text = (
		"[color=#ffc85a]КОМАНДЫ[/color]\n"
		+ "Выберите движение, обычное действие, Умения, Магию или Предметы. "
		+ "Наведение или фокус только показывают описание, условия, дальность и допустимые цели. "
		+ "Подтвердите команду, чтобы перейти к выбору цели."
	)


func _show_radial_entry_help(entry: Dictionary) -> void:
	if _ability_info_label == null:
		return
	var entry_id := str(entry.get("id", ""))
	var entry_action := Combat.command_definition(_selection_state(), entry_id)
	_pair_hover_action = (
		entry_id if not str(entry_action.get("partnerId", "")).is_empty() else ""
	)
	_sync_pair_context_visual()
	match entry_id:
		"__move":
			_ability_info_label.text = "[color=#65cfe1]ДВИЖЕНИЕ[/color]\nВыберите доступную клетку. Jump, высота и занятость клетки проверяются до перемещения."
		"__skills":
			_ability_info_label.text = "[color=#ffc85a]УМЕНИЯ[/color]\nФизические, парные и позиционные приёмы. Они опираются на размер, вес, союзников и состояние цели."
		"__magic":
			_ability_info_label.text = "[color=#ffc85a]МАГИЯ[/color]\nСтихийные действия расходуют личную MP и взаимодействуют со статусами и поверхностью поля."
		"__items":
			_ability_info_label.text = "[color=#79d8a3]ПРЕДМЕТЫ[/color]\nРасходуются из общей сумки. Применение детерминировано, занимает полное действие и не списывается до выбора допустимой цели."
		"__back":
			_ability_info_label.text = "[color=#91a0b8]НАЗАД[/color]\nВернуться к основным командам."
		"__lift_finish_throw":
			_ability_info_label.text = "[color=#ffc85a]БРОСИТЬ[/color]\nВыберите клетку приземления. Дальность и допустимые клетки будут показаны на поле."
		"__lift_finish_lower":
			_ability_info_label.text = "[color=#65cfe1]ОПУСТИТЬ[/color]\nВернуть поднятую цель на исходную соседнюю клетку и завершить действие."
		"__lift_finish_hold":
			_ability_info_label.text = "[color=#ad8cff]УДЕРЖИВАТЬ И ЗАЩИЩАТЬСЯ[/color]\nОставить цель над носителем и завершить его ход в Защите."
		_:
			var phase_copy := (
				"[color=#65cfe1]КОМАНДА ПОДТВЕРЖДЕНА · выберите цель · Esc/B — назад к списку[/color]"
				if entry_id == _selected_action and _radial_targeting
				else "[color=#91a0b8]ПРОСМОТР · подтвердите команду, чтобы выбирать цель[/color]"
			)
			_ability_info_label.text = "[b]%s[/b]\n%s" % [Combat.describe_intent(
				_state, entry_id, _selected_target, _pending_cell, _selection_state(),
				_selected_target_cell,
			), phase_copy]


func _browse_radial_entry(entry: Dictionary) -> void:
	var entry_id := str(entry.get("id", ""))
	if entry_id.is_empty():
		return
	if entry_id.begins_with("__lift_finish_"):
		_show_radial_entry_help(entry)
		return
	_browsed_command_id = entry_id
	_sync_browsed_button_states()
	_show_radial_entry_help(entry)
	_refresh_field()


func _focus_and_browse_entry(button: Button, entry: Dictionary) -> void:
	if button != null and not button.disabled:
		button.grab_focus()
	_browse_radial_entry(entry)


func _sync_browsed_button_states() -> void:
	for container in [_radial_menu, _command_drawer_list, _action_list]:
		if container == null:
			continue
		for child in container.get_children():
			var button := child as Button
			if button == null or not button.has_meta("combat_command_id"):
				continue
			var command_id := str(button.get_meta("combat_command_id"))
			button.button_pressed = (
				command_id == _selected_action
				or (_selected_action.is_empty() and command_id == _browsed_command_id)
			)


func _active_pair_context_action() -> String:
	if not _pair_hover_action.is_empty():
		return _pair_hover_action
	var selected := Combat.command_definition(_selection_state(), _selected_action)
	return _selected_action if not str(selected.get("partnerId", "")).is_empty() else ""


func _sync_pair_context_visual() -> void:
	if (
		_external_3d_world != null
		and _is_grid_mode()
		and _field_view_mode == "3d"
		and _external_3d_world.has_method("set_pair_context_action")
	):
		_external_3d_world.call("set_pair_context_action", _active_pair_context_action())


func _refresh_commands() -> void:
	_clear(_action_list)
	_lift_choice_row.visible = false
	var outcome := Combat.outcome(_state)
	var radial_mode := _is_grid_mode() and _field_view_mode == "3d"
	_action_list.visible = not radial_mode
	_preview_caption.visible = not radial_mode
	_preview_label.visible = not radial_mode
	_outcome_label.text = {
		"active": "Лаборатория активна",
		"victory": "ПОБЕДА · реакции проверены",
		"defeat": "ПОРАЖЕНИЕ · R для повтора",
	}.get(outcome, outcome)
	_outcome_label.modulate = COLOR_MUTED if outcome == "active" else COLOR_ACCENT
	# The old header button could leave the viewport when a long encounter title
	# expanded the row. Outcome navigation now lives in the centered result layer.
	_return_button.visible = false
	if outcome != "active":
		_movement_row.visible = false
		_turn_label.text = "Encounter завершён"
		_target_hint.text = "Выберите продолжение в окне результата."
		_preview_label.text = "[center]Нет следующего действия.[/center]"
		_predicted_label.text = ""
		_confirm_button.disabled = true
		return
	var actor_id := Combat.current_unit_id(_state)
	var actor := Combat.unit_definition(_state, actor_id)
	_movement_row.visible = (
		_is_grid_mode() and not radial_mode and str(actor.get("team", "")) == "hero"
		and Combat.held_target_id(_state, actor_id).is_empty()
	)
	if _movement_row.visible:
		_move_button.button_pressed = _move_mode
		_move_button.text = "Выберите клетку…" if _move_mode else "Перемещение по клеткам · M"
		var origin: Vector2i = actor.get("cell", Vector2i.ZERO)
		_cancel_move_button.visible = _pending_cell != origin
	_turn_label.text = "Ход: %s" % str(actor.get("name", "?"))
	_turn_label.modulate = COLOR_HERO if str(actor.get("team", "")) == "hero" else COLOR_ENEMY
	if str(actor.get("team", "")) != "hero":
		_target_hint.text = "Враг выбирает deterministic действие…"
		_preview_label.text = "[center]Ход противника рассчитывается тем же resolver.[/center]"
		_predicted_label.text = ""
		_confirm_button.disabled = true
		return
	var selection_state := _selection_state()
	var commands := Combat.command_ids_for_current_actor(selection_state)
	for index in commands.size():
		var action_id := commands[index]
		var action := Combat.command_definition(selection_state, action_id)
		var button := Button.new()
		button.name = "CombatAction_%s" % action_id
		button.set_meta("combat_command_id", action_id)
		button.toggle_mode = true
		button.button_pressed = (
			action_id == _selected_action
			or (_selected_action.is_empty() and action_id == _browsed_command_id)
		)
		var shortcut := "G" if action_id == "defend" else str(index + 1)
		var mp_copy := " · MP %d" % int(action.get("mpCost", 0)) if int(action.get("mpCost", 0)) > 0 else ""
		if not str(action.get("partnerId", "")).is_empty():
			mp_copy = " · MP %d+%d" % [
				int(action.get("mpCost", 0)), int(action.get("partnerMpCost", 0)),
			]
		if Combat.is_item_command(action_id):
			mp_copy = " · ×%d" % int((_state.get("inventory", {}) as Dictionary).get(
				Combat.item_id_from_command(action_id), 0
			))
		button.text = "%s. %s%s\n%s" % [
			shortcut,
			str(action.get("name", action_id)),
			mp_copy,
			str(action.get("hint", "")),
		]
		button.icon = _command_icon(action)
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 54)
		button.disabled = not _action_has_valid_target(action_id)
		button.modulate = _action_color(action)
		button.pressed.connect(_select_action.bind(action_id))
		button.mouse_entered.connect(_focus_and_browse_entry.bind(button, {"id": action_id}))
		button.focus_entered.connect(_browse_radial_entry.bind({"id": action_id}))
		_action_list.add_child(button)
	if _selected_action.is_empty():
		var browsed_action := _field_preview_action()
		_target_hint.text = (
			"ПРОСМОТР: %s · допустимые %s отмечены на поле · подтвердите команду" % [
				str(Combat.command_definition(selection_state, browsed_action).get("name", browsed_action)),
				(
					"клетки"
					if str(Combat.command_definition(selection_state, browsed_action).get("target", "")) == "cell"
					else "цели"
				),
			]
			if not browsed_action.is_empty()
			else "Выберите команду. Наведение показывает дальность и допустимые цели."
		)
	else:
		_target_hint.text = "%sЦель: %s" % [
			("Клетка после движения: %s · " % Grid.cell_label(_pending_cell)) if _is_grid_mode() else "",
			(
				Grid.cell_label(_selected_target_cell)
				if _selected_target_cell != Combat.INVALID_CELL
				else "выберите клетку на поле"
			)
			if str(Combat.command_definition(selection_state, _selected_action).get("target", "")) == "cell"
			else (
				str(Combat.unit_definition(_state, _selected_target).get("name", "выберите на поле"))
				if not _selected_target.is_empty() else "выберите на поле"
			),
		]
		if str(Combat.command_definition(selection_state, _selected_action).get("effect", "")) == "lift_throw":
			_target_hint.text += (
				" · выберите: бросить сейчас или оставить поднятой"
				if _lift_choice.is_empty() and not _selected_target.is_empty()
				else (
				" · приземление: %s" % Grid.cell_label(_selected_secondary_cell)
				if _selected_secondary_cell != Combat.INVALID_CELL
				else " · затем выберите клетку приземления"
				)
			)
		if _radial_targeting:
			_target_hint.text += " · команда подтверждена: выберите цель, Esc/B — назад к списку"
	if _selected_action.is_empty():
		_current_preview = {
			"ok": false,
			"summary": "Выберите клетку движения: M → клик по полю. После этого появятся доступные действия.",
		}
	else:
		if _is_grid_mode():
			_rebuild_action_plan()
		else:
			_current_preview = Combat.preview(_state, _selected_action, _selected_target)

	# The three completion choices live in the character-centred radial menu.
	# Keep the legacy row hidden so the same decision is never shown twice.
	_lift_choice_row.visible = false
	_preview_label.text = "[b]%s[/b]" % (
		Combat.describe_intent(
			_state, _selected_action, _selected_target, _pending_cell, _selection_state(),
			_selected_target_cell,
		)
		if not _selected_action.is_empty()
		else "Выберите действие и цель."
	)
	var approach_copy := _approach_intent_copy(_current_preview)
	if not approach_copy.is_empty():
		_preview_label.text += "\n\n%s" % approach_copy
		_target_hint.text += " · %s" % approach_copy.replace("\n", " · ")
	_refresh_predicted_timeline()
	_predicted_label.visible = _lifted_target_id.is_empty()
	if not _lifted_target_id.is_empty() and _lift_choice.is_empty():
		_target_hint.text = "Подъём: %s · остановка %s\nВыберите завершение. Esc — отмена." % [
			str(Combat.unit_definition(_state, _lifted_target_id).get("name", _lifted_target_id)),
			Grid.cell_label(_action_plan.get("destination", _pending_cell)),
		]
	_confirm_button.disabled = true


func _refresh_predicted_timeline() -> void:
	var timeline_action := str(_current_preview.get("actionId", _selected_action))
	var predicted := Combat.timeline(_state, 6, timeline_action)
	var names: Array[String] = []
	for entry in predicted:
		names.append(str(Combat.unit_definition(_state, str(entry.get("unitId", ""))).get("name", "?")))
	_predicted_label.text = "После действия: %s" % "  →  ".join(names)

func _refresh_radial_actions() -> void:
	if _radial_menu == null:
		return
	var lift_finish_menu := _lift_finish_menu_active()
	var focus_owner := get_viewport().gui_get_focus_owner()
	var preserve_radial_focus := (
		focus_owner != null and _radial_menu.is_ancestor_of(focus_owner)
	)
	var preserve_drawer_focus := (
		focus_owner != null
		and _command_drawer != null
		and _command_drawer.is_ancestor_of(focus_owner)
	)
	for child in _radial_menu.get_children():
		if child != _radial_ring and child != _radial_confirm:
			_radial_menu.remove_child(child)
			child.queue_free()
	var outcome := Combat.outcome(_state)
	if (
		outcome != "active"
		or not _is_grid_mode()
		or _field_view_mode != "3d"
		or (_radial_targeting and not lift_finish_menu)
		or (not _lifted_target_id.is_empty() and not lift_finish_menu)
	):
		_radial_menu.visible = false
		if _command_drawer != null:
			_command_drawer.visible = false
		return
	var actor_id := Combat.current_unit_id(_state)
	var actor := Combat.unit_definition(_state, actor_id)
	if str(actor.get("team", "")) != "hero":
		_radial_menu.visible = false
		if _command_drawer != null:
			_command_drawer.visible = false
		return
	if actor_id != _radial_actor_id:
		_radial_actor_id = actor_id
		_radial_page = "root"
	_radial_menu.visible = true
	var entries := _lift_finish_entries() if lift_finish_menu else _radial_entries(actor)
	var radius := 137.0 if entries.size() > 4 else 122.0
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var angle := -PI * 0.5 + TAU * float(index) / float(entries.size())
		var button := Button.new()
		var entry_id := str(entry.get("id", ""))
		button.name = "CombatRadial_%s" % entry_id.trim_prefix("__").replace(":", "_")
		button.set_meta("combat_command_id", entry_id)
		var button_size := Vector2(132, 64) if lift_finish_menu else Vector2(108, 50)
		button.position = Vector2(180, 180) + Vector2.from_angle(angle) * radius - button_size * 0.5
		button.size = button_size
		button.text = "%s\n%s" % [str(entry.get("shortcut", "")), str(entry.get("label", ""))]
		if lift_finish_menu:
			button.tooltip_text = str(entry.get("help", ""))
		if not entry_id.begins_with("__"):
			var action_definition := Combat.command_definition(_selection_state(), entry_id)
			var action_icon := _command_icon(action_definition)
			button.icon = action_icon
			button.expand_icon = true
			button.tooltip_text = "%s — %s\n%s" % [
				str(entry.get("shortcut", "")),
				str(action_definition.get("name", entry_id)),
				(
					"В сумке: %d" % int((_state.get("inventory", {}) as Dictionary).get(
						Combat.item_id_from_command(entry_id), 0
					))
					if Combat.is_item_command(entry_id)
					else "Стоимость: %d MP" % int(action_definition.get("mpCost", 0))
				),
			]
		button.add_theme_font_size_override("font_size", 13)
		button.toggle_mode = true
		button.button_pressed = (
			_move_mode if entry_id == "__move"
			else (
				_radial_page == "skill" if entry_id == "__skills"
				else (
					_radial_page == "magic" if entry_id == "__magic"
					else (
						_radial_page == "item" if entry_id == "__items"
						else (
							entry_id == _selected_action
							or (_selected_action.is_empty() and entry_id == _browsed_command_id)
						)
					)
				)
			)
		)
		var entry_color := _radial_entry_color(entry_id)
		button.add_theme_color_override("font_color", COLOR_TEXT)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_stylebox_override("normal", _panel_style(Color(0.035, 0.055, 0.09, 0.94), Color(entry_color, 0.9)))
		button.add_theme_stylebox_override("hover", _panel_style(Color(entry_color.darkened(0.68), 0.98), entry_color))
		button.add_theme_stylebox_override("pressed", _panel_style(Color(entry_color.darkened(0.58), 1.0), entry_color.lightened(0.18)))
		if not entry_id.begins_with("__"):
			button.disabled = not _action_has_valid_target(entry_id)
		button.pressed.connect(_activate_radial_entry.bind(entry))
		button.mouse_entered.connect(_focus_and_browse_entry.bind(button, entry))
		button.focus_entered.connect(_browse_radial_entry.bind(entry))
		_radial_menu.add_child(button)
	_radial_confirm.visible = false
	_radial_confirm.disabled = true
	_refresh_command_drawer(actor)
	_position_radial_menu()
	if preserve_drawer_focus and _radial_page != "root":
		call_deferred("_focus_first_command_button")
	elif preserve_radial_focus and _radial_page == "root":
		call_deferred("_focus_first_radial_button")


func _refresh_command_drawer(actor: Dictionary) -> void:
	if _command_drawer == null or _command_drawer_list == null:
		return
	if _radial_page == "root" or _radial_targeting or not _lifted_target_id.is_empty():
		_command_drawer.visible = false
		return
	_command_drawer.visible = true
	_command_drawer_title.text = {
		"skill": "УМЕНИЯ",
		"magic": "МАГИЯ",
		"item": "ПРЕДМЕТЫ",
	}.get(_radial_page, "КОМАНДЫ")
	for child in _command_drawer_list.get_children():
		_command_drawer_list.remove_child(child)
		child.queue_free()
	var selection_state := _selection_state()
	for entry in _drawer_entries(actor):
		var entry_id := str(entry.get("id", ""))
		var action := Combat.command_definition(selection_state, entry_id)
		var button := Button.new()
		button.name = "CombatCommand_%s" % entry_id.replace(":", "_")
		button.set_meta("combat_command_id", entry_id)
		button.toggle_mode = true
		button.button_pressed = (
			entry_id == _selected_action
			or (_selected_action.is_empty() and entry_id == _browsed_command_id)
		)
		button.custom_minimum_size = Vector2(0, 64)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.clip_text = true
		button.icon = _command_icon(action)
		button.expand_icon = true
		var availability := _command_availability_copy(entry_id, selection_state)
		button.text = "%s   %s" % [str(entry.get("shortcut", "")), str(entry.get("label", entry_id))]
		if not availability.is_empty():
			button.text += "\n%s" % availability
		button.disabled = not availability.is_empty()
		button.tooltip_text = str(action.get("conditionsRu", availability))
		var entry_color := _radial_entry_color(entry_id)
		button.add_theme_color_override("font_color", COLOR_TEXT)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_disabled_color", Color(COLOR_MUTED, 0.72))
		button.add_theme_stylebox_override("normal", _panel_style(Color(0.04, 0.065, 0.105, 0.98), Color(entry_color, 0.7)))
		button.add_theme_stylebox_override("hover", _panel_style(Color(entry_color.darkened(0.68), 1.0), entry_color))
		button.add_theme_stylebox_override("pressed", _panel_style(Color(entry_color.darkened(0.58), 1.0), entry_color.lightened(0.18)))
		button.add_theme_stylebox_override("disabled", _panel_style(Color(0.035, 0.045, 0.065, 0.92), Color(COLOR_MUTED, 0.32)))
		button.pressed.connect(_select_action.bind(entry_id))
		button.mouse_entered.connect(_focus_and_browse_entry.bind(button, entry))
		button.focus_entered.connect(_browse_radial_entry.bind(entry))
		_command_drawer_list.add_child(button)
	_position_command_drawer()


func _command_availability_copy(action_id: String, selection_state: Dictionary) -> String:
	if _action_has_valid_target(action_id):
		return ""
	var action := Combat.command_definition(selection_state, action_id)
	var actor := Combat.unit_definition(selection_state, Combat.current_unit_id(selection_state))
	var mp_cost := int(action.get("mpCost", 0))
	if mp_cost > int(actor.get("mp", 0)):
		return "Недоступно: нужно %d MP" % mp_cost
	var partner_reason := Combat.duo_partner_unavailable_reason(selection_state, action_id)
	if not partner_reason.is_empty():
		return "Недоступно: %s" % partner_reason
	if Combat.is_item_command(action_id):
		var item_id := Combat.item_id_from_command(action_id)
		if int((selection_state.get("inventory", {}) as Dictionary).get(item_id, 0)) <= 0:
			return "Недоступно: предмет закончился"
	return "Недоступно: нет подходящей цели"


func _lift_finish_menu_active() -> bool:
	return (
		_lift_menu_ready
		and not _lifted_target_id.is_empty()
		and _lift_choice.is_empty()
		and not _canceling_lift
	)


func _lift_finish_entries() -> Array[Dictionary]:
	return [
		{
			"id": "__lift_finish_throw",
			"shortcut": "1",
			"label": "Бросить",
			"help": "Выбрать клетку приземления и завершить действие броском.",
		},
		{
			"id": "__lift_finish_lower",
			"shortcut": "2",
			"label": "Опустить",
			"help": "Вернуть цель на исходную соседнюю клетку и завершить действие.",
		},
		{
			"id": "__lift_finish_hold",
			"shortcut": "3",
			"label": "Удержать\n+ защита",
			"help": "Оставить цель поднятой и завершить ход носителя в Защите.",
		},
	]


func _radial_entries(actor: Dictionary) -> Array[Dictionary]:
	var basic: Array[String] = []
	var skills: Array[String] = []
	var magic: Array[String] = []
	var selection_state := _selection_state()
	var items: Array[String] = []
	if Combat.held_target_id(
		selection_state, Combat.current_unit_id(selection_state)
	).is_empty():
		items = Combat.combat_item_ids(selection_state)
	var defend_id := ""
	for raw_id in Combat.command_ids_for_current_actor(selection_state, false):
		var action_id := str(raw_id)
		var action := Combat.command_definition(selection_state, action_id)
		if str(action.get("effect", "")) == "defend":
			defend_id = action_id
			continue
		match str(action.get("menuGroup", "basic")):
			"skill":
				skills.append(action_id)
			"magic":
				magic.append(action_id)
			_:
				basic.append(action_id)
	var result: Array[Dictionary] = []
	if Combat.held_target_id(selection_state, Combat.current_unit_id(selection_state)).is_empty():
		result.append({"id": "__move", "shortcut": "M", "label": "Движение"})
	var next_number := 1
	for action_id in basic:
		result.append(_radial_action_entry(action_id, str(next_number)))
		next_number += 1
	if not skills.is_empty():
		result.append({"id": "__skills", "shortcut": str(next_number), "label": "Умения"})
		next_number += 1
	if not magic.is_empty():
		result.append({"id": "__magic", "shortcut": str(next_number), "label": "Магия"})
		next_number += 1
	if not items.is_empty():
		result.append({"id": "__items", "shortcut": str(next_number), "label": "Предметы"})
	if not defend_id.is_empty():
		result.append(_radial_action_entry(defend_id, "G"))
	return result


func _drawer_entries(actor: Dictionary) -> Array[Dictionary]:
	var action_ids: Array[String] = []
	if _radial_page == "item":
		action_ids = Combat.combat_item_ids(_selection_state())
	else:
		for raw_id in Combat.command_ids_for_current_actor(_selection_state(), false):
			var action_id := str(raw_id)
			var action := Combat.command_definition(_selection_state(), action_id)
			if str(action.get("menuGroup", "basic")) == _radial_page:
				action_ids.append(action_id)
	var result: Array[Dictionary] = []
	for index in action_ids.size():
		result.append(_radial_action_entry(action_ids[index], str(index + 1)))
	return result


func _radial_action_entry(action_id: String, shortcut: String) -> Dictionary:
	var action := Combat.command_definition(_selection_state(), action_id)
	var mp_cost := int(action.get("mpCost", 0))
	var cost_copy := " · %dMP" % mp_cost if mp_cost > 0 else ""
	if not str(action.get("partnerId", "")).is_empty():
		cost_copy = " · %d+%dMP" % [mp_cost, int(action.get("partnerMpCost", 0))]
	if Combat.is_item_command(action_id):
		cost_copy = " · ×%d" % int((_state.get("inventory", {}) as Dictionary).get(
			Combat.item_id_from_command(action_id), 0
		))
	return {
		"id": action_id,
		"shortcut": shortcut,
		"label": "%s%s" % [
			str(action.get("name", action_id)),
			cost_copy,
		],
	}


func _radial_entry_color(entry_id: String) -> Color:
	match entry_id:
		"__move":
			return COLOR_HERO
		"__skills":
			return COLOR_ACCENT
		"__magic":
			return Color("ad8cff")
		"__items":
			return Color("79d8a3")
		"__back":
			return COLOR_MUTED
		"__lift_finish_throw":
			return COLOR_ACCENT
		"__lift_finish_lower":
			return COLOR_HERO
		"__lift_finish_hold":
			return Color("ad8cff")
		_:
			return _action_color(Combat.command_definition(_selection_state(), entry_id))


func _activate_radial_entry(entry: Dictionary) -> void:
	var entry_id := str(entry.get("id", ""))
	match entry_id:
		"__move":
			_toggle_move_mode()
		"__skills":
			_open_radial_page("skill")
		"__magic":
			_open_radial_page("magic")
		"__items":
			_open_radial_page("item")
		"__back":
			_open_radial_page("root")
		"__lift_finish_throw":
			_choose_lift_throw()
		"__lift_finish_lower":
			_choose_lift_lower()
		"__lift_finish_hold":
			_choose_lift_hold()
		_:
			_select_action(entry_id)


func _open_radial_page(page: String) -> void:
	var was_drawer_open := _radial_page != "root"
	if not _radial_targeting:
		_clear_selected_action_state()
	_browsed_command_id = ""
	_pair_hover_action = ""
	_radial_page = page if page in ["root", "skill", "magic", "item"] else "root"
	_refresh_radial_actions()
	_refresh_ability_info()
	_refresh_field()
	if _radial_page != "root":
		call_deferred("_focus_first_command_button")
	elif was_drawer_open:
		call_deferred("_focus_first_radial_button")


func _activate_radial_number(number: int) -> bool:
	var actor := Combat.unit_definition(_state, Combat.current_unit_id(_state))
	var entries := (
		_lift_finish_entries()
		if _lift_finish_menu_active()
		else (_drawer_entries(actor) if _radial_page != "root" else _radial_entries(actor))
	)
	for entry in entries:
		if str(entry.get("shortcut", "")) == str(number):
			_activate_radial_entry(entry)
			return true
	return false


func _focus_first_radial_button() -> void:
	if _radial_menu == null or not _radial_menu.visible:
		return
	for child in _radial_menu.get_children():
		var button := child as Button
		if (
			button != null
			and button != _radial_confirm
			and not button.is_queued_for_deletion()
			and button.visible
			and not button.disabled
		):
			button.grab_focus()
			return


func _focus_first_command_button() -> void:
	if _command_drawer == null or not _command_drawer.visible or _command_drawer_list == null:
		return
	for child in _command_drawer_list.get_children():
		var button := child as Button
		if button != null and not button.is_queued_for_deletion() and button.visible and not button.disabled:
			button.grab_focus()
			return
	if _command_drawer_close != null and _command_drawer_close.visible:
		_command_drawer_close.grab_focus()


func _focus_radial_command(command_id: String) -> void:
	if _radial_menu == null or not _radial_menu.visible:
		return
	for child in _radial_menu.get_children():
		var button := child as Button
		if (
			button != null
			and not button.is_queued_for_deletion()
			and not button.disabled
			and str(button.get_meta("combat_command_id", "")) == command_id
		):
			button.grab_focus()
			return
	_focus_first_radial_button()


func _focus_drawer_command(command_id: String) -> void:
	if _command_drawer == null or not _command_drawer.visible or _command_drawer_list == null:
		return
	for child in _command_drawer_list.get_children():
		var button := child as Button
		if (
			button != null
			and not button.is_queued_for_deletion()
			and not button.disabled
			and str(button.get_meta("combat_command_id", "")) == command_id
		):
			button.grab_focus()
			return
	_focus_first_command_button()


func _focus_action_list_command(command_id: String) -> void:
	if _action_list == null or not _action_list.visible:
		return
	for child in _action_list.get_children():
		var button := child as Button
		if (
			button != null
			and not button.is_queued_for_deletion()
			and not button.disabled
			and str(button.get_meta("combat_command_id", "")) == command_id
		):
			button.grab_focus()
			return


func _position_radial_menu() -> void:
	if _radial_menu == null or not _radial_menu.visible or _external_3d_world == null:
		return
	var actor_id := Combat.current_unit_id(_state)
	var actor := Combat.unit_definition(_state, actor_id)
	var actor_cell: Vector2i = _pending_cell if _pending_actor_id == actor_id else actor.get("cell", Vector2i.ZERO)
	if not _lifted_target_id.is_empty() and not _locked_lift_plan.is_empty():
		actor_cell = _locked_lift_plan.get("destination", actor_cell)
	var screen_position := _external_3d_world.call("screen_position_for_cell", actor_cell) as Vector2
	if not screen_position.is_finite():
		_radial_menu.visible = false
		return
	var half := _radial_menu.size * 0.5
	var safe_center := Vector2(
		clampf(screen_position.x, half.x, size.x - half.x),
		clampf(screen_position.y, half.y, size.y - half.y),
	)
	_radial_menu.position = safe_center - half
	_position_command_drawer()


func _position_command_drawer() -> void:
	if _command_drawer == null or not _command_drawer.visible or _radial_menu == null:
		return
	var gap := 14.0
	var drawer_size := _command_drawer.size
	if drawer_size.x <= 0.0 or drawer_size.y <= 0.0:
		drawer_size = _command_drawer.custom_minimum_size
	var left_space := _radial_menu.position.x
	var right_space := size.x - (_radial_menu.position.x + _radial_menu.size.x)
	# Keep the chosen side until the opposite one is clearly roomier. Without
	# this small hysteresis a slow camera orbit near screen centre can make the
	# drawer flicker from side to side.
	var side_switch_margin := 120.0
	var place_right := (
		not (left_space > right_space + side_switch_margin)
		if _command_drawer_side == "right"
		else right_space > left_space + side_switch_margin
	)
	_command_drawer_side = "right" if place_right else "left"
	var drawer_x := (
		_radial_menu.position.x + _radial_menu.size.x + gap
		if place_right
		else _radial_menu.position.x - drawer_size.x - gap
	)
	var safe_top := 126.0
	var safe_bottom := maxf(safe_top + drawer_size.y, size.y - 52.0)
	_command_drawer.position = Vector2(
		clampf(drawer_x, 8.0, maxf(8.0, size.x - drawer_size.x - 8.0)),
		clampf(
			_radial_menu.position.y + (_radial_menu.size.y - drawer_size.y) * 0.5,
			safe_top,
			safe_bottom - drawer_size.y
		),
	)


func _refresh_result_overlay() -> void:
	if _result_overlay == null:
		return
	var outcome := Combat.outcome(_state)
	_result_overlay.visible = outcome != "active"
	if not _result_overlay.visible:
		return
	_result_title.text = "ПОБЕДА" if outcome == "victory" else "ПОРАЖЕНИЕ"
	_result_title.modulate = COLOR_ACCENT if outcome == "victory" else COLOR_ENEMY
	var encounter_name := (
		_authored_encounter.display_name if _authored_encounter != null else "Тренировочная встреча"
	)
	_result_body.text = (
		"%s завершена. Нажмите «Продолжить»: результат применится один раз, затем вы вернётесь туда, где начался бой."
		% encounter_name
		if outcome == "victory" and _authored_encounter != null
		else ("%s завершена поражением. Можно повторить бой или вернуться в локацию." % encounter_name
		if _authored_encounter != null
		else "%s завершена. Это лабораторный бой — прогресс мира не изменяется." % encounter_name)
	)
	if _authored_encounter != null:
		var report := CombatResult.build(_authored_encounter, _state, outcome)
		var detail_lines: Array[String] = []
		var defeated: Array = report.get("defeatedEnemyIds", [])
		if not defeated.is_empty():
			detail_lines.append("Побеждено врагов: %d" % defeated.size())
		var xp_reward := int(report.get("xpReward", 0))
		if xp_reward > 0:
			detail_lines.append("Опыт: +%d XP каждому герою" % xp_reward)
			var level_ups: Array[String] = []
			for raw_row in report.get("xpRows", []):
				var row: Dictionary = raw_row
				if int(row.get("levelAfter", 1)) > int(row.get("levelBefore", 1)):
					level_ups.append("%s → ур. %d" % [
						str(row.get("nameRu", row.get("heroId", "?"))),
						int(row.get("levelAfter", 1)),
					])
			if not level_ups.is_empty():
				detail_lines.append("Повышение уровня: %s" % ", ".join(level_ups))
		var reward_parts: Array[String] = []
		for raw_reward in report.get("rewards", []):
			var reward: Dictionary = raw_reward
			reward_parts.append("%s ×%d" % [reward.get("nameRu", reward.get("itemId", "?")), reward.get("count", 1)])
		if not reward_parts.is_empty():
			detail_lines.append("Награда после возврата: %s" % ", ".join(reward_parts))
		if not detail_lines.is_empty():
			_result_body.text += "\n\n" + "\n".join(detail_lines)
	_result_continue.visible = outcome == "victory" and _authored_encounter != null
	_result_return.visible = outcome == "defeat" and _authored_encounter != null
	_result_retry.visible = not _transition_in_progress
	_set_result_buttons_disabled(_transition_in_progress)
	if _result_continue.visible and not _transition_in_progress:
		_result_continue.grab_focus()
	elif _result_retry.visible and not _transition_in_progress:
		_result_retry.grab_focus()

func _refresh_log() -> void:
	var log: Array = _state.get("log", [])
	var start := maxi(0, log.size() - 7)
	var lines: Array[String] = []
	for index in range(start, log.size()):
		lines.append("• %s" % str(log[index]))
	var console_text := ""
	if not _console_messages.is_empty():
		console_text = "\n[color=#65cfe1]КОМАНДЫ[/color]\n%s" % "\n".join(_console_messages)
	_log_label.text = "[color=#91a0b8]ЖУРНАЛ БОЯ[/color]\n%s%s" % ["\n".join(lines), console_text]
	_log_label.scroll_to_line(maxi(0, lines.size() + _console_messages.size()))


func _select_action(action_id: String) -> void:
	if _canceling_lift or not _lifted_target_id.is_empty():
		return
	_selection_origin_page = _radial_page
	_selection_origin_action = action_id
	_browsed_command_id = action_id
	_selected_action = action_id
	_selected_target_cell = Combat.INVALID_CELL
	_selected_secondary_cell = Combat.INVALID_CELL
	_lifted_target_id = ""
	_lift_choice = ""
	_lift_menu_ready = false
	_hover_cell = Combat.INVALID_CELL
	var action := Combat.command_definition(_selection_state(), action_id)
	_selected_target = (
		Combat.current_unit_id(_state)
		if str(action.get("target", "")) == "self"
		else ""
	)
	if not _action_has_valid_target(action_id):
		_clear_selected_action_state()
		_refresh()
		return
	_radial_targeting = str(action.get("target", "")) != "self"
	_refresh()
	if (
		str(action.get("target", "")) == "self"
		and bool(_current_preview.get("ok", false))
	):
		_confirm_action()


func _select_target(unit_id: String) -> void:
	if _canceling_lift or not _lifted_target_id.is_empty():
		return
	if unit_id not in _action_target_ids(_selected_action):
		return
	_selected_target = unit_id
	if str(Combat.command_definition(_selection_state(), _selected_action).get("effect", "")) == "lift_throw":
		_selected_secondary_cell = Combat.INVALID_CELL
		_lift_choice = ""
		_lift_menu_ready = false
		_rebuild_action_plan()
		if bool(_action_plan.get("fallbackDefend", false)):
			_confirm_action()
			return
		if not bool(_action_plan.get("ok", false)):
			return
		_lifted_target_id = unit_id
		_radial_targeting = false
		_refresh()
		_locked_lift_plan = _action_plan.duplicate(true)
		if _external_3d_world != null:
			_external_3d_world.call("begin_lift_presentation", _locked_lift_plan)
		else:
			_lift_menu_ready = true
			_refresh_radial_actions()
			call_deferred("_focus_first_radial_button")
		return
	_radial_targeting = false
	_refresh()
	if bool(_current_preview.get("ok", false)):
		_confirm_action()


func _confirm_action() -> void:
	if _lift_input_busy():
		return
	if _external_3d_world != null:
		_external_3d_world.call("finish_lift_presentation")
	if not bool(_current_preview.get("ok", false)) or Combat.outcome(_state) != "active":
		return
	_queue_world_animation(_state, _current_preview)
	_state = Combat.commit(_state, _current_preview)
	_clear_selected_action_state()
	_browsed_command_id = ""
	_selection_origin_page = "root"
	_selection_origin_action = ""
	_pending_actor_id = ""
	_manual_move_selected = false
	_pending_cell = Vector2i(-1, -1)
	_move_mode = false
	_radial_page = "root"
	_advance_enemy_turns()
	_refresh()


func _clear_selected_action_state() -> void:
	_locked_lift_plan = {}
	_action_plan = {}
	_hover_cell = Combat.INVALID_CELL
	_selected_action = ""
	_selected_target = ""
	_selected_target_cell = Combat.INVALID_CELL
	_selected_secondary_cell = Combat.INVALID_CELL
	_lifted_target_id = ""
	_lift_choice = ""
	_lift_menu_ready = false
	_radial_targeting = false


func _selection_state() -> Dictionary:
	if not _is_grid_mode():
		return _state
	var staged := Grid.stage_move(_state, _pending_cell)
	return _state if staged.is_empty() else staged


func _action_target_ids(action_id: String) -> Array[String]:
	if action_id.is_empty():
		return []
	if _action_target_cache.has(action_id):
		return (_action_target_cache[action_id] as Array[String]).duplicate()
	var result: Array[String]
	if _is_grid_mode():
		result = Grid.approach_target_ids(_state, action_id, _pending_cell)
	else:
		result = Combat.valid_target_ids(_state, action_id)
	_action_target_cache[action_id] = result
	return result.duplicate()


func _action_target_cells(action_id: String) -> Array[Vector2i]:
	if action_id.is_empty():
		return []
	if _action_target_cell_cache.has(action_id):
		return (_action_target_cell_cache[action_id] as Array[Vector2i]).duplicate()
	var result: Array[Vector2i]
	if _is_grid_mode() and _manual_move_selected:
		result = Combat.valid_target_cells(_selection_state(), action_id)
	elif _is_grid_mode():
		result = Grid.approach_target_cells(_state, action_id, _pending_cell)
	else:
		result = Combat.valid_target_cells(_selection_state(), action_id)
	_action_target_cell_cache[action_id] = result
	return result.duplicate()


func _action_has_valid_target(action_id: String) -> bool:
	var action := Combat.command_definition(_selection_state(), action_id)
	if str(action.get("target", "")) == "cell":
		return not _action_target_cells(action_id).is_empty()
	return not _action_target_ids(action_id).is_empty()


func _lift_input_busy() -> bool:
	return _canceling_lift or (_external_3d_world != null and bool(_external_3d_world.call("lift_presentation_busy")))


func _on_lift_presentation_finished() -> void:
	if _canceling_lift or _lifted_target_id.is_empty() or _locked_lift_plan.is_empty():
		return
	_lift_menu_ready = true
	_refresh_radial_actions()
	call_deferred("_focus_first_radial_button")


func _choose_lift_throw() -> void:
	if _selected_target.is_empty() or _lifted_target_id.is_empty() or _lift_input_busy():
		return
	_lift_choice = "throw"
	_lift_menu_ready = false
	_radial_targeting = true
	_refresh()


func _choose_lift_hold() -> void:
	if _selected_target.is_empty() or _lifted_target_id.is_empty() or _lift_input_busy():
		return
	_lift_choice = "hold"
	_lift_menu_ready = false
	_rebuild_action_plan()
	_confirm_action()


func _choose_lift_lower() -> void:
	if _selected_target.is_empty() or _lifted_target_id.is_empty() or _lift_input_busy():
		return
	_lift_choice = "lower"
	_lift_menu_ready = false
	_rebuild_action_plan()
	_confirm_action()


func _combat_item_definitions(inventory: Dictionary) -> Dictionary:
	var result := {}
	for raw_id in inventory:
		var item_id := str(raw_id)
		var definition := ItemCatalog.native_definition(item_id)
		if not definition.is_empty():
			result[item_id] = definition
	return result


func _select_encounter_mode(index: int) -> void:
	var selected := str(_mode_picker.get_item_metadata(index))
	if selected.begins_with("encounter:"):
		_authored_encounter = EncounterCatalog.definition(selected.trim_prefix("encounter:"))
		_encounter_mode = "encounter"
	else:
		_authored_encounter = null
		_encounter_mode = selected
	_reset_lab()


func _select_field_view_mode(index: int) -> void:
	_field_view_mode = str(_view_picker.get_item_metadata(index))
	_refresh()


func _show_camera_overview() -> void:
	if _external_3d_world != null and _external_3d_world.has_method("show_battlefield_overview"):
		_external_3d_world.call("show_battlefield_overview", true)


func _on_camera_menu_pressed(item_id: int) -> void:
	if _external_3d_world == null:
		return
	var settings := _external_3d_world.call("camera_control_snapshot") as Dictionary
	match item_id:
		CAMERA_MENU_OVERVIEW:
			_show_camera_overview()
		CAMERA_MENU_INVERT_VERTICAL:
			_external_3d_world.call(
				"set_camera_invert_vertical", not bool(settings.get("invertVertical", false))
			)
		CAMERA_MENU_STEP_ROTATION:
			_external_3d_world.call(
				"set_camera_axis_lock", not bool(settings.get("axisLock", false))
			)
		CAMERA_MENU_LOCK_HORIZONTAL:
			_external_3d_world.call(
				"set_camera_horizontal_lock", not bool(settings.get("horizontalLock", false))
			)
		CAMERA_MENU_LOCK_VERTICAL:
			_external_3d_world.call(
				"set_camera_vertical_lock", not bool(settings.get("verticalLock", false))
			)
	_sync_camera_controls()


func _sync_camera_controls() -> void:
	if _camera_menu == null:
		return
	var available := (
		_external_3d_world != null and _is_grid_mode() and _field_view_mode == "3d"
	)
	_camera_menu.disabled = not available
	if not available or not _external_3d_world.has_method("camera_control_snapshot"):
		return
	var settings := _external_3d_world.call("camera_control_snapshot") as Dictionary
	var popup := _camera_menu.get_popup()
	popup.set_item_checked(
		popup.get_item_index(CAMERA_MENU_INVERT_VERTICAL),
		bool(settings.get("invertVertical", false)),
	)
	popup.set_item_checked(
		popup.get_item_index(CAMERA_MENU_STEP_ROTATION),
		bool(settings.get("axisLock", false)),
	)
	popup.set_item_checked(
		popup.get_item_index(CAMERA_MENU_LOCK_HORIZONTAL),
		bool(settings.get("horizontalLock", false)),
	)
	popup.set_item_checked(
		popup.get_item_index(CAMERA_MENU_LOCK_VERTICAL),
		bool(settings.get("verticalLock", false)),
	)


func _refresh_mode_copy() -> void:
	var authored := _authored_encounter != null
	_mode_picker.visible = not authored
	_view_picker.visible = not authored and _is_grid_mode()
	_outcome_label.visible = not authored
	_reset_button.visible = not authored
	if _authored_encounter != null:
		_title_label.text = "EMBER · %s" % _authored_encounter.display_name.to_upper()
		_subtitle_label.text = _authored_encounter.description
		_field_heading.text = "ПОЛЕ · %s" % (
			_authored_encounter.battlefield.display_name
			if _authored_encounter.battlefield != null
			else "не назначено"
		)
		_source_note.text = _authored_encounter.intro_text
		_footer.text = "M движение · цифры: команды/категории · G защита · Esc назад/пауза"
		_scope_label.text = "Авторская встреча. После подтверждения результата исход и награда применяются один раз, затем загружается исходная локация."
		return
	if _encounter_mode == "terrain":
		_title_label.text = "EMBER COMBAT LAB · E3"
		_subtitle_label.text = "Хранитель оттепели · высота и атомарное изменение поверхности"
		_field_heading.text = "ИЗМЕНЯЕМОЕ ПОЛЕ · Frozen/Wet прогнозируются до выбора цели"
		_source_note.text = "Сначала Орик замораживает связанные мокрые панели; затем Сена может вернуть им Wet огнём. Высота уже ограничивает перемещение и толчок."
		_footer.text = "ПКМ ракурс · СКМ сдвиг · M движение · цифры: круг/категория · Esc назад"
		_scope_label.text = "Лабораторный режим: прогресс мира не сохраняется. Здесь проверяются поверхность и тактические решения."
		return
	if _encounter_mode == "vertical":
		_title_label.text = "EMBER COMBAT LAB · E4"
		_subtitle_label.text = "Вертикальная кузница · 10×8, полный риск-тест высоты"
		_field_heading.text = "ПОЛЕ 10×8 · Jump, LOS, падение, толчок и бросок"
		_source_note.text = "Зелёные клетки учитывают Jump. Выберите Подъём и бросок: сначала бойца, затем янтарную клетку приземления."
		_footer.text = "ПКМ ракурс · F фокус · M движение · цифры: Умения/Магия/Предметы · Esc назад"
		_scope_label.text = "Лаборатория этапа 1: save и прогресс мира не меняются. Все результаты проходят общий preview/commit."
		return
	if _encounter_mode == "stress":
		_title_label.text = "EMBER COMBAT LAB · E5"
		_subtitle_label.text = "Сердце кузницы · 16×12, большой вертикальный профиль"
		_field_heading.text = "ПОЛЕ 16×12 · нагрузка pathfinding, preview и AI"
		_source_note.text = "То же dense Battlefield: одна высота на колонку, без второго resolver и без stacked-этажей."
		_footer.text = "ПКМ ракурс · F фокус · M движение · цифры: Умения/Магия/Предметы · Esc назад"
		_scope_label.text = "Нагрузочная лаборатория этапа 1. Она проверяет масштаб, но не является финальной ареной босса."
		return
	if _encounter_mode == "grid":
		_title_label.text = "EMBER COMBAT LAB · E2"
		_subtitle_label.text = "Цветная переправа · 7×5, предпросмотр движения + действия"
		_field_heading.text = "ПОЛЕ 7×5 · M: выбрать клетку, затем действие и цель"
		_source_note.text = "Disgaea: связанные цветные панели несут общее правило  •  синие: Wet/проводимость  •  янтарные + фокус: огонь +2"
		_footer.text = "ПКМ вращать · СКМ двигать · M движение · цифры: круг/категория · G защита · Esc назад/пауза"
		_scope_label.text = "Лабораторный режим: прогресс мира не сохраняется. Здесь проверяются сетка, движение и действия."
		return
	_title_label.text = "EMBER COMBAT LAB · E1"
	_subtitle_label.text = "Мокрый проводник · области без сетки"
	_field_heading.text = "ПОЗИЦИОННЫЕ ОБЛАСТИ · кликните по доступной цели"
	_source_note.text = "Trails: видим следующий ход  •  Magicka: состояние + новая стихия  •  область несёт читаемое правило"
	_footer.text = "1–4: умения · G: защита · клик по бойцу сразу выполняет действие · Esc: пауза"
	_scope_label.text = "Лабораторный режим: прогресс мира не сохраняется. Здесь проверяются области и стихийные реакции."


func _toggle_move_mode() -> void:
	if not _lifted_target_id.is_empty() or _canceling_lift:
		return
	if not _is_grid_mode() or Combat.outcome(_state) != "active":
		return
	var actor := Combat.unit_definition(_state, Combat.current_unit_id(_state))
	if str(actor.get("team", "")) != "hero":
		return
	if not Combat.held_target_id(_state, Combat.current_unit_id(_state)).is_empty():
		return
	if _move_mode:
		_cancel_radial_targeting()
		return
	_clear_selected_action_state()
	_selection_origin_page = "root"
	_selection_origin_action = "__move"
	_browsed_command_id = "__move"
	_move_mode = true
	_radial_targeting = true
	_lifted_target_id = ""
	_refresh()


func _cancel_pending_move() -> void:
	if not _is_grid_mode():
		return
	var actor_id := Combat.current_unit_id(_state)
	_pending_actor_id = actor_id
	_manual_move_selected = false
	_pending_cell = Combat.unit_definition(_state, actor_id).get("cell", Vector2i.ZERO)
	_move_mode = false
	_radial_targeting = false
	_refresh()


func _on_grid_cell_chosen(cell: Vector2i, unit_id: String) -> void:
	if _canceling_lift or not _radial_targeting:
		return
	if _move_mode:
		if cell not in Grid.reachable_cells(_state, Combat.current_unit_id(_state)) or Grid.is_focus_cell(_state, cell):
			return
		_manual_move_selected = true
		_pending_cell = cell
		_move_mode = false
		_radial_targeting = false
		_browsed_command_id = ""
		_selection_origin_page = "root"
		_selection_origin_action = ""
		var valid_targets := _action_target_ids(_selected_action)
		if _selected_target not in valid_targets:
			_selected_target = valid_targets[0] if not valid_targets.is_empty() else ""
		_refresh()
		call_deferred("_focus_first_radial_button")
		return
	if (
		str(Combat.command_definition(_selection_state(), _selected_action).get("target", "")) == "cell"
		and cell in _action_target_cells(_selected_action)
	):
		_selected_target = ""
		_selected_target_cell = cell
		_radial_targeting = false
		_refresh()
		if bool(_current_preview.get("ok", false)):
			_confirm_action()
		return
	if (
		str(Combat.command_definition(_selection_state(), _selected_action).get("effect", "")) == "lift_throw"
		and _lift_choice == "throw"
		and not _selected_target.is_empty()
		and cell in Grid.approach_secondary_cells(
			_state, _selected_action, _selected_target, _pending_cell
		)
	):
		_selected_secondary_cell = cell
		_radial_targeting = false
		_refresh()
		if bool(_current_preview.get("ok", false)):
			_confirm_action()
		return
	var occupant := Grid.action_occupant_id(_selection_state(), _selected_action, cell)
	if not occupant.is_empty():
		_select_target(occupant)


func _cancel_radial_targeting() -> void:
	if _canceling_lift:
		return
	if not _radial_targeting and _lifted_target_id.is_empty():
		return
	if (
		_radial_targeting
		and not _lifted_target_id.is_empty()
		and _lift_choice == "throw"
	):
		_lift_choice = ""
		_selected_secondary_cell = Combat.INVALID_CELL
		_hover_cell = Combat.INVALID_CELL
		_radial_targeting = false
		_lift_menu_ready = true
		_refresh()
		call_deferred("_focus_first_radial_button")
		return
	if not _lifted_target_id.is_empty() and _external_3d_world != null:
		_canceling_lift = true
		await _external_3d_world.cancel_lift_presentation()
		_canceling_lift = false
	var restore_page := _selection_origin_page
	var restore_action := _selection_origin_action
	_move_mode = false
	_clear_selected_action_state()
	_browsed_command_id = restore_action
	_radial_page = restore_page if restore_page in ["root", "skill", "magic", "item"] else "root"
	_refresh()
	if not _is_grid_mode() or _field_view_mode != "3d":
		call_deferred("_focus_action_list_command", restore_action)
	elif _radial_page == "root":
		call_deferred("_focus_radial_command", restore_action)
	else:
		call_deferred("_focus_drawer_command", restore_action)


func _advance_enemy_turns() -> void:
	for _safety in 12:
		if Combat.outcome(_state) != "active":
			return
		var actor := Combat.unit_definition(_state, Combat.current_unit_id(_state))
		if str(actor.get("team", "")) != "enemy":
			return
		var command := Grid.enemy_command(_state) if _is_grid_mode() else Combat.enemy_command(_state)
		if not bool(command.get("ok", false)):
			return
		_queue_world_animation(_state, command)
		_state = Combat.commit(_state, command)


func _queue_world_animation(before_state: Dictionary, resolved: Dictionary) -> void:
	if (
		_external_3d_world != null
		and _is_grid_mode()
		and _field_view_mode == "3d"
		and _external_3d_world.has_method("queue_action_animation")
	):
		_external_3d_world.call("queue_action_animation", before_state, resolved)


func _is_grid_mode() -> bool:
	return _encounter_mode in ["grid", "terrain", "vertical", "stress", "encounter"]


func _field_for_mode() -> EmberBattlefieldResource:
	match _encounter_mode:
		"terrain":
			return Grid.DEFAULT_E3_FIELD
		"vertical":
			return Grid.VERTICAL_10X8_FIELD
		"stress":
			return Grid.STRESS_16X12_FIELD
		_:
			return Grid.DEFAULT_E2_FIELD


func _return_from_encounter() -> void:
	if _authored_encounter == null or _transition_in_progress:
		return
	var outcome := Combat.outcome(_state)
	if outcome == "active":
		return
	get_tree().paused = false
	_transition_in_progress = true
	_set_result_buttons_disabled(true)
	await _fade_out()
	var progress := get_node_or_null("/root/EmberExploreProgress") as EmberExploreState
	var error := EmberCombatTransition.finish(get_tree(), outcome, progress, _state)
	if error != OK:
		_transition_in_progress = false
		_outcome_label.text = "Не удалось вернуться в исходную локацию"
		_result_body.text = "Возврат не выполнен (код %d). Результат не будет выдан повторно; проверьте исходную сцену." % error
		_set_result_buttons_disabled(false)
		_fade_in()


func _retry_encounter() -> void:
	if _transition_in_progress:
		return
	_reset_lab()


func _open_pause_menu() -> void:
	if _pause_overlay == null or _pause_overlay.visible or _transition_in_progress:
		return
	_pause_overlay.visible = true
	get_tree().paused = true
	_pause_resume.call_deferred("grab_focus")


func _close_pause_menu() -> void:
	if _pause_overlay == null:
		return
	_pause_overlay.visible = false
	get_tree().paused = false


func _restart_from_pause() -> void:
	_close_pause_menu()
	_reset_lab()


func _quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()


func _push_console_message(message: String) -> void:
	_console_messages.append(message)
	if _console_messages.size() > 16:
		_console_messages.pop_front()


func _console_target_ids(selector: String) -> Array[String]:
	var normalized := selector.strip_edges().to_lower()
	var units := _state.get("units", {}) as Dictionary
	var result: Array[String] = []
	if units.has(normalized):
		result.append(normalized)
		return result
	var wanted_team := ""
	if normalized in ["heroes", "hero", "allies", "герои", "союзники"]:
		wanted_team = "hero"
	elif normalized in ["enemies", "enemy", "враги"]:
		wanted_team = "enemy"
	elif normalized not in ["all", "все"]:
		return result
	for raw_id in units:
		var unit_id := str(raw_id)
		var unit := units[unit_id] as Dictionary
		if wanted_team.is_empty() or str(unit.get("team", "")) == wanted_team:
			result.append(unit_id)
	return result


func _console_set_hp(selector: String, amount: int, add: bool) -> int:
	var ids := _console_target_ids(selector)
	var units := _state.get("units", {}) as Dictionary
	for unit_id in ids:
		var unit := units[unit_id] as Dictionary
		var next_hp := int(unit.get("hp", 0)) + amount if add else amount
		unit["hp"] = clampi(next_hp, 0, int(unit.get("maxHp", next_hp)))
		units[unit_id] = unit
	_state["units"] = units
	return ids.size()


func _console_add_status(selector: String, status_id: String, duration: int) -> int:
	var ids := _console_target_ids(selector)
	var units := _state.get("units", {}) as Dictionary
	for unit_id in ids:
		var unit := units[unit_id] as Dictionary
		var statuses := unit.get("statuses", {}).duplicate(true) as Dictionary
		statuses[status_id] = maxi(1, duration)
		unit["statuses"] = statuses
		units[unit_id] = unit
	_state["units"] = units
	return ids.size()


func _finish_console_mutation(message: String) -> void:
	_clear_selected_action_state()
	_browsed_command_id = ""
	_selection_origin_page = "root"
	_selection_origin_action = ""
	_pending_actor_id = ""
	_manual_move_selected = false
	_pending_cell = Vector2i(-1, -1)
	_move_mode = false
	_push_console_message(message)
	_refresh()


func _submit_console_command(raw_command: String) -> void:
	var command := raw_command.strip_edges()
	if _console_input != null:
		_console_input.clear()
	if command.is_empty():
		return
	var parts := command.split(" ", false)
	var verb := str(parts[0]).to_lower()
	_push_console_message("> %s" % command)
	if verb in ["help", "помощь"]:
		_push_console_message("help · units · kill <id|heroes|enemies> · heal <цель> [HP]")
		_push_console_message("add hp <цель> <HP> · add status <цель> <status> [ходы]")
		_push_console_message("victory · defeat · turn <id> · reset · clear")
		_refresh_log()
		return
	if verb in ["clear", "очистить"]:
		_console_messages.clear()
		_refresh_log()
		return
	if verb in ["reset", "сброс"]:
		_reset_lab()
		_push_console_message("Бой восстановлен из исходных данных.")
		_refresh_log()
		return
	if verb in ["units", "бойцы"]:
		var rows: Array[String] = []
		for raw_id in (_state.get("units", {}) as Dictionary):
			var unit_id := str(raw_id)
			var unit := Combat.unit_definition(_state, unit_id)
			rows.append("%s=%s %d/%d" % [unit_id, str(unit.get("name", unit_id)), int(unit.get("hp", 0)), int(unit.get("maxHp", 0))])
		_push_console_message(" · ".join(rows))
		_refresh_log()
		return
	if verb in ["victory", "победа"]:
		var victory_count := _console_set_hp("enemies", 0, false)
		_finish_console_mutation("Победа: выведено из боя врагов — %d." % victory_count)
		return
	if verb in ["defeat", "поражение"]:
		var defeat_count := _console_set_hp("heroes", 0, false)
		_finish_console_mutation("Поражение: выведено из боя героев — %d." % defeat_count)
		return
	if verb in ["kill", "убить"]:
		var kill_selector := str(parts[1]) if parts.size() > 1 else "enemies"
		var kill_count := _console_set_hp(kill_selector, 0, false)
		if kill_count == 0:
			_push_console_message("Цель не найдена: %s" % kill_selector)
			_refresh_log()
		else:
			_finish_console_mutation("Выведено из боя: %d." % kill_count)
		return
	if verb in ["heal", "лечить"]:
		var heal_selector := str(parts[1]) if parts.size() > 1 else "heroes"
		var heal_ids := _console_target_ids(heal_selector)
		if heal_ids.is_empty():
			_push_console_message("Цель не найдена: %s" % heal_selector)
			_refresh_log()
			return
		if parts.size() > 2 and str(parts[2]).is_valid_int():
			_console_set_hp(heal_selector, int(parts[2]), true)
		else:
			var units := _state.get("units", {}) as Dictionary
			for unit_id in heal_ids:
				var unit := units[unit_id] as Dictionary
				unit["hp"] = int(unit.get("maxHp", 1))
				units[unit_id] = unit
			_state["units"] = units
		_finish_console_mutation("Восстановлено бойцов: %d." % heal_ids.size())
		return
	if verb in ["add", "добавить"] and parts.size() >= 4:
		var kind := str(parts[1]).to_lower()
		var selector := str(parts[2])
		if kind == "hp" and str(parts[3]).is_valid_int():
			var hp_count := _console_set_hp(selector, int(parts[3]), true)
			if hp_count > 0:
				_finish_console_mutation("HP изменено у бойцов: %d." % hp_count)
			else:
				_push_console_message("Цель не найдена: %s" % selector)
				_refresh_log()
			return
		if kind == "status":
			var duration := int(parts[4]) if parts.size() > 4 and str(parts[4]).is_valid_int() else 2
			var status_count := _console_add_status(selector, str(parts[3]).to_lower(), duration)
			if status_count > 0:
				_finish_console_mutation("Статус добавлен бойцам: %d." % status_count)
			else:
				_push_console_message("Цель не найдена: %s" % selector)
				_refresh_log()
			return
	if verb == "turn" and parts.size() > 1:
		var turn_ids := _console_target_ids(str(parts[1]))
		if turn_ids.size() == 1 and int(Combat.unit_definition(_state, turn_ids[0]).get("hp", 0)) > 0:
			var units := _state.get("units", {}) as Dictionary
			var unit := units[turn_ids[0]] as Dictionary
			unit["nextAt"] = -1.0
			units[turn_ids[0]] = unit
			_state["units"] = units
			_finish_console_mutation("Следующий ход: %s." % turn_ids[0])
			return
	_push_console_message("Неизвестная команда или аргументы. Введите help.")
	_refresh_log()


func _set_result_buttons_disabled(disabled: bool) -> void:
	_result_continue.disabled = disabled
	_result_retry.disabled = disabled
	_result_return.disabled = disabled


func _fade_in() -> void:
	if _fade_overlay == null:
		return
	_fade_overlay.visible = true
	_fade_overlay.color.a = 1.0
	var tween := create_tween()
	tween.tween_property(_fade_overlay, "color:a", 0.0, 0.22)
	await tween.finished
	_fade_overlay.visible = false


func _fade_out() -> void:
	if _fade_overlay == null:
		return
	_fade_overlay.visible = true
	_fade_overlay.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(_fade_overlay, "color:a", 1.0, 0.22)
	await tween.finished


func _select_mode_metadata(value: String) -> void:
	for index in _mode_picker.item_count:
		if str(_mode_picker.get_item_metadata(index)) == value:
			_mode_picker.select(index)
			return


func _unhandled_input(event: InputEvent) -> void:
	var cancel_requested: bool = event.is_action_pressed("ui_cancel") or (
		event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE
	)
	if cancel_requested:
		if _pause_overlay != null and _pause_overlay.visible:
			_close_pause_menu()
		elif _console_input != null and get_viewport().gui_get_focus_owner() == _console_input:
			_console_input.release_focus()
		elif Combat.outcome(_state) == "active" and (
			_radial_targeting or not _lifted_target_id.is_empty()
		):
			_cancel_radial_targeting()
		elif Combat.outcome(_state) == "active" and _radial_page != "root":
			_open_radial_page("root")
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if _radial_targeting and not _canceling_lift:
		var direction := Vector2i.ZERO
		if event.is_action_pressed("ui_left"):
			direction = Vector2i.LEFT
		elif event.is_action_pressed("ui_right"):
			direction = Vector2i.RIGHT
		elif event.is_action_pressed("ui_up"):
			direction = Vector2i.UP
		elif event.is_action_pressed("ui_down"):
			direction = Vector2i.DOWN
		if direction != Vector2i.ZERO:
			var cursor := _hover_cell if Grid.is_inside(_state, _hover_cell) else (Combat.unit_definition(_state, Combat.current_unit_id(_state)).get("cell", Vector2i.ZERO) as Vector2i)
			if Grid.is_inside(_state, cursor + direction):
				_on_grid_cell_hovered(cursor + direction)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept") and Grid.is_inside(_state, _hover_cell):
			_on_grid_cell_chosen(_hover_cell, Grid.action_occupant_id(_selection_state(), _selected_action, _hover_cell))
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _pause_overlay != null and _pause_overlay.visible:
		return
	if _console_input != null and get_viewport().gui_get_focus_owner() == _console_input:
		return
	if (
		_console_input != null
		and (event.keycode == KEY_QUOTELEFT or event.physical_keycode == KEY_QUOTELEFT or event.unicode == 96)
	):
		_console_input.grab_focus()
		get_viewport().set_input_as_handled()
		return
	if (
		event.keycode == KEY_F
		and _external_3d_world != null
		and _is_grid_mode()
		and _field_view_mode == "3d"
		and _external_3d_world.has_method("focus_active_unit")
	):
		_external_3d_world.call("focus_active_unit", true)
		get_viewport().set_input_as_handled()
		return
	var outcome := Combat.outcome(_state)
	if outcome != "active":
		if event.keycode == KEY_R:
			_retry_encounter()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ENTER and _authored_encounter != null:
			_return_from_encounter()
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_R:
		_reset_lab()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_M:
		_toggle_move_mode()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_G:
		var actor := Combat.unit_definition(_state, Combat.current_unit_id(_state))
		var guard_id := (
			Combat.HELD_GUARD_COMMAND
			if not Combat.held_target_id(_state, Combat.current_unit_id(_state)).is_empty()
			else "defend"
		)
		if guard_id in Combat.command_ids_for_current_actor(_state, false):
			_select_action(guard_id)
			get_viewport().set_input_as_handled()
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var handled := false
		if _is_grid_mode() and _field_view_mode == "3d":
			handled = _activate_radial_number(int(event.keycode - KEY_0))
		else:
			var index := int(event.keycode - KEY_1)
			var actions := Combat.command_ids_for_current_actor(_state)
			if index < actions.size():
				_select_action(str(actions[index]))
				handled = true
		if handled:
			get_viewport().set_input_as_handled()


func _status_text(unit: Dictionary) -> String:
	var names: Array[String] = []
	for raw_id in unit.get("statuses", {}):
		var duration := int((unit.get("statuses", {}) as Dictionary)[raw_id])
		if duration > 0:
			names.append("%s %d" % [Combat.status_name(str(raw_id)), duration])
	return ", ".join(names)


func _element_color(element: String) -> Color:
	return {
		"water": Color("6ed8ff"),
		"cold": Color("a9eeff"),
		"lightning": Color("ffe56b"),
		"fire": Color("ff9a66"),
		"air": Color("a6e8bc"),
		"earth": Color("b9935a"),
		"support": Color("c3b6ff"),
		"duo": Color("f7a6de"),
	}.get(element, COLOR_TEXT)


func _action_color(action: Dictionary) -> Color:
	return action.get("uiColor", _element_color(str(action.get("element", ""))))


func _command_icon(command: Dictionary) -> Texture2D:
	var icon := command.get("icon", null) as Texture2D
	if icon != null:
		return icon
	var icon_id := str(command.get("iconId", ""))
	return ItemVisuals.icon_texture(icon_id, 36) if not icon_id.is_empty() else null


func _unit_color(unit: Dictionary) -> Color:
	return unit.get(
		"battleColor",
		COLOR_HERO if str(unit.get("team", "")) == "hero" else COLOR_ENEMY,
	)


func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 8.0
	style.content_margin_top = 8.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 8.0
	return style


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
