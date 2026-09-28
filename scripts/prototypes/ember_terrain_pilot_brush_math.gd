extends RefCounted
## Pure column-brush math for the isolated terrain pilot. The session owns
## input and UndoRedo; this leaf only maps a footprint to target heights.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
## Every compact map keeps 16 source columns per game block. These edit strides
## are shared by new maps and authored test maps; they are not stored per brush.
const COARSE_CELL_SIZE := TerrainResource.CELLS_PER_BLOCK / 2
const MEDIUM_CELL_SIZE := TerrainResource.CELLS_PER_BLOCK / 8
const QUARTER_BLOCK_HEIGHT_STEP := TerrainResource.CELLS_PER_BLOCK / 4
const HALF_BLOCK_HEIGHT_STEP := TerrainResource.CELLS_PER_BLOCK / 2


static func edit_profile(scale: String, shape := "auto", requested_height_step := 0) -> Dictionary:
	var structured := scale in ["coarse", "medium"]
	return {
		"cell_stride": COARSE_CELL_SIZE if scale == "coarse" else MEDIUM_CELL_SIZE if scale == "medium" else 1,
		"height_step": HALF_BLOCK_HEIGHT_STEP if structured and requested_height_step == HALF_BLOCK_HEIGHT_STEP else QUARTER_BLOCK_HEIGHT_STEP if structured else 1,
		"shape": shape if shape in ["circle", "square"] else "square" if structured else "circle",
	}


static func preview_radius_voxels(radius_blocks: float, cell_stride: int) -> float:
	var group_radius := clampi(roundi(radius_blocks * float(TerrainResource.CELLS_PER_BLOCK) / float(cell_stride)), 1, 128)
	return float(group_radius - (1 if cell_stride > 1 else 0)) * float(cell_stride) + float(cell_stride) * 0.5


static func stepped_height(height: int, height_step: int, height_limit: int) -> int:
	if height_limit < height_step: return clampi(height, 1, height_limit)
	return clampi(roundi(float(height) / float(height_step)) * height_step, height_step, (height_limit / height_step) * height_step)


static func group_height(baseline: PackedInt32Array, width: int, x: int, z: int, cell_stride: int, height_step: int, height_limit: int) -> int:
	if cell_stride == 1: return baseline[x + z * width]
	var total := 0
	for oz in cell_stride:
		for ox in cell_stride:
			total += baseline[x + ox + (z + oz) * width]
	return stepped_height(roundi(float(total) / float(cell_stride * cell_stride)), height_step, height_limit)


static func smooth_group_height(baseline: PackedInt32Array, width: int, depth: int, group_x: int, group_z: int, cell_stride: int, height_step: int, strength_steps: int, influence: float, height_limit: int) -> int:
	var total := 0
	var count := 0
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var x := (group_x + ox) * cell_stride
			var z := (group_z + oz) * cell_stride
			if x < 0 or z < 0 or x + cell_stride > width or z + cell_stride > depth: continue
			total += group_height(baseline, width, x, z, cell_stride, height_step, height_limit)
			count += 1
	var original := group_height(baseline, width, group_x * cell_stride, group_z * cell_stride, cell_stride, height_step, height_limit)
	var average := stepped_height(roundi(float(total) / float(maxi(1, count))), height_step, height_limit)
	var maximum_steps := maxi(1, ceili(float(strength_steps) * influence))
	return stepped_height(original + clampi(average - original, -maximum_steps * height_step, maximum_steps * height_step), height_step, height_limit)


static func falloff(dx: int, dz: int, radius: int) -> float:
	return falloff_squared(dx * dx + dz * dz, radius)


static func falloff_squared(distance_squared: int, radius: int) -> float:
	if distance_squared > radius * radius:
		return 0.0
	var normalized := clampf(sqrt(float(distance_squared)) / float(maxi(1, radius)), 0.0, 1.0)
	return 1.0 - smoothstep(0.0, 1.0, normalized)


static func relief_amount(influence: float, depth: int) -> int:
	return clampi(ceili(float(depth) * influence), 1, depth)


static func noise_offset(noise: FastNoiseLite, x: int, z: int, influence: float, amplitude: int, detail: int, direction: int) -> int:
	var sample := clampf(noise.get_noise_2d(float(x), float(z)), -1.0, 1.0)
	var effective_amplitude := amplitude
	if detail == 0:
		# The existing Relief "light" profile keeps only rare low crests.
		effective_amplitude = mini(amplitude, 2)
		var light_sign := signf(sample)
		var light_magnitude := clampf((absf(sample) - 0.12) / 0.88, 0.0, 1.0)
		sample = light_sign * smoothstep(0.0, 1.0, light_magnitude)
		if direction > 0:
			sample = maxf(sample, 0.0)
		elif direction < 0:
			sample = minf(sample, 0.0)
	else:
		if direction > 0:
			sample = (sample + 1.0) * 0.5
		elif direction < 0:
			sample = -(sample + 1.0) * 0.5
	return roundi(float(effective_amplitude) * influence * sample)


static func smooth_height(baseline: PackedInt32Array, width: int, depth: int, x: int, z: int, strength: int, influence: float) -> int:
	var total := 0
	var count := 0
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var px := x + ox
			var pz := z + oz
			if px < 0 or pz < 0 or px >= width or pz >= depth:
				continue
			total += baseline[px + pz * width]
			count += 1
	var original := baseline[x + z * width]
	var average := roundi(float(total) / float(maxi(1, count)))
	var maximum_step := maxi(1, ceili(float(strength) * influence))
	return original + clampi(average - original, -maximum_step, maximum_step)
