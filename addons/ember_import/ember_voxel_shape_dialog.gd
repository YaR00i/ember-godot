@tool
extends ConfirmationDialog
const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
signal created(prop: EmberVoxelProp)
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
	title = "Новая voxel-форма"
	size = Vector2i(620, 820)
	get_ok_button().text = "Создать и открыть Canvas"
	get_ok_button().disabled = true
	get_cancel_button().text = "Отмена"
	dialog_hide_on_ok = false
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 480)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
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
		number.value_changed.connect(_invalidate.unbind(1))
		row.add_child(number)
		_sizes.append(number)
		box.add_child(row)
	_density = OptionButton.new()
	_density.add_item("16 vox/block", 16)
	_density.add_item("32 vox/block", 32)
	box.add_child(_density)
	_color = ColorPickerButton.new()
	_color.text = "Цвет модели"
	_color.custom_minimum_size.y = 34
	_color.color = Color("b27a47")
	_color.edit_alpha = false
	box.add_child(_color)
	_large_ack = CheckBox.new()
	_large_ack.text = "Разрешить тяжёлый предпросмотр"
	_large_ack.visible = false
	box.add_child(_large_ack)
	var prepare := Button.new()
	prepare.text = "Обновить предпросмотр"
	prepare.pressed.connect(_prepare)
	box.add_child(prepare)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(300, 240)
	# Fixed preview height prevents the native dialog's minimum-size solver
	# from feeding expanded render-target height back into its next resize.
	container.size_flags_vertical = Control.SIZE_FILL
	box.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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
	confirmed.connect(_commit)
	_kind_changed()

func open_for(root: Node, parent: Node3D, undo: Object, position: Vector3, world_size := 16.0) -> void:
	_root = root
	_parent = parent
	_undo = undo
	_position = position
	_world_size = world_size
	_status.text = "Создание в %s · локальная позиция %s. До подтверждения файлы не создаются." % [parent.name, position]
	popup_centered()

func _kind_changed() -> void:
	var sphere := _kind.selected == 3
	var cylinder := _kind.selected == 2
	_labels[0].text = "Диаметр · vox" if sphere or cylinder else "X · vox"
	_sizes[1].get_parent().visible = not sphere
	_sizes[2].get_parent().visible = not sphere and not cylinder
	_invalidate()

func _invalidate() -> void:
	if _large_ack != null:
		_large_ack.set_pressed_no_signal(false)
	get_ok_button().disabled = true
	if _status != null:
		_status.text = "Параметры изменены. Обновите предпросмотр перед созданием."

func _check_large_budget(dimensions: Vector3i) -> bool:
	var density := _density.get_selected_id()
	var cells := ceili(float(dimensions.x) / density) * density * dimensions.y * ceili(float(dimensions.z) / density) * density
	_large_ack.visible = cells > Creation.Shapes.WARNING_CELLS and cells <= Creation.Shapes.MAX_CELLS
	if _large_ack.visible and not _large_ack.button_pressed:
		get_ok_button().disabled = true
		_status.text = "%d ячеек: подготовка и сохранение могут приостанавливать редактор на несколько секунд. Отметьте разрешение выше и нажмите «Обновить предпросмотр»." % cells
		return false
	return true

func _prepare() -> void:
	if not is_instance_valid(_root) or not is_instance_valid(_parent):
		_status.text = "Сцена закрыта. Откройте диалог создания заново."
		get_ok_button().disabled = true
		return
	creation = Creation.new()
	creation.world_size = _world_size
	var dimensions := Vector3i(int(_sizes[0].value), int(_sizes[1].value), int(_sizes[2].value))
	if _kind.selected == 2:
		dimensions.z = dimensions.x
	elif _kind.selected == 3:
		dimensions = Vector3i.ONE * dimensions.x
	if not _check_large_budget(dimensions):
		return
	if not creation.prepare(["empty", "block", "cylinder", "sphere"][_kind.selected], dimensions, _density.get_selected_id(), _color.color, _title.text):
		_status.text = creation.error
		get_ok_button().disabled = true
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
	get_ok_button().disabled = false

func _commit() -> void:
	var prop: EmberVoxelProp = creation.commit(_root, _parent, _undo, _position)
	if prop == null:
		_status.text = creation.error
		return
	hide()
	created.emit(prop)
