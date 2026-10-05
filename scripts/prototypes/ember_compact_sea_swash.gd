@tool
extends RefCounted
## Derived coastal coverage. One transient field feeds water, ground and queries.
## No authored terrain channel or material identity is created here.

const INLAND_LIMIT := 16
const OFFSHORE_LIMIT := 24
const HEIGHT_LIMIT := 4
const TILE_SIZE := 64
const NEIGHBOURS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const GPU = preload("res://scripts/prototypes/ember_compact_sea_swash_gpu.gd")
const QUERY_CACHE_LIMIT := 512

var bounds := Rect2i()
var info_texture: ImageTexture
var state_texture: Texture2D
var foam_age_texture: Texture2D
var dry_tiles := {}
var records := PackedVector4Array() # x, z, signed shore distance, authored level
var _source: EmberTerrainPilotResource
var _slots := PackedInt32Array()
var _info := PackedFloat32Array()
var _state := PackedFloat32Array()
var _foam_age := PackedFloat32Array()
var _record_pixels := PackedInt32Array()
var _phase_groups := PackedByteArray()
var _distance_groups := PackedByteArray()
var _grain_sin := PackedFloat32Array()
var _grain_cos := PackedFloat32Array()
var _last_time := -1.0
var update_us := 0
var active_height := 0.0
var use_gpu := true # Test/headless reference switch; not authored gameplay data.
var _gpu: RefCounted
var _history: Array[PackedFloat64Array] = []
var _history_span := 0.0
var _history_limit := 8.0
var _query_cache := {}
var _query_touched := {}
var _step := 0
var _last_parameters := PackedFloat64Array()
var coordinate_origin := Vector2i.ZERO
var _static_records := PackedFloat32Array()
static var _profile_key := PackedFloat64Array()
static var _profile_values := {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _gpu != null: _gpu.release()


func build(source: EmberTerrainPilotResource, ocean_mask := PackedByteArray(),
		origin := Vector2i.ZERO, core := Rect2i(), defer_upload := false,
		present := PackedByteArray(), cancelled := Callable()) -> void:
	if _gpu != null: _gpu.release(); _gpu = null
	_history.clear()
	_query_cache.clear()
	_query_touched.clear()
	_history_span = 0.0
	_history_limit = 8.0
	_last_parameters.clear()
	_step = 0
	_source = source
	coordinate_origin = origin
	dry_tiles.clear()
	records.clear()
	info_texture = null
	state_texture = null
	foam_age_texture = null
	bounds = Rect2i()
	_last_time = -1.0
	var count := source.width * source.depth
	var river_guard := PackedByteArray()
	river_guard.resize(count)
	river_guard.fill(0)
	var blocks_x := ceili(float(source.width) / 16.0)
	for block in source.water_flow.size():
		if source.water_flow[block].length_squared() <= 0.0001: continue
		var bx := (block % blocks_x) * 16
		var bz := (block / blocks_x) * 16
		for z in range(maxi(0, bz - 2), mini(source.depth, bz + 18)):
			for x in range(maxi(0, bx - 2), mini(source.width, bx + 18)):
					river_guard[x + z * source.width] = 1
	# Open sea is connected to a wet map edge. Calm isolated pools are not sea.
	var ocean := PackedByteArray()
	ocean.resize(count)
	ocean.fill(0)
	var ocean_queue := PackedInt32Array()
	for z in (source.depth if ocean_mask.is_empty() else 0):
		for x in source.width:
			if x != 0 and z != 0 and x != source.width - 1 and z != source.depth - 1: continue
			var index := x + z * source.width
			if not _wet(index) or river_guard[index] != 0: continue
			ocean[index] = 1
			ocean_queue.append(index)
	var ocean_cursor := 0
	while ocean_cursor < ocean_queue.size():
		if ocean_cursor % 1024 == 0 and cancelled.is_valid() and cancelled.call(): return
		var index := ocean_queue[ocean_cursor]
		ocean_cursor += 1
		var cell := Vector2i(index % source.width, index / source.width)
		for direction in NEIGHBOURS:
			var neighbour: Vector2i = cell + direction
			if not _inside(neighbour): continue
			var n := neighbour.x + neighbour.y * source.width
			if ocean[n] != 0 or river_guard[n] != 0 or not _wet(n): continue
			ocean[n] = 1
			ocean_queue.append(n)
	if not ocean_mask.is_empty(): ocean = ocean_mask
	_slots.resize(count)
	_slots.fill(-1)
	var queue := PackedVector4Array()
	# Seed only sea banks. Moving river cells retain their accepted renderer.
	for z in source.depth:
		if cancelled.is_valid() and cancelled.call(): return
		for x in source.width:
			var i := x + z * source.width
			if ocean[i] == 0: continue
			for direction in NEIGHBOURS:
				var p: Vector2i = Vector2i(x, z) + direction
				if not _inside(p): continue
				var n := p.x + p.y * source.width
				if not present.is_empty() and present[n] == 0: continue
				if _wet(n) or river_guard[n] != 0 or source.heights[n] > source.water_levels[i] + HEIGHT_LIMIT: continue
				if _slots[i] < 0:
					_slots[i] = queue.size()
					queue.append(Vector4(x, z, -0.5, source.water_levels[i]))
				if _slots[n] < 0:
					_slots[n] = queue.size()
					queue.append(Vector4(p.x, p.y, 0.5, source.water_levels[i]))
	var cursor := 0
	while cursor < queue.size():
		if cursor % 1024 == 0 and cancelled.is_valid() and cancelled.call(): return
		var item := queue[cursor]
		cursor += 1
		var dry := item.z > 0.0
		var distance := absf(item.z) + 1.0
		if distance > (INLAND_LIMIT if dry else OFFSHORE_LIMIT): continue
		for direction in NEIGHBOURS:
			var p: Vector2i = Vector2i(int(item.x), int(item.y)) + direction
			if not _inside(p): continue
			var i := p.x + p.y * source.width
			if not present.is_empty() and present[i] == 0: continue
			if _slots[i] >= 0 or _wet(i) == dry: continue
			if not dry and ocean[i] == 0: continue
			if dry and river_guard[i] != 0: continue
			if dry and source.heights[i] > item.w + HEIGHT_LIMIT: continue
			_slots[i] = queue.size()
			queue.append(Vector4(p.x, p.y, distance if dry else -distance, item.w))
	records = queue
	_prepare_records(source, origin, core, defer_upload)


func restore_static(source: EmberTerrainPilotResource, saved: PackedVector4Array,
		origin: Vector2i, core: Rect2i) -> bool:
	# Used only on a fresh field. Reconstruct transient state from the same records.
	var slots := PackedInt32Array()
	slots.resize(source.width * source.depth)
	slots.fill(-1)
	for index in saved.size():
		var item := saved[index]
		if not item.is_finite() or item.x != floorf(item.x) or item.y != floorf(item.y): return false
		if item.x < 0 or item.y < 0 or item.x >= source.width or item.y >= source.depth: return false
		if absf(item.z) < 0.5 or absf(item.z) > (INLAND_LIMIT + 0.5 if item.z > 0 else OFFSHORE_LIMIT + 0.5): return false
		if item.w < 0 or item.w > source.height_limit: return false
		var at := int(item.x) + int(item.y) * source.width
		if slots[at] >= 0: return false
		slots[at] = index
	_source = source
	coordinate_origin = origin
	_slots = slots
	records = saved
	_prepare_records(source, origin, core, true)
	return true


func _prepare_records(source: EmberTerrainPilotResource, origin: Vector2i,
		core: Rect2i, defer_upload: bool) -> void:
	if records.is_empty(): return
	var low := Vector2i(source.width, source.depth)
	var high := Vector2i.ZERO
	for item in records:
		var p := Vector2i(int(item.x), int(item.y))
		low = Vector2i(mini(low.x, p.x), mini(low.y, p.y))
		high = Vector2i(maxi(high.x, p.x), maxi(high.y, p.y))
		if item.z > 0.0 and (not core.has_area() or core.has_point(p + origin)):
			var tile := Vector2i((p.x + origin.x) / TILE_SIZE, (p.y + origin.y) / TILE_SIZE)
			if not dry_tiles.has(tile): dry_tiles[tile] = PackedVector4Array()
			var cells: PackedVector4Array = dry_tiles[tile]
			cells.append(Vector4(p.x + origin.x, p.y + origin.y, source.origin_y + source.heights[p.x + p.y * source.width], item.w))
			dry_tiles[tile] = cells
	bounds = Rect2i(low, high - low + Vector2i.ONE)
	_info.resize(bounds.size.x * bounds.size.y * 4)
	_info.fill(0.0)
	_state.resize(_info.size())
	_state.fill(0.0)
	_foam_age.resize(bounds.size.x * bounds.size.y)
	_foam_age.fill(8.0)
	_record_pixels.resize(records.size())
	_phase_groups.resize(records.size())
	_distance_groups.resize(records.size())
	_grain_sin.resize(records.size())
	_grain_cos.resize(records.size())
	for index in records.size():
		var item := records[index]
		var p := Vector2i(int(item.x), int(item.y))
		var slot := _pixel(p) * 4
		_record_pixels[index] = slot
		var phase_offset := sin((item.x + origin.x) * 0.025 + (item.y + origin.y) * 0.018) * 0.035
		_phase_groups[index] = roundi((phase_offset + 0.035) / 0.07 * 64.0)
		_distance_groups[index] = roundi(item.z + 23.5)
		var grain_angle := (item.x + origin.x) * 1.13 + (item.y + origin.y) * 0.71 + phase_offset * TAU
		_grain_sin[index] = sin(grain_angle)
		_grain_cos[index] = cos(grain_angle)
		_info[slot] = item.z
		_info[slot + 1] = source.origin_y + source.heights[p.x + p.y * source.width]
		_info[slot + 2] = source.origin_y + item.w
		_info[slot + 3] = 1.0
	_pack_static_records()
	if not defer_upload: upload()


func upload() -> void:
	if records.is_empty(): return
	info_texture = ImageTexture.create_from_image(_image(_info))
	if not enable_gpu():
		state_texture = ImageTexture.create_from_image(_image(_state))
		foam_age_texture = ImageTexture.create_from_image(_foam_image())


func enable_gpu() -> bool:
	# Also allows a running editor field to migrate without rebuilding its coast
	# or losing the current sand/foam history. No authored data is changed.
	if _gpu != null: return true
	if not use_gpu or records.is_empty() or DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null: return false
	if _static_records.is_empty(): _pack_static_records()
	_gpu = GPU.new()
	_gpu.initialize(bounds.size, _static_records, _state.to_byte_array(), _foam_age.to_byte_array())
	state_texture = _gpu.state_texture
	foam_age_texture = _gpu.foam_texture
	return true


func _pack_static_records() -> void:
	_static_records.resize(records.size() * 8)
	for index in records.size():
		var slot := _record_pixels[index]
		var at := index * 8
		_static_records[at] = slot / 4
		_static_records[at + 1] = _phase_groups[index]
		_static_records[at + 2] = _grain_sin[index]
		_static_records[at + 3] = _grain_cos[index]
		_static_records[at + 4] = _info[slot]
		_static_records[at + 5] = _info[slot + 1]
		_static_records[at + 6] = _info[slot + 2]


func advance(seconds: float, height: float, period: float, reach: float, offset: float, drying: float,
	approach := 20.0, offshore_strength := 0.65) -> void:
	if state_texture == null: return
	active_height = height
	var started := Time.get_ticks_usec()
	var parameters := PackedFloat64Array([seconds, height, period, reach, offset, drying, approach, offshore_strength])
	if parameters == _last_parameters: update_us = 0; return
	_last_parameters = parameters
	var reset := seconds < _last_time
	if reset:
		_state.fill(0.0)
		_foam_age.fill(8.0)
		_history.clear(); _query_cache.clear(); _query_touched.clear(); _history_span = 0.0
	var dt := clampf(seconds - _last_time, 0.0, 0.25) if _last_time >= 0.0 else 0.0
	_last_time = seconds
	var cycle := seconds / maxf(period, 4.0)
	var grain_sine := sin(cycle * TAU)
	var grain_cosine := cos(cycle * TAU)
	# Half-cell shore distances form just 40 bins. Evaluate the profile once
	# per distance/phase bin, rather than repeated exponentials for every cell.
	var table_key := PackedFloat64Array([seconds, height, period, reach, approach, offshore_strength])
	var table := profile_table(table_key)
	var profiles: PackedVector2Array = table.profiles
	var incoming: PackedByteArray = table.incoming
	var crest_fronts: PackedFloat32Array = table.fronts
	var drying_step := dt / maxf(drying, 1.0)
	if _gpu != null:
		_gpu.update(table.bytes, PackedFloat32Array([dt, drying_step, offset, height,
			grain_cosine, grain_sine, 1.0 if reset else 0.0, records.size()]).to_byte_array())
		_record_query_history(PackedFloat64Array([seconds, dt, height, period, reach, offset, drying, approach, offshore_strength]))
		update_us = Time.get_ticks_usec() - started
		return
	_update_cpu(profiles, incoming, crest_fronts, dt, drying_step, offset, height, grain_cosine, grain_sine)
	update_us = Time.get_ticks_usec() - started


static func profile_table(key: PackedFloat64Array) -> Dictionary:
	if key == _profile_key: return _profile_values
	_profile_key = key
	var cycle := key[0] / maxf(key[2], 4.0)
	var profiles := PackedVector2Array() # Shared by all regional GPU dispatches.
	profiles.resize(65 * 40)
	var incoming := PackedByteArray()
	incoming.resize(65)
	var crest_fronts := PackedFloat32Array()
	crest_fronts.resize(65)
	for group in 65:
		var phase := fposmod(cycle + (float(group) / 64.0 - 0.5) * 0.07, 1.0)
		incoming[group] = 1 if phase < 0.66 else 0
		var front := wave_front(phase, key[3], key[4])
		crest_fronts[group] = front
		for distance_group in 40:
			var distance := float(distance_group) - 23.5
			profiles[group * 40 + distance_group] = wave_profile(distance, phase, key[1], key[3], key[4], key[5])
	var phases := PackedVector2Array()
	phases.resize(65)
	for group in 65: phases[group] = Vector2(incoming[group], crest_fronts[group])
	var bytes := profiles.to_byte_array()
	bytes.append_array(phases.to_byte_array())
	_profile_values = {"profiles": profiles, "incoming": incoming, "fronts": crest_fronts, "bytes": bytes}
	return _profile_values


func _update_cpu(profiles: PackedVector2Array, incoming: PackedByteArray, crest_fronts: PackedFloat32Array,
		dt: float, drying_step: float, offset: float, height: float, grain_cosine: float, grain_sine: float) -> void:
	for index in records.size():
		var slot := _record_pixels[index]
		var distance := _info[slot]
		var floor_y := _info[slot + 1]
		var sea_y := _info[slot + 2] + 0.02 + offset
		# A slow, continuous approach, brief run-up, and longer draining tail.
		# Shore-distance bends the front along the actual coast; phase drift is smooth.
		var profile := profiles[_phase_groups[index] * 40 + _distance_groups[index]]
		var surface := sea_y + profile.x
		var depth := surface - floor_y
		var coverage := smoothstep(0.02, 0.20, depth) if distance > 0.0 else 1.0
		if height <= 0.001 and distance > 0.0: coverage = 0.0
		var edge := 1.0 - smoothstep(0.05, 0.75, maxf(depth, 0.0))
		var grain := 0.80 + 0.20 * (_grain_sin[index] * grain_cosine + _grain_cos[index] * grain_sine)
		var foam := (edge * 0.75 + profile.y) * coverage * grain if height > 0.001 else 0.0
		_state[slot] = maxf(surface, floor_y + 0.025) if distance > 0.0 else surface
		_state[slot + 1] = clampf(foam, 0.0, 1.0)
		_state[slot + 2] = maxf(maxf(_state[slot + 2] - drying_step, 0.0), coverage) if distance > 0.0 else 0.0
		_state[slot + 3] = coverage
		# Foam is born from the same incoming crest/contact edge, then ages in
		# place behind it. Retreat never continually repaints a fresh white web.
		var pixel := slot / 4
		_foam_age[pixel] = minf(_foam_age[pixel] + dt, 8.0)
		if incoming[_phase_groups[index]] != 0 and distance <= crest_fronts[_phase_groups[index]] + 0.5 and profile.x > 0.12 and foam > 0.07:
			_foam_age[pixel] = 0.0
	(state_texture as ImageTexture).update(_image(_state))
	(foam_age_texture as ImageTexture).update(_foam_image())


func _record_query_history(context: PackedFloat64Array) -> void:
	# Preserve history for cold physics queries without reading the GPU back.
	# Only queried cells are evaluated on CPU; their count is bounded and expires.
	_step += 1
	_history.append(context)
	_history_span += context[1]
	_history_limit = maxf(_history_limit, maxf(context[6], 1.0))
	while _history.size() > 1 and _history_span - _history[0][1] > _history_limit:
		_history_span -= _history.pop_front()[1]
	for index: int in _query_cache.keys():
		if _step - int(_query_touched[index]) > 20:
			_query_cache.erase(index); _query_touched.erase(index)
		else:
			_query_cache[index] = _query_step(index, context, _query_cache[index])


func _query_step(index: int, context: PackedFloat64Array, previous: PackedFloat32Array) -> PackedFloat32Array:
	var slot := _record_pixels[index]
	var seconds := context[0]
	var height := context[2]
	var cycle := seconds / maxf(context[3], 4.0)
	var phase := fposmod(cycle + (float(_phase_groups[index]) / 64.0 - 0.5) * 0.07, 1.0)
	var distance := _info[slot]
	var floor_y := _info[slot + 1]
	var profile := wave_profile(float(_distance_groups[index]) - 23.5, phase, height, context[4], context[7], context[8])
	var surface := _info[slot + 2] + 0.02 + context[5] + profile.x
	var depth := surface - floor_y
	var coverage := smoothstep(0.02, 0.20, depth) if distance > 0.0 else 1.0
	if height <= 0.001 and distance > 0.0: coverage = 0.0
	var edge := 1.0 - smoothstep(0.05, 0.75, maxf(depth, 0.0))
	var grain := 0.80 + 0.20 * (_grain_sin[index] * cos(cycle * TAU) + _grain_cos[index] * sin(cycle * TAU))
	var foam := (edge * 0.75 + profile.y) * coverage * grain if height > 0.001 else 0.0
	var wetness := maxf(maxf(previous[2] - context[1] / maxf(context[6], 1.0), 0.0), coverage) if distance > 0.0 else 0.0
	var age := minf(previous[4] + context[1], 8.0)
	if phase < 0.66 and distance <= wave_front(phase, context[4], context[7]) + 0.5 and profile.x > 0.12 and foam > 0.07: age = 0.0
	return PackedFloat32Array([maxf(surface, floor_y + 0.025) if distance > 0.0 else surface,
		clampf(foam, 0.0, 1.0), wetness, coverage, age])


func _query_state(index: int) -> PackedFloat32Array:
	if not _query_cache.has(index):
		var value := _query_baseline(index)
		for context in _history: value = _query_step(index, context, value)
		if _query_cache.size() >= QUERY_CACHE_LIMIT:
			var oldest: int = _query_cache.keys()[0]
			_query_cache.erase(oldest); _query_touched.erase(oldest)
		_query_cache[index] = value
	_query_touched[index] = _step
	return _query_cache[index]


func _query_baseline(index: int) -> PackedFloat32Array:
	var slot := _record_pixels[index]
	return PackedFloat32Array([_state[slot], _state[slot + 1], _state[slot + 2], _state[slot + 3], _foam_age[slot / 4]])


func _query_current(index: int) -> PackedFloat32Array:
	# Physics needs the current surface, not an entire replay of sand history.
	return _query_step(index, _history[-1], _query_baseline(index)) if not _history.is_empty() else _query_baseline(index)


static func wave_front(phase: float, reach: float, approach := 20.0) -> float:
	approach = clampf(approach, 6.0, 20.0)
	if phase < 0.45: return lerpf(-approach, 0.0, smoothstep(0.0, 0.45, phase))
	if phase < 0.66: return lerpf(0.0, reach, smoothstep(0.45, 0.66, phase))
	return lerpf(reach, -approach, smoothstep(0.66, 1.0, phase))


static func wave_profile(distance: float, phase: float, height: float, reach: float,
	approach := 20.0, offshore_strength := 0.65) -> Vector2:
	var front := wave_front(phase, reach, approach)
	var width := lerpf(3.5 if distance > front else 6.0, 7.0, smoothstep(0.60, 0.72, phase))
	var envelope := (distance - front) / width
	# Flat derivatives at birth/death avoid a pulse at the cycle seam. Keep
	# the accepted coast/run-up timing; offshore amplitude grows into it.
	var arrival := sin(phase * PI) * smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.82, 1.0, phase))
	var offshore := lerpf(clampf(offshore_strength, 0.0, 1.0), 1.0,
		smoothstep(-clampf(approach, 6.0, 20.0), -2.0, distance))
	var inland := 1.0 - smoothstep(maxf(reach - 0.5, 0.0), reach + 0.5, distance) if distance > 0.0 else 1.0
	return Vector2(height * arrival * exp(-envelope * envelope) * inland * offshore,
		exp(-envelope * envelope * 9.0) * arrival * offshore * 0.55)


func incident_height(point: Vector2, seconds: float, height: float, period: float, reach: float,
	approach := 20.0, offshore_strength := 0.65) -> float:
	var cell := Vector2i(point)
	if not bounds.has_point(cell): return 0.0
	var index := _slots[cell.x + cell.y * _source.width]
	if index < 0: return 0.0
	var phase := fposmod(seconds / period + (float(_phase_groups[index]) / 64.0 - 0.5) * 0.07, 1.0)
	return wave_profile(float(_distance_groups[index]) - 23.5, phase, height, reach, approach, offshore_strength).x


func sample(cell: Vector2i, with_history := true) -> Dictionary:
	if not bounds.has_point(cell): return {}
	var index := cell.x + cell.y * _source.width
	if _slots[index] < 0: return {}
	var slot := _pixel(cell) * 4
	if _gpu != null:
		var state := _query_state(_slots[index]) if with_history else _query_current(_slots[index])
		return {"height": state[0], "foam": state[1], "wetness": state[2], "coverage": state[3],
			"foam_age": state[4], "dry_bank": _info[slot] > 0.0, "distance": _info[slot]}
	return {"height": _state[slot], "coverage": _state[slot + 3], "wetness": _state[slot + 2],
		"dry_bank": _info[slot] > 0.0, "distance": _info[slot], "foam": _state[slot + 1],
		"foam_age": _foam_age[slot / 4]}


static func coastal_influence(distance: float) -> float:
	# Same outer blend as the shader; queries must not begin abruptly at 15.
	return 1.0 - smoothstep(15.0, float(OFFSHORE_LIMIT), absf(distance))


func surface_height(point: Vector2) -> float:
	# Match the shader's bilinear corner heights; coverage stays per terrain cell.
	var pixel := point - Vector2(bounds.position) - Vector2(0.5, 0.5)
	var low := Vector2i(floori(pixel.x), floori(pixel.y))
	var fraction := pixel - Vector2(low)
	var heights := PackedFloat32Array()
	for delta in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		var cell: Vector2i = low + delta
		cell.x = clampi(cell.x, 0, bounds.size.x - 1)
		cell.y = clampi(cell.y, 0, bounds.size.y - 1)
		if _gpu != null:
			var sample_cell := cell + bounds.position
			var index := _slots[sample_cell.x + sample_cell.y * _source.width]
			heights.append(_query_current(index)[0] if index >= 0 else 0.0)
		else:
			heights.append(_state[(cell.x + cell.y * bounds.size.x) * 4])
	return lerpf(lerpf(heights[0], heights[1], fraction.x), lerpf(heights[2], heights[3], fraction.x), fraction.y)


func _wet(index: int) -> bool:
	return _source.water_materials[index] > 0 and _source.water_levels[index] > _source.heights[index]


func _inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < _source.width and p.y < _source.depth


func _pixel(p: Vector2i) -> int:
	return p.x - bounds.position.x + (p.y - bounds.position.y) * bounds.size.x


func _image(data: PackedFloat32Array) -> Image:
	return Image.create_from_data(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBAF, data.to_byte_array())


func _foam_image() -> Image:
	return Image.create_from_data(bounds.size.x, bounds.size.y, false, Image.FORMAT_RF, _foam_age.to_byte_array())
