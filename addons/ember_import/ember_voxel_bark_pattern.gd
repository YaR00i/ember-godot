@tool
extends RefCounted
## Shared, deterministic surface-colour pattern in each wooden support's frame.
## No geometry, random-stream mutation, renderer or gameplay state.

static func normalized(parameters: Dictionary) -> Dictionary:
	var color: Variant = parameters.get("bark_pattern_color", Color("302b29"))
	if not color is Color or not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b):
		color = Color("302b29")
	return {"bark_pattern": bool(parameters.get("bark_pattern", false)),
		"bark_pattern_version": clampi(int(parameters.get("bark_pattern_version", 1)), 1, 2),
		"bark_pattern_direction": clampi(int(parameters.get("bark_pattern_direction", 0)), 0, 2),
		"bark_pattern_length": clampi(int(parameters.get("bark_pattern_length", 6)), 2, 24),
		"bark_pattern_density": clampi(int(parameters.get("bark_pattern_density", 60)), 0, 100),
		"bark_pattern_color": Color(color, 1.0)}

static func fields() -> Array[Dictionary]:
	return [
		{"key": "bark_pattern", "title": "Рисунок коры", "type": "bool"},
		{"key": "bark_pattern_direction", "title": "Направление рисунка", "options": ["Поперёк", "Вдоль", "Наклонно"]},
		{"key": "bark_pattern_color", "title": "Цвет рисунка коры", "type": "color"},
		{"key": "bark_pattern_length", "title": "Длина штрихов · vox", "min": 2, "max": 24},
		{"key": "bark_pattern_density", "title": "Насыщенность рисунка · %", "min": 0, "max": 100},
	]

static func _bucket(point: Vector3) -> Vector3i:
	return Vector3i((point / 8.0).floor())

static func _surface(wood: Dictionary, cell: Vector3i) -> bool:
	for offset in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
		if not wood.has(cell + offset): return true
	return false

static func marks(wood: Dictionary, lines: Array, seed: int, parameters: Dictionary) -> Dictionary:
	var settings := normalized(parameters)
	var result := {}
	if not settings.bark_pattern or settings.bark_pattern_density == 0: return result
	var frames: Array[Dictionary] = []
	var buckets := {}
	for line in lines:
		# Authoring float text precision must not change tile boundaries/tie breaks.
		var start: Vector3 = (line.start * 4.0).round() / 4.0
		var finish: Vector3 = (line.finish * 4.0).round() / 4.0
		var r0 := snappedf(float(line.r0), 1.0 / 64.0)
		var r1 := snappedf(float(line.r1), 1.0 / 64.0)
		var t0 := snappedf(float(line.t0), 1.0 / 1024.0)
		var t1 := snappedf(float(line.t1), 1.0 / 1024.0)
		var delta := finish - start
		var length := delta.length()
		if length < 0.01: continue
		var axis := delta / length
		var reference := Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > 0.85 else Vector3.UP
		var u := axis.cross(reference).normalized()
		var frame := {"start": start, "axis": axis, "u": u, "v": axis.cross(u),
			"length": length, "r0": r0, "r1": r1,
			"origin": t0 * length / maxf(0.01, t1 - t0) if line.branch else start.y}
		var index := frames.size()
		frames.append(frame)
		var extent := Vector3.ONE * (maxf(r0, r1) + 2.0)
		var low := _bucket(start.min(finish) - extent)
		var high := _bucket(start.max(finish) + extent)
		for y in range(low.y, high.y + 1):
			for z in range(low.z, high.z + 1):
				for x in range(low.x, high.x + 1):
					var key := Vector3i(x, y, z)
					if not buckets.has(key): buckets[key] = []
					buckets[key].append(index)
	for cell in wood:
		if not _surface(wood, cell): continue
		var point := Vector3(cell)
		var along := point.y
		var around := point.x
		var support_radius := 1.0
		var best := INF
		for index in buckets.get(_bucket(point), []):
			var frame: Dictionary = frames[index]
			var relative: Vector3 = point - frame.start
			var projection := clampf(relative.dot(frame.axis), 0.0, frame.length)
			var radial: Vector3 = relative - frame.axis * projection
			var radius := maxf(0.65, lerpf(frame.r0, frame.r1, projection / frame.length))
			var distance := radial.length_squared() / (radius * radius)
			if distance >= best: continue
			best = distance
			support_radius = radius
			along = frame.origin + projection
			var radial_v := radial.dot(frame.v)
			var radial_u := radial.dot(frame.u)
			# Text serialization discards negative zero. atan2(-0, -x) and
			# atan2(+0, -x) otherwise choose opposite sides of the cylinder seam.
			if absf(radial_v) < 0.00001: radial_v = 0.0
			if absf(radial_u) < 0.00001: radial_u = 0.0
			around = atan2(radial_v, radial_u) * radius
		if int(settings.bark_pattern_version) == 1:
			if _stroke(along, around, seed, settings): result[cell] = true
		elif _scattered_stroke(along, around, support_radius, seed, settings):
			result[cell] = true
	return result

## Independent, jittered marks with margins. No shared horizontal row centre;
## short cross strokes cannot occupy more than a fifth of the circumference.
static func _scattered_stroke(along: float, around: float, radius: float,
	seed: int, settings: Dictionary) -> bool:
	var direction := int(settings.bark_pattern_direction)
	var length := float(settings.bark_pattern_length)
	if direction != 1: length = minf(length, maxf(1.0, TAU * radius * 0.20))
	var x := around
	var y := along
	if direction == 1:
		x = along
		y = around
	elif direction == 2:
		x = (along + around) * 0.70710678
		y = (around - along) * 0.70710678
	var span := length + 2.5
	var spacing := 5.5
	var tile_x := floori(x / span)
	var tile_y := floori(y / spacing)
	# Adjacent rows are tested because a mark can cross its jittered row boundary.
	for row in range(tile_y - 1, tile_y + 2):
		var variation := int(hash(Vector3i(tile_x, row, seed))) & 0x7fffffff
		if variation % 100 >= settings.bark_pattern_density: continue
		var phase := float((variation / 101) % 1000) / 1000.0
		var jitter := float((variation / 100003) % 1000) / 1000.0
		var mark_length := maxf(1.0, length * lerpf(0.40, 0.85, phase))
		var start := float(tile_x) * span + 1.0 + (length - mark_length) * jitter
		if x < start or x > start + mark_length: continue
		var center := (float(row) + 0.5) * spacing + (jitter - 0.5) * spacing * 0.60
		center += sin(x * 0.50 + phase * TAU) * 0.20
		var width := lerpf(0.40, 0.70, phase)
		if absf(y - center) <= width: return true
	return false

static func _stroke(along: float, around: float, seed: int, settings: Dictionary) -> bool:
	var x := around
	var y := along
	if settings.bark_pattern_direction == 1:
		x = along
		y = around
	elif settings.bark_pattern_direction == 2:
		x = (along + around) * 0.70710678
		y = (around - along) * 0.70710678
	var length := float(settings.bark_pattern_length)
	var spacing := 3.5
	var tile := Vector3i(floori(x / (length * 1.35)), floori(y / spacing), seed)
	var variation := int(hash(tile)) & 0x7fffffff
	if variation % 100 >= settings.bark_pattern_density: return false
	var phase := float((variation / 101) % 1000) / 1000.0
	var start := float(tile.x) * length * 1.35 + length * phase * 0.25
	var finish := start + length * (0.45 + phase * 0.50)
	if x < start or x > finish: return false
	var center := (float(tile.y) + 0.5) * spacing + sin(x * 0.55 + phase * TAU) * 0.25
	var width := lerpf(0.40, 0.80, phase) * minf(1.0, (finish - x + 0.5) / 1.5)
	return absf(y - center) <= width
