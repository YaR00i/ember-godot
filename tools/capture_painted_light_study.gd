extends SceneTree
var scene
var output: String
var errors: Array[String] = []
var measurements: Array = []

func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
	await RenderingServer.frame_post_draw
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL ", message)
func check_tuft_roots() -> void:
	for i in scene.tuft_points.size():
		var p: Vector2 = scene.tuft_points[i]
		var floor: Dictionary = scene.get_node("Map").surface_floor_sample(Vector3(p.x,8,p.y))
		var position: Vector3 = scene.tuft_visual.multimesh.get_instance_transform(i).origin
		check(position.distance_to(floor.position-Vector3.UP*0.005)<0.001, "native tuft roots follow floor")
func check_tuft_clearance() -> void:
	# Inspect actual rendered vertices, independently of the scatter predicate.
	var vertices: PackedVector3Array = scene.tuft_visual.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var unique: Dictionary = {}
	for vertex in vertices: unique[vertex]=true
	var min_clearance := INF
	var stone_vertices := 0
	for i in scene.tuft_points.size():
		var transform: Transform3D = scene.tuft_visual.multimesh.get_instance_transform(i)
		for vertex: Vector3 in unique:
			var p: Vector3 = transform * vertex
			var floor: Dictionary = scene.get_node("Map").surface_floor_sample(Vector3(p.x,8,p.z))
			check(floor.get("solid",false),"blade has ground below")
			min_clearance=minf(min_clearance,p.y-floor.position.y)
			if floor.get("material_role","")=="stone": stone_vertices+=1
	check(min_clearance>=-0.012,"blade vertices do not sink through ground beyond 12mm root allowance")
	check(stone_vertices==0,"no rendered blade vertices over stone Source")
	check(Array(scene.tuft_fit).min()>0.0,"no clump disappears at morph endpoints or intermediate probes")
	print("TUFT_CLEARANCE min_m=",min_clearance," stone_vertices=",stone_vertices," min_width=",Array(scene.tuft_fit).min()," update_ms=",scene.tuft_update_ms)
func capture(label: String) -> Image:
	await frames(5)
	var image := root.get_texture().get_image()
	check(image.save_png(output.path_join(label + ".png")) == OK, "capture " + label)
	return image
func timing(label: String) -> void:
	await frames(20)
	var samples: Array[float] = []
	for i in 60:
		await process_frame
		samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	samples.sort()
	measurements.append({"label": label, "gpu_median_ms": samples[30], "gpu_p95_ms": samples[57], "vram_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)})

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	var scene_path: String = OS.get_cmdline_user_args()[1] if OS.get_cmdline_user_args().size()>1 else "res://scenes/compact_painted_light_study.tscn"
	scene = load(scene_path).instantiate()
	root.add_child(scene); current_scene = scene
	var deadline := Time.get_ticks_msec() + 60000
	while not scene.ready_for_painted and Time.get_ticks_msec() < deadline: await process_frame
	check(scene.ready_for_painted, "ready")
	if not scene.ready_for_painted: quit(1); return
	scene.get_node("Instructions").hide()
	await frames(15)
	check_tuft_roots()
	check_tuft_clearance()
	var source: Resource = scene.get_node("Map").compact_terrain
	var saved: Resource = load(source.resource_path)
	var initial_floor: Dictionary = scene.get_node("Map").surface_floor_sample(scene.walker.position)
	var depth: Texture2D = scene.depth_material.get_shader_parameter("material_depth_height")
	# Baseline comparison concerns the existing terrain renderer. The new
	# decorative mesh and its deliberately new blade lighting are separate.
	scene.set_tufts(false)
	scene.calm_stone = false; scene.set_grass(false); scene.set_painted(false)
	var a := await capture("gameplay-a")
	var painted_shader: Shader = scene.depth_material.shader
	scene.depth_material.shader = scene.Materials.compact_terrain_depth_shader()
	var legacy := await capture("gameplay-existing-renderer")
	check(a.get_data() == legacy.get_data(), "disabled study matches existing renderer exactly")
	scene.depth_material.shader = painted_shader
	scene.set_painted(true)
	var b := await capture("gameplay-b-light-only")
	scene.calm_stone = true; scene.set_grass(true)
	await capture("gameplay-b-painted")
	scene.calm_stone = false; scene.set_painted(false); scene.set_grass(false)
	var a_return := await capture("gameplay-a-return")
	check(a.get_data() == a_return.get_data(), "A return exact")
	check(a.get_data() != b.get_data(), "light changes actual rendered frame")
	check(scene.depth_material.get_shader_parameter("material_depth_height") == depth, "height texture retained")
	check(is_equal_approx(scene.depth_material.get_shader_parameter("material_depth_amplitude_m"), 0.04), "4cm retained")
	check(scene.depth_material.get_shader_parameter("material_depth_steps") == 32, "32 steps retained")
	check(initial_floor.position.is_equal_approx(scene.get_node("Map").surface_floor_sample(scene.walker.position).position), "floor unaffected by look")
	scene.calm_stone = true; scene.set_grass(true); scene.set_painted(true)
	scene.set_tufts(true)
	# Same camera/source, compare low-band change and real shadow response.
	scene.set_sun_pose(1)
	var low_saved: float=scene.grass_low
	var fill_saved: float=scene.grass_shadow_fill
	scene.grass_low=0.52; scene.grass_shadow_fill=0.0; scene.apply_grass_settings()
	await capture("grass-previous-dark")
	scene.grass_low=low_saved; scene.apply_grass_settings()
	await capture("grass-lighter-no-shadow-tint")
	scene.grass_shadow_fill=fill_saved; scene.apply_grass_settings()
	for preset in 3:
		scene.set_lighting_preset(preset)
		for pose in [0,1]:
			scene.set_sun_pose(pose)
			var tinted:=await capture("preset-%d-sun-%d" % [preset,pose])
			scene.grass_shadow_fill=0.0; scene.apply_grass_settings()
			var plain:=await capture("preset-%d-sun-%d-shadow-off" % [preset,pose])
			check(tinted.get_data()!=plain.get_data(),"real-shadow tint visible in each preset")
			scene.grass_shadow_fill=fill_saved; scene.apply_grass_settings()
	# With shadows disabled the shadow-only addition must disappear exactly.
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	sun.shadow_enabled=false
	var no_shadow:=await capture("no-shadow-fill-on")
	scene.grass_shadow_fill=0.0; scene.apply_grass_settings()
	check(no_shadow.get_data()==(await capture("no-shadow-fill-off")).get_data(),"shadow tint absent outside actual shadows")
	sun.shadow_enabled=true; sun.light_energy=0.0
	scene.grass_shadow_fill=fill_saved; scene.apply_grass_settings()
	var no_light:=await capture("no-light-fill-on")
	scene.grass_shadow_fill=0.0; scene.apply_grass_settings()
	check(no_light.get_data()==(await capture("no-light-fill-off")).get_data(),"shadow fill does not emit without light")
	scene.grass_shadow_fill=fill_saved; scene.apply_grass_settings(); scene.set_lighting_preset(0)
	for i in 3:
		scene.set_sun_pose(i)
		var lit_edge := await capture("gameplay-sun-%d" % i)
		scene.set_grass_color(false)
		var color_before := await capture("gameplay-sun-%d-color-before" % i)
		scene.set_grass_color(true)
		var color_after := await capture("gameplay-sun-%d-color-after" % i)
		check(color_before.get_data()!=color_after.get_data(),"pigment tint changes frame")
		check(lit_edge.get_data()==color_after.get_data(),"pigment toggle returns exactly")
		scene.set_grass_masses(false)
		var grass_before := await capture("gameplay-sun-%d-masses-before" % i)
		scene.set_grass_masses(true)
		var grass_after := await capture("gameplay-sun-%d-masses-after" % i)
		check(grass_before.get_data()!=grass_after.get_data(),"mass lighting changes frame")
		check(lit_edge.get_data()==grass_after.get_data(),"mass lighting toggle returns exactly")
		if i == 1:
			var env: Environment = scene.get_node("Map/Look/WorldEnvironment").environment
			env.ssao_enabled = false
			await capture("gameplay-sun-1-masses-no-ao")
			env.ssao_enabled = true
			scene.tuft_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			await capture("gameplay-sun-1-grass-cast-comparison")
			scene.tuft_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if i < 2:
			scene.set_tufts(false)
			var flat_grass := await capture("gameplay-sun-%d-tufts-off" % i)
			check(lit_edge.get_data() != flat_grass.get_data(), "tufts visible from game camera")
			scene.set_tufts(true)
		scene.depth_material.set_shader_parameter("painterly_rim_enabled", false)
		var no_edge := await capture("gameplay-sun-%d-rim-off" % i)
		if i < 2: check(lit_edge.get_data() != no_edge.get_data(), "back and lateral rim visible")
		scene.depth_material.set_shader_parameter("painterly_rim_enabled", true)
	scene.set_sun_pose(0)
	var rim_on := await capture("gameplay-rim-on")
	scene.depth_material.set_shader_parameter("painterly_rim_enabled", false)
	var rim_off := await capture("gameplay-rim-off")
	check(rim_on.get_data() != rim_off.get_data(), "rim visible from game camera")
	scene.depth_material.set_shader_parameter("painterly_rim_enabled", true)
	scene.depth_material.set_shader_parameter("painterly_grass_enabled", false)
	var grass_off := await capture("gameplay-grass-light-off")
	check(rim_on.get_data() != grass_off.get_data(), "grass patches affect game camera")
	scene.depth_material.set_shader_parameter("painterly_grass_enabled", true)
	scene.get_node("Camera3D").make_current()
	await capture("overview-b")
	for i in 3:
		scene.set_sun_pose(i)
		await capture("sun-%d" % i)
	scene.get_node("Map/Look/Sun").light_energy = 0.0
	var no_sun_rim := await capture("sun-off-rim-on")
	scene.depth_material.set_shader_parameter("painterly_rim_enabled", false)
	var no_sun_no_rim := await capture("sun-off-rim-off")
	check(no_sun_rim.get_data() == no_sun_no_rim.get_data(), "rim disappears without sun")
	scene.get_node("Map/Look/Sun").light_energy = 1.3
	scene.depth_material.set_shader_parameter("painterly_rim_enabled", true)
	scene.set_sun_pose(0)
	for phase in [0.25, 0.5, 0.75, 1.0, 0.0]:
		scene.set_phase(phase); await capture("morph-%d" % roundi(phase * 100))
		check_tuft_roots()
		check_tuft_clearance()
	scene.follow_camera._cam.make_current()
	# Deterministic real Player movement, same input/time for both lighting modes.
	var starts: Vector3 = scene.walker.position
	var endpoints: Array[Vector3] = []
	for enabled in [false, true]:
		scene.walker.position = starts; scene.walker.velocity = Vector3.ZERO
		scene.follow_camera.reset_follow_height(); scene.set_painted(enabled)
		await frames(6)
		scene.set_demo_walking(true)
		for step in 120:
			await physics_frame
			if step % 30 == 0: await capture("walk-%s-%03d" % ["b" if enabled else "a", step])
		scene.set_demo_walking(false)
		endpoints.append(scene.walker.position)
	check(source.same_terrain_data(saved), "Source unchanged")
	scene.walker.position = starts; scene.walker.velocity = Vector3.ZERO
	scene.follow_camera.reset_follow_height()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for enabled in [false, true]:
		scene.set_painted(enabled); await timing("B" if enabled else "A")
	var report := {"errors": errors, "measurements": measurements, "resolution": "1600x900", "fps_cap": 30, "source_unchanged": source.same_terrain_data(saved), "walk_endpoints": [str(endpoints[0]), str(endpoints[1])], "note": "Walk capture waits add frames; endpoints are observations, not deterministic equality evidence."}
	var file := FileAccess.open(output.path_join("native.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("PAINTED_NATIVE ", "PASS" if errors.is_empty() else errors)
	scene.queue_free(); await process_frame; await process_frame
	quit(0 if errors.is_empty() else 1)
