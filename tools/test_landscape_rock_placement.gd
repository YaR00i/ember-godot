extends SceneTree
## Native check of the rock group standing in the playable map scenes/landscape_compact.tscn (16 world
## units per authored block/metre): placement on dry ground, the same physical hull, the three looks at the
## map's own scale and light. Nothing under res:// is written. Argument after "--": evidence directory (landscape/).
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
var errors: Array[String] = []
var output: String
var scene: Node
var map: EmberMapLoader
var prop: EmberVoxelProp
var visual: MeshInstance3D
var camera: Camera3D
var report := {}

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL ", message)
func frames(count := 10) -> void:
	for i in count: await process_frame
	await RenderingServer.frame_post_draw
func shot(name: String) -> Image:
	await frames()
	var image := root.get_texture().get_image()
	if not name.is_empty(): check(image.save_png(output.path_join("landscape").path_join(name + ".png")) == OK, "capture " + name)
	return image
func diff(a: Image, b: Image) -> int:
	var da := a.get_data(); var db := b.get_data(); var changed := 0
	for i in range(0, da.size(), 4):
		var local := 0
		for c in 3: local = maxi(local, absi(int(da[i + c]) - int(db[i + c])))
		if local > 2: changed += 1
	return changed
func ground_at(x: float, z: float) -> float:
	var t = map.compact_terrain
	var cx := clampi(int(floor(x)), 0, t.width - 1); var cz := clampi(int(floor(z)), 0, t.depth - 1)
	return float(t.origin_y + t.heights[t.column_index(cx, cz)])
func wet_at(x: float, z: float) -> bool:
	var t = map.compact_terrain
	var cx := clampi(int(floor(x)), 0, t.width - 1); var cz := clampi(int(floor(z)), 0, t.depth - 1)
	var index: int = t.column_index(cx, cz)
	return t.water_levels[index] > t.heights[index]
func gpu_ms(count := 30) -> float:
	var viewport := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(viewport, true)
	await frames(8)
	var sum := 0.0
	for i in count:
		await process_frame
		sum += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
	return snappedf(sum / count, 0.01)
func evening(on: bool) -> void:
	var sun: DirectionalLight3D = map.get_node("Look/Sun")
	if on:
		sun.set_meta("day_basis", sun.global_transform.basis); sun.set_meta("day_colour", sun.light_color)
		sun.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-14.0), deg_to_rad(65.0), 0.0)), sun.global_position)
		sun.light_color = Color(1.0, 0.72, 0.5)
	elif sun.has_meta("day_basis"):
		sun.global_transform = Transform3D(sun.get_meta("day_basis"), sun.global_position); sun.light_color = sun.get_meta("day_colour")
func look_at_rock(offset: Vector3, fov: float) -> void:
	var bounds: AABB = visual.global_transform * (visual.mesh as ArrayMesh).get_aabb()
	var centre := bounds.get_center()
	camera.fov = fov
	camera.global_position = centre + offset
	camera.look_at(centre + Vector3(0, -4, 0))

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output.path_join("landscape"))
	scene = load("res://scenes/landscape_compact.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	var guard := 0
	while not scene._startup_complete and guard < 4000:
		await process_frame; guard += 1
	check(scene._startup_complete, "the map reaches play with the rock in it")
	map = scene.get_node("Map")
	prop = map.get_node_or_null("Props/PaintedRockGroup")
	check(prop != null and prop.model_id == "vox_painted_rock_group" and is_equal_approx(prop.block_world_size, 16.0), "the rock group is placed at 16 units per block")
	visual = prop.get_node("Mesh"); camera = root.get_viewport().get_camera_3d()
	check(camera != null, "the play camera exists")
	scene._player.camera_rig.set_process(false)
	scene._player.set_physics_process(false)
	var source: EmberVoxelModelResource = load("res://content/voxel_models/vox_painted_rock_group.tres")
	var voxels_before := source.voxels.duplicate()
	var shape: Shape3D = prop.get_node("Collision/Shape").shape
	var faces_before: PackedVector3Array = shape.get_faces()
	check(faces_before.size() > 0 and (prop.get_node("Collision") as StaticBody3D).collision_layer & 1 != 0, "the rock has its collider on the world layer")
	# 1. Sits on dry ground: no floating, bounded embedding, nothing in the water, clear of the player start.
	var bottom := (visual.global_transform * Vector3(0, (visual.mesh as ArrayMesh).get_aabb().position.y, 0)).y
	var start: Vector3 = map.get_node("Regions/PlayerStart").global_position
	var columns := 0; var floating := 0.0; var embed := 0.0; var wet := 0; var buried := 0; var nearest := INF
	for x in range(80, 156, 2):
		for z in range(160, 248, 2):
			var top: Dictionary = prop.surface_floor_sample(Vector3(x, 400, z))
			if not top.get("solid", false): continue
			columns += 1
			var ground := ground_at(x, z)
			floating = maxf(floating, bottom - ground)
			embed = maxf(embed, ground - bottom)
			if float(top.position.y) < ground: buried += 1
			if wet_at(x, z): wet += 1
			nearest = minf(nearest, Vector2(x - start.x, z - start.z).length())
	report["footprint_columns"] = columns; report["max_floating_units"] = floating; report["max_embed_units"] = embed; report["nearest_to_start_units"] = nearest
	check(columns > 400, "rock footprint found (%d columns)" % columns)
	check(floating <= 0.01, "the rock does not float anywhere (%.2f units)" % floating)
	check(embed <= 8.0, "the rock is embedded at most 8 units = 0.5 m (%.1f)" % embed)
	report["buried_columns"] = buried
	check(buried <= columns * 0.06, "the ground covers only the lowest rim of the rock (%d of %d columns)" % [buried, columns])
	check(wet == 0, "the rock stands on dry ground (%d wet columns)" % wet)
	check(nearest >= 8.0, "the rock leaves the player start free (%.1f units)" % nearest)
	var floor_sample: Dictionary = map.surface_floor_sample(Vector3(prop.global_position.x + 5.5, 400, prop.global_position.z + 4.0))
	check(floor_sample.get("solid", false) and floor_sample.get("object", null) == prop, "the map floor query finds the rock")
	# 2. Looks at the map's own scale: colour mapping in metres, depth in world units.
	var plain_material := visual.get_active_material(0) as ShaderMaterial
	check(is_equal_approx(float(plain_material.get_shader_parameter("solid_local_unit_m")), 1.0), "pattern maps one authored block to one metre in this world")
	var frames_by_look := {}
	var frame_ms := {}
	for preset in 2:
		evening(preset == 1)
		look_at_rock(Vector3(-95, 52, 40), 40.0)
		frames_by_look["low-%d" % preset] = await shot("lowpoly-close-%d" % preset)
	evening(false)
	look_at_rock(Vector3(-95, 52, 40), 40.0)
	frame_ms["low"] = await gpu_ms()
	prop.visible = false
	frame_ms["rock_hidden"] = await gpu_ms()
	prop.visible = true
	check(prop.set_solid_look(2) and prop.solid_look() == 2, "detailed look switches on in the map")
	var detailed := visual.mesh as ArrayMesh
	check(detailed.has_meta("solid_living_faces") and int(detailed.get_meta("solid_living_stats").faces) > 100 and float(detailed.get_meta("solid_living_stats").max_cm) <= 3.0001, "living faces are built at metre scale (not world units)")
	var material := visual.get_active_material(0) as ShaderMaterial
	check(is_equal_approx(float(material.get_shader_parameter("material_depth_amplitude_m")), 0.02 * 16.0), "depth amplitude 20 mm is 0.32 world units")
	check(is_equal_approx(float(material.get_shader_parameter("material_depth_fade_near_m")), Solid.DEPTH_FADE_M.x * 16.0), "depth fade distances follow the world scale")
	check(is_equal_approx(float(material.get_shader_parameter("solid_local_unit_m")), 1.0), "detailed material maps blocks to metres too")
	check(shape.get_faces() == faces_before, "collider unchanged by the detailed look")
	for preset in 2:
		evening(preset == 1)
		look_at_rock(Vector3(-95, 52, 40), 40.0)
		frames_by_look["detailed-%d" % preset] = await shot("detailed-close-%d" % preset)
	evening(false)
	look_at_rock(Vector3(-95, 52, 40), 40.0)
	frame_ms["detailed"] = await gpu_ms()
	check(diff(frames_by_look["low-0"], frames_by_look["detailed-0"]) > 3000, "the detailed look visibly differs from low poly in the map")
	# Wider views for the same look (game camera distance).
	look_at_rock(Vector3(-260, 150, 120), 40.0)
	await shot("detailed-mid")
	prop.set_solid_look(0)
	look_at_rock(Vector3(-260, 150, 120), 40.0)
	await shot("lowpoly-mid")
	prop.set_solid_look(1)
	look_at_rock(Vector3(-95, 52, 40), 40.0)
	await shot("voxel-close")
	check(prop.solid_look() == 1 and visual.mesh.has_meta("solid_voxel_look"), "voxel look works in the map")
	prop.set_solid_look(0)
	report["gpu_ms"] = frame_ms
	check(source.voxels == voxels_before, "Source untouched")
	report["pass"] = errors.is_empty(); report["errors"] = errors
	var file := FileAccess.open(output.path_join("landscape.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("LANDSCAPE_ROCK ", "PASS" if errors.is_empty() else errors, " ", JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
