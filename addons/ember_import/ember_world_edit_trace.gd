@tool
extends RefCounted
## Opt-in, editor-only trace. Samples stay in memory until recording is stopped.
## A post-draw timestamp is a submission proxy, not proof of visible pixels.

var recording := false
var started_usec := 0
var metadata := {}
var strokes: Array[Dictionary] = []
var events: Array[Dictionary] = []
var frame_intervals_usec: Array[int] = []
var _last_frame_usec := 0
var _current := -1
var _pending_visual := {}
var _pending_physics := {}
var _last_assignment_usec := 0
var _first_postdraw_after_assignment_usec := 0


func start() -> void:
	if recording: return
	recording = true
	started_usec = Time.get_ticks_usec()
	strokes.clear()
	events.clear()
	frame_intervals_usec.clear()
	_pending_visual.clear()
	_pending_physics.clear()
	_current = -1
	_last_frame_usec = 0
	_last_assignment_usec = 0
	_first_postdraw_after_assignment_usec = 0
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)


func stop() -> Dictionary:
	if not recording: return {}
	recording = false
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	var result := snapshot()
	result["ended_usec"] = Time.get_ticks_usec()
	return result


func begin_stroke(settings: Dictionary, input_usec: int, position: Vector2, cell: Vector3i, scheduled_usec := 0) -> void:
	if not recording: return
	var stroke := settings.duplicate(true)
	stroke["started_usec"] = input_usec
	stroke["input"] = []
	stroke["stages_usec"] = {}
	stroke["queue_wait_usec"] = 0
	stroke["max_queue_wait_usec"] = 0
	stroke["jobs_processed"] = 0
	stroke["steps_processed"] = 0
	stroke["changed_unique_voxels"] = 0
	stroke["changed_write_events"] = 0
	stroke["released_usec"] = 0
	stroke["committed_usec"] = 0
	stroke["queue_drained_usec"] = 0
	stroke["postdraw_settled_usec"] = 0
	stroke["frame_intervals_usec"] = []
	stroke["overlap_with_previous"] = not strokes.is_empty() and int(strokes.back().queue_drained_usec) == 0
	stroke["queue_peak"] = 0
	stroke["visual_chunks"] = {}
	stroke["physics_chunks"] = {}
	strokes.append(stroke)
	_current = strokes.size()-1
	input("press",input_usec,position,cell,scheduled_usec)


func input(kind: String, at_usec: int, position: Vector2, cell: Vector3i, scheduled_usec := 0) -> void:
	if not recording or _current < 0: return
	var stroke: Dictionary = strokes[_current]
	stroke.input.append({"kind":kind,"at_usec":at_usec,"scheduled_usec":scheduled_usec,"handler_delay_usec":maxi(0,at_usec-scheduled_usec) if scheduled_usec > 0 else -1,"screen":[position.x,position.y],"cell":[cell.x,cell.y,cell.z]})
	if kind == "release": stroke.released_usec = at_usec


func queue_sample(count: int, queue_size: int) -> void:
	if not recording or _current < 0: return
	var stroke: Dictionary = strokes[_current]
	stroke["queued_samples"] = int(stroke.get("queued_samples",0))+count
	stroke.queue_peak = maxi(int(stroke.queue_peak),queue_size)


func stage(name: String, duration_usec: int) -> void:
	if not recording or _current < 0: return
	var totals: Dictionary = strokes[_current].stages_usec
	totals[name] = int(totals.get(name,0))+duration_usec


func job_wait(duration_usec: int) -> void:
	if recording and _current >= 0:
		var stroke: Dictionary = strokes[_current]
		stroke.queue_wait_usec += maxi(0,duration_usec)
		stroke.max_queue_wait_usec = maxi(int(stroke.max_queue_wait_usec),duration_usec)
		stroke.jobs_processed += 1


func job_step() -> void:
	if recording and _current >= 0:
		strokes[_current].steps_processed += 1


func write_event(count: int) -> void:
	if recording and _current >= 0:
		strokes[_current].changed_write_events += count


func commit(changed_count: int) -> void:
	if not recording or _current < 0: return
	strokes[_current].changed_unique_voxels = changed_count
	strokes[_current].committed_usec = Time.get_ticks_usec()
	events.append({"kind":"commit","stroke":_current,"at_usec":strokes[_current].committed_usec,"changed":changed_count})


func cancel() -> void:
	if not recording or _current < 0 or strokes[_current].committed_usec > 0: return
	strokes[_current]["cancelled_usec"] = Time.get_ticks_usec()
	strokes[_current]["queue_drained_usec"] = strokes[_current].cancelled_usec
	events.append({"kind":"cancel","stroke":_current,"at_usec":strokes[_current].cancelled_usec})


func visual_dirty(chunk: Vector2i, pending_count: int) -> void:
	if not recording: return
	var key := _key(chunk)
	var now := Time.get_ticks_usec()
	if not _pending_visual.has(key): _pending_visual[key] = {"first_usec":now,"last_usec":now,"requests":0}
	_pending_visual[key].last_usec = now
	_pending_visual[key].requests += 1
	if _current >= 0:
		var chunks: Dictionary = strokes[_current].visual_chunks
		chunks[key] = int(chunks.get(key,0))+1


func physics_dirty(chunk: Vector2i, pending_count: int) -> void:
	if not recording: return
	var key := _key(chunk)
	if not _pending_physics.has(key): _pending_physics[key] = Time.get_ticks_usec()
	if _current >= 0:
		var chunks: Dictionary = strokes[_current].physics_chunks
		chunks[key] = int(chunks.get(key,0))+1


func visual_rebuilt(chunk: Vector2i, backend: String, reason: String, adapter_usec: int, stock_usec: int, assignment_usec: int, pending_count: int) -> void:
	if not recording: return
	var key := _key(chunk)
	var now := Time.get_ticks_usec()
	var pending: Dictionary = _pending_visual.get(key,{})
	events.append({"kind":"visual_rebuilt","stroke":_current,"at_usec":now,"chunk":key,"backend":backend,"fallback_reason":reason,"adapter_call_usec":adapter_usec,"stock_build_usec":stock_usec,"assignment_usec":assignment_usec,"tracked_dirty":not pending.is_empty(),"first_dirty_age_usec":now-int(pending.first_usec) if not pending.is_empty() else -1,"latest_request_age_usec":now-int(pending.last_usec) if not pending.is_empty() else -1,"requests_since_rebuild":int(pending.get("requests",0)),"pending":pending_count})
	_pending_visual.erase(key)
	_last_assignment_usec = now
	_first_postdraw_after_assignment_usec = 0


func physics_rebuilt(chunk: Vector2i, duration_usec: int, pending_count: int) -> void:
	if not recording: return
	var key := _key(chunk)
	var now := Time.get_ticks_usec()
	events.append({"kind":"physics_rebuilt","stroke":_current,"at_usec":now,"chunk":key,"duration_usec":duration_usec,"dirty_age_usec":now-int(_pending_physics[key]) if _pending_physics.has(key) else -1,"pending":pending_count})
	_pending_physics.erase(key)


func frame(queue_size: int, has_job: bool, visual_pending: int, physics_pending: int, oldest_brush_input_usec := 0, visual_live := -1, physics_live := -1) -> void:
	if not recording or _current < 0: return
	var now := Time.get_ticks_usec()
	var oldest_visual := now
	for value in _pending_visual.values(): oldest_visual = mini(oldest_visual,int(value.first_usec))
	var oldest_physics := now
	for value in _pending_physics.values(): oldest_physics = mini(oldest_physics,int(value))
	var unknown_age := visual_pending > _pending_visual.size() or physics_pending > _pending_physics.size()
	var oldest_unupdated_age := -1 if unknown_age else now-mini(oldest_visual,oldest_physics)
	if strokes[_current].queue_drained_usec == 0 or not _pending_visual.is_empty():
		events.append({"kind":"queue_frame","at_usec":now,"stroke":_current,"brush_queue":queue_size,"brush_job":has_job,"oldest_brush_input_age_usec":now-oldest_brush_input_usec if oldest_brush_input_usec > 0 else 0,"visual_live":visual_live,"physics_live":physics_live,"visual_pending":visual_pending,"physics_pending":physics_pending,"oldest_visual_dirty_age_usec":now-oldest_visual if not _pending_visual.is_empty() else -1 if visual_pending > 0 else 0,"oldest_physics_dirty_age_usec":now-oldest_physics if not _pending_physics.is_empty() else -1 if physics_pending > 0 else 0,"oldest_unupdated_change_age_usec":oldest_unupdated_age})
	if _current >= 0 and strokes[_current].committed_usec > 0 and visual_pending == 0 and physics_pending == 0 and _pending_visual.is_empty() and strokes[_current].queue_drained_usec == 0:
		strokes[_current].queue_drained_usec = now


func snapshot() -> Dictionary:
	var sorted := frame_intervals_usec.duplicate()
	sorted.sort()
	var result_strokes := strokes.duplicate(true)
	for stroke_index in result_strokes.size():
		var stroke: Dictionary = result_strokes[stroke_index]
		var samples: Array = stroke.frame_intervals_usec
		samples.sort()
		stroke.frame_post_draw_intervals_usec = {"count":samples.size(),"median":_percentile(samples,0.5),"p95":_percentile(samples,0.95),"max":samples.back() if not samples.is_empty() else -1}
		stroke.erase("frame_intervals_usec")
		stroke.duration_usec = int(stroke.released_usec)-int(stroke.started_usec) if stroke.released_usec > 0 else -1
		stroke.release_to_queue_drain_usec = int(stroke.queue_drained_usec)-int(stroke.released_usec) if stroke.queue_drained_usec > 0 and stroke.released_usec > 0 else -1
		stroke.release_to_postdraw_proxy_usec = int(stroke.postdraw_settled_usec)-int(stroke.released_usec) if stroke.postdraw_settled_usec > 0 and stroke.released_usec > 0 else -1
		stroke.visual_unique_chunks = stroke.visual_chunks.size()
		stroke.physics_unique_chunks = stroke.physics_chunks.size()
		stroke.visual_rebuilds_by_chunk = {}
		stroke.max_visual_pending = 0
		stroke.max_oldest_unupdated_change_age_usec = 0
		stroke.unknown_oldest_age_samples = 0
		stroke.max_brush_queue = 0
		stroke.max_oldest_brush_input_age_usec = 0
		var brush_ages: Array[int] = []
		for event in events:
			if int(event.get("stroke",-1)) != stroke_index: continue
			if event.kind == "visual_rebuilt":
				stroke.visual_rebuilds_by_chunk[event.chunk] = int(stroke.visual_rebuilds_by_chunk.get(event.chunk,0))+1
			elif event.kind == "queue_frame":
				if int(event.brush_queue) > 0 or bool(event.brush_job):
					brush_ages.append(int(event.oldest_brush_input_age_usec))
				stroke.max_visual_pending = maxi(int(stroke.max_visual_pending),int(event.visual_pending))
				stroke.max_oldest_unupdated_change_age_usec = maxi(int(stroke.max_oldest_unupdated_change_age_usec),int(event.oldest_unupdated_change_age_usec))
				if int(event.oldest_unupdated_change_age_usec) < 0: stroke.unknown_oldest_age_samples += 1
				stroke.max_brush_queue = maxi(int(stroke.max_brush_queue),int(event.brush_queue))
				stroke.max_oldest_brush_input_age_usec = maxi(int(stroke.max_oldest_brush_input_age_usec),int(event.oldest_brush_input_age_usec))
		brush_ages.sort()
		stroke.brush_input_age_usec = {"count":brush_ages.size(),"median":_percentile(brush_ages,0.5),"p95":_percentile(brush_ages,0.95),"max":brush_ages.back() if not brush_ages.is_empty() else -1}
		stroke.visual_rebuild_count = 0
		for count in stroke.visual_rebuilds_by_chunk.values(): stroke.visual_rebuild_count += int(count)
	return {"schema":"ember-world-edit-trace-v1","scope":"main Godot 3D editor tab; input routed through EmberWorldEditor","started_usec":started_usec,"metadata":metadata.duplicate(true),"strokes":result_strokes,"events":events.duplicate(true),"frame_post_draw_intervals_usec":{"count":sorted.size(),"median":_percentile(sorted,0.5),"p95":_percentile(sorted,0.95),"max":sorted.back() if not sorted.is_empty() else -1},"pending_visual_at_stop":_pending_visual.duplicate(true),"pending_physics_at_stop":_pending_physics.duplicate(true),"visibility_note":"First frame_post_draw after mesh assignment is only a render submission proxy, not a measured pixel-visible latency.","timing_note":"Stage times are exclusive call-site intervals. Adapter call includes internal preparation/composition, not pure native meshing. Queue and frame waiting are wall time, not brush compute."}


func _on_frame_post_draw() -> void:
	if not recording: return
	var now := Time.get_ticks_usec()
	if _current < 0:
		_last_frame_usec = now
		return
	if _last_frame_usec > 0:
		if strokes[_current].queue_drained_usec == 0: frame_intervals_usec.append(now-_last_frame_usec)
		if _current >= 0 and strokes[_current].queue_drained_usec == 0: strokes[_current].frame_intervals_usec.append(now-_last_frame_usec)
	_last_frame_usec = now
	if _current >= 0 and not strokes[_current].has("cancelled_usec") and strokes[_current].queue_drained_usec > 0 and strokes[_current].postdraw_settled_usec == 0:
		strokes[_current].postdraw_settled_usec = now
	if _last_assignment_usec > 0 and _first_postdraw_after_assignment_usec == 0:
		_first_postdraw_after_assignment_usec = now
		events.append({"kind":"first_postdraw_after_assignment","at_usec":now,"assignment_to_postdraw_usec":now-_last_assignment_usec})


func _percentile(sorted: Array, percentile: float) -> int:
	if sorted.is_empty(): return -1
	return sorted[clampi(ceili(float(sorted.size())*percentile)-1,0,sorted.size()-1)]


func _key(chunk: Vector2i) -> String:
	return "%d,%d" % [chunk.x,chunk.y]
