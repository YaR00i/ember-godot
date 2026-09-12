extends SceneTree

const Dialog = preload("res://addons/ember_import/ember_voxel_tree_object_dialog.gd")

var failures := 0


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var scene := Node3D.new()
	root.add_child(scene)
	var props := Node3D.new()
	props.name = "Props"
	scene.add_child(props)
	var undo := UndoRedo.new()
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.open_for(scene, props, undo, Vector3.ZERO, 16.0)
	for frame in 3:
		await process_frame
	dialog._height.value = 64
	dialog._prepare()
	for frame in 8:
		await process_frame
	check(dialog.creation != null and dialog.creation.source != null, "large tree dialog prepares source")
	check(not dialog.get_ok_button().disabled and dialog._preview != null, "large tree dialog exact preview")
	check(dialog._settings().generation_version == 2, "dialog defaults to large forms")
	dialog._shape_numbers.branch_thickness.value = 40
	check(dialog.get_ok_button().disabled, "parameter edit did not invalidate exact preview")
	dialog._shape_numbers.branch_thickness.value = 75
	dialog._prepare()
	dialog._style.select(1)
	dialog._style_changed()
	check(dialog._settings().generation_version == 1 and not dialog._shape.visible, "classic controls remain accessible")
	dialog._style.select(0)
	dialog._style_changed()
	dialog._prepare()
	for frame in 4:
		await process_frame
	check(dialog.size.x <= root.size.x and dialog.size.y <= root.size.y, "large tree dialog fits 1280x900: %s minimum %s" % [dialog.size, dialog.get_contents_minimum_size()])
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280, 720)
		for frame in 4:
			await process_frame
		check(dialog.size.y <= 680, "dialog does not reserve titlebar space at 720p")
		var path := "user://voxel_large_tree_dialog.png"
		root.get_texture().get_image().save_png(path)
		print("VOXEL_LARGE_TREE_CAPTURE ", ProjectSettings.globalize_path(path))
	dialog.free()
	scene.free()
	undo.clear_history()
	undo.free()
	print("Voxel large tree dialog: ", "PASS" if failures == 0 else "FAIL %d" % failures)
	quit(0 if failures == 0 else 1)
