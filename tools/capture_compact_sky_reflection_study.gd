extends SceneTree
## Fixed-camera Forward+ comparison for the separate clear-water study scene.

const STUDY_SCENE := "res://scenes/compact_sky_reflection_study.tscn"
const OUTPUT_DIR := "user://ember-tests/sky-reflection-study"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load(STUDY_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	var canvas := scene.get_node_or_null("CanvasLayer") as CanvasLayer
	var projection: EmberTerrainPilotProjection
	for frame in 720:
		await process_frame
		projection = _find_projection(scene)
		if projection != null and projection.pending_tile_count() == 0 and frame > 25:
			break
	if projection == null or projection.pending_tile_count() > 0:
		push_error("clear water study terrain did not finish")
		quit(1)
		return
	if canvas != null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
		await RenderingServer.frame_post_draw
		var controls_path := OUTPUT_DIR + "/river-foam-controls.png"
		if root.get_texture().get_image().save_png(controls_path) != OK:
			push_error("cannot save " + controls_path)
			quit(1)
			return
		canvas.hide()
	var water := projection.get("_water_material") as ShaderMaterial
	if water == null:
		push_error("clear water study material is missing")
		quit(1)
		return
	var sliders := scene.get_node("CanvasLayer/ReflectionControls").find_children("*", "HSlider", true, false)
	var study_control := scene.get_node("PlanarReflection")
	var river_button := scene.get_node("CanvasLayer/ReflectionControls").find_child("RiverViewButton", true, false) as Button
	if river_button == null or river_button.text != "К морю":
		push_error("river view shortcut is missing")
		quit(1)
		return
	if sliders.size() != 19:
		push_error("reflection controls are missing")
		quit(1)
		return
	var scene_slider := sliders[0] as HSlider
	var chosen_mix := scene_slider.value
	scene_slider.value = 0.5
	if not is_equal_approx(float(water.get_shader_parameter("planar_reflection_mix")), 0.5):
		push_error("scene reflection slider did not update the shader")
		quit(1)
		return
	var mirror_view := scene.get_node("PlanarReflection/PlanarReflectionViewport") as SubViewport
	if mirror_view.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		push_error("scene reflection camera did not start")
		quit(1)
		return
	scene_slider.value = chosen_mix
	if mirror_view.render_target_update_mode != SubViewport.UPDATE_DISABLED:
		push_error("scene reflection camera kept rendering while disabled")
		quit(1)
		return
	var resolution_slider := sliders[1] as HSlider
	resolution_slider.value = 1.0
	if mirror_view.size != Vector2i(1920, 1080):
		push_error("reflection resolution slider did not resize the mirror camera")
		quit(1)
		return
	resolution_slider.value = 0.5
	var distortion_slider := sliders[2] as HSlider
	distortion_slider.value = 0.5
	if not is_equal_approx(float(water.get_shader_parameter("planar_reflection_distortion")), 0.01):
		push_error("reflection ripple slider did not update the shader")
		quit(1)
		return
	distortion_slider.value = 0.1
	var sharpness_slider := sliders[3] as HSlider
	var chosen_sharpness := sharpness_slider.value
	sharpness_slider.value = 0.5
	if not is_equal_approx(float(water.get_shader_parameter("sky_reflection_roughness")), 0.5):
		push_error("sky sharpness slider did not update the shader")
		quit(1)
		return
	sharpness_slider.value = chosen_sharpness
	var sky_slider := sliders[4] as HSlider
	var chosen_sky := sky_slider.value
	sky_slider.value = 0.5
	if not is_equal_approx(float(water.get_shader_parameter("sky_reflection_strength")), 0.5):
		push_error("sky strength slider did not update the shader")
		quit(1)
		return
	sky_slider.value = chosen_sky
	var height_slider := sliders[5] as HSlider
	var chosen_height := height_slider.value
	height_slider.value = 0.5
	if not is_equal_approx(float(water.get_shader_parameter("wave_height_voxels")), 2.0):
		push_error("wave height slider did not update the shader")
		quit(1)
		return
	height_slider.value = chosen_height
	var river_speed_slider := sliders[6] as HSlider
	river_speed_slider.value = 0.5
	if not is_equal_approx(float(water.get_shader_parameter("river_flow_speed")), 1.5):
		push_error("river speed slider did not update the shader")
		quit(1)
		return
	river_speed_slider.value = 1.1 / 3.0
	var river_wave_slider := sliders[7] as HSlider
	river_wave_slider.value = 0.4
	if not is_equal_approx(float(water.get_shader_parameter("river_wave_mix")), 0.4):
		push_error("river wave slider did not update the shader")
		quit(1)
		return
	river_wave_slider.value = 0.8
	var foam_slider := sliders[8] as HSlider
	var chosen_foam := foam_slider.value
	foam_slider.value = 0.25
	if not is_equal_approx(float(water.get_shader_parameter("shore_foam_strength")), 0.25):
		push_error("shore foam slider did not update the shader")
		quit(1)
		return
	foam_slider.value = chosen_foam
	var width_slider := sliders[9] as HSlider
	var chosen_width := width_slider.value
	width_slider.value = 0.5
	if not is_equal_approx(float(water.get_shader_parameter("shore_foam_width_voxels")), 3.2):
		push_error("foam width slider did not update the shader")
		quit(1)
		return
	width_slider.value = chosen_width
	var foam_sharpness_slider := sliders[10] as HSlider
	var chosen_foam_sharpness := foam_sharpness_slider.value
	foam_sharpness_slider.value = 0.4
	if not is_equal_approx(float(water.get_shader_parameter("shore_foam_sharpness")), 0.4):
		push_error("foam sharpness slider did not update the shader")
		quit(1)
		return
	foam_sharpness_slider.value = chosen_foam_sharpness
	var motion_slider := sliders[11] as HSlider
	var chosen_motion := motion_slider.value
	motion_slider.value = 0.5
	if not is_equal_approx(float(water.get_shader_parameter("shore_foam_motion_voxels")), 2.0):
		push_error("foam motion slider did not update the shader")
		quit(1)
		return
	motion_slider.value = chosen_motion
	var crest_slider := sliders[12] as HSlider
	var chosen_crest := crest_slider.value
	crest_slider.value = 0.3
	if not is_equal_approx(float(water.get_shader_parameter("river_crest_whiteness")), 0.3):
		push_error("river crest slider did not update the shader")
		quit(1)
		return
	crest_slider.value = chosen_crest
	var object_slider := sliders[13] as HSlider
	var chosen_object := object_slider.value
	object_slider.value = 0.4
	if not is_equal_approx(float(water.get_shader_parameter("object_foam_strength")), 0.4):
		push_error("object foam slider did not update the shader")
		quit(1)
		return
	object_slider.value = chosen_object
	var bob_slider := sliders[14] as HSlider
	var chosen_bob := bob_slider.value
	bob_slider.value = 0.8
	if not is_equal_approx(float(water.get_shader_parameter("local_bob_strength")), 0.4):
		push_error("local bob slider did not update the shader")
		quit(1)
		return
	bob_slider.value = chosen_bob
	var refraction_slider := sliders[15] as HSlider
	var chosen_refraction := refraction_slider.value
	refraction_slider.value = 0.5
	if not is_equal_approx(float(water.get_shader_parameter("refraction_strength")), 0.02):
		push_error("refraction slider did not update the shader")
		quit(1)
		return
	refraction_slider.value = chosen_refraction
	var haze_slider := sliders[16] as HSlider
	var chosen_haze := haze_slider.value
	haze_slider.value = 0.8
	if not is_equal_approx(float(study_control.get("underwater_haze")), 0.8):
		push_error("underwater haze slider did not update the study")
		quit(1)
		return
	haze_slider.value = chosen_haze
	var caustic_slider := sliders[17] as HSlider
	var shaft_slider := sliders[18] as HSlider
	caustic_slider.value = 0.8
	shaft_slider.value = 0.7
	var ground := projection.get("_ground_material") as ShaderMaterial
	var volume := scene.get_node_or_null("Map/UnderwaterLightStudy") as FogVolume
	if ground == null or volume == null:
		push_error("underwater light study materials are missing")
		quit(1)
		return
	if not is_equal_approx(float((volume.material as ShaderMaterial).get_shader_parameter("ray_strength")), 0.7):
		push_error("underwater light shaft slider did not update the fog")
		quit(1)
		return
	caustic_slider.value = 0.80
	shaft_slider.value = 0.42
	print("PASS water controls: reflections, wave height, local bob, refraction")
	var follow: EmberFollowCamera
	for frame in 360:
		await process_frame
		follow = scene.get_tree().get_first_node_in_group("ember_follow_camera") as EmberFollowCamera
		if follow != null and follow.target != null and follow.target.name == "WaterViewTarget":
			break
	if follow == null or follow.pitch_lock or follow.target == null or follow.target.name != "WaterViewTarget":
		push_error("F6 water camera is not orbiting the water")
		quit(1)
		return
	var river_target := follow.target.global_position
	river_button.pressed.emit()
	if river_button.text != "К реке" or follow.target.global_position == river_target:
		push_error("river view did not switch to the sea")
		quit(1)
		return
	river_button.pressed.emit()
	if river_button.text != "К морю" or follow.target.global_position != river_target:
		push_error("river view did not return to the river")
		quit(1)
		return
	var initial_distance := follow.follow_distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	study_control.call("_unhandled_input", wheel)
	if follow.follow_distance >= initial_distance:
		push_error("F6 water camera did not zoom")
		quit(1)
		return
	follow.follow_distance = initial_distance
	var initial_yaw := follow.yaw
	var initial_polar := follow.polar_angle
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(press)
	await process_frame
	var orbit_motion := InputEventMouseMotion.new()
	orbit_motion.relative = Vector2(24.0, 18.0)
	orbit_motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(orbit_motion)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	Input.parse_input_event(release)
	if is_equal_approx(follow.yaw, initial_yaw) or is_equal_approx(follow.polar_angle, initial_polar):
		push_error("F6 water camera did not rotate in yaw and pitch")
		quit(1)
		return
	follow.yaw = initial_yaw
	follow.polar_angle = initial_polar
	print("PASS water view camera: RMB yaw/pitch and wheel zoom")
	study_control.call("_set_underwater_view", true)
	for frame in 12:
		await process_frame
	var underwater_environment := (scene.get_node("Map/Look/WorldEnvironment") as WorldEnvironment).environment
	if not underwater_environment.fog_enabled:
		push_error("underwater camera did not enter the water body")
		quit(1)
		return
	if not underwater_environment.volumetric_fog_enabled or not volume.visible:
		push_error("underwater light volume did not enable")
		quit(1)
		return
	if not is_equal_approx(float(ground.get_shader_parameter("underwater_caustics")), 0.80):
		push_error("underwater floor caustics did not enable")
		quit(1)
		return
	ground.set_shader_parameter("preview_time", 0.0)
	(volume.material as ShaderMaterial).set_shader_parameter("preview_time", 0.0)
	var underwater_path := OUTPUT_DIR + "/underwater-volume.png"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR)) != OK:
		push_error("cannot create underwater capture directory")
		quit(1)
		return
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(underwater_path) != OK:
		push_error("cannot save " + underwater_path)
		quit(1)
		return
	print("PASS underwater water view capture: ", ProjectSettings.globalize_path(underwater_path))
	shaft_slider.value = 0.0
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var component_path := OUTPUT_DIR + "/underwater-floor-light-only.png"
	if root.get_texture().get_image().save_png(component_path) != OK:
		push_error("cannot save " + component_path)
		quit(1)
		return
	caustic_slider.value = 1.0
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	component_path = OUTPUT_DIR + "/underwater-floor-light-full.png"
	if root.get_texture().get_image().save_png(component_path) != OK:
		push_error("cannot save " + component_path)
		quit(1)
		return
	ground.set_shader_parameter("preview_time", 4.0)
	(volume.material as ShaderMaterial).set_shader_parameter("preview_time", 4.0)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	component_path = OUTPUT_DIR + "/underwater-floor-light-full-t4.png"
	if root.get_texture().get_image().save_png(component_path) != OK:
		push_error("cannot save " + component_path)
		quit(1)
		return
	ground.set_shader_parameter("preview_time", 0.0)
	(volume.material as ShaderMaterial).set_shader_parameter("preview_time", 0.0)
	caustic_slider.value = 0.0
	shaft_slider.value = 0.42
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	component_path = OUTPUT_DIR + "/underwater-shafts-only.png"
	if root.get_texture().get_image().save_png(component_path) != OK:
		push_error("cannot save " + component_path)
		quit(1)
		return
	caustic_slider.value = 0.80
	follow.polar_angle = 2.20
	var upward_yaw := follow.yaw
	for angle in [0.0, 1.57, 3.14, 4.71]:
		follow.yaw = angle
		water.set_shader_parameter("preview_time", 0.0)
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var angle_path := "%s/underwater-upward-yaw-%d.png" % [OUTPUT_DIR, roundi(angle * 100.0)]
		if root.get_texture().get_image().save_png(angle_path) != OK:
			push_error("cannot save " + angle_path)
			quit(1)
			return
	follow.yaw = upward_yaw
	for moment in [0.0, 4.0]:
		water.set_shader_parameter("preview_time", moment)
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		var upward_path := "%s/underwater-upward-t%d.png" % [OUTPUT_DIR, int(moment)]
		if root.get_texture().get_image().save_png(upward_path) != OK:
			push_error("cannot save " + upward_path)
			quit(1)
			return
	shaft_slider.value = 0.0
	water.set_shader_parameter("preview_time", 0.0)
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var upward_clear_path := OUTPUT_DIR + "/underwater-upward-no-shafts.png"
	if root.get_texture().get_image().save_png(upward_clear_path) != OK:
		push_error("cannot save " + upward_clear_path)
		quit(1)
		return
	shaft_slider.value = 0.42
	water.set_shader_parameter("preview_time", -1.0)
	follow.polar_angle = 1.05
	caustic_slider.value = 0.0
	shaft_slider.value = 0.0
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var no_light_path := OUTPUT_DIR + "/underwater-no-light.png"
	if root.get_texture().get_image().save_png(no_light_path) != OK:
		push_error("cannot save " + no_light_path)
		quit(1)
		return
	caustic_slider.value = 0.80
	shaft_slider.value = 0.42
	study_control.call("_set_underwater_view", false)
	for frame in 12:
		await process_frame
	if underwater_environment.fog_enabled:
		push_error("underwater blue remained after surfacing")
		quit(1)
		return
	var water_vertices := 0
	var water_alpha_range := Vector2(1.0, 0.0)
	for mesh_instance in projection.find_children("Water", "MeshInstance3D", true, false):
		var mesh := (mesh_instance as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0:
			water_vertices += mesh.surface_get_array_len(0)
			var colors := mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
			for color in colors:
				water_alpha_range.x = minf(water_alpha_range.x, color.a)
				water_alpha_range.y = maxf(water_alpha_range.y, color.a)
	print("CLEAR_WATER water vertices: ", water_vertices, ", tile build ms: ", projection.all_tiles_ms)
	print("CLEAR_WATER vertex depth alpha: ", water_alpha_range)
	var depth_counts := [0, 0, 0, 0]
	var deep_counts := [0, 0, 0, 0]
	var min_depth := 1000000
	var max_depth := 0
	var wet_with_ground := 0
	var wet_top_materials := {}
	var water_level_counts := {}
	var wet_height_counts := {}
	for index in projection.document.water_levels.size():
		var depth: int = projection.document.water_levels[index] - projection.document.heights[index]
		if depth <= 0 or projection.document.water_materials[index] == 0:
			continue
		depth_counts[mini(depth, 4) - 1] += 1
		var level: int = projection.document.water_levels[index]
		water_level_counts[level] = int(water_level_counts.get(level, 0)) + 1
		var height: int = projection.document.heights[index]
		wet_height_counts[height] = int(wet_height_counts.get(height, 0)) + 1
		min_depth = mini(min_depth, depth)
		max_depth = maxi(max_depth, depth)
		deep_counts[0 if depth <= 8 else 1 if depth <= 16 else 2 if depth <= 32 else 3] += 1
		if projection.document.top_materials[index] > 0:
			wet_with_ground += 1
			var top: int = projection.document.top_materials[index]
			wet_top_materials[top] = int(wet_top_materials.get(top, 0)) + 1
	print("CLEAR_WATER wet depth 1/2/3/4+: ", depth_counts, ", wet ground: ", wet_with_ground)
	print("CLEAR_WATER wet depth min/max: ", min_depth, "/", max_depth,
		", depth <=8/<=16/<=32/>32: ", deep_counts)
	print("CLEAR_WATER wet top materials: ", wet_top_materials)
	print("CLEAR_WATER dimensions/origin/limit: ", projection.document.width, "x", projection.document.depth,
		" / ", projection.document.origin_y, " / ", projection.document.height_limit)
	print("CLEAR_WATER water levels: ", water_level_counts, ", wet floor heights: ", wet_height_counts)
	print("CLEAR_WATER palette slot 3: ", projection.document.palette[3],
		", role: ", projection.document.palette_surface_roles[3])
	var directory := ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("cannot create clear water study output directory")
		quit(1)
		return
	water.set_shader_parameter("preview_time", 0.0)
	if canvas != null:
		canvas.show()
	for frame in 16:
		await process_frame
	await RenderingServer.frame_post_draw
	var f6_path := OUTPUT_DIR + "/f6-water-camera.png"
	if root.get_texture().get_image().save_png(f6_path) != OK:
		push_error("cannot save " + f6_path)
		quit(1)
		return
	print("PASS F6 water view capture: ", ProjectSettings.globalize_path(f6_path))
	if canvas != null:
		canvas.hide()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 2400.0
	for view in ["high", "low", "shore", "opposite"]:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE if view == "shore" or view == "opposite" else Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 460.0 if view == "high" else 370.0
		camera.fov = 55.0
		camera.global_position = Vector3(720.0, 92.0, -170.0) if view == "shore" else Vector3(420.0, 95.0, 610.0) if view == "opposite" else Vector3(970.0, 660.0 if view == "high" else 260.0, -470.0)
		camera.look_at(Vector3(370.0, 18.0, 220.0) if view == "opposite" else Vector3(360.0, 18.0, 350.0) if view == "shore" else Vector3(350.0, 18.0, 350.0))
		camera.make_current()
		for moment in [0.0, 4.0]:
			water.set_shader_parameter("preview_time", moment)
			for frame in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/%s-t%d.png" % [OUTPUT_DIR, view, int(moment)]
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("cannot save " + path)
				quit(1)
				return
			print("PASS clear water study capture: ", ProjectSettings.globalize_path(path))
	# Compare how much of the straight-looking bands actually belongs to the
	# authored staircase seabed, with all reflection contributions disabled.
	scene_slider.value = 0.0
	sky_slider.value = 0.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 460.0
	camera.global_position = Vector3(970.0, 660.0, -470.0)
	camera.look_at(Vector3(350.0, 18.0, 350.0))
	camera.make_current()
	water.set_shader_parameter("preview_time", 0.0)
	for frame in 16:
		await process_frame
	await RenderingServer.frame_post_draw
	var clear_path := OUTPUT_DIR + "/high-clear-t0.png"
	if root.get_texture().get_image().save_png(clear_path) != OK:
		push_error("cannot save " + clear_path)
		quit(1)
		return
	water.set_shader_parameter("preview_time", 4.0)
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	clear_path = OUTPUT_DIR + "/high-clear-t4.png"
	if root.get_texture().get_image().save_png(clear_path) != OK:
		push_error("cannot save " + clear_path)
		quit(1)
		return
	scene_slider.value = chosen_mix
	sky_slider.value = chosen_sky
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 55.0
	camera.global_position = Vector3(720.0, 92.0, -170.0)
	camera.look_at(Vector3(360.0, 18.0, 350.0))
	camera.make_current()
	for frame in 12:
		await process_frame
	scene_slider.value = 0.25
	for frame in 8:
		await process_frame
	var reflection_view := scene.get_node("PlanarReflection/PlanarReflectionViewport") as SubViewport
	var reflected_camera := reflection_view.get_node("MirroredCamera") as Camera3D
	var probe_point := Vector3(384.0, 16.02, 384.0)
	var probe_projection := water.get_shader_parameter("reflection_view_projection") as Projection
	var probe_clip := probe_projection * Vector4(
		probe_point.x, probe_point.y, probe_point.z, 1.0)
	var probe_matrix_uv := Vector2(probe_clip.x / probe_clip.w * 0.5 + 0.5,
		0.5 - probe_clip.y / probe_clip.w * 0.5)
	var probe_camera_uv := reflected_camera.unproject_position(probe_point) / Vector2(reflection_view.size)
	if probe_matrix_uv.distance_to(probe_camera_uv) > 0.001:
		push_error("reflection shader projection does not match the camera")
		quit(1)
		return
	if camera.cull_mask & (1 << 19) != 0 or reflected_camera.cull_mask & (1 << 19) == 0:
		push_error("reflection pass camera layer was not isolated")
		quit(1)
		return
	var mirror_path := OUTPUT_DIR + "/mirror-camera-t4.png"
	var mirror_image := reflection_view.get_texture().get_image()
	if mirror_image.get_pixel(0, 0).a > 0.01 or mirror_image.get_pixel(500, 350).a < 0.99:
		push_error("scene reflection camera did not separate objects from the sky")
		quit(1)
		return
	if mirror_image.save_png(mirror_path) != OK:
		push_error("cannot save " + mirror_path)
		quit(1)
		return
	print("PASS planar reflection camera: ", ProjectSettings.globalize_path(mirror_path))
	scene_slider.value = 0.75
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var scene_path := OUTPUT_DIR + "/shore-scene-reflection-on-t4.png"
	if root.get_texture().get_image().save_png(scene_path) != OK:
		push_error("cannot save " + scene_path)
		quit(1)
		return
	scene_slider.value = 0.0
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	scene_path = OUTPUT_DIR + "/shore-scene-reflection-off-t4.png"
	if root.get_texture().get_image().save_png(scene_path) != OK:
		push_error("cannot save " + scene_path)
		quit(1)
		return
	print("PASS scene reflection on/off captures")
	camera.global_position = Vector3(420.0, 95.0, 610.0)
	camera.look_at(Vector3(370.0, 18.0, 220.0))
	scene_slider.value = 0.5
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	scene_path = OUTPUT_DIR + "/opposite-scene-reflection-on-t4.png"
	if root.get_texture().get_image().save_png(scene_path) != OK:
		push_error("cannot save " + scene_path)
		quit(1)
		return
	scene_slider.value = 0.0
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	scene_path = OUTPUT_DIR + "/opposite-scene-reflection-off-t4.png"
	if root.get_texture().get_image().save_png(scene_path) != OK:
		push_error("cannot save " + scene_path)
		quit(1)
		return
	scene_slider.value = chosen_mix
	camera.global_position = Vector3(720.0, 92.0, -170.0)
	camera.look_at(Vector3(360.0, 18.0, 350.0))
	var player := scene.find_children("*", "EmberPlayer", true, false)
	if player.size() != 1:
		push_error("shore reflection fixture character is missing")
		quit(1)
		return
	var character := player[0] as CharacterBody3D
	character.global_position = Vector3(707.0, 16.0, 357.0)
	character.velocity = Vector3.ZERO
	camera.global_position = Vector3(707.0, 65.0, 500.0)
	camera.look_at(Vector3(707.0, 24.0, 200.0))
	camera.make_current()
	scene_slider.value = 0.0
	refraction_slider.value = 0.88
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var character_path := OUTPUT_DIR + "/near-character-refraction-on.png"
	var floor_viewport := study_control.get("_floor_viewport") as SubViewport
	if floor_viewport == null:
		push_error("terrain-only refraction camera is missing")
		quit(1)
		return
	var floor_camera := floor_viewport.get_node("UnderwaterFloorCamera") as Camera3D
	var floor_image := floor_viewport.get_texture().get_image()
	if (floor_camera.cull_mask != 1 << 18 or floor_image.get_pixel(0, 0).a > 0.01
			or floor_image.get_pixel(300, 400).a < 0.99):
		push_error("terrain-only refraction camera captured sky or lost the seabed")
		quit(1)
		return
	if floor_image.save_png(OUTPUT_DIR + "/near-character-floor-only.png") != OK:
		push_error("cannot save terrain-only refraction source")
		quit(1)
		return
	var character_refraction_on := root.get_texture().get_image()
	if character_refraction_on.save_png(character_path) != OK:
		push_error("cannot save " + character_path)
		quit(1)
		return
	refraction_slider.value = 0.0
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	character_path = OUTPUT_DIR + "/near-character-refraction-off.png"
	var character_refraction_off := root.get_texture().get_image()
	if character_refraction_off.save_png(character_path) != OK:
		push_error("cannot save " + character_path)
		quit(1)
		return
	var ghost_on := character_refraction_on.get_pixel(705, 372)
	var ghost_off := character_refraction_off.get_pixel(705, 372)
	if ghost_on.g < ghost_off.g - 0.05:
		push_error("shore refraction pulled the dry character into the water")
		quit(1)
		return
	refraction_slider.value = chosen_refraction
	refraction_slider.value = 0.0
	scene_slider.value = 0.75
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	character_path = OUTPUT_DIR + "/near-character-mirror-on.png"
	var character_mirror_on := root.get_texture().get_image()
	if character_mirror_on.save_png(character_path) != OK:
		push_error("cannot save " + character_path)
		quit(1)
		return
	scene_slider.value = 0.0
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	character_path = OUTPUT_DIR + "/near-character-mirror-off.png"
	var character_mirror_off := root.get_texture().get_image()
	if character_mirror_off.save_png(character_path) != OK:
		push_error("cannot save " + character_path)
		quit(1)
		return
	var wrong_reflection_on := character_mirror_on.get_pixel(640, 350)
	var wrong_reflection_off := character_mirror_off.get_pixel(640, 350)
	if (absf(wrong_reflection_on.r - wrong_reflection_off.r)
			+ absf(wrong_reflection_on.g - wrong_reflection_off.g)
			+ absf(wrong_reflection_on.b - wrong_reflection_off.b)) > 0.03:
		push_error("dry shore character reflected into water behind the character")
		quit(1)
		return
	refraction_slider.value = chosen_refraction
	# View the same shoreline from the water, with the leader partly immersed.
	# The old landward capture above guards against dry silhouettes being copied
	# into water; this view shows whether the actual submerged body survives.
	for follower in scene.find_children("PartyFollower_*", "Node3D", true, false):
		(follower as Node3D).hide()
	character.global_position = Vector3(707.0, 6.0, 300.0)
	character.velocity = Vector3.ZERO
	camera.global_position = Vector3(707.0, 43.0, 220.0)
	camera.look_at(Vector3(707.0, 17.0, 310.0))
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	character_path = OUTPUT_DIR + "/water-side-submerged-character.png"
	var submerged_image := root.get_texture().get_image()
	if submerged_image.save_png(character_path) != OK:
		push_error("cannot save " + character_path)
		quit(1)
		return
	character.hide()
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var empty_water_image := root.get_texture().get_image()
	if empty_water_image.save_png(OUTPUT_DIR + "/water-side-character-hidden.png") != OK:
		push_error("cannot save submerged-character comparison")
		quit(1)
		return
	character.show()
	var submerged_pixel := submerged_image.get_pixel(640, 405)
	var empty_pixel := empty_water_image.get_pixel(640, 405)
	if absf(submerged_pixel.r - empty_pixel.r) + absf(submerged_pixel.g - empty_pixel.g) < 0.12:
		push_error("submerged character disappeared behind the water surface")
		quit(1)
		return
	print("PASS submerged character visible through water")
	# Water-edge diagnostics: high sky response exposes displaced tile joins.
	sharpness_slider.value = 1.0
	sky_slider.value = 1.0
	camera.global_position = Vector3(580.0, 43.0, 260.0)
	camera.look_at(Vector3(470.0, 16.0, 90.0))
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var edge_path := OUTPUT_DIR + "/diagnostic-wave-high-sky.png"
	if root.get_texture().get_image().save_png(edge_path) != OK:
		push_error("cannot save " + edge_path)
		quit(1)
		return
	var study_sun := scene.get_node("Map/Look/Sun") as DirectionalLight3D
	var chosen_sun_energy := study_sun.light_energy
	study_sun.light_energy = 0.0
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	edge_path = OUTPUT_DIR + "/diagnostic-wave-no-sun.png"
	if root.get_texture().get_image().save_png(edge_path) != OK:
		push_error("cannot save " + edge_path)
		quit(1)
		return
	study_sun.light_energy = chosen_sun_energy
	sky_slider.value = 0.0
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	edge_path = OUTPUT_DIR + "/diagnostic-wave-no-sky.png"
	if root.get_texture().get_image().save_png(edge_path) != OK:
		push_error("cannot save " + edge_path)
		quit(1)
		return
	sky_slider.value = 1.0
	height_slider.value = 0.0
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	edge_path = OUTPUT_DIR + "/diagnostic-wave-flat.png"
	if root.get_texture().get_image().save_png(edge_path) != OK:
		push_error("cannot save " + edge_path)
		quit(1)
		return
	height_slider.value = chosen_height
	camera.global_position = Vector3(675.0, 95.0, 445.0)
	camera.look_at(Vector3(707.0, 15.0, 355.0))
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	edge_path = OUTPUT_DIR + "/diagnostic-shore-sides.png"
	if root.get_texture().get_image().save_png(edge_path) != OK:
		push_error("cannot save " + edge_path)
		quit(1)
		return
	edge_path = OUTPUT_DIR + "/diagnostic-shore-floor-only.png"
	if floor_viewport.get_texture().get_image().save_png(edge_path) != OK:
		push_error("cannot save " + edge_path)
		quit(1)
		return
	sky_slider.value = 0.0
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	edge_path = OUTPUT_DIR + "/diagnostic-shore-no-sky.png"
	if root.get_texture().get_image().save_png(edge_path) != OK:
		push_error("cannot save " + edge_path)
		quit(1)
		return
	refraction_slider.value = 0.0
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	edge_path = OUTPUT_DIR + "/diagnostic-shore-no-refraction.png"
	if root.get_texture().get_image().save_png(edge_path) != OK:
		push_error("cannot save " + edge_path)
		quit(1)
		return
	refraction_slider.value = chosen_refraction
	sky_slider.value = 1.0
	var side_fill_value: Variant = ground.get_shader_parameter("terrain_side_fill")
	var chosen_side_fill := 1.2 if side_fill_value == null else float(side_fill_value)
	ground.set_shader_parameter("terrain_side_fill", 0.0)
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	edge_path = OUTPUT_DIR + "/diagnostic-shore-no-side-fill.png"
	if root.get_texture().get_image().save_png(edge_path) != OK:
		push_error("cannot save " + edge_path)
		quit(1)
		return
	ground.set_shader_parameter("terrain_side_fill", chosen_side_fill)
	sharpness_slider.value = chosen_sharpness
	sky_slider.value = chosen_sky
	camera.global_position = Vector3(720.0, 92.0, -170.0)
	camera.look_at(Vector3(360.0, 18.0, 350.0))
	if canvas != null:
		canvas.show()
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var controls_path := OUTPUT_DIR + "/shore-controls.png"
		if root.get_texture().get_image().save_png(controls_path) != OK:
			push_error("cannot save " + controls_path)
			quit(1)
			return
		print("PASS live reflection controls: ", ProjectSettings.globalize_path(controls_path))
		canvas.hide()
	# A deliberately different sky is a diagnostic. The camera, mesh, floor,
	# water palette and wave time stay fixed: changed water pixels must come
	# from Godot's sky radiance, not a hand-painted glint.
	var environment := scene.get_node("Map/Look/WorldEnvironment") as WorldEnvironment
	var sky_material := environment.environment.sky.sky_material as ProceduralSkyMaterial
	sky_slider.value = 0.5
	sky_material.sky_top_color = Color(0.90, 0.15, 0.12)
	sky_material.sky_horizon_color = Color(1.0, 0.38, 0.22)
	sky_material.ground_horizon_color = Color(0.88, 0.25, 0.15)
	water.set_shader_parameter("preview_time", 0.0)
	for frame in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var sky_probe_path := OUTPUT_DIR + "/shore-red-sky-t0.png"
	if root.get_texture().get_image().save_png(sky_probe_path) != OK:
		push_error("cannot save " + sky_probe_path)
		quit(1)
		return
	print("PASS sky radiance diagnostic capture: ", ProjectSettings.globalize_path(sky_probe_path))
	water.set_shader_parameter("sky_reflection_strength", 0.0)
	for frame in 16:
		await process_frame
	await RenderingServer.frame_post_draw
	var no_reflection_path := OUTPUT_DIR + "/shore-red-sky-no-reflection-t0.png"
	if root.get_texture().get_image().save_png(no_reflection_path) != OK:
		push_error("cannot save " + no_reflection_path)
		quit(1)
		return
	sky_material.sky_top_color = Color(0.21, 0.52, 0.82)
	sky_material.sky_horizon_color = Color(0.64, 0.84, 0.96)
	sky_material.ground_horizon_color = Color(0.7, 0.85, 0.96)
	for frame in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	no_reflection_path = OUTPUT_DIR + "/shore-blue-sky-no-reflection-t0.png"
	if root.get_texture().get_image().save_png(no_reflection_path) != OK:
		push_error("cannot save " + no_reflection_path)
		quit(1)
		return
	print("PASS sky reflection off comparison")
	quit()


func _find_projection(node: Node) -> EmberTerrainPilotProjection:
	if node is EmberTerrainPilotProjection:
		return node as EmberTerrainPilotProjection
	for child in node.get_children():
		var found := _find_projection(child)
		if found != null:
			return found
	return null
