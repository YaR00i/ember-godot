@tool
extends RefCounted
## Pure section-address planning. Selection is editor-only; committed columns
## still belong to the existing terrain Resource. Signed addresses allow growth
## to the west/north without moving previously authored world-space content.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const BLOCKS := 24
const MAX_SELECTION_AXIS := 4


static func plan(source: Terrain, area: Rect2i) -> Dictionary:
	if source == null: return {"error": "РћС‚РєСЂРѕР№С‚Рµ РєРѕРјРїР°РєС‚РЅСѓСЋ РєР°СЂС‚Сѓ."}
	if not area.has_area() or area.size.x > MAX_SELECTION_AXIS or area.size.y > MAX_SELECTION_AXIS:
		return {"error": "Р’С‹Р±РµСЂРёС‚Рµ РґРѕ 4Г—4 СѓС‡Р°СЃС‚РєРѕРІ Р·Р° РѕРґРёРЅ СЂР°Р· (96Г—96 Рј)."}
	var offset := Vector2i(maxi(0, -area.position.x), maxi(0, -area.position.y))
	var extent := Vector2i(ceili(float(source.width) / Terrain.Sections.CELLS), ceili(float(source.depth) / Terrain.Sections.CELLS))
	extent = (extent + offset).max(area.end + offset)
	if extent.x > Terrain.Sections.MAX_AXIS or extent.y > Terrain.Sections.MAX_AXIS:
		return {"error": "Р’С‹РґРµР»РµРЅРёРµ РїСЂРµРІС‹С€Р°РµС‚ РґРѕСЃС‚СѓРїРЅС‹Р№ СЂР°Р·РјРµСЂ РєР°СЂС‚С‹ (528 Рј РїРѕ РѕСЃРё)."}
	var new_keys: Array[Vector2i] = []
	for z in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if not complete(source, Vector2i(x, z)): new_keys.append(Vector2i(x, z) + offset)
	if new_keys.is_empty(): return {"error": "Р—РґРµСЃСЊ СѓР¶Рµ РµСЃС‚СЊ Р·РµРјР»СЏ. Р’С‹РґРµР»РёС‚Рµ РїСѓСЃС‚РѕРµ РјРµСЃС‚Рѕ СЂСЏРґРѕРј СЃ РєР°СЂС‚РѕР№."}
	return {"error": "", "offset": offset, "extent": extent, "keys": new_keys,
		"area": Rect2i((area.position + offset) * BLOCKS, area.size * BLOCKS)}


static func occupied(source: Terrain, key: Vector2i) -> bool:
	if key.x < 0 or key.y < 0: return false
	if source.is_sectioned(): return source.sections.has(key)
	return key.x * Terrain.Sections.CELLS < source.width and key.y * Terrain.Sections.CELLS < source.depth


static func complete(source: Terrain, key: Vector2i) -> bool:
	if not occupied(source,key): return false
	if not source.is_sectioned(): return (key.x+1)*Terrain.Sections.CELLS<=source.width and (key.y+1)*Terrain.Sections.CELLS<=source.depth
	var part: Terrain=source.sections[key]
	return part.width==Terrain.Sections.CELLS and part.depth==Terrain.Sections.CELLS


static func completed_section(header: Terrain, old: Terrain) -> Terrain:
	var part:=empty_section(header)
	for channel in Terrain.Sections.CHANNELS:
		var values=part.get(channel)
		var retained=old.get(channel)
		for z in old.depth:
			for x in old.width: values[x+z*part.width]=retained[x+z*old.width]
		part.set(channel,values)
	for index: int in old.column_material_overrides:
		part.column_material_overrides[index%old.width+(index/old.width)*part.width]=old.column_material_overrides[index].duplicate(true)
	if not old.water_flow.is_empty():
		var flow:=PackedVector2Array();flow.resize((part.width/16)*(part.depth/16))
		for z in old.depth/16:
			for x in old.width/16: flow[x+z*(part.width/16)]=old.water_flow[x+z*(old.width/16)]
		part.water_flow=flow
	return part


static func rebase(source: Terrain, selection: Dictionary) -> Terrain:
	var result := source.sectioned_copy()
	var moved := {}
	for key: Vector2i in result.sections: moved[key + selection.offset] = result.sections[key]
	result.sections = moved
	result.surface_rules=Terrain.SurfaceRules.shifted(result.surface_rules,selection.offset*Terrain.Sections.CELLS)
	# Preserve partial outer sections: section counts are a capacity bound, not the data extent.
	var size: Vector2i = Vector2i(source.width,source.depth)+selection.offset*Terrain.Sections.CELLS
	for key: Vector2i in selection.keys: size=size.max((key+Vector2i.ONE)*Terrain.Sections.CELLS)
	result.width = size.x
	result.depth = size.y
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
