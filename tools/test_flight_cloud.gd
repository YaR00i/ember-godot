extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var trial = load("res://scenes/wing_flight_trial.tscn").instantiate()
	trial.tuning_path = "user://ember-tests/cloud-fixture-%d.json" % OS.get_process_id()
	root.add_child(trial)
	await process_frame
	_settings_cases(trial)
	trial.start_run()
	trial.player.set_physics_process(false)
	trial._physics_process(0.5)
	trial._process(0.5)
	var material: ShaderMaterial = trial.get_node("Cloud").material
	_check(float(material.get_shader_parameter("cloud_time")) > 0.0, "cloud must evolve in flight")
	trial._show_menu("pause", "resume")
	var frozen: float = material.get_shader_parameter("cloud_time")
	trial._physics_process(1.0)
	trial._process(1.0)
	_check(is_equal_approx(frozen, material.get_shader_parameter("cloud_time")), "pause must freeze cloud")
	trial.start_run()
	_check(is_zero_approx(material.get_shader_parameter("cloud_time")), "R must reset cloud")
	trial.player.set_physics_process(false)
	trial.set_physics_process(false)
	trial.set_process(false)
	if "--capture" in OS.get_cmdline_user_args():
		root.focus_exited.disconnect(trial._focus_lost)
		var directory := "user://ember-tests/wing-flight"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		trial._show_menu("Облака — настройка в игре", "Продолжить")
		trial._tuning_tabs.current_tab = 2
		for frame in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory + "/cloud-menu.png")
		var scroll: ScrollContainer = trial._cloud_controls["density_scale"].get_parent().get_parent()
		scroll.scroll_vertical = 10000
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory + "/cloud-menu-edge.png")
		scroll.scroll_vertical = 0
		trial._menu.hide()
		trial._hud.show()
		for pose in [Vector3(750, 150, -300), Vector3(0, 10, -80), Vector3(0, 50, -1000), Vector3(0, 50, -1600)]:
			trial.player.global_position = pose
			trial.player.global_basis = Basis.IDENTITY
			if pose.x > 0:
				trial.player.look_at(trial.get_node("Cloud").global_position)
			trial.camera.reset_follow_height()
			for frame in range(25):
				await process_frame
				trial._update_clouds(0.0)
			await RenderingServer.frame_post_draw
			var filename := "cloud-%d.png" % absi(int(pose.z))
			root.get_texture().get_image().save_png(directory + "/" + filename)
		print("CLOUD CAPTURE: " + ProjectSettings.globalize_path(directory))
		# Same volume/view, scene sun on/off: verify visible light response on GPU.
		trial.get_node("Route").hide()
		trial.get_node("Obstacles").hide()
		trial.player.global_position = Vector3(650, 300, -450)
		trial.player.look_at(trial.get_node("Cloud").global_position)
		trial.camera.reset_follow_height()
		var lighting_images: Array[Image] = []
		var sun: DirectionalLight3D = trial.get_node("Sun")
		var original_energy := sun.light_energy
		for energy in [original_energy, 0.0]:
			sun.light_energy = energy
			trial._update_clouds(0.0)
			for frame in range(30):
				await process_frame
				trial._update_clouds(0.0)
			await RenderingServer.frame_post_draw
			var rendered := root.get_texture().get_image()
			lighting_images.append(rendered)
			rendered.save_png(directory + ("/cloud-sun.png" if energy > 0.0 else "/cloud-shadow.png"))
		var light_difference := 0.0
		var samples := 0
		for y in range(250, 550, 20):
			for x in range(600, 1000, 20):
				var a := lighting_images[0].get_pixel(x, y)
				var b := lighting_images[1].get_pixel(x, y)
				light_difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
				samples += 3
		_check(light_difference / samples > 0.01, "cloud image must respond to the actual scene sunlight")
		print("CLOUD SUN mean RGB difference: ", light_difference / samples)
		# Dense center of the isolated main cloud in this fixed daylight view.
		# Regresses the yellow cast and the opposite failure: clipping to white.
		var yellow_samples := 0
		var clipped_samples := 0
		var color_samples := 0
		for y in range(330, 510, 10):
			for x in range(700, 900, 10):
				var color := lighting_images[0].get_pixel(x, y)
				if color.r - color.b > 0.025 and color.g - color.b > 0.025:
					yellow_samples += 1
				if minf(color.r, minf(color.g, color.b)) > 0.98:
					clipped_samples += 1
				color_samples += 1
		_check(float(yellow_samples) / color_samples < 0.03, "daylight cloud must not acquire yellow/green transport tint")
		_check(float(clipped_samples) / color_samples < 0.25, "daylight cloud must retain shading without white clipping")
		print("CLOUD COLOR yellow fraction=", float(yellow_samples) / color_samples, "; clipped=", float(clipped_samples) / color_samples)
		sun.light_energy = original_energy
		trial._update_clouds(0.0)
		# Audit all cloud edges against a neutral background, excluding the colored
		# aircraft. Sky-blue transmitted through a thin edge is tested separately
		# in the ordinary captures, not mistaken for a shader tint here.
		var environment: Environment = trial.get_node("WorldEnvironment").environment
		var background := environment.background_mode
		var background_color := environment.background_color
		var ordinary_fog := environment.fog_enabled
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.2, 0.2, 0.2)
		environment.fog_enabled = false
		for frame in range(30):
			await process_frame
			trial._update_clouds(0.0)
		await RenderingServer.frame_post_draw
		var audit := root.get_texture().get_image()
		audit.save_png(directory + "/cloud-neutral-audit.png")
		var maximum_tint := 0.0
		var minimum_light := 1.0
		var maximum_light := 0.0
		for y in range(220, 550, 5):
			for x in range(300, 1400, 5):
				var color := audit.get_pixel(x, y)
				maximum_tint = maxf(maximum_tint, maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)))
				minimum_light = minf(minimum_light, color.r)
				maximum_light = maxf(maximum_light, color.r)
		_check(maximum_tint < 0.02 and maximum_light - minimum_light > 0.05, "neutral cloud must retain visible structure without colored fringes at any sampled edge")
		print("CLOUD EDGE maximum RGB spread: ", maximum_tint)
		environment.background_mode = background
		environment.background_color = background_color
		environment.fog_enabled = ordinary_fog
		await _rim_and_sky_cases(trial, directory)
		trial.get_node("Route").show()
		trial.get_node("Obstacles").show()
		if RenderingServer.has_method("viewport_get_measured_render_time_gpu"):
			var viewport := root.get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(viewport, true)
			trial.player.global_position = Vector3(0, 50, -1000)
			trial.camera.reset_follow_height()
			for enabled in [false, true]:
				trial.get_node("WorldEnvironment").environment.volumetric_fog_enabled = enabled
				for frame in range(20):
					await process_frame
				var total := 0.0
				for frame in range(20):
					await process_frame
					total += RenderingServer.viewport_get_measured_render_time_gpu(viewport)
				print("CLOUD GPU mean ms enabled=", enabled, ": ", total / 20.0)
	# Traverse the whole volume with the existing body and real collision surface.
	trial.start_run()
	trial.player.set_physics_process(false)
	trial.player.global_position = Vector3(0, 50, -550)
	trial.player.flight_motion.reset(Quaternion.IDENTITY, 500.0)
	var collided := false
	for frame in range(130):
		await physics_frame
		trial.player.flight_motion.step(1.0 / 60.0, Vector3.ZERO, 0.0, 0.0)
		trial.player.velocity = trial.player.flight_motion.velocity
		trial.player.move_and_slide()
		collided = collided or trial.player.get_slide_collision_count() > 0
	_check(trial.player.global_position.z < -1500.0 and not collided, "body must fly through cloud and exit without collision/reset")
	trial.queue_free()
	await process_frame
	print("PASS cloud lifecycle and traversal capture" if failures.is_empty() else "FAIL cloud")
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _settings_cases(trial: Node3D) -> void:
	var original_path: String = trial.cloud_settings_path
	var fixture := "user://ember-tests/cloud-config-%d.cfg" % OS.get_process_id()
	var config := ConfigFile.new()
	config.set_value("clouds", "height_offset_m", 250.0)
	config.set_value("clouds", "thickness_scale", 1.5)
	config.set_value("clouds", "near_cloud_count", 2)
	config.set_value("clouds", "density_scale", 0.6)
	config.set_value("colors", "highlight_color", Color(0.5, 0.5, 0.5))
	config.set_value("sky", "distant_clouds_enabled", false)
	config.set_value("edge", "edge_softness", 0.34)
	config.set_value("edge", "rim_strength", 0.7)
	config.set_value("edge", "rim_steps", 3)
	_check(config.save(fixture) == OK, "settings fixture save failed")
	trial.cloud_settings_path = fixture
	trial.start_run()
	var cloud: FogVolume = trial.get_node("Cloud")
	_check(is_equal_approx(cloud.position.y, 340.0) and is_equal_approx(cloud.size.y, 660.0), "R must apply configured cloud height/thickness")
	_check(trial.get_node("Cloud1").visible and not trial.get_node("Cloud2").visible, "cloud count must affect actual volumes")
	_check(cloud.material.get_shader_parameter("highlight_color") == Vector3(0.5, 0.5, 0.5), "cloud config color must reach actual shader")
	_check(is_equal_approx(cloud.material.get_shader_parameter("edge_softness"), 0.34) and is_equal_approx(cloud.material.get_shader_parameter("rim_strength"), 0.7) and is_equal_approx(cloud.material.get_shader_parameter("rim_steps"), 3.0), "edge/rim config must reach actual volume")
	_check(not trial.get_node("WorldEnvironment").environment.sky.sky_material.get_shader_parameter("distant_clouds_enabled"), "config must switch distant cloud layer")
	trial.start_run()
	_check(is_equal_approx(cloud.position.y, 340.0), "repeated R must not accumulate height offsets")
	config.set_value("clouds", "density_scale", 99999)
	config.set_value("clouds", "near_cloud_count", 0)
	config.save(fixture)
	_check(trial.reload_cloud_settings() and cloud.material.get_shader_parameter("density_scale") == 3.0 and not cloud.visible, "config must bound density and support zero clouds")
	var kept_height := cloud.position.y
	config.set_value("colors", "highlight_color", "invalid")
	config.set_value("clouds", "height_offset_m", 2000)
	config.save(fixture)
	_check(not trial.reload_cloud_settings() and is_equal_approx(cloud.position.y, kept_height), "invalid config must retain entire previous setup")
	config.set_value("colors", "highlight_color", Color.WHITE)
	config.save(fixture)
	trial.cloud_settings_path = original_path
	_check(trial.reload_cloud_settings() and cloud.visible and is_equal_approx(cloud.position.y, 90), "restoring natural config must restore authored cloud placement")
	var second = load("res://scenes/wing_flight_trial.tscn").instantiate()
	second.tuning_path = trial.tuning_path + "-second"
	second.cloud_settings_path = fixture
	root.add_child(second)
	_check(trial.get_node("WorldEnvironment").environment.sky.sky_material.get_shader_parameter("distant_clouds_enabled") and not second.get_node("WorldEnvironment").environment.sky.sky_material.get_shader_parameter("distant_clouds_enabled"), "cloud config must not leak into another scene instance")
	second.free()
	# Real controls and connected menu buttons, isolated from author files.
	trial.cloud_settings_path = fixture
	trial._tuning_tabs.current_tab = 2
	trial._cloud_controls["density_scale"].value = 0.85
	trial._cloud_controls["shadow_strength"].value = 0.0
	trial._cloud_controls["distant_clouds_enabled"].set_pressed(false)
	trial._cloud_controls["highlight_color"].color = Color(0.55, 0.55, 0.55)
	trial._cloud_controls["highlight_color"].color_changed.emit(Color(0.55, 0.55, 0.55))
	_check(is_equal_approx(cloud.material.get_shader_parameter("density_scale"), 0.85) and cloud.material.get_shader_parameter("shadow_strength") == 0.0, "menu sliders must change actual cloud immediately")
	trial.start_run()
	_check(is_equal_approx(cloud.material.get_shader_parameter("density_scale"), 0.85), "R must preserve unsaved menu changes")
	trial._tuning_tabs.current_tab = 2
	for button in trial.find_children("*", "Button", true, false):
		if button.text == "Сохранить":
			button.pressed.emit()
	var saved_config := ConfigFile.new()
	_check(saved_config.load(fixture) == OK and is_equal_approx(saved_config.get_value("clouds", "density_scale"), 0.85), "cloud tab Save button must write the cloud cfg")
	var saved_text := FileAccess.get_file_as_string(fixture)
	for button in trial.find_children("*", "Button", true, false):
		if button.text == "Сбросить":
			button.pressed.emit()
	_check(cloud.material.get_shader_parameter("density_scale") == 1.0 and FileAccess.get_file_as_string(fixture) == saved_text, "cloud Reset must restore session without overwriting cfg")
	for button in trial.find_children("*", "Button", true, false):
		if button.text == "Загрузить":
			button.pressed.emit()
	_check(is_equal_approx(trial._cloud_controls["density_scale"].value, 0.85) and cloud.material.get_shader_parameter("shadow_strength") == 0.0, "cloud Load must restore both controls and material")
	trial.cloud_settings_path = original_path
	trial.reload_cloud_settings()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))

func _rim_and_sky_cases(trial: Node3D, directory: String) -> void:
	var rim_images: Array[Image] = []
	for strength in [0.0, 1.2]:
		for cloud in trial._clouds:
			cloud.material.set_shader_parameter("rim_strength", strength)
			cloud.material.set_shader_parameter("rim_width", 0.65)
			cloud.material.set_shader_parameter("rim_steps", 3.0)
		trial._update_clouds(0.0)
		for cloud in trial._clouds:
			cloud.material.set_shader_parameter("transport_phase", 0.0)
		for frame in range(30):
			await process_frame
			trial._update_clouds(0.0)
			for cloud in trial._clouds:
				cloud.material.set_shader_parameter("transport_phase", 0.0)
		await RenderingServer.frame_post_draw
		var rendered := root.get_texture().get_image()
		rim_images.append(rendered)
		rendered.save_png(directory + ("/cloud-rim-off.png" if strength == 0.0 else "/cloud-rim-on.png"))
	var difference := 0.0
	for y in range(220, 550, 5):
		for x in range(300, 1400, 5):
			difference += absf(rim_images[0].get_pixel(x, y).r - rim_images[1].get_pixel(x, y).r)
	_check(difference > 15.0, "optional rim must visibly change actual cloud lighting")
	print("CLOUD RIM total red difference: ", difference)
	trial.reload_cloud_settings()
	for cloud in trial._clouds:
		cloud.hide()
	trial.camera.set_process(false)
	var cam: Camera3D = trial.camera._cam
	cam.global_position = Vector3(0, 1000, 0)
	cam.look_at(cam.global_position + trial.get_node("Sun").global_basis.z, Vector3.UP)
	var sky_material: ShaderMaterial = trial.get_node("WorldEnvironment").environment.sky.sky_material
	var sky_images: Array[Image] = []
	for enabled in [true, false]:
		sky_material.set_shader_parameter("distant_clouds_enabled", enabled)
		for frame in range(25):
			await process_frame
			trial._update_clouds(0.0)
		await RenderingServer.frame_post_draw
		var rendered := root.get_texture().get_image()
		sky_images.append(rendered)
		if enabled:
			rendered.save_png(directory + "/sky-sun.png")
	var overhead_difference := 0.0
	for y in range(120, 380, 10):
		for x in range(400, 1200, 10):
			overhead_difference = maxf(overhead_difference, absf(sky_images[0].get_pixel(x, y).r - sky_images[1].get_pixel(x, y).r))
	_check(overhead_difference < 0.005, "distant cloud banks must leave upper sky clear")
	var sun_pixel := sky_images[0].get_pixel(800, 450)
	var beside_sun := sky_images[0].get_pixel(650, 450)
	_check(sun_pixel.r > beside_sun.r + 0.08, "clear sky must visibly contain the scene sun")
	print("SKY OVERHEAD maximum difference: ", overhead_difference)
	trial.reload_cloud_settings()
	trial.camera.set_process(true)
	trial.camera.reset_follow_height()
