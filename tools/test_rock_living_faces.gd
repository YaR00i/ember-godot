extends SceneTree
## Native check of the living faces of the detailed look (key 6): the hull faces drift toward the voxel
## Source by the material's form_pull_mm, while edges, silhouette, collider, floor and Source stay exact.
## Nothing under res:// is written. Argument after "--": evidence directory (living/).
const Solid = preload("res://scripts/ember_voxel_solid_surface.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
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
	if not name.is_empty(): check(image.save_png(output.path_join("living").path_join(name + ".png")) == OK, "capture " + name)
	return image
func view_pose(view: int) -> void:
	camera.fov = game_fov; camera.global_transform = game_pose
	if view == 1: camera.fov = 40; camera.global_position = Vector3(3, 3.1, 6.5); camera.look_at(Vector3(2, 1.1, 2.5))
	if view == 2:
		var centre: Vector3 = visual.global_transform * (visual.mesh as ArrayMesh).get_aabb().get_center()
		camera.fov = 38; camera.global_position = centre + Vector3(-1.2, 2.7, 4.6); camera.look_at(centre + Vector3(0, 0.2, 0))
func diff(a: Image, b: Image) -> int:
	var da := a.get_data(); var db := b.get_data(); var changed := 0
	for i in range(0, da.size(), 4):
		var local := 0
		for c in 3: local = maxi(local, absi(int(da[i + c]) - int(db[i + c])))
		if local > 2: changed += 1
	return changed
func press(keycode: int) -> void:
	var event := InputEventKey.new(); event.keycode = keycode; event.pressed = true
	scene._unhandled_key_input(event)
func triangles(mesh: ArrayMesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output.path_join("living"))
	# 1. Setting: chosen 30 mm on the stone, validated.
	var stone: EmberCompactTerrainPattern = Materials.load_compact_terrain_variant("cartoon_stone")
	check(is_equal_approx(stone.form_pull_mm, 30.0) and stone.validation_errors().is_empty(), "stone carries the chosen 30 mm face pull")
	for bad in [NAN, -1.0, 61.0]:
		var broken := stone.duplicate(true) as EmberCompactTerrainPattern
		broken.form_pull_mm = bad
		check(not broken.validation_errors().is_empty(), "invalid face pull rejected " + str(bad))
	# 2. Pure geometry from the Source.
	var source: EmberVoxelModelResource = load("res://content/voxel_models/vox_painted_rock_group.tres")
	var voxels_before := source.voxels.duplicate()
	var model := EmberVoxelPrefab.model_of(source.to_definition())
	var hull: ArrayMesh = Solid.build(model)
	var saved := load("res://prefabs/voxels/meshes/vox_painted_rock_group_block.res") as ArrayMesh
	if saved != null:
		var a := hull.surface_get_arrays(0); var b := saved.surface_get_arrays(0)
		check(a[Mesh.ARRAY_VERTEX] == b[Mesh.ARRAY_VERTEX] and a[Mesh.ARRAY_NORMAL] == b[Mesh.ARRAY_NORMAL] and a[Mesh.ARRAY_COLOR] == b[Mesh.ARRAY_COLOR], "hull build is unchanged by the face refactor")
	var ids: PackedStringArray = model.solidSurface.material_ids
	var pulls := Solid.living_pulls(ids)
	check(pulls.size() == ids.size() and is_equal_approx(pulls[1], 0.03), "pull read per palette slot (stone 30 mm)")
	Solid.clear_living_cache()
	var t0 := Time.get_ticks_msec()
	var living: ArrayMesh = Solid.living_mesh(model, 1.0, pulls)
	var build_ms := Time.get_ticks_msec() - t0
	check(living.get_surface_count() == 1 and living.has_meta("solid_living_faces"), "living mesh built")
	var stats: Dictionary = living.get_meta("solid_living_stats", {})
	var living_vertices := triangles(living)
	var hull_vertices := triangles(hull)
	report["build_ms"] = build_ms; report["triangles"] = living_vertices.size() / 3; report["hull_triangles"] = hull_vertices.size() / 3; report["stats"] = stats
	check(living_vertices.size() / 3 > hull_vertices.size() / 3 and living_vertices.size() / 3 < 15000, "living triangle count is moderate (%d)" % (living_vertices.size() / 3))
	check(float(stats.get("max_cm", 99.0)) <= 3.0001 and float(stats.get("max_cm", 0.0)) > 1.0, "displacement stays within the 3 cm limit (max %.2f cm)" % float(stats.get("max_cm", -1.0)))
	check(int(stats.get("faces", 0)) > 50, "most hull faces are living (%d)" % int(stats.get("faces", 0)))
	var finite := true
	for vertex in living_vertices: if not vertex.is_finite(): finite = false
	check(finite, "all living vertices finite")
	# Hull corners keep their exact place and the overall extent only changes by the pull.
	var living_keys := {}
	for vertex in living_vertices: living_keys[Vector3i((vertex * 1000.0).round())] = true
	var missing := 0
	for vertex in hull_vertices: if not living_keys.has(Vector3i((vertex * 1000.0).round())): missing += 1
	check(missing == 0, "every hull corner exists unchanged in the living mesh (%d missing)" % missing)
	var hull_box := hull.get_aabb().grow(0.0301); var living_box := living.get_aabb()
	check(hull_box.encloses(living_box), "living mesh stays inside the hull box plus the pull")
	# Winding and normals follow the hull faces.
	var living_arrays := living.surface_get_arrays(0)
	var normals: PackedVector3Array = living_arrays[Mesh.ARRAY_NORMAL]
	var outward := 0; var total := living_vertices.size() / 3
	for t in total:
		var geometric := (living_vertices[t * 3 + 2] - living_vertices[t * 3]).cross(living_vertices[t * 3 + 1] - living_vertices[t * 3])
		if geometric.dot(normals[t * 3] + normals[t * 3 + 1] + normals[t * 3 + 2]) > 0.0: outward += 1
	check(outward >= total * 0.99, "triangles wind outward (%d of %d)" % [outward, total])
	var degenerate := 0
	for t in total:
		if (living_vertices[t * 3 + 1] - living_vertices[t * 3]).cross(living_vertices[t * 3 + 2] - living_vertices[t * 3]).length() < 1.0e-9: degenerate += 1
	check(degenerate == 0, "no degenerate triangles (%d)" % degenerate)
	# Cache, determinism, zero pull.
	check(Solid.living_mesh(model, 1.0, pulls) == living, "same Source and pull reuse the cached mesh")
	var other_pulls := pulls.duplicate(); other_pulls[1] = 0.06
	var stronger: ArrayMesh = Solid.living_mesh(model, 1.0, other_pulls)
	check(stronger != living and float(stronger.get_meta("solid_living_stats").max_cm) > float(stats.max_cm) and float(stronger.get_meta("solid_living_stats").max_cm) <= 6.0001, "60 mm pull reaches further than 30 mm (max %.2f cm)" % float(stronger.get_meta("solid_living_stats").max_cm))
	Solid.clear_living_cache()
	var again: ArrayMesh = Solid.living_mesh(model, 1.0, pulls)
	check(triangles(again) == living_vertices, "rebuild is deterministic")
	check(Solid.living_mesh(model, 1.0, PackedFloat32Array([0.0, 0.0])).get_surface_count() == 0, "zero pull gives no living mesh")
	# 3. Inside the scene: key 6 uses it, nothing physical changes.
	scene = load("res://scenes/compact_environment_material_review.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	while not scene.ready_for_play: await process_frame
	scene.player.set_physics_process(false); scene.camera.set_process(false)
	camera = scene.camera._cam; game_pose = camera.global_transform; game_fov = camera.fov
	prop = scene.get_node("Map/Props/PaintedRockGroup"); visual = prop.get_node("Mesh")
	var hull_mesh := visual.mesh as ArrayMesh
	var shape: Shape3D = prop.get_node("Collision/Shape").shape
	var faces_before: PackedVector3Array = shape.get_faces()
	var map: EmberMapLoader = scene.get_node("Map")
	var floor_before: Dictionary = map.surface_floor_sample(Vector3(1.52, 8, 1.6))
	var plain := {}
	for view in 3:
		scene.set_lighting(0, 1)
		view_pose(view)
		plain[view] = await shot("lowpoly-%d" % view)
	press(KEY_6)
	var detailed_mesh := visual.mesh as ArrayMesh
	check(prop.solid_look() == 2 and detailed_mesh.has_meta("solid_living_faces") and detailed_mesh != hull_mesh, "key 6 shows the living faces")
	check(detailed_mesh.has_meta("solid_surface_material_ids") and detailed_mesh.get_meta("solid_surface_material_ids") == hull_mesh.get_meta("solid_surface_material_ids"), "living mesh carries the same material slots")
	check(shape.get_faces() == faces_before, "collider unchanged")
	check(absf(float(map.surface_floor_sample(Vector3(1.52, 8, 1.6)).position.y) - float(floor_before.position.y)) < 0.00001, "floor unchanged")
	var material := visual.get_active_material(0) as ShaderMaterial
	check(material.shader.code.contains("#define EMBER_SOLID_DEPTH") and bool(material.get_shader_parameter("material_depth_enabled")), "depth is still bound on the living faces")
	var living_frames := {}
	for view in 3:
		scene.set_lighting(0, 1)
		view_pose(view)
		living_frames[view] = await shot("living-%d" % view)
	# Same pull as the 30 mm chosen: scene mesh equals the cached geometry of the pure build (scale 1 m / block).
	check(triangles(detailed_mesh) == living_vertices, "scene mesh equals the pure build")
	# 4. Editor draft: a larger pull previews, discarding returns the saved one, zero returns the flat hull.
	var draft := stone.duplicate(true) as EmberCompactTerrainPattern
	draft.form_pull_mm = 60.0
	prop.preview_solid_material_light(draft, "cartoon_stone")
	check(visual.mesh != detailed_mesh and is_equal_approx(float(visual.mesh.get_meta("solid_living_pulls")[1]), 0.06), "draft pull previews on the object")
	check((visual.get_active_material(0) as ShaderMaterial).get_meta("ember_detailed_depth", false) and bool((visual.get_active_material(0) as ShaderMaterial).get_shader_parameter("material_depth_enabled")), "depth stays bound after the draft rebuild")
	prop.preview_solid_material_light(stone, "cartoon_stone")
	check(visual.mesh == detailed_mesh, "returning to the saved pull restores the same mesh")
	draft.form_pull_mm = 0.0
	prop.preview_solid_material_light(draft, "cartoon_stone")
	check(visual.mesh == hull_mesh and prop.solid_look() == 2, "zero pull is the flat hull in the detailed look")
	var flat_frame := await shot("")
	prop.preview_solid_material_light(stone, "cartoon_stone")
	check(visual.mesh == detailed_mesh, "pull restored")
	check(diff(flat_frame, living_frames[0]) > 300, "living faces visibly differ from flat faces in the game view")
	# 5. Looks keep switching: 5 -> hull, 4 -> voxels, 6 -> the same living mesh again.
	press(KEY_5)
	check(visual.mesh == hull_mesh and prop.solid_look() == 0, "key 5 returns the hull")
	press(KEY_4)
	check(prop.solid_look() == 1 and visual.mesh.has_meta("solid_voxel_look"), "key 4 shows voxels")
	press(KEY_6)
	check(visual.mesh == detailed_mesh, "key 6 again reuses the cached living mesh")
	press(KEY_5)
	var returns := 0
	for view in 3:
		scene.set_lighting(0, 1)
		view_pose(view)
		if (await shot("")).get_data() == plain[view].get_data(): returns += 1
	check(returns == 3, "low poly frames return pixel-exact after the detailed look")
	check(source.voxels == voxels_before, "Source untouched")
	report["pass"] = errors.is_empty(); report["errors"] = errors
	var file := FileAccess.open(output.path_join("living.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("ROCK_LIVING_FACES ", "PASS" if errors.is_empty() else errors, " ", JSON.stringify(report))
	quit(0 if errors.is_empty() else 1)
