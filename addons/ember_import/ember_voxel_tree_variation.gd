@tool
extends RefCounted
## Pure structural variation, independent of foliage RNG and global tree rotation.
## Species builders still own envelopes and rasterization; this owns the plan only.

static func supported(settings: Dictionary) -> bool:
	return int(settings.get("generation_version", 1)) in [11, 12, 13, 14, 15, 16, 17]

## Independent secondary stream: primary composition and foliage RNG stay fixed.
static func oak_laterals(seed: int, amount: int, branchiness: int, count: int) -> Array:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 86028157
	var strength := clampf(float(amount) / 100.0, 0.0, 1.0)
	var result := []
	var base_count := 1 + roundi(float(branchiness) / 50.0)
	for limb in count:
		var shoots := []
		for index in base_count:
			var hand := -1.0 if (index + limb) % 2 == 0 else 1.0
			shoots.append({"anchor": lerpf(0.35 + index * 0.22, random.randf_range(0.28, 0.85), strength),
				"turn": hand * lerpf(0.95, random.randf_range(0.70, 1.25), strength),
				"length": lerpf(0.60, random.randf_range(0.48, 0.78), strength),
				"rise": lerpf(0.18, random.randf_range(0.03, 0.30), strength)})
		result.append(shoots)
	return result

## Separate composition stream preserves every saved species plan.
static func oak_composition(seed: int, amount: int, base_count: int) -> Dictionary:
	var result := plan(seed, amount, 1, base_count)
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 67867967
	var strength := clampf(float(amount) / 100.0, 0.0, 1.0)
	var phase := random.randf() * TAU
	var fork_level := random.randf_range(0.28, 0.43)
	var fan_count := random.randi_range(2, 4)
	result.trunk_height = lerpf(1.0, random.randf_range(0.73, 1.04), strength)
	result.trunk_bend = lerpf(1.0, random.randf_range(0.65, 2.2), strength)
	result.lean = random.randf_range(-1.7, 1.7) * strength
	result.leader_phase = phase
	result.leader_height = lerpf(0.80, random.randf_range(0.73, 0.85), strength)
	result.leader_reach = lerpf(0.28, random.randf_range(0.18, 0.42), strength)
	for index in result.limbs.size():
		var limb: Dictionary = result.limbs[index]
		var progress := float(index) / float(maxi(1, result.limbs.size() - 1))
		var fan: int = index % fan_count
		limb.altitude = lerpf(lerpf(0.26, 0.56, progress), fork_level + random.randf_range(-0.07, 0.09), strength)
		limb.azimuth = lerpf(index * 2.39996, phase + TAU * float(fan) / fan_count + random.randf_range(-0.48, 0.48), strength)
		limb.end_height = lerpf(lerpf(0.48, 0.81, progress), random.randf_range(0.52, 0.82), strength)
		limb.length = lerpf(1.0, random.randf_range(0.68, 1.10), strength)
		limb.upper = false
	return result

static func plan(seed: int, amount: int, kind: int, base_count: int) -> Dictionary:
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed) + 49979687 + kind * 32452843
	var strength := clampf(float(amount) / 100.0, 0.0, 1.0)
	# Keep the accepted oak/maple RNG stream unchanged when adding profiles.
	if kind in [0, 2, 4]:
		return _slender_plan(random, strength, kind, base_count)
	var count := clampi(base_count + roundi(random.randi_range(-2, 2) * strength), 4, 8) if kind == 1 else base_count
	var levels := 1 if kind == 1 else clampi(5 + roundi(random.randi_range(-1, 1) * strength), 4, 6)
	var trunk_height := lerpf(1.0, random.randf_range(0.90, 1.08), strength)
	var trunk_bend := lerpf(1.0, random.randf_range(0.40, 1.70), strength)
	var trunk_turn := random.randf_range(-1.4, 1.4) * strength
	var lean := random.randf_range(-0.8, 0.8) * strength
	var favored := random.randf() * TAU
	var upper_count := clampi(3 + roundi(random.randi_range(-2, 0) * strength), 1, 3)
	var upper_offset := roundi(random.randi_range(0, count - 1) * strength)
	var limbs := []
	for level in levels:
		var level_count := count
		if kind == 3 and strength > 0:
			level_count = clampi(count + roundi(random.randi_range(-2, 1) * strength), 2, mini(5, 24 / levels))
		var progress := float(level) / float(maxi(1, levels - 1))
		var altitude_shift := random.randf_range(-0.035, 0.035) * strength if kind == 3 else 0.0
		for index in level_count:
			var position := float(index) / float(maxi(1, level_count - 1)) if kind == 1 else progress
			var azimuth := float(index) * 2.39996 if kind == 1 else TAU * index / level_count
			var length_factor := clampf(random.randf_range(0.65, 1.08) - maxf(0.0, cos(azimuth - favored)) * 0.15, 0.50, 1.08)
			limbs.append({"progress": position, "level": level, "index": index, "count": level_count,
				"height_shift": altitude_shift + random.randf_range(-0.025, 0.025) * strength,
				"angle_shift": random.randf_range(-0.55, 0.55) * strength,
				"length": lerpf(1.0, length_factor, strength),
				"radius": lerpf(1.0, random.randf_range(0.75, 1.10), strength),
				"rise": lerpf(1.0, random.randf_range(0.60, 1.35), strength),
				"bend": lerpf(1.0, random.randf_range(-0.9, 1.8), strength),
				"twig_count": clampi((3 if kind == 1 else 2) + roundi(random.randi_range(-2, 1 if kind == 1 else 0) * strength), 1, 4 if kind == 1 else 2),
				"twig_spread": lerpf(1.0, random.randf_range(0.60, 1.40), strength),
				"upper": posmod(index - upper_offset, count) < upper_count})
	return {"limbs": limbs, "levels": levels, "trunk_height": trunk_height,
		"trunk_bend": trunk_bend, "trunk_turn": trunk_turn, "lean": lean}


static func _slender_plan(random: RandomNumberGenerator, strength: float, kind: int, base_count: int) -> Dictionary:
	var count := clampi(base_count + roundi(random.randi_range(-2, 2) * strength), 7, 14) if kind == 2 else clampi(base_count + roundi(random.randi_range(-1, 1) * strength), 3, 5)
	var levels := clampi(9 + roundi(random.randi_range(-2, 1) * strength), 7, 10) if kind == 4 else 1
	var trunk_bend := lerpf(1.0, random.randf_range(0.45, 1.65), strength)
	var trunk_turn := random.randf_range(-0.8, 0.8) * strength
	var fork_shift := random.randf_range(-0.08, 0.08) * strength
	var favored := random.randf() * TAU
	var limbs := []
	for level in levels:
		# At most 36 spruce limbs: trunk + roots + 3 segments/limb <= 120.
		var level_count := mini(36 / levels, clampi(count + roundi(random.randi_range(-1, 1) * strength), 3, 5)) if kind == 4 else count
		var progress := float(level) / float(maxi(1, levels - 1))
		var altitude_shift := random.randf_range(-0.018, 0.018) * strength
		for index in level_count:
			var position := float(index) / float(maxi(1, level_count - 1)) if kind == 2 else progress
			var azimuth := float(index) * 2.39996 if kind == 2 else TAU * index / level_count
			var length_factor := clampf(random.randf_range(0.70, 1.06) - maxf(0.0, cos(azimuth - favored)) * 0.12, 0.58, 1.06)
			limbs.append({"progress": position, "level": level, "index": index, "count": level_count,
				"height_shift": altitude_shift + random.randf_range(-0.018, 0.018) * strength,
				"angle_shift": random.randf_range(-0.38, 0.38) * strength,
				"length": lerpf(1.0, length_factor, strength),
				"radius": lerpf(1.0, random.randf_range(0.75, 1.08), strength),
				"rise": lerpf(1.0, random.randf_range(0.65, 1.30), strength),
				"bend": lerpf(1.0, random.randf_range(-0.45, 1.65), strength),
				"twig_count": (1 if random.randf() > strength * 0.30 else 0) if kind == 4 else clampi(3 + roundi(random.randi_range(-2, 1) * strength), 1, 3 if kind == 2 else 4),
				"twig_spread": lerpf(1.0, random.randf_range(0.65, 1.20), strength)})
	return {"limbs": limbs, "levels": levels, "trunk_bend": trunk_bend,
		"trunk_turn": trunk_turn, "fork_shift": fork_shift}
