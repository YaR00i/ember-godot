extends SceneTree
## Actual Forward+ sun response across a current/ocean boundary, pinned time.

const OUTPUT := "user://ember-tests/water-sun"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.sky = Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sun_angle_max = 10.0
	environment.environment.sky.sky_material = sky_material
	environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 0, 0)
	sun.light_energy = 0.25
	sun.light_angular_distance = 2.9
	root.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 55.0
	root.add_child(camera)
	camera.position = Vector3(0, 40, -23.094)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var flow := Image.create(128, 128, false, Image.FORMAT_RGBAF)
	flow.fill(Color(0.5, 0.5, 0, 1))
	for y in 128:
		for x in 64: flow.set_pixel(x, y, Color(0.5, 1, 0, 1))
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	# Keep the real normal/roughness/specular and direct lighting. Remove only
	# transmitted floor/foam colour, which otherwise obscures the sun measurement.
	shader.code = FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader").replace(
		"EMISSION = mix(surface_color, vec3(0.70, 0.95, 1.0), foam);", "EMISSION = vec3(0.0);")
	material.shader = shader
	material.set_shader_parameter("ripple_cell_field", preload("res://scripts/prototypes/ember_compact_ripple_field.gd").texture())
	material.set_shader_parameter("ripple_field_available", 1.0)
	material.set_shader_parameter("water_flow_map", ImageTexture.create_from_image(flow))
	material.set_shader_parameter("terrain_origin_xz", Vector2(-32, -32))
	material.set_shader_parameter("flow_origin_xz", Vector2(-32, -32))
	material.set_shader_parameter("flow_map_extent_blocks", Vector2(4, 4))
	material.set_shader_parameter("river_flow_enabled", 1.0)
	material.set_shader_parameter("wave_height_voxels", 3.0)
	material.set_shader_parameter("sky_reflection_strength", 0.15)
	material.set_shader_parameter("sky_reflection_roughness", 0.0)
	material.set_shader_parameter("sky_normal_strength", 0.6)
	material.set_shader_parameter("water_glint_strength", 0.32)
	material.set_shader_parameter("preview_time", 3.0)
	var plane := MeshInstance3D.new()
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in [Vector3(-32, 0, -32), Vector3(-32, 0, 32), Vector3(32, 0, -32),
		Vector3(32, 0, -32), Vector3(-32, 0, 32), Vector3(32, 0, 32)]:
		builder.set_uv(Vector2.ZERO)
		builder.set_color(Color.WHITE)
		builder.set_normal(Vector3.UP)
		builder.add_vertex(point)
	plane.mesh = builder.commit()
	plane.material_override = material
	root.add_child(plane)
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	rendered.save_png(OUTPUT + "/sun-current-sea.png")
	var river := 0.0
	var sea := 0.0
	for y in range(rendered.get_height() / 4, rendered.get_height() * 3 / 4):
		for x in range(rendered.get_width() / 4, rendered.get_width() * 3 / 4):
			var colour := rendered.get_pixel(x, y)
			var highlight := 1.0 if minf(colour.r, minf(colour.g, colour.b)) > 0.98 else 0.0
			if x < rendered.get_width() / 2: river += highlight
			else: sea += highlight
	print("SUN current=", river, " ocean=", sea)
	if minf(river, sea) < 10.0:
		push_error("real sky/sun highlight must exist on both sides of the fixture")
		quit(1)
		return
	# Far microdetail may simplify, but both bodies retain real sunlight.
	material.set_shader_parameter("water_detail_begin_m", 0.0)
	material.set_shader_parameter("water_detail_end_m", 1.0)
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	rendered = root.get_texture().get_image()
	rendered.save_png(OUTPUT + "/sun-current-sea-far-detail.png")
	river = 0.0
	sea = 0.0
	for y in range(rendered.get_height() / 4, rendered.get_height() * 3 / 4):
		for x in range(rendered.get_width() / 4, rendered.get_width() * 3 / 4):
			var colour := rendered.get_pixel(x, y)
			var highlight := 1.0 if minf(colour.r, minf(colour.g, colour.b)) > 0.98 else 0.0
			if x < rendered.get_width() / 2: river += highlight
			else: sea += highlight
	assert(minf(river, sea) >= 10.0, "simplified distant water must retain real sun reflection")
	material.set_shader_parameter("water_detail_begin_m", 40.0)
	material.set_shader_parameter("water_detail_end_m", 100.0)
	# Inspect the real fragment's optical response independently of sun alignment.
	# Flow/wave normals may differ, but material roughness/specular must not cut
	# off at the current mask, including the sharpest supported sky setting.
	var diagnostic := Shader.new()
	diagnostic.code = shader.code.replace("render_mode blend_mix, depth_draw_never, cull_disabled;",
		"render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;").replace(
		"SPECULAR = mix(sky_reflection_strength, max(sky_reflection_strength, 0.55), glint_strength);",
		"SPECULAR = mix(sky_reflection_strength, max(sky_reflection_strength, 0.55), glint_strength); ALBEDO = vec3(ROUGHNESS, SPECULAR, 0.0);")
	material.shader = diagnostic
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	rendered = root.get_texture().get_image()
	var logical_size := Vector2(root.content_scale_size) if root.content_scale_size.x > 0 else root.get_visible_rect().size
	var pixel_scale := Vector2(rendered.get_size()) / logical_size
	var current_pixel := rendered.get_pixelv(Vector2i(camera.unproject_position(Vector3(-8, 0, 0)) * pixel_scale))
	var ocean_pixel := rendered.get_pixelv(Vector2i(camera.unproject_position(Vector3(8, 0, 0)) * pixel_scale))
	print("SUN optical current=", current_pixel, " ocean=", ocean_pixel)
	if current_pixel.g < 0.2 or ocean_pixel.g < 0.2 or absf(current_pixel.r - ocean_pixel.r) + absf(current_pixel.g - ocean_pixel.g) > 0.02:
		push_error("reflection response must not change abruptly at river/ocean current boundary")
		quit(1)
		return
	for setting in [Vector2(0, 0), Vector2(0.45, 0.32), Vector2(0, 1)]:
		material.set_shader_parameter("sky_reflection_roughness", setting.x)
		material.set_shader_parameter("water_glint_strength", setting.y)
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		rendered = root.get_texture().get_image()
		current_pixel = rendered.get_pixelv(Vector2i(camera.unproject_position(Vector3(-8, 0, 0)) * pixel_scale))
		ocean_pixel = rendered.get_pixelv(Vector2i(camera.unproject_position(Vector3(8, 0, 0)) * pixel_scale))
		if current_pixel.g < 0.2 or absf(current_pixel.r - ocean_pixel.r) + absf(current_pixel.g - ocean_pixel.g) > 0.02:
			push_error("sky/glint extremes must retain one optical response across river/ocean")
			quit(1)
			return
	# Sparse coastal field: flat water borders missing river-guard data. Its
	# real optical normal must stay upright rather than face a false zero cliff.
	var state := Image.create(32, 32, false, Image.FORMAT_RGBAF)
	for y in 32:
		for x in range(16, 32): state.set_pixel(x, y, Color(16, 0, 0, 1))
	var coast_diagnostic := Shader.new()
	var source := FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader")
	# Pin every other slope term. This still calls the actual surface fragment.
	source = source.replace("study_fine_slope(water_point, seconds) * glint_strength * 0.13", "vec2(0.0)")
	coast_diagnostic.code = source.replace("render_mode blend_mix, depth_draw_never, cull_disabled;",
		"render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;").replace(
		"ALBEDO = vec3(0.0);\n\tNORMAL = view_normal;", "ALBEDO = vec3(water_normal.y);\n\tNORMAL = view_normal;")
	material.shader = coast_diagnostic
	material.set_shader_parameter("wave_height_voxels", 0.0)
	material.set_shader_parameter("sea_swash_available", 1.0)
	material.set_shader_parameter("sea_swash_strength", 1.0)
	material.set_shader_parameter("sea_swash_origin", Vector2(-16, -16))
	material.set_shader_parameter("sea_swash_extent", Vector2(32, 32))
	material.set_shader_parameter("sea_swash_state", ImageTexture.create_from_image(state))
	var info := Image.create(32, 32, false, Image.FORMAT_RGBAF)
	info.fill(Color(-4, 0, 16, 1))
	material.set_shader_parameter("sea_swash_info", ImageTexture.create_from_image(info))
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	rendered = root.get_texture().get_image()
	var edge_pixel := rendered.get_pixelv(Vector2i(camera.unproject_position(Vector3(0.5, 0, 0)) * pixel_scale))
	print("SUN sparse coast upright=", edge_pixel.r)
	if edge_pixel.r < 0.98:
		push_error("missing sea cells must not create a false cliff in the actual water normal")
		quit(1)
		return
	print("PASS SUN: real light response in river and ocean")
	quit()
