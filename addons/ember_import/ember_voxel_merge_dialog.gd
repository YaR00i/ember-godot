@tool
extends "res://addons/ember_import/ember_voxel_shape_dialog.gd"
const Session = preload("res://addons/ember_import/ember_voxel_merge_session.gd")
var _session: RefCounted
var _selection: Array = []
var _primary: OptionButton
var _align: CheckBox
var _bake_orientation: CheckBox
var _scene_orientation: CheckBox
var _presentation: Node3D
var _preview_container: SubViewportContainer
var _local_bounds := AABB()
var _view_bounds := AABB()
var _view_yaw := PI/4.0
var _view_pitch := atan(0.85/sqrt(2.0))
var _view_zoom := 1.0
var _orbiting := false
var _separating := false
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR

func open_merge(selection: Array, scene: Node, undo: Object, separating := false) -> void:
	_root = scene
	_undo = undo
	_selection = selection.duplicate()
	_separating = separating
	title = "Разобрать текущую склейку" if separating else "Склеить voxel-детали"
	size = Vector2i(720,660)
	get_ok_button().text = "Разобрать" if separating else "Склеить"
	for control in [_title,_kind,_density,_color,_large_ack]:
		control.hide()
	for control in _sizes:
		control.get_parent().hide()
	_primary = OptionButton.new()
	_primary.fit_to_longest_item = false
	_primary.clip_text = true
	_primary.tooltip_text = "При пересечении вокселей цвет и принадлежность основной детали имеют приоритет."
	for node in selection:
		_primary.add_item("Основная деталь: " + str(node.name))
	_primary.visible = not separating
	_primary.item_selected.connect(func(_index):
		_align.set_pressed_no_signal(false)
		if is_instance_valid(_preview):
			_preview.free()
		_session = null
		get_ok_button().disabled = true
		_status.text = "Основная деталь изменена. Обновите предпросмотр."
	)
	_status.get_parent().add_child(_primary)
	_status.get_parent().move_child(_primary,0)
	_align = CheckBox.new()
	_align.text = "Совместить сетки"
	_align.tooltip_text = "Основная деталь неподвижна. Остальные сдвигаются к ближайшей ячейке её сетки. Это не притягивание поверхностей; поворот и масштаб не меняются. Пока вы не нажали «Склеить», сцена не меняется."
	_align.visible = not separating
	_align.toggled.connect(func(_enabled: bool): _prepare())
	_status.get_parent().add_child(_align)
	_status.get_parent().move_child(_align,1)
	_bake_orientation = CheckBox.new()
	_bake_orientation.text = "Запечь ориентацию сцены"
	_bake_orientation.tooltip_text = "Переносит поворот сцены на 90° в сами воксели: Canvas и библиотека откроют модель в этой ориентации. Положение на карте сохраняется. Только одинаковый масштаб XYZ, без отражения, перекоса и округления угла. Выключено по умолчанию; исходные файлы не меняются."
	_bake_orientation.visible = not separating
	_bake_orientation.toggled.connect(func(_enabled: bool): _prepare())
	_status.get_parent().add_child(_bake_orientation)
	_status.get_parent().move_child(_bake_orientation,2)
	_scene_orientation = CheckBox.new()
	_scene_orientation.text = "Ориентация как в сцене"
	_scene_orientation.button_pressed = true
	_scene_orientation.tooltip_text = "Включено: поворот и пропорции как на карте. Выключено: локальные оси основной детали. Меняется только предпросмотр, не результат склейки."
	_scene_orientation.toggled.connect(func(_enabled: bool): _update_orientation())
	_status.get_parent().add_child(_scene_orientation)
	_status.get_parent().move_child(_scene_orientation,3)
	var view_controls := HBoxContainer.new()
	var hint := Label.new()
	hint.text = "ЛКМ / СКМ: вращать вид · колесо: масштаб"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_controls.add_child(hint)
	var reset := Button.new()
	reset.text = "Сбросить вид"
	reset.pressed.connect(_reset_view)
	view_controls.add_child(reset)
	_status.get_parent().add_child(view_controls)
	_status.get_parent().move_child(view_controls,4)
	_presentation = Node3D.new()
	_world.add_child(_presentation)
	_preview_container = _world.get_parent().get_parent() as SubViewportContainer
	# Keep the object visible before long alignment reports in this scroll box.
	_status.get_parent().move_child(_preview_container,5)
	_preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview_container.mouse_force_pass_scroll_events = false
	_preview_container.gui_input.connect(_view_input)
	_preview_container.resized.connect(_update_camera)
	_preview_container.mouse_exited.connect(func(): _orbiting = false)
	_world.get_parent().handle_input_locally = false
	_status.custom_minimum_size.x = 460
	_prepare()
	popup_centered()

func _prepare() -> void:
	if _primary == null:
		return
	get_ok_button().disabled = true
	if is_instance_valid(_preview):
		_preview.free()
	var ordered := _selection.duplicate()
	if not _separating and not ordered.is_empty():
		var primary: Node = ordered.pop_at(_primary.selected)
		ordered.push_front(primary)
	_session = Session.new()
	_session.source_directory = source_directory
	_session.prefab_directory = prefab_directory
	if not _session.prepare(ordered,_root,_separating,_align.button_pressed,_bake_orientation.button_pressed and not _separating):
		_status.text = _session.error
		return
	var source: EmberVoxelModelResource = _session.preview
	var packed := EmberVoxelPrefab.prepare_resource(source)
	if packed == null:
		_status.text = "Не удалось построить предпросмотр."
		return
	_preview = packed.instantiate()
	_presentation.add_child(_preview)
	_preview.transform = _preview.get_node("Mesh").transform.affine_inverse()
	var bounds: AABB = _preview.get_node("Mesh").get_aabb()
	for adjustment in _session.adjustments:
		var original: MeshInstance3D = ordered[adjustment.source_index].get_node("Mesh")
		var ghost := MeshInstance3D.new()
		ghost.mesh = original.mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.15,0.8,1,0.3)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		ghost.material_override = material
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.name = "OriginalPosition_%d" % adjustment.source_index
		_preview.add_child(ghost)
		var local_frame: Transform3D = _session.frame.affine_inverse()*adjustment.before
		ghost.transform = _preview.transform.affine_inverse()*local_frame
		bounds = bounds.merge(local_frame*original.get_aabb())
	_local_bounds = bounds
	if not _session.overlap.is_empty():
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE/float(source.normalized_density())*1.015
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1,0.15,0.1,0.65)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		cube.material = material
		instances.mesh = cube
		instances.instance_count = _session.overlap.size()
		for i in _session.overlap.size():
			var cell := Session.Merge.Selection.cell_of(_session.overlap[i],source.grid_size())
			instances.set_instance_transform(i,Transform3D(Basis.IDENTITY,(Vector3(cell)+Vector3.ONE*0.5)/source.normalized_density()))
		var overlay := MultiMeshInstance3D.new()
		overlay.multimesh = instances
		_preview.add_child(overlay)
		overlay.transform = _preview.transform.affine_inverse()
	_update_orientation()
	_status.text = "%d частей · сетка %s · %d vox/block.\n" % [source.merge_parts.size(),source.grid_size(),source.normalized_density()]
	if _session.orientation_baked:
		_status.text += "Ориентация сцены записана в сетку модели для Canvas и библиотеки.\n"
	if _separating:
		var labels := PackedStringArray()
		for item in _session.outputs:
			labels.append(item.source.display_name)
		_status.text += "Получится %d объектов: %s. Удалённые воксели не вернутся.\n" % [_session.outputs.size(),", ".join(labels)]
	else:
		_status.text += "Красным: %d перекрывающихся вокселей; приоритет основной детали.\n" % _session.overlap.size()
	if not _session.adjustments.is_empty():
		_status.text += "Голубой полупрозрачный силуэт — прежнее положение. Основная деталь неподвижна.\n"
		var shifts := PackedStringArray()
		for item in _session.adjustments:
			var delta: Vector3 = item.delta_vox
			shifts.append("%s: Δ X %+.3f · Y %+.3f · Z %+.3f vox" % [item.name,delta.x,delta.y,delta.z])
		_status.tooltip_text = "Сдвиги в вокселях, по осям сетки основной детали:\n" + "\n".join(shifts)
		_status.text += "\n".join(shifts.slice(0,4))+"\n"
		if shifts.size() > 4:
			_status.text += "Ещё %d сдвигов — в подсказке.\n" % (shifts.size()-4)
		_status.text += "При подтверждении применятся показанные сдвиги и склейка — одним Undo. "
	else:
		_status.tooltip_text = ""
		_status.text += "Положение и цвета сохраняются. Одна Undo-команда. "
	_status.text += "Исходные файлы не удаляются. Большая операция может занять несколько секунд."
	get_ok_button().disabled = false

func _update_orientation() -> void:
	if not is_instance_valid(_preview) or _session == null:
		return
	var basis := Basis.IDENTITY
	if _scene_orientation.button_pressed:
		basis = _session.frame.basis
		# Rebase the scene frame for this isolated viewport, preserving rotation,
		# reflection/shear and relative scale without huge world coordinates.
		var uniform := maxf(basis.x.length(),maxf(basis.y.length(),basis.z.length()))
		basis = basis.scaled(Vector3.ONE/uniform)
	_presentation.transform = Transform3D(basis,-(basis*_local_bounds.get_center()))
	_view_bounds = _presentation.transform*_local_bounds
	_reset_view()

func _reset_view() -> void:
	_view_yaw = PI/4.0
	_view_pitch = atan(0.85/sqrt(2.0))
	_view_zoom = 1.0
	_orbiting = false
	_update_camera()

func _update_camera() -> void:
	if not is_instance_valid(_preview) or _preview_container == null:
		return
	var center := _view_bounds.get_center()
	var radius := maxf(0.25,_view_bounds.size.length())
	var direction := Vector3(sin(_view_yaw)*cos(_view_pitch),sin(_view_pitch),cos(_view_yaw)*cos(_view_pitch))
	_camera.position = center+direction*radius*2.0
	_camera.look_at(center,Vector3.UP)
	_camera.near = 0.001
	_camera.far = maxf(10.0,radius*5.0)
	var projected: AABB = _camera.transform.affine_inverse()*_view_bounds
	var aspect := maxf(0.01,_preview_container.size.x/maxf(1.0,_preview_container.size.y))
	_camera.size = maxf(0.05,maxf(projected.size.y,projected.size.x/aspect)*1.15)*_view_zoom

func _view_input(event: InputEvent) -> void:
	if not is_instance_valid(_preview):
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]:
			_orbiting = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_view_zoom = clampf(_view_zoom*(0.85 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/0.85),0.2,5.0)
			_update_camera()
		else:
			return
		_preview_container.accept_event()
	elif event is InputEventMouseMotion and _orbiting:
		_view_yaw -= event.relative.x*0.008
		_view_pitch = clampf(_view_pitch+event.relative.y*0.008,-PI*0.49,PI*0.49)
		_update_camera()
		_preview_container.accept_event()

func _commit() -> void:
	get_ok_button().disabled = true
	if _session == null or not _session.commit(_undo):
		_status.text = _session.error if _session != null else "Обновите предпросмотр."
		return
	if Engine.is_editor_hint():
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()
	hide()
	queue_free()
