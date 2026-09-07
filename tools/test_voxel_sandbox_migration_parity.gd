extends SceneTree
## G1 sandbox preflight: the six selected models produce byte-stable source
## provenance and exact transient mesh parity without creating native files.

const Inventory = preload("res://addons/ember_import/ember_content_migration_report.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var inventory := Inventory.build()
	var candidates := Inventory.filtered_entries(inventory, "voxel", "sandbox_batch")
	var ids: Array[String] = []
	for entry in candidates:
		ids.append(str(entry.get("id", "")))
	var before := _watched_hashes(ids)
	var report := Parity.inspect_batch(ids)
	var after := _watched_hashes(ids)
	if before != after:
		errors.append("dry-run changed legacy, Resource or derived prefab files")
	if ids.size() != 6:
		errors.append("expected six dashboard-selected sandbox candidates")
	if not bool(report.get("ok", false)) or int(report.get("passed", 0)) != ids.size():
		errors.append("one or more sandbox models failed strict parity")
	for raw_entry in report.get("entries", []):
		var entry: Dictionary = raw_entry
		if not bool(entry.get("ok", false)):
			errors.append("%s: %s" % [entry.get("id", ""), "; ".join(entry.get("errors", []))])
		if int(entry.get("filled_voxels", 0)) <= 0 or int(entry.get("triangles", 0)) <= 0:
			errors.append("%s produced empty voxel or mesh output" % entry.get("id", ""))
	if not errors.is_empty():
		printerr("FAIL sandbox voxel migration parity")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS sandbox voxel migration parity · %d ms" % int(report.get("duration_ms", -1)))
	for entry in report.get("entries", []):
		print("  %s: %s · %d filled · %d triangles" % [
			entry.get("id", ""), entry.get("grid", Vector3i.ZERO),
			int(entry.get("filled_voxels", 0)), int(entry.get("triangles", 0)),
		])
	print("  no Resource/prefab write; legacy hashes preserved")
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
