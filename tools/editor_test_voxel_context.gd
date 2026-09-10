@tool
extends EditorPlugin
## Opt-in only in a disposable copy. No authored map/source writes.
var errors: Array[String] = []
func _enter_tree() -> void:
	_run.call_deferred()
func frames(count: int) -> void:
	for index in count:
		await get_tree().process_frame
func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
func capture(label: String) -> void:
	await frames(20)
	RenderingServer.force_draw(false)
	var path := "user://voxel-context-%s-%d.png" % [label,OS.get_process_id()]
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
	print("CONTEXT_CAPTURE ",ProjectSettings.globalize_path(path))
func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-canvas-smoke-"):
		push_error("Disposable editor copy required")
		return
	await frames(90)
	EditorInterface.open_scene_from_path("res://scenes/test_pier.tscn")
	await frames(60)
	var scene := EditorInterface.get_edited_scene_root()
	var prop := scene.get_node("Map/Props/BarrelA") as EmberVoxelProp
	var source_path := EmberVoxelCatalog.NATIVE_DIR.path_join(prop.model_id + ".tres")
	var before := FileAccess.get_sha256(source_path)
	var session := preload("res://addons/ember_import/ember_voxel_object_session.gd").new()
	if not session.open(prop,scene,get_undo_redo()):
		push_error(session.error)
		get_tree().quit(1)
		return
	var canvas := EditorInterface.get_editor_main_screen().find_child("EmberSurfaceCanvasWorkspace",true,false) as EmberVoxelSculptWorkspace
	canvas.open_object(session)
	EditorInterface.set_main_screen_editor("Surface Canvas")
	EditorInterface.edit_node(prop)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	await frames(20)
	var point := canvas._viewport_container.size * 0.5
	var pick_before: Dictionary = canvas._pick_at(point)
	var started := Time.get_ticks_usec()
	canvas._context_toggle.button_pressed = true
	print("PIER_CONTEXT ",canvas._scene_context.visuals.size()," visuals ",(Time.get_ticks_usec()-started)/1000.0," ms")
	check(canvas._scene_context.visible and canvas._scene_context.visuals.size() > 5,"Pier background missing")
	check(canvas._pick_at(point) == pick_before,"context changed ray target")
	await capture("pier-60")
	canvas._context_opacity.value = 100
	await capture("pier-100")
	canvas._actions.apply_stroke(session.draft,{0:{"before":session.draft.voxels[0],"after":1 if session.draft.voxels[0] == 0 else 0}})
	check(canvas.has_unsaved_changes(),"stroke not dirty")
	check(FileAccess.get_sha256(source_path) == before,"draft published before Save")
	canvas.discard_changes()
	check(not canvas.has_unsaved_changes(),"discard")
	canvas._context_toggle.button_pressed = false
	await capture("isolated")
	check(canvas._scene_context.visuals.is_empty(),"context retained after toggle off")
	print("CONTEXT_EDITOR ","PASS" if errors.is_empty() else "FAIL"," ",errors)
	await frames(30)
	get_tree().quit(0 if errors.is_empty() else 1)
