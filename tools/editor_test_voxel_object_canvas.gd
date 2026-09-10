@tool
extends EditorPlugin
## Opt-in disposable-project plugin. Never enable in the authored checkout.
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
var errors: Array[String] = []

func _enter_tree() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-canvas-smoke-"):
		push_error("Editor fixture requires a disposable ember-canvas-smoke project")
		return
	for frame in 30:
		await get_tree().process_frame
	check(Engine.is_editor_hint(), "not an actual editor run")
	var scene: Node
	for attempt in 10:
		EditorInterface.open_scene_from_path("res://scenes/test_pier.tscn")
		for frame in 30:
			await get_tree().process_frame
		scene = EditorInterface.get_edited_scene_root()
		if scene != null and scene.scene_file_path == "res://scenes/test_pier.tscn":
			break
	if scene == null or scene.scene_file_path != "res://scenes/test_pier.tscn":
		push_error("Editor fixture could not activate test_pier after startup")
		get_tree().quit(1)
		return
	var prop = scene.get_node("Map/Props/BarrelA")
	var water_probe := EmberVoxelProp.new()
	water_probe.water_contact_enabled = true
	scene.add_child(water_probe)
	check(water_probe.get_node_or_null("WaterContact") == null, "editor created runtime WaterContact")
	water_probe.free()
	var duplicate := EmberSceneAuthoring.make_duplicate(scene, prop, Vector3.ZERO)
	check(not duplicate.placement_id.is_empty() and duplicate.placement_id != prop.placement_id, "duplicate reused placement_id")
	duplicate.free()
	var undo := get_undo_redo()
	var edit := Session.new()
	check(prop.has_method("configure_voxel_scale"), "prop remains editor placeholder")
	check(edit.open(prop, scene, undo), "editor open: " + edit.error)
	var canvas := Workspace.new()
	EditorInterface.get_base_control().add_child(canvas)
	canvas.open_object(edit)
	var old_id: String = prop.model_id
	var old_pose: Transform3D = prop.transform
	var old_placement: String = prop.placement_id
	for index in edit.draft.voxels.size():
		if edit.draft.voxels[index] > 0:
			edit.draft.voxels[index] = 0
			break
	print("EDITOR_CANVAS Save")
	check(canvas.save_changes(), "actual editor Canvas Save: " + edit.error)
	print("EDITOR_CANVAS Saved")
	var new_id: String = prop.model_id
	check(prop.get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META) == EmberVoxelPrefab.source_signature(new_id), "Save signature stale")
	check(new_id != old_id, "Save did not fork")
	var history := undo.get_history_undo_redo(undo.get_object_history_id(scene))
	print("EDITOR_CANVAS Undo")
	history.undo()
	check(prop.model_id == old_id and prop.transform == old_pose, "editor Undo")
	print("EDITOR_CANVAS Redo")
	history.redo()
	print("EDITOR_CANVAS Redone")
	print("EDITOR_CANVAS live paths ", prop.get_node("Mesh").mesh.resource_path, " | ", prop.get_node("Collision/Shape").shape.resource_path)
	check(prop.get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META) == EmberVoxelPrefab.source_signature(new_id), "Redo signature stale")
	check(prop.model_id == new_id and prop.placement_id == old_placement, "editor Redo/placement")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "editor pack")
	var path := "user://editor-canvas-reopen-%d.tscn" % OS.get_process_id()
	check(ResourceSaver.save(packed, path) == OK, "editor scene save")
	var reopened := (ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	check(reopened.get_node("Map/Props/BarrelA").model_id == new_id, "editor scene reopen")
	reopened.free()
	canvas.anchor_right = 0
	canvas.anchor_bottom = 0
	for width in [1500, 1000, 1200, 1500]:
		canvas.size = Vector2(width, 650)
		for frame in 12:
			await get_tree().process_frame
		for control_name in ["SaveVoxelSurfacePilot", "VoxelSculptSidebarScroll", "VoxelSculptViewportContainer"]:
			var control := canvas.find_child(control_name, true, false) as Control
			check(control.get_global_rect().end.x <= canvas.get_global_rect().end.x + 1, "width %d clips %s" % [width, control_name])
		check(canvas.size.x <= width + 1, "Canvas minimum exceeded %d" % width)
	canvas.free()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1800, 900))
		EditorInterface.edit_node(prop)
		var actual := EditorInterface.get_editor_main_screen().get_node("EmberSurfaceCanvasWorkspace")
		actual.open_object(edit)
		EditorInterface.set_main_screen_editor("Surface Canvas")
		for frame in 45:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var capture := "user://editor-canvas-narrow-%d.png" % OS.get_process_id()
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(capture)
		print("EDITOR_CANVAS_CAPTURE ", ProjectSettings.globalize_path(capture), " center_size=", actual.size)
		check(not actual.has_unsaved_changes(), "reopened actual Canvas unexpectedly dirty")
		EditorInterface.set_main_screen_editor("3D")
	history.clear_history()
	EditorInterface.inspect_object(null)
	# This project is disposable: exercise the user's explicit Ctrl+S step too,
	# instead of quitting with a modified editor scene still awaiting save.
	check(EditorInterface.save_scene() == OK, "editor explicit scene Save")
	for frame in 10:
		await get_tree().process_frame
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	for message in errors:
		push_error(message)
	print("editor_test_voxel_object_canvas: ", "PASS" if errors.is_empty() else "FAIL", " Engine.is_editor_hint=", Engine.is_editor_hint())
	if errors.is_empty():
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		get_tree().quit(1)
