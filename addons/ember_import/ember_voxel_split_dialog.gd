@tool
extends "res://addons/ember_import/ember_voxel_shape_dialog.gd"
const Split = preload("res://addons/ember_import/ember_voxel_object_split.gd")
var _splitter: RefCounted
var _target_ref: WeakRef
var _section: OptionButton
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR
var can_commit := Callable()
var _dock_layout := false

func _init() -> void:
	super._init()
	_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.hide()
	_kind.hide()
	_density.hide()
	_color.hide()
	_large_ack.hide()
	for control in _sizes:
		control.get_parent().hide()
	_section = OptionButton.new()
	_section.fit_to_longest_item = false; _section.clip_text = true
	_section.tooltip_text = "Размер секции по X/Z в вокселях. Каждая секция сохраняет полную высоту исходника."
	for step in [32,64,128]:
		_section.add_item("Секции %d × %d vox · полная высота" % [step,step],step)
	_section.select(1)
	_section.item_selected.connect(_invalidate_split.unbind(1))
	_status.get_parent().add_child(_section)
	_status.get_parent().move_child(_section,0)

func use_dock_layout() -> void:
	_dock_layout = true; super.use_dock_layout(); pin_preview_action()

func open_split(prop: EmberVoxelProp, scene: Node, undo: Object) -> void:
	_root = scene; _undo = undo; _target_ref = weakref(prop)
	title = "Разрезать voxel-объект на секции"; _heading.text = title
	get_ok_button().text = "Разрезать" if _dock_layout else "Разрезать на отдельные объекты"
	get_ok_button().tooltip_text = "Заменить исходник группой отдельных секций одной отменяемой командой."
	_section.select(1); _invalidate_split(); show()
	if not _dock_layout:
		size = Vector2(680,620); _prepare(); popup_centered()

func matches_context(prop: Node, scene: Node) -> bool:
	return _root == scene and _target_ref != null and _target_ref.get_ref() == prop

func is_dirty() -> bool:
	return _root != null and _target_ref != null

func _invalidate_split() -> void:
	_splitter = null
	if is_instance_valid(_preview): _preview.free()
	_preview = null; get_ok_button().disabled = true; _status.tooltip_text = ""
	_status.text = "До подтверждения исходник и файлы сохраняются. Обновите предпросмотр."

func cancel_edit() -> void:
	_splitter = null; _target_ref = null; super.cancel_edit()

func _prepare() -> void:
	if _target_ref == null or _section == null:
		return
	get_ok_button().disabled = true
	if is_instance_valid(_preview): _preview.free()
	_preview = null; _splitter = null
	if can_commit.is_valid() and not can_commit.call():
		_status.text = "Сначала сохраните или отмените правки Canvas. Затем обновите предпросмотр."; return
	_splitter = Split.new()
	_splitter.source_directory = source_directory
	_splitter.prefab_directory = prefab_directory
	var prop := _target_ref.get_ref() as EmberVoxelProp
	if not _splitter.prepare(prop,_root,_section.get_selected_id()):
		_status.text = _splitter.error
		return
	if is_instance_valid(_preview):
		_preview.free()
	_preview = Node3D.new()
	_world.add_child(_preview)
	var original := prop.get_node("Mesh") as MeshInstance3D
	var visual := MeshInstance3D.new()
	visual.mesh = original.mesh
	visual.transform = original.transform
	_preview.add_child(visual)
	var lines := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1,0.8,0.1)
	material.no_depth_test = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES,material)
	for part in _splitter.parts:
		var corners: Array[Vector3] = []
		for i in 8:
			var corner: Vector3 = Vector3(part.origin) + Vector3(part.size) * Vector3(i&1,(i>>1)&1,(i>>2)&1)
			corners.append(original.transform * (corner / _splitter.source.normalized_density()))
		for i in 8:
			for axis in [1,2,4]:
				if (i & axis) == 0:
					lines.surface_add_vertex(corners[i])
					lines.surface_add_vertex(corners[i|axis])
	lines.surface_end()
	var wire := MeshInstance3D.new()
	wire.mesh = lines
	_preview.add_child(wire)
	var bounds := original.transform * original.get_aabb()
	var center := bounds.get_center()
	_camera.size = maxf(1,bounds.size[bounds.size.max_axis_index()])
	_camera.position = center + Vector3(1,0.8,1).normalized()*_camera.size*2
	_camera.look_at(center)
	_status.text = "%d самостоятельных секций. Жёлтые линии — границы реза X/Z.\nВысота, цвета и положение сохраняются. Пустые секции тоже сохраняются как редактируемые холсты.\nПрименение может занять несколько секунд. Одна Undo-команда; файлы при Undo не удаляются." % _splitter.parts.size()
	_status.text = "Сетка хранения: %s vox (включая пустой запас).\nПоследняя секция: %s vox.\n" % [_splitter.source.grid_size(),_splitter.parts.back().size] + _status.text
	var coordinates := "Границы в координатах исходной сетки, верхняя граница не включена:\n"
	for part in _splitter.parts:
		coordinates += "%s → %s\n" % [part.origin,part.origin+part.size]
	_status.tooltip_text = coordinates
	get_ok_button().disabled = false

func _commit() -> void:
	get_ok_button().disabled = true
	if can_commit.is_valid() and not can_commit.call():
		_status.text = "Сначала сохраните или отмените правки Canvas. Затем обновите предпросмотр."; return
	if _splitter == null:
		_status.text = "Обновите предпросмотр."; return
	var group: Node3D = _splitter.commit(_undo)
	if group == null:
		_status.text = _splitter.error
		return
	cancel_edit()
	if Engine.is_editor_hint():
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(group)
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()
	if not _dock_layout: queue_free()
