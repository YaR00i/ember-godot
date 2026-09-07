extends SceneTree
## Batch action gate: two untouched legacy fixtures migrate as one Undo/Redo
## transaction and always return to their exact pre-test Resource state.

const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const CANDIDATES := ["vox_fan_bed", "vox_fan_armor_stand", "vox_fan_bar"]


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var ids: Array[String] = []
	for model_id in CANDIDATES:
		if Store.owner(model_id) == "legacy_import":
			ids.append(model_id)
		if ids.size() == 2:
			break
	if ids.size() != 2:
		printerr("FAIL voxel migration batch\n - two legacy fixtures are required")
		return 1
	var snapshots: Array[Dictionary] = []
	var derived_snapshots: Array[Dictionary] = []
	var source_hashes := {}
	for model_id in ids:
		snapshots.append(Store.snapshot(model_id))
		for path in [
			EmberVoxelPrefab.prefab_path(model_id),
			EmberVoxelPrefab.mesh_path(model_id),
			EmberVoxelPrefab.mesh_path(model_id, true),
		]:
			derived_snapshots.append(_file_snapshot(path))
		source_hashes[model_id] = _source_hashes(EmberVoxelPrefab.source_paths(model_id))
	var undo := UndoRedo.new()
	var actions := Actions.new() as EmberObjectInspectorActions
	actions.configure(undo)
	var changes: Array[String] = []
	actions.voxel_model_changed.connect(func(model_id: String) -> void: changes.append(model_id))
	var context := Node.new()
	if not actions.migrate_voxel_models(ids, context):
		errors.append("batch action was rejected")
	else:
		_validate_owners(ids, "godot", errors)
		if not undo.has_undo():
			errors.append("batch did not create one Undo action")
		undo.undo()
		_validate_owners(ids, "legacy_import", errors)
		undo.redo()
		_validate_owners(ids, "godot", errors)
		undo.undo()
		_validate_owners(ids, "legacy_import", errors)
	if changes.size() != ids.size() * 4:
		errors.append("batch refresh emitted %d changes instead of %d" % [changes.size(), ids.size() * 4])
	for index in ids.size():
		if _source_hashes(EmberVoxelPrefab.source_paths(ids[index])) != source_hashes[ids[index]]:
			errors.append("batch changed frozen JOI source for %s" % ids[index])
		if Store.restore_snapshot(snapshots[index]) != OK:
			errors.append("could not restore Resource snapshot for %s" % ids[index])
	for value in derived_snapshots:
		if _restore_file_snapshot(value) != OK:
			errors.append("could not restore derived snapshot %s" % value.get("path", ""))
	undo.clear_history()
	actions.configure(null)
	actions = null
	undo.free()
	context.free()
	if not errors.is_empty():
		printerr("FAIL voxel migration batch")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS voxel migration batch: ", ", ".join(ids))
	print("  one action -> two Resources/prefabs -> Undo -> Redo -> cleanup")
	print("  strict parity preflight and frozen JOI hashes preserved")
	return 0


func _validate_owners(ids: Array[String], expected: String, errors: Array[String]) -> void:
	for model_id in ids:
		if Store.owner(model_id) != expected:
			errors.append("%s owner is not %s" % [model_id, expected])


func _source_hashes(paths: Dictionary) -> Dictionary:
	var result := {}
	for key in ["json", "vox"]:
		var path := str(paths.get(key, ""))
		if not path.is_empty() and FileAccess.file_exists(path):
			result[key] = FileAccess.get_sha256(path)
	return result


func _file_snapshot(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path)
	var existed := FileAccess.file_exists(absolute)
	var bytes := PackedByteArray()
	if existed:
		var file := FileAccess.open(absolute, FileAccess.READ)
		if file != null:
			bytes = file.get_buffer(file.get_length())
	return {"path": path, "existed": existed, "bytes": bytes}


func _restore_file_snapshot(snapshot: Dictionary) -> int:
	var path := str(snapshot.get("path", ""))
	var absolute := ProjectSettings.globalize_path(path)
	if bool(snapshot.get("existed", false)):
		var file := FileAccess.open(absolute, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_buffer(snapshot.get("bytes", PackedByteArray()))
		return OK
	return DirAccess.remove_absolute(absolute) if FileAccess.file_exists(absolute) else OK
