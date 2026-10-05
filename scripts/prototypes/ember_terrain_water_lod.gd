extends RefCounted
## Far indices for the existing indexed water mesh. Preserve shallow water,
## shader flags, depth/color transitions and every one-metre patch boundary.
## Limiting triangle spans keeps shader-displaced waves sampled across a tile.

const SharedLOD = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
const MIN_INDICES := 96
const PATCH_SIZE := 16.0 # One metre, in source units.
const MIN_DEPTH := 0.25 # One metre of the four-metre depth metadata range.
const MIN_ERROR := 8.0 # Dynamic wave sampling floor; planar static error is zero.

static func _inside_patch(vertices: PackedVector3Array, indices: PackedInt32Array, offset: int, bounds: Rect2i) -> bool:
	var center := (vertices[indices[offset]] + vertices[indices[offset + 1]] + vertices[indices[offset + 2]]) / 3.0
	var origin := Vector2(floorf(center.x / PATCH_SIZE), floorf(center.z / PATCH_SIZE)) * PATCH_SIZE
	for j in 3:
		var p := vertices[indices[offset + j]]
		if p.x <= origin.x or p.x >= origin.x + PATCH_SIZE or p.z <= origin.y or p.z >= origin.y + PATCH_SIZE: return false
		if p.x <= bounds.position.x or p.x >= bounds.end.x or p.z <= bounds.position.y or p.z >= bounds.end.y: return false
	return true

static func _constant_metadata(colors: PackedColorArray, uvs: PackedVector2Array, indices: PackedInt32Array, offset: int) -> bool:
	var first := indices[offset]
	if uvs[first].y != 0.0 or colors[first].a <= MIN_DEPTH: return false
	for j in range(1, 3):
		var next := indices[offset + j]
		if colors[next] != colors[first] or uvs[next] != uvs[first]: return false
	return true

static func build(input: Array, bounds: Rect2i) -> Dictionary:
	var started := Time.get_ticks_usec()
	var base: PackedInt32Array = input[Mesh.ARRAY_INDEX] if input[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var result := {"cpu_us": 0, "base_indices": base.size(), "far_indices": base.size(), "levels": 0, "extra_index_bytes": 0}
	var vertices: PackedVector3Array = input[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = input[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = input[Mesh.ARRAY_TEX_UV]
	var inside := PackedInt32Array()
	var protected := PackedInt32Array()
	for i in range(0, base.size(), 3):
		if _constant_metadata(colors, uvs, base, i) and _inside_patch(vertices, base, i, bounds):
			for j in 3: inside.append(base[i + j])
		else:
			for j in 3: protected.append(base[i + j])
	if inside.size() >= MIN_INDICES:
		var arrays := input.duplicate()
		arrays[Mesh.ARRAY_INDEX] = inside
		var importer := ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		importer.generate_lods(91.0, 0.0, [])
		var border := SharedLOD.boundary(vertices, inside)
		var lods := {}
		var previous_count := base.size()
		for level in importer.get_surface_lod_count(0):
			var indices := importer.get_surface_lod_indices(0, level)
			var count := indices.size() + protected.size()
			if count > base.size() * 0.85 or count >= previous_count: continue
			if SharedLOD.boundary(vertices, indices) != border: continue
			var valid := true
			for i in range(0, indices.size(), 3):
				if not _constant_metadata(colors, uvs, indices, i) or not _inside_patch(vertices, indices, i, bounds):
					valid = false
					break
			if not valid: continue
			var error := maxf(MIN_ERROR, importer.get_surface_lod_size(0, level))
			# Protected faces retain their relative draw order (walls before sheet).
			indices.append_array(protected)
			# Store one useful far level, rather than several almost identical
			# planar levels with a large additional memory cost.
			lods = {error: indices}
			previous_count = count
			result.extra_index_bytes = indices.size() * 4
		if not lods.is_empty():
			arrays[Mesh.ARRAY_INDEX] = base
			result.arrays = arrays
			result.lods = lods
			result.levels = lods.size()
			result.far_indices = previous_count
	result.cpu_us = Time.get_ticks_usec() - started
	return result
