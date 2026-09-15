@tool
class_name EmberVoxelSurfaceMesher
extends RefCounted
## Surface-specific projection: canonical voxels always remain opaque terrain,
## while their transparency channel acts as a shallow-water overlay mask.
## Level fills are a second, column-sized visual channel: they bridge a sculpted
## cavity with one horizontal plane without creating hidden liquid voxels.
## Generic voxel props keep the original VoxMesher transparency semantics.

const SURFACE_FILL_WATER := 1
const SURFACE_FILL_WATER_TRANSPARENCY := 208
const SHORE_RESPONSE_DISTANCE := 4.0
const SHORE_RUNUP_DISTANCE := 1.125
const SHORE_WAVE_METADATA_DISTANCE := 5.0
const SHORE_METADATA_PATCH_SIZE := 1.0
const SHORE_METADATA_DISTANCE_STEP := 0.25
const CARDINAL_DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const SurfacePhysics = preload("res://scripts/ember_voxel_surface_physics.gd")
const Heightfield = preload("res://scripts/ember_voxel_heightfield.gd")


static func build_region(
	resource: EmberVoxelModelResource,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size: float,
	draft_heightfield := false,
	include_water := true,
	visible_height := -1,
	water_shore_field: Dictionary = {},
) -> ArrayMesh:
	var result := ArrayMesh.new()
	if resource == null:
		return result
	var empty_transparency := PackedByteArray()
	var terrain := (
		VoxMesher.build_heightfield_preview_region(
			resource.voxels,
			resource.grid_size(),
			resource.palette,
			empty_transparency,
			region_min,
			region_size,
			voxel_size,
		)
		if draft_heightfield and visible_height < 0
		else VoxMesher.build_from_packed_voxel_region(
			resource.voxels,
			resource.grid_size(),
			resource.palette,
			empty_transparency,
			region_min,
			region_size,
			voxel_size,
			PackedByteArray(),
			visible_height,
		)
	)
	_copy_surfaces(terrain, result)
	if include_water and visible_height < 0:
		append_water_overlay(
			resource, result, region_min, region_size, voxel_size, water_shore_field
		)
	return result


static func _copy_surfaces(source: ArrayMesh, target: ArrayMesh) -> void:
	for surface_index in source.get_surface_count():
		target.add_surface_from_arrays(
			source.surface_get_primitive_type(surface_index),
			source.surface_get_arrays(surface_index),
		)
		target.surface_set_name(
			target.get_surface_count() - 1,
			source.surface_get_name(surface_index),
		)


static func build_water_shore_field(resource: EmberVoxelModelResource) -> Dictionary:
	## Build one canonical water/shore field for the complete Surface Resource.
	## Chunk builders only slice this result, so distance and direction cannot reset
	## or change at technical chunk boundaries.
	if resource == null:
		return {}
	var size := resource.grid_size()
	if size.x <= 0 or size.z <= 0:
		return {}
	var solid_heights := Heightfield.column_heights(
		resource.voxels, size, resource.palette.size() - 1
	)
	var columns := _build_water_columns(
		resource, Vector2i.ZERO, Vector2i(size.x, size.z), solid_heights
	)
	var heights := columns.get("heights", PackedInt32Array()) as PackedInt32Array
	if heights.size() != size.x * size.z:
		return {}
	var maximum_steps := ceili(
		SHORE_WAVE_METADATA_DISTANCE * float(resource.normalized_density())
	)
	var distances := PackedInt32Array()
	distances.resize(heights.size())
	distances.fill(maximum_steps + 1)
	var direction_codes := PackedByteArray()
	direction_codes.resize(heights.size())
	var walls := PackedByteArray()
	walls.resize(heights.size())
	var queue: Array[int] = []
	for z in size.z:
		for x in size.x:
			var index := x + z * size.x
			var height := int(heights[index])
			if height < 0:
				continue
			var inward_sum := Vector2.ZERO
			var exposed_count := 0
			var beach_count := 0
			var cell := Vector2i(x, z)
			for raw_direction in CARDINAL_DIRECTIONS:
				var direction := raw_direction as Vector2i
				var neighbor: Vector2i = cell + direction
				# A Resource edge can be an open continuation of the sea. Only real
				# authored terrain/water transitions seed a shoreline response.
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.z:
					continue
				var neighbor_water := _field_water_height(heights, size, neighbor)
				if neighbor_water == height:
					continue
				exposed_count += 1
				inward_sum -= Vector2(direction)
				var neighbor_solid := _field_solid_height(solid_heights, size, neighbor)
				var is_wall := neighbor_water >= 0 or neighbor_solid > height + 1
				if not is_wall:
					beach_count += 1
			if exposed_count == 0:
				continue
			distances[index] = 0
			direction_codes[index] = _encode_shore_direction(inward_sum.normalized())
			walls[index] = 1 if beach_count == 0 else 0
			queue.append(index)
	var read_index := 0
	while read_index < queue.size():
		var index := queue[read_index]
		read_index += 1
		var distance := int(distances[index])
		if distance >= maximum_steps:
			continue
		var cell := Vector2i(index % size.x, index / size.x)
		var height := int(heights[index])
		for raw_direction in CARDINAL_DIRECTIONS:
			var direction := raw_direction as Vector2i
			var neighbor: Vector2i = cell + direction
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.z:
				continue
			var neighbor_index: int = neighbor.x + neighbor.y * size.x
			if int(heights[neighbor_index]) != height:
				continue
			var next_distance := distance + 1
			if next_distance >= int(distances[neighbor_index]):
				continue
			distances[neighbor_index] = next_distance
			direction_codes[neighbor_index] = direction_codes[index]
			walls[neighbor_index] = walls[index]
			queue.append(neighbor_index)
	columns["size"] = Vector2i(size.x, size.z)
	columns["distances"] = distances
	columns["direction_codes"] = direction_codes
	columns["walls"] = walls
	columns["maximum_steps"] = maximum_steps
	return columns


static func _build_water_columns(
	resource: EmberVoxelModelResource,
	start: Vector2i,
	extent: Vector2i,
	solid_heights := PackedInt32Array(),
) -> Dictionary:
	var size := resource.grid_size()
	var count := extent.x * extent.y
	var heights := PackedInt32Array()
	heights.resize(count)
	heights.fill(-1)
	var palette_indices := PackedByteArray()
	palette_indices.resize(count)
	var amounts := PackedByteArray()
	amounts.resize(count)
	var water_depths := PackedByteArray()
	water_depths.resize(count)
	for local_z in extent.y:
		for local_x in extent.x:
			var x := start.x + local_x
			var z := start.y + local_z
			var local_index := local_x + local_z * extent.x
			var column_index := x + z * size.x
			var top_y := (
				int(solid_heights[column_index])
				if solid_heights.size() == size.x * size.z
				else SurfacePhysics.solid_height_at(resource, Vector2i(x, z))
			)
			var top_palette := 0
			var top_transparency := 0
			if top_y >= 0:
				var voxel_index := VoxMesher.cell_index(x, top_y, z, size.x, size.z)
				top_palette = int(resource.voxels[voxel_index])
				top_transparency = (
					int(resource.transparency[voxel_index])
					if voxel_index < resource.transparency.size()
					else 0
				)
			var fill_level := (
				int(resource.surface_fill_levels[column_index])
				if column_index < resource.surface_fill_levels.size()
				else 0
			)
			var fill_material := (
				int(resource.surface_fill_materials[column_index])
				if column_index < resource.surface_fill_materials.size()
				else 0
			)
			if (
				fill_material == SURFACE_FILL_WATER
				and fill_level > top_y + 1 and fill_level <= size.y
			):
				var fill_palette := (
					int(resource.surface_fill_palette[column_index])
					if column_index < resource.surface_fill_palette.size()
					else top_palette
				)
				heights[local_index] = fill_level - 1
				water_depths[local_index] = clampi(fill_level - (top_y + 1), 1, 255)
				palette_indices[local_index] = (
					fill_palette
					if fill_palette > 0 and fill_palette < resource.palette.size()
					else 0
				)
				amounts[local_index] = SURFACE_FILL_WATER_TRANSPARENCY
			elif top_y >= 0 and top_transparency > 0:
				heights[local_index] = top_y
				water_depths[local_index] = 1
				palette_indices[local_index] = top_palette
				amounts[local_index] = top_transparency
	return {
		"heights": heights,
		"palette_indices": palette_indices,
		"amounts": amounts,
		"water_depths": water_depths,
	}


static func _field_water_height(
	heights: PackedInt32Array,
	size: Vector3i,
	cell: Vector2i,
) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.z:
		return -1
	return int(heights[cell.x + cell.y * size.x])


static func _field_solid_height(
	heights: PackedInt32Array,
	size: Vector3i,
	cell: Vector2i,
) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.z:
		return -1
	if heights.size() != size.x * size.z:
		return -1
	return int(heights[cell.x + cell.y * size.x])


static func _encode_shore_direction(direction: Vector2) -> int:
	if direction.length_squared() < 0.25:
		return 0
	var angle := atan2(direction.y, direction.x)
	return posmod(roundi(angle / (PI * 0.25)), 8) + 1


static func _decode_shore_direction(code: int) -> Vector2:
	if code <= 0:
		return Vector2.ZERO
	var angle := float(code - 1) * PI * 0.25
	return Vector2(cos(angle), sin(angle))


static func append_water_overlay(
	resource: EmberVoxelModelResource,
	mesh: ArrayMesh,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size: float,
	water_shore_field: Dictionary = {},
) -> void:
	if resource.transparency.is_empty() and resource.surface_fill_materials.is_empty():
		return
	var size := resource.grid_size()
	var start := Vector2i(
		clampi(region_min.x, 0, size.x),
		clampi(region_min.z, 0, size.z),
	)
	var end := Vector2i(
		clampi(region_min.x + region_size.x, start.x, size.x),
		clampi(region_min.z + region_size.z, start.y, size.z),
	)
	var extent := end - start
	if extent.x <= 0 or extent.y <= 0:
		return
	var shore_field := water_shore_field
	if shore_field.is_empty():
		shore_field = build_water_shore_field(resource)
	var field_size: Vector2i = shore_field.get("size", Vector2i.ZERO)
	if field_size != Vector2i(size.x, size.z):
		return
	var field_heights := shore_field.get("heights", PackedInt32Array()) as PackedInt32Array
	var field_palette := shore_field.get("palette_indices", PackedByteArray()) as PackedByteArray
	var field_amounts := shore_field.get("amounts", PackedByteArray()) as PackedByteArray
	var field_depths := shore_field.get("water_depths", PackedByteArray()) as PackedByteArray
	if field_heights.size() != size.x * size.z:
		return
	var count := extent.x * extent.y
	var heights := PackedInt32Array()
	heights.resize(count)
	heights.fill(-1)
	var palette_indices := PackedByteArray()
	palette_indices.resize(count)
	palette_indices.fill(0)
	var amounts := PackedByteArray()
	amounts.resize(count)
	amounts.fill(0)
	var water_depths := PackedByteArray()
	water_depths.resize(count)
	water_depths.fill(0)
	for local_z in extent.y:
		for local_x in extent.x:
			var x := start.x + local_x
			var z := start.y + local_z
			var local_index := local_x + local_z * extent.x
			var field_index := x + z * size.x
			heights[local_index] = field_heights[field_index]
			water_depths[local_index] = field_depths[field_index]
			palette_indices[local_index] = field_palette[field_index]
			amounts[local_index] = field_amounts[field_index]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	var visited := PackedByteArray()
	visited.resize(count)
	visited.fill(0)
	for local_z in extent.y:
		for local_x in extent.x:
			var local_index := local_x + local_z * extent.x
			if visited[local_index] != 0 or heights[local_index] < 0:
				continue
			var height := int(heights[local_index])
			var palette_index := int(palette_indices[local_index])
			var amount := int(amounts[local_index])
			var water_depth := int(water_depths[local_index])
			var metadata_key := _water_shore_merge_key(
				shore_field, Vector2i(start.x + local_x, start.y + local_z), voxel_size
			)
			var maximum_span := maxi(1, floori(SHORE_METADATA_PATCH_SIZE / maxf(voxel_size, 0.0001)))
			var width := 1
			while local_x + width < extent.x and width < maximum_span:
				var next_index := local_index + width
				if (
					visited[next_index] != 0
					or int(heights[next_index]) != height
					or int(palette_indices[next_index]) != palette_index
					or int(amounts[next_index]) != amount
					or int(water_depths[next_index]) != water_depth
					or _water_shore_merge_key(
						shore_field,
						Vector2i(start.x + local_x + width, start.y + local_z),
						voxel_size,
					) != metadata_key
				):
					break
				width += 1
			var depth := 1
			while local_z + depth < extent.y and depth < maximum_span:
				var row_matches := true
				for offset_x in width:
					var next_index := local_x + offset_x + (local_z + depth) * extent.x
					if (
						visited[next_index] != 0
						or int(heights[next_index]) != height
						or int(palette_indices[next_index]) != palette_index
						or int(amounts[next_index]) != amount
						or int(water_depths[next_index]) != water_depth
						or _water_shore_merge_key(
							shore_field,
							Vector2i(
								start.x + local_x + offset_x,
								start.y + local_z + depth,
							),
							voxel_size,
						) != metadata_key
					):
						row_matches = false
						break
				if not row_matches:
					break
				depth += 1
			for offset_z in depth:
				for offset_x in width:
					visited[local_x + offset_x + (local_z + offset_z) * extent.x] = 1
			var color := (
				resource.palette[palette_index]
				if palette_index > 0 and palette_index < resource.palette.size()
				else Color("#4bc9ca")
			)
			color.a = VoxMesher.opacity_from_transparency(amount)
			_append_water_quad(
				vertices,
				normals,
				colors,
				uvs,
				uv2s,
				indices,
				Vector2i(start.x + local_x, start.y + local_z),
				Vector2i(width, depth),
				height,
				voxel_size,
				color,
				water_depth,
				shore_field,
			)
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(mesh.get_surface_count() - 1, "water")
	_append_water_foam(
		resource, mesh, heights, water_depths, start, extent, voxel_size,
		vertices, uvs, uv2s,
	)


static func region_has_water_overlay(
	resource: EmberVoxelModelResource,
	region_min: Vector3i,
	region_size: Vector3i,
) -> bool:
	## Query the canonical water columns without constructing visual geometry.
	## Native Surface composition uses append_water_overlay directly and keeps
	## its complete-Surface coordinates by baking the greedy terrain transform.
	if resource == null:
		return false
	if resource.transparency.is_empty() and resource.surface_fill_materials.is_empty():
		return false
	var size := resource.grid_size()
	var start := Vector2i(
		clampi(region_min.x, 0, size.x),
		clampi(region_min.z, 0, size.z),
	)
	var end := Vector2i(
		clampi(region_min.x + region_size.x, start.x, size.x),
		clampi(region_min.z + region_size.z, start.y, size.z),
	)
	for z in range(start.y, end.y):
		for x in range(start.x, end.x):
			if water_height_at(resource, Vector2i(x, z)) >= 0:
				return true
	return false


static func _append_water_foam(
	resource: EmberVoxelModelResource,
	mesh: ArrayMesh,
	heights: PackedInt32Array,
	water_depths: PackedByteArray,
	start: Vector2i,
	extent: Vector2i,
	voxel_size: float,
	water_vertices: PackedVector3Array,
	water_uvs: PackedVector2Array,
	water_uv2s: PackedVector2Array,
) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	# The water-side response reuses the exact non-overlapping water patches.
	# The former edge strips overlapped once per shoreline cell and multiplied
	# foam into bright parallel bands on curved or stair-stepped coasts.
	for quad_start in range(0, water_vertices.size(), 4):
		var include_quad := false
		for corner in 4:
			var source_index := quad_start + corner
			if (
				source_index < water_uv2s.size()
				and water_uv2s[source_index].length() > 0.5
				and absf(water_uvs[source_index].y) <= SHORE_RESPONSE_DISTANCE + 0.5
			):
				include_quad = true
				break
		if not include_quad:
			continue
		var first := vertices.size()
		for corner in 4:
			var source_index := quad_start + corner
			var vertex := water_vertices[source_index]
			vertex.y += 0.018 * voxel_size
			vertices.append(vertex)
			normals.append(Vector3.UP)
			var depth_factor := clampf(water_uvs[source_index].x, 0.0, 1.0)
			colors.append(Color(0.88, 1.0, depth_factor, 0.60))
			var signed_water_distance := water_uvs[source_index].y
			uvs.append(Vector2(absf(signed_water_distance), 1.0 if signed_water_distance < 0.0 else 0.0))
			uv2s.append(water_uv2s[source_index])
		indices.append_array(PackedInt32Array([
			first, first + 1, first + 2,
			first, first + 2, first + 3,
		]))
	for local_z in extent.y:
		for local_x in extent.x:
			var local_index := local_x + local_z * extent.x
			var height := int(heights[local_index])
			if height < 0:
				continue
			var cell := Vector2i(start.x + local_x, start.y + local_z)
			var exposed: Array[Vector2i] = []
			for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if _neighbor_water_height(
					resource, heights, start, extent, cell + direction
				) == height:
					continue
				exposed.append(direction)
			for direction in exposed:
				var pattern := _foam_pattern(cell, direction)
				var depth_factor := float(clampi(int(water_depths[local_index]) - 1, 0, 3)) / 3.0
				var neighbor := cell + direction
				var neighbor_water := _neighbor_water_height(
					resource, heights, start, extent, neighbor
				)
				var neighbor_solid := solid_height_at(resource, neighbor)
				# A dry cell at water level is a walkable beach step. A higher
				# column, or a second water plane at another height, is a hard
				# boundary that sends the crest back into the basin.
				var is_wall := neighbor_water >= 0 or neighbor_solid > height + 1
				if neighbor_water < 0 and neighbor_solid >= 0 and not is_wall:
					_append_foam_runup(
						resource,
						vertices,
						normals,
						colors,
						uvs,
						uv2s,
						indices,
						cell,
						direction,
						height,
						voxel_size,
						depth_factor,
						pattern,
					)
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(mesh.get_surface_count() - 1, "water_foam")


static func _neighbor_water_height(
	resource: EmberVoxelModelResource,
	heights: PackedInt32Array,
	start: Vector2i,
	extent: Vector2i,
	cell: Vector2i,
) -> int:
	var local := cell - start
	if local.x >= 0 and local.y >= 0 and local.x < extent.x and local.y < extent.y:
		return int(heights[local.x + local.y * extent.x])
	# Only chunk-border samples need the canonical Resource lookup. This keeps
	# a large lake O(area) instead of rescanning every water column four times.
	return water_height_at(resource, cell)


static func water_height_at(resource: EmberVoxelModelResource, cell: Vector2i) -> int:
	## Shared lookup for mesh building and lightweight runtime contact visuals.
	## The returned value is the water plane's voxel layer, or -1 when dry.
	var size := resource.grid_size()
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.z:
		return -1
	var top_y := solid_height_at(resource, cell)
	var top_voxel_index := (
		VoxMesher.cell_index(cell.x, top_y, cell.y, size.x, size.z)
		if top_y >= 0
		else -1
	)
	var column_index := cell.x + cell.y * size.x
	var fill_level := (
		int(resource.surface_fill_levels[column_index])
		if column_index < resource.surface_fill_levels.size()
		else 0
	)
	if (
		column_index < resource.surface_fill_materials.size()
		and int(resource.surface_fill_materials[column_index]) == SURFACE_FILL_WATER
		and fill_level > top_y + 1
		and fill_level <= size.y
	):
		return fill_level - 1
	if (
		top_voxel_index >= 0 and top_voxel_index < resource.transparency.size()
		and int(resource.transparency[top_voxel_index]) > 0
	):
		return top_y
	return -1


static func solid_height_at(resource: EmberVoxelModelResource, cell: Vector2i) -> int:
	## Shared top-solid lookup for rendering, water contact and explicit editor
	## projections. Fill planes are deliberately excluded.
	return SurfacePhysics.solid_height_at(resource, cell)


static func _append_foam_runup(
	resource: EmberVoxelModelResource,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	indices: PackedInt32Array,
	water_cell: Vector2i,
	direction: Vector2i,
	water_height: int,
	voxel_size: float,
	depth_factor: float,
	pattern: int,
) -> void:
	var boundary := Vector2(
		(float(water_cell.x) + 0.5 + float(direction.x) * 0.5) * voxel_size,
		(float(water_cell.y) + 0.5 + float(direction.y) * 0.5) * voxel_size,
	)
	var inward := -Vector2(float(direction.x), float(direction.y))
	var maximum_steps := ceili(SHORE_RUNUP_DISTANCE / max(voxel_size, 0.0001))
	var previous_height := water_height
	for step in range(1, maximum_steps + 1):
		var dry_cell := water_cell + direction * step
		if water_height_at(resource, dry_cell) >= 0:
			break
		var ground_height := solid_height_at(resource, dry_cell)
		if ground_height < 0 or ground_height > water_height + 2:
			break
		if step > 1 and absi(ground_height - previous_height) > 1:
			break
		previous_height = ground_height
		var x0 := float(dry_cell.x) * voxel_size
		var x1 := float(dry_cell.x + 1) * voxel_size
		var z0 := float(dry_cell.y) * voxel_size
		var z1 := float(dry_cell.y + 1) * voxel_size
		var y := (float(ground_height + 1) + 0.018) * voxel_size
		_append_shore_quad(
			vertices, normals, colors, uvs, uv2s, indices,
			Vector3(x0, y, z1), Vector3(x0, y, z0),
			Vector3(x1, y, z0), Vector3(x1, y, z1),
			boundary, inward, false, pattern, depth_factor,
		)


static func _append_shore_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	boundary: Vector2,
	inward: Vector2,
	is_wall: bool,
	pattern: int,
	depth_factor: float,
) -> void:
	var first := vertices.size()
	var wall_channel := 1.0 if is_wall else 0.0
	var alpha := 0.56 + float(pattern % 3) * 0.04
	for vertex in [a, b, c, d]:
		vertices.append(vertex)
		normals.append(Vector3.UP)
		# Foam colour is selected in the shader. COLOR.b carries the same derived
		# water depth used by the surface, keeping the H/depth break test shared.
		colors.append(Color(0.88, 1.0, clampf(depth_factor, 0.0, 1.0), alpha))
		var signed_distance := (Vector2(vertex.x, vertex.z) - boundary).dot(inward)
		uvs.append(Vector2(signed_distance, wall_channel))
		uv2s.append(inward)
	indices.append_array(PackedInt32Array([
		first, first + 1, first + 2,
		first, first + 2, first + 3,
	]))


static func _append_water_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	indices: PackedInt32Array,
	cell: Vector2i,
	extent: Vector2i,
	height: int,
	voxel_size: float,
	color: Color,
	water_depth: int,
	shore_field: Dictionary,
) -> void:
	var x0 := float(cell.x) * voxel_size
	var x1 := float(cell.x + extent.x) * voxel_size
	var z0 := float(cell.y) * voxel_size
	var z1 := float(cell.y + extent.y) * voxel_size
	var y := (float(height + 1) + 0.06) * voxel_size
	var first := vertices.size()
	var quad_vertices := [
		Vector3(x0, y, z1),
		Vector3(x0, y, z0),
		Vector3(x1, y, z0),
		Vector3(x1, y, z1),
	]
	var metadata_vertices := [
		Vector2i(cell.x, cell.y + extent.y),
		cell,
		Vector2i(cell.x + extent.x, cell.y),
		Vector2i(cell.x + extent.x, cell.y + extent.y),
	]
	var depth_factor := float(clampi(water_depth - 1, 0, 3)) / 3.0
	for vertex_index in 4:
		vertices.append(quad_vertices[vertex_index])
		normals.append(Vector3.UP)
		colors.append(color)
		var metadata := _water_shore_metadata_at_vertex(
			shore_field, metadata_vertices[vertex_index], height, voxel_size
		)
		# UV.x is the compact derived depth band. UV.y carries signed distance:
		# positive for a beach, negative for a reflecting wall. UV2 is the
		# canonical waterward direction shared with the foam surface.
		uvs.append(Vector2(depth_factor, metadata.x))
		uv2s.append(Vector2(metadata.y, metadata.z))
	indices.append_array(PackedInt32Array([
		first, first + 1, first + 2,
		first, first + 2, first + 3,
	]))


static func _water_shore_metadata_at_vertex(
	shore_field: Dictionary,
	vertex: Vector2i,
	water_height: int,
	voxel_size: float,
) -> Vector3:
	var size: Vector2i = shore_field.get("size", Vector2i.ZERO)
	var heights := shore_field.get("heights", PackedInt32Array()) as PackedInt32Array
	var distances := shore_field.get("distances", PackedInt32Array()) as PackedInt32Array
	var direction_codes := shore_field.get("direction_codes", PackedByteArray()) as PackedByteArray
	var walls := shore_field.get("walls", PackedByteArray()) as PackedByteArray
	var best_distance := 2147483647
	var inward_sum := Vector2.ZERO
	var candidate_count := 0
	var wall_count := 0
	for offset in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]:
		var cell: Vector2i = vertex + offset
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			continue
		var index := cell.x + cell.y * size.x
		if (
			index >= heights.size() or int(heights[index]) != water_height
			or index >= distances.size() or index >= direction_codes.size()
			or direction_codes[index] == 0
		):
			continue
		var distance := int(distances[index])
		if distance > best_distance:
			continue
		if distance < best_distance:
			best_distance = distance
			inward_sum = Vector2.ZERO
			candidate_count = 0
			wall_count = 0
		inward_sum += _decode_shore_direction(int(direction_codes[index]))
		candidate_count += 1
		wall_count += 1 if walls[index] != 0 else 0
	if candidate_count == 0 or inward_sum.length_squared() < 0.25:
		return Vector3.ZERO
	var distance := (float(best_distance) + 0.5) * voxel_size
	if wall_count == candidate_count:
		distance = -distance
	var inward := inward_sum.normalized()
	return Vector3(distance, inward.x, inward.y)


static func _water_shore_merge_key(
	shore_field: Dictionary,
	cell: Vector2i,
	voxel_size: float,
) -> int:
	var size: Vector2i = shore_field.get("size", Vector2i.ZERO)
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return 0
	var index := cell.x + cell.y * size.x
	var distances := shore_field.get("distances", PackedInt32Array()) as PackedInt32Array
	var direction_codes := shore_field.get("direction_codes", PackedByteArray()) as PackedByteArray
	var walls := shore_field.get("walls", PackedByteArray()) as PackedByteArray
	if index >= distances.size() or index >= direction_codes.size():
		return 0
	var distance_band := floori(
		float(distances[index]) * voxel_size / SHORE_METADATA_DISTANCE_STEP
	)
	return int(direction_codes[index]) + int(walls[index]) * 16 + distance_band * 32


static func _foam_pattern(cell: Vector2i, direction: Vector2i) -> int:
	return posmod(
		cell.x * 17 + cell.y * 31 + direction.x * 7 + direction.y * 13,
		11,
	)
