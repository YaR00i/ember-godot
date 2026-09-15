extends "res://tools/render_diorama.gd"
## Native disposable visual comparison. Sky/probe/light options never save a scene.
var water_baseline := false
var water_probe := false
var water_setup := false
var water_authored := false
var water_saved_preset := false
var water_no_foam := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--water-baseline": water_baseline = true
		if arg == "--water-probe": water_probe = true
		if arg == "--water-authored": water_authored = true
		if arg == "--water-saved-preset": water_saved_preset = true
		if arg == "--water-no-foam": water_no_foam = true


func _apply_saved_water_preset(scene: Node3D) -> void:
	var path := "res://art/water/presets/water-lab-user-saved-review2-mix-2026-09-15.json"
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("Water QA saved preset is unreadable: " + path)
		return
	for visual in scene.find_children("*", "MeshInstance3D", true, false):
		if visual.mesh == null:
			continue
		for surface_index in visual.mesh.get_surface_count():
			var active := visual.get_active_material(surface_index) as ShaderMaterial
			if active == null or active.shader == null or "water_wave_state" not in active.shader.code:
				continue
			var replacement := active.duplicate() as ShaderMaterial
			for key in parsed:
				if replacement.get_shader_parameter(key) == null:
					continue
				var value = parsed[key]
				if value is String and (key.ends_with("_color") or key.ends_with("_tone") or key == "water_tint"):
					value = Color(value)
				replacement.set_shader_parameter(key, value)
			replacement.set_shader_parameter("preview_time", frozen_time)
			visual.set_surface_override_material(surface_index, replacement)

func capture(scene: Node3D, camera: Camera3D, tag: String, eye: Vector3, target: Vector3) -> void:
	if not water_setup:
		water_setup = true
		for environment_node in ([] if water_authored else scene.find_children("*", "WorldEnvironment", true, false)):
			var environment: Environment = environment_node.environment
			environment.background_mode = Environment.BG_SKY
			var sky := Sky.new()
			var sky_material := ProceduralSkyMaterial.new()
			sky_material.sky_top_color = Color("668fa9") if not night else Color("061020")
			sky_material.sky_horizon_color = Color("cbd6d0") if not night else Color("182838")
			sky_material.ground_bottom_color = Color("425953") if not night else Color("06101a")
			sky_material.ground_horizon_color = Color("8eaba2") if not night else Color("10202c")
			sky.sky_material = sky_material
			environment.sky = sky
		if not water_authored:
			for light in scene.find_children("*", "Light3D", true, false): light.light_specular = 1.0
		if water_probe:
			var probe := ReflectionProbe.new()
			probe.name = "DisposableWaterReflection"
			probe.position = Vector3(65,12,56) if mode == "corner" else Vector3(177,25,165)
			probe.size = Vector3(200,90,200) if mode == "corner" else Vector3(450,130,450)
			probe.box_projection = true
			probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
			probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
			scene.add_child(probe)
		if water_baseline:
			var before_material := ShaderMaterial.new()
			var before_shader := Shader.new()
			before_shader.code = FileAccess.get_file_as_string("res://art/water/checkpoint-pre-w01/shaders/ember_voxel_surface_water.gdshader").replace("TIME", str(frozen_time))
			before_material.shader = before_shader
			before_material.render_priority = 1
			# The production baseline is kept as an ignored backup; load exact values manually.
			var text := FileAccess.get_file_as_string("res://art/water/checkpoint-pre-w01/materials/ember_voxel_surface_water.tres")
			for line in text.split("\n"):
				if line.begins_with("shader_parameter/"):
					var pair := line.split(" = ",true,1)
					before_material.set_shader_parameter(pair[0].trim_prefix("shader_parameter/"),str_to_var(pair[1]))
			for visual in scene.find_children("*", "MeshInstance3D", true, false):
				if visual.mesh == null: continue
				for i in visual.mesh.get_surface_count():
					var active: Material = visual.get_active_material(i)
					if active is ShaderMaterial and active.shader != null and "connected_ripple_network" in active.shader.code:
						var replacement := before_material.duplicate() as ShaderMaterial
						if active.get_shader_parameter("background_water") == true:
							replacement = ShaderMaterial.new()
							replacement.shader = before_shader
							if mode == "pier":
								var authored_text := FileAccess.get_file_as_string("res://scenes/test_pier.tscn")
								var section := authored_text.split('[sub_resource type="ShaderMaterial" id="water"]')[1].split('[sub_resource')[0]
								for line in section.split("\n"):
									if line.begins_with("shader_parameter/"):
										var pair := line.split(" = ",true,1)
										replacement.set_shader_parameter(pair[0].trim_prefix("shader_parameter/"),str_to_var(pair[1]))
							else:
								replacement.set_shader_parameter("background_water",true)
								replacement.set_shader_parameter("coordinate_scale",active.get_shader_parameter("coordinate_scale"))
						replacement.set_shader_parameter("preview_time", frozen_time)
						visual.set_surface_override_material(i,replacement)
		if water_saved_preset:
			_apply_saved_water_preset(scene)
		if water_no_foam:
			for visual in scene.find_children("*", "MeshInstance3D", true, false):
				if visual.mesh == null:
					continue
				for surface_index in visual.mesh.get_surface_count():
					var active := visual.get_active_material(surface_index) as ShaderMaterial
					if active == null or active.get_shader_parameter("systemic_shore_strength") == null:
						continue
					var replacement := active.duplicate() as ShaderMaterial
					replacement.set_shader_parameter("systemic_shore_strength", 0.0)
					visual.set_surface_override_material(surface_index, replacement)
	camera.position = eye
	camera.look_at(target)
	for frame in 60: await process_frame
	await RenderingServer.frame_post_draw
	var output := "res://art/water/qa/%s-%s%s-%s.png" % [label,mode,"-night" if night else "",tag]
	print("WATER_CAPTURE ",output," result=",root.get_texture().get_image().save_png(output))
	var gpu: Array[float] = []
	for frame in 60:
		await process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	gpu.sort()
	print("WATER_GPU_PROXY label=",label," mode=",mode," ",tag," median_ms=",gpu[30]," QA_probe=",water_probe," authored=",water_authored)
