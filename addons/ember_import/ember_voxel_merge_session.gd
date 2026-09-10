@tool
extends RefCounted
const Merge = preload("res://addons/ember_import/ember_voxel_merge.gd")
const Assembly = preload("res://addons/ember_import/ember_voxel_scene_assembly.gd")
const Edit = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR
var error := ""
var preview: EmberVoxelModelResource
var frame := Transform3D.IDENTITY
var overlap := PackedInt32Array()
var adjustments: Array[Dictionary] = []
var outputs: Array[Dictionary] = []
var _scene: Node
var _parent: Node3D
var _parent_pose := Transform3D.IDENTITY
var _inputs: Array[Dictionary] = []
var _new_nodes: Array[Node] = []
var _consumed := false
var _separating := false

func _fail(message: String) -> bool:
	error = message
	return false

func prepare(selection: Array, scene: Node, separating := false, align_grid := false) -> bool:
	error = ""
	_inputs.clear()
	outputs.clear()
	adjustments.clear()
	_separating = separating
	_scene = scene
	var guard := Assembly.new()
	guard.source_directory = source_directory
	if not guard._scene_valid(scene) or selection.is_empty():
		return _fail("Выберите voxel-детали открытой сцены.")
	if (separating and selection.size() != 1) or (not separating and (selection.size() < 2 or selection.size() > 32)):
		return _fail("Для склейки выберите 2–32 детали; для разбора — одну склейку.")
	_parent = selection[0].get_parent() as Node3D
	if _parent == null or absf(_parent.global_basis.determinant()) < 0.000001:
		return _fail("Нужен 3D-родитель с ненулевым масштабом.")
	_parent_pose = _parent.global_transform
	var inputs: Array[Dictionary] = []
	for node in selection:
		if not guard._ordinary(node,scene):
			return _fail(guard.error)
		if node.get_parent() != _parent:
			return _fail("Выберите детали под одним родителем в дереве сцены.")
		var edit := Edit.new()
		edit.source_directory = source_directory
		edit.prefab_directory = prefab_directory
		if not edit.open(node,scene,null):
			return _fail(edit.error)
		if not _compatible(edit,node):
			return false
		var mesh: MeshInstance3D = node.get_node("Mesh")
		var owners: Array[Dictionary] = [{"node":node,"owner":node.owner}]
		for child in node.find_children("*","",true,false):
			owners.append({"node":child,"owner":child.owner})
		_inputs.append({"node":node,"edit":edit,"pose":node.transform,"mesh_pose":mesh.transform,"index":node.get_index(),"name":node.name,"owners":owners})
		inputs.append({"source":edit.draft,"frame":mesh.global_transform,"name":str(node.name)})
	if not guard._references_clear(scene,selection):
		return _fail(guard.error)
	if separating:
		preview = inputs[0].source
		frame = inputs[0].frame
		overlap = PackedInt32Array()
		var result := Merge.separate(preview)
		if result.has("error"):
			return _fail(result.error)
		for item in result.pieces:
			outputs.append({"source":item.source,"frame":frame*Transform3D(Basis.IDENTITY,Vector3(item.origin)/preview.normalized_density())})
	else:
		var result := Merge.plan(inputs,align_grid)
		if result.has("error"):
			return _fail(result.error)
		preview = result.source
		frame = result.frame
		overlap = result.overlap
		adjustments.assign(result.adjustments)
		outputs.append({"source":preview,"frame":frame})
	return true

func _compatible(edit: RefCounted, prop: EmberVoxelProp) -> bool:
	var template_scene := EmberVoxelPrefab.prepare_resource(edit.draft)
	if template_scene == null:
		return _fail("Не удалось построить проверочную модель.")
	var template := template_scene.instantiate() as EmberVoxelProp
	template.configure_voxel_scale(edit.draft.normalized_density(),prop.block_world_size)
	var original: Dictionary = edit._capture(prop).nodes
	var defaults: Dictionary = edit._capture(template).nodes
	var compatible := original.keys() == defaults.keys()
	for path in original:
		for key in original[path]:
			if key not in ["mesh","shape","position","scale","ember_block_position"] and original[path][key] != defaults.get(path,{}).get(key):
				compatible = false
		var node := prop.get_node(NodePath(path))
		if node is CollisionShape3D and not node.global_transform.is_equal_approx(prop.get_node("Mesh").global_transform):
			compatible = false
		if node is StaticBody3D and (node.physics_material_override != null or node.constant_linear_velocity != Vector3.ZERO or node.constant_angular_velocity != Vector3.ZERO or not node.get_collision_exceptions().is_empty()):
			compatible = false
		if node is MeshInstance3D and (node.transparency != 0 or node.material_overlay != null or node.skin != null):
			compatible = false
	template.free()
	return true if compatible else _fail("У детали нестандартная геометрия, материал или коллизия. Операция не будет терять эти настройки.")

func commit(undo: Object) -> bool:
	var guard := Assembly.new()
	guard.source_directory = source_directory
	if _consumed or undo == null or not guard._scene_valid(_scene) or not is_instance_valid(_parent) or _parent.global_transform != _parent_pose:
		return _fail("Сцена изменилась. Откройте предпросмотр заново.")
	var targets: Array = []
	for input in _inputs:
		var node: Node3D = input.node
		if not is_instance_valid(node) or node.get_parent() != _parent or node.owner != _scene or node.get_index() != input.index or node.transform != input.pose or node.name != input.name or node.get_node("Mesh").transform != input.mesh_pose:
			return _fail("Деталь изменилась. Откройте предпросмотр заново.")
		if not guard._ordinary(node,_scene) or not _compatible(input.edit,node):
			return _fail("Настройки детали изменились. Обновите предпросмотр.")
		var validated: Dictionary = input.edit.save(input.edit._baseline,true)
		if not validated.ok:
			return _fail(validated.error)
		targets.append(node)
	if not guard._references_clear(_scene,targets):
		return _fail(guard.error)
	# Prepare all projections before publishing; scene references change only last.
	var plans: Array[Dictionary] = []
	for index in outputs.size():
		var output := outputs[index]
		var source := output.source.duplicate(true) as EmberVoxelModelResource
		var id := "vox_merge_%d_%d" % [Time.get_ticks_usec(),index]
		while FileAccess.file_exists(source_directory.path_join(id+".tres")) or FileAccess.file_exists(prefab_directory.path_join(id+".tscn")):
			id += "x"
		source.model_id = id
		var packed := EmberVoxelPrefab.prepare_resource(source)
		if packed == null:
			return _fail("Не удалось построить геометрию и коллизию; сцена не изменена.")
		plans.append({"source":source,"packed":packed,"path":source_directory.path_join(id+".tres"),"prefab":prefab_directory.path_join(id+".tscn"),"frame":output.frame})
	for plan in plans:
		var installed := Store.install_prepared_asset(plan.source,plan.packed,plan.path,plan.prefab)
		if not installed.ok:
			return _fail("Сцена не изменена. Созданные файлы оставлены для восстановления. " + str(installed.error))
		plan.installed = installed
	var reserved_names := {}
	for plan in plans:
		var prop := EmberSceneAuthoring.make_model_instance(_scene,plan.installed.packed,plan.source.model_id,Vector3.ZERO)
		prop.scene_file_path = plan.prefab
		prop.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META,plan.installed.signature)
		prop.transform = _parent_pose.affine_inverse()*plan.frame*prop.get_node("Mesh").transform.affine_inverse()
		var name: String = str(plan.source.display_name).validate_node_name() if _separating else "VoxelMerged"
		if name.is_empty():
			name = "MergePart"
		while _parent.has_node(NodePath(name)) or reserved_names.has(name):
			name += "_new"
		reserved_names[name] = true
		prop.name = name
		_new_nodes.append(prop)
	var title := "Разобрать текущую склейку" if _separating else "Склеить voxel-детали"
	if undo is EditorUndoRedoManager:
		undo.create_action(title,UndoRedo.MERGE_DISABLE,_scene)
		undo.add_do_method(self,"_apply",true)
		undo.add_undo_method(self,"_apply",false)
	else:
		undo.create_action(title)
		undo.add_do_method(_apply.bind(true))
		undo.add_undo_method(_apply.bind(false))
	for node in _new_nodes:
		undo.add_do_reference(node)
	for node in targets:
		undo.add_undo_reference(node)
	undo.add_do_reference(self)
	undo.commit_action()
	_consumed = true
	return true

func _apply(forward: bool) -> void:
	var originals: Array = _inputs.map(func(item): return item.node)
	var removed: Array = originals if forward else _new_nodes
	var added: Array = _new_nodes if forward else originals
	for node in removed:
		if node.get_parent() == _parent:
			_parent.remove_child(node)
	for node in added:
		EmberSceneAuthoring.attach_model_instance(_scene,_parent,node)
	if not forward:
		var ordered := _inputs.duplicate()
		ordered.sort_custom(func(a,b): return a.index < b.index)
		for item in ordered:
			for ownership in item.owners:
				ownership.node.owner = ownership.owner
			_parent.move_child(item.node,mini(item.index,_parent.get_child_count()-1))
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
		EditorInterface.get_selection().clear()
		for node in added:
			EditorInterface.get_selection().add_node(node)
