@tool
class_name EmberItemVisuals
extends RefCounted
## Read-only visual projection of the canonical item and pixel-icon catalogs.
## It never owns IDs or gameplay data and is safe to reuse in editor pickers.

const Catalog = preload("res://scripts/ember_item_catalog.gd")

static var _images := {}
static var _textures := {}


static func icon_image(icon_id: String) -> Image:
	var clean := icon_id.strip_edges()
	if _images.has(clean):
		return (_images[clean] as Image).duplicate()
	var definition := Catalog.icon_definition(clean)
	var size := maxi(1, int(definition.get("size", 16)))
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var palette: Dictionary = definition.get("palette", {})
	var rows: Variant = definition.get("rows", [])
	if typeof(rows) == TYPE_ARRAY:
		for y in mini(size, rows.size()):
			var row := str(rows[y])
			for x in mini(size, row.length()):
				var color_text := str(palette.get(row.substr(x, 1), "")).strip_edges()
				if not color_text.is_empty():
					image.set_pixel(x, y, Color.from_string(color_text, Color.TRANSPARENT))
	_images[clean] = image
	return image.duplicate()


static func icon_texture(icon_id: String, display_size := 56) -> Texture2D:
	if icon_id.strip_edges().is_empty() or DisplayServer.get_name() == "headless":
		return null
	var key := "%s:%d" % [icon_id.strip_edges(), display_size]
	if _textures.has(key) and is_instance_valid(_textures[key]):
		return _textures[key] as Texture2D
	var image := icon_image(icon_id)
	if image.is_empty():
		return null
	if display_size > 0 and (image.get_width() != display_size or image.get_height() != display_size):
		image.resize(display_size, display_size, Image.INTERPOLATE_NEAREST)
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture


static func item_texture(item_id: String, display_size := 56) -> Texture2D:
	var definition := Catalog.definition(item_id)
	return icon_texture(str(definition.get("iconId", "")), display_size)


static func icon_entries(include_empty := true) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if include_empty:
		entries.append({
			"id": "",
			"label": "Без иконки",
			"tooltip": "Оставить iconId пустым.",
			"texture": null,
		})
	var definitions := Catalog.icon_definitions()
	for icon_id in Catalog.icon_ids():
		var definition: Dictionary = definitions.get(icon_id, {})
		var title := str(definition.get("nameRu", icon_id)).strip_edges()
		entries.append({
			"id": icon_id,
			"label": "%s\n%s" % [title, icon_id],
			"tooltip": "%s · iconId: %s" % [title, icon_id],
			"texture": icon_texture(icon_id),
		})
	return entries


static func item_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for item_id in Catalog.ids():
		var definition := Catalog.definition(item_id)
		var title := str(definition.get("nameRu", item_id)).strip_edges()
		var kind := str(definition.get("kind", "item"))
		entries.append({
			"id": item_id,
			"label": "%s\n%s" % [title, item_id],
			"tooltip": "%s · %s · %s" % [title, kind, item_id],
			"texture": item_texture(item_id),
		})
	return entries


static func item_label(item_id: String) -> String:
	var definition := Catalog.definition(item_id)
	var title := str(definition.get("nameRu", "")).strip_edges()
	return item_id if title.is_empty() else "%s · %s" % [title, item_id]
