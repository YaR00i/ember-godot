extends RefCounted
## Shared identities/evidence for one disposable author -> play -> fresh Load gate.
const STORE = preload("res://addons/ember_import/ember_game_systems_store.gd")
const WEAPON := "cycle_weapon"
const SHOES := "cycle_shoes"
const POTION := "cycle_potion"
const STATUS := "cycle_mark"
const EFFECT := "cycle_apply_mark"
const ACTION := "cycle_marked_strike"
const AI := "cycle_ai"
const LOOT := "cycle_loot"
const ENEMY := "cycle_enemy"
const FIELD := "cycle_field"
const ENCOUNTER := "cycle_encounter"
const MAP := "cycle_map"
const ARENA := "res://scenes/combat/arenas/cycle_arena.tscn"
const DIRECTORY := "user://ember-tests/game-systems-cycle"
const MANIFEST := "res://.game-systems-cycle.json"
const EVIDENCE := DIRECTORY + "/result.json"
const RECORDS := [["start", "default"], ["equipment", WEAPON], ["equipment", SHOES], ["item", POTION], ["status", STATUS], ["effect", EFFECT], ["action", ACTION], ["ai", AI], ["loot", LOOT], ["unit", ENEMY], ["field", FIELD], ["encounter", ENCOUNTER], ["unit", "mira"]]

static func guarded() -> bool:
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	return actual == OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") and actual.contains("ember-game-systems-") and not DirAccess.dir_exists_absolute("res://.git") and FileAccess.file_exists("res://.game-systems-cycle-sandbox")

static func write_json(path: String, data: Dictionary) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return OK

static func file_errors() -> Array[String]:
	var errors: Array[String] = []
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary: return ["saved author manifest missing"]
	for path in manifest.hashes:
		if FileAccess.get_sha256(path) != manifest.hashes[path]: errors.append("saved author file changed: " + path)
		if str(ResourceLoader.get_resource_uid(path)) != str(manifest.uids[path]): errors.append("saved author UID changed: " + path)
	return errors
