@tool
extends RefCounted
## Optional B appearance baked into the existing canonical voxel source.
## Wood, collision, grid, identity and material channels retain their owners.

static func apply(source: EmberVoxelModelResource, detail: int) -> EmberVoxelModelResource:
	var size := Vector3i(4, 2, 4) if detail == 1 else Vector3i(8, 4, 8)
	var grid := source.grid_size()
	var buckets: Dictionary = {}
	for index in source.voxels.size():
		var palette_index := int(source.voxels[index])
		if palette_index not in [4, 5, 6]: continue
		var point := Vector3i(index % grid.x, index / (grid.x * grid.z), (index / grid.x) % grid.z)
		var key := Vector3i(point.x / size.x, point.y / size.y, point.z / size.z)
		var counts: Vector3i = buckets.get(key, Vector3i.ZERO)
		counts[palette_index - 4] += 1
		buckets[key] = counts
	var result := source.duplicate_model()
	for key: Vector3i in buckets:
		var counts: Vector3i = buckets[key]
		# One palette tone per element; ties prefer the quiet middle foliage tone.
		var palette_index := 5
		if counts.x > counts.y and counts.x >= counts.z: palette_index = 4
		elif counts.z > counts.y and counts.z > counts.x: palette_index = 6
		var start := key * size
		var finish := (start + size).min(grid)
		for y in range(start.y, finish.y):
			for z in range(start.z, finish.z):
				for x in range(start.x, finish.x):
					var index := x + grid.x * (z + grid.z * y)
					if source.voxels[index] != 0 and int(source.voxels[index]) not in [4, 5, 6]: continue
					result.voxels[index] = palette_index
	return result
