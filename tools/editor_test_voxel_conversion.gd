@tool
extends EditorPlugin
const Dialog = preload("res://addons/ember_import/ember_voxel_conversion_dialog.gd")
var errors: Array[String] = []
func _enter_tree() -> void:
	_run.call_deferred()
func frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame
func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
func capture(label: String, viewport: Viewport = null) -> void:
	await frames(20)
	RenderingServer.force_draw(false)
	var target := viewport if viewport != null else EditorInterface.get_base_control().get_viewport()
	var path := "user://voxel-conversion-%s-%d.png" % [label,OS.get_process_id()]
	target.get_texture().get_image().save_png(path)
	print("CONVERSION_CAPTURE ",ProjectSettings.globalize_path(path))
func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-canvas-smoke-"):
		push_error("Disposable editor copy required")
		return
	await frames(90)
	EditorInterface.open_scene_from_path("res://scenes/test_pier.tscn")
	await frames(60)
	var scene := EditorInterface.get_edited_scene_root()
	var parent := scene.get_node("Map/Props/MooringPost96_240")
	var original := parent.get_node("Visual")
	var collider := parent.get_node("Collision")
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(parent)
	get_parent().get_node("EmberImportPlugin").call("_convert_voxel_form")
	await frames(20)
	var dialog: ConfirmationDialog
	for child in EditorInterface.get_base_control().get_children():
		if child is Dialog:
			dialog = child
	check(dialog != null,"toolbar did not open conversion")
	if dialog == null:
		get_tree().quit(1)
		return
	check(not dialog.get_ok_button().disabled,"preview invalid: " + dialog._status.text)
	await capture("preview",dialog)
	dialog._show_original.button_pressed = true
	await capture("original",dialog)
	dialog._show_original.button_pressed = false
	dialog._commit()
	await frames(30)
	var prop := parent.get_node("Visual") as EmberVoxelProp
	check(prop != null and collider.get_parent() == null,"conversion not applied")
	var canvas := EditorInterface.get_editor_main_screen().find_child("EmberSurfaceCanvasWorkspace",true,false) as EmberVoxelSculptWorkspace
	check(canvas._object_session != null,"Canvas did not open")
	canvas._context_toggle.button_pressed = true
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	await capture("canvas")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	check(parent.get_node("Visual") == original and collider.get_parent() == parent,"editor Undo")
	history.redo()
	check(parent.get_node("Visual") == prop and collider.get_parent() == null,"editor Redo")
	for attempt in 100:
		if not EditorInterface.get_resource_filesystem().is_scanning():
			break
		await frames(5)
	check(EditorInterface.save_scene() == OK,"editor save")
	await frames(20)
	var saved := ResourceLoader.load(scene.scene_file_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := saved.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	check(reopened.get_node("Map/Props/MooringPost96_240/Visual") is EmberVoxelProp,"editor reopen")
	reopened.free()
	print("CONVERSION_EDITOR ","PASS" if errors.is_empty() else "FAIL"," ",errors)
	await frames(30)
	get_tree().quit(0 if errors.is_empty() else 1)
