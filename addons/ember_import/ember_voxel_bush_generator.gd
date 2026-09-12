@tool
extends RefCounted
## Pure deterministic provider for compact connected shrubs with stems and foliage.

const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Geometry = preload("res://addons/ember_import/ember_voxel_generator_geometry.gd")

const MIN_HEIGHT := 4
const MAX_HEIGHT := 24
const MIN_SPREAD := 2
const MAX_SPREAD := 12


static func defaults() -> Dictionary:
	return {
		"height": 10,
		"spread_radius": 5,
		"stem_count": 5,
		"foliage_density": 65,
		"roughness": 35,
		"density": 16,
		"stem_color": Color("755039"),
		"foliage_color": Color("568f4d"),
		"variant_count": 4,
		"size_variation": 20,
	}


static func normalize(parameters: Dictionary) -> Dictionary:
	var fallback := defaults()
	var height := clampi(int(parameters.get("height", fallback.height)), MIN_HEIGHT, MAX_HEIGHT)
	var max_spread := mini(MAX_SPREAD, maxi(MIN_SPREAD, height - 1))
	var stem_color: Variant = parameters.get("stem_color", fallback.stem_color)
	var foliage_color: Variant = parameters.get("foliage_color", fallback.foliage_color)
	return {
		"height": height,
		"spread_radius": clampi(
			int(parameters.get("spread_radius", fallback.spread_radius)),
			MIN_SPREAD,
			max_spread,
		),
		"stem_count": clampi(int(parameters.get("stem_count", fallback.stem_count)), 1, 12),
		"foliage_density": clampi(
			int(parameters.get("foliage_density", fallback.foliage_density)), 20, 100
		),
		"roughness": clampi(int(parameters.get("roughness", fallback.roughness)), 0, 100),
		"density": 32 if int(parameters.get("density", fallback.density)) == 32 else 16,
		"stem_color": Color(stem_color if stem_color is Color else fallback.stem_color, 1.0),
		"foliage_color": Color(
			foliage_color if foliage_color is Color else fallback.foliage_color, 1.0
		),
		"variant_count": clampi(int(parameters.get("variant_count", fallback.variant_count)), 1, 8),
		"size_variation": clampi(
			int(parameters.get("size_variation", fallback.size_variation)), 0, 50
		),
	}


static func variant_parameters(settings: Dictionary, random: RandomNumberGenerator) -> Dictionary:
	var result := normalize(settings)
	var variation := float(result.size_variation) / 100.0
	if variation > 0.0:
		result.height = clampi(
			roundi(float(result.height) * (1.0 + random.randf_range(-variation, variation))),
			MIN_HEIGHT,
			MAX_HEIGHT,
		)
		result.spread_radius = clampi(
			roundi(
				float(result.spread_radius)
				* (1.0 + random.randf_range(-variation, variation))
			),
			MIN_SPREAD,
			mini(MAX_SPREAD, maxi(MIN_SPREAD, int(result.height) - 1)),
		)
	result.stem_count = clampi(int(result.stem_count) + random.randi_range(-2, 2), 1, 12)
	result.foliage_density = clampi(
		int(result.foliage_density) + random.randi_range(-12, 12), 20, 100
	)
	result.roughness = clampi(int(result.roughness) + random.randi_range(-12, 12), 0, 100)
	return result


static func recommended_spacing(settings: Dictionary) -> int:
	return maxi(3, roundi(float(normalize(settings).spread_radius) * 1.55))


static func build(
	parameters: Dictionary,
	seed: int,
	_fallback_color: Color,
	material: Dictionary,
	title: String,
	model_id := "generated_bush",
) -> Dictionary:
	var settings := normalize(parameters)
	var height := int(settings.height)
	var spread := int(settings.spread_radius)
	var footprint := mini(32, spread * 2 + 5)
	var built := Shapes.build(
		"empty",
		Vector3i(footprint, height, footprint),
		int(settings.density),
		settings.foliage_color,
		model_id,
		title,
	)
	if not built.get("ok", false):
		return {"error": built.get("error", "Не удалось создать сетку куста.")}
	var source: EmberVoxelModelResource = built.source
	source.tags = PackedStringArray(["stamp", "generated", "bush"])
	source.material = material.duplicate(true)
	source.palette = PackedColorArray([
		Color.TRANSPARENT, settings.stem_color, settings.foliage_color,
	])
	var grid := source.grid_size()
	var base := Vector3(float(grid.x / 2), 0.0, float(grid.z / 2))
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 86028121
	var stem_count := int(settings.stem_count)
	var foliage_density := float(settings.foliage_density) / 100.0
	var endpoints: Array[Vector3] = []
	var stems: Array[Dictionary] = []
	for stem_index in stem_count:
		var angle := (
			TAU * float(stem_index) / float(maxi(1, stem_count))
			+ random.randf_range(-0.58, 0.58)
		)
		var reach := float(spread) * random.randf_range(0.32, 0.88)
		var endpoint := Vector3(
			base.x + cos(angle) * reach,
			clampf(
				float(height) * random.randf_range(0.28, 0.56),
				2.0,
				float(height - 1),
			),
			base.z + sin(angle) * reach,
		)
		endpoint.x = clampf(endpoint.x, 1.0, float(grid.x - 2))
		endpoint.z = clampf(endpoint.z, 1.0, float(grid.z - 2))
		stems.append({"from": base, "to": endpoint})
		endpoints.append(endpoint)
	# One central cluster makes sparse recipes read as a single shrub instead of a bouquet.
	endpoints.append(Vector3(base.x, float(height) * 0.45, base.z))
	var extra_clusters := roundi(foliage_density * float(stem_count) * 0.65)
	for _index in extra_clusters:
		var origin: Vector3 = endpoints[random.randi_range(0, endpoints.size() - 1)]
		var angle := random.randf_range(0.0, TAU)
		endpoints.append(
			origin
			+ Vector3(
				cos(angle) * random.randf_range(0.5, maxf(0.7, float(spread) * 0.24)),
				random.randf_range(-0.7, 0.7),
				sin(angle) * random.randf_range(0.5, maxf(0.7, float(spread) * 0.24)),
			)
		)
	var noise := FastNoiseLite.new()
	noise.seed = maxi(0, seed) + 104395303
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.19
	var cluster_radius := clampf(
		float(spread) * lerpf(0.42, 0.58, foliage_density), 1.45, 5.2
	)
	_paint_foliage(
		source,
		Vector3(base.x, maxf(1.1, cluster_radius * 0.62), base.z),
		Vector3(
			maxf(cluster_radius, float(spread) * 0.68),
			cluster_radius * 0.72,
			maxf(cluster_radius, float(spread) * 0.68),
		),
		float(settings.roughness) / 100.0,
		noise,
	)
	for endpoint in endpoints:
		_paint_foliage(
			source,
			endpoint,
			Vector3(
				cluster_radius * random.randf_range(0.82, 1.12),
				cluster_radius * random.randf_range(0.62, 0.88),
				cluster_radius * random.randf_range(0.82, 1.12),
			),
			float(settings.roughness) / 100.0,
			noise,
		)
	for stem: Dictionary in stems:
		_paint_connected_stem(source, stem.from, stem.to)
	Geometry.paint_sphere(source, base, 0.82, 1)
	Geometry.keep_largest_component(source)
	if source.voxels.count(1) == 0 or source.voxels.count(2) == 0:
		return {"error": "Параметры не создали связный куст со стеблями и листвой."}
	return {"geometry": source, "parameters": settings}


static func _paint_connected_stem(
	source: EmberVoxelModelResource,
	from: Vector3,
	to: Vector3,
) -> void:
	var grid := source.grid_size()
	var cell := Vector3i(from.round())
	var target := Vector3i(to.round())
	var total := Vector3i(
		absi(target.x - cell.x), absi(target.y - cell.y), absi(target.z - cell.z)
	)
	var moved := Vector3i.ZERO
	while true:
		source.voxels[Geometry.Model.index_of(cell, grid)] = 1
		if cell == target:
			break
		var remaining := total - moved
		var axis := 1
		if remaining.x > remaining.y and remaining.x >= remaining.z:
			axis = 0
		elif remaining.z > remaining.y and remaining.z > remaining.x:
			axis = 2
		match axis:
			0:
				cell.x += signi(target.x - cell.x)
				moved.x += 1
			1:
				cell.y += signi(target.y - cell.y)
				moved.y += 1
			2:
				cell.z += signi(target.z - cell.z)
				moved.z += 1


static func _paint_foliage(
	source: EmberVoxelModelResource,
	center: Vector3,
	radii: Vector3,
	roughness: float,
	noise: FastNoiseLite,
) -> void:
	var grid := source.grid_size()
	var low := Vector3i((center - radii).floor())
	var high := Vector3i((center + radii).ceil())
	for y in range(maxi(0, low.y), mini(grid.y - 1, high.y) + 1):
		for z in range(maxi(0, low.z), mini(grid.z - 1, high.z) + 1):
			for x in range(maxi(0, low.x), mini(grid.x - 1, high.x) + 1):
				var local := Vector3(x, y, z) - center
				var normalized := Vector3(
					local.x / maxf(0.5, radii.x),
					local.y / maxf(0.5, radii.y),
					local.z / maxf(0.5, radii.z),
				)
				var surface := 1.0 + noise.get_noise_3d(x, y, z) * roughness * 0.30
				if normalized.length() <= surface:
					source.voxels[Geometry.Model.index_of(Vector3i(x, y, z), grid)] = 2
