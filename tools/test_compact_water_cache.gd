extends SceneTree
const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Cache = preload("res://scripts/prototypes/ember_compact_water_cache.gd")
var directory := "user://ember-tests/water-cache/%s" % Time.get_ticks_usec()


func _initialize() -> void:
	_run.call_deferred()


func _fields(document: Terrain, use_disk := true) -> RefCounted:
	var fields := Regions.new()
	fields.cache_directory = directory if use_disk else ""
	fields.request(document, 1)
	var deadline := Time.get_ticks_msec() + 90000
	while not fields.prepare() and Time.get_ticks_msec() < deadline: await process_frame
	assert(fields.ready, "cache fixture preparation timed out")
	while not fields.gpu_ready() and Time.get_ticks_msec() < deadline: await process_frame
	assert(fields.gpu_ready())
	fields.commit()
	return fields


func _same(a: RefCounted, b: RefCounted) -> void:
	assert(a.regions.size() == b.regions.size())
	for key in a.regions:
		var first: Dictionary = a.regions[key]
		var second: Dictionary = b.regions[key]
		assert(first.sea.records == second.sea.records)
		assert(first.sea._info == second.sea._info)
		assert(first.sea._static_records == second.sea._static_records)
		assert(first.sea.dry_tiles == second.sea.dry_tiles)
		assert(first.shore_data.get_data() == second.shore_data.get_data())
		assert(first.height.get_image().get_data() == second.height.get_image().get_data())
	for time in [0.0, 1.5, 3.8, 5.7]:
		a.advance(time, 2.8, 8.0, 10.0, -0.35, 6.0)
		b.advance(time, 2.8, 8.0, 10.0, -0.35, 6.0)
		for x in [380, 384, 390, 900, 1150, 1538]:
			for z in [36, 39, 41, 70]:
				var p := Vector2i(x, z)
				assert(a.sample(p) == b.sample(p), "cached coast changed height/foam/wetness at %s" % p)


func _fixture() -> Terrain:
	var dense := Terrain.new()
	dense.width = 1920
	dense.depth = 96
	dense.height_limit = 64
	dense.palette = PackedColorArray([Color.TRANSPARENT, Color.SANDY_BROWN, Color.SKY_BLUE])
	for name in ["heights", "water_levels", "water_materials", "top_materials", "base_materials", "cap_depths"]:
		var channel = PackedInt32Array() if name in ["heights", "water_levels"] else PackedByteArray()
		channel.resize(dense.width * dense.depth)
		dense.set(name, channel)
	for z in dense.depth:
		for x in dense.width:
			var i := x + z * dense.width
			dense.heights[i] = 2 if z < 40 else 6
			dense.top_materials[i] = 1
			dense.base_materials[i] = 1
			dense.cap_depths[i] = 1
			if z < 40: dense.water_levels[i] = 4; dense.water_materials[i] = 2
	# An inland lake extends far beyond the inlet's neighbours.
	for z in range(68, 76):
		for x in range(372, 1500):
			var i := x + z * dense.width
			dense.heights[i] = 2
			dense.water_levels[i] = 4
			dense.water_materials[i] = 2
	return dense.sectioned_copy()


func _run() -> void:
	var document := _fixture()
	var authored := Cache.digest(document.sections[Vector2i.ZERO].heights)
	var cold := await _fields(document)
	assert(cold.stats.built_regions == 5 and cold.stats.disk_hits == 0 and cold.stats.cache_failures == 0)
	var source_path := directory.path_join("fixture.tres")
	assert(ResourceSaver.save(document, source_path) == OK)
	var reopened := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Terrain
	assert(reopened.sections[Vector2i.ZERO] != document.sections[Vector2i.ZERO])
	var warm := await _fields(reopened)
	assert(warm.stats.built_regions == 0 and warm.stats.disk_hits == 5)
	_same(cold, warm)
	print("WATER_CACHE_PROFILE cold=", cold.stats, " warm=", warm.stats)
	# No animation history or scene style is written to the cache.
	var reset := await _fields(reopened)
	assert(reset.regions[Vector2i.ZERO].sea._last_time == -1.0)
	assert(reset.regions[Vector2i.ZERO].sea._history.is_empty())
	var palette_only := reopened.working_copy()
	palette_only.palette[1] = Color.RED
	var painted := await _fields(palette_only)
	assert(painted.stats.disk_hits == 5)
	# Changing the middle section invalidates its halo neighbours, not the ends.
	var edited := reopened.working_copy()
	var part: Terrain = edited.sections[Vector2i(2, 0)].working_copy()
	part.heights[192 + 42 * part.width] = 5
	edited.sections[Vector2i(2, 0)] = part
	var changed := await _fields(edited)
	assert(changed.stats.built_regions == 3 and changed.stats.disk_hits == 2)
	var calculated := await _fields(edited, false)
	_same(changed, calculated)
	var undone := await _fields(reopened)
	assert(undone.stats.disk_hits == 5)
	# A distant sea/lake change must invalidate despite unchanged local content.
	var connected := reopened.working_copy()
	part = connected.sections[Vector2i.ZERO].working_copy()
	connected.sections[Vector2i.ZERO] = part
	for z in range(39, 72):
		for x in range(380, 384):
			var at := x + z * part.width
			part.heights[at] = 2; part.water_levels[at] = 4; part.water_materials[at] = 2
	var opened := await _fields(connected)
	assert(not opened.sample(Vector2i(1200, 70)).is_empty())
	assert(opened.regions[Vector2i(3, 0)].disk_key != warm.regions[Vector2i(3, 0)].disk_key)
	var closed := await _fields(reopened)
	assert(closed.stats.disk_hits == 5 and closed.sample(Vector2i(1200, 70)).is_empty())
	# Neighbouring flow outside a region's halo can still alter component labels
	# used inside that halo. Equal ocean flag arrays alone are not a valid key.
	var flow_edit := reopened.working_copy()
	part = flow_edit.sections[Vector2i(4, 0)].working_copy()
	part.water_flow.resize(part.width / 16 * (part.depth / 16))
	part.water_flow[0] = Vector2.RIGHT
	flow_edit.sections[Vector2i(4, 0)] = part
	var flowing := await _fields(flow_edit)
	assert(flowing.regions[Vector2i(2, 0)].disk_key != warm.regions[Vector2i(2, 0)].disk_key)
	var flowing_reference := await _fields(flow_edit, false)
	_same(flowing, flowing_reference)
	# Truncation, checksum failure, future version and valid but malformed payload.
	var storage := Cache.new()
	storage.directory = directory
	var key: String = warm.regions[Vector2i.ZERO].disk_key
	for kind in ["truncated", "checksum", "version", "payload", "missing"]:
		var file_path := storage.path(key)
		var bytes := FileAccess.get_file_as_bytes(file_path)
		if kind == "missing": assert(DirAccess.remove_absolute(file_path) == OK)
		elif kind == "payload": storage.write(key, {"records": "bad"}, func() -> bool: return false)
		else:
			if kind == "truncated": bytes.resize(20)
			if kind == "checksum": bytes[bytes.size() - 1] ^= 1
			if kind == "version": bytes.encode_u32(8, Cache.VERSION + 1)
			var file := FileAccess.open(file_path, FileAccess.WRITE)
			file.store_buffer(bytes); file.close()
		var repaired := await _fields(reopened)
		assert(repaired.stats.disk_hits == 4 and repaired.stats.built_regions == 1, kind)
		assert(not storage.read(key).is_empty(), "bad cache was not replaced: " + kind)
		repaired.close()
	# Read/write denial is a cache miss, never a startup failure.
	var blocker := directory.path_join("not-a-directory")
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("fixture"); file.close()
	var fallback := Regions.new()
	fallback.cache_directory = blocker
	fallback.request(reopened, 1)
	var deadline := Time.get_ticks_msec() + 60000
	while not fallback.prepare() and Time.get_ticks_msec() < deadline: await process_frame
	assert(fallback.ready)
	fallback.commit()
	assert(fallback.stats.built_regions == 5 and fallback.stats.cache_failures == 5)
	# Cancelled work cannot publish, and content-addressed writes cannot poison Undo.
	var cancelled_fields := Regions.new()
	cancelled_fields.cache_directory = directory
	cancelled_fields.request(connected, 1)
	cancelled_fields.prepare()
	cancelled_fields.request(reopened, 2)
	deadline = Time.get_ticks_msec() + 60000
	while not cancelled_fields.prepare() and Time.get_ticks_msec() < deadline: await process_frame
	assert(cancelled_fields.ready)
	cancelled_fields.commit()
	assert(cancelled_fields.source.same_terrain_geometry(reopened))
	assert(cancelled_fields.sample(Vector2i(1200, 70)).is_empty())
	assert(Cache.digest(document.sections[Vector2i.ZERO].heights) == authored)
	# Quota removes only derived cache entries, never authored files or live state.
	storage.trim(0)
	assert(FileAccess.file_exists(source_path))
	for name in DirAccess.get_files_at(directory): assert(not name.ends_with(".ewc"))
	assert(cancelled_fields.source.same_terrain_geometry(reopened))
	for fields in [cold, warm, reset, painted, changed, calculated, undone, opened, closed, flowing, flowing_reference, fallback, cancelled_fields]: fields.close()
	print("PASS WATER_CACHE: fresh resource/reopen, exact fields and queries, local edit/Undo, distant connectivity, history reset, corrupt/version/missing/I-O fallback, cancellation")
	quit()
