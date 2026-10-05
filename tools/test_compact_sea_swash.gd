extends SceneTree

const Swash = preload("res://scripts/prototypes/ember_compact_sea_swash.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const PilotProjection = preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const MeshBuilder = preload("res://scripts/prototypes/ember_terrain_pilot_mesh.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# A wave must be born and disappear with a flat temporal envelope; a
	# nonzero slope at the cycle seam looks like a new pulse switched on.
	assert(Swash.wave_profile(Swash.wave_front(0.0, 10.0), 0.0001, 2.8, 10.0).x < 0.00001,
		"offshore wave birth must start smoothly, rather than with a nonzero initial slope")
	assert(Swash.wave_profile(Swash.wave_front(1.0, 10.0), 0.9999, 2.8, 10.0).x < 0.00001)
	assert(Swash.wave_front(0.0, 10.0, 20.0) < Swash.wave_front(0.0, 10.0, 6.0))
	var early := Swash.wave_profile(-18.0, 0.12, 2.8, 10.0, 20.0, 0.65).x
	assert(early > Swash.wave_profile(-18.0, 0.12, 2.8, 10.0, 6.0, 0.65).x + 0.1)
	assert(early > Swash.wave_profile(-18.0, 0.12, 2.8, 10.0, 20.0, 0.0).x)
	assert(is_equal_approx(Swash.wave_profile(0.0, 0.45, 2.8, 10.0, 20.0, 0.0).x,
		Swash.wave_profile(0.0, 0.45, 2.8, 10.0, 20.0, 1.0).x), "offshore strength must preserve coast/run-up height")
	# Bound a 20 Hz update at every point of the whole approach/cycle.
	for distance in range(-24, 16):
		for step in 180:
			var a := Swash.wave_profile(distance, float(step) / 180.0, 2.8, 10.0)
			var b := Swash.wave_profile(distance, float(step + 1) / 180.0, 2.8, 10.0)
			assert(absf(a.x - b.x) < 0.30 and absf(a.y - b.y) < 0.18)
		assert(Swash.wave_profile(distance, 0.6599, 2.8, 10.0).distance_to(
			Swash.wave_profile(distance, 0.6601, 2.8, 10.0)) < 0.01,
			"changing from run-up to retreat must not switch crest width abruptly")
	var terrain := Terrain.new()
	terrain.width = 64
	terrain.depth = 32
	var count := terrain.width * terrain.depth
	terrain.heights.resize(count)
	terrain.water_levels.resize(count)
	terrain.water_materials.resize(count)
	terrain.top_materials.resize(count)
	terrain.base_materials.resize(count)
	terrain.cap_depths.resize(count)
	terrain.palette = PackedColorArray([Color.TRANSPARENT, Color(0.7, 0.6, 0.3), Color(0.1, 0.7, 0.8)])
	for z in terrain.depth:
		for x in terrain.width:
			var i := x + z * terrain.width
			terrain.heights[i] = 4 if x < 16 else 8 + (x - 16) / 4
			terrain.top_materials[i] = 1
			terrain.base_materials[i] = 1
			terrain.cap_depths[i] = 1
			terrain.water_levels[i] = 8 if x < 16 else 0
			terrain.water_materials[i] = 2 if x < 16 else 0
	var authored_levels := terrain.water_levels.duplicate()
	var authored_heights := terrain.heights.duplicate()
	var state := Swash.new()
	state.build(terrain)
	assert(not state.records.is_empty() and not state.dry_tiles.is_empty())
	var projection := PilotProjection.new()
	projection.water_visual_material = load("res://materials/ember_compact_sky_reflection_study.tres")
	root.add_child(projection)
	assert(projection.open_document(terrain))
	while projection.pending_tile_count() > 0 or projection.pending_runtime_lod_count() > 0: await process_frame
	assert(not projection.is_processing())
	var authored_revision := projection.column_revision()
	projection.set_sea_swash(state)
	assert(projection.is_processing(), "attaching a coast field must wake the tile queue")
	while projection.pending_tile_count() > 0 or projection.pending_runtime_lod_count() > 0: await process_frame
	var visible_film_vertices := 0
	for mesh in projection.find_children("Water", "MeshInstance3D", true, false):
		if mesh.mesh.get_surface_count() == 0: continue
		for uv in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
			if uv.y < -0.5: visible_film_vertices += 1
	assert(visible_film_vertices > 0, "real queued projection must contain bank coverage geometry")
	assert(projection.column_revision() == authored_revision)
	projection.set_water_surface_offset(-0.35)
	state.advance(1.35, 2.8, 9.0, 10.0, -0.35, 6.0, 20.0, 0.65)
	var offshore_point := Vector3(0.5, 0.0, 12.5)
	var offshore_sample := state.sample(Vector2i(0, 12))
	assert(float(offshore_sample.distance) < -15.0)
	var offshore_base := 8.085 - 0.35
	var expected_offshore := lerpf(offshore_base, state.surface_height(Vector2(0.5, 12.5)),
		Swash.coastal_influence(float(offshore_sample.distance)))
	assert(expected_offshore > offshore_base + 0.1)
	assert(is_equal_approx(projection.water_surface_sample(offshore_point).position.y, expected_offshore),
		"offshore query must include the blended approach outside the old 15-voxel cutoff")
	var bank := Vector2i(18, 12)
	var point := Vector3(bank.x + 0.5, 0, bank.y + 0.5)
	var max_cover := 0.0
	var foam_seen := false
	var web_seed_seen := false
	var dry_seen := false
	for step in range(91):
		state.advance(float(step) * 0.1, 2.8, 9.0, 10.0, -0.35, 6.0)
		var sample: Dictionary = state.sample(bank)
		if step == 36: assert(float(sample.foam_age) == 8.0, "foam web must not appear ahead of the incoming crest")
		max_cover = maxf(max_cover, float(sample.coverage))
		foam_seen = foam_seen or float(sample.foam) > 0.05
		web_seed_seen = web_seed_seen or (float(sample.foam_age) == 0.0 and float(sample.foam) > 0.07)
		var physical: Dictionary = projection.water_surface_sample(point)
		assert(bool(physical.wet) == (float(sample.coverage) > 0.05), "visible bank coverage and query must agree")
		if physical.wet: assert(is_equal_approx(physical.position.y, float(sample.height)))
		else: dry_seen = true
	assert(max_cover > 0.9 and foam_seen and dry_seen, "wave must arrive with foam and retreat")
	assert(web_seed_seen and float(state.sample(bank).foam_age) > 0.2,
		"sea foam web must be born at the incoming wave and age through retreat")
	assert(float(state.sample(bank).wetness) > 0.0, "retreat must leave wet sand")
	for step in range(1, 81): state.advance(9.0 + step * 0.1, 0.0, 9.0, 10.0, -0.35, 6.0)
	assert(float(state.sample(bank).coverage) == 0.0 and float(state.sample(bank).wetness) == 0.0)
	assert(float(state.sample(bank).foam_age) == 8.0, "an inactive wave must not repaint foam history")
	state.advance(4.95, 2.8, 9.0, 0.0, -0.35, 6.0)
	assert(float(state.sample(bank).coverage) == 0.0, "reach zero must prevent dry-bank coverage")
	state.advance(4.95, 2.8, 9.0, 10.0, -0.35, 6.0)
	var between := Vector3(bank.x + 0.25, 0, bank.y + 0.75)
	assert(is_equal_approx(projection.water_surface_sample(between).position.y,
		state.surface_height(Vector2(between.x, between.z))), "query must share the shader's interpolated height")
	assert(state.sample(Vector2i(45, 12)).is_empty(), "high bank must stop propagation")
	assert(terrain.water_levels == authored_levels and terrain.heights == authored_heights)
	var generated := MeshBuilder.build_tile(terrain, 0, 0, 64, 8, true, state.dry_tiles[Vector2i.ZERO])
	assert((generated.water as ArrayMesh).get_surface_count() == 1, "run-up belongs to the same Water mesh")
	var arrays := (generated.water as ArrayMesh).surface_get_arrays(0)
	var film_vertices := 0
	for uv in arrays[Mesh.ARRAY_TEX_UV]:
		if uv.y < -0.5: film_vertices += 1
	assert(film_vertices > 0)
	if DisplayServer.get_name() != "headless" and not await _verify_render(projection, state, bank):
		quit(1)
		return
	projection.set_sea_swash(null)
	assert(not projection.water_surface_sample(point).wet)
	while projection.pending_tile_count() > 0: await process_frame
	for mesh in projection.find_children("Water", "MeshInstance3D", true, false):
		if mesh.mesh.get_surface_count() == 0: continue
		for uv in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
			assert(uv.y >= -0.5, "removing the field must remove its derived geometry")
	# A calm landlocked puddle must not gain an ocean run-up.
	var puddle_cell := Vector2i(50, 12)
	var puddle_index := puddle_cell.x + puddle_cell.y * terrain.width
	terrain.heights[puddle_index] = 4
	terrain.water_levels[puddle_index] = 8
	terrain.water_materials[puddle_index] = 2
	var isolated := Swash.new()
	isolated.build(terrain)
	assert(isolated.sample(puddle_cell).is_empty())
	# Entirely flowing water cannot become a second sea run-up source.
	terrain.water_flow.resize(8)
	terrain.water_flow.fill(Vector2(0, 1))
	var river := Swash.new()
	river.build(terrain)
	assert(river.records.is_empty() and river.dry_tiles.is_empty())
	projection.queue_free()
	await process_frame
	print("PASS SEA_SWASH: approach/foam/retreat/drying, shared query/mesh, high bank, river isolation, authored data unchanged")
	quit()


func _verify_render(projection: Node3D, state: RefCounted, bank: Vector2i) -> bool:
	var ground: ShaderMaterial = projection.get("_ground_material")
	var water: ShaderMaterial = projection.get("_water_material")
	for material in [ground, water]:
		material.set_shader_parameter("sea_swash_available", 1.0)
		material.set_shader_parameter("sea_swash_info", state.info_texture)
		material.set_shader_parameter("sea_swash_state", state.state_texture)
		material.set_shader_parameter("sea_swash_origin", Vector2(state.bounds.position))
		material.set_shader_parameter("sea_swash_extent", Vector2(state.bounds.size))
	ground.set_shader_parameter("sand_wet_strength", 0.8)
	water.set_shader_parameter("sea_swash_strength", 2.8)
	water.set_shader_parameter("sea_foam_age", state.foam_age_texture)
	water.set_shader_parameter("water_level_offset_voxels", -0.35)
	water.set_shader_parameter("preview_time", 0.0)
	water.set_shader_parameter("wave_height_voxels", 0.0)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.2, 0.2)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.1
	root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.light_energy = 0.25
	light.rotation_degrees = Vector3(-60, 0, 0)
	root.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	root.add_child(camera)
	var bank_point := Vector3(bank.x + 0.5, 8.0, bank.y + 0.5)
	camera.position = bank_point + Vector3(0, 40, 0)
	camera.look_at(bank_point, Vector3(0, 0, -1))
	camera.make_current()
	state.advance(0.0, 0.0, 9.0, 10.0, -0.35, 6.0)
	var dry_colour := await _bank_colour(camera, bank_point)
	state.advance(4.95, 2.8, 9.0, 10.0, -0.35, 6.0)
	var covered_colour := await _bank_colour(camera, bank_point)
	print("SEA_SWASH pixel dry=", dry_colour, " covered=", covered_colour)
	if absf(dry_colour.r - covered_colour.r) + absf(dry_colour.g - covered_colour.g) + absf(dry_colour.b - covered_colour.b) <= 0.02:
		push_error("real Forward+ bank pixel must change when run-up geometry covers the sand")
		return false
	for step in range(50, 91): state.advance(step * 0.1, 2.8, 9.0, 10.0, -0.35, 6.0)
	assert(float(state.sample(bank).coverage) == 0.0)
	var wet_colour := await _bank_colour(camera, bank_point)
	ground.set_shader_parameter("sand_wet_strength", 0.0)
	var trace_disabled := await _bank_colour(camera, bank_point)
	if wet_colour.get_luminance() >= trace_disabled.get_luminance() - 0.03:
		push_error("real ground material must retain a darker sand pixel after water retreats")
		return false
	ground.set_shader_parameter("sand_wet_strength", 0.8)
	for step in range(1, 71): state.advance(9.0 + step * 0.1, 0.0, 9.0, 10.0, -0.35, 6.0)
	var dried_colour := await _bank_colour(camera, bank_point)
	if absf(dried_colour.get_luminance() - trace_disabled.get_luminance()) >= 0.02:
		push_error("drying must restore the same rendered sand colour")
		return false
	print("PASS SEA_SWASH Forward+: displayed bank coverage, retreat, real wet ground, drying restores colour")
	if not await _verify_foam_render(projection, state, water, environment): return false
	camera.queue_free()
	light.queue_free()
	environment.queue_free()
	return true


func _verify_foam_render(projection: Node3D, state: RefCounted, water: ShaderMaterial, environment: WorldEnvironment) -> bool:
	# Diagnostic output calls the actual shared web/sea lifecycle function.
	# Diagnostic colour excludes lighting; geometry/fields/wave birth are unchanged.
	var shader := Shader.new()
	var source := FileAccess.get_file_as_string("res://shaders/ember_compact_sky_reflection_study.gdshader").get_slice("void fragment()", 0)
	shader.code = source.replace("render_mode blend_mix, depth_draw_never, cull_disabled;",
		"render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;") + """
void fragment() {
 ALBEDO = vec3(study_sea_foam_trails(water_point)); ALPHA = 1.0;
}
"""
	water.shader = shader
	environment.environment.background_color = Color.BLACK
	for mesh in projection.find_children("Ground", "MeshInstance3D", true, false): mesh.hide()
	for step in range(56): state.advance(step * 0.1, 2.8, 9.0, 10.0, -0.35, 6.0)
	water.set_shader_parameter("sea_swash_time", 5.5)
	water.set_shader_parameter("foam_trail_strength", 0.0) # River controls no longer erase sea foam.
	water.set_shader_parameter("sea_foam_trail_strength", 0.7)
	water.set_shader_parameter("sea_foam_trail_lifetime", 0.3)
	var short := await _foam_energy()
	water.set_shader_parameter("sea_foam_trail_lifetime", 4.0)
	var long := await _foam_energy()
	water.set_shader_parameter("sea_foam_trail_strength", 0.0)
	var disabled := await _foam_energy()
	water.set_shader_parameter("sea_foam_trail_strength", 0.7)
	water.set_shader_parameter("sea_swash_strength", 0.0)
	var stopped := await _foam_energy()
	water.set_shader_parameter("sea_swash_strength", 2.8)
	for step in range(56, 121): state.advance(step * 0.1, 0.0, 9.0, 10.0, -0.35, 6.0)
	var dissolved := await _foam_energy()
	print("SEA_FOAM short=", short, " long=", long, " off=", disabled, " wave_off=", stopped, " dissolved=", dissolved)
	if long < 5.0 or long < short * 1.2 or disabled > 0.01 or stopped > 0.01 or dissolved > 0.01:
		push_error("sea web must follow wave birth, retain older threads at longer lifetime, and fully switch off/dissolve")
		return false
	print("PASS SEA_FOAM Forward+: real shared web, lifetime, strength/wave off, full decay")
	return true


func _foam_energy() -> float:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	var total := 0.0
	for y in range(0, rendered.get_height(), 4):
		for x in range(0, rendered.get_width(), 4): total += rendered.get_pixel(x, y).r
	return total


func _bank_colour(camera: Camera3D, point: Vector3) -> Color:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	var logical_size := Vector2(root.content_scale_size) if root.content_scale_size.x > 0 else root.get_visible_rect().size
	var pixel := Vector2i(camera.unproject_position(point) * Vector2(rendered.get_size()) / logical_size)
	return rendered.get_pixelv(pixel)
