@tool
class_name EmberBattlefieldInspectorPanel
extends VBoxContainer
## Compact visual summary/validation for the canonical battlefield Resource.

const COLOR_NEUTRAL := Color("34445e")
const COLOR_WET := Color("23708e")
const COLOR_EMBER := Color("a65e39")
const COLOR_FROZEN := Color("6ca8d9")
const COLOR_BLOCKED := Color("3d3946")
const Palette := preload("res://addons/ember_import/ember_battlefield_editor_palette.gd")

var _field: EmberBattlefieldResource
var _summary: Label
var _grid: GridContainer
var _diagnostics: Label
var _brush: OptionButton
var _group_id: LineEdit
var _paint_callback: Callable
var _resize_callback: Callable
var _water_sync_callback: Callable
var _height_sync_callback: Callable
var _water_threshold: OptionButton
var _water_sync_report: Label
var _water_sync_apply: Button
var _height_sync_report: Label
var _height_sync_apply: Button
var _connected_surface: EmberVoxelModelResource
var _resize_width: SpinBox
var _resize_height: SpinBox
var _resize_anchor: OptionButton
var _resize_report: Label
var _resize_apply: Button


func setup(
	field: EmberBattlefieldResource,
	paint_callback: Callable = Callable(),
	resize_callback: Callable = Callable(),
	water_sync_callback: Callable = Callable(),
	height_sync_callback: Callable = Callable(),
) -> void:
	_field = field
	_paint_callback = paint_callback
	_resize_callback = resize_callback
	_water_sync_callback = water_sync_callback
	_height_sync_callback = height_sync_callback
	name = "BattlefieldInspectorSummary"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "ПРЕДПРОСМОТР ПОЛЯ БОЯ"
	title.modulate = Color("e2b85b")
	add_child(title)

	_summary = Label.new()
	_summary.name = "BattlefieldSummary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)

	var water_title := Label.new()
	water_title.text = "VISUAL SURFACE → ПРАВИЛА ВОДЫ"
	water_title.modulate = Color("62d7e6")
	add_child(water_title)
	var water_hint := Label.new()
	water_hint.text = (
		"Считает покрытие водой внутри каждой крупной клетки и предлагает Wet. "
		+ "Правила боя изменятся только после применения. Ember/Frozen не перезаписываются."
	)
	water_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	water_hint.modulate = Color(0.67, 0.72, 0.8)
	add_child(water_hint)
	var water_row := HBoxContainer.new()
	water_row.name = "BattlefieldWaterSyncControls"
	add_child(water_row)
	_water_threshold = OptionButton.new()
	_water_threshold.name = "BattlefieldWaterCoverage"
	_water_threshold.tooltip_text = "Минимальная часть art-вокселей с водой, чтобы вся боевая клетка стала Wet."
	for entry in [["Покрытие ≥ 10%", 0.10], ["Покрытие ≥ 25%", 0.25], ["Покрытие ≥ 50%", 0.50]]:
		_water_threshold.add_item(str(entry[0]))
		_water_threshold.set_item_metadata(_water_threshold.item_count - 1, float(entry[1]))
	_water_threshold.select(1)
	_water_threshold.item_selected.connect(_update_water_sync_preview.unbind(1))
	water_row.add_child(_water_threshold)
	_water_sync_apply = Button.new()
	_water_sync_apply.name = "BattlefieldWaterSyncApply"
	_water_sync_apply.text = "Синхронизировать Wet"
	_water_sync_apply.tooltip_text = "Одна Undo-операция меняет только тип и группу затронутых клеток."
	_water_sync_apply.pressed.connect(_apply_water_sync)
	_water_sync_apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	water_row.add_child(_water_sync_apply)
	_water_sync_report = Label.new()
	_water_sync_report.name = "BattlefieldWaterSyncPreview"
	_water_sync_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_water_sync_report)

	var height_title := Label.new()
	height_title.text = "VISUAL SURFACE → ВЫСОТЫ БОЯ"
	height_title.modulate = Color("b9d779")
	add_child(height_title)
	var height_hint := Label.new()
	height_hint.text = (
		"Берёт медианную высоту пола по равномерным точкам внутри каждой крупной клетки и переводит "
		+ "каждые 14 art-вокселей в один тактический уровень. Камушки и мелкие сколы игнорируются."
	)
	height_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	height_hint.modulate = Color(0.67, 0.72, 0.8)
	add_child(height_hint)
	_height_sync_report = Label.new()
	_height_sync_report.name = "BattlefieldHeightSyncPreview"
	_height_sync_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_height_sync_report)
	_height_sync_apply = Button.new()
	_height_sync_apply.name = "BattlefieldHeightSyncApply"
	_height_sync_apply.text = "Синхронизировать высоты"
	_height_sync_apply.tooltip_text = "Одна Undo-операция меняет только canonical elevations поля боя."
	_height_sync_apply.pressed.connect(_apply_height_sync)
	add_child(_height_sync_apply)

	var tools := HBoxContainer.new()
	tools.name = "BattlefieldPaintToolbar"
	add_child(tools)
	_brush = OptionButton.new()
	_brush.name = "BattlefieldBrush"
	Palette.populate(_brush)
	_brush.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(_brush)
	_group_id = LineEdit.new()
	_group_id.name = "BattlefieldPaintGroup"
	_group_id.placeholder_text = "Группа (авто)"
	_group_id.tooltip_text = "Связывает панели общим эффектом. Пусто: Wet → tide, Ember → ember."
	_group_id.custom_minimum_size.x = 116.0
	tools.add_child(_group_id)

	var resize_separator := HSeparator.new()
	add_child(resize_separator)
	var resize_title := Label.new()
	resize_title.text = "РАЗМЕР И ПЕРЕНОС"
	resize_title.modulate = Color("e2b85b")
	add_child(resize_title)
	var resize_hint := Label.new()
	resize_hint.text = "Якорь фиксирует выбранную сторону старого поля. До применения показаны обрезанные клетки и точки."
	resize_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resize_hint.modulate = Color(0.67, 0.72, 0.8)
	add_child(resize_hint)
	var resize_row := HBoxContainer.new()
	resize_row.name = "BattlefieldResizeControls"
	add_child(resize_row)
	_resize_width = _make_dimension_spin("Ширина", field.width)
	resize_row.add_child(_resize_width)
	_resize_height = _make_dimension_spin("Глубина", field.height)
	resize_row.add_child(_resize_height)
	_resize_anchor = OptionButton.new()
	_resize_anchor.name = "BattlefieldResizeAnchor"
	_resize_anchor.tooltip_text = "Какая часть старого поля останется зафиксирована при изменении размера."
	for entry in [
		["↖ Верх-лево", EmberBattlefieldResource.ResizeAnchor.TOP_LEFT],
		["↑ Верх", EmberBattlefieldResource.ResizeAnchor.TOP_CENTER],
		["↗ Верх-право", EmberBattlefieldResource.ResizeAnchor.TOP_RIGHT],
		["← Слева", EmberBattlefieldResource.ResizeAnchor.MIDDLE_LEFT],
		["● Центр", EmberBattlefieldResource.ResizeAnchor.CENTER],
		["→ Справа", EmberBattlefieldResource.ResizeAnchor.MIDDLE_RIGHT],
		["↙ Низ-лево", EmberBattlefieldResource.ResizeAnchor.BOTTOM_LEFT],
		["↓ Низ", EmberBattlefieldResource.ResizeAnchor.BOTTOM_CENTER],
		["↘ Низ-право", EmberBattlefieldResource.ResizeAnchor.BOTTOM_RIGHT],
	]:
		_resize_anchor.add_item(str(entry[0]))
		_resize_anchor.set_item_metadata(_resize_anchor.item_count - 1, int(entry[1]))
	_resize_anchor.select(EmberBattlefieldResource.ResizeAnchor.CENTER)
	_resize_anchor.item_selected.connect(_update_resize_preview.unbind(1))
	resize_row.add_child(_resize_anchor)
	_resize_report = Label.new()
	_resize_report.name = "BattlefieldResizePreview"
	_resize_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_resize_report)
	_resize_apply = Button.new()
	_resize_apply.name = "BattlefieldResizeApply"
	_resize_apply.text = "Применить размер"
	_resize_apply.tooltip_text = "Одно действие Undo переносит клетки, фокус и точки расстановки."
	_resize_apply.pressed.connect(_apply_resize)
	add_child(_resize_apply)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(center)
	_grid = GridContainer.new()
	_grid.name = "BattlefieldCellPreview"
	center.add_child(_grid)

	_diagnostics = Label.new()
	_diagnostics.name = "BattlefieldDiagnostics"
	_diagnostics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_diagnostics)

	var hint := Label.new()
	hint.text = "Выберите кисть и нажимайте ЛКМ по клеткам. Ctrl+Z/Ctrl+Shift+Z работают штатно; Ctrl+S сохраняет .tres."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.67, 0.72, 0.8)
	add_child(hint)

	if not _field.changed.is_connected(_refresh):
		_field.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_field) or not is_instance_valid(_grid):
		return
	_summary.text = "%s · %dx%d · %d клеток\nWet %d · Ember %d · Frozen %d" % [
		_field.display_name,
		_field.width,
		_field.height,
		_field.cell_count(),
		_field.terrain_count(EmberBattlefieldResource.TerrainKind.WET),
		_field.terrain_count(EmberBattlefieldResource.TerrainKind.EMBER),
		_field.terrain_count(EmberBattlefieldResource.TerrainKind.FROZEN),
	]
	_summary.text += "\nТочки: герои %d · враги %d" % [
		_field.party_deployment_cells.size(), _field.enemy_deployment_cells.size(),
	]
	_ensure_surface_signal()
	_update_water_sync_preview()
	_update_height_sync_preview()
	_grid.columns = maxi(1, _field.width)
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for y in _field.height:
		for x in _field.width:
			_grid.add_child(_make_cell(Vector2i(x, y)))
	var errors := _field.validation_errors()
	if errors.is_empty():
		_diagnostics.text = "✓ Данные корректны — preview и runtime читают один Resource."
		_diagnostics.modulate = Color("7bc995")
	else:
		_diagnostics.text = "⚠ %s" % "\n⚠ ".join(errors)
		_diagnostics.modulate = Color("f08a82")
	if is_instance_valid(_resize_width) and not _resize_width.get_line_edit().has_focus():
		_resize_width.set_value_no_signal(_field.width)
	if is_instance_valid(_resize_height) and not _resize_height.get_line_edit().has_focus():
		_resize_height.set_value_no_signal(_field.height)
	_update_resize_preview()


func _ensure_surface_signal() -> void:
	if _connected_surface == _field.visual_surface:
		return
	if (
		is_instance_valid(_connected_surface)
		and _connected_surface.changed.is_connected(_refresh)
	):
		_connected_surface.changed.disconnect(_refresh)
	_connected_surface = _field.visual_surface
	if (
		is_instance_valid(_connected_surface)
		and not _connected_surface.changed.is_connected(_refresh)
	):
		_connected_surface.changed.connect(_refresh)


func _update_water_sync_preview() -> void:
	if not is_instance_valid(_water_sync_report) or not is_instance_valid(_water_sync_apply):
		return
	var threshold := (
		float(_water_threshold.get_selected_metadata())
		if is_instance_valid(_water_threshold) and _water_threshold.selected >= 0
		else 0.25
	)
	var report := _field.surface_water_sync_preview(threshold)
	if not bool(report.get("ok", false)):
		_water_sync_report.text = "Недоступно: %s" % str(report.get("error", "нет данных"))
		_water_sync_report.modulate = Color("f0bd6d")
		_water_sync_apply.disabled = true
		_water_sync_apply.text = "Синхронизировать Wet"
		return
	var wet: Array = report.get("wet_cells", [])
	var changed: Array = report.get("changed_cells", [])
	var protected: Array = report.get("protected_cells", [])
	_water_sync_report.text = "Вода покрывает %d клеток · изменится %d%s" % [
		wet.size(),
		changed.size(),
		(" · защищено Ember/Frozen: %d" % protected.size()) if not protected.is_empty() else "",
	]
	_water_sync_report.modulate = Color("7bc995") if changed.is_empty() else Color("62d7e6")
	_water_sync_apply.disabled = changed.is_empty() or not _water_sync_callback.is_valid()
	_water_sync_apply.text = (
		"Wet уже совпадает"
		if changed.is_empty()
		else "Применить %d изменений" % changed.size()
	)


func _apply_water_sync() -> void:
	if not _water_sync_callback.is_valid():
		return
	var threshold := float(_water_threshold.get_selected_metadata())
	_water_sync_callback.call(_field, threshold)


func _update_height_sync_preview() -> void:
	if not is_instance_valid(_height_sync_report) or not is_instance_valid(_height_sync_apply):
		return
	var report := _field.surface_height_sync_preview()
	if not bool(report.get("ok", false)):
		_height_sync_report.text = "Недоступно: %s" % str(report.get("error", "нет данных"))
		_height_sync_report.modulate = Color("f0bd6d")
		_height_sync_apply.disabled = true
		return
	var changed: Array = report.get("changed_cells", [])
	var uneven: Array = report.get("uneven_cells", [])
	var empty: Array = report.get("empty_cells", [])
	_height_sync_report.text = "Изменится %d клеток%s%s" % [
		changed.size(),
		(" · неровных: %d" % uneven.size()) if not uneven.is_empty() else "",
		(" · без пола: %d" % empty.size()) if not empty.is_empty() else "",
	]
	_height_sync_report.modulate = Color("7bc995") if changed.is_empty() else Color("b9d779")
	_height_sync_apply.disabled = changed.is_empty() or not _height_sync_callback.is_valid()
	_height_sync_apply.text = (
		"Высоты уже совпадают"
		if changed.is_empty()
		else "Применить %d изменений высоты" % changed.size()
	)


func _apply_height_sync() -> void:
	if _height_sync_callback.is_valid():
		_height_sync_callback.call(_field)


func _make_cell(cell: Vector2i) -> Control:
	var definition := _field.cell_definition(cell)
	var kind := int(definition.get("terrain", EmberBattlefieldResource.TerrainKind.NEUTRAL))
	var color := COLOR_NEUTRAL
	if bool(definition.get("blocked", false)):
		color = COLOR_BLOCKED
	elif kind == EmberBattlefieldResource.TerrainKind.WET:
		color = COLOR_WET
	elif kind == EmberBattlefieldResource.TerrainKind.EMBER:
		color = COLOR_EMBER
	elif kind == EmberBattlefieldResource.TerrainKind.FROZEN:
		color = COLOR_FROZEN
	var panel := Button.new()
	panel.flat = true
	panel.focus_mode = Control.FOCUS_NONE
	panel.custom_minimum_size = Vector2(34.0, 34.0)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	var party := cell in _field.party_deployment_cells
	var enemy := cell in _field.enemy_deployment_cells
	var deployment_label := ""
	if party:
		deployment_label = "Г%d·" % (_field.party_deployment_cells.find(cell) + 1)
	elif enemy:
		deployment_label = "В%d·" % (_field.enemy_deployment_cells.find(cell) + 1)
	style.border_color = (
		Color("ffbf47") if cell == _field.focus_cell
		else Color("62d7e6") if party
		else Color("f07883") if enemy
		else color.lightened(0.18)
	)
	panel.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.16)
	panel.add_theme_stylebox_override("hover", hover)
	panel.add_theme_stylebox_override("pressed", hover)
	panel.text = "%s%d" % [deployment_label, int(definition.get("elevation", 0))]
	panel.tooltip_text = "%s · h%d%s%s" % [
		_cell_label(cell),
		int(definition.get("elevation", 0)),
		" · преграда" if bool(definition.get("blocked", false)) else "",
		(" · группа %s" % str(definition.get("group", "")))
		if not str(definition.get("group", "")).is_empty()
		else "",
	]
	if party:
		panel.tooltip_text += " · старт героя %d" % (_field.party_deployment_cells.find(cell) + 1)
	elif enemy:
		panel.tooltip_text += " · старт врага %d" % (_field.enemy_deployment_cells.find(cell) + 1)
	panel.gui_input.connect(_on_cell_gui_input.bind(cell))
	return panel


func _cell_label(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(65 + cell.x), cell.y + 1]


func _on_cell_gui_input(event: InputEvent, cell: Vector2i) -> void:
	var should_paint: bool = (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	)
	if not should_paint or not _paint_callback.is_valid():
		return
	var tool := int(_brush.get_selected_metadata())
	_paint_callback.call(_field, cell, tool, _group_id.text)
	accept_event()


func _make_dimension_spin(label: String, value: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.name = "BattlefieldResize%s" % label
	spin.min_value = 1
	spin.max_value = 64
	spin.step = 1
	spin.value = value
	spin.prefix = "%s " % label
	spin.custom_minimum_size.x = 108.0
	spin.value_changed.connect(_update_resize_preview.unbind(1))
	return spin


func _update_resize_preview() -> void:
	if not is_instance_valid(_field) or not is_instance_valid(_resize_report):
		return
	var new_width := roundi(_resize_width.value)
	var new_height := roundi(_resize_height.value)
	var anchor := int(_resize_anchor.get_selected_metadata())
	var unchanged := new_width == _field.width and new_height == _field.height
	var report := _field.resize_preview(new_width, new_height, anchor)
	if unchanged:
		_resize_report.text = "Текущий размер. Измените ширину или глубину для preview."
		_resize_report.modulate = Color(0.67, 0.72, 0.8)
	elif bool(report.get("ok", false)):
		_resize_report.text = "Сохранится %d · обрежется %d · новых %d\nПотеря точек: герои %d · враги %d%s" % [
			int(report.get("kept_cells", 0)), int(report.get("lost_cells", 0)),
			int(report.get("new_cells", 0)), int(report.get("party_lost", 0)),
			int(report.get("enemy_lost", 0)),
			" · фокус перенесётся" if bool(report.get("focus_moved", false)) else "",
		]
		_resize_report.modulate = (
			Color("f0bd6d")
			if int(report.get("lost_cells", 0)) > 0 or int(report.get("party_lost", 0)) > 0 or int(report.get("enemy_lost", 0)) > 0
			else Color("7bc995")
		)
	else:
		_resize_report.text = "Нельзя применить:\n• %s" % "\n• ".join(report.get("errors", []))
		_resize_report.modulate = Color("f08a82")
	_resize_apply.disabled = unchanged or not bool(report.get("ok", false)) or not _resize_callback.is_valid()


func _apply_resize() -> void:
	if not _resize_callback.is_valid():
		return
	_resize_callback.call(
		_field,
		roundi(_resize_width.value),
		roundi(_resize_height.value),
		int(_resize_anchor.get_selected_metadata()),
	)
