extends SceneTree
## Short Forward+ visual check of the river, its mouth, and changing waves.

const SCENE := "res://scenes/compact_sky_reflection_study.tscn"
const OUTPUT := "user://ember-tests/river-study"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load(SCENE) as PackedScene).instantiate()
	if OS.get_environment("EMBER_WATER_STEP") == "4":
		(scene.get_node("Map") as EmberMapLoader).compact_water_mesh_step = 4
	elif OS.get_environment("EMBER_WATER_STEP") == "8":
		(scene.get_node("Map") as EmberMapLoader).compact_water_mesh_step = 8
	root.add_child(scene)
	var canvas := scene.get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas != null:
		canvas.hide()
	var projection: EmberTerrainPilotProjection
	for frame in 720:
		await process_frame
		var map := scene.get_node("Map") as EmberMapLoader
		projection = map.get("_visual_surface_projection") as EmberTerrainPilotProjection
		if projection != null and projection.pending_tile_count() == 0 and frame > 25:
			break
	if projection == null or projection.pending_tile_count() > 0:
		push_error("river study terrain did not finish")
		quit(1)
		return
	var water := projection.get("_water_material") as ShaderMaterial
	if water == null or float(water.get_shader_parameter("river_flow_enabled")) < 0.5:
		push_error("river flow did not reach the study material")
		quit(1)
		return
	if float(water.get_shader_parameter("object_contact_available")) < 0.5:
		push_error("trial object footprint did not reach the moving water surface")
		quit(1)
		return
	var ground := projection.get("_ground_material") as ShaderMaterial
	if ground != null:
		ground.set_shader_parameter("preview_time", 4.0)
	for player in scene.find_children("*", "EmberPlayer", true, false):
		(player as Node3D).hide()
	var actor_contact := scene.get_node("Map/Props/WaterContactStone/WaterContact") as EmberWaterContact3D
	actor_contact.refresh_now()
	print("RIVER_STUDY contact visible: ", actor_contact.is_contact_visible())
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.fov = 55.0
	camera.far = 2400.0
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) != OK:
		push_error("cannot create river capture folder")
		quit(1)
		return
	if OS.get_environment("EMBER_RIVER_FOCUS") == "1":
		var controls := scene.get_node("PlanarReflection")
		controls.set("scene_reflection", 0.41)
		controls.set("reflection_distortion", 0.0138)
		controls.set("river_flow_speed", 1.47)
		controls.set("river_crest_whiteness", 0.98)
		controls.set("shore_foam_sharpness", 1.0)
		controls.set("shore_foam_motion_voxels", 1.76)
		controls.call("_apply_parameters")
		water.set_shader_parameter("preview_time", 4.0)
		for view in ["waterline", "under", "high", "bend", "along"]:
			match view:
				"waterline":
					camera.global_position = Vector3(399.0, 17.5, 477.0)
					camera.look_at(Vector3(399.0, 16.0, 530.0))
				"under":
					camera.global_position = Vector3(399.0, 15.5, 477.0)
					camera.look_at(Vector3(399.0, 16.0, 530.0))
				"high":
					camera.global_position = Vector3(430.0, 88.0, 525.0)
					camera.look_at(Vector3(390.0, 16.0, 485.0))
				"bend":
					camera.global_position = Vector3(475.0, 140.0, 715.0)
					camera.look_at(Vector3(367.0, 16.0, 610.0))
				"along":
					camera.global_position = Vector3(398.0, 16.8, 535.0)
					camera.look_at(Vector3(391.0, 16.0, 430.0))
			camera.make_current()
			for moment in ([0.0, 1.5, 3.0, 4.5] if view == "along" else [4.0]):
				water.set_shader_parameter("preview_time", moment)
				for frame in 10:
					await process_frame
				await RenderingServer.frame_post_draw
				var focus_path := "%s/focus-%s-t%d-step%d.png" % [OUTPUT, view, roundi(moment * 10.0), (scene.get_node("Map") as EmberMapLoader).compact_water_mesh_step]
				if root.get_texture().get_image().save_png(focus_path) != OK:
					push_error("cannot save " + focus_path)
					quit(1)
					return
				print("PASS river focus: ", ProjectSettings.globalize_path(focus_path))
			if view in ["high", "bend"]:
				for whiteness in [0.0, 1.0]:
					water.set_shader_parameter("river_crest_whiteness", whiteness)
					for frame in 8:
						await process_frame
					await RenderingServer.frame_post_draw
					var crest_path := "%s/focus-%s-crest%d.png" % [OUTPUT, view, int(whiteness)]
					if root.get_texture().get_image().save_png(crest_path) != OK:
						push_error("cannot save " + crest_path)
						quit(1)
						return
				water.set_shader_parameter("river_crest_whiteness", 0.98)
		quit()
		return
	for view in ["river-high", "river-low", "river-mouth", "river-waterline", "river-surface", "river-grazing", "river-inland", "river-contact", "river-contact-close"]:
		match view:
			"river-high":
				camera.global_position = Vector3(650.0, 420.0, 820.0)
				camera.look_at(Vector3(375.0, 16.0, 540.0))
			"river-low":
				camera.global_position = Vector3(500.0, 83.0, 680.0)
				camera.look_at(Vector3(370.0, 16.0, 480.0))
			"river-mouth":
				camera.global_position = Vector3(650.0, 180.0, 560.0)
				camera.look_at(Vector3(350.0, 16.0, 340.0))
			"river-waterline":
				camera.global_position = Vector3(410.0, 24.0, 650.0)
				camera.look_at(Vector3(380.0, 17.0, 515.0))
			"river-surface":
				camera.global_position = Vector3(390.0, 18.8, 650.0)
				camera.look_at(Vector3(380.0, 16.0, 510.0))
			"river-grazing":
				camera.global_position = Vector3(390.0, 16.5, 650.0)
				camera.look_at(Vector3(380.0, 16.0, 510.0))
			"river-inland":
				camera.global_position = Vector3(395.0, 19.0, 430.0)
				camera.look_at(Vector3(380.0, 16.0, 600.0))
			"river-contact":
				camera.global_position = Vector3(448.0, 55.0, 550.0)
				camera.look_at(Vector3(405.0, 16.0, 500.0))
			"river-contact-close":
				camera.global_position = Vector3(423.0, 34.0, 530.0)
				camera.look_at(Vector3(405.0, 16.0, 500.0))
		camera.make_current()
		if view == "river-high":
			water.set_shader_parameter("floor_camera_available", 0.0)
			water.set_shader_parameter("preview_time", 4.0)
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var editor_path := OUTPUT + "/river-high-editor-preview.png"
			if root.get_texture().get_image().save_png(editor_path) != OK:
				push_error("cannot save " + editor_path)
				quit(1)
				return
			water.set_shader_parameter("floor_camera_available", 1.0)
		# Keep the same camera and frozen wave time while isolating the two
		# reported controls. These frames are the visual regression comparison.
		water.set_shader_parameter("preview_time", 4.0)
		for setting in ["refraction-off", "refraction-default", "refraction-low", "refraction-mid", "waves-flat", "waves-high", "foam-off"]:
			var distortion := 0.0 if setting == "refraction-off" else (0.005 if setting == "refraction-low" else (0.015 if setting == "refraction-mid" else 0.035))
			water.set_shader_parameter("refraction_strength", distortion)
			water.set_shader_parameter("wave_height_voxels", 0.0 if setting == "waves-flat" else (4.0 if setting == "waves-high" else 3.2))
			water.set_shader_parameter("shore_foam_strength", 0.0 if setting == "foam-off" else 0.60)
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var comparison_path := "%s/%s-%s.png" % [OUTPUT, view, setting]
			if root.get_texture().get_image().save_png(comparison_path) != OK:
				push_error("cannot save " + comparison_path)
				quit(1)
				return
			print("PASS river comparison: ", ProjectSettings.globalize_path(comparison_path))
		water.set_shader_parameter("refraction_strength", 0.035)
		water.set_shader_parameter("wave_height_voxels", 3.2)
		water.set_shader_parameter("shore_foam_strength", 0.60)
		for moment in [0.0, 4.0]:
			water.set_shader_parameter("preview_time", moment)
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/%s-t%d.png" % [OUTPUT, view, int(moment)]
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("cannot save " + path)
				quit(1)
				return
			print("PASS river capture: ", ProjectSettings.globalize_path(path))
		if view == "river-contact-close":
			for setting in ["foam-narrow", "foam-wide", "foam-soft", "motion-still", "motion-strong", "crest-strong", "object-foam-off"]:
				water.set_shader_parameter("shore_foam_width_voxels", 0.7 if setting == "foam-narrow" else (4.0 if setting == "foam-wide" else 1.8))
				water.set_shader_parameter("shore_foam_sharpness", 0.0 if setting == "foam-soft" else 0.7)
				water.set_shader_parameter("shore_foam_motion_voxels", 0.0 if setting == "motion-still" else (3.5 if setting == "motion-strong" else 1.25))
				water.set_shader_parameter("river_crest_whiteness", 1.0 if setting == "crest-strong" else 0.10)
				water.set_shader_parameter("object_foam_strength", 0.0 if setting == "object-foam-off" else 0.50)
				for frame in 8:
					await process_frame
				await RenderingServer.frame_post_draw
				var setting_path := "%s/%s-%s.png" % [OUTPUT, view, setting]
				if root.get_texture().get_image().save_png(setting_path) != OK:
					push_error("cannot save " + setting_path)
					quit(1)
					return
			water.set_shader_parameter("shore_foam_width_voxels", 1.8)
			water.set_shader_parameter("shore_foam_sharpness", 0.7)
			water.set_shader_parameter("shore_foam_motion_voxels", 1.25)
			water.set_shader_parameter("river_crest_whiteness", 0.10)
			water.set_shader_parameter("object_foam_strength", 0.50)
		if view == "river-high":
			water.set_shader_parameter("river_wave_mix", 0.0)
			for frame in 8:
				await process_frame
			await RenderingServer.frame_post_draw
			var still_path := OUTPUT + "/river-high-no-flow-t4.png"
			if root.get_texture().get_image().save_png(still_path) != OK:
				push_error("cannot save " + still_path)
				quit(1)
				return
			water.set_shader_parameter("river_wave_mix", 0.8)
	print("RIVER_STUDY all tiles ms: ", projection.all_tiles_ms)
	quit()
