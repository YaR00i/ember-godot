extends SceneTree
## Disposable terrain CPU profile. Authored scenes and resources are never saved.

const Creation = preload("res://addons/ember_import/ember_compact_map_creation.gd")
const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Diagnostics = preload("res://addons/ember_import/ember_terrain_diagnostics.gd")
const BEACH := "res://content/terrain_pilot/beach_region.res"
const DIRECTORY := "user://ember_terrain_diagnostics/fixtures"
const MIXED := "user://ember_terrain_diagnostics/fixtures/mixed_large.res"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var creation := Creation.new()
	creation.scene_directory = DIRECTORY.path_join("scenes")
	creation.terrain_directory = DIRECTORY.path_join("terrain")
	creation.map_id = "profile_flat_4x4"
	_cleanup(creation)
	var started := Time.get_ticks_usec()
	if not creation.prepare_sections("profile_flat_4x4", 4, 4, 8):
		_fail(creation.error, creation)
		return
	var flat_prepare_ms := _ms(started)
	started = Time.get_ticks_usec()
	var flat_path := creation.commit()
	if flat_path.is_empty():
		_fail(creation.error, creation)
		return
	var flat_save_ms := _ms(started)
	started = Time.get_ticks_usec()
	var flat_packed := ResourceLoader.load(flat_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if flat_packed == null:
		_fail("flat scene did not load", creation)
		return
	var flat_scene := flat_packed.instantiate()
	var flat_map := flat_scene.get_node("Map") as EmberMapLoader
	flat_scene.remove_child(flat_map)
	flat_scene.free()
	var flat_load_ms := _ms(started)
	var flat: Dictionary = await _measure_map(flat_map)
	flat["prepare_ms"] = flat_prepare_ms
	flat["save_ms"] = flat_save_ms
	flat["load_ms"] = flat_load_ms
	var beach := ResourceLoader.load(BEACH, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	if beach == null or not beach.validation_errors().is_empty():
		_fail("beach fixture is missing or invalid", creation)
		return
	started = Time.get_ticks_usec()
	var mixed_source := _repeat_4x4(beach)
	var mixed_prepare_ms := _ms(started)
	started = Time.get_ticks_usec()
	if ResourceSaver.save(mixed_source, MIXED) != OK:
		_fail("mixed fixture did not save", creation)
		return
	var mixed_save_ms := _ms(started)
	mixed_source = null
	started = Time.get_ticks_usec()
	var mixed_loaded := ResourceLoader.load(MIXED, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	var mixed_load_ms := _ms(started)
	if mixed_loaded == null:
		_fail("mixed fixture did not reload", creation)
		return
	var mixed_map := EmberMapLoader.new()
	mixed_map.map_id = "profile_mixed_4x4"
	mixed_map.hydrate_legacy_regions = false
	mixed_map.authored_size_blocks = Vector2i(mixed_loaded.width / 16, mixed_loaded.depth / 16)
	mixed_map.compact_terrain = mixed_loaded
	var mixed: Dictionary = await _measure_map(mixed_map)
	mixed["prepare_ms"] = mixed_prepare_ms
	mixed["save_ms"] = mixed_save_ms
	mixed["load_ms"] = mixed_load_ms
	var report := {"schema": 1, "context": "headless_cpu_pipeline", "godot": Engine.get_version_info().string,
		"flat_4x4": flat, "mixed_beach_4x4": mixed,
		"limitations": "Headless timing does not measure Forward+ GPU, editor UI, draw calls, or core utilisation. Mixed fixture repeats the existing beach, without props."}
	var path: String = Diagnostics.save_report(report)
	_cleanup(creation)
	if path.is_empty() or int(flat.terrain.tile_builds) != 576 or int(mixed.terrain.tile_builds) < 576:
		push_error("Terrain profile did not produce a complete report")
		quit(1)
		return
	print("TERRAIN_PIPELINE flat=", JSON.stringify(_brief(flat)), " mixed=", JSON.stringify(_brief(mixed)), " report=", ProjectSettings.globalize_path(path))
	quit()


func _measure_map(map: EmberMapLoader) -> Dictionary:
	var started := Time.get_ticks_usec()
	root.add_child(map)
	var enter_ms := _ms(started)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	var previous := Time.get_ticks_usec()
	var gaps: Array[float] = []
	var deadline := Time.get_ticks_msec() + 60000
	while projection.pending_tile_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
		var now := Time.get_ticks_usec()
		gaps.append(float(now - previous) / 1000.0)
		previous = now
	gaps.sort()
	var result := {"enter_ms": enter_ms, "build_ms": _ms(started),
		"frame_gap_p95_ms": gaps[clampi(ceili(gaps.size() * 0.95) - 1, 0, gaps.size() - 1)] if not gaps.is_empty() else 0.0,
		"frame_gap_max_ms": gaps.back() if not gaps.is_empty() else 0.0,
		"terrain": projection.profile_snapshot()}
	map.queue_free()
	await process_frame
	return result


func _brief(result: Dictionary) -> Dictionary:
	var terrain: Dictionary = result.terrain
	return {"tiles": terrain.tile_builds, "geometry_ms": float(terrain.geometry_us) / 1000.0,
		"top_ms": float(terrain.top_us) / 1000.0, "side_ms": float(terrain.side_us) / 1000.0,
		"water_ms": float(terrain.water_us) / 1000.0,
		"mesh_resource_ms": float(terrain.mesh_resource_us) / 1000.0,
		"nodes_ms": float(terrain.node_us) / 1000.0,
		"collision_shape_ms": float(terrain.collision_shape_us) / 1000.0,
		"collision_attach_ms": float(terrain.collision_attach_us) / 1000.0,
		"visual_ms": float(terrain.visual_us) / 1000.0, "build_ms": result.build_ms,
		"frame_gap_p95_ms": result.frame_gap_p95_ms}


func _repeat_4x4(source: TerrainResource) -> TerrainResource:
	var result := TerrainResource.new()
	result.width = source.width * 4
	result.depth = source.depth * 4
	result.height_limit = source.height_limit
	result.origin_y = source.origin_y
	result.palette = source.palette.duplicate()
	var count := result.width * result.depth
	result.heights.resize(count)
	result.top_materials.resize(count)
	result.base_materials.resize(count)
	result.cap_depths.resize(count)
	result.water_levels.resize(count)
	result.water_materials.resize(count)
	for z in result.depth:
		for x in result.width:
			var dst := x + z * result.width
			var src := x % source.width + (z % source.depth) * source.width
			result.heights[dst] = source.heights[src]
			result.top_materials[dst] = source.top_materials[src]
			result.base_materials[dst] = source.base_materials[src]
			result.cap_depths[dst] = source.cap_depths[src]
			result.water_levels[dst] = source.water_levels[src]
			result.water_materials[dst] = source.water_materials[src]
			if source.column_material_overrides.has(src):
				result.column_material_overrides[dst] = (source.column_material_overrides[src] as Dictionary).duplicate(true)
	return result


func _ms(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _cleanup(creation) -> void:
	for path in [creation.scene_path(), creation.terrain_path(), MIXED]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _fail(message: String, creation) -> void:
	_cleanup(creation)
	push_error(message)
	quit(1)
