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


static func expanded(source: TerrainResource, direction: String, mode := MODE_CONTINUE) -> TerrainResource:
	if source == null or not source.validation_errors().is_empty() or direction not in DIRECTIONS or mode not in MODES:
		return null
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
	result.unsupported_holes = source.unsupported_holes
	result.heights = _extend_ints(source.heights, source.width, source.depth, direction, cells)
	result.top_materials = _extend_bytes(source.top_materials, source.width, source.depth, direction, cells)
	result.base_materials = _extend_bytes(source.base_materials, source.width, source.depth, direction, cells)
	result.cap_depths = _extend_bytes(source.cap_depths, source.width, source.depth, direction, cells)
	result.water_levels = _extend_ints(source.water_levels, source.width, source.depth, direction, cells)
	result.water_materials = _extend_bytes(source.water_materials, source.width, source.depth, direction, cells)
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
