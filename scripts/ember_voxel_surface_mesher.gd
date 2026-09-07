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
const SurfacePhysics = preload("res://scripts/ember_voxel_surface_physics.gd")


static func build_region(
	resource: EmberVoxelModelResource,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size: float,
	draft_heightfield := false,
	include_water := true,
	visible_height := -1,
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
		append_water_overlay(resource, result, region_min, region_size, voxel_size)
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


static func append_water_overlay(
	resource: EmberVoxelModelResource,
	mesh: ArrayMesh,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size: float,
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
			var top_y := -1
			var top_palette := 0
			var top_transparency := 0
			for y in range(size.y - 1, -1, -1):
				var voxel_index := VoxMesher.cell_index(x, y, z, size.x, size.z)
				var palette_index := int(resource.voxels[voxel_index])
				if palette_index <= 0:
					continue
				top_y = y
				top_palette = palette_index
				top_transparency = (
					int(resource.transparency[voxel_index])
					if voxel_index < resource.transparency.size()
					else 0
				)
				break
			var column_index := x + z * size.x
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
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
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
			var width := 1
			while local_x + width < extent.x:
				var next_index := local_index + width
				if (
					visited[next_index] != 0
					or int(heights[next_index]) != height
					or int(palette_indices[next_index]) != palette_index
					or int(amounts[next_index]) != amount
					or int(water_depths[next_index]) != water_depth
				):
					break
				width += 1
			var depth := 1
			while local_z + depth < extent.y:
				var row_matches := true
				for offset_x in width:
					var next_index := local_x + offset_x + (local_z + depth) * extent.x
					if (
						visited[next_index] != 0
						or int(heights[next_index]) != height
						or int(palette_indices[next_index]) != palette_index
						or int(amounts[next_index]) != amount
						or int(water_depths[next_index]) != water_depth
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
				indices,
				Vector2i(start.x + local_x, start.y + local_z),
				Vector2i(width, depth),
				height,
				voxel_size,
				color,
				water_depth,
			)
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_name(mesh.get_surface_count() - 1, "water")
	_append_water_foam(resource, mesh, heights, start, extent, voxel_size)


static func region_has_water_overlay(
	resource: EmberVoxelModelResource,
	region_min: Vector3i,
	region_size: Vector3i,
) -> bool:
	## The native terrain adapter returns chunk-local voxel geometry, while this
	## mesher's water/foam vertices intentionally keep complete-Surface
	## coordinates for seamless shader patterns. Until the adapter exposes a
	## matching auxiliary-surface transform, water-bearing chunks must use the
	## exact stock Surface mesher as one coordinate-space owner.
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
	start: Vector2i,
	extent: Vector2i,
	voxel_size: float,
) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
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
				# Keep corners continuous, but interrupt long straight banks so the
				# contact line reads as quiet pixel foam instead of a white frame.
				if exposed.size() == 1 and pattern < 3:
					continue
				_append_foam_strip(
					vertices,
					normals,
					colors,
					indices,
					cell,
					direction,
					height,
					voxel_size,
					voxel_size * (0.15 + float(pattern % 3) * 0.02),
					pattern,
					exposed.size() >= 2,
				)
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
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


static func _append_foam_strip(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	cell: Vector2i,
	direction: Vector2i,
	height: int,
	voxel_size: float,
	strip_width: float,
	pattern: int,
	keep_corner: bool,
) -> void:
	var x0 := float(cell.x) * voxel_size
	var x1 := float(cell.x + 1) * voxel_size
	var z0 := float(cell.y) * voxel_size
	var z1 := float(cell.y + 1) * voxel_size
	var trim_start := voxel_size * (0.05 + float(pattern % 4) * 0.025)
	var trim_end := voxel_size * (
		0.04 + float(floori(float(pattern) / 3.0) % 4) * 0.025
	)
	if keep_corner:
		trim_start = 0.0
		trim_end = 0.0
	if direction == Vector2i.LEFT:
		x1 = x0 + strip_width
		z0 += trim_start
		z1 -= trim_end
	elif direction == Vector2i.RIGHT:
		x0 = x1 - strip_width
		z0 += trim_end
		z1 -= trim_start
	elif direction == Vector2i.UP:
		z1 = z0 + strip_width
		x0 += trim_end
		x1 -= trim_start
	else:
		z0 = z1 - strip_width
		x0 += trim_start
		x1 -= trim_end
	var y := (float(height + 1) + 0.078) * voxel_size
	var first := vertices.size()
	vertices.append(Vector3(x0, y, z1))
	vertices.append(Vector3(x0, y, z0))
	vertices.append(Vector3(x1, y, z0))
	vertices.append(Vector3(x1, y, z1))
	for unused in 4:
		normals.append(Vector3.UP)
		colors.append(Color(0.88, 1.0, 0.93, 0.56 + float(pattern % 3) * 0.04))
	indices.append_array(PackedInt32Array([
		first, first + 1, first + 2,
		first, first + 2, first + 3,
	]))


static func _append_water_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	cell: Vector2i,
	extent: Vector2i,
	height: int,
	voxel_size: float,
	color: Color,
	water_depth: int,
) -> void:
	var x0 := float(cell.x) * voxel_size
	var x1 := float(cell.x + extent.x) * voxel_size
	var z0 := float(cell.y) * voxel_size
	var z1 := float(cell.y + extent.y) * voxel_size
	var y := (float(height + 1) + 0.06) * voxel_size
	var first := vertices.size()
	vertices.append(Vector3(x0, y, z1))
	vertices.append(Vector3(x0, y, z0))
	vertices.append(Vector3(x1, y, z0))
	vertices.append(Vector3(x1, y, z1))
	for unused in 4:
		normals.append(Vector3.UP)
		colors.append(color)
		# UV.x is a compact derived depth band. It is not authored twice and
		# lets every consumer shade the same plane from its real voxel cavity.
		uvs.append(Vector2(float(clampi(water_depth - 1, 0, 3)) / 3.0, 0.0))
	indices.append_array(PackedInt32Array([
		first, first + 1, first + 2,
		first, first + 2, first + 3,
	]))


static func _foam_pattern(cell: Vector2i, direction: Vector2i) -> int:
	return posmod(
		cell.x * 17 + cell.y * 31 + direction.x * 7 + direction.y * 13,
		11,
	)
