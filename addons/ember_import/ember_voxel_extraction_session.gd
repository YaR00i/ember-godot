@tool
extends RefCounted
signal state_applied
## Atomic scene-reference transaction. New immutable assets are never deleted by Undo.
const Extract = preload("res://addons/ember_import/ember_voxel_fragment_extract.gd")
const ObjectSession = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const AssemblySession = preload("res://addons/ember_import/ember_voxel_assembly_session.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
var error := ""
var piece: EmberVoxelModelResource
var remainder: EmberVoxelModelResource
var packed: PackedScene
var world_pose := Transform3D.IDENTITY
var cut := false
var _edit: RefCounted
var _scene: Node
var _parent: Node3D
var _target: Node3D
var _frame := Transform3D.IDENTITY
var _parent_pose := Transform3D.IDENTITY
var _snapshot := {}
var _resource: EmberVoxelModelResource
var _plans: Array[Dictionary] = []
var _source_path := ""
var _prefab_path := ""
var _new_prop: EmberVoxelProp
var _before: Array[Dictionary] = []
var _after: Array[Dictionary] = []
var _applicator: RefCounted
var _consumed := false

func prepare(edit: RefCounted, source: EmberVoxelModelResource, indices: PackedInt32Array, cutting: bool) -> bool:
	if not edit is ObjectSession and not edit is AssemblySession:
		return _fail("Откройте обычный voxel-объект или сборку из сцены. Отделение из Surface пока недоступно.")
	if edit is ObjectSession and edit.shared:
		return _fail("Откройте «Редактировать в Canvas» для одного экземпляра, а не общую модель.")
	if source.to_definition().get("model") != edit._baseline.to_definition().get("model"):
		return _fail("Сначала сохраните текущие правки Canvas, затем отделите выделение.")
	_edit = edit
	_resource = source
	_snapshot = source.to_definition().duplicate(true)
	cut = cutting
	var context: Dictionary = edit.context_projection(source)
	if context.has("error"):
		return _fail(context.error)
	_scene = context.scene
	_target = context.target
	_parent = _target.get_parent() as Node3D
	if _parent == null or _target.owner != _scene:
		return _fail("Объект должен принадлежать открытой сцене и иметь 3D-родителя.")
	_frame = context.frame
	_parent_pose = _parent.global_transform
	if absf(_frame.basis.determinant()) < 0.000001 or absf(_parent_pose.basis.determinant()) < 0.000001:
		return _fail("Нулевой масштаб не позволяет сохранить положение фрагмента.")
	var extracted := Extract.plan(source,indices,cut)
	if extracted.has("error"):
		return _fail(extracted.error)
	piece = extracted.piece
	remainder = extracted.remainder
	var id := "vox_fragment_%d" % Time.get_ticks_usec()
	while FileAccess.file_exists(edit.source_directory.path_join(id+".tres")) or FileAccess.file_exists(edit.prefab_directory.path_join(id+".tscn")):
		id += "x"
	piece.model_id = id
	_source_path = edit.source_directory.path_join(id+".tres")
	_prefab_path = edit.prefab_directory.path_join(id+".tscn")
	packed = EmberVoxelPrefab.prepare_resource(piece)
	if packed == null:
		return _fail("Не удалось подготовить фрагмент и коллизию.")
	var template := packed.instantiate() as EmberVoxelProp
	# Keep generated child transforms exactly as authored in the prefab. All
	# placement adaptation belongs to the scene-owned prop root and round-trips.
	world_pose = _frame * Transform3D(Basis.IDENTITY,Vector3(extracted.origin)/piece.normalized_density()) * template.get_node("Mesh").transform.affine_inverse()
	template.free()
	return _prepare_original()

func _prepare_original() -> bool:
	_plans.clear()
	var edits: Array = [_edit]
	if _edit is AssemblySession:
		edits = _edit._slots.map(func(slot): return slot.session)
	for edit in edits:
		var prop := edit._target.get_ref() as EmberVoxelProp
		if prop == null:
			return _fail("Исходная деталь удалена.")
		var baseline: Dictionary = edit.save(edit._baseline,true)
		if not baseline.ok:
			return _fail(baseline.error)
		var template := EmberVoxelPrefab.prepare_resource(edit._baseline).instantiate() as EmberVoxelProp
		template.configure_voxel_scale(edit._baseline.normalized_density(),prop.block_world_size)
		var original: Dictionary = edit._capture(prop).nodes
		var defaults: Dictionary = edit._capture(template).nodes
		var compatible := true
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
		if not compatible:
			return _fail("У детали отдельные настройки геометрии или коллизии. Отделение остановлено, чтобы не потерять их.")
	var result: Dictionary
	if _edit is AssemblySession:
		result = _edit.save(remainder,true)
		if result.ok:
			_plans.assign(result.plans)
	else:
		result = _edit.save(remainder,true,true)
		if result.ok and result.has("next"):
			result.session = _edit
			_plans.append(result)
	if not result.ok:
		return _fail(result.error)
	_applicator = _edit._slots[0].session if _edit is AssemblySession else _edit
	return true

func commit(undo: Object) -> EmberVoxelProp:
	if _consumed or not is_instance_valid(_scene) or not is_instance_valid(_parent) or not is_instance_valid(_target) or not _scene.is_inside_tree() or _target.get_parent() != _parent or not _scene.is_ancestor_of(_target) or _target.owner != _scene or _parent.global_transform != _parent_pose or _resource.to_definition() != _snapshot:
		_fail("Объект или черновик изменились. Откройте отделение заново.")
		return null
	if Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != _scene:
		_fail("Активная сцена изменилась.")
		return null
	var context: Dictionary = _edit.context_projection(_resource)
	if context.has("error") or context.frame != _frame or not _prepare_original():
		if error.is_empty():
			_fail("Положение объекта изменилось. Обновите preview.")
		return null
	if FileAccess.file_exists(_source_path) or FileAccess.file_exists(_prefab_path):
		_fail("Путь фрагмента уже занят. Откройте операцию заново.")
		return null
	# Publish every detached asset first. Partial publication never changes scene references.
	var saved := Store.install_prepared_asset(piece,packed,_source_path,_prefab_path)
	if not saved.ok:
		_fail(saved.error)
		return null
	for plan in _plans:
		var installed := Store.install_prepared_asset(plan.next,plan.packed,plan.path,plan.prefab)
		if not installed.ok:
			_fail("Сцена не изменена. Не удалось сохранить все части; новые файлы оставлены для восстановления: " + str(installed.error))
			return null
		for state in plan.new_states:
			state.signature = installed.signature
		_before.append_array(plan.old_states)
		_after.append_array(plan.new_states)
	_new_prop = EmberSceneAuthoring.make_model_instance(_scene,saved.packed,piece.model_id,Vector3.ZERO)
	_new_prop.scene_file_path = _prefab_path
	_new_prop.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META,saved.signature)
	_new_prop.transform = _parent_pose.affine_inverse()*world_pose
	var name := "Fragment"
	while _parent.has_node(NodePath(name)):
		name += "_new"
	_new_prop.name = name
	var title := "Вырезать фрагмент в объект" if cut else "Скопировать фрагмент в объект"
	if undo is EditorUndoRedoManager:
		undo.create_action(title,UndoRedo.MERGE_DISABLE,_scene)
		undo.add_do_method(self,"_apply",true)
		undo.add_undo_method(self,"_apply",false)
	else:
		undo.create_action(title)
		undo.add_do_method(_apply.bind(true))
		undo.add_undo_method(_apply.bind(false))
	undo.add_do_reference(_new_prop)
	undo.add_do_reference(self)
	undo.commit_action()
	_consumed = true
	return _new_prop

func _apply(forward: bool) -> void:
	_applicator._apply(_after if forward else _before,{})
	if forward:
		EmberSceneAuthoring.attach_model_instance(_scene,_parent,_new_prop)
	elif _new_prop.get_parent() == _parent:
		_parent.remove_child(_new_prop)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(_new_prop if forward else _target)
	state_applied.emit()

func _fail(message: String) -> bool:
	error = message
	return false
