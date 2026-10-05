@tool
extends RefCounted
## Transient preparation/cache for the existing compact water owner.
## One CPU worker reads persistent terrain snapshots. Rendering objects are
## created on the main thread; animation remains on the main RenderingDevice.

const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Sections = preload("res://scripts/prototypes/ember_terrain_sections.gd")
const Swash = preload("res://scripts/prototypes/ember_compact_sea_swash.gd")
const Waterfall = preload("res://scripts/prototypes/ember_compact_waterfall.gd")
const Phase = preload("res://scripts/prototypes/ember_compact_river_phase.gd")
const Ripple = preload("res://scripts/prototypes/ember_compact_ripple_field.gd")
const DiskCache = preload("res://scripts/prototypes/ember_compact_water_cache.gd")
const SIZE := Sections.CELLS
const HALO := 96 # Chamfer saturates at 85 cells; swash extends only 24.
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const LOCAL_UNIFORMS := ["terrain_origin_xz", "terrain_extent_cells", "terrain_height_map",
	"shore_distance_map", "sea_swash_info", "sea_swash_state", "sea_foam_age",
	"sea_swash_origin", "sea_swash_extent", "sea_swash_available"]

var regions := {}
var dry_tiles := {}
var waterfall: RefCounted
var active_height := 0.0
var update_us := 0
var _last_time := -1.0
var ready := false
var flow_texture: ImageTexture
var phase_texture: ImageTexture
var source: Terrain
var stats := {}
var _thread := Thread.new()
var _mutex := Mutex.new()
var _cancelled := false
var _result := {}
var _cache := {}
var _requested: Terrain
var _revision := -1
var _candidate := {}
var _upload_keys: Array = []
var _upload_cursor := 0
var cache_directory := DiskCache.ROOT # Tests may select an isolated user:// fixture.


func request(document: Terrain, revision: int) -> void:
	if revision == _revision: return
	_revision = revision
	_requested = document.working_copy()
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()
	ready = false
	_candidate = {}
	_upload_keys.clear()


func cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value


func close() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()
	if _thread.is_started(): _thread.wait_to_finish()


func prepare(budget_us := 3000, water: ShaderMaterial = null, ground: ShaderMaterial = null, origin := Vector2.ZERO) -> bool:
	var started := Time.get_ticks_usec()
	if _thread.is_started():
		if _thread.is_alive(): return false
		_thread.wait_to_finish()
		if not cancelled() and not _result.is_empty():
			_candidate = _result
			_cache = _candidate.cache
			_upload_keys = _candidate.regions.keys()
			_upload_cursor = 0
		_result = {}
	if _requested != null:
		var snapshot := _requested
		_requested = null
		_mutex.lock()
		_cancelled = false
		_mutex.unlock()
		_thread.start(_build.bind(snapshot, _cache.duplicate(true)), Thread.PRIORITY_LOW)
		return false
	if _candidate.is_empty(): return ready
	var common := _common_parameters(water, ground) if water != null and _upload_cursor < _upload_keys.size() else []
	while _upload_cursor < _upload_keys.size() and Time.get_ticks_usec() - started < budget_us:
		var entry: Dictionary = _candidate.regions[_upload_keys[_upload_cursor]]
		_upload_cursor += 1
		if entry.has("shore"): continue # Reuse the exact uploaded GPU/history.
		entry.shore = ImageTexture.create_from_image(entry.shore_image)
		entry.shore_data = entry.shore_image
		entry.height = ImageTexture.create_from_image(entry.height_image)
		entry.erase("shore_image")
		entry.erase("height_image")
		entry.sea.upload()
		if water != null: _bind_entry(entry, water, ground, origin, common)
	stats["max_upload_us"] = maxi(int(stats.get("max_upload_us", 0)), Time.get_ticks_usec() - started)
	if _upload_cursor < _upload_keys.size(): return false
	if not _candidate.has("textures"):
		flow_texture = ImageTexture.create_from_image(_candidate.flow) if _candidate.flow != null else null
		phase_texture = ImageTexture.create_from_image(_candidate.phase) if _candidate.phase != null else null
		waterfall = _candidate.waterfall
		waterfall.upload()
		Ripple.install(_candidate.ripple)
		_candidate.textures = true
		return false
	ready = true
	return true


func gpu_ready() -> bool:
	for entry: Dictionary in _candidate.get("regions", {}).values():
		if entry.sea._gpu != null and not entry.sea._gpu.ready: return false
	return true


func commit() -> void:
	# Copy the live history immediately before publication, rather than when
	# textures are first uploaded: rebuilding coast meshes can take many frames.
	for entry: Dictionary in _candidate.regions.values():
		if entry.sea._gpu == null: continue
		var global_bounds: Rect2i = entry.sea.bounds
		global_bounds.position += entry.window.position
		for old: Dictionary in regions.values():
			if old.sea == entry.sea or old.sea._gpu == null: continue
			var old_bounds: Rect2i = old.sea.bounds
			old_bounds.position += old.window.position
			var overlap := global_bounds.intersection(old_bounds).intersection(old.core)
			if overlap.has_area():
				entry.sea._gpu.inherit_region(old.sea._gpu, overlap.position - old_bounds.position,
					overlap.position - global_bounds.position, overlap.size)
	regions = _candidate.regions
	source = _candidate.source
	dry_tiles = _candidate.dry_tiles
	stats.merge(_candidate.stats, true)
	_candidate = {}


func pending_dry_tiles() -> Dictionary:
	return _candidate.get("dry_tiles", {})


func changed_dry_tiles() -> Dictionary:
	var affected := {}
	var next: Dictionary = _candidate.get("regions", {})
	for key: Vector2i in next:
		var old: Dictionary = regions.get(key, {})
		if not old.is_empty() and old.sea == next[key].sea: continue
		affected.merge(next[key].sea.dry_tiles)
		if not old.is_empty(): affected.merge(old.sea.dry_tiles)
	for key: Vector2i in regions:
		if not next.has(key): affected.merge(regions[key].sea.dry_tiles)
	return affected


func shore_distance(point: Vector2) -> float:
	var entry := _region(point)
	if entry.is_empty(): return 85.0
	var cell: Vector2i = Vector2i(point) - entry.window.position
	var image: Image = entry.shore_data
	return image.get_pixel(clampi(cell.x, 0, image.get_width() - 1), clampi(cell.y, 0, image.get_height() - 1)).r * 255.0 / 3.0


func _common_parameters(water: ShaderMaterial, ground: ShaderMaterial) -> Array:
	var common := []
	for material in [water, ground]:
		var values := {}
		if material != null:
			for uniform: Dictionary in material.shader.get_shader_uniform_list():
				var key: String = uniform.name
				if key not in LOCAL_UNIFORMS: values[key] = material.get_shader_parameter(key)
		common.append(values)
	return common


func bind(water: ShaderMaterial, ground: ShaderMaterial, origin: Vector2) -> void:
	if regions.is_empty(): return
	var started := Time.get_ticks_usec()
	var common := _common_parameters(water, ground)
	for entry: Dictionary in regions.values(): _bind_entry(entry, water, ground, origin, common)
	stats["bind_us"] = Time.get_ticks_usec() - started


func _bind_entry(entry: Dictionary, water: ShaderMaterial, ground: ShaderMaterial, origin: Vector2, common: Array) -> void:
	var created := not entry.has("water")
	if created:
		entry.water = water.duplicate()
		entry.ground = ground.duplicate() if ground != null else null
	var previous: Array = entry.get("parameters", [{}, {}])
	for i in 2:
		var target: ShaderMaterial = entry.water if i == 0 else entry.ground
		if target == null: continue
		# Duplicate carries the shared parameters; reused materials receive only
		# differences. New duplication happens in the bounded upload phase.
		if not created:
			for key: String in common[i]:
				if previous[i].get(key) != common[i][key]: target.set_shader_parameter(key, common[i][key])
		target.set_shader_parameter("sea_swash_available", 1.0 if entry.sea.state_texture != null else 0.0)
		if entry.sea.state_texture != null:
			target.set_shader_parameter("sea_swash_info", entry.sea.info_texture)
			target.set_shader_parameter("sea_swash_state", entry.sea.state_texture)
			target.set_shader_parameter("sea_swash_origin", origin + Vector2(entry.window.position + entry.sea.bounds.position))
			target.set_shader_parameter("sea_swash_extent", Vector2(entry.sea.bounds.size))
	entry.water.set_shader_parameter("terrain_origin_xz", origin + Vector2(entry.window.position))
	entry.water.set_shader_parameter("terrain_extent_cells", entry.window.size)
	entry.water.set_shader_parameter("terrain_height_map", entry.height)
	entry.water.set_shader_parameter("shore_distance_map", entry.shore)
	entry.water.set_shader_parameter("sea_foam_age", entry.sea.foam_age_texture)
	entry.parameters = common


func set_water_parameter(key: String, value: Variant) -> void:
	for entry: Dictionary in regions.values():
		if entry.has("water"): entry.water.set_shader_parameter(key, value)


func set_ground_parameter(key: String, value: Variant) -> void:
	for entry: Dictionary in regions.values():
		if entry.get("ground") != null: entry.ground.set_shader_parameter(key, value)


func advance(seconds: float, height: float, period: float, reach: float, offset: float,
		drying: float, approach := 20.0, offshore_strength := 0.65) -> void:
	var started := Time.get_ticks_usec()
	active_height = height
	_last_time = seconds
	for entry: Dictionary in regions.values():
		entry.sea.advance(seconds, height, period, reach, offset, drying, approach, offshore_strength)
	update_us = Time.get_ticks_usec() - started


func _region(point: Vector2) -> Dictionary:
	return regions.get(Vector2i(floori(point.x / SIZE), floori(point.y / SIZE)), {})


func sample(cell: Vector2i, with_history := true) -> Dictionary:
	var entry := _region(Vector2(cell))
	return entry.sea.sample(cell - entry.window.position, with_history) if not entry.is_empty() else {}


func surface_height(point: Vector2) -> float:
	var entry := _region(point)
	return entry.sea.surface_height(point - Vector2(entry.window.position)) if not entry.is_empty() else 0.0


func incident_height(point: Vector2, seconds: float, height: float, period: float, reach: float,
		approach := 20.0, offshore_strength := 0.65) -> float:
	var entry := _region(point)
	return entry.sea.incident_height(point - Vector2(entry.window.position), seconds, height, period, reach, approach, offshore_strength) if not entry.is_empty() else 0.0


static func coastal_influence(distance: float) -> float:
	return Swash.coastal_influence(distance)


func _build(snapshot: Terrain, previous: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var disk := DiskCache.new()
	disk.directory = cache_directory
	var world := snapshot if snapshot.is_sectioned() else snapshot.sectioned_copy()
	var fingerprints := {}
	for key: Vector2i in world.sections:
		if cancelled(): return
		var part: Terrain = world.sections[key]
		fingerprints[key] = DiskCache.digest([part.width, part.depth, part.origin_y,
			part.heights, part.water_levels, part.water_materials, part.water_flow])
	var key_us := Time.get_ticks_usec() - started
	var components := {}
	var count_built := 0
	var count_reused := 0
	for key: Vector2i in world.sections:
		if cancelled(): return
		var dependencies := _dependencies(world, Rect2i(key * SIZE, Vector2i(SIZE, SIZE)).grow(16))
		var cached: Dictionary = previous.get("components", {}).get(key, {})
		if not cached.is_empty() and cached.dependencies == dependencies:
			components[key] = cached
		else:
			components[key] = _components(world.sections[key], key * SIZE, world)
			if cancelled(): return
			components[key].dependencies = dependencies
		# Flow just beyond a window can alter a participating section's labels.
		# Flags alone do not describe which cells belong to each wet component.
		if not components[key].has("mask_key"):
			components[key].mask_key = DiskCache.digest(components[key].labels)
	var component_us := Time.get_ticks_usec() - started - key_us
	var phase_started := Time.get_ticks_usec()
	var ocean := _ocean(world, components)
	var connectivity_us := Time.get_ticks_usec() - phase_started
	if cancelled(): return
	var result := {}
	var dry := {}
	var spill_groups := {}
	var bytes := 0
	var base_water_height := 16.02
	var found_level := false
	var disk_hits := 0
	var coast_build_us := 0
	var restore_us := 0
	var window_us := 0
	for key: Vector2i in world.sections:
		if cancelled(): return
		for spill: Vector4i in components[key].spills:
			if not spill_groups.has(spill): spill_groups[spill] = []
			spill_groups[spill].append_array(components[key].spills[spill])
		var part: Terrain = world.sections[key]
		if not found_level:
			for i in part.heights.size():
				if part.water_materials[i] > 0 and part.water_levels[i] > part.heights[i]:
					base_water_height = world.origin_y + part.water_levels[i] + 0.02
					found_level = true
					break
		var core := Rect2i(key * SIZE, Vector2i(part.width, part.depth))
		# Missing/outside columns have an explicit presence mask. A stable halo
		# avoids invalidating every old edge region when the map envelope grows.
		var expanded := core.grow(HALO)
		var start := Vector2i(maxi(0, expanded.position.x), maxi(0, expanded.position.y))
		var window := Rect2i(start, expanded.end - start)
		var mask_dependencies := _mask_dependencies(components, window)
		var signature := hash([_dependencies(world, window), _ocean_dependencies(ocean, window), mask_dependencies, window, world.origin_y])
		var cached: Dictionary = previous.get("regions", {}).get(key, {})
		var entry: Dictionary
		if not cached.is_empty() and cached.signature == signature:
			entry = cached
			count_reused += 1
		else:
			var content_dependencies := []
			for dependency: Array in _dependencies(world, window):
				content_dependencies.append([dependency[0], fingerprints.get(dependency[0], "missing")])
			var disk_key := DiskCache.digest([DiskCache.VERSION, SIZE, HALO, core, window,
				world.origin_y, world.height_limit, content_dependencies, _ocean_dependencies(ocean, window), mask_dependencies])
			var saved := disk.read(disk_key)
			phase_started = Time.get_ticks_usec()
			var local := world.dense_window(window)
			window_us += Time.get_ticks_usec() - phase_started
			if cancelled(): return
			var sea := Swash.new()
			phase_started = Time.get_ticks_usec()
			var restored := _valid_static(saved, window.size) and sea.restore_static(local, saved.records, window.position, core)
			restore_us += Time.get_ticks_usec() - phase_started
			if restored:
				entry = {"signature": signature, "window": window, "core": core, "sea": sea,
					"shore_image": Image.create_from_data(window.size.x, window.size.y, false, Image.FORMAT_R8, saved.shore),
					"height_image": Image.create_from_data(window.size.x, window.size.y, false, Image.FORMAT_RF, saved.height)}
				disk_hits += 1
			else:
				if not saved.is_empty(): disk.invalid += 1
				phase_started = Time.get_ticks_usec()
				var masks := _masks(local, window.position, components, ocean)
				if cancelled(): return
				sea = Swash.new()
				sea.build(local, masks.ocean, window.position, core, true, masks.present, cancelled)
				if cancelled(): return
				entry = {"signature": signature, "window": window, "core": core, "sea": sea,
					"shore_image": _shore(local, masks.present), "height_image": _height(local)}
				coast_build_us += Time.get_ticks_usec() - phase_started
				if cancelled(): return
				disk.write(disk_key, {"records": sea.records, "shore": entry.shore_image.get_data(),
					"height": entry.height_image.get_data()}, cancelled)
				count_built += 1
			if cancelled(): return
			entry.disk_key = disk_key
		result[key] = entry
		bytes += window.size.x * window.size.y * 5 + entry.sea._info.size() * 4 * 2 + entry.sea._foam_age.size() * 4
		for tile: Vector2i in entry.sea.dry_tiles: dry[tile] = entry.sea.dry_tiles[tile]
	if cancelled(): return
	phase_started = Time.get_ticks_usec()
	var flow_source := Terrain.new()
	flow_source.width = world.width
	flow_source.depth = world.depth
	var flow_image := Image.create_empty(world.width / 16, world.depth / 16, false, Image.FORMAT_RGBAF)
	for z in world.depth / 16:
		if cancelled(): return
		for x in world.width / 16:
			var flow := world.flow_at_cell(x * 16, z * 16)
			flow_source.water_flow.append(flow)
			flow_image.set_pixel(x, z, Color(0.5 + flow.x * 0.5, 0.5 + flow.y * 0.5, 0, 1))
	var fall := Waterfall.new()
	fall.build(world, true, spill_groups)
	if cancelled(): return
	var ripple: Image = previous.get("ripple")
	if ripple == null: ripple = Ripple.build_image()
	if cancelled(): return
	var phase_image := Phase.build(flow_source)
	var common_us := Time.get_ticks_usec() - phase_started
	disk.trim()
	if cancelled(): return
	_result = {"source": world, "regions": result, "dry_tiles": dry, "flow": flow_image,
		"phase": phase_image, "waterfall": fall, "ripple": ripple,
		"cache": {"components": components, "regions": result, "ripple": ripple},
		"stats": {"built_regions": count_built, "reused_regions": count_reused, "field_bytes": bytes,
			"cpu_build_us": Time.get_ticks_usec() - started, "regions": result.size(), "base_water_height": base_water_height,
			"disk_hits": disk_hits, "cache_read_us": disk.read_us, "cache_write_us": disk.write_us,
			"cache_read_bytes": disk.read_bytes, "cache_written_bytes": disk.written_bytes,
			"cache_invalid": disk.invalid, "cache_failures": disk.failures, "key_us": key_us,
			"components_us": component_us, "connectivity_us": connectivity_us, "coast_build_us": coast_build_us,
			"restore_us": restore_us, "window_us": window_us, "common_us": common_us}}


static func _valid_static(saved: Dictionary, size: Vector2i) -> bool:
	return saved.get("records") is PackedVector4Array and saved.get("shore") is PackedByteArray \
		and saved.get("height") is PackedByteArray and saved.shore.size() == size.x * size.y \
		and saved.height.size() == size.x * size.y * 4 and saved.records.size() <= size.x * size.y


static func _dependencies(world: Terrain, bounds: Rect2i) -> Array:
	var result: Array = []
	for z in range(maxi(0, bounds.position.y / SIZE), ceili(float(bounds.end.y) / SIZE)):
		for x in range(maxi(0, bounds.position.x / SIZE), ceili(float(bounds.end.x) / SIZE)):
			var key := Vector2i(x, z)
			var part: Terrain = world.sections.get(key)
			result.append([key, part.get_instance_id() if part != null else 0])
	return result


static func _ocean_dependencies(ocean: Dictionary, bounds: Rect2i) -> Array:
	var result: Array = []
	for z in range(bounds.position.y / SIZE, ceili(float(bounds.end.y) / SIZE)):
		for x in range(bounds.position.x / SIZE, ceili(float(bounds.end.x) / SIZE)):
			result.append(ocean.get(Vector2i(x, z), PackedInt32Array()))
	return result


static func _mask_dependencies(components: Dictionary, bounds: Rect2i) -> Array:
	var result: Array = []
	for z in range(bounds.position.y / SIZE, ceili(float(bounds.end.y) / SIZE)):
		for x in range(bounds.position.x / SIZE, ceili(float(bounds.end.x) / SIZE)):
			result.append(components.get(Vector2i(x, z), {}).get("mask_key", "missing"))
	return result


func _components(part: Terrain, offset: Vector2i, world: Terrain) -> Dictionary:
	var labels := PackedInt32Array()
	labels.resize(part.width * part.depth)
	labels.fill(0)
	var guard := PackedByteArray()
	guard.resize(labels.size())
	for z in range(-16, part.depth + 16, 16):
		for x in range(-16, part.width + 16, 16):
			if world.flow_at_cell(offset.x + x, offset.y + z).length_squared() < 0.0001: continue
			for rz in range(maxi(0, z - 2), mini(part.depth, z + 18)):
				for rx in range(maxi(0, x - 2), mini(part.width, x + 18)): guard[rx + rz * part.width] = 1
	var groups := 0
	for index in labels.size():
		if index % 1024 == 0 and cancelled(): return {}
		if labels[index] != 0 or guard[index] != 0 or part.water_materials[index] == 0 or part.water_levels[index] <= part.heights[index]: continue
		groups += 1
		labels[index] = groups
		var queue := PackedInt32Array([index])
		var cursor := 0
		while cursor < queue.size():
			if cursor % 1024 == 0 and cancelled(): return {}
			var at := queue[cursor]
			cursor += 1
			var point := Vector2i(at % part.width, at / part.width)
			for direction: Vector2i in DIRECTIONS:
				var neighbour := point + direction
				if neighbour.x < 0 or neighbour.y < 0 or neighbour.x >= part.width or neighbour.y >= part.depth: continue
				var n := neighbour.x + neighbour.y * part.width
				if labels[n] != 0 or guard[n] != 0 or part.water_materials[n] == 0 or part.water_levels[n] <= part.heights[n]: continue
				labels[n] = groups
				queue.append(n)
	return {"labels": labels, "groups": groups, "width": part.width, "depth": part.depth,
		"spills": Waterfall.scan_groups(part, offset, world)}


func _ocean(world: Terrain, components: Dictionary) -> Dictionary:
	var graph := {}
	var seeds: Array[Vector3i] = []
	for key: Vector2i in components:
		var c: Dictionary = components[key]
		for id in range(1, c.groups + 1): graph[Vector3i(key.x, key.y, id)] = {}
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var other: Dictionary = components.get(key + direction, {})
			var along: int = c.depth if direction.x != 0 else c.width
			for i in along:
				var p := Vector2i(0 if direction.x < 0 else c.width - 1, i) if direction.x != 0 else Vector2i(i, 0 if direction.y < 0 else c.depth - 1)
				var id: int = c.labels[p.x + p.y * c.width]
				if id == 0: continue
				var node := Vector3i(key.x, key.y, id)
				var global := key * SIZE + p
				if global.x == 0 or global.y == 0 or global.x == world.width - 1 or global.y == world.depth - 1:
					if not seeds.has(node): seeds.append(node)
				if other.is_empty(): continue
				var neighbour := global + direction - (key + direction) * SIZE
				if neighbour.x < 0 or neighbour.y < 0 or neighbour.x >= other.width or neighbour.y >= other.depth: continue
				var next_id: int = other.labels[neighbour.x + neighbour.y * other.width]
				if next_id > 0: graph[node][Vector3i(key.x + direction.x, key.y + direction.y, next_id)] = true
	var seen := {}
	var cursor := 0
	for node in seeds: seen[node] = true
	while cursor < seeds.size():
		var node := seeds[cursor]
		cursor += 1
		for neighbour: Vector3i in graph[node]:
			if not seen.has(neighbour): seen[neighbour] = true; seeds.append(neighbour)
	var result := {}
	for key: Vector2i in components:
		var flags := PackedInt32Array()
		flags.resize(components[key].groups + 1)
		for id in range(1, flags.size()): flags[id] = 1 if seen.has(Vector3i(key.x, key.y, id)) else 0
		result[key] = flags
	return result


func _masks(local: Terrain, offset: Vector2i, components: Dictionary, ocean: Dictionary) -> Dictionary:
	var wet := PackedByteArray()
	var present := PackedByteArray()
	wet.resize(local.width * local.depth)
	present.resize(wet.size())
	for z in local.depth:
		if cancelled(): return {}
		for x in local.width:
			var global := offset + Vector2i(x, z)
			var key := Vector2i(global.x / SIZE, global.y / SIZE)
			var c: Dictionary = components.get(key, {})
			if c.is_empty(): continue
			var p := global - key * SIZE
			if p.x >= c.width or p.y >= c.depth: continue
			var index := x + z * local.width
			present[index] = 1
			wet[index] = ocean[key][c.labels[p.x + p.y * c.width]]
	return {"ocean": wet, "present": present}


func _shore(local: Terrain, present: PackedByteArray) -> Image:
	var width := local.width
	var depth := local.depth
	var distances := PackedByteArray()
	distances.resize(width * depth)
	distances.fill(255)
	for z in depth:
		if cancelled(): return null
		for x in width:
			var index := x + z * width
			if present[index] != 0 and (local.water_materials[index] == 0 or local.water_levels[index] <= local.heights[index]): distances[index] = 0; continue
			var nearest := 255
			if x > 0: nearest = mini(nearest, int(distances[index - 1]) + 3)
			if z > 0:
				nearest = mini(nearest, int(distances[index - width]) + 3)
				if x > 0: nearest = mini(nearest, int(distances[index - width - 1]) + 4)
				if x + 1 < width: nearest = mini(nearest, int(distances[index - width + 1]) + 4)
			distances[index] = mini(nearest, 255)
	for z in range(depth - 1, -1, -1):
		if cancelled(): return null
		for x in range(width - 1, -1, -1):
			var index := x + z * width
			var nearest := int(distances[index])
			if x + 1 < width: nearest = mini(nearest, int(distances[index + 1]) + 3)
			if z + 1 < depth:
				nearest = mini(nearest, int(distances[index + width]) + 3)
				if x > 0: nearest = mini(nearest, int(distances[index + width - 1]) + 4)
				if x + 1 < width: nearest = mini(nearest, int(distances[index + width + 1]) + 4)
			distances[index] = mini(nearest, 255)
	return Image.create_from_data(width, depth, false, Image.FORMAT_R8, distances)


func _height(local: Terrain) -> Image:
	var image := Image.create_empty(local.width, local.depth, false, Image.FORMAT_RF)
	for z in local.depth:
		if cancelled(): return null
		for x in local.width:
			var highest := 0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					highest = maxi(highest, local.heights[clampi(x + dx, 0, local.width - 1) + clampi(z + dz, 0, local.depth - 1) * local.width])
			image.set_pixel(x, z, Color(local.origin_y + highest, 0, 0, 1))
	return image
