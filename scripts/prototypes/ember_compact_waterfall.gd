@tool
extends RefCounted
## One derived spill/impact field. Authoring remains the compact terrain columns.

var info := {}
var tiles := {}
var bounds := Rect2i()
var state_texture: ImageTexture
var update_us := 0
var _pixels := PackedInt32Array()
var _metrics := PackedVector2Array()
var _state := PackedFloat32Array()

func build(source: EmberTerrainPilotResource, defer_upload := false, prepared_groups := {}) -> void:
	info.clear()
	tiles.clear()
	_pixels.clear()
	_metrics.clear()
	_state.clear()
	bounds = Rect2i()
	update_us = 0
	state_texture = null
	# The existing flat river/sea study needs no spill scan or impact field.
	if not source.has_flow(): return
	var groups: Dictionary = prepared_groups
	if groups.is_empty() and source.is_sectioned(): return
	if groups.is_empty(): groups = scan_groups(source)
	_select_spill(groups)
	if info.is_empty(): return
	info.top += source.origin_y
	info.bottom += source.origin_y
	_build_sheet()
	_build_impact(source)
	if not defer_upload: upload()


static func scan_groups(source: EmberTerrainPilotResource, offset := Vector2i.ZERO,
		world: EmberTerrainPilotResource = null) -> Dictionary:
	var groups := {}
	if source.water_flow.is_empty(): return groups
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var blocks_x := ceili(float(source.width) / 16.0)
	for block in source.water_flow.size():
		var flow := source.water_flow[block]
		if flow.length_squared() < 0.04: continue
		var start := Vector2i(block % blocks_x, block / blocks_x) * 16
		for z in range(start.y, mini(start.y + 16, source.depth)):
			for x in range(start.x, mini(start.x + 16, source.width)):
				var index := source.column_index(x, z)
				var top := source.water_levels[index]
				if source.water_materials[index] == 0 or top <= source.heights[index]: continue
				for direction: Vector2i in directions:
					if flow.dot(Vector2(direction)) < 0.2: continue
					var neighbour := Vector2i(x, z) + direction + offset
					var target := world if world != null else source
					if not target.has_column(neighbour.x, neighbour.y): continue
					var ni := target.column_index(neighbour.x, neighbour.y)
					var bottom := target.column_value("water_levels", ni)
					if target.column_value("water_materials", ni) == 0 or bottom <= target.column_value("heights", ni) or top - bottom < 4: continue
					var line := (x + offset.x + maxi(direction.x, 0)) if direction.x != 0 else (z + offset.y + maxi(direction.y, 0))
					var key := Vector4i(directions.find(direction), line, top, bottom)
					if not groups.has(key): groups[key] = []
					groups[key].append(z + offset.y if direction.x != 0 else x + offset.x)
	return groups


func _select_spill(groups: Dictionary) -> void:
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	var best_score := 0.0
	for key: Vector4i in groups:
		var sides: Array = groups[key].duplicate()
		sides.sort()
		var first: int = sides[0]
		var previous := first - 1
		for side: int in sides + [int(sides.back()) + 2]:
			if side > previous + 1:
				var width := previous - first + 1
				var score := float(width * (key.z - key.w))
				if width >= 4 and score > best_score:
					best_score = score
					var direction: Vector2i = directions[key.x]
					var mid := (first + previous + 1.0) * 0.5
					var center := Vector2(key.y, mid) if direction.x != 0 else Vector2(mid, key.y)
					info = {"center": center, "direction": Vector2(direction), "width": float(width),
						"top": float(key.z) + 0.02, "bottom": float(key.w) + 0.02,
						"lower_level": key.w, "impact": center + Vector2(direction) * 6.0}
				first = side
			previous = side


func _build_impact(source: EmberTerrainPilotResource) -> void:
	var impact: Vector2 = info.impact
	var radius: float = info.width * 0.5 + 34.0
	var start := Vector2i(maxi(0, floori(impact.x - radius)), maxi(0, floori(impact.y - radius)))
	var finish := Vector2i(mini(source.width, ceili(impact.x + radius)), mini(source.depth, ceili(impact.y + radius)))
	bounds = Rect2i(start, finish - start)
	_state.resize(bounds.size.x * bounds.size.y * 4)
	var direction: Vector2 = info.direction
	var side := Vector2(direction.y, -direction.x)
	for z in range(start.y, finish.y):
		for x in range(start.x, finish.x):
			var i := source.column_index(x, z)
			if source.column_value("water_materials", i) == 0 or source.column_value("water_levels", i) != info.lower_level or source.column_value("water_levels", i) <= source.column_value("heights", i): continue
			var p := (x - start.x) + (z - start.y) * bounds.size.x
			var delta := Vector2(x + 0.5, z + 0.5) - impact
			_pixels.append(p)
			_metrics.append(Vector2(delta.dot(side), delta.dot(direction)))
			_state[p * 4 + 2] = 8.0
			_state[p * 4 + 3] = 1.0

func upload() -> void:
	if not _state.is_empty(): state_texture = ImageTexture.create_from_image(_image())

func _build_sheet() -> void:
	var center: Vector2 = info.center
	var direction: Vector2 = info.direction
	var side := Vector2(direction.y, -direction.x)
	var columns := ceili(float(info.width) / 1.5)
	var rows := maxi(12, ceili((float(info.top) - float(info.bottom)) / 1.2))
	for column in columns:
		for row in rows:
			var vertices := PackedVector3Array()
			var uvs := PackedVector2Array()
			for corner in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				var u := float(column + corner.x) / columns
				var q := float(row + corner.y) / rows
				var t := q * q
				var point := center + side * ((u - 0.5) * float(info.width)) + direction * (-1.0 + 7.0 * q)
				vertices.append(Vector3(point.x, lerpf(float(info.top), float(info.bottom) - 0.45, t), point.y))
				uvs.append(Vector2(-4.0 - u, t))
			var mid := (vertices[0] + vertices[1] + vertices[2]) / 3.0
			var key := Vector2i(floori(mid.x / 64.0), floori(mid.z / 64.0))
			if not tiles.has(key): tiles[key] = {"vertices": PackedVector3Array(), "uvs": PackedVector2Array(), "spill": info}
			var batch: Dictionary = tiles[key]
			batch.vertices.append_array(vertices)
			batch.uvs.append_array(uvs)

func advance(seconds: float, strength: float, speed: float, foam_strength: float) -> void:
	if state_texture == null: return
	var started := Time.get_ticks_usec()
	var time := seconds * speed
	var half_width: float = info.width * 0.5
	for i in _pixels.size():
		var p := _pixels[i] * 4
		var metric := _metrics[i]
		var side := metric.x
		var forward := metric.y
		var distance := Vector2(maxf(absf(side) - half_width * 0.35, 0.0) / 1.25, forward).length()
		var mask := smoothstep(-1.0, 2.0, forward)
		var height := 0.0
		var foam := exp(-pow(forward / 1.8, 2.0)) * (1.0 - smoothstep(half_width - 2.0, half_width + 1.5, absf(side)))
		foam *= 0.55 + sin(side * 0.69 + time * 2.1) * 0.16
		var trail_age := 8.0
		for wave in 3:
			var age := fposmod(time + wave * 1.7, 5.1)
			var fade := smoothstep(0.0, 0.5, age) * (1.0 - smoothstep(3.8, 5.1, age))
			var front := absf(distance - age * 6.0)
			height += exp(-pow(front / 1.25, 2.0)) * fade * mask * 0.50
			foam += (1.0 - smoothstep(0.45, 1.15, front)) * fade * mask * 0.48
			var elapsed := age - distance / 6.0
			if elapsed >= 0.0 and elapsed < 4.0 and fade > 0.05 and mask > 0.1: trail_age = minf(trail_age, elapsed)
		_state[p] = height * strength
		_state[p + 1] = clampf(foam * strength * foam_strength, 0.0, 1.0)
		_state[p + 2] = trail_age if strength * foam_strength > 0.001 else 8.0
	state_texture.update(_image())
	update_us = Time.get_ticks_usec() - started

func displacement(point: Vector2) -> float:
	if state_texture == null or not bounds.has_point(Vector2i(floori(point.x), floori(point.y))): return 0.0
	var local := point - Vector2(bounds.position) - Vector2(0.5, 0.5)
	var cell := Vector2i(floori(local.x), floori(local.y))
	var fraction := local - Vector2(cell)
	return lerpf(lerpf(_height(cell), _height(cell + Vector2i.RIGHT), fraction.x),
		lerpf(_height(cell + Vector2i.DOWN), _height(cell + Vector2i.ONE), fraction.x), fraction.y)

func _height(cell: Vector2i) -> float:
	cell = cell.clamp(Vector2i.ZERO, bounds.size - Vector2i.ONE)
	return _state[(cell.x + cell.y * bounds.size.x) * 4]

func _image() -> Image:
	return Image.create_from_data(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBAF, _state.to_byte_array())
