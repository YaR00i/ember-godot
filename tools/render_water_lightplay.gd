extends "res://tools/render_water_flow.gd"
## W04 native art comparison: W03, sharp sun pixels, shadow response, bottom light-play.

func select_water() -> void:
	water.set_shader_parameter("preview_time",3.25)
	water.set_shader_parameter("pixel_highlight_mix",0.0 if variant == "current" else 1.0)
	water.set_shader_parameter("pixel_highlight_cohesion",1.0 if variant == "patches" else 0.0)
	water.set_shader_parameter("pixel_highlight_smooth_motion",1.0 if variant in ["wobble","standing"] else 0.0)
	water.set_shader_parameter("pixel_highlight_edge_wobble",0.10 if variant == "wobble" else (0.08 if variant == "standing" else 0.0))
	water.set_shader_parameter("stylized_shadow_mix",1.0 if variant in ["shadow","caustics"] else 0.0)
	if variant != "current":
		water.set_shader_parameter("pixel_highlight_cell_size",0.25)
		water.set_shader_parameter("pixel_highlight_threshold",0.968)
		water.set_shader_parameter("pixel_highlight_core",0.996)
		water.set_shader_parameter("pixel_highlight_strength",0.72)
		water.set_shader_parameter("pixel_highlight_color",Color("d8ffff"))
		water.set_shader_parameter("flow_network_strength",0.34)
		water.set_shader_parameter("flow_network_deep_ratio",0.22)
		water.set_shader_parameter("stylized_shadow_pixel_size",0.1875)
		water.set_shader_parameter("stylized_shadow_steps",2.0)
	if variant == "patches":
		water.set_shader_parameter("pixel_highlight_flow_direction",Vector2(0.82,0.57))
		water.set_shader_parameter("pixel_highlight_flow_speed",0.24)
		water.set_shader_parameter("pixel_highlight_shape_scale",0.74)
		water.set_shader_parameter("pixel_highlight_shape_threshold",0.62)
	if variant == "standing":
		water.set_shader_parameter("pixel_highlight_threshold",0.991)
		water.set_shader_parameter("pixel_highlight_core",0.998)
		water.set_shader_parameter("pixel_highlight_strength",1.10)
		water.set_shader_parameter("pixel_highlight_view_dependence",0.15)
		water.set_shader_parameter("pixel_highlight_travel_speed",0.02)
		water.set_shader_parameter("pixel_highlight_wobble_speed",1.15)
	if variant == "caustics":
		water.set_shader_parameter("flow_network_strength",0.18)
		water.set_shader_parameter("underwater_light_mix",0.20)
		water.set_shader_parameter("underwater_caustic_strength",0.90)
		water.set_shader_parameter("underwater_refraction_strength",0.004)
		water.set_shader_parameter("underwater_depth_range",0.55)
	if variant not in ["current","sharp","wobble","standing","patches","shadow","caustics"]:
		errors.append("unknown light-play variant "+variant)
	for i in visual.mesh.get_surface_count():
		if visual.mesh.surface_get_name(i) == "water": visual.set_surface_override_material(i,water)


func build() -> void:
	super.build()
	environment.ambient_light_energy = 0.18
	sun.light_energy = 0.9
	# Voxel presentation: remove the stochastic PCF grain before the water
	# shader groups the resulting hard shadow into its larger receiving cells.
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	sun.light_angular_distance = 0.0
	# Lift the disposable pier enough for the accepted sun direction to project
	# the boards and posts beyond the deck instead of hiding the footprint below it.
	for child in scene.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh:
			var mesh_size := (child.mesh as BoxMesh).size
			if abs(child.position.y-1.37) < 0.01 and abs(child.position.z-3.0) < 0.01 and abs(mesh_size.y-0.16) < 0.01:
				child.position.y = 1.57
			elif abs(child.position.y-0.95) < 0.01 and child.position.x >= 1.9 and child.position.x <= 3.7:
				(child.mesh as BoxMesh).size.y = 1.10
				child.position.y = 1.02


func capture(name_text: String) -> Image:
	var review := "review7-" if variant == "standing" else ("review6-" if variant == "wobble" else ("review5-" if variant == "patches" else "review2-"))
	output = "res://art/water/lightplay/qa/"+review+view_kind+"-"+variant+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await frames()
	var image := root.get_texture().get_image()
	if image.save_png(output+name_text+".png") != OK: errors.append("capture "+name_text)
	return image


func run() -> void:
	root.size = Vector2i(1280,900)
	build()
	select_water()
	if view_kind == "close":
		camera.size = 6.4
		camera.position = Vector3(8.6,5.6,9.6)
		camera.look_at(Vector3(4.3,1,4.0))
	elif view_kind == "game":
		camera.size = 10.5
	else:
		errors.append("unknown light-play view "+view_kind)
	await capture("water")
	if animate:
		for frame in 48:
			var seconds := 3.25+float(frame)/12.0
			water.set_shader_parameter("preview_time",seconds)
			await frames(2)
			if root.get_texture().get_image().save_png(output+"motion-%03d.png"%frame) != OK:
				errors.append("motion frame save failed")
	scene.queue_free()
	await frames(10)
	for error in errors: push_error(error)
	print("PASS WATER_LIGHTPLAY_CAPTURE variant=",variant," view=",view_kind," native_motion=",animate if errors.is_empty() else "FAIL")
	quit(0 if errors.is_empty() else 1)
