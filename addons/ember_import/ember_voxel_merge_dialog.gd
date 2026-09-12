@tool
extends "res://addons/ember_import/ember_voxel_shape_dialog.gd"
const Session = preload("res://addons/ember_import/ember_voxel_merge_session.gd")
var _session: RefCounted
var _selection: Array = []
var _primary: OptionButton
var _align: CheckBox
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
	if not _session.prepare(ordered,_root,_separating,_align.button_pressed):
		_status.text = _session.error
		return
	var source: EmberVoxelModelResource = _session.preview
	var packed := EmberVoxelPrefab.prepare_resource(source)
	if packed == null:
		_status.text = "Не удалось построить предпросмотр."
		return
	_preview = packed.instantiate()
	_world.add_child(_preview)
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
	var center := bounds.get_center()
	_camera.size = maxf(0.25,bounds.size.length()*0.85)
	_camera.position = center+Vector3(1,0.85,1).normalized()*_camera.size*2
	_camera.look_at(center)
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
	_status.text = "%d частей · сетка %s · %d vox/block.\n" % [source.merge_parts.size(),source.grid_size(),source.normalized_density()]
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

func _commit() -> void:
	get_ok_button().disabled = true
	if _session == null or not _session.commit(_undo):
		_status.text = _session.error if _session != null else "Обновите предпросмотр."
		return
	if Engine.is_editor_hint():
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()
	hide()
	queue_free()
