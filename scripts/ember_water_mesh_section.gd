extends RefCounted
## Derived horizontal mesh section. No scene, authored data, renderer or history.
const SIZE := 64
const PADDING := 8.0

static func build(mesh: ArrayMesh, transform: Transform3D, water_y: float, origin: Vector2, angle: float) -> Dictionary:
	var segments := PackedVector2Array()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for triangle in range(0, count - 2, 3):
			var points := PackedVector3Array()
			for corner in range(3):
				points.append(transform * vertices[indices[triangle + corner] if not indices.is_empty() else triangle + corner])
			var crossings := PackedVector2Array()
			for edge in range(3):
				var a := points[edge]
				var b := points[(edge + 1) % 3]
				if (a.y <= water_y and b.y > water_y) or (b.y <= water_y and a.y > water_y):
					var hit := a.lerp(b, (water_y - a.y) / (b.y - a.y))
					crossings.append((Vector2(hit.x, hit.z) - origin).rotated(-angle))
			if crossings.size() == 2:
				for point in crossings:
					segments.append(point)
					minimum = minimum.min(point)
					maximum = maximum.max(point)
	if segments.is_empty(): return {}
	var center := (minimum + maximum) * 0.5
	var half := (maximum - minimum) * 0.5
	var extent := half * 2.0 + Vector2.ONE * PADDING * 2.0
	var start := minimum - Vector2.ONE * PADDING
	var cell := extent / SIZE
	var inside := PackedByteArray()
	inside.resize(SIZE * SIZE)
	# Even/odd scanline fill preserves separate islands and open channels.
	for z in SIZE:
		var line := start.y + (z + 0.5) * cell.y
		var crossings := PackedFloat32Array()
		for segment in range(0, segments.size(), 2):
			var a := segments[segment]
			var b := segments[segment + 1]
			if (a.y <= line and b.y > line) or (b.y <= line and a.y > line):
				crossings.append(lerpf(a.x, b.x, (line - a.y) / (b.y - a.y)))
		crossings.sort()
		for pair in range(0, crossings.size() - 1, 2):
			var first := clampi(ceili((crossings[pair] - start.x) / cell.x - 0.5), 0, SIZE)
			var last := clampi(ceili((crossings[pair + 1] - start.x) / cell.x - 0.5), 0, SIZE)
			for x in range(first, last): inside[x + z * SIZE] = 1
	var distances := PackedFloat32Array()
	distances.resize(SIZE * SIZE)
	distances.fill(10000.0)
	for z in range(1, SIZE - 1):
		for x in range(1, SIZE - 1):
			var i := x + z * SIZE
			if inside[i] != inside[i - 1] or inside[i] != inside[i + 1] or inside[i] != inside[i - SIZE] or inside[i] != inside[i + SIZE]:
				distances[i] = minf(cell.x, cell.y) * 0.5
	var diagonal := cell.length()
	for pass_index in range(2):
		var direction := 1 if pass_index == 0 else -1
		for row in SIZE:
			var z := row if direction == 1 else SIZE - 1 - row
			for column in SIZE:
				var x := column if direction == 1 else SIZE - 1 - column
				var i := x + z * SIZE
				for offset in [Vector2i(-direction, 0), Vector2i(0, -direction), Vector2i(-direction, -direction), Vector2i(direction, -direction)]:
					var next: Vector2i = Vector2i(x, z) + offset
					if next.x < 0 or next.y < 0 or next.x >= SIZE or next.y >= SIZE: continue
					var cost := diagonal if offset.x != 0 and offset.y != 0 else cell.x if offset.x != 0 else cell.y
					distances[i] = minf(distances[i], distances[next.x + next.y * SIZE] + cost)
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RF)
	for z in SIZE:
		for x in SIZE:
			var i := x + z * SIZE
			image.set_pixel(x, z, Color(-distances[i] if inside[i] else distances[i], 0, 0, 1))
	return {"center_offset": center, "half": half, "distance_half": extent * 0.5, "distance": image}

static func build_rig(segments: Array[Vector4], water_y: float, origin: Vector2) -> Dictionary:
	const GRID := 32
	const MARGIN := 3.0
	var minimum := Vector2.INF
	var maximum := -Vector2.INF
	var discs := PackedVector3Array()
	for index in range(0, segments.size(), 2):
		var start := segments[index]
		var end := segments[index + 1]
		var radius := start.w
		if water_y < minf(start.y, end.y) - radius or water_y > maxf(start.y, end.y) + radius:
			continue
		var steps := maxi(1, ceili(start.distance_to(end) / (radius * 0.5)))
		for step in range(steps + 1):
			var point := start.lerp(end, float(step) / steps)
			var depth := water_y - point.y
			if absf(depth) >= radius:
				continue
			var section_radius := sqrt(radius * radius - depth * depth)
			var center := Vector2(point.x, point.z) - origin
			discs.append(Vector3(center.x, center.y, section_radius))
			minimum = minimum.min(center - Vector2.ONE * section_radius)
			maximum = maximum.max(center + Vector2.ONE * section_radius)
	if discs.is_empty():
		return {}
	var bounds := Rect2(minimum, maximum - minimum).grow(MARGIN)
	var cell := bounds.size / GRID
	var distances := PackedFloat32Array()
	distances.resize(GRID * GRID)
	distances.fill(MARGIN)
	for disc in discs:
		var center := Vector2(disc.x, disc.y)
		var reach := Vector2.ONE * (disc.z + MARGIN)
		var first := Vector2i(((center - reach - bounds.position) / cell).floor()).max(Vector2i.ZERO)
		var last := Vector2i(((center + reach - bounds.position) / cell).ceil()).min(Vector2i.ONE * (GRID - 1))
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var point := bounds.position + (Vector2(x, z) + Vector2.ONE * 0.5) * cell
				var index := x + z * GRID
				distances[index] = minf(distances[index], point.distance_to(center) - disc.z)
	var image := Image.create_from_data(GRID, GRID, false, Image.FORMAT_RF, distances.to_byte_array())
	image.resize(SIZE, SIZE, Image.INTERPOLATE_BILINEAR)
	return {"center_offset": bounds.get_center(), "half": (maximum - minimum) * 0.5,
		"distance_half": bounds.size * 0.5, "distance": image}


static func sample(point: Vector2, shape: Dictionary) -> float:
	var local := (point - Vector2(shape.center)).rotated(-float(shape.angle))
	var half: Vector2 = shape.distance_half
	var uv := (local / (half * 2.0) + Vector2.ONE * 0.5) * SIZE - Vector2.ONE * 0.5
	var pixel := uv.clamp(Vector2.ZERO, Vector2.ONE * (SIZE - 1))
	var low := Vector2i(pixel.floor())
	var high := (low + Vector2i.ONE).min(Vector2i.ONE * (SIZE - 1))
	var fraction := pixel - Vector2(low)
	var image: Image = shape.distance
	var value := lerpf(lerpf(image.get_pixel(low.x, low.y).r, image.get_pixel(high.x, low.y).r, fraction.x),
		lerpf(image.get_pixel(low.x, high.y).r, image.get_pixel(high.x, high.y).r, fraction.x), fraction.y)
	return value + (local.abs() - half).max(Vector2.ZERO).length()
