extends SceneTree
const Dialog = preload("res://addons/ember_import/ember_voxel_split_dialog.gd")
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1100,900)
	var scene := (load("res://scenes/test_pier.tscn") as PackedScene).instantiate()
	scene.set_script(null)
	scene.get_node("Map").set_script(null)
	root.add_child(scene)
	var prop := scene.get_node("Map/Terrain/TimberPier/Visual") as EmberVoxelProp
	assert(prop != null)
	var undo := UndoRedo.new()
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.open_split(prop,scene,undo)
	assert(not dialog.get_ok_button().disabled,dialog._status.text)
	for frame in 20:
		await process_frame
	RenderingServer.force_draw(false)
	var path := "user://voxel-split-preview-%d.png" % OS.get_process_id()
	dialog.get_texture().get_image().save_png(path)
	print("SPLIT_PREVIEW PASS ",ProjectSettings.globalize_path(path))
	dialog.free()
	undo.free()
	scene.free()
	quit()
