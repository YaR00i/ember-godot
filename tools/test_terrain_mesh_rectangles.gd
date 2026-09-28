extends SceneTree
## Checks the derived mesh against the authored columns, including later detail edits.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")


func _initialize() -> void:
	var source := Terrain.new()
	source.width = 16
	source.depth = 16
	source.height_limit = 32
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.GREEN, Color.SADDLE_BROWN, Color.DEEP_SKY_BLUE, Color.YELLOW])
	var count := source.width * source.depth
	for channel in ["heights", "top_materials", "base_materials", "cap_depths", "water_levels", "water_materials"]:
		var data: Variant = source.get(channel)
		data.resize(count)
		source.set(channel, data)
	for z in source.depth:
		for x in source.width:
			var index := x + z * source.width
			source.heights[index] = 12 if x >= 3 and x < 13 and z >= 3 and z < 13 else 8
			source.top_materials[index] = 1
			source.base_materials[index] = 2
			source.cap_depths[index] = 2
			if x < 10 and z < 3:
				source.heights[index] = 4
				source.water_levels[index] = 8
				source.water_materials[index] = 3
	source.heights[6 + 7 * source.width] = 13
	source.top_materials[6 + 7 * source.width] = 4
	source.heights[4 + source.width] = 6
	source.water_materials[8 + source.width] = 4
	source.column_material_overrides[6 + 7 * source.width] = {11: 4}
	if not _verify_mesh(source):
		quit(1)
		return
	# A later fine brush can split a former large rectangle without changing
	# the map format or any neighbouring column.
	source.heights[5 + 5 * source.width] = 16
	source.top_materials[5 + 5 * source.width] = 2
	if not _verify_mesh(source):
		quit(1)
		return
	if not _verify_grouped_surface():
		quit(1)
		return
	if not _verify_grouped_seam():
		quit(1)
		return
	print("TERRAIN_MESH_RECTANGLES ground=ok water=ok detail=ok grouped_8=ok seam=ok collision_source=ok")
	quit()


func _verify_grouped_surface() -> bool:
	var source := Terrain.new()
	source.width = 16
	source.depth = 16
	source.height_limit = 32
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.GREEN, Color.SADDLE_BROWN, Color.DEEP_SKY_BLUE, Color.YELLOW])
	var count := source.width * source.depth
	for channel in ["heights", "top_materials", "base_materials", "cap_depths", "water_levels", "water_materials"]:
		var data: Variant = source.get(channel)
		data.resize(count)
		source.set(channel, data)
	for z in source.depth:
		for x in source.width:
			var index := x + z * source.width
			var group := x / 8 + z / 8 * 2
			source.heights[index] = [8, 12, 4, 16][group]
			source.top_materials[index] = 4 if group == 3 else 1
			source.base_materials[index] = 2
			source.cap_depths[index] = 2
			if group == 2:
				source.water_levels[index] = 8
				source.water_materials[index] = 3
	var grouped: Dictionary = MeshBuilder.build_tile(source, 0, 0, 16)
	if not bool(grouped.get("grouped_8", false)) or not _verify_mesh(source):
		return _fail("coarse grouped terrain did not preserve the surface")
	source.heights[6 + 7 * source.width] = 9
	var detailed: Dictionary = MeshBuilder.build_tile(source, 0, 0, 16)
	if bool(detailed.get("grouped_8", false)) or not _verify_mesh(source):
		return _fail("fine detail did not fall back to exact column geometry")
	source.heights[6 + 7 * source.width] = 8
	source.column_material_overrides[6 + 7 * source.width] = {6: 4}
	if bool(MeshBuilder.build_tile(source, 0, 0, 16).get("grouped_8", false)) or not _verify_mesh(source):
		return _fail("side material override did not use exact geometry")
	return true


func _verify_grouped_seam() -> bool:
	var source := Terrain.new()
	source.width = 24
	source.depth = 16
	source.height_limit = 32
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.GREEN, Color.SADDLE_BROWN])
	var count := source.width * source.depth
	for channel in ["heights", "top_materials", "base_materials", "cap_depths", "water_levels", "water_materials"]:
		var data: Variant = source.get(channel)
		data.resize(count)
		source.set(channel, data)
	for z in source.depth:
		for x in source.width:
			var index := x + z * source.width
			source.heights[index] = 12 if x >= 8 and x < 16 else 8
			source.top_materials[index] = 1
			source.base_materials[index] = 2
			source.cap_depths[index] = 2
	# A full-height neighbouring stripe permits one 8-wide side quad.
	var grouped: Dictionary = MeshBuilder.build_tile(source, 0, 0, 16)
	if not bool(grouped.get("grouped_8", false)):
		return _fail("uniform tile seam did not use grouped geometry")
	var ground := grouped.terrain as ArrayMesh
	if _sample_side(ground, 15, 4, 9, 1).is_empty():
		return _fail("grouped tile omitted its side at the next tile")
	# One detailed column across the seam must force exact side heights here.
	source.heights[16 + 4 * source.width] = 11
	var exact: Dictionary = MeshBuilder.build_tile(source, 0, 0, 16)
	if bool(exact.get("grouped_8", false)):
		return _fail("detailed neighbouring stripe did not use exact seam geometry")
	ground = exact.terrain as ArrayMesh
	if not _sample_side(ground, 15, 4, 9, 1).is_empty() or _sample_side(ground, 15, 4, 11, 1).is_empty() or _sample_side(ground, 15, 5, 9, 1).is_empty():
		return _fail("detailed neighbouring seam has the wrong side heights")
	if exact.collision_faces != ground.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		return _fail("seam collision differs from visible terrain")
	return true


func _verify_mesh(source: Terrain) -> bool:
	if not source.validation_errors().is_empty():
		return _fail("invalid terrain fixture")
	var generated: Dictionary = MeshBuilder.build_tile(source, 0, 0, 16)
	if generated.uniform_dry:
		return _fail("expected the mixed terrain path")
	var ground := generated.terrain as ArrayMesh
	var water := generated.water as ArrayMesh
	if generated.collision_faces != ground.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		return _fail("collision and visual terrain have different faces")
	for z in source.depth:
		for x in source.width:
			var index := x + z * source.width
			for offset in [Vector2(0.23, 0.37), Vector2(0.63, 0.19)]:
				var point: Vector2 = Vector2(x, z) + offset
				var top := _sample_horizontal(ground, point)
				if top.is_empty():
					return _fail("missing ground at %s" % point)
				for face in top:
					if not is_equal_approx(face.height, float(source.heights[index])) or not (face.color as Color).is_equal_approx(source.palette[source.top_materials[index]]):
						return _fail("wrong ground height or colour at %s" % point)
				var wet := source.water_levels[index] > source.heights[index] and source.water_materials[index] > 0
				var surface := _sample_horizontal(water, point)
				if (not surface.is_empty()) != wet:
					return _fail("wrong water coverage at %s" % point)
				if wet:
					for face in surface:
						if not is_equal_approx(face.height, float(source.water_levels[index]) + 0.02) or not (face.color as Color).is_equal_approx(source.palette[source.water_materials[index]]):
							return _fail("wrong water height or colour at %s" % point)
						if not is_equal_approx(face.depth, (float(clampi(source.water_levels[index] - source.heights[index], 1, 4)) - 0.5) / 4.0):
							return _fail("wrong water depth band at %s" % point)
			for direction in 4:
				var low := source.heights[index - 1] if direction == 0 and x > 0 else source.heights[index + 1] if direction == 1 and x + 1 < source.width else source.heights[index - source.width] if direction == 2 and z > 0 else source.heights[index + source.width] if direction == 3 and z + 1 < source.depth else 0
				for y in range(low, source.heights[index]):
					var hits := _sample_side(ground, x, z, y, direction)
					if hits.is_empty():
						return _fail("missing side at (%d,%d,%d), direction %d" % [x, y, z, direction])
					var cap_start := maxi(0, source.heights[index] - source.cap_depths[index])
					var material: int = int((source.column_material_overrides[index] as Dictionary).get(y, source.top_materials[index] if y >= cap_start else source.base_materials[index])) if source.column_material_overrides.has(index) else int(source.top_materials[index] if y >= cap_start else source.base_materials[index])
					for color in hits:
						if not (color as Color).is_equal_approx(source.palette[material]):
							return _fail("wrong side colour at (%d,%d,%d), direction %d" % [x, y, z, direction])
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false


func _sample_horizontal(mesh: ArrayMesh, point: Vector2) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if mesh.get_surface_count() == 0:
		return hits
	var arrays := mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	for i in range(0, vertices.size(), 3):
		if normals[i].dot(Vector3.UP) < 0.999:
			continue
		var a := Vector2(vertices[i].x, vertices[i].z)
		var b := Vector2(vertices[i + 1].x, vertices[i + 1].z)
		var c := Vector2(vertices[i + 2].x, vertices[i + 2].z)
		if _inside(point, a, b, c):
			hits.append({"height": vertices[i].y, "color": colors[i], "depth": uvs[i].x})
	return hits


func _sample_side(mesh: ArrayMesh, x: int, z: int, y: int, direction: int) -> Array[Color]:
	var hits: Array[Color] = []
	var arrays := mesh.surface_get_arrays(0)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var expected_normal := Vector3.LEFT if direction == 0 else Vector3.RIGHT if direction == 1 else Vector3.FORWARD if direction == 2 else Vector3.BACK
	var plane := float(x if direction == 0 else x + 1 if direction == 1 else z if direction == 2 else z + 1)
	var point := Vector2(float(z if direction < 2 else x) + 0.23, float(y) + 0.37)
	for i in range(0, vertices.size(), 3):
		if normals[i].dot(expected_normal) < 0.999:
			continue
		var actual_plane := vertices[i].x if direction < 2 else vertices[i].z
		if not is_equal_approx(actual_plane, plane):
			continue
		var a := Vector2(vertices[i].z if direction < 2 else vertices[i].x, vertices[i].y)
		var b := Vector2(vertices[i + 1].z if direction < 2 else vertices[i + 1].x, vertices[i + 1].y)
		var c := Vector2(vertices[i + 2].z if direction < 2 else vertices[i + 2].x, vertices[i + 2].y)
		if _inside(point, a, b, c):
			hits.append(colors[i])
	return hits


func _inside(point: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var ab := (b - a).cross(point - a)
	var bc := (c - b).cross(point - b)
	var ca := (a - c).cross(point - c)
	return not ((ab < -0.00001 or bc < -0.00001 or ca < -0.00001) and (ab > 0.00001 or bc > 0.00001 or ca > 0.00001))
