extends SceneTree
const Bundle = preload("res://scripts/prototypes/ember_terrain_prepared_bundle.gd")
const Cache = preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
var directory := "user://ember-tests/prepared-bundle/%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var document = preload("res://tools/build_compact_waterfall_study.gd").fixture().sectioned_copy()
	var source := directory.path_join("terrain.res")
	assert(ResourceSaver.save(document, source, ResourceSaver.FLAG_COMPRESS) == OK)
	var bundle_path := directory.path_join("bundle")
	var output := []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script",
		"res://tools/prepare_terrain_geometry_cache.gd", "--", "--source=" + source,
		"--cache=" + directory.path_join("geometry"), "--water-cache=" + directory.path_join("water"),
		"--water-step=8", "--volume-sides=true", "--bundle=" + bundle_path])
	assert(OS.execute(OS.get_executable_path(), args, output, true) == 0, str(output))
	var ready := Bundle.inspect(bundle_path)
	assert(ready.error.is_empty() and ready.files.size() == 26, str(ready))
	var manifest: Dictionary = ready.manifest
	var metadata := manifest.duplicate(); metadata.erase("files"); metadata.erase("total_bytes"); metadata.erase("version")
	var file: Dictionary = ready.files[0]
	var name: String = manifest.files[0].name
	var local := directory.path_join("empty-local")
	var store := Cache.Storage.new(); store.directory = local
	store.packaged_directory = file.source.get_base_dir(); store.packaged_for_directory = local
	var key := name.get_file().trim_suffix(".edc")
	assert(not store.read(key).is_empty() and store.packaged_hits == 1)
	assert(not DirAccess.dir_exists_absolute(local), "shipped data was copied into the writable cache")
	store.directory = directory.path_join("isolated")
	assert(store.read(key).is_empty(), "custom fixture inherited a packaged cache")
	store.directory = local; assert(DirAccess.make_dir_recursive_absolute(local) == OK)
	var broken := FileAccess.open(store.path(key), FileAccess.WRITE); broken.store_string("broken"); broken.close()
	assert(not store.read(key).is_empty() and store.invalid > 0 and store.packaged_hits == 2)
	var inputs := {}
	for entry: Dictionary in manifest.files: inputs[entry.name] = bundle_path.path_join(entry.name)
	assert(Bundle.write(directory.path_join("copy"), inputs, metadata).error.is_empty())
	var manifest_path := bundle_path.path_join("manifest.json")
	var original := FileAccess.get_file_as_bytes(manifest_path)
	var altered := manifest.duplicate(true); altered.files[0].name = "geometry/../escape.edc"
	_write(manifest_path, JSON.stringify(altered).to_utf8_buffer()); assert(not Bundle.inspect(bundle_path).error.is_empty())
	altered = manifest.duplicate(true); altered.files.append(altered.files[0])
	_write(manifest_path, JSON.stringify(altered).to_utf8_buffer()); assert(not Bundle.inspect(bundle_path).error.is_empty())
	altered = manifest.duplicate(true); altered.version = 999
	_write(manifest_path, JSON.stringify(altered).to_utf8_buffer()); assert(not Bundle.inspect(bundle_path).error.is_empty())
	_write(manifest_path, original)
	var saved := FileAccess.get_file_as_bytes(file.source)
	_write(file.source, "broken".to_utf8_buffer()); assert(not Bundle.inspect(bundle_path).error.is_empty())
	_write(file.source, saved)
	assert(Bundle.inspect(bundle_path).error.is_empty())
	print("PREPARED_BUNDLE PASS CLI/manifest/content-only/empty-local/no-copy/custom-isolation/corrupt-local/checksum/traversal/duplicate/version")
	quit()

func _write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE); assert(file != null)
	file.store_buffer(bytes); file.close()
