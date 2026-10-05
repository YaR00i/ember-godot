extends SceneTree
## Makes a disposable, scene-owned seabed study from the compact test map.
## The author's source Resource is loaded only; it is never saved by this tool.

const SOURCE := "res://content/world_terrains/new_landscape4.res"
const OUTPUT_CLEAR := "res://content/world_terrains/compact_clear_water_study.res"
const OUTPUT_IRREGULAR := "res://content/world_terrains/compact_irregular_water_study.res"
const EXTRA_DEPTH := 32
const FAR := 10000.0
const DIAGONAL := 1.41421356


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	var irregular := OS.get_cmdline_user_args().has("--irregular")
	var original := load(SOURCE) as EmberTerrainPilotResource
	if original == null or not original.validation_errors().is_empty():
		push_error("clear water study source terrain is invalid")
		quit(1)
		return
	var width := original.width
	var depth := original.depth
	var count := width * depth
	var distance := PackedFloat32Array()
	distance.resize(count)
	for index in count:
		distance[index] = FAR if original.water_levels[index] > original.heights[index] and original.water_materials[index] > 0 else 0.0
	for z in depth:
		for x in width:
			var index := x + z * width
			var value := distance[index]
			if x > 0:
				value = minf(value, distance[index - 1] + 1.0)
			if z > 0:
				value = minf(value, distance[index - width] + 1.0)
				if x > 0:
					value = minf(value, distance[index - width - 1] + DIAGONAL)
				if x + 1 < width:
					value = minf(value, distance[index - width + 1] + DIAGONAL)
			distance[index] = value
	for z in range(depth - 1, -1, -1):
		for x in range(width - 1, -1, -1):
			var index := x + z * width
			var value := distance[index]
			if x + 1 < width:
				value = minf(value, distance[index + 1] + 1.0)
			if z + 1 < depth:
				value = minf(value, distance[index + width] + 1.0)
				if x > 0:
					value = minf(value, distance[index + width - 1] + DIAGONAL)
				if x + 1 < width:
					value = minf(value, distance[index + width + 1] + DIAGONAL)
			distance[index] = value

	var study := original.working_copy()
	study.origin_y -= EXTRA_DEPTH
	study.height_limit += EXTRA_DEPTH
	study.source_path = ""
	study.source_sha256 = ""
	var depth_counts := {}
	for index in count:
		study.heights[index] += EXTRA_DEPTH
		if study.water_levels[index] > 0:
			study.water_levels[index] += EXTRA_DEPTH
		if distance[index] == 0.0:
			continue
		var old_depth: int = original.water_levels[index] - original.heights[index]
		var x := index % width
		var z := index / width
		var bend := sin(float(x) * 0.025) * 3.0 + sin(float(z) * 0.031) * 2.0
		if irregular:
			# The first study's even terraces read as diagonal surface waves.
			# Warp the contours after its shallow beach strip for an A/B map.
			var shore_weight := smoothstep(5.0, 54.0, distance[index])
			bend = (sin(float(x) * 0.027 + sin(float(z) * 0.016) * 2.1) * 12.0
				+ sin(float(z) * 0.034 - float(x) * 0.014) * 7.0
				+ sin(float(x + z) * 0.078) * 3.5) * shore_weight
		var distance_band := clampi(floori(maxf(distance[index] + bend, 0.0) / 16.0), 0, 9)
		var target_depth := maxi(old_depth, 4 + distance_band * 4)
		study.heights[index] = study.water_levels[index] - target_depth
		depth_counts[target_depth] = int(depth_counts.get(target_depth, 0)) + 1
	if not study.column_material_overrides.is_empty():
		for column in study.column_material_overrides:
			var shifted := {}
			for height in study.column_material_overrides[column]:
				shifted[int(height) + EXTRA_DEPTH] = study.column_material_overrides[column][height]
			study.column_material_overrides[column] = shifted
	var errors := study.validation_errors()
	if not errors.is_empty():
		push_error("clear water study invalid: " + str(errors))
		quit(1)
		return
	var path := ProjectSettings.globalize_path(OUTPUT_IRREGULAR if irregular else OUTPUT_CLEAR)
	var saved := ResourceSaver.save(study, path)
	if saved != OK:
		push_error("clear water study save failed: " + str(saved))
		quit(1)
		return
	print("PASS clear water seabed: ", path)
	print("STUDY_SEABED size/origin/water: ", width, "x", depth, "/", study.origin_y,
		"/", original.water_levels[0])
	print("STUDY_SEABED depth counts: ", depth_counts)
	quit()
