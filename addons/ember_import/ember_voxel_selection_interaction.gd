@tool
extends Control
## Canvas-only interaction overlay. SelectionPanel and SculptActions remain owners.
const Gesture = preload("res://addons/ember_import/ember_voxel_selection_gesture.gd")
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const SurfaceMarquee = preload("res://addons/ember_import/ember_voxel_surface_marquee.gd")
const SelectionPanel = preload("res://addons/ember_import/ember_voxel_selection_panel.gd")
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
const Pattern = preload("res://addons/ember_import/ember_voxel_pattern.gd")
var _stamp: Resource
var _stamp_controls: VBoxContainer
var _stamp_mode: OptionButton
var _stamp_mirror: OptionButton
var _stamp_anchor: OptionButton
var _stamp_application: OptionButton
var _stamp_spacing: SpinBox
var _stamp_scatter_spread: SpinBox
var _stamp_scatter_random_turns: CheckBox
var _stamp_scatter_variant: Button
var _stamp_scatter_conform: CheckBox
var _stamp_scatter_bend: SpinBox
var _stamp_depth: SpinBox
var _stamp_spacing_row: HBoxContainer
var _stamp_scatter_row: HBoxContainer
var _stamp_scatter_options: HBoxContainer
var _stamp_scatter_shape_status: Label
var _stamp_scatter_conform_row: HBoxContainer
var _stamp_depth_row: HBoxContainer
var _stamp_part := 0
var _surface_marquee: RefCounted
var _surface_bounds := {}
var _surface_footprint := {}
var _surface_stage := 0 # 0 none, 1 footprint drag, 2 depth adjustment.
var _surface_depth_origin := Vector2.ZERO
var _depth := 1
var _gesture_mode := 3
var workspace: Control
var dragging := false
var transforming := false
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _operation := 0
var _job: RefCounted
var _job_rect := Rect2()
var _finish := false
var _prior := {}
var _ghost: MultiMeshInstance3D
var _hover: MeshInstance3D
var _controls: VBoxContainer
var _numbers: Array[SpinBox] = []
var _axis: OptionButton
var _turns: OptionButton
var _axis_buttons: Array[Button] = []
var _turn_buttons: Array[Button] = []
var _stamp_mode_buttons: Array[Button] = []
var _stamp_mirror_buttons: Array[Button] = []
var _stamp_anchor_buttons: Array[Button] = []
var _stamp_application_buttons: Array[Button] = []
var _copy: CheckBox
var _apply: Button
var _hint: Label
var _indices := PackedInt32Array()
var _plan := {}
var _pending := false
var _offset := Vector3i.ZERO
var _arrow_axis := -1
var _arrow_start := Vector2.ZERO
var _arrow_value := 0
var _center := Vector3.ZERO
var _snapshot := {}
var _syncing := false
var _source: EmberVoxelModelResource
var _committing := false
var _stamp_knots: Array[Vector3i] = []
var _stamp_line_start := Vector3i.ZERO
var _stamp_line_started := false
var _stamp_drawing := false
var _stamp_draft_ready := false
var _stamp_position_picked := false
var _stamp_normal := Vector3i.UP
var _stamp_scatter_seed := 1
var _stamp_variant_count := 1
var _stamp_draft_visible_count := -1
var _stamp_settings_id := ""
var _stamp_session_settings: Dictionary = {}
var _ready_rect := Rect2(-9999,-9999,0,0)
var _selection_normal := Vector3i.UP
var _region := Rect2i()
var _height := -1
var _query_camera := Transform3D.IDENTITY
var _query_size := Vector2.ZERO
var _query_zoom := 0.0

func operation_hint() -> String:
	return ["Новое выделение", "Добавить к выделению", "Убрать из выделения"][_operation]

func setup(owner_workspace: Control) -> void:
	workspace = owner_workspace
	workspace._selection_panel.selection_changed.connect(func(has_selection: bool) -> void:
		if not has_selection and transforming and not _committing and _stamp == null:
			cancel_gesture())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ghost = MultiMeshInstance3D.new()
	workspace._surface_root.add_child(_ghost)
	_hover = MeshInstance3D.new()
	workspace._surface_root.add_child(_hover)
	var outline := ImmediateMesh.new()
	outline.surface_begin(Mesh.PRIMITIVE_LINES)
	var box := AABB(Vector3.ZERO,Vector3.ONE)
	for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
		outline.surface_add_vertex(box.get_endpoint(edge[0]))
		outline.surface_add_vertex(box.get_endpoint(edge[1]))
	outline.surface_end()
	_hover.mesh = outline
	_hover.material_override = _material(Color(0.1,1,1,1))
	_hover.hide()
	_controls = VBoxContainer.new()
	_controls.name = "VoxelWorkshopTransformControls"
	var controls_parent: Control = workspace._operation_panel if is_instance_valid(workspace._operation_panel) else workspace._selection_panel
	controls_parent.add_child(_controls)
	_controls.hide()
	var operation_heading := Label.new()
	operation_heading.text = "ТЕКУЩАЯ ОПЕРАЦИЯ"
	operation_heading.modulate = Color(0.96, 0.72, 0.32)
	_controls.add_child(operation_heading)
	_hint = Label.new()
	_hint.name = "VoxelWorkshopOperationMessage"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.modulate = Color(0.76, 0.82, 0.88)
	_controls.add_child(_hint)
	var coordinates := HBoxContainer.new()
	coordinates.add_theme_constant_override("separation", 5)
	_controls.add_child(coordinates)
	for axis in ["X", "Y", "Z"]:
		var row := VBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := Label.new()
		label.text = "Сдвиг " + axis
		row.add_child(label)
		var number := SpinBox.new()
		number.min_value = -4096
		number.max_value = 4096
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		number.value_changed.connect(_coordinate_changed)
		row.add_child(number)
		_numbers.append(number)
		coordinates.add_child(row)
	_axis = _state_options(["Вокруг X", "Вокруг Y", "Вокруг Z"])
	_axis.select(1)
	_turns = _state_options(["Без поворота", "+90°", "180°", "−90°"])
	_axis_buttons = _segment_row(_controls, "Ось", _axis, ["X", "Y", "Z"])
	_turn_buttons = _segment_row(_controls, "Поворот", _turns, ["0°", "90°", "180°", "−90°"])
	_copy = CheckBox.new()
	_copy.text = "Копия · оставить исходный фрагмент"
	_controls.add_child(_copy)
	_copy.toggled.connect(_changed.unbind(1))
	_stamp_controls = VBoxContainer.new()
	_stamp_controls.add_theme_constant_override("separation", 5)
	_controls.add_child(_stamp_controls)
	_stamp_mode = _state_options(["Добавить · занятое сохранить","Заменить · цвет и материал","Вдавить · удалить объём внутрь"])
	_stamp_mirror = _state_options(["Без отражения","Отразить X","Отразить Y","Отразить Z"])
	_stamp_anchor = _state_options(["Опора: нижний угол","Опора: центр основания","Опора: центр объёма"])
	_stamp_application = _state_options(["Один отпечаток","Непрерывный путь","Прямая A→B","Россыпь"])
	_stamp_mode_buttons = _segment_row(_stamp_controls, "Режим", _stamp_mode, ["Добавить", "Заменить", "Вдавить"])
	_stamp_mirror_buttons = _segment_row(_stamp_controls, "Зеркало", _stamp_mirror, ["Нет", "X", "Y", "Z"])
	_stamp_anchor_buttons = _segment_row(_stamp_controls, "Опора", _stamp_anchor, ["Угол", "Низ", "Центр"])
	_stamp_application_buttons = _segment_row(_stamp_controls, "Нанесение", _stamp_application, ["Один", "Путь", "Линия", "Россыпь"])
	_stamp_spacing_row = HBoxContainer.new()
	_stamp_spacing_row.name = "VoxelWorkshopStampSpacing"
	_stamp_spacing_row.add_theme_constant_override("separation", 5)
	_stamp_controls.add_child(_stamp_spacing_row)
	var spacing_label := Label.new()
	spacing_label.text = "Шаг"
	spacing_label.custom_minimum_size.x = 58.0
	spacing_label.modulate = Color(0.66, 0.73, 0.80)
	_stamp_spacing_row.add_child(spacing_label)
	_stamp_spacing = SpinBox.new()
	_stamp_spacing.min_value = 1
	_stamp_spacing.max_value = 128
	_stamp_spacing.value = 1
	_stamp_spacing.suffix = " vox"
	_stamp_spacing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamp_spacing.value_changed.connect(_changed.unbind(1))
	_stamp_spacing_row.add_child(_stamp_spacing)
	_stamp_scatter_row = HBoxContainer.new()
	_stamp_scatter_row.name = "VoxelWorkshopStampScatterSpread"
	_stamp_scatter_row.add_theme_constant_override("separation",5)
	_stamp_controls.add_child(_stamp_scatter_row)
	var spread_label := Label.new()
	spread_label.text = "Разброс"
	spread_label.custom_minimum_size.x = 58.0
	spread_label.modulate = Color(0.66,0.73,0.80)
	_stamp_scatter_row.add_child(spread_label)
	_stamp_scatter_spread = SpinBox.new()
	_stamp_scatter_spread.min_value = 0
	_stamp_scatter_spread.max_value = 32
	_stamp_scatter_spread.value = 2
	_stamp_scatter_spread.suffix = " vox"
	_stamp_scatter_spread.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamp_scatter_spread.tooltip_text = "Случайное смещение поперёк пути в плоскости первой грани."
	_stamp_scatter_spread.value_changed.connect(_changed.unbind(1))
	_stamp_scatter_row.add_child(_stamp_scatter_spread)
	_stamp_scatter_options = HBoxContainer.new()
	_stamp_scatter_options.name = "VoxelWorkshopStampScatterOptions"
	_stamp_scatter_options.add_theme_constant_override("separation",5)
	_stamp_controls.add_child(_stamp_scatter_options)
	_stamp_scatter_random_turns = CheckBox.new()
	_stamp_scatter_random_turns.text = "Повороты 90°"
	_stamp_scatter_random_turns.button_pressed = true
	_stamp_scatter_random_turns.tooltip_text = "Каждый отпечаток случайно поворачивается вокруг нормали поверхности."
	_stamp_scatter_random_turns.toggled.connect(_changed.unbind(1))
	_stamp_scatter_options.add_child(_stamp_scatter_random_turns)
	_stamp_scatter_variant = Button.new()
	_stamp_scatter_variant.text = "Другой вариант"
	_stamp_scatter_variant.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamp_scatter_variant.tooltip_text = "Пересчитать ту же россыпь, не рисуя путь заново."
	_stamp_scatter_variant.pressed.connect(_new_scatter_variant)
	_stamp_scatter_options.add_child(_stamp_scatter_variant)
	_stamp_scatter_shape_status = Label.new()
	_stamp_scatter_shape_status.name = "VoxelWorkshopStampScatterShapes"
	_stamp_scatter_shape_status.modulate = Color(0.58, 0.80, 0.90)
	_stamp_scatter_shape_status.tooltip_text = (
		"Для каждой точки детерминированно выбирается одна форма из рецепта. "
		+ "«Другой вариант» меняет и расположение, и выбор форм."
	)
	_stamp_controls.add_child(_stamp_scatter_shape_status)
	_stamp_scatter_conform_row = HBoxContainer.new()
	_stamp_scatter_conform_row.name = "VoxelWorkshopStampScatterConform"
	_stamp_scatter_conform_row.add_theme_constant_override("separation",5)
	_stamp_controls.add_child(_stamp_scatter_conform_row)
	_stamp_scatter_conform = CheckBox.new()
	_stamp_scatter_conform.text = "Облегать рельеф"
	_stamp_scatter_conform.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamp_scatter_conform.tooltip_text = "Поднять или опустить каждый столбик штампа до исходной поверхности, сохранив его толщину."
	_stamp_scatter_conform.toggled.connect(_scatter_conform_changed)
	_stamp_scatter_conform_row.add_child(_stamp_scatter_conform)
	var bend_label := Label.new()
	bend_label.text = "Изгиб ≤"
	bend_label.modulate = Color(0.66,0.73,0.80)
	bend_label.tooltip_text = "Максимальное расстояние поиска поверхности."
	_stamp_scatter_conform_row.add_child(bend_label)
	_stamp_scatter_bend = SpinBox.new()
	_stamp_scatter_bend.min_value = 1
	_stamp_scatter_bend.max_value = 8
	_stamp_scatter_bend.value = 2
	_stamp_scatter_bend.suffix = " vox"
	_stamp_scatter_bend.custom_minimum_size.x = 88.0
	_stamp_scatter_bend.editable = false
	_stamp_scatter_bend.tooltip_text = "Максимальное расстояние от жёсткой формы до найденной поверхности."
	_stamp_scatter_bend.value_changed.connect(_changed.unbind(1))
	_stamp_scatter_conform_row.add_child(_stamp_scatter_bend)
	_stamp_depth_row = HBoxContainer.new()
	_stamp_depth_row.name = "VoxelWorkshopPatternDepth"
	_stamp_depth_row.add_theme_constant_override("separation",5)
	_stamp_controls.add_child(_stamp_depth_row)
	var depth_label := Label.new()
	depth_label.text = "Глубина"
	depth_label.custom_minimum_size.x = 58.0
	depth_label.modulate = Color(0.66,0.73,0.80)
	_stamp_depth_row.add_child(depth_label)
	_stamp_depth = SpinBox.new()
	_stamp_depth.min_value = 1
	_stamp_depth.max_value = 32
	_stamp_depth.value = 1
	_stamp_depth.suffix = " vox"
	_stamp_depth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stamp_depth.value_changed.connect(_changed.unbind(1))
	_stamp_depth_row.add_child(_stamp_depth)
	_stamp_depth_row.hide()
	_apply = Button.new()
	_apply.name = "VoxelWorkshopApplyOperation"
	_apply.text = "Применить · Enter"
	_apply.theme_type_variation = &"WorkshopPrimaryButton"
	_apply.pressed.connect(commit)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 5)
	_controls.add_child(actions)
	_apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_apply)
	var cancel := Button.new()
	cancel.name = "VoxelWorkshopCancelOperation"
	cancel.text = "Отмена · Esc"
	cancel.pressed.connect(cancel_gesture)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(cancel)
	_sync_all_segments()

func _state_options(labels: Array) -> OptionButton:
	var control := OptionButton.new()
	for label in labels:
		control.add_item(label)
	control.item_selected.connect(_changed.unbind(1))
	control.hide()
	_controls.add_child(control)
	return control

func _segment_row(parent: VBoxContainer, title: String, option: OptionButton, labels: Array) -> Array[Button]:
	var row := HBoxContainer.new()
	row.name = "VoxelWorkshop%sSegments" % title
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var caption := Label.new()
	caption.text = title
	caption.custom_minimum_size.x = 58.0
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.modulate = Color(0.66, 0.73, 0.80)
	row.add_child(caption)
	var group := ButtonGroup.new()
	group.allow_unpress = false
	var buttons: Array[Button] = []
	for index in labels.size():
		var button := Button.new()
		button.text = labels[index]
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"WorkshopSegmentButton"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = option.get_item_text(index)
		button.pressed.connect(_select_segment.bind(option, index))
		row.add_child(button)
		buttons.append(button)
	return buttons

func _select_segment(option: OptionButton, index: int) -> void:
	option.select(index)
	if option == _stamp_application:
		_reset_stamp_path()
		if index == 3 and int(_stamp_spacing.value) == 1:
			_stamp_spacing.value = 3
	_sync_all_segments()
	_update_stamp_application_controls()
	_changed()


func _coordinate_changed(_value: float) -> void:
	if _stamp != null and not _syncing:
		_stamp_position_picked = true
	_changed()

func _sync_segment(option: OptionButton, buttons: Array[Button]) -> void:
	for index in buttons.size():
		buttons[index].set_pressed_no_signal(index == option.selected)

func _sync_all_segments() -> void:
	_sync_segment(_axis, _axis_buttons)
	_sync_segment(_turns, _turn_buttons)
	_sync_segment(_stamp_mode, _stamp_mode_buttons)
	_sync_segment(_stamp_mirror, _stamp_mirror_buttons)
	_sync_segment(_stamp_anchor, _stamp_anchor_buttons)
	_sync_segment(_stamp_application, _stamp_application_buttons)


func _new_scatter_variant() -> void:
	_stamp_scatter_seed += 1
	_changed()

func _scatter_conform_changed(enabled: bool) -> void:
	_stamp_scatter_bend.editable = enabled
	_changed()

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = color
	return material

func begin_transform() -> void:
	if workspace._selection_panel.busy() or workspace._selection_panel.selected.is_empty():
		return
	cancel_gesture()
	_indices = workspace._selection_panel.selection_indices()
	_start_transform()

func begin_stamp(preset: Resource, session_key: String = "") -> void:
	if workspace._resource == null:
		return
	cancel_gesture()
	_stamp_settings_id = session_key if not session_key.is_empty() else _stamp_session_key(preset)
	var candidate: Resource = preset.duplicate(true)
	if preset is Stamp.Preset and candidate is Stamp.Preset:
		candidate.generated_variants.assign(preset.generated_variants)
		candidate.generated_variants_key = preset.generated_variants_key
	var prepared := Stamp.prepare_generated_variants(candidate)
	if prepared.has("error"):
		_stamp_settings_id = ""
		workspace._set_status(prepared.error, true)
		return
	_stamp = candidate
	_stamp_variant_count = prepared.variants.size()
	_start_transform()
	_stamp_mode.select(0)
	_stamp_mirror.select(0)
	_stamp_anchor.select(clampi(_stamp.anchor,0,2))
	var placement_defaults := Stamp.recommended_placement(_stamp)
	_stamp_application.select(clampi(int(placement_defaults.get("application", 0)), 0, 3))
	_stamp_spacing.value = Stamp.recommended_spacing(_stamp)
	_stamp_scatter_spread.value = clampi(int(placement_defaults.get("spread", 2)), 0, 32)
	_stamp_scatter_random_turns.button_pressed = true
	_stamp_scatter_conform.set_pressed_no_signal(bool(placement_defaults.get("conform", false)))
	_stamp_scatter_bend.value = 2
	_stamp_scatter_bend.editable = false
	_stamp_scatter_seed = maxi(1,Time.get_ticks_usec())
	_stamp_depth.value = clampi(_stamp.pattern_depth,1,32) if _is_pattern() else 1
	_stamp_normal = Vector3i.UP
	_restore_stamp_session_settings()
	_configure_stamp_kind()
	_reset_stamp_path()
	_sync_all_segments()
	_numbers[0].set_value_no_signal(workspace._resource.grid_size().x/2)
	_numbers[2].set_value_no_signal(workspace._resource.grid_size().z/2)
	_changed()
	workspace._set_status(
		"Штамп выбран%s · наведите для точного preview · ЛКМ фиксирует черновик · Enter применяет · Esc возвращает кисть"
		% (" · форм в россыпи: %d" % _stamp_variant_count if _stamp_variant_count > 1 else "")
	)

func _start_transform() -> void:
	_snapshot = workspace._resource.to_definition().duplicate(true)
	_source = workspace._resource
	_source.changed.connect(_source_changed)
	_region = workspace._edit_region_blocks
	_height = workspace._slice_height
	transforming = true
	_syncing = true
	for number in _numbers:
		number.value = 0
	_turns.select(0)
	_sync_all_segments()
	_copy.set_pressed_no_signal(false)
	_copy.visible = _stamp == null
	_stamp_controls.visible = _stamp != null
	for i in 3:
		_numbers[i].get_parent().get_child(0).text = ("Опора " if _stamp != null else "Сдвиг ")+["X","Y","Z"][i]
	_syncing = false
	_controls.show()
	if _stamp != null:
		workspace._show_stamp_operation(_stamp.display_name, _is_pattern())
	else:
		workspace._show_selection_operation()
	var ancestor := _controls.get_parent()
	while ancestor != null and not ancestor is ScrollContainer:
		ancestor = ancestor.get_parent()
	if ancestor is ScrollContainer:
		ancestor.ensure_control_visible.call_deferred(_controls)
	workspace._selection_panel.set_active(true)
	_changed()

func _changed() -> void:
	_sync_all_segments()
	if _syncing or not transforming:
		return
	if _stamp != null:
		if _stamp_draft_ready and not _stamp_drawing:
			_stamp_draft_visible_count = -1
		workspace._update_tool_help(workspace._selected_tool_id())
	_offset = Vector3i(int(_numbers[0].value),int(_numbers[1].value),int(_numbers[2].value))
	_pending = true
	_apply.disabled = true

func cancel_gesture(return_to_parent := true) -> void:
	var was_transforming := transforming
	var was_stamp := _stamp != null
	_capture_stamp_session_settings()
	_surface_marquee = null
	_surface_bounds = {}
	_surface_footprint = {}
	_surface_stage = 0
	_ready_rect = Rect2(-9999,-9999,0,0)
	if _source != null and _source.changed.is_connected(_source_changed):
		_source.changed.disconnect(_source_changed)
	_source = null
	_stamp = null
	_stamp_variant_count = 1
	_stamp_settings_id = ""
	_reset_stamp_path()
	if was_stamp and is_instance_valid(workspace):
		workspace._update_tool_help(workspace._selected_tool_id())
	dragging = false
	transforming = false
	_finish = false
	_job = null
	_pending = false
	_arrow_axis = -1
	if is_instance_valid(_ghost):
		_ghost.hide()
	if is_instance_valid(_controls):
		_controls.hide()
	if return_to_parent and was_transforming and is_instance_valid(workspace):
		if was_stamp:
			workspace._show_stamp_library_mode(false)
		elif workspace._selection_panel.active:
			workspace._show_selection_mode()
	queue_redraw()

func commit() -> void:
	if not transforming or _pending or _apply.disabled:
		return
	_committing = true
	var valid: bool = workspace._resource.to_definition() == _snapshot and workspace._actions.apply_fragment(workspace._resource,_plan)
	_committing = false
	if not valid:
		_hint.text = "Модель изменилась. Отмените и выберите фрагмент заново."
		_apply.disabled = true
		return
	# A stamp is an independent authoring operation. It must not silently replace
	# a retained selection or the mask snapshot that is only suspended while the
	# stamp owns the Canvas.
	# Reuse the prepared generated set; the next begin_stamp still duplicates the
	# editor preset, but copies its transient cache instead of rebuilding it.
	var next_stamp: Resource = _stamp if _stamp != null else null
	var next_stamp_settings_id := _stamp_settings_id
	if _stamp == null:
		workspace._selection_panel.set_selection(_plan.selected)
	var message := "Фрагмент применён"
	if _stamp != null:
		message = "Паттерн применён" if _is_pattern() else "Вдавливание применено" if _stamp_mode.selected == 2 else "Штамп применён"
	if next_stamp != null:
		# Stamps behave like a selected paint brush: one Enter creates one Undo
		# operation, then the same preset is immediately ready for the next draft.
		begin_stamp(next_stamp, next_stamp_settings_id)
		workspace._set_status(message + " · штамп остаётся выбран · Ctrl+Z отменяет отпечаток")
	else:
		cancel_gesture()
		workspace._set_status(message + " · Ctrl+Z отменяет · Ctrl+S сохраняет")

func _reset_stamp_path() -> void:
	_stamp_knots.clear()
	_stamp_draft_visible_count = -1
	_stamp_line_started = false
	_stamp_drawing = false
	_stamp_draft_ready = false
	_stamp_position_picked = false


func _stamp_has_draft() -> bool:
	return (
		_stamp != null
		and (
			_stamp_position_picked
			or _stamp_drawing
			or _stamp_draft_ready
			or _stamp_line_started
			or not _stamp_knots.is_empty()
		)
	)


func _stamp_session_key(preset: Resource) -> String:
	var path := preset.resource_path
	var geometry_id := ""
	if preset.geometry != null:
		geometry_id = preset.geometry.model_id
	return "%d:%s:%s:%s" % [preset.kind, path, geometry_id, preset.display_name]


func _capture_stamp_session_settings() -> void:
	if _stamp == null or _stamp_settings_id.is_empty():
		return
	_stamp_session_settings[_stamp_settings_id] = {
		"mode": _stamp_mode.selected,
		"mirror": _stamp_mirror.selected,
		"anchor": _stamp_anchor.selected,
		"application": _stamp_application.selected,
		"spacing": int(_stamp_spacing.value),
		"spread": int(_stamp_scatter_spread.value),
		"random_turns": _stamp_scatter_random_turns.button_pressed,
		"conform": _stamp_scatter_conform.button_pressed,
		"bend": int(_stamp_scatter_bend.value),
		"depth": int(_stamp_depth.value),
		"axis": _axis.selected,
		"turns": _turns.selected,
	}


func _restore_stamp_session_settings() -> void:
	if not _stamp_session_settings.has(_stamp_settings_id):
		return
	var settings: Dictionary = _stamp_session_settings[_stamp_settings_id]
	_stamp_mode.select(clampi(int(settings.get("mode", 0)), 0, _stamp_mode.item_count - 1))
	_stamp_mirror.select(clampi(int(settings.get("mirror", 0)), 0, _stamp_mirror.item_count - 1))
	_stamp_anchor.select(clampi(int(settings.get("anchor", _stamp.anchor)), 0, _stamp_anchor.item_count - 1))
	_stamp_application.select(clampi(int(settings.get("application", 0)), 0, _stamp_application.item_count - 1))
	_stamp_spacing.set_value_no_signal(clampi(int(settings.get("spacing", 1)), 1, 128))
	_stamp_scatter_spread.set_value_no_signal(clampi(int(settings.get("spread", 2)), 0, 32))
	_stamp_scatter_random_turns.set_pressed_no_signal(bool(settings.get("random_turns", true)))
	_stamp_scatter_conform.set_pressed_no_signal(bool(settings.get("conform", false)))
	_stamp_scatter_bend.set_value_no_signal(clampi(int(settings.get("bend", 2)), 1, 8))
	_stamp_depth.set_value_no_signal(clampi(int(settings.get("depth", _stamp.pattern_depth)), 1, 32))
	_axis.select(clampi(int(settings.get("axis", 1)), 0, _axis.item_count - 1))
	_turns.select(clampi(int(settings.get("turns", 0)), 0, _turns.item_count - 1))

func _is_pattern() -> bool:
	return _stamp != null and _stamp.kind == Stamp.Preset.KIND_PATTERN

func _configure_stamp_kind() -> void:
	var pattern := _is_pattern()
	_stamp_mode_buttons[0].text = "Добавить"
	_stamp_mode_buttons[1].text = "Вырезать" if pattern else "Заменить"
	_stamp_mode_buttons[2].text = "Вдавить"
	_stamp_mode_buttons[0].tooltip_text = "Добавить текущим цветом" if pattern else _stamp_mode.get_item_text(0)
	_stamp_mode_buttons[1].tooltip_text = "Удалить форму паттерна" if pattern else _stamp_mode.get_item_text(1)
	_stamp_mode_buttons[2].tooltip_text = "Зеркально направить объём штампа внутрь поверхности и удалить его."
	_stamp_mode_buttons[2].visible = not pattern
	if pattern and _stamp_mode.selected == 2:
		_stamp_mode.select(1)
	for index in _stamp_mirror_buttons.size():
		_stamp_mirror_buttons[index].text = (["Нет","U","V","UV"] if pattern else ["Нет","X","Y","Z"])[index]
	_stamp_anchor_buttons[1].text = "Центр" if pattern else "Низ"
	_stamp_anchor_buttons[2].visible = not pattern
	_stamp_application_buttons[3].visible = not pattern
	if pattern and _stamp_application.selected == 3:
		_stamp_application.select(0)
	_stamp_application_buttons[0].get_parent().visible = true
	_stamp_spacing_row.visible = true
	_stamp_depth_row.visible = pattern
	_update_stamp_application_controls()


func _update_stamp_application_controls() -> void:
	if not is_instance_valid(_stamp_application):
		return
	var scatter := _stamp != null and not _is_pattern() and _stamp_application.selected == 3
	var placement_defaults := Stamp.recommended_placement(_stamp)
	var allow_conform := bool(placement_defaults.get("allow_conform", true))
	if not allow_conform:
		_stamp_scatter_conform.set_pressed_no_signal(false)
	var footprint_anchor := _is_pattern() or (_stamp != null and _stamp_mode.selected == 2)
	_stamp_anchor_buttons[1].text = "Центр" if footprint_anchor else "Низ"
	_stamp_anchor_buttons[2].text = "Центр"
	_stamp_anchor_buttons[2].visible = not footprint_anchor
	if footprint_anchor and _stamp_anchor.selected == 2:
		_stamp_anchor.select(1)
		_sync_segment(_stamp_anchor,_stamp_anchor_buttons)
	if not _axis_buttons.is_empty():
		_axis_buttons[0].get_parent().visible = not _is_pattern() and not scatter and _stamp_mode.selected != 2
	if is_instance_valid(_stamp_scatter_row):
		_stamp_scatter_row.visible = scatter
	if is_instance_valid(_stamp_scatter_options):
		_stamp_scatter_options.visible = scatter
	if is_instance_valid(_stamp_scatter_shape_status):
		_stamp_scatter_shape_status.visible = scatter and _stamp_variant_count > 1
		_stamp_scatter_shape_status.text = "Набор форм: %d" % _stamp_variant_count
	if is_instance_valid(_stamp_scatter_conform_row):
		_stamp_scatter_conform_row.visible = scatter and allow_conform
	if is_instance_valid(_stamp_scatter_bend):
		_stamp_scatter_bend.editable = scatter and _stamp_scatter_conform.button_pressed

func _set_stamp_position(cell: Vector3i, picked := true) -> void:
	if picked:
		_stamp_position_picked = true
	_syncing = true
	for i in 3:
		_numbers[i].value = cell[i]
	_syncing = false
	_offset = cell
	_pending = true
	_apply.disabled = true

func _stamp_cell_at(point: Vector2) -> Dictionary:
	var pick: Dictionary = workspace._pick_at(point)
	var cell: Vector3i = pick.get("adjacent",Vector3i(-1,-1,-1)) if _stamp_mode.selected == 0 else pick.get("hit",Vector3i(-1,-1,-1))
	return {"valid":cell.x >= 0 and cell.y >= 0 and cell.z >= 0,"cell":cell,"normal":pick.get("normal",Vector3i.UP)}

func _stamp_placements() -> Array[Vector3i]:
	var sampled := _all_stamp_placements()
	if _stamp_application.selected in [1,2,3] and _stamp_draft_ready and _stamp_draft_visible_count >= 0:
		var visible: Array[Vector3i] = []
		for index in mini(_stamp_draft_visible_count, sampled.size()):
			visible.append(sampled[index])
		return visible
	return sampled


func _all_stamp_placements() -> Array[Vector3i]:
	if _stamp_application.selected in [1,3] and not _stamp_knots.is_empty():
		return Stamp.sample_path(_stamp_knots,int(_stamp_spacing.value))
	if _stamp_application.selected == 2 and _stamp_line_started:
		return Stamp.sample_line(_stamp_line_start,_offset,int(_stamp_spacing.value))
	var points: Array[Vector3i] = [_offset]
	return points

func _source_changed() -> void:
	if _committing:
		return
	if _stamp != null and not _stamp_has_draft():
		# Undo/Redo changes the Resource, but it should not take the selected stamp
		# out of the user's hand when there is no unfinished draft to invalidate.
		var selected_stamp: Resource = _stamp.duplicate(true)
		var selected_settings_id := _stamp_settings_id
		begin_stamp(selected_stamp, selected_settings_id)
		return
	cancel_gesture()

func _step_stamp_draft(redo: bool) -> bool:
	if (
		not transforming or _stamp == null or not _stamp_draft_ready
		or _stamp_application.selected not in [1,2,3]
	):
		return false
	if _stamp_drawing:
		workspace._set_status("Отпустите ЛКМ, затем изменяйте черновик через Ctrl+Z / Ctrl+Shift+Z.")
		return true
	var sampled := _all_stamp_placements()
	var current := sampled.size() if _stamp_draft_visible_count < 0 else clampi(_stamp_draft_visible_count,0,sampled.size())
	if redo:
		if current >= sampled.size():
			workspace._set_status("В черновике больше нечего возвращать.")
			return true
		current += 1
	else:
		if current <= 0:
			workspace._set_status("Черновик уже пуст · Ctrl+Shift+Z возвращает отпечатки · Esc отменяет.")
			return true
		current -= 1
	_stamp_draft_visible_count = current
	_pending = true
	_apply.disabled = true
	var draft_name: String = ["", "пути", "линии", "россыпи"][_stamp_application.selected]
	workspace._set_status("Черновик %s · %d/%d отпечатков · Ctrl+Z назад · Ctrl+Shift+Z вперёд · Enter применяет" % [draft_name,current,sampled.size()])
	return true

func handle(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed:
		if event.is_command_or_control_pressed() and (
			event.keycode == KEY_Z or (event.keycode == KEY_Y and not event.shift_pressed)
		):
			var redo: bool = event.keycode == KEY_Y or event.shift_pressed
			if _step_stamp_draft(redo):
				return true
		if (
			event.keycode == KEY_S
			and event.is_command_or_control_pressed()
			and transforming
			and (_stamp == null or _stamp_has_draft())
		):
			_hint.text = "Сначала примените операцию (Enter) или отмените её (Esc), затем сохраните."
			return true
		if event.keycode == KEY_ESCAPE and _surface_stage != 0:
			cancel_gesture()
			workspace._set_status("Черновик двухэтапного выделения отменён · прежнее выделение сохранено")
			return true
		if event.keycode == KEY_ESCAPE and (dragging or _finish or transforming):
			if transforming and _stamp_has_draft():
				var selected_stamp: Resource = _stamp.duplicate(true)
				var selected_settings_id := _stamp_settings_id
				begin_stamp(selected_stamp, selected_settings_id)
				workspace._set_status("Черновик отменён · штамп остаётся выбран · Esc ещё раз возвращает кисть")
			else:
				cancel_gesture(false)
				workspace._return_to_last_brush()
			return true
		if event.keycode == KEY_ENTER and _surface_stage == 2:
			_finish = true
			_ready_rect = Rect2(-9999,-9999,0,0)
			workspace._set_status(operation_hint() + " · применение двухэтапного выделения…")
			return true
		if event.keycode == KEY_ENTER and transforming:
			# Let native numeric fields submit their pending text first.
			if workspace.get_viewport().gui_get_focus_owner() is LineEdit:
				return false
			commit()
			return true
	if not workspace._selection_panel.active or workspace._resource == null:
		return false
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT and (dragging or _finish or _surface_stage != 0):
		cancel_gesture() # Never mix a rectangle query with a changing camera.
	if event is InputEventMouseButton and event.button_index != MOUSE_BUTTON_LEFT:
		_arrow_axis = -1
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if transforming:
			if event.pressed:
				if _stamp == null or _stamp_application.selected == 0:
					for axis in 3:
						var segment := _arrow(axis)
						if Geometry2D.get_closest_point_to_segment(event.position,segment[0],segment[1]).distance_to(event.position) < 10:
							_arrow_axis = axis
							_arrow_start = event.position
							_arrow_value = _offset[axis]
							break
				if _stamp != null and _arrow_axis < 0:
					var picked := _stamp_cell_at(event.position)
					if picked.valid:
						var cell: Vector3i = picked.cell
						_stamp_position_picked = true
						# A repeated flat pattern keeps the plane chosen at the first point.
						if (_is_pattern() or _stamp_application.selected == 3 or _stamp_mode.selected == 2) and (_stamp_application.selected != 2 or not _stamp_line_started):
							_stamp_normal = Model.axis_normal(picked.normal)
						if _stamp_application.selected in [1,3]:
							_stamp_knots.assign([cell])
							_stamp_draft_visible_count = -1
							_stamp_draft_ready = false
							_stamp_drawing = true
							_set_stamp_position(cell)
							workspace._set_status(("Россыпь" if _stamp_application.selected == 3 else "Путь паттерна" if _is_pattern() else "Путь штампа")+" · ведите ЛКМ · отпускание завершает черновик")
						elif _stamp_application.selected == 2:
							if not _stamp_line_started:
								_stamp_line_start = cell
								_stamp_line_started = true
								_stamp_draft_ready = false
								_set_stamp_position(cell)
								workspace._set_status(("Линия паттерна" if _is_pattern() else "Линия штампа")+" · A задана · укажите B вторым кликом")
							else:
								_set_stamp_position(cell)
								_stamp_draft_ready = true
								_stamp_draft_visible_count = _all_stamp_placements().size()
								_pending = true
								workspace._set_status("Линия готова · Ctrl+Z правит черновик · Enter применяет · Esc отменяет")
						else:
							_set_stamp_position(cell)
			else:
				_arrow_axis = -1
				if _stamp != null and _stamp_application.selected in [1,3] and _stamp_drawing:
					_stamp_drawing = false
					_stamp_draft_ready = true
					_stamp_draft_visible_count = _all_stamp_placements().size()
					_pending = true
					workspace._set_status(("Россыпь" if _stamp_application.selected == 3 else "Путь")+" готов%s · Ctrl+Z правит черновик · Enter применяет · Esc отменяет" % ("а" if _stamp_application.selected == 3 else ""))
			return true
		if workspace._selection_panel._mode.selected not in [3,4]:
			return false
		if _surface_stage == 2:
			if event.pressed:
				_finish = true
				_ready_rect = Rect2(-9999,-9999,0,0)
				workspace._set_status(operation_hint() + " · применение двухэтапного выделения…")
			return true
		if event.pressed:
			if workspace._selection_panel.busy():
				return true
			cancel_gesture()
			_gesture_mode = workspace._selection_panel._mode.selected
			_depth = int(workspace._selection_panel._depth.value)
			_operation = 2 if event.ctrl_pressed else 1 if event.shift_pressed else workspace._selection_panel._operation.selected
			_prior = workspace._selection_panel.selected.duplicate()
			_selection_normal = workspace._selection_panel.selection_normal()
			if _gesture_mode == 4:
				var pick: Dictionary = workspace._pick_at(event.position)
				if not pick.has("hit") or not workspace._cell_in_edit_region(pick.hit):
					workspace._set_status("Начните рамку на грани объекта",true)
					return true
				var ray := _ray(event.position)
				_surface_marquee = SurfaceMarquee.new()
				if not _surface_marquee.begin(pick.hit,ray[0],ray[1],workspace._resource.normalized_density()):
					cancel_gesture()
					workspace._set_status("Не удалось определить грань. Начните ближе к её середине.",true)
					return true
				if _operation == 0 or _prior.is_empty():
					_selection_normal = Vector3i.ZERO
					_selection_normal[_surface_marquee.axis] = _surface_marquee.outward
				_surface_stage = 1
				_surface_footprint = {}
				_surface_bounds = {}
				_depth = 1
				workspace._selection_panel._depth.max_value = maxi(
					1,
					_surface_marquee.maximum_depth(workspace._resource.grid_size()),
				)
				workspace._selection_panel._depth.set_value_no_signal(1)
			elif _operation == 0 or _prior.is_empty():
				var pick: Dictionary = workspace._pick_at(event.position)
				if pick.has("normal"):
					_selection_normal = Model.axis_normal(pick.normal)
			dragging = true
			_from = event.position
			_to = _from
			_source = workspace._resource
			_source.changed.connect(_source_changed)
			_region = workspace._edit_region_blocks
			_height = workspace._slice_height
			_query_camera = workspace._camera.global_transform
			_query_size = workspace._viewport_container.size
			_query_zoom = workspace._camera.size
			workspace._set_status(
				operation_hint() + (
					" · этап 1/2: протяните область на начальной грани · Esc отменяет"
					if _gesture_mode == 4
					else " · протяните рамку · Esc отменяет"
				)
			)
		else:
			if dragging:
				_to = event.position
				dragging = false
				if _gesture_mode == 4:
					var footprint := _surface_footprint_at(_to)
					if footprint.has("error"):
						workspace._set_status(footprint.error,true)
						cancel_gesture()
						return true
					_surface_footprint = footprint
					_surface_bounds = _surface_marquee.bounds_from_footprint(
						_surface_footprint.low,
						_surface_footprint.high,
						1,
					)
					_surface_depth_origin = _to
					_surface_stage = 2
					_job = null
					_ready_rect = Rect2(-9999,-9999,0,0)
					workspace._set_status(
						operation_hint() + " · этап 2/2: двигайте мышь внутрь · глубина 1 vox · клик или Enter подтверждает"
					)
				else:
					_finish = true
		queue_redraw()
		return true
	if event is InputEventMouseMotion:
		if _surface_stage == 2:
			_to = event.position
			_set_surface_depth(_surface_depth_at(event.position))
			return true
		if transforming and _stamp != null and not _stamp_position_picked:
			var hover_pick := _stamp_cell_at(event.position)
			if hover_pick.valid:
				var hover_normal := _stamp_normal
				if _is_pattern() or _stamp_application.selected == 3 or _stamp_mode.selected == 2:
					hover_normal = Model.axis_normal(hover_pick.normal)
				if hover_pick.cell != _offset or hover_normal != _stamp_normal or not _ghost.visible:
					_stamp_normal = hover_normal
					_set_stamp_position(hover_pick.cell, false)
			else:
				_ghost.hide()
			return true
		if transforming and _arrow_axis >= 0:
			var unit := Vector3.ZERO
			unit[_arrow_axis] = 1.0 / workspace._resource.normalized_density()
			var direction := _screen(_center+unit)-_screen(_center)
			if direction.length_squared() > 0.01:
				_numbers[_arrow_axis].value = _arrow_value + roundi((event.position-_arrow_start).dot(direction)/direction.length_squared())
			return true
		if transforming and _stamp != null and (_stamp_drawing or (_stamp_application.selected == 2 and _stamp_line_started and not _stamp_draft_ready)):
			var picked := _stamp_cell_at(event.position)
			if picked.valid:
				var cell: Vector3i = picked.cell
				if _stamp_drawing and (_stamp_knots.is_empty() or _stamp_knots[-1] != cell):
					_stamp_knots.append(cell)
				_set_stamp_position(cell)
			return true
		if dragging:
			_to = event.position
			queue_redraw()
			return true
	return false

func _surface_footprint_at(point: Vector2) -> Dictionary:
	if _surface_marquee == null:
		return {"error":"Двухэтапное выделение не начато."}
	var ray := _ray(point)
	return _surface_marquee.footprint_bounds(ray[0],ray[1])

func _surface_depth_at(point: Vector2) -> int:
	if _surface_marquee == null or not _surface_footprint.has("box"):
		return 1
	var box: AABB = _surface_footprint.box
	var center := box.position+box.size*0.5
	var inward := Vector3.ZERO
	inward[_surface_marquee.axis] = -float(_surface_marquee.outward)/float(workspace._resource.normalized_density())
	var inward_step := _screen(center+inward)-_screen(center)
	if inward_step.length_squared() < 4.0:
		# When the fixed face normal points almost straight into the camera its
		# projection has no useful screen direction. Keep the gesture usable and
		# deterministic: vertical screen movement becomes the depth ruler, scaled
		# by the clearest tangential voxel direction (with a small readable floor).
		var tangent_scale := 0.0
		for component in 3:
			if component == _surface_marquee.axis:
				continue
			var tangent := Vector3.ZERO
			tangent[component] = 1.0/float(workspace._resource.normalized_density())
			tangent_scale = maxf(tangent_scale,(_screen(center+tangent)-_screen(center)).length())
		inward_step = Vector2(0,maxf(4.0,tangent_scale))
	return SurfaceMarquee.depth_from_screen(
		_surface_depth_origin,
		point,
		inward_step,
		_surface_marquee.maximum_depth(workspace._resource.grid_size()),
	)

func _set_surface_depth(value: int) -> void:
	if _surface_stage != 2 or _surface_marquee == null or _surface_footprint.is_empty():
		return
	var safe := clampi(
		value,
		1,
		maxi(1,_surface_marquee.maximum_depth(workspace._resource.grid_size())),
	)
	if safe == _depth and _surface_bounds.has("box"):
		return
	_depth = safe
	workspace._selection_panel._depth.set_value_no_signal(safe)
	_surface_bounds = _surface_marquee.bounds_from_footprint(
		_surface_footprint.low,
		_surface_footprint.high,
		_depth,
	)
	_job = null
	_ready_rect = Rect2(-9999,-9999,0,0)
	workspace._set_status(
		operation_hint() + " · этап 2/2: глубина %d vox · клик или Enter подтверждает · Esc отменяет" % _depth
	)
	queue_redraw()

func _process(_delta: float) -> void:
	if workspace == null:
		return
	if not workspace.is_visible_in_tree() or not workspace._selection_panel.active:
		cancel_gesture()
		_hover.hide()
		return
	if (transforming or dragging or _finish or _surface_stage != 0) and workspace._resource != _source:
		cancel_gesture()
		return
	if (transforming or dragging or _finish or _surface_stage != 0) and (_region != workspace._edit_region_blocks or _height != workspace._slice_height):
		cancel_gesture()
		return
	if (dragging or _finish or _surface_stage != 0) and (_query_camera != workspace._camera.global_transform or _query_zoom != workspace._camera.size):
		cancel_gesture()
		return
	if (dragging or _finish or _surface_stage != 0) and workspace._selection_panel._mode.selected != _gesture_mode:
		cancel_gesture()
		return
	if _surface_stage == 2 and int(workspace._selection_panel._depth.value) != _depth:
		_set_surface_depth(int(workspace._selection_panel._depth.value))
	workspace._cursor.hide()
	if _stamp != null and (workspace._groups_panel.isolation_enabled() or not workspace._hidden_group_indices.is_empty()):
		cancel_gesture()
		workspace._set_status("Отпечаток отменён: изменена видимость групп.",true)
		return
	if _stamp != null and _stamp_part != workspace._actions.active_part:
		_stamp_part = workspace._actions.active_part
		_changed()
	if dragging or _finish or _surface_stage == 2:
		if _surface_marquee != null:
			if _surface_stage == 1:
				_surface_bounds = _surface_footprint_at(_to)
			elif _surface_stage == 2:
				_surface_bounds = _surface_marquee.bounds_from_footprint(
					_surface_footprint.low,
					_surface_footprint.high,
					_depth,
				)
			if _surface_bounds.has("error"):
				workspace._set_status(_surface_bounds.error,true)
				cancel_gesture()
				return
		var rect := Rect2(_from,_to-_from).abs()
		if rect.size.x < 3 or rect.size.y < 3:
			rect = Rect2(_to-Vector2(3,3),Vector2(6,6))
		if _job == null and rect == _ready_rect and not _finish:
			return
		if _job == null:
			var query_source: EmberVoxelModelResource = workspace._isolation_resource if workspace._isolation_resource != null else workspace._resource
			if _surface_marquee != null:
				_job = Selection.new()
				_job.start_box(query_source,_surface_bounds.low,_surface_bounds.high,workspace._edit_region_blocks,workspace._slice_height)
			else:
				_job = Gesture.new()
				_job.source = query_source
				_job.camera = workspace._camera
				_job.rectangle = rect
				_job.viewport_scale = Vector2(workspace._viewport.size)/workspace._viewport_container.size
				_job.through = workspace._selection_panel._through.selected == 1
				_job.region = workspace._edit_region_blocks
				_job.height = workspace._slice_height
			_job_rect = rect
			workspace._set_status(
				operation_hint() + (
					" · этап 1/2: считаю плоскую область…"
					if _surface_stage == 1
					else " · этап 2/2: глубина %d vox · считаю объём…" % _depth
					if _surface_stage == 2
					else " · поиск в рамке… Esc отменяет; геометрия не меняется"
				)
			)
		var deadline := Time.get_ticks_usec()+3000
		while not _job.done and Time.get_ticks_usec() < deadline:
			_job.step(32)
		if _job.done:
			if _job_rect == rect:
				var failure: String = _job.error
				_ready_rect = rect
				workspace._set_status(
					_job.error
					if not _job.error.is_empty()
					else operation_hint() + " · этап 1/2: область %d vox · отпустите мышь" % _job.indices.size()
					if _surface_stage == 1
					else operation_hint() + " · этап 2/2: глубина %d vox · в объёме %d vox · клик или Enter подтверждает" % [_depth,_job.indices.size()]
					if _surface_stage == 2
					else operation_hint() + " · в рамке: %d vox · отпустите мышь" % _job.indices.size()
				)
				if _job.error.is_empty():
					_show_cells(_job.indices,Color(0.1,1,1,0.5))
					if _finish:
						var combined := Selection.combine(_prior,_job.indices,_operation)
						if combined.size() <= Selection.LIMIT:
							workspace._selection_panel.set_selection(
								PackedInt32Array(combined.keys()),
								SelectionPanel.DEFAULT_OVERLAY_COLOR,
								_selection_normal,
								true,
							)
						else:
							failure = "Суммарное выделение превышает лимит; прежнее сохранено"
				if _finish:
					cancel_gesture()
					workspace._set_status(failure if not failure.is_empty() else "Выделено: %d vox · переносите стрелками через «Перенос / копия / поворот…»" % workspace._selection_panel.selected.size(),not failure.is_empty())
			_job = null
	elif transforming and _pending:
		_pending = false
		if _stamp == null:
			_plan = Fragment.plan(workspace._resource,_indices,_offset,_axis.selected,_turns.selected,_copy.button_pressed,workspace._edit_region_blocks,workspace._slice_height)
		elif _is_pattern():
			var palette_index := int(workspace._palette.get_item_metadata(workspace._palette.selected)) if workspace._palette.selected >= 0 else 1
			_plan = Pattern.plan_many(workspace._resource,_stamp,_stamp_placements(),_stamp_normal,_turns.selected,_stamp_mirror.selected-1,mini(_stamp_anchor.selected,1),_stamp_mode.selected == 1,int(_stamp_depth.value),palette_index,workspace._actions.active_part,workspace._edit_region_blocks,workspace._slice_height)
		elif _stamp_application.selected == 3:
			_plan = Stamp.plan_scatter(
				workspace._resource,_stamp,_stamp_placements(),_stamp_normal,
				int(_stamp_scatter_spread.value),_stamp_scatter_seed,
				_stamp_scatter_random_turns.button_pressed,_turns.selected,
				_stamp_mirror.selected-1,_stamp_anchor.selected,
				_stamp_mode.selected == 1,workspace._actions.active_part,
				workspace._edit_region_blocks,workspace._slice_height,
				_stamp_scatter_conform.button_pressed,int(_stamp_scatter_bend.value),
				_stamp_mode.selected == 2,
			)
		else:
			var orient_to_surface := (
				_stamp_mode.selected == 2
				or bool(Stamp.recommended_placement(_stamp).get("up_only", false))
			)
			_plan = Stamp.plan_many(
				workspace._resource,_stamp,_stamp_placements(),_axis.selected,
				_turns.selected,_stamp_mirror.selected-1,_stamp_anchor.selected,
				_stamp_mode.selected == 1,workspace._actions.active_part,
				workspace._edit_region_blocks,workspace._slice_height,
				PackedInt32Array(),_stamp_normal if orient_to_surface else Vector3i.ZERO,
				false,2,_stamp_mode.selected == 2,
			)
		var awaiting_stamp_gesture: bool = _stamp != null and (
			(_stamp_application.selected == 0 and not _stamp_position_picked)
			or (_stamp_application.selected in [1,2,3] and not _stamp_draft_ready)
			or (_stamp_draft_ready and _stamp_placements().is_empty())
		)
		_apply.disabled = _plan.has("error") or awaiting_stamp_gesture
		_hint.modulate = Color(1.0, 0.45, 0.40) if _plan.has("error") else Color(0.76, 0.82, 0.88)
		_hint.text = _plan.get("error","Оранжевое — исходное · голубое — результат")
		if awaiting_stamp_gesture:
			_hint.modulate = Color(0.76,0.82,0.88)
			_hint.text = (
				"Черновик пуст · Ctrl+Shift+Z возвращает отпечаток · Esc отменяет"
				if _stamp_draft_ready and not _all_stamp_placements().is_empty()
				else "Зажмите ЛКМ для россыпи" if _stamp_application.selected == 3
				else "Зажмите ЛКМ для пути" if _stamp_application.selected == 1
				else "Кликните точку A для линии" if _stamp_application.selected == 2
				else "Наведите отпечаток и зафиксируйте его ЛКМ"
			)
		elif _is_pattern() and not _plan.has("error"):
			_hint.text = "Паттерн: %s · %d точек · глубина %d · %d vox" % [_stamp.display_name,_stamp_placements().size(),int(_stamp_depth.value),_plan.selected.size()]
		elif _stamp != null and not _plan.has("error"):
			_hint.text = (
				"%s: %s · %d точек · разброс %d%s%s · %d vox"
				% [
					"Вдавливание" if _stamp_mode.selected == 2 else "Россыпь",
					_stamp.display_name,_plan.placements.size(),int(_stamp_scatter_spread.value),
					" · %d форм" % _stamp_variant_count if _stamp_variant_count > 1 else "",
					" · облегание ≤%d" % int(_stamp_scatter_bend.value) if _stamp_scatter_conform.button_pressed else "",
					_plan.selected.size(),
				]
				if _stamp_application.selected == 3
				else "%s: %s · %d точек · %d vox" % ["Вдавливание" if _stamp_mode.selected == 2 else "Штамп",_stamp.display_name,_stamp_placements().size(),_plan.selected.size()]
			)
		_show_transform()
	var mouse: Vector2 = workspace._viewport_container.get_local_mouse_position()
	_hover.visible = not dragging and not _finish and not transforming and _surface_stage == 0 and Rect2(Vector2.ZERO,size).has_point(mouse)
	if _hover.visible:
		var pick: Dictionary = workspace._pick_at(mouse)
		_hover.visible = pick.has("hit") and workspace._cell_in_edit_region(pick.hit)
		if _hover.visible:
			var density := float(workspace._resource.normalized_density())
			_hover.position = Vector3(pick.hit)/density-Vector3.ONE*0.002/density
			_hover.scale = Vector3.ONE*1.004/density
	queue_redraw()

func _show_cells(indices: PackedInt32Array, color: Color) -> void:
	var cells: Array[Vector3] = []
	for index in indices:
		cells.append(Vector3(Selection.cell_of(index,workspace._resource.grid_size())))
	_show_positions(cells,color)

func _show_positions(cells: Array[Vector3], color: Color, colors := PackedColorArray()) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = not colors.is_empty()
	var mesh := BoxMesh.new()
	var density := float(workspace._resource.normalized_density())
	mesh.size = Vector3.ONE*1.01/density
	mesh.material = _material(color)
	mesh.material.vertex_color_use_as_albedo = not colors.is_empty()
	multi.mesh = mesh
	multi.instance_count = cells.size()
	for index in cells.size():
		multi.set_instance_transform(index,Transform3D(Basis.IDENTITY,(cells[index]+Vector3.ONE*0.5)/density))
		if not colors.is_empty():
			multi.set_instance_color(index,colors[index])
	_ghost.multimesh = multi
	_ghost.show()

func _show_transform() -> void:
	if _stamp != null:
		_show_stamp()
		return
	var low := workspace._resource.grid_size() as Vector3i
	var high := Vector3i.ZERO
	for index in _indices:
		var cell := Selection.cell_of(index,workspace._resource.grid_size())
		low = low.min(cell)
		high = high.max(cell)
	var cells: Array[Vector3] = []
	for index in _indices:
		var cell := Selection.cell_of(index,workspace._resource.grid_size())-low
		var extent := high-low+Vector3i.ONE
		for turn in _turns.selected:
			var transformed := Fragment.rotate_cell(cell,extent,_axis.selected)
			cell = transformed.cell
			extent = transformed.extent
		cells.append(Vector3(cell+low+_offset))
	_center = (Vector3(low+high)*0.5+Vector3(_offset)+Vector3.ONE*0.5)/workspace._resource.normalized_density()
	_show_positions(cells,Color(1,0.15,0.15,0.5) if _plan.has("error") else Color(0.1,1,1,0.5))

func _show_stamp() -> void:
	var cells: Array[Vector3] = []
	var colors := PackedColorArray()
	_center = (Vector3(_offset)+Vector3.ONE*0.5)/workspace._resource.normalized_density()
	if _plan.has("error"):
		cells.assign(_plan.get("positions",[]))
		_show_positions(cells,Color(1,0.15,0.15,0.5))
		return
	if _plan.get("removes",false):
		for index in _plan.selected:
			cells.append(Vector3(Selection.cell_of(index,workspace._resource.grid_size())))
		_show_positions(cells,Color(1.0,0.28,0.72,0.72))
		return
	var values: PackedByteArray = _plan.properties.get("voxels",workspace._resource.voxels)
	var palette: PackedColorArray = _plan.properties.get("palette",workspace._resource.palette)
	for index in _plan.selected:
		cells.append(Vector3(Selection.cell_of(index,workspace._resource.grid_size())))
		colors.append(palette[values[index]])
	_show_positions(cells,Color(1,1,1,0.8),colors)

func _screen(point: Vector3) -> Vector2:
	return workspace._camera.unproject_position(point)*workspace._viewport_container.size/Vector2(workspace._viewport.size)

func _ray(point: Vector2) -> Array[Vector3]:
	var pixel: Vector2 = point*Vector2(workspace._viewport.size)/workspace._viewport_container.size
	return [workspace._camera.project_ray_origin(pixel),workspace._camera.project_ray_normal(pixel)]

func _arrow(axis: int) -> PackedVector2Array:
	var unit := Vector3.ZERO
	unit[axis] = 1
	var start := _screen(_center)
	var direction := (_screen(_center+unit)-start).normalized()
	return PackedVector2Array([start+direction*16,start+direction*90])

func _draw() -> void:
	if dragging or _finish or _surface_stage == 2:
		var label := operation_hint()
		if _surface_stage == 1:
			label += " · 1/2 область"
		elif _surface_stage == 2:
			label += " · 2/2 глубина %d" % _depth
		var width := ThemeDB.fallback_font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x + 24
		draw_rect(Rect2(8,8,width,32),Color(0.04,0.08,0.12,0.95))
		draw_string(ThemeDB.fallback_font,Vector2(20,31),label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(0.3,1,1))
	if is_instance_valid(_hover) and _hover.visible:
		var box := AABB(Vector3.ZERO,Vector3.ONE)
		for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
			draw_line(_screen(_hover.transform*box.get_endpoint(edge[0])),_screen(_hover.transform*box.get_endpoint(edge[1])),Color(0.1,1,1),2,true)
	if (dragging or _finish or _surface_stage == 2) and _surface_marquee != null and _surface_bounds.has("box"):
		var box: AABB = _surface_bounds.box
		for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
			draw_line(_screen(box.get_endpoint(edge[0])),_screen(box.get_endpoint(edge[1])),Color(0.1,1,1),2,true)
	elif dragging or _finish:
		var rectangle := Rect2(_from,_to-_from).abs()
		draw_rect(rectangle,Color(0.1,0.9,1,0.12),true)
		draw_rect(rectangle,Color(0.1,1,1),false,2)
	if transforming and (_stamp == null or (_stamp_application.selected == 0 and _stamp_position_picked)):
		for axis in 3:
			var points := _arrow(axis)
			var color: Color = [Color(1,0.3,0.3),Color(0.3,1,0.4),Color(0.4,0.7,1)][axis]
			draw_line(points[0],points[1],color,4,true)
			var direction := (points[1]-points[0]).normalized()
			draw_colored_polygon(PackedVector2Array([points[1],points[1]-direction.rotated(0.5)*14,points[1]-direction.rotated(-0.5)*14]),color)
			draw_string(ThemeDB.fallback_font,points[1]+Vector2(5,-5),["X","Y","Z"][axis],HORIZONTAL_ALIGNMENT_LEFT,-1,18,color)

func _exit_tree() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	if is_instance_valid(_hover):
		_hover.queue_free()
