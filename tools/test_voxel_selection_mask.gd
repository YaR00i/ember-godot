extends SceneTree
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const PATH := "user://ember_selection_mask_test.tres"
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var resource := _fixture()
	var original := resource.voxels.duplicate()
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null, undo)
	root.add_child(workspace)
	workspace.open_surface(resource, PATH)
	for frame in 4:
		await process_frame
	var selection: VBoxContainer = workspace.get("_selection_panel")
	var mask: CheckButton = selection.get("_mask")
	var target := _index(resource, Vector3i(5, 1, 5))
	var neighbor := _index(resource, Vector3i(6, 1, 5))
	var far := _index(resource, Vector3i(12, 1, 12))
	_select_tool(workspace, Model.TOOL_PAINT)
	selection.call("set_selection", PackedInt32Array([target, far]))
	await _settle(selection)
	mask.button_pressed = true
	workspace.call("_select_palette_color", 2)
	workspace.call("_prepare_stroke", Model.TOOL_PAINT)
	workspace.call("_apply_stroke_centers", _centers(Vector3i(5, 1, 5)))
	workspace.call("_finish_stroke")
	_check(resource.voxels[target] == 2 and resource.voxels[neighbor] == 1 and resource.voxels[far] == 1, "masked paint escaped mask or painted untouched member")
	_check(selection.call("selection_indices") == PackedInt32Array([target, far]) and mask.button_pressed, "masked paint discarded mask")
	undo.undo()
	_check(resource.voxels == original and selection.call("selection_indices").is_empty(), "paint Undo did not restore/clear stale mask")
	undo.redo()
	_check(resource.voxels[target] == 2 and resource.voxels[neighbor] == 1, "paint Redo escaped mask")
	# Material uses the exact same mask, preserves it on commit and clears on Undo.
	_select_tool(workspace, Model.TOOL_MATERIAL)
	selection.call("set_selection", PackedInt32Array([target]))
	await _settle(selection)
	mask.button_pressed = true
	workspace.call("_prepare_stroke", Model.TOOL_MATERIAL)
	workspace.call("_apply_stroke_centers", _centers(Vector3i(5, 1, 5)))
	workspace.call("_finish_stroke")
	_check(resource.transparency[target] == 208 and resource.transparency[neighbor] == 0, "masked material escaped mask")
	_check(selection.call("selection_indices") == PackedInt32Array([target]), "masked material discarded mask")
	undo.undo()
	_check(resource.transparency[target] == 0 and selection.call("selection_indices").is_empty(), "material Undo did not restore/clear")
	# Shape tools use the XZ footprint rather than exact occupied indices.
	selection.call("set_selection", PackedInt32Array([target]))
	await _settle(selection)
	mask.button_pressed = true
	_select_tool(workspace, Model.TOOL_REMOVE)
	_check(not mask.disabled and mask.button_pressed and selection.call("mask_brushes_enabled"), "shape tool did not expose the selected-column footprint")
	workspace.call("_prepare_stroke", Model.TOOL_REMOVE)
	workspace.call("_apply_stroke_centers", _centers(Vector3i(5, 1, 5)))
	workspace.call("_finish_stroke")
	_check(resource.voxels[target] == 0 and resource.voxels[neighbor] == 1, "shape brush escaped the selected-column footprint")
	_check(selection.call("selection_indices").is_empty() and not mask.button_pressed, "shape commit retained stale voxel indices")
	# The same footprint clips newly created relief voxels, not only removals.
	undo.undo()
	selection.call("set_selection", PackedInt32Array([target]))
	await _settle(selection)
	mask.button_pressed = true
	_select_tool(workspace, Model.TOOL_RAISE)
	workspace.call("_prepare_stroke", Model.TOOL_RAISE)
	workspace.call("_apply_stroke_centers", _centers(Vector3i(5, 1, 5)), 1)
	workspace.call("_finish_stroke")
	var target_above := _index(resource, Vector3i(5, 2, 5))
	var neighbor_above := _index(resource, Vector3i(6, 2, 5))
	_check(resource.voxels[target_above] != 0 and resource.voxels[neighbor_above] == 0, "relief extrusion escaped the selected-column footprint")
	# Canceling a live masked edit restores source and keeps the useful mask.
	undo.undo()
	_select_tool(workspace, Model.TOOL_PAINT)
	selection.call("set_selection", PackedInt32Array([target]))
	await _settle(selection)
	mask.button_pressed = true
	var before_cancel := resource.voxels.duplicate()
	workspace.call("_prepare_stroke", Model.TOOL_PAINT)
	workspace.call("_apply_stroke_centers", _centers(Vector3i(5, 1, 5)))
	workspace.call("_cancel_stroke")
	_check(resource.voxels == before_cancel and selection.call("selection_indices") == PackedInt32Array([target]), "cancel cleared mask or kept live change")
	_check(bool(workspace.call("_save")), "save failed")
	var reopened := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(reopened != null and reopened.voxels == resource.voxels and reopened.transparency == resource.transparency, "round trip diverged")
	if "--visual" in OS.get_cmdline_user_args():
		_select_tool(workspace, Model.TOOL_SHELL_RAISE)
		selection.call("set_selection", PackedInt32Array([target]))
		await _settle(selection)
		mask.button_pressed = true
		var scroll := selection.get_parent().get_parent() as ScrollContainer
		scroll.ensure_control_visible(selection)
		workspace.call("_fit_camera_to_surface")
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://ember_selection_mask_test.png")
		print("VISUAL: ", ProjectSettings.globalize_path("user://ember_selection_mask_test.png"))
	workspace.free()
	undo.clear_history()
	undo.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	for error in errors:
		printerr(error)
	if errors.is_empty():
		print("PASS selection mask: exact paint/material, column-shape footprint, lifecycle and save")
	quit(0 if errors.is_empty() else 1)


func _select_tool(workspace: Control, tool_id: int) -> void:
	_check(bool(workspace.call("_activate_tool_id", tool_id)), "tool not found %d" % tool_id)


func _settle(panel: VBoxContainer) -> void:
	for frame in 300:
		if not panel.call("busy"):
			return
		await process_frame
	_check(false, "overlay did not settle")


func _fixture() -> EmberVoxelModelResource:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "selection_mask_test"
	resource.display_name = "Маска кисти · тест"
	resource.height_voxels = 4
	resource.palette = PackedColorArray([Color.TRANSPARENT, Color(0.2, 0.6, 0.3), Color(0.8, 0.35, 0.2)])
	var size := resource.grid_size()
	resource.voxels.resize(size.x * size.y * size.z)
	for z in range(2, 15):
		for x in range(2, 15):
			resource.voxels[Model.index_of(Vector3i(x, 1, z), size)] = 1
	resource.transparency.resize(resource.voxels.size())
	return resource


func _index(resource: EmberVoxelModelResource, cell: Vector3i) -> int:
	return Model.index_of(cell, resource.grid_size())


func _centers(cell: Vector3i) -> Array[Vector3i]:
	return [cell]


func _check(condition: bool, message: String) -> void:
	if not condition and message not in errors:
		errors.append(message)
