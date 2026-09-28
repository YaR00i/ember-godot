extends SceneTree
## Recovery uses a detached Resource while the live compact map keeps changing.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Sessions = preload("res://addons/ember_import/ember_world_edit_sessions.gd")
const DIRECTORY := "user://ember_world_recovery_async_test"
const SOURCE := DIRECTORY + "/source.res"
const SIZE := 1536


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY)) == OK)
	var source := TerrainResource.new()
	source.width = SIZE
	source.depth = SIZE
	source.palette = PackedColorArray([Color.BLACK, Color.GREEN])
	var count := SIZE * SIZE
	source.heights.resize(count)
	source.heights.fill(4)
	source.top_materials.resize(count)
	source.top_materials.fill(1)
	source.base_materials.resize(count)
	source.base_materials.fill(1)
	source.cap_depths.resize(count)
	source.cap_depths.fill(4)
	source.water_levels.resize(count)
	source.water_materials.resize(count)
	assert(ResourceSaver.save(source, SOURCE) == OK)
	var saved := ResourceLoader.load(SOURCE, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	assert(saved != null and saved.validation_errors().is_empty())
	var scene := Node3D.new()
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = "recovery_async_fixture"
	map.authored_size_blocks = Vector2i(SIZE / 16, SIZE / 16)
	map.compact_terrain = saved
	scene.add_child(map)
	var sessions := Sessions.new()
	sessions.recovery_directory = DIRECTORY
	var entry := sessions.open_map(map, scene)
	assert(entry.get("compact", false))
	entry.resource.heights[0] = 5
	assert(sessions.start_periodic_recovery())
	entry.resource.heights[0] = 9
	for frame in 10000:
		sessions.poll_recovery()
		if not sessions.last_recovery_profile.is_empty(): break
		await process_frame
	assert(int(sessions.last_recovery_profile.get("result", FAILED)) == OK)
	var draft_path := DIRECTORY.path_join("draft_%s.res" % map.get_instance_id())
	var first := ResourceLoader.load(draft_path, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	assert(first != null and first.heights[0] == 5 and entry.resource.heights[0] == 9)
	var first_profile: Dictionary = sessions.last_recovery_profile.duplicate()
	assert(sessions.start_periodic_recovery())
	# A synchronous save must wait for the older background job, then write the latest edit.
	sessions.write_recovery()
	var latest := ResourceLoader.load(draft_path, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainResource
	assert(latest != null and latest.heights[0] == 9)
	var restored := Sessions.new()
	restored.recovery_directory = DIRECTORY
	assert(restored.restore_recovery(scene) == 1)
	var restored_entry: Dictionary = restored.entries[map.get_instance_id()]
	assert(restored_entry.resource.heights[0] == 9)
	print("PASS async world recovery: 4x4-sized fixture, immutable snapshot, latest sync write, restore; snapshot_ms=",
		float(first_profile.snapshot_usec) / 1000.0, " worker_save_ms=", float(first_profile.write_usec) / 1000.0)
	restored.release()
	sessions.release()
	scene.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(draft_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIRECTORY.path_join("manifest.cfg")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SOURCE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIRECTORY))
	quit()
