@tool
extends VBoxContainer
## Transient selection owner + bounded visualization. No saved schema or Undo stack.
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const DEFAULT_OVERLAY_COLOR := Color(1, 0.45, 0.05, 0.45)
signal activation_requested
signal transform_requested
signal extract_requested(cut: bool)
var _box_anchor := Vector3i(-1, -1, -1)
signal paint_requested(indices: PackedInt32Array)
signal selection_changed(has_selection: bool)
var active := false
var selected: Dictionary = {}
var _resource: EmberVoxelModelResource
var _region := Rect2i()
var _height := -1
var _toggle: Button
var _mode: OptionButton
var _through: OptionButton
var _depth: SpinBox
var _operation: OptionButton
var _tolerance: SpinBox
var _tolerance_row: HBoxContainer
var _status: Label
var _paint: Button
var _mask: CheckButton
var _mode_buttons: Array[Button] = []
var _through_buttons: Array[Button] = []
var _operation_buttons: Array[Button] = []
var _through_row: HBoxContainer
var _overlay: MultiMeshInstance3D
var _job: RefCounted
var _pending_operation := 0
var _drawing := false
var _draw_indices := PackedInt32Array()
var _draw_cursor := 0
var _applying := false
var _preserve_next_change := false
var _mask_kind := "none"
var _selected_columns: Dictionary = {}
var _overlay_color := DEFAULT_OVERLAY_COLOR


func _init() -> void:
	name = "VoxelSelectionPanel"
	_toggle = Button.new()
	_toggle.name = "VoxelSelectToggle"
	_toggle.text = "Выбирать воксели · V"
	_toggle.toggle_mode = true
	_toggle.theme_type_variation = &"WorkshopToolButton"
	_toggle.pressed.connect(func() -> void: activation_requested.emit())
	add_child(_toggle)
	_mode = _state_options(["Один воксель", "Связные похожего цвета", "Все похожего цвета", "Рамка · протяните мышью", "Рамка по поверхности"])
	_mode.item_selected.connect(_on_mode_selected)
	_mode.select(3)
	var method_label := Label.new()
	method_label.text = "СПОСОБ ВЫДЕЛЕНИЯ"
	method_label.modulate = Color(0.60, 0.72, 0.82)
	add_child(method_label)
	var method_group := ButtonGroup.new()
	method_group.allow_unpress = false
	var method_primary := HBoxContainer.new()
	method_primary.add_theme_constant_override("separation", 4)
	add_child(method_primary)
	_add_segment_buttons(method_primary, method_group, _mode, [0, 1, 2], ["Воксель", "Связные", "Цвет"], _mode_buttons)
	var method_area := HBoxContainer.new()
	method_area.add_theme_constant_override("separation", 4)
	add_child(method_area)
	_add_segment_buttons(method_area, method_group, _mode, [3, 4], ["Рамка", "Поверхность"], _mode_buttons)
	_through = _state_options(["Рамка: видимая поверхность", "Рамка: насквозь"])
	_through_row = HBoxContainer.new()
	_through_row.add_theme_constant_override("separation", 4)
	add_child(_through_row)
	var through_group := ButtonGroup.new()
	through_group.allow_unpress = false
	_add_segment_buttons(_through_row, through_group, _through, [0, 1], ["Видимые", "Насквозь"], _through_buttons)
	_depth = SpinBox.new()
	_depth.min_value = 1
	_depth.max_value = 256
	_depth.value = 1
	_depth.prefix = "Глубина внутрь · "
	_depth.suffix = "vox"
	_depth.tooltip_text = "Число слоёв внутрь от грани, с которой начат жест. Плоскость не огибает рельеф."
	add_child(_depth)
	_depth.hide()
	_operation = _state_options(["Новое выделение", "Добавить · Shift", "Вычесть · Ctrl"])
	_operation.tooltip_text = "Операция меняет только выделение, не геометрию. Зажмите Shift или Ctrl ДО начала протягивания; без клавиш используется режим этого списка."
	var operation_label := Label.new()
	operation_label.text = "ИЗМЕНЕНИЕ ВЫДЕЛЕНИЯ"
	operation_label.modulate = Color(0.60, 0.72, 0.82)
	add_child(operation_label)
	var operation_row := HBoxContainer.new()
	operation_row.add_theme_constant_override("separation", 4)
	add_child(operation_row)
	var operation_group := ButtonGroup.new()
	operation_group.allow_unpress = false
	_add_segment_buttons(operation_row, operation_group, _operation, [0, 1, 2], ["Новое", "+ Shift", "− Ctrl"], _operation_buttons)
	_tolerance_row = HBoxContainer.new()
	var label := Label.new()
	label.text = "Допуск цвета %"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tolerance_row.add_child(label)
	_tolerance = SpinBox.new()
	_tolerance.name = "VoxelSelectionTolerance"
	_tolerance.max_value = 100
	_tolerance.custom_minimum_size.x = 96.0
	_tolerance_row.add_child(_tolerance)
	add_child(_tolerance_row)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var primary_actions := HBoxContainer.new()
	primary_actions.add_theme_constant_override("separation", 5)
	add_child(primary_actions)
	_paint = Button.new()
	_paint.name = "VoxelSelectionPaint"
	_paint.text = "Окрасить"
	_paint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paint.pressed.connect(_request_paint)
	primary_actions.add_child(_paint)
	var transform_button := Button.new()
	transform_button.text = "Перенести…"
	transform_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transform_button.pressed.connect(func() -> void:
		if not busy() and not selected.is_empty():
			transform_requested.emit())
	primary_actions.add_child(transform_button)
	var extract_actions := HBoxContainer.new()
	extract_actions.add_theme_constant_override("separation", 5)
	add_child(extract_actions)
	for cutting in [true,false]:
		var extract := Button.new()
		extract.text = "Вырезать…" if cutting else "Копировать…"
		extract.tooltip_text = "Создать новый объект из выделения" if cutting else "Скопировать выделение в новый объект"
		extract.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		extract.pressed.connect(func() -> void:
			if not busy() and not selected.is_empty():
				extract_requested.emit(cutting))
		extract_actions.add_child(extract)
	var selection_actions := HBoxContainer.new()
	selection_actions.add_theme_constant_override("separation", 5)
	add_child(selection_actions)
	_mask = CheckButton.new()
	_mask.name = "VoxelSelectionMaskBrush"
	_mask.text = "Маска кисти"
	_mask.tooltip_text = "Точная маска для цвета; XZ-отпечаток для формы."
	_mask.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_actions.add_child(_mask)
	var clear := Button.new()
	clear.text = "Снять"
	clear.tooltip_text = "Очистить текущее выделение вокселей"
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear.pressed.connect(clear_selection)
	selection_actions.add_child(clear)
	_sync_segments()
	_on_mode_selected(_mode.selected)
	_update_status()


func _state_options(labels: Array) -> OptionButton:
	var option := OptionButton.new()
	for label in labels:
		option.add_item(str(label))
	option.hide()
	add_child(option)
	return option


func _add_segment_buttons(
	parent: HBoxContainer,
	group: ButtonGroup,
	option: OptionButton,
	indices: Array,
	labels: Array,
	buttons: Array[Button],
) -> void:
	for local_index in indices.size():
		var option_index := int(indices[local_index])
		var button := Button.new()
		button.text = str(labels[local_index])
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"WorkshopSegmentButton"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = option.get_item_text(option_index)
		button.pressed.connect(_select_segment.bind(option, option_index))
		parent.add_child(button)
		buttons.append(button)


func _select_segment(option: OptionButton, index: int) -> void:
	option.select(index)
	option.item_selected.emit(index)
	_sync_segments()


func _sync_option(option: OptionButton, buttons: Array[Button]) -> void:
	for button in buttons:
		button.set_pressed_no_signal(button.tooltip_text == option.get_item_text(option.selected))


func _sync_segments() -> void:
	_sync_option(_mode, _mode_buttons)
	_sync_option(_through, _through_buttons)
	_sync_option(_operation, _operation_buttons)


func _on_mode_selected(index: int) -> void:
	_box_anchor = Vector3i(-1, -1, -1)
	_depth.visible = index == 4
	_through_row.visible = index != 4
	_tolerance_row.visible = index in [1, 2]
	_sync_segments()


func sync(resource: EmberVoxelModelResource, region: Rect2i, height: int, surface: Node3D) -> void:
	if resource != _resource or region != _region or height != _height:
		if _resource != null and _resource.changed.is_connected(_on_source_changed):
			_resource.changed.disconnect(_on_source_changed)
		_resource = resource
		_region = region
		_height = height
		clear_selection()
		if _resource != null:
			_resource.changed.connect(_on_source_changed)
	if not is_instance_valid(_overlay) and is_instance_valid(surface):
		_overlay = MultiMeshInstance3D.new()
		_overlay.name = "VoxelSelectionOverlay"
		_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surface.add_child(_overlay)
	_toggle.disabled = resource == null


func set_active(value: bool) -> void:
	active = value and _resource != null
	_toggle.set_pressed_no_signal(active)
	if not active:
		cancel_search()


func busy() -> bool:
	return _job != null or _drawing


func set_tool_support(kind: String) -> void:
	_mask_kind = kind
	if kind == "none":
		_mask.set_pressed_no_signal(false)
	_update_status()


func mask_brushes_enabled() -> bool:
	return _mask.button_pressed and _mask_kind != "none" and not selected.is_empty()


func preserves_mask_after_commit() -> bool:
	return mask_brushes_enabled() and _mask_kind == "voxels"


func allows_brush_index(index: int) -> bool:
	if not mask_brushes_enabled():
		return true
	if _mask_kind == "voxels":
		return selected.has(index)
	if _resource == null or index < 0 or index >= _resource.voxels.size():
		return false
	var size := _resource.grid_size()
	var cell := Selection.cell_of(index, size)
	return _selected_columns.has(cell.x + cell.z * size.x)


func preserve_next_source_change() -> void:
	_preserve_next_change = true


func choose(seed: Vector3i, shift := false, control := false) -> void:
	if _resource == null or _drawing:
		return
	_overlay_color = DEFAULT_OVERLAY_COLOR
	_pending_operation = 2 if control else 1 if shift else _operation.selected
	if _mode.selected == 3:
		if _box_anchor.x < 0:
			_box_anchor = seed
			_update_status("Первый угол %s. Выберите противоположный угол объёма; Esc отменяет." % seed)
			return
		var low := _box_anchor.min(seed)
		var high := _box_anchor.max(seed)
		_box_anchor = Vector3i(-1,-1,-1)
		_job = Selection.new()
		_job.start_box(_resource, low, high, _region, _height)
		return
	_job = Selection.new()
	_job.start(_resource, seed, _mode.selected, _tolerance.value / 100.0, _region, _height)
	_update_status("Поиск… Esc отменяет; карта пока не меняется")


func _process(_delta: float) -> void:
	_sync_segments()
	var deadline := Time.get_ticks_usec() + 3000
	while _job != null and Time.get_ticks_usec() < deadline:
		_job.step(128)
		if _job.done:
			var message: String = _job.error
			if message.is_empty():
				var next := Selection.combine(selected, _job.indices, _pending_operation)
				if next.size() > Selection.LIMIT:
					message = "Лимит %d вокселей; прежнее выделение сохранено" % Selection.LIMIT
				else:
					selected = next
					_rebuild_selected_columns()
					_begin_overlay()
					selection_changed.emit(not selected.is_empty())
			_job = null
			_update_status(message)
	while _drawing and Time.get_ticks_usec() < deadline:
		_draw_one()
	if not busy():
		_paint.disabled = selected.is_empty()


func cancel_search() -> void:
	_box_anchor = Vector3i(-1,-1,-1)
	_job = null
	_update_status()


func clear_selection() -> void:
	_box_anchor = Vector3i(-1,-1,-1)
	_job = null
	_drawing = false
	selected.clear()
	_selected_columns.clear()
	_draw_indices.clear()
	if is_instance_valid(_overlay):
		_overlay.multimesh = null
	_mask.set_pressed_no_signal(false)
	_update_status()
	selection_changed.emit(false)


func set_selection(indices: PackedInt32Array, color := DEFAULT_OVERLAY_COLOR) -> void:
	_overlay_color = color
	_overlay_color.a = 0.45
	selected.clear()
	for index in indices:
		selected[int(index)] = true
	_rebuild_selected_columns()
	_begin_overlay()
	_update_status()
	selection_changed.emit(not selected.is_empty())


func selection_indices() -> PackedInt32Array:
	var result := PackedInt32Array(selected.keys())
	result.sort()
	return result


func _on_source_changed() -> void:
	if _preserve_next_change:
		_preserve_next_change = false
	elif not _applying:
		clear_selection() # Undo/brush/palette edits cannot leave a stale mask.


func _request_paint() -> void:
	if busy() or selected.is_empty():
		return
	_applying = true
	paint_requested.emit(PackedInt32Array(selected.keys()))
	_applying = false


func _begin_overlay() -> void:
	_draw_indices = PackedInt32Array(selected.keys())
	_draw_cursor = 0
	_drawing = not _draw_indices.is_empty()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * (1.006 / _resource.normalized_density())
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = _overlay_color
	material.no_depth_test = true
	mesh.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = _draw_indices.size()
	multi.visible_instance_count = 0
	_overlay.multimesh = multi


func _draw_one() -> void:
	var cell := Selection.cell_of(_draw_indices[_draw_cursor], _resource.grid_size())
	var at := (Vector3(cell) + Vector3.ONE * 0.5) / _resource.normalized_density()
	_overlay.multimesh.set_instance_transform(_draw_cursor, Transform3D(Basis.IDENTITY, at))
	_draw_cursor += 1
	if _draw_cursor >= _draw_indices.size():
		_drawing = false
		_overlay.multimesh.visible_instance_count = _draw_cursor
		_update_status()


func _update_status(message := "") -> void:
	_status.text = message if not message.is_empty() else "Выделено: %d vox%s" % [selected.size(), " · подсветка…" if _drawing else ""]
	_paint.disabled = busy() or selected.is_empty()
	_mask.disabled = selected.is_empty() or _mask_kind == "none"
	if _mask_kind == "voxels":
		_mask.text = "Маска кисти"
		_mask.tooltip_text = "Цвет или материал меняются только на точных индексах выделения; после мазка маска остаётся."
	elif _mask_kind == "columns":
		_mask.text = "Маска кисти"
		_mask.tooltip_text = "Форма меняется лишь в вертикальном XZ-отпечатке выделения; после успешного мазка устаревшая маска очищается."
	else:
		_mask.text = "Маска кисти"
		_mask.tooltip_text = "Заливка уровня работает с замкнутым водоёмом, а не с voxel-маской."


func _rebuild_selected_columns() -> void:
	_selected_columns.clear()
	if _resource == null:
		return
	var size := _resource.grid_size()
	for raw_index in selected:
		var cell := Selection.cell_of(int(raw_index), size)
		_selected_columns[cell.x + cell.z * size.x] = true


func _exit_tree() -> void:
	_job = null
	if _resource != null and _resource.changed.is_connected(_on_source_changed):
		_resource.changed.disconnect(_on_source_changed)
	if is_instance_valid(_overlay):
		_overlay.queue_free()
