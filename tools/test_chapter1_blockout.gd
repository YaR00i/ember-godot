extends SceneTree
const MAPS = ["residential", "centre", "harbor", "estate", "woodland", "coast", "tide_cave", "home", "guild", "smith", "general_store", "alchemy", "mansion"]
const Transition = preload("res://scripts/ember_map_transition.gd")
var errors: Array[String] = []
var routes: Dictionary = {}
var visited: Dictionary = {}
var hashes: Dictionary = {}
var state: EmberExploreState
var output := ""
var transitions := 0
var screenshots: Dictionary = {}
var resume_interiors := false

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> bool:
	if not value: errors.append(message); printerr("CHECK FAIL ", message)
	return value

func descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child); result.append_array(descendants(child))
	return result

func _run() -> void:
	resume_interiors = "--resume-interiors" in OS.get_cmdline_user_args()
	state = root.get_node("EmberExploreProgress")
	state.persistence_enabled = false; state.restore_enabled = false
	output = "user://ember-tests/chapter1-gate-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	state.set_meta("world_canvas_storage_root", output.path_join("saves"))
	state.storage_root = output.path_join("saves")
	state.legacy_storage_root = output.path_join("legacy-unused")
	state.reset_new_game(); Transition.clear_for_test()
	if "--traversal-parks" in OS.get_cmdline_user_args():
		await test_traversal_parks()
		if errors.is_empty(): print("CHAPTER1 BLOCKOUT PASS: three parks / free ice / branch jumps / climb rope")
		quit(0 if errors.is_empty() else 1)
		return
	if "--pipe-slide" in OS.get_cmdline_user_args():
		await test_pipe_slide()
		if errors.is_empty(): print("CHAPTER1 BLOCKOUT PASS: pipe steering / collision / Mira / walking")
		quit(0 if errors.is_empty() else 1)
		return
	if "--ice-slope" in OS.get_cmdline_user_args():
		await test_ice_slope()
		if errors.is_empty(): print("CHAPTER1 BLOCKOUT PASS: ice acceleration / steering / dry stop / walking")
		quit(0 if errors.is_empty() else 1)
		return
	if "--zipline" in OS.get_cmdline_user_args():
		await test_zipline()
		if errors.is_empty(): await test_vine_fork()
		if errors.is_empty(): print("CHAPTER1 BLOCKOUT PASS: woodland zipline / vine fork / both transfers / Mira")
		quit(0 if errors.is_empty() else 1)
		return
	if "--pressure-battle" in OS.get_cmdline_user_args():
		await test_pressure_battle()
		if errors.is_empty(): print("CHAPTER1 BLOCKOUT PASS: carry / battle plate / passage / return")
		quit(0 if errors.is_empty() else 1)
		return
	if "--fishing" in OS.get_cmdline_user_args():
		await test_coast_fishing()
		if errors.is_empty(): print("CHAPTER1 BLOCKOUT PASS: coast fishing / cooking / Mira / cold save")
		quit(0 if errors.is_empty() else 1)
		return
	if "--tide-cache" in OS.get_cmdline_user_args():
		await test_tide_cache()
		if errors.is_empty(): print("CHAPTER1 BLOCKOUT PASS: tide cache, bypass / weighted plate / cold save")
		quit(0 if errors.is_empty() else 1)
		return
	if "--team-gate" in OS.get_cmdline_user_args():
		await test_team_gate()
		if errors.is_empty(): print("CHAPTER1 BLOCKOUT PASS: companion hold, cancel, leader switch, reopen and saved latch")
		quit(0 if errors.is_empty() else 1)
		return
	if "--day1" in OS.get_cmdline_user_args() or "--day1-clip" in OS.get_cmdline_user_args():
		await test_day1()
		if errors.is_empty(): print("CHAPTER1 BLOCKOUT PASS: Day 1 guild / ribbon / Mira / gift / mother, cold load")
		quit(0 if errors.is_empty() else 1)
		return
	for suffix in MAPS:
		var id: String = "chapter1_" + suffix
		var path := Transition.scene_path(id)
		hashes[path] = FileAccess.get_sha256(path)
		var packed = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		if not check(packed is PackedScene, "saved map missing: " + id): continue
		var scene = packed.instantiate()
		var map: EmberMapLoader = scene.get_node("Map")
		check(map.map_id == id and scene.map_id == id, "map IDs differ: " + id)
		check(not map.hydrate_legacy_regions, "legacy hydration enabled: " + id)
		check(map.compact_terrain.validation_errors().is_empty(), "terrain invalid: " + id)
		check(map.find_region("entry") != null, "default entry absent: " + id)
		check(map.spawn_world().is_equal_approx(map.region_world("entry")), "default entry order: " + id)
		var rows: Array[Dictionary] = []
		for node in descendants(scene):
			if node is EmberInteract:
				if node.kind == "door": check(not node.target_map_id.is_empty() and not node.target_region_id.is_empty(), "unbound door: %s/%s" % [id, scene.get_path_to(node)])
				if node.kind == "shop": check(not node.shop_id.is_empty(), "unbound shop: " + id)
				if node.kind == "talk": check(not node.script_id.is_empty(), "unbound talk: " + id)
			if node is EmberRegion or node is EmberInteract:
				if not node.target_map_id.is_empty():
					rows.append({"path": str(scene.get_path_to(node)), "map": node.target_map_id, "region": node.target_region_id})
		routes[id] = rows
		scene.free()
	for source in routes:
		for row in routes[source]:
			check(routes.has(row.map), "destination outside chapter graph: " + str(row))
			var destination = load(Transition.scene_path(row.map)).instantiate()
			check(destination.get_node("Map").find_region(row.region) != null, "missing named destination: %s -> %s/%s" % [source, row.map, row.region])
			destination.free()
	if errors.is_empty():
		if resume_interiors:
			await test_interior_routes()
		else:
			if await goto_map("chapter1_residential"):
				await visit_graph("chapter1_residential")
				check(visited.size() == MAPS.size(), "not all maps visited natively")
		if errors.is_empty(): await test_bridge()
		if errors.is_empty(): await test_relocation()
		if errors.is_empty(): await test_save()
	for path in hashes: check(FileAccess.get_sha256(path) == hashes[path], "test changed source scene: " + path)
	if current_scene != null:
		var old = current_scene; current_scene = null; old.queue_free(); await process_frame
	if errors.is_empty():
		print("CHAPTER1 BLOCKOUT PASS maps=", visited.size(), " transitions=", transitions, " resumed_interiors=", resume_interiors)
		print("  grouped building/NPC relocation + saved reopen; UI talk/shop + unique stock; cold owner load; real bridge walk")
		print("  EVIDENCE ", ProjectSettings.globalize_path(output))
	else:
		printerr("CHAPTER1 BLOCKOUT FAIL ", errors)
	quit(0 if errors.is_empty() else 1)

func wait_map(id: String) -> bool:
	for frame in 2400:
		await process_frame
		if current_scene != null and current_scene.get("map_id") == id and current_scene.get("_startup_complete"):
			for tick in 3: await physics_frame
			var player = current_scene.get_node_or_null("Player")
			if not check(player != null, "missing player: " + id): return false
			check(player.global_position.is_finite() and player.global_position.y > -16, "unsupported player: " + id)
			check(state.active_hero_ids == ["protagonist", "mira"], "blockout roster changed: " + id)
			check(current_scene.get_node_or_null("PartyFollowers") != null, "followers absent: " + id)
			if id in ["chapter1_centre", "chapter1_general_store"] and not screenshots.has(id):
				screenshots[id] = true
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(output.path_join(id + ".png"))
			print("READY ", id)
			return true
	return check(false, "startup timeout: " + id)

func goto_map(id: String) -> bool:
	Transition.clear_for_test()
	if not check(change_scene_to_file(Transition.scene_path(id)) == OK, "cannot load " + id): return false
	return await wait_map(id)

func travel(row: Dictionary) -> bool:
	var scene = current_scene
	var node = scene.get_node_or_null(NodePath(row.path))
	if not check(node != null, "route node absent " + str(row)): return false
	if node is EmberRegion: node._on_body_entered(scene.get_node("Player"))
	else: check(node.activate().begins_with("enter"), "door refused: " + str(row))
	if not await wait_map(row.map): return false
	transitions += 1
	var map: EmberMapLoader = current_scene.get_node("Map")
	var expected = map.region_world(row.region)
	var actual: Vector3 = current_scene.get_node("Player").global_position
	check(Vector2(expected.x, expected.z).distance_to(Vector2(actual.x, actual.z)) < 2.0, "wrong arrival: %s/%s expected%s actual%s" % [row.map, row.region, expected, actual])
	check(not Transition.trigger_allowed(row.region), "arrival guard missing: " + str(row))
	return errors.is_empty()

func physics_ticks(count: int) -> void:
	for index in count:
		await physics_frame


func test_pipe_slide() -> void:
	if not await goto_map("chapter1_woodland"): return
	var player := current_scene.get_node("Player") as EmberPlayer
	var route = current_scene.get_node("Map/Props/PipeSlide")
	var landing: Vector3 = route.get_node("Landing").global_position
	player.global_position = route.global_position + Vector3(-70, -23.5, 0)
	player.camera_rig.yaw = 0.0
	player.party_followers.reset_to_leader()
	await physics_ticks(5)
	Input.action_press("move_east")
	var saw_approach_blend := false
	for frame in 180:
		if player.camera_rig._pipe_weight > 0.05 and player.camera_rig._pipe_weight < 0.95 and player.zipline == null:
			saw_approach_blend = true
		if player.global_position.x >= route.global_position.x - 7.0: break
		await physics_frame
	Input.action_release("move_east")
	check(saw_approach_blend and player.camera_rig._pipe_weight > 0.95,
		"camera did not blend toward the pipe before F")
	var entry := player.global_position
	var visual := player.get_node("Viz") as Node3D
	var normal_basis := visual.basis
	var camera := player.camera_rig.get_node("Camera3D") as Camera3D
	var exploration_yaw := player.camera_rig.yaw
	if not check(player._nearest() == route and player.activate_interact(route) and player.zipline == route,
		"could not walk to the pipe and start via F: %s" % entry): return
	await physics_ticks(85)
	check(player.zipline == null and player.global_position.distance_to(entry) < 2.0,
		"straight slide did not collide with the first obstacle and reset")
	check(visual.basis.is_equal_approx(normal_basis) and player.camera_rig.pipe_forward.is_zero_approx(),
		"collision did not restore the exploration pose and camera")
	if not check(player.activate_interact(route) and player.zipline == route, "could not retry right side"): return
	Input.action_press("move_east")
	await physics_ticks(72)
	Input.action_release("move_east")
	check(player.zipline == route and player.global_position.x > route.global_position.x + 48.0,
		"right-side steering did not pass the center obstacle")
	await physics_ticks(75)
	check(player.zipline == null and player.global_position.distance_to(entry) < 2.0,
		"side barrier did not block the right-side route")
	if not check(player.activate_interact(route) and player.zipline == route, "could not retry pipe"): return
	Input.action_press("move_west")
	await physics_ticks(48)
	Input.action_release("move_west")
	var mira: Node3D = player.party_followers.combat_world_actors().get("mira")
	check(player.zipline == route and player.global_position.z < route.global_position.z - 15.0
		and mira != null and mira.global_position.z < route.global_position.z - 5.0,
		"steering did not move Kai and the trailing companion up the wall")
	await RenderingServer.frame_post_draw
	var camera_offset := camera.global_position - player.global_position
	var forward: Vector3 = route.pipe_forward()
	var across: Vector3 = route.rider_position(player._zipline_elapsed) - route.global_position.lerp(
		landing, player._zipline_elapsed / route.duration()) - Vector3.UP * 0.5
	var radial_tangent := Vector3(0.0, across.z, 25.0 - across.y)
	var expected_up := radial_tangent.cross(forward).normalized()
	check(visual.global_basis.y.normalized().dot(expected_up) > 0.99 and absf(visual.global_basis.y.z) > 0.5,
		"Kai did not lean perpendicular to the pipe wall")
	check(camera_offset.dot(forward) < -35.0 and camera_offset.y > 20.0
		and (-camera.global_basis.z).dot(forward) > 0.8,
		"pipe camera did not follow above and behind Kai")
	var frame_size := root.get_visible_rect().size
	var torso_uv := camera.unproject_position(visual.global_position) / frame_size
	check(Rect2(0.2, 0.15, 0.6, 0.72).has_point(torso_uv), "Kai drifted to the edge of the pipe camera")
	var capture := output.path_join("woodland-pipe-slide.png")
	root.get_texture().get_image().save_png(capture)
	print("PIPE CAPTURE ", ProjectSettings.globalize_path(capture))
	await physics_ticks(200)
	check(player.zipline == null and player.is_on_floor() and player.global_position.distance_to(landing) < 2.0,
		"steered slide did not pass the obstacles and reach the lower trail")
	check(visual.basis.is_equal_approx(normal_basis) and player.camera_rig.pipe_forward.is_zero_approx()
		and is_equal_approx(player.camera_rig.yaw, exploration_yaw)
		and is_equal_approx(camera.fov, player.camera_rig.fov),
		"landing did not restore the exploration pose and camera")
	check(mira != null and mira.global_position.distance_to(landing) < 12.0, "Mira did not land after Kai")
	var before := player.global_position
	Input.action_press("move_east")
	await physics_ticks(12)
	Input.action_release("move_east")
	check(player.global_position.distance_to(before) > 2.0, "walking did not resume after the pipe")
	var old_duration: float = route.duration()
	route.cross_section = 1
	route.radius = 30.0
	route.segment_count = 8
	route.speed = 78.0
	route._build_shell()
	route._place_obstacles()
	var shell := route.get_node("PipeShell") as MeshInstance3D
	var center_slot := route.get_node("CenterSlot") as Node3D
	check(shell.get_aabb().size.y > 80.0 and center_slot.position.x < 40.0
		and route.duration() < old_duration, "full shell, segment layout or configurable speed did not update")
	center_slot.get_node("CenterBarrier").collision_layer = 0
	route.get_node("SideSlot/SideBarrier").collision_layer = 0
	player.global_position = entry
	player.velocity = Vector3.ZERO
	await physics_ticks(3)
	if not check(player.begin_zipline(route), "could not mount the full tube"): return
	Input.action_press("move_west")
	await physics_ticks(86)
	Input.action_release("move_west")
	check(player.zipline == route and visual.global_basis.y.y < -0.4, "full tube did not allow steering toward its roof")
	await RenderingServer.frame_post_draw
	var full_capture := output.path_join("woodland-pipe-full.png")
	root.get_texture().get_image().save_png(full_capture)
	print("FULL PIPE CAPTURE ", ProjectSettings.globalize_path(full_capture))
	for frame in 100:
		if player._route_airborne: break
		await physics_frame
	if not check(player._route_airborne and player.global_position.y > landing.y + 25.0
		and player.velocity.x > 65.0, "roof exit lost height or forward momentum"): return
	var launch := player.global_position
	await physics_ticks(32)
	check(player.global_position.x > launch.x + 25.0 and player.global_position.y < launch.y
		and visual.global_basis.y.dot(Vector3.UP) > 0.98, "air exit did not travel forward, fall and right the rider")
	await physics_ticks(150)
	check(player.zipline == null and player.is_on_floor() and player.global_position.x > landing.x + 30.0
		and mira.global_position.distance_to(player.global_position) < 12.0,
		"air exit did not land the party beyond the lip and release control")
	var path := Path3D.new()
	path.name = "RoutePath"
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3.ZERO, Vector3.ZERO, Vector3(18, -3, 5))
	path.curve.add_point(Vector3(66, -11, 23), Vector3(-20, 3, 0), Vector3(20, -3, 0))
	path.curve.add_point(Vector3(144, -24, 0), Vector3(-22, 4, 6))
	route.add_child(path)
	route._refresh_geometry()
	var slot_progress := 2.0 / float(route.segment_count)
	check(center_slot.global_position.distance_to(route.route_point(slot_progress)) < 0.1
		and shell.get_aabb().end.z > 45.0, "pipe shell or obstacle did not move to the curved route")
	player.global_position = entry
	player.velocity = Vector3.ZERO
	await physics_ticks(4)
	if not check(player.begin_zipline(route), "could not mount the curved tube"): return
	await physics_ticks(50)
	check(player.zipline == route and player.global_position.z > route.global_position.z + 14.0,
		"curved tube rider did not follow its lateral bend")
	await physics_ticks(135)
	check(player.zipline == null and player.is_on_floor() and player.global_position.distance_to(landing) < 2.0,
		"curved tube did not reach the exit")


func test_ice_slope() -> void:
	if not await goto_map("chapter1_woodland"): return
	var player := current_scene.get_node("Player") as EmberPlayer
	var slope := current_scene.get_node("Map/Props/IceSlope") as Node3D
	player.global_position = slope.global_position + Vector3(-61, 0.5, 0)
	player.camera_rig.yaw = 0.0
	player.party_followers.reset_to_leader()
	await physics_ticks(5)
	Input.action_press("move_east")
	for frame in 200:
		if player._sliding_on_ice: break
		await physics_frame
	Input.action_release("move_east")
	if not check(player._sliding_on_ice, "walk from the trail never reached ice: %s" % player.global_position): return
	var initial_speed := player._ice_momentum.x
	var initial_z := player.global_position.z
	Input.action_press("move_south")
	await physics_ticks(36)
	Input.action_release("move_south")
	check(player._sliding_on_ice and player._ice_momentum.x > initial_speed + 10.0, "ice did not accelerate downhill")
	check(player.global_position.z > initial_z + 2.0 and absf(player._ice_momentum.z) < player._ice_momentum.x,
		"ice steering did not provide limited lateral control")
	await RenderingServer.frame_post_draw
	var capture := output.path_join("woodland-ice-slope.png")
	root.get_texture().get_image().save_png(capture)
	print("ICE SLOPE CAPTURE ", ProjectSettings.globalize_path(capture))
	for frame in 240:
		if player._ice_momentum.is_zero_approx(): break
		await physics_frame
	check(player.global_position.x >= slope.global_position.x + 84.0 and player.is_on_floor()
		and player._ice_momentum.is_zero_approx(), "Kai did not stop on the dry runout: %s" % player.global_position)
	var stopped := player.global_position
	await physics_ticks(12)
	check(player.global_position.distance_to(stopped) < 0.2, "Kai continued drifting on dry ground")
	Input.action_press("move_east")
	await physics_ticks(12)
	Input.action_release("move_east")
	check(player.global_position.distance_to(stopped) > 2.0, "ordinary walking did not resume")


func test_zipline() -> void:
	if not await goto_map("chapter1_woodland"): return
	var player := current_scene.get_node("Player") as EmberPlayer
	var route = current_scene.get_node("Map/Props/Zipline")
	var mira: Node3D = player.party_followers.combat_world_actors().get("mira")
	if not check(mira != null, "Mira missing on the woodland route"): return
	var landing: Vector3 = route.get_node("Landing").global_position
	player.global_position = landing + Vector3.UP
	check(not player.begin_zipline(route), "mounted from the lower trail")
	player.global_position = route.global_position + Vector3(-65, -23.5, 0)
	player.camera_rig.yaw = 0.0
	player.party_followers.reset_to_leader()
	await physics_ticks(5)
	Input.action_press("move_east")
	for frame in 150:
		if player.global_position.x >= route.global_position.x - 7.0: break
		await physics_frame
	Input.action_release("move_east")
	if not check(absf(player.global_position.y - route.global_position.y) < 2.0,
		"walkable ramp did not reach upper deck: %s" % player.global_position): return
	var departure := player.global_position
	if not check(player._nearest() == route and player.activate_interact(route) and player.zipline == route,
		"F interaction did not mount the cable at the upper deck"): return
	await physics_ticks(48)
	check(player.zipline == route and player.global_position.x > mira.global_position.x
		and mira.global_position.x > route.global_position.x, "Mira did not follow Kai on the cable")
	check(player._ui_blocks_movement() and not player.world_strike(), "exploration commands remained available mid-ride")
	await RenderingServer.frame_post_draw
	var capture := output.path_join("woodland-zipline.png")
	root.get_texture().get_image().save_png(capture)
	print("ZIPLINE CAPTURE ", ProjectSettings.globalize_path(capture))
	await physics_ticks(120)
	check(player.zipline == null and player.is_on_floor() and player.global_position.distance_to(landing) < 2.0,
		"Kai did not land at the lower trail")
	check(mira.global_position.distance_to(landing) < 12.0, "Mira did not arrive on the lower trail")
	var before := player.global_position
	Input.action_press("move_east")
	await physics_ticks(12)
	Input.action_release("move_east")
	check(player.global_position.distance_to(before) > 2.0, "walking did not resume on landing")
	var blocker := test_field_box(route, route.rider_position(route.duration() * 0.5) + Vector3.UP * 8.0, Vector3(6, 18, 12))
	player.global_position = departure
	await physics_ticks(3)
	check(player.begin_zipline(route), "repeat ride refused before the obstacle")
	await physics_ticks(90)
	check(player.zipline == null and player.global_position.distance_to(departure) < 2.0,
		"blocked cable did not return the party to departure")
	blocker.queue_free()
	await physics_ticks(3)
	route.route_mode = 1
	route._refresh_geometry()
	check(route.prompt() == "Спуститься по лиане" and route.get_node("RouteLine").visible,
		"switching the same route to vine did not update the interaction and visual")
	if not check(player.activate_interact(route) and player.zipline == route, "vine did not use the shared entry"): return
	await physics_ticks(180)
	check(player.zipline == null and player.global_position.distance_to(landing) < 2.0,
		"vine did not use the shared landing")


func test_vine_fork() -> void:
	var player := current_scene.get_node("Player") as EmberPlayer
	var main = current_scene.get_node("Map/Props/MainVine")
	var side = current_scene.get_node("Map/Props/SideVine")
	var mira: Node3D = player.party_followers.combat_world_actors().get("mira")
	var bend: Vector3 = main.route_point(0.45)
	var chord: Vector3 = main.route_point(0.0).lerp(main.route_point(1.0), 0.45)
	check(bend.z > chord.z + 6.0 and main.route_length() > main.route_point(0.0).distance_to(main.route_point(1.0)),
		"authored vine curve did not bend away from the straight chord")
	player.global_position = main.global_position + Vector3(-66, -23.5, 0)
	player.camera_rig.yaw = 0.0
	player.party_followers.reset_to_leader()
	await physics_ticks(5)
	Input.action_press("move_east")
	for frame in 150:
		if player.global_position.x >= main.global_position.x - 7.0: break
		await physics_frame
	Input.action_release("move_east")
	var entry := player.global_position
	if not check(player._nearest() == main and player.activate_interact(main) and player.zipline == main,
		"could not walk to the first vine and mount it"): return
	await physics_ticks(4)
	Input.action_press("move_west")
	await physics_ticks(2)
	Input.action_release("move_west")
	check(player._vine_target == null, "vine jump worked before the marked window")
	await physics_ticks(50)
	check(player.zipline == main and player.global_position.z > chord.z + 5.0,
		"Kai followed the straight chord instead of the bend")
	await physics_ticks(125)
	check(player.zipline == null and player.global_position.distance_to(main.landing.global_position) < 2.0,
		"staying on the main vine did not reach its own exit")
	for switch_back in [false, true]:
		player.global_position = entry
		player.velocity = Vector3.ZERO
		await physics_ticks(4)
		if not check(player.activate_interact(main) and player.zipline == main, "could not restart the vine"): return
		await physics_ticks(38)
		Input.action_press("move_west")
		await physics_ticks(3)
		Input.action_release("move_west")
		if not check(player._vine_target == side, "A did not start the left transfer inside its window"): return
		await physics_ticks(10)
		check(player.global_position.y > main.rider_position(player._zipline_elapsed).y + 4.0, "vine jump had no arc")
		await RenderingServer.frame_post_draw
		var capture := output.path_join("woodland-vine-jump.png")
		root.get_texture().get_image().save_png(capture)
		await physics_ticks(14)
		if not check(player.zipline == side, "left jump did not attach to the side vine"): return
		if switch_back:
			await physics_ticks(8)
			Input.action_press("move_east")
			await physics_ticks(3)
			Input.action_release("move_east")
			if not check(player._vine_target == main, "D did not start the right transfer"): return
		await physics_ticks(170)
		var expected: Vector3 = main.landing.global_position if switch_back else side.landing.global_position
		check(player.zipline == null and player.is_on_floor() and player.global_position.distance_to(expected) < 2.0,
			"vine transfer did not reach the chosen exit: %s expected %s" % [player.global_position, expected])
		check(mira != null and mira.global_position.distance_to(expected) < 12.0, "Mira did not follow the chosen branch")


func test_traversal_parks() -> void:
	if not await goto_map("chapter1_woodland"): return
	for index in 3:
		var door := current_scene.get_node("Map/Props/ParkDoor%d" % index) as EmberInteract
		var player := current_scene.get_node("Player") as EmberPlayer
		player.global_position = door.global_position
		if not check(player._nearest() == door and player.activate_interact(door), "woodland entrance was not usable"): return
		var park: String = ["traversal_ice_park", "traversal_vine_park", "traversal_cable_park"][index]
		if not await wait_map(park): return
		player = current_scene.get_node("Player") as EmberPlayer
		player.camera_rig.yaw = 0.0
		if index == 0:
			await test_ice_sled(player)
			player.global_position = Vector3(300, 9.4, 189)
			await physics_ticks(5)
			Input.action_press("move_east")
			await physics_ticks(54)
			Input.action_release("move_east")
			var coast := player.global_position
			await physics_ticks(20)
			check(player._sliding_on_ice and player.global_position.x > coast.x + 4.0, "free ice did not retain inertia")
			Input.action_press("move_east")
			await physics_ticks(135)
			Input.action_release("move_east")
			check(player.global_position.y > 11.0, "free ice did not allow an uphill run")
			player.global_position = Vector3(444, 18.7, 224)
			player.velocity = Vector3.ZERO
			player._ice_momentum = Vector3.ZERO
			await physics_ticks(100)
			check(player.global_position.x < 437.0 and player.global_position.y < 18.5,
				"ice slope did not pull Kai downhill: %s" % player.global_position)
			player.global_position = Vector3(330, 9.4, 259)
			player.velocity = Vector3.ZERO
			player._ice_momentum = Vector3.ZERO
			await physics_ticks(5)
			Input.action_press("move_south")
			await physics_ticks(75)
			Input.action_release("move_south")
			await physics_ticks(38)
			check(player.global_position.z > 274.0 and not player._sliding_on_ice and player._ice_momentum.is_zero_approx(),
				"ice coast did not stop on dry ground")
		else:
			var first = current_scene.get_node("Map/Props/Lane1")
			var next = current_scene.get_node("Map/Props/Lane2")
			check(current_scene.get_node_or_null("Map/Props/Lane3") != null and first.route_mode == (1 if index == 1 else 0),
				"park does not have the intended four lanes")
			player.global_position = first.route_point(0.0) + Vector3(-6, 0.5, 0)
			player.velocity = Vector3.ZERO
			await physics_ticks(5)
			if not check(player.activate_interact(first) and player.zipline == first, "could not mount park route"): return
			await physics_ticks(50)
			if index == 2:
				check(first.rope_offset(0.0).is_zero_approx() and first.rope_offset(1.0).is_zero_approx()
					and first.rope_offset(player._zipline_elapsed / first.duration()).y < -0.5,
					"cable did not sag under Kai with both endpoints pinned")
			Input.action_press("move_east")
			await physics_ticks(3)
			Input.action_release("move_east")
			check(player._vine_target == next, "park route did not start a right jump")
			await physics_ticks(170)
			check(player.zipline == null and player.global_position.distance_to(next.route_point(1.0)) < 2.0,
				"park route did not reach the switched exit")
			if index == 2:
				var rope = current_scene.get_node("Map/Props/ClimbRope")
				player.global_position = rope.route_point(1.0) + Vector3.UP * 0.5
				check(not player.begin_zipline(rope), "rope worked from below before release")
				player.global_position = rope.route_point(0.0)
				check(player.activate_interact(rope) and state.flags.get(rope.rope_flag, false), "rope was not released from above")
				player.global_position = rope.route_point(1.0) + Vector3.UP * 0.5
				await physics_ticks(5)
				if not check(player._nearest() == rope and player.activate_interact(rope) and player.zipline == rope,
					"deployed rope was not usable from below"): return
				await physics_ticks(17)
				var tail: Vector3 = rope.rope_offset(1.0)
				await physics_ticks(9)
				check(rope.rope_offset(0.0).is_zero_approx() and tail.distance_to(rope.rope_offset(1.0)) > 0.2,
					"climbing rope did not sway at the free end")
				await physics_ticks(99)
				check(player.zipline == null and player.global_position.distance_to(rope.route_point(0.0)) < 2.0,
					"rope ascent did not land on the upper deck")
		var back := current_scene.get_node("Map/Props/Return") as EmberInteract
		player.global_position = back.global_position
		if not check(player.activate_interact(back), "return door refused"): return
		if not await wait_map("chapter1_woodland"): return
	var cable_door := current_scene.get_node("Map/Props/ParkDoor2") as EmberInteract
	var leader := current_scene.get_node("Player") as EmberPlayer
	leader.global_position = cable_door.global_position
	leader.activate_interact(cable_door)
	if await wait_map("traversal_cable_park"):
		var deployed = current_scene.get_node("Map/Props/ClimbRope")
		check(deployed.get_node("RouteLine").visible and deployed._rope_deployed(), "released rope was lost after reentry")


func test_ice_sled(player: EmberPlayer) -> void:
	var sled = current_scene.get_node("Map/Props/Sled")
	var parked: Transform3D = sled.sled_visual.global_transform
	player.global_position = Vector3(136, 8.5, 224)
	await physics_ticks(5)
	Input.action_press("move_east")
	for frame in 150:
		if player.global_position.x >= 185.0: break
		await physics_frame
	Input.action_release("move_east")
	if not check(player._nearest() == sled and player.activate_interact(sled) and player.ice_sled == sled,
		"could not walk up and mount the sled via F at %s" % player.global_position): return
	var launch := player.global_position
	await physics_ticks(33)
	var straight_speed := player._sled_speed
	check(straight_speed > 14.0 and player.global_position.y < launch.y, "sled did not gain speed downhill")
	Input.action_press("move_east")
	await physics_ticks(14)
	Input.action_release("move_east")
	check(player._sled_heading.z > 0.1 and player._sled_heading.x > 0.8, "sled steering was absent or excessive")
	for frame in 120:
		if player.global_position.x > 245.0 or player.ice_sled == null: break
		await physics_frame
	if not check(player.ice_sled == sled and player.global_position.x > 245.0,
		"steered sled did not pass both downhill obstacles: %s" % player.global_position): return
	Input.action_press("move_west")
	await physics_ticks(12)
	Input.action_release("move_west")
	for frame in 140:
		if player.global_position.x > 254.0 or player.ice_sled == null: break
		await physics_frame
	var flat_start := player.global_position
	var flat_speed := player._sled_speed
	await physics_ticks(35)
	check(player.ice_sled == sled and flat_start.x > 254.0 and player.global_position.x > flat_start.x + 15.0
		and player._sled_speed > 20.0 and player._sled_speed < flat_speed,
		"sled did not retain and gradually lose momentum on flat ice")
	for frame in 110:
		if player.global_position.x > 299.0 and not player.is_on_floor(): break
		await physics_frame
	if not check(player.ice_sled == sled and not player.is_on_floor() and player.velocity.y > 2.0,
		"sled did not launch with upward velocity: %s / %s" % [player.global_position, player.velocity]): return
	var takeoff_speed := player._sled_speed
	await RenderingServer.frame_post_draw
	var capture := output.path_join("ice-park-sled.png")
	root.get_texture().get_image().save_png(capture)
	print("SLED CAPTURE ", ProjectSettings.globalize_path(capture))
	await physics_ticks(10)
	check(not player.is_on_floor() and absf(player._sled_speed - takeoff_speed) < 0.1,
		"sled lost horizontal speed in the air")
	for frame in 100:
		if player.is_on_floor(): break
		await physics_frame
	var touchdown := player.global_position
	check(player.ice_sled == sled and player.is_on_floor() and touchdown.x > 315.0
		and player._sled_speed > takeoff_speed * 0.9,
		"sled did not land on the far ice with momentum: %s" % touchdown)
	await physics_ticks(16)
	check(player.global_position.x > touchdown.x + 4.0, "sled stopped after landing")
	for frame in 450:
		if player.ice_sled == null: break
		await physics_frame
	check(player.ice_sled == null and sled.sled_visual.global_transform.is_equal_approx(parked),
		"sled did not dismount and reset for the next run")


func test_team_gate() -> void:
	if not await goto_map("chapter1_tide_cave"): return
	var gate = current_scene.get_node("Map/Props/TideTeamGate")
	var player := current_scene.get_node("Player") as EmberPlayer
	var followers := player.party_followers as EmberPartyFollowers
	var outside := gate.get_node("OutsideLever/MechanismLeverInput") as EmberInteract
	var inside := gate.get_node("InsideLever/MechanismLeverInput") as EmberInteract
	var anchor := outside.get_parent() as Node3D
	var completion := "mechanism_latch_tide_team_secured"
	if not check(gate.diagnostics.is_empty(), str(gate.diagnostics)): return
	await physics_ticks(60)
	check(gate.openness < 0.01, "gate should start closed")
	player.global_position = anchor.global_position + Vector3(0, 0.5, 13)
	followers.reset_to_leader()
	check(player.activate_interact(outside) and followers.assigned_to(anchor), "could not assign Mira")
	check(not gate.values.get("outside", false), "lever fired before Mira arrived")
	await physics_ticks(100)
	check(followers.holding_at(anchor) and gate.openness > 0.99, "Mira did not hold gate open")
	check(not state.flags.has("mechanism_tide_team_outside"), "temporary lever was saved")
	check(player.activate_interact(outside) and not followers.assigned_to(anchor), "recall did not release Mira")
	await physics_ticks(60)
	check(gate.openness < 0.01, "recall left gate open")
	check(player.activate_interact(outside), "could not reassign Mira")
	state.set_exploration_leader("mira")
	check(not followers.assigned_to(anchor), "switching leader kept the assignment")
	state.set_exploration_leader("protagonist")
	player.global_position = anchor.global_position + Vector3(0, 0.5, 13)
	followers.reset_to_leader()
	check(player.activate_interact(outside), "could not assign before reload")
	await physics_ticks(95)
	state.persistence_enabled = true
	check(state.save_slot(1), "could not save unfinished room")
	check(state.load_slot(1), "could not load unfinished room")
	if not await goto_map("chapter1_tide_cave"): return
	gate = current_scene.get_node("Map/Props/TideTeamGate")
	player = current_scene.get_node("Player")
	followers = player.party_followers
	outside = gate.get_node("OutsideLever/MechanismLeverInput")
	inside = gate.get_node("InsideLever/MechanismLeverInput")
	anchor = outside.get_parent()
	await physics_ticks(60)
	check(gate.openness < 0.01 and not followers.assigned_to(anchor), "unfinished hold survived scene reload")
	player.global_position = anchor.global_position + Vector3(0, 0.5, 13)
	followers.reset_to_leader()
	check(player.activate_interact(outside), "could not solve after reload")
	await physics_ticks(100)
	check(gate.openness > 0.99, "gate did not reopen")
	var query := PhysicsRayQueryParameters3D.create(gate.global_position + Vector3(0, 16, 25), gate.global_position + Vector3(0, 16, -25), 1)
	check(player.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "open gate still blocks the passage")
	player.global_position = inside.global_position + Vector3(0, 0.5, -8)
	check(player.activate_interact(inside), "inside lever not usable")
	await physics_ticks(60)
	check(state.flags.get(completion, false) and gate.openness > 0.99, "inside lever did not secure gate")
	check(not followers.assigned_to(anchor), "completion did not release Mira")
	check(state.save_slot(1), "could not save completed room")
	var cold := EmberExploreState.new()
	cold.storage_root = state.storage_root
	cold.restore_enabled = false
	check(cold.load_slot(1) and cold.flags.get(completion, false), "saved latch did not restore")
	cold.free()
	check(state.load_slot(1), "could not load completed room")
	if not await goto_map("chapter1_tide_cave"): return
	gate = current_scene.get_node("Map/Props/TideTeamGate")
	await physics_ticks(60)
	check(gate.openness > 0.99, "completed gate closed on reload")


func test_field_box(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)
	parent.add_child(body)
	body.global_position = at
	return body


func check_field_height_and_placement(host: Node3D, player: EmberPlayer, footprint: CapsuleShape3D) -> void:
	const Geometry = preload("res://scripts/ember_field_geometry.gd")
	const Terrain = preload("res://scripts/prototypes/ember_combat_terrain.gd")
	var space := player.get_world_3d().direct_space_state
	var origin := Vector3(1500, 8, 1500)
	var fixture := Node3D.new()
	host.add_child(fixture)
	for index in 4:
		var height: float = [0.0, 7.0, 14.0, 0.0][index]
		var tread := test_field_box(fixture, origin + Vector3(index * 16 + 8, height * 0.5 - 1, 8), Vector3(16, height + 2, 16))
		tread.add_to_group("ember_battle_walkable")
	var near_wall := origin + Vector3(0, 0, 64)
	test_field_box(fixture, near_wall + Vector3(24, -1, 8), Vector3(48, 2, 16))
	test_field_box(fixture, near_wall + Vector3(8, 8, 8), Vector3(12, 16, 12))
	var ramp_origin := origin + Vector3(0, 0, 96)
	var ramp := test_field_box(fixture, ramp_origin + Vector3(16, -1, 8), Vector3(38, 2, 16))
	ramp.rotation.z = deg_to_rad(8.0)
	ramp.add_to_group("ember_battle_walkable")
	await physics_ticks(3)
	var stairs := Geometry.sample(space, origin, Vector2i(4, 1), footprint, [])
	var cells := {}
	for index in 4: cells[Terrain.cell_key(Vector2i(index, 0))] = {"blocked": false, "elevation": 0}
	var snapshot := {"fieldGeometry": stairs, "grid": {"cells": cells}}
	var bottom := Vector2i(0, 0)
	var middle := Vector2i(1, 0)
	var top := Vector2i(2, 0)
	var landing := Vector2i(3, 0)
	check(stairs.blocked.is_empty() and stairs.edges.is_empty(), "stairs or ledge became blocked: " + str(stairs))
	check(Terrain.can_step(snapshot, bottom, middle, 1) and Terrain.can_step(snapshot, top, middle, 0), "stair traversal failed")
	check(Terrain.can_step(snapshot, top, landing, 0) and not Terrain.can_step(snapshot, landing, top, 1), "drop/ascent limits wrong")
	check(Terrain.fall_damage(snapshot, top, landing) > 0 and Terrain.fall_damage(snapshot, top, middle) == 0, "fall damage did not use real height")
	check(is_equal_approx(float(stairs.offsets.get(top, 0)), 14.0), "exact physical floor offset lost")
	var incline := Geometry.sample(space, ramp_origin, Vector2i(2, 1), footprint, [])
	check(incline.blocked.is_empty() and incline.edges.is_empty() and float(incline.offsets.get(Vector2i.RIGHT, 0)) > 1
		and incline.walkEdges.has(Terrain.world_edge_key(Vector2i.ZERO, Vector2i.RIGHT)), "shallow incline was not captured as walkable")
	var field := EmberBattlefieldResource.new()
	field.width = 2
	field.height = 1
	field.party_deployment_cells = [Vector2i.ZERO]
	var enemy_cells: Array[Vector2i] = [Vector2i.RIGHT]
	var moved := Geometry.find_placement(space, near_wall, field, footprint, [], enemy_cells, 1, false)
	check(moved.get("corner") == near_wall + Vector3.RIGHT * 16, "wall did not shift the placement by one cell")
	check(Geometry.find_placement(space, near_wall, field, footprint, [], enemy_cells, 1, true).is_empty(), "fixed puzzle field shifted")
	fixture.queue_free()


func test_native_stair_battle(player: EmberPlayer) -> void:
	const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
	const Terrain = preload("res://scripts/prototypes/ember_combat_terrain.gd")
	const Host = preload("res://scripts/ember_field_encounter.gd")
	var origin := Vector3(1200, 8, 1200)
	var host := Host.new()
	host.encounter_id = "shore_boar"
	host.field_corner = origin
	current_scene.add_child(host)
	for column in 6:
		var height: float = [0.0, 0.0, 7.0, 14.0, 0.0, 0.0][column]
		var tread := test_field_box(host, origin + Vector3(column * 16 + 8, height * 0.5 - 1, 40), Vector3(16, height + 2, 80))
		tread.add_to_group("ember_battle_walkable")
	test_field_box(host, origin + Vector3(8, 8, 40), Vector3(13, 16, 80))
	player.interaction_ui.close()
	player.global_position = origin + Vector3(24, 0.5, 40)
	await physics_ticks(4)
	if not check(host.engage("player") == OK, "stair battle entry failed: " + host.last_error): return
	for frame in 450:
		if host.presentation_complete: break
		await process_frame
	if not check(host.presentation_complete, "stair entry did not finish"): return
	var hud = host.battle.get_node("CombatHUDLayer/CombatHUD")
	check(is_equal_approx(float(hud.in_place_context.transform.origin.x), origin.x + 16), "native arena did not shift off wall")
	if hud._deployment_active:
		check(hud._confirm_deployment(), "stairs deployment refused")
	hud._state.units.protagonist.nextAt = 0.0
	hud._state.units.mira.nextAt = 9000.0
	hud._state.units.shore_boar.nextAt = 9000.0
	var snapshot: Dictionary = hud.state_snapshot()
	var top := Vector2i(2, 2)
	var climb := Grid.command_preview(snapshot, "defend", "protagonist", top)
	if not check(climb.get("ok", false), "battle could not climb steps"): return
	hud._current_preview = climb
	hud._confirm_action()
	await physics_ticks(55)
	var actor: Node3D = host._world_actors.get("protagonist")
	check(actor != null and absf(actor.global_position.y - (origin.y + 14.0)) < 0.7, "actor did not land on exact stair height")
	snapshot = hud.state_snapshot()
	var bottom := Vector2i(3, 1)
	check(Terrain.elevation(snapshot, top) == 2 and Terrain.elevation(snapshot, bottom) == 0, "battle heights missing")
	var drop := Grid.command_preview(snapshot, "defend", "protagonist", bottom)
	if not check(drop.get("ok", false) and int(drop.get("damage", {}).get("protagonist", 0)) > 0, "battle drop did not preview fall damage"): return
	var hp_before: int = snapshot.units.protagonist.hp
	hud._current_preview = drop
	hud._confirm_action()
	await physics_ticks(55)
	check(hud._state.units.protagonist.hp < hp_before and absf(actor.global_position.y - origin.y) < 0.7, "drop did not land and apply damage")
	EmberCombatTransition.clear_for_test()
	host.finish_in_place()
	host.queue_free()


func test_pressure_battle() -> void:
	const Combat = preload("res://scripts/prototypes/ember_combat_prototype.gd")
	const Grid = preload("res://scripts/prototypes/ember_combat_grid.gd")
	const Terrain = preload("res://scripts/prototypes/ember_combat_terrain.gd")
	const Geometry = preload("res://scripts/ember_field_geometry.gd")
	const CRATE := "world_item:chapter1_tide_battle_crate"
	const HEAVY := "world_item:chapter1_tide_battle_heavy_crate"
	if not await goto_map("chapter1_tide_cave"): return
	var host := current_scene.get_node("Map/Props/TidePressureEncounter") as Node3D
	var player := current_scene.get_node("Player") as EmberPlayer
	var crate := host.get_node("Crate") as RigidBody3D
	var circuit = host.get_node("Circuit")
	var corner: Vector3 = host.field_corner
	# Real world geometry deliberately absent from the authored battlefield.
	test_field_box(host, corner + Vector3(16, 8, 8), Vector3(1, 16, 12))
	test_field_box(host, corner + Vector3(40, 8, 8), Vector3(12, 16, 12))
	var probe_corner := Vector3(1400, 8, 1400)
	var floor := test_field_box(host, probe_corner + Vector3(7.5, -1, 8), Vector3(15, 2, 16))
	var second_floor := test_field_box(host, probe_corner + Vector3(24.5, -1, 8), Vector3(15, 2, 16))
	await physics_ticks(3)
	var footprint := (player.get_node("Shape") as CollisionShape3D).shape as CapsuleShape3D
	await check_field_height_and_placement(host, player, footprint)
	var probe := Geometry.sample(player.get_world_3d().direct_space_state, probe_corner, Vector2i(3, 1), footprint, [])
	check(not probe.blocked.has(Vector2i.ZERO) and not probe.blocked.has(Vector2i.RIGHT) and probe.blocked.has(Vector2i(2, 0)), "missing floor was not blocked")
	check(probe.edges.has(Terrain.world_edge_key(Vector2i.ZERO, Vector2i.RIGHT)), "gap between supported cells was not blocked")
	floor.queue_free()
	second_floor.queue_free()
	player.global_position = crate.global_position + Vector3(0, 0.25, 7)
	var pickup := crate.get_node("Pickup") as EmberInteract
	if not check(player._nearest() == pickup and player.activate_interact(pickup) and crate.is_carried(), "could not take authored crate"): return
	state.persistence_enabled = true
	player.global_position = (host.get_node("BattleEntry") as Area3D).global_position - Vector3.UP * 11.5
	for frame in 450:
		if host.presentation_complete: break
		await process_frame
	if not check(host.presentation_complete, "entry trigger failed: " + str(host.last_error) + " / " + str(host.get_node("BattleEntry").get_overlapping_bodies())): return
	var hud = host.battle.get_node("CombatHUDLayer/CombatHUD")
	if hud._deployment_active:
		check(hud._confirm_deployment(), "deployment refused")
	var snapshot: Dictionary = hud.state_snapshot()
	check(Grid.is_blocked(snapshot, Vector2i(2, 0)), "rock collider did not block its cell")
	check(not Grid.is_blocked(snapshot, Vector2i.ZERO) and not Grid.is_blocked(snapshot, Vector2i.RIGHT), "thin wall blocked whole cells")
	check(not Terrain.has_line_of_sight(snapshot, Vector2i.ZERO, Vector2i.RIGHT) and not Terrain.can_force_move(snapshot, Vector2i.ZERO, Vector2i.RIGHT), "thin wall did not block adjacent sight or push")
	var routing := snapshot.duplicate(true)
	routing.holds.clear()
	routing.units.protagonist.cell = Vector2i.ZERO
	var around := Grid.movement_path(routing, "protagonist", Vector2i.RIGHT)
	check(not around.is_empty() and around.size() > 2, "movement did not route around thin wall")
	var gate_cell: Vector2i = snapshot.pressureGate.gateCell
	var plate_cell: Vector2i = snapshot.pressureGate.plateCell
	if not check(snapshot.holds.get("protagonist", "") == CRATE and crate.combat_suspended, "battle lost carried crate"): return
	check(Grid.is_blocked(snapshot, gate_cell) and Grid.movement_path(snapshot, "protagonist", gate_cell).is_empty(), "closed gate allowed movement")
	check(circuit.openness < 0.01, "physical gate started open")
	if not check(snapshot.units.has(HEAVY), "push-only crate was not projected into combat"): return
	for unit_id in ["protagonist", "mira", "shore_boar"]:
		var weights := snapshot.duplicate(true)
		var old_cell: Vector2i = weights.units[unit_id].cell
		weights.units[unit_id].cell = plate_cell
		check(not Grid.is_blocked(weights, gate_cell), "%s did not activate the plate" % unit_id)
		weights.units[unit_id].cell = old_cell
		check(Grid.is_blocked(weights, gate_cell), "%s left the plate active" % unit_id)
	hud._state.units.protagonist.nextAt = 9000.0
	hud._state.units.shore_boar.nextAt = 9000.0
	hud._state.units.mira.nextAt = 0.0
	snapshot = hud.state_snapshot()
	var pusher_cell := plate_cell + Vector2i(0, 2)
	var push := Grid.command_preview(snapshot, "push_world_item", HEAVY, pusher_cell)
	if not check(push.get("ok", false) and push.get("moves", {}).get(HEAVY) == plate_cell,
		"heavy crate push did not target plate: %s, active=%s Mira=%s crate=%s plate=%s reachable=%s" % [
			push, Combat.current_unit_id(snapshot), snapshot.units.mira.cell, snapshot.units[HEAVY].cell,
			plate_cell, Grid.reachable_cells(snapshot, "mira")]): return
	check(Grid.is_blocked(hud.state_snapshot(), gate_cell), "push preview opened gate before confirmation")
	var occupied := snapshot.duplicate(true)
	occupied.units.protagonist.cell = plate_cell
	check(not Grid.command_preview(occupied, "push_world_item", HEAVY, pusher_cell).get("ok", false),
		"push accepted occupied plate")
	hud._current_preview = push
	hud._confirm_action()
	await physics_ticks(55)
	snapshot = hud.state_snapshot()
	check(snapshot.units[HEAVY].cell == plate_cell and not Grid.is_blocked(snapshot, gate_cell)
		and circuit.openness > 0.99, "heavy crate did not open both projections of the gate")
	hud._retry_encounter()
	await physics_ticks(8)
	if hud._deployment_active:
		check(hud._confirm_deployment(), "retry after push refused")
	await physics_ticks(10)
	snapshot = hud.state_snapshot()
	check(snapshot.units[HEAVY].cell == plate_cell + Vector2i.DOWN and Grid.is_blocked(snapshot, gate_cell),
		"retry did not restore the heavy crate and close the gate")
	for attempt in 2:
		hud._state.units.protagonist.nextAt = 0.0
		hud._state.units.mira.nextAt = 9000.0
		hud._state.units.shore_boar.nextAt = 9000.0
		snapshot = hud.state_snapshot()
		var lower := {}
		for destination in Grid.reachable_cells(snapshot, "protagonist"):
			var offset := (destination - plate_cell).abs()
			if offset.x + offset.y != 1: continue
			var candidate := Grid.command_preview(snapshot, Combat.HELD_LOWER_COMMAND, "protagonist", destination)
			if candidate.get("ok", false) and candidate.get("moves", {}).get(CRATE) == plate_cell:
				lower = candidate
				break
		if not check(lower.get("ok", false) and lower.get("moves", {}).get(CRATE) == plate_cell, "lower did not target the free plate: " + str(lower)): return
		check(Grid.is_blocked(hud.state_snapshot(), gate_cell), "preview opened the gate")
		hud._current_preview = lower
		hud._confirm_action()
		await physics_ticks(50)
		snapshot = hud.state_snapshot()
		check(not snapshot.holds.has("protagonist") and snapshot.units[CRATE].cell == plate_cell, "lower did not place same crate")
		check(not Grid.is_blocked(snapshot, gate_cell) and not Grid.movement_path(snapshot, "protagonist", gate_cell).is_empty(), "lower did not open tactical route")
		check(circuit.openness > 0.99, "physical gate did not open")
		if attempt == 0:
			hud._retry_encounter()
			await physics_ticks(8)
			if hud._deployment_active:
				check(hud._confirm_deployment(), "retry deployment refused")
			await physics_ticks(10)
			snapshot = hud.state_snapshot()
			check(snapshot.holds.get("protagonist", "") == CRATE and Grid.is_blocked(snapshot, gate_cell) and circuit.openness < 0.01, "retry did not reset gate and hold")
	var leaves_cell := Vector2i(1, 1)
	var fire_state := snapshot.duplicate(true)
	fire_state.units.protagonist.nextAt = -1000.0
	var kai_cell: Vector2i = fire_state.units.protagonist.cell
	var ignite_plan := Grid.action_plan(fire_state, "ignite_leaves", leaves_cell, kai_cell)
	var ignite := Grid.command_preview(fire_state, "ignite_leaves", "", kai_cell, Combat.INVALID_CELL, leaves_cell)
	check(ignite_plan.get("ok", false) and leaves_cell in ignite_plan.get("footprint", [])
		and "dry_leaves" in Terrain.cell_definition(fire_state, leaves_cell).tags,
		"ignite preview did not mark the dry leaves without mutation")
	var arena = host.battle.get_node("Arena")
	arena.configure(fire_state, "ignite_leaves", "", kai_cell, false, ignite_plan)
	var fire_hint := arena.get_node_or_null("CombatOverlays3D/CombatOverlay_1_1") as MeshInstance3D
	check(fire_hint != null and fire_hint.material_override.albedo_color.r > 0.9
		and fire_hint.material_override.albedo_color.b < 0.2, "ignite preview did not show an orange footprint")
	var burning := Combat.commit(fire_state, ignite)
	check("burning_leaves" in Terrain.cell_definition(burning, leaves_cell).tags, "leaves did not ignite")
	hud._state = burning
	hud._refresh_field()
	await RenderingServer.frame_post_draw
	var fire_visual := host.battle.get_node_or_null("Arena/CombatOverlays3D/WorldSurfaceStates") as MeshInstance3D
	check(fire_visual != null and fire_visual.visible, "fire hazard was not visible")
	root.get_texture().get_image().save_png(output.path_join("pressure-battle-fire.png"))
	var defend := Grid.command_preview(burning, "defend", "protagonist", leaves_cell)
	var scorched := Combat.commit(burning, defend)
	check(scorched.units.protagonist.hp == burning.units.protagonist.hp - 2, "ending a turn in the fire did not cost 2 HP")
	burning.units.mira.nextAt = -2000.0
	var mira_cell: Vector2i = burning.units.mira.cell
	var quench_plan := Grid.action_plan(burning, "quench_leaves", leaves_cell, mira_cell)
	var quench := Grid.command_preview(burning, "quench_leaves", "", mira_cell, Combat.INVALID_CELL, leaves_cell)
	check(quench_plan.get("ok", false) and leaves_cell in quench_plan.get("footprint", [])
		and "burning_leaves" in Terrain.cell_definition(burning, leaves_cell).tags,
		"quench preview did not mark the fire without mutation")
	arena.configure(burning, "quench_leaves", "", mira_cell, false, quench_plan)
	var water_hint := arena.get_node_or_null("CombatOverlays3D/CombatOverlay_1_1") as MeshInstance3D
	check(water_hint != null and water_hint.material_override.albedo_color.b > 0.9
		and water_hint.material_override.albedo_color.r < 0.3, "quench preview did not show a blue footprint")
	var quenched := Combat.commit(burning, quench)
	check("wet" in Terrain.cell_definition(quenched, leaves_cell).tags
		and "burning_leaves" not in Terrain.cell_definition(quenched, leaves_cell).tags,
		"water did not extinguish the fire")
	hud._state = snapshot
	hud._refresh_field()
	var wet := snapshot.duplicate(true)
	var target_cell: Vector2i = wet.units.shore_boar.cell
	var dry_cell := target_cell + Vector2i.UP
	var wet_cell := plate_cell + Vector2i.RIGHT
	check("wet" in Terrain.cell_definition(wet, target_cell).tags
		and "wet" in Terrain.cell_definition(wet, wet_cell).tags
		and "wet" not in Terrain.cell_definition(wet, dry_cell).tags, "visible puddle did not project the expected wet strip and dry bypass")
	wet.units.protagonist.cell = wet_cell
	wet.units.mira.cell = dry_cell
	wet.units.mira.nextAt = -1000.0
	var spark := {}
	for seed in range(1, 40):
		wet["rngSeed"] = seed
		spark = Combat.preview(wet, "spark", "shore_boar")
		if spark.get("hit", false): break
	check(spark.get("damage", {}).has("protagonist") and not spark.get("damage", {}).has("mira")
		and wet_cell in Combat.action_footprint(wet, "spark", target_cell),
		"wet ally was missing from spark damage or footprint, or dry Mira was hit: " + str(spark))
	if spark.get("damage", {}).has("protagonist"):
		var shocked := Combat.commit(wet, spark)
		check(shocked.units.protagonist.hp < wet.units.protagonist.hp, "committed spark did not hurt wet Kai")
	wet.units.protagonist.cell = wet_cell + Vector2i.DOWN
	check(not Combat.preview(wet, "spark", "shore_boar").get("damage", {}).has("protagonist"),
		"dry Kai was chained by spark")
	var freeze := {}
	for seed in range(1, 40):
		wet["rngSeed"] = seed
		freeze = Combat.preview(wet, "chill", "shore_boar")
		if freeze.get("hit", false): break
	check(freeze.get("cellChanges", {}).size() == 3 and "wet" in Terrain.cell_definition(wet, wet_cell).tags,
		"chill preview did not cover three wet cells or changed the live surface")
	var frozen := Combat.commit(wet, freeze)
	check("frozen" in Terrain.cell_definition(frozen, wet_cell).tags
		and "frozen" not in Terrain.cell_definition(frozen, dry_cell).tags,
		"chill commit did not freeze only the linked puddle")
	hud._state = frozen
	hud._refresh_field()
	await RenderingServer.frame_post_draw
	var frozen_visual := host.battle.get_node_or_null("Arena/CombatOverlays3D/WorldSurfaceStates") as MeshInstance3D
	check(frozen_visual != null and frozen_visual.mesh.get_surface_count() == 1, "frozen surface was not rendered in place")
	root.get_texture().get_image().save_png(output.path_join("pressure-battle-ice.png"))
	frozen.units.protagonist.cell = wet_cell
	frozen.units.protagonist.nextAt = -1000.0
	var melt := {}
	for seed in range(1, 40):
		frozen["rngSeed"] = seed
		melt = Combat.preview(frozen, "kindle", "shore_boar")
		if melt.get("hit", false): break
	var melted := Combat.commit(frozen, melt)
	check("wet" in Terrain.cell_definition(melted, wet_cell).tags
		and "frozen" not in Terrain.cell_definition(melted, wet_cell).tags,
		"kindle did not restore the wet surface")
	hud._state = melted
	hud._refresh_field()
	await process_frame
	check(not host.battle.has_node("Arena/CombatOverlays3D/WorldSurfaceStates"), "ice remained visible after melting")
	hud._state = snapshot
	hud._refresh_field()
	var approach := Grid.command_preview(snapshot, "strike", "shore_boar", gate_cell)
	if not check(approach.get("ok", false), "cannot move through open gate and attack: " + str(approach.get("error", ""))): return
	hud._current_preview = approach
	hud._confirm_action()
	await physics_ticks(50)
	check(hud._state.units.protagonist.cell == gate_cell, "combat movement did not enter passage")
	await RenderingServer.frame_post_draw
	var capture := output.path_join("pressure-battle.png")
	root.get_texture().get_image().save_png(capture)
	print("PRESSURE BATTLE CAPTURE ", ProjectSettings.globalize_path(capture))
	for attempt in 16:
		if Combat.outcome(hud._state) != "active": break
		snapshot = hud.state_snapshot()
		var strike := Grid.command_preview(snapshot, "strike", "shore_boar", gate_cell)
		if not check(strike.get("ok", false), "could not finish encounter"): return
		hud._current_preview = strike
		hud._confirm_action()
		await physics_ticks(42)
	if not check(Combat.outcome(hud._state) == "victory", "encounter did not reach victory"): return
	check(EmberCombatTransition.finish(self, "victory", state, hud.state_snapshot()) == OK, "could not return from combat")
	await physics_ticks(55)
	check(not state.combat_party_locked and not crate.combat_suspended and state.flags.get("chapter1_tide_pressure_defeated", false), "world did not restore after victory")
	check(circuit.combat_plate_signal == null and circuit.pressed and circuit.openness > 0.99,
		"returned crate did not keep gate open: crate=%s plate=%s mask=%d" % [crate.global_position, circuit.get_node("WeightPlate").global_position, crate.collision_mask])
	var cold := EmberExploreState.new()
	cold.storage_root = state.storage_root
	cold.restore_enabled = false
	check(cold.load_autosave() and cold.flags.get("chapter1_tide_pressure_defeated", false), "victory save did not restore")
	check(cold.world_items.get("chapter1_tide_battle_crate", {}).get("count", 0) == 1, "save lost surviving crate")
	cold.free()
	await test_native_stair_battle(player)


func finish_fishing_round(ui: EmberInteractionUi, reel: bool) -> void:
	for tick in 1100:
		if ui.view_state().mode != "fishing": break
		ui._step_fishing(1.0 / 60.0, reel and ui._fishing_round.phase() != "tug")


func test_coast_fishing() -> void:
	const FISH := "chapter1_raw_fish"
	const PERCH := "chapter1_perch"
	const SCALE := "chapter1_perch_scale"
	const DISH := "chapter1_cooked_fish"
	const CAUGHT := "chapter1_coast_fish_caught"
	if not await goto_map("chapter1_coast"): return
	var player := current_scene.get_node("Player") as EmberPlayer
	var stop := current_scene.get_node("Map/Props/FishingStop") as Node3D
	var fishing := stop.get_node("Fishing") as EmberInteract
	var stove := stop.get_node("CoastKitchen/Interaction") as EmberInteract
	var ui := player.interaction_ui
	var profiles: Array[Dictionary] = fishing.get("catches")
	if not check(profiles.size() == 2 and profiles[0].calm > profiles[1].calm, "missing distinct fishing rhythms"): return
	var small_fish: Array[Dictionary] = [profiles[0]]
	var perch_profile := profiles[1].duplicate()
	perch_profile.bonusChance = 1.0
	var perch_only: Array[Dictionary] = [perch_profile]
	fishing.set("catches", small_fish)
	player.global_position = stove.global_position - Vector3.UP * 7.5
	check(player._nearest() == stove and player.activate_interact(stove), "coast kitchen unreachable")
	if not check(ui.view_state().mode == "craft", "coast kitchen did not open"): return
	ui.advance()
	check(ui.view_state().mode == "craft" and not state.inventory.has(DISH), "cooked without fish")
	ui.close()
	player.global_position = stop.global_position + Vector3(-5, 0.5, 0)
	check(player._nearest() == fishing and player.activate_interact(fishing), "fishing point unreachable")
	if not check(ui.view_state().title == "Мира", "first casting dialogue missing"): return
	ui.advance()
	check(ui.view_state().mode == "fishing", "first cast did not start")
	ui.close()
	await physics_ticks(3)
	check(not fishing.get_node("Bobber").visible, "cancel left bobber in water")
	check(not ui.is_open() and not state.flags.has(CAUGHT) and not state.inventory.has(FISH), "cancelled cast yielded fish")
	check(player.activate_interact(fishing), "cast could not restart")
	ui.advance()
	finish_fishing_round(ui, false)
	check(ui.view_state().mode == "fishing_result" and not state.inventory.has(FISH), "escape rewarded fish")
	ui.advance()
	if not check(ui.view_state().mode == "fishing", "retry replayed the introduction"): return
	for tick in 48: ui._step_fishing(1.0 / 60.0, false)
	Input.action_press("interact")
	await physics_ticks(10)
	Input.action_release("interact")
	check(ui._fishing_round.progress > 0.0, "holding F did not reel in")
	for tick in 150:
		if ui._fishing_round.phase() == "tug": break
		ui._step_fishing(1.0 / 60.0, true)
	var distance_before_tug := ui._fishing_round.progress
	ui._step_fishing(1.0 / 60.0, true)
	check(ui._fishing_round.progress < distance_before_tug, "pulling during tug was not penalized")
	check(fishing.get_node("Bobber/Ripple").is_visible_in_tree(), "tug warning did not appear on water")
	check(ui.view_state().body == "ОТПУСТИ F", "tug command missing")
	var sound := fishing.get_node_or_null("TugSound") as AudioStreamPlayer
	if check(sound != null and sound.playing, "tug sound did not start"):
		await physics_ticks(5)
		check(sound.get_playback_position() > 0.025, "tug sound restarted during the same phase")
	await RenderingServer.frame_post_draw
	var capture := output.path_join("coast-fishing-round.png")
	root.get_texture().get_image().save_png(capture)
	print("FISHING CAPTURE ", ProjectSettings.globalize_path(capture))
	state.persistence_enabled = true
	var saves: Array[String] = []
	state.saved.connect(func(path: String): saves.append(path))
	finish_fishing_round(ui, true)
	check(state.inventory.get(FISH, 0) == 1 and state.flags.get(CAUGHT, false), "small fish catch not committed")
	check(not state.inventory.has(SCALE) and saves.size() == 1, "wrong reward or extra save for small fish")
	fishing.set("catches", perch_only)
	state.inventory[SCALE] = int(EmberItemCatalog.definition(SCALE).stackMax)
	ui.advance()
	finish_fishing_round(ui, true)
	check(not state.inventory.has(PERCH) and saves.size() == 1, "full bonus stack partially committed catch")
	state.inventory.erase(SCALE)
	ui.advance()
	finish_fishing_round(ui, true)
	check(state.inventory.get(PERCH, 0) == 1 and state.inventory.get(SCALE, 0) == 1, "perch and its bonus were not awarded together")
	check(saves.size() == 2, "bonus was not saved atomically with fish")
	ui.close()
	check(player.activate_interact(fishing) and ui.view_state().mode == "fishing", "reopening after catch did not skip the intro")
	ui.close()
	player.global_position = stove.global_position - Vector3.UP * 7.5
	check(player.activate_interact(stove) and ui.view_state().mode == "craft", "could not cook catch")
	ui.advance()
	check(ui.view_state().mode == "dialogue" and ui.view_state().title == "Мира", "successful cooking did not open Mira reply")
	ui.advance()
	check(player.activate_interact(stove) and ui.view_state().mode == "craft", "could not reopen kitchen")
	ui._move_craft_selection(1)
	ui.advance()
	check(ui.view_state().mode == "dialogue" and ui.view_state().title == "Мира", "perch recipe did not open Mira reply")
	ui.advance()
	check(state.inventory.get(DISH, 0) == 2 and not state.inventory.has(FISH) and not state.inventory.has(PERCH) and saves.size() == 4, "cooking did not exchange both catches")
	var cold := EmberExploreState.new()
	cold.storage_root = state.storage_root
	cold.restore_enabled = false
	check(cold.load_autosave() and cold.flags.get(CAUGHT, false) and cold.inventory.get(DISH, 0) == 2 and cold.inventory.get(SCALE, 0) == 1, "catch/cooking state lost on load")
	check(fishing.runtime_available(cold.flags), "old catch flag closed the repeatable point")
	cold.free()


func cache_step(player: EmberPlayer, destination: Vector3) -> bool:
	if not check(not player.test_move(player.global_transform, destination - player.global_position), "cache route blocked towards " + str(destination)):
		return false
	player.global_position = destination
	return true


func test_tide_cache() -> void:
	const SHELL_ID := "chapter1_tide_cache_shell"
	for use_crate in [false, true]:
		state.persistence_enabled = false
		state.reset_new_game()
		if not await goto_map("chapter1_tide_cave"): return
		var cache = current_scene.get_node("Map/Props/TideCache")
		var player := current_scene.get_node("Player") as EmberPlayer
		var shell := cache.get_node("Shell") as RigidBody3D
		var crate := cache.get_node("CacheCrate") as RigidBody3D
		var origin: Vector3 = cache.global_position + Vector3.UP * 0.5
		if not check(cache.diagnostics.is_empty(), str(cache.diagnostics)): return
		player.global_position = origin + Vector3(0, 0, 45)
		await physics_ticks(65)
		if not use_crate:
			await RenderingServer.frame_post_draw
			var image_path := output.path_join("tide-cache.png")
			root.get_texture().get_image().save_png(image_path)
			print("CACHE CAPTURE ", ProjectSettings.globalize_path(image_path))
		check(cache.openness < 0.01 and not cache.pressed, "player alone opened weight plate")
		player.global_position = origin + Vector3(0, 0, 31)
		check(player.test_move(player.global_transform, Vector3(0, 0, -31)), "closed grate did not block player")
		check(player._nearest() != shell.get_node("Pickup"), "shell reachable through grate")
		if use_crate:
			player.global_position = origin + Vector3(-30, 0, 55)
			var handle := crate.get_node("Pickup") as EmberInteract
			check(player._nearest() == handle and player.activate_interact(handle) and crate.is_carried(), "crate could not be picked up")
			player.global_position = origin + Vector3(0, 0, 69)
			player.set("_interaction_forward", Vector3.FORWARD)
			check(player.activate_interact(handle) and not crate.is_carried(), "crate could not be placed on plate")
			await physics_ticks(100)
			if not check(cache.pressed and cache.openness > 0.99, "weighted plate did not open grate"): return
			player.global_position = origin + Vector3(0, 0, 32)
			if not cache_step(player, origin + Vector3(0, 0, 8)): return
		else:
			player.global_position = origin + Vector3(0, 0, 34)
			for offset in [Vector3(46, 0, 34), Vector3(46, 0, -13), Vector3(0, 0, -13), Vector3(0, 0, -8)]:
				if not cache_step(player, origin + offset): return
			check(cache.openness < 0.01, "bypass opened the grate")
		var pickup := shell.get_node("Pickup") as EmberInteract
		var before := int(state.inventory.get("shore_shell", 0))
		check(player._nearest() == pickup and player.activate_interact(pickup), "shell pickup unavailable on reached side")
		check(int(state.inventory.get("shore_shell", 0)) == before + 1, "shell did not reach inventory")
		check(int(state.world_items.get(SHELL_ID, {}).get("count", 1)) == 0, "shell record was not consumed")
		if use_crate:
			state.persistence_enabled = true
			check(state.save_slot(1), "cache save failed")
			var cold := EmberExploreState.new()
			cold.storage_root = state.storage_root
			cold.restore_enabled = false
			check(cold.load_slot(1) and int(cold.inventory.get("shore_shell", 0)) == before + 1, "cache inventory lost on load")
			check(int(cold.world_items.get(SHELL_ID, {}).get("count", 1)) == 0, "cache pickup restored on load")
			cold.free()
			check(state.load_slot(1), "could not reopen cache save")
			if not await goto_map("chapter1_tide_cave"): return
			await physics_ticks(80)
			check(not current_scene.has_node("Map/Props/TideCache/Shell"), "collected shell respawned")


func day1_travel(path: String, destination: String) -> bool:
	var gate = current_scene.get_node(path)
	return await travel({"path": path, "map": "chapter1_" + destination, "region": gate.target_region_id})

func day1_interact(path: String, mode: String) -> EmberInteractionUi:
	var player := current_scene.get_node("Player") as EmberPlayer
	var area := current_scene.get_node(path) as EmberInteract
	if not check(player.activate_interact(area), "day 1 interaction refused: " + path): return null
	var ui := player.interaction_ui
	return ui if check(ui.view_state().mode == mode, "day 1 UI did not open " + mode) else null

func finish_day1_talk(ui: EmberInteractionUi) -> void:
	for index in 10:
		if not ui.is_open(): break
		ui.advance()

func check_day1_direction(objective_id: String, landmark: String, use_key := false) -> void:
	var player := current_scene.get_node("Player") as EmberPlayer
	var journal := player.quest_journal_ui
	var ui := player.interaction_ui
	var before := state.flags.duplicate(true)
	journal.open()
	var note := journal.find_child("QuestDirection_" + objective_id, true, false) as Label
	if not check(note != null and landmark in note.text, "journal direction missing: " + objective_id):
		journal.close()
		return
	var direction := note.text
	check(not player.ask_mira_direction(), "Mira interrupted journal")
	if use_key:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("day1-journal-direction.png"))
	journal.close()
	if use_key:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_J
		event.pressed = true
		Input.parse_input_event(event)
		for frame in 12:
			if ui.is_open(): break
			await process_frame
		event = InputEventKey.new()
		event.physical_keycode = KEY_J
		event.pressed = false
		Input.parse_input_event(event)
	else:
		check(player.ask_mira_direction(), "Mira hint did not open: " + objective_id)
	check(ui.view_state().title == "Мира" and ui.view_state().body == direction, "Mira and journal directions differ")
	if use_key:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("day1-mira-direction.png"))
		print("DIRECTION CAPTURES ", ProjectSettings.globalize_path(output))
	ui.advance()
	check(not ui.is_open() and state.flags == before, "hint changed quest progress or blocked further play")


func test_day1() -> void:
	if not await goto_map("chapter1_residential"): return
	if not await day1_travel("Map/Props/ToCentre/exit_from_centre", "centre"): return
	if not await day1_travel("Map/Props/GeneralStore/DoorInteraction", "general_store"): return
	var ui := day1_interact("Map/Props/Shopkeeper/Interaction", "shop")
	if ui == null: return
	ui.close()
	if not check(not state.inventory.has("chapter1_day1_ribbon"), "early store visit granted ribbon"): return
	if not await day1_travel("Map/Props/ExitDoor/DoorInteraction", "centre"): return
	if not await day1_travel("Map/Props/Guild/DoorInteraction", "guild"): return
	ui = day1_interact("Map/Props/GuildClerk/Interaction", "dialogue")
	if ui == null: return
	ui.close()
	if not check(not state.flags.has("chapter1_day1_status"), "cancelled guild talk started quest"): return
	ui = day1_interact("Map/Props/GuildClerk/Interaction", "dialogue")
	if ui == null: return
	check("«Товары»" in ui.view_state().body, "clerk did not mention the sign")
	finish_day1_talk(ui)
	if not check(state.flags.get("chapter1_day1_guild", false), "guild did not start quest"): return
	await check_day1_direction("errand", "«Товары»", true)
	if not await day1_travel("Map/Props/ExitDoor/DoorInteraction", "centre"): return
	if not await day1_travel("Map/Props/GeneralStore/DoorInteraction", "general_store"): return
	ui = day1_interact("Map/Props/Shopkeeper/Interaction", "dialogue")
	if ui == null: return
	ui.close()
	if not check(not state.inventory.has("chapter1_day1_ribbon"), "cancelled errand granted ribbon"): return
	ui = day1_interact("Map/Props/Shopkeeper/Interaction", "dialogue")
	if ui == null: return
	check("«К усадьбе Миры»" in ui.view_state().body, "shopkeeper did not mention the estate sign")
	while ui.view_state().mode == "dialogue":
		ui.advance()
	if not check(state.inventory.get("chapter1_day1_ribbon", 0) == 1 and state.flags.get("chapter1_day1_errand", false), "ribbon handoff not counted"): return
	ui.close()
	ui = day1_interact("Map/Props/Shopkeeper/Interaction", "shop")
	if ui == null: return
	ui.close()
	await check_day1_direction("mira", "Жилую улицу")
	if not await day1_travel("Map/Props/ExitDoor/DoorInteraction", "centre"): return
	if not await day1_travel("Map/Props/ToResidential/exit_from_residential", "residential"): return
	if not await day1_travel("Map/Props/ToEstate/exit_from_estate", "estate"): return
	var workbench := current_scene.get_node("Map/Props/CraftingWorkbench/Interaction") as EmberInteract
	if not check(not workbench.runtime_available(), "workbench opened before Mira"): return
	ui = day1_interact("Map/Props/Mira/Interaction", "dialogue")
	if ui == null: return
	finish_day1_talk(ui)
	await check_day1_direction("craft", "Подарок для мамы")
	ui = day1_interact("Map/Props/CraftingWorkbench/Interaction", "craft")
	if ui == null: return
	ui.advance()
	if not check(state.inventory.get("chapter1_day1_gift", 0) == 1 and state.flags.get("chapter1_day1_craft", 0) == 1, "gift crafting not counted"): return
	check(not state.inventory.has("chapter1_day1_ribbon"), "craft did not consume ribbon")
	ui.close()
	await check_day1_direction("home", "«Дом Кая»")
	if not await day1_travel("Map/Props/ToResidential/exit_from_residential", "residential"): return
	if not await day1_travel("Map/Props/KaiHome/DoorInteraction", "home"): return
	if "--day1-clip" in OS.get_cmdline_user_args() and not await test_day1_clip(): return
	ui = day1_interact("Map/Props/Mother/Interaction", "dialogue")
	if ui == null: return
	finish_day1_talk(ui)
	var quest := EmberQuestCatalog.definition("chapter1_day1")
	if not check(EmberQuestCatalog.projection(quest, state.flags).status == "done", "day 1 did not finish"): return
	check(not (current_scene.get_node("Player") as EmberPlayer).ask_mira_direction(), "finished quest still offers directions")
	check(not state.inventory.has("chapter1_day1_gift"), "handover did not consume gift")
	ui = day1_interact("Map/Props/Mother/Interaction", "dialogue")
	if ui == null: return
	finish_day1_talk(ui)
	state.persistence_enabled = true
	check(state.save_slot(1), "day 1 save failed")
	var cold := EmberExploreState.new()
	cold.storage_root = state.storage_root
	cold.restore_enabled = false
	check(cold.load_slot(1), "day 1 cold load failed")
	check(EmberQuestCatalog.projection(quest, cold.flags).status == "done", "completion lost on load")
	check(not cold.inventory.has("chapter1_day1_gift"), "gift restored after handover")
	cold.free()

func test_day1_clip() -> bool:
	if not check(FileAccess.file_exists("res://.interaction-test-sandbox") and not DirAccess.dir_exists_absolute("res://.git"), "clip fixture must be disposable"):
		return false
	var stage := current_scene as Node3D
	var mother := stage.get_node("Map/Props/Mother") as Node3D
	var avatar := (load("res://assets/local_characters/hoshi/avatar.scn") as PackedScene).instantiate() as Node3D
	avatar.name = "StoryActor"
	avatar.scale = Vector3.ONE * 16.0
	avatar.position = mother.position + Vector3(28, 0, 8)
	mother.get_parent().add_child(avatar)
	avatar.owner = stage
	var motion := avatar.get_node("Motion") as AnimationPlayer
	motion.stop()
	if motion.has_animation_library(""): motion.remove_animation_library("")
	motion.add_animation_library("", load("res://assets/local_characters/hoshi/motion.res"))
	var history := UndoRedo.new()
	var actions := preload("res://addons/ember_import/ember_object_inspector_actions.gd").new()
	actions.configure(history)
	var form := preload("res://addons/ember_import/ember_story_authoring_dialog.gd").new()
	root.add_child(form)
	form.setup(stage)
	form.find_child("StoryTitle", true, false).text = "Маленькая вина · постановочная проба"
	form.find_child("StoryMoveX", true, false).value = 0.0
	for selection in [["primary", "Map/Props/StoryActor"], ["secondary", "Map/Props/Mother"], ["item", "Map/Props/KitchenTable"]]:
		var picker := form.find_child("StoryTarget_" + selection[0], true, false) as OptionButton
		for index in picker.item_count:
			if str(picker.get_item_metadata(index)) == selection[1]:
				picker.select(index)
				picker.item_selected.emit(index)
				break
	var clip_picker := form.find_child("StoryActorClip", true, false) as OptionButton
	for index in range(1, clip_picker.item_count):
		if clip_picker.get_item_metadata(index).name == "idle":
			clip_picker.select(index)
			break
	var values: Dictionary = form.values()
	form.queue_free()
	if not check(not values.actorClip.is_empty() and values.actorClip.name == "idle", "local idle missing in editor picker"):
		history.free()
		return false
	var created := actions.create_story_scene(stage, values)
	if not check(created.ok, str(created.get("error", "could not create story"))):
		history.free()
		return false
	var assembly: Node3D = created.node
	var presentation = created.presenter
	var assembly_name := str(assembly.name)
	history.undo()
	check(not stage.has_node(assembly_name), "story clip Undo failed")
	history.redo()
	check(stage.has_node(assembly_name), "story clip Redo failed")
	history.free()
	var packed := PackedScene.new()
	var saved_path := output.path_join("day1-story.tscn")
	if not check(packed.pack(stage) == OK and ResourceSaver.save(packed, saved_path) == OK, "story scene save failed"): return false
	var reopened := (ResourceLoader.load(saved_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved_player := reopened.get_node(assembly_name + "/AnimationPlayer") as AnimationPlayer
	check(saved_player.get_animation("story").get_track_count() > 2, "saved scene lost bone tracks")
	reopened.free()
	var store = preload("res://addons/ember_import/ember_action_script_store.gd")
	var action: Dictionary = store.document("chapter1_day1_deliver")
	action.steps.push_front({"type": "play_cutscene", "presentationId": presentation.presentation_id})
	if not check(store.write_document(action) == OK, "test could not bind scene to handover"): return false
	var actor := stage.get_node("Player") as EmberPlayer
	var interaction := mother.get_node("Interaction") as EmberInteract
	var skeleton := avatar.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var poses: Array[Transform3D] = []
	for index in skeleton.get_bone_count(): poses.append(skeleton.get_bone_pose(index))
	var camera := root.get_camera_3d()
	if not check(actor.activate_interact(interaction) and presentation.active, "handover did not start clip"): return false
	presentation.player.seek(1.0, true)
	var moved := false
	for index in poses.size():
		if not skeleton.get_bone_pose(index).is_equal_approx(poses[index]): moved = true
	check(moved, "clip did not move the selected actor")
	presentation.restore()
	check(not state.flags.has("chapter1_day1_home") and state.inventory.has("chapter1_day1_gift"), "cancelled clip consumed gift")
	check(root.get_camera_3d() == camera, "cancel did not restore camera")
	for index in poses.size():
		if not check(skeleton.get_bone_pose(index).is_equal_approx(poses[index]), "cancel left actor in clip pose"): break
	if not check(actor.activate_interact(interaction) and presentation.active, "handover retry did not start clip"): return false
	presentation.player.speed_scale = 4.0
	for frame in 180:
		if not presentation.active: break
		await process_frame
	if not check(not presentation.active and root.get_camera_3d() == camera, "natural finish did not restore camera"): return false
	for index in poses.size():
		if not check(skeleton.get_bone_pose(index).is_equal_approx(poses[index]), "finish left actor in clip pose"): break
	check(actor.interaction_ui.view_state().mode == "dialogue", "clip did not continue into handover")
	finish_day1_talk(actor.interaction_ui)
	# The normal Day 1 assertions now check the completed quest and repeat reply.
	print("DAY1 CLIP PASS: native picker / saved bone tracks / cancel / retry / natural completion")
	return errors.is_empty()

func visit_graph(id: String) -> void:
	visited[id] = true
	await test_actions(id)
	for row in routes[id]:
		if visited.has(row.map): continue
		if not await travel(row): return
		await visit_graph(row.map)
		if not errors.is_empty(): return
		var reverse: Dictionary = {}
		for candidate in routes[row.map]:
			if candidate.map == id: reverse = candidate; break
		if not check(not reverse.is_empty(), "no reverse to " + id): return
		if not await travel(reverse): return

func test_actions(id: String) -> void:
	var player = current_scene.get_node("Player")
	var ui: EmberInteractionUi = player.interaction_ui
	for node in descendants(current_scene.get_node("Map/Props")):
		if not node is EmberInteract or node.kind not in ["talk", "shop"]: continue
		if node.quest_id == "chapter1_day1" and not node.runtime_available(): continue
		check(player.activate_interact(node), "player action refused: " + id)
		check(ui.is_open() and ui.blocks_movement(), "UI not opened: " + id)
		if node.kind == "shop":
			check(str(ui.get("_mode")) == "shop", "shop did not open: " + id)
			var shop: Dictionary = ui.get("_shop")
			var listings: Array = shop.get("listings", [])
			if check(not listings.is_empty(), "empty shop " + id):
				var item: String = str(listings[0].itemId)
				state.inventory["coin"] = 100
				var before := int(state.inventory.get(item, 0))
				var stock := int(state.shop_view(node.shop_id).listings[0].stock)
				ui.advance()
				check(int(state.inventory.get(item, 0)) == before + 1, "shop UI did not buy item: " + id)
				check(int(state.shop_view(node.shop_id).listings[0].stock) == stock - 1, "shop stock not decremented: " + id)
		elif node.quest_id == "chapter1_day1":
			check(not ui.conversation_session().current_text().is_empty(), "day 1 dialogue absent: " + id)
		else:
			check(ui.conversation_session().current_text().contains("макет") or ui.conversation_session().current_text().contains("Здесь будет"), "placeholder dialogue absent: " + id)
		ui.close()
		check(not ui.blocks_movement(), "UI did not close: " + id)
	await process_frame

func test_interior_routes() -> void:
	for suffix in ["home", "guild", "smith", "general_store", "alchemy", "mansion"]:
		var id: String = "chapter1_" + suffix
		var back: Dictionary = routes[id][0]
		if current_scene == null or current_scene.map_id != back.map:
			if not await goto_map(back.map): return
		var forward: Dictionary = {}
		for candidate in routes[back.map]:
			if candidate.map == id: forward = candidate; break
		if not check(not forward.is_empty(), "missing exterior door for " + id): return
		if not await travel(forward): return
		visited[id] = true
		await test_actions(id)
		if not errors.is_empty() or not await travel(back): return
	check(visited.size() == 6, "not all six interiors visited")

func test_bridge() -> void:
	if current_scene.map_id != "chapter1_residential":
		if not await goto_map("chapter1_residential"): return
	var player: EmberPlayer = current_scene.get_node("Player")
	player.global_position = Vector3(198, 8.5, 160)
	player.camera_rig.yaw = 0.0
	for frame in 6: await physics_frame
	Input.action_press("move_east")
	for frame in 220: await physics_frame
	Input.action_release("move_east")
	check(player.global_position.x > 310, "bridge walk blocked: " + str(player.global_position))
	check(player.global_position.y >= 7.5, "bridge walk fell into canal: " + str(player.global_position))
	player.velocity = Vector3.ZERO
	print("BRIDGE WALK ", player.global_position)

func test_relocation() -> void:
	var path := Transition.scene_path("chapter1_residential")
	var original = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var disposable = original.instantiate()
	var group: Node3D = disposable.get_node("Map/Props/KaiHome")
	var map: EmberMapLoader = disposable.get_node("Map")
	var before := map.region_world("return_home")
	group.position += Vector3(16, 0, 0)
	check(map.region_world("return_home").is_equal_approx(before + Vector3(16, 0, 0)), "detached grouped return did not move")
	var packed := PackedScene.new()
	check(packed.pack(disposable) == OK, "repack moved building")
	var moved_path := output.path_join("moved-residential.tscn")
	check(ResourceSaver.save(packed, moved_path) == OK, "save moved building")
	disposable.free()
	var reopened = ResourceLoader.load(moved_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	reopened.take_over_path(path)
	if not await goto_map("chapter1_residential"): return
	var door: EmberInteract = current_scene.get_node("Map/Props/KaiHome/DoorInteraction")
	var current_map: EmberMapLoader = current_scene.get_node("Map")
	check(current_map.region_world("return_home").is_equal_approx(before + Vector3(16, 0, 0)), "reopen moved building did not retain marker")
	if not await travel({"path":"Map/Props/KaiHome/DoorInteraction","map":"chapter1_home","region":"entry"}): return
	if not await travel(routes.chapter1_home[0]): return
	original.take_over_path(path)
	# NPC local movement changes actual interaction location; saved round-trip uses the same child.
	var shop_path := Transition.scene_path("chapter1_general_store")
	var shop_original = ResourceLoader.load(shop_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var shop_scene = shop_original.instantiate()
	var npc: Node3D = shop_scene.get_node("Map/Props/Shopkeeper")
	var action: EmberInteract = npc.get_node("Interaction")
	var local := action.position
	npc.position.x += 12
	var moved_npc := npc.position
	var shop_packed := PackedScene.new()
	check(shop_packed.pack(shop_scene) == OK, "pack moved NPC")
	var npc_path := output.path_join("moved-shop.tscn")
	check(ResourceSaver.save(shop_packed, npc_path) == OK, "save moved NPC")
	shop_scene.free()
	var shop_reopen = ResourceLoader.load(npc_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	shop_reopen.take_over_path(shop_path)
	if await goto_map("chapter1_general_store"):
		var actual: Node3D = current_scene.get_node("Map/Props/Shopkeeper")
		check(actual.position == moved_npc and actual.get_node("Interaction").position == local, "NPC binding lost after reopen")
		await test_actions("chapter1_general_store")
	shop_original.take_over_path(shop_path)

func test_save() -> void:
	state.persistence_enabled = true
	state.set_flag("chapter1_gate_seen", true, false)
	var expected := state.capture_save()
	check(state.save_slot(3), "save failed")
	var loaded := EmberExploreState.new()
	loaded.persistence_enabled = true; loaded.restore_enabled = true
	loaded.storage_root = state.storage_root
	loaded.legacy_storage_root = output.path_join("legacy-unused")
	check(loaded.load_slot(3), "cold owner load failed")
	var result := loaded.capture_save()
	for key in ["inventory", "flags", "shopStock", "activeHeroIds"]:
		check(result[key] == expected[key], "save roundtrip lost " + key)
	check(result.mapId == expected.mapId, "map ID lost in save")
	check(loaded.resume_scene_path() == Transition.scene_path(str(expected.mapId)), "resume path changed")
	state.flags.erase("chapter1_gate_seen")
	state.inventory.clear()
	check(state.load_slot(3), "live load failed")
	state.restore_enabled = true
	var target: String = loaded.resume_scene_path()
	check(change_scene_to_file(target) == OK, "resume transition failed")
	await wait_map(str(expected.mapId))
	check(state.inventory == expected.inventory and state.flags == expected.flags, "resume duplicated/lost state")
	state.persistence_enabled = false; state.restore_enabled = false
	loaded.free()
