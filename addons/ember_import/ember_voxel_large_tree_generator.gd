@tool
extends RefCounted
## Deterministic editor-only builder for large, editable broadleaf voxel objects.
##
## The tapered recursive branch construction adapts ideas from NGNT/treegen-pinegen
## (MIT, Copyright 2025 NGNT). The Ember implementation is sparse, bounded and
## emits the canonical EmberVoxelModelResource instead of a VOX document.

const MIN_HEIGHT := 64
const MAX_HEIGHT := 256
const MAX_STORAGE_CELLS := 4_194_304
const MAX_OCCUPIED_VOXELS := 360_000
const LATEST_VERSIONS := [9, 8, 5, 7, 10]
const BarkPattern = preload("res://addons/ember_import/ember_voxel_bark_pattern.gd")


static func defaults() -> Dictionary:
	return {
		"generation_version": 2,
		"bark_pattern_version": 2,
		"tree_type": 0,
		"branch_direction": 0,
		"foliage_along": 65,
		"crown_shape": 0,
		"branch_thickness": 75,
		"branch_taper": 60,
		"branch_curve": 55,
		"branch_start": 34,
		"cluster_size": 130,
		"cluster_flatten": 60,
		"canopy_cohesion": 55,
		"root_flare": 65,
		"height": 96,
		"trunk_width": 10,
		"crown_spread": 65,
		"branchiness": 62,
		"irregularity": 42,
		"leaf_density": 62,
		"density": 16,
		"bark_color": Color("765039"),
		"foliage_color": Color("4f8f50"),
	}


static func normalize(parameters: Dictionary) -> Dictionary:
	var fallback := defaults()
	if int(parameters.get("generation_version", 1)) == 1:
		fallback.trunk_width = 7
		fallback.crown_spread = 55
	var bark: Variant = parameters.get("bark_color", fallback.bark_color)
	var foliage: Variant = parameters.get("foliage_color", fallback.foliage_color)
	var height := clampi(int(parameters.get("height", fallback.height)), MIN_HEIGHT, MAX_HEIGHT)
	# Ember resources hold at most eight blocks vertically. Heights above 128
	# therefore require the existing 32 vox/block density.
	var density := 32 if height > 128 or int(parameters.get("density", fallback.density)) == 32 else 16
	var tree_type := clampi(int(parameters.get("tree_type", 0)), 0, 4)
	var direction := clampi(int(parameters.get("branch_direction", 0)), 0, 3)
	var version := clampi(int(parameters.get("generation_version", 1)), 1, 10)
	if tree_type > 0 or direction > 0: version = maxi(3, version)
	if tree_type == 4: version = 10
	if version == 10 and tree_type != 4: version = LATEST_VERSIONS[tree_type]
	if version == 9 and tree_type != 0: version = 8 if tree_type == 1 else (5 if tree_type == 2 else 7)
	if version == 8 and tree_type != 1: version = 7 if tree_type == 3 else (5 if tree_type == 2 else 3)
	if version in [6, 7] and tree_type != 3: version = 5 if tree_type == 2 else (4 if tree_type == 1 else 3)
	if version == 5 and tree_type != 2: version = 4 if tree_type == 1 else 3
	if version == 4 and tree_type != 1: version = 3
	var result := {
		# Missing version belongs to saved v1 recipes, not today's UI defaults.
		"generation_version": version,
		"tree_type": tree_type,
		"branch_direction": direction,
		"foliage_along": clampi(int(parameters.get("foliage_along", 65)), 0, 100),
		"crown_shape": clampi(int(parameters.get("crown_shape", fallback.crown_shape)), 0, 2),
		"branch_thickness": clampi(int(parameters.get("branch_thickness", fallback.branch_thickness)), 25, 100),
		"branch_taper": clampi(int(parameters.get("branch_taper", fallback.branch_taper)), 0, 100),
		"branch_curve": clampi(int(parameters.get("branch_curve", fallback.branch_curve)), 0, 100),
		"branch_start": clampi(int(parameters.get("branch_start", fallback.branch_start)), 20, 55),
		"cluster_size": clampi(int(parameters.get("cluster_size", fallback.cluster_size)), 65, 180),
		"cluster_flatten": clampi(int(parameters.get("cluster_flatten", fallback.cluster_flatten)), 0, 100),
		"canopy_cohesion": clampi(int(parameters.get("canopy_cohesion", fallback.canopy_cohesion)), 0, 100),
		"root_flare": clampi(int(parameters.get("root_flare", fallback.root_flare)), 0, 100),
		"height": height,
		"trunk_width": clampi(int(parameters.get("trunk_width", fallback.trunk_width)), 3, 24),
		"crown_spread": clampi(int(parameters.get("crown_spread", fallback.crown_spread)), 25, 85),
		"branchiness": clampi(int(parameters.get("branchiness", fallback.branchiness)), 0, 100),
		"irregularity": clampi(int(parameters.get("irregularity", fallback.irregularity)), 0, 100),
		"leaf_density": clampi(int(parameters.get("leaf_density", fallback.leaf_density)), 20, 100),
		"foliage_amount": clampi(int(parameters.get("foliage_amount", 100)), 0, 100),
		"density": density,
		"bark_color": Color(bark if bark is Color else fallback.bark_color, 1.0),
		"foliage_color": Color(foliage if foliage is Color else fallback.foliage_color, 1.0),
	}
	result.merge(BarkPattern.normalized(parameters))
	return result


static func build(
	parameters: Dictionary, seed: int, fallback_color: Color, material: Dictionary,
	title: String, model_id := "generated_large_tree",
) -> Dictionary:
	if int(normalize(parameters).generation_version) == 1:
		return _build_legacy(parameters, seed, fallback_color, material, title, model_id)
	if int(normalize(parameters).generation_version) == 4:
		return _build_oak(normalize(parameters), seed, material, title, model_id)
	if int(normalize(parameters).generation_version) == 5:
		return _build_birch(normalize(parameters), seed, material, title, model_id)
	if int(normalize(parameters).generation_version) == 6:
		return _build_maple(normalize(parameters), seed, material, title, model_id)
	if int(normalize(parameters).generation_version) == 7:
		return _build_maple_upright(normalize(parameters), seed, material, title, model_id)
	if int(normalize(parameters).generation_version) == 8:
		return _build_oak_mature(normalize(parameters), seed, material, title, model_id)
	if int(normalize(parameters).generation_version) == 9:
		return _build_savanna_umbrella(normalize(parameters), seed, material, title, model_id)
	if int(normalize(parameters).generation_version) == 10:
		return _build_spruce(normalize(parameters), seed, material, title, model_id)
	return _build_sculpted(normalize(parameters), seed, material, title, model_id)


static func _build_legacy(
	parameters: Dictionary,
	seed: int,
	_fallback_color: Color,
	material: Dictionary,
	title: String,
	model_id := "generated_large_tree",
) -> Dictionary:
	var settings := normalize(parameters)
	var height := int(settings.height)
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 86028121
	var wood := {}
	var collision := {}
	var leaves := {}
	var terminals: Array[Vector3] = []
	var lines: Array = []
	var trunk_width := float(settings.trunk_width)
	var irregularity := float(settings.irregularity) / 100.0
	var crown_radius := clampf(
		float(height) * float(settings.crown_spread) / 240.0,
		10.0,
		46.0,
	)
	var trunk_top_y := float(height) * 0.76
	var trunk_points: Array[Vector3] = [Vector3.ZERO]
	var trunk_segments := clampi(height / 18, 4, 12)
	for segment in range(1, trunk_segments + 1):
		var t := float(segment) / float(trunk_segments)
		var previous := trunk_points[-1]
		var drift := Vector3(
			random.randf_range(-1.0, 1.0), 0.0, random.randf_range(-1.0, 1.0)
		) * irregularity * lerpf(0.35, 1.15, t)
		trunk_points.append(Vector3(previous.x + drift.x, trunk_top_y * t, previous.z + drift.z))
	for segment in trunk_segments:
		var t0 := float(segment) / float(trunk_segments)
		var t1 := float(segment + 1) / float(trunk_segments)
		_record_line(
			lines, wood, collision, trunk_points[segment], trunk_points[segment + 1],
			lerpf(trunk_width * 0.52, trunk_width * 0.17, t0),
			lerpf(trunk_width * 0.52, trunk_width * 0.17, t1), true,
		)
	var main_count := 7 + roundi(float(settings.branchiness) * 0.11)
	for branch_index in main_count:
		var level_t := lerpf(0.35, 0.92, float(branch_index) / float(maxi(1, main_count - 1)))
		level_t = clampf(level_t + random.randf_range(-0.045, 0.045), 0.30, 0.95)
		var start := _sample_polyline(trunk_points, level_t)
		var angle := TAU * (float(branch_index) / 2.61803398875) + random.randf_range(-0.35, 0.35)
		var reach := crown_radius * random.randf_range(0.58, 1.0) * lerpf(1.05, 0.68, level_t)
		var rise := crown_radius * random.randf_range(0.18, 0.62)
		var end := start + Vector3(cos(angle) * reach, rise, sin(angle) * reach)
		end.y = minf(float(height - 4), end.y)
		var radius0 := maxf(1.45, trunk_width * lerpf(0.31, 0.18, level_t))
		var radius1 := maxf(0.85, radius0 * 0.42)
		_record_line(lines, wood, collision, start, end, radius0, radius1, true, true)
		var secondary_count := 1 + roundi(float(settings.branchiness) / 55.0)
		for secondary_index in secondary_count:
			var side := -1.0 if secondary_index % 2 == 0 else 1.0
			var turn := angle + side * random.randf_range(0.48, 1.05)
			var secondary_start := start.lerp(end, random.randf_range(0.46, 0.72))
			var secondary_reach := reach * random.randf_range(0.28, 0.52)
			var secondary_end := end + Vector3(
				cos(turn) * secondary_reach,
				random.randf_range(-0.08, 0.32) * crown_radius,
				sin(turn) * secondary_reach,
			)
			secondary_end.y = clampf(secondary_end.y, start.y + 2.0, float(height - 3))
			_record_line(
				lines, wood, collision, secondary_start, secondary_end,
				maxf(0.82, radius1 * 0.95), 0.65, radius1 >= 1.25, true,
			)
			terminals.append(secondary_end)
		terminals.append(end)
	# Keep the requested height structural: a tapered central leader reaches the
	# top crown instead of adding a disconnected decorative voxel island.
	var leader_end := Vector3(
		trunk_points[-1].x + random.randf_range(-1.5, 1.5) * irregularity,
		float(height - 1),
		trunk_points[-1].z + random.randf_range(-1.5, 1.5) * irregularity,
	)
	_record_line(
		lines, wood, collision, trunk_points[-1], leader_end,
		maxf(1.2, trunk_width * 0.18), 0.72, true,
	)
	terminals.append(leader_end)
	# The crown grows from branch tips, not from one solid sphere. Overlapping
	# noisy ellipsoids leave readable gaps between the major boughs.
	var noise := FastNoiseLite.new()
	noise.seed = maxi(0, seed) + 104729
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.12
	var leaf_density := float(settings.leaf_density) / 100.0
	for terminal_index in terminals.size():
		var terminal := terminals[terminal_index]
		var radius := crown_radius * random.randf_range(0.14, 0.23)
		_paint_leaf_cluster(
			leaves, wood, terminal,
			Vector3(radius, radius * random.randf_range(0.68, 0.90), radius),
			leaf_density, irregularity, noise,
		)
	# A few smaller inner clusters join the silhouette without sealing every gap.
	for point_index in range(maxi(1, trunk_points.size() - 4), trunk_points.size()):
		var center := trunk_points[point_index] + Vector3(
			random.randf_range(-0.22, 0.22) * crown_radius,
			random.randf_range(0.0, 0.18) * crown_radius,
			random.randf_range(-0.22, 0.22) * crown_radius,
		)
		var radius := crown_radius * random.randf_range(0.15, 0.21)
		_paint_leaf_cluster(leaves, wood, center, Vector3(radius, radius * 0.8, radius), leaf_density, irregularity, noise)
	return _emit(settings, wood, collision, leaves, noise, seed, material, title, model_id, lines)


static func _emit(
	settings: Dictionary, wood: Dictionary, collision: Dictionary, leaves: Dictionary,
	noise: FastNoiseLite, seed: int, material: Dictionary, title: String, model_id: String,
	lines: Array = [],
) -> Dictionary:
	var height := int(settings.height)
	if wood.is_empty() or (leaves.is_empty() and not settings.has("_pivot_bias") and int(settings.generation_version) < 4):
		return {"error": "Параметры не создали дерево со стволом и листвой."}
	var bounds := _bounds(wood, leaves)
	var raw_size: Vector3i = bounds.max - bounds.min + Vector3i.ONE
	var density := int(settings.density)
	var grid := Vector3i(
		ceili(float(raw_size.x + 4) / density) * density,
		height,
		ceili(float(raw_size.z + 4) / density) * density,
	)
	if settings.has("_pivot_bias"):
		var bias: Vector2i = settings._pivot_bias
		grid.x = ceili(float(maxi(-bounds.min.x - bias.x, bounds.max.x + bias.x + 1) * 2) / density) * density
		grid.z = ceili(float(maxi(-bounds.min.z - bias.y, bounds.max.z + bias.y + 1) * 2) / density) * density
		var base_grid: Vector3i = settings.get("_base_grid", Vector3i.ZERO)
		grid.x = maxi(grid.x, base_grid.x)
		grid.z = maxi(grid.z, base_grid.z)
	var cells := grid.x * grid.y * grid.z
	if cells > MAX_STORAGE_CELLS:
		return {"error": "Крона требует %s ячеек хранения; предел большого дерева — %s." % [cells, MAX_STORAGE_CELLS]}
	if wood.size() + leaves.size() > MAX_OCCUPIED_VOXELS:
		return {"error": "Дерево содержит слишком много вокселей. Уменьшите крону или листву."}
	var offset := Vector3i(
		(grid.x - raw_size.x) / 2 - bounds.min.x,
		-bounds.min.y,
		(grid.z - raw_size.z) / 2 - bounds.min.z,
	)
	if settings.has("_pivot_bias"):
		var bias: Vector2i = settings._pivot_bias
		offset = Vector3i(grid.x / 2 + bias.x, 0, grid.z / 2 + bias.y)
	var source := EmberVoxelModelResource.new()
	source.model_id = model_id
	source.display_name = title.strip_edges() if not title.strip_edges().is_empty() else "Большое дерево"
	source.tags = PackedStringArray(["generated", "tree", "large_tree", "broadleaf", "godot-native"])
	source.voxels_per_block = density
	source.size_blocks = Vector3i(grid.x / density, ceili(float(height) / density), grid.z / density)
	source.height_voxels = height
	source.palette = _palette(settings.bark_color, settings.foliage_color)
	var bark_marks := BarkPattern.marks(wood, lines, seed, settings)
	if not bark_marks.is_empty(): source.palette.append(settings.bark_pattern_color)
	source.material = material.duplicate(true)
	source.material["generator"] = "large_broadleaf_tree_v%d" % int(settings.generation_version)
	source.physical = true
	source.voxels.resize(cells)
	source.collision_voxels.resize(cells)
	var bark_noise := FastNoiseLite.new()
	bark_noise.seed = maxi(0, seed) + 15485863
	bark_noise.frequency = 0.08 if int(settings.generation_version) >= 2 else 0.16
	for raw_cell in wood:
		var cell: Vector3i = raw_cell + offset
		if not _contains(cell, grid):
			continue
		var index := VoxMesher.cell_index(cell.x, cell.y, cell.z, grid.x, grid.z)
		var tone := bark_noise.get_noise_3d(raw_cell.x, raw_cell.y * 0.7, raw_cell.z)
		source.voxels[index] = 1 if tone < -0.18 else (3 if tone > 0.33 else 2)
		if bark_marks.has(raw_cell): source.voxels[index] = 7
		source.collision_voxels[index] = 1 if collision.has(raw_cell) else 0
	for raw_cell in leaves:
		if wood.has(raw_cell):
			continue
		var cell: Vector3i = raw_cell + offset
		if not _contains(cell, grid):
			continue
		var index := VoxMesher.cell_index(cell.x, cell.y, cell.z, grid.x, grid.z)
		var light := noise.get_noise_3d(raw_cell.x + 31, raw_cell.y + 17, raw_cell.z - 23)
		source.voxels[index] = 4 if light < -0.12 else (6 if light > 0.34 else 5)
	return {
		"geometry": source,
		"parameters": settings,
		"grid": grid,
		"occupied": source.voxels.size() - source.voxels.count(0),
		"colliding": source.collision_voxels.count(1),
		"pivot_bias": Vector2i(offset.x - grid.x / 2, offset.z - grid.z / 2),
	}


## Quarter-voxel support coordinates survive text Recipe serialization exactly.
static func _support_point(point: Vector3) -> Vector3:
	return (point * 4.0).round() / 4.0


static func _record_crown_volume(groups: Array, center: Vector3, radii: Vector3, along := false) -> void:
	radii = _support_point(radii).max(Vector3.ONE)
	groups.append({"center": _support_point(center), "radius": maxf(radii.x, maxf(radii.y, radii.z)),
		"radii": radii, "along": along, "top": false, "state": 0})


static func _build_oak(settings: Dictionary, seed: int, material: Dictionary,
	title: String, model_id: String) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 86028121
	var wood := {}
	var collision := {}
	var leaves := {}
	var lines: Array = []
	var groups: Array = []
	var height := float(settings.height)
	var radius := float(settings.trunk_width) * 0.56
	var curve := float(settings.branch_curve) / 100.0
	var angle := random.randf() * TAU
	var fork_height := height * clampf(float(settings.branch_start) / 100.0, 0.22, 0.45)
	var fork := _support_point(Vector3(cos(angle) * radius * curve, fork_height, sin(angle) * radius * curve))
	var trunk_mid := _support_point(fork * 0.52 + Vector3(-sin(angle), 0, cos(angle)) * radius * curve * 0.65)
	_record_line(lines, wood, collision, Vector3.ZERO, trunk_mid, radius * 1.18, radius, true)
	_record_line(lines, wood, collision, trunk_mid, fork, radius, radius * 0.86, true)
	var flare := float(settings.root_flare) / 100.0
	if flare > 0:
		for root_index in 5:
			var root_angle := angle + TAU * float(root_index) / 5.0 + random.randf_range(-0.2, 0.2)
			var reach := radius * lerpf(1.2, 3.0, flare) * random.randf_range(0.8, 1.1)
			_record_line(lines, wood, collision, Vector3(0, radius, 0),
				_support_point(Vector3(cos(root_angle) * reach, 0, sin(root_angle) * reach)), radius * 0.7, 0.7, true)
	var leaf_size := float(settings.cluster_size) / 130.0
	leaf_size *= lerpf(0.85, 1.18, float(settings.canopy_cohesion) / 100.0)
	var half_budget := floorf(sqrt(float(MAX_STORAGE_CELLS) / height) / float(settings.density)) * float(settings.density) * 0.5
	var reach := minf(height * float(settings.crown_spread) / 200.0, (half_budget - 4.0) / (1.45 + 0.85 * leaf_size))
	if int(settings.crown_shape) == 1: reach *= 0.82
	var flatten := _canopy_flatten(settings)
	var leaf_radius := maxf(1.0, snappedf(reach * 0.56 * leaf_size, 0.25))
	var count := 3 + roundi(float(settings.branchiness) / 40.0)
	var branch_radius := maxf(1.0, radius * float(settings.branch_thickness) / 100.0)
	var tip_ratio := lerpf(1.0, 0.12, float(settings.branch_taper) / 100.0)
	for index in count:
		var heading := angle + TAU * float(index) / float(count) + random.randf_range(-0.22, 0.22)
		var outward := Vector3(cos(heading), 0, sin(heading))
		var sideways := Vector3(-sin(heading), 0, cos(heading))
		var length := reach * random.randf_range(0.85, 1.08)
		var knee := fork + outward * length * 0.42 + sideways * length * curve * random.randf_range(-0.18, 0.18)
		knee.y = height * random.randf_range(0.47, 0.54)
		var end := fork + outward * length
		end.y = height * random.randf_range(0.64, 0.73)
		if int(settings.crown_shape) == 2: end.y += float(index % 2) * height * 0.04
		if int(settings.branch_direction) > 0:
			var slope: float = [0.0, 0.65, 0.06, -0.20][int(settings.branch_direction)]
			end.y = clampf(knee.y + length * slope, height * 0.44, height * 0.80)
		knee = _support_point(knee)
		end = _support_point(end)
		_record_line(lines, wood, collision, fork, knee, branch_radius, maxf(0.85, branch_radius * lerpf(1.0, tip_ratio, 0.48)), true, true, 0.0, 0.48)
		_record_line(lines, wood, collision, knee, end, maxf(0.85, branch_radius * lerpf(1.0, tip_ratio, 0.48)), maxf(0.65, branch_radius * tip_ratio), true, true, 0.48, 1.0)
		# Overlapping, unequal foliage volumes grow around boughs, not a pole.
		var variation := random.randf_range(0.88, 1.16)
		_record_crown_volume(groups, end + Vector3(0, leaf_radius * 0.18, 0),
			Vector3(leaf_radius * variation, leaf_radius * flatten * 0.88, leaf_radius * random.randf_range(0.85, 1.08)))
		var connector := knee.lerp(end, 0.45)
		connector.y = maxf(connector.y, end.y - leaf_radius * 0.30)
		_record_crown_volume(groups, connector, Vector3(leaf_radius * 1.10, leaf_radius * flatten, leaf_radius), true)
		for twig in 2:
			var turn := heading + (-1.0 if twig == 0 else 1.0) * random.randf_range(0.45, 0.85)
			var twig_start := knee.lerp(end, 0.6)
			var twig_end := end + Vector3(cos(turn), random.randf_range(0.1, 0.35), sin(turn)) * length * 0.26
			_record_crown_volume(groups, twig_end, Vector3(leaf_radius * 0.70, leaf_radius * flatten * 0.68, leaf_radius * 0.75))
			_record_line(lines, wood, collision, _support_point(twig_start), _support_point(twig_end), maxf(0.85, branch_radius * 0.40), 0.65, true, true, 0.6, 1.0)
		# Several bent crown leaders replace the single vertical wooden spike.
		if index < 3:
			var upper := fork + outward * length * 0.62 + sideways * length * 0.16
			upper.y = height - 1.0 - ceilf(leaf_radius * flatten * 0.80)
			upper = _support_point(upper)
			var upper_mid := _support_point(end.lerp(upper, 0.5) + sideways * length * curve * 0.12)
			_record_line(lines, wood, collision, end, upper_mid, maxf(1.0, branch_radius * 0.40), maxf(0.85, branch_radius * 0.25), true, true, 0.65, 0.84)
			_record_line(lines, wood, collision, upper_mid, upper, maxf(0.85, branch_radius * 0.25), 0.70, true, true, 0.84, 1.0)
			_record_crown_volume(groups, upper, Vector3(leaf_radius * 0.95, ceilf(leaf_radius * flatten * 0.80), leaf_radius * 0.90))
	var noise := _volume_noise(seed, leaf_radius)
	_paint_crown_volumes(leaves, wood, groups, settings, settings, noise)
	var result := _emit(settings, wood, collision, leaves, noise, seed, material, title, model_id, lines)
	if not result.has("error"):
		result["structure"] = {"version": 1, "lines": lines, "groups": groups,
			"parameters": settings.duplicate(true), "pivot_bias": result.pivot_bias, "grid": result.grid,
			"noise_radius": leaf_radius}
	return result


## A continuous slender leader, ascending boughs and hanging outer twigs.
## Uses the same frozen lines/crown volumes as oak, not a second generator.
static func _build_birch(settings: Dictionary, seed: int, material: Dictionary,
	title: String, model_id: String) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 86028121
	var wood := {}
	var collision := {}
	var leaves := {}
	var lines: Array = []
	var groups: Array = []
	var height := float(settings.height)
	var radius := float(settings.trunk_width) * 0.42
	var curve := float(settings.branch_curve) / 100.0
	var heading := random.randf() * TAU
	var drift := Vector3(cos(heading), 0, sin(heading)) * height * curve * 0.055
	var trunk: Array[Vector3] = [Vector3.ZERO]
	for index in range(1, 6):
		var progress := float(index) / 5.0
		var point := drift * progress + Vector3(-sin(heading), 0, cos(heading)) * sin(progress * PI) * radius * curve
		point.y = height * 0.98 * progress
		trunk.append(_support_point(point))
		_record_line(lines, wood, collision, trunk[index - 1], trunk[index],
			maxf(0.65, radius * lerpf(1.10, 0.16, float(index - 1) / 5.0)),
			maxf(0.65, radius * lerpf(1.10, 0.16, progress)), true)
	var flare := float(settings.root_flare) / 100.0
	if flare > 0:
		for index in 4:
			var angle := heading + TAU * float(index) / 4.0
			var reach := radius * lerpf(1.0, 2.0, flare)
			_record_line(lines, wood, collision, Vector3(0, radius, 0),
				_support_point(Vector3(cos(angle) * reach, 0, sin(angle) * reach)), radius * 0.45, 0.65, true)
	var leaf_scale := float(settings.cluster_size) / 130.0
	leaf_scale *= lerpf(0.85, 1.18, float(settings.canopy_cohesion) / 100.0)
	var half_budget := floorf(sqrt(float(MAX_STORAGE_CELLS) / height) / float(settings.density)) * float(settings.density) * 0.5
	var spread := minf(height * float(settings.crown_spread) / 200.0 * 0.85,
		(half_budget - drift.length() - radius - 4.0) / (1.65 + 0.30 * leaf_scale))
	spread = maxf(3.0, spread)
	if int(settings.crown_shape) == 1: spread *= 0.82
	var leaf_radius := maxf(1.0, snappedf(spread * 0.28 * leaf_scale, 0.25))
	var flatten := _canopy_flatten(settings)
	var count := 8 + roundi(float(settings.branchiness) / 16.0)
	var start_height := clampf(float(settings.branch_start) / 100.0, 0.25, 0.50)
	var branch_radius := maxf(0.85, radius * float(settings.branch_thickness) / 100.0)
	var tip_ratio := lerpf(1.0, 0.12, float(settings.branch_taper) / 100.0)
	for index in count:
		var progress := float(index) / float(count - 1)
		var level := lerpf(start_height, 0.88, progress) + random.randf_range(-0.015, 0.015)
		if int(settings.crown_shape) == 2:
			level = snappedf(level, 0.08) + random.randf_range(-0.01, 0.01)
		var start := _support_point(_sample_polyline(trunk, level / 0.98))
		var angle := heading + float(index) * TAU / 2.61803398875 + random.randf_range(-0.2, 0.2)
		var outward := Vector3(cos(angle), 0, sin(angle))
		var sideways := Vector3(-sin(angle), 0, cos(angle))
		var envelope := sin(lerpf(0.30, 0.93, progress) * PI)
		var reach := spread * envelope * random.randf_range(0.85, 1.08)
		var slope := 0.32
		if int(settings.branch_direction) > 0:
			slope = [0.32, 0.65, 0.06, -0.20][int(settings.branch_direction)]
		var end := start + outward * reach + Vector3.UP * reach * slope
		end.y = minf(end.y, height * 0.95)
		var knee := _support_point(start.lerp(end, 0.55) + sideways * reach * curve * 0.12)
		end = _support_point(end)
		var r0 := maxf(0.85, branch_radius * lerpf(1.0, 0.50, progress))
		var rm := maxf(0.65, r0 * lerpf(1.0, tip_ratio, 0.55))
		_record_line(lines, wood, collision, start, knee, r0, rm, true, true, 0.0, 0.55)
		_record_line(lines, wood, collision, knee, end, rm, maxf(0.65, r0 * tip_ratio), true, true, 0.55, 1.0)
		var size := leaf_radius * lerpf(1.15, 0.45, progress)
		_record_crown_volume(groups, knee.lerp(end, 0.40), Vector3(size, size * flatten, size), true)
		for twig in 3:
			var anchor := _support_point(knee.lerp(end, 0.35 + float(twig) * 0.30))
			var turn := angle + (-0.60 + float(twig) * 0.60)
			var length := reach * random.randf_range(0.25, 0.42)
			var tip := anchor + Vector3(cos(turn), 0, sin(turn)) * length
			tip.y -= length * (0.45 + curve * 0.55) + height * 0.015
			tip = _support_point(tip)
			var middle := _support_point(anchor.lerp(tip, 0.45) + Vector3.UP * length * 0.08)
			_record_line(lines, wood, collision, anchor, middle, maxf(0.65, rm * 0.65), 0.65, true, true, 0.70, 0.85)
			_record_line(lines, wood, collision, middle, tip, 0.65, 0.65, true, true, 0.85, 1.0)
			_record_crown_volume(groups, middle.lerp(tip, 0.60),
				Vector3(size * 0.80, size * flatten * random.randf_range(1.30, 1.80), size * 0.70))
	# Two small lateral shoots dress the leader without stacking balls on it.
	for index in 2:
		var angle := heading + float(index) * PI + 0.65
		var start := _support_point(_sample_polyline(trunk, 0.94 / 0.98))
		var tip := _support_point(start + Vector3(cos(angle), -0.55, sin(angle)) * spread * 0.13)
		_record_line(lines, wood, collision, start, tip, 0.65, 0.65, true, true, 0.85, 1.0)
		_record_crown_volume(groups, tip, Vector3(leaf_radius * 0.55, leaf_radius * flatten * 0.85, leaf_radius * 0.50))
	var noise := _volume_noise(seed, leaf_radius)
	_paint_crown_volumes(leaves, wood, groups, settings, settings, noise)
	var result := _emit(settings, wood, collision, leaves, noise, seed, material, title, model_id, lines)
	if not result.has("error"):
		result["structure"] = {"version": 1, "lines": lines, "groups": groups,
			"parameters": settings.duplicate(true), "pivot_bias": result.pivot_bias, "grid": result.grid,
			"noise_radius": leaf_radius}
	return result


## Upright, spreading forks support a rounded crown. Same frozen volume pipeline.
static func _build_maple(settings: Dictionary, seed: int, material: Dictionary,
	title: String, model_id: String) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 67867967
	var wood := {}
	var collision := {}
	var leaves := {}
	var lines: Array = []
	var groups: Array = []
	var height := float(settings.height)
	var radius := float(settings.trunk_width) * 0.46
	var curve := float(settings.branch_curve) / 100.0
	var heading := random.randf() * TAU
	var outward := Vector3(cos(heading), 0, sin(heading))
	var sideways := Vector3(-sin(heading), 0, cos(heading))
	var fork_height := height * clampf(float(settings.branch_start) / 100.0, 0.26, 0.46)
	var fork := _support_point(Vector3.UP * fork_height + outward * radius * curve)
	var middle := _support_point(fork * 0.52 + sideways * radius * curve * 0.40)
	_record_line(lines, wood, collision, Vector3.ZERO, middle, radius * 1.10, radius, true)
	_record_line(lines, wood, collision, middle, fork, radius, radius * 0.82, true)
	var flare := float(settings.root_flare) / 100.0
	if flare > 0:
		for index in 4:
			var angle := heading + TAU * float(index) / 4.0
			var reach := radius * lerpf(1.0, 2.2, flare)
			_record_line(lines, wood, collision, Vector3(0, radius, 0),
				_support_point(Vector3(cos(angle) * reach, 0, sin(angle) * reach)), radius * 0.55, 0.65, true)
	var leaf_scale := float(settings.cluster_size) / 130.0
	leaf_scale *= lerpf(0.85, 1.18, float(settings.canopy_cohesion) / 100.0)
	var half_budget := floorf(sqrt(float(MAX_STORAGE_CELLS) / height) / float(settings.density)) * float(settings.density) * 0.5
	var reach := minf(height * float(settings.crown_spread) / 200.0 * 0.92,
		(half_budget - radius - 4.0) / (1.45 + 0.72 * leaf_scale))
	if int(settings.crown_shape) == 1: reach *= 0.80
	reach = maxf(3.0, reach)
	var leaf_radius := maxf(1.0, snappedf(reach * 0.48 * leaf_scale, 0.25))
	var flatten := _canopy_flatten(settings)
	var leader := _support_point(fork + outward * reach * curve * 0.14 + Vector3.UP * (height * 0.66 - fork.y))
	var top := _support_point(leader + sideways * reach * curve * 0.12)
	top.y = height - 1.0 - ceilf(leaf_radius * flatten)
	_record_line(lines, wood, collision, fork, leader, radius * 0.82, maxf(0.85, radius * 0.38), true)
	_record_line(lines, wood, collision, leader, top, maxf(0.85, radius * 0.38), 0.65, true)
	_record_crown_volume(groups, top, Vector3(leaf_radius * 1.05, ceilf(leaf_radius * flatten), leaf_radius))
	_record_crown_volume(groups, leader.lerp(top, 0.35), Vector3(leaf_radius * 1.25, leaf_radius * flatten * 1.10, leaf_radius * 1.20), true)
	var count := 4 + roundi(float(settings.branchiness) / 35.0)
	var branch_radius := maxf(0.85, radius * float(settings.branch_thickness) / 100.0)
	var tip_ratio := lerpf(1.0, 0.12, float(settings.branch_taper) / 100.0)
	for index in count:
		var progress := float(index) / float(count - 1)
		var angle := heading + TAU * float(index) / float(count) + random.randf_range(-0.16, 0.16)
		var radial := Vector3(cos(angle), 0, sin(angle))
		var tangent := Vector3(-sin(angle), 0, cos(angle))
		var start := _support_point(fork.lerp(leader, progress * 0.25))
		var length := reach * lerpf(1.0, 0.72, progress) * random.randf_range(0.92, 1.07)
		var end := start + radial * length
		end.y = height * (lerpf(0.66, 0.82, progress) + random.randf_range(-0.02, 0.02))
		if int(settings.crown_shape) == 2: end.y = snappedf(end.y, height * 0.08)
		var knee := start.lerp(end, 0.50) + tangent * length * curve * random.randf_range(-0.12, 0.12)
		if int(settings.branch_direction) > 0:
			var slope: float = [0.0, 0.65, 0.06, -0.20][int(settings.branch_direction)]
			end.y = clampf(knee.y + length * slope, height * 0.44, top.y)
		end.y = minf(end.y, top.y)
		knee = _support_point(knee)
		end = _support_point(end)
		var r0 := maxf(0.85, branch_radius * lerpf(1.0, 0.65, progress))
		var rm := maxf(0.65, r0 * lerpf(1.0, tip_ratio, 0.5))
		_record_line(lines, wood, collision, start, knee, r0, rm, true, true, 0.0, 0.5)
		_record_line(lines, wood, collision, knee, end, rm, maxf(0.65, r0 * tip_ratio), true, true, 0.5, 1.0)
		var size := leaf_radius * random.randf_range(0.88, 1.08)
		_record_crown_volume(groups, end, Vector3(size, size * flatten, size * random.randf_range(0.90, 1.08)))
		_record_crown_volume(groups, knee.lerp(end, 0.65), Vector3(size * 1.10, size * flatten, size), true)
		for twig in 2:
			var turn := angle + (-1.0 if twig == 0 else 1.0) * random.randf_range(0.40, 0.65)
			var anchor := _support_point(knee.lerp(end, 0.55))
			var tip := end + Vector3(cos(turn), 0, sin(turn)) * length * 0.22
			tip.y = minf(top.y, end.y + length * random.randf_range(0.20, 0.35))
			tip = _support_point(tip)
			_record_line(lines, wood, collision, anchor, tip, maxf(0.65, rm * 0.60), 0.65, true, true, 0.60, 1.0)
			_record_crown_volume(groups, tip, Vector3(size * 0.75, size * flatten * 0.80, size * 0.78))
	var noise := _volume_noise(seed, leaf_radius)
	_paint_crown_volumes(leaves, wood, groups, settings, settings, noise)
	var result := _emit(settings, wood, collision, leaves, noise, seed, material, title, model_id, lines)
	if not result.has("error"):
		result["structure"] = {"version": 1, "lines": lines, "groups": groups,
			"parameters": settings.duplicate(true), "pivot_bias": result.pivot_bias, "grid": result.grid,
			"noise_radius": leaf_radius}
	return result


## Reference-led maple: a tall rounded envelope, branches at five heights,
## broad middle and narrowing top. Saved v6 keeps its original fan silhouette.
static func _build_maple_upright(settings: Dictionary, seed: int, material: Dictionary,
	title: String, model_id: String) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 67867967
	var wood := {}
	var collision := {}
	var leaves := {}
	var lines: Array = []
	var groups: Array = []
	var height := float(settings.height)
	var radius := float(settings.trunk_width) * 0.46
	var curve := float(settings.branch_curve) / 100.0
	var heading := random.randf() * TAU
	var leaf_scale := float(settings.cluster_size) / 130.0
	leaf_scale *= lerpf(0.85, 1.18, float(settings.canopy_cohesion) / 100.0)
	var half_budget := floorf(sqrt(float(MAX_STORAGE_CELLS) / height) / float(settings.density)) * float(settings.density) * 0.5
	var reach := maxf(3.0, minf(height * float(settings.crown_spread) / 200.0 * 0.95,
		(half_budget - radius - 4.0) / (1.35 + 0.75 * leaf_scale)))
	if int(settings.crown_shape) == 1: reach *= 0.80
	var leaf_radius := maxf(1.0, snappedf(reach * 0.48 * leaf_scale, 0.25))
	var flatten := _canopy_flatten(settings)
	var vertical_radius := minf(height * 0.10, maxf(leaf_radius * flatten, height * 0.105 * leaf_scale * flatten))
	var top_height := height - 1.0 - ceilf(vertical_radius * 0.75)
	var trunk: Array[Vector3] = [Vector3.ZERO]
	for index in range(1, 7):
		var progress := float(index) / 6.0
		var bend := radius * curve * sin(progress * PI) * 1.15
		var point := _support_point(Vector3(cos(heading + progress) * bend,
			top_height * progress, sin(heading + progress) * bend))
		trunk.append(point)
		_record_line(lines, wood, collision, trunk[index - 1], point,
			maxf(0.65, radius * lerpf(1.10, 0.12, float(index - 1) / 6.0)),
			maxf(0.65, radius * lerpf(1.10, 0.12, progress)), true)
	var flare := float(settings.root_flare) / 100.0
	if flare > 0:
		for index in 4:
			var angle := heading + TAU * float(index) / 4.0
			var extent := radius * lerpf(1.0, 2.2, flare)
			_record_line(lines, wood, collision, Vector3(0, radius, 0),
				_support_point(Vector3(cos(angle) * extent, 0, sin(angle) * extent)), radius * 0.55, 0.65, true)
	_record_crown_volume(groups, trunk[-1], Vector3(leaf_radius * 0.80, ceilf(vertical_radius * 0.75), leaf_radius * 0.78))
	var count := 3 + roundi(float(settings.branchiness) / 55.0)
	var start_height := clampf(float(settings.branch_start) / 100.0, 0.24, 0.45)
	var branch_radius := maxf(0.85, radius * float(settings.branch_thickness) / 100.0)
	var tip_ratio := lerpf(1.0, 0.12, float(settings.branch_taper) / 100.0)
	for level in 5:
		var progress := float(level) / 4.0
		var altitude := lerpf(start_height, 0.85, progress)
		if int(settings.crown_shape) == 2: altitude = snappedf(altitude, 0.10)
		var envelope := sin(lerpf(0.25, 0.88, progress) * PI)
		var core := _support_point(_sample_polyline(trunk, altitude * height / top_height) + Vector3.UP * vertical_radius * 0.15)
		_record_crown_volume(groups, core, Vector3(reach * envelope * 0.55, vertical_radius * 1.12, reach * envelope * 0.53))
		for index in count:
			var angle := heading + float(level) * 2.39996 + TAU * float(index) / float(count) + random.randf_range(-0.18, 0.18)
			var radial := Vector3(cos(angle), 0, sin(angle))
			var tangent := Vector3(-sin(angle), 0, cos(angle))
			var start := _support_point(_sample_polyline(trunk, altitude * height / top_height))
			var length := reach * envelope * random.randf_range(0.86, 1.08)
			var slope := lerpf(0.12, 0.38, progress)
			if int(settings.branch_direction) > 0: slope = [0.0, 0.65, 0.06, -0.20][int(settings.branch_direction)]
			var end := start + radial * length + Vector3.UP * length * slope
			end.y = clampf(end.y, height * 0.23, top_height)
			var knee := _support_point(start.lerp(end, 0.50) + tangent * length * curve * random.randf_range(-0.14, 0.14))
			end = _support_point(end)
			var r0 := maxf(0.85, branch_radius * lerpf(1.0, 0.35, progress))
			var rm := maxf(0.65, r0 * lerpf(1.0, tip_ratio, 0.5))
			_record_line(lines, wood, collision, start, knee, r0, rm, true, true, 0.0, 0.5)
			_record_line(lines, wood, collision, knee, end, rm, maxf(0.65, r0 * tip_ratio), true, true, 0.5, 1.0)
			var size := random.randf_range(0.86, 1.10) * lerpf(1.05, 0.70, progress)
			_record_crown_volume(groups, end, Vector3(leaf_radius * size, vertical_radius * size, leaf_radius * size * 0.95))
			_record_crown_volume(groups, knee.lerp(end, 0.50), Vector3(leaf_radius * size * 1.12, vertical_radius * size, leaf_radius * size), true)
			for twig in 2:
				var turn := angle + (-1.0 if twig == 0 else 1.0) * random.randf_range(0.40, 0.70)
				var anchor := _support_point(knee.lerp(end, 0.55))
				var tip := end + Vector3(cos(turn), 0, sin(turn)) * length * 0.20
				tip.y = minf(top_height, end.y + length * random.randf_range(0.12, 0.25))
				tip = _support_point(tip)
				_record_line(lines, wood, collision, anchor, tip, maxf(0.65, rm * 0.60), 0.65, true, true, 0.60, 1.0)
				_record_crown_volume(groups, tip, Vector3(leaf_radius * size * 0.65, vertical_radius * size * 0.75, leaf_radius * size * 0.70))
	var noise := _volume_noise(seed, leaf_radius)
	_paint_crown_volumes(leaves, wood, groups, settings, settings, noise)
	var result := _emit(settings, wood, collision, leaves, noise, seed, material, title, model_id, lines)
	if not result.has("error"):
		result["structure"] = {"version": 1, "lines": lines, "groups": groups,
			"parameters": settings.duplicate(true), "pivot_bias": result.pivot_bias, "grid": result.grid,
			"noise_radius": leaf_radius}
	return result


## Mature spreading oak: flared curved trunk, staggered crooked scaffold limbs,
## lateral lower growth and ascending upper forks. Saved v4 is unchanged.
static func _build_oak_mature(settings: Dictionary, seed: int, material: Dictionary,
	title: String, model_id: String) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 982451653
	var wood := {}
	var collision := {}
	var leaves := {}
	var lines: Array = []
	var groups: Array = []
	var height := float(settings.height)
	var radius := float(settings.trunk_width) * 0.65
	var curve := float(settings.branch_curve) / 100.0
	var heading := random.randf() * TAU
	var radial := Vector3(cos(heading), 0, sin(heading))
	var tangent := Vector3(-sin(heading), 0, cos(heading))
	var flare := float(settings.root_flare) / 100.0
	var trunk: Array[Vector3] = [Vector3.ZERO]
	var trunk_top := height * 0.60
	for index in range(1, 6):
		var progress := float(index) / 5.0
		var point := _support_point(Vector3.UP * trunk_top * progress
			+ radial * radius * curve * sin(progress * PI * 0.70)
			+ tangent * radius * curve * sin(progress * PI * 1.60) * 0.45)
		var r0 := radius * (lerpf(1.05, 1.60, flare) if index == 1 else lerpf(1.08, 0.55, float(index - 1) / 5.0))
		var r1 := radius * lerpf(1.08, 0.55, progress)
		_record_line(lines, wood, collision, trunk[-1], point, r0, r1, true)
		trunk.append(point)
	# Short thick buttresses merge into the collar instead of long separate toes.
	if flare > 0:
		for index in 5:
			var angle := heading + TAU * float(index) / 5.0 + random.randf_range(-0.18, 0.18)
			var extent := radius * lerpf(1.0, 1.75, flare) * random.randf_range(0.90, 1.05)
			_record_line(lines, wood, collision, trunk[1] * 0.65,
				_support_point(Vector3(cos(angle) * extent, 0, sin(angle) * extent)), radius * 0.72, radius * 0.36, true)
	var leaf_scale := float(settings.cluster_size) / 130.0 * lerpf(0.85, 1.18, float(settings.canopy_cohesion) / 100.0)
	var half_budget := floorf(sqrt(float(MAX_STORAGE_CELLS) / height) / float(settings.density)) * float(settings.density) * 0.5
	var reach := maxf(3.0, minf(height * float(settings.crown_spread) / 200.0,
		(half_budget - radius - 4.0) / (1.45 + 0.45 * leaf_scale)))
	if int(settings.crown_shape) == 1: reach *= 0.80
	var leaf_radius := maxf(1.0, snappedf(reach * 0.30 * leaf_scale, 0.25))
	var vertical_radius := minf(height * 0.105, maxf(height * 0.075, leaf_radius) * _canopy_flatten(settings))
	var ceiling := height - 1.0 - ceilf(vertical_radius)
	var count := 5 + roundi(float(settings.branchiness) / 50.0)
	var branch_radius := maxf(0.85, radius * float(settings.branch_thickness) / 100.0)
	var tip_ratio := lerpf(1.0, 0.12, float(settings.branch_taper) / 100.0)
	for index in count:
		var progress := float(index) / float(count - 1)
		var altitude := lerpf(clampf(float(settings.branch_start) / 100.0, 0.22, 0.36), 0.56, progress)
		var start := _support_point(_sample_polyline(trunk, altitude * height / trunk_top))
		var angle := heading + float(index) * 2.39996 + random.randf_range(-0.20, 0.20)
		var outward := Vector3(cos(angle), 0, sin(angle))
		var sideways := Vector3(-sin(angle), 0, cos(angle))
		var length := reach * lerpf(1.05, 0.67, progress) * random.randf_range(0.90, 1.08)
		var end := start + outward * length + sideways * length * curve * random.randf_range(-0.20, 0.20)
		end.y = height * lerpf(0.48, 0.81, progress) + height * random.randf_range(-0.025, 0.025)
		if int(settings.crown_shape) == 2: end.y = snappedf(end.y, height * 0.10)
		if int(settings.branch_direction) > 0:
			end.y = start.y + length * [0.0, 0.65, 0.06, -0.20][int(settings.branch_direction)]
		end.y = clampf(end.y, height * 0.30, ceiling)
		end = _support_point(end)
		var knee := _support_point(start.lerp(end, 0.35) + sideways * length * curve * 0.22
			- Vector3.UP * height * curve * random.randf_range(0.025, 0.060))
		var elbow := _support_point(start.lerp(end, 0.72) - sideways * length * curve * 0.12)
		var r0 := maxf(0.85, branch_radius * lerpf(1.0, 0.55, progress))
		var rm := maxf(0.65, r0 * lerpf(1.0, tip_ratio, 0.55))
		_record_line(lines, wood, collision, start, knee, r0, maxf(0.65, r0 * 0.80), true, true, 0.0, 0.35)
		_record_line(lines, wood, collision, knee, elbow, maxf(0.65, r0 * 0.80), rm, true, true, 0.35, 0.72)
		_record_line(lines, wood, collision, elbow, end, rm, maxf(0.65, r0 * tip_ratio), true, true, 0.72, 1.0)
		var size := random.randf_range(0.85, 1.15)
		_record_crown_volume(groups, end, Vector3(leaf_radius * size, vertical_radius * size, leaf_radius * size * 0.95))
		_record_crown_volume(groups, elbow.lerp(end, 0.55), Vector3(leaf_radius, vertical_radius * 0.90, leaf_radius), true)
		# Uneven inner foliage joins the outer fans, while keeping lower forks visible.
		var inner := _support_point(knee.lerp(elbow, 0.65) + Vector3.UP * height * 0.085)
		_record_crown_volume(groups, inner, Vector3(leaf_radius * 1.10, vertical_radius * 1.20, leaf_radius), true)
		for twig in 3:
			var anchor := _support_point(knee.lerp(elbow, 0.45 + float(twig) * 0.22))
			var turn: float = angle + [-0.80, 0.65, 0.05][twig] + random.randf_range(-0.15, 0.15)
			var tip := end + Vector3(cos(turn), 0, sin(turn)) * length * 0.18
			tip += sideways * length * [-0.20, 0.22, 0.0][twig]
			tip.y = minf(ceiling, end.y + height * random.randf_range(0.065, 0.14))
			tip = _support_point(tip)
			var middle := _support_point(anchor.lerp(tip, 0.55) + sideways * length * curve * 0.10)
			_record_line(lines, wood, collision, anchor, middle, maxf(0.65, rm * 0.70), maxf(0.65, rm * 0.40), true, true, 0.50, 0.78)
			_record_line(lines, wood, collision, middle, tip, maxf(0.65, rm * 0.40), 0.65, true, true, 0.78, 1.0)
			_record_crown_volume(groups, tip, Vector3(leaf_radius * size * 0.80, vertical_radius * 0.85, leaf_radius * size * 0.85))
			_record_crown_volume(groups, middle.lerp(tip, 0.35), Vector3(leaf_radius * 0.85, vertical_radius * 0.80, leaf_radius * 0.80), true)
		if index < 3:
			var upper := _support_point(start + outward * length * 0.38 + sideways * length * 0.15)
			upper.y = snappedf(minf(ceiling, height * (0.84 + float(index) * 0.025)), 0.25)
			var bend := _support_point(knee.lerp(upper, 0.55) - sideways * length * curve * 0.20)
			_record_line(lines, wood, collision, knee, bend, maxf(0.85, r0 * 0.62), maxf(0.65, r0 * 0.35), true, true, 0.35, 0.70)
			_record_line(lines, wood, collision, bend, upper, maxf(0.65, r0 * 0.35), 0.65, true, true, 0.70, 1.0)
			_record_crown_volume(groups, bend.lerp(upper, 0.40), Vector3(leaf_radius * 1.08, vertical_radius, leaf_radius * 1.05), true)
			_record_crown_volume(groups, bend.lerp(upper, 0.75), Vector3(leaf_radius * 1.15, vertical_radius * 1.10, leaf_radius * 1.10), true)
			_record_crown_volume(groups, upper, Vector3(leaf_radius * 1.05, vertical_radius, leaf_radius))
	var noise := _volume_noise(seed, leaf_radius)
	_paint_crown_volumes(leaves, wood, groups, settings, settings, noise)
	var result := _emit(settings, wood, collision, leaves, noise, seed, material, title, model_id, lines)
	if not result.has("error"):
		result["structure"] = {"version": 1, "lines": lines, "groups": groups,
			"parameters": settings.duplicate(true), "pivot_bias": result.pivot_bias, "grid": result.grid,
			"noise_radius": leaf_radius}
	return result


## Thin spreading scaffold below a shallow, gently domed umbrella.
## Saved savanna v2/v3 keep the original sculpted builder and random sequence.
static func _build_savanna_umbrella(settings: Dictionary, seed: int, material: Dictionary,
	title: String, model_id: String) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 15485863
	var wood := {}
	var collision := {}
	var leaves := {}
	var lines: Array = []
	var groups: Array = []
	var height := float(settings.height)
	var radius := float(settings.trunk_width) * 0.48
	var curve := float(settings.branch_curve) / 100.0
	var heading := random.randf() * TAU
	var outward := Vector3(cos(heading), 0, sin(heading))
	var tangent := Vector3(-sin(heading), 0, cos(heading))
	var fork_height := height * clampf(float(settings.branch_start) / 100.0 + random.randf_range(-0.04, 0.14), 0.30, 0.55)
	var trunk: Array[Vector3] = [Vector3.ZERO]
	for index in range(1, 5):
		var progress := float(index) / 4.0
		var point := _support_point(Vector3.UP * fork_height * progress
			+ outward * radius * curve * sin(progress * PI * 0.90) * 1.80
			+ tangent * radius * curve * sin(progress * PI * 1.50) * 0.65)
		_record_line(lines, wood, collision, trunk[-1], point,
			radius * lerpf(1.18, 0.80, float(index - 1) / 4.0), radius * lerpf(1.18, 0.80, progress), true)
		trunk.append(point)
	var flare := float(settings.root_flare) / 100.0
	if flare > 0:
		for index in 4:
			var angle := heading + TAU * float(index) / 4.0
			_record_line(lines, wood, collision, trunk[1] * 0.35,
				_support_point(Vector3(cos(angle), 0, sin(angle)) * radius * lerpf(1.0, 1.70, flare)), radius * 0.65, radius * 0.32, true)
	var leaf_scale := float(settings.cluster_size) / 130.0 * lerpf(0.85, 1.18, float(settings.canopy_cohesion) / 100.0)
	var half_budget := floorf(sqrt(float(MAX_STORAGE_CELLS) / height) / float(settings.density)) * float(settings.density) * 0.5
	var reach := maxf(3.0, minf(height * float(settings.crown_spread) / 200.0 * 1.15,
		(half_budget - radius - 4.0) / (1.50 + 0.50 * leaf_scale)))
	if int(settings.crown_shape) == 1: reach *= 0.80
	var leaf_radius := maxf(1.0, snappedf(reach * 0.34 * leaf_scale, 0.25))
	var vertical_radius := maxf(1.0, minf(height * 0.075, leaf_radius * _canopy_flatten(settings)))
	var ceiling := height - 1.0 - ceilf(vertical_radius)
	var count := 3 + roundi(float(settings.branchiness) / 70.0)
	var branch_radius := maxf(0.85, radius * float(settings.branch_thickness) / 100.0)
	var tip_ratio := lerpf(1.0, 0.12, float(settings.branch_taper) / 100.0)
	for index in count:
		var angle := heading + TAU * float(index) / float(count) + random.randf_range(-0.22, 0.22)
		var radial := Vector3(cos(angle), 0, sin(angle))
		var sideways := Vector3(-sin(angle), 0, cos(angle))
		var start := _support_point(_sample_polyline(trunk, 0.80 + float(index % 3) * 0.10))
		var length := reach * random.randf_range(0.65, 0.78)
		var end := start + radial * length
		end.y = minf(ceiling, height * 0.87 + reach * random.randf_range(-0.035, 0.035))
		if int(settings.branch_direction) > 0:
			end.y = clampf(start.y + length * [0.0, 0.65, 0.06, -0.20][int(settings.branch_direction)], height * 0.55, ceiling)
		var knee := _support_point(start.lerp(end, 0.43) + sideways * length * curve * 0.25)
		var elbow := _support_point(start.lerp(end, 0.76) - sideways * length * curve * 0.15)
		end = _support_point(end)
		var r0 := branch_radius * random.randf_range(0.90, 1.08)
		_record_line(lines, wood, collision, start, knee, r0, maxf(0.65, r0 * 0.70), true, true, 0.0, 0.43)
		_record_line(lines, wood, collision, knee, elbow, maxf(0.65, r0 * 0.70), maxf(0.65, r0 * 0.40), true, true, 0.43, 0.76)
		_record_line(lines, wood, collision, elbow, end, maxf(0.65, r0 * 0.40), maxf(0.65, r0 * tip_ratio), true, true, 0.76, 1.0)
		_record_crown_volume(groups, end, Vector3(leaf_radius * 1.10, vertical_radius, leaf_radius))
		var inner := _support_point(end * 0.55)
		inner.y = minf(ceiling, end.y + reach * 0.10)
		_record_crown_volume(groups, inner, Vector3(leaf_radius * 1.20, vertical_radius, leaf_radius * 1.10), true)
		for twig in 3:
			var turn: float = angle + [-0.65, 0.65, 0.0][twig]
			var anchor := _support_point(knee.lerp(elbow, 0.40 + float(twig) * 0.25))
			var tip := end + Vector3(cos(turn), 0, sin(turn)) * reach * random.randf_range(0.27, 0.38)
			tip.y = end.y - reach * random.randf_range(0.02, 0.10)
			if int(settings.crown_shape) == 2: tip.y -= height * float(index % 2) * 0.045
			tip = _support_point(tip)
			var bend := _support_point(anchor.lerp(tip, 0.50) + sideways * length * curve * 0.12)
			_record_line(lines, wood, collision, anchor, bend, maxf(0.65, r0 * 0.45), maxf(0.65, r0 * 0.26), true, true, 0.50, 0.78)
			_record_line(lines, wood, collision, bend, tip, maxf(0.65, r0 * 0.26), 0.65, true, true, 0.78, 1.0)
			var size := random.randf_range(0.85, 1.10)
			_record_crown_volume(groups, tip, Vector3(leaf_radius * size, vertical_radius * size * 0.85, leaf_radius * size))
			_record_crown_volume(groups, end.lerp(tip, 0.45), Vector3(leaf_radius, vertical_radius * 0.90, leaf_radius), true)
			var fan_tip := _support_point(tip + sideways * reach * (0.13 if twig % 2 == 0 else -0.13))
			_record_line(lines, wood, collision, bend, fan_tip, maxf(0.65, r0 * 0.22), 0.65, true, true, 0.78, 1.0)
	var noise := _volume_noise(seed, leaf_radius)
	_paint_crown_volumes(leaves, wood, groups, settings, settings, noise)
	var result := _emit(settings, wood, collision, leaves, noise, seed, material, title, model_id, lines)
	if not result.has("error"):
		result["structure"] = {"version": 1, "lines": lines, "groups": groups,
			"parameters": settings.duplicate(true), "pivot_bias": result.pivot_bias, "grid": result.grid,
			"noise_radius": leaf_radius}
	return result


## Spruce scaffold and elongated foliage supports use the existing frozen format.
## No cone primitive, alternate renderer or individual needle geometry.
static func _build_spruce(settings: Dictionary, seed: int, material: Dictionary,
	title: String, model_id: String) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 32452843
	var wood := {}
	var collision := {}
	var leaves := {}
	var lines: Array = []
	var groups: Array = []
	var height := float(settings.height)
	var radius := float(settings.trunk_width) * 0.43
	var curve := float(settings.branch_curve) / 100.0
	var heading := random.randf() * TAU
	var trunk: Array[Vector3] = [Vector3.ZERO]
	var top_height := height - 2.0
	for index in range(1, 9):
		var progress := float(index) / 8.0
		var drift := radius * curve * sin(progress * PI) * 0.65
		var point := _support_point(Vector3(cos(heading) * drift, top_height * progress, sin(heading) * drift))
		_record_line(lines, wood, collision, trunk[-1], point,
			maxf(0.65, radius * lerpf(1.15, 0.10, float(index - 1) / 8.0)),
			maxf(0.65, radius * lerpf(1.15, 0.10, progress)), true)
		trunk.append(point)
	var flare := float(settings.root_flare) / 100.0
	if flare > 0:
		for index in 4:
			var angle := heading + TAU * float(index) / 4.0
			_record_line(lines, wood, collision, Vector3.UP * radius * 0.75,
				_support_point(Vector3(cos(angle), 0, sin(angle)) * radius * lerpf(1.0, 1.60, flare)), radius * 0.60, 0.65, true)
	var scale := float(settings.cluster_size) / 130.0 * lerpf(0.85, 1.18, float(settings.canopy_cohesion) / 100.0)
	var half_budget := floorf(sqrt(float(MAX_STORAGE_CELLS) / height) / float(settings.density)) * float(settings.density) * 0.5
	var reach := maxf(3.0, minf(height * float(settings.crown_spread) / 180.0,
		(half_budget - radius - 4.0) / (1.35 + 0.50 * scale)))
	if int(settings.crown_shape) == 1: reach *= 0.75
	var leaf_radius := maxf(1.0, reach * 0.23 * scale)
	var leaf_vertical := clampf(_canopy_flatten(settings), 0.35, 1.05)
	_record_crown_volume(groups, trunk[-1], Vector3(1.6, 3.0, 1.6))
	var start_height := clampf(float(settings.branch_start) / 100.0, 0.20, 0.45)
	var count := 3 + roundi(float(settings.branchiness) / 100.0)
	var branch_radius := maxf(0.85, radius * float(settings.branch_thickness) / 100.0)
	var tip_ratio := lerpf(1.0, 0.12, float(settings.branch_taper) / 100.0)
	for level in 9:
		var progress := float(level) / 8.0
		var altitude := lerpf(start_height, 0.91, progress)
		var envelope := pow(1.0 - progress * 0.93, 0.90)
		# Overlapping slender inner masses keep the leader clothed, while the
		# branch supports still define an irregular, open outer silhouette.
		var core := maxf(2.0, reach * envelope * 0.24 * scale)
		_record_crown_volume(groups, _sample_polyline(trunk, altitude * height / top_height),
			Vector3(core, maxf(4.0, height * 0.055 * scale), core))
		for index in count:
			var angle := heading + float(level) * 2.39996 + TAU * float(index) / float(count) + random.randf_range(-0.18, 0.18)
			var radial := Vector3(cos(angle), 0, sin(angle))
			var tangent := Vector3(-sin(angle), 0, cos(angle))
			var start := _support_point(_sample_polyline(trunk, (altitude + random.randf_range(-0.008, 0.008)) * height / top_height))
			var length := reach * envelope * random.randf_range(0.88, 1.08)
			var slope := lerpf(-0.12, 0.25, progress)
			if int(settings.branch_direction) > 0: slope = [0.0, 0.65, 0.06, -0.20][int(settings.branch_direction)]
			var end := _support_point(start + radial * length + Vector3.UP * length * slope)
			end.y = minf(end.y, top_height)
			var knee := _support_point(start.lerp(end, 0.65) - Vector3.UP * length * curve * 0.10 + tangent * length * curve * random.randf_range(-0.06, 0.06))
			var r0 := maxf(0.65, branch_radius * lerpf(1.0, 0.20, progress))
			_record_line(lines, wood, collision, start, knee, r0, maxf(0.65, r0 * 0.45), true, true, 0.0, 0.65)
			_record_line(lines, wood, collision, knee, end, maxf(0.65, r0 * 0.45), maxf(0.65, r0 * tip_ratio), true, true, 0.65, 1.0)
			var size := maxf(0.85, leaf_radius * envelope)
			var vertical := maxf(height * 0.027 * scale, size * leaf_vertical * 0.90)
			var radii := Vector3(size + absf(radial.x) * length * 0.22, vertical, size + absf(radial.z) * length * 0.22)
			_record_crown_volume(groups, knee.lerp(end, 0.45), radii)
			_record_crown_volume(groups, start.lerp(knee, 0.70), radii * 0.90, true)
			for twig in 1:
				var anchor := _support_point(start.lerp(knee, 0.60 + float(twig) * 0.30))
				var direction := (radial + tangent * (-0.65 if posmod(level + index, 2) == 0 else 0.65)).normalized()
				var tip := _support_point(anchor + direction * length * 0.48 - Vector3.UP * length * curve * 0.08)
				_record_line(lines, wood, collision, anchor, tip, maxf(0.65, r0 * 0.35), 0.65, true, true, 0.60, 1.0)
				var twig_radii := Vector3(size * 0.65 + absf(direction.x) * length * 0.12, vertical * 0.85, size * 0.65 + absf(direction.z) * length * 0.12)
				_record_crown_volume(groups, anchor.lerp(tip, 0.65), twig_radii)
	var noise := _volume_noise(seed, leaf_radius)
	_paint_crown_volumes(leaves, wood, groups, settings, settings, noise)
	var result := _emit(settings, wood, collision, leaves, noise, seed, material, title, model_id, lines)
	if not result.has("error"):
		result["structure"] = {"version": 1, "lines": lines, "groups": groups,
			"parameters": settings.duplicate(true), "pivot_bias": result.pivot_bias, "grid": result.grid,
			"noise_radius": leaf_radius}
	return result


static func _volume_noise(seed: int, radius: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = maxi(0, seed) + 104729
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.9 / maxf(3.0, radius)
	return noise


static func _paint_crown_volumes(leaves: Dictionary, wood: Dictionary, groups: Array,
	settings: Dictionary, base: Dictionary, noise: FastNoiseLite) -> void:
	var scale := float(settings.cluster_size) / float(base.cluster_size)
	scale *= lerpf(0.85, 1.18, float(settings.canopy_cohesion) / 100.0) / lerpf(0.85, 1.18, float(base.canopy_cohesion) / 100.0)
	var vertical := _canopy_flatten(settings) / _canopy_flatten(base)
	for index in groups.size():
		if posmod(index * 37 + 17, 100) >= int(settings.foliage_amount): continue
		var group: Dictionary = groups[index]
		var radii: Vector3 = group.radii * scale
		radii.y *= vertical
		if bool(group.along):
			if int(settings.foliage_along) == 0: continue
			radii *= sqrt(float(settings.foliage_along) / 100.0)
		var center: Vector3 = group.center
		center.y = minf(center.y, float(settings.height - 1) - ceilf(radii.y))
		_paint_canopy(leaves, wood, center, radii, float(settings.irregularity) / 100.0, noise, true)


static func _canopy_flatten(settings: Dictionary) -> float:
	var kind := int(settings.tree_type)
	var amount := float(settings.cluster_flatten) / 100.0
	var flatten := lerpf(0.88, 0.30, amount)
	if kind > 0: flatten = lerpf(1.10 if kind == 2 else 1.05, 0.65 if kind == 2 else 0.50, amount)
	if int(settings.crown_shape) == 1: flatten = maxf(0.65, flatten)
	return flatten


static func _build_sculpted(
	settings: Dictionary, seed: int, material: Dictionary, title: String, model_id: String,
) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 86028121
	var wood := {}
	var collision := {}
	var leaves := {}
	var height := float(settings.height)
	var lines: Array = []
	var groups: Array = []
	var shape := int(settings.crown_shape)
	var kind := int(settings.tree_type) if int(settings.generation_version) >= 3 else 0
	var radius := float(settings.trunk_width) * 0.52
	if kind == 2: radius *= 0.65
	var spread := clampf(height * float(settings.crown_spread) / 210.0, 12.0, 44.0)
	if kind == 2: spread *= 0.72
	if shape == 1:
		spread *= 0.7
	var curve := float(settings.branch_curve) / 100.0
	var roughness := float(settings.irregularity) / 100.0
	var cohesion := float(settings.canopy_cohesion) / 100.0
	var envelope_factor := 1.5 + 0.25 * float(settings.cluster_size) / 100.0 * lerpf(0.85, 1.22, cohesion) * 1.6
	var half_budget := floorf(sqrt(float(MAX_STORAGE_CELLS) / height) / float(settings.density)) * float(settings.density) * 0.5
	spread = minf(spread, (half_budget - radius * 2.0 - 4.0) / envelope_factor)
	var crown_radius := spread * 0.25 * float(settings.cluster_size) / 100.0
	crown_radius *= lerpf(0.85, 1.22, cohesion)
	if kind == 2: crown_radius *= 0.78
	var flatten := _canopy_flatten(settings)
	var noise := FastNoiseLite.new()
	noise.seed = maxi(0, seed) + 104729
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.7 / maxf(3.0, crown_radius)
	var trunk_top := height * (0.66 if shape == 1 else 0.56)
	if kind > 0: trunk_top = height * (0.84 if kind == 2 else 0.76)
	var trunk: Array[Vector3] = [Vector3.ZERO]
	var drift_angle := random.randf() * TAU
	for index in range(1, 6):
		var t := float(index) / 5.0
		var bend := sin(t * PI * 0.8) * radius * curve * 1.6
		trunk.append(Vector3(cos(drift_angle) * bend, trunk_top * t, sin(drift_angle) * bend))
	for index in 5:
		_record_line(lines, wood, collision, trunk[index], trunk[index + 1],
			radius * lerpf(1.15, 0.62, float(index) / 5.0),
			radius * lerpf(1.15, 0.62, float(index + 1) / 5.0), true)
	# Broad tapered buttresses, not disconnected decorative root blocks.
	var flare := float(settings.root_flare) / 100.0
	if flare > 0.0:
		for index in 5:
			var angle := drift_angle + TAU * float(index) / 5.0 + random.randf_range(-0.2, 0.2)
			var reach := radius * lerpf(1.2, 3.0, flare) * random.randf_range(0.8, 1.1)
			_record_line(lines, wood, collision, Vector3(0, radius * 1.3, 0),
				Vector3(cos(angle) * reach, 0, sin(angle) * reach), radius * 0.7, 0.7, true)
	var count := 4 + roundi(float(settings.branchiness) / 20.0)
	var branch_radius := radius * float(settings.branch_thickness) / 100.0
	var tip_ratio := lerpf(1.0, 0.12, float(settings.branch_taper) / 100.0)
	var middle_ratio := lerpf(1.0, tip_ratio, 0.55)
	var start_height := float(settings.branch_start) / 100.0
	if kind > 0: start_height = maxf(0.20, start_height - 0.08)
	for index in count:
		var angle := drift_angle + TAU * float(index) / 2.61803398875 + random.randf_range(-0.25, 0.25)
		var level := random.randf_range(start_height, maxf(start_height + 0.04, trunk_top / height - 0.02))
		if shape == 2:
			level = lerpf(start_height, trunk_top / height - 0.02, float(index % 3) / 2.0)
		var progress := float(index) / float(maxi(1, count - 1))
		if kind > 0:
			var tier := float(index % 3) / 2.0 if kind == 3 else progress
			level = lerpf(start_height, trunk_top / height - 0.06, tier) + random.randf_range(-0.025, 0.025)
		var start := _sample_polyline(trunk, level * height / trunk_top)
		var reach := spread * random.randf_range(0.65, 1.05)
		var rise := height * random.randf_range(0.16, 0.28) * (1.2 if shape == 1 else 1.0)
		if kind > 0:
			var taper := clampf((level - start_height) / maxf(0.1, trunk_top / height - start_height), 0.0, 1.0)
			reach *= lerpf(1.05, 0.40 if kind == 2 else 0.62, taper)
			rise = reach * random.randf_range(0.22, 0.52) if kind == 2 else reach * random.randf_range(0.08, 0.28)
		if int(settings.branch_direction) > 0:
			var slope: float = [0.0, 0.65, 0.06, -0.20][int(settings.branch_direction)]
			rise = reach * (float(slope) + random.randf_range(-0.06, 0.06))
		var end := start + Vector3(cos(angle) * reach, rise, sin(angle) * reach)
		if shape == 0 and kind == 0 and int(settings.branch_direction) == 0:
			end.y = height * random.randf_range(0.70, 0.84)
		if kind > 0 or int(settings.branch_direction) > 0:
			end.y = maxf(end.y, crown_radius * flatten + 2.0)
		end.y = minf(end.y, height - 2.0 - ceilf(crown_radius * flatten * 1.5))
		var midpoint := start.lerp(end, 0.52) + Vector3(-sin(angle), -0.35, cos(angle)) * reach * curve * 0.18
		_record_line(lines, wood, collision, start, midpoint, maxf(1.0, branch_radius), maxf(0.85, branch_radius * middle_ratio), true, true, 0.0, 0.55)
		_record_line(lines, wood, collision, midpoint, end, maxf(0.85, branch_radius * middle_ratio), maxf(0.65, branch_radius * tip_ratio), true, true, 0.55, 1.0)
		_record_group(groups, leaves, wood, end, crown_radius * random.randf_range(0.85, 1.2), flatten, roughness, noise, random, int(height))
		if kind > 0:
			for anchor in [0.38, 0.72]:
				_record_group(groups, leaves, wood, start.lerp(end, float(anchor)), crown_radius * 0.72,
					flatten, roughness, noise, random, int(height), true, int(settings.foliage_along))
		var forks := 1 + roundi(float(settings.branchiness) / 65.0)
		for fork in forks:
			var fork_angle := angle + (-1.0 if fork % 2 == 0 else 1.0) * random.randf_range(0.45, 0.95)
			var fork_start := midpoint.lerp(end, 0.25)
			var fork_slope := random.randf_range(0.1, 0.35)
			if kind > 0 or int(settings.branch_direction) > 0: fork_slope = rise / maxf(1.0, reach) * 0.55
			var fork_end := end + Vector3(cos(fork_angle), fork_slope, sin(fork_angle)) * reach * 0.42
			fork_end.y = minf(fork_end.y, height - 2.0 - ceilf(crown_radius * flatten * 1.4))
			_record_line(lines, wood, collision, fork_start, fork_end, maxf(0.85, branch_radius * 0.55), 0.65, true, true, 0.55, 1.0)
			_record_group(groups, leaves, wood, fork_end, crown_radius * random.randf_range(0.65, 0.95), flatten, roughness, noise, random, int(height))
		if cohesion > 0.25:
			_record_group(groups, leaves, wood, midpoint.lerp(end, 0.6), crown_radius * lerpf(0.5, 0.85, cohesion), flatten, roughness, noise, random, int(height))
	# Reserve headroom for foliage. The top pole is a leaf, not a cut wooden spike.
	var top_radii := Vector3(crown_radius * 1.05, ceilf(crown_radius * flatten), crown_radius)
	var top := Vector3(roundf(trunk[-1].x), 0, roundf(trunk[-1].z))
	top.y = height - 1.0 - top_radii.y
	_record_line(lines, wood, collision, trunk[-1], top, maxf(1.0, radius * 0.6), 0.8, true)
	groups.append({"center": top, "radius": crown_radius, "top": true, "radii": top_radii})
	_paint_canopy(leaves, wood, top, top_radii, roughness, noise)
	if cohesion > 0.2:
		for index in range(1, 4):
			var center := top - Vector3(0, top_radii.y * float(index) * 1.5, 0)
			center.x += random.randf_range(-0.35, 0.35) * crown_radius
			center.z += random.randf_range(-0.35, 0.35) * crown_radius
			_record_group(groups, leaves, wood, center, crown_radius * random.randf_range(0.85, 1.15), flatten, roughness, noise, random, int(height))
	var result := _emit(settings, wood, collision, leaves, noise, seed, material, title, model_id, lines)
	if not result.has("error"):
		result["structure"] = {"version": 1, "lines": lines, "groups": groups,
			"parameters": settings.duplicate(true), "pivot_bias": result.pivot_bias, "grid": result.grid}
	return result


static func _record_line(lines: Array, wood: Dictionary, collision: Dictionary,
	start: Vector3, finish: Vector3, radius0: float, radius1: float, physical: bool,
	branch := false, t0 := 0.0, t1 := 1.0) -> void:
	lines.append({"start": start, "finish": finish, "r0": radius0, "r1": radius1,
		"physical": physical, "branch": branch, "t0": t0, "t1": t1})
	_paint_tapered_line(wood, collision, start, finish, radius0, radius1, physical)


static func _record_group(groups: Array, leaves: Dictionary, wood: Dictionary,
	center: Vector3, radius: float, flatten: float, roughness: float,
	noise: FastNoiseLite, random: RandomNumberGenerator, height: int,
	along := false, coverage := 100) -> void:
	var group := {"center": center, "radius": radius, "top": false, "state": random.state}
	if along: group["along"] = true
	groups.append(group)
	if along and coverage == 0:
		# Reserve the same anchors and RNG sequence even without interior foliage.
		for draw in 10: random.randf()
		return
	var scale := sqrt(float(coverage) / 100.0) if along else 1.0
	_paint_canopy_group(leaves, wood, center, radius * scale, flatten, roughness, noise, random, height)


static func structure_errors(structure: Dictionary) -> Array[String]:
	if int(structure.get("version", 0)) != 1 or not structure.get("lines") is Array or not structure.get("groups") is Array or not structure.get("parameters") is Dictionary or not structure.get("pivot_bias") is Vector2i:
		return ["Каркас дерева повреждён или имеет неизвестную версию."]
	if structure.lines.is_empty() or structure.lines.size() > 128 or structure.groups.size() > 128:
		return ["Недопустимый размер каркаса дерева."]
	if int(structure.parameters.get("generation_version", 0)) >= 4:
		var noise_radius: Variant = structure.get("noise_radius")
		var expected_type := 4 if int(structure.parameters.generation_version) == 10 else (0 if int(structure.parameters.generation_version) == 9 else (1 if int(structure.parameters.generation_version) == 8 else mini(3, int(structure.parameters.generation_version) - 3)))
		if int(structure.parameters.get("tree_type", 0)) != expected_type or (not noise_radius is float and not noise_radius is int) or not is_finite(float(noise_radius)) or float(noise_radius) <= 0 or float(noise_radius) > 64:
			return ["Некорректный профиль кроны дерева."]
	if absi(structure.pivot_bias.x) > 128 or absi(structure.pivot_bias.y) > 128 or int(structure.parameters.get("generation_version", 0)) not in [2, 3, 4, 5, 6, 7, 8, 9, 10]:
		return ["Недопустимая привязка каркаса дерева."]
	if structure.has("grid"):
		if not structure.grid is Vector3i or structure.grid.x < 1 or structure.grid.z < 1 or structure.grid.x > 256 or structure.grid.z > 256:
			return ["Некорректная сетка каркаса дерева."]
	for line in structure.lines:
		if not line is Dictionary or not line.get("start") is Vector3 or not line.get("finish") is Vector3:
			return ["У ветви нет корректных опорных точек."]
		for key in ["r0", "r1", "t0", "t1"]:
			if not line.get(key) is float and not line.get(key) is int:
				return ["Некорректный параметр ветви."]
			if not is_finite(float(line[key])):
				return ["Неконечный параметр ветви."]
		if not line.get("branch") is bool or not line.get("physical") is bool or float(line.t0) < 0 or float(line.t1) > 1 or float(line.t0) > float(line.t1):
			return ["Некорректный профиль ветви."]
		if not line.start.is_finite() or not line.finish.is_finite() or line.start.length() > 512 or line.finish.length() > 512 or float(line.get("r0", 0)) <= 0 or float(line.get("r0", 0)) > 32 or float(line.get("r1", 0)) <= 0 or float(line.get("r1", 0)) > 32:
			return ["Недопустимая геометрия ветви."]
	for group in structure.groups:
		if int(structure.parameters.generation_version) >= 4:
			if not group is Dictionary or not group.get("along") is bool or not group.get("radii") is Vector3 or not group.radii.is_finite() or group.radii.x <= 0 or group.radii.y <= 0 or group.radii.z <= 0 or group.radii.length() > 128:
				return ["Некорректная масса кроны дерева."]
		if group is Dictionary and group.has("along") and not group.along is bool:
			return ["Некорректное распределение листвы вдоль ветвей."]
		if not group is Dictionary or not group.get("center") is Vector3 or not group.center.is_finite() or group.center.length() > 512 or float(group.get("radius", 0)) <= 0 or float(group.get("radius", 0)) > 64:
			return ["Недопустимая опора листвы."]
		if not is_finite(float(group.radius)) or not group.get("top") is bool or (not bool(group.top) and not group.get("state") is int):
			return ["Некорректный профиль листвы."]
	return []


static func build_on_structure(parameters: Dictionary, structure: Dictionary, seed: int,
	material: Dictionary, title: String, model_id: String) -> Dictionary:
	var errors := structure_errors(structure)
	if not errors.is_empty():
		return {"error": errors[0]}
	var settings := normalize(parameters)
	var base := normalize(structure.parameters)
	settings.height = base.height
	settings.density = base.density
	settings.generation_version = base.generation_version
	settings.tree_type = base.tree_type
	settings.branch_direction = base.branch_direction
	settings.crown_shape = base.crown_shape
	settings["_pivot_bias"] = structure.pivot_bias
	settings["_base_grid"] = structure.get("grid", Vector3i.ZERO)
	var wood := {}
	var collision := {}
	var leaves := {}
	var scale_radius := float(settings.branch_thickness) / float(base.branch_thickness)
	var old_tip := lerpf(1.0, 0.12, float(base.branch_taper) / 100.0)
	var new_tip := lerpf(1.0, 0.12, float(settings.branch_taper) / 100.0)
	var pattern_lines: Array = []
	for line in structure.lines:
		var r0 := float(line.r0)
		var r1 := float(line.r1)
		if bool(line.branch):
			r0 *= scale_radius * lerpf(1.0, new_tip, float(line.t0)) / lerpf(1.0, old_tip, float(line.t0))
			r1 *= scale_radius * lerpf(1.0, new_tip, float(line.t1)) / lerpf(1.0, old_tip, float(line.t1))
		r0 = clampf(r0, 0.65, 24)
		r1 = clampf(r1, 0.65, 24)
		_paint_tapered_line(wood, collision, line.start, line.finish, r0, r1, bool(line.physical))
		if settings.bark_pattern:
			var painted_line: Dictionary = line.duplicate()
			painted_line.r0 = r0
			painted_line.r1 = r1
			pattern_lines.append(painted_line)
	var noise := FastNoiseLite.new()
	noise.seed = maxi(0, seed) + 104729
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var leaf_scale := float(settings.cluster_size) / float(base.cluster_size)
	leaf_scale *= lerpf(0.85, 1.22, float(settings.canopy_cohesion) / 100.0) / lerpf(0.85, 1.22, float(base.canopy_cohesion) / 100.0)
	var flatten := _canopy_flatten(settings)
	var roughness := float(settings.irregularity) / 100.0
	for group in structure.groups:
		if bool(group.top):
			noise.frequency = 0.7 / maxf(3.0, float(group.radius) * leaf_scale)
			break
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 86028121
	if int(base.generation_version) >= 4:
		noise = _volume_noise(seed, float(structure.get("noise_radius", 8.0)))
		_paint_crown_volumes(leaves, wood, structure.groups, settings, base, noise)
	else:
		for index in structure.groups.size():
			# Stable group thinning: palette changes do not consume randomness.
			if posmod(index * 37 + 17, 100) >= int(settings.foliage_amount): continue
			var group: Dictionary = structure.groups[index]
			var leaf_radius := float(group.radius) * leaf_scale
			if bool(group.get("along", false)):
				if int(settings.foliage_along) == 0: continue
				leaf_radius *= sqrt(float(settings.foliage_along) / 100.0)
			if bool(group.top):
				var radii := Vector3(leaf_radius * 1.05, ceilf(leaf_radius * flatten), leaf_radius)
				_paint_canopy(leaves, wood, group.center, radii, roughness, noise)
			else:
				random.state = int(group.state)
				_paint_canopy_group(leaves, wood, group.center, leaf_radius, flatten, roughness, noise, random, int(settings.height))
	var result := _emit(settings, wood, collision, leaves, noise, seed, material, title, model_id, pattern_lines)
	if not result.has("error"):
		result["structure"] = structure.duplicate(true)
	return result


static func _paint_canopy_group(
	leaves: Dictionary, wood: Dictionary, center: Vector3, radius: float, flatten: float,
	roughness: float, noise: FastNoiseLite, random: RandomNumberGenerator, height: int,
) -> void:
	var radii := Vector3(radius, ceilf(radius * flatten), radius * random.randf_range(0.85, 1.1))
	center.y = minf(center.y, float(height - 1) - radii.y)
	_paint_canopy(leaves, wood, center, radii, roughness, noise)
	for index in 3:
		var angle := random.randf() * TAU
		var satellite := center + Vector3(cos(angle), random.randf_range(-0.1, 0.1), sin(angle)) * radius * 0.65
		var small := radii * random.randf_range(0.42, 0.65)
		satellite.y = minf(satellite.y, float(height - 1) - small.y)
		_paint_canopy(leaves, wood, satellite, small, roughness, noise)


static func _paint_canopy(
	leaves: Dictionary, wood: Dictionary, center: Vector3, radii: Vector3,
	roughness: float, noise: FastNoiseLite, fast_union: bool = false,
) -> void:
	var extent := radii * 1.3
	var max_contour_squared := pow(1.0 + roughness * 0.3 + 0.001, 2.0)
	var low := Vector3i((center - extent).floor())
	var high := Vector3i((center + extent).ceil())
	for y in range(maxi(0, low.y), high.y + 1):
		for z in range(low.z, high.z + 1):
			for x in range(low.x, high.x + 1):
				var cell := Vector3i(x, y, z)
				if wood.has(cell) or (fast_union and leaves.has(cell)):
					continue
				var local := (Vector3(cell) - center) / radii
				# Oak volumes overlap heavily; skip existing leaves and points beyond
				# the maximum noise contour without changing the union's geometry.
				if fast_union and local.length_squared() > max_contour_squared:
					continue
				# Coherent contour lobes. No per-voxel hash holes or floating speckles.
				var contour := 1.0 + noise.get_noise_3d(x, y, z) * roughness * 0.3 * maxf(0.0, 1.0 - absf(local.y))
				if local.length() <= contour + 0.001:
					leaves[cell] = true


static func _sample_polyline(points: Array[Vector3], t: float) -> Vector3:
	var scaled := clampf(t, 0.0, 1.0) * float(points.size() - 1)
	var index := mini(points.size() - 2, floori(scaled))
	return points[index].lerp(points[index + 1], scaled - float(index))


static func _paint_tapered_line(
	wood: Dictionary,
	collision: Dictionary,
	start: Vector3,
	finish: Vector3,
	radius_start: float,
	radius_end: float,
	physical: bool,
) -> void:
	var distance := start.distance_to(finish)
	var steps := maxi(1, ceili(distance * 1.45))
	for step in range(steps + 1):
		var t := float(step) / float(steps)
		var radius := lerpf(radius_start, radius_end, t)
		_paint_ball(wood, collision, start.lerp(finish, t), radius, physical and radius >= 1.15)


static func _paint_ball(
	wood: Dictionary, collision: Dictionary, center: Vector3, radius: float, physical: bool
) -> void:
	var low := Vector3i((center - Vector3.ONE * radius).floor())
	var high := Vector3i((center + Vector3.ONE * radius).ceil())
	var squared := radius * radius + 0.35
	for y in range(maxi(0, low.y), high.y + 1):
		for z in range(low.z, high.z + 1):
			for x in range(low.x, high.x + 1):
				var cell := Vector3i(x, y, z)
				if Vector3(cell).distance_squared_to(center) <= squared:
					wood[cell] = true
					if physical:
						collision[cell] = true


static func _paint_leaf_cluster(
	leaves: Dictionary,
	wood: Dictionary,
	center: Vector3,
	radii: Vector3,
	density: float,
	irregularity: float,
	noise: FastNoiseLite,
) -> void:
	var low := Vector3i((center - radii).floor())
	var high := Vector3i((center + radii).ceil())
	for y in range(maxi(0, low.y), high.y + 1):
		for z in range(low.z, high.z + 1):
			for x in range(low.x, high.x + 1):
				var cell := Vector3i(x, y, z)
				if wood.has(cell):
					continue
				var local := Vector3(cell) - center
				var normalized := Vector3(local.x / radii.x, local.y / radii.y, local.z / radii.z)
				var edge := normalized.length()
				var surface := 1.0 + noise.get_noise_3d(x, y, z) * irregularity * 0.22
				if edge > surface:
					continue
				if edge <= 0.72:
					leaves[cell] = true
					continue
				var keep := density + (1.0 - edge) * 0.28
				var hash_value := absf(sin(float(x * 127 + y * 311 + z * 743)) * 43758.5453)
				if fmod(hash_value, 1.0) <= keep:
					leaves[cell] = true


static func _bounds(wood: Dictionary, leaves: Dictionary) -> Dictionary:
	var minimum := Vector3i(1 << 29, 1 << 29, 1 << 29)
	var maximum := Vector3i(-(1 << 29), -(1 << 29), -(1 << 29))
	for cell in wood:
		minimum = minimum.min(cell)
		maximum = maximum.max(cell)
	for cell in leaves:
		minimum = minimum.min(cell)
		maximum = maximum.max(cell)
	return {"min": minimum, "max": maximum}


static func _contains(cell: Vector3i, size: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < size.x and cell.y < size.y and cell.z < size.z


static func _palette(bark: Color, foliage: Color) -> PackedColorArray:
	return PackedColorArray([
		Color.TRANSPARENT,
		bark.darkened(0.20), bark, bark.lightened(0.16),
		foliage.darkened(0.20), foliage, foliage.lightened(0.18),
	])
