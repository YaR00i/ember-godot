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
	if ResourceLoader.exists(SOURCE_PREFAB_PATH) or FileAccess.file_exists(ProjectSettings.globalize_path(SOURCE_PREFAB_PATH)):
		errors.append("source-only preview wrote a forbidden PackedScene")
	renderer.queue_free()
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
