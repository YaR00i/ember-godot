extends RefCounted
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")

static func prepare(tree: SceneTree) -> Dictionary:
	var directory := "user://ember-tests/native-voxel-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var state := Maps.prepare(tree, directory)
	state.directory = directory
	var expected := OS.get_environment("EMBER_VOXEL_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	state.refused = expected.is_empty() or expected != actual or not FileAccess.file_exists("res://.voxel-native-test-sandbox") or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git")
	if state.refused:
		printerr("REFUSED: run python tools/run_native_voxel_tests.py; fixture writes require disposable project")
		return state
	var pack := directory.path_join("poison-legacy")
	var models := pack.path_join("voxels/models")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(models))
	ProjectSettings.set_setting("ember/pack_path", ProjectSettings.globalize_path(pack))
	state.poison = models.path_join("retired_model.json")
	var file := FileAccess.open(state.poison, FileAccess.WRITE)
	file.store_string('{"id":"retired_model","model":{"voxelsPerBlock":32}}')
	file.close()
	state.poison_hash = FileAccess.get_sha256(state.poison)
	return state

static func check_detached(state: Dictionary, errors: Array[String]) -> void:
	EmberVoxelPrefab.begin_import()
	if not EmberVoxelCatalog.definition("retired_model").is_empty() or "retired_model" in EmberVoxelCatalog.ids() or not EmberVoxelCatalog.owner("retired_model").is_empty():
		errors.append("native catalog revived legacy model")
	if not str(EmberVoxelPrefab.source_paths("retired_model").source).is_empty() or not EmberVoxelPrefab.source_signature("retired_model").is_empty() or not EmberVoxelPrefab.load_json("retired_model").is_empty():
		errors.append("runtime builder revived legacy source")
	if FileAccess.get_sha256(state.poison) != state.poison_hash: errors.append("runtime changed frozen JSON")
	ProjectSettings.set_setting("ember/pack_path", ProjectSettings.globalize_path(state.directory.path_join("absent-pack")))
	EmberVoxelPrefab.begin_import()
