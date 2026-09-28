extends SceneTree
## Isolated replay of the real 70-step WorldEditor level gesture.
## All surfaces are new in-memory copies. No authored Resource is opened/saved.

const Macro = preload("res://tools/prototypes/ember_macro_terrain_2_5d.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const SurfaceProjection = preload("res://scripts/ember_voxel_surface_projection.gd")
const TRACE := "res://tools/fixtures/world_edit_level_real_cells_v1.json"
const OUTPUT := "user://qa_macro_landscape_2_5d.json"
const COMPARISON := "user://qa_macro_landscape_2_5d_comparison.png"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, reason: String) -> void:
	if not value:
		_failures.append(reason)


func _digest(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func _stats(samples: Array[int]) -> Dictionary:
	if samples.is_empty():
		return {"median": -1, "p95": -1, "max": -1}
	var sorted := samples.duplicate()
	sorted.sort()
	return {"median": sorted[sorted.size() / 2], "p95": sorted[mini(sorted.size() - 1, ceili(sorted.size() * 0.95) - 1)], "max": sorted.back()}


func _surface(blocks: Vector2i) -> EmberVoxelModelResource:
	var result := EmberVoxelModelResource.new()
	result.model_id = "macro_landscape_disposable"
	result.display_name = "Disposable Macro Landscape benchmark"
	result.size_blocks = Vector3i(blocks.x, 1, blocks.y)
	result.voxels_per_block = 16
	result.height_voxels = 32
	result.palette = PackedColorArray([Color.TRANSPARENT, Color("#705447"), Color("#6b995e"), Color("#d1a55f"), Color("#777777")])
	result.physical = false # Physics intentionally deferred outside interactive stage.
	result.voxels.resize(result.grid_size().x * result.grid_size().y * result.grid_size().z)
	result.voxels.fill(1)
	return result


func _point(values: Array) -> Vector3i:
	return Vector3i(int(values[1]), int(values[2]), int(values[3]))


func _run() -> void:
	var file := FileAccess.open(TRACE, FileAccess.READ)
	if file == null:
		printerr("FAIL Macro benchmark: recorded trace is missing")
		quit(1)
		return
	var fixture: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var points: Array = fixture.get("points", [])
	_check(points.size() == 70 and str(fixture.get("tool", "")) == "level", "expected complete real 70-point level trace")
	if not _failures.is_empty():
		_finish({})
		return
	var reports: Array[Dictionary] = []
	var final_surface: EmberVoxelModelResource
	var final_macro: RefCounted
	# First pass warms GDScript, ArrayMesh creation and packed-array allocation.
	for pass_index in 4:
		var result: Dictionary = await _replay(points, pass_index == 0, pass_index == 3)
		if pass_index > 0:
			reports.append(result.report)
		if pass_index == 3:
			final_surface = result.surface
			final_macro = result.macro
		if not _failures.is_empty():
			break
	var report := {"scope": "Recorded 70 cells/timestamps through isolated 2.5D Macro, not live editor input", "display_server": DisplayServer.get_name(), "renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "not_measured"), "fps_limit": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode(), "fixture": {"blocks": [14, 15], "fine_density": 16, "macro_density": 8, "height_voxels": 32, "seed": 3817, "tool": "level", "radius_fine": roundi(float(fixture.radius_blocks) * 16.0), "level_top_y": int(_point(points[0]).y)}, "runs_after_warmup": reports}
	if final_surface != null and final_macro != null and _failures.is_empty():
		report["visual"] = await _visual_check(final_surface, final_macro, points)
	_finish(report)


func _replay(points: Array, warmup: bool, measure_projection: bool) -> Dictionary:
	var blocks := Vector2i(14, 15)
	var surface := _surface(blocks)
	var macro := Macro.new()
	macro.configure(blocks, surface.height_voxels, 3817)
	var projection: Node3D
	var holder: Node3D
	if measure_projection:
		holder = Node3D.new()
		root.add_child(holder)
		projection = SurfaceProjection.new()
		holder.add_child(projection)
		projection.configure(surface, 1.0, blocks, null, false)
		var initial_deadline := Time.get_ticks_msec() + 90000
		while not projection.is_projection_complete() and Time.get_ticks_msec() < initial_deadline:
			await process_frame
		_check(projection.is_projection_complete(), "initial fine projection did not settle before replay")
		for unused in 10:
			await process_frame
	var radius := 25
	var level := _point(points[0]).y
	var current_preview := {}
	var preview_nodes := {}
	var preview_root := Node3D.new()
	root.add_child(preview_root)
	var handler_delay: Array[int] = []
	var frame_intervals: Array[int] = []
	var brush_active_usec := 0
	var preview_active_usec := 0
	var controls_changed := 0
	var preview_rebuilds := 0
	var preview_triangles := 0
	var prev := _point(points[0])
	var first_due := Time.get_ticks_usec() + 100000
	var first_offset := int(points[0][0])
	var cursor := 0
	var last_frame := Time.get_ticks_usec()
	while cursor < points.size():
		var now := Time.get_ticks_usec()
		while cursor < points.size() and first_due + int(points[cursor][0]) - first_offset <= now:
			var next := _point(points[cursor])
			var due := first_due + int(points[cursor][0]) - first_offset
			handler_delay.append(maxi(0, Time.get_ticks_usec() - due))
			var begin := Time.get_ticks_usec()
			var change: Dictionary = macro.apply_level_segment(prev, next, level, radius)
			brush_active_usec += Time.get_ticks_usec() - begin
			controls_changed += int(change.changed_controls)
			prev = next
			begin = Time.get_ticks_usec()
			for chunk in macro.preview_target_chunks():
				var mesh: ArrayMesh = macro.preview_chunk(chunk)
				current_preview[chunk] = mesh
				if not preview_nodes.has(chunk):
					var visual := MeshInstance3D.new()
					preview_root.add_child(visual)
					preview_nodes[chunk] = visual
				(preview_nodes[chunk] as MeshInstance3D).mesh = mesh
				preview_rebuilds += 1
				# Arithmetic only: querying surface arrays here would read back GPU
				# data in Forward+ and contaminate the preview/input measurement.
				preview_triangles += 2 * mini(Macro.REGION, macro.width - chunk.x * Macro.REGION) * mini(Macro.REGION, macro.depth - chunk.y * Macro.REGION)
			preview_active_usec += Time.get_ticks_usec() - begin
			cursor += 1
			now = Time.get_ticks_usec()
		if cursor < points.size():
			await process_frame
			var frame_now := Time.get_ticks_usec()
			frame_intervals.append(frame_now - last_frame)
			last_frame = frame_now
	var pointer_up := Time.get_ticks_usec()
	var preview_mesh_count := current_preview.size()
	current_preview.clear()
	preview_root.free()
	# Explicitly defer bake until the next frame; one dirty region per frame.
	await process_frame
	var bake_started := Time.get_ticks_usec()
	var target_chunks: Array[Vector2i] = macro.dirty_target_chunks()
	macro.begin_bake(surface, target_chunks)
	while macro.pending_bake_chunks() > 0:
		macro.bake_next_chunk()
		if macro.pending_bake_chunks() > 0:
			await process_frame
	var bake_stats: Dictionary = macro.finish_bake()
	var bake_done := Time.get_ticks_usec()
	var output := {"input_events": cursor, "handler_delay_usec": _stats(handler_delay), "frame_interval_usec": _stats(frame_intervals), "macro_brush_active_usec": brush_active_usec, "macro_controls_changed_events": controls_changed, "macro_unique_dirty_controls": macro.dirty_count(), "preview_active_usec": preview_active_usec, "preview_scope": "ArrayMesh creation plus MeshInstance assignment; no live editor viewport", "preview_region_rebuilds": preview_rebuilds, "preview_triangles_submitted": preview_triangles, "preview_live_regions": preview_mesh_count, "pointer_up_to_bake_start_usec": bake_started - pointer_up, "bake_active_usec": int(bake_stats.cpu_usec), "bake_wall_usec": bake_done - bake_started, "bake_regions": target_chunks.size(), "bake_columns": int(bake_stats.columns), "bake_voxel_writes": int(bake_stats.voxel_writes), "bake_changed_voxels": int(bake_stats.changed_voxels), "read_only_halo_samples": int(bake_stats.halo_control_samples), "fine_sha256": _digest(surface.voxels)}
	if measure_projection:
		var projection_started := Time.get_ticks_usec()
		surface.notify_geometry_changed(macro.last_changed_indices)
		output["fine_notify_usec"] = Time.get_ticks_usec() - projection_started
		var deadline := Time.get_ticks_msec() + 90000
		while not projection.is_projection_complete() and Time.get_ticks_msec() < deadline:
			await process_frame
		output["fine_projection_complete"] = projection.is_projection_complete()
		output["fine_projection_wall_usec"] = Time.get_ticks_usec() - projection_started
		output["pointer_up_to_fine_mesh_ready_usec"] = Time.get_ticks_usec() - pointer_up if projection.is_projection_complete() else -1
		output["fine_visual_chunks"] = projection.rendered_chunk_count()
		_check(projection.is_projection_complete(), "isolated fine projection did not settle")
		projection.free()
		holder.free()
	_check(cursor == points.size(), "input sample dropped")
	if not warmup:
		print("MACRO_RUN brush_ms=", brush_active_usec / 1000.0, " preview_ms=", preview_active_usec / 1000.0, " input_p95_ms=", float(output.handler_delay_usec.p95) / 1000.0, " bake_cpu_ms=", float(bake_stats.cpu_usec) / 1000.0, " bake_wall_ms=", float(output.bake_wall_usec) / 1000.0)
	return {"report": output, "surface": surface, "macro": macro, "pointer_up_usec": pointer_up}


func _visual_check(surface: EmberVoxelModelResource, macro: RefCounted, points: Array) -> Dictionary:
	var full_bake := _surface(Vector2i(14, 15))
	macro.bake_chunks(full_bake, macro.all_chunks())
	var dirty_equals_full := full_bake.voxels == surface.voxels
	_check(dirty_equals_full, "real-trace dirty-region bake differs from full bake")
	var fine := _surface(Vector2i(14, 15))
	var baseline := fine.duplicate_model()
	var working := fine.voxels.duplicate()
	var previous := _point(points[0])
	var level := previous.y
	for point in points:
		var next := _point(point)
		var changes: Dictionary = Model.level_segment_changes(baseline, previous, next, level, 2, 25)
		for index in changes:
			working[int(index)] = int(changes[index].after)
		previous = next
	fine.voxels = working
	_check(ResourceSaver.save(surface, "user://qa_macro_baked_surface.res") == OK, "Macro baked copy was not saved for visual review")
	_check(ResourceSaver.save(fine, "user://qa_macro_reference_surface.res") == OK, "Fine reference copy was not saved for visual review")
	var image := Image.create(448, 240, false, Image.FORMAT_RGBA8)
	var size := surface.grid_size()
	var macro_values := surface.voxels
	var fine_values := fine.voxels
	var height_difference := 0
	var nonzero_difference := 0
	var affected_columns := 0
	var affected_height_difference := 0
	var max_height_difference := 0
	var waterline_disagreement := 0
	for z in size.z:
		for x in size.x:
			var coarse_top := _top(macro_values, size, x, z)
			var fine_top := _top(fine_values, size, x, z)
			height_difference += absi(coarse_top - fine_top)
			max_height_difference = maxi(max_height_difference, absi(coarse_top - fine_top))
			if coarse_top < 31 or fine_top < 31:
				affected_columns += 1
				affected_height_difference += absi(coarse_top - fine_top)
			if coarse_top != fine_top:
				nonzero_difference += 1
			if (coarse_top < 18) != (fine_top < 18):
				waterline_disagreement += 1
			image.set_pixel(x, z, _height_color(fine_top))
			image.set_pixel(x + size.x, z, _height_color(coarse_top))
	var comparison_path := ProjectSettings.globalize_path(COMPARISON)
	_check(image.save_png(COMPARISON) == OK, "comparison image could not be saved")
	var visual := {"comparison_png": comparison_path, "left": "current fine level brush", "right": "Macro refined fine result", "dirty_equals_full_bake": dirty_equals_full, "total_columns": size.x * size.z, "affected_columns": affected_columns, "mean_absolute_top_height_difference_voxels_all": float(height_difference) / float(size.x * size.z), "mean_absolute_top_height_difference_voxels_affected": float(affected_height_difference) / maxf(1.0, float(affected_columns)), "max_top_height_difference_voxels": max_height_difference, "different_top_height_columns": nonzero_difference, "waterline_18_disagreement_columns": waterline_disagreement, "reference_fine_sha256": _digest(fine.voxels), "reference_matches_recorded_sha256": _digest(fine.voxels) == "bd227df4444e308c40f6b58513a46b9871eca6a87b2d520bc598358350137276"}
	return visual


func _top(values: PackedByteArray, size: Vector3i, x: int, z: int) -> int:
	var base := x + z * size.x
	var stride := size.x * size.z
	for y in range(size.y - 1, -1, -1):
		if values[base + y * stride] != 0:
			return y
	return -1


func _height_color(top: int) -> Color:
	if top < 0:
		return Color("#284658")
	var intensity := float(top) / 32.0
	var color := Color("#c5ad78") if top < 9 else Color("#80a46d")
	if top % 2 == 1:
		color = color.darkened(0.12)
	return color.darkened(0.35 * (1.0 - intensity))


func _finish(report: Dictionary) -> void:
	if not report.is_empty():
		var output_path := OUTPUT.replace(".json", "_forward.json") if DisplayServer.get_name() != "headless" else OUTPUT
		var output := FileAccess.open(output_path, FileAccess.WRITE)
		if output == null:
			_failures.append("report could not be saved")
		else:
			output.store_string(JSON.stringify(report, "  "))
			output.close()
			print("MACRO_REPORT ", ProjectSettings.globalize_path(output_path))
	if _failures.is_empty():
		print("PASS isolated Macro Landscape benchmark and visual reference")
	else:
		for reason in _failures:
			printerr("FAIL Macro benchmark: ", reason)
	quit(0 if _failures.is_empty() else 1)
