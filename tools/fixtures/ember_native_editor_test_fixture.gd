extends RefCounted
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const ID := "diagnostic_fixture"

static func prepare(tree: SceneTree) -> Dictionary:
	var directory := "user://ember-tests/editor-deps-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var state := Maps.prepare(tree, directory)
	state.directory = directory
	var expected := OS.get_environment("EMBER_EDITOR_DEPS_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	state.refused = expected.is_empty() or expected != actual or not FileAccess.file_exists("res://.editor-deps-test-sandbox") or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git")
	if state.refused: printerr("REFUSED: run python tools/run_native_editor_tests.py; native mutations require disposable project")
	return state

static func diagnostic_source(state: Dictionary) -> Dictionary:
	var source: EmberVoxelModelResource = Shapes.build("block", Vector3i(16, 16, 16), 16, Color.BROWN, ID, "Diagnostic fixture").source
	var path := EmberVoxelCatalog.native_path(ID)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if ResourceSaver.save(source, path) != OK: return {}
	var pack := str(state.directory).path_join("poison/voxels/models")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pack))
	var poison := pack.path_join("retired_diagnostic.json")
	var file := FileAccess.open(poison, FileAccess.WRITE)
	file.store_string('{"id":"retired_diagnostic","nameRu":"Retired fixture"}')
	file.close()
	ProjectSettings.set_setting("ember/pack_path", ProjectSettings.globalize_path(pack.get_base_dir().get_base_dir()))
	return {"source": path, "source_hash": FileAccess.get_sha256(path), "poison": poison, "poison_hash": FileAccess.get_sha256(poison)}

static func unchanged(saved: Dictionary) -> bool:
	return FileAccess.get_sha256(saved.source) == saved.source_hash and FileAccess.get_sha256(saved.poison) == saved.poison_hash
