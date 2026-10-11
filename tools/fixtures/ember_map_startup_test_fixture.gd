extends RefCounted
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const MAP := "native_startup_fixture"

static func prepare(tree: SceneTree) -> Dictionary:
	var directory := "user://ember-tests/map-startup-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var state := Maps.prepare(tree, directory)
	state.directory = directory
	var expected := OS.get_environment("EMBER_MAP_STARTUP_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	state.refused = expected.is_empty() or expected != actual or not FileAccess.file_exists("res://.map-startup-test-sandbox") or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git")
	if state.refused:
		printerr("REFUSED: run python tools/run_map_startup_tests.py; fixtures require a disposable project")
		return state
	var pack := directory.path_join("poison-legacy")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pack.path_join("maps")))
	ProjectSettings.set_setting("ember/pack_path", ProjectSettings.globalize_path(pack))
	state.pack = ProjectSettings.globalize_path(pack)
	state.poison_hashes = {}
	for id in [MAP, "empty_startup_fixture"]:
		var path := pack.path_join("maps/%s.json" % id)
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(JSON.stringify({"id": id, "width": 375, "height": 257, "tileSize": 32,
			"regions": [{"id": "entry", "kind": "teleport", "targetMapId": "retired_map"},
			{"id": "chest", "kind": "trigger", "lootIds": ["retired_item"], "opened": true}],
			"voxelProps": [], "light": {"sunIntensity": 0.0}}))
		file.close()
		state.poison_hashes[path] = FileAccess.get_sha256(path)
	return state

static func saved_scene(state: Dictionary, cutaways := false) -> Dictionary:
	var source := Maps.save_map(MAP, state.directory, [], [], [{"id": "chest", "position": Vector3(48, 4, 48), "loot": ["herb"], "nested": true}])
	if source == null: return {}
	var scene := source.instantiate()
	scene.scene_file_path = ""
	var map := scene.get_node("Map") as EmberMapLoader
	# Both old flags are deliberately true: they must not reactivate JSON reads.
	map.hydrate_legacy_regions = true
	map.native_cutaway_enabled = true
	if cutaways:
		var group := Node3D.new()
		group.name = "Cutaways"
		map.add_child(group)
		var nested := Node3D.new()
		nested.name = "Sections"
		group.add_child(nested)
		for index in 2:
			var roof := ArrayMesh.new()
			roof.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().surface_get_arrays(0))
			var volume := EmberCutawayVolume.new()
			volume.setup({"id": "fixture_%d" % index, "origin": Vector3(200 + index * 40, 0, 200),
				"mesh": roof, "area_size": Vector3(16, 16, 16)}, EmberVoxelPrefab.voxel_material())
			(group if index == 0 else nested).add_child(volume)
		_own(group, scene)
	var packed := PackedScene.new()
	var path := str(state.directory).path_join("native_saved.tscn")
	if packed.pack(scene) != OK or ResourceSaver.save(packed, path) != OK:
		scene.free()
		return {}
	scene.free()
	return {"path": path, "hash": FileAccess.get_sha256(path),
		"scene": ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)}

static func verify(state: Dictionary, saved: Dictionary, errors: Array[String]) -> void:
	if FileAccess.get_sha256(saved.path) != saved.hash: errors.append("runtime changed saved native scene")
	for path in state.poison_hashes:
		if FileAccess.get_sha256(path) != state.poison_hashes[path]: errors.append("runtime changed frozen map JSON")

static func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children(): _own(child, owner_node)
