@tool
extends RefCounted
## Pure ownership operations. Geometry is never restored from historical data.

static func stroke(source: EmberVoxelModelResource, before: PackedByteArray, after: PackedByteArray, active: int, indices: PackedInt32Array) -> PackedInt32Array:
	var owners := source.voxel_part_ids.duplicate()
	if owners.is_empty():
		return owners
	active = clampi(active, 0, source.merge_parts.size())
	for index in indices:
		if index < 0 or index >= after.size():
			continue
		if after[index] == 0:
			owners[index] = 0
		elif before[index] == 0:
			owners[index] = active
	return owners

static func remap(source: EmberVoxelModelResource, mapping: Dictionary, count: int, retain := false) -> PackedInt32Array:
	if source.voxel_part_ids.is_empty():
		return PackedInt32Array()
	var result := source.voxel_part_ids.duplicate() if retain else PackedInt32Array()
	result.resize(count)
	for index in mapping:
		result[mapping[index]] = source.voxel_part_ids[index]
	return result
