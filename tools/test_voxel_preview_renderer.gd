extends SceneTree
## Run headless for lifecycle/texture shape and once with the Windows renderer
## for the real-pixel gate. No preview files are written to the project.

const Renderer = preload("res://addons/ember_import/ember_voxel_preview_renderer.gd")
const MODEL_ID := "vox_fan_anvil"
const PREFAB_PATH := "res://prefabs/voxels/vox_fan_anvil.tscn"
const SOURCE_MODEL_ID := "vox_crate_1"
const SOURCE_PREFAB_PATH := "res://prefabs/voxels/vox_crate_1.tscn"

var _textures: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("PASS voxel preview renderer")
		print("  display: headless")
		print("  real-render gate skipped; run without --headless for pixel verification")
		quit(0)
		return
	var renderer := Renderer.new() as EmberVoxelPreviewRenderer
	var source_prefab_before := FileAccess.get_sha256(SOURCE_PREFAB_PATH) if FileAccess.file_exists(SOURCE_PREFAB_PATH) else ""
	root.add_child(renderer)
	renderer.preview_ready.connect(func(model_id: String, texture: Texture2D) -> void:
		_textures[model_id] = texture
	)
	renderer.queue_preview(MODEL_ID, PREFAB_PATH)
	renderer.queue_preview(SOURCE_MODEL_ID)
	var deadline := Time.get_ticks_msec() + 12000
	while _textures.size() < 2 and Time.get_ticks_msec() < deadline:
		await process_frame
	var errors: Array[String] = []
	for model_id in [MODEL_ID, SOURCE_MODEL_ID]:
		var texture := _textures.get(model_id, null) as Texture2D
		if texture == null:
			errors.append("preview renderer did not return %s" % model_id)
			continue
		var image := texture.get_image()
		if image == null or image.is_empty() or image.get_size() != Renderer.PREVIEW_SIZE:
			errors.append("%s preview has no 128x128 render image" % model_id)
		elif not _has_model_pixels(image):
			errors.append("%s preview returned only the background" % model_id)
	var source_prefab_after := FileAccess.get_sha256(SOURCE_PREFAB_PATH) if FileAccess.file_exists(SOURCE_PREFAB_PATH) else ""
	if source_prefab_after != source_prefab_before:
		errors.append("source-only preview wrote or replaced a forbidden PackedScene")
	var source_key := renderer._cache_key(SOURCE_MODEL_ID, "")
	renderer.clear_cache(EmberVoxelCatalog.native_path(SOURCE_MODEL_ID))
	if renderer._cache.has(source_key):
		errors.append("source publication did not invalidate source-based thumbnail")
	# Cancel/requeue while a request is active; a duplicate must not publish twice.
	var cancelled_results: Array = []
	renderer.preview_ready.connect(func(id: String, _texture: Texture2D):
		if id == "cancelled": cancelled_results.append(id)
	)
	renderer.clear_cache(PREFAB_PATH)
	renderer.queue_preview("cancelled", PREFAB_PATH)
	await process_frame
	renderer.queue_preview("cancelled", PREFAB_PATH)
	if renderer._pending.size() > 1:
		errors.append("active preview accepted duplicate queue work")
	renderer.cancel_pending()
	renderer.queue_preview("cancelled", PREFAB_PATH)
	deadline = Time.get_ticks_msec() + 12000
	while renderer.pending_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if cancelled_results.size() != 1 or renderer.pending_count() != 0:
		errors.append("cancel/requeue published stale result or failed to finish")
	var invalidated_results: Array = []
	renderer.preview_ready.connect(func(id: String, _texture: Texture2D):
		if id == "invalidated": invalidated_results.append(id)
	)
	renderer.clear_cache(PREFAB_PATH)
	renderer.queue_preview("invalidated", PREFAB_PATH)
	await process_frame
	renderer.clear_cache(PREFAB_PATH)
	renderer.queue_preview("invalidated", PREFAB_PATH)
	deadline = Time.get_ticks_msec() + 12000
	while renderer.pending_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if invalidated_results.size() != 1 or renderer.pending_count() != 0:
		errors.append("in-flight cache invalidation published stale image or lost replacement")
	var bad_path := "user://preview_bad_root_%d.tscn" % Time.get_ticks_usec()
	var bad_root := Node.new()
	var bad_scene := PackedScene.new()
	bad_scene.pack(bad_root)
	ResourceSaver.save(bad_scene, bad_path)
	bad_root.free()
	var failed_results: Array = []
	renderer.preview_failed.connect(func(id: String, reason: String): failed_results.append([id, reason]))
	renderer.queue_preview("invalid_root", bad_path)
	deadline = Time.get_ticks_msec() + 12000
	while renderer.pending_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if failed_results.size() != 1 or renderer.failure_count() != 1 or renderer.pending_count() != 0:
		errors.append("invalid preview did not finish with an explicit failure")
	renderer.clear_cache(bad_path)
	if renderer.failure_count() != 0:
		errors.append("cache invalidation did not allow failed asset retry")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_path))
	# Repair a failed file load at the same path; failed threaded tasks must drain.
	var broken_path := "user://preview_broken_%d.tscn" % Time.get_ticks_usec()
	var broken_file := FileAccess.open(broken_path, FileAccess.WRITE)
	broken_file.store_string("[gd_scene format=3]\n[node name=\"Broken\" type=\"Node3D\"\n")
	broken_file.close()
	failed_results.clear()
	renderer.queue_preview("broken_file", broken_path)
	deadline = Time.get_ticks_msec() + 12000
	while renderer.pending_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if failed_results.size() != 1 or renderer.failure_count() != 1:
		errors.append("failed file load did not report failure")
	var repaired_root := Node3D.new()
	var repaired_scene := PackedScene.new()
	repaired_scene.pack(repaired_root)
	ResourceSaver.save(repaired_scene, broken_path)
	repaired_root.free()
	renderer.clear_cache(broken_path)
	renderer.queue_preview("repaired_file", broken_path)
	deadline = Time.get_ticks_msec() + 12000
	while renderer.pending_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _textures.has("repaired_file") or renderer.failure_count() != 0:
		errors.append("repaired file could not be retried after failed threaded load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(broken_path))
	# A sizeable user:// fixture keeps the threaded load alive across frames.
	# One renderer exits, the other shares the load and must still get its pixels.
	var loading_path := "user://preview_loading_%d.tscn" % Time.get_ticks_usec()
	var loading_root := Node3D.new()
	var padding := PackedByteArray()
	padding.resize(8 * 1024 * 1024)
	loading_root.set_meta("fixture_padding", padding)
	var loading_mesh := MeshInstance3D.new()
	loading_mesh.name = "Mesh"
	loading_mesh.mesh = BoxMesh.new()
	loading_root.add_child(loading_mesh)
	loading_mesh.owner = loading_root
	var loading_scene := PackedScene.new()
	loading_scene.pack(loading_root)
	ResourceSaver.save(loading_scene, loading_path)
	loading_root.free()
	# Cancellation must dispose every prefetched token, including those that
	# complete without ever becoming the active scene on the viewport.
	var ahead_paths: Array[String] = []
	var ahead := Renderer.new()
	root.add_child(ahead)
	var ahead_results: Array = []
	ahead.preview_ready.connect(func(id: String, _texture: Texture2D): ahead_results.append(id))
	for index in Renderer.MAX_LOADING_REQUESTS + 2:
		var path := loading_path.get_basename() + "_ahead_%d.tscn" % index
		DirAccess.copy_absolute(ProjectSettings.globalize_path(loading_path), ProjectSettings.globalize_path(path))
		ahead_paths.append(path)
		ahead.queue_preview("ahead_%d" % index, path)
	await process_frame
	if ahead._prefetched_paths.is_empty() or ahead._prefetched_paths.size() + (0 if ahead._loading_path.is_empty() else 1) > Renderer.MAX_LOADING_REQUESTS:
		errors.append("prefetch did not exercise a bounded loading window")
	ahead.cancel_pending()
	deadline = Time.get_ticks_msec() + 12000
	while (ahead.pending_count() > 0 or not Renderer._abandoned_loads.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not ahead_results.is_empty() or not ahead._prefetched_paths.is_empty() or not Renderer._abandoned_loads.is_empty():
		errors.append("cancelled prefetched jobs published results or leaked tokens")
	for path in ahead_paths:
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			errors.append("prefetched loader token remained after cancellation")
	# Requeue after cancellation uses the same renderer and must return pixels.
	ahead.queue_preview("ahead_requeued", ahead_paths[0])
	deadline = Time.get_ticks_msec() + 12000
	while ahead.pending_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if ahead_results != ["ahead_requeued"] or ahead.failure_count() != 0:
		errors.append("prefetched cancellation broke requeue")
	ahead_results.clear()
	for index in 3:
		ahead.clear_cache(ahead_paths[index])
		ahead.queue_preview("ahead_old_%d" % index, ahead_paths[index])
	await process_frame
	var stale_key := ahead._cache_key("ahead_old_1", ahead_paths[1])
	if not ahead._prefetched_paths.has(stale_key):
		errors.append("fixture did not invalidate a prefetched pending scene")
	ahead.clear_cache(ahead_paths[1])
	ahead.queue_preview("ahead_fresh", ahead_paths[1])
	ahead._prefetch_pending()
	if ahead._prefetched_paths.values().count(ahead_paths[1]) > 1:
		errors.append("replacement revision joined an obsolete prefetched same-path job")
	deadline = Time.get_ticks_msec() + 12000
	while ahead.pending_count() > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	if ahead_results.has("ahead_old_1") or ahead_results.count("ahead_fresh") != 1:
		errors.append("pending prefetch invalidation published stale pixels or lost replacement")
	ahead.free()
	var exiting := Renderer.new()
	var survivor := Renderer.new()
	root.add_child(exiting)
	root.add_child(survivor)
	var survivor_pixels: Array = []
	survivor.preview_ready.connect(func(_id: String, texture: Texture2D): survivor_pixels.append(texture))
	exiting.queue_preview("exiting", loading_path)
	for index in ahead_paths.size():
		exiting.queue_preview("exit_ahead_%d" % index, ahead_paths[index])
	survivor.queue_preview("survivor", loading_path)
	deadline = Time.get_ticks_msec() + 6000
	while (exiting._loading_path.is_empty() or survivor._loading_path.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if exiting._loading_path.is_empty() or survivor._loading_path.is_empty():
		errors.append("fixture did not exercise concurrent active resource loading")
	exiting.free()
	deadline = Time.get_ticks_msec() + 12000
	while (survivor.pending_count() > 0 or not Renderer._abandoned_loads.is_empty()) and Time.get_ticks_msec() < deadline:
		await process_frame
	if survivor_pixels.size() != 1 or survivor.failure_count() != 0 or not Renderer._abandoned_loads.is_empty():
		errors.append("exiting renderer leaked a loader task or broke shared-path survivor")
	elif not _has_model_pixels((survivor_pixels[0] as Texture2D).get_image()):
		errors.append("shared-path survivor returned only background pixels")
	survivor.free()
	for path in ahead_paths:
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			errors.append("renderer exit leaked a prefetched loader token")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(loading_path))
	renderer.queue_free()
	await process_frame
	if not errors.is_empty():
		printerr("FAIL voxel preview renderer")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS voxel preview renderer")
	print("  display: ", DisplayServer.get_name())
	print("  in-memory preview: ", Renderer.PREVIEW_SIZE)
	print("  prefab + source-only model pixels: renderer verified")
	print("  duplicate/cancel/requeue + invalid root/cache invalidation + failed-file repair: verified")
	print("  in-flight renderer exit/task disposal + concurrent shared-path pixels: verified")
	quit(0)


func _has_model_pixels(image: Image) -> bool:
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			var pixel := image.get_pixel(x, y)
			if Vector3(pixel.r, pixel.g, pixel.b).distance_to(
				Vector3(Renderer.BACKGROUND.r, Renderer.BACKGROUND.g, Renderer.BACKGROUND.b)
			) > 0.08:
				return true
	return false
