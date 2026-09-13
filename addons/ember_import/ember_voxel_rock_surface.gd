@tool
extends RefCounted
## Colour-only, low-frequency rock dressing. Never changes occupancy or shape RNG.
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")


static func normalized(parameters: Dictionary) -> Dictionary:
	var moss := _color(parameters.get("moss_color"), Color("394b23"))
	return {
		"surface_seed": clampi(int(parameters.get("surface_seed", 37)), 0, 2147483647),
		"surface_strength": clampi(int(parameters.get("surface_strength", 0)), 0, 100),
		"surface_patch_size": clampi(int(parameters.get("surface_patch_size", 12)), 4, 32),
		"mineral_pattern": clampi(int(parameters.get("mineral_pattern", 0)), 0, 2),
		"mineral_color": _color(parameters.get("mineral_color"), Color("8b8170")),
		"mineral_strength": clampi(int(parameters.get("mineral_strength", 70)), 0, 100),
		"mineral_direction": clampi(int(parameters.get("mineral_direction", 2)), 0, 2),
		"mineral_angle": clampi(int(parameters.get("mineral_angle", 25)), 0, 179),
		"mineral_width": clampi(int(parameters.get("mineral_width", 2)), 1, 8),
		"mineral_spacing": clampi(int(parameters.get("mineral_spacing", 12)), 4, 32),
		"mineral_vein_style": clampi(int(parameters.get("mineral_vein_style", 0)), 0, 1),
		"mineral_irregularity": clampi(int(parameters.get("mineral_irregularity", 65)), 0, 100),
		"mineral_branching": clampi(int(parameters.get("mineral_branching", 55)), 0, 100),
		"moss_coverage": clampi(int(parameters.get("moss_coverage", 0)), 0, 100),
		"moss_color": moss,
		# Missing fields reproduce the previous automatic 12% highlight exactly.
		"moss_highlight_color": _color(parameters.get("moss_highlight_color"), moss.lightened(0.12)),
		"moss_highlight_strength": clampi(int(parameters.get("moss_highlight_strength", 100)), 0, 100),
		"moss_patch_size": clampi(int(parameters.get("moss_patch_size", 14)), 4, 32),
		"moss_drape": clampi(int(parameters.get("moss_drape", 35)), 0, 100),
	}


static func _color(value: Variant, fallback: Color) -> Color:
	if not value is Color: return fallback
	if not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b): return fallback
	return Color(clampf(value.r, 0, 1), clampf(value.g, 0, 1), clampf(value.b, 0, 1), 1)


static func fields() -> Array[Dictionary]:
	return [
		{"key": "surface_seed", "title": "Сид оформления · форма не меняется", "min": 0, "max": 2147483647, "section": "Рисунок породы", "heading": true},
		{"key": "surface_strength", "title": "Пятна породы · выраженность %", "min": 0, "max": 100, "section": "Рисунок породы"},
		{"key": "surface_patch_size", "title": "Размер пятен · vox", "min": 4, "max": 32, "section": "Рисунок породы"},
		{"key": "mineral_pattern", "title": "Минеральный рисунок", "options": ["Без минералов", "Слои", "Прожилка"], "section": "Минералы", "heading": true},
		{"key": "mineral_color", "title": "Цвет минералов", "type": "color", "section": "Минералы"},
		{"key": "mineral_strength", "title": "Контраст минералов · %", "min": 0, "max": 100, "section": "Минералы"},
		{"key": "mineral_direction", "title": "Направление минералов", "options": ["Горизонтальное", "Вертикальное", "Наклонное"], "section": "Минералы"},
		{"key": "mineral_angle", "title": "Поворот направления · °", "min": 0, "max": 179, "section": "Минералы"},
		{"key": "mineral_width", "title": "Толщина полосы · vox", "min": 1, "max": 8, "section": "Минералы"},
		{"key": "mineral_spacing", "title": "Расстояние между слоями · vox", "min": 4, "max": 32, "section": "Минералы"},
		{"key": "mineral_vein_style", "title": "Характер жилы", "options": ["Ровная · прежняя", "Неровная · разветвлённая"], "section": "Минералы"},
		{"key": "mineral_irregularity", "title": "Изгибы и включения жилы · %", "min": 0, "max": 100, "section": "Минералы"},
		{"key": "mineral_branching", "title": "Ответвления жилы · %", "min": 0, "max": 100, "section": "Минералы"},
		{"key": "moss_coverage", "title": "Покрытие мхом · %", "min": 0, "max": 100, "section": "Мох", "heading": true},
		{"key": "moss_color", "title": "Цвет мха", "type": "color", "section": "Мох"},
		{"key": "moss_highlight_strength", "title": "Сила светлого акцента мха · %", "min": 0, "max": 100, "section": "Мох"},
		{"key": "moss_highlight_color", "title": "Светлый цвет мха", "type": "color", "section": "Мох"},
		{"key": "moss_patch_size", "title": "Размер островков · vox", "min": 4, "max": 32, "section": "Мох"},
		{"key": "moss_drape", "title": "Спуск мха по бокам · %", "min": 0, "max": 100, "section": "Мох"},
	]


static func _noise(seed: int, size: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0 / float(size)
	return noise


static func field_enabled(key: String, parameters: Dictionary) -> bool:
	if int(parameters.get("generation_version", 1)) != 2: return false
	if key == "surface_patch_size": return int(parameters.surface_strength) > 0
	if key == "mineral_angle": return int(parameters.mineral_pattern) > 0 and int(parameters.mineral_direction) != 0
	if key == "mineral_spacing": return int(parameters.mineral_pattern) == 1
	if key == "mineral_vein_style": return int(parameters.mineral_pattern) == 2
	if key in ["mineral_irregularity", "mineral_branching"]: return int(parameters.mineral_pattern) == 2 and int(parameters.mineral_vein_style) == 1
	if key.begins_with("mineral_") and key != "mineral_pattern": return int(parameters.mineral_pattern) > 0
	if key == "moss_highlight_color": return int(parameters.moss_coverage) > 0 and int(parameters.moss_highlight_strength) > 0
	if key.begins_with("moss_") and key != "moss_coverage": return int(parameters.moss_coverage) > 0
	return true


static func needs_vein_upgrade(parameters: Dictionary, key: String, value: Variant) -> bool:
	return key == "mineral_pattern" and int(value) == 2 and int(parameters.get("mineral_vein_style", 0)) == 0


static func apply(source: EmberVoxelModelResource, settings: Dictionary, origin: Vector3i) -> void:
	if settings.surface_strength == 0 and settings.mineral_pattern == 0 and settings.moss_coverage == 0: return
	var base: Color = source.palette[1]
	var contrast := float(settings.surface_strength) / 100.0
	var mineral: Color = base.lerp(settings.mineral_color, float(settings.mineral_strength) / 100.0)
	var moss: Color = settings.moss_color
	source.palette.append_array(PackedColorArray([
		base.darkened(contrast * 0.32), base.lightened(contrast * 0.22),
		mineral, moss, moss.lerp(settings.moss_highlight_color, float(settings.moss_highlight_strength) / 100.0),
	]))
	var grid := source.grid_size()
	var dimensions: Vector3i = settings.dimensions
	var patches := _noise(settings.surface_seed, settings.surface_patch_size)
	var islands := _noise(settings.surface_seed ^ 0x4b1d, settings.moss_patch_size)
	var waves := _noise(settings.surface_seed ^ 0x17a3, 24)
	var random := RandomNumberGenerator.new()
	random.seed = settings.surface_seed
	var offset := Vector3(random.randf_range(-100, 100), random.randf_range(-100, 100), random.randf_range(-100, 100))
	var center := Vector3(dimensions - Vector3i.ONE) * 0.5
	var angle := deg_to_rad(float(settings.mineral_angle))
	var normal := Vector3.UP
	if settings.mineral_direction != 0:
		normal = Vector3(cos(angle), 0 if settings.mineral_direction == 1 else 0.8, sin(angle)).normalized()
	var vein_offset := random.randf_range(-0.15, 0.15) * float(mini(dimensions.x, dimensions.z))
	var layer_offset := random.randf_range(0, float(settings.mineral_spacing))
	var vein := {}
	if settings.mineral_pattern == 2 and settings.mineral_vein_style == 1:
		vein = _vein_frame(normal, random, dimensions, settings)
	var top := PackedInt32Array()
	top.resize(grid.x * grid.z)
	top.fill(-1)
	if settings.moss_coverage > 0:
		for y in dimensions.y:
			for z in dimensions.z:
				for x in dimensions.x:
					var cell := Vector3i(x, y, z) + origin
					if source.voxels[Model.index_of(cell, grid)] != 0: top[cell.x + cell.z * grid.x] = y
	for y in dimensions.y:
		for z in dimensions.z:
			for x in dimensions.x:
				var cell := Vector3i(x, y, z) + origin
				var index := Model.index_of(cell, grid)
				if source.voxels[index] == 0: continue
				# Two-voxel blocks and one octave: broad masses, no salt-and-pepper detail.
				var point := Vector3(x / 2 * 2, y / 2 * 2, z / 2 * 2)
				var sample := point + offset
				var patch := patches.get_noise_3dv(sample)
				var tint := 1
				if settings.surface_strength > 0:
					if patch < -0.14: tint = 2
					elif patch > 0.14: tint = 3
				if settings.mineral_pattern != 0 and settings.mineral_strength > 0:
					# Continuous 3D bands cross face boundaries without UV seams.
					var along := (Vector3(x, y, z) - center).dot(normal) + waves.get_noise_3dv(sample) * 1.5
					var distance := absf(along - vein_offset)
					var width := float(settings.mineral_width)
					if settings.mineral_pattern == 1:
						var spacing := float(settings.mineral_spacing)
						distance = absf(fposmod(along + layer_offset + spacing * 0.5, spacing) - spacing * 0.5)
						width = minf(width, spacing * 0.5)
					if not vein.is_empty():
						if _vein_contains(Vector3(x, y, z) - center, vein_offset, vein): tint = 4
					elif distance <= width * 0.5: tint = 4
				if settings.moss_coverage > 0 and y > 0 and _surface(source.voxels, cell, grid):
					var column_top := top[cell.x + cell.z * grid.x]
					var depth := float(dimensions.y) * 0.45 * float(settings.moss_drape) / 100.0
					var mask := islands.get_noise_2d(sample.x, sample.z)
					var threshold := lerpf(0.38, -0.55, float(settings.moss_coverage) / 100.0)
					if column_top - y <= depth and y >= int(float(dimensions.y) * 0.3) and mask >= threshold:
						tint = 6 if settings.moss_highlight_strength > 0 and mask > threshold + 0.3 else 5
				source.voxels[index] = tint


static func _vein_frame(normal: Vector3, random: RandomNumberGenerator, dimensions: Vector3i, settings: Dictionary) -> Dictionary:
	var reference := Vector3.UP if absf(normal.y) < 0.85 else Vector3.FORWARD
	var u := normal.cross(reference).normalized()
	var v := normal.cross(u).normalized()
	var span := float(maxi(dimensions.x, maxi(dimensions.y, dimensions.z)))
	var irregularity := float(settings.mineral_irregularity) / 100.0
	var pockets: Array[Vector3] = []
	for index in 3:
		pockets.append(Vector3(random.randf_range(-span * 0.35, span * 0.35), random.randf_range(-span * 0.35, span * 0.35), random.randf_range(2.5, 4.5)))
	# Branch count must not move the main vein or its width inclusions.
	var phase := random.randf_range(0, TAU)
	var branches: Array[Vector3] = []
	var branching := float(settings.mineral_branching) / 100.0
	for index in ceili(float(settings.mineral_branching) / 50.0):
		# Each short tapered offshoot joins the main crack at its start.
		branches.append(Vector3(random.randf_range(-span * 0.3, span * 0.1), span * random.randf_range(0.2, 0.35) * lerpf(0.4, 1.0, branching), (1 if index == 0 else -1) * random.randf_range(0.45, 0.8)))
	return {"normal": normal, "u": u, "v": v, "frequency": TAU / maxf(12, span * 0.85),
		"phase": phase, "amplitude": span * 0.13 * irregularity,
		"width": float(settings.mineral_width), "irregularity": irregularity,
		"pockets": pockets, "branches": branches}


static func _vein_curve(u: float, v: float, frame: Dictionary) -> float:
	return (sin(u * frame.frequency + frame.phase) + sin(v * frame.frequency * 0.8 + frame.phase * 1.7) * 0.35) * frame.amplitude


static func _vein_contains(point: Vector3, offset: float, frame: Dictionary) -> bool:
	var u := point.dot(frame.u)
	var v := point.dot(frame.v)
	var across := point.dot(frame.normal) - offset
	var curve := _vein_curve(u, v, frame)
	var width: float = frame.width * (1.0 + sin(u * frame.frequency * 1.4 + frame.phase) * 0.5 * frame.irregularity)
	for pocket in frame.pockets:
		var radius: float = pocket.z
		var distance := Vector2(u - pocket.x, v - pocket.y).length_squared()
		width += exp(-distance / (radius * radius)) * frame.width * 1.8 * frame.irregularity
	if absf(across - curve) <= width * 0.5: return true
	for branch in frame.branches:
		var t: float = (u - branch.x) / branch.y
		if t < 0 or t > 1: continue
		var branch_curve: float = curve + (u - branch.x) * branch.z
		if absf(across - branch_curve) <= frame.width * 0.5 * (1.0 - t * 0.85): return true
	return false


static func _surface(voxels: PackedByteArray, cell: Vector3i, grid: Vector3i) -> bool:
	for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
		var next: Vector3i = cell + direction
		if next.x < 0 or next.y < 0 or next.z < 0 or next.x >= grid.x or next.y >= grid.y or next.z >= grid.z: return true
		if voxels[Model.index_of(next, grid)] == 0: return true
	return false
