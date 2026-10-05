@tool
extends RefCounted
## Derived wave distance for the trial's single channel. The compact Resource
## remains the only flow owner. Integrating along its channel avoids rotating
## a world-space wave independently at every bend and folding its phase.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")


static func texture(document: Terrain) -> ImageTexture:
	var image := build(document)
	return ImageTexture.create_from_image(image) if image != null else null


static func build(document: Terrain) -> Image:
	if document == null or document.water_flow.is_empty():
		return null
	var width := ceili(float(document.width) / Terrain.CELLS_PER_BLOCK)
	var depth := ceili(float(document.depth) / Terrain.CELLS_PER_BLOCK)
	var average := Vector2.ZERO
	for flow in document.water_flow:
		average += flow
	var along_z := absf(average.y) >= absf(average.x)
	var rows := depth if along_z else width
	var columns := width if along_z else depth
	var centers := PackedFloat32Array()
	var directions := PackedVector2Array()
	centers.resize(rows)
	directions.resize(rows)
	var valid_rows: Array[int] = []
	for row in rows:
		var weight := 0.0
		var center := 0.0
		var direction := Vector2.ZERO
		for column in columns:
			var x := column if along_z else row
			var z := row if along_z else column
			var flow := document.water_flow[x + z * width]
			var strength := flow.length_squared()
			weight += strength
			center += (float(column) + 0.5) * strength
			direction += flow * strength
		if weight > 0.00001:
			centers[row] = center / weight
			directions[row] = direction.normalized()
			valid_rows.append(row)
	if valid_rows.is_empty():
		return null
	# Continue the nearest channel row through still-water margins. Its phase
	# remains continuous while the existing flow field fades the river out.
	for row in rows:
		if directions[row] != Vector2.ZERO:
			continue
		var nearest := valid_rows[0]
		for candidate in valid_rows:
			if absi(candidate - row) < absi(nearest - row):
				nearest = candidate
		centers[row] = centers[nearest]
		directions[row] = directions[nearest]
	var distances := PackedFloat32Array()
	distances.resize(rows)
	for row in range(1, rows):
		var delta := Vector2(centers[row] - centers[row - 1], 1.0)
		if not along_z:
			delta = Vector2(delta.y, delta.x)
		var tangent := (directions[row] + directions[row - 1]).normalized()
		distances[row] = distances[row - 1] + delta.dot(tangent)
	var image := Image.create_empty(width, depth, false, Image.FORMAT_RGF)
	for row in rows:
		var cross_direction := directions[row].x if along_z else directions[row].y
		for column in columns:
			var distance := distances[row] + (float(column) + 0.5 - centers[row]) * cross_direction
			var x := column if along_z else row
			var z := row if along_z else column
			var side := (float(column) + 0.5 - centers[row]) * (directions[row].y if along_z else -directions[row].x)
			image.set_pixel(x, z, Color(distance, side, 0, 1))
	return image
