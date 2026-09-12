@tool
extends RefCounted
## Pure crown dressing: overlapping connected lobes, not individual random voxels.
## Supports are derived from the frozen crown volumes; no new scaffold or owner.

static func supported(settings: Dictionary) -> bool:
	return int(settings.get("tree_type", 0)) in [0, 1, 2, 3, 4] and int(settings.get("generation_version", 1)) in range(4, 18)


static func supports_style(settings: Dictionary, style: int) -> bool:
	if style == 2:
		return int(settings.get("tree_type", 0)) == 1 and int(settings.get("generation_version", 1)) in [8, 11, 16, 17]
	return supported(settings) and style in [0, 1, 3]


static func needs_style_upgrade(settings: Dictionary, style: int) -> bool:
	return (style == 1 and int(settings.get("foliage_pattern_version", 1)) < 2) or (style == 3 and int(settings.get("foliage_cloud_version", 1)) < 2)


## Broad connected pillows carry the silhouette; sparse folded leaves accent
## their outer rim. Reuses the same volumes, rasterization and leaf primitives.
static func paint_clouds(leaves: Dictionary, wood: Dictionary, center: Vector3,
	radii: Vector3, settings: Dictionary, seed: int) -> void:
	if int(settings.get("foliage_cloud_version", 1)) >= 2:
		_paint_caps(leaves, wood, center, radii, settings, seed)
		return
	var amount := float(settings.foliage_amount) / 100.0
	if amount <= 0.0: return
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.13
	var extent := radii * lerpf(0.38, 1.0, sqrt(amount))
	# Preserve the author's flatten control but avoid spherical secondary pads.
	var pad_height := minf(extent.y, (extent.x + extent.z) * 0.24)
	var body := Vector3(extent.x * 0.60, extent.y * 0.56, extent.z * 0.60)
	_lobe(leaves, wood, center, body, 4, noise, 0.04, 2)
	var count := random.randi_range(7, 10)
	var phase := random.randf() * TAU
	var pads := []
	for index in count:
		var angle := phase + TAU * float(index) / float(count) + random.randf_range(-0.18, 0.18)
		var radial := Vector3(cos(angle), 0, sin(angle))
		var offset := radial * extent * random.randf_range(0.42, 0.62)
		offset.y = extent.y * random.randf_range(-0.14, 0.28)
		var size := random.randf_range(0.42, 0.63)
		var pad := Vector3(extent.x * size, maxf(1.0, pad_height * random.randf_range(0.48, 0.78)), extent.z * size * random.randf_range(0.85, 1.15))
		var tone := 6 if offset.y > extent.y * 0.08 else 5
		_lobe(leaves, wood, center + offset, pad, tone, noise, 0.08, 2)
		pads.append({"center": center + offset, "radii": pad, "radial": radial, "tone": tone})
	var accents := float(settings.foliage_leaf_accents) / 100.0
	var leaf_size := float(settings.foliage_leaf_size)
	# Nested deterministic selection: increasing accents adds puffs, not reshuffles
	# the body, and never exposes a uniformly spiky covering of individual leaves.
	for pad: Dictionary in pads:
		var selected := random.randf() < accents * sqrt(amount)
		var direction: Vector3 = (pad.radial + Vector3.UP * random.randf_range(-0.12, 0.32)).normalized()
		var side := direction.cross(Vector3.UP).normalized()
		var size := leaf_size * random.randf_range(0.75, 1.0)
		if not selected: continue
		var attachment: Vector3 = pad.center + pad.radial * pad.radii * 0.65
		var tip := attachment + direction * minf(size * 0.35, pad.radii.length() * 0.22)
		_stem(leaves, wood, attachment, tip, settings.height, 5)
		for index in 2:
			var axis := (direction * 0.65 + side * (-0.55 if index == 0 else 0.55) + Vector3.UP * 0.12).normalized()
			var across := axis.cross(Vector3.UP).normalized()
			_leaf(leaves, wood, tip, axis, across, size, settings.height, int(pad.tone))


## Raised substantial domes, not a radial ring of thin discs. Neighbouring
## volumes overlap through broad bodies while frozen support positions persist.
static func _paint_caps(leaves: Dictionary, wood: Dictionary, center: Vector3,
	radii: Vector3, settings: Dictionary, seed: int) -> void:
	var amount := float(settings.foliage_amount) / 100.0
	if amount <= 0.0: return
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.13
	var extent := radii * lerpf(0.38, 1.0, sqrt(amount))
	# Keep author flattening; remove the extra forced flatten from revision1.
	var roof := center + Vector3.UP * extent.y * 0.14
	roof.y = minf(roof.y, float(settings.height - 1) - ceilf(extent.y * 1.12))
	var floor_height := roof.y - extent.y * 0.35
	_lobe(leaves, wood, roof, extent * Vector3(0.85, 0.82, 0.85), 5, noise, 0.045, 2, floor_height)
	var count := random.randi_range(3, 5)
	var phase := random.randf() * TAU
	var pads := []
	for index in count:
		var angle := phase + TAU * float(index) / float(count) + random.randf_range(-0.30, 0.30)
		var radial := Vector3(cos(angle), 0, sin(angle))
		var offset := radial * extent * random.randf_range(0.28, 0.43)
		offset.y = extent.y * random.randf_range(0.25, 0.48)
		var size := random.randf_range(0.48, 0.61)
		var pad := extent * Vector3(size, random.randf_range(0.48, 0.62), size * random.randf_range(0.88, 1.10))
		_lobe(leaves, wood, roof + offset, pad, 5, noise, 0.075, 2, floor_height)
		pads.append({"center": roof + offset, "radii": pad, "radial": radial})
	var accents := float(settings.foliage_leaf_accents) / 100.0
	for pad: Dictionary in pads:
		var selected := random.randf() < accents * sqrt(amount)
		var direction: Vector3 = (pad.radial + Vector3.UP * random.randf_range(0.08, 0.32)).normalized()
		var side := direction.cross(Vector3.UP).normalized()
		var size := float(settings.foliage_leaf_size) * random.randf_range(0.75, 1.0)
		if not selected: continue
		var attachment: Vector3 = pad.center + pad.radial * pad.radii * 0.65
		var tip := attachment + direction * minf(size * 0.35, pad.radii.length() * 0.22)
		_stem(leaves, wood, attachment, tip, settings.height, 5)
		for index in 2:
			var axis := (direction * 0.65 + side * (-0.55 if index == 0 else 0.55) + Vector3.UP * 0.12).normalized()
			_leaf(leaves, wood, tip, axis, axis.cross(Vector3.UP).normalized(), size, settings.height, 5)

## Hybrid dressing: an inner mass and connected, folded leaves on green shoots.
## Closest frozen wood anchors the dressing; wood/collision are never modified.
static func paint_shoots(leaves: Dictionary, wood: Dictionary, center: Vector3,
	radii: Vector3, settings: Dictionary, seed: int) -> void:
	var amount := float(settings.foliage_amount) / 100.0
	if amount <= 0.0: return
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.13
	var fullness := lerpf(0.45, 1.0, sqrt(amount))
	var extent := radii * fullness
	_lobe(leaves, wood, center, extent * 0.36, 4, noise, 0.06, 2)
	var anchor := center
	var nearest := INF
	for cell: Vector3i in wood:
		var distance := center.distance_squared_to(Vector3(cell))
		if distance < nearest:
			nearest = distance
			anchor = Vector3(cell)
	_stem(leaves, wood, anchor, center, settings.height, 4)
	var growth := (center - anchor).normalized()
	if growth.length_squared() < 0.01: growth = Vector3.UP
	var size := float(settings.foliage_leaf_size)
	var count := clampi(roundi(extent.length() * 0.50 * sqrt(amount) / sqrt(size / 5.0)), 6, 24)
	var phase := random.randf_range(-PI, PI)
	for index in count:
		var y := 1.0 - 2.0 * (float(index) + 0.5) / float(count)
		var angle := phase + index * 2.39996323
		var radial := Vector3(cos(angle) * sqrt(1.0 - y * y), y, sin(angle) * sqrt(1.0 - y * y))
		var direction := (radial + growth * 0.22).normalized()
		var finish := center + direction * extent * random.randf_range(0.82, 1.05)
		var start := center + direction * extent * 0.34
		_stem(leaves, wood, start, finish, settings.height, 5)
		var axis := (finish - start).normalized()
		var side := axis.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.01: side = Vector3.RIGHT
		side = side.rotated(axis, random.randf_range(-0.65, 0.65))
		var tone := 6 if radial.y > 0.35 and random.randf() < 0.45 else 5
		for leaf_index in 4:
			var base := start.lerp(finish, 0.48 + leaf_index * 0.16)
			var handed := -1.0 if leaf_index % 2 == 0 else 1.0
			var leaf_axis := (axis * 0.35 + side * handed + Vector3.UP * random.randf_range(-0.25, 0.28)).normalized()
			var width_axis := leaf_axis.cross(Vector3.UP).normalized()
			if width_axis.length_squared() < 0.01: width_axis = side
			var length := size * random.randf_range(0.75, 1.2)
			_leaf(leaves, wood, base, leaf_axis, width_axis, length, settings.height, tone)

static func _stem(leaves: Dictionary, wood: Dictionary, start: Vector3, finish: Vector3,
	height: int, tone: int) -> void:
	var steps := maxi(1, ceili(start.distance_to(finish) * 2.0))
	for index in steps + 1:
		_put(leaves, wood, Vector3i(start.lerp(finish, float(index) / steps).round()), height, tone)

static func _leaf(leaves: Dictionary, wood: Dictionary, base: Vector3, axis: Vector3,
	side: Vector3, length: float, height: int, tone: int) -> void:
	var normal := axis.cross(side).normalized()
	var steps := maxi(4, ceili(length * 2.0))
	for index in steps + 1:
		var t := float(index) / steps
		var width := length * 0.32 * (1.0 - absf(t * 2.0 - 1.0))
		var across := ceili(width * 2.0)
		for offset in range(-across, across + 1):
			var lateral := float(offset) * 0.5
			# Raised midrib, folded sides and a gently drooping tip, not a flat disc.
			var point := base + axis * length * t + side * lateral
			point += normal * (absf(lateral) * 0.38 - t * t * length * 0.12)
			var cell := Vector3i(point.round())
			_put(leaves, wood, cell, height, tone)
			if absf(lateral) < 0.51: _put(leaves, wood, cell + Vector3i.UP, height, tone)

static func _put(leaves: Dictionary, wood: Dictionary, cell: Vector3i, height: int, tone: int) -> void:
	if cell.y < 0 or cell.y >= height or wood.has(cell): return
	leaves[cell] = tone

static func paint(leaves: Dictionary, wood: Dictionary, center: Vector3, radii: Vector3,
	settings: Dictionary, seed: int) -> void:
	var amount := float(settings.foliage_amount) / 100.0
	if amount <= 0.0: return
	# Revision2 separates pattern scale from the accepted crown geometry.
	var detail := float(settings.get("foliage_geometry_detail", 55) if int(settings.get("foliage_pattern_version", 1)) >= 2 else settings.foliage_detail) / 100.0
	var random := RandomNumberGenerator.new()
	random.seed = maxi(0, seed)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = 0.13
	var fullness := lerpf(0.38, 1.0, sqrt(amount))
	# The core keeps each crown mass substantial and joins the outer leaf groups.
	_lobe(leaves, wood, center, radii * 0.68 * fullness, 4, noise, 0.04, 2)
	var count := roundi(lerpf(12.0, 28.0, detail))
	var phase := random.randf_range(-PI, PI)
	for index in count:
		var y := 1.0 - 2.0 * (float(index) + 0.5) / float(count)
		var horizontal := sqrt(maxf(0.0, 1.0 - y * y))
		var angle := phase + float(index) * 2.39996323
		var direction := Vector3(cos(angle) * horizontal, y, sin(angle) * horizontal)
		var offset := direction * radii * random.randf_range(0.53, 0.72) * fullness
		var size := random.randf_range(0.33, 0.48) * lerpf(1.12, 0.84, detail) * fullness
		var lobe_radii := radii * size * Vector3(random.randf_range(0.88, 1.18), random.randf_range(0.72, 1.08), random.randf_range(0.88, 1.18))
		var tone := 6 if random.randf() > 0.72 else 5
		var roughness := lerpf(0.04, 0.17, detail) * lerpf(0.65, 1.2, float(settings.irregularity) / 100.0)
		_lobe(leaves, wood, center + offset, lobe_radii, tone, noise, roughness, clampi(roundi(lobe_radii.length() / 8.0), 1, 4))

static func _lobe(leaves: Dictionary, wood: Dictionary, center: Vector3, radii: Vector3,
	tone: int, noise: FastNoiseLite, roughness: float, step: int, floor_height: float = -INF) -> void:
	var safe := radii.max(Vector3.ONE)
	var extent := safe * (1.0 + roughness)
	var minimum := Vector3i((center - extent).floor())
	var maximum := Vector3i((center + extent).ceil())
	var bottom := maxi(0, minimum.y)
	if is_finite(floor_height): bottom = maxi(bottom, ceili(floor_height))
	for y in range(bottom, maximum.y + 1):
		for z in range(minimum.z, maximum.z + 1):
			for x in range(minimum.x, maximum.x + 1):
				var cell := Vector3i(x, y, z)
				if wood.has(cell) or leaves.has(cell): continue
				var local := (Vector3(cell) - center) / safe
				if local.length_squared() > (1.0 + roughness) * (1.0 + roughness): continue
				# Coarse coherent edge steps; never independently delete leaf voxels.
				var contour := 1.0 + noise.get_noise_3d(floorf(float(x) / step) * step, floorf(float(y) / step) * step, floorf(float(z) / step) * step) * roughness
				if local.length_squared() <= contour * contour:
					leaves[cell] = tone

static func colorize(leaves: Dictionary, wood: Dictionary, settings: Dictionary, seed: int) -> void:
	if not supported(settings): return
	var cloud := int(settings.get("foliage_style", 0)) == 3 and int(settings.get("foliage_cloud_version", 1)) >= 2
	if not cloud and (int(settings.get("foliage_style", 0)) != 1 or int(settings.get("foliage_pattern_version", 1)) < 2): return
	var size := roundi(lerpf(9.0, 3.0, float(settings.foliage_detail) / 100.0))
	var offset := Vector3i(posmod(seed, 37), posmod(seed / 37, 41), posmod(seed / 1517, 43))
	var neighbors := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
	for cell: Vector3i in leaves:
		var exposed := false
		for direction: Vector3i in neighbors:
			if not leaves.has(cell + direction) and not wood.has(cell + direction):
				exposed = true
				break
		if not exposed: continue
		# Coordinate-owned motifs are independent of volume/Dictionary insertion order.
		var point := (Vector3(cell + offset) + Vector3.ONE * 0.5) / float(size)
		var tile := Vector3i(point.floor())
		var code := _tile_hash(tile, seed)
		var local := point - Vector3(tile) - Vector3.ONE * 0.5
		local += Vector3(float(code & 7) / 7.0 - 0.5, float((code >> 3) & 7) / 7.0 - 0.5, float((code >> 6) & 7) / 7.0 - 0.5) * 0.24
		var axes := posmod(code, 3)
		var u := local.x if axes == 0 else (local.y if axes == 1 else local.z)
		var v := local.y if axes == 0 else (local.z if axes == 1 else local.x)
		var w := local.z if axes == 0 else (local.x if axes == 1 else local.y)
		u *= -1.0 if (code & 512) != 0 else 1.0
		var distance := absf(u + v * 0.35) + absf(v) * 0.75 + absf(w) * 0.25
		var edge := lerpf(0.43, 0.61, float((code >> 10) & 15) / 15.0)
		leaves[cell] = 4 if distance > edge else (6 if distance < edge * 0.50 and u + v < -0.06 else 5)

static func _tile_hash(tile: Vector3i, seed: int) -> int:
	var value := (tile.x * 73856093) ^ (tile.y * 19349663) ^ (tile.z * 83492791) ^ (seed * 2654435761)
	value &= 0x7fffffff
	value = (value ^ (value >> 13)) * 1274126177
	return (value ^ (value >> 16)) & 0x7fffffff
