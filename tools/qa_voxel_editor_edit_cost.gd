extends SceneTree
## Opt-in visible Forward+ diagnostic Canvas. No authored Resource or scene is saved.

const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const SurfaceMesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const SOURCE := "res://content/world_surfaces/agent_sandbox_surface.tres"
const RESULT_BEFORE := "user://ember_editor_edit_cost_v15_before.json"
const RESULT_AFTER := "user://ember_editor_edit_cost_v15_after.json"
const STROKE_POINTS := 40

var _errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		_errors.append(message)
		printerr("EDIT_COST_FAIL ", message)


func _pending(canvas: Control) -> int:
	return (canvas.get("_pending_preview_chunks") as Dictionary).size()


func _settle(canvas: Control, timeout_ms := 120000) -> Dictionary:
	var start := Time.get_ticks_usec()
	var frame_await_usec := 0
	var frames := 0
	while _pending(canvas) > 0 and Time.get_ticks_usec() - start < timeout_ms * 1000:
		var before := Time.get_ticks_usec()
		await process_frame
		frame_await_usec += Time.get_ticks_usec() - before
		frames += 1
	_check(_pending(canvas) == 0, "preview queue did not settle")
	return {
		"queue_wall_usec": Time.get_ticks_usec() - start,
		"frame_await_wall_usec_including_work": frame_await_usec,
		"frames": frames,
	}


func _line(resource: EmberVoxelModelResource, heights: PackedInt32Array, wet: bool) -> Dictionary:
	var size := resource.grid_size()
	var best: Array[Vector3i] = []
	for z in range(20, size.z - 20):
		var consecutive: Array[Vector3i] = []
		for x in range(20, size.x - 20):
			var height := int(heights[x + z * size.x])
			var is_wet := SurfaceMesher.water_height_at(resource, Vector2i(x, z)) >= 0
			if height > 0 and is_wet == wet:
				consecutive.append(Vector3i(x, height - 1, z))
				if consecutive.size() >= STROKE_POINTS:
					return {"centers": consecutive, "contiguous": true}
			else:
				if consecutive.size() > best.size():
					best = consecutive.duplicate()
				consecutive.clear()
		if consecutive.size() > best.size():
			best = consecutive.duplicate()
	# Preserve one row and classification if the fixture has no 40-cell run.
	var by_row: Array[Vector3i] = []
	for z in range(20, size.z - 20):
		by_row.clear()
		for x in range(20, size.x - 20):
			var height := int(heights[x + z * size.x])
			if height > 0 and (SurfaceMesher.water_height_at(resource, Vector2i(x, z)) >= 0) == wet:
				by_row.append(Vector3i(x, height - 1, z))
				if by_row.size() >= STROKE_POINTS:
					return {"centers": by_row.duplicate(), "contiguous": false, "longest_run": best.size()}
	return {"centers": best, "contiguous": best.size() >= STROKE_POINTS, "longest_run": best.size()}


func _configure_paint(canvas: Control) -> void:
	canvas.call("_activate_tool_id", Model.TOOL_PAINT)
	var radius := canvas.get("_radius") as OptionButton
	radius.select(mini(2, radius.item_count - 1))
	var palette := canvas.get("_palette") as OptionButton
	var resource := canvas.get("_resource") as EmberVoxelModelResource
	canvas.call("_select_option_metadata", palette, resource.palette.size() - 1)


func _paint(canvas: Control, undo: UndoRedo, centers: Array[Vector3i], traced: bool) -> Dictionary:
	_configure_paint(canvas)
	var trace = canvas.get("_edit_trace") if traced else null
	if traced:
		trace.begin_operation("prepare")
	canvas.call("_prepare_stroke", Model.TOOL_PAINT)
	if traced:
		trace.end_operation()
	var hold_start := Time.get_ticks_usec()
	var direct_usec := 0
	var frame_await_usec := 0
	if traced:
		trace.begin_operation("paint_hold")
	for center in centers:
		var step_start := Time.get_ticks_usec()
		var points: Array[Vector3i] = [center]
		canvas.call("_apply_stroke_centers", points)
		direct_usec += Time.get_ticks_usec() - step_start
		var frame_start := Time.get_ticks_usec()
		await process_frame
		frame_await_usec += Time.get_ticks_usec() - frame_start
	if traced:
		trace.end_operation()
	var hold_usec := Time.get_ticks_usec() - hold_start
	var changed := (canvas.get("_stroke_changes") as Dictionary).size()
	_check(changed > 0, "paint changed no voxels")
	if traced:
		trace.begin_operation("pointer_up")
	var pointer_start := Time.get_ticks_usec()
	canvas.call("_finish_stroke")
	var pointer_usec := Time.get_ticks_usec() - pointer_start
	if traced:
		trace.end_operation()
	var exact_pending := _pending(canvas)
	if traced:
		trace.begin_operation("exact_settle")
	var exact := await _settle(canvas)
	if traced:
		trace.end_operation()
	var undo_usec := 0
	var redo_usec := 0
	var undo_settle := {}
	var redo_settle := {}
	if changed > 0:
		if traced:
			trace.begin_operation("undo_call")
		var start := Time.get_ticks_usec()
		undo.undo()
		undo_usec = Time.get_ticks_usec() - start
		if traced:
			trace.end_operation()
		if traced:
			trace.begin_operation("undo_settle")
		undo_settle = await _settle(canvas)
		if traced:
			trace.end_operation()
		if traced:
			trace.begin_operation("redo_call")
		start = Time.get_ticks_usec()
		undo.redo()
		redo_usec = Time.get_ticks_usec() - start
		if traced:
			trace.end_operation()
		if traced:
			trace.begin_operation("redo_settle")
		redo_settle = await _settle(canvas)
		if traced:
			trace.end_operation()
	return {
		"changed_voxels": changed,
		"hold_wall_usec_including_frames": hold_usec,
		"paint_direct_calls_usec": direct_usec,
		"hold_frame_await_wall_usec_including_chunk_work": frame_await_usec,
		"pointer_up_direct_usec": pointer_usec,
		"exact_pending_after_pointer_up": exact_pending,
		"exact_settle": exact,
		"undo_direct_usec": undo_usec,
		"undo_settle": undo_settle,
		"redo_direct_usec": redo_usec,
		"redo_settle": redo_settle,
	}


func _trial(source: EmberVoxelModelResource, centers: Array[Vector3i], site: String, adaptive: bool, repeat: int) -> Dictionary:
	var resource := source.duplicate(true) as EmberVoxelModelResource
	var undo := UndoRedo.new()
	var canvas := Workspace.new()
	canvas.setup(null, undo)
	root.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.open_surface(resource, "user://ember-tests/edit-cost-%s.tres" % site)
	if adaptive:
		var option := canvas.get("_perf_chunk_mode") as OptionButton
		option.select(1)
		canvas.call("_on_perf_chunk_mode_changed", 1)
	await _settle(canvas)
	var warm_start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warm_start < 1500000:
		await RenderingServer.frame_post_draw
	# Warm the exact same edit path, then restore the identical source state.
	await _paint(canvas, undo, centers, false)
	undo.undo()
	await _settle(canvas)
	undo.clear_history()
	var source_equal := resource.voxels == source.voxels
	var transparency_equal := resource.transparency == source.transparency
	_check(source_equal, "warm-up did not restore source voxels: %s/%s" % [site, adaptive])
	_check(transparency_equal, "warm-up did not restore transparency")
	var viewport := canvas.get("_viewport") as SubViewport
	var preflight := canvas.editor_performance_snapshot() as Dictionary
	_check(int(canvas.call("_preview_chunk_size")) == (32 if adaptive else 16), "chunk size mismatch")
	_check(bool(preflight.studio_shadows), "Shadows OFF in edit-cost trial")
	_check(str(preflight.msaa_label) == "4x", "MSAA not 4x in edit-cost trial")
	canvas.begin_edit_cost_trace()
	var gesture := await _paint(canvas, undo, centers, true)
	var trace := canvas.end_edit_cost_trace()
	var result := {
		"site": site,
		"mode": "Adaptive 32" if adaptive else "Legacy 16",
		"repeat": repeat,
		"starting_voxels_equal_source": source_equal,
		"starting_transparency_equal_source": transparency_equal,
		"chunk_size": int(canvas.call("_preview_chunk_size")),
		"viewport": "standalone_diagnostic_canvas_subviewport",
		"viewport_size": [viewport.size.x, viewport.size.y],
		"editor_hint": Engine.is_editor_hint(),
		"studio_shadows": bool(preflight.studio_shadows),
		"msaa_label": str(preflight.msaa_label),
		"context_sources": int(preflight.context_sources),
		"gesture": gesture,
		"trace": trace,
	}
	undo.undo()
	await _settle(canvas)
	canvas.queue_free()
	await process_frame
	undo.clear_history()
	undo.free()
	return result


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "visible Forward+ display required")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	var loaded := ResourceLoader.load(SOURCE, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(loaded != null, "Surface source did not load")
	if loaded == null:
		quit(1)
		return
	var heights := Model.column_heights(loaded.voxels, loaded.grid_size(), loaded.palette.size() - 1)
	var dry := _line(loaded, heights, false)
	var wet := _line(loaded, heights, true)
	_check((dry.centers as Array).size() >= STROKE_POINTS, "no dry 40-cell line")
	_check((wet.centers as Array).size() >= STROKE_POINTS, "no wet 40-cell line")
	if not _errors.is_empty():
		quit(1)
		return
	var result := {
		"fixture": SOURCE,
		"grid": [loaded.grid_size().x, loaded.grid_size().y, loaded.grid_size().z],
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"root_window_size": [root.size.x, root.size.y],
		"engine_max_fps": Engine.max_fps,
		"window_vsync_mode": DisplayServer.window_get_vsync_mode(),
		"project_max_fps": ProjectSettings.get_setting("application/run/max_fps", "unset"),
		"project_vsync_mode": ProjectSettings.get_setting("display/window/vsync/vsync_mode", "unset"),
		"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(),
		"cmdline_args": Array(OS.get_cmdline_args()),
		"cmdline_user_args": Array(OS.get_cmdline_user_args()),
		"scenario": "direct paint-center calls, 40 points, one process_frame between calls; no mouse/pointer routing; Context OFF",
		"dry_line": {"from": str((dry.centers as Array)[0]), "to": str((dry.centers as Array)[STROKE_POINTS - 1]), "contiguous": dry.contiguous},
		"wet_line": {"from": str((wet.centers as Array)[0]), "to": str((wet.centers as Array)[STROKE_POINTS - 1]), "contiguous": wet.contiguous},
		"trials": [],
	}
	var order := [
		["dry", false, 1], ["dry", true, 1],
		["wet", true, 1], ["wet", false, 1],
		["wet", false, 2], ["wet", true, 2],
		["dry", true, 2], ["dry", false, 2],
	]
	for item in order:
		var centers: Array[Vector3i] = wet.centers if item[0] == "wet" else dry.centers
		var trial := await _trial(loaded, centers, item[0], item[1], item[2])
		result.trials.append(trial)
		print("EDIT_COST_TRIAL ", item[0], " ", trial.mode, " #", item[2], " hold=", trial.gesture.hold_wall_usec_including_frames, " direct=", trial.gesture.paint_direct_calls_usec, " chunks=", (trial.trace.chunks as Array).size())
	var result_path := RESULT_AFTER if "--after-fix" in OS.get_cmdline_user_args() else RESULT_BEFORE
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	_check(file != null, "could not write edit-cost report")
	if file != null:
		file.store_string(JSON.stringify(result, "  "))
		file.close()
		print("EDIT_COST_RESULT ", ProjectSettings.globalize_path(result_path))
	print("EDIT_COST_STATUS ", "PASS" if _errors.is_empty() else "FAIL: " + "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)
