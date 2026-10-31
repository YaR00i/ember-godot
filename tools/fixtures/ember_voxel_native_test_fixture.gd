extends RefCounted
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const IDS := ["qa_native_block", "qa_native_slab", "qa_native_source"]

static func source(id: String) -> EmberVoxelModelResource:
	var size := Vector3i(16,8,16) if id == IDS[1] else Vector3i(16,16,16)
	var result: EmberVoxelModelResource = Shapes.build("block",size,16,Color("a46b45"),id,"Синтетическая форма · " + id).source
	result.tags = PackedStringArray(["test_fixture"])
	return result

static func install() -> bool:
	var expected := OS.get_environment("EMBER_VOXEL_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if expected.is_empty() or expected != actual or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git"): return false
	if not FileAccess.file_exists("res://.voxel-native-test-sandbox") and not FileAccess.file_exists("res://.editor-mechanics-test-sandbox"): return false
	DirAccess.make_dir_recursive_absolute(EmberVoxelCatalog.NATIVE_DIR)
	for id in IDS:
		if not FileAccess.file_exists(EmberVoxelCatalog.native_path(id)):
			if ResourceSaver.save(source(id),EmberVoxelCatalog.native_path(id)) != OK:return false
		if id != IDS[2] and not FileAccess.file_exists(EmberVoxelPrefab.prefab_path(id)):
			if EmberVoxelPrefab.ensure_saved(id,16.0,{}) == null:return false
	return true

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
	if not install():
		state.refused = true
		printerr("REFUSED: synthetic native fixture installation failed")
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
