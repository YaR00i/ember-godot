extends SceneTree
## Native Forward+ parity against the existing CPU field, including cold queries.

const Swash = preload("res://scripts/prototypes/ember_compact_sea_swash.gd")
const Terrain = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message); printerr("SWASH_GPU FAIL ", message)

func frames(count := 2) -> void:
	for i in count: await process_frame

func field() -> EmberTerrainPilotResource:
	var source := Terrain.new()
	source.width = 128; source.depth = 64
	var count := source.width * source.depth
	for key in ["heights", "water_levels", "water_materials", "top_materials", "base_materials", "cap_depths"]:
		var channel = source.get(key); channel.resize(count); source.set(key, channel)
	for z in source.depth:
		for x in source.width:
			var i := x + z * source.width
			source.heights[i] = 4 if x < 64 else 8 + (x - 64) / 4
			source.water_levels[i] = 8 if x < 64 else 0
			source.water_materials[i] = 2 if x < 64 else 0
	return source

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("SWASH_GPU needs native Forward+."); quit(1); return
	var source := field()
	var cpu := Swash.new(); cpu.use_gpu = false; cpu.build(source)
	var gpu := Swash.new(); gpu.build(source)
	await frames(8)
	check(gpu._gpu != null and gpu._gpu.ready and gpu._gpu.error.is_empty(), "compute did not initialize")
	if not failures.is_empty(): quit(1); return
	var comparisons := 0
	for step in 650:
		var seconds := step * 0.05 if step < 100 else (step - 100) * 0.05
		var height := 0.0 if step > 450 else 2.8
		var drying := 20.0 if step > 200 else 6.0
		for state in [cpu, gpu]: state.advance(seconds, height, 9.0, 10.0, -0.35, drying)
		var warm_cell := Vector2i(gpu.records[0].x, gpu.records[0].y)
		var warm: Dictionary = gpu.sample(warm_cell)
		var warm_expected: Dictionary = cpu.sample(warm_cell)
		check(absf(warm.wetness - warm_expected.wetness) < 0.0002 and absf(warm.foam_age - warm_expected.foam_age) < 0.0002,
			"continuously queried history diverged")
		# Repeating a frozen preview must not dispatch or erase history.
		var before: int = gpu._gpu.dispatches
		gpu.advance(seconds, height, 9.0, 10.0, -0.35, drying)
		check(gpu.update_us == 0, "identical preview was recalculated")
		await frames()
		check(gpu._gpu.dispatches == before + 1 or gpu._gpu.dispatches == before, "duplicate dispatch")
		if step % 25 != 0: continue
		var image: Image = gpu.state_texture.get_image()
		var foam: Image = gpu.foam_age_texture.get_image()
		check(image != null and foam != null, "readback failed")
		for record in range(0, gpu.records.size(), 97):
			var p := Vector2i(gpu.records[record].x, gpu.records[record].y)
			var expected: Dictionary = cpu.sample(p)
			var actual := image.get_pixelv(p - gpu.bounds.position)
			var age := foam.get_pixelv(p - gpu.bounds.position).r
			check(absf(actual.r - expected.height) < 0.0002 and absf(actual.g - expected.foam) < 0.0002
				and absf(actual.b - expected.wetness) < 0.0002 and absf(actual.a - expected.coverage) < 0.0002
				and absf(age - expected.foam_age) < 0.0002, "GPU history diverged at step %d cell %s" % [step, p])
			var query: Dictionary = gpu.sample(p)
			check(absf(query.height - expected.height) < 0.0002 and absf(query.wetness - expected.wetness) < 0.0002
				and absf(query.foam_age - expected.foam_age) < 0.0002, "CPU query history diverged")
			var current: Dictionary = gpu.sample(p, false)
			check(absf(current.height - expected.height) < 0.0002 and absf(current.coverage - expected.coverage) < 0.0002,
				"current physics query diverged")
			check(absf(gpu.surface_height(Vector2(p) + Vector2(0.25, 0.75)) - cpu.surface_height(Vector2(p) + Vector2(0.25, 0.75))) < 0.0002, "bilinear surface query diverged")
			comparisons += 1
	check(gpu._query_cache.size() <= Swash.QUERY_CACHE_LIMIT, "query cache exceeded its budget")
	# Migrating an already running editor must keep the current foam/wet sand.
	var migrating := Swash.new(); migrating.use_gpu = false; migrating.build(source)
	var reference := Swash.new(); reference.use_gpu = false; reference.build(source)
	for step in 90:
		for state in [migrating, reference]: state.advance(step * 0.05, 2.8, 9.0, 10.0, -0.35, 12.0)
	migrating.use_gpu = true
	check(migrating.enable_gpu(), "existing editor field did not migrate")
	await frames(8)
	for step in range(90, 110):
		for state in [migrating, reference]: state.advance(step * 0.05, 2.8, 9.0, 10.0, -0.35, 12.0)
		await frames()
	var migrated_image: Image = migrating.state_texture.get_image()
	for record in range(0, migrating.records.size(), 97):
		var p := Vector2i(migrating.records[record].x, migrating.records[record].y)
		var expected: Dictionary = reference.sample(p)
		var actual := migrated_image.get_pixelv(p - migrating.bounds.position)
		var queried: Dictionary = migrating.sample(p)
		check(absf(actual.b - expected.wetness) < 0.0002 and absf(actual.r - expected.height) < 0.0002
			and absf(queried.wetness - expected.wetness) < 0.0002, "migration lost existing history")
	# A replacement regional field inherits history without CPU readback.
	# Drop the old owner immediately after queueing the copy: its RID cleanup
	# must remain behind the copy despite the release flag changing on the CPU.
	var copied_records := migrating.records.duplicate()
	var copied_bounds := migrating.bounds
	var old_foam: Image = migrating.foam_age_texture.get_image()
	var migration_backend: RefCounted = migrating._gpu
	var replacement := Swash.new(); replacement.build(source)
	await frames(8)
	replacement._gpu.inherit_region(migration_backend, Vector2i.ZERO, Vector2i.ZERO, copied_bounds.size)
	migrating = null
	replacement.advance(109 * 0.05, 2.8, 9.0, 10.0, -0.35, 12.0)
	await frames(3)
	var copied_image: Image = replacement.state_texture.get_image()
	var copied_foam: Image = replacement.foam_age_texture.get_image()
	for record in range(0, copied_records.size(), 97):
		var point := Vector2i(copied_records[record].x, copied_records[record].y) - copied_bounds.position
		check(absf(copied_image.get_pixelv(point).b - migrated_image.get_pixelv(point).b) < 0.0002
			and absf(copied_foam.get_pixelv(point).r - old_foam.get_pixelv(point).r) < 0.0002, "regional replacement lost foam or wet sand")
	replacement._gpu.release()
	await frames()
	check(migration_backend._resources.is_empty(), "owner disposal leaked GPU handles")
	if FileAccess.file_exists("res://qa_swash/profile.res"):
		var author_copy := load("res://qa_swash/profile.res") as EmberTerrainPilotResource
		var dense := author_copy.dense_window(Rect2i(0, 0, author_copy.width, author_copy.depth)) if author_copy.is_sectioned() else author_copy
		var benchmark := Swash.new(); benchmark.build(dense)
		await frames(8)
		var costs: Array[int] = []
		for i in 45:
			benchmark.advance(i * 0.05, 2.8, 9.0, 10.0, -0.35, 12.0)
			costs.append(benchmark.update_us)
			await frames()
		costs.sort()
		print("SWASH_GPU_PROFILE records=", benchmark.records.size(), " median_ms=", costs[22] / 1000.0, " p95_ms=", costs[42] / 1000.0)
		check(costs[22] < 8000, "expanded coast still stalls CPU above 8 ms")
		benchmark._gpu.release()
		await frames()
		check(benchmark._gpu._resources.is_empty(), "GPU release leaked handles")
	gpu._gpu.release()
	await frames()
	check(gpu._gpu._resources.is_empty(), "GPU field leaked handles")
	print("SWASH_GPU ", "PASS" if failures.is_empty() else "FAIL", " comparisons=", comparisons, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
