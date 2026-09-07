@tool
class_name EmberCombatEffectCatalog
extends RefCounted
## Shared editor/runtime lookup for reusable combat effect steps.

const ROOT := "res://content/combat/effects"

static var _ordered: Array[Resource] = []
static var _by_id := {}


static func ids() -> PackedStringArray:
	var result := PackedStringArray()
	for effect in resources():
		result.append(str(effect.get("effect_id")).strip_edges())
	return result


static func resources() -> Array[Resource]:
	_ensure_cache()
	return _ordered.duplicate()


static func refresh() -> void:
	_ordered.clear()
	_by_id.clear()
	_reload()


static func resource(effect_id: String) -> Resource:
	var clean := effect_id.strip_edges()
	if clean.is_empty():
		return null
	_ensure_cache()
	var cached := _by_id.get(clean, null) as Resource
	if cached != null and str(cached.get("effect_id")) == clean:
		return cached
	refresh()
	return _by_id.get(clean, null) as Resource


static func definitions() -> Dictionary:
	var result := {}
	for effect in resources():
		result[str(effect.get("effect_id"))] = effect.call("to_definition")
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
		var effect := ResourceLoader.load(
			ROOT.path_join(filename), "", ResourceLoader.CACHE_MODE_REUSE
		) as Resource
		if effect == null or str(effect.get("effect_id")).strip_edges().is_empty():
			continue
		_ordered.append(effect)
		_by_id[str(effect.get("effect_id"))] = effect
	_ordered.sort_custom(func(left: Resource, right: Resource) -> bool:
		return str(left.get("effect_id")) < str(right.get("effect_id"))
	)
