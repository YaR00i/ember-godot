extends SceneTree
## Reproducible native layout capture for the combat content editor workspace.

const Workspace := preload("res://addons/ember_import/ember_combat_content_library_workspace.gd")
const WIDE_OUTPUT := "user://combat_content_library_1600.png"
const COMPACT_OUTPUT := "user://combat_content_library_1280.png"
const ACTION_OUTPUT := "user://combat_content_action_1600.png"
const UNIT_OUTPUT := "user://combat_content_unit_1600.png"


func _init() -> void:
	root.size = Vector2i(1600, 900)
	_capture_and_quit.call_deferred()


func _capture_and_quit() -> void:
	var background := ColorRect.new()
	background.color = Color("20242b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var workspace := Workspace.new() as Control
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(workspace)
	var undo := UndoRedo.new()
	workspace.call("setup", null, undo)
	await process_frame
	await process_frame
	await create_timer(0.15).timeout
	var error := root.get_texture().get_image().save_png(WIDE_OUTPUT)
	if error != OK:
		printerr("FAIL combat content library wide capture: ", error_string(error))
		quit(1)
		return
	workspace.call("_open_related", "action", "earth_wall")
	await process_frame
	await process_frame
	error = root.get_texture().get_image().save_png(ACTION_OUTPUT)
	if error != OK:
		printerr("FAIL combat action editor capture: ", error_string(error))
		quit(1)
		return
	workspace.call("_open_related", "unit", "mira")
	await process_frame
	await process_frame
	error = root.get_texture().get_image().save_png(UNIT_OUTPUT)
	if error != OK:
		printerr("FAIL combat unit editor capture: ", error_string(error))
		quit(1)
		return
	workspace.call("_open_related", "effect", "apply_burning")
	await process_frame
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	await create_timer(0.15).timeout
	error = root.get_texture().get_image().save_png(COMPACT_OUTPUT)
	if error != OK:
		printerr("FAIL combat content library compact capture: ", error_string(error))
		quit(1)
		return
	print("PASS combat content library 1600 capture: ", ProjectSettings.globalize_path(WIDE_OUTPUT))
	print("PASS combat content action capture: ", ProjectSettings.globalize_path(ACTION_OUTPUT))
	print("PASS combat content unit capture: ", ProjectSettings.globalize_path(UNIT_OUTPUT))
	print("PASS combat content library 1280 capture: ", ProjectSettings.globalize_path(COMPACT_OUTPUT))
	workspace.free()
	undo.clear_history(false)
	undo.free()
	quit(0)
