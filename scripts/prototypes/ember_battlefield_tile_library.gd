@tool
class_name EmberBattlefieldTileLibrary
extends RefCounted
## Contract for the standard visual MeshLibrary used by Battlefield projection.

const RESOURCE_PATH := "res://content/combat/tiles/ember_battlefield_tiles.tres"
const ITEM_NEUTRAL := 0
const ITEM_WET := 1
const ITEM_EMBER := 2
const ITEM_FROZEN := 3
const ITEM_BLOCKED := 4
const ITEM_BLOCKED_FADED := 5
const EXPECTED_NAMES := {
	ITEM_NEUTRAL: "Neutral",
	ITEM_WET: "Wet",
	ITEM_EMBER: "Ember",
	ITEM_FROZEN: "Frozen",
	ITEM_BLOCKED: "Blocked",
}


static func default_library() -> MeshLibrary:
	return ResourceLoader.load(RESOURCE_PATH, "MeshLibrary", ResourceLoader.CACHE_MODE_REUSE) as MeshLibrary


static func has_item(library: MeshLibrary, item_id: int) -> bool:
	return library != null and item_id in library.get_item_list()


static func validation_errors(library: MeshLibrary) -> PackedStringArray:
	var errors := PackedStringArray()
	if library == null:
		errors.append("Назначьте MeshLibrary визуальных боевых тайлов узлу CombatGridMap.")
		return errors
	for raw_item_id in EXPECTED_NAMES:
		var item_id := int(raw_item_id)
		if not has_item(library, item_id):
			errors.append("MeshLibrary: отсутствует item %d (%s)." % [item_id, EXPECTED_NAMES[item_id]])
			continue
		if library.get_item_name(item_id) != EXPECTED_NAMES[item_id]:
			errors.append("MeshLibrary item %d должен называться %s." % [item_id, EXPECTED_NAMES[item_id]])
		if library.get_item_mesh(item_id) == null:
			errors.append("MeshLibrary item %d не имеет mesh." % item_id)
		if library.get_item_shapes(item_id).is_empty():
			errors.append("MeshLibrary item %d не имеет collision shape." % item_id)
	return errors
