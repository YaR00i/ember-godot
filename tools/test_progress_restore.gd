extends SceneTree
## Save v2 restore + real chest region over the existing agent_sandbox map.

const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"
const MAIN_SCENE := "res://scenes/fan_town.tscn"
const ExploreState = preload("res://scripts/ember_explore_state.gd")


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var runtime_progress := root.get_node_or_null("EmberExploreProgress") as ExploreState
	if runtime_progress:
		runtime_progress.persistence_enabled = false
		runtime_progress.restore_enabled = false
	var nonce := "%s_%s" % [Time.get_unix_time_from_system(), randi()]
	var storage := "user://ember-tests/progress-restore-%s" % nonce
	var state := ExploreState.new()
	state.storage_root = storage
	state.inventory = {"coin": 20}
	state.shop_stock = {"village_kiosk": {"herb": 0}}
	state.opened_chests = ["fan_town:old_chest"]
	state.flags = {
		"sandbox_chain_done": true,
		"quest_status": "active",
		"quest_count": 2,
	}
	var player := Node3D.new()
	player.position = Vector3(123.5, 7.25, 234.5)
	state.set_world_context("agent_sandbox", player, 16.0)
	if not state.save_slot(0):
		errors.append("could not write isolated save v2 fixture")

	var loaded := ExploreState.new()
	loaded.storage_root = storage
	if not loaded.load_slot(0):
		errors.append("could not load isolated save v2 fixture")
	else:
		if loaded.start_scene_path_for(MAIN_SCENE) != SANDBOX_SCENE:
			errors.append("main scene did not resolve to saved map scene")
		if not loaded.start_scene_path_for(SANDBOX_SCENE).is_empty():
			errors.append("running a current scene would be redirected like main run")
		if loaded.consume_saved_spawn("fan_town", 16.0) != null:
			errors.append("saved spawn leaked into another map")
		var restored: Variant = loaded.consume_saved_spawn("agent_sandbox", 16.0)
		if not restored is Vector3 or not (restored as Vector3).is_equal_approx(player.position):
			errors.append("saved x/y/elev did not restore the exact Godot world position")
		if loaded.consume_saved_spawn("agent_sandbox", 16.0) != null:
			errors.append("saved spawn was consumed more than once")
		if loaded.flags != state.flags:
			errors.append("typed flags did not survive save/load")

	await _test_live_chest(loaded, errors)
	if not loaded.save_slot(0):
		errors.append("could not persist chest progress")
	var reopened := ExploreState.new()
	reopened.storage_root = storage
	if not reopened.load_slot(0):
		errors.append("could not reopen chest progress")
	elif not reopened.chest_is_opened("agent_sandbox", "chest"):
		errors.append("opened chest key did not survive restart")
	elif int(reopened.inventory.get("herb", 0)) != 1:
		errors.append("chest inventory did not survive restart")
	elif reopened.flags != state.flags:
		errors.append("flags changed during chest round-trip")

	var file_path := state.save_path(0)
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	player.free()
	state.free()
	loaded.free()
	reopened.free()

	if not errors.is_empty():
		printerr("FAIL progress restore")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS progress restore")
	print("  main run resolves saved map; F6 current scene stays explicit")
	print("  exact x/y/elev spawn is consumed once")
	print("  chest loot/opened key + typed flags survive save v2 restart")
	return 0


func _test_live_chest(state: ExploreState, errors: Array[String]) -> void:
	state.persistence_enabled = false
	state.opened_chests.erase("agent_sandbox:chest")
	state.inventory = {"coin": 20}
	if change_scene_to_file(SANDBOX_SCENE) != OK:
		errors.append("could not start agent_sandbox runtime scene")
		return
	await process_frame
	await process_frame
	var sandbox := current_scene
	var map := sandbox.get_node_or_null("Map") as EmberMapLoader
	var chest := sandbox.get_node_or_null("Map/Regions/chest") as EmberRegion
	# Runtime owns the concrete EmberPlayer; this route smoke needs only the
	# CharacterBody transform plus dynamic interaction hooks.
	var runtime_player := sandbox.get_node_or_null("Player") as CharacterBody3D
	if map == null or chest == null or runtime_player == null:
		errors.append("agent_sandbox lost chest region or player")
		return
	if map.occupying_region_id(map.region_world("cabin_enter"), ["trigger"]) != "cabin_enter":
		errors.append("saved-position arrival guard cannot resolve occupying trigger geometry")
	chest.progress_state = state
	if chest.map_id != "agent_sandbox" or chest.loot_ids != ["coin", "herb", "funeral_polearm"]:
		errors.append("authored .tscn chest was not hydrated from map JSON")
	var chest_visual := chest.get_node_or_null("ChestVisual") as EmberVoxelProp
	var chest_mesh := chest_visual.get_node_or_null("Mesh") as MeshInstance3D if chest_visual else null
	if chest.closed_model_id != "vox_ms8vsb53" or chest_visual == null:
		errors.append("chest closedModelId did not create its authored voxel visual")
	elif chest_visual.model_id != chest.closed_model_id:
		errors.append("chest visual does not use the authored closedModelId")
	elif not chest_visual.global_position.is_equal_approx(Vector3(168.0, 0.0, 264.0)):
		errors.append("chest visual is not grounded at the authored region center")
	elif chest_mesh == null or chest_mesh.mesh == null:
		errors.append("chest visual prefab has no rendered mesh")
	if chest not in get_nodes_in_group("ember_interact"):
		errors.append("runtime chest is not discoverable by player interaction")
	runtime_player.global_position = chest.global_position
	if str(runtime_player.call("_nearest_prompt")) != "Открыть сундук":
		errors.append("player did not expose the chest F prompt")
	var first := chest.activate()
	if not first.begins_with("Лут:"):
		errors.append("first chest activation did not return loot message")
	if int(state.inventory.get("coin", 0)) != 21:
		errors.append("chest did not grant coin on top of inventory")
	if int(state.inventory.get("herb", 0)) != 1 or int(state.inventory.get("funeral_polearm", 0)) != 1:
		errors.append("chest did not grant all authored lootIds")
	var after_first := state.inventory.duplicate(true)
	if chest.activate() != "Сундук уже открыт" or state.inventory != after_first:
		errors.append("non-repeatable chest granted loot twice")
	state.persistence_enabled = true
