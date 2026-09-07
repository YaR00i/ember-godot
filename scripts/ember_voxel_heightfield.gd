class_name EmberVoxelHeightfield
extends RefCounted
## Shared pure heightfield math for editor tools and transient runtime physics.
## Results are derived from canonical dense voxels and are never serialized.


static func column_heights(
	values: PackedByteArray,
	size: Vector3i,
	maximum_palette_index := 255,
) -> PackedInt32Array:
	var heights := PackedInt32Array()
	if values.size() != size.x * size.y * size.z:
		return heights
	heights.resize(size.x * size.z)
	heights.fill(-1)
	# Surface Resources are often mostly air. PackedByteArray.find() scans in
	# native code, so visiting occupied palette entries beats a GDScript Y walk.
	# Dense volumes and large palettes retain the predictable column traversal.
	var occupied := values.size() - values.count(0)
	var palette_limit := clampi(maximum_palette_index, 0, 255)
	if palette_limit >= 1 and palette_limit <= 32 and occupied * 3 <= values.size():
		var layer_size := size.x * size.z
		for palette_index in range(1, palette_limit + 1):
			var index := values.find(palette_index)
			while index >= 0:
				var column := index % layer_size
				heights[column] = maxi(
					heights[column], floori(float(index) / float(layer_size))
				)
				index = values.find(palette_index, index + 1)
		return heights
	for z in size.z:
		for x in size.x:
			heights[x + z * size.x] = top_filled_y(values, size, x, z)
	return heights


static func build_column_heights_into(
	values: PackedByteArray,
	size: Vector3i,
	maximum_palette_index: int,
	output: Dictionary,
) -> void:
	## WorkerThreadPool actions do not return values. This dedicated entrypoint
	## publishes exactly once; the main thread reads it only after task completion.
	output["heights"] = column_heights(values, size, maximum_palette_index)


static func refresh_column_heights(
	heights: PackedInt32Array,
	values: PackedByteArray,
	size: Vector3i,
	changed_indices := PackedInt32Array(),
	maximum_palette_index := 255,
) -> PackedInt32Array:
	if heights.size() != size.x * size.z or changed_indices.is_empty():
		return column_heights(values, size, maximum_palette_index)
	var touched := {}
	var layer_size := size.x * size.z
	for index in changed_indices:
		touched[int(index) % layer_size] = true
	for raw_column_index in touched:
		var column_index := int(raw_column_index)
		var x := column_index % size.x
		var z := floori(float(column_index) / float(size.x))
		heights[column_index] = top_filled_y(values, size, x, z)
	return heights


static func top_filled_y(values: PackedByteArray, size: Vector3i, x: int, z: int) -> int:
	if x < 0 or z < 0 or x >= size.x or z >= size.z:
		return -1
	for y in range(size.y - 1, -1, -1):
		if values[VoxMesher.cell_index(x, y, z, size.x, size.z)] != 0:
			return y
	return -1
