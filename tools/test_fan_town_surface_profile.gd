extends SceneTree
## Read-only G3 preflight for fan_town. Canonical project content is hashed,
## while the generated Surface save/reopen probe stays under user://.

const MAP_ID := "fan_town"
const MAP_PATH := "res://../joi-conductor/content/ember/maps/fan_town.json"
const SCENE_PATH := "res://scenes/fan_town.tscn"
const PROFILE_PATH := "user://ember_fan_town_surface_profile.json"
const TEMP_SURFACE_PATH := "user://ember_fan_town_surface_profile.tres"
const PHYSICS_CHUNK_SIZE := 64
const VISUAL_CHUNK_SIZE := 16
const VISUAL_SAMPLES := 12
const SculptModel = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const SurfaceMesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const SurfacePhysics = preload("res://scripts/ember_voxel_surface_physics.gd")
const NativePreview = preload("res://scripts/ember_voxel_native_mesher.gd")
const ProjectionScript = preload("res://scripts/ember_voxel_surface_projection.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var errors: Array[String] = []
	var source_path := EmberPack.map_path(MAP_ID)
	var source_hash := FileAccess.get_sha256(source_path)
	var scene_hash := FileAccess.get_sha256(SCENE_PATH)
	var raw: Variant = EmberPack.parse_json_file(source_path)
	if typeof(raw) != TYPE_DICTIONARY:
		printerr("FAIL fan_town Surface profile: legacy map is unavailable")
		quit(1)
		return
	var map := raw as Dictionary
	var grid := EmberTileMesher.surface_grid(map)
	var legacy_started := Time.get_ticks_usec()
	var legacy_result := EmberTileMesher.build(map)
	var legacy_mesh_usec := Time.get_ticks_usec() - legacy_started
	var legacy_mesh := legacy_result.get("mesh") as ArrayMesh
	var legacy_shape_started := Time.get_ticks_usec()
	var legacy_shape := legacy_mesh.create_trimesh_shape() if legacy_mesh != null else null
	var legacy_shape_usec := Time.get_ticks_usec() - legacy_shape_started
	if legacy_shape == null:
		errors.append("legacy terrain did not produce collision")

	var seed_started := Time.get_ticks_usec()
	var surface := SculptModel.make_world_surface(
		MAP_ID,
		"FanTown",
		grid,
		EmberTileMesher.tileset_colors(str(map.get("tilesetId", "village_16"))),
	)
	var seed_usec := Time.get_ticks_usec() - seed_started
	surface.physical = true
	for validation_error in surface.validation_errors():
		errors.append("generated Surface: %s" % validation_error)
	_validate_height_parity(surface, grid, errors)
	var cached_heights_started := Time.get_ticks_usec()
	var cached_heights := SculptModel.column_heights(
		surface.voxels, surface.grid_size(), surface.palette.size() - 1
	)
	var cached_heights_usec := Time.get_ticks_usec() - cached_heights_started
	if cached_heights.size() != surface.grid_size().x * surface.grid_size().z:
		errors.append("transient full height cache has the wrong size")

	var visual_times := PackedInt64Array()
	var native_visual_times := PackedInt64Array()
	var native_visual_successes := 0
	var visual_triangles := 0
	var size := surface.grid_size()
	var visual_count_x := ceili(float(size.x) / float(VISUAL_CHUNK_SIZE))
	var visual_count_z := ceili(float(size.z) / float(VISUAL_CHUNK_SIZE))
	for sample_index in VISUAL_SAMPLES:
		var flat_index := floori(
			float(sample_index) * float(visual_count_x * visual_count_z - 1)
			/ float(maxi(1, VISUAL_SAMPLES - 1))
		)
		var chunk := Vector2i(flat_index % visual_count_x, floori(float(flat_index) / visual_count_x))
		var region_min := Vector3i(chunk.x * VISUAL_CHUNK_SIZE, 0, chunk.y * VISUAL_CHUNK_SIZE)
		var region_size := Vector3i(
			mini(VISUAL_CHUNK_SIZE, size.x - region_min.x),
			size.y,
			mini(VISUAL_CHUNK_SIZE, size.z - region_min.z),
		)
		var started := Time.get_ticks_usec()
		var mesh := SurfaceMesher.build_region(
			surface, region_min, region_size, 1.0 / float(surface.normalized_density())
		)
		visual_times.append(Time.get_ticks_usec() - started)
		visual_triangles += _triangle_count(mesh)
		if NativePreview.available():
			var native := NativePreview.new()
			started = Time.get_ticks_usec()
			var native_result := native.build_region(
				surface.voxels,
				size,
				surface.palette,
				PackedByteArray(),
				region_min,
				region_size,
				1.0 / float(surface.normalized_density()),
				StandardMaterial3D.new(),
				StandardMaterial3D.new(),
			)
			native_visual_times.append(Time.get_ticks_usec() - started)
			if native_result.has("mesh"):
				native_visual_successes += 1

	var solid_heights := PackedInt32Array()
	solid_heights.resize(size.x * size.z)
	solid_heights.fill(-1)
	var physics_started := Time.get_ticks_usec()
	var physics_max_usec := 0
	var physics_chunks := 0
	var physics_triangles := 0
	var physics_chunk_size := _physics_chunk_size()
	var use_cached_physics := "--cached-physics" in OS.get_cmdline_user_args()
	var physics_count_x := ceili(float(size.x) / float(physics_chunk_size))
	var physics_count_z := ceili(float(size.z) / float(physics_chunk_size))
	for chunk_z in physics_count_z:
		for chunk_x in physics_count_x:
			var region_min := Vector3i(
				chunk_x * physics_chunk_size, 0, chunk_z * physics_chunk_size
			)
			var region_size := Vector3i(
				mini(physics_chunk_size, size.x - region_min.x),
				size.y,
				mini(physics_chunk_size, size.z - region_min.z),
			)
			var started := Time.get_ticks_usec()
			var result := SurfacePhysics.build_collision_region_result(
				surface,
				region_min,
				region_size,
				1.0 / float(surface.normalized_density()),
				cached_heights if use_cached_physics else PackedInt32Array(),
			)
			physics_max_usec = maxi(physics_max_usec, Time.get_ticks_usec() - started)
			var mesh := result.get("mesh") as ArrayMesh
			if mesh != null and mesh.get_surface_count() > 0:
				physics_chunks += 1
				physics_triangles += _triangle_count(mesh)
			_copy_region_heights(result, solid_heights, size.x)
	var physics_total_usec := Time.get_ticks_usec() - physics_started

	var projection_host := Node3D.new()
	root.add_child(projection_host)
	var fallback_visual := Node3D.new()
	projection_host.add_child(fallback_visual)
	var fallback_collision := StaticBody3D.new()
	projection_host.add_child(fallback_collision)
	var projection := ProjectionScript.new()
	projection_host.add_child(projection)
	projection.configure(
		surface,
		16.0,
		Vector2i(surface.size_blocks.x, surface.size_blocks.z),
		fallback_visual,
		true,
		fallback_collision,
	)
	projection.set_process(false)
	var runtime_heightfield_started := Time.get_ticks_usec()
	while int(projection.get("_heightfield_task_id")) >= 0:
		projection.drain_next_physics_chunk(false)
		await process_frame
	var runtime_heightfield_wall_usec := Time.get_ticks_usec() - runtime_heightfield_started
	var runtime_physics_started := Time.get_ticks_usec()
	var runtime_physics_max_usec := 0
	while projection.pending_physics_chunk_count() > 0:
		var runtime_chunk_started := Time.get_ticks_usec()
		projection.drain_next_physics_chunk()
		runtime_physics_max_usec = maxi(
			runtime_physics_max_usec, Time.get_ticks_usec() - runtime_chunk_started
		)
	var runtime_physics_usec := Time.get_ticks_usec() - runtime_physics_started
	if projection.collision_chunk_count() != 64 or not projection.physics_is_ready():
		errors.append("runtime projection did not activate 64 cached collision chunks")
	var runtime_visual_times := PackedInt64Array()
	for sample in VISUAL_SAMPLES:
		var runtime_visual_started := Time.get_ticks_usec()
		projection.drain_next_chunk()
		runtime_visual_times.append(Time.get_ticks_usec() - runtime_visual_started)
	projection_host.queue_free()
	await process_frame

	var route_grid_started := Time.get_ticks_usec()
	var navigation := SurfacePhysics.navigation_grid_from_solid_heights(surface, solid_heights)
	var navigation_usec := Time.get_ticks_usec() - route_grid_started
	var route_started := Time.get_ticks_usec()
	var route := SurfacePhysics.find_block_path_from_grid(
		navigation, Vector2i(16, 29), Vector2i(16, 28), 4
	)
	var route_usec := Time.get_ticks_usec() - route_started
	if route.size() < 2:
		errors.append("generated Surface cannot route between neighboring southern blocks")

	var save_started := Time.get_ticks_usec()
	var save_error := ResourceSaver.save(surface, TEMP_SURFACE_PATH)
	var save_usec := Time.get_ticks_usec() - save_started
	if save_error != OK:
		errors.append("temporary save failed: %s" % error_string(save_error))
	var reopen_started := Time.get_ticks_usec()
	var reopened := ResourceLoader.load(
		TEMP_SURFACE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE
	) as EmberVoxelModelResource
	var reopen_usec := Time.get_ticks_usec() - reopen_started
	if reopened == null or reopened.voxels != surface.voxels or not reopened.physical:
		errors.append("temporary save/reopen changed the generated Surface")

	if FileAccess.get_sha256(source_path) != source_hash:
		errors.append("read-only profile changed the legacy map")
	if FileAccess.get_sha256(SCENE_PATH) != scene_hash:
		errors.append("read-only profile changed fan_town.tscn")
	var metrics := {
		"profile_format": 1,
		"map_id": MAP_ID,
		"blocks": [surface.size_blocks.x, surface.size_blocks.z],
		"grid": [size.x, size.y, size.z],
		"terrain_cells": int(grid.get("cells", 0)),
		"occupied_voxels": surface.voxels.size() - surface.voxels.count(0),
		"dense_voxel_bytes": surface.voxels.size(),
		"temporary_file_bytes": FileAccess.get_file_as_bytes(TEMP_SURFACE_PATH).size(),
		"seed_ms": float(seed_usec) / 1000.0,
		"transient_height_cache_ms": float(cached_heights_usec) / 1000.0,
		"legacy_mesh_ms": float(legacy_mesh_usec) / 1000.0,
		"legacy_collision_shape_ms": float(legacy_shape_usec) / 1000.0,
		"visual_chunks_total": visual_count_x * visual_count_z,
		"visual_sample_ms": _time_stats(visual_times),
		"visual_sample_triangles": visual_triangles,
		"native_visual_available": NativePreview.available(),
		"native_visual_sample_ms": _time_stats(native_visual_times),
		"native_visual_successes": native_visual_successes,
		"physics_chunks_total": physics_count_x * physics_count_z,
		"physics_chunk_size": physics_chunk_size,
		"physics_uses_transient_height_cache": use_cached_physics,
		"physics_chunks_with_mesh": physics_chunks,
		"physics_total_ms": float(physics_total_usec) / 1000.0,
		"physics_max_chunk_ms": float(physics_max_usec) / 1000.0,
		"physics_triangles": physics_triangles,
		"runtime_heightfield_wall_ms": float(runtime_heightfield_wall_usec) / 1000.0,
		"runtime_physics_total_ms": float(runtime_physics_usec) / 1000.0,
		"runtime_physics_max_chunk_ms": float(runtime_physics_max_usec) / 1000.0,
		"runtime_visual_sample_ms": _time_stats(runtime_visual_times),
		"navigation_grid_ms": float(navigation_usec) / 1000.0,
		"route_ms": float(route_usec) / 1000.0,
		"save_ms": float(save_usec) / 1000.0,
		"reopen_ms": float(reopen_usec) / 1000.0,
		"errors": errors,
	}
	var profile := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if profile != null:
		profile.store_string(JSON.stringify(metrics, "\t"))
	print(JSON.stringify(metrics, "\t"))
	print("PROFILE: ", ProjectSettings.globalize_path(PROFILE_PATH))
	if errors.is_empty():
		print("PASS fan_town Surface read-only profile")
		quit(0)
	else:
		printerr("FAIL fan_town Surface read-only profile")
		quit(1)


func _validate_height_parity(
	surface: EmberVoxelModelResource,
	grid: Dictionary,
	errors: Array[String],
) -> void:
	var width := int(grid.get("width", 0))
	var depth := int(grid.get("depth", 0))
	var heights: PackedInt32Array = grid.get("heights", PackedInt32Array())
	var density := surface.normalized_density()
	for block_z in depth:
		for block_x in width:
			var expected := int(heights[block_x + block_z * width]) - 1
			var actual := SurfacePhysics.solid_height_at(
				surface,
				Vector2i(block_x * density + density / 2, block_z * density + density / 2),
			)
			if actual != expected:
				errors.append(
					"height parity failed at %d,%d: %d != %d"
					% [block_x, block_z, actual, expected]
				)
				return


func _copy_region_heights(result: Dictionary, target: PackedInt32Array, width: int) -> void:
	var start: Vector2i = result.get("start", Vector2i.ZERO)
	var extent: Vector2i = result.get("extent", Vector2i.ZERO)
	var heights: PackedInt32Array = result.get("heights", PackedInt32Array())
	if heights.size() != extent.x * extent.y:
		return
	for local_z in extent.y:
		for local_x in extent.x:
			target[start.x + local_x + (start.y + local_z) * width] = (
				heights[local_x + local_z * extent.x]
			)


func _triangle_count(mesh: ArrayMesh) -> int:
	if mesh == null:
		return 0
	var triangles := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		triangles += floori(
			float(indices.size() if not indices.is_empty() else vertices.size()) / 3.0
		)
	return triangles


func _time_stats(values: PackedInt64Array) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	var total := 0
	var maximum := 0
	for value in values:
		total += value
		maximum = maxi(maximum, value)
	return {
		"count": values.size(),
		"mean": float(total) / float(values.size()) / 1000.0,
		"max": float(maximum) / 1000.0,
	}


func _physics_chunk_size() -> int:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--physics-chunk="):
			return clampi(int(argument.trim_prefix("--physics-chunk=")), 8, 64)
	return PHYSICS_CHUNK_SIZE
