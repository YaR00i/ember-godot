extends RefCounted
## Mutation tests may only run in the disposable project made by the runner.

const IDS: Array[String] = ["migration_fixture_json", "migration_fixture_vox"]


static func check() -> bool:
	var expected := OS.get_environment("EMBER_MIGRATION_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if expected.is_empty() or expected != actual:
		printerr("REFUSED: run python tools/run_voxel_migration_tests.py; mutation requires a disposable project")
		return false
	if not FileAccess.file_exists("res://.migration-test-sandbox") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("REFUSED: project is not a migration test sandbox")
		return false
	if EmberPack.pack_root() != "res://migration-fixtures":
		printerr("REFUSED: legacy input must stay inside the disposable project")
		return false
	for model_id in IDS:
		if not EmberVoxelCatalog.owner(model_id).is_empty() or str(EmberVoxelLegacyImporter.source_paths(model_id).json).is_empty():
			printerr("REFUSED: sandbox requires fresh synthetic legacy fixtures")
			return false
	return true


static func interruption_checkpoint() -> void:
	if "--pause-after-migration" not in OS.get_cmdline_user_args():
		return
	var file := FileAccess.open("res://.migration-written", FileAccess.WRITE)
	file.store_string("ready for forced termination")
	file.close()
	# The runner kills this child after observing the marker, before Undo/cleanup.
	OS.delay_msec(30000)
