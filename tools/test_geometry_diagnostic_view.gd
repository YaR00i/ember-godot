extends SceneTree
## Actual Forward+ LOD counts and reversible viewport diagnostics.
const Overlay = preload("res://scripts/ember_benchmark_overlay.gd")
const Lod = preload("res://scripts/prototypes/ember_terrain_mesh_lod.gd")
var failures: Array[String] = []
var observations: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("GEOMETRY_VIEW_FAIL ", label)

func primitives() -> int:
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)

func run() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		printerr("GEOMETRY_VIEW_FAIL requires native Forward+")
		quit(2)
		return
	root.size = Vector2i(1024, 640)
	root.mesh_lod_threshold = 0.75
	root.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	var stage := Node3D.new()
	root.add_child(stage)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.far = 1000
	camera.position = Vector3(0, 0, 12)
	camera.make_current()
	var sphere := SphereMesh.new()
	sphere.radius = 2
	sphere.height = 4
	sphere.radial_segments = 96
	sphere.rings = 64
	var source := ArrayMesh.new()
	source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sphere.get_mesh_arrays())
	var baked := Lod.object_mesh(source)
	check(baked.levels > 0, "fixture has native mesh LODs")
	var visual := MeshInstance3D.new()
	visual.mesh = baked.mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.CORAL
	visual.material_override = material
	stage.add_child(visual)
	var original_surfaces: Array = visual.mesh.get("_surfaces").duplicate(true)
	var overlay := Overlay.new()
	root.add_child(overlay)
	overlay.set_geometry_view(1)
	check(root.debug_draw == Viewport.DEBUG_DRAW_LIGHTING, "native material replacement")
	check(visual.material_override == material, "source material identity preserved")
	overlay.set_geometry_view(2)
	check(root.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME, "native wireframe")
	overlay.set_geometry_view(0)
	check(root.debug_draw == Viewport.DEBUG_DRAW_UNSHADED, "original rendering restored")
	overlay.set_geometry_lod_enabled(true)
	observations.near_auto = await primitives()
	camera.position.z = 240
	observations.far_auto = await primitives()
	overlay.set_geometry_lod_enabled(false)
	observations.far_full = await primitives()
	check(observations.near_auto > observations.far_auto, "camera distance actually selects fewer primitives")
	check(observations.far_full > observations.far_auto, "zero threshold actually disables native LOD")
	overlay.set_geometry_lod_enabled(true)
	check(is_equal_approx(root.mesh_lod_threshold, 0.75), "exact initial LOD threshold restored")
	check(visual.mesh.get("_surfaces") == original_surfaces and visual.material_override == material, "mesh surfaces and materials unchanged")
	overlay.set_geometry_view(1)
	overlay.set_geometry_lod_enabled(false)
	root.remove_child(overlay)
	overlay.free()
	check(root.debug_draw == Viewport.DEBUG_DRAW_UNSHADED and is_equal_approx(root.mesh_lod_threshold, 0.75), "removing overlay restores viewport state")
	print("GEOMETRY_VIEW_RESULT ", JSON.stringify({"observations": observations, "failures": failures}))
	if failures.is_empty() and "main" in OS.get_cmdline_user_args():
		stage.queue_free()
		await process_frame
		await capture_main()
	quit(0 if failures.is_empty() else 1)

func capture_main() -> void:
	var output := "user://ember-tests/geometry-view-%d" % OS.get_process_id()
	var reference_root := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("output="):
			output = argument.trim_prefix("output=")
		if argument.begins_with("reference="):
			reference_root = argument.trim_prefix("reference=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var isolated := preload("res://tools/fixtures/ember_exploration_test_fixture.gd").prepare(self, "user://ember-tests/geometry-main-%d" % OS.get_process_id())
	check(isolated.error == OK, "main capture storage isolated")
	var paths := ["res://scenes/landscape_compact.tscn", "res://content/world_terrains/landscape_compact.res"]
	var hashes: Array[String] = []
	for path in paths:
		hashes.append(FileAccess.get_sha256(path))
	root.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	root.mesh_lod_threshold = 1.0
	root.size = Vector2i(2560, 1440)
	root.scaling_3d_scale = 1.0
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene: Node = load(paths[0]).instantiate()
	scene.sandbox_storage_root = "user://ember-tests/geometry-main-%d" % OS.get_process_id()
	root.add_child(scene)
	current_scene = scene
	var deadline := Time.get_ticks_msec() + 240000
	while not scene._startup_complete and Time.get_ticks_msec() < deadline:
		await process_frame
	check(scene._startup_complete, "authored main reaches gameplay")
	if not scene._startup_complete:
		return
	var rig: EmberFollowCamera = scene._player.camera_rig
	var overlay: Label = scene.get_node("CanvasLayer/LightingBenchmark")
	var rows: Array = []
	var lod_only := "lod-only" in OS.get_cmdline_user_args()
	var shadow_only := "shadow-only" in OS.get_cmdline_user_args()
	var depth_only := "depth-only" in OS.get_cmdline_user_args()
	var far_only := "far-only" in OS.get_cmdline_user_args()
	var depth_props: Array[EmberVoxelProp] = []
	var depth_materials: Dictionary = {}
	var shader_pairs: Dictionary = {}
	for node in scene.find_children("*", "GeometryInstance3D", true, false):
		var material: Material = node.material_override
		if material is ShaderMaterial and material.get_meta("ember_detailed_depth", false):
			depth_materials[material] = material.get_shader_parameter("material_depth_enabled")
			if node.get_parent() is EmberVoxelProp:
				depth_props.append(node.get_parent())
			if not reference_root.is_empty():
				var original: Shader = material.shader
				var reference := Shader.new()
				reference.code = expand_shader(original.code, reference_root)
				shader_pairs[material] = [original, reference]
	var shadow_lights: Array[Light3D] = []
	for node in scene.find_children("*", "Light3D", true, false):
		if node.shadow_enabled:
			shadow_lights.append(node)
	for wide in [false, true]:
		rig.fov = 70.0 if wide else 40.0
		rig.follow_distance = 600.0 if wide else 120.0
		for frame in 300:
			await process_frame
		var modes := [0, 0, 0] if lod_only or shadow_only or depth_only or far_only or not reference_root.is_empty() else [0, 1, 2, 0]
		for phase in modes.size():
			var mode: int = modes[phase]
			if far_only:
				for prop in depth_props:
					prop.set_process(phase == 1)
					var material: ShaderMaterial = prop.get_node("Mesh").material_override
					material.shader = material.shader.get_meta("ember_depth_full_shader", material.shader)
			for light in shadow_lights:
				light.shadow_enabled = not shadow_only or phase != 1
			for material: ShaderMaterial in depth_materials:
				material.set_shader_parameter("material_depth_enabled", false if depth_only and phase == 1 else depth_materials[material])
			for material: ShaderMaterial in shader_pairs:
				material.shader = shader_pairs[material][0 if phase == 1 else 1]
			overlay.set_geometry_lod_enabled(not lod_only or phase != 1)
			overlay.set_geometry_view(mode)
			overlay.visible = true
			for frame in 60:
				await process_frame
			var gpu: Array[float] = []
			var wall: Array[float] = []
			var before := Time.get_ticks_usec()
			for frame in 120:
				await process_frame
				var now := Time.get_ticks_usec()
				wall.append(float(now - before) / 1000.0)
				before = now
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			gpu.sort()
			wall.sort()
			await RenderingServer.frame_post_draw
			var file := "wide" if wide else "near"
			file += "-%d-%d.png" % [mode, rows.size()]
			root.get_texture().get_image().save_png(output.path_join(file))
			var camera := root.get_camera_3d()
			var row := {"wide": wide, "mode": mode, "automatic_lod": root.mesh_lod_threshold > 0.0, "shadow_control": shadow_only, "shadows_enabled": not shadow_only or phase != 1, "gpu_median_ms": gpu[60], "wall_median_ms": wall[60], "wall_p95_ms": wall[113], "primitives": root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME), "shadow_primitives": root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME), "fov": camera.fov, "camera": var_to_str(camera.global_transform), "viewport": str(root.size), "scale": root.scaling_3d_scale, "screenshot": file}
			rows.append(row)
			row.depth_control = depth_only
			row.depth_enabled = not depth_only or phase != 1
			row.depth_materials = depth_materials.size()
			row.reference_control = not reference_root.is_empty()
			row.optimized_shader = phase == 1 and not reference_root.is_empty()
			row.far_control = far_only
			row.automatic_far_program = far_only and phase == 1
			row.far_material_count = 0
			for material: ShaderMaterial in depth_materials:
				if material.shader.has_meta("ember_depth_full_shader"):row.far_material_count += 1
			print("GEOMETRY_MAIN_SAMPLE ", JSON.stringify(row))
		if lod_only:
			var start := rows.size() - 3
			check(rows[start + 1].primitives > rows[start].primitives, "native LOD reduces actual main geometry wide=" + str(wide))
			check(rows[start + 2].primitives == rows[start].primitives, "main geometry restored exactly wide=" + str(wide))
	for i in paths.size():
		check(FileAccess.get_sha256(paths[i]) == hashes[i], "main source bytes unchanged " + paths[i])
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"scope": "authored main static diagnostics, not dense moving stress or gameplay FPS acceptance; debug modes change alpha and vertex effects", "rows": rows, "failures": failures}, "\t"))
	print("GEOMETRY_MAIN_DONE ", ProjectSettings.globalize_path(output))
	scene.queue_free()
	for frame in 6:
		await process_frame

func expand_shader(code: String, reference_root: String) -> String:
	var result := ""
	for line in code.split("\n"):
		if line.strip_edges().begins_with("#include "):
			var path := line.split('"')[1]
			var reference_path := reference_root.path_join(path.get_file())
			var actual_path := reference_path if FileAccess.file_exists(reference_path) else path
			result += expand_shader(FileAccess.get_file_as_string(actual_path), reference_root) + "\n"
		else:
			result += line + "\n"
	return result
