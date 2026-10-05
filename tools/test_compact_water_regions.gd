extends SceneTree
const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const Sea = preload("res://scripts/prototypes/ember_compact_sea_swash.gd")

func _initialize() -> void:
	_run.call_deferred()

func _ready_fields(fields: RefCounted, document: Terrain, revision: int) -> void:
	fields.request(document, revision)
	var deadline := Time.get_ticks_msec() + 60000
	while not fields.prepare() and Time.get_ticks_msec() < deadline: await process_frame
	assert(fields.ready, "regional preparation timed out")
	while not fields.gpu_ready() and Time.get_ticks_msec() < deadline: await process_frame
	assert(fields.gpu_ready())
	fields.commit()

func _run() -> void:
	var dense := Terrain.new()
	dense.width = 1152
	dense.depth = 384
	dense.height_limit = 64
	dense.palette = PackedColorArray([Color.TRANSPARENT, Color.SANDY_BROWN, Color.SKY_BLUE])
	for channel in ["heights", "water_levels", "water_materials", "top_materials", "base_materials", "cap_depths"]:
		var array = PackedInt32Array() if channel in ["heights", "water_levels"] else PackedByteArray()
		array.resize(dense.width * dense.depth)
		dense.set(channel, array)
	for z in dense.depth:
		for x in dense.width:
			var i := x + z * dense.width
			dense.heights[i] = 4 if z < 160 else 9
			dense.top_materials[i] = 1
			dense.base_materials[i] = 1
			dense.cap_depths[i] = 1
			if z < 160: dense.water_levels[i] = 8; dense.water_materials[i] = 2
	# An isolated pool crosses the section boundary. It must never become sea.
	for z in range(240, 260):
		for x in range(372, 1060):
			var i := x + z * dense.width
			dense.heights[i] = 4
			dense.water_levels[i] = 8
			dense.water_materials[i] = 2
	var authored := dense.heights.duplicate()
	var document := dense.sectioned_copy()
	var fields := Regions.new()
	fields.cache_directory = "" # This regression exercises calculation, not disk hits.
	await _ready_fields(fields, document, 1)
	assert(fields.regions.size() == 3)
	assert(fields.sample(Vector2i(380, 248)).is_empty(), "internal region edge incorrectly classified a lake as sea")
	var reference := Sea.new()
	reference.build(dense)
	for time in [0.0, 1.5, 3.8, 5.7, 6.2]:
		fields.advance(time, 2.8, 8.0, 10.0, -0.35, 6.0)
		reference.advance(time, 2.8, 8.0, 10.0, -0.35, 6.0)
		for x in range(378, 391):
			for z in range(145, 166):
				var p := Vector2i(x, z)
				var a: Dictionary = fields.sample(p, false)
				var b: Dictionary = reference.sample(p, false)
				assert(not a.is_empty() and not b.is_empty())
				assert(absf(a.height - b.height) < 0.0002, "wave changed at a regional seam")
				assert(a.distance == b.distance and a.dry_bank == b.dry_bank)
				assert(absf(fields.surface_height(Vector2(p) + Vector2(0.3, 0.7)) - reference.surface_height(Vector2(p) + Vector2(0.3, 0.7))) < 0.0002)
	assert(dense.heights == authored)
	# Identical immutable parts must retain their field and its foam history.
	var first: RefCounted = fields.regions[Vector2i.ZERO].sea
	await _ready_fields(fields, document.working_copy(), 2)
	assert(fields.stats.built_regions == 0 and fields.stats.reused_regions == 3)
	assert(fields.regions[Vector2i.ZERO].sea == first)
	# Grow the envelope beyond the former 120 m guard, with an empty gap.
	# Existing regions keep their stable halo, connectivity and foam history.
	var expanded := document.working_copy()
	expanded.width = 3072
	expanded.depth = 1920
	expanded.sections[Vector2i(7, 4)] = document.sections[Vector2i.ZERO].working_copy()
	await _ready_fields(fields, expanded, 3)
	assert(fields.stats.reused_regions == 3 and fields.stats.built_regions == 1)
	assert(fields.regions[Vector2i.ZERO].sea == first)
	assert(fields.source.width == 3072 and fields.source.depth == 1920)
	# Connectivity can change far beyond the changed section's halo. Opening
	# a narrow inlet in section zero turns the distant pool in section two into
	# sea even though that distant section and its immediate neighbours persist.
	var distant: RefCounted = fields.regions[Vector2i(2, 0)].sea
	var connected := document.working_copy()
	var changed: Terrain = connected.sections[Vector2i.ZERO].working_copy()
	connected.sections[Vector2i.ZERO] = changed
	for z in range(159, 250):
		for x in range(380, 384):
			var i := x + z * changed.width
			changed.heights[i] = 4
			changed.water_levels[i] = 8
			changed.water_materials[i] = 2
	await _ready_fields(fields, connected, 4)
	assert(not fields.sample(Vector2i(900, 248)).is_empty(), "global inlet change left a distant sea region stale")
	assert(fields.regions[Vector2i(2, 0)].sea != distant)
	# Cancelled work must not publish an old source after Undo/new edits.
	fields.request(connected, 5)
	fields.prepare()
	fields.request(document, 6)
	await _ready_fields(fields, document, 6)
	assert(fields.sample(Vector2i(900, 248)).is_empty(), "Undo did not close the distant sea connection")
	assert(fields.source.same_terrain_geometry(document))
	fields.close()
	print("PASS WATER_REGIONS: global sea/lake connectivity, seam parity/query, persistent cache, cancellation, authored data unchanged")
	quit()
