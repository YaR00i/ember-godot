@tool
extends VBoxContainer
const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
signal created(prop: EmberVoxelProp)
signal edit_closed
signal canceled
var title := "Новая voxel-форма"
var _legacy_window: ConfirmationDialog
var _cancel_button: Button
var _shape_preview_container: SubViewportContainer
var parameters_panel: VBoxContainer
var _parameter_scroll: ScrollContainer
var _create_button: Button
var _prepare_button: Button
var _preview_viewport: SubViewport
var _heading: Label
var _baseline := {}
var source_directory_override := ""
var prefab_directory_override := ""
var creation: RefCounted
var _root: Node
var _parent: Node3D
var _undo: Object
var _position: Vector3
var _world_size := 16.0
var _kind: OptionButton
var _title: LineEdit
var _density: OptionButton
var _color: ColorPickerButton
var _sizes: Array[SpinBox] = []
var _labels: Array[Label] = []
var _status: Label
var _world: Node3D
var _camera: Camera3D
var _preview: Node3D
var _large_ack: CheckBox

func _init() -> void:
	size = Vector2(620,820) # Preserve the remaining modal subclasses' default size.
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	parameters_panel = VBoxContainer.new(); parameters_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(parameters_panel)
	_heading = Label.new(); _heading.text = "Новая voxel-форма"; parameters_panel.add_child(_heading)
	var scroll := ScrollContainer.new()
	_parameter_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parameters_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_title = LineEdit.new()
	_title.placeholder_text = "Название модели"
	_title.text = "Новая форма"
	box.add_child(_title)
	_kind = OptionButton.new()
	for label in ["Пустая область", "Блок", "Цилиндр", "Сфера"]:
		_kind.add_item(label)
	box.add_child(_kind)
	for label in ["X · vox", "Y · vox", "Z · vox"]:
		var row := HBoxContainer.new()
		var heading := Label.new()
		heading.text = label
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(heading)
		_labels.append(heading)
		var number := SpinBox.new()
		number.min_value = 1
		number.max_value = 10000
		number.allow_greater = true
		number.allow_lesser = true
		number.value = 16
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		number.value_changed.connect(_invalidate.unbind(1))
		row.add_child(number)
		_sizes.append(number)
		box.add_child(row)
	_density = OptionButton.new()
	_density.add_item("16 вокселей на блок", 16)
	_density.add_item("32 вокселя на блок", 32)
	box.add_child(_density)
	_color = ColorPickerButton.new()
	_color.text = "Цвет модели"
	_color.custom_minimum_size.y = 34
	_color.color = Color("b27a47")
	_color.edit_alpha = false
	box.add_child(_color)
	_large_ack = CheckBox.new()
	_large_ack.text = "Разрешить тяжёлый предпросмотр"
	_large_ack.clip_text = true
	_large_ack.tooltip_text = _large_ack.text
	_large_ack.visible = false
	box.add_child(_large_ack)
	var prepare := Button.new()
	_prepare_button = prepare
	prepare.text = "Обновить предпросмотр"
	prepare.pressed.connect(_prepare)
	box.add_child(prepare)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var container := SubViewportContainer.new()
	_shape_preview_container = container
	container.stretch = true
	container.custom_minimum_size = Vector2(300, 240)
	container.name = "ShapePreview"
	container.size_flags_vertical = Control.SIZE_FILL
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	_preview_viewport = viewport
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	_world = Node3D.new()
	viewport.add_child(_world)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_world.add_child(_camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	_world.add_child(light)
	_title.text_changed.connect(_invalidate.unbind(1))
	_density.item_selected.connect(_invalidate.unbind(1))
	_color.color_changed.connect(_invalidate.unbind(1))
	_kind.item_selected.connect(_kind_changed.unbind(1))
	var actions := VBoxContainer.new(); parameters_panel.add_child(actions)
	_create_button = Button.new(); _create_button.text = "Создать и открыть Canvas"
	_create_button.disabled = true; _create_button.pressed.connect(_commit); actions.add_child(_create_button)
	var cancel := Button.new(); cancel.text = "Отмена"; cancel.pressed.connect(cancel_edit); actions.add_child(cancel)
	_cancel_button = cancel
	_kind_changed()

func open_for(root: Node, parent: Node3D, undo: Object, position: Vector3, world_size := 16.0) -> void:
	_root = root
	_parent = parent
	_undo = undo
	_position = position
	_world_size = world_size
	_status.text = "Создание в %s · локальная позиция %s. До подтверждения файлы не создаются." % [parent.name, position]
	_baseline = _parameters()
	_create_button.disabled = true
	show()

func _kind_changed() -> void:
	var sphere := _kind.selected == 3
	var cylinder := _kind.selected == 2
	_labels[0].text = "Диаметр · vox" if sphere or cylinder else "X · vox"
	_sizes[1].get_parent().visible = not sphere
	_sizes[2].get_parent().visible = not sphere and not cylinder
	_invalidate()

func _invalidate() -> void:
	creation = null
	if is_instance_valid(_preview): _preview.free()
	_preview = null
	if _large_ack != null:
		_large_ack.set_pressed_no_signal(false)
	_create_button.disabled = true
	if _status != null:
		_status.text = "Параметры изменены. Обновите предпросмотр перед созданием."

func _check_large_budget(dimensions: Vector3i) -> bool:
	var density := _density.get_selected_id()
	var cells := ceili(float(dimensions.x) / density) * density * dimensions.y * ceili(float(dimensions.z) / density) * density
	_large_ack.visible = cells > Creation.Shapes.WARNING_CELLS and cells <= Creation.Shapes.MAX_CELLS
	if _large_ack.visible and not _large_ack.button_pressed:
		_create_button.disabled = true
		_status.text = "%d ячеек: подготовка и сохранение могут приостанавливать редактор на несколько секунд. Отметьте разрешение выше и нажмите «Обновить предпросмотр»." % cells
		return false
	return true

func _prepare() -> void:
	if not is_instance_valid(_root) or not is_instance_valid(_parent):
		_status.text = "Сцена закрыта. Откройте диалог создания заново."
		_create_button.disabled = true
		return
	creation = Creation.new()
	creation.world_size = _world_size
	if not source_directory_override.is_empty(): creation.source_directory = source_directory_override
	if not prefab_directory_override.is_empty(): creation.prefab_directory = prefab_directory_override
	var dimensions := Vector3i(int(_sizes[0].value), int(_sizes[1].value), int(_sizes[2].value))
	if _kind.selected == 2:
		dimensions.z = dimensions.x
	elif _kind.selected == 3:
		dimensions = Vector3i.ONE * dimensions.x
	if not _check_large_budget(dimensions):
		return
	if not creation.prepare(["empty", "block", "cylinder", "sphere"][_kind.selected], dimensions, _density.get_selected_id(), _color.color, _title.text):
		_status.text = creation.error
		_create_button.disabled = true
		return
	if is_instance_valid(_preview):
		_preview.free()
	_preview = creation.packed.instantiate()
	_preview.configure_voxel_scale(creation.source.normalized_density(), _world_size)
	_world.add_child(_preview)
	var extent: Vector3 = Vector3(creation.report.grid) * (_world_size / creation.source.normalized_density())
	_camera.size = maxf(extent.x, maxf(extent.y, extent.z)) * 1.8
	var center := Vector3(0, extent.y * 0.5, 0)
	_camera.position = center + Vector3(1, 0.8, 1).normalized() * _camera.size * 2
	_camera.look_at(center)
	_status.text = "%s: %s вокселей. Сетка хранения: %s; пустой запас X/Z: %s. Создание в %s · %s.\n%s" % ["Пустая рабочая область" if _kind.selected == 0 else "Форма", dimensions, creation.report.grid, Vector2i(creation.report.grid.x - dimensions.x, creation.report.grid.z - dimensions.z), _parent.name, _position, "Нет геометрии и активной коллизии; инструментом «Объём» добавьте первый воксель на нижнюю плоскость Canvas." if _kind.selected == 0 else "Предпросмотр и созданный объект используют одну подготовленную геометрию."]
	if _kind.selected == 0:
		_status.text = "Запрошено: %s вокселей. Область редактирования: %s (включает пустой запас X/Z).\nСоздание в %s · %s. Нет геометрии и коллизии. Инструментом «Объём» добавьте первый воксель на нижнюю плоскость Canvas." % [dimensions, creation.report.grid, _parent.name, _position]
	_create_button.disabled = false

func _commit() -> void:
	if creation == null or _create_button.disabled: return
	var prop: EmberVoxelProp = creation.commit(_root, _parent, _undo, _position)
	if prop == null:
		_status.text = creation.error
		return
	cancel_edit()
	created.emit(prop)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(parameters_panel): parameters_panel.free()
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_legacy_window):
		_legacy_window.hide(); _legacy_window.queue_free()


func use_dock_layout() -> void:
	# One preview/controller serves both the new dock and its existing subclasses.
	if parameters_panel.get_parent() == self: remove_child(parameters_panel)
	_shape_preview_container.reparent(self)
	_shape_preview_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	size = Vector2(300,240)


func get_ok_button() -> Button:
	return _create_button


func pin_preview_action() -> void:
	_prepare_button.reparent(parameters_panel)
	parameters_panel.move_child(_prepare_button,2) # Above Apply/Cancel.


func get_cancel_button() -> Button:
	return _cancel_button


func popup_centered(minimum_size := Vector2i(620,640)) -> void:
	# Legacy callers and the remaining split/conversion tools use this modal adapter.
	_parameter_scroll.custom_minimum_size = Vector2(460,480)
	if not is_instance_valid(_legacy_window):
		var host := get_parent()
		_legacy_window = ConfirmationDialog.new(); _legacy_window.dialog_hide_on_ok = false
		_legacy_window.get_ok_button().hide(); _legacy_window.get_cancel_button().hide()
		_legacy_window.canceled.connect(cancel_edit)
		host.add_child(_legacy_window)
		reparent(_legacy_window)
	_legacy_window.title = title; _heading.text = title; show()
	_legacy_window.popup_centered(Vector2i(size).max(minimum_size))


func _parameters() -> Dictionary:
	return {"kind": _kind.selected, "title": _title.text, "density": _density.get_selected_id(), "color": _color.color,
		"size": Vector3(_sizes[0].value, _sizes[1].value, _sizes[2].value)}


func is_dirty() -> bool:
	return _root != null and (creation != null or _parameters() != _baseline)


func get_create_button() -> Button:
	return _create_button


func cancel_edit() -> void:
	creation = null; _root = null; _parent = null; _undo = null; _baseline.clear()
	if is_instance_valid(_preview): _preview.free()
	_preview = null; _create_button.disabled = true; hide(); edit_closed.emit()
	if is_instance_valid(_legacy_window):
		_legacy_window.hide(); canceled.emit()
