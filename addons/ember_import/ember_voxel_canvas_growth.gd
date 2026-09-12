@tool
extends RefCounted
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
## Grow-only remapping; XZ centering matches the existing prefab adapter.
static func plan(source: EmberVoxelModelResource, size: Vector3i) -> Dictionary:
	if source == null or not source.validation_errors().is_empty():
		return {"error": "Исходная модель не прошла проверку."}
	var old := source.grid_size()
	var density := source.normalized_density()
	if size == old:
		return {"error": "Укажите больший размер холста."}
	if size.x < old.x or size.y < old.y or size.z < old.z:
		return {"error": "Уменьшение холста не поддерживается: воксели не обрезаются."}
	if size.x % density != 0 or size.z % density != 0 or size.y > 8 * density or size.x > 256 or size.z > 256 or size.x * size.y * size.z > Shapes.MAX_CELLS:
		return {"error": "XZ должны быть кратны %d; высота до %d; всего до 524 288 ячеек." % [density, 8 * density]}
	if not source.surface_fill_levels.is_empty() or not source.surface_fill_materials.is_empty() or not source.surface_fill_palette.is_empty():
		return {"error": "Холст с водной заливкой пока нельзя расширить этой командой."}
	var offset := Vector3i((size.x - old.x) / 2, 0, (size.z - old.z) / 2)
	var mapping := PackedInt32Array()
	mapping.resize(source.voxels.size())
	for y in old.y:
		for z in old.z:
			for x in old.x:
				mapping[VoxMesher.cell_index(x, y, z, old.x, old.z)] = VoxMesher.cell_index(x + offset.x, y, z + offset.z, size.x, size.z)
	var properties := {"size_blocks": Vector3i(size.x / density, ceili(float(size.y) / density), size.z / density), "height_voxels": size.y}
	for channel in ["voxels", "emissive", "shine", "transparency", "transmittance", "collision_voxels"]:
		var before: PackedByteArray = source.get(channel)
		if before.is_empty():
			continue
		var after := PackedByteArray()
		after.resize(size.x * size.y * size.z)
		for index in before.size():
			after[mapping[index]] = before[index]
		properties[channel] = after
	var groups := source.voxel_groups.duplicate(true)
	if not source.voxel_part_ids.is_empty():
		var owners := PackedInt32Array()
		owners.resize(size.x * size.y * size.z)
		for index in mapping.size():
			owners[mapping[index]] = source.voxel_part_ids[index]
		properties.voxel_part_ids = owners
	for group in groups:
		var indices := PackedInt32Array()
		for index in group.get("indices", []):
			indices.append(mapping[index])
		group["indices"] = indices
	properties["voxel_groups"] = groups
	return {"properties": properties, "offset": offset, "size": size}
