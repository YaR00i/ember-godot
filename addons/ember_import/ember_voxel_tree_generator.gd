@tool
extends RefCounted
## Pure deterministic provider for a connected stylized trunk, branches and crown.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Geometry = preload("res://addons/ember_import/ember_voxel_generator_geometry.gd")

const MIN_HEIGHT := 8
const MAX_HEIGHT := 32
const MIN_CROWN_RADIUS := 2
const MAX_CROWN_RADIUS := 10


static func defaults() -> Dictionary:
	return {
		"height": 18,
		"trunk_width": 2,
		"crown_radius": 5,
		"branchiness": 55,
		"crown_roughness": 35,
		"density": 16,
		"trunk_color": Color("7a5134"),
		"foliage_color": Color("4f9250"),
		"variant_count": 1,
		"size_variation": 0,
	}


static func normalize(parameters: Dictionary) -> Dictionary:
	var fallback := defaults()
	var height := clampi(int(parameters.get("height", fallback.height)), MIN_HEIGHT, MAX_HEIGHT)
	var max_radius := clampi((height - 2) / 2, MIN_CROWN_RADIUS, MAX_CROWN_RADIUS)
	var trunk_color: Variant = parameters.get("trunk_color", fallback.trunk_color)
	var foliage_color: Variant = parameters.get("foliage_color", fallback.foliage_color)
	return {
		"height": height,
		"trunk_width": clampi(int(parameters.get("trunk_width", fallback.trunk_width)), 1, 5),
		"crown_radius": clampi(
			int(parameters.get("crown_radius", fallback.crown_radius)),
			MIN_CROWN_RADIUS,
			max_radius,
		),
		"branchiness": clampi(int(parameters.get("branchiness", fallback.branchiness)), 0, 100),
		"crown_roughness": clampi(
			int(parameters.get("crown_roughness", fallback.crown_roughness)), 0, 100
		),
		"density": 32 if int(parameters.get("density", fallback.density)) == 32 else 16,
		"trunk_color": Color(trunk_color if trunk_color is Color else fallback.trunk_color, 1.0),
		"foliage_color": Color(
			foliage_color if foliage_color is Color else fallback.foliage_color, 1.0
		),
		"variant_count": clampi(int(parameters.get("variant_count", 1)), 1, 8),
		"size_variation": clampi(int(parameters.get("size_variation", 0)), 0, 50),
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
		var max_radius := clampi(
			(int(result.height) - 2) / 2, MIN_CROWN_RADIUS, MAX_CROWN_RADIUS
		)
		result.crown_radius = clampi(
			roundi(
				float(result.crown_radius)
				* (1.0 + random.randf_range(-variation, variation))
			),
			MIN_CROWN_RADIUS,
			max_radius,
		)
		result.trunk_width = clampi(
			roundi(
				float(result.trunk_width)
				* (1.0 + random.randf_range(-variation * 0.5, variation * 0.5))
			),
			1,
			5,
		)
	result.branchiness = clampi(
		int(result.branchiness) + random.randi_range(-12, 12), 0, 100
	)
	result.crown_roughness = clampi(
		int(result.crown_roughness) + random.randi_range(-10, 10), 0, 100
	)
	return result


static func recommended_spacing(settings: Dictionary) -> int:
	var radius := int(normalize(settings).crown_radius)
	return maxi(3, roundi(float(radius) * 1.8))


static func build(
	parameters: Dictionary,
	seed: int,
	_fallback_color: Color,
	material: Dictionary,
	title: String,
	model_id := "generated_tree",
) -> Dictionary:
	var settings := normalize(parameters)
	var height := int(settings.height)
	var crown_radius := int(settings.crown_radius)
	var footprint := mini(32, crown_radius * 2 + 5)
	var built := Shapes.build(
		"empty",
		Vector3i(footprint, height, footprint),
		int(settings.density),
		settings.foliage_color,
		model_id,
		title,
	)
	if not built.get("ok", false):
		return {"error": built.get("error", "Не удалось создать сетку дерева.")}
	var source: EmberVoxelModelResource = built.source
	source.tags = PackedStringArray(["stamp", "generated", "tree"])
	source.material = material.duplicate(true)
	source.palette = PackedColorArray([
		Color.TRANSPARENT, settings.trunk_color, settings.foliage_color,
	])
	var grid := source.grid_size()
	var center := Vector3(float(grid.x / 2), 0.0, float(grid.z / 2))
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 49979687
	var crown_center_y := float(height - 1) - float(crown_radius) * 0.72
	var trunk_top := Vector3(
		center.x + random.randf_range(-0.8, 0.8),
		crown_center_y,
		center.z + random.randf_range(-0.8, 0.8),
	)
	var trunk_mid := Vector3(
		center.x + random.randf_range(-0.7, 0.7),
		crown_center_y * 0.52,
		center.z + random.randf_range(-0.7, 0.7),
	)
	var branch_count := roundi(float(settings.branchiness) / 100.0 * 7.0)
	var branches: Array[Dictionary] = []
	var crown_centers: Array[Vector3] = [trunk_top]
	for branch_index in branch_count:
		var angle := (
			TAU * float(branch_index) / float(maxi(1, branch_count))
			+ random.randf_range(-0.42, 0.42)
		)
		var start := trunk_mid.lerp(trunk_top, random.randf_range(0.18, 0.82))
		var reach := float(crown_radius) * random.randf_range(0.55, 0.95)
		var endpoint := start + Vector3(
			cos(angle) * reach,
			random.randf_range(0.8, maxf(1.2, float(crown_radius) * 0.45)),
			sin(angle) * reach,
		)
		endpoint.x = clampf(endpoint.x, 1.0, float(grid.x - 2))
		endpoint.y = clampf(endpoint.y, 2.0, float(height - 2))
		endpoint.z = clampf(endpoint.z, 1.0, float(grid.z - 2))
		branches.append({"from": start, "to": endpoint})
		crown_centers.append(endpoint)
	# Extra overlapping blobs keep sparse trees leafy without breaking connectivity.
	for _index in 2:
		var angle := random.randf_range(0.0, TAU)
		crown_centers.append(
			trunk_top
			+ Vector3(
				cos(angle) * float(crown_radius) * 0.35,
				random.randf_range(-0.5, 1.0),
				sin(angle) * float(crown_radius) * 0.35,
			)
		)
	var noise := FastNoiseLite.new()
	noise.seed = maxi(0, seed) + 67867967
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.16
	for index in crown_centers.size():
		var blob_scale := 1.0 if index == 0 else random.randf_range(0.48, 0.68)
		_paint_crown(
			source,
			crown_centers[index],
			Vector3(
				float(crown_radius) * blob_scale,
				float(crown_radius) * blob_scale * 0.78,
				float(crown_radius) * blob_scale,
			),
			float(settings.crown_roughness) / 100.0,
			noise,
		)
	var trunk_radius := maxf(0.62, float(settings.trunk_width) * 0.5)
	Geometry.paint_line(source, center, trunk_mid, trunk_radius, 1)
	Geometry.paint_line(source, trunk_mid, trunk_top, trunk_radius * 0.88, 1)
	for branch: Dictionary in branches:
		Geometry.paint_line(
			source, branch.from, branch.to, maxf(0.58, trunk_radius * 0.62), 1
		)
	# Guarantee a compact ground contact even for a one-voxel trunk.
	Geometry.paint_sphere(source, center, maxf(0.72, trunk_radius), 1)
	Geometry.keep_largest_component(source)
	if source.voxels.count(1) == 0 or source.voxels.count(2) == 0:
		return {"error": "Параметры не создали связное дерево со стволом и кроной."}
	return {"geometry": source, "parameters": settings}


static func _paint_crown(
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
				var surface := 1.0 + noise.get_noise_3d(x, y, z) * roughness * 0.28
				if normalized.length() <= surface:
					var cell := Vector3i(x, y, z)
					source.voxels[Model.index_of(cell, grid)] = 2
