@tool
extends RefCounted
## Pure deterministic provider for sparse, non-colliding voxel grass tufts.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")

const MIN_HEIGHT := 2
const MAX_HEIGHT := 12
const MIN_SPREAD := 1
const MAX_SPREAD := 4


static func defaults() -> Dictionary:
	return {
		"height": 6,
		"spread_radius": 2,
		"blade_count": 7,
		"height_variation": 35,
		"lean": 30,
		"density": 16,
		"base_color": Color("4f873e"),
		"tip_color": Color("89bd58"),
		"variant_count": 6,
		"size_variation": 20,
	}


static func normalize(parameters: Dictionary) -> Dictionary:
	var fallback := defaults()
	var base_color: Variant = parameters.get("base_color", fallback.base_color)
	var tip_color: Variant = parameters.get("tip_color", fallback.tip_color)
	return {
		"height": clampi(int(parameters.get("height", fallback.height)), MIN_HEIGHT, MAX_HEIGHT),
		"spread_radius": clampi(
			int(parameters.get("spread_radius", fallback.spread_radius)), MIN_SPREAD, MAX_SPREAD
		),
		"blade_count": clampi(int(parameters.get("blade_count", fallback.blade_count)), 2, 16),
		"height_variation": clampi(
			int(parameters.get("height_variation", fallback.height_variation)), 0, 75
		),
		"lean": clampi(int(parameters.get("lean", fallback.lean)), 0, 100),
		"density": 32 if int(parameters.get("density", fallback.density)) == 32 else 16,
		"base_color": Color(base_color if base_color is Color else fallback.base_color, 1.0),
		"tip_color": Color(tip_color if tip_color is Color else fallback.tip_color, 1.0),
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
			MAX_SPREAD,
		)
	result.blade_count = clampi(int(result.blade_count) + random.randi_range(-2, 2), 2, 16)
	result.height_variation = clampi(
		int(result.height_variation) + random.randi_range(-12, 12), 0, 75
	)
	result.lean = clampi(int(result.lean) + random.randi_range(-15, 15), 0, 100)
	return result


static func recommended_spacing(settings: Dictionary) -> int:
	return clampi(int(normalize(settings).spread_radius) * 2 + 1, 3, 9)


static func build(
	parameters: Dictionary,
	seed: int,
	_fallback_color: Color,
	material: Dictionary,
	title: String,
	model_id := "generated_grass",
) -> Dictionary:
	var settings := normalize(parameters)
	var height := int(settings.height)
	var spread := int(settings.spread_radius)
	var lean_margin := ceili(float(height) * 0.30)
	var footprint := mini(32, spread * 2 + lean_margin * 2 + 3)
	var built := Shapes.build(
		"empty",
		Vector3i(footprint, height, footprint),
		int(settings.density),
		settings.base_color,
		model_id,
		title,
	)
	if not built.get("ok", false):
		return {"error": built.get("error", "Не удалось создать сетку травы.")}
	var source: EmberVoxelModelResource = built.source
	source.tags = PackedStringArray(["stamp", "generated", "grass"])
	source.material = material.duplicate(true)
	source.palette = PackedColorArray([
		Color.TRANSPARENT, settings.base_color, settings.tip_color,
	])
	# Explicit zeroes distinguish decorative grass from legacy all-solid geometry.
	source.collision_voxels.resize(source.voxels.size())
	source.collision_voxels.fill(0)
	var grid := source.grid_size()
	var center := Vector3i(grid.x / 2, 0, grid.z / 2)
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 122949829
	var shared_angle := random.randf_range(0.0, TAU)
	for blade_index in int(settings.blade_count):
		var base := center
		if blade_index > 0:
			var base_angle := random.randf_range(0.0, TAU)
			var base_radius := sqrt(random.randf()) * float(spread)
			base.x += roundi(cos(base_angle) * base_radius)
			base.z += roundi(sin(base_angle) * base_radius)
		var blade_height := height
		if blade_index > 0:
			var loss := roundi(
				float(height - 1)
				* float(settings.height_variation) / 100.0
				* random.randf()
			)
			blade_height = clampi(height - loss, MIN_HEIGHT, height)
		var radial_angle := (
			TAU * float(blade_index) / float(maxi(1, int(settings.blade_count)))
			+ random.randf_range(-0.55, 0.55)
		)
		var direction := (
			Vector2(cos(radial_angle), sin(radial_angle)) * 0.72
			+ Vector2(cos(shared_angle), sin(shared_angle)) * 0.28
		).normalized()
		var lean_distance := mini(lean_margin, roundi(
			float(blade_height - 1)
			* float(settings.lean) / 100.0
			* random.randf_range(0.25, 0.45)
		))
		var tip := Vector3i(
			base.x + roundi(direction.x * float(lean_distance)),
			blade_height - 1,
			base.z + roundi(direction.y * float(lean_distance)),
		)
		tip.x = clampi(tip.x, 0, grid.x - 1)
		tip.z = clampi(tip.z, 0, grid.z - 1)
		_paint_blade(source, base, tip, blade_height)
	if source.voxels.count(1) == 0 or source.voxels.count(2) == 0:
		return {"error": "Параметры не создали траву с основанием и светлыми кончиками."}
	return {"geometry": source, "parameters": settings}


static func _paint_blade(
	source: EmberVoxelModelResource,
	from: Vector3i,
	to: Vector3i,
	blade_height: int,
) -> void:
	var grid := source.grid_size()
	var cell := from
	var total := Vector3i(
		absi(to.x - cell.x), absi(to.y - cell.y), absi(to.z - cell.z)
	)
	var moved := Vector3i.ZERO
	while true:
		var palette_index := 2 if cell.y * 3 >= maxi(1, blade_height - 1) * 2 else 1
		source.voxels[Model.index_of(cell, grid)] = palette_index
		if cell == to:
			break
		var remaining := total - moved
		var axis := 1
		if remaining.x > remaining.y and remaining.x >= remaining.z:
			axis = 0
		elif remaining.z > remaining.y and remaining.z > remaining.x:
			axis = 2
		match axis:
			0:
				cell.x += signi(to.x - cell.x)
				moved.x += 1
			1:
				cell.y += signi(to.y - cell.y)
				moved.y += 1
			2:
				cell.z += signi(to.z - cell.z)
				moved.z += 1
