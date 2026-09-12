@tool
extends RefCounted
## Pure bounded helpers shared by procedural voxel content providers.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")


static func paint_sphere(
	source: EmberVoxelModelResource,
	center: Vector3,
	radius: float,
	color_index: int,
) -> void:
	if source == null or radius <= 0.0 or color_index <= 0:
		return
	var size := source.grid_size()
	var low := Vector3i((center - Vector3.ONE * radius).floor())
	var high := Vector3i((center + Vector3.ONE * radius).ceil())
	for y in range(maxi(0, low.y), mini(size.y - 1, high.y) + 1):
		for z in range(maxi(0, low.z), mini(size.z - 1, high.z) + 1):
			for x in range(maxi(0, low.x), mini(size.x - 1, high.x) + 1):
				var cell := Vector3i(x, y, z)
				if (Vector3(cell) - center).length_squared() <= radius * radius:
					source.voxels[Model.index_of(cell, size)] = color_index


static func paint_line(
	source: EmberVoxelModelResource,
	from: Vector3,
	to: Vector3,
	radius: float,
	color_index: int,
) -> void:
	var delta := to - from
	var steps := maxi(1, ceili(delta.length() * 2.0))
	for step in range(steps + 1):
		paint_sphere(
			source,
			from + delta * float(step) / float(steps),
			radius,
			color_index,
		)


static func keep_largest_component(source: EmberVoxelModelResource) -> void:
	if source == null:
		return
	var size := source.grid_size()
	var visited := {}
	var largest := PackedInt32Array()
	var directions: Array[Vector3i] = [
		Vector3i.LEFT,
		Vector3i.RIGHT,
		Vector3i.DOWN,
		Vector3i.UP,
		Vector3i.FORWARD,
		Vector3i.BACK,
	]
	for start in source.voxels.size():
		if source.voxels[start] == 0 or visited.has(start):
			continue
		var component := PackedInt32Array()
		var pending: Array[int] = [start]
		visited[start] = true
		while not pending.is_empty():
			var index: int = pending.pop_back()
			component.append(index)
			var cell := Vector3i(
				index % size.x,
				index / (size.x * size.z),
				(index / size.x) % size.z,
			)
			for direction: Vector3i in directions:
				var neighbor := cell + direction
				if not Model.contains(neighbor, size):
					continue
				var neighbor_index := Model.index_of(neighbor, size)
				if source.voxels[neighbor_index] != 0 and not visited.has(neighbor_index):
					visited[neighbor_index] = true
					pending.append(neighbor_index)
		if component.size() > largest.size():
			largest = component
	var retained := {}
	for index in largest:
		retained[index] = true
	for index in source.voxels.size():
		if source.voxels[index] != 0 and not retained.has(index):
			source.voxels[index] = 0
