extends SceneTree
## Native fully-faded color parity and conservative automatic shader switching.
var failures: Array[String] = []
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		printerr("SOLID_FAR_FAIL ", label)
func picture() -> Image:
	for frame in 16:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(640, 640)
	root.use_taa = false
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.3
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.far = 4000
	stage.add_child(camera)
	camera.make_current()
	var prop: EmberVoxelProp = load("res://prefabs/voxels/vox_painted_rock_group.tscn").instantiate()
	stage.add_child(prop)
	prop.set_world_look(0)
	prop.set_process(false)
	var visual: MeshInstance3D = prop.get_node("Mesh")
	var material: ShaderMaterial = visual.material_override
	var full := material.shader
	var mesh := visual.mesh
	var original_arrays: Array = mesh.surface_get_arrays(0).duplicate(true)
	var profiles: Variant = material.get_shader_parameter("stone_profiles")
	var bounds := visual.global_transform * visual.get_aabb()
	var fade := float(material.get_shader_parameter("material_depth_fade_far_m"))
	camera.position = bounds.get_center() + Vector3(0, fade, fade * 3.0 + bounds.size.length())
	camera.look_at(bounds.get_center())
	var before := await picture()
	prop._sync_solid_depth()
	check(material.shader != full and material.shader.get_meta("ember_depth_full_shader") == full, "far shader automatically selected after existing fade")
	check(not material.shader.get_shader_uniform_list().is_empty(), "far shader compiles")
	check(material.get_shader_parameter("stone_profiles") == profiles, "identical profile texture binding")
	check(is_equal_approx(float(material.get_shader_parameter("material_depth_fade_far_m")), fade), "depth uniforms survive shader switch")
	var after := await picture()
	var changed := 0
	var maximum := 0.0
	for y in before.get_height():
		for x in before.get_width():
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			var error := maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b)))
			maximum = maxf(maximum,error)
			if error > 2.0 / 255.0:changed += 1
	# Removing manual FRAGCOORD depth can move a few raster/shadow edge samples.
	# Bound those differences; an area-wide paint/finish mismatch must fail.
	check(changed <= 16, "fully faded pixels preserve color/finish apart from bounded edge samples")
	camera.position = bounds.end + Vector3.ONE
	prop._sync_solid_depth()
	check(material.shader == full, "near corner of a large object restores full program")
	camera.position = bounds.get_center() + Vector3(0, fade, fade * 4.0 + bounds.size.length())
	prop._sync_solid_depth()
	check(material.shader != full, "far return reuses cached program")
	prop.authoring_source = EmberVoxelModelResource.new()
	prop._sync_solid_depth()
	check(material.shader == full, "active source editing restores full program")
	prop.authoring_source = null
	material.set_shader_parameter("ember_anomaly_prepared",true)
	prop._sync_solid_depth()
	check(material.shader == full, "deforming anomaly keeps the full program")
	material.set_shader_parameter("ember_anomaly_prepared",false)
	check(visual.mesh == mesh and mesh.surface_get_arrays(0) == original_arrays, "mesh identity and streams unchanged")
	check(visual.material_override == material, "same instance-owned material")
	# Native dense opaque overlap: all fragments are beyond the unchanged fade.
	# This isolates the benefit of automatic depth testing on a rocky distant view.
	root.size = Vector2i(2560, 1440)
	camera.fov = 20
	camera.position = bounds.get_center() + Vector3(0, fade, fade * 3.0 + bounds.size.length())
	camera.look_at(bounds.get_center())
	sun.shadow_enabled = false
	var copies: Array[MeshInstance3D] = []
	for i in 64:
		var copy := MeshInstance3D.new()
		copy.mesh = mesh
		copy.material_override = material
		stage.add_child(copy)
		copy.global_transform = visual.global_transform
		copy.position += Vector3((i % 4 - 1.5) * bounds.size.x * 0.35, (i / 4 % 4 - 1.5) * bounds.size.y * 0.3, -float(i / 16) * bounds.size.z * 0.5)
		copies.append(copy)
	var far_shader: Shader = load("res://scripts/ember_voxel_solid_surface.gd").far_depth_shader(full)
	check(load("res://scripts/ember_voxel_solid_surface.gd").far_depth_shader(far_shader) == far_shader, "far shader requests are idempotent")
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var gpu_rows: Array = []
	for shader: Shader in ([] if "correctness-only" in OS.get_cmdline_user_args() else [full,far_shader,full]):
		material.shader = shader
		for frame in 60:
			await process_frame
		var values: Array[float] = []
		for frame in 240:
			await process_frame
			values.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		values.sort()
		gpu_rows.append({"far": shader == far_shader,"median_ms":values[120],"p95_ms":values[227],"primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
	print("SOLID_FAR_OVERLAP ",JSON.stringify({"viewport":str(root.size),"copies":copies.size(),"rows":gpu_rows}))
	for copy in copies:copy.queue_free()
	root.size=Vector2i(640,640)
	var plain: ShaderMaterial = material.duplicate()
	plain.shader=load("res://scripts/ember_voxel_solid_surface.gd").solid_depth_shader()
	visual.material_override=plain
	prop._sync_solid_depth()
	check(plain.shader.has_meta("ember_depth_full_shader"), "nonlayered solid also selects its far program")
	check(not plain.shader.get_shader_uniform_list().is_empty(), "nonlayered far program compiles")
	await picture()
	print("SOLID_FAR_RESULT ", JSON.stringify({"failures": failures,"pixel_changed_over_2_levels":changed,"maximum_channel_error":maximum,"fade":fade}))
	quit(0 if failures.is_empty() else 1)
