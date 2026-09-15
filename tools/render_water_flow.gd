extends "res://tools/render_water_pixel.gd"
## W03 comparison, same native Surface fixture and reflection sources.

func previous_material() -> ShaderMaterial:
	var previous := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string("res://art/water/checkpoint-w02/shaders/ember_voxel_surface_water.gdshader")
	previous.shader = shader
	previous.render_priority = 1
	var text := FileAccess.get_file_as_string("res://art/water/checkpoint-w02/materials/ember_voxel_surface_water.tres")
	for line in text.split("\n"):
		if line.begins_with("shader_parameter/"):
			var pair := line.split(" = ",true,1)
			previous.set_shader_parameter(pair[0].trim_prefix("shader_parameter/"),str_to_var(pair[1]))
	return previous

func select_water() -> void:
	if variant == "before": water = previous_material()
	elif variant == "no-network": water.set_shader_parameter("flow_network_strength",0.0)
	elif variant == "coarse": water.set_shader_parameter("reflection_pixel_size",0.125)
	elif variant != "flow": errors.append("unknown flow variant "+variant)
	water.set_shader_parameter("preview_time",3.25)
	for i in visual.mesh.get_surface_count():
		if visual.mesh.surface_get_name(i) == "water": visual.set_surface_override_material(i,water)

func capture(name_text: String) -> Image:
	output = "res://art/water/flow/qa/"+view_kind+"-"+variant+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	return await super.capture(name_text)
