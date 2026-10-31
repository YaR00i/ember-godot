extends SceneTree
## Targeted integration check of the actual map and World Look command.
## Save/reopen uses user://; authored scene and Source are never written.
var failures: Array[String] = []
var output := "user://location-world-looks"

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func settle(projection: Node) -> void:
	var limit := Time.get_ticks_msec() + 60000
	while projection.pending_tile_count() > 0 or not projection._look_pending.is_empty():
		if Time.get_ticks_msec() > limit:
			check(false, "terrain preparation timeout")
			return
		await process_frame
	for i in 3: await process_frame

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty(): output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var scene: Node = load("res://scenes/landscape_compact.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var map: EmberMapLoader = scene.get_node("Map")
	var projection: Node = map.get_node("DerivedCompactWorldTerrain")
	await settle(projection)
	var timeout := Time.get_ticks_msec() + 60000
	while not scene._startup_complete and Time.get_ticks_msec() < timeout: await process_frame
	check(scene._startup_complete, "ordinary map starts gameplay")
	if not scene._startup_complete:
		quit(1)
		return
	# Freeze camera/actors at their normal initial gameplay pose for paired frames.
	scene._player.set_physics_process(false)
	scene._party_followers.set_physics_process(false)
	scene._player.camera_rig.set_process(false)
	var source_heights: PackedInt32Array = map.compact_terrain.heights.duplicate()
	var source_water: PackedInt32Array = map.compact_terrain.water_levels.duplicate()
	var rock: EmberVoxelProp = map.get_node("Props/PaintedRockGroup")
	var collider: Shape3D = rock.get_node("Collision/Shape").shape
	var tile_collider: Shape3D = projection._tiles[Vector2i(1, 2)].get_node("GroundPhysics/Shape").shape
	var floor_before := map.surface_floor_sample(Vector3(72, 100, 200))
	var patch: Node = map.get_node("Props/GrassPatch")
	map.compact_material_gray_preview = true
	check(patch._visual.material_override.get_shader_parameter("material_gray_preview") == true, "grass follows shared material preview")
	map.compact_material_gray_preview = false
	var panel = load("res://addons/ember_import/ember_world_look_panel.gd").new()
	root.add_child(panel)
	panel.hide()
	var history := UndoRedo.new()
	panel.set_target(scene, map, history)
	for look in [1, 2, 0]:
		var previous := map.world_look
		panel._commit("world_look", previous, look, false)
		await settle(projection)
		check(map.world_look == look, "world look command %d" % look)
		check(projection._ground_material.get_shader_parameter("look_study_mode") == look, "terrain material receives world look %d" % look)
		check(is_equal_approx(float(projection._ground_material.get_shader_parameter("look_study_pixel_m")), map.imported_tile_size / 16.0), "material cells retain 6.25 cm world scale")
		for region: Dictionary in projection._water_regions.values():
			if region.get("ground") != null:
				check(region.ground.get_shader_parameter("look_study_mode") == look, "regional terrain material follows world look")
		check(rock.solid_look() == [2, 0, 1][look], "rock receives look %d" % look)
		check(rock.get_node("Collision/Shape").shape == collider, "rock collider stays shared")
		check(projection._tiles[Vector2i(1, 2)].get_node("GroundPhysics/Shape").shape == tile_collider, "terrain collider stays shared")
		check(map.surface_floor_sample(Vector3(72, 100, 200)) == floor_before, "physical floor stays shared")
		check(map.compact_terrain.heights == source_heights and map.compact_terrain.water_levels == source_water, "look leaves authored terrain and water unchanged")
		var grass: Node = map.get_node("Props/GrassPatch")
		check(grass._visual != null and grass._visual.multimesh.instance_count > 0, "editable grass has dry instances")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(output.path_join("look-%d.png" % look)) == OK, "capture look %d" % look)
		history.undo()
		await settle(projection)
		check(map.world_look == previous, "Undo restores previous look")
		history.redo()
		await settle(projection)
		check(map.world_look == look, "Redo restores chosen look")
	# Editor save notifications restore published geometry; derived data stays transient.
	map.world_look = 2
	await settle(projection)
	scene.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "pack map")
	var saved_path := "user://location-world-looks-check.tscn"
	check(ResourceSaver.save(packed, saved_path) == OK, "save temporary map")
	scene.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
	var reopened: Node = (ResourceLoader.load(saved_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").world_look == 2, "saved look survives fresh reopen")
	check(reopened.get_node("Map/Props/GrassPatch").scatter_seed == map.get_node("Props/GrassPatch").scatter_seed, "grass parameters survive reopen")
	check(reopened.get_node("Map/Props/PaintedRockGroup/Mesh").mesh.resource_path == "res://prefabs/voxels/meshes/vox_painted_rock_group_block.res", "save references published mesh")
	map.world_look = 1
	await settle(projection)
	var teardown_deadline := Time.get_ticks_msec() + 10000
	while (patch._dirty or patch._rebuilding) and Time.get_ticks_msec() < teardown_deadline:
		await process_frame
	check(not patch._dirty and not patch._rebuilding, "grass completes its look update before teardown")
	check(reopened.get_node("Map").world_look == 2, "discard keeps saved look")
	reopened.free()
	var report := {"pass": failures.is_empty(), "failures": failures, "scene": "res://scenes/landscape_compact.tscn", "renderer": RenderingServer.get_current_rendering_method(), "save": saved_path, "manual_gate": "mouse/hotkeys and visual acceptance by author"}
	var file := FileAccess.open(output.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("LOCATION_WORLD_LOOKS ", JSON.stringify(report))
	history.clear_history()
	panel.free()
	current_scene = null
	root.remove_child(scene)
	scene.free()
	quit(0 if failures.is_empty() else 1)
