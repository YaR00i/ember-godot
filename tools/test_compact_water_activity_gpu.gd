extends SceneTree
## Real Forward+ readback: seam history at 20 Hz, far interiors at 5 Hz.
const Swash = preload("res://scripts/prototypes/ember_compact_sea_swash.gd")
const Fixture = preload("res://tools/test_compact_water_activity.gd")
var failures: Array[String] = []

func _initialize() -> void: _run.call_deferred()
func frames(count := 2) -> void:
	for i in count: await process_frame
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); printerr("WATER_ACTIVITY_GPU FAIL ", message)
func same(a: Color, b: Dictionary) -> bool:
	return absf(a.r - b.height) < 0.0002 and absf(a.g - b.foam) < 0.0002 and absf(a.b - b.wetness) < 0.0002 and absf(a.a - b.coverage) < 0.0002

func _run() -> void:
	if DisplayServer.get_name() == "headless": printerr("Native Forward+ required."); quit(1); return
	var source := Fixture.source()
	var exact := Swash.new(); exact.use_gpu = false; exact.build(source)
	var coarse := Swash.new(); coarse.use_gpu = false; coarse.build(source)
	var gpu := Swash.new(); gpu.build(source, PackedByteArray(), Vector2i.ZERO, Rect2i(384, 0, 384, 64))
	await frames(8)
	check(gpu._gpu != null and gpu._gpu.ready and gpu._gpu.error.is_empty(), "compute initialization")
	if not failures.is_empty(): quit(1); return
	var comparisons := 0
	for step in 241:
		var seconds := step * 0.05
		exact.advance(seconds, 2.8, 8.0, 10.0, -0.35, 6.0)
		gpu.advance(seconds, 2.8, 8.0, 10.0, -0.35, 6.0, 20.0, 0.65, false)
		if step % 4 == 0: coarse.advance(seconds, 2.8, 8.0, 10.0, -0.35, 6.0)
		await frames()
		if step % 3 != 0: continue
		var image: Image = gpu.state_texture.get_image()
		var age: Image = gpu.foam_age_texture.get_image()
		# Both sides of a core edge, including dry ground, retain full clock/history.
		for x in [376, 383, 384, 385, 392, 760, 767]:
			for z in [15, 30, 32, 37, 45]:
				var p := Vector2i(x, z)
				var expected: Dictionary = exact.sample(p)
				var pixel := p - gpu.bounds.position
				check(same(image.get_pixelv(pixel), expected) and absf(age.get_pixelv(pixel).r - expected.foam_age) < 0.0002,
					"shared seam history at %d / %s" % [step, p])
				comparisons += 1
		for p: Vector2i in [Vector2i(600, 15), Vector2i(600, 32), Vector2i(600, 37), Vector2i(600, 45)]:
			var expected: Dictionary = coarse.sample(p)
			var pixel := p - gpu.bounds.position
			check(same(image.get_pixelv(pixel), expected) and absf(age.get_pixelv(pixel).r - expected.foam_age) < 0.0002,
				"far foam/wetness five-Hz history at %d / %s" % [step, p])
			var current: Dictionary = gpu.sample(p, false)
			check(absf(current.height - exact.sample(p, false).height) < 0.0002, "physical query fell behind far GPU")
			comparisons += 1
	check(gpu._gpu.full_dispatches == 61 and gpu._gpu.border_dispatches == 180, "wrong 20/5 dispatch ratio")
	var reduced_records: int = gpu._gpu.processed_records
	var all_records: int = gpu.records.size() * 241
	# Promote in between far ticks; current seam's age must not advance twice.
	exact.advance(12.05, 2.8, 8.0, 10.0, -0.35, 6.0)
	gpu.advance(12.05, 2.8, 8.0, 10.0, -0.35, 6.0, 20.0, 0.65, false)
	gpu.promote_gpu(); gpu.promote_gpu()
	await frames()
	check(gpu._gpu.full_dispatches == 62, "promotion repeated")
	var image: Image = gpu.state_texture.get_image()
	check(absf(image.get_pixelv(Vector2i(600, 32) - gpu.bounds.position).r - exact.sample(Vector2i(600, 32), false).height) < 0.0002, "approach did not catch up")
	for state in [exact, gpu]: state.advance(0.0, 0.0, 8.0, 10.0, -0.35, 6.0)
	await frames()
	image = gpu.state_texture.get_image()
	check(same(image.get_pixelv(Vector2i(600, 32) - gpu.bounds.position), exact.sample(Vector2i(600, 32))), "reset/disabled wave")
	gpu._gpu.release(); await frames()
	check(gpu._gpu._resources.is_empty(), "border GPU buffers leaked")
	print("WATER_ACTIVITY_GPU ", "PASS" if failures.is_empty() else "FAIL", " comparisons=", comparisons,
		" processed_records=", reduced_records, " full_rate_records=", all_records, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
