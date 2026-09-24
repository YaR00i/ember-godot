extends SceneTree
## Opt-in native Forward+ A/B fixture. Reads authored sources; writes only user:// QA.

const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const SURFACE_PATH := "res://content/world_surfaces/agent_sandbox_surface.tres"
const PIER_PATH := "res://scenes/test_pier.tscn"
const RESULT_PATH := "user://ember_editor_performance_ab_v13.json"
const DIAGNOSTICS_RESULT_PATH := "user://ember_editor_performance_diagnostics_v14.json"

var _errors: Array[String] = []
var _results := {}


func _init() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
		printerr("QA_FAIL ", message)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "Forward+ fixture needs a visible display server")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	_results["display_server"] = DisplayServer.get_name()
	_results["renderer"] = RenderingServer.get_current_rendering_method()
	_results["adapter"] = RenderingServer.get_video_adapter_name()
	_results["window"] = [1600, 900]

	if "--diagnostics-only" in OS.get_cmdline_user_args():
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		var previous := FileAccess.open(RESULT_PATH, FileAccess.READ)
		if previous != null:
			var parsed = JSON.parse_string(previous.get_as_text())
			previous.close()
			if parsed is Dictionary:
				_results.merge(parsed, false)
		if not _results.has("surface") or not _results.has("context"):
			await _measure_surface()
			await _measure_context()
		await _measure_diagnostics()
	else:
		await _measure_surface()
		if "--surface-only" not in OS.get_cmdline_user_args():
			await _measure_context()
	_finish()


func _make_workspace(undo: UndoRedo) -> Control:
	var canvas := Workspace.new()
	canvas.setup(null, undo)
	root.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return canvas


func _chunk_count(canvas: Control) -> int:
	return (canvas.get("_chunk_meshes") as Dictionary).size()


func _pending_count(canvas: Control) -> int:
	return (canvas.get("_pending_preview_chunks") as Dictionary).size()


func _settle(canvas: Control, timeout_ms := 120000) -> float:
	var start := Time.get_ticks_msec()
	while _pending_count(canvas) > 0 and Time.get_ticks_msec() - start < timeout_ms:
		await process_frame
	for frame in 20:
		await process_frame
	_check(_pending_count(canvas) == 0, "Canvas preview queue did not settle")
	return float(Time.get_ticks_msec() - start)


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	values.sort()
	return values[values.size() / 2]


func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	values.sort()
	return values[clampi(ceili(fraction * values.size()) - 1, 0, values.size() - 1)]


func _sample(canvas: Control) -> Dictionary:
	var fps: Array[float] = []
	var draws: Array[float] = []
	var objects: Array[float] = []
	var primitives: Array[float] = []
	var report := canvas.get("_context_report") as Dictionary
	for frame in 90:
		await process_frame
		var snapshot := canvas.editor_performance_snapshot() as Dictionary
		if frame >= 30:
			fps.append(float(snapshot.fps))
			draws.append(float(snapshot.draw_calls))
			objects.append(float(snapshot.objects))
			primitives.append(float(snapshot.primitives))
	return {
		"fps": _median(fps),
		"draw_calls": _median(draws),
		"visible_objects": _median(objects),
		"primitives": _median(primitives),
		"live_chunks": _chunk_count(canvas),
		"pending_chunks": _pending_count(canvas),
		"context_sources": int(report.get("source_count", 0)),
		"context_visuals": int(report.get("visual_count", 0)),
		"context_batched": int(report.get("batched_instances", 0)),
		"context_culled": int(report.get("culled_count", 0)),
		"context_rebuild_ms": float(report.get("milliseconds", 0.0)),
	}


func _capture(canvas: Control, label: String) -> String:
	await RenderingServer.frame_post_draw
	var path := "user://ember_editor_perf_%s.png" % label
	var viewport := canvas.get("_viewport") as SubViewport
	var image := viewport.get_texture().get_image()
	_check(image.save_png(path) == OK, "Canvas capture failed: " + label)
	return ProjectSettings.globalize_path(path)


func _surface_line(canvas: Control, minimum := 40) -> Array[Vector3i]:
	var resource := canvas.get("_resource") as EmberVoxelModelResource
	var heights := canvas.get("_surface_heightfield") as PackedInt32Array
	var size := resource.grid_size()
	for z in range(24, size.z - 24):
		var line: Array[Vector3i] = []
		for x in range(24, size.x - 24):
			var height := heights[x + z * size.x]
			if height > 0:
				line.append(Vector3i(x, height - 1, z))
				if line.size() >= minimum:
					return line
			else:
				line.clear()
	return []


func _measure_gesture(canvas: Control, undo: UndoRedo, tool_id: int, centers: Array[Vector3i]) -> Dictionary:
	canvas.call("_activate_tool_id", tool_id)
	var radius := canvas.get("_radius") as OptionButton
	radius.select(mini(2, radius.item_count - 1))
	if tool_id == Model.TOOL_PAINT:
		var palette := canvas.get("_palette") as OptionButton
		var resource := canvas.get("_resource") as EmberVoxelModelResource
		canvas.call("_select_option_metadata", palette, resource.palette.size() - 1)
	canvas.call("_prepare_stroke", tool_id)
	var step_times: Array[float] = []
	var start := Time.get_ticks_usec()
	var previous_height := 0
	for index in centers.size():
		var points: Array[Vector3i] = [centers[index]]
		var step_start := Time.get_ticks_usec()
		if tool_id == Model.TOOL_PAINT:
			canvas.call("_apply_stroke_centers", points)
		else:
			var height := index + 1
			canvas.call("_apply_stroke_centers", points, height, previous_height)
			previous_height = height
		step_times.append(float(Time.get_ticks_usec() - step_start) / 1000.0)
		await process_frame
	var hold_ms := float(Time.get_ticks_usec() - start) / 1000.0
	var changed := (canvas.get("_stroke_changes") as Dictionary).size()
	var pointer_start := Time.get_ticks_usec()
	canvas.call("_finish_stroke")
	var pointer_ms := float(Time.get_ticks_usec() - pointer_start) / 1000.0
	var exact_queue := _pending_count(canvas)
	var exact_settle_ms := await _settle(canvas)
	_check(changed > 0, "gesture did not change voxels: %d" % tool_id)
	var undo_ms := 0.0
	var redo_ms := 0.0
	if changed > 0:
		var undo_start := Time.get_ticks_usec()
		undo.undo()
		undo_ms = float(Time.get_ticks_usec() - undo_start) / 1000.0
		await _settle(canvas)
		var redo_start := Time.get_ticks_usec()
		undo.redo()
		redo_ms = float(Time.get_ticks_usec() - redo_start) / 1000.0
		await _settle(canvas)
		undo.undo()
		await _settle(canvas)
	return {
		"changed_voxels": changed,
		"hold_wall_ms": hold_ms,
		"max_step_ms": step_times.max() if not step_times.is_empty() else 0.0,
		"pointer_up_ms": pointer_ms,
		"exact_queue": exact_queue,
		"exact_settle_ms": exact_settle_ms,
		"undo_ms": undo_ms,
		"redo_ms": redo_ms,
	}


func _measure_surface() -> void:
	var loaded := ResourceLoader.load(SURFACE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(loaded != null, "large Surface failed to load")
	if loaded == null:
		return
	var resource := loaded.duplicate(true) as EmberVoxelModelResource
	var undo := UndoRedo.new()
	var canvas := _make_workspace(undo)
	canvas.open_surface(resource, "user://ember-tests/perf-ab-surface.tres")
	var line := _surface_line(canvas)
	_check(line.size() >= 40, "no long occupied line on profile Surface")
	var modes := {}
	for mode in 2:
		if mode == 1:
			var option := canvas.get("_perf_chunk_mode") as OptionButton
			option.select(1)
			canvas.call("_on_perf_chunk_mode_changed", 1)
		var settle_ms := await _settle(canvas)
		var data := await _sample(canvas)
		data["chunk_size"] = int(canvas.call("_preview_chunk_size"))
		data["open_or_switch_settle_ms"] = settle_ms
		data["capture"] = await _capture(canvas, "surface_legacy" if mode == 0 else "surface_adaptive")
		if line.size() >= 40:
			data["paint"] = await _measure_gesture(canvas, undo, Model.TOOL_PAINT, line)
			var relief: Array[Vector3i] = []
			for index in 4:
				relief.append(line[20])
			data["relief"] = await _measure_gesture(canvas, undo, Model.TOOL_RAISE, relief)
		modes["Legacy 16" if mode == 0 else "Adaptive"] = data
		print("QA_SURFACE_MODE ", "Legacy 16" if mode == 0 else "Adaptive", " ", JSON.stringify(data))
	var chunk_option := canvas.get("_perf_chunk_mode") as OptionButton
	for mode in 2:
		chunk_option.select(mode)
		canvas.call("_on_perf_chunk_mode_changed", mode)
		await _settle(canvas)
		var repeat := await _sample(canvas)
		modes["Legacy 16 repeat" if mode == 0 else "Adaptive repeat"] = repeat
		print("QA_SURFACE_REPEAT ", "Legacy 16" if mode == 0 else "Adaptive", " ", JSON.stringify(repeat))
	_results["surface"] = {"grid": [384, 32, 384], "modes": modes}
	canvas.queue_free()
	await process_frame
	undo.clear_history()
	undo.free()


func _diagnostic_sample(canvas: Control) -> Dictionary:
	var keys := PackedStringArray([
		"fps", "visible_draw_calls", "visible_objects", "visible_primitives",
		"shadow_draw_calls", "shadow_objects", "shadow_primitives",
		"canvas_cpu_ms", "canvas_gpu_ms", "frame_setup_cpu_ms",
		"root_cpu_ms", "root_gpu_ms", "frame_interval_ms",
	])
	var series := {}
	for key in keys:
		series[key] = []
	var warm_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - warm_start < 1500:
		await RenderingServer.frame_post_draw
	var latest := {}
	var previous_frame_usec := Time.get_ticks_usec()
	for frame in 120:
		await RenderingServer.frame_post_draw
		var current_frame_usec := Time.get_ticks_usec()
		latest = canvas.editor_performance_snapshot()
		latest["root_cpu_ms"] = RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		latest["root_gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		latest["frame_interval_ms"] = float(current_frame_usec - previous_frame_usec) / 1000.0
		previous_frame_usec = current_frame_usec
		for key in keys:
			series[key].append(float(latest.get(key, 0.0)))
	var data := {
		"sampled_frames": 120,
		"warm_ms": 1500,
		"chunk_size": int(canvas.call("_preview_chunk_size")),
		"live_chunks": int(latest.get("render_chunks", 0)),
		"pending_chunks": int(latest.get("pending_chunks", 0)),
		"context_sources": int(latest.get("context_sources", 0)),
		"context_visuals": int(latest.get("context_visuals", 0)),
		"studio_shadows": bool(latest.get("studio_shadows", false)),
		"msaa_label": str(latest.get("msaa_label", "Off")),
	}
	for key in keys:
		var numbers: Array[float] = []
		for value in series[key]:
			numbers.append(float(value))
		data[key + "_median"] = _median(numbers)
		data[key + "_p95"] = _percentile(numbers, 0.95)
	data["fps"] = data["fps_median"]
	data["measured_fps_from_frame_interval"] = (
		1000.0 / float(data["frame_interval_ms_median"])
		if float(data["frame_interval_ms_median"]) > 0.0 else 0.0
	)
	return data


func _diagnostic_mode(
	canvas: Control,
	undo: UndoRedo,
	line: Array[Vector3i],
	mode_name: String,
	chunk_index: int,
	shadows_enabled: bool,
	msaa_index: int,
	measure_edit: bool,
) -> Dictionary:
	var chunks := canvas.get("_perf_chunk_mode") as OptionButton
	var shadows := canvas.get("_perf_shadow_toggle") as CheckButton
	var msaa := canvas.get("_perf_msaa") as OptionButton
	if chunks.selected != chunk_index:
		chunks.select(chunk_index)
		canvas.call("_on_perf_chunk_mode_changed", chunk_index)
	shadows.button_pressed = shadows_enabled
	if msaa.selected != msaa_index:
		msaa.select(msaa_index)
		msaa.item_selected.emit(msaa_index)
	var settle_ms := await _settle(canvas)
	var data := await _diagnostic_sample(canvas)
	data["mode"] = mode_name
	data["settle_ms"] = settle_ms
	if mode_name.begins_with("A Legacy 16"):
		await RenderingServer.frame_post_draw
		var ui_path := "user://ember_editor_perf_diagnostics_ui.png"
		var ui_image := root.get_texture().get_image()
		_check(ui_image.save_png(ui_path) == OK, "diagnostic UI capture failed")
		data["ui_capture"] = ProjectSettings.globalize_path(ui_path)
	_check(bool(data.studio_shadows) == shadows_enabled, "shadow state mismatch: " + mode_name)
	_check(str(data.msaa_label) == ["Off", "2x", "4x"][msaa_index], "MSAA state mismatch: " + mode_name)
	_check(int(data.pending_chunks) == 0, "pending chunks after sample: " + mode_name)
	_check(int(data.context_sources) == 0, "context was not OFF: " + mode_name)
	if measure_edit and line.size() >= 40:
		data["paint"] = await _measure_gesture(canvas, undo, Model.TOOL_PAINT, line)
		var relief: Array[Vector3i] = []
		for index in 4:
			relief.append(line[20])
		data["relief"] = await _measure_gesture(canvas, undo, Model.TOOL_RAISE, relief)
	print("QA_DIAGNOSTICS_MODE ", mode_name, " ", JSON.stringify(data))
	return data


func _adaptive_cost_ratio(legacy: Dictionary, adaptive: Dictionary) -> float:
	var legacy_gpu := float(legacy.get("canvas_gpu_ms_median", 0.0))
	var adaptive_gpu := float(adaptive.get("canvas_gpu_ms_median", 0.0))
	if legacy_gpu > 0.0 and adaptive_gpu > 0.0:
		return adaptive_gpu / legacy_gpu
	var legacy_fps := float(legacy.get("fps_median", 0.0))
	var adaptive_fps := float(adaptive.get("fps_median", 0.0))
	return legacy_fps / adaptive_fps if adaptive_fps > 0.0 else 0.0


func _measure_diagnostics() -> void:
	var loaded := ResourceLoader.load(SURFACE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(loaded != null, "diagnostics Surface failed to load")
	if loaded == null:
		return
	var resource := loaded.duplicate(true) as EmberVoxelModelResource
	var undo := UndoRedo.new()
	var canvas := _make_workspace(undo)
	canvas.open_surface(resource, "user://ember-tests/perf-diagnostics-surface.tres")
	var line := _surface_line(canvas)
	_check(line.size() >= 40, "diagnostics paint line missing")
	var modes := {}
	var configurations := [
		["A Legacy 16 · Shadows ON · MSAA 4x", 0, true, 2, true],
		["B Adaptive 32 · Shadows ON · MSAA 4x", 1, true, 2, true],
		["C Legacy 16 · Shadows OFF · MSAA 4x", 0, false, 2, true],
		["D Adaptive 32 · Shadows OFF · MSAA 4x", 1, false, 2, true],
		["E Legacy 16 · Shadows ON · MSAA Off", 0, true, 0, false],
		["F Adaptive 32 · Shadows ON · MSAA Off", 1, true, 0, false],
	]
	for config in configurations:
		modes[config[0]] = await _diagnostic_mode(
			canvas, undo, line, config[0], config[1], config[2], config[3], config[4]
		)
	var ratio_4x := _adaptive_cost_ratio(modes[configurations[0][0]], modes[configurations[1][0]])
	var ratio_off := _adaptive_cost_ratio(modes[configurations[4][0]], modes[configurations[5][0]])
	var msaa_ratio_change := absf(ratio_off / ratio_4x - 1.0) if ratio_4x > 0.0 else 0.0
	if msaa_ratio_change >= 0.15:
		for config in [
			["G Legacy 16 · Shadows ON · MSAA 2x", 0, true, 1, false],
			["H Adaptive 32 · Shadows ON · MSAA 2x", 1, true, 1, false],
		]:
			modes[config[0]] = await _diagnostic_mode(
				canvas, undo, line, config[0], config[1], config[2], config[3], config[4]
			)
	# Revisit the original A/B state so warm-up or external load is visible.
	for config in [
		["A repeat Legacy 16 · Shadows ON · MSAA 4x", 0, true, 2, false],
		["B repeat Adaptive 32 · Shadows ON · MSAA 4x", 1, true, 2, false],
	]:
		modes[config[0]] = await _diagnostic_mode(
			canvas, undo, line, config[0], config[1], config[2], config[3], config[4]
		)
	_results["diagnostics"] = {
		"fixture": SURFACE_PATH,
		"grid": [384, 32, 384],
		"camera": "Canvas default overview, unchanged between modes",
		"sampled_frames_per_mode": 120,
		"warm_ms_per_mode": 1500,
		"msaa_adaptive_cost_ratio_4x": ratio_4x,
		"msaa_adaptive_cost_ratio_off": ratio_off,
		"msaa_ratio_relative_change": msaa_ratio_change,
		"modes": modes,
	}
	canvas.queue_free()
	await process_frame
	undo.clear_history()
	undo.free()


func _measure_context() -> void:
	var packed := load(PIER_PATH) as PackedScene
	_check(packed != null, "Pier scene failed to load")
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var projection := scene.get_node("Map").get("_visual_surface_projection") as Node
	var deadline := Time.get_ticks_msec() + 120000
	while projection != null and not projection.call("is_projection_complete") and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(projection != null and projection.call("is_projection_complete"), "Pier projection did not settle")
	var target := scene.get_node("Map/Props/BarrelA") as EmberVoxelProp
	var shared_mesh := BoxMesh.new()
	for index in 12:
		var prop := MeshInstance3D.new()
		prop.mesh = shared_mesh
		prop.name = "PerfRepeated_%d" % index
		scene.add_child(prop)
		prop.global_position = target.global_position + Vector3(float(index % 4) * 4.0, 0.0, float(index / 4) * 4.0)
	var undo := UndoRedo.new()
	var session := Session.new()
	_check(session.open(target, scene, undo), "Object Canvas session failed: " + session.error)
	if not session.error.is_empty():
		scene.queue_free()
		return
	var canvas := _make_workspace(undo)
	canvas.open_object(session)
	var context_toggle := canvas.get("_context_toggle") as CheckButton
	var context_mode := canvas.get("_context_mode") as OptionButton
	var opacity := canvas.get("_context_opacity") as SpinBox
	context_toggle.button_pressed = true
	for frame in 30:
		await process_frame
	var modes := {}
	modes["Legacy Context 60%"] = await _sample(canvas)
	modes["Legacy Context 60%"]["capture"] = await _capture(canvas, "context_legacy_60")
	context_mode.select(1)
	context_mode.item_selected.emit(1)
	for frame in 30:
		await process_frame
	modes["Optimized Context 60%"] = await _sample(canvas)
	modes["Optimized Context 60%"]["capture"] = await _capture(canvas, "context_optimized_60")
	var report := canvas.get("_context_report") as Dictionary
	_check(not bool(report.get("batching_allowed", true)), "Optimized 60% unexpectedly batches")
	_check(int(report.get("batched_instances", -1)) == 0, "Optimized 60% batch count is nonzero")
	opacity.value = 100
	for frame in 30:
		await process_frame
	modes["Optimized Context 100%"] = await _sample(canvas)
	modes["Optimized Context 100%"]["capture"] = await _capture(canvas, "context_optimized_100")
	report = canvas.get("_context_report") as Dictionary
	_check(bool(report.get("batching_allowed", false)), "60 -> 100 did not enable batching")
	_check(int(report.get("batched_instances", 0)) >= 12, "60 -> 100 did not batch repeated props")
	opacity.value = 60
	for frame in 30:
		await process_frame
	var return_60 := await _sample(canvas)
	report = canvas.get("_context_report") as Dictionary
	_check(not bool(report.get("batching_allowed", true)), "100 -> 60 left batching enabled")
	_check(int(report.get("batched_instances", -1)) == 0, "100 -> 60 left a MultiMesh batch")
	modes["Optimized Context 60% return"] = return_60
	context_mode.select(0)
	context_mode.item_selected.emit(0)
	for frame in 30:
		await process_frame
	modes["Legacy Context 60% repeat"] = await _sample(canvas)
	_results["context"] = {"scene": PIER_PATH, "modes": modes}
	for key in modes:
		print("QA_CONTEXT_MODE ", key, " ", JSON.stringify(modes[key]))
	canvas.queue_free()
	await process_frame
	undo.clear_history()
	undo.free()
	scene.queue_free()
	await process_frame


func _finish() -> void:
	_results["errors"] = _errors
	var path := DIAGNOSTICS_RESULT_PATH if _results.has("diagnostics") else RESULT_PATH
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_results, "  "))
		file.close()
	print("QA_RESULT ", ProjectSettings.globalize_path(path))
	print("QA_STATUS ", "PASS" if _errors.is_empty() else "FAIL")
	quit(0 if _errors.is_empty() else 1)
