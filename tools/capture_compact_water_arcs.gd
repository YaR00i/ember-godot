extends SceneTree
## Forward+ comparison of the actual trial shader and contact motion owner.

const OUTPUT := "user://ember-tests/water-arcs"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := (load("res://scenes/compact_sky_reflection_study.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var study := scene.get_node("PlanarReflection")
	for frame in 500:
		await process_frame
		if study.get("_prepared") and frame > 30: break
	assert(study.get("_prepared"))
	var canvas := scene.get_node("CanvasLayer") as CanvasLayer
	canvas.hide()
	for player in scene.find_children("*", "EmberPlayer", true, false):
		(player as Node3D).hide()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.fov = 55.0
	camera.far = 2400.0
	camera.make_current()
	var water: ShaderMaterial = study.get("_material")
	water.set_shader_parameter("preview_time", 4.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if "--live-motion" in OS.get_cmdline_user_args():
		camera.global_position = Vector3(443, 100, 550)
		camera.look_at(Vector3(398, 16, 505))
		study.call("_toggle_reaction_preview")
		for frame in 40:
			await create_timer(0.1).timeout
			await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png("%s/live-%02d.png" % [OUTPUT, frame]) == OK)
		study.call("_toggle_reaction_preview")
		print("PASS live F6 motion preview")
		quit()
		return
	for view in ["contact", "bend"]:
		camera.global_position = Vector3(430, 88, 525) if view == "contact" else Vector3(475, 140, 715)
		camera.look_at(Vector3(390, 16, 485) if view == "contact" else Vector3(367, 16, 610))
		for crisp in [0.0, 1.0]:
			study.set("river_crest_sharpness", crisp)
			study.set("river_crest_whiteness", 1.0)
			study.call("_apply_parameters")
			await _capture("%s-sharp%d" % [view, int(crisp)])
	study.set("river_crest_whiteness", 0.15)
	study.set("river_crest_sharpness", 1.0)
	study.call("_apply_parameters")
	var prop := scene.get_node("Map/Props/WaterContactStone") as Node3D
	var contact := prop.get_node("WaterContact") as EmberWaterContact3D
	contact.set_process(false)
	var original := prop.position
	camera.global_position = Vector3(443, 100, 550)
	camera.look_at(Vector3(398, 16, 505))
	contact.sample_motion(0.1)
	contact.refresh_now()
	for frame in 36:
		prop.position = original + Vector3(-0.35, 0, 1.3) * float(frame)
		contact.sample_motion(0.10)
		contact.refresh_now()
		contact._advance_wake(0.10)
		study.call("_upload_surface_contacts")
		if frame in [12, 20, 28]:
			await _capture("motion-%02d" % frame)
		await process_frame
	assert(int(water.get_shader_parameter("reaction_count")) > 0)
	contact._advance_wake(3.0)
	study.call("_upload_surface_contacts")
	assert(int(water.get_shader_parameter("reaction_count")) == 0)
	await _capture("motion-stopped")
	prop.position = original
	# Render the real editor panel class at the sidebar's working width.
	var panel := preload("res://addons/ember_import/ember_world_look_panel.gd").new()
	var ui := CanvasLayer.new()
	root.add_child(ui)
	var backdrop := PanelContainer.new()
	backdrop.position = Vector2(1100, 12)
	backdrop.size = Vector2(326, 860)
	ui.add_child(backdrop)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	backdrop.add_child(scroll)
	scroll.add_child(panel)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.set_target(scene, scene.get_node("Map"), null)
	panel._tabs.current_tab = 1
	await _capture("water-panel")
	assert(panel.size.x <= 326.0, "water tab must fit the existing sidebar")
	print("PASS water arcs Forward+: soft/crisp, contacts, moving wake, expiry, sidebar width")
	scene.queue_free()
	ui.queue_free()
	camera.queue_free()
	await process_frame
	quit()


func _capture(name: String) -> void:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [OUTPUT, name]
	assert(root.get_texture().get_image().save_png(path) == OK)
	print("CAPTURE ", ProjectSettings.globalize_path(path))
