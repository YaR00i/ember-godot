@tool
class_name EmberVoxelVisuals
extends RefCounted
## Visual entries for voxel model IDs. Existing PackedScenes use Godot's
## EditorResourcePreview asynchronously; missing prefabs remain explicit.

const Catalog = preload("res://scripts/ember_voxel_catalog.gd")


static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var definitions := Catalog.definitions()
	var model_ids: Array[String] = []
	for raw_id in definitions:
		model_ids.append(str(raw_id))
	model_ids.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for model_id in model_ids:
		var definition: Dictionary = definitions.get(model_id, {})
		var model_raw: Variant = definition.get("model", {})
		var model: Dictionary = model_raw if typeof(model_raw) == TYPE_DICTIONARY else {}
		var title := str(definition.get("nameRu", model.get("nameRu", model_id))).strip_edges()
		if title.is_empty():
			title = model_id
		var tags := _string_values(definition.get("tags", model.get("tags", [])))
		var density := VoxMesher.voxels_per_block(model)
		var blocks_raw: Variant = model.get("sizeBlocks", {})
		var blocks: Dictionary = blocks_raw if typeof(blocks_raw) == TYPE_DICTIONARY else {}
		var scale_line := "%d vox/block · %d×%d×%d blocks" % [
			density,
			maxi(1, int(blocks.get("x", 1))),
			maxi(1, int(blocks.get("y", 1))),
			maxi(1, int(blocks.get("z", 1))),
		]
		var path := EmberVoxelPrefab.prefab_path(model_id)
		var ready := ResourceLoader.exists(path)
		var owner := str(definition.get("_owner", "legacy_import"))
		var owner_line := "Источник: Godot Resource" if owner == "godot" else "Ожидает одноразового импорта из JOI"
		result.append({
			"id": model_id,
			"label": "%s%s\n%s" % ["" if ready else "◇ ", title, model_id],
			"tooltip": "%s\nmodelId: %s\n%s\n%s\n%s\n%s" % [
				title,
				model_id,
				scale_line,
				"Теги: %s" % ", ".join(tags) if not tags.is_empty() else "Теги не заданы",
				owner_line,
			"Prefab готов · %s" % path if ready else "Source preview · prefab создастся только при добавлении",
			],
			"texture": null,
			"previewPath": path if ready else "",
			"previewModelId": model_id,
			"ready": ready,
			"owner": owner,
			"migrated": owner == "godot",
		})
	return result


static func _string_values(raw: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(raw) == TYPE_ARRAY or typeof(raw) == TYPE_PACKED_STRING_ARRAY:
		for value in raw:
			result.append(str(value))
	return result
