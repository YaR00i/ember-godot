@tool
extends RefCounted
## Editor-only transaction for Canvas -> existing prop. Canonical assets remain
## VoxelModelResource + VoxelPrefab; this object owns only a detached edit session.

const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
const UNIQUE_META := "ember_canvas_unique_source"
const GENERATED := ["Mesh", "ShadowBody", "Collision", "Collision/Shape", "Omni"]

var draft: EmberVoxelModelResource
var error := ""
var shared := false
var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR
var _target: WeakRef
var _root: WeakRef
var _undo: Object
var _source: EmberVoxelModelResource
var _baseline: EmberVoxelModelResource
var _projection_cache: RefCounted
var _source_path := ""
var _source_hash := ""
var _legacy_signature := ""
var _expected_id := ""
var _unique_id := ""
var _context_mesh_frame := Transform3D.IDENTITY
var _context_size := Vector3i.ONE


func open(prop: EmberVoxelProp, scene_root: Node, undo_redo: Object, edit_shared := false) -> bool:
	error = ""
	_unique_id = ""
	_legacy_signature = ""
	if not is_instance_valid(prop) or not is_instance_valid(scene_root):
		return _fail("Объект или сцена уже закрыты.")
	_target = weakref(prop)
	_root = weakref(scene_root)
	_undo = undo_redo
	shared = edit_shared
	_expected_id = prop.model_id
	_source_path = source_directory.path_join(_expected_id + ".tres")
	if FileAccess.file_exists(_source_path):
		_source = ResourceLoader.load(_source_path) as EmberVoxelModelResource
	else:
		if not FileAccess.file_exists(EmberPack.model_json_path(_expected_id)):
			return _fail("Voxel source не найден: %s" % _expected_id)
		var parity := Parity.inspect_model(_expected_id)
		if not bool(parity.get("ok", false)):
			return _fail("Legacy-модель не прошла точную проверку: %s" % "; ".join(parity.get("errors", [])))
		_source = EmberVoxelLegacyImporter.preview_model(_expected_id).get("resource")
		_source_path = EmberPack.model_json_path(_expected_id)
		_legacy_signature = EmberVoxelPrefab.source_signature(_expected_id)
	if _source == null:
		return _fail("Не удалось прочитать voxel source.")
	_baseline = _source.duplicate(true) as EmberVoxelModelResource
	_projection_cache = preload("res://scripts/ember_voxel_projection_cache.gd").new() if _baseline.voxels.size() > 131072 else null
	draft = _source.duplicate(true) as EmberVoxelModelResource
	_source_hash = FileAccess.get_sha256(_source_path)
	var parity_errors := _projection_errors(prop, _baseline)
	if not parity_errors.is_empty():
		return _fail("Сохранённый объект не совпадает с voxel source; автоматическая пересборка заблокирована: %s" % parity_errors[0])
	_context_mesh_frame = (prop.get_node("Mesh") as MeshInstance3D).transform
	_context_size = draft.size_blocks
	return true


func label() -> String:
	return "Общая модель · меняются связанные экземпляры" if shared else "Выбранный экземпляр · остальные не изменятся"

func release_projection_cache() -> void:
	# Undo retains this session, but does not need its acceleration data.
	_projection_cache = null


func refresh_before_open() -> bool:
	return open(_target.get_ref() as EmberVoxelProp, _root.get_ref() as Node, _undo, shared)


func context_projection(resource: EmberVoxelModelResource) -> Dictionary:
	var prop := _target.get_ref() as EmberVoxelProp if _target != null else null
	var scene := _root.get_ref() as Node if _root != null else null
	if not is_instance_valid(prop) or not is_instance_valid(scene) or not scene.is_inside_tree() or not scene.is_ancestor_of(prop):
		return {"error": "Объект удалён или исходная сцена закрыта."}
	var mesh := prop.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or resource == null:
		return {"error": "У объекта нет геометрической привязки."}
	# Stable editing anchor survives Save Undo while the draft remains open.
	# The object's scene placement stays live; the initial authored mesh adapter
	# is adjusted for the current draft's centered grid, just like Save.
	var frame := _context_mesh_frame
	var old_size := _context_size
	var next_size := resource.size_blocks
	var offset := Vector3(old_size.x - next_size.x, 0, old_size.z - next_size.z) * 0.5 * prop.block_world_size
	frame.origin += offset
	frame = prop.global_transform * frame
	return {"scene": scene, "target": prop, "frame": frame}


func save(resource: EmberVoxelModelResource, prepare_only := false, fresh_asset := false) -> Dictionary:
	error = ""
	var prop := _target.get_ref() as EmberVoxelProp if _target != null else null
	var scene_root := _root.get_ref() as Node if _root != null else null
	if not is_instance_valid(prop) or not is_instance_valid(scene_root) or not scene_root.is_ancestor_of(prop):
		return _result_error("Объект удалён или сцена закрыта. Черновик сохранён в Canvas.")
	if shared and Engine.is_editor_hint() and EditorInterface.get_open_scenes().size() > 1:
		return _result_error("Для общей модели сначала сохраните и закройте другие вкладки сцен. Их несохранённые экземпляры нельзя безопасно обновить из текущего Canvas.")
	if prop.model_id != _expected_id or FileAccess.get_sha256(_source_path) != _source_hash or not _same_data(_source, _baseline):
		return _result_error("Source изменён вне этой сессии. Откройте объект заново; чужие правки не перезаписаны.")
	if not _legacy_signature.is_empty() and EmberVoxelPrefab.source_signature(_expected_id) != _legacy_signature:
		return _result_error("Legacy JSON/VOX изменены вне этой сессии. Откройте объект заново; source не изменён.")
	# One detached baseline per transaction. Never cache across saves: external
	# mesh edits must still be compared with independently built source geometry.
	var baseline_packed := EmberVoxelPrefab.prepare_resource(_baseline, _projection_cache)
	if baseline_packed == null or not _projection_errors(prop, _baseline, baseline_packed).is_empty():
		return _result_error("Геометрия или коллизия объекта изменены вне Canvas. Черновик не опубликован.")
	if _same_data(resource, _baseline):
		return {"ok": true, "path": _source_path}
	if resource.surface_fill_levels != _baseline.surface_fill_levels or resource.surface_fill_materials != _baseline.surface_fill_materials or resource.surface_fill_palette != _baseline.surface_fill_palette:
		return _result_error("Заливка водой доступна для Surface. Для обычных объектов этот режим появится на этапе воды; source не изменён.")
	var problems := resource.validation_errors()
	if not problems.is_empty():
		return _result_error("Некорректная модель: %s" % problems[0])
	var id := _expected_id if shared else _unique_id
	if fresh_asset and not shared:
		id = ""
	if id.is_empty():
		id = _allocate_id(_expected_id)
	var next := resource.duplicate(true) as EmberVoxelModelResource
	next.model_id = id
	var packed := EmberVoxelPrefab.prepare_resource(next, _projection_cache)
	if packed == null:
		return _result_error("Не удалось собрать модель; source не изменён.")
	var targets := _instances(scene_root, _expected_id) if shared else [prop]
	var old_states: Array[Dictionary] = []
	var new_states: Array[Dictionary] = []
	var template := packed.instantiate() as EmberVoxelProp
	var baseline_template := baseline_packed.instantiate() as EmberVoxelProp
	for target in targets:
		if target != prop and not _projection_errors(target, _baseline, baseline_packed).is_empty():
			template.free()
			baseline_template.free()
			return _result_error("Один из связанных объектов содержит отдельную геометрию/коллизию. Общая модель не изменена.")
		var state := _capture(target)
		old_states.append(state)
		template.configure_voxel_scale(next.normalized_density(), target.block_world_size)
		baseline_template.configure_voxel_scale(_baseline.normalized_density(), target.block_world_size)
		var defaults := _capture(baseline_template)
		var new_state := _capture(template)
		new_state["target"] = weakref(target)
		new_state["unique"] = id if not shared else str(target.get_meta(UNIQUE_META, ""))
		# Instance placement and authored descendants are never replaced.
		new_state["scene_path"] = prefab_directory.path_join(id + ".tscn")
		for path in GENERATED:
			if state.nodes.has(path) and not new_state.nodes.has(path):
				template.free()
				baseline_template.free()
				return _result_error("Изменение структуры generated children требует отдельной проверки; source не изменён.")
			if state.nodes.has(path) and new_state.nodes.has(path):
				if defaults.nodes.has(path):
					new_state.nodes[path].position += state.nodes[path].position - defaults.nodes[path].position
					new_state.nodes[path].scale *= state.nodes[path].scale / defaults.nodes[path].scale
				# Preserve per-instance presentation/physics overrides. Stage 1 only
				# replaces mesh/shape and the generated position/scale adapter.
				for key in state.nodes[path]:
					if key not in ["mesh", "shape", "position", "scale", "ember_block_position"]:
						new_state.nodes[path][key] = state.nodes[path][key]
		new_states.append(new_state)
	template.free()
	baseline_template.free()
	var destination := source_directory.path_join(id + ".tres")
	var prefab_path := prefab_directory.path_join(id + ".tscn")
	if prepare_only:
		return {"ok":true,"next":next,"packed":packed,"new_states":new_states,"old_states":old_states,"path":destination,"prefab":prefab_path}
	var published := Store.install_prepared_asset(next, packed, destination, prefab_path)
	if not bool(published.get("ok", false)):
		return _result_error("Сохранение не завершено: %s" % published.get("error", ""))
	var old_asset: Dictionary = {}
	if id == _expected_id and _source_path.begins_with(source_directory):
		old_asset = {"source": _baseline.duplicate(true), "packed": baseline_packed, "path": destination, "prefab": prefab_path}
	var new_asset := {"source": next, "packed": packed, "path": destination, "prefab": prefab_path}
	for state in new_states:
		state.signature = published.signature
	# First application is already prepared/published; commit_action(false) avoids
	# a second disk transaction. Undo/Redo reuse these exact IDs and node snapshots.
	_apply(new_states, {})
	if _undo is EditorUndoRedoManager:
		_undo.create_action("Canvas · %s" % label(), UndoRedo.MERGE_DISABLE, scene_root)
		_undo.add_do_method(self, "_apply", new_states, new_asset)
		_undo.add_undo_method(self, "_apply", old_states, old_asset)
	else:
		_undo.create_action("Canvas · %s" % label())
		_undo.add_do_method(_apply.bind(new_states, new_asset))
		_undo.add_undo_method(_apply.bind(old_states, old_asset))
	_undo.add_do_reference(self)
	_undo.commit_action(false)
	accept_prepared_save(next,destination)
	resource.model_id = id
	return {"ok": true, "path": destination}

func accept_prepared_save(next: EmberVoxelModelResource, destination: String, reuse_id := true) -> void:
	_expected_id = next.model_id
	_unique_id = next.model_id if reuse_id and not shared else ""
	_source_path = destination
	_source_hash = FileAccess.get_sha256(destination)
	_legacy_signature = ""
	_source = ResourceLoader.load(destination) as EmberVoxelModelResource
	_baseline = next.duplicate(true) as EmberVoxelModelResource

func can_grow_canvas() -> bool:
	return true


func _apply(states: Array[Dictionary], asset: Dictionary) -> void:
	if not asset.is_empty():
		var result := Store.install_prepared_asset(asset.source, asset.packed, asset.path, asset.prefab)
		if not bool(result.get("ok", false)):
			push_warning("Canvas Undo/Redo: %s" % result.get("error", "save failed"))
			return
		for state in states:
			state.signature = result.signature
	for state in states:
		var prop := (state.target as WeakRef).get_ref() as EmberVoxelProp
		if prop == null:
			continue
		prop.model_id = state.id
		prop.scene_file_path = state.scene_path
		prop.voxels_per_block = state.density
		prop.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, state.signature)
		if str(state.unique).is_empty():
			prop.remove_meta(UNIQUE_META)
		else:
			prop.set_meta(UNIQUE_META, state.unique)
		for path in GENERATED:
			if not state.nodes.has(path):
				continue
			var node := prop.get_node_or_null(NodePath(path))
			var values: Dictionary = state.nodes[path]
			if node == null:
				node = ClassDB.instantiate(values.type)
				node.name = str(path).get_file()
				var parent := prop if not str(path).contains("/") else prop.get_node(NodePath(str(path).get_base_dir()))
				parent.add_child(node)
				node.owner = prop.owner
			for key in values:
				if key == "type":
					continue
				if key.begins_with("ember_"):
					node.set_meta(key, values[key])
				else:
					node.set(key, values[key])
		prop.notify_property_list_changed()
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
		EditorInterface.get_resource_filesystem().scan()


func create_independent_copy() -> bool:
	var prop := _target.get_ref() as EmberVoxelProp
	var scene_root := _root.get_ref() as Node
	if prop == null or scene_root == null or prop.get_parent() == null:
		return _fail("Исходный объект больше недоступен.")
	var source := draft.duplicate(true) as EmberVoxelModelResource
	source.model_id = _allocate_id(prop.model_id)
	var packed := EmberVoxelPrefab.prepare_resource(source)
	if packed == null:
		return _fail("Не удалось подготовить независимую копию без изменения source.")
	var result := Store.install_prepared_asset(source, packed, source_directory.path_join(source.model_id + ".tres"), prefab_directory.path_join(source.model_id + ".tscn"))
	if not bool(result.get("ok", false)):
		return _fail(str(result.get("error")))
	var copy := EmberSceneAuthoring.make_duplicate(scene_root, prop, Vector3(prop.block_world_size, 0, 0))
	var template := packed.instantiate() as EmberVoxelProp
	template.configure_voxel_scale(source.normalized_density(), prop.block_world_size)
	var state := _capture(template)
	var original_state := _capture(copy)
	for path in GENERATED:
		if state.nodes.has(path) and original_state.nodes.has(path):
			for key in original_state.nodes[path]:
				if key not in ["mesh", "shape", "type"]:
					state.nodes[path][key] = original_state.nodes[path][key]
	state.target = weakref(copy)
	state.unique = source.model_id
	state.scene_path = prefab_directory.path_join(source.model_id + ".tscn")
	template.free()
	_apply([state], {})
	var parent := prop.get_parent()
	if _undo is EditorUndoRedoManager:
		_undo.create_action("Создать независимую voxel-копию", UndoRedo.MERGE_DISABLE, scene_root)
		_undo.add_do_method(self, "_attach_copy", scene_root, prop, parent, copy)
		_undo.add_undo_method(self, "_detach_copy", parent, copy)
	else:
		_undo.create_action("Создать независимую voxel-копию")
		_undo.add_do_method(_attach_copy.bind(scene_root, prop, parent, copy))
		_undo.add_undo_method(_detach_copy.bind(parent, copy))
	_undo.add_do_reference(copy)
	_undo.add_do_reference(self)
	_undo.commit_action()
	return true


func _attach_copy(scene_root: Node, source: EmberVoxelProp, parent: Node, copy: EmberVoxelProp) -> void:
	if not is_instance_valid(scene_root) or not is_instance_valid(parent):
		return
	EmberSceneAuthoring.attach_duplicate(scene_root, source, parent, copy)
	if scene_root.is_editable_instance(source):
		scene_root.set_editable_instance(copy, true)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
		EditorInterface.get_resource_filesystem().scan()


func _detach_copy(parent: Node, copy: EmberVoxelProp) -> void:
	if is_instance_valid(parent) and copy.get_parent() == parent:
		parent.remove_child(copy)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()


func _capture(prop: EmberVoxelProp) -> Dictionary:
	var nodes := {}
	for path in GENERATED:
		var node := prop.get_node_or_null(NodePath(path))
		if node == null:
			continue
		var values := {"type": node.get_class()}
		for field in ["position", "scale", "visible"]:
			values[field] = node.get(field)
		for field in ["ember_block_position", "ember_range_blocks"]:
			if node.has_meta(field):
				values[field] = node.get_meta(field)
		if node is MeshInstance3D:
			for field in ["mesh", "material_override", "cast_shadow", "layers"]:
				values[field] = node.get(field)
		if node is CollisionShape3D:
			values.shape = node.shape
			values.disabled = node.disabled
		if node is StaticBody3D:
			values.collision_layer = node.collision_layer
			values.collision_mask = node.collision_mask
		if node is OmniLight3D:
			for field in ["light_color", "light_energy", "omni_range", "shadow_enabled"]:
				values[field] = node.get(field)
		nodes[path] = values
	return {"target": weakref(prop), "id": prop.model_id, "scene_path": prop.scene_file_path, "density": prop.voxels_per_block, "signature": prop.get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, ""), "unique": prop.get_meta(UNIQUE_META, ""), "nodes": nodes}


func _instances(node: Node, id: String) -> Array:
	var result: Array = []
	if node is EmberVoxelProp and node.model_id == id:
		result.append(node)
	for child in node.get_children():
		result.append_array(_instances(child, id))
	return result


func _projection_errors(prop: EmberVoxelProp, source: EmberVoxelModelResource, prepared: PackedScene = null) -> Array[String]:
	var problems: Array[String] = []
	if prepared == null:
		prepared = EmberVoxelPrefab.prepare_resource(source)
	if prepared == null:
		return ["source не создаёт поддерживаемый prefab"]
	var expected := prepared.instantiate() as EmberVoxelProp
	var visual := prop.get_node_or_null("Mesh") as MeshInstance3D
	if visual == null or not visual.mesh is ArrayMesh:
		problems.append("изменён тип визуальной геометрии")
	else:
		var checks: Array[String] = []
		var expected_mesh: ArrayMesh = expected.get_node("Mesh").mesh
		if visual.mesh.get_surface_count() > 0 or expected_mesh.get_surface_count() > 0:
			Parity._compare_meshes(visual.mesh, expected_mesh, problems, checks)
	var collision := prop.get_node_or_null("Collision/Shape") as CollisionShape3D
	var expected_collision := expected.get_node_or_null("Collision/Shape") as CollisionShape3D
	if (collision == null) != (expected_collision == null):
		problems.append("изменена структура коллизии")
	elif collision != null:
		if collision.shape == null and expected_collision.shape == null:
			pass
		elif not collision.shape is ConcavePolygonShape3D or not expected_collision.shape is ConcavePolygonShape3D:
			problems.append("коллизия задана вручную")
		else:
			Parity._compare_vectors(collision.shape.get_faces(), expected_collision.shape.get_faces(), "collision", problems)
	expected.free()
	return problems


func _allocate_id(base: String) -> String:
	var id := "%s_canvas_%d" % [base, Time.get_ticks_usec()]
	while FileAccess.file_exists(source_directory.path_join(id + ".tres")) or FileAccess.file_exists(prefab_directory.path_join(id + ".tscn")):
		id += "x"
	return id


func _same_data(a: EmberVoxelModelResource, b: EmberVoxelModelResource) -> bool:
	return a != null and b != null and a.to_definition().get("model") == b.to_definition().get("model")


func _fail(message: String) -> bool:
	error = message
	return false


func _result_error(message: String) -> Dictionary:
	error = message
	return {"ok": false, "error": message}
