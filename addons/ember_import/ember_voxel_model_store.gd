@tool
class_name EmberVoxelModelStore
extends RefCounted
## Editor mutation boundary for one-way voxel migration. Legacy files are never
## changed; Undo removes/restores only the native Resource and rebuilds cache.

const Catalog = preload("res://scripts/ember_voxel_catalog.gd")
const Importer = preload("res://scripts/ember_voxel_legacy_importer.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")


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
