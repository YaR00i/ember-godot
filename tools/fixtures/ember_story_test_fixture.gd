extends RefCounted
## Native story authoring fixtures. Historical story data is never copied.

const Content = preload("res://tools/fixtures/ember_interaction_test_fixture.gd")
const MAP := "story_authoring_fixture"
const PROP := "story_prop"


static func prepare(tree: SceneTree) -> Dictionary:
	var directory := "user://ember-tests/story-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var state := Content.Maps.prepare(tree, directory)
	state.directory = directory
	var expected := OS.get_environment("EMBER_STORY_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	state.refused = expected.is_empty() or expected != actual or not FileAccess.file_exists("res://.story-test-sandbox") or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git")
	if state.refused:
		printerr("REFUSED: run python tools/run_story_tests.py; native authoring requires a disposable project")
		return state
	state = Content.prepare(tree)
	if state.error != OK or state.refused: return state
	state.map = Content.Maps.save_map(MAP, state.directory, [], [], [], 16.0, [], [], 0.0, [{"id": PROP}])
	if state.map == null:
		state.error = ERR_CANT_CREATE
		return state
	# Reference validation catalogs inspect saved res:// files; write only in the
	# guarded disposable project, never an author scene or the working checkout.
	state.scene_path = EmberMapTransition.scene_path(MAP)
	state.error = ResourceSaver.save(state.map, state.scene_path)
	state.source_hashes[state.scene_path] = FileAccess.get_sha256(state.scene_path)
	return state


static func verify_sources(state: Dictionary, errors: Array[String]) -> void:
	Content.verify_sources(state, errors)
