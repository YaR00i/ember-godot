@tool
extends ConfirmationDialog
const Session = preload("res://addons/ember_import/ember_walk_surface_session.gd")
const Surface = preload("res://addons/ember_import/ember_walk_surface.gd")
const Context = preload("res://addons/ember_import/ember_voxel_canvas_context.gd")
signal applied
var session: RefCounted
var _undo: Object
var _numbers: Array[SpinBox] = []
var _status: Label
var _context: Node3D
var _overlay: Node3D
var _camera: Camera3D
var _visible: CheckBox
var _busy := false

func _init() -> void:
	title = "Поверхность прохода"
	dialog_hide_on_ok = false
	get_ok_button().text = "Применить"
	get_cancel_button().text = "Отмена"
	var layout := HBoxContainer.new()
	add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(325, 510)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(fields)
	var info := Label.new()
	info.text = "Невидимая в игре опора. Размеры и координаты — в локальных единицах родителя. Доски и их коллизия остаются без изменений."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(info)
	for caption in ["Ширина X", "Длина Z", "Центр X", "Высота Y", "Центр Z", "Наклон X°", "Поворот Y°", "Наклон Z°"]:
		var row := HBoxContainer.new()
		fields.add_child(row)
		var label := Label.new()
		label.text = caption
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var number := SpinBox.new()
		number.min_value = -100000
		number.max_value = 100000
		number.step = 0.01
		number.custom_minimum_size.x = 125
		row.add_child(number)
		_numbers.append(number)
		number.value_changed.connect(_refresh.unbind(1))
	_visible = CheckBox.new()
	_visible.text = "Показать физическую поверхность"
	_visible.button_pressed = true
	fields.add_child(_visible)
	_visible.toggled.connect(func(value: bool): _overlay.visible = value)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(_status)
	var viewport_box := SubViewportContainer.new()
	viewport_box.name = "WalkPreview"
	viewport_box.stretch = true
	viewport_box.custom_minimum_size = Vector2(350, 510)
	layout.add_child(viewport_box)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_box.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	_context = Context.new()
	world.add_child(_context)
	_overlay = Node3D.new()
	world.add_child(_overlay)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.current = true
	_camera.far = 100000
	world.add_child(_camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	world.add_child(light)
	confirmed.connect(_commit)

func open_for(selected: Node3D, scene: Node, undo: Object) -> bool:
	session = Session.new()
	_undo = undo
	if not session.open(selected, scene):
		_status.text = session.error
		return false
	var report: Dictionary = _context.rebuild(scene, selected, Transform3D.IDENTITY, false)
	if report.has("error"):
		_status.text = report.error
		return false
	_busy = true
	var pos: Vector3 = session.initial_pose.origin
	var angles: Vector3 = session.initial_pose.basis.get_euler() * 180.0 / PI
	var values := [session.initial_size.x, session.initial_size.y, pos.x, pos.y, pos.z, angles.x, angles.y, angles.z]
	for index in values.size():
		_numbers[index].value = values[index]
	_busy = false
	_refresh()
	popup_centered(Vector2i(730, 620))
	return true

func _refresh() -> void:
	if _busy or session == null:
		return
	get_ok_button().disabled = true
	var size := Vector2(_numbers[0].value, _numbers[1].value)
	var angles := Vector3(_numbers[5].value, _numbers[6].value, _numbers[7].value) * PI / 180.0
	var basis := Basis.from_euler(angles) * Basis.from_scale(session.initial_pose.basis.get_scale())
	var pose := Transform3D(basis, Vector3(_numbers[2].value, _numbers[3].value, _numbers[4].value))
	if not session.plan(size, pose):
		_status.text = session.error
		return
	for child in _overlay.get_children():
		child.free()
	_overlay.transform = session.world_pose()
	var plane := MeshInstance3D.new()
	plane.mesh = Surface.visual_mesh(size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.1, 0.9, 0.75, 0.3)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material_override = material
	_overlay.add_child(plane)
	_add_lines(Surface.grid_lines(size), Color(0.1, 1, 0.85))
	var red := PackedVector3Array()
	for index in mini(128, session.warnings.size()):
		var box: AABB = session.warnings[index]
		for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
			red.append(box.get_endpoint(edge[0]))
			red.append(box.get_endpoint(edge[1]))
	if not red.is_empty():
		_add_lines(red, Color(1, 0.25, 0.15))
	var bounds: AABB = session.world_pose() * AABB(Vector3(-size.x * 0.5, 0, -size.y * 0.5), Vector3(size.x, 0.1, size.y))
	var extent := maxf(1, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
	_camera.size = extent * 1.5 * maxf(1.0, 510.0 / 350.0)
	_camera.position = bounds.get_center() + Vector3(1, 0.85, 1).normalized() * extent * 2.5
	_camera.look_at(bounds.get_center())
	_status.text = "Слой коллизии 1 — общая физика мира. Сетка в игру не сохраняется."
	if not session.warnings.is_empty():
		_status.text += "\nВозможные выступы: %d (красные рамки). Проверка по видимым габаритам, не гарантия свободного прохода. Поднимите/наклоните площадку или поправьте детали." % session.warnings.size()
	_status.text += "\nВход должен стыковаться с землёй. Это не автоматический подъём на ступеньки."
	_status.text += "\nДля исследовательской сцены. Клеточные высоты боевой арены не обновляются."
	get_ok_button().disabled = false

func _add_lines(vertices: PackedVector3Array, color: Color) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = color
	visual.material_override = material
	_overlay.add_child(visual)

func _commit() -> void:
	if session.commit(_undo) == null:
		_status.text = session.error
		get_ok_button().disabled = true
		return
	hide()
	applied.emit()
