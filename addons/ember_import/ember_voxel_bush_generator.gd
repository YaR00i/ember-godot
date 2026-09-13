@tool
extends RefCounted
## Pure deterministic provider for compact connected shrubs with stems and foliage.

const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Geometry = preload("res://addons/ember_import/ember_voxel_generator_geometry.gd")
const Foliage = preload("res://addons/ember_import/ember_voxel_foliage_pattern.gd")

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
	if int(parameters.get("generation_version", 1)) >= 2:
		return _normalize_object(parameters)
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
	if int(result.get("generation_version", 1)) >= 2:
		var variation := float(result.size_variation) / 100.0
		result.height = roundi(float(result.height) * random.randf_range(1.0 - variation, 1.0 + variation))
		result.spread_radius = roundi(float(result.spread_radius) * random.randf_range(1.0 - variation, 1.0 + variation))
		return normalize(result)
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
	if int(settings.get("generation_version", 1)) >= 2:
		return _build_object(settings, seed, material, title, model_id)
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


static func _normalize_object(parameters: Dictionary) -> Dictionary:
	# Missing version still routes to the frozen compact stamp algorithm above.
	var result := normalize({})
	result.merge(parameters, true)
	result.generation_version = clampi(int(result.generation_version), 2, 6)
	result.height = clampi(int(result.height), 8, 96)
	result.spread_radius = clampi(int(result.spread_radius), 4, 30)
	result.stem_count = clampi(int(result.stem_count), 3, 12)
	result.foliage_density = clampi(int(result.foliage_density), 20, 100)
	result.roughness = clampi(int(result.roughness), 0, 100)
	result.density = 32 if int(result.density) == 32 else 16
	result.variant_count = clampi(int(result.variant_count), 1, 8)
	result.size_variation = clampi(int(result.size_variation), 0, 50)
	result.bush_type = clampi(int(result.get("bush_type", 0)), 0, 2)
	if int(result.generation_version) == 5 and int(result.bush_type) != 0:
		result.generation_version = 2
		result.erase("base_height")
	if int(result.generation_version) >= 5:
		result.base_height = clampi(int(result.get("base_height", 2)), 0, 32)
		result.stem_count = clampi(int(parameters.get("stem_count", 5)), 1, 12)
	result.foliage_style = 3 if int(result.get("foliage_style", 1)) == 3 else 1
	for key in ["structure_diversity", "cluster_flatten", "foliage_detail", "foliage_pattern_strength"]:
		result[key] = clampi(int(result.get(key, 60 if key != "cluster_flatten" else 20)), 0, 100)
	for key in ["stem_color", "foliage_color"]:
		var value: Variant = result[key]
		result[key] = _opaque_color(value, defaults()[key])
	for key in ["foliage_highlight_color", "foliage_shadow_color"]:
		var fallback: Color = result.foliage_color.lightened(0.24) if key == "foliage_highlight_color" else result.foliage_color.darkened(0.24)
		var value: Variant = result.get(key, fallback)
		result[key] = _opaque_color(value, fallback)
	return result


static func _opaque_color(value: Variant, fallback: Color) -> Color:
	if not value is Color: return fallback
	if not is_finite(value.r) or not is_finite(value.g) or not is_finite(value.b): return fallback
	return Color(clampf(value.r, 0, 1), clampf(value.g, 0, 1), clampf(value.b, 0, 1), 1)


static func _build_object(settings: Dictionary, seed: int, material: Dictionary,
	title: String, model_id: String) -> Dictionary:
	var height := int(settings.height)
	var spread := float(settings.spread_radius)
	var footprint := int(spread) * 2 + 4
	var storage_height := height + (int(settings.base_height) if int(settings.generation_version) >= 5 else 0)
	var built := Shapes.build("empty", Vector3i(footprint, storage_height, footprint),
		int(settings.density), settings.foliage_color, model_id, title)
	if not built.get("ok", false): return {"error": built.get("error", "Не удалось создать куст.")}
	var source: EmberVoxelModelResource = built.source
	source.tags = PackedStringArray(["stamp", "generated", "bush"])
	source.material = material.duplicate(true)
	var strength := float(settings.foliage_pattern_strength) / 100.0
	source.palette = PackedColorArray([Color.TRANSPARENT, settings.stem_color,
		settings.foliage_color, settings.foliage_color,
		settings.foliage_color.lerp(settings.foliage_shadow_color, strength),
		settings.foliage_color, settings.foliage_color.lerp(settings.foliage_highlight_color, strength)])
	if int(settings.generation_version) == 6 or (int(settings.generation_version) == 5 and int(settings.bush_type) == 0):
		_paint_cloud_shrub(source, settings, seed)
		return {"geometry": source, "parameters": settings}
	if int(settings.generation_version) == 4 and int(settings.bush_type) == 0:
		_paint_shoot_shrub(source, settings, seed)
		return {"geometry": source, "parameters": settings}
	if int(settings.generation_version) == 3 and int(settings.bush_type) == 0:
		_paint_basic_shrub(source, settings, seed)
		return {"geometry": source, "parameters": settings}
	var grid := source.grid_size()
	var origin := Vector3i((grid.x - footprint) / 2, 0, (grid.z - footprint) / 2)
	var maximum := origin + Vector3i(footprint - 1, height - 1, footprint - 1)
	var base := Vector3(origin) + Vector3(float(footprint - 1) * 0.5, 0, float(footprint - 1) * 0.5)
	var leaves := {}
	var wood := {}
	var stems: Array[Dictionary] = []
	var random := RandomNumberGenerator.new()
	var diversity := float(settings.structure_diversity) / 100.0
	random.seed = maxi(0, seed) + 86028121 if diversity > 0.0 else 86028121
	var flatten := lerpf(1.0, 0.48, float(settings.cluster_flatten) / 100.0)
	var fullness := lerpf(0.64, 1.0, float(settings.foliage_density) / 100.0)
	var kind := int(settings.bush_type)
	var canopy := {"height": height, "foliage_amount": 100, "irregularity": settings.roughness,
		"foliage_detail": 55, "foliage_geometry_detail": 55, "foliage_pattern_version": 2,
		"foliage_cloud_version": 2, "foliage_leaf_accents": 15, "foliage_leaf_size": 3,
		"cloud_roughness": lerpf(0.25, 2.0, float(settings.roughness) / 100.0), "cloud_floor_ratio": 1.0}
	# A broad low core closes the centre; no tree-style exposed single trunk.
	var center := base + Vector3.UP * float(height) * (0.49 if kind == 2 else 0.43)
	var core := Vector3(spread * 0.64, float(height) * (0.32 if kind == 2 else 0.38) * flatten, spread * 0.64) * fullness
	_dress(leaves, wood, center, core, canopy, int(settings.foliage_style), 86028121)
	if kind == 2:
		# Low growth keeps the tall form shrub-like instead of a crown on a bare pole.
		_dress(leaves, wood, base + Vector3.UP * float(height) * 0.23,
			Vector3(spread * 0.55, float(height) * 0.22 * flatten, spread * 0.55) * fullness,
			canopy, int(settings.foliage_style), 86028122)
	var count := int(settings.stem_count)
	var phase := random.randf() * TAU * diversity
	for index in count:
		var angle := phase + TAU * float(index) / count + random.randf_range(-0.38, 0.38) * diversity
		var radial := Vector3(cos(angle), 0, sin(angle))
		var reach := spread * (0.56 if kind == 1 else 0.42) * (1.0 + random.randf_range(-0.35, 0.35) * diversity)
		var rise := float(height) * (0.55 if kind == 2 else 0.42) * (1.0 + random.randf_range(-0.38, 0.38) * diversity)
		var endpoint := base + radial * reach + Vector3.UP * rise
		var root := base + radial * minf(2.0, spread * 0.12)
		stems.append({"from": base, "to": root})
		stems.append({"from": root, "to": endpoint})
		var radius := Vector3(spread * (0.40 if kind == 1 else 0.43),
			float(height) * (0.27 if kind == 2 else 0.31) * flatten, spread * 0.40) * fullness
		radius *= 1.0 + random.randf_range(-0.17, 0.17) * diversity
		_dress(leaves, wood, endpoint, radius, canopy, int(settings.foliage_style), int(random.randi() % 2147483647))
		# Short branch supports stay inside their own mass of greenery.
		stems.append({"from": root.lerp(endpoint, 0.62), "to": endpoint + radial * radius.x * 0.35})
	Foliage.colorize_motifs(leaves, wood, int(settings.foliage_detail), seed)
	for cell: Vector3i in leaves:
		if cell.x >= origin.x and cell.z >= origin.z and cell.x <= maximum.x and cell.z <= maximum.z and cell.y > 0 and cell.y < height:
			source.voxels[Geometry.Model.index_of(cell, grid)] = int(leaves[cell])
	for stem in stems:
		_paint_connected_stem(source, stem.from.clamp(Vector3(origin), Vector3(maximum)),
			stem.to.clamp(Vector3(origin), Vector3(maximum)))
	Geometry.keep_largest_component(source)
	if source.voxels.count(1) == 0 or source.voxels.count(4) + source.voxels.count(5) + source.voxels.count(6) == 0:
		return {"error": "Не удалось создать связный куст со стеблями и листвой."}
	return {"geometry": source, "parameters": settings}


static func _dress(leaves: Dictionary, wood: Dictionary, center: Vector3, radii: Vector3,
	settings: Dictionary, style: int, seed: int) -> void:
	if style == 3: Foliage.paint_clouds(leaves, wood, center, radii, settings, seed)
	else: Foliage.paint(leaves, wood, center, radii, settings, seed)


## Version5: overlapping leaf clouds, not oversized blades on exposed shoots.
## Foliage owns the silhouette; short branching supports stay inside its clouds.
## base_height translates foliage independently of its height and flattening.
static func _paint_cloud_shrub(source: EmberVoxelModelResource, settings: Dictionary, seed: int) -> void:
	var grid := source.grid_size()
	var base := Vector3(float(grid.x - 1) * 0.5, 0, float(grid.z - 1) * 0.5)
	var floor_y := float(settings.base_height)
	var spread := float(settings.spread_radius)
	var height := float(settings.height - 2) * lerpf(1.0, 0.55, float(settings.cluster_flatten) / 100.0)
	var kind := int(settings.bush_type) if int(settings.generation_version) >= 6 else 0
	if kind == 1: height *= 0.72
	var fullness := lerpf(0.74, 1.0, float(settings.foliage_density) / 100.0)
	var diversity := float(settings.structure_diversity) / 100.0
	var random := RandomNumberGenerator.new()
	random.seed = 218371 + (maxi(seed, 0) if diversity > 0 else 0)
	var noise := FastNoiseLite.new()
	noise.seed = int(random.randi())
	noise.frequency = 0.11
	var roughness := lerpf(0.015, 0.16, float(settings.roughness) / 100.0)
	var phase := random.randf_range(-PI, PI) * diversity
	var leaves := {}
	var wood := {}
	var stems: Array[Dictionary] = []
	var center := base + Vector3.UP * (floor_y + height * (0.46 if kind == 2 else (0.35 if kind == 1 else 0.43)))
	var core := Vector3(spread * (0.47 if kind == 2 else (0.66 if kind == 1 else 0.58)),
		height * (0.43 if kind == 2 else (0.31 if kind == 1 else 0.40)), spread * (0.47 if kind == 2 else 0.58))
	Foliage.paint_mass(leaves, wood, center - Vector3.UP * floor_y,
		core * fullness, noise, roughness)
	var count := int(settings.stem_count)
	for index in count:
		var angle := phase + TAU * float(index) / float(count) + random.randf_range(-0.22, 0.22) * diversity
		var radial := Vector3(cos(angle), 0, sin(angle))
		var reach := spread * ((0.30 if kind == 2 else (0.43 if kind == 1 else 0.36)) + random.randf_range(-0.08, 0.08) * diversity)
		var level: float = float([0.40, 0.68, 0.52, 0.30][index % 4]) if kind == 2 else (0.30 if kind == 1 else 0.38)
		var tip := base + radial * reach + Vector3.UP * (floor_y + height * (level + random.randf_range(-0.12, 0.16) * diversity))
		var root := base + radial * minf(1.2, spread * 0.08)
		var elbow := root + radial * reach * 0.65 + Vector3.UP * (floor_y * 0.60 + height * 0.08)
		stems.append({"from": base, "to": root})
		stems.append({"from": root, "to": elbow})
		stems.append({"from": elbow, "to": tip})
		var radii := Vector3(spread * (0.39 + random.randf_range(-0.05, 0.06) * diversity),
			height * ((0.22 if kind == 2 else 0.30) + random.randf_range(-0.05, 0.06) * diversity), spread * 0.40) * fullness
		Foliage.paint_mass(leaves, wood, tip - Vector3.UP * floor_y, radii, noise, roughness)
		# A few nested rounded puffs, never enormous detached leaf blades.
		var puff_count := 3 if int(settings.foliage_style) == 1 else 2
		for puff in puff_count:
			var puff_angle := angle + float(puff - 1) * 0.85
			var offset := Vector3(cos(puff_angle) * radii.x * 0.48,
				radii.y * (0.30 if puff == 1 else -0.12), sin(puff_angle) * radii.z * 0.48)
			Foliage.paint_mass(leaves, wood, tip + offset - Vector3.UP * floor_y,
				radii * (0.55 if int(settings.foliage_style) == 1 else 0.70), noise, roughness)
		var fork := tip + radial.rotated(Vector3.UP, 0.65) * radii.x * 0.32 + Vector3.UP * radii.y * 0.12
		stems.append({"from": elbow.lerp(tip, 0.7), "to": fork})
	Foliage.colorize_motifs(leaves, wood, int(settings.foliage_detail), seed)
	for cell: Vector3i in leaves:
		var placed := cell + Vector3i.UP * int(floor_y)
		if cell.x >= 0 and cell.z >= 0 and cell.x < grid.x and cell.z < grid.z and cell.y >= 1 and placed.y < grid.y:
			source.voxels[Geometry.Model.index_of(placed, grid)] = int(leaves[cell])
	for stem: Dictionary in stems:
		_paint_connected_stem(source, stem.from, stem.to)
	Geometry.keep_largest_component(source)


## Version4 retained for saved recipes: foliage on curved shoots.
static func _paint_shoot_shrub(source: EmberVoxelModelResource, settings: Dictionary, seed: int) -> void:
	var grid := source.grid_size()
	var base := Vector3(float(grid.x - 1) * 0.5, 0, float(grid.z - 1) * 0.5)
	var spread := float(settings.spread_radius)
	var diversity := float(settings.structure_diversity) / 100.0
	var flatten := lerpf(1.0, 0.55, float(settings.cluster_flatten) / 100.0)
	var fullness := lerpf(0.70, 1.0, float(settings.foliage_density) / 100.0)
	var height := float(settings.height - 2) * flatten
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 1498307 if diversity > 0 else 1498307
	var noise := FastNoiseLite.new()
	noise.seed = int(random.randi() % 2147483647)
	noise.frequency = 0.12
	var roughness := lerpf(0.015, 0.12, float(settings.roughness) / 100.0)
	var phase := random.randf_range(-PI, PI) * diversity
	var count := clampi(int(settings.stem_count), 3, 8)
	var leaves := {}
	var wood := {}
	var stems: Array[Dictionary] = []
	for index in count:
		var angle := phase + TAU * float(index) / count + random.randf_range(-0.30, 0.30) * diversity
		var radial := Vector3(cos(angle), 0, sin(angle))
		var tangent := radial.cross(Vector3.UP)
		var reach := spread * (0.45 + random.randf_range(-0.13, 0.13) * diversity)
		var rise: float = height * (float([0.67, 0.88, 0.60, 0.76][index % 4]) + random.randf_range(-0.12, 0.12) * diversity)
		var root := base + radial * spread * 0.12
		var elbow := root + radial * reach * 0.27 + Vector3.UP * rise * 0.40 + tangent * reach * random.randf_range(-0.2, 0.2) * diversity
		var tip := root + radial * reach + Vector3.UP * rise
		stems.append({"from": base, "to": root})
		stems.append({"from": root, "to": elbow})
		stems.append({"from": elbow, "to": tip})
		# Several overlapping small bodies close the middle, never the whole crown.
		Foliage.paint_mass(leaves, wood, elbow.lerp(tip, 0.28),
			Vector3(spread * 0.30, height * 0.18, spread * 0.28) * fullness, noise, roughness)
		Foliage.paint_mass(leaves, wood, root.lerp(elbow, 0.85),
			Vector3(spread * 0.22, height * 0.14, spread * 0.22) * fullness, noise, roughness)
		# Three large groups per shoot: outer, ascending and low side growth.
		for group in 3:
			var attachment: Vector3 = elbow.lerp(tip, float([0.78, 0.93, 0.28][group]))
			var direction: Vector3 = (radial.rotated(Vector3.UP, float([-0.42, 0.42, 0.80][group])) * float([0.90, 0.55, 1.0][group])
				+ Vector3.UP * float([0.25, 0.95, -0.05][group]) + tangent * random.randf_range(-0.15, 0.15) * diversity).normalized()
			var length: float = spread * float([0.47, 0.40, 0.40][group]) * fullness * (1.0 + random.randf_range(-0.18, 0.18) * diversity)
			var petiole := attachment + direction * length * 0.10
			stems.append({"from": attachment, "to": petiole})
			if int(settings.foliage_style) == 3:
				Foliage.paint_mass(leaves, wood, petiole + direction * length * 0.30,
					Vector3(length * 0.37, length * 0.25 * flatten, length * 0.37), noise, roughness)
			Foliage.paint_leaf_group(leaves, wood, petiole, direction, length, int(settings.height))
	Foliage.colorize_motifs(leaves, wood, int(settings.foliage_detail), seed)
	for cell: Vector3i in leaves:
		if cell.x >= 0 and cell.z >= 0 and cell.x < grid.x and cell.z < grid.z and cell.y > 0 and cell.y < grid.y:
			source.voxels[Geometry.Model.index_of(cell, grid)] = int(leaves[cell])
	for stem in stems:
		_paint_connected_stem(source, stem.from.clamp(Vector3.ZERO, Vector3(grid - Vector3i.ONE)),
			stem.to.clamp(Vector3.ZERO, Vector3(grid - Vector3i.ONE)))
	Geometry.keep_largest_component(source)


## Version3 base: ground-hugging skirt and distinct unequal upright growths.
## No whole-crown ellipsoid and no tree canopy dressing; motifs remain colour-only.
static func _paint_basic_shrub(source: EmberVoxelModelResource, settings: Dictionary, seed: int) -> void:
	var grid := source.grid_size()
	var base := Vector3(float(grid.x - 1) * 0.5, 0, float(grid.z - 1) * 0.5)
	var diversity := float(settings.structure_diversity) / 100.0
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 1203907 if diversity > 0 else 1203907
	var noise := FastNoiseLite.new()
	noise.seed = int(random.randi() % 2147483647)
	noise.frequency = 0.11
	var spread := float(settings.spread_radius)
	var fullness := lerpf(0.72, 1.0, float(settings.foliage_density) / 100.0)
	var height := float(settings.height - 2) * lerpf(1.0, 0.56, float(settings.cluster_flatten) / 100.0)
	var roughness := lerpf(0.015, 0.12, float(settings.roughness) / 100.0)
	var leaves := {}
	var wood := {}
	var stems: Array[Dictionary] = []
	var count := clampi(roundi(float(settings.stem_count) * 0.66), 3, 5)
	var phase := random.randf_range(-PI, PI) * diversity
	var sizes := [0.64, 0.98, 0.76, 0.56, 0.85]
	# Only the low skirt joins the puffs; it never fills their upper valleys.
	_paint_shrub_dome(leaves, base + Vector3.UP, Vector3(spread * 0.54, height * 0.28, spread * 0.50) * fullness,
		noise, roughness, int(settings.foliage_style))
	for index in count:
		var angle := phase + TAU * float(index) / count + random.randf_range(-0.22, 0.22) * diversity
		var radial := Vector3(cos(angle), 0, sin(angle))
		var reach := spread * (0.44 + random.randf_range(-0.12, 0.12) * diversity)
		var center := base + radial * reach
		center.y = maxf(1, height * (0.045 + random.randf_range(0, 0.05) * diversity))
		var scale := 1.0 + random.randf_range(-0.14, 0.14) * diversity
		var radii := Vector3(spread * 0.48 * scale, height * float(sizes[index]), spread * 0.43 / scale) * fullness
		_paint_shrub_dome(leaves, center, radii, noise, roughness, int(settings.foliage_style))
		var root := base + radial * spread * 0.22
		var endpoint := center + Vector3.UP * radii.y * 0.55
		stems.append({"from": base, "to": root})
		stems.append({"from": root, "to": endpoint})
		for branch in 2:
			var anchor := root.lerp(endpoint, 0.46 + branch * 0.18)
			stems.append({"from": anchor, "to": anchor + radial.rotated(Vector3.UP, -0.7 if branch == 0 else 0.7) * radii.x * 0.42 + Vector3.UP * radii.y * 0.14})
	# One coherent air pocket between growths, not random missing foliage voxels.
	var gap_angle := phase + PI / count
	var gap_radial := Vector3(cos(gap_angle), 0, sin(gap_angle))
	var gap_side := gap_radial.cross(Vector3.UP)
	var gap_center := base + gap_radial * spread * 0.48 + Vector3.UP * height * 0.32
	for cell: Vector3i in leaves.keys():
		var delta := Vector3(cell) - gap_center
		var local := Vector3(delta.dot(gap_side) / maxf(1, spread * 0.14),
			delta.y / maxf(1, height * 0.11), delta.dot(gap_radial) / maxf(1, spread * 0.45))
		if local.length_squared() < 1: leaves.erase(cell)
	Foliage.colorize_motifs(leaves, wood, int(settings.foliage_detail), seed)
	for cell: Vector3i in leaves:
		if cell.x >= 0 and cell.z >= 0 and cell.x < grid.x and cell.z < grid.z and cell.y > 0 and cell.y < grid.y:
			source.voxels[Geometry.Model.index_of(cell, grid)] = int(leaves[cell])
	for stem in stems:
		_paint_connected_stem(source, stem.from.clamp(Vector3.ZERO, Vector3(grid - Vector3i.ONE)),
			stem.to.clamp(Vector3.ZERO, Vector3(grid - Vector3i.ONE)))
	Geometry.keep_largest_component(source)


static func _paint_shrub_dome(leaves: Dictionary, bottom: Vector3, radii: Vector3,
	noise: FastNoiseLite, roughness: float, style: int) -> void:
	var safe := radii.max(Vector3.ONE)
	var extent := safe * (1 + roughness)
	var minimum := Vector3i((bottom - Vector3(extent.x, 0, extent.z)).floor())
	var maximum := Vector3i((bottom + extent).ceil())
	for y in range(maxi(1, minimum.y), maximum.y + 1):
		for z in range(minimum.z, maximum.z + 1):
			for x in range(minimum.x, maximum.x + 1):
				var local := (Vector3(x, y, z) - bottom) / safe
				if local.y < 0: continue
				# Upper dome: broad at the foot, tapering upwards, never a hanging heart.
				var distance := local.x * local.x + local.z * local.z + pow(local.y, 1.6 if style == 1 else 2.2)
				var contour := 1.0 + noise.get_noise_3d(floorf(x / 2.0) * 2, floorf(y / 2.0) * 2, floorf(z / 2.0) * 2) * roughness
				if distance <= contour: leaves[Vector3i(x, y, z)] = 5


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
