extends SceneTree

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Builder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const LOD = preload("res://scripts/prototypes/ember_terrain_water_lod.gd")
const SharedLOD = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")

func _initialize() -> void: _run.call_deferred()

func fixture() -> Terrain:
	var source := Terrain.new()
	source.height_limit = 192
	source.width = 80
	source.depth = 64
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.AQUA, Color.BLUE])
	for channel in Terrain.Sections.CHANNELS:
		var data = PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray()
		data.resize(source.width * source.depth)
		data.fill(8 if channel == "heights" else 128 if channel == "water_levels" else 2 if channel == "water_materials" else 1 if channel in ["top_materials", "base_materials"] else 4)
		source.set(channel, data)
	for z in source.depth:
		for x in source.width:
			var i := x + z * source.width
			if x < 8: source.heights[i] = 120 # Shallow shore stays exact.
			if x >= 24 and x < 32 and z >= 24 and z < 32: source.heights[i] = 144 # Hole/island.
			if x >= 64:
				source.water_levels[i] = 136
				source.water_materials[i] = 3
	assert(source.validation_errors().is_empty())
	return source

func verify(input: Array, bounds: Rect2i) -> int:
	var result := LOD.build(input, bounds)
	if result.levels == 0: return 0
	assert(result.levels == 1 and result.far_indices <= result.base_indices * .85)
	assert(result.arrays == input, "near water arrays/index order changed")
	var vertices: PackedVector3Array = input[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = input[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = input[Mesh.ARRAY_TEX_UV]
	var base: PackedInt32Array = input[Mesh.ARRAY_INDEX]
	var protected := PackedInt32Array()
	for i in range(0, base.size(), 3):
		if not LOD._inside_patch(vertices, base, i, bounds) or not LOD._constant_metadata(colors, uvs, base, i):
			for j in 3: protected.append(base[i + j])
	for error: float in result.lods:
		assert(error >= LOD.MIN_ERROR)
		var far: PackedInt32Array = result.lods[error]
		assert(SharedLOD.boundary(vertices, far) == SharedLOD.boundary(vertices, base), "far water opened a seam/hole")
		assert(far.slice(far.size() - protected.size()) == protected, "shore/wall/swash/sheet triangle order changed")
		for i in range(0, far.size() - protected.size(), 3):
			assert(LOD._inside_patch(vertices, far, i, bounds))
			assert(LOD._constant_metadata(colors, uvs, far, i))
	return result.base_indices - result.far_indices

func settle(projection: TerrainProjection) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while projection.pending_tile_count() > 0 or projection.pending_runtime_lod_count() > 0:
		assert(Time.get_ticks_msec() < deadline)
		await process_frame

func _run() -> void:
	var saved := 0
	var source := fixture()
	var original := source.working_copy()
	for document: Terrain in [source, source.sectioned_copy()]:
		for x in [0, 64]:
			var sheet := {"vertices": PackedVector3Array([Vector3(20, 128, 20), Vector3(20, 4, 20), Vector3(24, 4, 20)]), "uvs": PackedVector2Array([Vector2(0, 3), Vector2(0, 4), Vector2(1, 4)])}
			var swash := PackedVector4Array([Vector4(24, 30, 128, 0), Vector4(24, 31, 128, 0)])
			var generated := Builder.build_tile(document, x, 0, 64, 8, true, swash if x == 0 else PackedVector4Array(), sheet if x == 0 else {}, true, true)
			saved += verify(generated.water.surface_get_arrays(0), Rect2i(x, 0, mini(64, source.width - x), 64))
	assert(saved > 0, "fixture did not exercise far water")
	var projection := TerrainProjection.new()
	projection.runtime_geometry_cache_enabled = false
	projection.water_mesh_step = 8
	projection.water_volume_sides = true
	root.add_child(projection)
	assert(projection.open_document(source))
	await settle(projection)
	var profile := projection.profile_snapshot()
	assert(profile.water_lod_tiles > 0 and profile.water_lod_saved_indices > 0 and profile.mesh_lod_worker_failures == 0)
	assert(source.same_terrain_data(original))
	var water: Mesh = projection._tiles[Vector2i.ZERO].get_node("Water").mesh
	var exact := Builder.build_tile(source, 0, 0, 64, 8, true, PackedVector4Array(), {}, true, true)
	assert(water.surface_get_arrays(0) == exact.water.surface_get_arrays(0))
	assert(projection._tiles[Vector2i.ZERO].get_node("Water").lod_bias == TerrainProjection.RUNTIME_WATER_LOD_BIAS)
	assert(projection._tiles[Vector2i.ZERO].get_node("GroundPhysics/Shape").shape.get_faces() == exact.collision_faces)
	var camera := Camera3D.new()
	root.add_child(camera)
	for point in [Vector3(32, 80, 32), Vector3(32, 800, 800), Vector3(32, 80, 32)]:
		camera.position = point
		await process_frame
	assert(projection.profile_snapshot().water_lod_jobs == profile.water_lod_jobs and not projection.is_processing())
	# A new water field may remesh without changing column revision. Old far
	# indices must never overwrite this new source mesh.
	var revision := projection._column_revision
	projection._rebuild_tile(Vector2i.ZERO)
	projection.set_process(true)
	await settle(projection)
	assert(projection._column_revision == revision)
	assert(projection._tiles[Vector2i.ZERO].get_node("Water").mesh != water)
	assert(projection._tiles[Vector2i.ZERO].get_node("Water").mesh.surface_get_arrays(0) == exact.water.surface_get_arrays(0))
	projection._rebuild_tile(Vector2i.ZERO)
	projection.set_process(true)
	var stale_deadline := Time.get_ticks_msec() + 10000
	while not projection._mesh_lod_thread.is_started():
		assert(Time.get_ticks_msec() < stale_deadline)
		await process_frame
	# Replace the source mesh before the previous worker result can publish.
	projection._rebuild_tile(Vector2i.ZERO)
	projection.set_process(true)
	await settle(projection)
	assert(projection.profile_snapshot().water_lod_stale_results > 0)
	# Cancel while the shared worker holds only CPU arrays and Resource refs.
	projection._rebuild_tile(Vector2i.ZERO)
	projection.set_process(true)
	var deadline := Time.get_ticks_msec() + 10000
	while not projection._mesh_lod_thread.is_started():
		assert(Time.get_ticks_msec() < deadline)
		await process_frame
	projection.free()
	camera.free()
	var disabled := TerrainProjection.new()
	disabled.runtime_geometry_cache_enabled = false
	disabled.runtime_water_lod_enabled = false
	disabled.water_mesh_step = 8
	disabled.water_volume_sides = true
	root.add_child(disabled)
	assert(disabled.open_document(source))
	await settle(disabled)
	assert(disabled.profile_snapshot().water_lod_jobs == 0)
	disabled.free()
	print("WATER_LOD PASS near/order/patches/seams/holes/depth/material/wall/swash/sheet/physics/camera/remesh/stale/cancel/disabled saved_indices=", saved)
	quit()
