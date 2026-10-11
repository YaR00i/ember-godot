@tool
extends VBoxContainer
const Assembly = preload("res://addons/ember_import/ember_voxel_scene_assembly.gd")
const Placement = preload("res://addons/ember_import/ember_voxel_placement_session.gd")
signal created(world_step: Vector3)
signal edit_closed
var parameters_panel: VBoxContainer
var _parameter_scroll: ScrollContainer
var _create_button: Button
var _title: Label
var operation: RefCounted
var placement: RefCounted
var _undo: Object
var _grid: OptionButton
var _axes: Array[SpinBox] = []
var _count: SpinBox
var _status: Label
var _preview: Node3D
var _camera: Camera3D
var _updating := false

func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	parameters_panel = VBoxContainer.new(); parameters_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_title = Label.new(); _title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; parameters_panel.add_child(_title)
	var scroll := ScrollContainer.new()
	_parameter_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parameters_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var info := Label.new()
	info.text = "Новые экземпляры общей модели. Canvas меняет только выбранную копию."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	_grid = OptionButton.new()
	_grid.fit_to_longest_item = false
	_grid.clip_text = true
	box.add_child(_grid)
	for axis in ["X", "Y", "Z"]:
		var row := VBoxContainer.new(); box.add_child(row)
		var label := Label.new()
		label.text = axis + " · vox"
		row.add_child(label)
		var number := SpinBox.new()
		number.min_value = -100000
		number.max_value = 100000
		number.step = 0.01
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(number)
		_axes.append(number)
		number.value_changed.connect(_refresh.unbind(1))
	var amount := HBoxContainer.new()
	box.add_child(amount)
	var heading := Label.new()
	heading.text = "Новых копий"
	amount.add_child(heading)
	_count = SpinBox.new()
	_count.min_value = 1
	_count.max_value = 32
	_count.value = 1
	amount.add_child(_count)
	_count.value_changed.connect(_refresh.unbind(1))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var container := SubViewportContainer.new()
	container.name = "CopyPreview"
	container.stretch = true
	container.custom_minimum_size = Vector2(320,240)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(560, 300)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	_preview = Node3D.new()
	viewport.add_child(_preview)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_camera.far = 100000
	_preview.add_child(_camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	_preview.add_child(light)
	_grid.item_selected.connect(_refresh.unbind(1))
	var actions := HBoxContainer.new(); parameters_panel.add_child(actions)
	_create_button = Button.new(); _create_button.text = "Создать копии"; _create_button.disabled = true
	_create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; actions.add_child(_create_button); _create_button.pressed.connect(_commit)
	var cancel := Button.new(); cancel.text = "Отмена"; actions.add_child(cancel); cancel.pressed.connect(cancel_edit)

func open_for(prop: EmberVoxelProp, scene: Node, undo: Object, directory := EmberVoxelCatalog.NATIVE_DIR) -> bool:
	_undo = undo
	placement = Placement.new()
	placement.source_directory = directory
	if not placement.open(prop, scene, null):
		_status.text = placement.error
		return false
	operation = Assembly.new()
	operation.source_directory = directory
	_updating = true
	_grid.clear()
	for number in _axes: number.value = 0
	_count.value = 1
	for index in placement.grids.size():
		_grid.add_item(placement.grid_label(index))
	_grid.select(0)
	_axes[0].value = maxf(1, placement.bounds_local.size.x * prop.global_basis.x.length())
	_updating = false
	_refresh()
	_title.text = "Дублирование · %s" % prop.name
	show()
	return true

func world_step() -> Vector3:
	return Vector3(_axes[0].value, _axes[1].value, _axes[2].value) * placement.grid_steps(_grid.selected)

func _refresh() -> void:
	if _updating or operation == null:
		return
	_grid.tooltip_text = placement.grid_label(_grid.selected)
	_create_button.disabled = true
	for child in _preview.get_children():
		if child is MeshInstance3D:
			child.free()
	var prop: EmberVoxelProp = placement.target()
	if prop == null or not operation.prepare_copies(prop, placement.scene(), world_step(), int(_count.value)):
		_status.text = operation.error
		return
	var mesh := prop.get_node("Mesh") as MeshInstance3D
	var transforms: Array[Transform3D] = [prop.global_transform]
	transforms.append_array(operation.positions)
	var box := AABB()
	var first := true
	for transform in transforms:
		var visual := MeshInstance3D.new()
		visual.mesh = mesh.mesh
		visual.material_override = mesh.material_override
		visual.material_overlay = mesh.material_overlay
		visual.transparency = mesh.transparency
		visual.visible = mesh.is_visible_in_tree()
		for surface in mesh.mesh.get_surface_count():
			visual.set_surface_override_material(surface, mesh.get_surface_override_material(surface))
		visual.transform = transform * mesh.transform
		_preview.add_child(visual)
		var bounds: AABB = visual.transform * mesh.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	var extent := maxf(1, maxf(box.size.x, maxf(box.size.y, box.size.z)))
	_camera.size = extent * 1.6
	_camera.position = box.get_center() + Vector3(1, 1, 1).normalized() * extent * 2.5
	_camera.look_at(box.get_center())
	_status.text = "%d новых копий · шаг в единицах сцены %s. Исходник остаётся на месте." % [int(_count.value), world_step()]
	_create_button.disabled = false

func _commit() -> void:
	if operation == null or _create_button.disabled: return
	var copies: Array = operation.commit_copies(_undo)
	if copies.is_empty():
		_status.text = operation.error
		_create_button.disabled = true
		return
	var step := world_step()
	cancel_edit()
	created.emit(step)


func get_create_button() -> Button:
	return _create_button


func is_dirty() -> bool:
	return placement != null


func cancel_edit() -> void:
	operation = null; placement = null; _undo = null; _create_button.disabled = true
	for child in _preview.get_children():
		if child is MeshInstance3D: child.free()
	hide(); edit_closed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(parameters_panel): parameters_panel.free()
