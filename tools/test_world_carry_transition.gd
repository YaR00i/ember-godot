extends SceneTree
const Transition = preload("res://scripts/ember_map_transition.gd")
const Records = preload("res://scripts/ember_world_items.gd")
const ID := "chapter1_delivery_crate"
var state: EmberExploreState
var errors: Array[String] = []
var output := ""

func _init() -> void:
	if not FileAccess.file_exists("res://.interaction-test-sandbox"):
		printerr("REFUSED: disposable project required"); quit(2); return
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	if not ok: errors.append(text); printerr("CHECK FAIL ", text)

func body() -> RigidBody3D:
	var result: RigidBody3D
	var count := 0
	for node in get_nodes_in_group("ember_world_item_bodies"):
		if current_scene.is_ancestor_of(node) and node.pickup_id == ID and not node.is_queued_for_deletion(): result = node; count += 1
	check(count <= 1, "duplicate physical identity")
	return result

func player() -> EmberPlayer:
	return current_scene.get_node("Player") as EmberPlayer

func near(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]: return absf(float(a) - float(b)) < 0.00001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not near(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not near(a[index], b[index]): return false
		return true
	return a == b

func ready_map(id: String) -> bool:
	for frame in 900:
		await process_frame
		if current_scene != null and str(current_scene.get("map_id")) == id and current_scene.get("_startup_complete") == true:
			for tick in 3: await physics_frame
			return true
	check(false, "map not ready: " + id); return false

func travel(exit: String, destination: String) -> bool:
	var region = current_scene.get_node("Map").find_region(exit)
	if region == null: check(false, "exit missing " + exit); return false
	Transition.guard_arrival("different_guard", 0)
	region._on_body_entered(player())
	return await ready_map(destination)

func held(id: String) -> void:
	var crate := body()
	check(crate != null, "cargo absent in " + id)
	if crate == null: return
	check(crate.is_carried(), "cargo not held in " + id)
	check(crate.map_id == id and state.world_items[ID].mapId == id, "wrong map ownership")
	check(is_equal_approx(crate.mass, 3.0) and is_equal_approx(crate.visual_size, 12.0) and not crate.breakable, "physics profile lost")
	check(str(state.world_items[ID].get("carrierHeroId", "")) == player().controlled_hero_id, "carrier ID lost in %s: %s expected %s" % [id,str(state.world_items[ID].get("carrierHeroId", "")),player().controlled_hero_id])

func _run() -> void:
	state = root.get_node("EmberExploreProgress")
	state.persistence_enabled = false; state.restore_enabled = false
	output = "user://ember-tests/cargo-%d" % Time.get_ticks_usec()
	state.storage_root = output.path_join("saves"); state.legacy_storage_root = output.path_join("legacy")
	state.set_meta("world_canvas_storage_root", state.storage_root)
	state.reset_new_game(); state.world_items.clear(); Transition.clear_for_test()
	check(change_scene_to_file("res://scenes/chapter1_woodland.tscn") == OK, "start woodland failed")
	if not await ready_map("chapter1_woodland"): quit(1); return
	var crate := body()
	if crate == null: check(false,"authored cargo missing"); quit(1); return
	player().global_position = crate.global_position + Vector3(0, 0, 20)
	crate.take(player())
	check(crate.is_carried(), "initial pickup failed")
	held("chapter1_woodland")
	if not await travel("exit_from_centre", "chapter1_centre"): quit(1); return
	held("chapter1_centre")
	if not await travel("exit_from_residential", "chapter1_residential"): quit(1); return
	held("chapter1_residential")
	var door = current_scene.get_node("Map/Props/KaiHome/DoorInteraction")
	player().global_position = door.global_position + Vector3(0, 0, 5)
	check(player()._nearest() == door, "door didn't take F priority")
	player()._try_interact()
	if not await ready_map("chapter1_home"): quit(1); return
	held("chapter1_home")
	state.persistence_enabled = true
	check(state.save_slot(1), "held save failed")
	var saved: Dictionary = state.world_items[ID].duplicate(true)
	var fresh := EmberExploreState.new(); fresh.name = "FreshCargoState"
	fresh.persistence_enabled = false; fresh.restore_enabled = false
	fresh.storage_root = state.storage_root; fresh.legacy_storage_root = state.legacy_storage_root
	root.add_child(fresh)
	check(fresh.load_slot(1) and near(fresh.world_items.get(ID, {}), saved), "fresh normalization lost carry/profile")
	fresh.queue_free()
	check(state.load_slot(1), "held load failed")
	state.restore_enabled = true
	check(change_scene_to_file("res://scenes/chapter1_home.tscn") == OK, "held reopen failed")
	if not await ready_map("chapter1_home"): quit(1); return
	held("chapter1_home")
	state.persistence_enabled = false; state.restore_enabled = false
	check(state.set_exploration_leader("mira"), "leader switch failed")
	check(body().is_carried() and str(state.world_items[ID].carrierHeroId) == "protagonist" and not player().has_meta("ember_carried_item"), "Tab reassigned cargo or left old player binding")
	check(state.set_exploration_leader("protagonist"), "leader return failed")
	held("chapter1_home")
	player().global_position = Vector3(96, 8, 120)
	check(player()._nearest() == body().get_node("Pickup"), "away from doors F didn't offer place")
	player()._try_interact()
	check(not body().is_carried() and not state.world_items[ID].has("carrierHeroId"), "place didn't clear held record")
	var exit_door = current_scene.get_node("Map/Props/ExitDoor/DoorInteraction")
	check(exit_door.activate().begins_with("enter"), "home exit failed")
	if not await ready_map("chapter1_residential"): quit(1); return
	check(body() == null, "left item followed without carrier")
	if not await travel("exit_from_centre", "chapter1_centre"): quit(1); return
	if not await travel("exit_from_woodland", "chapter1_woodland"): quit(1); return
	check(body() == null and state.world_items[ID].mapId == "chapter1_home", "original authored crate respawned after transfer")
	if not await travel("exit_from_centre", "chapter1_centre"): quit(1); return
	if not await travel("exit_from_residential", "chapter1_residential"): quit(1); return
	door = current_scene.get_node("Map/Props/KaiHome/DoorInteraction")
	door.activate()
	if not await ready_map("chapter1_home"): quit(1); return
	crate = body()
	check(crate != null and not crate.is_carried() and crate.carryable, "loose cargo not restored")
	if crate != null:
		player().global_position = crate.global_position + Vector3(0, 0, 20)
		crate.take(player()); held("chapter1_home")
		var before: Dictionary = state.world_items[ID].duplicate(true)
		check(Transition.change_scene(self, "__missing_cargo_target", "entry") == ERR_FILE_NOT_FOUND, "missing target accepted")
		check(state.world_items[ID] == before and crate.is_carried(), "failed transition lost cargo")
		exit_door = current_scene.get_node("Map/Props/ExitDoor/DoorInteraction")
		exit_door.condition_flag_id = "test_locked_door"
		player().global_position = exit_door.global_position + Vector3(0, 0, 5)
		check(player()._nearest() == crate.get_node("Pickup"), "locked door stole F priority")
		exit_door.condition_flag_id = ""
		player().global_position = Vector3(96, 8, 120)
		check(crate.throw_from(player()).begins_with("Брошено"), "G throw failed after transition")
		for tick in 10: await physics_frame
		check(not crate.is_carried() and not state.world_items[ID].has("carrierHeroId"), "throw retained carrier")
		var anchor := Records.vector(state.world_items[ID].physical.returnOrigin)
		crate.global_position = Vector3(96, -600, 120); crate.recover_from_void()
		check(crate.global_position.distance_to(anchor) < 0.1 and state.world_items[ID].mapId == "chapter1_home", "recovery used previous map coordinates")
		if DisplayServer.get_name() != "headless":
			player().global_position = crate.global_position + Vector3(0, 0, 20)
			crate.take(player())
			await process_frame; await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
			root.get_texture().get_image().save_png(output.path_join("cargo-in-home.png"))
	var legacy := {"old":{"itemId":"quest_crate","mapId":"chapter1_home","count":1,"position":[0,8,0],"rotation":[0,0,0]}}
	check(Records.normalize(legacy) == legacy, "legacy record changed")
	var malformed: Dictionary = saved.duplicate(true); malformed.physical.itemMass = -3; malformed.carrierHeroId = "bad"
	var cleaned := Records.normalize({"bad":malformed})
	check(cleaned.has("bad") and not cleaned.bad.has("physical") and not cleaned.bad.has("carrierHeroId"), "invalid optional profile not isolated")
	current_scene.queue_free(); current_scene = null
	await process_frame
	if not errors.is_empty(): printerr("CARGO TRANSITION FAIL ", errors); quit(1); return
	print("CARGO TRANSITION PASS held gates+door/identity/profile/fresh save+load/no respawn/place+throw/recovery/failed destination/F priority/legacy")
	print("EVIDENCE ", ProjectSettings.globalize_path(output))
	quit(0)
