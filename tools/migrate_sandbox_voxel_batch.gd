extends SceneTree
## Explicit one-time G1 migration. The --apply guard prevents accidental writes.
## Usage: godot --headless --path . --script res://tools/migrate_sandbox_voxel_batch.gd -- --apply

const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Parity = preload("res://addons/ember_import/ember_voxel_migration_parity.gd")
const MODEL_IDS: Array[String] = [
	"vox_ms8vsb53",
	"vox_vil_bush",
	"vox_vil_counter",
	"vox_vil_mailbox",
	"vox_vil_planter",
	"vox_vil_sign",
]


func _init() -> void:
	if not OS.get_cmdline_user_args().has("--apply"):
		printerr("Refusing to write: pass --apply after Godot's -- separator.")
		quit(2)
		return
	var parity := Parity.inspect_batch(MODEL_IDS)
	if not bool(parity.get("ok", false)):
		printerr("FAIL sandbox migration: strict parity did not pass")
		for entry in parity.get("entries", []):
			if not bool((entry as Dictionary).get("ok", false)):
				printerr(" - ", entry.get("id", ""), ": ", "; ".join(entry.get("errors", [])))
		quit(1)
		return
	var error := Store.migrate_batch_to_native(MODEL_IDS)
	if error != OK:
		printerr("FAIL sandbox migration: atomic batch returned ", error)
		quit(1)
		return
	for model_id in MODEL_IDS:
		print("MIGRATED ", model_id, " -> ", EmberVoxelCatalog.native_path(model_id))
	print("PASS sandbox migration: 6/6 Resources and prefabs written after strict dry-run")
	print("Frozen JOI remains read-only; Godot is now the canonical owner for this batch.")
	quit(0)
