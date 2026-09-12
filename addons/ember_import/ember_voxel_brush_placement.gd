@tool
extends RefCounted
## Shared pure placement sampling for authored and generated voxel brush sources.
## Content providers create geometry; this module owns where repeated instances land.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")


static func sample_line(from: Vector3i, to: Vector3i, spacing: int) -> Array[Vector3i]:
	var points: Array[Vector3i] = [from]
	var delta := Vector3(to - from)
	var length := delta.length()
	if length <= 0.001:
		return points
	var safe_spacing := maxi(1, spacing)
	var distance := float(safe_spacing)
	while distance < length:
		var point := Vector3i((Vector3(from) + delta * distance / length).round())
		if point != points[-1]:
			points.append(point)
		distance += safe_spacing
	if points[-1] != to:
		points.append(to)
	return points


static func sample_path(knots: Array[Vector3i], spacing: int) -> Array[Vector3i]:
	var points: Array[Vector3i] = []
	if knots.is_empty():
		return points
	points.append(knots[0])
	var safe_spacing := maxi(1, spacing)
	var remaining := float(safe_spacing)
	for knot_index in range(1, knots.size()):
		var segment_start := Vector3(knots[knot_index - 1])
		var segment_end := Vector3(knots[knot_index])
		var delta := segment_end - segment_start
		var length := delta.length()
		if length <= 0.001:
			continue
		var walked := remaining
		while walked <= length:
			var point := Vector3i((segment_start + delta * walked / length).round())
			if point != points[-1]:
				points.append(point)
			walked += safe_spacing
		remaining = walked - length
	return points


static func scatter_instances(
	target: EmberVoxelModelResource,
	placements: Array[Vector3i],
	normal: Vector3i,
	spread: int,
	seed: int,
	add_outward: bool,
	variant_count := 1,
) -> Dictionary:
	if target == null or placements.is_empty():
		return {"error": "Проведите путь россыпи по поверхности."}
	var outward := Model.axis_normal(normal)
	if outward == Vector3i.ZERO:
		return {"error": "Россыпь должна начинаться на видимой грани."}
	var safe_spread := clampi(spread, 0, 32)
	var tangents := Model.tangent_axes(outward)
	var tangent_a: Vector3i = tangents[0]
	var tangent_b: Vector3i = tangents[1]
	var random := RandomNumberGenerator.new()
	random.seed = seed
	var instances: Array[Dictionary] = []
	var occupied := {}
	for placement in placements:
		var offset_a := 0
		var offset_b := 0
		if safe_spread > 0:
			for _attempt in 8:
				offset_a = random.randi_range(-safe_spread, safe_spread)
				offset_b = random.randi_range(-safe_spread, safe_spread)
				if Vector2(offset_a, offset_b).length() <= float(safe_spread) + 0.01:
					break
		var candidate := placement + tangent_a * offset_a + tangent_b * offset_b
		var snapped := surface_placement(
			target, candidate, outward, add_outward, maxi(2, safe_spread + 1)
		)
		if snapped == Model.INVALID_CELL:
			return {
				"error": (
					"Россыпь вышла с поверхности или за край холста. "
					+ "Уменьшите разброс либо ведите дальше от края."
				)
			}
		# Keep random consumption stable even when two jittered points coincide.
		var random_turns := random.randi_range(0, 3)
		# Do not consume another random value for legacy single-source scatter.
		var variant := random.randi_range(0, variant_count - 1) if variant_count > 1 else 0
		if occupied.has(snapped):
			continue
		occupied[snapped] = true
		instances.append({"position": snapped, "turns": random_turns, "variant": variant})
	if instances.is_empty():
		return {"error": "Россыпь не нашла свободной поверхности."}
	return {"instances": instances, "seed": seed, "normal": outward}


static func surface_placement(
	target: EmberVoxelModelResource,
	candidate: Vector3i,
	outward: Vector3i,
	add_outward: bool,
	snap_distance: int,
) -> Vector3i:
	var size := target.grid_size()
	var offsets: Array[int] = [0]
	for distance in range(1, clampi(snap_distance, 1, 32) + 1):
		offsets.append(-distance)
		offsets.append(distance)
	for offset in offsets:
		var cell := candidate + outward * offset
		if not Model.contains(cell, size):
			continue
		var index := Model.index_of(cell, size)
		if add_outward:
			var support := cell - outward
			if (
				target.voxels[index] == 0
				and Model.contains(support, size)
				and target.voxels[Model.index_of(support, size)] != 0
			):
				return cell
		else:
			var outside := cell + outward
			if (
				target.voxels[index] != 0
				and (
					not Model.contains(outside, size)
					or target.voxels[Model.index_of(outside, size)] == 0
				)
			):
				return cell
	return Model.INVALID_CELL
