class_name EmberInteractionContent
extends RefCounted
## Read-only adapter over action JSON and Godot-native/legacy dialogue content.

const MAX_SCRIPT_DEPTH := 8
const ActionCatalog = preload("res://scripts/ember_action_catalog.gd")
const DialogueCatalog = preload("res://scripts/ember_dialogue_catalog.gd")
const ShopCatalog = preload("res://scripts/ember_shop_catalog.gd")
const ItemCatalog = preload("res://scripts/ember_item_catalog.gd")


static func resolve_script_ref(ref_id: String) -> Dictionary:
	var clean_id := ref_id.strip_edges()
	if clean_id.is_empty():
		return {}
	var script := ActionCatalog.document(clean_id)
	if not script.is_empty():
		return {"kind": "script", "data": script}
	var scene := DialogueCatalog.document(clean_id)
	if not scene.is_empty():
		return {"kind": "scene", "data": scene}
	return {}


static func dialogue_for_id(ref_id: String) -> Dictionary:
	return _dialogue_for_id(ref_id, {}, 0)


static func shop_view(shop_id: String) -> Dictionary:
	var shop := shop_definition(shop_id)
	if shop.is_empty():
		return {}
	return {
		"id": str(shop.get("id", shop_id)),
		"nameRu": str(shop.get("nameRu", shop_id)),
		"listings": EmberEconomy.listing_views(
			shop,
			EmberEconomy.seed_shop_remaining(shop),
			item_definitions(),
		),
	}


static func shop_definition(shop_id: String) -> Dictionary:
	return ShopCatalog.definition(shop_id)


static func item_definitions() -> Dictionary:
	return ItemCatalog.definitions()


static func script_ref_ids() -> Array[String]:
	var ids := ActionCatalog.ids()
	for scene_id in DialogueCatalog.ids():
		if scene_id not in ids:
			ids.append(scene_id)
	ids.sort()
	return ids


static func action_script_ids() -> Array[String]:
	return ActionCatalog.ids()


static func dialogue_ids() -> Array[String]:
	return DialogueCatalog.ids()


static func item_ids() -> Array[String]:
	return ItemCatalog.ids()


static func shop_ids() -> Array[String]:
	return ShopCatalog.ids()


static func map_ids() -> Array[String]:
	return _json_ids_in_dir(EmberPack.pack_root().path_join("maps"))


static func region_ids(map_id: String) -> Array[String]:
	var result: Array[String] = []
	if map_id.strip_edges().is_empty():
		return result
	var map: Variant = EmberPack.parse_json_file(EmberPack.map_path(map_id))
	if typeof(map) != TYPE_DICTIONARY:
		return result
	var regions: Variant = map.get("regions", [])
	if typeof(regions) != TYPE_ARRAY:
		return result
	for raw_region in regions:
		if typeof(raw_region) == TYPE_DICTIONARY:
			var region_id := str(raw_region.get("id", "")).strip_edges()
			if not region_id.is_empty():
				result.append(region_id)
	result.sort()
	return result


static func region_definition(map_id: String, region_id: String) -> Dictionary:
	var clean_map := map_id.strip_edges()
	var clean_region := region_id.strip_edges()
	if clean_map.is_empty() or clean_region.is_empty():
		return {}
	var map: Variant = EmberPack.parse_json_file(EmberPack.map_path(clean_map))
	if typeof(map) != TYPE_DICTIONARY:
		return {}
	var regions: Variant = (map as Dictionary).get("regions", [])
	if typeof(regions) != TYPE_ARRAY:
		return {}
	for raw_region in regions:
		if (
			typeof(raw_region) == TYPE_DICTIONARY
			and str((raw_region as Dictionary).get("id", "")) == clean_region
		):
			return (raw_region as Dictionary).duplicate(true)
	return {}


static func _dialogue_for_id(ref_id: String, visited: Dictionary, depth: int) -> Dictionary:
	if depth >= MAX_SCRIPT_DEPTH or visited.has(ref_id):
		return {}
	visited[ref_id] = true
	var resolved := resolve_script_ref(ref_id)
	if resolved.is_empty():
		return {}
	var data: Dictionary = resolved.get("data", {})
	if str(resolved.get("kind", "")) == "scene":
		return data
	var steps: Variant = data.get("steps", [])
	if typeof(steps) != TYPE_ARRAY:
		return {}
	for raw_step in steps:
		if typeof(raw_step) != TYPE_DICTIONARY:
			continue
		var step: Dictionary = raw_step
		match str(step.get("type", "")):
			"talk":
				var scene_id := str(step.get("dialogueId", ""))
				var nested := _dialogue_for_id(scene_id, visited, depth + 1)
				if not nested.is_empty():
					return nested
			"run_script":
				var nested_id := str(step.get("scriptId", ""))
				var nested := _dialogue_for_id(nested_id, visited, depth + 1)
				if not nested.is_empty():
					return nested
	return {}


static func _json_ids_in_dir(path: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.get_extension().to_lower() == "json":
			result.append(file_name.get_basename())
		file_name = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result
