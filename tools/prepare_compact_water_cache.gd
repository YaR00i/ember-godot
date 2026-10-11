extends SceneTree
## Explicit CPU-only preparation of the existing disposable water cache.
## --headless --path . --script res://tools/prepare_compact_water_cache.gd --
## --source=res://scenes/<saved-map>.tscn
## Test fixtures may use --cache=user://ember-tests/<unique-directory>.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const Cache = preload("res://scripts/prototypes/ember_compact_water_cache.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var source_path := ""
	var cache_path := Cache.ROOT
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="): source_path = argument.trim_prefix("--source=")
		elif argument.begins_with("--cache="): cache_path = argument.trim_prefix("--cache=")
		else:
			printerr("Unknown argument: ", argument); quit(1); return
	if source_path.is_empty() or not ResourceLoader.exists(source_path):
		printerr("Choose a saved compact map .tscn or terrain .tres/.res with --source=."); quit(1); return
	if cache_path != Cache.ROOT and not cache_path.begins_with("user://ember-tests/") \
		or ".." in cache_path or "\\" in cache_path:
		printerr("Cache must be the existing user cache or an isolated user://ember-tests/ directory."); quit(1); return
	var started := Time.get_ticks_msec()
	var resource := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var document: Terrain
	if resource is Terrain:
		document = resource
	elif resource is PackedScene:
		# Never enter the scene tree: no gameplay, remesh, physics or GPU uploads.
		var scene: Node = resource.instantiate()
		var maps := _maps(scene)
		if maps.size() == 1: document = maps[0].compact_terrain
		scene.free()
	if document == null:
		printerr("Source must contain exactly one compact terrain map."); quit(1); return
	var errors := document.validation_errors()
	if not errors.is_empty():
		printerr("Invalid source terrain: ", errors); quit(1); return
	var fields := Regions.new()
	fields.cache_directory = cache_path
	# The same worker and serializer as editor/runtime; only publication is omitted.
	var error := fields._thread.start(fields._build.bind(document.working_copy(), {}), Thread.PRIORITY_LOW)
	if error != OK:
		printerr("Cannot start water preparation: ", error); quit(1); return
	print("WATER_PREPARE_STARTED source=", source_path, " cache=", ProjectSettings.globalize_path(cache_path))
	var deadline := Time.get_ticks_msec() + 600000
	while fields._thread.is_alive() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	if fields._thread.is_alive():
		fields.close(); printerr("Water preparation timed out."); quit(1); return
	fields._thread.wait_to_finish()
	var stats: Dictionary = fields._result.get("stats", {})
	fields.close()
	if stats.is_empty() or stats.get("cache_failures", 1) != 0:
		printerr("Water cache preparation failed: ", stats); quit(1); return
	print("WATER_PREPARE_READY elapsed_ms=", Time.get_ticks_msec() - started, " stats=", JSON.stringify(stats))
	quit()

func _maps(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	if node is EmberMapLoader: result.append(node)
	for child in node.get_children(): result.append_array(_maps(child))
	return result
