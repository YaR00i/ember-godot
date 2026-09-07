@tool
class_name EmberVoxelSurfacePhysics
extends RefCounted
## Pure derived physics/navigation queries for one canonical world Surface.
## No collision, route or height data is persisted beside the voxel Resource.


static func solid_height_at(resource: EmberVoxelModelResource, cell: Vector2i) -> int:
	if resource == null:
		return -1
	var size := resource.grid_size()
	if (
		cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.z
		or resource.voxels.size() != size.x * size.y * size.z
	):
		return -1
	for y in range(size.y - 1, -1, -1):
		var voxel_index := VoxMesher.cell_index(cell.x, y, cell.y, size.x, size.z)
		if int(resource.voxels[voxel_index]) > 0:
			return y
	return -1


static func build_collision_region(
	resource: EmberVoxelModelResource,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size: float,
	solid_heights := PackedInt32Array(),
) -> ArrayMesh:
	var result := build_collision_region_result(
		resource, region_min, region_size, voxel_size, solid_heights
	)
	return result.get("mesh", ArrayMesh.new()) as ArrayMesh


static func build_collision_region_result(
	resource: EmberVoxelModelResource,
	region_min: Vector3i,
	region_size: Vector3i,
	voxel_size: float,
	solid_heights := PackedInt32Array(),
) -> Dictionary:
	## World collision is the top-solid heightfield of the same dense voxels.
	## Equal-height columns are greedily merged so collision stays exact at the
	## art-voxel boundary without emitting one top quad per dense cell. Visual
	## water/fill planes and internal faces are deliberately excluded.
	if resource == null:
		return {"mesh": ArrayMesh.new(), "heights": PackedInt32Array()}
	var size := resource.grid_size()
	var start := Vector2i(
		clampi(region_min.x, 0, size.x), clampi(region_min.z, 0, size.z)
	)
	var extent := Vector2i(
		clampi(region_size.x, 0, size.x - start.x),
		clampi(region_size.z, 0, size.z - start.y),
	)
	var mesh := ArrayMesh.new()
	if extent.x < 1 or extent.y < 1:
		return {"mesh": mesh, "start": start, "extent": extent, "heights": PackedInt32Array()}
	var heights := PackedInt32Array()
	heights.resize(extent.x * extent.y)
	heights.fill(-1)
	var cache_min := Vector2i(maxi(0, start.x - 1), maxi(0, start.y - 1))
	var cache_max := Vector2i(
		mini(size.x, start.x + extent.x + 1), mini(size.z, start.y + extent.y + 1)
	)
	var cache_extent := cache_max - cache_min
	var padded_heights := PackedInt32Array()
	padded_heights.resize(cache_extent.x * cache_extent.y)
	padded_heights.fill(-1)
	var has_full_height_cache := solid_heights.size() == size.x * size.z
	for cached_z in range(cache_min.y, cache_max.y):
		for cached_x in range(cache_min.x, cache_max.x):
			padded_heights[
				(cached_x - cache_min.x) + (cached_z - cache_min.y) * cache_extent.x
			] = (
				solid_heights[cached_x + cached_z * size.x]
				if has_full_height_cache
				else solid_height_at(resource, Vector2i(cached_x, cached_z))
			)
	for local_z in extent.y:
		for local_x in extent.x:
			var cell := start + Vector2i(local_x, local_z)
			heights[local_x + local_z * extent.x] = padded_heights[
				(cell.x - cache_min.x) + (cell.y - cache_min.y) * cache_extent.x
			]
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var claimed := PackedByteArray()
	claimed.resize(heights.size())
	claimed.fill(0)
	# Greedy top rectangles are the dominant win on a handcrafted Surface.
	for local_z in extent.y:
		for local_x in extent.x:
			var local_index := local_x + local_z * extent.x
			var height := heights[local_index]
			if height < 0 or claimed[local_index] != 0:
				continue
			var run_width := 1
			while (
				local_x + run_width < extent.x
				and claimed[local_index + run_width] == 0
				and heights[local_index + run_width] == height
			):
				run_width += 1
			var run_depth := 1
			while local_z + run_depth < extent.y:
				var row_matches := true
				for offset_x in run_width:
					var candidate := (
						local_x + offset_x + (local_z + run_depth) * extent.x
					)
					if claimed[candidate] != 0 or heights[candidate] != height:
						row_matches = false
						break
				if not row_matches:
					break
				run_depth += 1
			for offset_z in run_depth:
				for offset_x in run_width:
					claimed[
						local_x + offset_x + (local_z + offset_z) * extent.x
					] = 1
			var x0 := float(start.x + local_x) * voxel_size
			var x1 := float(start.x + local_x + run_width) * voxel_size
			var z0 := float(start.y + local_z) * voxel_size
			var z1 := float(start.y + local_z + run_depth) * voxel_size
			var y := float(height + 1) * voxel_size
			_append_quad(
				vertices, indices,
				Vector3(x0, y, z1), Vector3(x1, y, z1),
				Vector3(x1, y, z0), Vector3(x0, y, z0),
			)
	# Only exposed drops need vertical collision. Global neighbor lookup keeps
	# chunk seams closed without duplicating internal walls.
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
	]
	for local_z in extent.y:
		for local_x in extent.x:
			var height := heights[local_x + local_z * extent.x]
			if height < 0:
				continue
			var cell := start + Vector2i(local_x, local_z)
			for direction in directions:
				var neighbor := cell + direction
				var neighbor_height := -1
				if (
					neighbor.x >= cache_min.x and neighbor.y >= cache_min.y
					and neighbor.x < cache_max.x and neighbor.y < cache_max.y
				):
					neighbor_height = padded_heights[
						(neighbor.x - cache_min.x)
						+ (neighbor.y - cache_min.y) * cache_extent.x
					]
				if neighbor_height >= height:
					continue
				_append_drop_quad(
					vertices, indices, cell, direction,
					neighbor_height + 1, height + 1, voxel_size,
				)
	if vertices.is_empty():
		return {"mesh": mesh, "start": start, "extent": extent, "heights": heights}
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return {"mesh": mesh, "start": start, "extent": extent, "heights": heights}


static func _append_drop_quad(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	cell: Vector2i,
	direction: Vector2i,
	bottom_layer: int,
	top_layer: int,
	voxel_size: float,
) -> void:
	var x0 := float(cell.x) * voxel_size
	var x1 := float(cell.x + 1) * voxel_size
	var z0 := float(cell.y) * voxel_size
	var z1 := float(cell.y + 1) * voxel_size
	var bottom := float(maxi(0, bottom_layer)) * voxel_size
	var top := float(top_layer) * voxel_size
	if direction == Vector2i.RIGHT:
		_append_quad(vertices, indices, Vector3(x1, bottom, z0), Vector3(x1, bottom, z1), Vector3(x1, top, z1), Vector3(x1, top, z0))
	elif direction == Vector2i.LEFT:
		_append_quad(vertices, indices, Vector3(x0, bottom, z1), Vector3(x0, bottom, z0), Vector3(x0, top, z0), Vector3(x0, top, z1))
	elif direction == Vector2i.DOWN:
		_append_quad(vertices, indices, Vector3(x1, bottom, z1), Vector3(x0, bottom, z1), Vector3(x0, top, z1), Vector3(x1, top, z1))
	else:
		_append_quad(vertices, indices, Vector3(x0, bottom, z0), Vector3(x1, bottom, z0), Vector3(x1, top, z0), Vector3(x0, top, z0))


static func _append_quad(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
) -> void:
	var base := vertices.size()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	indices.append_array(PackedInt32Array([
		base, base + 1, base + 2, base, base + 2, base + 3,
	]))


static func navigation_grid(resource: EmberVoxelModelResource) -> Dictionary:
	## Exploration routes operate on gameplay blocks, not individual art voxels.
	## A 3x3 median rejects small decorative bumps without inventing a second map.
	if resource == null:
		return {"width": 0, "depth": 0, "heights": PackedInt32Array()}
	var width := maxi(0, resource.size_blocks.x)
	var depth := maxi(0, resource.size_blocks.z)
	var heights := PackedInt32Array()
	heights.resize(width * depth)
	heights.fill(-1)
	var density := resource.normalized_density()
	var sample_offsets := PackedInt32Array([
		maxi(0, density / 4),
		maxi(0, density / 2),
		mini(density - 1, (density * 3) / 4),
	])
	for block_z in depth:
		for block_x in width:
			var samples: Array[int] = []
			for offset_z in sample_offsets:
				for offset_x in sample_offsets:
					var height := solid_height_at(
						resource,
						Vector2i(block_x * density + offset_x, block_z * density + offset_z),
					)
					if height >= 0:
						samples.append(height)
			if samples.size() >= 5:
				samples.sort()
				heights[block_x + block_z * width] = samples[samples.size() / 2]
	return {"width": width, "depth": depth, "heights": heights}


static func navigation_grid_from_solid_heights(
	resource: EmberVoxelModelResource,
	solid_heights: PackedInt32Array,
) -> Dictionary:
	if resource == null:
		return {"width": 0, "depth": 0, "heights": PackedInt32Array()}
	var grid_size := resource.grid_size()
	if solid_heights.size() != grid_size.x * grid_size.z:
		return navigation_grid(resource)
	var width := maxi(0, resource.size_blocks.x)
	var depth := maxi(0, resource.size_blocks.z)
	var heights := PackedInt32Array()
	heights.resize(width * depth)
	heights.fill(-1)
	var density := resource.normalized_density()
	var sample_offsets := PackedInt32Array([
		maxi(0, density / 4),
		maxi(0, density / 2),
		mini(density - 1, (density * 3) / 4),
	])
	for block_z in depth:
		for block_x in width:
			var samples: Array[int] = []
			for offset_z in sample_offsets:
				for offset_x in sample_offsets:
					var cell_x := block_x * density + offset_x
					var cell_z := block_z * density + offset_z
					var height := solid_heights[cell_x + cell_z * grid_size.x]
					if height >= 0:
						samples.append(height)
			if samples.size() >= 5:
				samples.sort()
				heights[block_x + block_z * width] = samples[samples.size() / 2]
	return {"width": width, "depth": depth, "heights": heights}


static func find_block_path(
	resource: EmberVoxelModelResource,
	start: Vector2i,
	goal: Vector2i,
	max_step_voxels := 4,
) -> Array[Vector2i]:
	return find_block_path_from_grid(navigation_grid(resource), start, goal, max_step_voxels)


static func find_block_path_from_grid(
	grid: Dictionary,
	start: Vector2i,
	goal: Vector2i,
	max_step_voxels := 4,
) -> Array[Vector2i]:
	var width := int(grid.get("width", 0))
	var depth := int(grid.get("depth", 0))
	var heights: PackedInt32Array = grid.get("heights", PackedInt32Array())
	var empty: Array[Vector2i] = []
	if (
		width < 1 or depth < 1
		or not _block_in_bounds(start, width, depth)
		or not _block_in_bounds(goal, width, depth)
	):
		return empty
	var start_index := start.x + start.y * width
	var goal_index := goal.x + goal.y * width
	if heights[start_index] < 0 or heights[goal_index] < 0:
		return empty
	var open: Array[int] = [start_index]
	var came_from := PackedInt32Array()
	came_from.resize(width * depth)
	came_from.fill(-1)
	var cost := PackedInt32Array()
	cost.resize(width * depth)
	cost.fill(2147483647)
	cost[start_index] = 0
	var closed := PackedByteArray()
	closed.resize(width * depth)
	closed.fill(0)
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
	]
	while not open.is_empty():
		var best_position := 0
		var best_index: int = open[0]
		var best_score := cost[best_index] + _manhattan(_block(best_index, width), goal)
		for position in range(1, open.size()):
			var candidate: int = open[position]
			var score := cost[candidate] + _manhattan(_block(candidate, width), goal)
			if score < best_score:
				best_position = position
				best_index = candidate
				best_score = score
		open.remove_at(best_position)
		if best_index == goal_index:
			return _reconstruct_path(came_from, goal_index, width)
		if closed[best_index] != 0:
			continue
		closed[best_index] = 1
		var current := _block(best_index, width)
		for direction in directions:
			var next: Vector2i = current + direction
			if not _block_in_bounds(next, width, depth):
				continue
			var next_index: int = next.x + next.y * width
			if (
				heights[next_index] < 0
				or absi(heights[next_index] - heights[best_index]) > maxi(0, max_step_voxels)
			):
				continue
			var next_cost := cost[best_index] + 1
			if next_cost >= cost[next_index]:
				continue
			cost[next_index] = next_cost
			came_from[next_index] = best_index
			open.append(next_index)
	return empty


static func _reconstruct_path(
	came_from: PackedInt32Array,
	goal_index: int,
	width: int,
) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = []
	var current := goal_index
	while current >= 0:
		reversed.append(_block(current, width))
		current = came_from[current]
	reversed.reverse()
	return reversed


static func _block(index: int, width: int) -> Vector2i:
	return Vector2i(index % width, floori(float(index) / float(width)))


static func _block_in_bounds(block: Vector2i, width: int, depth: int) -> bool:
	return block.x >= 0 and block.y >= 0 and block.x < width and block.y < depth


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
