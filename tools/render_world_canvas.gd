extends SceneTree
## Standalone Forward+ QA: no editor-camera overrides or author-file writes.
func _init() -> void: _run.call_deferred()

func _run() -> void:
	var fixture := "user://ember-tests/world-canvas-render-%d" % Time.get_ticks_usec()
	root.get_node("EmberExploreProgress").set_meta("world_canvas_storage_root",fixture)
	var scene := (load("res://scenes/world_canvas.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	var projection: Node = scene.get_node("Map")._visual_surface_projection
	var deadline := Time.get_ticks_msec()+120000
	while not projection.is_projection_complete() and Time.get_ticks_msec() < deadline: await process_frame
	if not projection.is_projection_complete(): printerr("FAIL WORLD_CANVAS_RENDER projection timeout"); quit(1); return
	scene.get_node("CanvasLayer").hide()
	var overview := Camera3D.new()
	scene.add_child(overview)
	overview.fov = 40
	overview.near = 1
	overview.far = 2400
	overview.position = Vector3(520,500,580)
	overview.look_at(Vector3(192,0,200))
	overview.make_current()
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("user://world-canvas-overview.png")
	var image := root.get_texture().get_image()
	var result := image.save_png(path)
	print("PASS WORLD_CANVAS_RENDER ",path," image=",image.get_size()," result=",result)
	quit(0 if result == OK else 1)
