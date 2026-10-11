extends SceneTree
## Save v2 + chest mechanics on saved native fixtures. The runner isolates
## native model/prefab writes in a disposable project, never author res://.

const Fixture = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const ExploreState = preload("res://scripts/ember_explore_state.gd")
const CLOSED := "restore_fixture_closed"
const OPEN := "restore_fixture_open"
const TILE_SIZE := 8.0
var _directory := ""
var _map_id := ""
var _scene_path := ""
var _source: PackedScene
var _setup: Dictionary = {}


func _init() -> void:
	var expected := OS.get_environment("EMBER_PROGRESS_TEST_ROOT").replace("\\", "/").rstrip("/")
	var actual := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if expected.is_empty() or expected != actual or not FileAccess.file_exists("res://.progress-test-sandbox") or DirAccess.dir_exists_absolute("res://.git") or FileAccess.file_exists("res://.git"):
		printerr("REFUSED: run python tools/run_progress_restore_test.py; native chest prefab writes require a disposable project")
		quit.call_deferred(2)
		return
	_directory = "user://ember-tests/progress-restore-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_map_id = "restore_fixture_%d" % OS.get_process_id()
	_scene_path = EmberMapTransition.scene_path(_map_id)
	_setup = Fixture.prepare(self, _directory)
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	if _setup.error != OK or not _setup.progress_isolated or not _save_model(CLOSED, 1) or not _save_model(OPEN, 2):
		printerr("FAIL progress restore: fixture/progress isolation or native voxel setup failed")
		return 1
	var closed_visual := EmberVoxelPrefab.ensure_saved(CLOSED, 16.0, {})
	if closed_visual == null:
		printerr("FAIL progress restore: could not build serialized closed visual fixture")
		return 1
	_source = Fixture.save_map(_map_id, _directory, [], [{
		"id": "arrival", "map": "absent_destination", "region": "entry", "position": Vector3(12, 4, 12),
	}], [{
		"id": "chest", "position": Vector3(20, 6, 20), "loot": ["coin", "herb", "meat_bun"],
		"closed_model": CLOSED, "open_model": OPEN,
	}, {
		"id": "authored_chest", "position": Vector3(20, 6, 8), "loot": [],
		"closed_model": CLOSED, "open_model": OPEN, "saved_visual": closed_visual,
	}, {
		"id": "nested_chest", "position": Vector3(6, 6, 20), "loot": [],
		"closed_model": CLOSED, "open_model": OPEN, "nested": true,
	}], TILE_SIZE)
	if _source == null:
		printerr("FAIL progress restore: could not save/reopen native scene")
		return 1
	var fixture_path := _directory.path_join(_map_id + ".tscn")
	var scene_hash := FileAccess.get_sha256(fixture_path)
	var model_hashes := {CLOSED: FileAccess.get_sha256(EmberVoxelCatalog.native_path(CLOSED)), OPEN: FileAccess.get_sha256(EmberVoxelCatalog.native_path(OPEN))}
	var storage := _directory.path_join("manual-save")
	var state := ExploreState.new()
	state.storage_root = storage
	state.inventory = {"coin": 20}
	state.shop_stock = {"fixture_shop": {"herb": 0}}
	state.opened_chests = ["other_fixture:old_chest"]
	state.flags = {"fixture_done": true, "quest_status": "active", "quest_count": 2}
	var player := Node3D.new()
	player.position = Vector3(23.5, 7.25, 14.5)
	state.set_world_context(_map_id, player, TILE_SIZE)
	if not state.save_slot(0): errors.append("could not write isolated save v2 fixture")
	var loaded := ExploreState.new()
	loaded.storage_root = storage
	if not loaded.load_slot(0):
		errors.append("could not load isolated save v2 fixture")
	else:
		var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
		if loaded.start_scene_path_for(main_scene) != _scene_path:
			errors.append("main scene did not resolve to saved map scene")
		if not loaded.start_scene_path_for(_scene_path).is_empty():
			errors.append("running a current scene would be redirected like main run")
		if loaded.consume_saved_spawn("other_fixture", TILE_SIZE) != null:
			errors.append("saved spawn leaked into another map")
		var restored: Variant = loaded.consume_saved_spawn(_map_id, TILE_SIZE)
		if not restored is Vector3 or not (restored as Vector3).is_equal_approx(player.position):
			errors.append("saved x/y/elev did not restore the exact Godot world position")
		if loaded.consume_saved_spawn(_map_id, TILE_SIZE) != null:
			errors.append("saved spawn was consumed more than once")
		if loaded.flags != state.flags or loaded.shop_stock != state.shop_stock or loaded.opened_chests != state.opened_chests:
			errors.append("typed flags/shop stock/other chest keys did not survive save/load")
	# Use the real autoload before scene readiness, as normal save loading does.
	var runtime := root.get_node("EmberExploreProgress") as ExploreState
	runtime.adopt_loaded_save(loaded)
	runtime.restore_enabled = true
	runtime.arm_saved_spawn_restore()
	runtime.storage_root = storage
	await _test_live_chest(runtime, errors)
	runtime.opened_chests.append(_map_id + ":authored_chest")
	runtime.opened_chests.append(_map_id + ":nested_chest")
	if not runtime.save_slot(0): errors.append("could not persist chest progress")
	var reopened := ExploreState.new()
	reopened.storage_root = storage
	if not reopened.load_slot(0):
		errors.append("could not reopen chest progress")
	else:
		if not reopened.chest_is_opened(_map_id, "chest"):
			errors.append("opened chest key did not survive save reopen")
		if reopened.inventory != runtime.inventory or int(reopened.inventory.get("herb", 0)) != 1:
			errors.append("chest inventory did not survive save reopen")
		if reopened.flags != state.flags or reopened.shop_stock != state.shop_stock or not reopened.chest_is_opened("other_fixture", "old_chest"):
			errors.append("unrelated progress changed during chest round-trip")
		# Real load -> scene readiness must replace even a serialized closed visual.
		if not runtime.load_slot(0): errors.append("runtime could not load saved chest state")
		if await _open_scene(errors):
			var chest := current_scene.get_node("Map/Regions/chest") as EmberRegion
			if chest.opened: errors.append("fixture scene itself stored runtime chest state")
			_check_visual(chest, OPEN, errors)
			_check_other_chests(OPEN, errors)
			var inventory := runtime.inventory.duplicate(true)
			if chest.prompt() != "Сундук уже открыт" or chest.activate() != "Сундук уже открыт" or runtime.inventory != inventory:
				errors.append("reopened scene allowed duplicate chest loot")
	if FileAccess.get_sha256(fixture_path) != scene_hash:
		errors.append("runtime changed saved native scene fixture")
	for id in model_hashes:
		if FileAccess.get_sha256(EmberVoxelCatalog.native_path(id)) != model_hashes[id]:
			errors.append("runtime changed native model source fixture")
	player.free()
	state.free()
	loaded.free()
	reopened.free()
	if not errors.is_empty():
		printerr("FAIL progress restore")
		for error in errors: printerr(" - ", error)
		return 1
	print("PASS progress restore")
	print("  native scene + exact one-use spawn; main run / explicit current scene")
	print("  real chest prompt/loot once; typed flags/shop stock/save and scene reopen")
	print("  automatic native closed/open startup; nested and serialized visual restore")
	return 0


func _test_live_chest(state: ExploreState, errors: Array[String]) -> void:
	state.persistence_enabled = false
	if not await _open_scene(errors): return
	var map := current_scene.get_node_or_null("Map") as EmberMapLoader
	var chest := current_scene.get_node_or_null("Map/Regions/chest") as EmberRegion
	var runtime_player := current_scene.get_node_or_null("Player") as EmberPlayer
	if map == null or chest == null or runtime_player == null:
		errors.append("native fixture lost chest region or player")
		return
	if map.hydrate_legacy_regions or map.occupying_region_id(map.region_world("arrival"), ["trigger"]) != "arrival":
		errors.append("native saved-position arrival geometry/hydration boundary is wrong")
	if FileAccess.file_exists(EmberPack.map_path(_map_id)):
		errors.append("native chest startup fixture unexpectedly has map JSON")
	if chest.progress_state != null: errors.append("chest bypassed the real progress autoload")
	if chest.map_id != _map_id or chest.loot_ids != ["coin", "herb", "meat_bun"]:
		errors.append("native authored chest properties did not survive scene save/reopen")
	_check_visual(chest, CLOSED, errors)
	_check_other_chests(CLOSED, errors)
	var visuals := {}
	for id in ["chest", "authored_chest", "nested_chest"]:
		var visual := map.find_region(id).get_node_or_null("ChestVisual")
		if visual != null: visuals[id] = visual.get_instance_id()
	# Refresh is idempotent; an enabled compatibility flag with no JSON must
	# also leave native regions usable without recreating their models.
	map.refresh_region_runtime()
	map.hydrate_legacy_regions = true
	map.refresh_region_runtime()
	map.hydrate_legacy_regions = false
	for id in visuals:
		var visual := map.find_region(id).get_node_or_null("ChestVisual")
		if visual == null or visual.get_instance_id() != visuals[id]:
			errors.append("region refresh recreated an unchanged native chest visual")
	if chest not in get_nodes_in_group("ember_interact"):
		errors.append("runtime chest is not discoverable by player interaction")
	runtime_player.global_position = chest.global_position
	if str(runtime_player.call("_nearest_prompt")) != "Открыть сундук":
		errors.append("player did not expose the chest F prompt")
	if not chest.activate().begins_with("Лут:"):
		errors.append("first chest activation did not return loot message")
	if int(state.inventory.get("coin", 0)) != 21 or int(state.inventory.get("herb", 0)) != 1 or int(state.inventory.get("meat_bun", 0)) != 1:
		errors.append("chest did not grant all authored lootIds on top of inventory")
	_check_visual(chest, OPEN, errors)
	var after_first := state.inventory.duplicate(true)
	if chest.activate() != "Сундук уже открыт" or state.inventory != after_first:
		errors.append("non-repeatable chest granted loot twice")
	state.persistence_enabled = true


func _check_other_chests(model_id: String, errors: Array[String]) -> void:
	for path in ["Map/Regions/authored_chest", "Map/Regions/Entries/nested_chest"]:
		var chest := current_scene.get_node_or_null(path) as EmberRegion
		if chest == null:
			errors.append("native scene lost chest " + path)
		else:
			_check_visual(chest, model_id, errors)
			if chest.get_children().filter(func(child: Node) -> bool: return child is EmberVoxelProp).size() != 1:
				errors.append("chest startup has missing/duplicate voxel visual " + path)


func _check_visual(chest: EmberRegion, model_id: String, errors: Array[String]) -> void:
	var visual := chest.get_node_or_null("ChestVisual") as EmberVoxelProp
	var mesh := visual.get_node_or_null("Mesh") as MeshInstance3D if visual else null
	if visual == null or visual.model_id != model_id:
		errors.append("chest visual does not use expected native model " + model_id)
	elif not is_equal_approx(visual.block_world_size, TILE_SIZE):
		errors.append("chest visual did not adopt the map block size")
	elif not visual.global_position.is_equal_approx(chest.to_global(Vector3(0, -2, 0))):
		errors.append("chest visual placement differs from its region's grounded center")
	elif mesh == null or mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
		errors.append("chest visual prefab has no rendered mesh")
	elif not mesh.scale.is_equal_approx(Vector3.ONE * TILE_SIZE):
		errors.append("chest rendered mesh scale differs from map block size")
	elif str(visual.get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, "")) != EmberVoxelPrefab.source_signature(model_id):
		errors.append("chest visual was not derived from current native source")


func _open_scene(errors: Array[String]) -> bool:
	var previous := current_scene
	if change_scene_to_file(_scene_path) != OK:
		errors.append("could not start native runtime fixture scene")
		return false
	for frame in 12:
		await process_frame
		if current_scene != null and current_scene != previous:
			await process_frame
			return true
	errors.append("native fixture scene handoff timed out")
	return false


func _save_model(model_id: String, occupied: int) -> bool:
	var model := EmberVoxelModelResource.new()
	model.model_id = model_id
	model.display_name = model_id
	model.height_voxels = 1
	model.physical = false
	model.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN])
	model.voxels.resize(16 * 16)
	for index in occupied: model.voxels[index] = 1
	if not model.validation_errors().is_empty(): return false
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EmberVoxelCatalog.NATIVE_DIR)) != OK: return false
	return ResourceSaver.save(model, EmberVoxelCatalog.native_path(model_id)) == OK
