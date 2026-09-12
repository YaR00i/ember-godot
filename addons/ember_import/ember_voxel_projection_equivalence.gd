extends RefCounted
## Strict indexed-triangle equivalence for explicit derived-data refresh only.
## Allows vertex reuse/order and the known voxel-unit adapter, not new geometry.

static func mesh_scale(old: ArrayMesh, expected: ArrayMesh, density: int) -> float:
	if old == null or expected == null or old.get_surface_count() != expected.get_surface_count(): return 0.0
	if old.get_blend_shape_count() > 0: return 0.0
	for factor in [1.0, float(density)]:
		var matches := true
		for surface in expected.get_surface_count():
			if old.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				matches = false
				break
			if old.surface_get_name(surface) != expected.surface_get_name(surface) or old.surface_get_material(surface) != expected.surface_get_material(surface):
				matches = false
				break
			if not _mesh_triangles(old.surface_get_arrays(surface), expected.surface_get_arrays(surface), factor):
				matches = false
				break
		if matches: return factor
	return 0.0

static func scaled_mesh(mesh: ArrayMesh, factor: float) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		for index in vertices.size(): vertices[index] *= factor
		arrays[Mesh.ARRAY_VERTEX] = vertices
		result.add_surface_from_arrays(mesh.surface_get_primitive_type(surface), arrays)
		result.surface_set_name(surface, mesh.surface_get_name(surface))
		result.surface_set_material(surface, mesh.surface_get_material(surface))
	return result

static func scaled_shape(shape: ConcavePolygonShape3D, factor: float) -> ConcavePolygonShape3D:
	var result := shape.duplicate() as ConcavePolygonShape3D
	var faces := shape.get_faces()
	for index in faces.size(): faces[index] *= factor
	result.set_faces(faces)
	return result

static func _mesh_triangles(old: Array, expected: Array, factor: float) -> bool:
	for slot in range(Mesh.ARRAY_MAX):
		if slot not in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX] and old[slot] != null and old[slot].size() > 0: return false
	var vertices: PackedVector3Array = old[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = old[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = old[Mesh.ARRAY_COLOR]
	if vertices.size() != normals.size() or vertices.size() != colors.size(): return false
	var wanted := _mesh_keys(expected, 1.0)
	var actual := _mesh_keys(old, factor)
	return not wanted.is_empty() and wanted == actual

static func _mesh_keys(arrays: Array, factor: float) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	if tangents.size() not in [0, vertices.size() * 4]: return {}
	if indices.size() == 0 or indices.size() % 3 != 0 or vertices.size() != normals.size() or vertices.size() != colors.size(): return {}
	var result := {}
	for first in range(0, indices.size(), 3):
		var tokens: Array[String] = []
		var bottom := true
		for offset in 3:
			var index := indices[first + offset]
			if index < 0 or index >= vertices.size(): return {}
			bottom = bottom and normals[index].is_equal_approx(Vector3.DOWN)
			var tangent := ""
			if not tangents.is_empty():
				tangent = ":%d,%d,%d,%d" % [roundi(tangents[index * 4] * 1000000.0), roundi(tangents[index * 4 + 1] * 1000000.0), roundi(tangents[index * 4 + 2] * 1000000.0), roundi(tangents[index * 4 + 3] * 1000000.0)]
			tokens.append(_vector_key(vertices[index] / factor) + ":" + _vector_key(normals[index]) + ":" + str(colors[index].to_rgba64()) + tangent)
		if bottom: tokens.sort() # Only the known old bottom winding is accepted.
		var key := _cycle_key(tokens)
		result[key] = int(result.get(key, 0)) + 1
	return result

static func faces_match(old: PackedVector3Array, expected: PackedVector3Array, factor: float) -> bool:
	if old.size() != expected.size() or expected.size() % 3 != 0: return false
	var wanted := {}
	var reversed_bottom := {}
	for first in range(0, expected.size(), 3):
		var tokens: Array[String] = [_vector_key(expected[first]), _vector_key(expected[first + 1]), _vector_key(expected[first + 2])]
		var key := _cycle_key(tokens)
		wanted[key] = int(wanted.get(key, 0)) + 1
		# Clockwise outward DOWN has an upward geometric cross product.
		var cross := (expected[first + 1] - expected[first]).cross(expected[first + 2] - expected[first])
		if cross.normalized().is_equal_approx(Vector3.UP): reversed_bottom[_cycle_key([tokens[0], tokens[2], tokens[1]])] = key
	for first in range(0, old.size(), 3):
		var key := _cycle_key([_vector_key(old[first] / factor), _vector_key(old[first + 1] / factor), _vector_key(old[first + 2] / factor)])
		if int(wanted.get(key, 0)) == 0: key = str(reversed_bottom.get(key, key))
		if int(wanted.get(key, 0)) == 0: return false
		wanted[key] -= 1
	return true

static func _cycle_key(tokens: Array[String]) -> String:
	var choices: Array[String] = [tokens[0] + "|" + tokens[1] + "|" + tokens[2], tokens[1] + "|" + tokens[2] + "|" + tokens[0], tokens[2] + "|" + tokens[0] + "|" + tokens[1]]
	choices.sort()
	return choices[0]

static func _vector_key(value: Vector3) -> String:
	return "%d,%d,%d" % [roundi(value.x * 1000000.0), roundi(value.y * 1000000.0), roundi(value.z * 1000000.0)]
