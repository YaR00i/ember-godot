extends SceneTree

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Builder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const LOD = preload("res://scripts/prototypes/ember_terrain_ground_lod.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")

func _initialize() -> void: _run.call_deferred()

func fixture() -> Terrain:
	var source := Terrain.new()
	source.width = 128
	source.depth = 64
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.GREEN, Color.SADDLE_BROWN, Color.BLUE])
	for channel in Terrain.Sections.CHANNELS:
		var data = PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray()
		data.resize(source.width * source.depth)
		data.fill(1 if channel == "top_materials" else 2 if channel == "base_materials" else 4 if channel == "cap_depths" else 0)
		source.set(channel, data)
	var noise := FastNoiseLite.new()
	noise.seed = 0
	noise.frequency = 0.03
	for z in source.depth:
		for x in source.width:
			var index := x + z * source.width
			source.heights[index] = 32 + roundi(noise.get_noise_2d((x / 8) * 8, (z / 8) * 8) * 8) * 4
			source.top_materials[index] = 1 if source.heights[index] > 24 else 3
			if x >= 120 and z < 8:
				source.water_levels[index] = 80
				source.water_materials[index] = 3
	assert(source.validation_errors().is_empty())
	return source

func _settle(projection: TerrainProjection) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while (projection.pending_tile_count() > 0 or projection.pending_runtime_lod_count() > 0) and Time.get_ticks_msec() < deadline: await process_frame
	assert(projection.pending_tile_count() == 0 and projection.pending_runtime_lod_count() == 0)

func _run() -> void:
	var source := fixture()
	var original := source.working_copy()
	var mesh := Builder.build_tile(source, 0, 0, 64, 0, false, PackedVector4Array(), {}, true)
	var arrays: Array = mesh.terrain.surface_get_arrays(0)
	var derived := LOD.build(arrays, Rect2i(0, 0, 64, 64))
	assert(derived.levels > 0, "fixture did not exercise LOD")
	assert(derived.arrays[Mesh.ARRAY_VERTEX] == arrays[Mesh.ARRAY_VERTEX])
	assert(derived.arrays[Mesh.ARRAY_NORMAL] == arrays[Mesh.ARRAY_NORMAL])
	assert(derived.arrays[Mesh.ARRAY_COLOR] == arrays[Mesh.ARRAY_COLOR])
	assert(derived.arrays[Mesh.ARRAY_TEX_UV] == arrays[Mesh.ARRAY_TEX_UV])
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var base: PackedInt32Array = derived.arrays[Mesh.ARRAY_INDEX]
	for i in base.size(): assert(base[i] == i)
	var boundary := LOD._boundary(vertices, base)
	for indices: PackedInt32Array in derived.lods.values():
		assert(indices.size() < base.size())
		assert(LOD._single_material_triangles(arrays[Mesh.ARRAY_COLOR], indices))
		assert(LOD._boundary(vertices, indices) == boundary)
		var kept := {}
		for i in range(0, indices.size(), 3): kept[[indices[i], indices[i + 1], indices[i + 2]]] = true
		for i in range(0, base.size(), 3):
			var border_face := false
			for j in 3:
				var point := vertices[i + j]
				border_face = border_face or point.x == 0 or point.x == 64 or point.z == 0 or point.z == 64
			if border_face: assert(kept.has([i, i + 1, i + 2]))
	var projection := TerrainProjection.new()
	projection.runtime_geometry_cache_enabled = false
	root.add_child(projection)
	assert(projection.open_document(source))
	await _settle(projection)
	assert(source.same_terrain_data(original))
	var profile := projection.profile_snapshot()
	assert(profile.ground_lod_tiles > 0 and profile.runtime_mesh_ready_ms >= 0)
	var ground: Mesh = projection._tiles[Vector2i.ZERO].get_node("Ground").mesh
	assert(projection._tiles[Vector2i.ZERO].get_node("Ground").lod_bias == TerrainProjection.RUNTIME_GROUND_LOD_BIAS)
	assert(projection._tiles[Vector2i.ZERO].get_node("Water").lod_bias == TerrainProjection.RUNTIME_WATER_LOD_BIAS)
	assert(ground.get_faces() == mesh.collision_faces) # Near geometry is exact.
	var physical: ConcavePolygonShape3D = projection._tiles[Vector2i.ZERO].get_node("GroundPhysics/Shape").shape
	assert(physical.get_faces() == mesh.collision_faces)
	var water: Mesh = projection._tiles[Vector2i.ZERO].get_node("Water").mesh
	assert(water.get_surface_count() == mesh.water.get_surface_count())
	var right := Builder.build_tile(source, 64, 0, 64, 0, false, PackedVector4Array(), {}, true, true)
	var wet: Mesh = projection._tiles[Vector2i(1, 0)].get_node("Water").mesh
	assert(wet.surface_get_arrays(0) == right.water.surface_get_arrays(0))
	var camera := Camera3D.new()
	root.add_child(camera)
	for position in [Vector3(32, 80, 32), Vector3(32, 800, 800), Vector3(32, 80, 32)]:
		camera.position = position
		await process_frame
	assert(projection.profile_snapshot().ground_lod_jobs == profile.ground_lod_jobs)
	assert(projection.profile_snapshot().tile_builds == profile.tile_builds)
	assert(projection._tiles[Vector2i.ZERO].get_node("GroundPhysics/Shape").shape == physical)
	# Existing non-LOD path stays available, and cancellation cannot retain an
	# old mesh or lock/free the projection Node while a worker is running.
	var replacement := source.working_copy()
	replacement.heights[32 + 32 * source.width] += 8
	assert(projection.open_document(replacement))
	var cancellation_deadline := Time.get_ticks_msec() + 10000
	while not projection._mesh_lod_thread.is_started() and Time.get_ticks_msec() < cancellation_deadline: await process_frame
	assert(projection._mesh_lod_thread.is_started(), "cancellation fixture did not start the worker")
	projection.free()
	camera.free()
	var exact := TerrainProjection.new()
	exact.runtime_geometry_cache_enabled = false
	exact.runtime_ground_lod_enabled = false
	root.add_child(exact)
	assert(exact.open_document(source))
	await _settle(exact)
	assert(exact.profile_snapshot().ground_lod_jobs == 0)
	exact.free()
	print("GROUND_LOD PASS levels=", derived.levels, " base=", derived.base_indices, " far=", derived.far_indices, " exact_near=ok border=ok material=ok collision=ok camera_no_rebuild=ok cancel=ok profile=", profile)
	quit()
