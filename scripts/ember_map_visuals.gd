@tool
class_name EmberMapVisuals
extends RefCounted
## CPU-only saved-region schematics over native map scenes; never runs a scene.

const PREVIEW_SIZE := Vector2i(96, 96)
const BACKGROUND := Color("171922")
const REGION_COLOR := Color("ffd35a")
static var _texture_cache: Dictionary = {}


static func map_entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for map_id in EmberInteractionContent.map_ids():
		# Map cards stay lightweight. Saved geometry/regions belong to the
		# selected entrance view, not an eager load of every authored scene.
		var path := EmberInteractionContent.MAP_SCENE_DIRECTORY.path_join(map_id + ".tscn")
		result.append({
			"id": map_id, "label": map_id,
			"tooltip": "Карта Godot · %s\n%s\nСхема сохранённых регионов доступна при выборе точки входа." % [map_id, path],
			"texture": null,
		})
	return result


static func region_entries(map_id: String, include_default := true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var document := EmberInteractionContent.map_snapshot(map_id)
	if document.is_empty(): return result
	if include_default:
		result.append({"id": "", "label": "Стандартный вход\nplayer_start",
			"tooltip": "Не задавать targetRegionId; runtime использует старт карты.", "texture": _texture(map_id)})
	for region in document.get("regions", []):
		var position: Vector3 = region.position
		result.append({"id": region.id, "label": "%s\n%s" % [region.id, region.kind],
			"tooltip": "%s · %s\n%s\nПозиция в карте: %.1f, %.1f, %.1f" % [
				region.id, region.kind, region.note, position.x, position.y, position.z],
			"texture": _texture(map_id, region.id)})
	return result


static func map_image(map_id: String, region_id := "") -> Image:
	var document := EmberInteractionContent.map_snapshot(map_id)
	if document.is_empty(): return Image.new()
	var bounds: Rect2 = document.bounds
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		bounds = Rect2(Vector2.ZERO, Vector2.ONE * 16.0)
	for region in document.regions:
		var position: Vector3 = region.position
		bounds = bounds.expand(Vector2(position.x, position.z))
	var extent := maxf(1.0, maxf(bounds.size.x, bounds.size.y))
	var factor := 80.0 / extent
	var offset := (Vector2(PREVIEW_SIZE) - bounds.size * factor) * 0.5
	var image := Image.create(PREVIEW_SIZE.x, PREVIEW_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(BACKGROUND)
	var rect := Rect2i(Vector2i(offset), Vector2i(bounds.size * factor).max(Vector2i.ONE))
	image.fill_rect(rect, Color("334442"))
	for region in document.regions:
		var position: Vector3 = region.position
		var point := Vector2i(offset + (Vector2(position.x, position.z) - bounds.position) * factor)
		var selected := str(region.id) == region_id
		var radius := 4 if selected else 1
		var marker := Rect2i(point - Vector2i.ONE * radius, Vector2i.ONE * (radius * 2 + 1))
		image.fill_rect(marker.intersection(Rect2i(Vector2i.ZERO, PREVIEW_SIZE)), REGION_COLOR if selected else Color("bccbc8"))
	return image


static func _texture(map_id: String, region_id := "") -> Texture2D:
	if DisplayServer.get_name() == "headless": return null
	var document := EmberInteractionContent.map_snapshot(map_id)
	var key := "%s:%s:%s" % [map_id, region_id, str(document).sha256_text()]
	if _texture_cache.has(key): return _texture_cache[key]
	var picture := map_image(map_id, region_id)
	if picture.is_empty(): return null
	var texture := ImageTexture.create_from_image(picture)
	# Keep one current image per selection, not every revision of a saved scene.
	var slot := map_id + ":" + region_id
	var previous: String = _texture_cache.get(slot, "")
	if not previous.is_empty(): _texture_cache.erase(previous)
	_texture_cache[slot] = key
	_texture_cache[key] = texture
	return texture
