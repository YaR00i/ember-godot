@tool
class_name EmberCombatActionCatalog
extends RefCounted
## Shared editor/runtime lookup for authored combat action Resources.

const ROOT := "res://content/combat/actions"

static var _ordered: Array[EmberCombatActionResource] = []
static var _by_id := {}


static func ids() -> PackedStringArray:
	var result := PackedStringArray()
	for action in resources():
		result.append(action.action_id.strip_edges())
	return result


static func resources() -> Array[EmberCombatActionResource]:
	_ensure_cache()
	return _ordered.duplicate()


static func refresh() -> void:
	_ordered.clear()
	_by_id.clear()
	_reload()


static func _ensure_cache() -> void:
	if _ordered.is_empty():
		_reload()


static func _reload() -> void:
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return
	for filename in dir.get_files():
		if filename.get_extension().to_lower() != "tres":
			continue
		var action := ResourceLoader.load(
			ROOT.path_join(filename), "", ResourceLoader.CACHE_MODE_REUSE
		) as EmberCombatActionResource
		if action == null or action.action_id.strip_edges().is_empty():
			continue
		_ordered.append(action)
		_by_id[action.action_id] = action
	_ordered.sort_custom(func(left: EmberCombatActionResource, right: EmberCombatActionResource) -> bool:
		return left.action_id < right.action_id
	)


static func resource(action_id: String) -> EmberCombatActionResource:
	var clean := action_id.strip_edges()
	if clean.is_empty():
		return null
	_ensure_cache()
	var cached := _by_id.get(clean, null) as EmberCombatActionResource
	if cached != null and cached.action_id == clean:
		return cached
	refresh()
	return _by_id.get(clean, null) as EmberCombatActionResource


static func definition(action_id: String) -> Dictionary:
	var action := resource(action_id)
	return action.to_definition() if action != null else {}


static func definitions() -> Dictionary:
	var result := {}
	for action in resources():
		result[action.action_id] = action.to_definition()
	return result
