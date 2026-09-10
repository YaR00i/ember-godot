@tool
class_name EmberVoxelSculptModel
extends RefCounted
## Pure authoring operations for the first style-first voxel surface gate.
## The pilot deliberately reuses EmberVoxelModelResource and VoxMesher; it does
## not introduce the future chunked world-surface owner before visual approval.

const PILOT_ID := "ember_surface_pilot"
const PILOT_PATH := "res://content/voxel_models/ember_surface_pilot.tres"
const BATTLE_SURFACE_DIRECTORY := "res://content/combat/surfaces"
const BATTLEFIELD_RESOURCE_DIRECTORY := "res://content/combat/battlefields"
const BattleSurfaceProjection := preload("res://scripts/ember_battle_surface_projection.gd")
const Heightfield := preload("res://scripts/ember_voxel_heightfield.gd")
const WORLD_SURFACE_DIRECTORY := EmberVoxelModelResource.WORLD_SURFACE_DIRECTORY
const INVALID_CELL := Vector3i(-999999, -999999, -999999)

const TOOL_ADD := 0
const TOOL_REMOVE := 1
const TOOL_PAINT := 2
const TOOL_RAISE := 3
const TOOL_LOWER := 4
const TOOL_SHELL_RAISE := 5
const TOOL_LEVEL := 6
const TOOL_SHELL_LOWER := 7
const TOOL_SMOOTH := 8
const TOOL_RAMP := 9
const TOOL_MATERIAL := 10
const TOOL_SURFACE_FILL := 11
const SURFACE_FILL_NONE := 0
const SURFACE_FILL_WATER := 1
const MAX_CONNECTED_MATERIAL_VOXELS := 131072
const MAX_SURFACE_FILL_COLUMNS := 131072
const AUTO_FILL_SEARCH_RADIUS := 128


static func make_pilot() -> EmberVoxelModelResource:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = PILOT_ID
	resource.display_name = "Surface Canvas · ALLfiring/Ember pilot"
	resource.tags = PackedStringArray(["surface", "pilot", "environment", "godot-native"])
	resource.voxels_per_block = 32
	resource.size_blocks = Vector3i(4, 1, 4)
	resource.height_voxels = 24
	resource.palette = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color("#49545a"), # cool stone
		Color("#b98550"), # warm worn path
		Color("#2f7775"), # oxidized/wet accent
		Color("#74505f"), # dark region accent
		Color("#d1a55f"), # landmark highlight
	])
	resource.material = {
		"preset": "surface_pilot",
		"artDirection": "handcrafted_diorama",
	}
	resource.physical = true
	var size := resource.grid_size()
	var values := PackedByteArray()
	values.resize(size.x * size.y * size.z)
	values.fill(0)
	for z in size.z:
		for x in size.x:
			var top := 3
			var palette_index := 1
			# One broad authored terrace, not per-cell random height noise.
			if x >= 70 and z >= 56:
				top = 5
				palette_index = 3
			if x >= 98 and z >= 82:
				top = 7
				palette_index = 4
			# A readable warm route crosses the larger masses.
			var path_center := 24 + x / 3
			if absi(z - path_center) <= 5:
				top = maxi(top, 4)
				palette_index = 2
			# A single chipped boundary demonstrates that the canvas is volumetric.
			if x < 7 and z >= 40 and z <= 54:
				top = maxi(0, top - (7 - x))
			for y in top:
				values[index_of(Vector3i(x, y, z), size)] = palette_index
	resource.voxels = values
	return resource


static func battle_surface_path(field_id: String) -> String:
	var safe_id := field_id.strip_edges().to_lower().validate_filename().replace(" ", "_")
	if safe_id.is_empty():
		safe_id = "battlefield"
	return "%s/%s_surface.tres" % [BATTLE_SURFACE_DIRECTORY, safe_id]


static func world_surface_path(map_id: String) -> String:
	return EmberVoxelModelResource.world_surface_path(map_id)


static func is_writable_resource_path(path: String) -> bool:
	## `res://owner.tres::SubResource_id` is a readable identity, not a file
	## destination accepted by ResourceSaver.
	var normalized := path.strip_edges()
	if normalized.is_empty() or "::" in normalized:
		return false
	if not normalized.begins_with("res://") and not normalized.begins_with("user://"):
		return false
	return normalized.get_extension().to_lower() in ["tres", "res"]


static func surface_save_path(
	resource: EmberVoxelModelResource,
	requested_path: String,
) -> String:
	if is_writable_resource_path(requested_path):
		return requested_path
	if resource == null:
		return ""
	var owner := str(resource.material.get("semanticOwner", "")).strip_edges()
	if "battlefield" in resource.tags and not owner.is_empty():
		return battle_surface_path(owner)
	if "world" in resource.tags and not owner.is_empty():
		return world_surface_path(owner)
	if resource.model_id == PILOT_ID:
		return PILOT_PATH
	return ""


static func battlefield_resource_path_for_surface(resource: EmberVoxelModelResource) -> String:
	if resource == null or "battlefield" not in resource.tags:
		return ""
	var owner := str(resource.material.get("semanticOwner", "")).strip_edges()
	if owner.is_empty():
		return ""
	var direct := "%s/%s.tres" % [
		BATTLEFIELD_RESOURCE_DIRECTORY,
		owner.to_lower().validate_filename().replace(" ", "_"),
	]
	if ResourceLoader.exists(direct):
		return direct
	for file_name in DirAccess.get_files_at(BATTLEFIELD_RESOURCE_DIRECTORY):
		if not file_name.ends_with(".tres"):
			continue
		var candidate_path := "%s/%s" % [BATTLEFIELD_RESOURCE_DIRECTORY, file_name]
		var candidate := load(candidate_path)
		if candidate != null and str(candidate.get("field_id")) == owner:
			return candidate_path
	return ""


static func make_world_surface(
	map_id: String,
	display_name: String,
	surface_grid: Dictionary,
	tile_colors: Dictionary,
) -> EmberVoxelModelResource:
	## Legacy maps use 16 art voxels per gameplay block. Keeping that density for
	## the first map pilot preserves every imported height exactly; the selected
	## rectangle is only an editor scope over this one map-owned Resource.
	var width := clampi(int(surface_grid.get("width", 0)), 1, 128)
	var depth := clampi(int(surface_grid.get("depth", 0)), 1, 128)
	var heights: PackedInt32Array = surface_grid.get("heights", PackedInt32Array())
	var tile_ids: PackedInt32Array = surface_grid.get("tileIds", PackedInt32Array())
	var maximum_height := 1
	for value in heights:
		maximum_height = maxi(maximum_height, int(value))
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "%s_surface" % map_id.strip_edges().to_lower().replace(" ", "_")
	resource.display_name = "%s · общая поверхность" % display_name
	resource.tags = PackedStringArray(["surface", "world", "environment", "godot-native"])
	resource.voxels_per_block = 16
	resource.size_blocks = Vector3i(width, 1, depth)
	resource.height_voxels = clampi(maximum_height + 16, 24, 256)
	resource.material = {
		"preset": "world_surface",
		"artDirection": "handcrafted_diorama",
		"semanticOwner": map_id,
		"selectionIsEditorScope": true,
	}
	resource.physical = false

	var palette := PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color("#5a4437"), # common soil / exposed walls
	])
	var palette_by_tile := {}
	var sorted_tile_ids := tile_colors.keys()
	sorted_tile_ids.sort()
	for raw_tile_id in sorted_tile_ids:
		if palette.size() >= 256:
			break
		var tile_id := int(raw_tile_id)
		palette_by_tile[tile_id] = palette.size()
		palette.append(tile_colors.get(raw_tile_id, Color("#6f9147")) as Color)
	resource.palette = palette

	var size := resource.grid_size()
	var values := PackedByteArray()
	values.resize(size.x * size.y * size.z)
	values.fill(0)
	for block_z in depth:
		for block_x in width:
			var cell_index := block_z * width + block_x
			var column_height := (
				clampi(int(heights[cell_index]), 0, size.y)
				if cell_index < heights.size()
				else 0
			)
			if column_height <= 0:
				continue
			var tile_id := int(tile_ids[cell_index]) if cell_index < tile_ids.size() else 0
			var top_color := int(palette_by_tile.get(tile_id, 1))
			var x_from := block_x * 16
			var z_from := block_z * 16
			for z in range(z_from, z_from + 16):
				for x in range(x_from, x_from + 16):
					for y in column_height:
						values[index_of(Vector3i(x, y, z), size)] = (
							top_color if y == column_height - 1 else 1
						)
	resource.voxels = values
	return resource


static func make_battlefield_surface(
	field_id: String,
	display_name: String,
	width: int,
	depth: int,
	elevations: PackedInt32Array,
	terrain_kinds: PackedByteArray,
	blocked: PackedByteArray,
) -> EmberVoxelModelResource:
	## One visual block maps to one semantic battle cell. Fine voxels may be
	## sculpted freely later; gameplay still reads the Battlefield Resource.
	var safe_width := clampi(width, 1, 64)
	var safe_depth := clampi(depth, 1, 64)
	var density := 32
	var elevation_step := BattleSurfaceProjection.ELEVATION_STEP_VOXELS
	var maximum_elevation := 0
	for value in elevations:
		maximum_elevation = maxi(maximum_elevation, int(value))
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "%s_surface" % field_id.strip_edges().to_lower().replace(" ", "_")
	resource.display_name = "%s · поверхность" % display_name
	resource.tags = PackedStringArray(["surface", "battlefield", "environment", "godot-native"])
	resource.voxels_per_block = density
	resource.size_blocks = Vector3i(safe_width, 1, safe_depth)
	resource.height_voxels = clampi(20 + maximum_elevation * elevation_step, 24, 256)
	resource.palette = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color("#6b4d38"), # common soil / visible walls
		Color("#6f9147"), # neutral grass/stone placeholder
		Color("#2f7775"), # Wet
		Color("#b85e36"), # Ember
		Color("#92b8c7"), # Frozen
		Color("#55454d"), # Blocked
	])
	resource.material = {
		"preset": "battlefield_surface",
		"artDirection": "handcrafted_diorama",
		"semanticOwner": field_id,
	}
	resource.physical = false
	var size := resource.grid_size()
	var values := PackedByteArray()
	values.resize(size.x * size.y * size.z)
	values.fill(0)
	for cell_z in safe_depth:
		for cell_x in safe_width:
			var cell_index := cell_z * safe_width + cell_x
			var elevation := maxi(0, int(elevations[cell_index])) if cell_index < elevations.size() else 0
			var top := mini(
				size.y - 1,
				BattleSurfaceProjection.BASE_TOP_VOXEL + elevation * elevation_step,
			)
			var top_color := 2
			if cell_index < blocked.size() and int(blocked[cell_index]) != 0:
				top_color = 6
			elif cell_index < terrain_kinds.size():
				match int(terrain_kinds[cell_index]):
					1:
						top_color = 3
					2:
						top_color = 4
					3:
						top_color = 5
			var x_from := cell_x * density
			var z_from := cell_z * density
			for z in range(z_from, z_from + density):
				for x in range(x_from, x_from + density):
					for y in range(top + 1):
						values[index_of(Vector3i(x, y, z), size)] = top_color if y == top else 1
	resource.voxels = values
	return resource


static func index_of(cell: Vector3i, size: Vector3i) -> int:
	return cell.x + cell.z * size.x + cell.y * size.x * size.z


static func contains(cell: Vector3i, size: Vector3i) -> bool:
	return (
		cell.x >= 0 and cell.y >= 0 and cell.z >= 0
		and cell.x < size.x and cell.y < size.y and cell.z < size.z
	)


static func line_cells(from: Vector3i, to: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var delta := to - from
	var steps := maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.z)))
	if steps == 0:
		cells.append(from)
		return cells
	var previous := INVALID_CELL
	for step_index in range(steps + 1):
		var progress := float(step_index) / float(steps)
		var cell := Vector3i(
			roundi(float(from.x) + float(delta.x) * progress),
			roundi(float(from.y) + float(delta.y) * progress),
			roundi(float(from.z) + float(delta.z) * progress),
		)
		if cell != previous:
			cells.append(cell)
			previous = cell
	return cells


static func block_region_for_cells(
	from: Vector3i,
	to: Vector3i,
	density: int,
	size_blocks: Vector3i,
) -> Rect2i:
	var safe_density := maxi(1, density)
	var from_block := Vector2i(
		clampi(floori(float(from.x) / float(safe_density)), 0, maxi(0, size_blocks.x - 1)),
		clampi(floori(float(from.z) / float(safe_density)), 0, maxi(0, size_blocks.z - 1)),
	)
	var to_block := Vector2i(
		clampi(floori(float(to.x) / float(safe_density)), 0, maxi(0, size_blocks.x - 1)),
		clampi(floori(float(to.z) / float(safe_density)), 0, maxi(0, size_blocks.z - 1)),
	)
	var minimum := Vector2i(mini(from_block.x, to_block.x), mini(from_block.y, to_block.y))
	var maximum := Vector2i(maxi(from_block.x, to_block.x), maxi(from_block.y, to_block.y))
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


static func changes_in_block_region(
	changes: Dictionary,
	size: Vector3i,
	density: int,
	region: Rect2i,
) -> Dictionary:
	if region.size.x <= 0 or region.size.y <= 0:
		return changes
	var filtered := {}
	var layer_size := size.x * size.z
	var safe_density := maxi(1, density)
	for raw_index in changes:
		var index := int(raw_index)
		var flat := index % layer_size
		var x := flat % size.x
		var z := floori(float(flat) / float(size.x))
		if region.has_point(Vector2i(
			floori(float(x) / float(safe_density)),
			floori(float(z) / float(safe_density)),
		)):
			filtered[index] = changes[raw_index]
	return filtered


static func indices_in_block_region(
	indices: PackedInt32Array,
	size: Vector3i,
	density: int,
	region: Rect2i,
) -> PackedInt32Array:
	if region.size.x <= 0 or region.size.y <= 0:
		return indices
	var filtered := PackedInt32Array()
	var layer_size := size.x * size.z
	var safe_density := maxi(1, density)
	for index in indices:
		var flat := int(index) % layer_size
		var x := flat % size.x
		var z := floori(float(flat) / float(size.x))
		if region.has_point(Vector2i(
			floori(float(x) / float(safe_density)),
			floori(float(z) / float(safe_density)),
		)):
			filtered.append(index)
	return filtered


static func buildup_height(elapsed_seconds: float, voxels_per_second: float, limit: int) -> int:
	var safe_limit := maxi(1, limit)
	var safe_rate := maxf(0.01, voxels_per_second)
	return clampi(1 + floori(maxf(0.0, elapsed_seconds) * safe_rate), 1, safe_limit)


static func column_heights(
	values: PackedByteArray,
	size: Vector3i,
	maximum_palette_index := 255,
) -> PackedInt32Array:
	return Heightfield.column_heights(values, size, maximum_palette_index)


static func refresh_column_heights(
	heights: PackedInt32Array,
	values: PackedByteArray,
	size: Vector3i,
	changed_indices := PackedInt32Array(),
	maximum_palette_index := 255,
) -> PackedInt32Array:
	return Heightfield.refresh_column_heights(
		heights, values, size, changed_indices, maximum_palette_index
	)


static func stroke_changes(
	resource: EmberVoxelModelResource,
	center: Vector3i,
	tool: int,
	palette_index: int,
	brush_radius := 1,
	coarse := false,
) -> Dictionary:
	var changes := {}
	if resource == null:
		return changes
	var size := resource.grid_size()
	if not contains(center, size):
		return changes
	var radius := clampi(brush_radius, 1, 32)
	var extent := radius - 1
	var step := 2 if coarse else 1
	var base_y := floori(float(center.y) / float(step)) * step
	for dz in range(-extent, extent + 1, step):
		for dx in range(-extent, extent + 1, step):
			if Vector2(dx, dz).length() > float(radius) - 0.25:
				continue
			var base_x := floori(float(center.x + dx) / float(step)) * step
			var base_z := floori(float(center.z + dz) / float(step)) * step
			for oy in step:
				for oz in step:
					for ox in step:
						var cell := Vector3i(base_x + ox, base_y + oy, base_z + oz)
						if not contains(cell, size):
							continue
						var index := index_of(cell, size)
						var before := int(resource.voxels[index])
						var after := before
						if tool == TOOL_ADD and before == 0:
							after = clampi(palette_index, 1, resource.palette.size() - 1)
						elif tool == TOOL_REMOVE and before != 0:
							after = 0
						elif tool == TOOL_PAINT and before != 0:
							after = clampi(palette_index, 1, resource.palette.size() - 1)
						if after != before:
							changes[index] = {"before": before, "after": after}
	return changes


static func material_stroke_indices(
	resource: EmberVoxelModelResource,
	center: Vector3i,
	brush_radius := 1,
	coarse := false,
) -> PackedInt32Array:
	## Material paint follows the same visible-volume footprint as color paint,
	## but returns every filled voxel even when its palette color is unchanged.
	var indices := PackedInt32Array()
	if resource == null:
		return indices
	var size := resource.grid_size()
	if not contains(center, size):
		return indices
	var radius := clampi(brush_radius, 1, 32)
	var extent := radius - 1
	var step := 2 if coarse else 1
	var base_y := floori(float(center.y) / float(step)) * step
	for dz in range(-extent, extent + 1, step):
		for dx in range(-extent, extent + 1, step):
			if Vector2(dx, dz).length() > float(radius) - 0.25:
				continue
			var base_x := floori(float(center.x + dx) / float(step)) * step
			var base_z := floori(float(center.z + dz) / float(step)) * step
			for oy in step:
				for oz in step:
					for ox in step:
						var cell := Vector3i(base_x + ox, base_y + oy, base_z + oz)
						if not contains(cell, size):
							continue
						var index := index_of(cell, size)
						if resource.voxels[index] != 0:
							indices.append(index)
	return indices


static func normalized_channel(values: PackedByteArray, count: int) -> PackedByteArray:
	var normalized := PackedByteArray()
	normalized.resize(maxi(0, count))
	normalized.fill(0)
	for index in mini(values.size(), normalized.size()):
		normalized[index] = values[index]
	return normalized


static func normalized_int_channel(values: PackedInt32Array, count: int) -> PackedInt32Array:
	var normalized := PackedInt32Array()
	normalized.resize(maxi(0, count))
	normalized.fill(0)
	for index in mini(values.size(), normalized.size()):
		normalized[index] = values[index]
	return normalized


static func surface_fill_selection(
	resource: EmberVoxelModelResource,
	seed: Vector3i,
	manual_raise := 0,
	region_blocks := Rect2i(),
	heightfield := PackedInt32Array(),
	maximum_count := MAX_SURFACE_FILL_COLUMNS,
	edge_inset := 0,
) -> Dictionary:
	## Priority-flood finds the lowest escape height around the clicked basin.
	## It works on the derived heightfield only: no terrain voxel is rewritten.
	if resource == null:
		return _empty_surface_fill_result("missing_resource")
	var size := resource.grid_size()
	if not contains(seed, size):
		return _empty_surface_fill_result("invalid_seed")
	if heightfield.size() != size.x * size.z:
		heightfield = column_heights(resource.voxels, size, resource.palette.size() - 1)
	var seed_column := seed.x + seed.z * size.x
	if int(heightfield[seed_column]) != seed.y:
		return _empty_surface_fill_result("seed_is_not_surface")
	var bounds := _surface_fill_search_bounds(
		resource, Vector2i(seed.x, seed.z), region_blocks
	)
	if bounds.size.x < 3 or bounds.size.y < 3:
		return _empty_surface_fill_result("search_area_too_small")
	var seed_surface := seed.y + 1
	var level := clampi(seed_surface + maxi(0, manual_raise), 0, size.y)
	var spill_level := level
	if manual_raise <= 0:
		spill_level = _priority_flood_escape_level(heightfield, size, bounds, seed_column)
		level = maxi(seed_surface + 1, spill_level - clampi(edge_inset, 0, 2))
	if spill_level <= seed_surface:
		var open_result := _empty_surface_fill_result("open_basin")
		open_result["open"] = true
		return open_result
	var selection := _connected_columns_below_level(
		heightfield,
		size,
		bounds,
		Vector2i(seed.x, seed.z),
		level,
		maximum_count,
	)
	selection["level"] = level
	selection["spill_level"] = spill_level
	return selection


static func connected_surface_fill_columns(
	resource: EmberVoxelModelResource,
	seed: Vector2i,
	region_blocks := Rect2i(),
	maximum_count := MAX_SURFACE_FILL_COLUMNS,
) -> Dictionary:
	if resource == null:
		return {"columns": PackedInt32Array(), "truncated": false}
	var size := resource.grid_size()
	if seed.x < 0 or seed.y < 0 or seed.x >= size.x or seed.y >= size.z:
		return {"columns": PackedInt32Array(), "truncated": false}
	var count := size.x * size.z
	var levels := normalized_int_channel(resource.surface_fill_levels, count)
	var materials := normalized_channel(resource.surface_fill_materials, count)
	var seed_index := seed.x + seed.y * size.x
	var seed_level := int(levels[seed_index])
	var seed_material := int(materials[seed_index])
	if seed_level <= 0 or seed_material == SURFACE_FILL_NONE:
		return {"columns": PackedInt32Array(), "truncated": false}
	var bounds := _surface_fill_scope_bounds(resource, region_blocks)
	var visited := PackedByteArray()
	visited.resize(count)
	visited.fill(0)
	visited[seed_index] = 1
	var queue: Array[Vector2i] = [seed]
	var cursor := 0
	var columns := PackedInt32Array()
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		var column_index := cell.x + cell.y * size.x
		if (
			int(levels[column_index]) != seed_level
			or int(materials[column_index]) != seed_material
		):
			continue
		columns.append(column_index)
		if columns.size() > maxi(1, maximum_count):
			return {"columns": PackedInt32Array(), "truncated": true}
		for raw_offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var offset: Vector2i = raw_offset
			var neighbor: Vector2i = cell + offset
			if not bounds.has_point(neighbor):
				continue
			var neighbor_index: int = neighbor.x + neighbor.y * size.x
			if visited[neighbor_index] == 0:
				visited[neighbor_index] = 1
				queue.append(neighbor)
	return {"columns": columns, "truncated": false, "level": seed_level}


static func surface_fill_replacement_columns(
	resource: EmberVoxelModelResource,
	seed: Vector2i,
	next_columns: PackedInt32Array,
	target_material: int,
	region_blocks := Rect2i(),
	maximum_count := MAX_SURFACE_FILL_COLUMNS,
) -> Dictionary:
	## Re-authoring a level fill replaces its complete connected liquid family.
	## This removes shallower fringe columns and also repairs adjacent rings left
	## by older partial updates. A dry column remains a hard boundary between
	## intentionally separate ponds.
	if resource == null:
		return {
			"columns": PackedInt32Array(),
			"previous_columns": PackedInt32Array(),
			"truncated": false,
			"escaped_scope": false,
		}
	var size := resource.grid_size()
	if seed.x < 0 or seed.y < 0 or seed.x >= size.x or seed.y >= size.z:
		return {
			"columns": PackedInt32Array(),
			"previous_columns": PackedInt32Array(),
			"truncated": false,
			"escaped_scope": false,
		}
	var count := size.x * size.z
	var levels := normalized_int_channel(resource.surface_fill_levels, count)
	var materials := normalized_channel(resource.surface_fill_materials, count)
	var seed_index := seed.x + seed.y * size.x
	var previous_material := int(materials[seed_index])
	if int(levels[seed_index]) <= 0 or previous_material == SURFACE_FILL_NONE:
		previous_material = target_material
	var bounds := _surface_fill_scope_bounds(resource, region_blocks)
	var queued := PackedByteArray()
	queued.resize(count)
	queued.fill(0)
	var queue: Array[Vector2i] = []
	var source_indices := PackedInt32Array([seed_index])
	for raw_index in next_columns:
		var index := int(raw_index)
		if index < 0 or index >= count:
			continue
		source_indices.append(index)
		var cell := Vector2i(index % size.x, floori(float(index) / float(size.x)))
		for raw_offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var offset: Vector2i = raw_offset
			var neighbor: Vector2i = cell + offset
			if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < size.x and neighbor.y < size.z:
				source_indices.append(neighbor.x + neighbor.y * size.x)
	for raw_source in source_indices:
		var source := int(raw_source)
		if (
			queued[source] != 0
			or int(levels[source]) <= 0
			or int(materials[source]) != previous_material
		):
			continue
		var source_cell := Vector2i(
			source % size.x, floori(float(source) / float(size.x))
		)
		if not bounds.has_point(source_cell):
			continue
		queued[source] = 1
		queue.append(source_cell)
	var previous := PackedInt32Array()
	var cursor := 0
	var escaped_scope := false
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		var column_index := cell.x + cell.y * size.x
		previous.append(column_index)
		if previous.size() > maxi(1, maximum_count):
			return {
				"columns": PackedInt32Array(),
				"previous_columns": PackedInt32Array(),
				"truncated": true,
				"escaped_scope": false,
			}
		for raw_offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var offset: Vector2i = raw_offset
			var neighbor: Vector2i = cell + offset
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.z:
				continue
			var neighbor_index: int = neighbor.x + neighbor.y * size.x
			if (
				int(levels[neighbor_index]) <= 0
				or int(materials[neighbor_index]) != previous_material
			):
				continue
			if not bounds.has_point(neighbor):
				escaped_scope = true
				continue
			if queued[neighbor_index] == 0:
				queued[neighbor_index] = 1
				queue.append(neighbor)
	var affected_mask := PackedByteArray()
	affected_mask.resize(count)
	affected_mask.fill(0)
	var affected := PackedInt32Array()
	for source in [next_columns, previous]:
		for raw_index in source:
			var index := int(raw_index)
			if index < 0 or index >= count or affected_mask[index] != 0:
				continue
			affected_mask[index] = 1
			affected.append(index)
			if affected.size() > maxi(1, maximum_count):
				return {
					"columns": PackedInt32Array(),
					"previous_columns": PackedInt32Array(),
					"truncated": true,
					"escaped_scope": false,
				}
	return {
		"columns": affected,
		"previous_columns": previous,
		"truncated": false,
		"escaped_scope": escaped_scope,
	}


static func _surface_fill_search_bounds(
	resource: EmberVoxelModelResource,
	seed: Vector2i,
	region_blocks: Rect2i,
) -> Rect2i:
	var scope := _surface_fill_scope_bounds(resource, region_blocks)
	var minimum := Vector2i(
		maxi(scope.position.x, seed.x - AUTO_FILL_SEARCH_RADIUS),
		maxi(scope.position.y, seed.y - AUTO_FILL_SEARCH_RADIUS),
	)
	var maximum := Vector2i(
		mini(scope.end.x, seed.x + AUTO_FILL_SEARCH_RADIUS + 1),
		mini(scope.end.y, seed.y + AUTO_FILL_SEARCH_RADIUS + 1),
	)
	return Rect2i(minimum, maximum - minimum)


static func _surface_fill_scope_bounds(
	resource: EmberVoxelModelResource,
	region_blocks: Rect2i,
) -> Rect2i:
	var size := resource.grid_size()
	if not region_blocks.has_area():
		return Rect2i(Vector2i.ZERO, Vector2i(size.x, size.z))
	var density := resource.normalized_density()
	var minimum := Vector2i(
		clampi(region_blocks.position.x * density, 0, size.x),
		clampi(region_blocks.position.y * density, 0, size.z),
	)
	var maximum := Vector2i(
		clampi(region_blocks.end.x * density, minimum.x, size.x),
		clampi(region_blocks.end.y * density, minimum.y, size.z),
	)
	return Rect2i(minimum, maximum - minimum)


static func _priority_flood_escape_level(
	heightfield: PackedInt32Array,
	size: Vector3i,
	bounds: Rect2i,
	seed_column: int,
) -> int:
	var local_count := bounds.size.x * bounds.size.y
	var escape := PackedInt32Array()
	escape.resize(local_count)
	escape.fill(-1)
	var buckets: Array = []
	for unused in range(size.y + 1):
		buckets.append([])
	for local_z in bounds.size.y:
		for local_x in bounds.size.x:
			if (
				local_x != 0 and local_z != 0
				and local_x != bounds.size.x - 1 and local_z != bounds.size.y - 1
			):
				continue
			var global_x := bounds.position.x + local_x
			var global_z := bounds.position.y + local_z
			var global_index := global_x + global_z * size.x
			var local_index := local_x + local_z * bounds.size.x
			var cost := clampi(int(heightfield[global_index]) + 1, 0, size.y)
			if escape[local_index] < 0 or cost < escape[local_index]:
				escape[local_index] = cost
				(buckets[cost] as Array).append(local_index)
	var seed_x := seed_column % size.x
	var seed_z := floori(float(seed_column) / float(size.x))
	var seed_local := (
		seed_x - bounds.position.x
		+ (seed_z - bounds.position.y) * bounds.size.x
	)
	for cost in range(size.y + 1):
		var cursor := 0
		var bucket: Array = buckets[cost]
		while cursor < bucket.size():
			var local_index := int(bucket[cursor])
			cursor += 1
			if int(escape[local_index]) != cost:
				continue
			if local_index == seed_local:
				return cost
			var local_x := local_index % bounds.size.x
			var local_z := floori(float(local_index) / float(bounds.size.x))
			for raw_offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
				var offset: Vector2i = raw_offset
				var neighbor: Vector2i = Vector2i(local_x, local_z) + offset
				if (
					neighbor.x < 0 or neighbor.y < 0
					or neighbor.x >= bounds.size.x or neighbor.y >= bounds.size.y
				):
					continue
				var neighbor_local: int = neighbor.x + neighbor.y * bounds.size.x
				var neighbor_global: int = (
					bounds.position.x + neighbor.x
					+ (bounds.position.y + neighbor.y) * size.x
				)
				var next_cost := maxi(
					cost, clampi(int(heightfield[neighbor_global]) + 1, 0, size.y)
				)
				if escape[neighbor_local] < 0 or next_cost < escape[neighbor_local]:
					escape[neighbor_local] = next_cost
					(buckets[next_cost] as Array).append(neighbor_local)
	return -1


static func _connected_columns_below_level(
	heightfield: PackedInt32Array,
	size: Vector3i,
	bounds: Rect2i,
	seed: Vector2i,
	level: int,
	maximum_count: int,
) -> Dictionary:
	var count := size.x * size.z
	var visited := PackedByteArray()
	visited.resize(count)
	visited.fill(0)
	var seed_index := seed.x + seed.y * size.x
	visited[seed_index] = 1
	var queue: Array[Vector2i] = [seed]
	var cursor := 0
	var columns := PackedInt32Array()
	var touches_boundary := false
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		var column_index := cell.x + cell.y * size.x
		if int(heightfield[column_index]) + 1 >= level:
			continue
		if (
			cell.x == bounds.position.x or cell.y == bounds.position.y
			or cell.x == bounds.end.x - 1 or cell.y == bounds.end.y - 1
		):
			touches_boundary = true
		columns.append(column_index)
		if columns.size() > maxi(1, maximum_count):
			return {
				"columns": PackedInt32Array(), "truncated": true,
				"open": false, "reason": "too_large",
			}
		for raw_offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var offset: Vector2i = raw_offset
			var neighbor: Vector2i = cell + offset
			if not bounds.has_point(neighbor):
				continue
			var neighbor_index: int = neighbor.x + neighbor.y * size.x
			if visited[neighbor_index] == 0:
				visited[neighbor_index] = 1
				queue.append(neighbor)
	if touches_boundary:
		return {
			"columns": PackedInt32Array(), "truncated": false,
			"open": true, "reason": "open_basin",
		}
	return {
		"columns": columns, "truncated": false,
		"open": false, "reason": "",
	}


static func _empty_surface_fill_result(reason: String) -> Dictionary:
	return {
		"columns": PackedInt32Array(),
		"level": -1,
		"truncated": false,
		"open": false,
		"reason": reason,
	}


static func connected_surface_material_indices(
	resource: EmberVoxelModelResource,
	seed: Vector3i,
	color_tolerance: float,
	region_blocks := Rect2i(),
	heightfield := PackedInt32Array(),
	maximum_count := MAX_CONNECTED_MATERIAL_VOXELS,
) -> Dictionary:
	## Surface water is an overlay above an authored floor, not transparent soil.
	## Magic-wand therefore walks one connected X/Z top plane of similar color.
	if resource == null:
		return {"indices": PackedInt32Array(), "truncated": false}
	var size := resource.grid_size()
	if not contains(seed, size) or resource.voxels.is_empty():
		return {"indices": PackedInt32Array(), "truncated": false}
	var seed_index := index_of(seed, size)
	var seed_palette := int(resource.voxels[seed_index])
	if seed_palette <= 0 or seed_palette >= resource.palette.size():
		return {"indices": PackedInt32Array(), "truncated": false}
	if heightfield.size() != size.x * size.z:
		heightfield = column_heights(resource.voxels, size, resource.palette.size() - 1)
	if int(heightfield[seed.x + seed.z * size.x]) != seed.y:
		return {"indices": PackedInt32Array(), "truncated": false}
	var seed_color: Color = resource.palette[seed_palette]
	var density := resource.normalized_density()
	var minimum := Vector2i.ZERO
	var maximum := Vector2i(size.x, size.z)
	if region_blocks.has_area():
		minimum = Vector2i(
			clampi(region_blocks.position.x * density, 0, size.x),
			clampi(region_blocks.position.y * density, 0, size.z),
		)
		maximum = Vector2i(
			clampi(region_blocks.end.x * density, minimum.x, size.x),
			clampi(region_blocks.end.y * density, minimum.y, size.z),
		)
	if seed.x < minimum.x or seed.z < minimum.y or seed.x >= maximum.x or seed.z >= maximum.y:
		return {"indices": PackedInt32Array(), "truncated": false}
	var visited := PackedByteArray()
	visited.resize(size.x * size.z)
	visited.fill(0)
	visited[seed.x + seed.z * size.x] = 1
	var queue: Array[Vector2i] = [Vector2i(seed.x, seed.z)]
	var cursor := 0
	var selected := PackedInt32Array()
	var tolerance := clampf(color_tolerance, 0.0, 1.0)
	var limit := maxi(1, maximum_count)
	var neighbor_offsets: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN,
	]
	while cursor < queue.size():
		var column: Vector2i = queue[cursor]
		cursor += 1
		var voxel_index := index_of(Vector3i(column.x, seed.y, column.y), size)
		var palette_index := int(resource.voxels[voxel_index])
		if palette_index <= 0 or palette_index >= resource.palette.size():
			continue
		if _normalized_rgb_distance(seed_color, resource.palette[palette_index]) > tolerance:
			continue
		selected.append(voxel_index)
		if selected.size() > limit:
			return {"indices": PackedInt32Array(), "truncated": true}
		for offset in neighbor_offsets:
			var neighbor := column + offset
			if (
				neighbor.x < minimum.x or neighbor.y < minimum.y
				or neighbor.x >= maximum.x or neighbor.y >= maximum.y
			):
				continue
			var neighbor_index := neighbor.x + neighbor.y * size.x
			if visited[neighbor_index] == 0 and int(heightfield[neighbor_index]) == seed.y:
				visited[neighbor_index] = 1
				queue.append(neighbor)
	return {"indices": selected, "truncated": false}


static func _normalized_rgb_distance(left: Color, right: Color) -> float:
	var red := left.r - right.r
	var green := left.g - right.g
	var blue := left.b - right.b
	return sqrt(red * red + green * green + blue * blue) / sqrt(3.0)


static func level_segment_changes(
	resource: EmberVoxelModelResource,
	from: Vector3i,
	to: Vector3i,
	target_top_y: int,
	palette_index: int,
	brush_radius := 4,
	coarse := false,
) -> Dictionary:
	var changes := {}
	if resource == null:
		return changes
	var size := resource.grid_size()
	if not contains(from, size) or not contains(to, size):
		return changes
	var radius := clampi(brush_radius, 1, 32)
	var step := 2 if coarse else 1
	var target_top := clampi(target_top_y, 0, size.y - 1)
	if coarse:
		# A coarse terrace ends on a complete 2-voxel layer, matching the
		# existing 2x2x2 Add/Remove authoring contract.
		target_top = mini(size.y - 1, floori(float(target_top) / 2.0) * 2 + 1)
	var palette_value := clampi(palette_index, 1, resource.palette.size() - 1)
	var extent := radius - 1
	var start_2d := Vector2(from.x, from.z)
	var end_2d := Vector2(to.x, to.z)
	var minimum_x := maxi(0, mini(from.x, to.x) - extent)
	var maximum_x := mini(size.x - 1, maxi(from.x, to.x) + extent)
	var minimum_z := maxi(0, mini(from.z, to.z) - extent)
	var maximum_z := mini(size.z - 1, maxi(from.z, to.z) + extent)
	var first_x := floori(float(minimum_x) / float(step)) * step
	var first_z := floori(float(minimum_z) / float(step)) * step
	for base_z in range(first_z, maximum_z + 1, step):
		for base_x in range(first_x, maximum_x + 1, step):
			if _distance_to_segment_2d(
				Vector2(base_x, base_z), start_2d, end_2d
			) > float(radius) - 0.25:
				continue
			for oz in step:
				for ox in step:
					var x := base_x + ox
					var z := base_z + oz
					if x < 0 or z < 0 or x >= size.x or z >= size.z:
						continue
					var current_top := _top_filled_y(resource.voxels, size, x, z)
					if current_top < target_top:
						for y in range(current_top + 1, target_top + 1):
							var index := index_of(Vector3i(x, y, z), size)
							var before := int(resource.voxels[index])
							if before == 0:
								changes[index] = {"before": before, "after": palette_value}
					elif current_top > target_top:
						for y in range(target_top + 1, current_top + 1):
							var index := index_of(Vector3i(x, y, z), size)
							var before := int(resource.voxels[index])
							if before != 0:
								changes[index] = {"before": before, "after": 0}
	return changes


static func smooth_segment_changes(
	resource: EmberVoxelModelResource,
	baseline_values: PackedByteArray,
	from: Vector3i,
	to: Vector3i,
	palette_index: int,
	brush_radius := 4,
	strength := 1,
	coarse := false,
	baseline_top_cache: Dictionary = {},
	applied_column_cache: Dictionary = {},
	baseline_heightfield := PackedInt32Array(),
) -> Dictionary:
	var changes := {}
	if resource == null:
		return changes
	var size := resource.grid_size()
	if (
		baseline_values.size() != resource.voxels.size()
		or not contains(from, size)
		or not contains(to, size)
	):
		return changes
	var radius := clampi(brush_radius, 1, 32)
	var step := 2 if coarse else 1
	var effective_strength := clampi(strength, 1, size.y)
	if coarse:
		effective_strength = maxi(2, ceili(float(effective_strength) / 2.0) * 2)
	var palette_value := clampi(palette_index, 1, resource.palette.size() - 1)
	var has_heightfield := baseline_heightfield.size() == size.x * size.z
	var extent := radius - 1
	var start_2d := Vector2(from.x, from.z)
	var end_2d := Vector2(to.x, to.z)
	var minimum_x := maxi(0, mini(from.x, to.x) - extent)
	var maximum_x := mini(size.x - 1, maxi(from.x, to.x) + extent)
	var minimum_z := maxi(0, mini(from.z, to.z) - extent)
	var maximum_z := mini(size.z - 1, maxi(from.z, to.z) + extent)
	var first_x := floori(float(minimum_x) / float(step)) * step
	var first_z := floori(float(minimum_z) / float(step)) * step
	for base_z in range(first_z, maximum_z + 1, step):
		for base_x in range(first_x, maximum_x + 1, step):
			if _distance_to_segment_2d(
				Vector2(base_x, base_z), start_2d, end_2d
			) > float(radius) - 0.25:
				continue
			var base_column_index := base_x + base_z * size.x
			if step == 1 and applied_column_cache.has(base_column_index):
				continue
			var average_top := _neighbor_average_top(
				baseline_values,
				size,
				base_x,
				base_z,
				baseline_top_cache,
				baseline_heightfield,
			)
			if average_top < 0:
				continue
			if coarse:
				average_top = mini(size.y - 1, floori(float(average_top) / 2.0) * 2 + 1)
			for oz in step:
				for ox in step:
					var x := base_x + ox
					var z := base_z + oz
					if x < 0 or z < 0 or x >= size.x or z >= size.z:
						continue
					var column_index := x + z * size.x
					if applied_column_cache.has(column_index):
						continue
					applied_column_cache[column_index] = true
					var baseline_top := (
						int(baseline_heightfield[column_index])
						if has_heightfield
						else _cached_column_top(
							baseline_values, size, x, z, column_index, baseline_top_cache
						)
					)
					# Empty authored holes are preserved. Smooth reshapes an existing
					# surface; closing/filling a void remains an explicit Add/Level action.
					if baseline_top < 0:
						continue
					var target_top := clampi(
						average_top,
						baseline_top - effective_strength,
						baseline_top + effective_strength,
					)
					target_top = clampi(target_top, 0, size.y - 1)
					if coarse:
						target_top = mini(size.y - 1, floori(float(target_top) / 2.0) * 2 + 1)
					# Each column is admitted exactly once through applied_column_cache,
					# so its live top still equals the pointer-down baseline here.
					var current_top := baseline_top
					if current_top < target_top:
						for y in range(current_top + 1, target_top + 1):
							var index := index_of(Vector3i(x, y, z), size)
							var before := int(resource.voxels[index])
							if before == 0:
								changes[index] = {"before": before, "after": palette_value}
					elif current_top > target_top:
						for y in range(target_top + 1, current_top + 1):
							var index := index_of(Vector3i(x, y, z), size)
							var before := int(resource.voxels[index])
							if before != 0:
								changes[index] = {"before": before, "after": 0}
	return changes


static func ramp_segment_changes(
	resource: EmberVoxelModelResource,
	baseline_values: PackedByteArray,
	from: Vector3i,
	to: Vector3i,
	palette_index: int,
	brush_radius := 4,
	coarse := false,
	baseline_heightfield := PackedInt32Array(),
) -> Dictionary:
	var changes := {}
	if resource == null:
		return changes
	var size := resource.grid_size()
	if (
		baseline_values.size() != resource.voxels.size()
		or not contains(from, size)
		or not contains(to, size)
	):
		return changes
	var heightfield := baseline_heightfield
	if heightfield.size() != size.x * size.z:
		heightfield = column_heights(baseline_values, size, resource.palette.size() - 1)
	var from_top := int(heightfield[from.x + from.z * size.x])
	var to_top := int(heightfield[to.x + to.z * size.x])
	if from_top < 0 or to_top < 0:
		return changes
	var radius := clampi(brush_radius, 1, 32)
	var step := 2 if coarse else 1
	var palette_value := clampi(palette_index, 1, resource.palette.size() - 1)
	var extent := radius - 1
	var start_2d := Vector2(from.x, from.z)
	var end_2d := Vector2(to.x, to.z)
	var minimum_x := maxi(0, mini(from.x, to.x) - extent)
	var maximum_x := mini(size.x - 1, maxi(from.x, to.x) + extent)
	var minimum_z := maxi(0, mini(from.z, to.z) - extent)
	var maximum_z := mini(size.z - 1, maxi(from.z, to.z) + extent)
	var first_x := floori(float(minimum_x) / float(step)) * step
	var first_z := floori(float(minimum_z) / float(step)) * step
	for base_z in range(first_z, maximum_z + 1, step):
		for base_x in range(first_x, maximum_x + 1, step):
			var sample := Vector2(base_x, base_z)
			if _distance_to_segment_2d(sample, start_2d, end_2d) > float(radius) - 0.25:
				continue
			var progress := _segment_progress_2d(sample, start_2d, end_2d)
			var target_top := clampi(
				roundi(lerpf(float(from_top), float(to_top), progress)),
				0,
				size.y - 1,
			)
			if coarse:
				target_top = mini(size.y - 1, floori(float(target_top) / 2.0) * 2 + 1)
			for oz in step:
				for ox in step:
					var x := base_x + ox
					var z := base_z + oz
					if x < 0 or z < 0 or x >= size.x or z >= size.z:
						continue
					var current_top := int(heightfield[x + z * size.x])
					if current_top < target_top:
						for y in range(current_top + 1, target_top + 1):
							var index := index_of(Vector3i(x, y, z), size)
							var before := int(baseline_values[index])
							if before == 0:
								changes[index] = {"before": before, "after": palette_value}
					elif current_top > target_top:
						for y in range(target_top + 1, current_top + 1):
							var index := index_of(Vector3i(x, y, z), size)
							var before := int(baseline_values[index])
							if before != 0:
								changes[index] = {"before": before, "after": 0}
	return changes


static func _neighbor_average_top(
	values: PackedByteArray,
	size: Vector3i,
	x: int,
	z: int,
	cache: Dictionary,
	heightfield := PackedInt32Array(),
) -> int:
	var total := 0
	var count := 0
	var has_heightfield := heightfield.size() == size.x * size.z
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var neighbor_x := x + dx
			var neighbor_z := z + dz
			if neighbor_x < 0 or neighbor_z < 0 or neighbor_x >= size.x or neighbor_z >= size.z:
				continue
			var column_index := neighbor_x + neighbor_z * size.x
			var top := (
				int(heightfield[column_index])
				if has_heightfield
				else _cached_column_top(
					values, size, neighbor_x, neighbor_z, column_index, cache
				)
			)
			if top < 0:
				continue
			total += top
			count += 1
	return -1 if count == 0 else roundi(float(total) / float(count))


static func relief_changes(
	resource: EmberVoxelModelResource,
	baseline_values: PackedByteArray,
	center: Vector3i,
	tool: int,
	palette_index: int,
	brush_radius := 4,
	height_limit := 4,
	coarse := false,
	baseline_top_cache: Dictionary = {},
	previous_height := 0,
	applied_amount_cache: Dictionary = {},
) -> Dictionary:
	return relief_segment_changes(
		resource,
		baseline_values,
		center,
		center,
		tool,
		palette_index,
		brush_radius,
		height_limit,
		coarse,
		baseline_top_cache,
		previous_height,
		applied_amount_cache,
	)


static func relief_segment_changes(
	resource: EmberVoxelModelResource,
	baseline_values: PackedByteArray,
	from: Vector3i,
	to: Vector3i,
	tool: int,
	palette_index: int,
	brush_radius := 4,
	height_limit := 4,
	coarse := false,
	baseline_top_cache: Dictionary = {},
	previous_height := 0,
	applied_amount_cache: Dictionary = {},
) -> Dictionary:
	var changes := {}
	if resource == null or tool not in [TOOL_RAISE, TOOL_LOWER]:
		return changes
	var size := resource.grid_size()
	if (
		baseline_values.size() != resource.voxels.size()
		or not contains(from, size)
		or not contains(to, size)
	):
		return changes
	var radius := clampi(brush_radius, 1, 32)
	var maximum_height := clampi(height_limit, 1, size.y)
	var previous_maximum_height := clampi(previous_height, 0, maximum_height)
	var palette_value := clampi(palette_index, 1, resource.palette.size() - 1)
	var amount_changes := _relief_segment_amount_changes(
		size,
		from,
		to,
		radius,
		maximum_height,
		previous_maximum_height,
		coarse,
		applied_amount_cache,
	)
	for raw_column_index in amount_changes:
		var column_index := int(raw_column_index)
		var x := column_index % size.x
		var z := floori(float(column_index) / float(size.x))
		var amounts: Vector2i = amount_changes[raw_column_index]
		var applied_amount := amounts.x
		var amount := amounts.y
		var baseline_top: int
		if baseline_top_cache.has(column_index):
			baseline_top = int(baseline_top_cache[column_index])
		else:
			baseline_top = _top_filled_y(baseline_values, size, x, z)
			baseline_top_cache[column_index] = baseline_top
		if tool == TOOL_RAISE:
			var target_top := mini(size.y - 1, baseline_top + amount)
			var previous_target_top := mini(size.y - 1, baseline_top + applied_amount)
			for y in range(previous_target_top + 1, target_top + 1):
				var index := index_of(Vector3i(x, y, z), size)
				var before := int(resource.voxels[index])
				if before == 0:
					changes[index] = {"before": before, "after": palette_value}
		else:
			var target_top := maxi(-1, baseline_top - amount)
			var previous_target_top := maxi(-1, baseline_top - applied_amount)
			for y in range(target_top + 1, previous_target_top + 1):
				var index := index_of(Vector3i(x, y, z), size)
				var before := int(resource.voxels[index])
				if before != 0:
					changes[index] = {"before": before, "after": 0}
	return changes


static func shell_relief_segment_changes(
	resource: EmberVoxelModelResource,
	baseline_values: PackedByteArray,
	from: Vector3i,
	to: Vector3i,
	palette_index: int,
	brush_radius := 4,
	height_limit := 4,
	coarse := false,
	baseline_top_cache: Dictionary = {},
	previous_height := 0,
	applied_amount_cache: Dictionary = {},
	foundation_top_cache: Dictionary = {},
) -> Dictionary:
	return _shell_relief_segment_changes(
		resource,
		baseline_values,
		from,
		to,
		palette_index,
		brush_radius,
		height_limit,
		coarse,
		baseline_top_cache,
		previous_height,
		applied_amount_cache,
		foundation_top_cache,
		1,
	)


static func shell_lower_segment_changes(
	resource: EmberVoxelModelResource,
	baseline_values: PackedByteArray,
	from: Vector3i,
	to: Vector3i,
	palette_index: int,
	brush_radius := 4,
	height_limit := 4,
	coarse := false,
	baseline_top_cache: Dictionary = {},
	previous_height := 0,
	applied_amount_cache: Dictionary = {},
	foundation_top_cache: Dictionary = {},
) -> Dictionary:
	return _shell_relief_segment_changes(
		resource,
		baseline_values,
		from,
		to,
		palette_index,
		brush_radius,
		height_limit,
		coarse,
		baseline_top_cache,
		previous_height,
		applied_amount_cache,
		foundation_top_cache,
		-1,
	)


static func _shell_relief_segment_changes(
	resource: EmberVoxelModelResource,
	baseline_values: PackedByteArray,
	from: Vector3i,
	to: Vector3i,
	palette_index: int,
	brush_radius: int,
	height_limit: int,
	coarse: bool,
	baseline_top_cache: Dictionary,
	previous_height: int,
	applied_amount_cache: Dictionary,
	foundation_top_cache: Dictionary,
	direction: int,
) -> Dictionary:
	var changes := {}
	if resource == null or direction not in [-1, 1]:
		return changes
	var size := resource.grid_size()
	if (
		baseline_values.size() != resource.voxels.size()
		or not contains(from, size)
		or not contains(to, size)
	):
		return changes
	var maximum_height := clampi(height_limit, 1, size.y)
	var amount_changes := _relief_segment_amount_changes(
		size,
		from,
		to,
		clampi(brush_radius, 1, 32),
		maximum_height,
		clampi(previous_height, 0, maximum_height),
		coarse,
		applied_amount_cache,
	)
	if amount_changes.is_empty():
		return changes
	var recompute_columns := {}
	var neighbor_offsets := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]
	for raw_column_index in amount_changes:
		var column_index := int(raw_column_index)
		recompute_columns[column_index] = true
		var x := column_index % size.x
		var z := floori(float(column_index) / float(size.x))
		for raw_offset in neighbor_offsets:
			var offset: Vector2i = raw_offset
			var neighbor_x: int = x + offset.x
			var neighbor_z: int = z + offset.y
			if neighbor_x >= 0 and neighbor_z >= 0 and neighbor_x < size.x and neighbor_z < size.z:
				recompute_columns[neighbor_x + neighbor_z * size.x] = true
	var palette_value := clampi(palette_index, 1, resource.palette.size() - 1)
	for raw_column_index in recompute_columns:
		var column_index := int(raw_column_index)
		var x := column_index % size.x
		var z := floori(float(column_index) / float(size.x))
		var amount := int(applied_amount_cache.get(column_index, 0))
		# Raise owns the higher affected column, so untouched neighbors do not
		# need a rewrite. A depression exposes the outside higher column and must
		# include its one-cell ring when the source is already a hollow shell.
		if amount <= 0 and direction > 0:
			continue
		var baseline_top := _cached_column_top(
			baseline_values, size, x, z, column_index, baseline_top_cache
		)
		var foundation_top: int
		if foundation_top_cache.has(column_index):
			foundation_top = int(foundation_top_cache[column_index])
		else:
			foundation_top = _contiguous_filled_top(baseline_values, size, x, z)
			foundation_top_cache[column_index] = foundation_top
		var target_top := (
			mini(size.y - 1, baseline_top + amount)
			if direction > 0
			else maxi(-1, baseline_top - amount)
		)
		# On a solid column lowering simply removes its upper mass. On a hollow
		# column the old contiguous foundation remains stable and the visible
		# top/walls move inside the interval above it.
		if direction < 0:
			foundation_top = mini(foundation_top, target_top)
		var wall_bottom := target_top
		for raw_offset in neighbor_offsets:
			var offset: Vector2i = raw_offset
			var neighbor_x: int = x + offset.x
			var neighbor_z: int = z + offset.y
			if neighbor_x < 0 or neighbor_z < 0 or neighbor_x >= size.x or neighbor_z >= size.z:
				wall_bottom = mini(wall_bottom, foundation_top + 1)
				continue
			var neighbor_index: int = neighbor_x + neighbor_z * size.x
			var neighbor_baseline_top := _cached_column_top(
				baseline_values,
				size,
				neighbor_x,
				neighbor_z,
				neighbor_index,
				baseline_top_cache,
			)
			var neighbor_amount := int(applied_amount_cache.get(neighbor_index, 0))
			var neighbor_target := (
				mini(size.y - 1, neighbor_baseline_top + neighbor_amount)
				if direction > 0
				else maxi(-1, neighbor_baseline_top - neighbor_amount)
			)
			wall_bottom = mini(wall_bottom, neighbor_target + 1)
		wall_bottom = maxi(foundation_top + 1, wall_bottom)
		# The shell only owns the interval between its stable foundation and
		# current target. Scanning the unused remainder of the 24-voxel canvas
		# made a sparse brush slower than the solid variant.
		var owned_top := target_top if direction > 0 else maxi(target_top, baseline_top)
		for y in range(foundation_top + 1, owned_top + 1):
			var index := index_of(Vector3i(x, y, z), size)
			var before := int(resource.voxels[index])
			var after := palette_value if y >= wall_bottom and y <= target_top else 0
			if before != after:
				changes[index] = {"before": before, "after": after}
	return changes


static func _relief_segment_amount_changes(
	size: Vector3i,
	from: Vector3i,
	to: Vector3i,
	radius: int,
	maximum_height: int,
	previous_maximum_height: int,
	coarse: bool,
	applied_amount_cache: Dictionary,
) -> Dictionary:
	var amount_changes := {}
	var extent := radius - 1
	var step := 2 if coarse else 1
	var start_2d := Vector2(from.x, from.z)
	var end_2d := Vector2(to.x, to.z)
	var minimum_x := maxi(0, mini(from.x, to.x) - extent)
	var maximum_x := mini(size.x - 1, maxi(from.x, to.x) + extent)
	var minimum_z := maxi(0, mini(from.z, to.z) - extent)
	var maximum_z := mini(size.z - 1, maxi(from.z, to.z) + extent)
	var first_x := floori(float(minimum_x) / float(step)) * step
	var first_z := floori(float(minimum_z) / float(step)) * step
	for base_z in range(first_z, maximum_z + 1, step):
		for base_x in range(first_x, maximum_x + 1, step):
			var distance := _distance_to_segment_2d(
				Vector2(base_x, base_z), start_2d, end_2d
			)
			if distance > float(radius) - 0.25:
				continue
			var normalized := clampf(distance / float(radius), 0.0, 1.0)
			var falloff := 1.0 - smoothstep(0.0, 1.0, normalized)
			var amount := clampi(ceili(float(maximum_height) * falloff), 1, maximum_height)
			var previous_amount := 0
			if previous_maximum_height > 0:
				previous_amount = clampi(
					ceili(float(previous_maximum_height) * falloff),
					1,
					previous_maximum_height,
				)
			for oz in step:
				for ox in step:
					var x := base_x + ox
					var z := base_z + oz
					if x < 0 or z < 0 or x >= size.x or z >= size.z:
						continue
					var column_index := x + z * size.x
					var applied_amount := maxi(
						previous_amount, int(applied_amount_cache.get(column_index, 0))
					)
					if amount <= applied_amount:
						continue
					applied_amount_cache[column_index] = amount
					amount_changes[column_index] = Vector2i(applied_amount, amount)
	return amount_changes


static func _cached_column_top(
	values: PackedByteArray,
	size: Vector3i,
	x: int,
	z: int,
	column_index: int,
	cache: Dictionary,
) -> int:
	if cache.has(column_index):
		return int(cache[column_index])
	var top := _top_filled_y(values, size, x, z)
	cache[column_index] = top
	return top


static func _contiguous_filled_top(
	values: PackedByteArray,
	size: Vector3i,
	x: int,
	z: int,
) -> int:
	var top := -1
	for y in size.y:
		if values[index_of(Vector3i(x, y, z), size)] == 0:
			break
		top = y
	return top


static func _distance_to_segment_2d(point: Vector2, from: Vector2, to: Vector2) -> float:
	var delta := to - from
	var length_squared := delta.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(from)
	var along := clampf((point - from).dot(delta) / length_squared, 0.0, 1.0)
	return point.distance_to(from + delta * along)


static func _segment_progress_2d(point: Vector2, from: Vector2, to: Vector2) -> float:
	var delta := to - from
	var length_squared := delta.length_squared()
	if length_squared <= 0.000001:
		return 0.0
	return clampf((point - from).dot(delta) / length_squared, 0.0, 1.0)


static func values_with_changes(
	values: PackedByteArray,
	changes: Dictionary,
	use_after := true,
) -> PackedByteArray:
	var result := values.duplicate()
	var field := "after" if use_after else "before"
	for raw_index in changes:
		var index := int(raw_index)
		if index >= 0 and index < result.size():
			result[index] = int((changes[raw_index] as Dictionary).get(field, result[index]))
	return result


static func _top_filled_y(
	values: PackedByteArray,
	size: Vector3i,
	x: int,
	z: int,
) -> int:
	for y in range(size.y - 1, -1, -1):
		if values[index_of(Vector3i(x, y, z), size)] != 0:
			return y
	return -1


static func pick(
	resource: EmberVoxelModelResource,
	ray_origin: Vector3,
	ray_direction: Vector3,
	visible_height := -1,
	allow_empty_floor := false,
) -> Dictionary:
	if resource == null or ray_direction.is_zero_approx():
		return {}
	var size := preload("res://scripts/ember_voxel_edit_bounds.gd").visible_size(resource.grid_size(), visible_height)
	if size.y <= 0:
		return {}
	var density := float(resource.normalized_density())
	var bounds := Vector3(size) / density
	var interval := _ray_box_interval(ray_origin, ray_direction.normalized(), bounds)
	if interval.x < 0.0 or interval.y < interval.x:
		return {}
	var step := 0.32 / density
	var t := maxf(interval.x, 0.0) + step * 0.25
	var previous_cell := INVALID_CELL
	var last_empty := INVALID_CELL
	while t <= interval.y + step:
		var point := ray_origin + ray_direction.normalized() * t
		var cell := Vector3i(
			floori(point.x * density),
			floori(point.y * density),
			floori(point.z * density),
		)
		cell.x = clampi(cell.x, 0, size.x - 1)
		cell.y = clampi(cell.y, 0, size.y - 1)
		cell.z = clampi(cell.z, 0, size.z - 1)
		if cell != previous_cell:
			var value := int(resource.voxels[index_of(cell, size)])
			if value != 0:
				return {"hit": cell, "adjacent": last_empty}
			last_empty = cell
			previous_cell = cell
		t += step
	if allow_empty_floor and absf(ray_direction.y) > 0.00001:
		var floor_t := -ray_origin.y / ray_direction.y
		var point := ray_origin + ray_direction * floor_t
		var floor_cell := Vector3i(floori(point.x * density), 0, floori(point.z * density))
		if floor_t >= 0.0 and contains(floor_cell, size):
			return {"hit": INVALID_CELL, "adjacent": floor_cell, "empty_floor": true}
	return {}


static func _ray_box_interval(origin: Vector3, direction: Vector3, bounds: Vector3) -> Vector2:
	var t_min := -INF
	var t_max := INF
	for axis in 3:
		var o := origin[axis]
		var d := direction[axis]
		var maximum := bounds[axis]
		if absf(d) < 0.000001:
			if o < 0.0 or o > maximum:
				return Vector2(-1.0, -1.0)
			continue
		var first := (0.0 - o) / d
		var second := (maximum - o) / d
		if first > second:
			var swap := first
			first = second
			second = swap
		t_min = maxf(t_min, first)
		t_max = minf(t_max, second)
		if t_min > t_max:
			return Vector2(-1.0, -1.0)
	return Vector2(t_min, t_max)
