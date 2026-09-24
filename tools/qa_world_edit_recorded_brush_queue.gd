extends SceneTree
## Replays recorded 3D-editor cells/timestamps at WorldEditor's input-queue seam.
## This is a repeatable throughput/data check, not a substitute for the live tab.

const World = preload("res://addons/ember_import/ember_world_editor.gd")

class BackgroundReplayWorld extends World:
	# A background benchmark window loses OS focus; real user focus-out still
	# cancels the stroke in the unmodified editor.
	func _notification(_what: int) -> void:
		pass

var _errors: Array[String] = []
var _fixture_nodes: Array[Node] = []
var _history: UndoRedo


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	if not ok:
		_errors.append(reason)


func _argument(name: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(name + "="):
			return argument.substr(name.length() + 1)
	return ""


func _cell(input: Dictionary) -> Vector3i:
	var values: Array = input.get("cell", [])
	return Vector3i(int(values[0]), int(values[1]), int(values[2])) if values.size() == 3 else Vector3i(-9999, -9999, -9999)


func _screen(input: Dictionary) -> Vector2:
	var values: Array = input.get("screen", [])
	return Vector2(float(values[0]), float(values[1])) if values.size() == 2 else Vector2.ZERO


func _digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _run() -> void:
	var trace_path := _argument("--trace")
	if trace_path.is_empty():
		trace_path = "res://tools/fixtures/world_edit_level_real_cells_v1.json"
	var output_path := _argument("--output")
	if output_path.is_empty():
		output_path = "user://qa_world_edit_recorded_brush_queue.json"
	var source_file := FileAccess.open(trace_path, FileAccess.READ) if not trace_path.is_empty() else null
	if source_file == null:
		printerr("FAIL recorded brush queue: trace fixture cannot be opened")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(source_file.get_as_text())
	source_file.close()
	if not parsed is Dictionary:
		printerr("FAIL recorded brush queue: trace is not a dictionary")
		quit(1)
		return
	var recorded: Dictionary = {}
	if (parsed as Dictionary).has("points"):
		var points: Array = parsed.points
		var normalized: Array[Dictionary] = []
		for index in points.size():
			var point: Array = points[index]
			normalized.append({"kind":"press" if index == 0 else "release" if index == points.size() - 1 else "move","at_usec":int(point[0]),"cell":[int(point[1]),int(point[2]),int(point[3])]})
		recorded = {"tool":parsed.tool,"radius_blocks":parsed.radius_blocks,"depth_voxels":parsed.depth_voxels,"input":normalized}
	elif not (parsed as Dictionary).get("strokes", []).is_empty():
		recorded = parsed.strokes[0]
	else:
		printerr("FAIL recorded brush queue: trace has no points or strokes")
		quit(1)
		return
	var inputs: Array = recorded.get("input", [])
	if inputs.size() < 3 or str(recorded.get("tool", "")) != "level":
		printerr("FAIL recorded brush queue: expected recorded level stroke")
		quit(1)
		return

	var scene := Node3D.new()
	scene.name = "RecordedBrushQueueFixture"
	root.add_child(scene)
	_fixture_nodes.append(scene)
	var surface := EmberVoxelModelResource.new()
	surface.model_id = "recorded_brush_queue_fixture"
	surface.display_name = "Recorded brush queue fixture"
	surface.voxels_per_block = 16
	# Smallest whole-chunk map containing every recorded brush footprint.
	surface.size_blocks = Vector3i(14, 1, 15)
	surface.height_voxels = 32
	surface.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.GREEN])
	surface.physical = true
	var grid := surface.grid_size()
	var voxels := PackedByteArray()
	voxels.resize(grid.x * grid.y * grid.z)
	voxels.fill(1)
	surface.voxels = voxels
	var map := EmberMapLoader.new()
	map.name = "Map"
	map.map_id = "recorded_brush_queue_fixture"
	map.authored_size_blocks = Vector2i(14, 15)
	map.hydrate_legacy_regions = false
	map.visual_surface = surface
	scene.add_child(map)
	var camera := Camera3D.new()
	camera.position = Vector3(120, 260, 160)
	scene.add_child(camera)
	camera.look_at(Vector3(112, 0, 120))
	camera.current = true
	_history = UndoRedo.new()
	var world := BackgroundReplayWorld.new()
	root.add_child(world)
	_fixture_nodes.append(world)
	world.configure(null, _history)
	var toolbar := world.build_toolbar()
	var sidebar := world.build_sidebar()
	root.add_child(toolbar)
	root.add_child(sidebar)
	_fixture_nodes.append(toolbar)
	_fixture_nodes.append(sidebar)
	world.scene = scene
	world.map = map
	world.entry = world.sessions.open_map(map, scene)
	_check(not world.entry.is_empty(), "map draft did not open: " + world.sessions.error)
	if world.entry.is_empty():
		_finish()
		return
	world.actions.history_context = scene
	world.sessions.preview(world.entry)
	world._refresh_palette()
	world.category.select(0)
	world._category_changed(0)
	world.tools.select(5)
	world._tool_changed()
	world.palette.select(1)
	world.radius.value = float(recorded.radius_blocks)
	world.depth.value = float(recorded.depth_voxels)
	world.active = true
	var projection: Node = map._visual_surface_projection
	# Standalone --script does not set Engine.is_editor_hint(), so bind the same
	# draft that EmberMapLoader binds automatically in the actual editor tab.
	projection.configure(world.entry.resource, map.imported_tile_size, Vector2i(14, 15), null, true, null)
	var deadline := Time.get_ticks_msec() + 120000
	while is_instance_valid(projection) and not projection.is_projection_complete() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(is_instance_valid(projection) and projection.is_projection_complete(), "initial projection did not settle")
	if not _errors.is_empty():
		_finish()
		return
	for unused in 20:
		await process_frame
	var ground: EmberVoxelModelResource = world.entry.resource
	var original := ground.voxels.duplicate()
	world._trace.start()
	projection.editor_diagnostic_sink = world._trace
	var first_usec := int(inputs[0].at_usec)
	var start_usec := Time.get_ticks_usec() + 100000
	var cursor := 0
	while cursor < inputs.size():
		var now := Time.get_ticks_usec()
		while cursor < inputs.size() and start_usec + int(inputs[cursor].at_usec) - first_usec <= now:
			var input: Dictionary = inputs[cursor]
			var cell := _cell(input)
			var point := _screen(input)
			var due := start_usec + int(input.at_usec) - first_usec
			var pick := {"hit": cell, "adjacent": cell, "normal": Vector3i.UP}
			if cursor == 0:
				world._begin_stroke(pick, false, now, point, due)
			else:
				if str(input.kind) == "release":
					world.released = true
				world._trace.input(str(input.kind), now, point, cell, due)
				world._queue_pick(pick)
			cursor += 1
		if cursor < inputs.size():
			await process_frame
	deadline = Time.get_ticks_msec() + 120000
	while (world.dragging or not projection.is_projection_complete() or world._trace.strokes[0].postdraw_settled_usec == 0) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not world.dragging and projection.is_projection_complete(), "stroke/projection did not settle")
	var after := ground.voxels.duplicate()
	var report: Dictionary = world._trace.stop()
	projection.editor_diagnostic_sink = null
	if report.strokes.is_empty():
		_check(false, "no recorded stroke")
		_finish()
		return
	var stroke: Dictionary = report.strokes[0]
	stroke.input_source = "recorded_cell_queue_replay"
	var final_digest := _digest(after)
	var original_digest := _digest(original)
	var expected_digest := _argument("--expected-sha256")
	if expected_digest.is_empty():
		expected_digest = str((parsed as Dictionary).get("expected_sha256", ""))
	if not expected_digest.is_empty():
		_check(final_digest == expected_digest, "voxel result differs from the baseline algorithm")
	var undo_started := Time.get_ticks_usec()
	_history.undo()
	var undo_usec := Time.get_ticks_usec() - undo_started
	_check(ground.voxels == original, "Undo did not restore complete voxel array")
	var redo_started := Time.get_ticks_usec()
	_history.redo()
	var redo_usec := Time.get_ticks_usec() - redo_started
	_check(ground.voxels == after, "Redo did not restore complete voxel array")
	_history.undo()
	_check(ground.voxels == original, "second Undo did not restore original data")
	_check(int(stroke.queued_samples) == inputs.size(), "input samples were lost or skipped")
	_check(int(stroke.jobs_processed) == inputs.size(), "not all queued jobs were processed")
	if _argument("--assert-lag") == "true":
		_check(int(stroke.brush_input_age_usec.p95) < 9000000, "p95 brush input age still exceeds 9 s")
	report.scope = "recorded timed cells replayed through main WorldEditor queue; not live Godot editor 3D tab"
	report.metadata = {"fixture": "14x15 flat solid map, density 16; complete recorded footprint; Forward+ if non-headless", "recorded_input_events": inputs.size()}
	report["data_before_sha256"] = original_digest
	report["data_after_sha256"] = final_digest
	report["undo_usec"] = undo_usec
	report["redo_usec"] = redo_usec
	report["checks_passed"] = _errors.is_empty()
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		_check(false, "cannot write output report")
	else:
		output.store_string(JSON.stringify(report))
		output.close()
	print("RECORDED_BRUSH_QUEUE jobs=", stroke.jobs_processed, " steps=", stroke.steps_processed, " changed=", stroke.changed_unique_voxels, " queue_peak=", stroke.max_brush_queue, " age_p95_ms=", float(stroke.brush_input_age_usec.p95) / 1000.0, " age_max_ms=", float(stroke.brush_input_age_usec.max) / 1000.0, " drain_ms=", float(stroke.release_to_queue_drain_usec) / 1000.0, " digest=", final_digest, " output=", output_path)
	_finish()


func _finish() -> void:
	if _history != null:
		_history.clear_history()
	for index in [3, 2, 1, 0]:
		if index < _fixture_nodes.size() and is_instance_valid(_fixture_nodes[index]):
			_fixture_nodes[index].free()
	_fixture_nodes.clear()
	if _history != null:
		_history.free()
		_history = null
	if _errors.is_empty():
		print("PASS recorded brush queue: complete input, voxel result and Undo/Redo")
	else:
		for reason in _errors:
			printerr("FAIL recorded brush queue: ", reason)
	call_deferred("_quit_after_cleanup", 0 if _errors.is_empty() else 1)


func _quit_after_cleanup(code: int) -> void:
	await process_frame
	await process_frame
	quit(code)
