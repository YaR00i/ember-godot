extends RefCounted
## Private CPU derivation for the existing ground mesh. No scene, collision,
## water or authoring writes. ArrayMesh publication belongs to the projection.

const MIN_INDICES := 96
const MIN_ERROR := 1.0 # Source units (1/16 m), not a world-distance threshold.

const SharedLOD = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")

static func build(input: Array, bounds: Rect2i) -> Dictionary:
	var started := Time.get_ticks_usec()
	var vertices: PackedVector3Array = input[Mesh.ARRAY_VERTEX]
	var result := {"cpu_us": 0, "base_indices": vertices.size(), "far_indices": vertices.size(), "levels": 0, "extra_index_bytes": 0}
	if vertices.size() < MIN_INDICES:
		result.cpu_us = Time.get_ticks_usec() - started
		return result
	var colors: PackedColorArray = input[Mesh.ARRAY_COLOR]
	var inside := PackedInt32Array()
	var protected := PackedInt32Array()
	for i in range(0, vertices.size(), 3):
		var inner := true
		for j in 3:
			var point := vertices[i + j]
			inner = inner and point.x > bounds.position.x and point.x < bounds.end.x and point.z > bounds.position.y and point.z < bounds.end.y
		# Any face touching the outer tile border remains the exact original
		# triangle at every LOD. Adjacent tiles can choose levels independently.
		if inner:
			inside.append(i); inside.append(i + 1); inside.append(i + 2)
		else:
			protected.append(i); protected.append(i + 1); protected.append(i + 2)
	if inside.size() < MIN_INDICES:
		result.cpu_us = Time.get_ticks_usec() - started
		return result
	var arrays := input.duplicate()
	arrays[Mesh.ARRAY_INDEX] = inside
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Permit fine stair steps to simplify. Material boundaries and geometry
	# borders are validated below, rather than trusting decimation blindly.
	importer.generate_lods(91.0, 0.0, [])
	var border := _boundary(vertices, inside)
	var lods := {}
	var previous_error := 0.0
	var previous_count := vertices.size()
	for level in importer.get_surface_lod_count(0):
		var indices := importer.get_surface_lod_indices(0, level)
		var count := indices.size() + protected.size()
		if count > vertices.size() * 0.85 or count >= previous_count: continue
		if not _single_material_triangles(colors, indices): continue
		if _boundary(vertices, indices) != border: continue
		var error := maxf(MIN_ERROR, importer.get_surface_lod_size(0, level))
		error = maxf(error, previous_error * 1.5)
		indices.append_array(protected)
		lods[error] = indices
		previous_error = error
		previous_count = count
		result.extra_index_bytes += indices.size() * 4
	if not lods.is_empty():
		var base := PackedInt32Array()
		base.resize(vertices.size())
		for i in base.size(): base[i] = i
		arrays[Mesh.ARRAY_INDEX] = base
		result.arrays = arrays
		result.lods = lods
		result.levels = lods.size()
		result.far_indices = previous_count
		result.extra_index_bytes += base.size() * 4
	result.cpu_us = Time.get_ticks_usec() - started
	return result

static func _single_material_triangles(colors: PackedColorArray, indices: PackedInt32Array) -> bool:
	for i in range(0, indices.size(), 3):
		var slot := colors[indices[i]].a
		if not is_equal_approx(slot, colors[indices[i + 1]].a) or not is_equal_approx(slot, colors[indices[i + 2]].a): return false
	return true

static func _boundary(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	return SharedLOD.boundary(vertices, indices)
