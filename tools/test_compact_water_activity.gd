extends SceneTree
## Runtime scheduling and physical-query clocks, without a RenderingDevice.
const Regions = preload("res://scripts/prototypes/ember_compact_water_regions.gd")
const Swash = preload("res://scripts/prototypes/ember_compact_sea_swash.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")

class DispatchSpy extends RefCounted:
	var full := 0
	var border := 0
	var records := 0
	func configure_border(_records: PackedFloat32Array) -> void: pass
	func release() -> void: pass
	func update(_table: PackedByteArray, constants: PackedByteArray, border_only := false) -> void:
		assert(constants.size() == 48)
		if border_only: border += 1
		else: full += 1
		records += int(constants.to_float32_array()[7])

static func source() -> EmberTerrainPilotResource:
	var field := Terrain.new()
	field.width = 768; field.depth = 64
	for key in ["heights", "water_levels", "water_materials", "top_materials", "base_materials", "cap_depths"]:
		var channel = field.get(key); channel.resize(field.width * field.depth); field.set(key, channel)
	for z in field.depth:
		for x in field.width:
			var at := x + z * field.width
			field.heights[at] = 4 if z < 32 else 9
			field.water_levels[at] = 8 if z < 32 else 0
			field.water_materials[at] = 2 if z < 32 else 0
	return field

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var document := source()
	var original := document.heights.duplicate()
	var fields := Regions.new()
	var spies := []
	for x in 2:
		var sea := Swash.new(); sea.use_gpu = false
		var core := Rect2i(x * 384, 0, 384, 64)
		sea.build(document, PackedByteArray(), Vector2i.ZERO, core)
		var spy := DispatchSpy.new(); sea._gpu = spy; spies.append(spy)
		fields.regions[Vector2i(x, 0)] = {"sea": sea, "core": core, "window": Rect2i(0, 0, 768, 64)}
	fields.set_runtime_activity(true, PackedVector2Array([Vector2(20, 20)]), 100.0, 20.0)
	var reference := Swash.new(); reference.use_gpu = false; reference.build(document)
	for step in 81:
		var time := step * 0.05
		fields.advance(time, 2.8, 8.0, 10.0, -0.35, 6.0)
		reference.advance(time, 2.8, 8.0, 10.0, -0.35, 6.0)
		var far: RefCounted = fields.regions[Vector2i(1, 0)].sea
		# Query the leaf here: the regional public query intentionally promotes it.
		var actual: Dictionary = far.sample(Vector2i(600, 32), false)
		var expected: Dictionary = reference.sample(Vector2i(600, 32), false)
		assert(absf(actual.height - expected.height) < 0.0002, "far physical clock fell behind")
	assert(spies[0].full == 81 and spies[0].border == 0)
	assert(spies[1].full == 21 and spies[1].border == 60)
	assert(fields.stats.near_regions == 1 and fields.stats.far_regions == 1)
	# Duplicate/frozen time must not dispatch again; returning near is immediate.
	var count: int = spies[1].full
	fields.advance(4.0, 2.8, 8.0, 10.0, -0.35, 6.0)
	assert(spies[1].full == count)
	fields.advance(4.05, 2.8, 8.0, 10.0, -0.35, 6.0)
	fields.sample(Vector2i(600, 32), false)
	assert(spies[1].full == count + 1, "physical query did not publish current GPU surface")
	fields.surface_height(Vector2(600.25, 32.75))
	assert(spies[1].full == count + 1, "query promotion repeated at the same time")
	fields.advance(4.1, 2.8, 8.0, 10.0, -0.35, 6.0)
	assert(fields.stats.near_regions == 2)
	fields.advance(6.2, 2.8, 8.0, 10.0, -0.35, 6.0)
	assert(fields.stats.far_regions == 1, "query protection did not expire")
	fields.set_runtime_activity(true, PackedVector2Array([Vector2(500, 20)]), 100.0, 20.0)
	fields.advance(6.25, 2.8, 8.0, 10.0, -0.35, 6.0)
	assert(fields.regions[Vector2i(1, 0)].runtime_near)
	# Hysteresis holds at 110 cells; releases past 120 without permanent leases.
	fields.set_runtime_activity(true, PackedVector2Array([Vector2(274, 20)]), 100.0, 20.0)
	fields.advance(6.3, 2.8, 8.0, 10.0, -0.35, 6.0)
	assert(fields.regions[Vector2i(1, 0)].runtime_near)
	fields.set_runtime_activity(true, PackedVector2Array([Vector2(260, 20)]), 100.0, 20.0)
	fields.advance(6.35, 2.8, 8.0, 10.0, -0.35, 6.0)
	assert(not fields.regions[Vector2i(1, 0)].runtime_near)
	count = spies[1].full
	fields.advance(6.4, 0.0, 8.0, 10.0, -0.35, 6.0)
	assert(spies[1].full == count + 1, "setting change left far field stale")
	fields.advance(0.0, 0.0, 8.0, 10.0, -0.35, 6.0)
	assert(not fields.regions[Vector2i(1, 0)].has("query_until"))
	fields.set_runtime_activity(true) # No camera/player: retain the exact path.
	fields.advance(0.05, 0.0, 8.0, 10.0, -0.35, 6.0)
	assert(not fields.stats.activity_enabled and fields.stats.far_regions == 0)
	assert(document.heights == original)
	print("PASS WATER_ACTIVITY: 20/5 Hz, seam dispatch, exact queries, promotion/lease, hysteresis, settings/reset/fallback; saved source unchanged")
	quit()
