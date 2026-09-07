extends SceneTree
## Wave 4 smoke: the existing Ember map/region destination survives scene
## handoff, resolves to the authored region, and cannot loop immediately.

const Transition = preload("res://scripts/ember_map_transition.gd")
const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"
const INTERIOR_SCENE := "res://scenes/agent_sandbox_interior.tscn"
const FAN_SCENE := "res://scenes/fan_town.tscn"
const FAN_ROUTES := [
	{"door": "ft_inn_door", "map": "fan_town_inn", "root": "FanTownInn", "return": "inn_enter"},
	{"door": "ft_mage_door", "map": "fan_town_mage", "root": "FanTownMage", "return": "mage_enter"},
	{"door": "ft_smith_door", "map": "fan_town_smith", "root": "FanTownSmith", "return": "smith_enter"},
	{"door": "ft_house_door", "map": "fan_town_house", "root": "FanTownHouse", "return": "house_enter"},
]


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var progress: Node = get_root().get_node_or_null("EmberExploreProgress")
	if progress != null:
		progress.set(&"persistence_enabled", false)
		progress.set(&"restore_enabled", false)
	Transition.clear_for_test()

	Transition.prepare("agent_sandbox_interior", "start")
	if Transition.consume_spawn_region("agent_sandbox_interior", 1000) != "start":
		errors.append("door targetRegionId=start was not handed to the interior")
	if not Transition.consume_spawn_region("agent_sandbox_interior", 1001).is_empty():
		errors.append("spawn destination was consumed more than once")

	Transition.prepare("agent_sandbox", "cabin_enter")
	if Transition.consume_spawn_region("agent_sandbox", 2000) != "cabin_enter":
		errors.append("exit targetRegionId=cabin_enter was not handed back")
	if Transition.trigger_allowed("cabin_enter", 2500):
		errors.append("return trigger guard did not block the arrival region")
	if not Transition.trigger_allowed("cabin_enter", 3300):
		errors.append("return trigger guard did not expire")
	Transition.prepare("stale_map", "stale_region")
	if Transition.change_scene(self, "__missing_transition_scene__", "missing") != ERR_FILE_NOT_FOUND:
		errors.append("missing target scene did not report ERR_FILE_NOT_FOUND")
	if not Transition.consume_spawn_region("stale_map", 3400).is_empty():
		errors.append("missing target scene left a stale pending destination")

	var required_scenes := [SANDBOX_SCENE, INTERIOR_SCENE, FAN_SCENE]
	for route in FAN_ROUTES:
		required_scenes.append(Transition.scene_path(route.map))
	for path in required_scenes:
		if not ResourceLoader.exists(path):
			errors.append("target scene unavailable: %s" % path)

	var packed := ResourceLoader.load(SANDBOX_SCENE, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var root := packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if packed else null
	if root == null:
		errors.append("agent_sandbox scene could not be instantiated")
	else:
		var map := root.get_node_or_null("Map") as EmberMapLoader
		var region := root.get_node_or_null("Map/Regions/cabin_enter") as Node3D
		if map == null or region == null:
			errors.append("agent_sandbox cabin_enter region is missing")
		elif not map.region_world("cabin_enter").is_equal_approx(region.position):
			errors.append("map loader did not resolve cabin_enter to its authored position")
		root.free()

	var interior_packed := ResourceLoader.load(
		INTERIOR_SCENE,
		"",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as PackedScene
	var interior := interior_packed.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) if interior_packed else null
	if interior == null:
		errors.append("agent_sandbox_interior scene could not be instantiated")
	else:
		var interior_map := interior.get_node_or_null("Map") as EmberMapLoader
		if interior_map == null or interior_map.map_id != "agent_sandbox_interior":
			errors.append("interior scene is not wired to its Ember map id")
		if interior.get_node_or_null("CanvasLayer/Gate") == null:
			errors.append("interior play HUD contract is missing")
		interior.free()

	Transition.clear_for_test()
	await _run_live_scene_route(errors)
	Transition.clear_for_test()
	await _run_live_fan_town_routes(errors)
	Transition.clear_for_test()
	if not errors.is_empty():
		printerr("FAIL map transition")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS map transition")
	print("  door -> interior:start")
	print("  exit -> sandbox:cabin_enter")
	print("  fan_town inn/mage/smith/house -> interior:start -> matching return region")
	print("  arrival trigger guard expires after 1200 ms")
	return 0


func _run_live_scene_route(errors: Array[String]) -> void:
	if change_scene_to_file(SANDBOX_SCENE) != OK:
		errors.append("could not start agent_sandbox runtime scene")
		return
	await process_frame
	await process_frame
	var sandbox := current_scene
	var door := sandbox.get_node_or_null("Map/Props/sbx_cabin_door/Interact") as EmberInteract
	if door == null:
		errors.append("runtime cabin door Interact is missing")
		return
	if not door.activate().begins_with("enter"):
		errors.append("runtime cabin door did not request a scene transition")
		return
	await process_frame
	await process_frame
	var interior := current_scene
	if interior == null or interior.name != "AgentSandboxInterior":
		errors.append("runtime door did not enter agent_sandbox_interior")
		return
	var interior_map := interior.get_node_or_null("Map") as EmberMapLoader
	# This suite verifies scene routing and spawn positions, not player gameplay.
	# Keep it independent from the editor's global-class cache: the packed scene
	# still instantiates the real EmberPlayer, while the test only needs its
	# CharacterBody3D position/body contract.
	var interior_player := interior.get_node_or_null("Player") as CharacterBody3D
	if interior_map == null or interior_player == null:
		errors.append("runtime interior did not create Map + Player")
		return
	if interior_player.find_child("WaterContact", false, false) == null:
		errors.append("runtime player lacks its automatic water contact visual")
	var interior_spawn := interior_map.region_world("start")
	if not _same_xz(interior_player.global_position, interior_spawn):
		errors.append("runtime interior player did not spawn at region start")
	var exit_region := interior.get_node_or_null("Map/Regions/exit") as EmberRegion
	if exit_region == null:
		errors.append("runtime interior exit trigger is missing")
		return
	exit_region._on_body_entered(interior_player)
	await process_frame
	await process_frame
	var returned := current_scene
	if returned == null or returned.name != "AgentSandbox":
		errors.append("runtime exit did not return to agent_sandbox")
		return
	var returned_map := returned.get_node_or_null("Map") as EmberMapLoader
	var returned_player := returned.get_node_or_null("Player") as CharacterBody3D
	if returned_map == null or returned_player == null:
		errors.append("returned sandbox did not create Map + Player")
		return
	var return_spawn := returned_map.region_world("cabin_enter")
	if not _same_xz(returned_player.global_position, return_spawn):
		errors.append("runtime return did not spawn at cabin_enter")
	if Transition.trigger_allowed("cabin_enter"):
		errors.append("runtime return did not guard cabin_enter against an immediate loop")


func _run_live_fan_town_routes(errors: Array[String]) -> void:
	if change_scene_to_file(FAN_SCENE) != OK:
		errors.append("could not start fan_town runtime scene")
		return
	await process_frame
	await process_frame
	for route in FAN_ROUTES:
		var town := current_scene
		var door_path := "Map/Props/%s/Interact" % route.door
		var door := town.get_node_or_null(door_path) as EmberInteract
		if door == null:
			errors.append("runtime fan_town door is missing: %s" % route.door)
			return
		if not door.activate().begins_with("enter"):
			errors.append("runtime fan_town door did not transition: %s" % route.door)
			return
		await process_frame
		await process_frame
		var interior := current_scene
		if interior == null or interior.name != route.root:
			errors.append("%s did not enter %s" % [route.door, route.map])
			return
		var interior_map := interior.get_node_or_null("Map") as EmberMapLoader
		var interior_player := interior.get_node_or_null("Player") as CharacterBody3D
		if interior_map == null or interior_player == null:
			errors.append("%s did not create Map + Player" % route.map)
			return
		if not _same_xz(interior_player.global_position, interior_map.region_world("start")):
			errors.append("%s did not spawn at start" % route.map)
		var exit_region := interior.get_node_or_null("Map/Regions/exit") as EmberRegion
		if exit_region == null:
			errors.append("%s exit trigger is missing" % route.map)
			return
		exit_region._on_body_entered(interior_player)
		await process_frame
		await process_frame
		var returned := current_scene
		if returned == null or returned.name != "FanTown":
			errors.append("%s exit did not return to fan_town" % route.map)
			return
		var returned_map := returned.get_node_or_null("Map") as EmberMapLoader
		var returned_player := returned.get_node_or_null("Player") as CharacterBody3D
		if returned_map == null or returned_player == null:
			errors.append("fan_town return from %s lost Map + Player" % route.map)
			return
		var expected_return := returned_map.region_world(route.return)
		if not _near_xz(
			returned_player.global_position,
			expected_return,
			returned_map.imported_tile_size,
		):
			errors.append(
			"%s did not return near %s: player=%s region=%s"
			% [route.map, route.return, returned_player.global_position, expected_return]
		)
		if Transition.trigger_allowed(route.return):
			errors.append("%s return region was not guarded" % route.return)


func _same_xz(a: Vector3, b: Vector3) -> bool:
	return Vector2(a.x, a.z).is_equal_approx(Vector2(b.x, b.z))


func _near_xz(a: Vector3, b: Vector3, radius: float) -> bool:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) <= radius
