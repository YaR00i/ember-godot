extends SceneTree
## Native check of the ordinary rock transfer: form normals in the library prefab, object-local
## pattern, rim from the material (0.5, 10 mm silhouette frame), unchanged collider. Nothing under res:// is written.
## Arguments after "--": evidence directory (has before-files/ and frames/ from the probe).
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
	if not name.is_empty(): check(image.save_png(output.path_join("transfer").path_join(name + ".png")) == OK, "capture " + name)
	return image
func view_pose(view: int) -> void:
	camera.fov = game_fov; camera.global_transform = game_pose
	if view == 1: camera.fov = 40; camera.global_position = Vector3(3, 3.1, 6.5); camera.look_at(Vector3(2, 1.1, 2.5))
	if view == 2: camera.fov = 42; camera.global_position = Vector3(10, 8, 16); camera.look_at(Vector3(4.5, 1.1, 4.7))
func diff(a: Image, b: Image) -> Dictionary:
	var da := a.get_data(); var db := b.get_data(); var sum := 0.0; var maximum := 0; var changed := 0
	for i in range(0, da.size(), 4):
		var local := 0
		for c in 3: local = maxi(local, absi(int(da[i + c]) - int(db[i + c])))
		sum += local; maximum = maxi(maximum, local)
		if local > 2: changed += 1
	return {"mean": snappedf(sum / (da.size() / 4.0), 0.0001), "max": maximum, "pixels_gt2": changed}
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
	DirAccess.make_dir_recursive_absolute(output.path_join("transfer"))
	scene = load("res://scenes/compact_environment_material_review.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	while not scene.ready_for_play: await process_frame
	scene.player.set_physics_process(false); scene.camera.set_process(false)
	camera = scene.camera._cam; game_pose = camera.global_transform; game_fov = camera.fov
	prop = scene.get_node("Map/Props/PaintedRockGroup"); visual = prop.get_node("Mesh")
	var mesh := visual.mesh as ArrayMesh
	# 1. Data: ordinary prefab carries form normals; Source untouched; collider identical.
	check(mesh.has_meta("solid_form_contract") and mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0 != 0, "library mesh carries CUSTOM0 form normals")
	var stone: EmberCompactTerrainPattern = load("res://content/terrain_materials/cartoon_stone.tres")
	check(stone.style_rim_custom and stone.style_rim_enabled and is_equal_approx(stone.style_rim_strength, 0.5) and stone.validation_errors().is_empty(), "stone material rim 0.5 validates")
	var material := visual.get_active_material(0) as ShaderMaterial
	check(int(material.get_shader_parameter("solid_projection_mode")) == 1 and bool(material.get_shader_parameter("solid_form_rim")), "instance material uses form look")
	var silhouette_data := Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3
	check(mesh.surface_get_format(0) & silhouette_data == silhouette_data and is_equal_approx(stone.style_rim_width_mm, 10.0), "rim is a 10 mm silhouette frame (data + material setting)")
	check(is_equal_approx(float(material.get_shader_parameter("solid_facet_bias")), 0.35) and is_equal_approx(float(material.get_shader_parameter("solid_local_unit_m")), prop.block_world_size), "bias and unit bound")
	var rim: Image = material.get_meta("ember_style_rim_image")
	check(rim.get_pixel(1, 0).r > 0.5 and rim.get_pixel(1, 0).g > 0.5 and is_equal_approx(rim.get_pixel(1, 0).b, 0.5), "GPU rim lookup from the material")
	var before_scene: PackedScene = ResourceLoader.load(output.path_join("before-files/vox_painted_rock_group.tscn"), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	var before := before_scene.instantiate()
	var faces_before: PackedVector3Array = before.get_node("Collision/Shape").shape.get_faces()
	var faces_after: PackedVector3Array = prop.get_node("Collision/Shape").shape.get_faces()
	check(faces_before == faces_after and not faces_after.is_empty(), "collider triangles identical to previous prefab")
	check(before.get_node("Mesh").mesh.get_faces() == mesh.get_faces(), "visual triangles identical to previous prefab")
	before.free()
	var map: EmberMapLoader = scene.get_node("Map")
	for point in [Vector2(1.52, 1.6), Vector2(1.96, 2.8), Vector2(0.76, 2.65), Vector2(2.98, 2.28)]:
		await physics_frame
		var sample: Dictionary = map.surface_floor_sample(Vector3(point.x, 8, point.y))
		var hit: Dictionary = scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x, 8, point.y), Vector3(point.x, -2, point.y), 1))
		check(sample.get("solid", false) and not hit.is_empty() and absf(sample.position.y - hit.position.y) < 0.0001, "floor query equals physics ray")
	# 2. Frames at the game camera/close/overview, 3 presets x 2 sun sides; compare with probe C2s.
	var probe_exact := 0; var probe_worst := 0.0; var records: Array = []
	for preset in 3:
		for side in 2:
			scene.set_lighting(preset, side)
			for view in 3:
				view_pose(view)
				var name := "after-%d-%d-%d" % [preset, side, view]
				var image := await shot(name)
				var d := {"mean": 0.0, "max": 0}
				if side == 1 and view < 2:
					# Chosen rim: 10 mm frame along silhouette edges (option Wb).
					var reference := Image.load_from_file(output.path_join("options/Wb-%d-%d.png" % [preset, view]))
					d = diff(image, reference)
					if d.max == 0: probe_exact += 1
					probe_worst = maxf(probe_worst, d.mean)
					check(d.mean < 0.05, "production frame matches chosen rim frame " + name)
				records.append({"frame": name, "vs_chosen_option": d})
				var old_frame := Image.load_from_file(output.path_join("frames/A-%d-%d-%d.png" % [preset, side, view]))
				records[-1]["vs_previous_A"] = diff(image, old_frame)
	report["option_match"] = {"exact": probe_exact, "of": 6, "worst_mean": probe_worst}
	# 3. Master switch (map) and real shadows still control the rim.
	scene.set_lighting(1, 1); view_pose(1)
	var with_rim := await shot("")
	map.compact_style_rim_enabled = false
	var without := await shot("shot-master-off")
	check(diff(with_rim, without).pixels_gt2 > 500, "map rim switch removes the rim")
	map.compact_style_rim_enabled = true
	check((await shot("")).get_data() == with_rim.get_data(), "rim switch returns exactly")
	var sun: DirectionalLight3D = scene.get_node("Map/Look/Sun")
	sun.shadow_enabled = false
	var no_shadow := await shot("")
	check(diff(with_rim, no_shadow).pixels_gt2 > 500, "real shadows affect the scene")
	sun.shadow_enabled = true
	check((await shot("")).get_data() == with_rim.get_data(), "shadow return exact")
	# 4. The pattern belongs to the object: rock alone, no sun, white ambient.
	var environment: Environment = scene.get_node("Map/Look/WorldEnvironment").environment
	var saved := {"energy": sun.light_energy, "colour": environment.ambient_light_color, "ambient": environment.ambient_light_energy, "source": environment.ambient_light_source, "ssao": environment.ssao_enabled}
	sun.light_energy = 0.0; environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE; environment.ambient_light_energy = 1.0; environment.ssao_enabled = false
	isolate_rock(true)
	var pivot: Vector3 = visual.global_transform * (visual.mesh as ArrayMesh).get_aabb().get_center()
	var home := prop.global_transform
	var direction := Vector3(0.62, 0.55, 0.78).normalized()
	var reference: Image; var motion := {}
	for case in ["home", "yaw22", "yaw45", "shift"]:
		var turn := Transform3D.IDENTITY
		if case == "yaw22": turn = Transform3D(Basis(Vector3.UP, deg_to_rad(22.5)), Vector3.ZERO)
		if case == "yaw45": turn = Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), Vector3.ZERO)
		var about := Transform3D(Basis.IDENTITY, pivot) * turn * Transform3D(Basis.IDENTITY, -pivot)
		if case == "shift": about = Transform3D(Basis.IDENTITY, Vector3(1.3, 0, 0.7))
		prop.global_transform = about * home
		camera.fov = 38; camera.global_position = about * (pivot + direction * 6.5); camera.look_at(about * pivot)
		var image := await shot("motion-" + case)
		if case == "home": reference = image
		else:
			motion[case] = diff(reference, image)
			check(motion[case].pixels_gt2 < 50, "pattern sticks to the rock: " + case)
	prop.global_transform = home
	isolate_rock(false)
	report["motion"] = motion
	report["frames"] = records
	var file := FileAccess.open(output.path_join("transfer.json"), FileAccess.WRITE)
	report["pass"] = errors.is_empty(); report["errors"] = errors
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("ROCK_FORM_TRANSFER ", "PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
