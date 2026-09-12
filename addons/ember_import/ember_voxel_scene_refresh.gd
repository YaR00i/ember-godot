@tool
extends RefCounted
## Explicit derived-data transaction. Session validates/captures/applies props;
## Store publishes prefab only. No canonical model, recipe or map is rewritten.

const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const SurfaceProjection = preload("res://scripts/ember_voxel_surface_projection.gd")
const Filesystem = preload("res://addons/ember_import/ember_editor_filesystem.gd")

signal progress(message: String)
signal assets_changed
signal library_progress(done: int, total: int, model_id: String)

var source_directory := EmberVoxelCatalog.NATIVE_DIR
var prefab_directory := EmberVoxelPrefab.PREFAB_DIR
var _changes: Array[Dictionary] = []
var _surfaces: Array[WeakRef] = []
var _cancel_library := false
var _publication_error := ""
var _publication_retryable := false


func cancel_library() -> void:
	_cancel_library = true


func rebuild_library(ids: Array[String], host: Node, scene: Node, undo: Object) -> Dictionary:
	_cancel_library = false
	var scan_hold := Filesystem.defer_scans()
	var unique: Array[String] = []
	for id in ids:
		if not unique.has(id): unique.append(id)
	var completed := 0
	var rebuilt := 0
	var skipped: Array[String] = []
	var skipped_ids: Array[String] = []
	for id in unique:
		# One completed transaction per model, never a giant retained batch.
		# Cancellation leaves completed derived assets recoverable via Undo.
		if _cancel_library or not is_instance_valid(host): break
		library_progress.emit(completed, unique.size(), id)
		await host.get_tree().process_frame
		if _cancel_library or not is_instance_valid(host): break
		var wait_until := Time.get_ticks_msec() + 30000
		while Engine.is_editor_hint() and (EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing()) and Time.get_ticks_msec() < wait_until:
			if _cancel_library or not is_instance_valid(host): break
			await host.get_tree().process_frame
		if _cancel_library or not is_instance_valid(host): break
		if Engine.is_editor_hint() and (EditorInterface.get_resource_filesystem().is_scanning() or EditorInterface.get_resource_filesystem().is_importing()):
			skipped.append("Сканирование/import не завершились за 30 секунд; очередь остановлена.")
			break
		if Engine.is_editor_hint() and (EditorInterface.get_edited_scene_root() != scene):
			skipped.append("Сцена переключена; очередь остановлена.")
			break
		var operation := get_script().new() as RefCounted
		operation.source_directory = source_directory
		operation.prefab_directory = prefab_directory
		var result: Dictionary = operation.rebuild_catalog_model(id, scene, undo)
		var retry_until := Time.get_ticks_msec() + 3000
		while not result.ok and bool(result.get("retryable", false)) and Time.get_ticks_msec() < retry_until:
			# Keep the prepared transaction; do not recompute the mesh. Yield
			# real frames/time so filesystem readers can release their handles.
			var next_attempt := Time.get_ticks_msec() + 100
			while Time.get_ticks_msec() < next_attempt and is_instance_valid(host):
				await host.get_tree().process_frame
			if not is_instance_valid(host) or (Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != scene): break
			result = operation.retry_catalog_publication(scene, undo)
		if result.ok:
			rebuilt += 1
		else:
			skipped.append(id + ": " + str(result.error))
			skipped_ids.append(id)
		completed += 1
		library_progress.emit(completed, unique.size(), id)
	scan_hold = null
	Filesystem.request()
	assets_changed.emit()
	return {"ok": true, "completed": completed, "total": unique.size(), "rebuilt": rebuilt,
		"cancelled": _cancel_library or completed < unique.size(), "skipped": skipped, "skipped_ids": skipped_ids}


func rebuild_catalog_model(id: String, scene: Node, undo: Object) -> Dictionary:
	if undo == null: return {"ok": false, "error": "Undo manager недоступен."}
	if not id.is_valid_filename(): return {"ok": false, "error": "Некорректный model ID."}
	var path := prefab_directory.path_join(id + ".tscn")
	var old_bytes := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var source_path := source_directory.path_join(id + ".tres")
	var source: EmberVoxelModelResource
	if FileAccess.file_exists(source_path):
		source = ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as EmberVoxelModelResource
	elif FileAccess.file_exists(EmberPack.model_json_path(id)):
		source = EmberVoxelLegacyImporter.preview_model(id).get("resource")
	if source == null: return {"ok": false, "error": "Voxel source отсутствует."}
	# Do not remesh a large existing asset merely to load its saved proxy; the
	# session's validated/cached builder already prepares the replacement.
	var stored: PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene if FileAccess.file_exists(path) else EmberVoxelPrefab.prepare_resource(source)
	if stored == null: return {"ok": false, "error": "Сохранённый prefab не читается."}
	var proxy := stored.instantiate() as EmberVoxelProp
	if proxy == null: return {"ok": false, "error": "Prefab не является voxel prop."}
	if proxy.model_id != id:
		proxy.free()
		return {"ok": false, "error": "Model ID prefab не совпадает с source."}
	var validation_root := Node3D.new()
	validation_root.add_child(proxy)
	var edit := Session.new()
	edit.source_directory = source_directory
	edit.prefab_directory = prefab_directory
	if not edit.open(proxy, validation_root, undo, true, true):
		validation_root.free()
		return {"ok": false, "error": edit.error}
	var targets: Array = []
	if is_instance_valid(scene): targets = edit._instances(scene, id)
	# Validate saved prefab too, even when this model is absent from the scene.
	var prepared: Dictionary = edit.prepare_geometry_refresh([proxy] + targets)
	validation_root.free()
	if not prepared.ok: return prepared
	if FileAccess.get_sha256(edit._source_path) != edit._source_hash or (FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()) != old_bytes:
		return {"ok": false, "error": "Source/prefab изменён во время подготовки. Не перезаписан."}
	prepared.old_states.remove_at(0)
	prepared.new_states.remove_at(0)
	var signature := _signature(id)
	for state in prepared.new_states: state.signature = signature
	_changes = [{"edit": edit, "path": path, "packed": prepared.packed, "signature": signature,
		"source_path": edit._source_path, "source_hash": edit._source_hash,
		"old_bytes": old_bytes,
		"old_states": prepared.old_states, "new_states": prepared.new_states}]
	return _finish_catalog_publication(scene, undo)


func retry_catalog_publication(scene: Node, undo: Object) -> Dictionary:
	for change in _changes:
		if FileAccess.get_sha256(change.source_path) != change.source_hash or (FileAccess.get_file_as_bytes(change.path) if FileAccess.file_exists(change.path) else PackedByteArray()) != change.old_bytes:
			return {"ok": false, "error": "Source/prefab изменён во время ожидания; не перезаписан."}
		for state in change.old_states:
			var target := (state.target as WeakRef).get_ref() as EmberVoxelProp
			if not is_instance_valid(target) or target.model_id != state.id or change.edit._capture(target).nodes != state.nodes:
				return {"ok": false, "error": "Экземпляр изменён во время ожидания; не перезаписан."}
	return _finish_catalog_publication(scene, undo)


func _finish_catalog_publication(scene: Node, undo: Object) -> Dictionary:
	if not _apply(true): return {"ok": false, "error": "Публикация prefab не завершена: " + _publication_error, "retryable": _publication_retryable}
	var change := _changes[0]
	var edit: RefCounted = change.edit
	var id: String = edit._expected_id
	var source: EmberVoxelModelResource = edit._source
	var title := "Пересобрать voxel: " + id
	if undo is EditorUndoRedoManager:
		undo.create_action(title, UndoRedo.MERGE_DISABLE, scene if is_instance_valid(scene) else source)
		undo.add_do_method(self, "_apply", true)
		undo.add_undo_method(self, "_apply", false)
	else:
		undo.create_action(title)
		undo.add_do_method(_apply.bind(true))
		undo.add_undo_method(_apply.bind(false))
	undo.add_do_reference(self)
	undo.commit_action(false)
	# History needs only snapshots, not dense canonical/draft voxel buffers.
	edit.release_projection_cache()
	edit.draft = null
	edit._source = null
	edit._baseline = null
	return {"ok": true, "instances": change.new_states.size()}


func refresh(scene: Node, undo: Object, model_id := "", stale_only := true) -> Dictionary:
	if not is_instance_valid(scene) or undo == null:
		return {"ok": false, "error": "Нет активной сцены."}
	_changes.clear()
	_surfaces.clear()
	var groups := {}
	var queue: Array[Node] = [scene]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is EmberVoxelProp and (model_id.is_empty() or node.model_id == model_id):
			if not groups.has(node.model_id): groups[node.model_id] = []
			groups[node.model_id].append(node)
		if model_id.is_empty() and node.get_script() == SurfaceProjection:
			_surfaces.append(weakref(node))
		queue.append_array(node.get_children())
	var skipped: Array[String] = []
	var instance_count := 0
	var started := Time.get_ticks_usec()
	for id in groups:
		var targets: Array = groups[id]
		var signature := _signature(str(id))
		var stale := not stale_only
		for target in targets:
			stale = stale or str(target.get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, "")) != signature
		if not stale: continue
		progress.emit("Проверяю и собираю: " + str(id))
		var edit := Session.new()
		edit.source_directory = source_directory
		edit.prefab_directory = prefab_directory
		if not edit.open(targets[0], scene, undo, true, true):
			skipped.append(str(id) + ": " + edit.error)
			continue
		var prepared: Dictionary = edit.prepare_geometry_refresh(targets)
		if not prepared.ok:
			skipped.append(str(id) + ": " + str(prepared.error))
			continue
		var path := prefab_directory.path_join(str(id) + ".tscn")
		# Existing props must have a recoverable prefab for exact Undo.
		if not FileAccess.file_exists(path):
			skipped.append(str(id) + ": prefab отсутствует; сначала сохраните модель.")
			continue
		for state in prepared.new_states: state.signature = signature
		_changes.append({"edit": edit, "path": path, "packed": prepared.packed,
			"signature": signature, "old_bytes": FileAccess.get_file_as_bytes(path),
			"source_path": edit._source_path, "source_hash": edit._source_hash,
			"old_states": prepared.old_states, "new_states": prepared.new_states})
		instance_count += targets.size()
		edit.release_projection_cache()
		if scene.is_inside_tree():
			await scene.get_tree().process_frame
		if not is_instance_valid(scene) or (Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() != scene):
			return {"ok": false, "error": "Сцена закрыта/переключена. Ничего не опубликовано."}
	if not _changes.is_empty():
		for change in _changes:
			if FileAccess.get_sha256(change.source_path) != change.source_hash or FileAccess.get_file_as_bytes(change.path) != change.old_bytes:
				return {"ok": false, "error": "Source/prefab изменился во время подготовки. Ничего не опубликовано."}
			for state in change.old_states:
				var target := (state.target as WeakRef).get_ref() as EmberVoxelProp
				if not is_instance_valid(target) or target.model_id != state.id or change.edit._capture(target).nodes != state.nodes:
					return {"ok": false, "error": "Экземпляр изменился во время подготовки. Ничего не опубликовано."}
		if not _apply(true):
			return {"ok": false, "error": "Не удалось опубликовать prefab. Экземпляры не изменены."}
		var title := "Обновить воксельную геометрию сцены"
		if undo is EditorUndoRedoManager:
			undo.create_action(title, UndoRedo.MERGE_DISABLE, scene)
			undo.add_do_method(self, "_apply", true)
			undo.add_undo_method(self, "_apply", false)
		else:
			undo.create_action(title)
			undo.add_do_method(_apply.bind(true))
			undo.add_undo_method(_apply.bind(false))
		undo.add_do_reference(self)
		undo.commit_action(false)
	else:
		_refresh_surfaces()
	return {"ok": true, "models": _changes.size(), "instances": instance_count,
		"surfaces": _surfaces.size(), "skipped": skipped, "elapsed_usec": Time.get_ticks_usec() - started}


func _signature(id: String) -> String:
	var path := source_directory.path_join(id + ".tres")
	if FileAccess.file_exists(path):
		return (EmberVoxelPrefab.BUILD_CONTRACT + ":" + FileAccess.get_sha256(path) + ":json-only").sha256_text()
	return EmberVoxelPrefab.source_signature(id)


func _apply(forward: bool) -> bool:
	_publication_error = ""
	_publication_retryable = false
	var published: Array[Dictionary] = []
	for change in _changes:
		var previous := FileAccess.get_file_as_bytes(change.path)
		var result := Store.install_derived_prefab(change.packed, change.path, change.signature) if forward else (Store.restore_derived_prefab(change.old_bytes, change.path) if not change.old_bytes.is_empty() else {"ok": true})
		if not bool(result.ok):
			_publication_error = str(result.error)
			_publication_retryable = bool(result.get("retryable", false))
			if bool(result.get("published", false)):
				var restored := Store.restore_derived_prefab(previous, change.path)
				if not restored.ok:
					# Preserve exact previous bytes even if another filesystem reader
					# prevents rollback too. Never lose recovery when the queue skips.
					var recovery := "user://ember-editor-staging/recovery-%d-%d.tscn" % [OS.get_process_id(), Time.get_ticks_usec()]
					var recovery_file := FileAccess.open(recovery, FileAccess.WRITE)
					if recovery_file != null:
						recovery_file.store_buffer(previous)
						recovery_file.close()
						_publication_error += " · Исходные bytes для восстановления: " + ProjectSettings.globalize_path(recovery)
					else: _publication_error += " · Не удалось записать recovery: " + str(restored.error)
					_publication_retryable = false
			for item in published: Store.restore_derived_prefab(item.bytes, item.path)
			if not _publication_retryable: push_warning("Voxel refresh: " + str(result.error))
			return false
		published.append({"path": change.path, "bytes": previous})
		if forward and result.has("packed"):
			change.packed = result.packed
	for change in _changes:
		change.edit._apply(change.new_states if forward else change.old_states, {})
	_refresh_surfaces()
	assets_changed.emit()
	if Engine.is_editor_hint():
		preload("res://addons/ember_import/ember_editor_filesystem.gd").request()
	return true


func _refresh_surfaces() -> void:
	# Surface chunks are nonserialized derived data. Requeue them on refresh,
	# Undo and Redo; canonical geometry stays identical throughout.
	for reference in _surfaces:
		var projection := reference.get_ref() as Node
		if is_instance_valid(projection): projection.refresh_geometry()
