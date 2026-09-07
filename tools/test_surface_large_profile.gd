extends SceneTree
## Reproducible performance gate for the current dense Surface contract.
## It reads the authored sandbox Surface, but writes only disposable user:// data.

const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const NativePreview = preload("res://addons/ember_import/ember_voxel_tools_preview.gd")
const PROFILE_SOURCE := "res://content/world_surfaces/agent_sandbox_surface.tres"
const PROFILE_SAVE := "user://ember_large_surface_profile.tres"
const PROFILE_JSON := "user://ember_large_surface_profile.json"
const PROFILE_IMAGE := "user://ember_large_surface_profile.png"
const SAMPLE_COUNT := 32768

var _metrics := {}
var _errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_metrics["profile_format"] = 1
	_metrics["engine"] = Engine.get_version_info().get("string", "unknown")
	_metrics["platform"] = OS.get_name()
	_metrics["display_server"] = DisplayServer.get_name()
	var resource := _measure_load()
	if resource == null:
		_finish()
		return
	var size := resource.grid_size()
	_metrics["surface"] = {
		"path": PROFILE_SOURCE,
		"file_bytes": _source_file_size(),
		"grid": [size.x, size.y, size.z],
		"dense_voxels": resource.voxels.size(),
		"dense_bytes": (
			resource.voxels.size()
			+ resource.transparency.size()
			+ resource.surface_fill_levels.size() * 4
			+ resource.surface_fill_materials.size()
			+ resource.surface_fill_palette.size()
		),
	}
	_metrics["native_preview_available"] = NativePreview.available()
	_metrics["occupied_voxels"] = resource.voxels.size() - resource.voxels.count(0)
	_metrics["palette_size"] = resource.palette.size()
	var started := Time.get_ticks_usec()
	var voxel_snapshot := resource.voxels.duplicate()
	var transparency_snapshot := resource.transparency.duplicate()
	_metrics["dense_snapshot_ms"] = _elapsed_ms(started)
	_check(voxel_snapshot == resource.voxels and transparency_snapshot == resource.transparency, "dense snapshot differs")
	started = Time.get_ticks_usec()
	var measured_heights := Model.column_heights(
		resource.voxels, size, resource.palette.size() - 1
	)
	_metrics["column_heights_ms"] = _elapsed_ms(started)
	_check(measured_heights.size() == size.x * size.z, "heightfield size differs")
	started = Time.get_ticks_usec()
	var reference_heights := _column_heights_reference(resource.voxels, size)
	_metrics["reference_column_heights_ms"] = _elapsed_ms(started)
	_check(reference_heights == measured_heights, "optimized heightfield differs")
	root.size = Vector2i(1280, 720)
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null, undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	started = Time.get_ticks_usec()
	workspace.open_surface(resource, PROFILE_SAVE)
	_metrics["open_sync_ms"] = _elapsed_ms(started)
	_metrics["opening_queued_chunks"] = (workspace.get("_pending_preview_chunks") as Dictionary).size()

	var chunk_times: Array[float] = []
	for sample in 12:
		started = Time.get_ticks_usec()
		workspace.call("_rebuild_chunk", Vector2i(sample, 0), false)
		chunk_times.append(_elapsed_ms(started))
	_metrics["chunk_rebuild_ms"] = _distribution(chunk_times)
	var pending_before := (workspace.get("_pending_preview_chunks") as Dictionary).size()
	started = Time.get_ticks_usec()
	workspace.call("_drain_preview_chunk")
	_metrics["chunk_drain_batch_ms"] = _elapsed_ms(started)
	_metrics["chunk_drain_batch_count"] = pending_before - (workspace.get("_pending_preview_chunks") as Dictionary).size()
	var draft_times: Array[float] = []
	for sample in 12:
		started = Time.get_ticks_usec()
		workspace.call("_rebuild_chunk", Vector2i(sample % 12, sample / 12), true)
		draft_times.append(_elapsed_ms(started))
	_metrics["draft_chunk_rebuild_ms"] = _distribution(draft_times)
	var native := NativePreview.new()
	var native_times: Array[float] = []
	var native_successes := 0
	var opaque := StandardMaterial3D.new()
	var transparent := StandardMaterial3D.new()
	for sample in 12:
		var region_min := Vector3i(sample * Workspace.PREVIEW_CHUNK_SIZE, 0, 0)
		started = Time.get_ticks_usec()
		var projection := native.build_region(
			resource.voxels,
			size,
			resource.palette,
			resource.transparency,
			region_min,
			Vector3i(Workspace.PREVIEW_CHUNK_SIZE, size.y, Workspace.PREVIEW_CHUNK_SIZE),
			1.0 / resource.normalized_density(),
			opaque,
			transparent,
		)
		native_times.append(_elapsed_ms(started))
		if projection.has("mesh"):
			native_successes += 1
	_metrics["native_chunk_rebuild_ms"] = _distribution(native_times)
	_metrics["native_chunk_successes"] = native_successes

	var sample_indices := _occupied_indices(resource, SAMPLE_COUNT)
	_metrics["sample_indices"] = sample_indices.size()
	started = Time.get_ticks_usec()
	var affected: Array = workspace.call("_affected_preview_chunks", sample_indices)
	_metrics["affected_chunk_mapping_ms"] = _elapsed_ms(started)
	_metrics["affected_chunk_count"] = affected.size()
	var seed := Selection.cell_of(sample_indices[0], size) if not sample_indices.is_empty() else Vector3i(-1, -1, -1)
	if seed.x >= 0:
		var selection := Selection.new()
		started = Time.get_ticks_usec()
		selection.start(resource, seed, 1, 0.0)
		var steps := 0
		while not selection.done:
			selection.step(256)
			steps += 1
		_metrics["selection_connected_ms"] = _elapsed_ms(started)
		_metrics["selection_connected_count"] = selection.indices.size()
		_metrics["selection_connected_steps"] = steps
		_metrics["selection_connected_error"] = selection.error

	var panel: VBoxContainer = workspace.get("_selection_panel")
	started = Time.get_ticks_usec()
	panel.call("set_selection", sample_indices)
	var overlay_slices := 0
	while panel.call("busy") and overlay_slices < SAMPLE_COUNT:
		panel.call("_process", 0.0)
		overlay_slices += 1
	_metrics["selection_overlay_ms"] = _elapsed_ms(started)
	_metrics["selection_overlay_slices"] = overlay_slices

	started = Time.get_ticks_usec()
	workspace.call("_set_hidden_group_indices", sample_indices)
	_metrics["group_filter_ms"] = _elapsed_ms(started)
	_metrics["group_filter_queued_chunks"] = (workspace.get("_pending_preview_chunks") as Dictionary).size()
	started = Time.get_ticks_usec()
	workspace.call("_set_hidden_group_indices", PackedInt32Array())
	_metrics["group_filter_clear_ms"] = _elapsed_ms(started)
	if "--visual" in OS.get_cmdline_user_args():
		panel.call("clear_selection")
		workspace.call("_fit_camera_to_surface")
		var visual_started := Time.get_ticks_usec()
		var visual_frames := 0
		while (
			not (workspace.get("_pending_preview_chunks") as Dictionary).is_empty()
			and Time.get_ticks_usec() - visual_started < 20000000
		):
			await process_frame
			visual_frames += 1
		await RenderingServer.frame_post_draw
		var image_error := root.get_texture().get_image().save_png(PROFILE_IMAGE)
		_metrics["visual_preview_ms"] = _elapsed_ms(visual_started)
		_metrics["visual_preview_frames"] = visual_frames
		_check(
			(workspace.get("_pending_preview_chunks") as Dictionary).is_empty(),
			"large visual preview did not finish within 20 seconds",
		)
		_check(image_error == OK, "large visual capture failed: %s" % error_string(image_error))
		print("VISUAL: ", ProjectSettings.globalize_path(PROFILE_IMAGE))

	started = Time.get_ticks_usec()
	var validation := resource.validation_errors()
	_metrics["validation_ms"] = _elapsed_ms(started)
	_check(validation.is_empty(), "profile source is invalid: %s" % [validation])
	started = Time.get_ticks_usec()
	var save_error := ResourceSaver.save(resource, PROFILE_SAVE)
	_metrics["save_ms"] = _elapsed_ms(started)
	_check(save_error == OK, "profile save failed: %s" % error_string(save_error))
	if save_error == OK:
		started = Time.get_ticks_usec()
		var reopened := ResourceLoader.load(
			PROFILE_SAVE, "", ResourceLoader.CACHE_MODE_IGNORE
		) as EmberVoxelModelResource
		_metrics["reopen_saved_ms"] = _elapsed_ms(started)
		_check(reopened != null and reopened.voxels == resource.voxels, "saved profile did not round-trip")

	workspace.free()
	undo.clear_history()
	undo.free()
	_finish()


func _measure_load() -> EmberVoxelModelResource:
	if not ResourceLoader.exists(PROFILE_SOURCE):
		_errors.append("missing profile source: %s" % PROFILE_SOURCE)
		return null
	var samples: Array[float] = []
	var result: EmberVoxelModelResource
	for iteration in 3:
		var started := Time.get_ticks_usec()
		var loaded := ResourceLoader.load(
			PROFILE_SOURCE, "", ResourceLoader.CACHE_MODE_IGNORE
		) as EmberVoxelModelResource
		samples.append(_elapsed_ms(started))
		if loaded == null:
			_errors.append("profile source did not load")
			return null
		result = loaded
	_metrics["resource_load_ms"] = _distribution(samples)
	return result


func _source_file_size() -> int:
	var file := FileAccess.open(PROFILE_SOURCE, FileAccess.READ)
	return file.get_length() if file != null else -1


func _occupied_indices(resource: EmberVoxelModelResource, limit: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for index in resource.voxels.size():
		if resource.voxels[index] > 0:
			result.append(index)
			if result.size() >= limit:
				break
	return result


func _column_heights_reference(values: PackedByteArray, size: Vector3i) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(size.x * size.z)
	heights.fill(-1)
	for z in size.z:
		for x in size.x:
			for y in range(size.y - 1, -1, -1):
				if values[Model.index_of(Vector3i(x, y, z), size)] != 0:
					heights[x + z * size.x] = y
					break
	return heights


func _distribution(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"count": 0}
	values.sort()
	var total := 0.0
	for value in values:
		total += value
	return {
		"count": values.size(),
		"min": snappedf(values[0], 0.001),
		"mean": snappedf(total / values.size(), 0.001),
		"median": snappedf(values[values.size() / 2], 0.001),
		"max": snappedf(values[-1], 0.001),
	}


func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0


func _finish() -> void:
	_metrics["errors"] = _errors
	var json := JSON.stringify(_metrics, "  ")
	var file := FileAccess.open(PROFILE_JSON, FileAccess.WRITE)
	if file != null:
		file.store_string(json + "\n")
	print(json)
	print("PROFILE: ", ProjectSettings.globalize_path(PROFILE_JSON))
	if FileAccess.file_exists(_profile_save_absolute()):
		DirAccess.remove_absolute(_profile_save_absolute())
	quit(0 if _errors.is_empty() else 1)


func _profile_save_absolute() -> String:
	return ProjectSettings.globalize_path(PROFILE_SAVE)


func _check(condition: bool, message: String) -> void:
	if not condition and message not in _errors:
		_errors.append(message)
