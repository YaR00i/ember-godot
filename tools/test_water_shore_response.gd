extends SceneTree
## Focused regression for terrain-derived approach, runup and wall reflection.

const SurfaceMesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func _fixture() -> EmberVoxelModelResource:
	var shore := EmberVoxelModelResource.new()
	shore.model_id = "systemic_shore_response"
	shore.voxels_per_block = 16
	shore.size_blocks = Vector3i(10, 1, 10)
	shore.height_voxels = 8
	shore.palette = PackedColorArray([
		Color.TRANSPARENT,
		Color("#8ca27c"),
		Color("#4bbfbb"),
	])
	var size := shore.grid_size()
	shore.voxels.resize(size.x * size.y * size.z)
	shore.voxels.fill(0)
	shore.surface_fill_levels.resize(size.x * size.z)
	shore.surface_fill_materials.resize(size.x * size.z)
	shore.surface_fill_palette.resize(size.x * size.z)
	for z in size.z:
		for x in size.x:
			shore.voxels[x + z * size.x] = 1
	for z in range(16, 144):
		for x in range(16, 144):
			var column := x + z * size.x
			shore.surface_fill_levels[column] = 4
			shore.surface_fill_materials[column] = 1
			shore.surface_fill_palette[column] = 2
	# Low connected bank on the left; vertical retaining wall on the right.
	for z in range(16, 144):
		for x in range(0, 16):
			for y in range(1, 4):
				shore.voxels[x + z * size.x + y * size.x * size.z] = 1
		for y in range(1, 7):
			shore.voxels[144 + z * size.x + y * size.x * size.z] = 1
	return shore


func _open_water_fixture() -> EmberVoxelModelResource:
	var open_water := EmberVoxelModelResource.new()
	open_water.model_id = "open_water_boundary"
	open_water.voxels_per_block = 16
	open_water.size_blocks = Vector3i.ONE
	open_water.height_voxels = 4
	open_water.palette = PackedColorArray([Color.TRANSPARENT, Color("#4bbfbb")])
	var size := open_water.grid_size()
	open_water.voxels.resize(size.x * size.y * size.z)
	open_water.surface_fill_levels.resize(size.x * size.z)
	open_water.surface_fill_levels.fill(2)
	open_water.surface_fill_materials.resize(size.x * size.z)
	open_water.surface_fill_materials.fill(1)
	open_water.surface_fill_palette.resize(size.x * size.z)
	open_water.surface_fill_palette.fill(1)
	return open_water


func _water_seam_samples(mesh: ArrayMesh, seam_x: float) -> Dictionary:
	var samples := {}
	for surface_index in mesh.get_surface_count():
		if mesh.surface_get_name(surface_index) != "water":
			continue
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		for index in vertices.size():
			if not is_equal_approx(vertices[index].x, seam_x):
				continue
			var key := roundi(vertices[index].z * 100000.0)
			var sample := Vector4(uvs[index].x, uvs[index].y, uv2s[index].x, uv2s[index].y)
			if samples.has(key) and not (samples[key] as Vector4).is_equal_approx(sample):
				errors.append("water metadata differs inside one chunk seam sample")
			samples[key] = sample
	return samples


func _run() -> void:
	var open_field := SurfaceMesher.build_water_shore_field(_open_water_fixture())
	var open_directions := open_field.get("direction_codes", PackedByteArray()) as PackedByteArray
	_check(
		open_directions.count(0) == open_directions.size(),
		"an open Resource bound was misclassified as an authored shore",
	)
	var source := _fixture()
	var shore_field := SurfaceMesher.build_water_shore_field(source)
	var mesh := SurfaceMesher.build_region(
		source,
		Vector3i.ZERO,
		source.grid_size(),
		1.0 / float(source.normalized_density()),
		false,
		true,
		-1,
		shore_field,
	)
	var voxel_size := 1.0 / float(source.normalized_density())
	var left_chunk := SurfaceMesher.build_region(
		source, Vector3i.ZERO, Vector3i(80, source.grid_size().y, source.grid_size().z),
		voxel_size, false, true, -1, shore_field
	)
	var right_chunk := SurfaceMesher.build_region(
		source, Vector3i(80, 0, 0), Vector3i(80, source.grid_size().y, source.grid_size().z),
		voxel_size, false, true, -1, shore_field
	)
	var left_seam := _water_seam_samples(left_chunk, 80.0 * voxel_size)
	var right_seam := _water_seam_samples(right_chunk, 80.0 * voxel_size)
	var seam_matches := 0
	for key in left_seam:
		if not right_seam.has(key):
			continue
		seam_matches += 1
		_check(
			(left_seam[key] as Vector4).is_equal_approx(right_seam[key] as Vector4),
			"water shore metadata changes at a technical chunk boundary",
		)
	_check(seam_matches > 0, "fixture did not exercise a wet chunk boundary")
	var water_surface := -1
	var shore_surface := -1
	for surface_index in mesh.get_surface_count():
		if mesh.surface_get_name(surface_index) == "water":
			water_surface = surface_index
		elif mesh.surface_get_name(surface_index) == "water_foam":
			shore_surface = surface_index
	_check(water_surface >= 0, "derived map has no water surface")
	if water_surface >= 0:
		var arrays := mesh.surface_get_arrays(water_surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		_check(
			vertices.size() == uvs.size() and uvs.size() == uv2s.size(),
			"water shore metadata does not match geometry",
		)
		var has_beach := false
		var has_wall := false
		var has_left_waterward := false
		var has_right_waterward := false
		var has_real_depth := false
		for index in uvs.size():
			has_beach = has_beach or uvs[index].y > 0.0
			has_wall = has_wall or uvs[index].y < 0.0
			has_real_depth = has_real_depth or uvs[index].x > 0.5
			has_left_waterward = has_left_waterward or uv2s[index].x > 0.7
			has_right_waterward = has_right_waterward or uv2s[index].x < -0.7
		_check(has_beach, "water surface has no low-bank distance metadata")
		_check(has_wall, "water surface has no reflecting-wall distance metadata")
		_check(has_real_depth, "water surface lost its real cavity depth")
		_check(
			has_left_waterward and has_right_waterward,
			"water directions do not follow both real banks",
		)
	_check(shore_surface >= 0, "derived water mesh has no shore response surface")
	if shore_surface >= 0:
		var arrays := mesh.surface_get_arrays(shore_surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		_check(vertices.size() == uvs.size() and uvs.size() == uv2s.size(), "shore metadata does not match geometry")
		var has_approach := false
		var has_runup := false
		var has_wall := false
		var has_left_waterward := false
		var has_right_waterward := false
		for index in uvs.size():
			has_approach = has_approach or uvs[index].x >= 3.5
			has_runup = has_runup or uvs[index].x < -0.25
			has_wall = has_wall or uvs[index].y > 0.5
			has_left_waterward = has_left_waterward or uv2s[index].x > 0.9
			has_right_waterward = has_right_waterward or uv2s[index].x < -0.9
			if uv2s[index].length() > 0.001:
				_check(is_equal_approx(uv2s[index].length(), 1.0), "shore contains a non-unit waterward direction")
		_check(has_approach, "incoming response band does not cover the full control range")
		_check(has_runup, "low terrain did not receive a landward runup band")
		_check(has_wall, "high terrain was not classified as a reflecting wall")
		_check(has_left_waterward and has_right_waterward, "response directions do not follow both real banks")
	var foam := Materials.foam_material()
	var water := Materials.water_material()
	_check(is_equal_approx(float(foam.get_shader_parameter("systemic_shore_strength")), 0.82), "production shore response is disabled")
	_check(is_equal_approx(float(foam.get_shader_parameter("shore_response_distance")), 4.0), "foam fade no longer matches the derived response width")
	var water_shader_source := FileAccess.get_file_as_string("res://shaders/ember_voxel_surface_water.gdshader")
	var foam_shader_source := FileAccess.get_file_as_string("res://shaders/ember_voxel_surface_foam.gdshader")
	var shared_include := "#include \"res://shaders/ember_water_wave.gdshaderinc\""
	_check(shared_include in water_shader_source, "water surface does not use the shared wave field")
	_check(shared_include in foam_shader_source, "shore response does not use the shared wave field")
	_check("systemic_shore_cycle" not in foam_shader_source, "shore response still owns a second travelling wave")
	_check("reflection_edge_fade" in foam_shader_source, "reflected wave still clips at the response mesh edge")
	_check("water_shore_wave_state" in water_shader_source, "water surface has no shared depth-driven wave transformation")
	_check("water_shore_wave_state" in foam_shader_source, "foam does not continue the transformed water crest")
	_check("water_break_factor" in foam_shader_source, "shore foam does not use a depth-relative break condition")
	_check("dominant_wave_phase" in foam_shader_source and "front_distance" in foam_shader_source, "beach runup is not one phase-linked boundary crest")
	_check(is_equal_approx(float(water.get_shader_parameter("shore_wave_transform")), 1.0), "accepted shore transformation is not enabled on production water")
	_check(water.get_shader_parameter("shore_geometry_driven") == true, "production water ignores Surface shore metadata")
	_check(is_equal_approx(float(foam.get_shader_parameter("shore_wave_transform")), 1.0), "production foam ignores the accepted depth-driven crest")
	for accepted in [
		["shore_break_distance", 3.20],
		["shore_foam_width", 0.08],
		["shore_break_softness", 0.07],
		["shore_runup_speed", 0.38],
	]:
		var key := accepted[0] as String
		var expected := float(accepted[1])
		_check(is_equal_approx(float(water.get_shader_parameter(key)), expected), "production water lost accepted %s" % key)
		_check(is_equal_approx(float(foam.get_shader_parameter(key)), expected), "production foam lost accepted %s" % key)
	for key in [
		"wave_length",
		"wave_speed",
		"wave_direction_degrees",
		"wave_natural_mix",
		"wave_direction_spread",
		"wave_scale_variation",
		"wave_grouping",
		"wind_ripple_strength",
		"wave_crest_sharpness",
	]:
		_check(foam.get_shader_parameter(key) != null, "foam material is missing shared parameter %s" % key)
		_check(foam.get_shader_parameter(key) == water.get_shader_parameter(key), "canonical water and shore differ at %s" % key)
	for error in errors:
		push_error(error)
	print(
		"PASS WATER_SHORE_RESPONSE: real boundaries derive approach, beach runup and wall reflection"
		if errors.is_empty()
		else "FAIL WATER_SHORE_RESPONSE: %d" % errors.size()
	)
	quit(0 if errors.is_empty() else 1)
