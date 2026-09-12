@tool
extends RefCounted
## Pure deterministic provider for one connected, groundable voxel rock.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Geometry = preload("res://addons/ember_import/ember_voxel_generator_geometry.gd")

const MIN_DIMENSION := 3
const MAX_DIMENSION := 32


static func defaults() -> Dictionary:
	return {
		"dimensions": Vector3i(10, 7, 9),
		"roughness": 35,
		"chips": 25,
		"density": 16,
		# One/no size variation preserves recipes saved before variant sets existed.
		"variant_count": 1,
		"size_variation": 0,
	}


static func normalize(parameters: Dictionary) -> Dictionary:
	var fallback := defaults()
	var dimensions: Variant = parameters.get("dimensions", fallback.dimensions)
	if not dimensions is Vector3i:
		dimensions = fallback.dimensions
	var raw_dimensions: Vector3i = dimensions
	return {
		"dimensions": Vector3i(
			clampi(raw_dimensions.x, MIN_DIMENSION, MAX_DIMENSION),
			clampi(raw_dimensions.y, MIN_DIMENSION, MAX_DIMENSION),
			clampi(raw_dimensions.z, MIN_DIMENSION, MAX_DIMENSION)
		),
		"roughness": clampi(int(parameters.get("roughness", fallback.roughness)), 0, 100),
		"chips": clampi(int(parameters.get("chips", fallback.chips)), 0, 100),
		"density": 32 if int(parameters.get("density", fallback.density)) == 32 else 16,
		"variant_count": clampi(
			int(parameters.get("variant_count", fallback.variant_count)), 1, 8
		),
		"size_variation": clampi(
			int(parameters.get("size_variation", fallback.size_variation)), 0, 50
		),
	}


static func variant_parameters(settings: Dictionary, random: RandomNumberGenerator) -> Dictionary:
	var result := normalize(settings)
	var dimensions: Vector3i = result.dimensions
	var variation := float(result.size_variation) / 100.0
	if variation > 0.0:
		for axis in 3:
			var factor := 1.0 + random.randf_range(-variation, variation)
			dimensions[axis] = clampi(
				roundi(float(dimensions[axis]) * factor), MIN_DIMENSION, MAX_DIMENSION
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
