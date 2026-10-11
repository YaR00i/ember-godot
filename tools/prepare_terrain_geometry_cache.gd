extends SceneTree
## Explicit preparation of existing local derived caches, never an authored bake.
## --headless --path . --script res://tools/prepare_terrain_geometry_cache.gd --
## --source=res://scenes/<saved-map>.tscn
## Terrain .tres/.res: optional --water-step=8 --volume-sides=true.
## Fixtures: --cache=user://ember-tests/... --water-cache=user://ember-tests/...

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Builder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")
const Cache = preload("res://scripts/prototypes/ember_terrain_geometry_cache.gd")
const WaterCache = preload("res://scripts/prototypes/ember_compact_water_cache.gd")
const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const GroundLOD = preload("res://scripts/prototypes/ember_terrain_ground_lod.gd")
const WaterLOD = preload("res://scripts/prototypes/ember_terrain_water_lod.gd")
const Bundle = preload("res://scripts/prototypes/ember_terrain_prepared_bundle.gd")
const TIMEOUT_MS := 600000

func _initialize() -> void: _run.call_deferred()

static func _allowed_cache(path: String, canonical: String) -> bool:
	return (path == canonical or path.begins_with("user://ember-tests/")) and ".." not in path and "\\" not in path

func _maps(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	if node is EmberMapLoader: result.append(node)
	for child in node.get_children(): result.append_array(_maps(child))
	return result

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		printerr("Geometry preparation requires --headless; no editor/gameplay renderer is used."); quit(1); return
	var source_path := ""
	var destination := Cache.ROOT
	var water_destination := WaterCache.ROOT
	var bundle_path := ""
	var step := -1
	var sides: Variant = null
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="): source_path = argument.trim_prefix("--source=")
		elif argument.begins_with("--cache="): destination = argument.trim_prefix("--cache=")
		elif argument.begins_with("--water-cache="): water_destination = argument.trim_prefix("--water-cache=")
		elif argument.begins_with("--bundle="): bundle_path = argument.trim_prefix("--bundle=")
		elif argument.begins_with("--water-step="):
			var value := argument.trim_prefix("--water-step=")
			if not value.is_valid_int() or int(value) < 0 or int(value) > 16:
				printerr("Water mesh step must be an integer from 0 to 16."); quit(1); return
			step = int(value)
		elif argument in ["--volume-sides=true", "--volume-sides=false"]: sides = argument == "--volume-sides=true"
		else:
			printerr("Unknown argument: ", argument); quit(1); return
	if not _allowed_cache(destination, Cache.ROOT) or not _allowed_cache(water_destination, WaterCache.ROOT):
		printerr("Choose the existing user caches or isolated user://ember-tests/ directories."); quit(1); return
	if not bundle_path.is_empty() and not _allowed_cache(bundle_path, Bundle.ROOT):
		printerr("Bundle must use res://build/terrain-prepared or isolated user://ember-tests/."); quit(1); return
	if source_path.is_empty() or not ResourceLoader.exists(source_path):
		printerr("Choose a saved compact map .tscn or terrain .tres/.res with --source=."); quit(1); return
	var started := Time.get_ticks_msec()
	var resource := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var document: Terrain
	if resource is Terrain: document = resource
	elif resource is PackedScene:
		# Off-tree inspection only: no _ready, gameplay, terrain projection or physics.
		var scene: Node = resource.instantiate()
		var maps := _maps(scene)
		if maps.size() == 1:
			document = maps[0].compact_terrain
			if step < 0: step = maps[0].compact_water_mesh_step
			if sides == null: sides = maps[0].compact_water_volume_sides
		scene.free()
	if document == null or not document.validation_errors().is_empty():
		printerr("Source must contain exactly one valid compact terrain map."); quit(1); return
	if step < 0: step = 0
	if sides == null: sides = false
	if DirAccess.make_dir_recursive_absolute(destination) != OK or DirAccess.make_dir_recursive_absolute(water_destination) != OK \
		or not DirAccess.dir_exists_absolute(destination) or not DirAccess.dir_exists_absolute(water_destination):
		printerr("Cannot create derived cache directories."); quit(1); return
	print("TERRAIN_PREPARE_STARTED source=", source_path, " step=", step, " volume_sides=", sides)
	var fields := Regions.new(); fields.cache_directory = water_destination
	# The loaded Resource is immutable in this isolated process. The existing
	# CPU water producer supplies exactly the runtime's final swash/sheet inputs.
	if fields._thread.start(fields._build.bind(document, {}), Thread.PRIORITY_LOW) != OK:
		printerr("Cannot start water preparation."); quit(1); return
	while fields._thread.is_alive() and Time.get_ticks_msec() - started < TIMEOUT_MS:
		await create_timer(0.05).timeout
	if fields._thread.is_alive():
		fields.close(); printerr("Preparation timed out."); quit(1); return
	fields._thread.wait_to_finish()
	var water_stats: Dictionary = fields._result.get("stats", {})
	var water_keys: PackedStringArray = fields._result.get("cache_keys", PackedStringArray())
	var bank: Dictionary = fields._result.get("dry_tiles", {})
	var fall: RefCounted = fields._result.get("waterfall")
	fields.close()
	fields._result = {} # Release CPU images/history; retain only mesh dependencies.
	if water_stats.is_empty() or water_stats.get("cache_failures", 1) != 0 or fall == null:
		printerr("Water cache preparation failed: ", water_stats); quit(1); return
	var cache := Cache.new(); cache.directory = destination
	var policy := [step, bool(sides), true, true, true]
	var keys := document.tile_keys(Cache.TILE_SIZE)
	var stats := {"tiles": keys.size(), "geometry_hits": 0, "geometry_built": 0, "lod_hits": 0, "lod_built": 0, "lod_failures": 0, "water": water_stats}
	var required_files := {}
	for i in keys.size():
		var tile: Vector2i = keys[i]
		var swash: PackedVector4Array = bank.get(tile, PackedVector4Array())
		var sheet: Dictionary = fall.tiles.get(tile, {})
		# Runtime first draws the ordinary tile, then stages coast geometry. Bake
		# both content-addressed variants only where the dependencies differ.
		var variants := [[PackedVector4Array(), {}]]
		if not swash.is_empty() or not sheet.is_empty(): variants.append([swash, sheet])
		for variant: Array in variants:
			var key := cache.tile_key(document, tile, 1, policy, variant[0], variant[1])
			required_files[key] = true
			var data := cache.read_geometry_arrays(key)
			if data.is_empty():
				# Same mesher on the headless dummy server: no GPU, scene, collision
				# Nodes or new topology. At most one near tile is built at a time.
				var generated := Builder.build_tile(document, tile.x * Cache.TILE_SIZE, tile.y * Cache.TILE_SIZE,
					Cache.TILE_SIZE, step, bool(sides), variant[0], variant[1], true, true)
				var arrays := cache.write_geometry(key, generated)
				data = {"ground_arrays": arrays.ground_arrays, "water_arrays": arrays.water_arrays}
				stats.geometry_built += 1
			else: stats.geometry_hits += 1
			var bounds := Rect2i(tile * Cache.TILE_SIZE, Vector2i(mini(Cache.TILE_SIZE, document.width - tile.x * Cache.TILE_SIZE), mini(Cache.TILE_SIZE, document.depth - tile.y * Cache.TILE_SIZE)))
			for kind in ["ground", "water"]:
				var arrays: Array = data[kind + "_arrays"]
				if arrays.is_empty(): continue
				if kind == "ground" and arrays[Mesh.ARRAY_VERTEX].size() < GroundLOD.MIN_INDICES: continue
				if kind == "water" and (arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_INDEX].size() < WaterLOD.MIN_INDICES): continue
				var job := {"cache_directory": destination, "cache_key": Cache.lod_key(key, kind), "arrays": arrays,
					"bounds": bounds, "builder": GroundLOD.build if kind == "ground" else WaterLOD.build}
				required_files[job.cache_key] = true
				var result := Cache.build_lod(job, func() -> bool: return Time.get_ticks_msec() - started >= TIMEOUT_MS)
				stats.lod_hits += int(result.cache_hit)
				stats.lod_built += int(not result.cache_hit)
				stats.lod_failures += int(result.cache_failures)
			if cache.disk.failures > 0 or stats.lod_failures > 0 or Time.get_ticks_msec() - started >= TIMEOUT_MS:
				printerr("Geometry preparation failed/timed out at tile ", tile, ": ", stats); quit(1); return
		if (i + 1) % 128 == 0 or i + 1 == keys.size(): print("TERRAIN_PREPARE_PROGRESS tiles=", i + 1, "/", keys.size())
		if (i + 1) % Cache.PREPARE_TILES == 0: await create_timer(0.001).timeout
	Cache.trim(destination)
	# A quota-limited partial cache remains a valid runtime fallback, but must
	# not be advertised as completely prepared for this saved map.
	for key: String in required_files:
		if not FileAccess.file_exists(destination.path_join(key + ".edc")):
			printerr("The complete geometry/LOD cache does not fit the existing cache quota."); quit(1); return
	if not bundle_path.is_empty():
		var inputs := {}
		for key: String in required_files: inputs["geometry/" + key + ".edc"] = destination.path_join(key + ".edc")
		for key: String in water_keys: inputs["water/" + key + ".ewc"] = water_destination.path_join(key + ".ewc")
		var bundle := Bundle.write(bundle_path, inputs, {"source": source_path,
			"source_sha256": Cache.Storage.checksum(FileAccess.get_file_as_bytes(source_path)).hex_encode(),
			"godot_hex": Engine.get_version_info().hex, "geometry_version": Cache.VERSION,
			"water_version": WaterCache.VERSION, "component_version": WaterCache.COMPONENT_VERSION, "policy": policy})
		if not bundle.error.is_empty(): printerr(bundle.error); quit(1); return
		stats.bundle_files = bundle.files.size()
		stats.bundle_bytes = bundle.manifest.total_bytes
	stats.elapsed_ms = Time.get_ticks_msec() - started
	stats.geometry_invalid = cache.disk.invalid
	stats.geometry_failures = cache.disk.failures
	stats.prepared_files = required_files.size()
	print("TERRAIN_PREPARE_READY ", JSON.stringify(stats))
	quit()
