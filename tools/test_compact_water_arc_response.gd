extends SceneTree
## Forward+ regression: evaluate the real shader phase and reaction functions.
## Only the diagnostic output replaces fragment colour; no wave math is copied.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Phase = preload("res://scripts/prototypes/ember_compact_river_phase.gd")
const Study = preload("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var source := FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader")
	var shader := Shader.new()
	shader.code = source.get_slice("void fragment()", 0) + """
uniform int diagnostic_mode = 0;
uniform float diagnostic_time = 0.0;
void fragment() {
 ALBEDO = vec3(0.0); ALPHA = 1.0;
 EMISSION = diagnostic_mode == 5 ? vec3((water_world_position.y + 1.0) * 0.5)
  : diagnostic_mode == 4 ? vec3(study_shore_foam(water_point, diagnostic_time))
  : diagnostic_mode == 3 ? vec3(study_foam_width_scale(water_point, diagnostic_time, 0.0) * 0.5)
  : diagnostic_mode == 2 ? vec3(study_foam_trails(water_point, 1.0) * 4.0) : diagnostic_mode == 0
  ? vec3(sin(study_river_phase(water_point, 0.0)) * 0.5 + 0.5)
  : vec3(study_reaction(water_point, 0.0).x / 0.23);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("wave_height_voxels", 0.0)
	material.set_shader_parameter("flow_map_extent_blocks", Vector2(16, 16))
	material.set_shader_parameter("reaction_strength", 1.0)
	var settings := Study.new()
	material.set_shader_parameter("reaction_spread_speed", settings.reaction_spread_speed)
	material.set_shader_parameter("reaction_opening", settings.reaction_opening)
	material.set_shader_parameter("reaction_birth_seconds", settings.reaction_birth_seconds)
	settings.free()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color.BLACK
	viewport.add_child(world)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(256, 256)
	mesh.mesh = plane
	mesh.material_override = material
	mesh.position = Vector3(128, 0, 128)
	viewport.add_child(mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 256
	camera.far = 600
	viewport.add_child(camera)
	camera.position = Vector3(128, 300, 128)
	camera.look_at(Vector3(128, 0, 128), Vector3(0, 0, -1))
	camera.make_current()
	var terrain := Terrain.new()
	terrain.width = 256
	terrain.depth = 256
	terrain.water_flow.resize(256)
	var failures: Array[String] = []
	for forward in [1.0, -1.0]:
		terrain.water_flow.fill(Vector2(0, forward))
		material.set_shader_parameter("river_phase_map", Phase.texture(terrain))
		var image := await _image(viewport)
		var low := 256 if forward > 0 else 160
		var high := 384 if forward > 0 else 288
		var center := _crest(image, 256, low, high)
		var edge := _crest(image, 224, low, high)
		print("ARC_RESPONSE forward=", forward, " center=", center, " side=", edge)
		if (center - edge) * forward < 2.0:
			failures.append("river front center points against the current")
	material.set_shader_parameter("diagnostic_mode", 1)
	material.set_shader_parameter("reaction_count", 1)
	var pulses := PackedVector4Array()
	var details := PackedVector4Array()
	pulses.resize(12)
	details.resize(12)
	var early := 0.0
	var mature := 0.0
	for age in [0.01, 0.25]:
		pulses[0] = Vector4(8, 8, age, 1)
		details[0] = Vector4(0, 1, 1.0 - age / 2.6, 0.55)
		material.set_shader_parameter("reaction_samples", pulses)
		material.set_shader_parameter("reaction_details", details)
		var image := await _image(viewport)
		var peak := 0.0
		for y in range(220, 255):
			peak = maxf(peak, image.get_pixel(256, y).r)
		if age < 0.1: early = peak
		else: mature = peak
	print("ARC_RESPONSE birth_peak=", early, " developed_peak=", mature)
	if early > mature * 0.4:
		failures.append("new reaction appears at almost full height instead of growing")
	# Evaluate actual foam shader lifecycle, including full off and stopped flow.
	material.set_shader_parameter("diagnostic_mode", 2)
	material.set_shader_parameter("river_flow_enabled", 1.0)
	material.set_shader_parameter("river_flow_speed", 1.0)
	material.set_shader_parameter("river_crest_whiteness", 1.0)
	material.set_shader_parameter("river_wave_mix", 1.0)
	var flow := Image.create(2, 2, false, Image.FORMAT_RGF)
	flow.fill(Color(0.5, 1.0, 0.0, 1.0))
	material.set_shader_parameter("water_flow_map", ImageTexture.create_from_image(flow))
	var amounts: Array[float] = []
	for life in [0.3, 3.0]:
		material.set_shader_parameter("foam_trail_strength", 1.0)
		material.set_shader_parameter("foam_trail_lifetime", life)
		amounts.append(_foam_amount(await _image(viewport)))
	material.set_shader_parameter("foam_trail_strength", 0.0)
	var off := _foam_amount(await _image(viewport))
	material.set_shader_parameter("foam_trail_strength", 1.0)
	material.set_shader_parameter("river_flow_speed", 0.0)
	var stopped := _foam_amount(await _image(viewport))
	print("FOAM_RESPONSE short=", amounts[0], " long=", amounts[1], " off=", off, " stopped=", stopped)
	if amounts[0] < 1.0 or amounts[1] < amounts[0] * 1.5 or off > 0.01 or stopped > 0.01:
		failures.append("foam trails must grow with lifetime and disappear when disabled or current stops")
	# Shared bank/object width must breathe smoothly, stay bounded and switch off.
	material.set_shader_parameter("diagnostic_mode", 3)
	material.set_shader_parameter("wave_height_voxels", 3.0)
	var widths: Array[float] = []
	for seconds in range(16):
		material.set_shader_parameter("diagnostic_time", float(seconds) * 0.4)
		var image := await _image(viewport)
		widths.append(image.get_pixel(256, 256).srgb_to_linear().r * 2.0)
	var minimum := 2.0
	var maximum := 0.0
	for i in widths.size():
		minimum = minf(minimum, widths[i])
		maximum = maxf(maximum, widths[i])
		if i > 0 and absf(widths[i] - widths[i - 1]) > 0.13:
			failures.append("foam width jumps instead of breathing smoothly")
	material.set_shader_parameter("foam_width_pulse", 0.0)
	var steady := (await _image(viewport)).get_pixel(256, 256).srgb_to_linear().r * 2.0
	print("FOAM_WIDTH min=", minimum, " max=", maximum, " disabled=", steady)
	if minimum < 0.65 or maximum > 1.35 or maximum - minimum < 0.15 or absf(steady - 1.0) > 0.01:
		failures.append("foam width must vary within bounds and return to authored width when disabled")
	# A changing bank band must keep its root at the first wet shore samples.
	# Constant distance textures isolate the real foam function from terrain/noise.
	material.set_shader_parameter("diagnostic_mode", 4)
	material.set_shader_parameter("shore_field_available", 1.0)
	material.set_shader_parameter("shore_foam_strength", 1.0)
	material.set_shader_parameter("shore_foam_sharpness", 1.0)
	material.set_shader_parameter("shore_foam_breakup", 0.0)
	material.set_shader_parameter("wave_height_voxels", 0.0)
	var shore := Image.create(2, 2, false, Image.FORMAT_RF)
	for width in [0.4, 1.8, 6.0]:
		material.set_shader_parameter("shore_foam_width_voxels", width)
		shore.fill(Color(0.4 * 3.0 / 255.0, 0.0, 0.0, 1.0))
		material.set_shader_parameter("shore_distance_map", ImageTexture.create_from_image(shore))
		var root_amount := (await _image(viewport)).get_pixel(256, 256).r
		print("SHORE_ROOT width=", width, " near_bank=", root_amount)
		if root_amount < 0.25:
			failures.append("bank foam detaches from shore when width changes")
	material.set_shader_parameter("shore_foam_width_voxels", 0.4)
	material.set_shader_parameter("shore_foam_motion_voxels", 4.0)
	material.set_shader_parameter("foam_width_pulse", 1.0)
	material.set_shader_parameter("wave_height_voxels", 3.0)
	for seconds in range(8):
		material.set_shader_parameter("diagnostic_time", float(seconds))
		if (await _image(viewport)).get_pixel(256, 256).r < 0.25:
			failures.append("moving narrow bank foam loses its fixed shore root")
	material.set_shader_parameter("wave_height_voxels", 0.0)
	shore.fill(Color(2.0 * 3.0 / 255.0, 0.0, 0.0, 1.0))
	material.set_shader_parameter("shore_distance_map", ImageTexture.create_from_image(shore))
	var outer_amounts: Array[float] = []
	for width in [0.4, 6.0]:
		material.set_shader_parameter("shore_foam_width_voxels", width)
		outer_amounts.append((await _image(viewport)).get_pixel(256, 256).r)
	if outer_amounts[0] > 0.01 or outer_amounts[1] < 0.25:
		failures.append("bank width must expand the outer edge into water")
	for distance in [0.0, 10.0]:
		shore.fill(Color(distance * 3.0 / 255.0, 0.0, 0.0, 1.0))
		material.set_shader_parameter("shore_distance_map", ImageTexture.create_from_image(shore))
		if (await _image(viewport)).get_pixel(256, 256).r > 0.01:
			failures.append("bank foam leaks beyond wet bank band")
	material.set_shader_parameter("diagnostic_mode", 5)
	for offset in [0.0, -0.5]:
		material.set_shader_parameter("water_level_offset_voxels", offset)
		var actual_height := (await _image(viewport)).get_pixel(256, 256).srgb_to_linear().r * 2.0 - 1.0
		print("WATER_LEVEL offset=", offset, " vertex_height=", actual_height)
		if absf(actual_height - offset) > 0.02:
			failures.append("water level control does not move the rendered surface")
	viewport.queue_free()
	await process_frame
	if not failures.is_empty():
		for failure in failures: printerr("FAIL ARC_RESPONSE: ", failure)
		quit(1)
	else:
		print("PASS ARC_RESPONSE: downstream front, reaction birth, foam web lifecycle, bounded width pulse, fixed wet bank root")
		quit()


func _foam_amount(image: Image) -> float:
	var amount := 0.0
	for y in range(32, 480, 2):
		for x in range(32, 480, 2): amount += image.get_pixel(x, y).r
	return amount


func _image(viewport: SubViewport) -> Image:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()


func _crest(image: Image, x: int, low: int, high: int) -> float:
	var peak := 0.0
	var rows := PackedInt32Array()
	for y in range(low, high):
		var value := image.get_pixel(x, y).r
		if value > peak:
			peak = value
			rows.clear()
		if is_equal_approx(value, peak): rows.append(y)
	assert(peak > 0.5, "shader diagnostic did not render")
	var total := 0.0
	for y in rows: total += y
	return total / float(rows.size())
