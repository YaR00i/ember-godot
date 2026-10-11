extends RefCounted
## Test-owned equipment and a saved native map. Never writes author Resources.

const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const WEAPON := "party_fixture_weapon"
const ARENA := "party_fixture_arena"
const ARMOR := "party_fixture_armor"
const WEAPON_NAME := "Тестовое оружие"


static func prepare(tree: SceneTree, debug_damage: float = 0.0) -> Dictionary:
	var directory := "user://ember-tests/party-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	# Isolate the real autoload before _ready, including refused direct runs.
	var state := Maps.prepare(tree, directory)
	state.directory = directory
	var expected := OS.get_environment("EMBER_PARTY_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	state.refused = expected.is_empty() or expected != actual or not FileAccess.file_exists("res://.party-test-sandbox") or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git")
	if state.refused:
		printerr("REFUSED: run python tools/run_party_tests.py; native fixtures require a disposable project")
		return state
	for definition in [
		{"id": WEAPON, "nameRu": WEAPON_NAME, "kind": "weapon_jrpg", "atk": 14},
		{"id": ARENA, "nameRu": "Тестовое оружие арены", "kind": "weapon_arena", "atk": 10},
		{"id": ARMOR, "nameRu": "Тестовая броня", "kind": "armor", "slot": "body", "def": 8},
	]:
		# Copied current items stay untouched; fixture IDs must never collide.
		if FileAccess.file_exists(EmberItemCatalog.native_path(definition.id)):
			state.error = ERR_ALREADY_EXISTS
			continue
		var error := EmberItemCatalog.write_native(definition)
		if error != OK: state.error = error
	state.source_hashes = {}
	for name in DirAccess.get_files_at(EmberItemCatalog.NATIVE_DIR):
		var path: String = EmberItemCatalog.NATIVE_DIR.path_join(name)
		state.source_hashes[path] = FileAccess.get_sha256(path)
	state.map_id = "party_fixture_%d" % OS.get_process_id()
	state.scene = Maps.save_map(state.map_id, directory, [], [], [], 16.0, [], [], debug_damage)
	if state.scene == null:
		state.error = ERR_CANT_CREATE
	else:
		var scene_path: String = directory.path_join(state.map_id + ".tscn")
		state.source_hashes[scene_path] = FileAccess.get_sha256(scene_path)
	return state


static func verify_sources(state: Dictionary, errors: Array[String]) -> void:
	for path in state.source_hashes:
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != state.source_hashes[path]:
			errors.append("runtime changed native item source " + path)
