extends SceneTree
## Real World Canvas startup: no hero or camera switch exposed before water.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> bool:
	if not ok:
		_failed = true
		push_error("WORLD_STARTUP FAIL: " + message)
	return ok


func _fixture() -> Terrain:
	var terrain := Terrain.new()
	terrain.width = 128
	terrain.depth = 128
	terrain.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.AQUA])
	var count := terrain.width * terrain.depth
	terrain.heights.resize(count)
	terrain.heights.fill(4)
	terrain.top_materials.resize(count)
	terrain.top_materials.fill(1)
	terrain.base_materials = terrain.top_materials.duplicate()
	terrain.cap_depths.resize(count)
	terrain.cap_depths.fill(1)
	terrain.water_levels.resize(count)
	terrain.water_levels.fill(8)
	terrain.water_materials.resize(count)
	terrain.water_materials.fill(2)
	for z in terrain.depth:
		for x in 16: terrain.water_materials[z * terrain.width + x] = 0
	return terrain.sectioned_copy()


func _scene(with_water: bool) -> Node3D:
	var scene := (load("res://scenes/compact_material_light_study.tscn") as PackedScene).instantiate() as Node3D
	scene.sandbox_storage_root = "user://ember-tests/world-startup"
	var map := scene.get_node("Map") as EmberMapLoader
	map.compact_terrain = _fixture()
	map.authored_size_blocks = Vector2i(8, 8)
	if not with_water:
		scene.get_node("PlanarReflection").free()
	root.add_child(scene)
	current_scene = scene
	return scene


func _run() -> void:
	var scene := _scene(true)
	var study = scene.get_node("PlanarReflection")
	if "--cancel-startup" in OS.get_cmdline_user_args():
		await process_frame
		var escape := InputEventKey.new()
		escape.physical_keycode = KEY_ESCAPE
		escape.pressed = true
		print("WORLD_STARTUP_EXIT requested before water ready=", not study._prepared)
		Input.parse_input_event(escape)
		for frame in 4: await process_frame
		_check(false, "Escape did not close the loading screen")
		quit(1)
		return
	_check(scene.get_node_or_null("WorldLoadingScreen") != null, "startup cover is missing")
	_check(not scene.get_node("CanvasLayer").visible, "game HUD is visible during preparation")
	if not InputMap.has_action("move_east"): InputMap.add_action("move_east")
	Input.action_press("move_east")
	var saw_water_wait := false
	var deadline := Time.get_ticks_msec() + 30000
	while not study._prepared and Time.get_ticks_msec() < deadline:
		await process_frame
		if study._prepared: break
		if scene.get_node("Map")._visual_surface_projection.pending_physics_chunk_count() == 0:
			saw_water_wait = true
			if not _check(scene._player == null, "hero spawned while shore fields are still loading"):
				scene.queue_free()
				await process_frame
				quit(1)
				return
	_check(saw_water_wait, "fixture did not exercise the interval between ground and water")
	_check(study._prepared, "water preparation timed out")
	for frame in 12: await process_frame
	Input.action_release("move_east")
	_check(scene._player != null, "hero never spawned after preparation")
	_check(study._follow != null, "startup camera is missing")
	if _failed:
		scene.queue_free()
		await process_frame
		quit(1)
		return
	_check(scene._startup_complete and scene.get_node_or_null("WorldLoadingScreen") == null, "cover did not finish")
	_check(scene.get_node("Map")._visual_surface_projection.pending_runtime_lod_count() == 0, "gameplay opened before ground LOD preparation")
	var target = study._follow.target
	var yaw: float = study._follow.yaw
	for frame in 20: await process_frame
	_check(study._follow.target == target and is_equal_approx(study._follow.yaw, yaw), "camera changed after gameplay became available")
	var before: Vector3 = scene._player.global_position
	Input.action_press("move_east")
	for frame in 18: await physics_frame
	Input.action_release("move_east")
	_check(Vector2(scene._player.global_position.x - before.x, scene._player.global_position.z - before.z).length() > 1.0,
		"movement did not resume after preparation")
	scene.queue_free()
	await process_frame
	var plain := _scene(false)
	for frame in 120:
		await process_frame
		if plain.get_node("Map")._visual_surface_projection.pending_runtime_lod_count() > 0:
			_check(plain._player == null and not plain._startup_complete, "plain map exposed gameplay during ground LOD preparation")
		if plain._player != null: break
	_check(plain._player != null, "map without a water controller was blocked")
	plain.queue_free()
	await process_frame
	# A real spill exercises the second automatic camera selection as well.
	var fall := (load("res://scenes/compact_material_light_study.tscn") as PackedScene).instantiate() as Node3D
	fall.sandbox_storage_root = "user://ember-tests/world-startup"
	fall.get_node("Map").compact_terrain = preload("res://tools/build_compact_waterfall_study.gd").fixture().sectioned_copy()
	root.add_child(fall)
	current_scene = fall
	deadline = Time.get_ticks_msec() + 30000
	while not fall._startup_complete and Time.get_ticks_msec() < deadline: await process_frame
	_check(fall._startup_complete, "waterfall map did not open")
	var fall_study = fall.get_node("PlanarReflection")
	_check(fall_study._waterfall_camera_initialized and not fall_study._waterfall.info.is_empty(), "waterfall camera was not selected before play")
	var fall_position: Vector3 = fall_study._study_target.global_position
	for frame in 12: await process_frame
	_check(fall_study._study_target.global_position == fall_position, "waterfall camera changed after the cover disappeared")
	fall.queue_free()
	await process_frame
	var cancelled := _scene(true)
	await process_frame
	cancelled.queue_free()
	for frame in 6: await process_frame
	if not _failed: print("WORLD_STARTUP PASS: ground/water barrier, camera, input, plain map, waterfall, cancellation")
	quit(1 if _failed else 0)
