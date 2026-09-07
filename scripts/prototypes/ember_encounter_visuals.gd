@tool
class_name EmberEncounterVisuals
extends RefCounted
## CPU miniatures for the shared visual picker. No preview data is serialized.

const Catalog := preload("res://scripts/prototypes/ember_encounter_catalog.gd")
const SIZE := Vector2i(112, 88)
const BG := Color("151923")

static var _cache := {}


static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for encounter_id in Catalog.ids():
		var encounter := Catalog.definition(encounter_id)
		if encounter == null:
			continue
		result.append({
			"id": encounter_id,
			"label": "%s\n%s" % [encounter.display_name, encounter_id],
			"tooltip": "%s\nГерои: %d · враги: %d\n%s" % [
				encounter.description,
				encounter.party_unit_ids.size(),
				encounter.enemy_unit_ids.size(),
				"Готово" if encounter.validation_errors().is_empty() else "⚠ Есть ошибки",
			],
			"texture": texture(encounter),
		})
	return result


static func texture(encounter: EmberEncounterResource) -> Texture2D:
	if encounter == null or encounter.battlefield == null or DisplayServer.get_name() == "headless":
		return null
	var key := encounter.content_signature()
	if _cache.has(key):
		return _cache[key] as Texture2D
	var image := image(encounter)
	var result := ImageTexture.create_from_image(image)
	_cache[key] = result
	return result


static func image(encounter: EmberEncounterResource) -> Image:
	var result := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	result.fill(BG)
	if encounter == null or encounter.battlefield == null:
		return result
	var field := encounter.battlefield
	var cell_size := maxi(2, mini((SIZE.x - 12) / field.width, (SIZE.y - 12) / field.height))
	var offset := Vector2i((SIZE.x - field.width * cell_size) / 2, (SIZE.y - field.height * cell_size) / 2)
	for y in field.height:
		for x in field.width:
			var cell := Vector2i(x, y)
			var definition := field.cell_definition(cell)
			var color := Color("46505f")
			if bool(definition.get("blocked", false)):
				color = Color("332f3a")
			elif "frozen" in definition.get("tags", []):
				color = Color("6ba8d9")
			elif "wet" in definition.get("tags", []):
				color = Color("27758f")
			elif str(definition.get("group", "")) == "ember":
				color = Color("c66b34")
			result.fill_rect(Rect2i(offset + cell * cell_size, Vector2i(cell_size - 1, cell_size - 1)), color)
	for cell in field.party_deployment_cells:
		_draw_marker(result, offset + cell * cell_size, cell_size, Color("65d8e9"))
	for cell in field.enemy_deployment_cells:
		_draw_marker(result, offset + cell * cell_size, cell_size, Color("f07883"))
	return result


static func _draw_marker(target: Image, origin: Vector2i, cell_size: int, color: Color) -> void:
	var inset := maxi(1, cell_size / 4)
	var marker_size := maxi(2, cell_size - inset * 2)
	target.fill_rect(Rect2i(origin + Vector2i(inset, inset), Vector2i(marker_size, marker_size)), color)
