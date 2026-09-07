class_name EmberVoxelLight
extends RefCounted
## Emissive voxel centroid + shadow-skip mask.
## Same index as JOI `voxelIndex` / `summarizeVoxelEmissive`: x + z*sx + y*sx*sz.
## Window glow cubes must not occlude the Omni sitting in the chamber.


static func summarize(model: Dictionary) -> Dictionary:
	var size := VoxMesher.ember_grid_size(model)
	var em: Array = model.get("emissive", [])
	var n := size.x * size.y * size.z
	if n < 1 or em.size() != n:
		return {}
	var count := 0
	var weight := 0.0
	var cx := 0.0
	var cy := 0.0
	var cz := 0.0
	for y in size.y:
		for z in size.z:
			for x in size.x:
				var i := VoxMesher.cell_index(x, y, z, size.x, size.z)
				var amt := int(em[i])
				if amt <= 0:
					continue
				var w := float(amt) / 255.0
				count += 1
				weight += w
				cx += (float(x) + 0.5) * w
				cy += (float(y) + 0.5) * w
				cz += (float(z) + 0.5) * w
	if count <= 0 or weight <= 0.0:
		return {}
	return {
		"count": count,
		"weight": weight,
		"cx": cx / weight,
		"cy": cy / weight,
		"cz": cz / weight,
	}


static func skip_mask(model: Dictionary, size: Vector3i) -> PackedByteArray:
	var n := size.x * size.y * size.z
	var em: Array = model.get("emissive", [])
	var empty := PackedByteArray()
	if n < 1 or em.size() != n:
		return empty
	var skip := PackedByteArray()
	skip.resize(n)
	skip.fill(0)
	var any := false
	for i in n:
		if int(em[i]) > 0:
			skip[i] = 1
			any = true
	if not any:
		return empty
	return skip


static func local_from_cell(
	inner_pos: Vector3,
	cx: float,
	cy: float,
	cz: float,
	voxel_size: float,
) -> Vector3:
	return inner_pos + Vector3(cx, cy, cz) * voxel_size


static func world_from_cell(
	root: Node3D,
	inner_pos: Vector3,
	cx: float,
	cy: float,
	cz: float,
	voxel_size: float,
) -> Vector3:
	return root.position + root.basis * local_from_cell(inner_pos, cx, cy, cz, voxel_size)
