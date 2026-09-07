class_name EmberMapTransition
extends RefCounted
## Process-local map transition handoff. The authored targetMapId/targetRegionId
## remains in the existing Ember schema; no Godot-only save format is created.

const RETURN_TRIGGER_GUARD_MS := 1200

static var _pending_map_id := ""
static var _pending_region_id := ""
static var _blocked_region_id := ""
static var _blocked_until_ms := 0
static var _blocked_until_frame := 0


static func scene_path(map_id: String) -> String:
	return "res://scenes/%s.tscn" % map_id


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
	var error := tree.change_scene_to_file(path)
	if error != OK:
		_clear_pending()
	return error


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


static func _now_ms(override_ms: int) -> int:
	return override_ms if override_ms >= 0 else Time.get_ticks_msec()
