extends SceneTree
## Final-state gate: the first fan_town batch must equal its reviewed legacy
## conversion and keep valid derived prefabs at the paths already used by scene.

const Importer = preload("res://scripts/ember_voxel_legacy_importer.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
const Inventory = preload("res://addons/ember_import/ember_content_migration_report.gd")
const Batches = preload("res://addons/ember_import/ember_voxel_migration_batches.gd")


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var model_ids := Batches.model_ids("fan_town_ready")
	var parity := Parity.inspect_batch(model_ids)
	if not bool(parity.get("ok", false)):
		errors.append("legacy-to-native transient parity no longer passes")
	for model_id in model_ids:
		var expected_report := Importer.preview_model(model_id)
		var expected: EmberVoxelModelResource = expected_report.get("resource")
		var actual := EmberVoxelCatalog.native_resource(model_id)
		if EmberVoxelCatalog.owner(model_id) != "godot" or actual == null:
			errors.append("%s is not owned by its Godot Resource" % model_id)
			continue
		if not actual.validation_errors().is_empty():
			errors.append("%s saved Resource is invalid" % model_id)
		if expected == null or actual.to_definition().get("model", {}) != expected.to_definition().get("model", {}):
			errors.append("%s saved Resource differs from reviewed dry-run data" % model_id)
		if actual.imported_source_hash != str(expected_report.get("sourceHash", "")):
			errors.append("%s provenance hash differs from frozen source" % model_id)
		var packed := ResourceLoader.load(
			EmberVoxelPrefab.prefab_path(model_id), "", ResourceLoader.CACHE_MODE_REPLACE
		) as PackedScene
		var prefab_report := EmberVoxelPrefab.validate_packed(model_id, packed)
		if not bool(prefab_report.get("ok", false)):
			errors.append("%s prefab is invalid: %s" % [
				model_id, "; ".join(prefab_report.get("errors", [])),
			])
	var inventory := Inventory.build()
	if not Inventory.filtered_entries(inventory, "voxel", "fan_town_ready_pending").is_empty():
		errors.append("migrated fan_town models still appear in the legacy batch queue")
	for entry in Inventory.filtered_entries(inventory, "voxel", "fan_town_ready_batch"):
		if str(entry.get("owner", "")) != "native" or str(entry.get("derived_status", "")) != "ready":
			errors.append("%s scene reference is not native with ready prefab" % entry.get("id", ""))
	if "--visual" in OS.get_cmdline_user_args():
		await _capture_fan_town(errors)
	if not errors.is_empty():
		printerr("FAIL fan_town ready native voxel batch")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS fan_town ready native voxel batch")
	print("  7 Godot Resources equal the reviewed transient conversion")
	print("  7 fan_town prefabs remain current at their existing scene paths")
	print("  frozen legacy sources remain available only to the importer")
	return 0


func _capture_fan_town(errors: Array[String]) -> void:
	var packed := load("res://scenes/fan_town.tscn") as PackedScene
	var scene := packed.instantiate() if packed != null else null
	if scene == null:
		errors.append("fan_town could not be instantiated for Forward+ inspection")
		return
	root.add_child(scene)
	var projection := scene.get_node_or_null("Map/DerivedVoxelWorldSurface")
	var deadline := Time.get_ticks_msec() + 25000
	if projection == null:
		errors.append("fan_town did not create its Surface projection")
	else:
		while not bool(projection.call("is_projection_complete")) and Time.get_ticks_msec() < deadline:
			await process_frame
		if not bool(projection.call("is_projection_complete")):
			errors.append("fan_town Surface did not finish before visual capture")
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	if screenshot == null or screenshot.is_empty():
		errors.append("Forward+ inspection did not produce an image")
	else:
		var output := "user://ember_fan_town_ready_native_batch.png"
		if screenshot.save_png(output) != OK:
			errors.append("Forward+ inspection image could not be saved")
		else:
			print("VISUAL: ", ProjectSettings.globalize_path(output))
	scene.free()
