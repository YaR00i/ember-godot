@tool
class_name EmberVoxelModelStore
extends RefCounted
## Editor mutation boundary for one-way voxel migration. Legacy files are never
## changed; Undo removes/restores only the native Resource and rebuilds cache.

const Catalog = preload("res://scripts/ember_voxel_catalog.gd")
const Importer = preload("res://scripts/ember_voxel_legacy_importer.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
static var _canvas_cache: Dictionary = {}
static var derived_rename_override: Callable # Test-only transient sharing violation.


static func install_derived_prefab(packed: PackedScene, path: String, signature: String) -> Dictionary:
	# Rebuild never reserializes the canonical source. Like Canvas Save, serialize
	# outside res://, then publish atomically without mutating live subresources.
	var directory := "user://ember-editor-staging/refresh-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var temporary := directory.path_join(path.get_file())
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		return {"ok": false, "error": "Не удалось открыть staging папку."}
	var node := packed.instantiate()
	node.scene_file_path = ""
	node.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, signature)
	var detached := PackedScene.new()
	var result := detached.pack(node)
	node.free()
	if result == OK:
		result = ResourceSaver.save(detached, temporary)
	var uid := EmberVoxelPrefab.resource_uid_from_header(path)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	if result != OK:
		return {"ok": false, "error": "Сериализация staging: " + error_string(result)}
	# set_uid rewrites text through a .uidren file and resource-directory access.
	# Avoid that second filesystem transaction for user:// staging, especially
	# in the native editor. Change only the generated header before publication.
	var text := FileAccess.get_file_as_string(temporary)
	var end := text.find("\n")
	if end < 0 or not text.begins_with("[gd_scene "):
		return {"ok": false, "error": "Staging не содержит заголовок PackedScene."}
	var header := text.left(end).strip_edges()
	var uid_start := header.find(" uid=\"")
	if uid_start >= 0:
		var uid_end := header.find("\"", uid_start + 6)
		if uid_end < 0: return {"ok": false, "error": "Некорректный UID staging."}
		header = header.left(uid_start) + header.substr(uid_end + 1)
	header = header.trim_suffix("]") + " uid=\"" + ResourceUID.id_to_text(uid) + "\"]"
	var published := restore_derived_prefab((header + text.substr(end)).to_utf8_buffer(), path)
	if not Engine.is_editor_hint():
		_cleanup_serialization([temporary], directory)
	return published


static func restore_derived_prefab(bytes: PackedByteArray, path: String) -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
		return {"ok": false, "error": "Не удалось открыть папку prefab."}
	var temporary := path + ".refresh-%d.tmp" % Time.get_ticks_usec()
	var had_target := FileAccess.file_exists(path)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Запись временного prefab: " + error_string(FileAccess.get_open_error())}
	file.store_buffer(bytes)
	var result := file.get_error()
	file.close()
	if result == OK:
		result = derived_rename_override.call(temporary, path) if derived_rename_override.is_valid() else DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if result != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return {"ok": false, "error": "Замена prefab на диске: %s · %s" % [error_string(result), path], "retryable": result in [FAILED, ERR_FILE_CANT_WRITE, ERR_FILE_CANT_OPEN, ERR_CANT_CREATE], "published": had_target and not FileAccess.file_exists(path)}
	var uid := EmberVoxelPrefab.resource_uid_from_header(path)
	if uid != ResourceUID.INVALID_ID:
		ResourceUID.set_id(uid, path) if ResourceUID.has_id(uid) else ResourceUID.add_id(uid, path)
	var cached := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if cached == null:
		return {"ok": false, "error": "Опубликованный prefab не читается.", "published": true}
	cached.resource_path = ""
	cached.take_over_path(path)
	_canvas_cache[path] = cached
	EmberVoxelPrefab.begin_import()
	return {"ok": true, "packed": cached}


static func install_prepared_asset(
	source: EmberVoxelModelResource, packed: PackedScene,
	source_path: String, prefab_path: String,
) -> Dictionary:
	## Editor save transaction. Stage both files before publishing either one.
	## Live scene nodes/resources are applied only by the caller after success.
	var paths := [source_path, prefab_path]
	var previous := {}
	var staged: Array[String] = []
	var serialized: Array[String] = []
	var serialization_root := "user://ember-editor-staging/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var uids: Array[int] = []
	var published: Array[String] = []
	var signature := ""
	for path in paths:
		if FileAccess.file_exists(path.get_base_dir()):
			return {"ok": false, "error": "Путь папки занят файлом: %s" % path.get_base_dir()}
		previous[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
			return {"ok": false, "error": "Не удалось открыть папку сохранения: %s" % path}
		# Windows does not treat dot-prefixed files as hidden. Use an unrecognized
		# extension so background scans cannot index a temporary .tres/.tscn.
		staged.append(path.get_base_dir().path_join("." + path.get_file() + ".canvas-stage-%d.tmp" % Time.get_ticks_usec()))
		serialized.append(serialization_root.path_join(path.get_file()))
		var uid := EmberVoxelPrefab.resource_uid_from_header(path)
		uids.append(ResourceUID.create_id() if uid == ResourceUID.INVALID_ID else uid)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(serialization_root)) != OK:
		return {"ok": false, "error": "Не удалось создать временную папку сериализации."}
	# ResourceSaver notifies the editor asynchronously even for hidden res://
	# files. Serialize outside its index, then copy beside the final destination
	# for same-filesystem atomic publication (user:// may be on another drive).
	var result := ResourceSaver.save(source, serialized[0])
	if result == OK:
		result = ResourceSaver.set_uid(serialized[0], uids[0])
	if result == OK:
		var node := packed.instantiate()
		# Replays may receive a PackedScene previously serialized to a staging
		# path. Never repack it into itself or retain that path as inheritance.
		node.scene_file_path = ""
		packed = PackedScene.new()
		signature = (EmberVoxelPrefab.BUILD_CONTRACT + ":" + FileAccess.get_sha256(serialized[0]) + ":json-only").sha256_text()
		node.set_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, signature)
		result = packed.pack(node)
		node.free()
	if result == OK:
		result = ResourceSaver.save(packed, serialized[1])
	if result == OK:
		result = ResourceSaver.set_uid(serialized[1], uids[1])
	if result == OK:
		for index in paths.size():
			result = DirAccess.copy_absolute(ProjectSettings.globalize_path(serialized[index]), ProjectSettings.globalize_path(staged[index]))
			if result != OK:
				break
	if result == OK:
		for index in paths.size():
			result = DirAccess.rename_absolute(ProjectSettings.globalize_path(staged[index]), ProjectSettings.globalize_path(paths[index]))
			if result != OK:
				break
			published.append(paths[index])
	if result != OK:
		for path in published:
			if previous[path] != null:
				var file := FileAccess.open(path, FileAccess.WRITE)
				if file != null:
					file.store_buffer(previous[path])
				else:
					return {"ok": false, "error": "Ошибка восстановления %s; исходные bytes остаются в транзакции." % path, "recovery": previous}
			elif FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for path in staged:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(path + ".uidren"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".uidren"))
	# Editor preview/folding workers can read ResourceSaver paths after several
	# frames. Keep this recoverable user cache for the editor's full lifetime;
	# deleting it on a guessed deferred frame races those background readers.
	if not Engine.is_editor_hint():
		_cleanup_serialization(serialized, serialization_root)
	if result == OK:
		for index in paths.size():
			ResourceUID.set_id(uids[index], paths[index]) if ResourceUID.has_id(uids[index]) else ResourceUID.add_id(uids[index], paths[index])
		EmberVoxelPrefab.begin_import()
		# Install new cache identities, never mutate cached mesh/shape resources
		# before the scene transaction applies its explicit per-instance snapshots.
		for path in paths:
			var saved_resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if saved_resource != null:
				# CACHE_MODE_IGNORE can retain the path without registering in cache;
				# clear it so take_over_path does not short-circuit on an equal path.
				saved_resource.resource_path = ""
				saved_resource.take_over_path(path)
				_canvas_cache[path] = saved_resource
				if saved_resource is PackedScene and Engine.is_editor_hint():
					# Editor comparisons need the published SceneState's path cache,
					# including saves that rebind an existing node to this prefab.
					var cache_instance := (saved_resource as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
					cache_instance.free()
		packed = _canvas_cache.get(prefab_path, packed) as PackedScene
	return {"ok": result == OK, "error": error_string(result), "packed": packed, "signature": signature}


static func _cleanup_serialization(paths: Array[String], directory: String) -> void:
	# Runtime tests have no editor preview readers and can remove exact files.
	for path in paths:
		for candidate in [path, path + ".uidren"]:
			if FileAccess.file_exists(candidate):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


static func owner(model_id: String) -> String:
	var definition := Catalog.definition(model_id)
	return str(definition.get("_owner", ""))


static func snapshot(model_id: String) -> Dictionary:
	var path := Catalog.native_path(model_id)
	var absolute := ProjectSettings.globalize_path(path)
	var existed := FileAccess.file_exists(absolute)
	var bytes := PackedByteArray()
	if existed:
		var file := FileAccess.open(absolute, FileAccess.READ)
		if file != null:
			bytes = file.get_buffer(file.get_length())
	return {"modelId": model_id, "path": path, "existed": existed, "bytes": bytes}


static func migrate_to_native(model_id: String) -> int:
	if owner(model_id) != "legacy_import":
		return ERR_ALREADY_EXISTS
	var parity := Parity.inspect_model(model_id)
	if not bool(parity.get("ok", false)):
		push_error("Ember voxel parity: %s" % "; ".join(parity.get("errors", [])))
		return ERR_INVALID_DATA
	return _migrate_validated(model_id)


static func migrate_batch_to_native(model_ids: Array[String]) -> int:
	if model_ids.is_empty():
		return ERR_INVALID_PARAMETER
	for model_id in model_ids:
		if owner(model_id) != "legacy_import":
			return ERR_ALREADY_EXISTS
	var parity := Parity.inspect_batch(model_ids)
	if not bool(parity.get("ok", false)):
		push_error("Ember voxel batch parity failed")
		return ERR_INVALID_DATA
	var snapshots: Array[Dictionary] = []
	for model_id in model_ids:
		var value := snapshot(model_id)
		snapshots.append(value)
		var error := _migrate_validated(model_id)
		if error != OK:
			for index in range(snapshots.size() - 1, -1, -1):
				restore_snapshot(snapshots[index])
			return error
	return OK


static func restore_snapshots(snapshots: Array[Dictionary]) -> int:
	var first_error := OK
	for index in range(snapshots.size() - 1, -1, -1):
		var error := restore_snapshot(snapshots[index])
		if error != OK and first_error == OK:
			first_error = error
	return first_error


static func _migrate_validated(model_id: String) -> int:
	var report := Importer.import_model(model_id)
	if not bool(report.get("ok", false)):
		push_error("Ember voxel migration: %s" % report.get("error", "unknown error"))
		return ERR_CANT_CREATE
	return _rebuild(model_id)


static func restore_snapshot(value: Dictionary) -> int:
	var model_id := str(value.get("modelId", ""))
	var path := str(value.get("path", Catalog.native_path(model_id)))
	var absolute := ProjectSettings.globalize_path(path)
	if bool(value.get("existed", false)):
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var file := FileAccess.open(absolute, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_buffer(value.get("bytes", PackedByteArray()))
	else:
		if FileAccess.file_exists(absolute):
			var remove_error := DirAccess.remove_absolute(absolute)
			if remove_error != OK:
				return remove_error
	return _rebuild(model_id)


static func _rebuild(model_id: String) -> int:
	EmberVoxelPrefab.begin_import()
	var packed := EmberVoxelPrefab.ensure_saved(model_id, 16.0, {}, true)
	if packed == null:
		return ERR_CANT_CREATE
	var report := EmberVoxelPrefab.validate_packed(model_id, packed)
	return OK if bool(report.get("ok", false)) else ERR_INVALID_DATA
