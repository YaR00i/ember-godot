@tool
class_name EmberCombatAiProfileCatalog
extends RefCounted
## Shared editor/runtime lookup for authored enemy decision policies.

const ROOT := "res://content/combat/ai_profiles"

static var _ordered: Array[EmberCombatAiProfileResource] = []
static var _by_id := {}


static func ids() -> PackedStringArray:
	var result := PackedStringArray()
	for profile in resources():
		result.append(profile.profile_id.strip_edges())
	return result


static func resources() -> Array[EmberCombatAiProfileResource]:
	_ensure_cache()
	return _ordered.duplicate()


static func refresh() -> void:
	_ordered.clear()
	_by_id.clear()
	_reload()


static func resource(profile_id: String) -> EmberCombatAiProfileResource:
	var clean := profile_id.strip_edges()
	if clean.is_empty():
		return null
	_ensure_cache()
	var cached := _by_id.get(clean, null) as EmberCombatAiProfileResource
	if cached != null and cached.profile_id == clean:
		return cached
	refresh()
	return _by_id.get(clean, null) as EmberCombatAiProfileResource


static func definition(profile_id: String) -> Dictionary:
	var profile := resource(profile_id)
	return profile.to_definition() if profile != null else {}


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
		var profile := ResourceLoader.load(
			ROOT.path_join(filename), "", ResourceLoader.CACHE_MODE_REUSE
		) as EmberCombatAiProfileResource
		if profile == null or profile.profile_id.strip_edges().is_empty():
			continue
		_ordered.append(profile)
		_by_id[profile.profile_id] = profile
	_ordered.sort_custom(func(left: EmberCombatAiProfileResource, right: EmberCombatAiProfileResource) -> bool:
		return left.profile_id < right.profile_id
	)
