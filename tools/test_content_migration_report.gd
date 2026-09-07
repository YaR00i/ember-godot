extends SceneTree
## G1/G2 inventory gate: the report is complete, internally consistent and
## read-only for both canonical Godot content and the frozen JOI archive.

const Report = preload("res://addons/ember_import/ember_content_migration_report.gd")
const REPORT_PATH := "user://ember_content_migration_report.json"


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var before := _source_hashes()
	var report := Report.build()
	var after := _source_hashes()
	if before != after:
		errors.append("read-only inventory changed canonical or legacy source files")
	if int(report.get("schema", 0)) != 1:
		errors.append("inventory schema is missing")
	var domains: Dictionary = report.get("domains", {})
	for domain_name in ["voxel", "action", "dialogue", "item", "shop", "vn"]:
		if not domains.has(domain_name):
			errors.append("inventory omitted %s" % domain_name)
			continue
		var domain: Dictionary = domains[domain_name]
		var counts: Dictionary = domain.get("counts", {})
		var accounted := (
			int(counts.get("native", 0))
			+ int(counts.get("legacy_remaining", 0))
			+ int(counts.get("missing", 0))
		)
		if accounted != int(counts.get("total", -1)):
			errors.append("%s ownership counts are inconsistent" % domain_name)
		if domain.get("entries", []).size() != accounted:
			errors.append("%s detail rows do not match its summary" % domain_name)
	var voxel: Dictionary = domains.get("voxel", {})
	var voxel_counts: Dictionary = voxel.get("counts", {})
	var all_rows := Report.filtered_entries(report)
	if all_rows.size() != int((report.get("totals", {}) as Dictionary).get("total", -1)):
		errors.append("dashboard projection omitted inventory rows")
	var legacy_rows := Report.filtered_entries(report, "all", "legacy")
	if legacy_rows.size() != int((report.get("totals", {}) as Dictionary).get("legacy_remaining", -1)):
		errors.append("legacy dashboard filter disagrees with inventory totals")
	var sandbox_rows := Report.filtered_entries(report, "voxel", "sandbox_batch")
	if sandbox_rows.size() != 6:
		errors.append("sandbox scope should contain its six current scene props")
	for entry in sandbox_rows:
		if str(entry.get("owner", "")) != "native" or int(entry.get("reference_count", 0)) <= 0:
			errors.append("migrated sandbox scope contains a non-native or unreferenced entry")
	if not Report.filtered_entries(report, "voxel", "sandbox_pending").is_empty():
		errors.append("sandbox legacy candidate queue should be empty after the first batch")
	var fan_town_rows := Report.filtered_entries(report, "voxel", "fan_town_ready_batch")
	if fan_town_rows.size() != 7:
		errors.append("fan_town ready batch should contain seven reviewed scene models")
	for entry in fan_town_rows:
		if str(entry.get("owner", "")) != "native" or str(entry.get("derived_status", "")) != "ready":
			errors.append("fan_town ready batch contains a non-native or stale entry")
	if not Report.filtered_entries(report, "voxel", "fan_town_ready_pending").is_empty():
		errors.append("migrated fan_town ready batch remains in the legacy queue")
	var missing_vn := Report.filtered_entries(
		report, "vn", "attention", "49bd31e4-b1e2-495d-b57d-eb01994be362"
	)
	if missing_vn.size() != 1:
		errors.append("dashboard search cannot isolate the known missing VN asset")
	if int(voxel_counts.get("native", 0)) < 2:
		errors.append("known native voxel owners disappeared")
	if int(voxel_counts.get("legacy_remaining", 0)) <= 0:
		errors.append("legacy voxel queue unexpectedly disappeared before migration")
	var required_prefabs := 0
	for entry in voxel.get("entries", []):
		if str((entry as Dictionary).get("kind", "model")) == "model":
			required_prefabs += 1
	var accounted_prefabs := (
		int(voxel_counts.get("derived_ready", 0))
		+ int(voxel_counts.get("derived_missing", 0))
		+ int(voxel_counts.get("derived_stale", 0))
		+ int(voxel_counts.get("derived_invalid", 0))
	)
	if required_prefabs != accounted_prefabs:
		errors.append("voxel derived-data counts are inconsistent")
	if not voxel.get("missing_references", []).is_empty():
		errors.append("scene references missing voxel owners: %s" % [
			", ".join(voxel.get("missing_references", [])),
		])
	var absolute_report := ProjectSettings.globalize_path(REPORT_PATH)
	var file := FileAccess.open(absolute_report, FileAccess.WRITE)
	if file == null:
		errors.append("inventory JSON could not be written to user://")
	else:
		file.store_string(JSON.stringify(report, "  ", false) + "\n")
		file.close()
		var reopened: Variant = JSON.parse_string(FileAccess.get_file_as_string(absolute_report))
		if typeof(reopened) != TYPE_DICTIONARY or int(reopened.get("schema", 0)) != 1:
			errors.append("inventory JSON did not reopen")
	if not errors.is_empty():
		printerr("FAIL content migration report")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS content migration report · %d ms" % int(report.get("duration_ms", -1)))
	for domain_name in ["voxel", "action", "dialogue", "item", "shop", "vn"]:
		var counts: Dictionary = (domains[domain_name] as Dictionary).get("counts", {})
		print("  %s: total %d · native %d · legacy %d · invalid %d" % [
			domain_name,
			int(counts.get("total", 0)),
			int(counts.get("native", 0)),
			int(counts.get("legacy_remaining", 0)),
			int(counts.get("invalid", 0)),
		])
	print("  voxel prefabs: ready %d · missing %d · stale %d · invalid %d" % [
		int(voxel_counts.get("derived_ready", 0)),
		int(voxel_counts.get("derived_missing", 0)),
		int(voxel_counts.get("derived_stale", 0)),
		int(voxel_counts.get("derived_invalid", 0)),
	])
	print("  dashboard: %d rows · sandbox batch %d" % [all_rows.size(), sandbox_rows.size()])
	print("  JSON: ", absolute_report)
	return 0


func _source_hashes() -> Dictionary:
	var result := {}
	_collect_hashes("res://content/voxel_models", result)
	_collect_hashes("res://prefabs/voxels", result)
	var legacy_dir := EmberPack.pack_root().path_join("voxels").path_join("models")
	_collect_hashes(legacy_dir, result)
	return result


func _collect_hashes(directory: String, result: Dictionary) -> void:
	var absolute := ProjectSettings.globalize_path(directory) if directory.begins_with("res://") else directory
	if not DirAccess.dir_exists_absolute(absolute):
		return
	for child_directory in DirAccess.get_directories_at(absolute):
		_collect_hashes(absolute.path_join(child_directory), result)
	for filename in DirAccess.get_files_at(absolute):
		var path := absolute.path_join(filename)
		result[path] = FileAccess.get_sha256(path)
