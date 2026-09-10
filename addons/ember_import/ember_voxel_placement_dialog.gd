@tool
extends ConfirmationDialog
## Bounded native preview for exact voxel placement. The authored scene is only
## touched by Session.commit() after confirmation.

const Context = preload("res://addons/ember_import/ember_voxel_canvas_context.gd")
const Math = preload("res://addons/ember_import/ember_voxel_placement_math.gd")
signal applied(target: Node3D)

var placement: RefCounted
var _grid: OptionButton
var _grid_help: Label
var _pivot: OptionButton
var _custom: Array[SpinBox] = []
var _coordinates: Array[SpinBox] = []
var _offsets: Array[SpinBox] = []
var _rotations: Array[SpinBox] = []
var _snap_enabled: CheckBox
var _snap_step: SpinBox
var _context_enabled: CheckBox
var _status: Label
var _world: Node3D
var _camera: Camera3D
var _context: Node3D
var _selected_preview: Node3D
var _pivot_preview: MeshInstance3D
var _preview_relatives: Array[Dictionary] = []
var _pivot_local := Vector3.ZERO
var _desired_world := Vector3.ZERO
var _planned_world := Transform3D.IDENTITY
var _updating := false


func _init() -> void:
	title = "Точная voxel-расстановка"
	size = Vector2i(720,640)
	get_ok_button().text = "Применить"
	get_ok_button().disabled = true
	get_cancel_button().text = "Отмена"
	dialog_hide_on_ok = false
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation",12)
	add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.name = "PlacementScroll"
	scroll.custom_minimum_size = Vector2(350,460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var intro := Label.new()
	intro.text = "XYZ — мировые оси. Расстановка не меняет масштаб или наклон скрыто."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	_grid = OptionButton.new()
	_grid.tooltip_text = "Общая мировая сетка с началом координат 0. Размер шага взят из фактического voxel выбранной детали."
	box.add_child(_grid)
	_grid_help = Label.new()
	_grid_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_grid_help)
	var pivot_row := HBoxContainer.new()
	box.add_child(pivot_row)
	var pivot_label := Label.new()
	pivot_label.text = "Опорная точка"
	pivot_label.custom_minimum_size.x = 120
	pivot_row.add_child(pivot_label)
	_pivot = OptionButton.new()
	_pivot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pivot.add_item("Центр",0)
	_pivot.add_item("Нижний угол",1)
	_pivot.add_item("Своя · vox",2)
	pivot_row.add_child(_pivot)
	var custom_grid := GridContainer.new()
	custom_grid.columns = 4
	box.add_child(custom_grid)
	var custom_label := Label.new()
	custom_label.text = "Своя точка"
	custom_grid.add_child(custom_label)
	for axis in ["X","Y","Z"]:
		var number := _number(-1000000,1000000,0.01)
		number.tooltip_text = "%s вокселей от исходного угла модели; для сборки — от нижнего угла по мировой сетке." % axis
		custom_grid.add_child(number)
		_custom.append(number)
	var values := GridContainer.new()
	values.columns = 3
	values.name = "PositionGrid"
	box.add_child(values)
	for heading in ["Ось","Координата · vox","Смещение · vox"]:
		var label := Label.new()
		label.text = heading
		values.add_child(label)
	for axis in ["X","Y","Z"]:
		var label := Label.new()
		label.text = axis
		values.add_child(label)
		var coordinate := _number(-1000000,1000000,0.001)
		coordinate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		values.add_child(coordinate)
		_coordinates.append(coordinate)
		var offset := _number(-1000000,1000000,0.001)
		offset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		values.add_child(offset)
		_offsets.append(offset)
	var snap_row := HBoxContainer.new()
	box.add_child(snap_row)
	_snap_enabled = CheckBox.new()
	_snap_enabled.text = "Привязка при вводе"
	_snap_enabled.button_pressed = true
	snap_row.add_child(_snap_enabled)
	var step_label := Label.new()
	step_label.text = "Шаг · vox"
	snap_row.add_child(step_label)
	_snap_step = _number(0.001,1024,0.001)
	_snap_step.value = 1
	snap_row.add_child(_snap_step)
	var snap_now := Button.new()
	snap_now.text = "Привязать сейчас"
	snap_now.tooltip_text = "Привязать выбранную опорную точку к ближайшему шагу мировой сетки."
	snap_now.pressed.connect(_snap_now)
	box.add_child(snap_now)
	var rotation_title := Label.new()
	rotation_title.text = "Поворот от исходного положения · градусы"
	box.add_child(rotation_title)
	var rotations := GridContainer.new()
	rotations.columns = 4
	box.add_child(rotations)
	for axis in ["X","Y","Z"]:
		var label := Label.new()
		label.text = axis
		rotations.add_child(label)
		var number := _number(-360000,360000,0.1)
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rotations.add_child(number)
		_rotations.append(number)
		var minus := Button.new()
		minus.text = "−90°"
		minus.pressed.connect(_rotate_quarter.bind(_rotations.size()-1,-90.0))
		rotations.add_child(minus)
		var plus := Button.new()
		plus.text = "+90°"
		plus.pressed.connect(_rotate_quarter.bind(_rotations.size()-1,90.0))
		rotations.add_child(plus)
	_context_enabled = CheckBox.new()
	_context_enabled.text = "Показать окружение"
	_context_enabled.button_pressed = true
	box.add_child(_context_enabled)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "PlacementPreview"
	viewport_container.stretch = true
	viewport_container.custom_minimum_size = Vector2(330,460)
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(viewport_container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport_container.add_child(viewport)
	_world = Node3D.new()
	viewport.add_child(_world)
	_context = Context.new()
	_world.add_child(_context)
	_selected_preview = Node3D.new()
	_world.add_child(_selected_preview)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_camera.far = 100000
	_world.add_child(_camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-35,0)
	light.light_energy = 1.2
	_world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(35,145,0)
	fill.light_energy = 0.35
	_world.add_child(fill)
	_pivot_preview = MeshInstance3D.new()
	var pivot_mesh := SphereMesh.new()
	pivot_mesh.radius = 0.5
	pivot_mesh.height = 1.0
	var pivot_material := StandardMaterial3D.new()
	pivot_material.albedo_color = Color("ffd35c")
	pivot_material.emission_enabled = true
	pivot_material.emission = Color("ff9b31")
	pivot_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pivot_mesh.material = pivot_material
	_pivot_preview.mesh = pivot_mesh
	_world.add_child(_pivot_preview)
	_grid.item_selected.connect(_grid_changed.unbind(1))
	_pivot.item_selected.connect(_pivot_changed.unbind(1))
	for index in _custom.size():
		_custom[index].value_changed.connect(_custom_changed.unbind(1))
		_coordinates[index].value_changed.connect(_coordinate_changed.bind(index))
		_offsets[index].value_changed.connect(_offset_changed.bind(index))
		_rotations[index].value_changed.connect(_rotation_changed.unbind(1))
	_context_enabled.toggled.connect(_context_toggled)
	confirmed.connect(_commit)


func open_for(session: RefCounted) -> bool:
	placement = session
	if placement == null or placement.target() == null:
		return false
	_updating = true
	_grid.clear()
	for index in placement.grids.size():
		_grid.add_item(placement.grid_label(index),index)
	_grid.select(0)
	_pivot.select(0)
	for number in _custom:
		number.value = 0
	for number in _rotations:
		number.value = 0
	_updating = false
	_build_preview()
	_pivot_local = placement.pivot_local(0,Vector3.ZERO,0)
	_desired_world = placement.initial_world()*_pivot_local
	_sync_fields()
	_update_plan()
	popup_centered(Vector2i(720,640))
	return true


func _number(minimum: float,maximum: float,step: float) -> SpinBox:
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.allow_greater = true
	number.allow_lesser = true
	number.step = step
	number.custom_arrow_step = step
	number.update_on_text_changed = false
	return number


func _grid_changed() -> void:
	if _updating or placement == null:
		return
	_preserve_transform_with_new_pivot()


func _pivot_changed() -> void:
	if _updating or placement == null:
		return
	_preserve_transform_with_new_pivot()


func _custom_changed() -> void:
	if _updating or placement == null or _pivot.get_selected_id() != 2:
		return
	_preserve_transform_with_new_pivot()


func _preserve_transform_with_new_pivot() -> void:
	var current: Transform3D = _planned_world
	_pivot_local = placement.pivot_local(_pivot.get_selected_id(),_vector(_custom),_grid.get_selected_id())
	_desired_world = current*_pivot_local
	_sync_fields()
	_update_plan()


func _coordinate_changed(value: float,index: int) -> void:
	if _updating or placement == null:
		return
	var coordinates: Vector3 = placement.coordinate_for_world(_desired_world,_grid.get_selected_id())
	coordinates[index] = value
	if _snap_enabled.button_pressed:
		coordinates[index] = Math.snap_vox(Vector3(coordinates[index],0,0),_snap_step.value).x
	_desired_world = placement.world_for_coordinate(coordinates,_grid.get_selected_id())
	_sync_fields()
	_update_plan()


func _offset_changed(value: float,index: int) -> void:
	if _updating or placement == null:
		return
	var initial: Vector3 = placement.initial_world()*_pivot_local
	var initial_coordinates: Vector3 = placement.coordinate_for_world(initial,_grid.get_selected_id())
	var offset: Vector3 = placement.coordinate_for_world(_desired_world,_grid.get_selected_id())-initial_coordinates
	offset[index] = value
	var coordinates: Vector3 = initial_coordinates+offset
	if _snap_enabled.button_pressed:
		coordinates[index] = Math.snap_vox(Vector3(coordinates[index],0,0),_snap_step.value).x
	_desired_world = placement.world_for_coordinate(coordinates,_grid.get_selected_id())
	_sync_fields()
	_update_plan()


func _rotation_changed() -> void:
	if not _updating:
		_update_plan()


func _rotate_quarter(index: int,amount: float) -> void:
	_rotations[index].value += amount


func _snap_now() -> void:
	if placement == null:
		return
	var coordinates: Vector3 = placement.coordinate_for_world(_desired_world,_grid.get_selected_id())
	coordinates = Math.snap_vox(coordinates,_snap_step.value)
	_desired_world = placement.world_for_coordinate(coordinates,_grid.get_selected_id())
	_sync_fields()
	_update_plan()


func _sync_fields() -> void:
	if placement == null:
		return
	_updating = true
	var grid_index := _grid.get_selected_id()
	var coordinates: Vector3 = placement.coordinate_for_world(_desired_world,grid_index)
	var initial: Vector3 = placement.coordinate_for_world(placement.initial_world()*_pivot_local,grid_index)
	for index in 3:
		_coordinates[index].set_value_no_signal(coordinates[index])
		_offsets[index].set_value_no_signal(coordinates[index]-initial[index])
	var steps: Vector3 = placement.grid_steps(grid_index)
	_grid_help.text = "1 vox выбранной мировой сетки: X %s, Y %s, Z %s единиц сцены. Начало координат мира = 0; ориентация детали не выравнивается." % [str(snappedf(steps.x,0.0001)),str(snappedf(steps.y,0.0001)),str(snappedf(steps.z,0.0001))]
	_updating = false


func _update_plan() -> void:
	if placement == null:
		return
	var coordinates: Vector3 = placement.coordinate_for_world(_desired_world,_grid.get_selected_id())
	var result: Dictionary = placement.plan(_pivot_local,coordinates,_vector(_rotations),_grid.get_selected_id())
	if not result.get("ok",false):
		_status.text = result.get("error","Предпросмотр не построен.")
		get_ok_button().disabled = true
		return
	_planned_world = result.world
	for entry in _preview_relatives:
		var visual := entry.visual as Node3D
		if is_instance_valid(visual):
			visual.transform = _planned_world*entry.relative
	_pivot_preview.position = result.pivot_world
	_frame_camera()
	var rotation := _vector(_rotations)
	_status.text = "%s · опорная точка в мире %s · Δ поворот %s. До «Применить» сцена и voxel-файлы не меняются." % [placement.target().name,result.pivot_world,rotation]
	get_ok_button().disabled = false


func _build_preview() -> void:
	_preview_relatives.clear()
	for child in _selected_preview.get_children():
		child.free()
	var selected: Node3D = placement.target()
	var initial: Transform3D = placement.initial_world()
	var nodes: Array[Node] = [selected]
	while not nodes.is_empty():
		var node := nodes.pop_back() as Node
		if node is MeshInstance3D:
			var source := node as MeshInstance3D
			if source.mesh != null and source.is_visible_in_tree() and source.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				var copy := MeshInstance3D.new()
				copy.mesh = source.mesh
				copy.material_override = source.material_override
				copy.material_overlay = source.material_overlay
				copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				for surface in source.mesh.get_surface_count():
					copy.set_surface_override_material(surface,source.get_surface_override_material(surface))
				_selected_preview.add_child(copy)
				_preview_relatives.append({"visual":copy,"relative":initial.affine_inverse()*source.global_transform})
		for child in node.get_children():
			nodes.append(child)
	var report: Dictionary = _context.rebuild(placement.scene(),selected,Transform3D.IDENTITY)
	if report.has("error"):
		_context_enabled.button_pressed = false
	_context.visible = _context_enabled.button_pressed
	_context.set_opacity(0.22)
	var extent: Vector3 = placement.bounds_local.size
	var world_extent := Vector3(
		(initial.basis*Vector3(extent.x,0,0)).length(),
		(initial.basis*Vector3(0,extent.y,0)).length(),
		(initial.basis*Vector3(0,0,extent.z)).length(),
	)
	var marker: float = maxf(0.05,maxf(world_extent.x,maxf(world_extent.y,world_extent.z))*0.018)
	_pivot_preview.scale = Vector3.ONE*marker*2.0


func _frame_camera() -> void:
	var box: AABB = _planned_bounds()
	var extent: float = maxf(1.0,maxf(box.size.x,maxf(box.size.y,box.size.z)))
	_camera.size = extent*1.8
	var center := box.get_center()
	_camera.position = center+Vector3(1,0.75,1).normalized()*extent*2.5
	_camera.look_at(center)


func _planned_bounds() -> AABB:
	var local: AABB = placement.bounds_local
	var first := true
	var result := AABB()
	for x in [local.position.x,local.end.x]:
		for y in [local.position.y,local.end.y]:
			for z in [local.position.z,local.end.z]:
				var point := _planned_world*Vector3(x,y,z)
				if first:
					result = AABB(point,Vector3.ZERO)
					first = false
				else:
					result = result.expand(point)
	return result


func _context_toggled(enabled: bool) -> void:
	_context.visible = enabled


func _commit() -> void:
	if not placement.commit():
		_status.text = placement.error
		get_ok_button().disabled = true
		return
	var selected: Node3D = placement.target()
	hide()
	applied.emit(selected)


func _vector(values: Array[SpinBox]) -> Vector3:
	return Vector3(values[0].value,values[1].value,values[2].value)
