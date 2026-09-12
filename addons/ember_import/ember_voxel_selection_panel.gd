@tool
extends VBoxContainer
## Transient selection + independent brush-mask snapshot. No saved schema or Undo stack.
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
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
var _mask_outline: MeshInstance3D
var _history_actions: Object
var _job: RefCounted
var _pending_operation := 0
var _pending_normal := Vector3i.UP
var _pending_history_state: Dictionary = {}
var _drawing := false
var _draw_indices := PackedInt32Array()
var _draw_cursor := 0
var _applying := false
var _applying_history := false
var _preserve_next_change := false
var _clear_selected_after_next_change := false
var _mask_kind := "none"
var _mask_suspended := false
var _selection_overlay_suspended := false
var _selection_normal := Vector3i.UP
var _selected_footprint: Dictionary = {}
var _mask_indices: Dictionary = {}
var _mask_normal := Vector3i.UP
var _mask_footprint: Dictionary = {}
var _mask_depths: Dictionary = {}
var _mask_grid_size := Vector3i.ZERO
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
	_mode = _state_options(["Один воксель", "Связные похожего цвета", "Все похожего цвета", "Рамка · протяните мышью", "Двухэтапное выделение"])
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
	_add_segment_buttons(method_area, method_group, _mode, [3, 4], ["Рамка", "Два этапа"], _mode_buttons)
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
	_depth.prefix = "Этап 2 · внутрь "
	_depth.suffix = " vox"
	_depth.tooltip_text = "После рамки двигайте мышь поперёк начальной грани или задайте точное число слоёв. Второй клик либо Enter подтверждает."
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
	_mask.tooltip_text = "Точная маска для цвета; плоскость первой грани для формы."
	_mask.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mask.toggled.connect(_on_mask_toggled)
	selection_actions.add_child(_mask)
	var clear := Button.new()
	clear.text = "Снять"
	clear.tooltip_text = "Очистить текущее выделение и снимок маски кисти"
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear.pressed.connect(func() -> void: clear_selection(true))
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


func configure_history(actions: Object) -> void:
	_history_actions = actions


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
		clear_selection(false)
		if _resource != null:
			_resource.changed.connect(_on_source_changed)
	if not is_instance_valid(_overlay) and is_instance_valid(surface):
		_overlay = MultiMeshInstance3D.new()
		_overlay.name = "VoxelSelectionOverlay"
		_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surface.add_child(_overlay)
	if not is_instance_valid(_mask_outline) and is_instance_valid(surface):
		_mask_outline = MeshInstance3D.new()
		_mask_outline.name = "VoxelSelectionMaskOutline"
		_mask_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		surface.add_child(_mask_outline)
	_toggle.disabled = resource == null
	_update_overlay_visibility()


func set_active(value: bool) -> void:
	active = value and _resource != null
	_toggle.set_pressed_no_signal(active)
	if not active:
		cancel_search()
	_update_overlay_visibility()


func busy() -> bool:
	return _job != null or _drawing


func set_tool_support(kind: String) -> void:
	_mask_kind = kind
	_rebuild_mask_outline()
	_update_status()
	_update_overlay_visibility()


func set_mask_suspended(value: bool) -> void:
	_mask_suspended = value
	_update_status()
	_update_overlay_visibility()


func set_selection_overlay_suspended(value: bool) -> void:
	_selection_overlay_suspended = value
	_update_overlay_visibility()


func has_saved_mask() -> bool:
	return _mask.button_pressed and _has_mask_snapshot()


func mask_is_suspended() -> bool:
	return _mask_suspended and has_saved_mask()


func mask_brushes_enabled() -> bool:
	if _mask_suspended or not _mask.button_pressed or _mask_kind == "none":
		return false
	return not (_mask_indices if _mask_kind == "voxels" else _mask_footprint).is_empty()


func preserves_mask_after_commit() -> bool:
	return mask_brushes_enabled()


func allows_brush_index(index: int) -> bool:
	if not mask_brushes_enabled():
		return true
	if _mask_kind == "voxels":
		return _mask_indices.has(index)
	if _resource == null or index < 0 or index >= _resource.voxels.size():
		return false
	var size := _resource.grid_size()
	var cell := Selection.cell_of(index, size)
	return _mask_footprint.has(_plane_key(cell, _normal_axis(_mask_normal)))


func preserve_next_source_change(clear_transient_selection := false) -> void:
	_preserve_next_change = true
	_clear_selected_after_next_change = clear_transient_selection


func choose(
	seed: Vector3i,
	shift := false,
	control := false,
	normal := Vector3i.UP,
) -> void:
	if _resource == null or _drawing:
		return
	_overlay_color = DEFAULT_OVERLAY_COLOR
	_pending_operation = 2 if control else 1 if shift else _operation.selected
	_pending_normal = (
		Model.axis_normal(normal)
		if _pending_operation == 0 or selected.is_empty()
		else _selection_normal
	)
	_pending_history_state = history_state()
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
					_selection_normal = _pending_normal
					_rebuild_selected_footprint()
					_on_selection_updated()
					_begin_overlay()
					selection_changed.emit(not selected.is_empty())
					_record_history(_pending_history_state, "Voxel Surface · изменить маску")
			_job = null
			_pending_history_state = {}
			_update_status(message)
	while _drawing and Time.get_ticks_usec() < deadline:
		_draw_one()
	if not busy():
		_paint.disabled = selected.is_empty()


func cancel_search() -> void:
	_box_anchor = Vector3i(-1,-1,-1)
	_job = null
	_pending_history_state = {}
	_update_status()


func clear_selection(record_history := false) -> void:
	var before := history_state() if record_history else {}
	_clear_selected_only()
	_clear_mask_snapshot()
	_update_status()
	_update_overlay_visibility()
	if record_history:
		_record_history(before, "Voxel Surface · снять маску")


func _clear_selected_only() -> void:
	_box_anchor = Vector3i(-1,-1,-1)
	_job = null
	_drawing = false
	selected.clear()
	_selected_footprint.clear()
	_draw_indices.clear()
	if is_instance_valid(_overlay):
		_overlay.multimesh = null
	selection_changed.emit(false)


func set_selection(
	indices: PackedInt32Array,
	color := DEFAULT_OVERLAY_COLOR,
	normal := Vector3i.ZERO,
	record_history := false,
) -> void:
	var before := history_state() if record_history else {}
	_overlay_color = color
	_overlay_color.a = 0.45
	if normal != Vector3i.ZERO:
		_selection_normal = Model.axis_normal(normal)
	selected.clear()
	for index in indices:
		selected[int(index)] = true
	_rebuild_selected_footprint()
	_on_selection_updated()
	_begin_overlay()
	_update_status()
	selection_changed.emit(not selected.is_empty())
	if record_history:
		_record_history(before, "Voxel Surface · изменить маску")


func selection_indices() -> PackedInt32Array:
	var result := PackedInt32Array(selected.keys())
	result.sort()
	return result


func _on_source_changed() -> void:
	var preserve_selection := _preserve_next_change
	var clear_selected := _clear_selected_after_next_change
	_preserve_next_change = false
	_clear_selected_after_next_change = false
	if _applying:
		_rebuild_mask_outline()
		_update_overlay_visibility()
		return
	if _has_mask_snapshot():
		if _resource == null or _resource.grid_size() != _mask_grid_size:
			clear_selection()
			return
		# Geometry/Undo may stale exact selected indices, but the editor-only mask
		# remains useful. Column contours are rebuilt against the current surface.
		if clear_selected or not preserve_selection:
			_clear_selected_only()
		_rebuild_mask_outline()
		_update_status()
		_update_overlay_visibility()
		return
	if not preserve_selection:
		clear_selection()


func _request_paint() -> void:
	if busy() or selected.is_empty():
		return
	_applying = true
	paint_requested.emit(PackedInt32Array(selected.keys()))
	_applying = false


func _begin_overlay() -> void:
	if _resource == null or not is_instance_valid(_overlay):
		return
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
	_update_overlay_visibility()


func _draw_one() -> void:
	var cell := Selection.cell_of(_draw_indices[_draw_cursor], _resource.grid_size())
	var at := (Vector3(cell) + Vector3.ONE * 0.5) / _resource.normalized_density()
	_overlay.multimesh.set_instance_transform(_draw_cursor, Transform3D(Basis.IDENTITY, at))
	_draw_cursor += 1
	if _draw_cursor >= _draw_indices.size():
		_drawing = false
		_overlay.multimesh.visible_instance_count = _draw_cursor
		_update_status()
		_update_overlay_visibility()


func _update_status(message := "") -> void:
	if not message.is_empty():
		_status.text = message
	elif _mask.button_pressed and _has_mask_snapshot():
		if _mask_suspended or _mask_kind == "none":
			_status.text = "Маска сохранена · не действует в текущем режиме"
		else:
			var mask_count := _mask_footprint.size() if _mask_kind == "columns" else _mask_indices.size()
			var unit := "ячеек" if _mask_kind == "columns" else "vox"
			_status.text = "Маска · %s · %s · %d %s%s" % [
				_plane_label(_mask_normal), _normal_label(_mask_normal), mask_count, unit,
				" · подсветка…" if _drawing else "",
			]
	else:
		_status.text = "Выделено: %d vox%s" % [selected.size(), " · подсветка…" if _drawing else ""]
	_paint.disabled = busy() or selected.is_empty()
	_mask.disabled = (_mask_kind == "none") or (selected.is_empty() and not _has_mask_snapshot())
	if _mask_kind == "voxels":
		_mask.text = "Маска кисти"
		_mask.tooltip_text = "Цвет или материал меняются только на точных индексах выделения; после мазка маска остаётся."
	elif _mask_kind == "columns":
		_mask.text = "Маска кисти"
		_mask.tooltip_text = "Форма меняется только в отпечатке первой грани; эта грань также фиксирует направление объёмной кисти."
	else:
		_mask.text = "Маска кисти"
		_mask.tooltip_text = "Маска сохранена, но текущий инструмент её не использует."


func _rebuild_selected_footprint() -> void:
	_selected_footprint.clear()
	if _resource == null:
		return
	var size := _resource.grid_size()
	var axis := _normal_axis(_selection_normal)
	for raw_index in selected:
		var cell := Selection.cell_of(int(raw_index), size)
		_selected_footprint[_plane_key(cell, axis)] = true


func _on_selection_updated() -> void:
	if _mask.button_pressed:
		_capture_mask_from_selection()
	elif _has_mask_snapshot():
		# An explicitly edited selection replaces a disabled old snapshot too.
		_clear_mask_snapshot(false)


func _on_mask_toggled(enabled: bool) -> void:
	var before := history_state()
	before["mask_enabled"] = not enabled
	if enabled and not _has_mask_snapshot():
		_capture_mask_from_selection()
	if enabled and not _has_mask_snapshot():
		_mask.set_pressed_no_signal(false)
	_rebuild_mask_outline()
	_update_status()
	_update_overlay_visibility()
	if not _applying_history:
		_record_history(before, "Voxel Surface · %s маску" % ("включить" if enabled else "выключить"))


func _capture_mask_from_selection() -> void:
	if selected.is_empty():
		_clear_mask_snapshot()
		return
	_mask_indices = selected.duplicate()
	_mask_normal = _selection_normal
	_rebuild_mask_footprint()
	_rebuild_mask_outline()


func _clear_mask_snapshot(unpress := true) -> void:
	_mask_indices.clear()
	_mask_footprint.clear()
	_mask_depths.clear()
	_mask_normal = Vector3i.UP
	_mask_grid_size = Vector3i.ZERO
	if unpress:
		_mask.set_pressed_no_signal(false)
	if is_instance_valid(_mask_outline):
		_mask_outline.mesh = null


func _has_mask_snapshot() -> bool:
	return not _mask_indices.is_empty() or not _mask_footprint.is_empty()


func selection_normal() -> Vector3i:
	return _selection_normal


func mask_normal() -> Vector3i:
	return _mask_normal


func history_state() -> Dictionary:
	var mask_indices := PackedInt32Array(_mask_indices.keys())
	mask_indices.sort()
	return {
		"selected": selection_indices(),
		"selection_normal": _selection_normal,
		"mask_indices": mask_indices,
		"mask_normal": _mask_normal,
		"mask_enabled": _mask.button_pressed,
		"overlay_color": _overlay_color,
		"grid_size": _resource.grid_size() if _resource != null else Vector3i.ZERO,
	}


func apply_history_state(state: Dictionary) -> void:
	if _resource == null or state.get("grid_size", Vector3i.ZERO) != _resource.grid_size():
		return
	_applying_history = true
	_box_anchor = Vector3i(-1, -1, -1)
	_job = null
	_pending_history_state = {}
	_drawing = false
	_draw_indices.clear()
	selected.clear()
	var size := _resource.grid_size()
	for raw_index in state.get("selected", PackedInt32Array()):
		var index := int(raw_index)
		if index >= 0 and index < _resource.voxels.size():
			selected[index] = true
	_selection_normal = Model.axis_normal(state.get("selection_normal", Vector3i.UP) as Vector3i)
	_overlay_color = state.get("overlay_color", DEFAULT_OVERLAY_COLOR)
	_rebuild_selected_footprint()
	_mask_indices.clear()
	for raw_index in state.get("mask_indices", PackedInt32Array()):
		var index := int(raw_index)
		if index >= 0 and index < _resource.voxels.size():
			_mask_indices[index] = true
	_mask_normal = Model.axis_normal(state.get("mask_normal", Vector3i.UP) as Vector3i)
	_rebuild_mask_footprint()
	_mask.set_pressed_no_signal(bool(state.get("mask_enabled", false)) and _has_mask_snapshot())
	if selected.is_empty():
		if is_instance_valid(_overlay):
			_overlay.multimesh = null
	else:
		_begin_overlay()
	_rebuild_mask_outline()
	_update_status()
	_update_overlay_visibility()
	selection_changed.emit(not selected.is_empty())
	_applying_history = false


func _record_history(before: Dictionary, title: String) -> void:
	if _applying_history or _history_actions == null or _resource == null or before.is_empty():
		return
	_history_actions.call(
		"record_editor_state", _resource, self, before, history_state(), title
	)


func _rebuild_mask_footprint() -> void:
	_mask_footprint.clear()
	_mask_depths.clear()
	_mask_grid_size = Vector3i.ZERO
	if _resource == null or _mask_indices.is_empty():
		return
	var size := _resource.grid_size()
	_mask_grid_size = size
	var axis := _normal_axis(_mask_normal)
	for raw_index in _mask_indices:
		var index := int(raw_index)
		if index < 0 or index >= _resource.voxels.size():
			continue
		var cell := Selection.cell_of(index, size)
		var key := _plane_key(cell, axis)
		_mask_footprint[key] = true
		var fallback := size[axis] if _mask_normal[axis] < 0 else -1
		var previous := int(_mask_depths.get(key, fallback))
		_mask_depths[key] = (
			maxi(previous, cell[axis])
			if _mask_normal[axis] > 0
			else mini(previous, cell[axis])
		)


func _normal_axis(normal: Vector3i) -> int:
	if normal.x != 0:
		return 0
	if normal.y != 0:
		return 1
	return 2


func _plane_key(cell: Vector3i, axis: int) -> Vector2i:
	if axis == 0:
		return Vector2i(cell.y, cell.z)
	if axis == 1:
		return Vector2i(cell.x, cell.z)
	return Vector2i(cell.x, cell.y)


func _cell_from_plane(key: Vector2i, depth: int, axis: int) -> Vector3i:
	if axis == 0:
		return Vector3i(depth, key.x, key.y)
	if axis == 1:
		return Vector3i(key.x, depth, key.y)
	return Vector3i(key.x, key.y, depth)


func _plane_label(normal: Vector3i) -> String:
	return ["YZ", "XZ", "XY"][_normal_axis(normal)]


func _normal_label(normal: Vector3i) -> String:
	var axis := _normal_axis(normal)
	return "%s%s" % ["+" if normal[axis] >= 0 else "−", ["X", "Y", "Z"][axis]]


func _scan_bounds(size: Vector3i) -> Array[Vector3i]:
	var low := Vector3i.ZERO
	var high := size
	high.y = size.y if _height < 0 else clampi(_height, 0, size.y)
	if _region.has_area():
		var density := _resource.normalized_density()
		low.x = clampi(_region.position.x * density, 0, size.x)
		low.z = clampi(_region.position.y * density, 0, size.z)
		high.x = clampi(_region.end.x * density, low.x, size.x)
		high.z = clampi(_region.end.y * density, low.z, size.z)
	return [low, high]


func _update_overlay_visibility() -> void:
	var show_mask_outline := (
		not active
		and not _mask_suspended
		and _mask_kind != "none"
		and _mask.button_pressed
		and _has_mask_snapshot()
		and is_instance_valid(_mask_outline)
		and _mask_outline.mesh != null
	)
	if is_instance_valid(_overlay):
		_overlay.visible = (
			_overlay.multimesh != null
			and active
			and not _selection_overlay_suspended
		)
	if is_instance_valid(_mask_outline):
		_mask_outline.visible = show_mask_outline


func _rebuild_mask_outline() -> void:
	if not is_instance_valid(_mask_outline):
		return
	_mask_outline.mesh = null
	if _resource == null or not _has_mask_snapshot():
		return
	var size := _resource.grid_size()
	if _resource.voxels.size() != size.x * size.y * size.z:
		return
	var cells: Array[Vector3i] = []
	var columns := _mask_kind == "columns"
	if columns:
		var axis := _normal_axis(_mask_normal)
		var bounds := _scan_bounds(size)
		var low: Vector3i = bounds[0]
		var high: Vector3i = bounds[1]
		for raw_key in _mask_footprint:
			var key := raw_key as Vector2i
			cells.append(_mask_surface_cell(key, axis, low, high, size))
	else:
		for raw_index in _mask_indices:
			var index := int(raw_index)
			if index >= 0 and index < _resource.voxels.size() and _resource.voxels[index] != 0:
				cells.append(Selection.cell_of(index, size))
	if cells.is_empty():
		return
	var edges: Dictionary = {}
	for cell in cells:
		var normals: Array[Vector3i] = []
		if columns:
			normals.append(_mask_normal)
		else:
			normals.assign([
				Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP,
				Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK,
			])
		for normal in normals:
			var neighbor := cell + normal
			if not columns and _inside_grid(neighbor, size) and _resource.voxels[_index_of(neighbor, size)] != 0:
				continue
			_add_face_outline_edges(edges, cell, normal)
	if edges.is_empty():
		return
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.63, 0.12, 0.96)
	var density := float(_resource.normalized_density())
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for edge in edges.values():
		var offset: Vector3 = Vector3(edge[2]) * (0.025 / density)
		immediate.surface_add_vertex(Vector3(edge[0]) / density + offset)
		immediate.surface_add_vertex(Vector3(edge[1]) / density + offset)
	immediate.surface_end()
	_mask_outline.mesh = immediate


func _mask_surface_cell(
	key: Vector2i,
	axis: int,
	low: Vector3i,
	high: Vector3i,
	size: Vector3i,
) -> Vector3i:
	var fallback := clampi(
		int(_mask_depths.get(key, low[axis])),
		low[axis], maxi(low[axis], high[axis] - 1),
	)
	var outward := 1 if _mask_normal[axis] > 0 else -1
	var baseline := _cell_from_plane(key, fallback, axis)
	if _resource.voxels[_index_of(baseline, size)] != 0:
		var result := baseline
		var depth := fallback + outward
		while depth >= low[axis] and depth < high[axis]:
			var next := _cell_from_plane(key, depth, axis)
			if _resource.voxels[_index_of(next, size)] == 0:
				break
			result = next
			depth += outward
		return result
	var depth := fallback - outward
	while depth >= low[axis] and depth < high[axis]:
		var inward := _cell_from_plane(key, depth, axis)
		if _resource.voxels[_index_of(inward, size)] != 0:
			return inward
		depth -= outward
	return baseline


func _add_face_outline_edges(edges: Dictionary, cell: Vector3i, normal: Vector3i) -> void:
	var origin := cell
	var tangent_a: Vector3i
	var tangent_b: Vector3i
	if normal.x != 0:
		if normal.x > 0:
			origin.x += 1
		tangent_a = Vector3i.UP
		tangent_b = Vector3i.BACK
	elif normal.y != 0:
		if normal.y > 0:
			origin.y += 1
		tangent_a = Vector3i.RIGHT
		tangent_b = Vector3i.BACK
	else:
		if normal.z > 0:
			origin.z += 1
		tangent_a = Vector3i.RIGHT
		tangent_b = Vector3i.UP
	var corners: Array[Vector3i] = [origin, origin + tangent_a, origin + tangent_a + tangent_b, origin + tangent_b]
	for edge_index in 4:
		_toggle_outline_edge(edges, corners[edge_index], corners[(edge_index + 1) % 4], normal)


func _toggle_outline_edge(edges: Dictionary, a: Vector3i, b: Vector3i, normal: Vector3i) -> void:
	var first := a
	var second := b
	if _vector3i_less(second, first):
		first = b
		second = a
	var key := "%d,%d,%d|%d,%d,%d|%d,%d,%d" % [
		normal.x, normal.y, normal.z,
		first.x, first.y, first.z,
		second.x, second.y, second.z,
	]
	if edges.has(key):
		edges.erase(key)
	else:
		edges[key] = [first, second, normal]


func _vector3i_less(a: Vector3i, b: Vector3i) -> bool:
	return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))


func _inside_grid(cell: Vector3i, size: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < size.x and cell.y < size.y and cell.z < size.z


func _index_of(cell: Vector3i, size: Vector3i) -> int:
	return cell.x + cell.z * size.x + cell.y * size.x * size.z


func _exit_tree() -> void:
	_job = null
	if _resource != null and _resource.changed.is_connected(_on_source_changed):
		_resource.changed.disconnect(_on_source_changed)
	if is_instance_valid(_overlay):
		_overlay.queue_free()
	if is_instance_valid(_mask_outline):
		_mask_outline.queue_free()
