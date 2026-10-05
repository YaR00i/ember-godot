extends SceneTree
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const TerrainProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Cache = preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
var directory := "user://ember-tests/geometry-cache-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
class WaterFields extends RefCounted:
	var tiles := {}
	var dry_tiles := {}

func _initialize() -> void: run.call_deferred()

func fixture() -> Terrain:
	var source := Terrain.new()
	source.width = 256
	source.depth = 128
	source.height_limit = 160
	source.palette = PackedColorArray([Color.TRANSPARENT, Color.GREEN, Color.BROWN, Color.BLUE])
	for channel in Terrain.Sections.CHANNELS:
		var data = PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray()
		data.resize(source.width * source.depth)
		data.fill(128 if channel == "water_levels" else 3 if channel == "water_materials" else 1 if channel == "top_materials" else 2 if channel == "base_materials" else 4)
		source.set(channel, data)
	var noise := FastNoiseLite.new()
	noise.seed = 0
	noise.frequency = .03
	for z in source.depth:
		for x in source.width: source.heights[x + z * source.width] = 32 + roundi(noise.get_noise_2d((x / 8) * 8, (z / 8) * 8) * 8) * 4
	assert(source.validation_errors().is_empty())
	return source.sectioned_copy()

func project(source: Terrain, path := "", enabled := true, fields: WaterFields = null) -> TerrainProjection:
	var projection := TerrainProjection.new()
	projection.runtime_geometry_cache_directory = directory if path.is_empty() else path
	projection.runtime_geometry_cache_enabled = enabled
	projection.water_mesh_step = 8
	projection.water_volume_sides = true
	root.add_child(projection)
	assert(projection.open_document(source))
	if fields != null:
		projection.set_waterfall(fields)
		projection.set_sea_swash(fields)
	var deadline := Time.get_ticks_msec() + 20000
	while projection.pending_tile_count() > 0 or projection.pending_runtime_lod_count() > 0:
		assert(Time.get_ticks_msec() < deadline)
		await process_frame
	assert(not projection.is_processing())
	return projection

func snapshot(projection: TerrainProjection) -> Dictionary:
	var result := {}
	for key: Vector2i in projection._tiles:
		var tile: Node3D = projection._tiles[key]
		result[key] = [Cache.mesh_arrays(tile.get_node("Ground").mesh), Cache.mesh_arrays(tile.get_node("Water").mesh), tile.get_node("GroundPhysics/Shape").shape.get_faces()]
	return result

func run() -> void:
	var source := fixture()
	var original := source.working_copy()
	var cold := await project(source)
	var baseline := snapshot(cold)
	var cold_profile := cold.profile_snapshot()
	assert(cold_profile.geometry_cache_hits == 0 and cold_profile.geometry_cache_misses == 8)
	assert(cold_profile.ground_lod_tiles > 0 and cold_profile.water_lod_tiles > 0)
	assert(cold_profile.geometry_cache_failures == 0)
	var geometry_key: String = cold._geometry_keys[Vector2i.ZERO]
	cold.free()
	var resource_path := directory.path_join("fixture.tres")
	assert(ResourceSaver.save(source, resource_path) == OK)
	var reopened: Terrain = ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var warm := await project(reopened)
	var warm_profile := warm.profile_snapshot()
	assert(warm_profile.geometry_cache_hits == 8 and warm_profile.geometry_cache_misses == 0)
	assert(warm_profile.ground_lod_cache_hits == warm_profile.ground_lod_jobs and warm_profile.water_lod_cache_hits == warm_profile.water_lod_jobs)
	assert(warm_profile.ground_lod_cpu_us == 0 and warm_profile.water_lod_cpu_us == 0)
	assert(snapshot(warm) == baseline and reopened.same_terrain_data(original))
	var camera := Camera3D.new()
	root.add_child(camera)
	for point in [Vector3(30, 60, 30), Vector3(30, 4000, 4000), Vector3(30, 60, 30)]:
		camera.position = point
		await process_frame
	assert(warm.profile_snapshot().geometry_cache_hits == 8 and warm.profile_snapshot().tile_builds == 8)
	warm.free()
	camera.free()
	var edited := original.working_copy()
	var index := 32 + 32 * edited.width
	var height := edited.column_value("heights", index) + 8
	edited.write_columns(PackedInt32Array([index]), PackedInt32Array([height]), PackedByteArray([1]), PackedInt32Array([128]), PackedByteArray([3]))
	var changed := await project(edited)
	assert(changed.profile_snapshot().geometry_cache_misses == 4 and changed.profile_snapshot().geometry_cache_hits == 4, "local edit invalidated distant tiles")
	var exact := await project(edited, "", false)
	assert(snapshot(changed) == snapshot(exact))
	changed.free(); exact.free()
	var undo := await project(original)
	assert(undo.profile_snapshot().geometry_cache_hits == 8 and snapshot(undo) == baseline)
	undo.free()
	# Truncated/checksum-invalid and semantically malformed files rebuild safely.
	var store := Cache.Storage.new()
	store.directory = directory
	var file := FileAccess.open(store.path(geometry_key), FileAccess.WRITE)
	file.store_string("broken"); file.close()
	var repaired := await project(original)
	assert(repaired.profile_snapshot().geometry_cache_invalid > 0 and repaired.profile_snapshot().geometry_cache_misses == 1)
	assert(snapshot(repaired) == baseline)
	repaired.free()
	store.write(geometry_key, {"version": Cache.VERSION, "ground": [false], "water": [], "collision_faces": PackedVector3Array()}, func() -> bool: return false)
	var malformed := await project(original)
	assert(malformed.profile_snapshot().geometry_cache_invalid > 0 and snapshot(malformed) == baseline)
	malformed.free()
	store.write(Cache.lod_key(geometry_key, "water"), {"version": Cache.VERSION, "base": PackedInt32Array([-1]), "lods": {}}, func() -> bool: return false)
	var bad_lod := await project(original)
	assert(bad_lod.profile_snapshot().water_lod_cache_misses == 1 and bad_lod.profile_snapshot().geometry_cache_invalid > 0)
	assert(snapshot(bad_lod) == baseline)
	bad_lod.free()
	var payload := store.read(geometry_key)
	payload.version = Cache.VERSION + 1
	store.write(geometry_key, payload, func() -> bool: return false)
	var versioned := await project(original)
	assert(versioned.profile_snapshot().geometry_cache_invalid > 0 and snapshot(versioned) == baseline)
	versioned.free()
	# Water-field geometry has its own dependency even at the same column revision.
	var fields := WaterFields.new()
	fields.tiles[Vector2i.ZERO] = {"vertices": PackedVector3Array([Vector3(20, 128, 20), Vector3(20, 4, 20), Vector3(24, 4, 20)]), "uvs": PackedVector2Array([Vector2(0, 3), Vector2(0, 4), Vector2(1, 4)])}
	fields.dry_tiles[Vector2i.ZERO] = PackedVector4Array([Vector4(24, 30, 128, 0)])
	var with_fields := await project(original, "", true, fields)
	assert(with_fields.profile_snapshot().geometry_cache_hits == 7 and with_fields.profile_snapshot().geometry_cache_misses == 1)
	var field_geometry := snapshot(with_fields)
	assert(field_geometry[Vector2i.ZERO][1] != baseline[Vector2i.ZERO][1])
	with_fields.free()
	var warm_fields := await project(original, "", true, fields)
	assert(warm_fields.profile_snapshot().geometry_cache_hits == 8 and snapshot(warm_fields) == field_geometry)
	warm_fields.free()
	# Growing the envelope only changes dependencies near its former edge.
	var grown := original.dense_window(Rect2i(0, 0, 320, 128)).sectioned_copy()
	assert(grown.validation_errors().is_empty())
	var keyer := Cache.new()
	var policy := [8, true, true, true, true]
	var before := keyer.tile_key(original, Vector2i.ZERO, 1, policy, PackedVector4Array(), {})
	var after := keyer.tile_key(grown, Vector2i.ZERO, 2, policy, PackedVector4Array(), {})
	assert(before == after, "growth invalidated distant geometry")
	# An unavailable cache is only a fallback condition, never a gameplay error.
	var blocked := directory.path_join("blocked")
	file = FileAccess.open(blocked, FileAccess.WRITE); file.store_string("sentinel"); file.close()
	var fallback := await project(original, blocked)
	assert(fallback.profile_snapshot().geometry_cache_failures > 0 and snapshot(fallback) == baseline)
	fallback.free()
	# Closing a scene during worker/cache work cannot publish into freed Nodes
	# or leave half-written files that a later fresh scene treats as meshes.
	var cancel_path := directory.path_join("cancel")
	var closing := TerrainProjection.new()
	closing.runtime_geometry_cache_directory = cancel_path
	closing.water_mesh_step = 8
	closing.water_volume_sides = true
	root.add_child(closing)
	assert(closing.open_document(original))
	var deadline := Time.get_ticks_msec() + 20000
	while not closing._mesh_lod_thread.is_started():
		assert(Time.get_ticks_msec() < deadline)
		await process_frame
	closing.free()
	for name in DirAccess.get_files_at(cancel_path): assert(not name.ends_with(".tmp"))
	var recovered := await project(original, cancel_path)
	assert(snapshot(recovered) == baseline and recovered.profile_snapshot().geometry_cache_failures == 0)
	recovered.free()
	# The transport budget only removes its own derived-file extension.
	store.trim(0)
	assert(FileAccess.file_exists(resource_path) and FileAccess.get_file_as_string(blocked) == "sentinel")
	assert(DirAccess.get_files_at(directory).size() == 2)
	print("GEOMETRY_CACHE PASS fresh-resource/warm/near/LOD/physics/local-edit/Undo/growth/water-fields/corrupt/version/malformed/I-O/budget/camera/cancel cold=", cold_profile, " warm=", warm_profile)
	quit()
