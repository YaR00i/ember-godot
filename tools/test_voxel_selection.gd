extends SceneTree
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const PATH := "user://ember_selection_test.tres"
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var resource := _fixture()
	var original := resource.voxels.duplicate()
	var size := resource.grid_size()
	var job := Selection.new()
	job.start(resource, Vector3i(2, 1, 2), 1, 0)
	job.step(1)
	_check(not job.done, "search did not yield")
	_finish(job)
	_check(job.indices.size() == 64 and job.error.is_empty(), "3D flood missed interior or vertical wall / crossed color")
	job.start(resource, Vector3i(2, 1, 2), 2, 0)
	_finish(job)
	_check(job.indices.size() == 65, "all similar missed disconnected island")
	job.start(resource, Vector3i(2, 1, 2), 1, 0.03)
	_finish(job)
	_check(job.indices.size() == 66, "tolerance did not include near palette and connect island")
	job.start(resource, Vector3i(2, 1, 2), 1, 0, Rect2i(), 2)
	_finish(job)
	_check(job.indices.size() == 16, "slice crossed protected upper layers")
	job.start(resource, Vector3i(18, 1, 2), 2, 1, Rect2i(0, 0, 1, 1))
	_check(job.done and not job.error.is_empty(), "out of region seed accepted")
	job.start(resource, Vector3i(2, 1, 2), 1, 0, Rect2i(), -1, 8)
	_finish(job)
	_check(not job.error.is_empty() and job.indices.is_empty(), "overflow returned partial selection")
	job.start(resource, Vector3i.ZERO, 1, 0)
	_check(job.done and not job.error.is_empty(), "empty voxel selected")
	_check(Selection.combine({1:true}, PackedInt32Array([2]), 0) == {2:true}, "replace union failed")
	_check(Selection.combine({1:true}, PackedInt32Array([2]), 1) == {1:true, 2:true}, "add failed")
	_check(Selection.combine({1:true, 2:true}, PackedInt32Array([2]), 2) == {1:true}, "subtract failed")
	_check(resource.voxels == original, "search mutated resource")
	root.size = Vector2i(1280, 720)
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null, undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(resource, PATH)
	for frame in 4:
		await process_frame
	var panel: VBoxContainer = workspace.get("_selection_panel")
	panel.get("_mode").select(1) # This regression exercises color connectivity, not the new default marquee.
	workspace.call("_toggle_voxel_selection")
	var camera: Camera3D = workspace.get("_camera")
	var viewport: SubViewport = workspace.get("_viewport")
	var container: SubViewportContainer = workspace.get("_viewport_container")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(Vector3(0.22, 0.3125, 0.22)) * container.size / Vector2(viewport.size)
	workspace.call("_on_viewport_input", click)
	await _settle(panel)
	_check(panel.get("selected").size() == 64 and not workspace.has_unsaved_changes() and not undo.has_undo(), "selection changed source/Undo")
	_check(not bool(workspace.get("_stroke_active")), "selection click started a sculpt brush")
	panel.call("choose", Vector3i(2, 1, 2))
	var overflow: RefCounted = panel.get("_job")
	overflow.start(resource, Vector3i(2, 1, 2), 1, 0, Rect2i(), -1, 8)
	await _settle(panel)
	_check(panel.get("selected").size() == 64, "overflow discarded previous selection")
	panel.call("choose", Vector3i(7, 1, 2), true)
	await _settle(panel)
	_check(panel.get("selected").size() == 65, "Shift UI did not add island")
	panel.call("choose", Vector3i(7, 1, 2), false, true)
	await _settle(panel)
	_check(panel.get("selected").size() == 64, "Ctrl UI did not subtract island")
	workspace.call("_select_palette_color", 3)
	panel.call("_request_paint")
	var edited := resource.voxels.duplicate()
	_check(edited != original and edited[Model.index_of(Vector3i(2, 1, 2), size)] == 3, "paint command did not apply")
	_check(edited[Model.index_of(Vector3i(7, 1, 2), size)] == 1 and resource.palette[1] == Color(0.2, 0.6, 0.3), "paint leaked to outside/palette")
	_check(resource.surface_fill_palette[0] == 1 and resource.transparency[0] == 7, "paint changed water/material channel")
	_check(panel.get("selected").size() == 64, "own paint lost selection")
	undo.undo()
	_check(resource.voxels == original and not undo.has_undo() and panel.get("selected").is_empty(), "Undo did not restore / invalidate stale mask")
	undo.redo()
	_check(resource.voxels == edited, "Redo differed")
	_check(bool(workspace.call("_save")), "save failed")
	var reopened := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(reopened != null and reopened.voxels == edited, "round trip failed")
	panel.call("choose", Vector3i(2, 1, 2))
	panel.call("cancel_search")
	await _settle(panel)
	_check(panel.get("selected").is_empty(), "cancel committed unfinished search")
	panel.call("choose", Vector3i(2, 1, 2))
	resource.emit_changed()
	_check(not panel.call("busy"), "resource mutation did not cancel job")
	panel.call("choose", Vector3i(2, 1, 2))
	await _settle(panel)
	var slice: CheckButton = workspace.find_child("EnableHeightSlice", true, false)
	slice.button_pressed = true
	_check(panel.get("selected").is_empty(), "scope switch retained stale selection")
	slice.button_pressed = false
	panel.call("choose", Vector3i(2, 1, 2))
	await _settle(panel)
	if "--visual" in OS.get_cmdline_user_args():
		workspace.call("_fit_camera_to_surface")
		var scroll := panel.get_parent().get_parent() as ScrollContainer
		scroll.ensure_control_visible(panel)
		for frame in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://ember_selection_test.png")
		print("VISUAL: ", ProjectSettings.globalize_path("user://ember_selection_test.png"))
	workspace.open_surface(_fixture(), "user://ember_selection_other.tres")
	_check(panel.get("selected").is_empty(), "resource switch retained mask")
	workspace.free()
	undo.clear_history()
	undo.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	for error in errors:
		printerr(error)
	if errors.is_empty():
		print("PASS voxel selection: 3D connectivity, similarity, bounds, incremental/cancel, replace/add/subtract, explicit paint, Undo, save, lifecycle")
	quit(0 if errors.is_empty() else 1)


func _settle(panel: VBoxContainer) -> void:
	for frame in 300:
		if not panel.call("busy"):
			return
		await process_frame
	_check(false, "selection did not settle")


func _finish(job: RefCounted) -> void:
	while not job.done:
		job.step(64)


func _fixture() -> EmberVoxelModelResource:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "selection_test"
	resource.display_name = "Выделение · стенки и остров"
	resource.size_blocks = Vector3i(2, 1, 1)
	resource.height_voxels = 6
	resource.palette = PackedColorArray([Color.TRANSPARENT, Color(0.2, 0.6, 0.3), Color(0.22, 0.62, 0.32), Color(0.8, 0.3, 0.2)])
	var size := resource.grid_size()
	resource.voxels.resize(size.x * size.y * size.z)
	for y in range(1, 5):
		for z in range(2, 6):
			for x in range(2, 6):
				resource.voxels[Model.index_of(Vector3i(x, y, z), size)] = 1
	resource.voxels[Model.index_of(Vector3i(6, 1, 2), size)] = 2
	resource.voxels[Model.index_of(Vector3i(7, 1, 2), size)] = 1
	resource.transparency.resize(resource.voxels.size())
	resource.transparency[0] = 7
	resource.surface_fill_levels.resize(size.x * size.z)
	resource.surface_fill_materials.resize(size.x * size.z)
	resource.surface_fill_palette.resize(size.x * size.z)
	resource.surface_fill_palette[0] = 1
	return resource


func _check(condition: bool, message: String) -> void:
	if not condition and message not in errors:
		errors.append(message)
