extends SceneTree

const Dialog = preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const OUTPUT := "user://ember-tests/compact-material-dialog-finish.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1600, 900)
	var dialog := Dialog.new()
	root.add_child(dialog)
	if not dialog.open_variant("grass_autumn", "grass"):
		printerr("FAIL: pattern dialog did not open")
		quit(1)
		return
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(OUTPUT) != OK:
		printerr("FAIL: could not capture pattern dialog")
		quit(1)
		return
	print("PASS Forward+ pattern canvas: ", ProjectSettings.globalize_path(OUTPUT))
	quit()
