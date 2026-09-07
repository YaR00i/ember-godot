@tool
class_name EmberEncounterCatalog
extends RefCounted
## Shared editor/runtime lookup for native encounter Resources.

const ROOT := "res://content/combat/encounters"


static func ids() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return result
	for filename in dir.get_files():
		if filename.get_extension().to_lower() != "tres":
			continue
		var encounter := ResourceLoader.load(ROOT.path_join(filename)) as EmberEncounterResource
		if encounter != null and not encounter.encounter_id.strip_edges().is_empty():
			result.append(encounter.encounter_id.strip_edges())
	result.sort()
	return result


static func definition(encounter_id: String) -> EmberEncounterResource:
	var clean := encounter_id.strip_edges()
	if clean.is_empty():
		return null
	for filename in _resource_files():
		var encounter := ResourceLoader.load(ROOT.path_join(filename)) as EmberEncounterResource
		if encounter != null and encounter.encounter_id == clean:
			return encounter
	return null


static func resource_path(encounter_id: String) -> String:
	var encounter := definition(encounter_id)
	return encounter.resource_path if encounter != null else ""


static func _resource_files() -> PackedStringArray:
	var result := PackedStringArray()
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return result
	for filename in dir.get_files():
		if filename.get_extension().to_lower() == "tres":
			result.append(filename)
	return result
