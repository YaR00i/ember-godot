@tool
class_name EmberCombatLootTableCatalog
extends RefCounted
## Shared lookup for reusable enemy loot tables.

const ROOT := "res://content/combat/loot_tables"


static func ids() -> Array[String]:
	var result: Array[String] = []
	for table in resources():
		result.append(table.table_id)
	return result


static func resources() -> Array[EmberCombatLootTableResource]:
	var result: Array[EmberCombatLootTableResource] = []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return result
	for filename in dir.get_files():
		if filename.get_extension().to_lower() != "tres":
			continue
		var table := ResourceLoader.load(
			ROOT.path_join(filename), "", ResourceLoader.CACHE_MODE_IGNORE
		) as EmberCombatLootTableResource
		if table != null and not table.table_id.strip_edges().is_empty():
			result.append(table)
	result.sort_custom(func(left: EmberCombatLootTableResource, right: EmberCombatLootTableResource) -> bool:
		return left.table_id < right.table_id
	)
	return result


static func resource(table_id: String) -> EmberCombatLootTableResource:
	for table in resources():
		if table.table_id == table_id.strip_edges():
			return table
	return null
