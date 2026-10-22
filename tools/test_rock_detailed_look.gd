extends SceneTree
## Native check of the detailed look (key 6): low poly hull + optical depth derived from the painted
## colour. Nothing under res:// is written. Argument after "--": evidence directory (frames/, depth/).
const Height = preload("res://scripts/ember_material_height.gd")
var errors: Array[String] = []
var output: String
var scene: Node
var prop: EmberVoxelProp
var visual: MeshInstance3D
var camera: Camera3D
var game_pose: Transform3D
var game_fov: float
var report := {}

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL ", message)
func frames(count := 8) -> void:
	for i in count: await process_frame
	await RenderingServer.frame_post_draw
func shot(name: String) -> Image:
	await frames()
	var image := root.get_texture().get_image()
	if not name.is_empty(): check(image.save_png(output.path_join("detailed").path_join(name + ".png")) == OK, "capture " + name)
	return image
func view_pose(view: int) -> void:
	camera.fov = game_fov; camera.global_transform = game_pose
	if view == 1: camera.fov = 40; camera.global_position = Vector3(3, 3.1, 6.5); camera.look_at(Vector3(2, 1.1, 2.5))
	if view == 2:
		var centre: Vector3 = visual.global_transform * (visual.mesh as ArrayMesh).get_aabb().get_center()
		camera.fov = 38; camera.global_position = centre + Vector3(-1.2, 2.7, 4.6); camera.look_at(centre + Vector3(0, 0.2, 0))
func diff(a: Image, b: Image) -> Dictionary:
	var da := a.get_data(); var db := b.get_data(); var sum := 0.0; var maximum := 0; var changed := 0
	for i in range(0, da.size(), 4):
		var local := 0
		for c in 3: local = maxi(local, absi(int(da[i + c]) - int(db[i + c])))
		sum += local; maximum = maxi(maximum, local)
		if local > 2: changed += 1
	return {"mean": snappedf(sum / (da.size() / 4.0), 0.0001), "max": maximum, "pixels_gt2": changed}
func press(keycode: int) -> void:
	var event := InputEventKey.new(); event.keycode = keycode; event.pressed = true
	scene._unhandled_key_input(event)
func isolate_rock(on: bool) -> void:
	var map := scene.get_node("Map")
	for child in map.get_children():
		if child.name != "Look" and child.name != "Props" and "visible" in child: child.visible = not on
	var oak := map.get_node_or_null("Props/PaintedOak")
	if oak: oak.visible = not on
	var grass := scene.get_node_or_null("GrassTufts")
	if grass: grass.visible = not on

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output.path_join("detailed"))
	# 1. Pure height derivation: deterministic, periodic-sized, equal to the accepted probe map.
	var stone: EmberCompactTerrainPattern = load("res://content/terrain_materials/cartoon_stone.tres")
	check(is_equal_approx(stone.depth_mm, 20.0) and is_equal_approx(stone.depth_softness, 2.5) and is_equal_approx(stone.depth_sharpness, 0.1) and stone.validation_errors().is_empty(), "stone carries the chosen depth setting")
	for bad in [[NAN, 2.5, 0.1], [-1.0, 2.5, 0.1], [31.0, 2.5, 0.1], [10.0, 0.2, 0.1], [10.0, 2.5, 1.5]]:
		var broken := stone.duplicate(true) as EmberCompactTerrainPattern
		broken.depth_mm = bad[0]; broken.depth_softness = bad[1]; broken.depth_sharpness = bad[2]
		check(not broken.validation_errors().is_empty(), "invalid depth setting rejected " + str(bad))
	var source := Image.load_from_file(ProjectSettings.globalize_path("res://content/terrain_materials/textures/rock-painted-calm-v2-runtime.png"))
	var first := Height.bake(source, 2.5, 0.1); var second := Height.bake(source, 2.5, 0.1)
	check(first.get_data() == second.get_data() and first.get_size() == Vector2i(256, 256), "height bake is deterministic")
	var accepted := Image.load_from_file(output.path_join("depth/height-C2.png"))
	if accepted != null:
		accepted.convert(Image.FORMAT_R8)
		var same := 0
		var base_level := first.duplicate() as Image
		base_level.clear_mipmaps()
		var a := base_level.get_data(); var b := accepted.get_data()
		for i in mini(a.size(), b.size()): if absi(int(a[i]) - int(b[i])) <= 1: same += 1
		check(a.size() == b.size() and same == a.size(), "height equals the accepted probe C2 map (within 1/255)")
	var soft := Height.bake(source, 2.5, 0.0); var steep := Height.bake(source, 2.5, 0.8)
	check(soft.get_data() != first.get_data() and first.get_data() != steep.get_data(), "softness/sharpness change the map")
	scene = load("res://scenes/compact_environment_material_review.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	while not scene.ready_for_play: await process_frame
	scene.player.set_physics_process(false); scene.camera.set_process(false)
	camera = scene.camera._cam; game_pose = camera.global_transform; game_fov = camera.fov
	prop = scene.get_node("Map/Props/PaintedRockGroup"); visual = prop.get_node("Mesh")
	var hull := visual.mesh as ArrayMesh
	var shape: Shape3D = prop.get_node("Collision/Shape").shape
	var faces_before: PackedVector3Array = shape.get_faces()
	var map: EmberMapLoader = scene.get_node("Map")
	var source_resource: EmberVoxelModelResource = load("res://content/voxel_models/vox_painted_rock_group.tres")
	var voxels_before := source_resource.voxels.duplicate()
	var floor_before: Dictionary = map.surface_floor_sample(Vector3(1.52, 8, 1.6))
	var plain := {}
	for preset in 3:
		scene.set_lighting(preset, 1)
		for view in 3:
			view_pose(view)
			plain["%d-%d" % [preset, view]] = await shot("lowpoly-%d-%d" % [preset, view])
	var plain_material := visual.get_active_material(0) as ShaderMaterial
	check(not plain_material.shader.code.contains("EMBER_SOLID_DEPTH"), "low poly keeps the plain shader (no depth cost)")
	# 2. Key 6.
	press(KEY_6)
	check(prop.solid_look() == 2 and visual.mesh != hull and visual.mesh.has_meta("solid_living_faces"), "key 6 shows the detailed look on the living faces of the stone")
	# The accepted C2 reference frames are the flat hull: ask for it with a zero face pull (editor draft).
	var flat_draft := stone.duplicate(true) as EmberCompactTerrainPattern
	flat_draft.form_pull_mm = 0.0
	prop.preview_solid_material_light(flat_draft, "cartoon_stone")
	check(prop.solid_look() == 2 and visual.mesh == hull, "zero face pull shows the detailed look on the same hull mesh")
	var material := visual.get_active_material(0) as ShaderMaterial
	check(material.shader.code.contains("#define EMBER_SOLID_DEPTH") and bool(material.get_meta("ember_detailed_depth", false)), "detailed material uses the solid depth shader and bound a height map")
	check(bool(material.get_shader_parameter("material_depth_enabled")) and is_equal_approx(float(material.get_shader_parameter("material_depth_amplitude_m")), 0.02), "depth 20 mm total")
	var height_texture: Texture2D = material.get_shader_parameter("material_depth_height")
	check(height_texture != null and height_texture.get_width() == 256, "256 px height map bound")
	check(shape.get_faces() == faces_before, "collider unchanged in the detailed look")
	check(absf(float(map.surface_floor_sample(Vector3(1.52, 8, 1.6)).position.y) - float(floor_before.position.y)) < 0.00001, "floor unchanged in the detailed look")
	var expected_inverse := Projection(visual.global_transform.affine_inverse())
	var bound: Projection = material.get_shader_parameter("solid_depth_world_to_local")
	check(bound == expected_inverse, "object transform bound for the object-space depth")
	var detailed_frames := {}
	var probe_diffs := {}
	for preset in 3:
		scene.set_lighting(preset, 1)
		await process_frame
		for view in 3:
			view_pose(view)
			var image := await shot("detailed-%d-%d" % [preset, view])
			detailed_frames["%d-%d" % [preset, view]] = image
			var probe := Image.load_from_file(output.path_join("depth/C2-%d-%d.png" % [preset, view]))
			if probe != null: probe_diffs["%d-%d" % [preset, view]] = diff(image, probe)
			check(diff(image, plain["%d-%d" % [preset, view]]).pixels_gt2 > 5000, "depth visibly changes the rock: %d-%d" % [preset, view])
	report["vs_probe_C2"] = probe_diffs
	for key in probe_diffs: check(probe_diffs[key].mean < 0.5, "production detailed frame matches the accepted probe " + key)
	# 3. The depth belongs to the object: sun off, rock alone, rotate/shift together with the camera.
	var sun: DirectionalLight3D = scene.get_node("Map/Look/Sun")
	var environment: Environment = scene.get_node("Map/Look/WorldEnvironment").environment
	var saved := {"energy": sun.light_energy, "colour": environment.ambient_light_color, "ambient": environment.ambient_light_energy, "source": environment.ambient_light_source, "ssao": environment.ssao_enabled}
	sun.light_energy = 0.0; environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE; environment.ambient_light_energy = 1.0; environment.ssao_enabled = false
	isolate_rock(true)
	var pivot: Vector3 = visual.global_transform * hull.get_aabb().get_center()
	var home := prop.global_transform; var direction := Vector3(0.62, 0.55, 0.78).normalized()
	var reference: Image; var motion := {}
	for case in ["home", "yaw22", "yaw45", "shift"]:
		var turn := Transform3D.IDENTITY
		if case == "yaw22": turn = Transform3D(Basis(Vector3.UP, deg_to_rad(22.5)), Vector3.ZERO)
		if case == "yaw45": turn = Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), Vector3.ZERO)
		var about := Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot)
		if case == "shift": about = Transform3D(Basis.IDENTITY, Vector3(1.3, 0, 0.7))
		prop.global_transform = about * home
		await process_frame
		camera.fov = 38; camera.global_position = about * (pivot + direction * 6.5); camera.look_at(about * pivot)
		var image := await shot("motion-" + case)
		if case == "home": reference = image
		else:
			motion[case] = diff(reference, image)
			check(motion[case].pixels_gt2 < 400, "depth sticks to the rock: " + case + " " + str(motion[case]))
	prop.global_transform = home
	await process_frame
	isolate_rock(false)
	sun.light_energy = saved.energy; environment.ambient_light_color = saved.colour; environment.ambient_light_energy = saved.ambient
	environment.ambient_light_source = saved.source; environment.ssao_enabled = saved.ssao
	report["motion"] = motion
	# 4. Back to low poly exactly; other looks keep working with the detailed one in between.
	press(KEY_5)
	check(visual.mesh == hull and prop.solid_look() == 0 and not (visual.get_active_material(0) as ShaderMaterial).shader.code.contains("EMBER_SOLID_DEPTH"), "key 5 returns the plain low poly material")
	var returns := 0
	for preset in 3:
		scene.set_lighting(preset, 1)
		for view in 3:
			view_pose(view)
			if (await shot("")).get_data() == plain["%d-%d" % [preset, view]].get_data(): returns += 1
	check(returns == 9, "low poly frames return pixel-exact after 6 -> 5")
	report["lowpoly_returns_exact"] = returns
	press(KEY_4); press(KEY_6); press(KEY_5)
	check(visual.mesh == hull and prop.solid_look() == 0, "4 -> 6 -> 5 keeps the looks consistent")
	check(source_resource.voxels == voxels_before, "Source untouched")
	report["pass"] = errors.is_empty(); report["errors"] = errors
	var file := FileAccess.open(output.path_join("detailed.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("ROCK_DETAILED_LOOK ", "PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
