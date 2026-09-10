extends SceneTree
const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
const Split = preload("res://addons/ember_import/ember_voxel_object_split.gd")
const Assembly = preload("res://addons/ember_import/ember_voxel_assembly_session.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1200,850)
	var scene := Node3D.new()
	root.add_child(scene)
	var undo := UndoRedo.new()
	var creation := Creation.new()
	var folder := "user://ember-tests/assembly-preview-%d" % Time.get_ticks_usec()
	creation.source_directory = folder.path_join("sources")
	creation.prefab_directory = folder.path_join("prefabs")
	assert(creation.prepare("block",Vector3i(192,10,256),16,Color.BROWN,"Deck"))
	var prop := creation.commit(scene,scene,undo,Vector3.ZERO)
	var split := Split.new()
	split.source_directory = creation.source_directory
	split.prefab_directory = creation.prefab_directory
	assert(split.prepare(prop,scene,64),split.error)
	var group := split.commit(undo)
	assert(group != null)
	var session := Assembly.new()
	session.source_directory = creation.source_directory
	session.prefab_directory = creation.prefab_directory
	assert(session.open(group,scene,undo),session.error)
	var canvas := Workspace.new()
	root.add_child(canvas)
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.setup(null,undo)
	canvas.open_object(session)
	for index in 500:
		await process_frame
		if index > 20 and canvas._pending_preview_chunks.is_empty():
			break
	RenderingServer.force_draw(false)
	var path := "user://voxel-assembly-preview-%d.png" % OS.get_process_id()
	root.get_texture().get_image().save_png(path)
	print("ASSEMBLY_PREVIEW PASS ",ProjectSettings.globalize_path(path))
	canvas.free()
	undo.clear_history()
	undo.free()
	scene.free()
	quit()
