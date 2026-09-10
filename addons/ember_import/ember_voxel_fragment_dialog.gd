@tool
extends ConfirmationDialog
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
signal applied(indices: PackedInt32Array)
var source: EmberVoxelModelResource
var indices := PackedInt32Array()
var region := Rect2i()
var height := -1
var actions: RefCounted
var result := {}
var _snapshot: Dictionary
var _numbers: Array[SpinBox] = []
var _copy: CheckBox
var _axis: OptionButton
var _turns: OptionButton
var _status: Label
var _world: Node3D
var _camera: Camera3D
var _preview: Node3D

func _init() -> void:
	title = "Фрагмент · точные воксельные операции"
	size = Vector2i(620, 650)
	dialog_hide_on_ok = false
	get_ok_button().text = "Применить"
	get_ok_button().disabled = true
	get_cancel_button().text = "Отмена"
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 490)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "Смещение в вокселях. Поворот сохраняет нижний угол габаритов фрагмента. Перекрытие других вокселей запрещено."
	box.add_child(help)
	for label in ["Сдвиг X", "Сдвиг Y", "Сдвиг Z"]:
		var row := HBoxContainer.new()
		var heading := Label.new()
		heading.text = label
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(heading)
		var number := SpinBox.new()
		number.min_value = -4096
		number.max_value = 4096
		number.value_changed.connect(_invalidate.unbind(1))
		row.add_child(number)
		_numbers.append(number)
		box.add_child(row)
	_axis = OptionButton.new()
	for axis in ["Вокруг X", "Вокруг Y", "Вокруг Z"]:
		_axis.add_item(axis)
	_axis.select(1)
	box.add_child(_axis)
	_turns = OptionButton.new()
	for angle in ["Без поворота", "+90°", "180°", "−90°"]:
		_turns.add_item(angle)
	box.add_child(_turns)
	_copy = CheckBox.new()
	_copy.text = "Скопировать · оставить исходный фрагмент"
	box.add_child(_copy)
	_axis.item_selected.connect(_invalidate.unbind(1))
	_turns.item_selected.connect(_invalidate.unbind(1))
	_copy.toggled.connect(_invalidate.unbind(1))
	var prepare := Button.new()
	prepare.text = "Обновить предпросмотр результата"
	prepare.pressed.connect(_prepare)
	box.add_child(prepare)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(300,240)
	container.size_flags_vertical = Control.SIZE_FILL
	box.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	container.add_child(viewport)
	_world = Node3D.new()
	viewport.add_child(_world)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_world.add_child(_camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-35,0)
	_world.add_child(light)
	confirmed.connect(_commit)

func open_for(resource: EmberVoxelModelResource, selection: PackedInt32Array, owner_actions: RefCounted, edit_region: Rect2i, slice_height: int) -> void:
	source = resource
	indices = selection
	actions = owner_actions
	region = edit_region
	height = slice_height
	_snapshot = source.to_definition().duplicate(true)
	_invalidate()
	popup_centered()

func _invalidate() -> void:
	result = {}
	get_ok_button().disabled = true
	if _status != null:
		_status.text = "Задайте преобразование и обновите preview. До применения модель не меняется."
	if is_instance_valid(_preview):
		_preview.hide()

func _prepare() -> void:
	_invalidate()
	if source.to_definition() != _snapshot:
		_status.text = "Модель изменилась. Откройте операцию заново."
		return
	result = Fragment.plan(source, indices, Vector3i(int(_numbers[0].value),int(_numbers[1].value),int(_numbers[2].value)), _axis.selected, _turns.selected, _copy.button_pressed, region, height)
	if result.has("error"):
		_status.text = result.error
		return
	var draft := source.duplicate(true) as EmberVoxelModelResource
	for key in result.properties:
		draft.set(key, result.properties[key])
	var packed := EmberVoxelPrefab.prepare_resource(draft)
	if packed == null:
		_status.text = "Не удалось построить preview. Исходная модель сохранена."
		return
	if is_instance_valid(_preview):
		_preview.free()
	_preview = packed.instantiate()
	_preview.configure_voxel_scale(draft.normalized_density(), 1.0)
	_world.add_child(_preview)
	var mesh := _preview.get_node("Mesh") as MeshInstance3D
	var bounds: AABB = mesh.transform * mesh.get_aabb()
	var extent := maxf(1, bounds.size.length())
	_camera.size = extent * 1.2
	_camera.position = bounds.get_center() + Vector3(1,0.9,1).normalized() * extent * 3
	_camera.look_at(bounds.get_center())
	_status.text = "%d vox · preview показывает всю модель после операции. Цвета, материалы и группы переносятся вместе с формой." % indices.size()
	get_ok_button().disabled = false

func _commit() -> void:
	if source.to_definition() != _snapshot or not actions.apply_fragment(source,result):
		_status.text = "Модель или preview изменились. Откройте операцию заново."
		get_ok_button().disabled = true
		return
	applied.emit(result.selected)
	hide()
