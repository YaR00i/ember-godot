extends SceneTree
## Final-state gate for the first real G1 batch. Saved Resources must equal the
## preflight conversion and own valid derived prefabs used by sandbox scenes.

const Importer = preload("res://scripts/ember_voxel_legacy_importer.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
const Inventory = preload("res://addons/ember_import/ember_content_migration_report.gd")
const MODEL_IDS: Array[String] = [
	"vox_ms8vsb53",
	"vox_vil_bush",
	"vox_vil_counter",
	"vox_vil_mailbox",
	"vox_vil_planter",
	"vox_vil_sign",
]


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var parity := Parity.inspect_batch(MODEL_IDS)
	if not bool(parity.get("ok", false)):
		errors.append("legacy-to-native transient parity no longer passes")
	for model_id in MODEL_IDS:
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
	if not Inventory.filtered_entries(inventory, "voxel", "sandbox_pending").is_empty():
		errors.append("migrated sandbox models still appear in the legacy candidate queue")
	for entry in Inventory.filtered_entries(inventory, "voxel", "scene_used"):
		if str(entry.get("id", "")) in MODEL_IDS:
			if str(entry.get("owner", "")) != "native" or str(entry.get("derived_status", "")) != "ready":
				errors.append("%s scene reference is not native with ready prefab" % entry.get("id", ""))
	if "--visual" in OS.get_cmdline_user_args():
		var packed := load("res://scenes/agent_sandbox.tscn") as PackedScene
		var sandbox := packed.instantiate() if packed != null else null
		if sandbox == null:
			errors.append("agent_sandbox could not be instantiated for Forward+ inspection")
		else:
			root.add_child(sandbox)
			for frame in 10:
				await process_frame
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			screenshot.save_png("user://ember_sandbox_native_voxel_batch.png")
			print("VISUAL: ", ProjectSettings.globalize_path("user://ember_sandbox_native_voxel_batch.png"))
			sandbox.free()
	if not errors.is_empty():
		printerr("FAIL sandbox native voxel batch")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS sandbox native voxel batch")
	print("  6 Godot Resources equal the reviewed transient conversion")
	print("  6 scene-used prefabs are current and valid")
	print("  legacy sandbox candidate queue is empty")
	return 0
