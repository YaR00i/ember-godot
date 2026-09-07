extends SceneTree
## G1.1 queue gate: a legacy card migrates through the shared Undo/Redo owner,
## rebuilds derived data, and leaves the frozen JOI pair byte-identical.

const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Actions = preload("res://addons/ember_import/ember_object_inspector_actions.gd")
const Visuals = preload("res://scripts/ember_voxel_visuals.gd")
const CANDIDATES := ["vox_fan_bed", "vox_fan_armor_stand", "vox_fan_bar"]


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var model_id := _legacy_candidate()
	if model_id.is_empty():
		printerr("FAIL voxel migration queue\n - no legacy fixture remains")
		return 1
	var source_paths := EmberVoxelPrefab.source_paths(model_id)
	var source_hashes := _source_hashes(source_paths)
	var snapshot := Store.snapshot(model_id)
	var undo := UndoRedo.new()
	var actions := Actions.new() as EmberObjectInspectorActions
	actions.configure(undo)
	var changes: Array[String] = []
	actions.voxel_model_changed.connect(func(changed_id: String) -> void: changes.append(changed_id))
	var context := Node.new()

	if not actions.migrate_voxel_model(model_id, context):
		errors.append("migration action was rejected")
	else:
		_validate_native(model_id, errors)
		undo.undo()
		if Store.owner(model_id) != "legacy_import":
			errors.append("Ctrl+Z did not return the model to the import queue")
		undo.redo()
		_validate_native(model_id, errors)
		undo.undo()
		if Store.owner(model_id) != "legacy_import":
			errors.append("final cleanup did not restore the legacy owner")
	if changes.size() != 4:
		errors.append("migration UI refresh signal count is %d instead of 4" % changes.size())
	if source_hashes != _source_hashes(source_paths):
		errors.append("migration or Undo modified the frozen JOI source pair")
	# Always restore the exact pre-test native state, even after a failed check.
	if Store.restore_snapshot(snapshot) != OK:
		errors.append("could not restore the pre-test native snapshot")
	undo.clear_history()
	actions.configure(null)
	actions = null
	undo.free()
	undo = null
	context.free()

	if not errors.is_empty():
		printerr("FAIL voxel migration queue")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS voxel migration queue: ", model_id)
	print("  legacy card -> native Resource/prefab -> Ctrl+Z -> Redo -> cleanup")
	print("  frozen JOI source hashes preserved")
	return 0


func _legacy_candidate() -> String:
	for model_id in CANDIDATES:
		if Store.owner(model_id) == "legacy_import":
			return model_id
	return ""


func _validate_native(model_id: String, errors: Array[String]) -> void:
	if Store.owner(model_id) != "godot":
		errors.append("migrated model is not owned by Godot")
		return
	var resource := EmberVoxelCatalog.native_resource(model_id)
	if resource == null or not resource.validation_errors().is_empty():
		errors.append("migrated Resource is missing or invalid")
	elif resource.imported_from.begins_with("C:") or resource.imported_from.begins_with("/"):
		errors.append("migrated Resource stores an absolute legacy path")
	var entry := _entry(model_id)
	if str(entry.get("owner", "")) != "godot" or not bool(entry.get("migrated", false)):
		errors.append("visual queue did not refresh to the native owner")
	var packed := ResourceLoader.load(
		EmberVoxelPrefab.prefab_path(model_id), "", ResourceLoader.CACHE_MODE_REPLACE
	) as PackedScene
	var report := EmberVoxelPrefab.validate_packed(model_id, packed)
	if not bool(report.get("ok", false)):
		errors.append("derived prefab is invalid: %s" % "; ".join(report.get("errors", [])))


func _entry(model_id: String) -> Dictionary:
	for entry in Visuals.entries():
		if str(entry.get("id", "")) == model_id:
			return entry
	return {}


func _source_hashes(paths: Dictionary) -> Dictionary:
	var result := {}
	for key in ["json", "vox"]:
		var path := str(paths.get(key, ""))
		if not path.is_empty() and FileAccess.file_exists(path):
			result[key] = FileAccess.get_sha256(path)
	return result
