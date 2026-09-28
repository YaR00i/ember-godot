extends SceneTree

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const DIRECTORY := "user://compact_map_open_performance"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var creation := Creation.new()
	creation.scene_directory = DIRECTORY.path_join("scenes")
	creation.terrain_directory = DIRECTORY.path_join("world_terrains")
	_cleanup(creation)
	var started := Time.get_ticks_usec()
	if not creation.prepare_sections("flat_open_test", 4, 4, 8):
		_fail(creation, creation.error)
		return
	var prepare_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var path := creation.commit()
	if path.is_empty():
		_fail(creation, creation.error)
		return
	var save_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		_fail(creation, "Created scene did not load")
		return
	var scene := packed.instantiate()
	var map := scene.get_node("Map") as EmberMapLoader
	if map == null:
		_fail(creation, "Created scene has no map")
		return
	var scene_load_ms := _elapsed_ms(started)
	# WorldCanvas runs gameplay in a headless SceneTree; the map projection is
	# the editor's same 3D build path and isolates the cost of opening the map.
	scene.remove_child(map)
	scene.free()
	started = Time.get_ticks_usec()
	root.add_child(map)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	if projection == null:
		map.free()
		_fail(creation, "Map projection was not created")
		return
	var enter_ms := _elapsed_ms(started)
	started = Time.get_ticks_usec()
	var pending_warnings := map._get_configuration_warnings()
	var pending_warning_ms := _elapsed_ms(started)
	if not pending_warnings.is_empty() or pending_warning_ms > 100.0:
		map.free()
		_fail(creation, "Warnings rescanned the valid terrain during initial build")
		return
	started = Time.get_ticks_usec()
	var last_frame := Time.get_ticks_usec()
	var worst_frame_ms := 0.0
	var frames := 0
	while projection.pending_tile_count() > 0 and frames < 2000:
		await process_frame
		var now := Time.get_ticks_usec()
		worst_frame_ms = maxf(worst_frame_ms, float(now - last_frame) / 1000.0)
		last_frame = now
		frames += 1
	var build_ms := _elapsed_ms(started)
	var built := projection.built_tile_count()
	var interior := projection.get_node("TerrainTile_5_5") as Node3D
	var interior_mesh := (interior.get_node("Ground") as MeshInstance3D).mesh as ArrayMesh
	var interior_shape := (interior.get_node("GroundPhysics/Shape") as CollisionShape3D).shape as ConcavePolygonShape3D
	var face_count := interior_shape.get_faces().size()
	var top_vertices := (interior_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	await physics_frame
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(Vector3(355.5, 100, 355.5), Vector3(355.5, -10, 355.5))
	var hit := root.world_3d.direct_space_state.intersect_ray(ray)
	var heights := map.compact_terrain.heights
	heights[0] = map.compact_terrain.height_limit + 1
	map.compact_terrain.heights = heights
	var invalid_warnings := map._get_configuration_warnings()
	map.queue_free()
	await process_frame
	_cleanup(creation)
	print("COMPACT_MAP_OPEN_PERFORMANCE prepare_ms=%.1f save_ms=%.1f scene_load_ms=%.1f enter_ms=%.1f pending_warning_ms=%.1f build_ms=%.1f worst_frame_ms=%.1f tiles=%d interior_vertices=%d collision_faces=%d" % [prepare_ms, save_ms, scene_load_ms, enter_ms, pending_warning_ms, build_ms, worst_frame_ms, built, top_vertices, face_count])
	if built != 576 or top_vertices != 6 or face_count != 6 or hit.is_empty() or not is_equal_approx(hit.position.y, 8.0) or build_ms > 1400.0 or worst_frame_ms > 40.0 or invalid_warnings.is_empty():
		push_error("4x4 flat map opening exceeds the performance budget")
		quit(1)
	else:
		quit()


func _elapsed_ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _cleanup(creation) -> void:
	for path in [creation.scene_path(), creation.terrain_path()]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(creation, message: String) -> void:
	_cleanup(creation)
	push_error(message)
	quit(1)
