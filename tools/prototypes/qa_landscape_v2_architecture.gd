extends SceneTree
## Isolated, non-production 16-sample Landscape replay. Uses only disposable resources.

const Heightfield = preload("res://tools/prototypes/ember_landscape_v2_heightfield.gd")
const GpuPreview = preload("res://tools/prototypes/ember_landscape_v2_gpu_preview.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const SurfaceProjection = preload("res://scripts/ember_voxel_surface_projection.gd")
const TRACE := "res://tools/fixtures/world_edit_level_real_cells_v1.json"
const OUTPUT := "user://qa_landscape_v2_architecture.json"
const COMPARISON := "user://qa_landscape_v2_architecture_comparison.png"
const GPU_PREVIEW := "user://qa_landscape_v2_gpu_preview.png"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	if not ok:
		failures.append(reason)


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


func _surface() -> EmberVoxelModelResource:
	var result := EmberVoxelModelResource.new()
	result.model_id = "landscape_v2_disposable"
	result.display_name = "Disposable Landscape v2 architecture benchmark"
	result.size_blocks = Vector3i(14, 1, 15)
	result.voxels_per_block = 16
	result.height_voxels = 32
	result.palette = PackedColorArray([Color.TRANSPARENT, Color("#705447"), Color("#6b995e"), Color("#d1a55f"), Color("#777777")])
	result.physical = false # Physics is intentionally deferred until after the gesture.
	result.voxels.resize(result.grid_size().x * result.grid_size().y * result.grid_size().z)
	result.voxels.fill(1)
	return result


func _point(values: Array) -> Vector3i:
	return Vector3i(int(values[1]), int(values[2]), int(values[3]))


func _run() -> void:
	var file := FileAccess.open(TRACE, FileAccess.READ)
	if file == null:
		failures.append("recorded 70-input trace missing")
		_finish({})
		return
	var fixture: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var points: Array = fixture.get("points", [])
	_check(points.size() == 70 and str(fixture.get("tool", "")) == "level", "fixture must contain 70 level inputs")
	if not failures.is_empty():
		_finish({})
		return
	var runs: Array[Dictionary] = []
	var final_surface: EmberVoxelModelResource
	var final_landscape: RefCounted
	# One warm-up, then three identically timed replays. Projection only on last pass.
	for pass_index in 4:
		var result: Dictionary = await _replay(points, pass_index == 3)
		if pass_index > 0:
			runs.append(result.report)
		if pass_index == 3:
			final_surface = result.surface
			final_landscape = result.landscape
		if not failures.is_empty():
			break
	var report := {"scope": "Recorded 70 cells/timestamps through isolated 16-sample Landscape GPU preview, not live Godot editor input", "fixture": {"blocks": [14, 15], "samples_per_block": 16, "height_voxels": 32, "radius_fine": 25, "tool": "level", "inputs": points.size()}, "display_server": DisplayServer.get_name(), "renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"), "fps_limit": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode(), "warmup_runs": 1, "runs_after_warmup": runs}
	if final_surface != null and final_landscape != null and failures.is_empty():
		report["comparison"] = _compare_reference(points, final_surface, final_landscape)
		report["override_regression"] = _check_overrides(final_surface, final_landscape)
	_finish(report)


func _replay(points: Array, measure_projection: bool) -> Dictionary:
	var surface := _surface()
	var landscape := Heightfield.new()
	landscape.configure(Vector2i(14, 15), 32)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(7.0, 24.0, 12.0)
	camera.look_at(Vector3(7.0, 1.0, 7.0))
	camera.current = true
	var preview := GpuPreview.new()
	viewport.add_child(preview)
	preview.configure(landscape)
	var initial_meshes := preview.mesh_creations
	var holder: Node3D
	var projection: Node3D
	if measure_projection:
		holder = Node3D.new()
		root.add_child(holder)
		projection = SurfaceProjection.new()
		holder.add_child(projection)
		projection.configure(surface, 1.0, Vector2i(14, 15), null, false)
		var deadline := Time.get_ticks_msec() + 90000
		while not projection.is_projection_complete() and Time.get_ticks_msec() < deadline:
			await process_frame
		_check(projection.is_projection_complete(), "initial fine projection timed out")
		for unused in 10:
			await process_frame
	var first_offset := int(points[0][0])
	var first_due := Time.get_ticks_usec() + 100000
	var cursor := 0
	var previous := _point(points[0])
	var target_top := previous.y
	var delays: Array[int] = []
	var intervals: Array[int] = []
	var brush_cpu := 0
	var preview_cpu := 0
	var changed_events := 0
	var preview_uploads := 0
	var preview_pixels := 0
	var frame_time := Time.get_ticks_usec()
	while cursor < points.size():
		var now := Time.get_ticks_usec()
		while cursor < points.size() and first_due + int(points[cursor][0]) - first_offset <= now:
			var due := first_due + int(points[cursor][0]) - first_offset
			delays.append(maxi(0, Time.get_ticks_usec() - due))
			var next := _point(points[cursor])
			var brush: Dictionary = landscape.apply_level_segment(previous, next, target_top, 25)
			brush_cpu += int(brush.cpu_usec)
			changed_events += int(brush.changed_columns)
			previous = next
			var updated: Dictionary = preview.update_regions(landscape.sorted_regions(landscape.last_input_regions), landscape.last_changed_samples)
			preview_cpu += int(updated.cpu_usec)
			preview_uploads += int(updated.regions)
			preview_pixels += int(updated.pixels)
			cursor += 1
			now = Time.get_ticks_usec()
		if cursor < points.size():
			await process_frame
			var next_frame := Time.get_ticks_usec()
			intervals.append(next_frame - frame_time)
			frame_time = next_frame
	var pointer_up := Time.get_ticks_usec()
	_check(preview.mesh_creations == initial_meshes, "preview created a mesh during gesture")
	var preview_meshes := preview.mesh_creations
	# A real editor would keep rendering the preview until exact projection catches up.
	await process_frame
	var bake_started := Time.get_ticks_usec()
	var regions: Array[Vector2i] = landscape.sorted_regions(landscape.dirty_regions)
	landscape.begin_bake()
	var bake_cpu := 0
	var bake_columns := 0
	var bake_writes := 0
	for i in regions.size():
		var baked: Dictionary = landscape.bake_region(surface, regions[i])
		bake_cpu += int(baked.cpu_usec)
		bake_columns += int(baked.columns)
		bake_writes += int(baked.writes)
		if i + 1 < regions.size():
			await process_frame
	var bake_done := Time.get_ticks_usec()
	var result := {"input_events": cursor, "input_delay_usec": _stats(delays), "frame_interval_usec": _stats(intervals), "brush_cpu_usec": brush_cpu, "changed_height_events": changed_events, "unique_dirty_regions": regions.size(), "preview_upload_cpu_usec": preview_cpu, "preview_texture_uploads": preview_uploads, "preview_uploaded_pixels": preview_pixels, "preview_mesh_creations_before_and_after_gesture": [initial_meshes, preview_meshes], "pointer_up_to_bake_start_usec": bake_started - pointer_up, "bake_cpu_usec": bake_cpu, "bake_wall_usec": bake_done - bake_started, "bake_columns": bake_columns, "bake_voxel_writes": bake_writes, "bake_changed_voxels": landscape.last_changed_indices.size(), "pointer_up_to_bake_done_usec": bake_done - pointer_up, "fine_sha256": _digest(surface.voxels)}
	if measure_projection:
		var notification_started := Time.get_ticks_usec()
		surface.notify_geometry_changed(landscape.last_changed_indices)
		result["fine_notify_usec"] = Time.get_ticks_usec() - notification_started
		var projection_deadline := Time.get_ticks_msec() + 90000
		while not projection.is_projection_complete() and Time.get_ticks_msec() < projection_deadline:
			await process_frame
		result["fine_projection_complete"] = projection.is_projection_complete()
		result["fine_projection_wall_usec"] = Time.get_ticks_usec() - notification_started
		result["pointer_up_to_fine_mesh_ready_usec"] = Time.get_ticks_usec() - pointer_up if projection.is_projection_complete() else -1
		result["fine_visual_chunks"] = projection.rendered_chunk_count()
		_check(projection.is_projection_complete(), "fine projection did not finish")
		projection.free()
		holder.free()
	if measure_projection and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var captured := viewport.get_texture().get_image()
		result["gpu_preview_png"] = ProjectSettings.globalize_path(GPU_PREVIEW)
		_check(captured.save_png(GPU_PREVIEW) == OK, "GPU preview screenshot not saved")
	viewport.free()
	_check(cursor == points.size(), "input event lost")
	print("LANDSCAPE_V2_RUN brush_ms=", brush_cpu / 1000.0, " gpu_upload_ms=", preview_cpu / 1000.0, " input_p95_ms=", float(result.input_delay_usec.p95) / 1000.0, " bake_cpu_ms=", bake_cpu / 1000.0, " bake_wall_ms=", float(result.bake_wall_usec) / 1000.0)
	return {"report": result, "surface": surface, "landscape": landscape}


func _compare_reference(points: Array, derived: EmberVoxelModelResource, landscape: RefCounted) -> Dictionary:
	var fine := _surface()
	var baseline := fine.duplicate_model()
	var values := fine.voxels.duplicate()
	var previous := _point(points[0])
	var target_top := previous.y
	for point in points:
		var next := _point(point)
		var changes: Dictionary = Model.level_segment_changes(baseline, previous, next, target_top, 2, 25)
		for index in changes:
			values[int(index)] = int(changes[index].after)
		previous = next
	fine.voxels = values
	var exact := derived.voxels == fine.voxels
	_check(exact, "Landscape bake differs from existing level brush")
	var full := _surface()
	landscape.begin_bake()
	for region in landscape.all_regions():
		landscape.bake_region(full, region)
	var dirty_equals_full := full.voxels == derived.voxels
	_check(dirty_equals_full, "dirty region bake differs from full bake")
	var size: Vector3i = fine.grid_size()
	var image := Image.create(size.x * 2, size.z, false, Image.FORMAT_RGBA8)
	var top_different := 0
	for z in size.z:
		for x in size.x:
			var reference_top := _top(fine.voxels, size, x, z)
			var derived_top := _top(derived.voxels, size, x, z)
			if reference_top != derived_top:
				top_different += 1
			image.set_pixel(x, z, _height_color(reference_top))
			image.set_pixel(x + size.x, z, _height_color(derived_top))
	_check(image.save_png(COMPARISON) == OK, "comparison PNG not saved")
	return {"exact_voxel_bytes": exact, "reference_sha256": _digest(fine.voxels), "derived_sha256": _digest(derived.voxels), "dirty_equals_full": dirty_equals_full, "top_height_different_columns": top_different, "comparison_png": ProjectSettings.globalize_path(COMPARISON), "left": "existing fine level brush", "right": "Landscape v2 exact bake", "note": "Flat solid-column fixture; does not prove parity for caves, holes, shoreline or multi-material authored maps"}


func _check_overrides(reference: EmberVoxelModelResource, landscape: RefCounted) -> Dictionary:
	var modified := reference.duplicate_model()
	var added := Vector3i(63, 27, 64)
	var removed := Vector3i(64, 10, 64)
	var replaced := Vector3i(65, 9, 64)
	landscape.set_detail_override(added, 4)
	landscape.set_detail_override(removed, 0)
	landscape.set_detail_override(replaced, 3)
	landscape.begin_bake()
	for region in landscape.sorted_regions(landscape.dirty_regions):
		landscape.bake_region(modified, region)
	var before := [_voxel(modified, added), _voxel(modified, removed), _voxel(modified, replaced)]
	# Re-bake both sides of a region seam, then change base height strongly.
	landscape.begin_bake()
	landscape.bake_region(modified, Vector2i(0, 1))
	landscape.bake_region(modified, Vector2i(1, 1))
	var after_neighbor := [_voxel(modified, added), _voxel(modified, removed), _voxel(modified, replaced)]
	landscape.apply_level_segment(Vector3i(63, 9, 64), Vector3i(65, 9, 64), 9, 2)
	landscape.begin_bake()
	landscape.bake_region(modified, Vector2i(0, 1))
	landscape.bake_region(modified, Vector2i(1, 1))
	var after_base_change := [_voxel(modified, added), _voxel(modified, removed), _voxel(modified, replaced)]
	var preserved := before == [4, 0, 3] and after_neighbor == before and after_base_change == before
	_check(preserved, "add/remove/replace overrides lost across region seam or large height change")
	return {"add_remove_replace_preserved": preserved, "after_initial_bake": before, "after_neighbor_rebake": after_neighbor, "after_strong_base_change": after_base_change, "policy": "absolute world-space voxel overrides win over generated base; moving-with-surface detail requires separate RFC decision"}


func _voxel(surface: EmberVoxelModelResource, cell: Vector3i) -> int:
	var size := surface.grid_size()
	return surface.voxels[cell.x + cell.z * size.x + cell.y * size.x * size.z]


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
	var color := Color("#c5ad78") if top < 9 else Color("#80a46d")
	if top % 2 == 1:
		color = color.darkened(0.12)
	return color.darkened(0.35 * (1.0 - float(top) / 32.0))


func _finish(report: Dictionary) -> void:
	if not report.is_empty():
		var output := FileAccess.open(OUTPUT, FileAccess.WRITE)
		if output == null:
			failures.append("report could not be saved")
		else:
			output.store_string(JSON.stringify(report, "  "))
			output.close()
			print("LANDSCAPE_V2_REPORT ", ProjectSettings.globalize_path(OUTPUT))
	if failures.is_empty():
		print("PASS isolated Landscape v2 architecture proof")
	else:
		for failure in failures:
			printerr("FAIL Landscape v2 architecture proof: ", failure)
	quit(0 if failures.is_empty() else 1)
