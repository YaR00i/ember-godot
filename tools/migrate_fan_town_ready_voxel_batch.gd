extends SceneTree
## Explicit one-time G1 migration. The --apply guard prevents accidental writes.
## Usage: godot --headless --path . --script res://tools/migrate_fan_town_ready_voxel_batch.gd -- --apply

const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
const Batches = preload("res://addons/ember_import/ember_voxel_migration_batches.gd")


func _init() -> void:
	if not OS.get_cmdline_user_args().has("--apply"):
		printerr("Refusing to write: pass --apply after Godot's -- separator.")
		quit(2)
		return
	var model_ids := Batches.model_ids("fan_town_ready")
	var parity := Parity.inspect_batch(model_ids)
	if not bool(parity.get("ok", false)):
		printerr("FAIL fan_town ready-batch migration: strict parity did not pass")
		for entry in parity.get("entries", []):
			if not bool((entry as Dictionary).get("ok", false)):
				printerr(" - ", entry.get("id", ""), ": ", "; ".join(entry.get("errors", [])))
		quit(1)
		return
	var error := Store.migrate_batch_to_native(model_ids)
	if error != OK:
		printerr("FAIL fan_town ready-batch migration: atomic batch returned ", error)
		quit(1)
		return
	for model_id in model_ids:
		print("MIGRATED ", model_id, " -> ", EmberVoxelCatalog.native_path(model_id))
	print("PASS fan_town ready-batch migration: 7/7 Resources and prefabs written after strict dry-run")
	print("Frozen JOI remains read-only; scene paths and Resource schema are unchanged.")
	quit(0)
