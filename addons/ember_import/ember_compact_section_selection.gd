@tool
extends RefCounted
## Pure section-address planning. Selection is editor-only; committed columns
## still belong to the existing terrain Resource. Signed addresses allow growth
## to the west/north without moving previously authored world-space content.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const BLOCKS := 24
const MAX_SELECTION_AXIS := 4


static func plan(source: Terrain, area: Rect2i) -> Dictionary:
	if source == null: return {"error": "Откройте компактную карту."}
	if not area.has_area() or area.size.x > MAX_SELECTION_AXIS or area.size.y > MAX_SELECTION_AXIS:
		return {"error": "Выберите до 4×4 участков за один раз (96×96 м)."}
	var offset := Vector2i(maxi(0, -area.position.x), maxi(0, -area.position.y))
	var extent := Vector2i(ceili(float(source.width) / Terrain.Sections.CELLS), ceili(float(source.depth) / Terrain.Sections.CELLS))
	extent = (extent + offset).max(area.end + offset)
	if extent.x > Terrain.Sections.MAX_AXIS or extent.y > Terrain.Sections.MAX_AXIS:
		return {"error": "Выделение превышает доступный размер карты (528 м по оси)."}
	var new_keys: Array[Vector2i] = []
	for z in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if not occupied(source, Vector2i(x, z)): new_keys.append(Vector2i(x, z) + offset)
	if new_keys.is_empty(): return {"error": "Здесь уже есть земля. Выделите пустое место рядом с картой."}
	return {"error": "", "offset": offset, "extent": extent, "keys": new_keys,
		"area": Rect2i((area.position + offset) * BLOCKS, area.size * BLOCKS)}


static func occupied(source: Terrain, key: Vector2i) -> bool:
	if key.x < 0 or key.y < 0: return false
	if source.is_sectioned(): return source.sections.has(key)
	return key.x * Terrain.Sections.CELLS < source.width and key.y * Terrain.Sections.CELLS < source.depth


static func rebase(source: Terrain, selection: Dictionary) -> Terrain:
	var result := source.sectioned_copy()
	var moved := {}
	for key: Vector2i in result.sections: moved[key + selection.offset] = result.sections[key]
	result.sections = moved
	result.width = selection.extent.x * Terrain.Sections.CELLS
	result.depth = selection.extent.y * Terrain.Sections.CELLS
	return result


static func empty_section(header: Terrain) -> Terrain:
	var part := Terrain.new()
	part.width = Terrain.Sections.CELLS
	part.depth = Terrain.Sections.CELLS
	part.height_limit = header.height_limit
	part.origin_y = header.origin_y
	part.palette = header.palette
	part.palette_surface_roles = header.palette_surface_roles
	part.palette_material_ids = header.palette_material_ids
	for channel in Terrain.Sections.CHANNELS:
		var values = PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray()
		values.resize(part.width * part.depth)
		values.fill(4 if channel == "heights" else 1 if channel in ["top_materials", "base_materials"] else 0)
		part.set(channel, values)
	return part
