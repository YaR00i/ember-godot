extends SceneTree
## Bake the saved map's authored ordinary grass with the same placement code as play.
## --headless --path . --script res://tools/prepare_grass_positions.gd -- --source=res://scenes/landscape_compact.tscn --output=<dedicated bundle directory>
const Patch = preload("res://scripts/ember_grass_patch.gd")
const Preparation = preload("res://scripts/ember_detail_preparation.gd")
const Storage = preload("res://scripts/prototypes/ember_derived_data_cache.gd")
const Bundle = preload("res://scripts/prototypes/ember_terrain_prepared_bundle.gd")

var inputs := {}
var entries := {}
var reused := 0
var generated := 0
var store := Storage.new()

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var source := "res://scenes/landscape_compact.tscn"
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source = arg.trim_prefix("--source=")
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=").simplify_path()
		else: fail("Unknown argument: " + arg); return
	if output.is_empty() or not output.is_absolute_path():
		fail("Specify a dedicated absolute --output directory."); return
	if FileAccess.file_exists(output.path_join("manifest.json")):
		var existing := Bundle.inspect(output)
		if existing.error != "" or existing.manifest.get("kind") != "painted-grass" or existing.manifest.get("source") != source:
			fail("Output belongs to another bundle or has an invalid manifest."); return
	elif DirAccess.dir_exists_absolute(output):
		# A failed first build may have written immutable records before the manifest.
		if not DirAccess.get_files_at(output).is_empty() or DirAccess.get_directories_at(output) not in [PackedStringArray(),PackedStringArray(["details"])]:
			fail("Refusing to mix a grass bundle with unrelated output."); return
	var source_hash := FileAccess.get_sha256(source)
	var packed := load(source) as PackedScene
	if packed == null: fail("Cannot load saved map: " + source); return
	var scene := packed.instantiate()
	var map := scene.get_node_or_null("Map") as EmberMapLoader
	if map == null or map.compact_terrain == null:
		scene.free(); fail("Expected a compact terrain Map."); return
	if not is_finite(map.imported_tile_size) or map.imported_tile_size<=0:
		scene.free(); fail("Invalid map scale."); return
	var terrain_path := map.compact_terrain.resource_path.get_slice("::",0)
	var terrain_hash := FileAccess.get_sha256(terrain_path) if not terrain_path.is_empty() else ""
	# Enter only the map and its physical props. Preserve the scene's coordinate
	# system without starting player simulation, recovery or game saves.
	if scene is Node3D: map.transform = scene.transform * map.transform
	scene.remove_child(map)
	scene.free()
	var groups := {}
	var empty_masks := 0
	for node in map.find_children("*", "Node3D", true, false):
		if not node is Patch or not node.painted_only or node.detail_kind != 0: continue
		if not node.validation_errors().is_empty():
			var path := str(map.get_path_to(node))
			map.free(); fail("Invalid grass patch " + path); return
		if node.density_cells.is_empty(): empty_masks += 1; continue
		var world: Transform3D = node.transform
		var parent: Node = node.get_parent()
		while parent is Node3D:
			world = parent.transform * world
			parent = parent.get_parent()
		var sector := Vector2i((Vector2(world.origin.x,world.origin.z) / (12.0 * map.imported_tile_size)).floor())
		if not groups.has(sector): groups[sector] = []
		groups[sector].append(node)
	store.directory = output.path_join("details")
	store.magic = "EDSCATR1"
	store.max_bytes = 4 * 1024 * 1024
	Preparation.cache_root = "user://ember-grass-bake-work"
	var projection: EmberTerrainPilotProjection
	if not groups.is_empty():
		root.add_child(map)
		projection = map._visual_surface_projection
		if not is_instance_valid(projection) or projection.document == null:
			map.free(); fail("Map has no terrain projection."); return
		var context = Preparation.for_projection(projection)
		context.disk.packaged_for_directory = Preparation.cache_root
		context.disk.packaged_directory = store.directory
	for group: Array in groups.values():
		var first: Node3D = group[0]
		projection.set_runtime_start_anchor(first.global_position)
		var deadline := Time.get_ticks_msec() + 90000
		var pending := group.duplicate()
		while not pending.is_empty():
			await process_frame
			for i in range(pending.size()-1,-1,-1):
				var patch: Patch = pending[i]
				if patch._dirty or patch._rebuilding or patch.prepared_placement_key.is_empty(): continue
				if not record(map, patch):
					map.free(); fail("Cannot publish a validated placement record."); return
				pending.remove_at(i)
			if Time.get_ticks_msec() >= deadline and not pending.is_empty():
				var path := str(map.get_path_to(pending[0]))
				map.free(); fail("Timed out preparing " + path); return
	map.free()
	if FileAccess.get_sha256(source)!=source_hash or (not terrain_path.is_empty() and FileAccess.get_sha256(terrain_path)!=terrain_hash):
		fail("Map or terrain changed during preparation. Run again."); return
	var result := Bundle.write(output, inputs, {"kind":"painted-grass", "source":source,
		"source_sha256":source_hash, "terrain":terrain_path, "terrain_sha256":terrain_hash,
		"patches":entries, "empty_masks":empty_masks})
	if result.error != "": fail(result.error); return
	print("GRASS_BUNDLE_READY ",JSON.stringify({"patches":entries.size(),"empty_masks":empty_masks,
		"files":result.files.size(),"reused":reused,"runtime_generations":generated,"bytes":result.manifest.total_bytes,"output":output}))
	quit()

func record(map: EmberMapLoader, patch: Patch) -> bool:
	var key := patch.prepared_placement_key
	var looks := patch._detail_transform_cache
	if looks.is_empty() or not looks.has(0): return false
	generated+=patch.detail_generations
	var existing:=store.read(key)
	if existing.is_empty():
		store.write(key, {"looks":looks}, func():return false)
		if store.read(key).get("looks") != looks: return false
	elif existing.get("looks") == looks:
		reused += 1
	else:
		printerr("Placement changed under the same content key: ",key)
		return false
	inputs["details/"+key+store.extension] = store.path(key)
	entries[str(map.get_path_to(patch))] = key
	return true

func fail(message: String) -> void:
	printerr("GRASS_BUNDLE_ERROR ",message)
	quit(1)
