extends SceneTree
## Fixed native Forward+ views; leaves authored scenes and settings untouched.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := (load("res://scenes/compact_sky_reflection_study.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var study := scene.get_node("PlanarReflection")
	for frame in 600:
		await process_frame
		if study.get("_prepared") and frame > 30 and scene.get_node("Map").get("_visual_surface_projection").pending_tile_count() == 0: break
	assert(study.get("_prepared"))
	(scene.get_node("CanvasLayer") as CanvasLayer).hide()
	for player in scene.find_children("*", "EmberPlayer", true, false): (player as Node3D).hide()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.fov = 55
	camera.far = 2400
	camera.make_current()
	var material: ShaderMaterial = study.get("_material")
	material.set_shader_parameter("preview_time", 3.0)
	study.refresh_water_settings()
	var sun: DirectionalLight3D = scene.get_node("Map/Look/Sun")
	var direction := sun.global_basis.z
	direction = Vector3(-direction.x, absf(direction.y), -direction.z)
	var tag := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "current"
	var output := "user://ember-tests/water-sun/" + tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for view in [Vector3(380, 16, 550), Vector3(380, 16, 415), Vector3(380, 16, 335), Vector3(380, 16, 285)]:
		camera.global_position = view + direction * 100.0
		camera.look_at(view)
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output + "/sun-%s.png" % int(view.z))
		var highlight_pixels := 0
		var image := root.get_texture().get_image()
		for y in range(image.get_height() / 4, image.get_height() * 3 / 4):
			for x in range(image.get_width() / 4, image.get_width() * 3 / 4):
				var colour := image.get_pixel(x, y)
				if minf(colour.r, minf(colour.g, colour.b)) > 0.98: highlight_pixels += 1
		print("SUN_CAPTURE z=", view.z, " white_pixels=", highlight_pixels)
		if tag != "baseline" and view.z <= 335 and highlight_pixels < 100:
			push_error("sun disappears in sea under the same reflection camera/light/settings")
			quit(1)
			return
	print("CAPTURE baseline: pinned camera/light/time" if tag == "baseline" else "PASS SUN capture: pinned camera/light/time, actual river, mouth, ocean")
	quit()
