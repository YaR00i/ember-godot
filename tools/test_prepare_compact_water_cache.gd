extends SceneTree
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Cache = preload("res://scripts/prototypes/ember_compact_water_cache.gd")
const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
var directory := "user://ember-tests/water-preparation/%s" % Time.get_ticks_usec()

func _initialize() -> void:
	_run.call_deferred()

func _prepare(source: String, destination: String) -> int:
	var output := []
	var result := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/prepare_compact_water_cache.gd", "--",
		"--source=" + source, "--cache=" + destination]), output, true)
	print("WATER_PREPARE_CLI ", output)
	return result

func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var document: Terrain = preload("res://tools/build_compact_waterfall_study.gd").fixture().sectioned_copy()
	var source := directory.path_join("terrain.res")
	assert(ResourceSaver.save(document, source, ResourceSaver.FLAG_COMPRESS) == OK)
	var authored := Cache.checksum(FileAccess.get_file_as_bytes(source))
	var destination := directory.path_join("cache")
	assert(_prepare(source, destination) == 0)
	var fields := Regions.new(); fields.cache_directory = destination
	fields._build(document, {})
	assert(fields._result.stats.component_disk_hits == document.sections.size())
	assert(fields._result.stats.component_builds == 0 and fields._result.stats.built_regions == 0)
	var map := EmberMapLoader.new(); map.compact_terrain = document
	var scene := PackedScene.new(); assert(scene.pack(map) == OK); map.free()
	var scene_path := directory.path_join("map.tscn")
	assert(ResourceSaver.save(scene, scene_path) == OK)
	var saved_scene := Cache.checksum(FileAccess.get_file_as_bytes(scene_path))
	assert(_prepare(scene_path, destination) == 0)
	assert(_prepare(source, "res://content/world_terrains") != 0)
	assert(_prepare(source, directory.path_join("../escape")) != 0)
	assert(_prepare(directory.path_join("missing.res"), destination) != 0)
	var blocker := directory.path_join("not-a-directory")
	var file := FileAccess.open(blocker, FileAccess.WRITE); file.store_string("fixture"); file.close()
	assert(_prepare(source, blocker) != 0)
	assert(Cache.checksum(FileAccess.get_file_as_bytes(source)) == authored)
	assert(Cache.checksum(FileAccess.get_file_as_bytes(scene_path)) == saved_scene)
	fields.close()
	print("PASS WATER_PREPARE: terrain/scene routes, ready cache, no source writes, invalid arguments and I/O rejection")
	quit()
