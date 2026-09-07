extends SceneTree
## Read-only gate for the first bounded fan_town batch. These seven scene-used
## models already have current prefabs, so only canonical ownership should move.

const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
const Batches = preload("res://addons/ember_import/ember_voxel_migration_batches.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var model_ids := Batches.model_ids("fan_town_ready")
	var before := _watched_hashes(model_ids)
	var report := Parity.inspect_batch(model_ids)
	var after := _watched_hashes(model_ids)
	if before != after:
		errors.append("dry-run changed legacy, Resource or derived prefab files")
	if model_ids.size() != 7:
		errors.append("reviewed fan_town batch no longer contains seven models")
	if not bool(report.get("ok", false)) or int(report.get("passed", 0)) != model_ids.size():
		errors.append("one or more fan_town models failed strict parity")
	for raw_entry in report.get("entries", []):
		var entry: Dictionary = raw_entry
		if not bool(entry.get("ok", false)):
			errors.append("%s: %s" % [entry.get("id", ""), "; ".join(entry.get("errors", []))])
		if int(entry.get("filled_voxels", 0)) <= 0 or int(entry.get("triangles", 0)) <= 0:
			errors.append("%s produced empty voxel or mesh output" % entry.get("id", ""))
	if not errors.is_empty():
		printerr("FAIL fan_town ready-batch parity")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS fan_town ready-batch parity · %d ms" % int(report.get("duration_ms", -1)))
	for entry in report.get("entries", []):
		print("  %s: %s · %d filled · %d triangles" % [
			entry.get("id", ""), entry.get("grid", Vector3i.ZERO),
			int(entry.get("filled_voxels", 0)), int(entry.get("triangles", 0)),
		])
	print("  no Resource/prefab write; frozen legacy hashes preserved")
	return 0


func _watched_hashes(model_ids: Array[String]) -> Dictionary:
	var result := {}
	for model_id in model_ids:
		var preview := EmberVoxelLegacyImporter.preview_model(model_id)
		var paths: Dictionary = preview.get("sourcePaths", {})
		for key in ["json", "vox"]:
			_add_hash(result, str(paths.get(key, "")))
		_add_hash(result, EmberVoxelCatalog.native_path(model_id))
		_add_hash(result, EmberVoxelPrefab.prefab_path(model_id))
		_add_hash(result, EmberVoxelPrefab.mesh_path(model_id))
		_add_hash(result, EmberVoxelPrefab.mesh_path(model_id, true))
	return result


func _add_hash(result: Dictionary, path: String) -> void:
	if path.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	result[path] = FileAccess.get_sha256(absolute) if FileAccess.file_exists(absolute) else "missing"
