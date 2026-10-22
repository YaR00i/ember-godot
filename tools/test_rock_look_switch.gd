extends SceneTree
## Native check of the developer look switch (keys 4 voxel / 5 low poly) on the ordinary rock.
## Nothing under res:// is written. Argument after "--": evidence directory.
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
	if not name.is_empty(): check(image.save_png(output.path_join("looks").path_join(name + ".png")) == OK, "capture " + name)
	return image
func view_pose(view: int) -> void:
	camera.fov = game_fov; camera.global_transform = game_pose
	if view == 1: camera.fov = 40; camera.global_position = Vector3(3, 3.1, 6.5); camera.look_at(Vector3(2, 1.1, 2.5))
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
	DirAccess.make_dir_recursive_absolute(output.path_join("looks"))
	scene = load("res://scenes/compact_environment_material_review.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	while not scene.ready_for_play: await process_frame
	scene.player.set_physics_process(false); scene.camera.set_process(false)
	camera = scene.camera._cam; game_pose = camera.global_transform; game_fov = camera.fov
	prop = scene.get_node("Map/Props/PaintedRockGroup"); visual = prop.get_node("Mesh")
	var hull := visual.mesh as ArrayMesh
	var source: EmberVoxelModelResource = load("res://content/voxel_models/vox_painted_rock_group.tres")
	var voxels_before := source.voxels.duplicate(); var parts_before := source.voxel_part_ids.duplicate()
	var shape: Shape3D = prop.get_node("Collision/Shape").shape
	var faces_before: PackedVector3Array = shape.get_faces()
	var map: EmberMapLoader = scene.get_node("Map")
	var floor_before: Dictionary = map.surface_floor_sample(Vector3(1.52, 8, 1.6))
	# Frames in the default look, for the exact return check.
	var hull_frames := {}
	for preset in 3:
		scene.set_lighting(preset, 1)
		for view in 2:
			view_pose(view)
			hull_frames["%d-%d" % [preset, view]] = await shot("lowpoly-%d-%d" % [preset, view])
	# Key 4: voxel cubes of the same Source.
	var started := Time.get_ticks_msec()
	press(KEY_4)
	report["voxel_build_ms"] = Time.get_ticks_msec() - started
	var voxel := visual.mesh as ArrayMesh
	check(voxel != hull and voxel.has_meta("solid_voxel_look"), "key 4 shows the voxel look")
	check(prop.solid_look() == 1, "prop reports voxel look")
	# Expected exposed faces counted independently from the Source.
	var size := source.grid_size(); var expected_quads := 0
	var model := EmberVoxelPrefab.model_of(source.to_definition())
	var channel := VoxMesher.model_channel(model, "voxels")
	for z in size.z:
		for y in size.y:
			for x in size.x:
				if channel[VoxMesher.cell_index(x, y, z, size.x, size.z)] == 0: continue
				for n in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					var nx: int = x + n.x; var ny: int = y + n.y; var nz: int = z + n.z
					if nx < 0 or ny < 0 or nz < 0 or nx >= size.x or ny >= size.y or nz >= size.z or channel[VoxMesher.cell_index(nx, ny, nz, size.x, size.z)] == 0: expected_quads += 1
	var arrays := voxel.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]; var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	report["voxel_triangles"] = vertices.size() / 3; report["expected_quads"] = expected_quads
	check(vertices.size() == expected_quads * 6, "one quad per exposed voxel face and nothing else")
	var on_grid := true; var axis_normals := true; var outward := true
	for i in vertices.size():
		var scaled := vertices[i] * 16.0
		if not (is_equal_approx(scaled.x, roundf(scaled.x)) and is_equal_approx(scaled.y, roundf(scaled.y)) and is_equal_approx(scaled.z, roundf(scaled.z))): on_grid = false
		if absf(normals[i].length() - 1.0) > 0.001 or absf(normals[i].abs().x + normals[i].abs().y + normals[i].abs().z - 1.0) > 0.001: axis_normals = false
	for t in range(0, vertices.size(), 3):
		var face_normal := (vertices[t + 2] - vertices[t]).cross(vertices[t + 1] - vertices[t]).normalized()
		if face_normal.dot(normals[t]) < 0.99: outward = false
	check(on_grid, "all voxel corners lie on the 1/16 block grid")
	check(axis_normals, "normals are the six cube directions")
	check(outward, "triangle winding faces outward")
	var material := visual.get_active_material(0) as ShaderMaterial
	check(is_equal_approx(float(material.get_shader_parameter("solid_pixel_cells")), 16.0) and int(material.get_shader_parameter("solid_projection_mode")) == 1, "voxel material reads the pattern once per voxel")
	check(shape.get_faces() == faces_before and prop.get_node("Collision/Shape").shape == shape, "collider unchanged in voxel look")
	var floor_after: Dictionary = map.surface_floor_sample(Vector3(1.52, 8, 1.6))
	check(floor_after.get("solid", false) and absf(floor_after.position.y - floor_before.position.y) < 0.00001, "floor unchanged in voxel look")
	check(source.voxels == voxels_before and source.voxel_part_ids == parts_before, "Source untouched")
	for preset in 3:
		scene.set_lighting(preset, 1)
		for view in 2:
			view_pose(view)
			await shot("voxel-%d-%d" % [preset, view])
	# Pattern belongs to the object in the voxel look too (sun off, rock alone).
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
		camera.fov = 38; camera.global_position = about * (pivot + direction * 6.5); camera.look_at(about * pivot)
		var image := await shot("voxel-motion-" + case)
		if case == "home": reference = image
		else:
			motion[case] = diff(reference, image)
			check(motion[case].pixels_gt2 < 50, "voxel pattern sticks to the rock: " + case)
	prop.global_transform = home
	isolate_rock(false)
	sun.light_energy = saved.energy; environment.ambient_light_color = saved.colour; environment.ambient_light_energy = saved.ambient
	environment.ambient_light_source = saved.source; environment.ssao_enabled = saved.ssao
	report["voxel_motion"] = motion
	# Key 5: back to the low poly hull, exactly.
	press(KEY_5)
	check(visual.mesh == hull and prop.solid_look() == 0, "key 5 returns the original hull mesh")
	var restored := visual.get_active_material(0) as ShaderMaterial
	check(float(restored.get_shader_parameter("solid_pixel_cells") if restored.get_shader_parameter("solid_pixel_cells") != null else 0.0) == 0.0, "pixel quantisation off in low poly")
	var returns := 0
	for preset in 3:
		scene.set_lighting(preset, 1)
		for view in 2:
			view_pose(view)
			var back := await shot("return-%d-%d" % [preset, view])
			var d := diff(back, hull_frames["%d-%d" % [preset, view]])
			report["return_%d_%d" % [preset, view]] = d
			if d.max == 0: returns += 1
	check(returns == 6, "low poly frames return pixel-exact after 4 -> 5")
	report["lowpoly_returns_exact"] = returns
	check(shape.get_faces() == faces_before, "collider unchanged after switching back")
	# Repeated switching keeps the cached meshes.
	press(KEY_4); var cached := visual.mesh; press(KEY_5); press(KEY_4)
	check(visual.mesh == cached, "voxel mesh is built once and reused")
	press(KEY_5)
	report["pass"] = errors.is_empty(); report["errors"] = errors
	var file := FileAccess.open(output.path_join("looks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("ROCK_LOOK_SWITCH ", "PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
