extends SceneTree
const Trace = preload("res://addons/ember_import/ember_world_edit_trace.gd")
const SurfaceProjectionScript = preload("res://scripts/ember_voxel_surface_projection.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var trace := Trace.new()
	trace.start()
	var started := Time.get_ticks_usec()
	trace.begin_stroke({"tool":"paint","input_source":"main_3d_forward_input"},started,Vector2(12,34),Vector3i(1,2,3))
	trace.queue_sample(3,3)
	trace.job_wait(120)
	trace.stage("brush_evaluation",50)
	trace.stage("brush_evaluation",30)
	trace.write_event(7)
	trace.visual_dirty(Vector2i(1,2),1)
	OS.delay_msec(2)
	trace.visual_dirty(Vector2i(1,2),1)
	trace.frame(0,false,1,0)
	trace.visual_rebuilt(Vector2i(1,2),"native","",70,0,10,0)
	trace.commit(5)
	trace.frame(0,false,0,0)
	var result := trace.stop()
	var stroke: Dictionary = result.strokes[0]
	var rebuilt: Dictionary = result.events.filter(func(event): return event.kind == "visual_rebuilt")[0]
	if stroke.input.size() != 1 or stroke.queued_samples != 3 or stroke.queue_wait_usec != 120 or stroke.stages_usec.brush_evaluation != 80 or stroke.changed_unique_voxels != 5 or stroke.changed_write_events != 7 or stroke.queue_drained_usec < stroke.committed_usec or rebuilt.requests_since_rebuild != 2 or rebuilt.first_dirty_age_usec < rebuilt.latest_request_age_usec or not result.pending_visual_at_stop.is_empty():
		printerr("FAIL world edit trace: ",result)
		quit(1)
		return
	var surface := EmberVoxelModelResource.new()
	surface.voxels_per_block = 16
	surface.size_blocks = Vector3i.ONE
	surface.height_voxels = 16
	surface.palette = PackedColorArray([Color.TRANSPARENT,Color.RED,Color.BLUE])
	surface.physical = false
	surface.voxels.resize(16*16*16)
	surface.voxels.fill(1)
	var projection := SurfaceProjectionScript.new()
	root.add_child(projection)
	projection.configure(surface,1.0,Vector2i.ONE,null)
	while projection.drain_next_chunk(): pass
	trace.start()
	trace.begin_stroke({"tool":"paint"},Time.get_ticks_usec(),Vector2.ZERO,Vector3i.ZERO)
	projection.editor_diagnostic_sink = trace
	surface.voxels[0] = 2
	surface.notify_geometry_changed(PackedInt32Array([0]))
	if projection.pending_chunk_count() < 1:
		printerr("FAIL world edit trace: shared projection did not queue dirty chunk")
		quit(1)
		return
	projection.drain_next_chunk()
	var projection_result := trace.stop()
	var rebuild_events: Array = projection_result.events.filter(func(event): return event.kind == "visual_rebuilt")
	if rebuild_events.size() != 1 or projection_result.strokes[0].visual_unique_chunks != 1 or projection_result.strokes[0].visual_rebuild_count != 1 or rebuild_events[0].first_dirty_age_usec < rebuild_events[0].latest_request_age_usec:
		printerr("FAIL world edit trace: shared projection hook: ",projection_result)
		quit(1)
		return
	projection.editor_diagnostic_sink = null
	projection.free()
	print("PASS world edit trace: opt-in input, exclusive stages, first-dirty age, settle and actual change count")
	quit()
