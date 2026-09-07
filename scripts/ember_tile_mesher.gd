class_name EmberTileMesher
extends RefCounted
## Height-column mesh from Ember map layers. Same units as JOI:
## height layer is voxels; one story = tileSize; voxel world size = tileSize/16.

const VOXELS_PER_BLOCK := 16


static func build(map: Dictionary) -> Dictionary:
	var surface := surface_grid(map)
	var width := int(surface.get("width", 0))
	var depth := int(surface.get("depth", 0))
	var tile_size := float(map.get("tileSize", 16))
	var vw := tile_size / float(VOXELS_PER_BLOCK)
	if width < 1 or depth < 1:
		return {"mesh": ArrayMesh.new(), "cells": 0}
	var colors := tileset_colors(str(map.get("tilesetId", "village_16")))
	var cols: PackedInt32Array = surface.get("heights", PackedInt32Array())
	var tile_ids: PackedInt32Array = surface.get("tileIds", PackedInt32Array())
	var tint: PackedColorArray = PackedColorArray()
	tint.resize(width * depth)
	for index in tile_ids.size():
		if cols[index] > 0:
			tint[index] = colors.get(tile_ids[index], Color(0.35, 0.32, 0.28))
	var cells := int(surface.get("cells", 0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in depth:
		for x in width:
			var i := y * width + x
			var h: int = cols[i]
			if h <= 0:
				continue
			var color: Color = tint[i]
			var o := Vector3(float(x) * tile_size, 0.0, float(y) * tile_size)
			var top_y := float(h) * vw
			_quad(st, color, Vector3.UP, [
				o + Vector3(0, top_y, tile_size),
				o + Vector3(0, top_y, 0),
				o + Vector3(tile_size, top_y, 0),
				o + Vector3(tile_size, top_y, tile_size),
			])
			if _height(cols, width, depth, x, y - 1) < h:
				_quad(st, color.darkened(0.12), Vector3.FORWARD, [
					o + Vector3(tile_size, 0, 0),
					o + Vector3(tile_size, top_y, 0),
					o + Vector3(0, top_y, 0),
					o + Vector3(0, 0, 0),
				])
			if _height(cols, width, depth, x, y + 1) < h:
				_quad(st, color.darkened(0.18), Vector3.BACK, [
					o + Vector3(0, 0, tile_size),
					o + Vector3(0, top_y, tile_size),
					o + Vector3(tile_size, top_y, tile_size),
					o + Vector3(tile_size, 0, tile_size),
				])
			if _height(cols, width, depth, x - 1, y) < h:
				_quad(st, color.darkened(0.22), Vector3.LEFT, [
					o + Vector3(0, 0, 0),
					o + Vector3(0, top_y, 0),
					o + Vector3(0, top_y, tile_size),
					o + Vector3(0, 0, tile_size),
				])
			if _height(cols, width, depth, x + 1, y) < h:
				_quad(st, color.darkened(0.08), Vector3.RIGHT, [
					o + Vector3(tile_size, 0, tile_size),
					o + Vector3(tile_size, top_y, tile_size),
					o + Vector3(tile_size, top_y, 0),
					o + Vector3(tile_size, 0, 0),
				])
	st.index()
	return {"mesh": st.commit(), "cells": cells}


static func surface_grid(map: Dictionary) -> Dictionary:
	## Shared top-surface projection for runtime terrain and editor map previews.
	var width := int(map.get("width", 0))
	var depth := int(map.get("height", 0))
	var tile_size := float(map.get("tileSize", 16))
	var heights := PackedInt32Array()
	var tile_ids := PackedInt32Array()
	if width < 1 or depth < 1:
		return {"width": width, "depth": depth, "heights": heights, "tileIds": tile_ids, "cells": 0}
	heights.resize(width * depth)
	heights.fill(0)
	tile_ids.resize(width * depth)
	tile_ids.fill(0)
	var height := EmberPack.layer_data(map, "height")
	var ground0 := EmberPack.layer_data(map, "ground_z0")
	if ground0.is_empty():
		ground0 = EmberPack.layer_data(map, "ground")
	var ground1 := EmberPack.layer_data(map, "ground_z1")
	var cells := 0
	for y in depth:
		for x in width:
			var index := y * width + x
			var hv := _at(height, index)
			var g0 := _at(ground0, index)
			var g1 := _at(ground1, index)
			if hv <= 0 and g0 <= 0:
				continue
			heights[index] = hv if hv > 0 else 1
			var tile_id := g1 if (hv > int(tile_size) and g1 > 0) else g0
			tile_ids[index] = tile_id if tile_id > 0 else (g0 if g0 > 0 else 1)
			cells += 1
	return {
		"width": width,
		"depth": depth,
		"heights": heights,
		"tileIds": tile_ids,
		"cells": cells,
	}


static func tileset_colors(tileset_id: String) -> Dictionary:
	return _tileset_colors(tileset_id)


static func build_cutaway_roofs(map: Dictionary) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	var volumes: Array = map.get("interiorVolumes", [])
	if volumes.is_empty():
		return sections
	var width := int(map.get("width", 0))
	var depth := int(map.get("height", 0))
	var tile_size := float(map.get("tileSize", 16.0))
	if width < 1 or depth < 1 or tile_size <= 0.0:
		return sections
	var tiles := _tileset_tiles(str(map.get("tilesetId", "village_16")))
	var elevated := _elevated_ground_layers(map)
	var claimed := {}
	for raw_volume in volumes:
		if typeof(raw_volume) != TYPE_DICTIONARY:
			continue
		var volume: Dictionary = raw_volume
		var volume_id := str(volume.get("id", "")).strip_edges()
		var vx := int(volume.get("x", 0))
		var vy := int(volume.get("y", 0))
		var vw := maxi(1, int(volume.get("w", 1)))
		var vh := maxi(1, int(volume.get("h", 1)))
		var x0 := maxi(0, vx - 1)
		var y0 := maxi(0, vy - 1)
		var x1 := mini(width - 1, vx + vw)
		var y1 := mini(depth - 1, vy + vh)
		var cells: Array[Dictionary] = []
		for layer in elevated:
			var elev := int(layer.get("elev", 0))
			var data: Array = layer.get("data", [])
			for y in range(y0, y1 + 1):
				for x in range(x0, x1 + 1):
					var tile_id := _at(data, y * width + x)
					if tile_id <= 0:
						continue
					var tile: Dictionary = tiles.get(tile_id, {})
					var tile_name := str(tile.get("name", "")).to_lower()
					if elev < 2 and not tile_name.contains("крыша"):
						continue
					var key := "%d,%d,%d" % [x, y, elev]
					if claimed.has(key):
						continue
					claimed[key] = volume_id
					cells.append({
						"x": x,
						"y": y,
						"elev": elev,
						"height": maxf(1.0, float(tile.get("defaultHeight", 1.0))),
						"color": EmberLights.hex_color(
							str(tile.get("color", "#888888")),
							Color(0.4, 0.4, 0.4),
						),
					})
		if cells.is_empty():
			continue
		var roof := _build_roof_mesh(cells, x0, y0, tile_size)
		var roof_height := float(roof.get("height", tile_size * 2.0))
		sections.append({
			"id": volume_id if not volume_id.is_empty() else "interior_%d" % sections.size(),
			"origin": Vector3(float(x0) * tile_size, 0.0, float(y0) * tile_size),
			"mesh": roof.get("mesh"),
			"area_position": Vector3(
				(float(vx - x0) + float(vw) * 0.5) * tile_size,
				roof_height * 0.5,
				(float(vy - y0) + float(vh) * 0.5) * tile_size,
			),
			"area_size": Vector3(
				float(vw) * tile_size,
				maxf(roof_height, tile_size),
				float(vh) * tile_size,
			),
			"cells": cells.size(),
		})
	return sections


static func _build_roof_mesh(
	cells: Array[Dictionary],
	x0: int,
	y0: int,
	tile_size: float,
) -> Dictionary:
	var voxel_world := tile_size / float(VOXELS_PER_BLOCK)
	var occupied := {}
	var roof_height := 0.0
	for cell in cells:
		occupied["%d,%d,%d" % [cell.x, cell.y, cell.elev]] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell in cells:
		var x := int(cell.x)
		var y := int(cell.y)
		var elev := int(cell.elev)
		var bottom := float(elev) * tile_size
		var top := bottom + float(cell.height) * voxel_world
		roof_height = maxf(roof_height, top)
		var o := Vector3(float(x - x0) * tile_size, 0.0, float(y - y0) * tile_size)
		var color: Color = cell.color
		_quad(st, color, Vector3.UP, [
			o + Vector3(0, top, tile_size),
			o + Vector3(0, top, 0),
			o + Vector3(tile_size, top, 0),
			o + Vector3(tile_size, top, tile_size),
		])
		if not occupied.has("%d,%d,%d" % [x, y - 1, elev]):
			_quad(st, color.darkened(0.12), Vector3.FORWARD, [
				o + Vector3(tile_size, bottom, 0),
				o + Vector3(tile_size, top, 0),
				o + Vector3(0, top, 0),
				o + Vector3(0, bottom, 0),
			])
		if not occupied.has("%d,%d,%d" % [x, y + 1, elev]):
			_quad(st, color.darkened(0.18), Vector3.BACK, [
				o + Vector3(0, bottom, tile_size),
				o + Vector3(0, top, tile_size),
				o + Vector3(tile_size, top, tile_size),
				o + Vector3(tile_size, bottom, tile_size),
			])
		if not occupied.has("%d,%d,%d" % [x - 1, y, elev]):
			_quad(st, color.darkened(0.22), Vector3.LEFT, [
				o + Vector3(0, bottom, 0),
				o + Vector3(0, top, 0),
				o + Vector3(0, top, tile_size),
				o + Vector3(0, bottom, tile_size),
			])
		if not occupied.has("%d,%d,%d" % [x + 1, y, elev]):
			_quad(st, color.darkened(0.08), Vector3.RIGHT, [
				o + Vector3(tile_size, bottom, tile_size),
				o + Vector3(tile_size, top, tile_size),
				o + Vector3(tile_size, top, 0),
				o + Vector3(tile_size, bottom, 0),
			])
	st.index()
	return {"mesh": st.commit(), "height": roof_height}


static func _height(cols: PackedInt32Array, width: int, depth: int, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= depth:
		return 0
	return cols[y * width + x]


static func _at(data: Array, index: int) -> int:
	if index < 0 or index >= data.size():
		return 0
	return int(data[index])


static func _tileset_colors(tileset_id: String) -> Dictionary:
	var out := {}
	var tiles := _tileset_tiles(tileset_id)
	for id in tiles:
		var tile: Dictionary = tiles[id]
		out[id] = EmberLights.hex_color(str(tile.get("color", "#888888")), Color(0.4, 0.4, 0.4))
	return out


static func _tileset_tiles(tileset_id: String) -> Dictionary:
	var out := {}
	var parsed: Variant = EmberPack.parse_json_file(EmberPack.tileset_path(tileset_id))
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var tiles: Array = parsed.get("tiles", [])
	for raw_tile in tiles:
		if typeof(raw_tile) != TYPE_DICTIONARY:
			continue
		var tile: Dictionary = raw_tile
		var id := int(tile.get("id", 0))
		if id > 0:
			out[id] = tile
	return out


static func _elevated_ground_layers(map: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var layers: Array = map.get("layers", [])
	for raw_layer in layers:
		if typeof(raw_layer) != TYPE_DICTIONARY:
			continue
		var layer: Dictionary = raw_layer
		var name := str(layer.get("name", ""))
		if not name.begins_with("ground_z"):
			continue
		var elev_text := name.trim_prefix("ground_z")
		if not elev_text.is_valid_int():
			continue
		var elev := int(elev_text)
		if elev < 1:
			continue
		out.append({"elev": elev, "data": layer.get("data", [])})
	return out


static func _quad(st: SurfaceTool, color: Color, normal: Vector3, pts: Array) -> void:
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(pts[0])
	st.add_vertex(pts[1])
	st.add_vertex(pts[2])
	st.add_vertex(pts[0])
	st.add_vertex(pts[2])
	st.add_vertex(pts[3])
