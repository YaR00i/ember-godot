@tool
extends RefCounted
## Pure deterministic provider for one connected, groundable voxel rock.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Geometry = preload("res://addons/ember_import/ember_voxel_generator_geometry.gd")
const Surface = preload("res://addons/ember_import/ember_voxel_rock_surface.gd")

const MIN_DIMENSION := 3
const MAX_DIMENSION := 32
const OBJECT_MAX_DIMENSION := 256


static func defaults() -> Dictionary:
	var result := {
		"generation_version": 1,
		"rock_type": 0,
		"stone_color": Color("343b42"),
		"dimensions": Vector3i(10, 7, 9),
		"roughness": 35,
		"chips": 25,
		"density": 16,
		# One/no size variation preserves recipes saved before variant sets existed.
		"variant_count": 1,
		"size_variation": 0,
		"crystal_count": 4,
		"crystal_width": 7,
		"crystal_variation": 65,
		"crystal_lean": 45,
		"crystal_tip": 1,
		"crystal_base_size": 35,
		# Missing key keeps the first crystal recipes visually unchanged.
		"crystal_base_enabled": true,
	}
	result.merge(Surface.normalized({}))
	return result


static func normalize(parameters: Dictionary) -> Dictionary:
	var fallback := defaults()
	var dimensions: Variant = parameters.get("dimensions", fallback.dimensions)
	if not dimensions is Vector3i:
		dimensions = fallback.dimensions
	var raw_dimensions: Vector3i = dimensions
	var version := clampi(int(parameters.get("generation_version", 1)), 1, 2)
	var limits := dimension_limits(parameters)
	var result := {
		"generation_version": version,
		"rock_type": clampi(int(parameters.get("rock_type", 0)), 0, 4),
		"stone_color": Color(parameters.get("stone_color", fallback.stone_color), 1.0) if parameters.get("stone_color", fallback.stone_color) is Color else fallback.stone_color,
		"dimensions": Vector3i(
			clampi(raw_dimensions.x, MIN_DIMENSION, limits.x),
			clampi(raw_dimensions.y, MIN_DIMENSION, limits.y),
			clampi(raw_dimensions.z, MIN_DIMENSION, limits.z)
		),
		"roughness": clampi(int(parameters.get("roughness", fallback.roughness)), 0, 100),
		"chips": clampi(int(parameters.get("chips", fallback.chips)), 0, 100),
		"crystal_count": clampi(int(parameters.get("crystal_count", fallback.crystal_count)), 1, 8),
		"crystal_width": clampi(int(parameters.get("crystal_width", fallback.crystal_width)), 2, 20),
		"crystal_variation": clampi(int(parameters.get("crystal_variation", fallback.crystal_variation)), 0, 100),
		"crystal_lean": clampi(int(parameters.get("crystal_lean", fallback.crystal_lean)), 0, 100),
		"crystal_tip": clampi(int(parameters.get("crystal_tip", fallback.crystal_tip)), 0, 1),
		"crystal_base_size": clampi(int(parameters.get("crystal_base_size", fallback.crystal_base_size)), 0, 100),
		"crystal_base_enabled": bool(parameters.get("crystal_base_enabled", true)),
		"density": 32 if int(parameters.get("density", fallback.density)) == 32 else 16,
		"variant_count": clampi(
			int(parameters.get("variant_count", fallback.variant_count)), 1, 8
		),
		"size_variation": clampi(
			int(parameters.get("size_variation", fallback.size_variation)), 0, 50
		),
	}
	result.merge(Surface.normalized(parameters))
	return result


static func dimension_limits(parameters: Dictionary) -> Vector3i:
	if int(parameters.get("generation_version", 1)) < 2:
		return Vector3i.ONE * MAX_DIMENSION
	var density := 32 if int(parameters.get("density", 16)) == 32 else 16
	return Vector3i(OBJECT_MAX_DIMENSION, 8 * density, OBJECT_MAX_DIMENSION)


static func variant_parameters(settings: Dictionary, random: RandomNumberGenerator) -> Dictionary:
	var result := normalize(settings)
	var dimensions: Vector3i = result.dimensions
	var variation := float(result.size_variation) / 100.0
	if variation > 0.0:
		for axis in 3:
			var factor := 1.0 + random.randf_range(-variation, variation)
			dimensions[axis] = clampi(
				roundi(float(dimensions[axis]) * factor), MIN_DIMENSION, dimension_limits(result)[axis]
			)
	result.dimensions = dimensions
	return result


static func recommended_spacing(settings: Dictionary) -> int:
	var dimensions: Vector3i = normalize(settings).dimensions
	return maxi(2, roundi(float(maxi(dimensions.x, dimensions.z)) * 0.75))


static func build(
	parameters: Dictionary,
	seed: int,
	color: Color,
	material: Dictionary,
	title: String,
	model_id := "generated_rock",
) -> Dictionary:
	var settings := normalize(parameters)
	if int(settings.generation_version) == 2:
		return _build_object(settings, seed, material, title, model_id)
	var dimensions: Vector3i = settings.dimensions
	var built := Shapes.build(
		"empty", dimensions, int(settings.density), Color(color, 1.0), model_id, title
	)
	if not built.get("ok", false):
		return {"error": built.get("error", "Не удалось создать сетку камня.")}
	var source: EmberVoxelModelResource = built.source
	source.tags = PackedStringArray(["stamp", "generated", "rock"])
	source.material = material.duplicate(true)
	var grid := source.grid_size()
	var origin: Vector3i = built.origin
	var center := Vector3(dimensions - Vector3i.ONE) * 0.5
	var radii := Vector3(dimensions) * 0.5
	var noise := FastNoiseLite.new()
	noise.seed = maxi(0, seed)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var smallest_dimension := mini(dimensions.x, mini(dimensions.y, dimensions.z))
	noise.frequency = 1.0 / maxf(2.0, float(smallest_dimension) * 0.65)
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 104729
	var chip_strength := float(settings.chips) / 100.0
	var chip_planes: Array[Dictionary] = []
	var chip_count := ceili(chip_strength * 4.0)
	for _index in chip_count:
		var normal := Vector3(
			random.randf_range(-1.0, 1.0),
			random.randf_range(-0.45, 1.0),
			random.randf_range(-1.0, 1.0)
		)
		if normal.length_squared() < 0.01:
			normal = Vector3(1.0, 0.35, 0.0)
		chip_planes.append({
			"normal": normal.normalized(),
			"threshold": lerpf(0.82, 0.50, chip_strength) + random.randf_range(-0.04, 0.04),
		})
	var roughness := float(settings.roughness) / 100.0
	for y in dimensions.y:
		for z in dimensions.z:
			for x in dimensions.x:
				var local := Vector3(x, y, z)
				var normalized := Vector3(
					(local.x - center.x) / radii.x,
					(local.y - center.y) / radii.y,
					(local.z - center.z) / radii.z
				)
				var radius := normalized.length()
				var surface := 1.0 + noise.get_noise_3d(local.x, local.y, local.z) * roughness * 0.24
				var occupied := radius <= surface
				if occupied:
					for plane in chip_planes:
						if normalized.dot(plane.normal) > float(plane.threshold):
							occupied = false
							break
				# A compact base keeps every generated rock stable on a surface.
				if y == 0 and Vector2(normalized.x, normalized.z).length() <= 0.48:
					occupied = true
				if occupied:
					var cell := Vector3i(x + origin.x, y, z + origin.z)
					source.voxels[Model.index_of(cell, grid)] = 1
	Geometry.keep_largest_component(source)
	if source.voxels.count(0) == source.voxels.size():
		return {"error": "Параметры создали пустой камень. Уменьшите сколы."}
	return {"geometry": source, "parameters": settings}


static func _build_object(settings: Dictionary, seed: int, material: Dictionary, title: String, model_id: String) -> Dictionary:
	if int(settings.rock_type) >= 3: return _build_cluster(settings, seed, material, title, model_id)
	var dimensions: Vector3i = settings.dimensions
	var built := Shapes.build("empty", dimensions, settings.density, settings.stone_color, model_id, title)
	if not built.get("ok", false): return {"error": built.get("error", "Не удалось создать камень.")}
	var source: EmberVoxelModelResource = built.source
	source.tags = PackedStringArray(["generated", "rock"])
	source.material = material.duplicate(true)
	var grid := source.grid_size()
	var origin: Vector3i = built.origin
	var noise := FastNoiseLite.new()
	noise.seed = maxi(0, seed)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / maxf(3.0, float(mini(dimensions.x, dimensions.z)) * 0.45)
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 104729
	var type := int(settings.rock_type)
	var rough := float(settings.roughness) / 100.0
	var chips := float(settings.chips) / 100.0
	var lean := Vector2(random.randf_range(-0.13, 0.13), random.randf_range(-0.13, 0.13))
	var width := Vector2(random.randf_range(0.90, 1.06), random.randf_range(0.90, 1.06))
	var facets: Array[Dictionary] = []
	if type != 0:
		# Convex planes give actual broad faces, not a noisy ball painted like a rock.
		var count := 7 if type == 2 else 11
		var phase := random.randf_range(0, TAU)
		for index in count:
			var angle := phase + TAU * float(index) / count + random.randf_range(-0.15, 0.15)
			facets.append({"normal": Vector3(cos(angle), random.randf_range(-0.12, 0.12) if type == 2 else random.randf_range(-0.7, 0.8), sin(angle)).normalized(), "threshold": random.randf_range(0.73, 0.97)})
	for index in ceili(chips * 5):
		facets.append({"normal": Vector3(random.randf_range(-1,1), random.randf_range(0.1,1), random.randf_range(-1,1)).normalized(), "threshold": lerpf(0.94, 0.57, chips) + random.randf_range(-0.05,0.05)})
	for y in dimensions.y:
		for z in dimensions.z:
			for x in dimensions.x:
				var height := float(y) / float(dimensions.y - 1)
				var p := Vector3(
					(float(x) - float(dimensions.x - 1) * 0.5) / (float(dimensions.x) * 0.5) / width.x - lean.x * height,
					lerpf(-0.68, 1.0, height) if type == 0 else lerpf(-0.8, 1.0, height),
					(float(z) - float(dimensions.z - 1) * 0.5) / (float(dimensions.z) * 0.5) / width.y - lean.y * height)
				var perturb := noise.get_noise_3d(x, y, z) * rough * (0.24 if type == 0 else 0.12)
				var occupied := p.length() <= 1.0 + perturb if type == 0 else maxf(absf(p.x), maxf(absf(p.y), absf(p.z))) <= 1.0 + perturb
				if occupied:
					for plane in facets:
						if p.dot(plane.normal) > float(plane.threshold) + perturb:
							occupied = false
							break
				if occupied:
					source.voxels[Model.index_of(Vector3i(x + origin.x, y, z + origin.z), grid)] = 1
	Geometry.keep_largest_component(source)
	if source.voxels.count(0) == source.voxels.size(): return {"error": "Параметры создали пустой камень."}
	Surface.apply(source, settings, origin)
	return {"geometry": source, "parameters": settings}


## Oriented convex prisms share a solid footing. No loose specks or mesh-only shards.
static func _build_cluster(settings: Dictionary, seed: int, material: Dictionary, title: String, model_id: String) -> Dictionary:
	var dimensions: Vector3i = settings.dimensions
	var built := Shapes.build("empty", dimensions, settings.density, settings.stone_color, model_id, title)
	if not built.get("ok", false): return {"error": built.get("error", "Не удалось создать сросток.")}
	var source: EmberVoxelModelResource = built.source
	source.tags = PackedStringArray(["generated", "rock", "crystal" if settings.rock_type == 3 else "ice"])
	source.material = material.duplicate(true)
	var grid := source.grid_size()
	var origin: Vector3i = built.origin
	var center := Vector3(dimensions - Vector3i.ONE) * 0.5
	var base_size := float(settings.crystal_base_size) / 100.0
	var base_height := maxf(1, float(dimensions.y - 1) * lerpf(0.04, 0.22, base_size))
	var base_radius := Vector2(dimensions.x, dimensions.z) * lerpf(0.37, 0.49, base_size)
	for y in range(mini(dimensions.y, ceili(base_height) + 1) if settings.crystal_base_enabled else 0):
		for z in dimensions.z:
			for x in dimensions.x:
				var radial := Vector2((x - center.x) / base_radius.x, (z - center.z) / base_radius.y)
				if radial.length_squared() + pow(float(y) / base_height, 2) * 0.35 <= 1.0:
					source.voxels[Model.index_of(Vector3i(x, y, z) + origin, grid)] = 1
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 130363
	var count := int(settings.crystal_count)
	var variation := float(settings.crystal_variation) / 100.0
	var lean := float(settings.crystal_lean) / 100.0
	var phase := random.randf_range(0, TAU)
	for index in count:
		# Fixed draws per prism: changing variation/lean cannot re-roll neighbours.
		var angle := phase + TAU * float(index) / maxi(1, count - 1) + random.randf_range(-0.3, 0.3)
		var position_factor := random.randf_range(0.65, 0.95) if index > 0 else random.randf_range(0.0, 0.18)
		var size_random := random.randf_range(-0.18, 0.18)
		var height_random := random.randf_range(-0.12, 0.12)
		var drift_angle := angle + random.randf_range(-0.6, 0.6)
		var drift_strength := random.randf_range(0.15, 0.42)
		var radius := minf(float(settings.crystal_width) * 0.5, float(mini(dimensions.x, dimensions.z)) * 0.24)
		var rank := float(index) / float(maxi(1, count - 1))
		radius *= maxf(0.45, 1.0 + (size_random - rank * 0.35) * variation)
		var radius_v := radius * (1.0 if settings.rock_type == 3 else random.randf_range(0.65, 0.95))
		var drift := Vector2(cos(drift_angle) * dimensions.x, sin(drift_angle) * dimensions.z) * drift_strength * lean
		var travel := Vector2(maxf(0, float(dimensions.x) * 0.5 - radius * 1.5 - absf(drift.x)), maxf(0, float(dimensions.z) * 0.5 - radius * 1.5 - absf(drift.y)))
		var foot := Vector3(center.x + cos(angle) * travel.x * position_factor, 0, center.z + sin(angle) * travel.y * position_factor)
		var height := maxf(1.0, float(dimensions.y - 1) * clampf(0.96 - rank * variation * 0.6 + height_random * variation, 0.22, 1.0))
		var axis := Vector3(drift.x, height, drift.y)
		var length := axis.length()
		axis /= length
		var u := axis.cross(Vector3.FORWARD).normalized()
		var v := axis.cross(u).normalized()
		var rotation := random.randf_range(0, TAU)
		var planes: Array[Vector2] = []
		var faces := 6 if settings.rock_type == 3 else 4
		for face in faces: planes.append(Vector2(cos(rotation + TAU * face / faces), sin(rotation + TAU * face / faces)))
		var top_slope := Vector2(random.randf_range(-0.3, 0.3), random.randf_range(-0.3, 0.3))
		var chip := Vector2(cos(rotation + 0.6), sin(rotation + 0.6))
		var frame := {"foot": foot, "axis": axis, "u": u, "v": v, "length": length,
			"radius": Vector2(maxf(0.65, radius), maxf(0.65, radius_v)), "planes": planes,
			"top_slope": top_slope, "chip": chip, "phase": rotation}
		var end := foot + axis * length
		var extent := Vector3.ONE * (maxf(radius, radius_v) * 1.8 + 1)
		var low := Vector3i((foot.min(end) - extent).floor()).max(Vector3i.ZERO)
		var high := Vector3i((foot.max(end) + extent).ceil()).min(dimensions - Vector3i.ONE)
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				for x in range(low.x, high.x + 1):
					if _prism_contains(Vector3(x, y, z), frame, settings):
						source.voxels[Model.index_of(Vector3i(x, y, z) + origin, grid)] = 1
	# Without a footing, separate prisms are intentional parts of one object.
	if settings.crystal_base_enabled: Geometry.keep_largest_component(source)
	if source.voxels.count(0) == source.voxels.size(): return {"error": "Параметры создали пустой сросток."}
	Surface.apply(source, settings, origin)
	return {"geometry": source, "parameters": settings}


static func _prism_contains(point: Vector3, frame: Dictionary, settings: Dictionary) -> bool:
	var delta: Vector3 = point - frame.foot
	var t: float = delta.dot(frame.axis) / frame.length
	if t < -0.25 or t > 1.2: return false
	var radial: Vector2 = Vector2(delta.dot(frame.u), delta.dot(frame.v)) / frame.radius
	if int(settings.crystal_tip) == 1:
		if t > 1: return false
		var taper := maxf(0.06, 1.0 - maxf(0, t - 0.68) / 0.32)
		radial /= taper
	elif t > 1.0 + radial.dot(frame.top_slope) * 0.2: return false
	var rough := float(settings.roughness) / 100.0
	var width: float = 1.0 + sin(t * TAU + frame.phase) * rough * 0.1
	for plane in frame.planes:
		if radial.dot(plane) > width: return false
	# One broad clipped corner instead of a high-frequency chipped surface.
	if settings.chips > 0 and radial.dot(frame.chip) + t * 0.8 > lerpf(1.65, 1.1, float(settings.chips) / 100.0): return false
	return true


static func cluster_fields() -> Array[Dictionary]:
	return [
		{"key": "crystal_count", "title": "Количество крупных элементов", "min": 1, "max": 8, "section": "Сросток / лёд", "heading": true},
		{"key": "crystal_width", "title": "Толщина элементов · vox", "min": 2, "max": 20, "section": "Сросток / лёд"},
		{"key": "crystal_variation", "title": "Разброс высоты и толщины · %", "min": 0, "max": 100, "section": "Сросток / лёд"},
		{"key": "crystal_lean", "title": "Наклон элементов · %", "min": 0, "max": 100, "section": "Сросток / лёд"},
		{"key": "crystal_tip", "title": "Форма вершины", "options": ["Обломанная", "Острая"], "section": "Сросток / лёд"},
		{"key": "crystal_base_enabled", "title": "Общее основание", "type": "bool", "section": "Сросток / лёд"},
		{"key": "crystal_base_size", "title": "Размер общего основания · %", "min": 0, "max": 100, "section": "Сросток / лёд"},
	]
