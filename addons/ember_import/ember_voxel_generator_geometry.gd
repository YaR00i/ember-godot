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


static func bounds_planes(lo: Vector3, hi: Vector3) -> Array[Plane]:
	return [Plane(Vector3.RIGHT,hi.x),Plane(Vector3.LEFT,-lo.x),Plane(Vector3.UP,hi.y),Plane(Vector3.DOWN,-lo.y),Plane(Vector3.BACK,hi.z),Plane(Vector3.FORWARD,-lo.z)]


static func paint_convex_part(source: EmberVoxelModelResource, grid: Vector3i, part: Dictionary, id: int) -> void:
	# Work on local packed buffers; repeated indexed writes through Resource
	# properties otherwise detach/copy the full house array for each voxel.
	var voxels := source.voxels
	var owners := source.voxel_part_ids
	var planes: Array[Plane]=part.planes
	var lo:=Vector3i(ceili(-planes[1].d),ceili(-planes[3].d),ceili(-planes[5].d)).clamp(Vector3i.ZERO,grid)
	var hi:=Vector3i(floori(planes[0].d),floori(planes[2].d),floori(planes[4].d)).clamp(Vector3i.ZERO,grid)
	var first_clip := 6
	if part.has("paint_bounds"):
		var bounds: AABB = part.paint_bounds
		lo = Vector3i(bounds.position.floor()).clamp(Vector3i.ZERO, grid)
		hi = Vector3i(bounds.end.ceil()).clamp(Vector3i.ZERO, grid)
		first_clip = 0
	for y in range(lo.y,hi.y):
		for z in range(lo.z,hi.z):
			for x in range(lo.x,hi.x):
				var inside:=true
				for i in range(first_clip,planes.size()):
					if planes[i].distance_to(Vector3(x+0.5,y+0.5,z+0.5))>0.0001:inside=false;break
				if not inside:continue
				var index:=VoxMesher.cell_index(x,y,z,grid.x,grid.z)
				voxels[index]=part.slot;owners[index]=id
	source.voxels=voxels;source.voxel_part_ids=owners
