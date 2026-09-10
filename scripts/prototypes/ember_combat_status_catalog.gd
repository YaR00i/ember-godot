@tool
class_name EmberCombatStatusCatalog
extends RefCounted
## Shared editor/runtime lookup for canonical combat status Resources.

const ROOT := "res://content/combat/statuses"
const StatusScript := preload("res://scripts/prototypes/ember_combat_status_resource.gd")

static var _ordered: Array[Resource] = []
static var _by_id := {}


static func ids() -> PackedStringArray:
	var result := PackedStringArray()
	for status in resources():
		result.append(status.status_id.strip_edges())
	return result


static func resources() -> Array[Resource]:
	_ensure_cache()
	return _ordered.duplicate()


static func refresh() -> void:
	_ordered.clear()
	_by_id.clear()
	_reload()


static func resource(status_id: String) -> Resource:
	var clean := status_id.strip_edges()
	if clean.is_empty():
		return null
	_ensure_cache()
	var cached := _by_id.get(clean, null) as Resource
	if cached != null and str(cached.get("status_id")) == clean:
		return cached
	refresh()
	return _by_id.get(clean, null) as Resource


static func definition(status_id: String) -> Dictionary:
	var status := resource(status_id)
	return status.call("to_definition") if status != null else {}


static func definitions() -> Dictionary:
	var result := {}
	for status in resources():
		result[str(status.get("status_id"))] = status.call("to_definition")
	return result


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
		var status := ResourceLoader.load(
			ROOT.path_join(filename), "", ResourceLoader.CACHE_MODE_REUSE
		) as Resource
		if (
			status == null
			or status.get_script() != StatusScript
			or str(status.get("status_id")).strip_edges().is_empty()
		):
			continue
		_ordered.append(status)
		_by_id[str(status.get("status_id"))] = status
	_ordered.sort_custom(func(left: Resource, right: Resource) -> bool:
		return str(left.get("status_id")) < str(right.get("status_id"))
	)
