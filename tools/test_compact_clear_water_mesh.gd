extends SceneTree
## A small fixture proves that the study's finer visual water mesh does not
## change terrain collision or the normal compact-water geometry.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := TerrainResource.new()
	source.width = 16
	source.depth = 16
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.AQUA])
	var count := source.width * source.depth
	source.heights.resize(count)
	source.top_materials.resize(count)
	source.top_materials.fill(1)
	source.base_materials.resize(count)
	source.base_materials.fill(1)
	source.cap_depths.resize(count)
	source.water_levels.resize(count)
	source.water_levels.fill(16)
	source.water_materials.resize(count)
	source.water_materials.fill(2)
	for z in source.depth:
		for x in source.width:
			source.heights[source.column_index(x, z)] = 8 if z < 8 else 4
	if not source.validation_errors().is_empty():
		_fail("fixture is invalid")
		return
	for fine_ground in [false, true]:
		if fine_ground:
			source.heights[source.column_index(3, 3)] = 7
		var normal := MeshBuilder.build_tile(source, 0, 0, 16)
		var zero := MeshBuilder.build_tile(source, 0, 0, 16, 0)
		var refined := MeshBuilder.build_tile(source, 0, 0, 16, 4)
		if normal.collision_faces != zero.collision_faces or normal.collision_faces != refined.collision_faces:
			_fail("visual water detail changed terrain collision")
			return
		if normal.water_vertices != zero.water_vertices or refined.water_vertices <= normal.water_vertices:
			_fail("default water geometry changed or study mesh was not refined")
			return
		var normal_water := normal.water as ArrayMesh
		var zero_water := zero.water as ArrayMesh
		var refined_water := refined.water as ArrayMesh
		if normal_water.surface_get_arrays(0) != zero_water.surface_get_arrays(0):
			_fail("omitted water step differs from explicit zero")
			return
		var arrays := refined_water.surface_get_arrays(0)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
		var depth_by_corner := {}
		var shallow := 1.0
		var deep := 0.0
		for index in vertices.size():
			var position := vertices[index]
			var depth := colors[index].a
			if depth_by_corner.has(position) and not is_equal_approx(float(depth_by_corner[position]), depth):
				_fail("a shared water corner has mismatched depth")
				return
			depth_by_corner[position] = depth
			shallow = minf(shallow, depth)
			deep = maxf(deep, depth)
		if shallow >= deep or shallow <= 0.0 or deep > 1.0:
			_fail("water depth metadata has no valid gradient")
			return
		var volume := MeshBuilder.build_tile(source, 0, 0, 16, 4, true)
		if volume.collision_faces != refined.collision_faces:
			_fail("visual water walls changed terrain collision")
			return
		var volume_arrays := (volume.water as ArrayMesh).surface_get_arrays(0)
		var volume_vertices := volume_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var volume_uvs := volume_arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
		var volume_colors := volume_arrays[Mesh.ARRAY_COLOR] as PackedColorArray
		var wall_vertices := 0
		var wall_rim := {}
		var top_rim := {}
		for vertex_index in volume_vertices.size():
			var vertex := volume_vertices[vertex_index]
			if volume_uvs[vertex_index].y > 0.5:
				wall_vertices += 1
				if is_equal_approx(volume_uvs[vertex_index].y, 1.0):
					wall_rim[vertex] = volume_colors[vertex_index].a
			else:
				top_rim[vertex] = volume_colors[vertex_index].a
		if wall_vertices != 16 * 4 * 6:
			_fail("water volume must close all four exposed edges once")
			return
		for rim in wall_rim:
			if not top_rim.has(rim):
				_fail("moving water wall rim does not meet top mesh")
				return
			if not is_equal_approx(float(wall_rim[rim]), float(top_rim[rim])):
				_fail("water wall rim depth color differs from the adjoining surface")
				return
	# A raised floor patch must not fragment one continuous water surface into
	# mismatched edge subdivisions. Those T-junctions open white slits after
	# the water shader moves the vertices.
	source.heights.fill(8)
	for z in range(3, 8):
		for x in range(3, 8):
			source.heights[source.column_index(x, z)] = 12
	var patch := MeshBuilder.build_tile(source, 0, 0, 16, 4)
	var patch_water := patch.water as ArrayMesh
	var patch_vertices := patch_water.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var junctions := _count_t_junctions(patch_vertices)
	if junctions > 0:
		_fail("continuous water has %d axis edge T-junctions above bathymetry" % junctions)
		return
	source.heights.fill(8)
	for z in source.depth:
		for x in source.width:
			if x < 2 + z / 2:
				source.heights[source.column_index(x, z)] = 16
	var shore := MeshBuilder.build_tile(source, 0, 0, 16, 4)
	var shore_water := shore.water as ArrayMesh
	var shore_vertices := shore_water.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	junctions = _count_t_junctions(shore_vertices)
	if junctions > 0:
		_fail("continuous shore has %d axis edge T-junctions" % junctions)
		return
	source.width = 32
	source.heights.resize(source.width * source.depth)
	source.heights.fill(8)
	source.top_materials.resize(source.width * source.depth)
	source.top_materials.fill(1)
	source.base_materials.resize(source.width * source.depth)
	source.base_materials.fill(1)
	source.cap_depths.resize(source.width * source.depth)
	source.water_levels.resize(source.width * source.depth)
	source.water_levels.fill(16)
	source.water_materials.resize(source.width * source.depth)
	source.water_materials.fill(2)
	for z in range(2, 9):
		for x in range(7, 12):
			source.heights[source.column_index(x, z)] = 12
	var left := MeshBuilder.build_tile(source, 0, 0, 16, 4).water as ArrayMesh
	var right := MeshBuilder.build_tile(source, 16, 0, 16, 4).water as ArrayMesh
	var left_seam := _seam_points(left, 16)
	var right_seam := _seam_points(right, 16)
	if left_seam.size() != 17 or left_seam != right_seam:
		_fail("neighbouring water tiles do not share every border vertex")
		return
	var volume_left := MeshBuilder.build_tile(source, 0, 0, 16, 4, true).water as ArrayMesh
	var volume_right := MeshBuilder.build_tile(source, 16, 0, 16, 4, true).water as ArrayMesh
	for tile in [volume_left, volume_right]:
		var tile_arrays := (tile as ArrayMesh).surface_get_arrays(0)
		var tile_vertices := tile_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var tile_uvs := tile_arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
		for vertex_index in range(0, tile_vertices.size(), 3):
			if (tile_uvs[vertex_index].y > 0.5
				and is_equal_approx(tile_vertices[vertex_index].x, 16.0)
				and is_equal_approx(tile_vertices[vertex_index + 1].x, 16.0)
				and is_equal_approx(tile_vertices[vertex_index + 2].x, 16.0)):
				_fail("volume wall appeared at an internal tile seam")
				return
	print("PASS compact clear water mesh: legacy geometry, collision, depth corners, watertight shore and tile seams")
	quit()


func _seam_points(mesh: ArrayMesh, seam_x: int) -> Dictionary:
	var found := {}
	for vertex in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		if is_equal_approx(vertex.x, float(seam_x)):
			found[roundi(vertex.z)] = true
	return found


func _count_t_junctions(vertices: PackedVector3Array) -> int:
	var unique := {}
	for vertex in vertices:
		unique[Vector2i(roundi(vertex.x), roundi(vertex.z))] = true
	var count := 0
	for index in range(0, vertices.size(), 3):
		for side in 3:
			var a := Vector2i(roundi(vertices[index + side].x), roundi(vertices[index + side].z))
			var b := Vector2i(roundi(vertices[index + (side + 1) % 3].x),
				roundi(vertices[index + (side + 1) % 3].z))
			if a.x == b.x:
				for z in range(mini(a.y, b.y) + 1, maxi(a.y, b.y)):
					if unique.has(Vector2i(a.x, z)):
						count += 1
			elif a.y == b.y:
				for x in range(mini(a.x, b.x) + 1, maxi(a.x, b.x)):
					if unique.has(Vector2i(x, a.y)):
						count += 1
	return count


func _fail(message: String) -> void:
	push_error("compact clear water mesh: " + message)
	quit(1)
