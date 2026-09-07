@tool
class_name EmberCombatUnitCatalog
extends RefCounted
## Shared editor/runtime lookup for authored combatant Resources.

const ROOT := "res://content/combat/units"


static func ids(team_filter := "") -> Array[String]:
	var result: Array[String] = []
	for resource in resources(team_filter):
		result.append(resource.unit_id.strip_edges())
	result.sort()
	return result


static func resources(team_filter := "") -> Array[EmberCombatUnitResource]:
	var result: Array[EmberCombatUnitResource] = []
	for filename in _resource_files():
		var unit := ResourceLoader.load(
			ROOT.path_join(filename), "", ResourceLoader.CACHE_MODE_IGNORE
		) as EmberCombatUnitResource
		if unit == null or unit.unit_id.strip_edges().is_empty():
			continue
		if not team_filter.is_empty() and unit.team_id() != team_filter:
			continue
		result.append(unit)
	result.sort_custom(func(left: EmberCombatUnitResource, right: EmberCombatUnitResource) -> bool:
		return left.unit_id < right.unit_id
	)
	return result


static func resource(unit_id: String) -> EmberCombatUnitResource:
	var clean := unit_id.strip_edges()
	if clean.is_empty():
		return null
	for unit in resources():
		if unit.unit_id == clean:
			return unit
	return null


static func definition(unit_id: String) -> Dictionary:
	var unit := resource(unit_id)
	return unit.to_definition() if unit != null else {}


static func definitions() -> Dictionary:
	var result := {}
	var ordered := resources()
	ordered.sort_custom(func(left: EmberCombatUnitResource, right: EmberCombatUnitResource) -> bool:
		if left.team != right.team:
			return left.team < right.team
		if left.prototype_roster_order != right.prototype_roster_order:
			return left.prototype_roster_order < right.prototype_roster_order
		return left.unit_id < right.unit_id
	)
	for unit in ordered:
		result[unit.unit_id] = unit.to_definition()
	return result


static func resource_path(unit_id: String) -> String:
	var unit := resource(unit_id)
	return unit.resource_path if unit != null else ""


static func _resource_files() -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return result
	for filename in dir.get_files():
		if filename.get_extension().to_lower() == "tres":
			result.append(filename)
	return result
