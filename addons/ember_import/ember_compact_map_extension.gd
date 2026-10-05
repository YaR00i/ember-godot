@tool
extends RefCounted
## Extends the existing compact terrain owner by one authoring section.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const DIRECTIONS := ["west", "east", "north", "south"]
const MODE_FLAT := "flat"
const MODE_CONTINUE := "continue"
const MODES := [MODE_FLAT, MODE_CONTINUE]
const TRANSITION_BLOCKS := 2
const MAX_SECTION_AXIS := TerrainResource.Sections.MAX_AXIS


static func expanded(source: TerrainResource, direction: String, mode := MODE_CONTINUE, section_index := -1) -> TerrainResource:
	if source == null or not source.validation_errors().is_empty() or direction not in DIRECTIONS or mode not in MODES:
		return null
	if section_index >= 0 or source.is_sectioned():
		return _expanded_sections(source, direction, mode, section_index)
	var cells := Creation.SECTION_BLOCKS * TerrainResource.CELLS_PER_BLOCK
	var max_cells := Creation.MAX_EXTENDED_SECTIONS * cells
	var width := source.width + (cells if direction in ["west", "east"] else 0)
	var depth := source.depth + (cells if direction in ["north", "south"] else 0)
	if width > max_cells or depth > max_cells:
		return null
	var offset_x := cells if direction == "west" else 0
	var offset_z := cells if direction == "north" else 0
	var result := TerrainResource.new()
	result.schema_version = source.schema_version
	result.source_path = source.source_path
	result.source_sha256 = source.source_sha256
	result.width = width
	result.depth = depth
	result.height_limit = source.height_limit
	result.origin_y = source.origin_y
	result.palette = source.palette.duplicate()
	result.palette_surface_roles = source.palette_surface_roles.duplicate()
	result.palette_material_ids = source.palette_material_ids.duplicate()
	result.unsupported_holes = source.unsupported_holes
	result.heights = _extend_ints(source.heights, source.width, source.depth, direction, cells)
	result.top_materials = _extend_bytes(source.top_materials, source.width, source.depth, direction, cells)
	result.base_materials = _extend_bytes(source.base_materials, source.width, source.depth, direction, cells)
	result.cap_depths = _extend_bytes(source.cap_depths, source.width, source.depth, direction, cells)
	result.water_levels = _extend_ints(source.water_levels, source.width, source.depth, direction, cells)
	result.water_materials = _extend_bytes(source.water_materials, source.width, source.depth, direction, cells)
	if not source.water_flow.is_empty():
		var old_blocks_x := ceili(float(source.width) / float(TerrainResource.CELLS_PER_BLOCK))
		var old_blocks_z := ceili(float(source.depth) / float(TerrainResource.CELLS_PER_BLOCK))
		var new_blocks_x := ceili(float(width) / float(TerrainResource.CELLS_PER_BLOCK))
		var new_blocks_z := ceili(float(depth) / float(TerrainResource.CELLS_PER_BLOCK))
		var offset_blocks_x := offset_x / TerrainResource.CELLS_PER_BLOCK
		var offset_blocks_z := offset_z / TerrainResource.CELLS_PER_BLOCK
		result.water_flow.resize(new_blocks_x * new_blocks_z)
		for block_z in new_blocks_z:
			for block_x in new_blocks_x:
				var source_x := block_x - offset_blocks_x
				var source_z := block_z - offset_blocks_z
				var inside := source_x >= 0 and source_z >= 0 and source_x < old_blocks_x and source_z < old_blocks_z
				var outside_blocks := maxi(maxi(-source_x, source_x - old_blocks_x + 1),
					maxi(-source_z, source_z - old_blocks_z + 1))
				var edge_x := clampi(source_x, 0, old_blocks_x - 1)
				var edge_z := clampi(source_z, 0, old_blocks_z - 1)
				var flow := source.water_flow[edge_x + edge_z * old_blocks_x]
				if not inside and mode == MODE_FLAT:
					flow *= 1.0 - smoothstep(0.0, float(TRANSITION_BLOCKS), float(outside_blocks))
				result.water_flow[block_x + block_z * new_blocks_x] = flow
	for raw_index in source.column_material_overrides:
		var old_index := int(raw_index)
		var old_x := old_index % source.width
		var old_z := old_index / source.width
		var value: Dictionary = source.column_material_overrides[raw_index]
		result.column_material_overrides[(old_x + offset_x) + (old_z + offset_z) * width] = value.duplicate(true)
		for edge in cells:
			var next_index := -1
			match direction:
				"west":
					if old_x == 0: next_index = edge + (old_z + offset_z) * width
				"east":
					if old_x == source.width - 1: next_index = (source.width + edge) + old_z * width
				"north":
					if old_z == 0: next_index = old_x + edge * width
				"south":
					if old_z == source.depth - 1: next_index = old_x + (source.depth + edge) * width
			if next_index >= 0 and (mode == MODE_CONTINUE or edge == 0): result.column_material_overrides[next_index] = value.duplicate(true)
	if mode == MODE_FLAT:
		_flatten_new_section(source, result, direction, cells)
	return result if result.validation_errors().is_empty() else null


static func _expanded_sections(source: TerrainResource, direction: String, mode: String, along: int) -> TerrainResource:
	var cells := TerrainResource.Sections.CELLS
	var across := source.depth if direction in ["west", "east"] else source.width
	if along >= ceili(float(across) / cells): return null
	var result := source.sectioned_copy()
	var shift := Vector2i(1 if direction == "west" else 0, 1 if direction == "north" else 0)
	if shift != Vector2i.ZERO:
		var moved := {}
		for key: Vector2i in result.sections: moved[key + shift] = result.sections[key]
		result.sections = moved
	var start := Vector2i(source.width if direction == "east" else 0, source.depth if direction == "south" else 0)
	var length := across if along < 0 else cells
	if direction in ["west", "east"]: start.y = maxi(0, along) * cells
	else: start.x = maxi(0, along) * cells
	var patch := Rect2i(start, Vector2i(cells, length) if direction in ["west", "east"] else Vector2i(length, cells))
	result.width = maxi(source.width + shift.x * cells, patch.end.x)
	result.depth = maxi(source.depth + shift.y * cells, patch.end.y)
	if result.width > MAX_SECTION_AXIS * cells or result.depth > MAX_SECTION_AXIS * cells: return null
	var edge := []
	var sample_heights: Array[int] = []
	for n in length:
		var coord := maxi(0, along) * cells + n
		var x := 0 if direction == "west" else source.width - 1 if direction == "east" else mini(coord, source.width - 1)
		var z := 0 if direction == "north" else source.depth - 1 if direction == "south" else mini(coord, source.depth - 1)
		var index := source.column_index(x, z)
		var item := {}
		for channel in TerrainResource.Sections.CHANNELS: item[channel] = source.column_value(channel, index)
		if item.heights > 0: sample_heights.append(int(item.heights))
		item.flow = source.flow_at_cell(x, z)
		if not source.is_sectioned(): item.overrides = source.column_material_overrides.get(index, {}).duplicate(true)
		else:
			var key := Vector2i(x / cells, z / cells)
			var part := source.sections.get(key) as TerrainResource
			item.overrides = part.column_material_overrides.get(x % cells + (z % cells) * part.width, {}).duplicate(true) if part != null else {}
		edge.append(item)
	sample_heights.sort()
	var flat := clampi(roundi(float(sample_heights[sample_heights.size() / 2] if not sample_heights.is_empty() else 8) / 4.0) * 4, 4, source.height_limit)
	var first := Vector2i(patch.position.x / cells, patch.position.y / cells)
	var last := Vector2i((patch.end.x - 1) / cells, (patch.end.y - 1) / cells)
	for key_z in range(first.y, last.y + 1):
		for key_x in range(first.x, last.x + 1):
			var key := Vector2i(key_x, key_z)
			var bounds := Rect2i(key * cells, Vector2i(mini(cells, result.width - key.x * cells), mini(cells, result.depth - key.y * cells)))
			var part := result.dense_window(bounds)
			var overlap := patch.intersection(bounds)
			for z in range(overlap.position.y, overlap.end.y):
				for x in range(overlap.position.x, overlap.end.x):
					var distance := x - patch.position.x if direction == "east" else patch.end.x - x - 1 if direction == "west" else z - patch.position.y if direction == "south" else patch.end.y - z - 1
					var n := z - patch.position.y if direction in ["west", "east"] else x - patch.position.x
					var item: Dictionary = edge[n]
					var weight := smoothstep(0.0, float(TRANSITION_BLOCKS * 16), float(distance)) if mode == MODE_FLAT else 0.0
					var index := x - bounds.position.x + (z - bounds.position.y) * part.width
					part.heights[index] = clampi(roundi(lerpf(float(item.heights), float(flat), weight) / 4.0) * 4, 4, source.height_limit) if mode == MODE_FLAT else item.heights
					part.top_materials[index] = item.top_materials if item.top_materials > 0 else mini(2, source.palette.size() - 1)
					part.base_materials[index] = item.base_materials if item.base_materials > 0 else 1
					part.cap_depths[index] = mini(item.cap_depths if item.cap_depths > 0 else 3, part.heights[index])
					part.water_levels[index] = item.water_levels if weight < 0.999 else 0
					part.water_materials[index] = item.water_materials if weight < 0.999 else 0
					if mode == MODE_CONTINUE or distance == 0:
						if not item.overrides.is_empty(): part.column_material_overrides[index] = item.overrides.duplicate(true)
				# Keep coarse flow vectors, including on a dry bed, just as the
				# original full-edge extension does. A vector does not add water.
			if source.has_flow():
				if part.water_flow.is_empty(): part.water_flow.resize(ceili(float(part.width) / 16) * ceili(float(part.depth) / 16))
				for z in range(overlap.position.y, overlap.end.y, 16):
					for x in range(overlap.position.x, overlap.end.x, 16):
						var n := z - patch.position.y if direction in ["west", "east"] else x - patch.position.x
						var distance := x - patch.position.x if direction == "east" else patch.end.x - x - 16 if direction == "west" else z - patch.position.y if direction == "south" else patch.end.y - z - 16
						var weight := smoothstep(0.0, float(TRANSITION_BLOCKS * 16), float(distance)) if mode == MODE_FLAT else 0.0
						part.water_flow[(x - bounds.position.x) / 16 + ((z - bounds.position.y) / 16) * ceili(float(part.width) / 16)] = edge[n].flow * (1.0 - weight)
			result.sections[key] = part
	return result if result.validation_errors().is_empty() else null


static func at_address(source: TerrainResource, address: Vector2i, mode := MODE_FLAT) -> TerrainResource:
	if source == null or not source.validation_errors().is_empty() or mode not in MODES or address.x < 0 or address.y < 0 or address.x >= MAX_SECTION_AXIS or address.y >= MAX_SECTION_AXIS: return null
	var result := source.sectioned_copy()
	if result.sections.has(address): return null
	if address.x == ceili(float(source.width) / TerrainResource.Sections.CELLS) and address.y < ceili(float(source.depth) / TerrainResource.Sections.CELLS): return _expanded_sections(source, "east", mode, address.y)
	if address.y == ceili(float(source.depth) / TerrainResource.Sections.CELLS) and address.x < ceili(float(source.width) / TerrainResource.Sections.CELLS): return _expanded_sections(source, "south", mode, address.x)
	var cells := TerrainResource.Sections.CELLS
	var part := source.get_script().new() as TerrainResource
	part.width = cells
	part.depth = cells
	part.height_limit = source.height_limit
	part.origin_y = source.origin_y
	part.palette = source.palette
	part.palette_surface_roles = source.palette_surface_roles
	part.palette_material_ids = source.palette_material_ids
	var nearest: TerrainResource
	var nearest_distance := INF
	for key: Vector2i in result.sections:
		var distance := Vector2(key).distance_squared_to(Vector2(address))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = result.sections[key]
	var level := nearest.heights[(nearest.width / 2) + (nearest.depth / 2) * nearest.width] if nearest != null else 8
	level = clampi(roundi(float(level) / 4.0) * 4, 4, source.height_limit)
	for channel in TerrainResource.Sections.CHANNELS:
		var values = PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray()
		values.resize(cells * cells)
		values.fill(level if channel == "heights" else mini(2, source.palette.size() - 1) if channel == "top_materials" else 1 if channel == "base_materials" else mini(3, level) if channel == "cap_depths" else 0)
		part.set(channel, values)
	result.sections[address] = part
	result.width = maxi(result.width, (address.x + 1) * cells)
	result.depth = maxi(result.depth, (address.y + 1) * cells)
	return result if result.validation_errors().is_empty() else null


static func _flatten_new_section(source: TerrainResource, result: TerrainResource, direction: String, cells: int) -> void:
	var along := source.depth if direction in ["west", "east"] else source.width
	var edge_heights: Array[int] = []
	var wet_levels: Array[int] = []
	var top_counts := {}
	var base_counts := {}
	var liquid_counts := {}
	for along_index in along:
		var edge_x := 0 if direction == "west" else source.width - 1 if direction == "east" else along_index
		var edge_z := 0 if direction == "north" else source.depth - 1 if direction == "south" else along_index
		var edge_index := source.column_index(edge_x, edge_z)
		edge_heights.append(source.heights[edge_index])
		_count(top_counts, int(source.top_materials[edge_index]))
		_count(base_counts, int(source.base_materials[edge_index]))
		if source.water_levels[edge_index] > source.heights[edge_index]:
			wet_levels.append(source.water_levels[edge_index])
			_count(liquid_counts, int(source.water_materials[edge_index]))
	edge_heights.sort()
	wet_levels.sort()
	var flat_height := clampi(roundi(float(edge_heights[edge_heights.size() / 2]) / 4.0) * 4, 0, source.height_limit)
	var flat_top := _most_common(top_counts)
	var flat_base := _most_common(base_counts)
	var carry_liquid := wet_levels.size() * 2 > along
	var flat_liquid_level := wet_levels[wet_levels.size() / 2] if carry_liquid else 0
	var flat_liquid_material := _most_common(liquid_counts) if carry_liquid else 0
	if flat_liquid_level <= flat_height:
		flat_liquid_level = 0
		flat_liquid_material = 0
	var heights := result.heights
	var tops := result.top_materials
	var bases := result.base_materials
	var caps := result.cap_depths
	var liquids := result.water_levels
	var liquid_materials := result.water_materials
	var transition := TRANSITION_BLOCKS * TerrainResource.CELLS_PER_BLOCK
	for along_index in along:
		var edge_x := 0 if direction == "west" else source.width - 1 if direction == "east" else along_index
		var edge_z := 0 if direction == "north" else source.depth - 1 if direction == "south" else along_index
		var source_index := source.column_index(edge_x, edge_z)
		for distance in cells:
			var x := distance if direction == "west" else source.width + distance if direction == "east" else along_index
			var z := distance if direction == "north" else source.depth + distance if direction == "south" else along_index
			if direction == "west": x = cells - 1 - distance
			if direction == "north": z = cells - 1 - distance
			var index := result.column_index(x, z)
			if distance == 0:
				continue
			var weight := smoothstep(0.0, float(transition), float(distance))
			heights[index] = clampi(roundi(lerpf(float(source.heights[source_index]), float(flat_height), weight) / 4.0) * 4, 0, source.height_limit)
			tops[index] = flat_top if distance >= transition / 2 else source.top_materials[source_index]
			bases[index] = flat_base if distance >= transition / 2 else source.base_materials[source_index]
			caps[index] = mini(int(source.cap_depths[source_index]), heights[index])
			liquids[index] = flat_liquid_level if distance >= transition else source.water_levels[source_index]
			liquid_materials[index] = flat_liquid_material if distance >= transition else source.water_materials[source_index]
	result.heights = heights
	result.top_materials = tops
	result.base_materials = bases
	result.cap_depths = caps
	result.water_levels = liquids
	result.water_materials = liquid_materials


static func _count(counts: Dictionary, value: int) -> void:
	counts[value] = int(counts.get(value, 0)) + 1


static func _most_common(counts: Dictionary) -> int:
	var winner := 0
	var frequency := -1
	for value in counts:
		if int(counts[value]) > frequency:
			winner = int(value)
			frequency = int(counts[value])
	return winner


static func _extend_ints(values: PackedInt32Array, old_width: int, old_depth: int, direction: String, cells: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if direction in ["north", "south"]:
		var edge := values.slice(0, old_width) if direction == "north" else values.slice((old_depth - 1) * old_width, old_depth * old_width)
		if direction == "south": result.append_array(values)
		for _row in cells: result.append_array(edge)
		if direction == "north": result.append_array(values)
		return result
	for z in old_depth:
		var row := values.slice(z * old_width, (z + 1) * old_width)
		var edge := PackedInt32Array()
		edge.resize(cells)
		edge.fill(values[z * old_width if direction == "west" else (z + 1) * old_width - 1])
		if direction == "west": result.append_array(edge)
		result.append_array(row)
		if direction == "east": result.append_array(edge)
	return result


static func _extend_bytes(values: PackedByteArray, old_width: int, old_depth: int, direction: String, cells: int) -> PackedByteArray:
	var result := PackedByteArray()
	if direction in ["north", "south"]:
		var edge := values.slice(0, old_width) if direction == "north" else values.slice((old_depth - 1) * old_width, old_depth * old_width)
		if direction == "south": result.append_array(values)
		for _row in cells: result.append_array(edge)
		if direction == "north": result.append_array(values)
		return result
	for z in old_depth:
		var row := values.slice(z * old_width, (z + 1) * old_width)
		var edge := PackedByteArray()
		edge.resize(cells)
		edge.fill(values[z * old_width if direction == "west" else (z + 1) * old_width - 1])
		if direction == "west": result.append_array(edge)
		result.append_array(row)
		if direction == "east": result.append_array(edge)
	return result


static func scene_shift(direction: String, tile_size: float) -> Vector3:
	var distance := float(Creation.SECTION_BLOCKS) * tile_size
	match direction:
		"west": return Vector3(distance, 0.0, 0.0)
		"north": return Vector3(0.0, 0.0, distance)
	return Vector3.ZERO
