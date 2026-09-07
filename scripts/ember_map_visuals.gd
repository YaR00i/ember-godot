@tool
class_name EmberMapVisuals
extends RefCounted
## CPU-only schematic previews over the existing map/tileset/region contract.
## Textures are editor cache only; map JSON and runtime scene ownership stay put.

const PREVIEW_SIZE := Vector2i(96, 96)
const BACKGROUND := Color("171922")
const REGION_COLOR := Color("ffd35a")
const PROP_COLOR := Color("f3f0dc")

static var _texture_cache: Dictionary = {}


static func map_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for map_id in EmberInteractionContent.map_ids():
		var document := _document(map_id)
		if document.is_empty():
			continue
		var name_ru := str(document.get("nameRu", map_id)).strip_edges()
		var width := int(document.get("width", 0))
		var depth := int(document.get("height", 0))
		var regions: Array = document.get("regions", [])
		var scene_path := EmberMapTransition.scene_path(map_id)
		var scene_ready := ResourceLoader.exists(scene_path)
		result.append({
			"id": map_id,
			"label": "%s\n%s" % [name_ru if not name_ru.is_empty() else map_id, map_id],
			"tooltip": "%s\nmapId: %s\n%d×%d · регионов: %d\n%s" % [
				name_ru,
				map_id,
				width,
				depth,
				regions.size(),
				"Godot-сцена готова" if scene_ready else "⚠ Godot-сцена ещё не создана",
			],
			"texture": _texture(map_id),
		})
	return result


static func region_entries(map_id: String, include_default := true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var document := _document(map_id)
	if document.is_empty():
		return result
	if include_default:
		result.append({
			"id": "",
			"label": "Стандартный вход\nstart/player_start",
			"tooltip": "Не задавать targetRegionId; runtime использует стандартную точку входа карты.",
			"texture": _texture(map_id),
		})
	var regions: Array = document.get("regions", [])
	for raw_region in regions:
		if typeof(raw_region) != TYPE_DICTIONARY:
			continue
		var region: Dictionary = raw_region
		var region_id := str(region.get("id", "")).strip_edges()
		if region_id.is_empty():
			continue
		var kind := str(region.get("kind", "region"))
		var note := str(region.get("note", "")).strip_edges()
		result.append({
			"id": region_id,
			"label": "%s\n%s" % [region_id, kind],
			"tooltip": "%s · %s\n%s\n%d,%d · %d×%d" % [
				region_id,
				kind,
				note if not note.is_empty() else "Без заметки",
				int(region.get("x", 0)),
				int(region.get("y", 0)),
				maxi(1, int(region.get("w", 1))),
				maxi(1, int(region.get("h", 1))),
			],
			"texture": _texture(map_id, region_id),
		})
	return result


static func map_image(map_id: String, region_id := "") -> Image:
	var document := _document(map_id)
	if document.is_empty():
		return Image.new()
	var surface := EmberTileMesher.surface_grid(document)
	var width := int(surface.get("width", 0))
	var depth := int(surface.get("depth", 0))
	if width < 1 or depth < 1:
		return Image.new()
	var colors := EmberTileMesher.tileset_colors(str(document.get("tilesetId", "village_16")))
	var heights: PackedInt32Array = surface.get("heights", PackedInt32Array())
	var tile_ids: PackedInt32Array = surface.get("tileIds", PackedInt32Array())
	var image := Image.create(PREVIEW_SIZE.x, PREVIEW_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(BACKGROUND)
	var cell_size := maxi(1, mini((PREVIEW_SIZE.x - 8) / width, (PREVIEW_SIZE.y - 8) / depth))
	var offset := Vector2i(
		(PREVIEW_SIZE.x - width * cell_size) / 2,
		(PREVIEW_SIZE.y - depth * cell_size) / 2,
	)
	for y in depth:
		for x in width:
			var index := y * width + x
			if index >= heights.size() or heights[index] <= 0:
				continue
			var color: Color = colors.get(tile_ids[index], Color(0.35, 0.32, 0.28))
			color = color.lightened(minf(float(heights[index]) / 128.0, 0.18))
			image.fill_rect(
				Rect2i(offset + Vector2i(x, y) * cell_size, Vector2i(cell_size, cell_size)),
				color,
			)
	_draw_props(image, document, offset, cell_size, width, depth)
	if not region_id.is_empty():
		var region := _region(document, region_id)
		if not region.is_empty():
			_draw_region(image, region, offset, cell_size, width, depth)
	return image


static func _texture(map_id: String, region_id := "") -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var path := EmberPack.map_path(map_id)
	var key := "%s:%s:%d" % [map_id, region_id, FileAccess.get_modified_time(path)]
	if _texture_cache.has(key):
		return _texture_cache[key] as Texture2D
	var image := map_image(map_id, region_id)
	if image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	_texture_cache[key] = texture
	return texture


static func _draw_props(
	image: Image,
	document: Dictionary,
	offset: Vector2i,
	cell_size: int,
	width: int,
	depth: int,
) -> void:
	var props: Array = document.get("voxelProps", [])
	for raw_prop in props:
		if typeof(raw_prop) != TYPE_DICTIONARY:
			continue
		var x := int(raw_prop.get("x", -1))
		var y := int(raw_prop.get("y", -1))
		if x < 0 or y < 0 or x >= width or y >= depth:
			continue
		var marker := maxi(1, cell_size / 2)
		var center := offset + Vector2i(x, y) * cell_size + Vector2i(cell_size / 2, cell_size / 2)
		image.fill_rect(Rect2i(center - Vector2i(marker / 2, marker / 2), Vector2i(marker, marker)), PROP_COLOR)


static func _draw_region(
	image: Image,
	region: Dictionary,
	offset: Vector2i,
	cell_size: int,
	width: int,
	depth: int,
) -> void:
	var x := clampi(int(region.get("x", 0)), 0, width - 1)
	var y := clampi(int(region.get("y", 0)), 0, depth - 1)
	var w := clampi(maxi(1, int(region.get("w", 1))), 1, width - x)
	var h := clampi(maxi(1, int(region.get("h", 1))), 1, depth - y)
	var rect := Rect2i(offset + Vector2i(x, y) * cell_size, Vector2i(w, h) * cell_size)
	var thickness := 2 if cell_size > 1 else 1
	image.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, thickness)), REGION_COLOR)
	image.fill_rect(Rect2i(rect.position + Vector2i(0, rect.size.y - thickness), Vector2i(rect.size.x, thickness)), REGION_COLOR)
	image.fill_rect(Rect2i(rect.position, Vector2i(thickness, rect.size.y)), REGION_COLOR)
	image.fill_rect(Rect2i(rect.position + Vector2i(rect.size.x - thickness, 0), Vector2i(thickness, rect.size.y)), REGION_COLOR)


static func _document(map_id: String) -> Dictionary:
	var raw: Variant = EmberPack.parse_json_file(EmberPack.map_path(map_id))
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


static func _region(document: Dictionary, region_id: String) -> Dictionary:
	var regions: Array = document.get("regions", [])
	for raw_region in regions:
		if typeof(raw_region) == TYPE_DICTIONARY and str(raw_region.get("id", "")) == region_id:
			return raw_region as Dictionary
	return {}
