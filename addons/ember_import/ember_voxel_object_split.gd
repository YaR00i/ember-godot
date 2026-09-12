@tool
extends RefCounted
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR
var error := ""
var parts: Array[Dictionary] = []
var source: EmberVoxelModelResource
var _target: WeakRef
var _scene: WeakRef
var _session: RefCounted
var _pose := Transform3D.IDENTITY
var _visual_pose := Transform3D.IDENTITY

func prepare(prop: EmberVoxelProp, scene: Node, section: int) -> bool:
	parts.clear()
	error = ""
	if not is_instance_valid(prop) or not is_instance_valid(scene) or not scene.is_ancestor_of(prop) or prop.owner != scene or section not in [32,64,128]:
		return _fail("Выберите обычный voxel-объект сцены; секция 32, 64 или 128 vox.")
	if prop.get_script() != preload("res://scripts/ember_voxel_prop.gd") or prop.water_contact_enabled or prop.is_set_as_top_level():
		return _fail("Объект имеет отдельное поведение; автоматическая резка остановлена.")
	if not FileAccess.file_exists(source_directory.path_join(prop.model_id + ".tres")):
		return _fail("Сначала сохраните объект в Canvas как native voxel-модель.")
	if _has_persistent_signals(prop):
		return _fail("Объект участвует в сохраняемых сигналах; резка не будет разрывать связи.")
	for node in prop.find_children("*","",true,false):
		if _has_persistent_signals(node):
			return _fail("Часть объекта участвует в сохраняемых сигналах; резка остановлена.")
		if str(prop.get_path_to(node)) not in ["Mesh","Collision","Collision/Shape"] or node.get_script() != null:
			return _fail("У объекта есть дополнительные узлы или скрипты. Резка не будет удалять их.")
		if node is StaticBody3D and (node.physics_material_override != null or node.constant_linear_velocity != Vector3.ZERO or node.constant_angular_velocity != Vector3.ZERO or not node.get_collision_exceptions().is_empty()):
			return _fail("У коллизии есть отдельный материал или поведение; резка остановлена.")
		if node is MeshInstance3D and (node.transparency != 0 or node.material_overlay != null or node.skin != null):
			return _fail("У модели есть отдельные визуальные настройки; резка остановлена.")
	_session = Session.new()
	_session.source_directory = source_directory
	_session.prefab_directory = prefab_directory
	if not _session.open(prop,scene,null):
		return _fail(_session.error)
	source = _session.draft
	if source.emissive_casts_light or not source.emissive_lights.is_empty() or not source.surface_fill_levels.is_empty() or not source.surface_fill_materials.is_empty() or not source.surface_fill_palette.is_empty():
		return _fail("Объекты с заливкой воды или собственными источниками света пока не режутся.")
	if source.voxels.size() > Shapes.MAX_CELLS:
		return _fail("Первый этап резки ограничен 524 288 исходными ячейками.")
	# Reject authored generated-node overrides rather than silently lose behavior.
	var template := EmberVoxelPrefab.prepare_resource(source).instantiate() as EmberVoxelProp
	template.configure_voxel_scale(source.normalized_density(),prop.block_world_size)
	var original: Dictionary = _session._capture(prop).nodes
	var defaults: Dictionary = _session._capture(template).nodes
	var compatible := true
	for path in original:
		for key in original[path]:
			if key in ["mesh","shape"]:
				continue
			if original[path][key] != defaults.get(path,{}).get(key):
				compatible = false
		var node := prop.get_node(NodePath(path))
		if node is Node3D and not node.transform.is_equal_approx(template.get_node(NodePath(path)).transform):
			compatible = false
	template.free()
	if not compatible:
		return _fail("У геометрии или коллизии есть отдельные настройки. Резка пока поддерживает стандартные производные узлы; положение и масштаб всего объекта допустимы.")
	var size := source.grid_size()
	var count := ceili(float(size.x)/section) * ceili(float(size.z)/section)
	if count < 2 or count > 32:
		return _fail("Получится %d секций. Выберите размер, дающий от 2 до 32 деталей." % count)
	for z in range(0,size.z,section):
		for x in range(0,size.x,section):
			var extent := Vector3i(mini(section,size.x-x),size.y,mini(section,size.z-z))
			parts.append({"origin":Vector3i(x,0,z),"size":extent})
	_target = weakref(prop)
	_scene = weakref(scene)
	_pose = prop.transform
	_visual_pose = prop.get_node("Mesh").transform
	return true

func _extract(part: Dictionary, id: String) -> EmberVoxelModelResource:
	var result := source.duplicate(true) as EmberVoxelModelResource
	var size: Vector3i = part.size
	var origin: Vector3i = part.origin
	var old := source.grid_size()
	var density := source.normalized_density()
	result.model_id = id
	result.display_name = "%s · %d,%d" % [source.display_name,origin.x,origin.z]
	result.size_blocks = Vector3i(size.x/density,ceili(float(size.y)/density),size.z/density)
	result.height_voxels = size.y
	for channel in ["voxels","emissive","shine","transparency","transmittance","collision_voxels"]:
		var values: PackedByteArray = source.get(channel)
		if values.is_empty():
			continue
		var sliced := PackedByteArray()
		sliced.resize(size.x*size.y*size.z)
		for y in size.y:
			for z in size.z:
				var start := VoxMesher.cell_index(origin.x,y,origin.z+z,old.x,old.z)
				var dest := VoxMesher.cell_index(0,y,z,size.x,size.z)
				for x in size.x:
					sliced[dest+x] = values[start+x]
		result.set(channel,sliced)
	if not source.voxel_part_ids.is_empty():
		result.voxel_part_ids = PackedInt32Array()
		result.voxel_part_ids.resize(size.x*size.y*size.z)
		for y in size.y:
			for z in size.z:
				for x in size.x:
					result.voxel_part_ids[VoxMesher.cell_index(x,y,z,size.x,size.z)] = source.voxel_part_ids[VoxMesher.cell_index(x+origin.x,y+origin.y,z+origin.z,old.x,old.z)]
	result.voxel_groups = []
	for group in source.voxel_groups:
		var indices := PackedInt32Array()
		for index in group.get("indices",[]):
			var x: int = index % old.x
			var z: int = (index / old.x) % old.z
			var y: int = index / (old.x*old.z)
			if x >= origin.x and x < origin.x+size.x and z >= origin.z and z < origin.z+size.z:
				indices.append(VoxMesher.cell_index(x-origin.x,y,z-origin.z,size.x,size.z))
		if not indices.is_empty():
			var copy: Dictionary = group.duplicate(true)
			copy.indices = indices
			result.voxel_groups.append(copy)
	return result

func commit(undo: Object) -> Node3D:
	var prop := _target.get_ref() as EmberVoxelProp if _target != null else null
	var scene := _scene.get_ref() as Node if _scene != null else null
	if prop == null or scene == null or prop.get_parent() == null or prop.transform != _pose:
		_fail("Объект изменился или удалён. Обновите предпросмотр.")
		return null
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != scene:
		_fail("Активная сцена изменилась.")
		return null
	var fresh = get_script().new()
	if FileAccess.get_sha256(_session._source_path) != _session._source_hash:
		_fail("Файл источника изменён после предпросмотра. Обновите предпросмотр.")
		return null
	fresh.source_directory = source_directory
	fresh.prefab_directory = prefab_directory
	var section: int = maxi(parts[0].size.x,parts[0].size.z)
	if not fresh.prepare(prop,scene,section) or not _session._same_data(fresh.source,source):
		_fail("Источник или настройки изменились. Обновите предпросмотр.")
		return null
	var group := Node3D.new()
	group.name = prop.name
	group.transform = prop.transform
	group.visible = prop.visible
	group.process_mode = prop.process_mode
	group.unique_name_in_owner = prop.unique_name_in_owner
	for meta in prop.get_meta_list():
		if meta not in [EmberVoxelPrefab.SOURCE_SIGNATURE_META,Session.UNIQUE_META]:
			group.set_meta(meta,prop.get_meta(meta))
	for tag in prop.get_groups():
		if not str(tag).begins_with("_"):
			group.add_to_group(tag,true)
	var batch := str(Time.get_ticks_usec())
	var used_placements := EmberSceneAuthoring.placement_ids(scene)
	for index in parts.size():
		var part := parts[index]
		var id := "%s_part_%s_%d" % [source.model_id,batch,index]
		var path := source_directory.path_join(id + ".tres")
		var prefab := prefab_directory.path_join(id + ".tscn")
		if FileAccess.file_exists(path) or FileAccess.file_exists(prefab):
			group.free()
			_fail("Имя секции занято; повторите предпросмотр.")
			return null
		var extracted := _extract(part,id)
		var packed := EmberVoxelPrefab.prepare_resource(extracted)
		var saved := Store.install_prepared_asset(extracted,packed,path,prefab) if packed != null else {"ok":false}
		if not saved.ok:
			group.free()
			_fail("Сохранение секций не завершено; сцена не менялась. Уже созданные файлы секций оставлены для восстановления.")
			return null
		var child := EmberSceneAuthoring.make_model_instance(scene,saved.packed,id,Vector3.ZERO)
		while used_placements.has(child.placement_id):
			child.placement_id += "_part"
		used_placements[child.placement_id] = true
		child.name = "Part_%02d" % (index+1)
		child.configure_voxel_scale(extracted.normalized_density(),prop.block_world_size)
		child.scene_file_path = prefab
		group.add_child(child)
		child.transform = _visual_pose * Transform3D(Basis.IDENTITY,Vector3(part.origin)/source.normalized_density()) * (child.get_node("Mesh") as Node3D).transform.affine_inverse()
	var parent := prop.get_parent()
	var position := prop.get_index()
	if undo is EditorUndoRedoManager:
		undo.create_action("Разрезать voxel-объект",UndoRedo.MERGE_DISABLE,scene)
		undo.add_do_method(self,"_swap",parent,prop,group,scene,position)
		undo.add_undo_method(self,"_swap",parent,group,prop,scene,position)
	else:
		undo.create_action("Разрезать voxel-объект")
		undo.add_do_method(_swap.bind(parent,prop,group,scene,position))
		undo.add_undo_method(_swap.bind(parent,group,prop,scene,position))
	undo.add_do_reference(group)
	undo.add_undo_reference(prop)
	undo.add_do_reference(self)
	undo.commit_action()
	return group

func _swap(parent: Node, before: Node, after: Node, scene: Node, index: int) -> void:
	parent.remove_child(before)
	parent.add_child(after)
	parent.move_child(after,index)
	after.owner = scene
	if not after is EmberVoxelProp:
		for part in after.get_children():
			part.owner = scene
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()

func _fail(message: String) -> bool:
	error = message
	return false

func _has_persistent_signals(node: Node) -> bool:
	for connection in node.get_incoming_connections():
		if int(connection.get("flags",0)) & Object.CONNECT_PERSIST:
			return true
	for entry in node.get_signal_list():
		for connection in node.get_signal_connection_list(entry.name):
			if int(connection.get("flags",0)) & Object.CONNECT_PERSIST:
				return true
	return false
