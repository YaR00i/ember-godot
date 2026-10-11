extends SceneTree
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Cache = preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
var directory := "user://ember-tests/terrain-preparation/%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]

class WaterFields extends RefCounted:
	var dry_tiles := {}
	var tiles := {}

func _initialize() -> void: _run.call_deferred()

func _prepare(source: String, destination: String, extra := PackedStringArray()) -> Dictionary:
	var output := []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/prepare_terrain_geometry_cache.gd", "--",
		"--source=" + source, "--cache=" + destination, "--water-cache=" + directory.path_join("water")])
	args.append_array(extra)
	var status := OS.execute(OS.get_executable_path(), args, output, true)
	var stats := {}
	for line in str(output[0]).split("\n"):
		if line.begins_with("TERRAIN_PREPARE_READY "): stats = JSON.parse_string(line.trim_prefix("TERRAIN_PREPARE_READY "))
	print("TERRAIN_PREPARE_CLI exit=", status, " stats=", stats)
	if status != 0: print("TERRAIN_PREPARE_REJECT ", output)
	return {"exit": status, "stats": stats}

func _project(document: Terrain, fields: WaterFields, enabled: bool) -> TerrainProjection:
	var projection := TerrainProjection.new()
	projection.runtime_geometry_cache_directory = directory.path_join("geometry")
	projection.runtime_geometry_cache_enabled = enabled
	projection.water_mesh_step = 8; projection.water_volume_sides = true
	root.add_child(projection); assert(projection.open_document(document))
	if fields != null: projection.set_sea_swash(fields); projection.set_waterfall(fields)
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
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var document: Terrain = preload("res://tools/build_compact_waterfall_study.gd").fixture().sectioned_copy()
	var source := directory.path_join("terrain.res")
	assert(ResourceSaver.save(document, source, ResourceSaver.FLAG_COMPRESS) == OK)
	var source_hash := Cache.Storage.checksum(FileAccess.get_file_as_bytes(source))
	var map := EmberMapLoader.new(); map.compact_terrain = document
	map.compact_water_mesh_step = 8; map.compact_water_volume_sides = true
	var scene := PackedScene.new(); assert(scene.pack(map) == OK); map.free()
	var scene_path := directory.path_join("map.tscn")
	assert(ResourceSaver.save(scene, scene_path) == OK)
	var scene_hash := Cache.Storage.checksum(FileAccess.get_file_as_bytes(scene_path))
	var destination := directory.path_join("geometry")
	var cold := _prepare(scene_path, destination)
	assert(cold.exit == 0 and cold.stats.geometry_built > 0 and cold.stats.lod_built > 0)
	var field_producer := Regions.new(); field_producer.cache_directory = directory.path_join("water")
	field_producer._build(document, {})
	var fields := WaterFields.new()
	fields.dry_tiles = field_producer._result.dry_tiles; fields.tiles = field_producer._result.waterfall.tiles
	assert(not fields.tiles.is_empty())
	var ordinary := await _project(document, null, true)
	assert(ordinary.profile_snapshot().geometry_cache_misses == 0, "ordinary startup variants were not prepared")
	ordinary.free()
	var prepared := await _project(document, fields, true)
	var profile := prepared.profile_snapshot()
	assert(profile.geometry_cache_misses == 0 and profile.ground_lod_cache_misses == 0 and profile.water_lod_cache_misses == 0,
		"offline files were not usable by real runtime keys/arrays/LOD")
	assert(profile.ground_lod_cpu_us == 0 and profile.water_lod_cpu_us == 0)
	var snapshot := _snapshot(prepared)
	var repair_key: String = prepared._geometry_keys[Vector2i.ZERO]
	prepared.free()
	var exact := await _project(document, fields, false)
	assert(snapshot == _snapshot(exact), "headless preparation changed native near/waterfall/physics arrays")
	exact.free()
	var repeated := _prepare(scene_path, destination)
	assert(repeated.exit == 0 and repeated.stats.geometry_built == 0 and repeated.stats.lod_built == 0)
	var resource_route := _prepare(source, destination, PackedStringArray(["--water-step=8", "--volume-sides=true"]))
	assert(resource_route.exit == 0 and resource_route.stats.geometry_built == 0 and resource_route.stats.lod_built == 0)
	var store := Cache.Storage.new(); store.directory = destination
	var file := FileAccess.open(store.path(repair_key), FileAccess.WRITE); file.store_string("broken"); file.close()
	var repaired := _prepare(scene_path, destination)
	assert(repaired.exit == 0 and repaired.stats.geometry_built == 1 and repaired.stats.geometry_invalid > 0)
	var edited := document.working_copy()
	var index := 4 + 4 * edited.width
	edited.write_columns(PackedInt32Array([index]), PackedInt32Array([edited.column_value("heights", index) + 4]),
		PackedByteArray([edited.column_value("top_materials", index)]), PackedInt32Array([edited.column_value("water_levels", index)]), PackedByteArray([edited.column_value("water_materials", index)]))
	var edited_path := directory.path_join("edited.res")
	assert(ResourceSaver.save(edited, edited_path, ResourceSaver.FLAG_COMPRESS) == OK)
	var changed := _prepare(edited_path, destination, PackedStringArray(["--water-step=8", "--volume-sides=true"]))
	assert(changed.exit == 0 and changed.stats.geometry_built > 0 and changed.stats.geometry_hits > 0)
	assert(_prepare(scene_path, "res://content/world_terrains").exit != 0)
	assert(_prepare(scene_path, directory.path_join("../escape")).exit != 0)
	assert(_prepare(directory.path_join("missing.res"), destination).exit != 0)
	assert(_prepare(scene_path, destination, PackedStringArray(["--water-step=17"])).exit != 0)
	assert(_prepare(scene_path, destination, PackedStringArray(["--volume-sides=maybe"])).exit != 0)
	var invalid := Terrain.new()
	var invalid_path := directory.path_join("invalid.res")
	assert(ResourceSaver.save(invalid, invalid_path) == OK)
	assert(_prepare(invalid_path, destination).exit != 0)
	var scene_root := Node3D.new()
	var empty_scene := PackedScene.new(); assert(empty_scene.pack(scene_root) == OK)
	var empty_path := directory.path_join("empty.tscn")
	assert(ResourceSaver.save(empty_scene, empty_path) == OK)
	assert(_prepare(empty_path, destination).exit != 0)
	for i in 2:
		var duplicate_map := EmberMapLoader.new(); duplicate_map.name = "Map" + str(i)
		duplicate_map.compact_terrain = document
		scene_root.add_child(duplicate_map); duplicate_map.owner = scene_root
	var ambiguous := PackedScene.new(); assert(ambiguous.pack(scene_root) == OK); scene_root.free()
	var ambiguous_path := directory.path_join("ambiguous.tscn")
	assert(ResourceSaver.save(ambiguous, ambiguous_path) == OK)
	assert(_prepare(ambiguous_path, destination).exit != 0)
	var blocker := directory.path_join("blocked")
	file = FileAccess.open(blocker, FileAccess.WRITE); file.store_string("fixture"); file.close()
	assert(_prepare(scene_path, blocker).exit != 0)
	assert(Cache.Storage.checksum(FileAccess.get_file_as_bytes(source)) == source_hash)
	assert(Cache.Storage.checksum(FileAccess.get_file_as_bytes(scene_path)) == scene_hash)
	field_producer.close()
	print("TERRAIN_PREPARE PASS scene/resource/options/base+coast/warm/LOD/curved-waterfall/exact-physics/corrupt/local-edit/source-hashes/I-O")
	quit()
