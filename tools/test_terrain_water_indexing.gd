extends SceneTree
## Exact runtime water storage: all triangles and their attribute order survive.
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Builder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")

func _initialize() -> void: _run.call_deferred()

func fixture(grouped: bool) -> Terrain:
	var source := Terrain.new()
	source.width = 80
	source.depth = 64
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.AQUA, Color.BLUE])
	for channel in Terrain.Sections.CHANNELS:
		var data = PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray()
		data.resize(source.width * source.depth)
		data.fill(8 if channel == "heights" else 32 if channel == "water_levels" else 2 if channel == "water_materials" else 1 if channel in ["top_materials", "base_materials"] else 4)
		source.set(channel, data)
	for z in source.depth:
		for x in source.width:
			var i := x + z * source.width
			var px := (x / 8) * 8 if grouped else x
			var pz := (z / 8) * 8 if grouped else z
			source.heights[i] = 8 + (px + pz) % 16
			if px >= 16 and px < 24 and pz > 16 and pz < 48: source.heights[i] = 48
			if px >= 56:
				source.water_levels[i] = 40
				source.water_materials[i] = 3
	assert(source.validation_errors().is_empty())
	return source

func same_surface(before: ArrayMesh, after: ArrayMesh) -> void:
	assert(before.get_surface_count() == after.get_surface_count())
	if before.get_surface_count() == 0: return
	var exact := before.surface_get_arrays(0)
	var indexed := after.surface_get_arrays(0)
	var indices: PackedInt32Array = indexed[Mesh.ARRAY_INDEX]
	assert(indices.size() == (exact[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
		for i in indices.size(): assert(exact[channel][i] == indexed[channel][indices[i]], "water attribute or transparent triangle order changed")

func _settle(projection: TerrainProjection) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while projection.pending_tile_count() > 0 or projection.pending_runtime_lod_count() > 0:
		assert(Time.get_ticks_msec() < deadline)
		await process_frame

func _run() -> void:
	var saved_vertices := 0
	for grouped in [false, true]:
		var dense := fixture(grouped)
		for source: Terrain in [dense, dense.sectioned_copy()]:
			var original := source.working_copy()
			for step in [0, 4, 8]:
				for sides in [false, true]:
					for x in [0, 64]:
						var before := Builder.build_tile(source, x, 0, 64, step, sides)
						var after := Builder.build_tile(source, x, 0, 64, step, sides, PackedVector4Array(), {}, false, true)
						assert(before.collision_faces == after.collision_faces)
						assert(before.terrain.surface_get_arrays(0) == after.terrain.surface_get_arrays(0))
						same_surface(before.water, after.water)
						saved_vertices += before.water_vertices - after.water_vertices
			var sheet := {"vertices": PackedVector3Array([Vector3(20, 32, 20), Vector3(20, 4, 20), Vector3(24, 4, 20)]), "uvs": PackedVector2Array([Vector2(0, 3), Vector2(0, 4), Vector2(1, 4)])}
			var swash := PackedVector4Array([Vector4(18, 30, 32, 0), Vector4(18, 31, 32, 0)])
			var exact := Builder.build_tile(source, 0, 0, 64, 8, true, swash, sheet)
			var indexed := Builder.build_tile(source, 0, 0, 64, 8, true, swash, sheet, false, true)
			same_surface(exact.water, indexed.water)
			assert(source.same_terrain_data(original))
	# Every build owns a new depth cache; a changed point cannot reuse stale depth.
	var source := fixture(false)
	var projection := TerrainProjection.new()
	projection.runtime_geometry_cache_enabled = false
	root.add_child(projection)
	assert(projection.open_document(source))
	await _settle(projection)
	var profile := projection.profile_snapshot()
	assert(profile.water_vertices < profile.water_source_vertices and profile.water_indices == profile.water_source_vertices)
	projection.free()
	source.heights[32 + source.width * 32] += 4
	var exact := Builder.build_tile(source, 0, 0, 64, 8, true)
	var indexed := Builder.build_tile(source, 0, 0, 64, 8, true, PackedVector4Array(), {}, false, true)
	same_surface(exact.water, indexed.water)
	var disabled := TerrainProjection.new()
	disabled.runtime_geometry_cache_enabled = false
	disabled.runtime_water_mesh_optimization = false
	root.add_child(disabled)
	assert(disabled.open_document(source))
	await _settle(disabled)
	assert(disabled.profile_snapshot().water_indices == 0)
	disabled.free()
	assert(saved_vertices > 0)
	print("WATER_INDEXING PASS dense/sectioned/grouped/fine/partial/seam/depth/material/wall/swash/sheet/order/physics/source/invalidation/runtime-policy saved_vertices=", saved_vertices)
	quit()
