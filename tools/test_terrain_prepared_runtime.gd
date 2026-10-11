extends SceneTree
## Entry point for the isolated exported PCK test, never an authored map.
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Cache = preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
const WaterCache = preload("res://scripts/prototypes/ember_compact_water_cache.gd")
const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")

class WaterFields extends RefCounted:
	var dry_tiles := {}
	var tiles := {}

func _initialize() -> void: _run.call_deferred()

func _project(source: Terrain, fields: WaterFields, enabled: bool) -> TerrainProjection:
	var projection := TerrainProjection.new(); projection.water_mesh_step = 8; projection.water_volume_sides = true
	projection.runtime_geometry_cache_enabled = enabled
	root.add_child(projection); assert(projection.open_document(source))
	projection.set_sea_swash(fields); projection.set_waterfall(fields)
	var deadline := Time.get_ticks_msec() + 30000
	while projection.pending_tile_count() > 0 or projection.pending_runtime_lod_count() > 0:
		assert(Time.get_ticks_msec() < deadline); await process_frame
	return projection

func _snapshot(projection: TerrainProjection) -> Dictionary:
	var result := {}
	for key: Vector2i in projection._tiles:
		var tile: Node3D = projection._tiles[key]
		result[key] = [Cache.mesh_arrays(tile.get_node("Ground").mesh), Cache.mesh_arrays(tile.get_node("Water").mesh), tile.get_node("GroundPhysics/Shape").shape.get_faces()]
	return result

func _run() -> void:
	assert("ember-portable-" in OS.get_user_data_dir(), "test requires a private exported project")
	assert(not DirAccess.dir_exists_absolute(Cache.ROOT) and not DirAccess.dir_exists_absolute(WaterCache.ROOT), "test needs empty local caches")
	var source := load("res://qa_selection/portable_terrain.res") as Terrain
	assert(source != null)
	var producer := Regions.new(); producer._build(source, {})
	var water_stats: Dictionary = producer._result.stats
	assert(water_stats.disk_hits == 1 and water_stats.component_disk_hits == 1 and water_stats.built_regions == 0 and water_stats.component_builds == 0)
	var fields := WaterFields.new(); fields.dry_tiles = producer._result.dry_tiles; fields.tiles = producer._result.waterfall.tiles
	var prepared := await _project(source, fields, true)
	var profile := prepared.profile_snapshot()
	assert(profile.geometry_cache_misses == 0 and profile.ground_lod_cache_misses == 0 and profile.water_lod_cache_misses == 0)
	assert(profile.ground_lod_cpu_us == 0 and profile.water_lod_cpu_us == 0)
	assert(prepared._geometry_cache.disk.packaged_hits > 0)
	var snapshot := _snapshot(prepared)
	var repair_key: String = prepared._geometry_keys[Vector2i.ZERO]
	prepared.free()
	assert(not DirAccess.dir_exists_absolute(Cache.ROOT) and not DirAccess.dir_exists_absolute(WaterCache.ROOT), "prepared cache caused local copies/writes")
	var exact := await _project(source, fields, false)
	assert(snapshot == _snapshot(exact), "packaged arrays/physics differ from ordinary native mesher")
	exact.free()
	assert(DirAccess.make_dir_recursive_absolute(Cache.ROOT) == OK)
	var file := FileAccess.open(Cache.ROOT.path_join(repair_key + ".edc"), FileAccess.WRITE); file.store_string("broken"); file.close()
	var repaired := await _project(source, fields, true)
	assert(repaired.profile_snapshot().geometry_cache_misses == 0 and repaired.profile_snapshot().geometry_cache_invalid > 0)
	assert(snapshot == _snapshot(repaired)); repaired.free()
	var edited := source.working_copy()
	var index := 4 + 4 * edited.width
	edited.write_columns(PackedInt32Array([index]), PackedInt32Array([edited.column_value("heights", index) + 4]),
		PackedByteArray([edited.column_value("top_materials", index)]), PackedInt32Array([edited.column_value("water_levels", index)]), PackedByteArray([edited.column_value("water_materials", index)]))
	var changed := await _project(edited, fields, true)
	var edit_profile := changed.profile_snapshot()
	assert(edit_profile.geometry_cache_misses > 0 and edit_profile.geometry_cache_hits > 0, "local edit reused stale packaged geometry")
	assert(_snapshot(changed) != snapshot); changed.free()
	var original := await _project(source, fields, true)
	assert(original.profile_snapshot().geometry_cache_misses == 0 and _snapshot(original) == snapshot); original.free()
	producer.close()
	print("PREPARED_RUNTIME PASS empty-user-cache/PCK/near+coast+LOD+water/exact-physics/corrupt-local/edit+restore renderer=", RenderingServer.get_current_rendering_method(), " hits=", profile.geometry_cache_hits, " user=", OS.get_user_data_dir())
	quit()
