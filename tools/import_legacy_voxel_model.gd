extends SceneTree
## One-way command-line migration helper.
## Usage: godot --headless --path . --script res://tools/import_legacy_voxel_model.gd -- <model_id> [--overwrite]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var overwrite := args.has("--overwrite")
	args.erase("--overwrite")
	if args.size() != 1:
		printerr("usage: import_legacy_voxel_model.gd -- <model_id> [--overwrite]")
		quit(2)
		return
	var report := EmberVoxelLegacyImporter.import_model(args[0], "", overwrite)
	if not bool(report.get("ok", false)):
		printerr("FAIL voxel migration: ", report.get("error", "unknown error"))
		quit(1)
		return
	print("MIGRATED ", args[0], " -> ", report.path)
	print("Godot Resource is now canonical; the JOI pair was not modified.")
	quit(0)
