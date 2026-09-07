@tool
extends VBoxContainer
## Palette authoring UI only; mutations go through the workspace's Undo owner.
const PaletteModel = preload("res://addons/ember_import/ember_voxel_palette_model.gd")
signal color_selected(index: int)
signal operation_requested(resource: EmberVoxelModelResource, operation: Dictionary)
signal pick_requested
signal editing_started

var _resource: EmberVoxelModelResource
var _colors := PackedColorArray()
var _selected := 1
var _grid: GridContainer
var _swatch_scroll: ScrollContainer
var _label: Label
var _add: Button
var _edit: Button
var _merge: Button
var _ramp: Button
var _pick: Button
var _dialog: ConfirmationDialog
var _warning: Label
var _picker: ColorPicker
var _replacement: OptionButton
var _ramp_box: VBoxContainer
var _ramp_style: OptionButton
var _ramp_steps: OptionButton
var _ramp_preview: HBoxContainer
var _pending: Dictionary = {}
var _pending_colors := PackedColorArray()
var _pending_resource: EmberVoxelModelResource


func _init() -> void:
	name = "VoxelPalettePanel"
	var heading := Label.new()
	heading.text = "ПАЛИТРА"
	add_child(heading)
	_label = Label.new()
	add_child(_label)
	_swatch_scroll = ScrollContainer.new()
	_swatch_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_swatch_scroll)
	_grid = GridContainer.new()
	_grid.columns = 6
	_swatch_scroll.add_child(_grid)
	var buttons := HBoxContainer.new()
	add_child(buttons)
	_add = _button(buttons, "+ Цвет", "PaletteAdd", _open_dialog.bind("add"))
	_edit = _button(buttons, "Изменить", "PaletteEdit", _open_dialog.bind("set"))
	_merge = _button(buttons, "Заменить…", "PaletteMerge", _open_dialog.bind("merge"))
	_merge.tooltip_text = "Заменить все ссылки другим цветом и удалить образец. Не удаляет воксели."
	_ramp = _button(self, "Рамп оттенков…", "PaletteRamp", _open_dialog.bind("ramp"))
	_ramp.tooltip_text = "Развернуть выбранный цвет в связный набор теней и светов."
	_pick = _button(self, "Пипетка · I", "PaletteEyedropper", func() -> void: pick_requested.emit())
	_dialog = ConfirmationDialog.new()
	_dialog.name = "PaletteEditDialog"
	_dialog.ok_button_text = "Применить"
	_dialog.cancel_button_text = "Отмена"
	_dialog.get_label().hide()
	add_child(_dialog)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dialog.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_warning = Label.new()
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_warning)
	_picker = ColorPicker.new()
	_picker.name = "PaletteColorPicker"
	_picker.edit_alpha = false
	_picker.presets_visible = false
	body.add_child(_picker)
	_replacement = OptionButton.new()
	_replacement.name = "PaletteReplacement"
	body.add_child(_replacement)
	_ramp_box = VBoxContainer.new()
	body.add_child(_ramp_box)
	var style_label := Label.new()
	style_label.text = "Характер света"
	_ramp_box.add_child(style_label)
	_ramp_style = OptionButton.new()
	_ramp_style.name = "PaletteRampStyle"
	_ramp_style.add_item("Ровный тон", 0)
	_ramp_style.add_item("Тёплый свет · холодная тень", 1)
	_ramp_style.add_item("Мягкий пастельный", 2)
	_ramp_style.select(1)
	_ramp_style.item_selected.connect(func(_index: int) -> void: _update_ramp_preview())
	_ramp_box.add_child(_ramp_style)
	var steps_label := Label.new()
	steps_label.text = "Число оттенков"
	_ramp_box.add_child(steps_label)
	_ramp_steps = OptionButton.new()
	_ramp_steps.name = "PaletteRampSteps"
	for steps in [3, 5, 7]:
		_ramp_steps.add_item(str(steps), steps)
	_ramp_steps.select(1)
	_ramp_steps.item_selected.connect(func(_index: int) -> void: _update_ramp_preview())
	_ramp_box.add_child(_ramp_steps)
	var preview_label := Label.new()
	preview_label.text = "Предпросмотр"
	_ramp_box.add_child(preview_label)
	_ramp_preview = HBoxContainer.new()
	_ramp_preview.name = "PaletteRampPreview"
	_ramp_box.add_child(_ramp_preview)
	_dialog.confirmed.connect(_confirm)
	_dialog.canceled.connect(_clear_pending)


func sync(resource: EmberVoxelModelResource, selected: int) -> void:
	if resource != _resource or (resource != null and resource.palette != _colors):
		_dialog.hide()
		_clear_pending()
		_resource = resource
		_colors = resource.palette.duplicate() if resource != null else PackedColorArray()
		for child in _grid.get_children():
			_grid.remove_child(child)
			child.queue_free()
		for index in range(1, _colors.size()):
			var button := Button.new()
			button.name = "PaletteColor_%d" % index
			button.custom_minimum_size = Vector2(38, 38)
			button.icon = swatch(_colors[index], 26)
			button.toggle_mode = true
			button.tooltip_text = "Цвет %d · #%s" % [index, _colors[index].to_html(false)]
			button.pressed.connect(func() -> void: color_selected.emit(index))
			_grid.add_child(button)
	_swatch_scroll.custom_minimum_size.y = clampi(ceili(float(_grid.get_child_count()) / 6.0) * 42, 42, 136)
	_selected = clampi(selected, 1, maxi(1, _colors.size() - 1))
	for index in _grid.get_child_count():
		(_grid.get_child(index) as Button).set_pressed_no_signal(index + 1 == _selected)
	_label.text = "Цвет %d · #%s" % [_selected, _colors[_selected].to_html(false)] if _colors.size() > 1 else "Нет палитры"
	_add.disabled = _resource == null or _colors.size() >= 256
	_edit.disabled = _resource == null
	_merge.disabled = _colors.size() <= 2
	_ramp.disabled = _resource == null or _colors.size() + 2 > 256
	_pick.disabled = _resource == null


func set_pick_active(active: bool) -> void:
	_pick.text = "Клик по вокселю · Esc отмена" if active else "Пипетка · I"


func cancel_edit() -> void:
	_dialog.hide()
	_clear_pending()


func _open_dialog(kind: String) -> void:
	if _resource == null:
		return
	editing_started.emit()
	_pending = {"kind": kind, "index": _selected}
	_pending_resource = _resource
	_pending_colors = _resource.palette.duplicate()
	_picker.color = _colors[_selected]
	_picker.visible = kind not in ["merge", "ramp"]
	_replacement.visible = kind == "merge"
	_ramp_box.visible = kind == "ramp"
	_replacement.clear()
	for index in range(1, _colors.size()):
		if index != _selected:
			_replacement.add_icon_item(swatch(_colors[index], 20), "Цвет %d · #%s" % [index, _colors[index].to_html(false)], index)
	_dialog.title = (
		"Добавить цвет" if kind == "add" else
		"Изменить цвет всей модели" if kind == "set" else
		"Рамп оттенков" if kind == "ramp" else
		"Заменить и удалить цвет"
	)
	_warning.text = (
		"Новый образец не перекрашивает модель. После добавления рисуйте выбранным цветом."
		if kind == "add" else
		"Исходный цвет останется центральным: модель визуально не изменится. Тени и света станут обычными соседними образцами. Один Ctrl+Z отменяет."
		if kind == "ramp" else
		"Вся модель, включая скрытые слои и участки вне выделения: %d вокселей, %d ссылок оттенка воды. Один Ctrl+Z отменяет."
		% [_resource.voxels.count(_selected), _resource.surface_fill_palette.count(_selected)]
	)
	if kind == "ramp":
		_update_ramp_preview()
	_dialog.reset_size()
	_dialog.popup_centered_clamped(Vector2i(460, 620) if kind not in ["merge", "ramp"] else Vector2i(460, 420), 0.9)


func _confirm() -> void:
	if _pending.is_empty() or _pending_resource != _resource or _pending_colors != _resource.palette:
		return # A resource switch/Undo invalidated the dialog; never target a shifted index.
	var operation := _pending.duplicate()
	operation["color"] = _picker.color
	operation["target"] = _replacement.get_selected_id()
	if str(operation.get("kind", "")) == "ramp":
		operation["colors"] = PaletteModel.build_ramp(
			_colors[_selected],
			_ramp_steps.get_selected_id(),
			_ramp_style.get_selected_id(),
		)
	_clear_pending()
	operation_requested.emit(_resource, operation)


func _clear_pending() -> void:
	_pending.clear()
	_pending_resource = null
	_pending_colors = PackedColorArray()


func _update_ramp_preview() -> void:
	for child in _ramp_preview.get_children():
		child.hide()
		_ramp_preview.remove_child(child)
		child.queue_free()
	if _colors.size() <= _selected:
		return
	var ramp := PaletteModel.build_ramp(
		_colors[_selected],
		_ramp_steps.get_selected_id(),
		_ramp_style.get_selected_id(),
	)
	for index in ramp.size():
		var sample := TextureRect.new()
		sample.custom_minimum_size = Vector2(40, 40)
		sample.texture = swatch(ramp[index], 32)
		sample.tooltip_text = "%d/%d · #%s%s" % [
			index + 1,
			ramp.size(),
			ramp[index].to_html(false),
			" · исходный" if index == ramp.size() / 2 else "",
		]
		_ramp_preview.add_child(sample)


static func swatch(color: Color, size: int) -> Texture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([color, color])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = size
	texture.height = size
	return texture


func _button(parent: Node, text: String, node_name: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button
