extends SceneTree

const SCENE := preload("res://scenes/test_pier.tscn")
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)


func _save_hashes(path: String) -> Dictionary:
	var result := {}
	if not DirAccess.dir_exists_absolute(path):
		return result
	for file in DirAccess.get_files_at(path):
		result[file] = FileAccess.get_sha256(path.path_join(file))
	for directory in DirAccess.get_directories_at(path):
		result[directory] = _save_hashes(path.path_join(directory))
	return result


func _run() -> void:
	var progress := root.get_node("EmberExploreProgress") as EmberExploreState
	var original_v2 := _save_hashes(EmberExploreState.DEFAULT_STORAGE_ROOT)
	var original_v1 := _save_hashes(EmberExploreState.DEFAULT_LEGACY_STORAGE_ROOT)
	var fixture := "user://ember-tests/test-pier-%d" % Time.get_ticks_usec()
	progress.set_meta("test_pier_storage_root", fixture)
	var scene := SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 90:
		await physics_frame
	var player := scene.get_node("Player") as EmberPlayer
	var map := scene.get_node("Map") as EmberMapLoader
	_check(progress.active_hero_ids == ["protagonist", "mira"], "F6 bootstrap did not select the pair")
	_check(progress.storage_root == fixture and progress.legacy_storage_root.begins_with(fixture), "save roots not isolated")
	_check(map.has_authored_content() and not map.hydrate_legacy_regions and not map.native_cutaway_enabled, "native scene uses legacy fallback")
	_check(scene.get_node("PartyFollowers").view_state().count == 1, "pair must have one follower")
	_check(scene.get_node_or_null("CombatLab") == null, "unexpected combat lab")
	_check(player.is_on_floor(), "spawn did not settle on authored collision")
	_check(player.global_position.y > -1.0, "player fell through pier")
	var tab := InputEventKey.new()
	tab.pressed = true
	tab.physical_keycode = KEY_TAB
	scene.call("_input", tab)
	_check(player.controlled_hero_id == "mira", "Tab did not select Mira")
	scene.call("_input", tab)
	_check(player.controlled_hero_id == "protagonist", "Tab escaped the pair")
	var inventory := scene.get_node("CanvasLayer/InventoryUI") as EmberInventoryUi
	inventory.open()
	var visible_heroes := 0
	for button in inventory._hero_buttons:
		if button.visible:
			visible_heroes += 1
	_check(visible_heroes == 2, "inventory shows inactive heroes")
	var next := InputEventKey.new()
	next.pressed = true
	next.physical_keycode = KEY_E
	inventory.call("_input", next)
	_check(progress.exploration_leader_id == "mira", "inventory E did not select Mira")
	next.physical_keycode = KEY_Q
	inventory.call("_input", next)
	_check(progress.exploration_leader_id == "protagonist", "inventory Q did not return protagonist")
	inventory.close()
	# Probe the physical deck and the water-facing wall through the same world
	# queries used by movement/follower obstacle checks.
	var space := player.get_world_3d().direct_space_state
	var ground := PhysicsRayQueryParameters3D.create(Vector3(192, 40, 120), Vector3(192, -20, 120), 1)
	_check(not space.intersect_ray(ground).is_empty(), "pier has no physical walking surface")
	var edge := PhysicsRayQueryParameters3D.create(Vector3(192, 6, 120), Vector3(60, 6, 120), 1)
	_check(not space.intersect_ray(edge).is_empty(), "water edge is not blocked")
	_check(player.test_move(player.global_transform, Vector3(-160, 0, 0)), "player capsule can leave the west edge")
	var point_a := player.global_position
	scene.get_node("CanvasLayer/ExplorePauseUI").call("_save_game", 0)
	_check(progress.slot_metadata(0).get("mapId") == "test_pier", "save does not reopen real scene id")
	player.global_position += Vector3(0, 0, 32)
	# Exercise the actual pause menu, old scene exit, and new scene ready chain.
	scene.get_node("CanvasLayer/ExplorePauseUI").call("_load_game", 0)
	for frame in 90:
		await physics_frame
	scene = current_scene
	player = scene.get_node("Player") as EmberPlayer
	_check(player.global_position.distance_to(point_a) < 1.0, "pause load lost selected slot position during reload")
	_check(progress.active_hero_ids == ["protagonist", "mira"], "reload lost pair")
	progress.save_autosave()
	# Simulate a fresh F6 process: discard only memory, keep fixture saves.
	root.remove_child(scene)
	scene.free()
	progress.storage_root = EmberExploreState.DEFAULT_STORAGE_ROOT
	progress.reset_new_game()
	scene = SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	for frame in 90:
		await physics_frame
	player = scene.get_node("Player") as EmberPlayer
	_check(player.global_position.distance_to(point_a) < 1.0, "F6 restart lost isolated saved location")
	_check(progress.active_hero_ids == ["protagonist", "mira"], "F6 restart lost pair")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for frame in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := fixture.path_join("pier.png")
		root.get_texture().get_image().save_png(capture)
		print("PIER_CAPTURE ", ProjectSettings.globalize_path(capture))
		inventory = scene.get_node("CanvasLayer/InventoryUI") as EmberInventoryUi
		inventory.open()
		await process_frame
		await RenderingServer.frame_post_draw
		capture = fixture.path_join("pier-inventory.png")
		root.get_texture().get_image().save_png(capture)
		print("PIER_CAPTURE ", ProjectSettings.globalize_path(capture))
		inventory.close()
	root.remove_child(scene)
	scene.free()
	_check(_save_hashes(EmberExploreState.DEFAULT_STORAGE_ROOT) == original_v2, "existing v2 saves changed")
	_check(_save_hashes(EmberExploreState.DEFAULT_LEGACY_STORAGE_ROOT) == original_v1, "existing legacy saves changed")
	for error in errors:
		push_error(error)
	print("test_test_pier: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size(), " errors")
	quit(0 if errors.is_empty() else 1)
