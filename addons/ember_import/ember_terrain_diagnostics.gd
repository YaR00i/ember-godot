@tool
extends RefCounted
## Read-only editor viewport sampling and a local, disposable terrain report.

const REPORT_DIRECTORY := "user://ember_terrain_diagnostics"
const MAX_RECORDED_FRAMES := 3600
const MAX_RECORDED_STEPS := 2000
const MAX_RECORDED_HOVERS := 2000

var recording := false
var _started_usec := 0
var _viewport_rid := RID()
var _projection_ref: WeakRef
var _warning_map_ref: WeakRef
var _metadata := {}
var _frames: Array[Dictionary] = []
var _strokes: Array[Dictionary] = []
var _hovers: Array[Dictionary] = []
var _current_stroke := -1
var _last_draw_usec := 0
var _last_release_usec := -1
var _truncated_frames := 0
var _truncated_steps := 0
var _truncated_hovers := 0
var _frame_write_index := 0
var _hover_write_index := 0
var _editor_process_usec := 0
var _dirty_status_usec := 0
var _dirty_status_count := 0


func start_brush_recording(metadata: Dictionary, viewport: Viewport, projection: EmberTerrainPilotProjection) -> bool:
	if recording or viewport == null or projection == null:
		return false
	_viewport_rid = viewport.get_viewport_rid()
	if not _viewport_rid.is_valid():
		return false
	_projection_ref = weakref(projection)
	var warning_map := projection.get_parent() as EmberMapLoader
	_warning_map_ref = weakref(warning_map) if warning_map != null else null
	if warning_map != null:
		warning_map.editor_warning_validation_count = 0
		warning_map.editor_warning_validation_usec = 0
		warning_map.editor_warning_validation_last_start_usec = 0
		warning_map.editor_warning_validation_last_duration_usec = 0
		warning_map.editor_warning_timing_enabled = true
	_metadata = metadata.duplicate(true)
	_metadata["baseline_terrain"] = projection.profile_snapshot()
	_metadata["viewport_pixels"] = [viewport.size.x, viewport.size.y]
	_started_usec = Time.get_ticks_usec()
	_last_draw_usec = 0
	_last_release_usec = -1
	_frames.clear()
	_strokes.clear()
	_hovers.clear()
	_current_stroke = -1
	_truncated_frames = 0
	_truncated_steps = 0
	_truncated_hovers = 0
	_frame_write_index = 0
	_hover_write_index = 0
	_editor_process_usec = 0
	_dirty_status_usec = 0
	_dirty_status_count = 0
	recording = true
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	RenderingServer.frame_post_draw.connect(_record_editor_frame)
	return true


func begin_brush_stroke(settings: Dictionary) -> void:
	if not recording:
		return
	var stroke := settings.duplicate(true)
	stroke["press_usec"] = Time.get_ticks_usec() - _started_usec
	stroke["release_usec"] = -1
	stroke["changed_columns"] = 0
	stroke["stages_usec"] = {}
	stroke["steps"] = []
	stroke["cancelled"] = false
	_strokes.append(stroke)
	_current_stroke = _strokes.size() - 1


func stage(name: String, duration_usec: int) -> void:
	if not recording or _current_stroke < 0:
		return
	var stages: Dictionary = _strokes[_current_stroke]["stages_usec"]
	stages[name] = int(stages.get(name, 0)) + maxi(0, duration_usec)


func record_editor_process(duration_usec: int) -> void:
	if recording:
		_editor_process_usec += maxi(0, duration_usec)


func record_dirty_status(duration_usec: int) -> void:
	if recording:
		_dirty_status_usec += maxi(0, duration_usec)
		_dirty_status_count += 1


func brush_step(kind: String, duration_usec: int, changed_columns: int, pending_tiles: int) -> void:
	if not recording or _current_stroke < 0:
		return
	var stroke: Dictionary = _strokes[_current_stroke]
	stroke["changed_columns"] = changed_columns
	var steps: Array = stroke["steps"]
	if steps.size() >= MAX_RECORDED_STEPS:
		_truncated_steps += 1
		return
	steps.append({"kind": kind, "at_usec": Time.get_ticks_usec() - _started_usec,
		"duration_usec": maxi(0, duration_usec), "changed_columns": changed_columns,
		"pending_tiles": pending_tiles})


func record_hover(sample: Dictionary) -> void:
	if not recording:
		return
	var entry := sample.duplicate(true)
	entry["at_usec"] = Time.get_ticks_usec() - _started_usec
	if _hovers.size() < MAX_RECORDED_HOVERS:
		_hovers.append(entry)
	else:
		_hovers[_hover_write_index] = entry
		_hover_write_index = (_hover_write_index + 1) % MAX_RECORDED_HOVERS
		_truncated_hovers += 1


func finish_brush_stroke(changed_columns: int, cancelled := false) -> void:
	if not recording or _current_stroke < 0:
		return
	var stroke: Dictionary = _strokes[_current_stroke]
	stroke["release_usec"] = Time.get_ticks_usec() - _started_usec
	_last_release_usec = int(stroke["release_usec"])
	stroke["changed_columns"] = changed_columns
	stroke["cancelled"] = cancelled
	_current_stroke = -1


func stop_brush_recording() -> Dictionary:
	if not recording:
		return {}
	if _current_stroke >= 0:
		finish_brush_stroke(int(_strokes[_current_stroke]["changed_columns"]), true)
	recording = false
	var warning_map := _warning_map_ref.get_ref() as EmberMapLoader if _warning_map_ref != null else null
	if is_instance_valid(warning_map):
		warning_map.editor_warning_timing_enabled = false
	_warning_map_ref = null
	if RenderingServer.frame_post_draw.is_connected(_record_editor_frame):
		RenderingServer.frame_post_draw.disconnect(_record_editor_frame)
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)
	var projection := _projection_ref.get_ref() as EmberTerrainPilotProjection if _projection_ref != null else null
	var intervals: Array[int] = []
	for frame in _frames:
		if int(frame["interval_usec"]) > 0:
			intervals.append(int(frame["interval_usec"]))
	intervals.sort()
	return {"schema": "ember-compact-brush-trace-v1", "context": "Godot editor 3D viewport",
		"started_usec": _started_usec, "duration_usec": Time.get_ticks_usec() - _started_usec,
		"metadata": _metadata.duplicate(true), "strokes": _strokes.duplicate(true),
		"hovers": _ordered_samples(_hovers, _hover_write_index, _truncated_hovers),
		"truncated_hovers": _truncated_hovers,
		"frames": _ordered_samples(_frames, _frame_write_index, _truncated_frames),
		"truncated_frames": _truncated_frames,
		"truncated_steps": _truncated_steps,
		"frame_interval_usec": {"count": intervals.size(),
			"median": _sorted_percentile(intervals, 0.5),
			"p95": _sorted_percentile(intervals, 0.95),
			"max": intervals.back() if not intervals.is_empty() else -1},
		"final_terrain": projection.profile_snapshot() if is_instance_valid(projection) else {},
		"limitations": "Editor frame intervals and per-step CPU wall times. Render GPU/CPU times cover the 3D viewport only; they do not include brush scripting or physics."}


func _record_editor_frame() -> void:
	if not recording:
		return
	var now := Time.get_ticks_usec()
	var interval := now - _last_draw_usec if _last_draw_usec > 0 else 0
	_last_draw_usec = now
	var projection := _projection_ref.get_ref() as EmberTerrainPilotProjection if _projection_ref != null else null
	var terrain := projection.profile_snapshot() if is_instance_valid(projection) else {}
	var warning_map := _warning_map_ref.get_ref() as EmberMapLoader if _warning_map_ref != null else null
	var frame := {"at_usec": now - _started_usec, "interval_usec": interval,
		"stroke": _current_stroke, "focused": DisplayServer.window_is_focused(),
		"editor_process_usec": _editor_process_usec,
		"dirty_status_usec": _dirty_status_usec,
		"dirty_status_count": _dirty_status_count,
		"warning_validation_count": warning_map.editor_warning_validation_count if is_instance_valid(warning_map) else 0,
		"warning_validation_usec": warning_map.editor_warning_validation_usec if is_instance_valid(warning_map) else 0,
		"warning_validation_last_start_usec": warning_map.editor_warning_validation_last_start_usec if is_instance_valid(warning_map) else 0,
		"warning_validation_last_duration_usec": warning_map.editor_warning_validation_last_duration_usec if is_instance_valid(warning_map) else 0,
		"since_last_release_usec": now - _started_usec - _last_release_usec if _last_release_usec >= 0 else -1,
		"pending_tiles": int(terrain.get("pending_tiles", -1)),
		"coalesced_tile_requests": int(terrain.get("coalesced_tile_requests", 0)),
		"deferred_repeat_builds": int(terrain.get("deferred_repeat_builds", 0)),
		"repeat_edit_builds": int(terrain.get("repeat_edit_builds", 0)),
		"max_pending_age_usec": int(terrain.get("max_pending_age_us", 0)),
		"built_tiles": int(terrain.get("built_tiles", -1)),
		"tile_builds": int(terrain.get("tile_builds", 0)),
		"mesh_usec": int(terrain.get("mesh_us", 0)),
		"geometry_usec": int(terrain.get("geometry_us", 0)),
		"collision_usec": int(terrain.get("collision_shape_us", 0)) + int(terrain.get("collision_attach_us", 0)),
		"process_usec": int(terrain.get("process_us", 0)),
		"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid),
		"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid),
		"visible_draw_calls": RenderingServer.viewport_get_render_info(_viewport_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	if _frames.size() < MAX_RECORDED_FRAMES:
		_frames.append(frame)
	else:
		_frames[_frame_write_index] = frame
		_frame_write_index = (_frame_write_index + 1) % MAX_RECORDED_FRAMES
		_truncated_frames += 1


func _ordered_samples(samples: Array[Dictionary], write_index: int, dropped: int) -> Array[Dictionary]:
	if dropped == 0:
		return samples.duplicate(true)
	var ordered: Array[Dictionary] = []
	for i in range(write_index, samples.size()): ordered.append(samples[i].duplicate(true))
	for i in write_index: ordered.append(samples[i].duplicate(true))
	return ordered


func _sorted_percentile(values: Array[int], percentile: float) -> int:
	return values[clampi(ceili(float(values.size()) * percentile) - 1, 0, values.size() - 1)] if not values.is_empty() else -1


static func capture(tree: SceneTree, viewport: Viewport, projection: EmberTerrainPilotProjection, samples := 90) -> Dictionary:
	if tree == null or viewport == null or projection == null or samples < 1:
		return {}
	var rid := viewport.get_viewport_rid()
	if not rid.is_valid():
		return {}
	var series := {"frame_interval_ms": [], "fps": [], "render_cpu_ms": [], "render_gpu_ms": [],
		"visible_draw_calls": [], "shadow_draw_calls": [], "visible_primitives": []}
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var previous := Time.get_ticks_usec()
	for i in samples:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		(series.frame_interval_ms as Array).append(float(now - previous) / 1000.0)
		previous = now
		(series.fps as Array).append(float(Performance.get_monitor(Performance.TIME_FPS)))
		(series.render_cpu_ms as Array).append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		(series.render_gpu_ms as Array).append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		(series.visible_draw_calls as Array).append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		(series.shadow_draw_calls as Array).append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		(series.visible_primitives as Array).append(RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
	RenderingServer.viewport_set_measure_render_time(rid, false)
	var measured := {}
	for key in series:
		var values: Array = series[key]
		values.sort()
		measured[key + "_median"] = values[int(values.size() / 2)]
		measured[key + "_p95"] = values[clampi(ceili(values.size() * 0.95) - 1, 0, values.size() - 1)]
	if not is_instance_valid(projection):
		return {}
	return {"schema": 1, "context": "editor_viewport_3d", "renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown")),
		"sampled_frames": samples, "viewport_pixels": [int(viewport.size.x), int(viewport.size.y)],
		"terrain": projection.profile_snapshot(), "viewport": measured,
		"gpu_timer_available": float(measured.get("render_gpu_ms_median", 0.0)) > 0.0,
		"limitations": "Terrain timings are CPU wall time; viewport render CPU/GPU times and draw calls do not identify individual cores or GPU units."}


static func save_report(report: Dictionary) -> String:
	if report.is_empty():
		return ""
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIRECTORY)) != OK:
		return ""
	var path := REPORT_DIRECTORY.path_join("terrain_%d_%d.json" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	return path
