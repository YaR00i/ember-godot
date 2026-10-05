extends SceneTree
## Rebuilds the disposable river variant of the accepted water study. The
## original map and the still-water study Resource are only read, never saved.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const SOURCE := "res://content/world_terrains/compact_irregular_water_study.res"
const OUTPUT := "res://content/world_terrains/compact_river_water_study.res"
const RIVER_SOURCE_Z := 700.0
const RIVER_MOUTH_Z := 300.0


func _initialize() -> void:
	_build_and_save.call_deferred()


func _build_and_save() -> void:
	var source := load(SOURCE) as TerrainResource
	if source == null or not source.validation_errors().is_empty():
		push_error("river study source is invalid")
		quit(1)
		return
	var study := build(source)
	if study == null or not study.validation_errors().is_empty():
		push_error("river study is invalid")
		quit(1)
		return
	var result := ResourceSaver.save(study, ProjectSettings.globalize_path(OUTPUT))
	if result != OK:
		push_error("river study save failed: " + str(result))
		quit(1)
		return
	print("PASS compact river study: ", OUTPUT)
	quit()


static func build(source: TerrainResource) -> TerrainResource:
	if source == null or not source.validation_errors().is_empty():
		return null
	var level := 0
	var water_material := 0
	for index in source.water_levels.size():
		if source.water_levels[index] > source.heights[index] and source.water_materials[index] > 0:
			level = source.water_levels[index]
			water_material = source.water_materials[index]
			break
	if level == 0 or water_material == 0:
		return null
	var result := source.working_copy()
	result.source_path = ""
	result.source_sha256 = ""
	var sand := result.palette_surface_roles.find("sand")
	var heights := result.heights
	var tops := result.top_materials
	var caps := result.cap_depths
	var waters := result.water_levels
	var water_materials := result.water_materials
	var pond_center := _center_x(RIVER_SOURCE_Z, result.width)
	for z in range(maxi(0, floori(RIVER_MOUTH_Z)), mini(result.depth, ceili(RIVER_SOURCE_Z + 52.0))):
		var center := _center_x(float(z), result.width)
		var half_width := 36.0 + sin(float(z) * 0.021) * 3.0
		var tangent := _center_slope(float(z))
		var normal_distance_scale := 1.0 / sqrt(1.0 + tangent * tangent)
		var start_x := maxi(0, floori(minf(center, pond_center) - 100.0))
		var end_x := mini(result.width, ceili(maxf(center, pond_center) + 100.0))
		for x in range(start_x, end_x):
			var distance := absf(float(x) - center) * normal_distance_scale
			var channel_edge := distance - half_width if float(z) <= RIVER_SOURCE_Z else 10000.0
			var pond_edge := Vector2(float(x) - pond_center, float(z) - RIVER_SOURCE_Z).length() - 40.0
			var shore_distance := minf(channel_edge, pond_edge)
			if shore_distance > 54.0:
				continue
			var index := result.column_index(x, z)
			var target_floor := (float(level) - 2.0 - 14.0 * (1.0 - smoothstep(-half_width, 0.0, shore_distance))
				if shore_distance <= 0.0 else float(level) + 25.0 * smoothstep(0.0, 54.0, shore_distance))
			var contour_warp := sin(float(x) * 0.043 + float(z) * 0.037) * 1.3 \
				+ sin(float(x) * 0.112 - float(z) * 0.061) * 0.9
			var carved_height := mini(heights[index],
				clampi(roundi((target_floor + contour_warp) / 4.0) * 4, 0, result.height_limit))
			if carved_height >= heights[index]:
				continue
			heights[index] = carved_height
			caps[index] = mini(caps[index], carved_height)
			if carved_height < level:
				waters[index] = level
				water_materials[index] = water_material
			if sand > 0 and shore_distance < 23.0:
				tops[index] = sand
			result.column_material_overrides.erase(index)
	result.heights = heights
	result.top_materials = tops
	result.cap_depths = caps
	result.water_levels = waters
	result.water_materials = water_materials
	var blocks_x := ceili(float(result.width) / float(TerrainResource.CELLS_PER_BLOCK))
	var blocks_z := ceili(float(result.depth) / float(TerrainResource.CELLS_PER_BLOCK))
	result.water_flow.resize(blocks_x * blocks_z)
	for block_z in blocks_z:
		var z := minf((float(block_z) + 0.5) * float(TerrainResource.CELLS_PER_BLOCK), float(result.depth - 1))
		if z < RIVER_MOUTH_Z or z > RIVER_SOURCE_Z + 42.0:
			continue
		var center := _center_x(z, result.width)
		var tangent := Vector2(-_center_slope(z), -1.0).normalized()
		var width := 36.0 + sin(z * 0.021) * 3.0
		for block_x in blocks_x:
			var x := minf((float(block_x) + 0.5) * float(TerrainResource.CELLS_PER_BLOCK), float(result.width - 1))
			var distance := absf(x - center) / sqrt(1.0 + _center_slope(z) * _center_slope(z))
			var bank := 1.0 - smoothstep(width * 0.46, width * 1.10, distance)
			var mouth := smoothstep(315.0, 405.0, z)
			var source_fade := 1.0 - smoothstep(RIVER_SOURCE_Z - 30.0, RIVER_SOURCE_Z + 42.0, z)
			var speed := bank * mouth * source_fade * 0.92
			if speed > 0.001:
				result.water_flow[block_x + block_z * blocks_x] = tangent * speed
	return result


static func _center_x(z: float, width: int) -> float:
	return float(width) * 0.48 + sin((z - 400.0) * 0.013) * 38.0 + sin((z - 400.0) * 0.029) * 12.0


static func _center_slope(z: float) -> float:
	return cos((z - 400.0) * 0.013) * 38.0 * 0.013 + cos((z - 400.0) * 0.029) * 12.0 * 0.029
