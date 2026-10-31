extends SceneTree
## Reproduces the false dark shell with -- --legacy; current transport must pass.

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var trial = load("res://scenes/wing_flight_trial.tscn").instantiate()
	trial.tuning_path = "user://ember-tests/edge-transport-%d.json" % OS.get_process_id()
	root.add_child(trial)
	await process_frame
	root.focus_exited.disconnect(trial._focus_lost)
	trial.start_run()
	trial.player.set_physics_process(false)
	trial.set_process(false)
	trial.set_physics_process(false)
	trial.get_node("Route").hide()
	trial.get_node("Obstacles").hide()
	for cloud in trial._clouds:
		cloud.visible = cloud == trial.get_node("Cloud")
	trial.get_node("WorldEnvironment").environment.sky.sky_material.set_shader_parameter("distant_clouds_enabled", false)
	trial.player.position = Vector3(430, 210, -650)
	trial.player.look_at(Vector3(0, 150, -1000))
	trial.camera.reset_follow_height()
	var material: ShaderMaterial = trial.get_node("Cloud").material
	material.set_shader_parameter("shadow_strength", 0.0)
	material.set_shader_parameter("rim_strength", 0.0)
	if "--legacy" in OS.get_cmdline_user_args():
		var shader := Shader.new()
		shader.code = FileAccess.get_file_as_string("res://shaders/ember_flight_cloud.gdshader").replace("+ threshold)", "+ 0.5)")
		material.shader = shader
	var images: Array[Image] = []
	for visible_cloud in [true, false]:
		trial.get_node("Cloud").visible = visible_cloud
		for frame in range(70):
			await process_frame
			trial._update_clouds(0.0)
		await RenderingServer.frame_post_draw
		images.append(root.get_texture().get_image())
	var loss := 0.0
	var dark_blocks := 0
	for y in range(280, 840, 8):
		for x in range(360, 1320, 8):
			if y > 560 and y < 650 and x > 580 and x < 1020:
				continue
			var difference := 0.0
			for dy in range(8):
				for dx in range(8):
					difference += images[1].get_pixel(x + dx, y + dy).r - images[0].get_pixel(x + dx, y + dy).r
			difference /= 64.0
			loss += maxf(difference, 0.0)
			if difference > 0.01:
				dark_blocks += 1
	var directory := "user://ember-tests/wing-flight"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	images[0].save_png(directory + ("/edge-legacy.png" if "--legacy" in OS.get_cmdline_user_args() else "/edge-corrected.png"))
	print("EDGE TRANSPORT dark blocks=", dark_blocks, " loss=", loss)
	var passed := dark_blocks < 8 and loss < 0.2
	print("PASS edge transport" if passed else "FAIL false dark edge")
	trial.queue_free()
	await process_frame
	quit(0 if passed else 1)
