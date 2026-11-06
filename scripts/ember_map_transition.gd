class_name EmberMapTransition
extends RefCounted
## Process-local map transition handoff. The authored targetMapId/targetRegionId
## remains in the existing Ember schema; no Godot-only save format is created.

const DEFAULT_MAP_ID := "landscape_compact"
const RETIRED_MAP_IDS := ["fan_town", "fan_town_house", "fan_town_inn", "fan_town_mage", "fan_town_smith", "agent_sandbox", "agent_sandbox_interior", "test_pier"]
const RETURN_TRIGGER_GUARD_MS := 1200
const LOCATION_TEST_MODE := &"ember_location_test_mode"
const TEST_DESTINATIONS := {
	"Основная карта": {
		"landscape_compact": "Берег и опушка", "coastal_house_interior": "Дом у берега",
	},
	"Глава 1 · город": {
		"chapter1_residential": "Жилая улица", "chapter1_home": "Дом Кая",
		"chapter1_centre": "Центр и торговая улица", "chapter1_guild": "Гильдия",
		"chapter1_general_store": "Лавка", "chapter1_smith": "Кузница",
		"chapter1_alchemy": "Алхимическая лавка", "chapter1_harbor": "Порт",
		"chapter1_estate": "Двор и сад Миры", "chapter1_mansion": "Особняк Миры",
	},
	"Глава 1 · за городом": {
		"chapter1_woodland": "Опушка и склоны", "chapter1_coast": "Побережье",
		"chapter1_tide_cave": "Приливная пещера",
	},
	"Полигоны": {
		"mira_palace_test": "Дворец и сад Миры · проба",
		"traversal_ice_park": "Каток и сани", "traversal_vine_park": "Парк лиан",
		"traversal_cable_park": "Парк канатов",
	},
}

static var _pending_map_id := ""
static var _pending_region_id := ""
static var _pending_cargo: Array[Dictionary] = []
static var _cargo_map_id := ""
static var _blocked_region_id := ""
static var _blocked_until_ms := 0
static var _blocked_until_frame := 0


static func scene_path(map_id: String) -> String:
	return "res://scenes/%s.tscn" % map_id

static func saved_destination(map_id: String) -> Dictionary:
	var clean := map_id.strip_edges()
	var path := scene_path(clean)
	if not clean.is_empty() and clean not in RETIRED_MAP_IDS and ResourceLoader.exists(path):
		return {"map_id": clean, "at_entry": false}
	# Retired maps must never reopen, even while their archived scenes are still
	# physically present. An unavailable fallback remains a controlled load error.
	if clean in RETIRED_MAP_IDS or ResourceLoader.exists(scene_path(DEFAULT_MAP_ID)):
		return {"map_id": DEFAULT_MAP_ID, "at_entry": true}
	return {"map_id": clean, "at_entry": false}



static func prepare(map_id: String, region_id: String) -> void:
	_pending_map_id = map_id.strip_edges()
	_pending_region_id = region_id.strip_edges()


static func change_scene(tree: SceneTree, map_id: String, region_id: String) -> Error:
	var clean_map_id := map_id.strip_edges()
	var path := scene_path(clean_map_id)
	if tree == null or clean_map_id.is_empty() or not ResourceLoader.exists(path):
		_clear_pending()
		return ERR_FILE_NOT_FOUND
	prepare(clean_map_id, region_id)
	_pending_cargo.clear()
	_cargo_map_id = clean_map_id
	if tree.current_scene != null:
		for body in tree.get_nodes_in_group("ember_world_item_bodies"):
			if not tree.current_scene.is_ancestor_of(body) or body.is_queued_for_deletion() or not body.is_carried(): continue
			body.capture_progress()
			var progress := body.get("progress_state") as EmberExploreState
			var row: Dictionary = progress.world_items.get(body.pickup_id, {}) if progress != null else {}
			if int(row.get("count", 0)) > 0:
				_pending_cargo.append({"id":body.pickup_id,"sourceMapId":body.map_id,"heroId":str(row.get("carrierHeroId", ""))})
	var error := tree.change_scene_to_file(path)
	if error != OK:
		_clear_pending()
	return error

static func test_mode(progress: EmberExploreState) -> bool:
	return progress != null and bool(progress.get_meta(LOCATION_TEST_MODE, false))

static func enable_test_mode(progress: EmberExploreState) -> void:
	progress.set_meta(LOCATION_TEST_MODE, true)
	progress.persistence_enabled = false
	progress.restore_enabled = false

static func restart_test_session(tree: SceneTree, progress: EmberExploreState) -> Error:
	if tree == null or tree.current_scene == null or progress == null or progress.combat_party_locked:
		return ERR_UNAVAILABLE
	var path := tree.current_scene.scene_file_path
	if path.is_empty() or not ResourceLoader.exists(path):
		return ERR_FILE_NOT_FOUND
	var scene := load(path) as PackedScene
	if scene == null or not scene.can_instantiate():
		return ERR_CANT_CREATE
	var was_testing := test_mode(progress)
	var old_persistence := progress.persistence_enabled
	var old_restore := progress.restore_enabled
	enable_test_mode(progress)
	if not progress.reset_new_game():
		if not was_testing:
			progress.remove_meta(LOCATION_TEST_MODE)
		progress.persistence_enabled = old_persistence
		progress.restore_enabled = old_restore
		return ERR_INVALID_DATA
	_clear_pending()
	return tree.change_scene_to_packed(scene)

static func visit_test_location(tree: SceneTree, progress: EmberExploreState, map_id: String) -> Error:
	if progress == null or progress.combat_party_locked:
		return ERR_UNAVAILABLE
	var available := false
	for group: Dictionary in TEST_DESTINATIONS.values():
		if group.has(map_id):
			available = true
			break
	if not available:
		return ERR_INVALID_PARAMETER
	var was_testing := test_mode(progress)
	var old_persistence := progress.persistence_enabled
	var old_restore := progress.restore_enabled
	enable_test_mode(progress)
	var arrival := "landscape_compact_start" if map_id == DEFAULT_MAP_ID else "entry"
	var result := change_scene(tree, map_id, arrival)
	if result != OK:
		if not was_testing:
			progress.remove_meta(LOCATION_TEST_MODE)
		progress.persistence_enabled = old_persistence
		progress.restore_enabled = old_restore
	return result

static func consume_cargo(map_id: String) -> Array[Dictionary]:
	if _cargo_map_id != map_id: return []
	var result := _pending_cargo.duplicate(true)
	_pending_cargo.clear(); _cargo_map_id = ""
	return result


static func consume_spawn_region(map_id: String, now_ms := -1) -> String:
	if _pending_map_id != map_id:
		return ""
	var region_id := _pending_region_id
	_pending_map_id = ""
	_pending_region_id = ""
	if not region_id.is_empty():
		guard_arrival(region_id, now_ms)
	return region_id


static func guard_arrival(region_id: String, now_ms := -1) -> void:
	_blocked_region_id = region_id.strip_edges()
	_blocked_until_ms = _now_ms(now_ms) + RETURN_TRIGGER_GUARD_MS
	# A large Surface can make the first rendered frame longer than the wall-time
	# guard. Keep a tiny frame floor as well so loading work can never consume the
	# whole protection window before the player sees the destination.
	_blocked_until_frame = Engine.get_process_frames() + 3 if now_ms < 0 else 0


static func trigger_allowed(region_id: String, now_ms := -1) -> bool:
	if region_id != _blocked_region_id:
		return true
	if now_ms < 0 and Engine.get_process_frames() < _blocked_until_frame:
		return false
	return _now_ms(now_ms) >= _blocked_until_ms


static func clear_for_test() -> void:
	_clear_pending()
	_blocked_region_id = ""
	_blocked_until_ms = 0
	_blocked_until_frame = 0


static func _clear_pending() -> void:
	_pending_map_id = ""
	_pending_region_id = ""
	_pending_cargo.clear(); _cargo_map_id = ""


static func _now_ms(override_ms: int) -> int:
	return override_ms if override_ms >= 0 else Time.get_ticks_msec()
