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
	selection.call("set_selection", PackedInt32Array([target]), Color(1, 0.45, 0.05, 0.45), Vector3i.UP, true)
	await _settle(selection)
	mask.button_pressed = true
	undo.undo()
	_check(not mask.button_pressed and selection.call("selection_indices") == PackedInt32Array([target]), "Undo did not revert enabling the mask")
	undo.redo()
	_check(mask.button_pressed and selection.call("allows_brush_index", target), "Redo did not restore enabled mask snapshot")
	selection.call("set_selection", PackedInt32Array([target, far]), Color(1, 0.45, 0.05, 0.45), Vector3i.UP, true)
	await _settle(selection)
	undo.undo()
	_check(selection.call("selection_indices") == PackedInt32Array([target]) and selection.call("allows_brush_index", target) and not selection.call("allows_brush_index", far), "Undo did not restore previous mask edit")
	undo.redo()
	_check(selection.call("selection_indices") == PackedInt32Array([target, far]) and selection.call("allows_brush_index", far), "Redo did not restore edited mask")
	workspace.call("_select_palette_color", 2)
	workspace.call("_prepare_stroke", Model.TOOL_PAINT)
	workspace.call("_apply_oriented_stroke_segments", _oriented_segment(Vector3i(5, 1, 5)))
	workspace.call("_finish_stroke")
	_check(resource.voxels[target] == 2 and resource.voxels[neighbor] == 1 and resource.voxels[far] == 1, "masked paint escaped mask or painted untouched member")
	_check(selection.call("selection_indices") == PackedInt32Array([target, far]) and mask.button_pressed, "masked paint discarded mask")
	undo.undo()
	_check(resource.voxels == original and selection.call("selection_indices").is_empty(), "paint Undo did not restore source/clear transient selection")
	_check(mask.button_pressed and selection.call("mask_brushes_enabled"), "paint Undo discarded the independent mask snapshot")
	_check(selection.call("allows_brush_index", target) and selection.call("allows_brush_index", far) and not selection.call("allows_brush_index", neighbor), "paint Undo changed exact mask membership")
	undo.redo()
	_check(resource.voxels[target] == 2 and resource.voxels[neighbor] == 1, "paint Redo escaped mask")
	_check(mask.button_pressed and selection.call("mask_brushes_enabled"), "paint Redo discarded mask")
	# Material uses the exact same independent snapshot across commit and Undo.
	_select_tool(workspace, Model.TOOL_MATERIAL)
	selection.call("set_selection", PackedInt32Array([target]))
	await _settle(selection)
	mask.button_pressed = true
	workspace.call("_prepare_stroke", Model.TOOL_MATERIAL)
	workspace.call("_apply_oriented_stroke_segments", _oriented_segment(Vector3i(5, 1, 5)))
	workspace.call("_finish_stroke")
	_check(resource.transparency[target] == 208 and resource.transparency[neighbor] == 0, "masked material escaped mask")
	_check(selection.call("selection_indices") == PackedInt32Array([target]), "masked material discarded mask")
	undo.undo()
	_check(resource.transparency[target] == 0 and selection.call("selection_indices").is_empty(), "material Undo did not restore/clear transient selection")
	_check(mask.button_pressed and selection.call("mask_brushes_enabled") and selection.call("allows_brush_index", target), "material Undo discarded exact mask")
	# Shape tools keep and reuse the XZ footprint after transient voxel indices stale.
	selection.call("set_selection", PackedInt32Array([target, far]))
	await _settle(selection)
	_select_tool(workspace, Model.TOOL_REMOVE)
	_check(not mask.disabled and mask.button_pressed and selection.call("mask_brushes_enabled"), "shape tool did not expose the selected-column footprint")
	workspace.call("_prepare_stroke", Model.TOOL_REMOVE)
	workspace.call("_apply_oriented_stroke_segments", _oriented_segment(Vector3i(5, 1, 5)))
	workspace.call("_finish_stroke")
	_check(resource.voxels[target] == 0 and resource.voxels[neighbor] == 1, "shape brush escaped the selected-column footprint")
	_check(selection.call("selection_indices").is_empty() and mask.button_pressed and selection.call("mask_brushes_enabled"), "shape commit did not separate stale selection from persistent mask")
	workspace.call("_prepare_stroke", Model.TOOL_REMOVE)
	workspace.call("_apply_oriented_stroke_segments", _oriented_segment(Vector3i(12, 1, 12)))
	workspace.call("_finish_stroke")
	_check(resource.voxels[far] == 0 and resource.voxels[neighbor] == 1, "second shape stroke did not reuse mask or escaped it")
	undo.undo()
	_check(resource.voxels[far] != 0 and resource.voxels[target] == 0 and mask.button_pressed, "shape Undo did not restore second stroke/preserve mask")
	undo.undo()
	_check(resource.voxels[target] != 0 and mask.button_pressed and selection.call("mask_brushes_enabled"), "shape Undo did not restore first stroke/preserve mask")
	# The same persisted footprint clips newly created relief voxels after a tool switch.
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
	workspace.call("_apply_oriented_stroke_segments", _oriented_segment(Vector3i(5, 1, 5)))
	workspace.call("_cancel_stroke")
	_check(resource.voxels == before_cancel and selection.call("selection_indices") == PackedInt32Array([target]), "cancel cleared selection or kept live change")
	_check(mask.button_pressed and selection.call("mask_brushes_enabled"), "cancel cleared independent mask")
	# Selection mode shows filled voxels; sculpt mode replaces them with a thin outline.
	selection.call("set_selection", PackedInt32Array([target, neighbor]))
	await _settle(selection)
	_select_tool(workspace, Model.TOOL_REMOVE)
	selection.call("set_active", false)
	var overlay := selection.get("_overlay") as MultiMeshInstance3D
	var outline := selection.get("_mask_outline") as MeshInstance3D
	_check(not overlay.visible and outline.visible and outline.mesh != null and outline.mesh.get_surface_count() > 0, "sculpt mode did not replace filled mask overlay with contour")
	var outline_arrays := outline.mesh.surface_get_arrays(0)
	_check((outline_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 12, "column contour retained the shared interior edge")
	workspace.call("_switch_canvas_mode", Workspace.CanvasMode.SELECTION)
	_check(overlay.visible and not outline.visible, "selection mode did not restore filled selection overlay")
	workspace.call("_switch_canvas_mode", Workspace.CanvasMode.BRUSH)
	_check(not overlay.visible and outline.visible, "returning to sculpt mode did not restore contour")
	# Supported tool switches retain the snapshot; explicit clear removes both states.
	_select_tool(workspace, Model.TOOL_PAINT)
	_check(mask.button_pressed and selection.call("mask_brushes_enabled") and outline.visible, "supported tool switch discarded mask snapshot")
	mask.button_pressed = false
	_check(not selection.call("mask_brushes_enabled") and not overlay.visible and not outline.visible, "inactive ordinary selection should stay hidden while sculpting")
	mask.button_pressed = true
	_check(selection.call("mask_brushes_enabled") and not overlay.visible and outline.visible, "re-enabling mask did not reuse saved snapshot")
	_select_tool(workspace, Model.TOOL_SURFACE_FILL)
	_check(mask.button_pressed and not selection.call("mask_brushes_enabled") and not outline.visible, "unsupported tool did not suspend the saved mask")
	_check((selection.get("_status") as Label).text.contains("Маска сохранена"), "suspended mask state is not explained")
	_select_tool(workspace, Model.TOOL_PAINT)
	_check(mask.button_pressed and selection.call("mask_brushes_enabled") and outline.visible, "returning to a compatible brush did not restore the mask")
	# A new selection locks its first face plane; shape masks extrude through that
	# normal and reject movement in either tangent direction.
	var orientation_cell := Vector3i(8, 1, 8)
	for normal in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD]:
		selection.call("set_selection", PackedInt32Array([_index(resource, orientation_cell)]), Color(1, 0.45, 0.05, 0.45), normal)
		_select_tool(workspace, Model.TOOL_REMOVE)
		var axis := 0 if normal.x != 0 else 1 if normal.y != 0 else 2
		var through := orientation_cell
		through[axis] += 1 if orientation_cell[axis] + 1 < resource.grid_size()[axis] else -1
		var tangent := orientation_cell
		var tangent_axis := 1 if axis == 0 else 0
		tangent[tangent_axis] += 1
		_check(selection.call("mask_normal") == normal, "mask lost signed face normal %s" % normal)
		_check(selection.call("allows_brush_index", _index(resource, through)), "mask did not extrude through plane %s" % normal)
		_check(not selection.call("allows_brush_index", _index(resource, tangent)), "mask leaked along tangent for plane %s" % normal)
		_check((selection.get("_status") as Label).text.contains(["YZ", "XZ", "XY"][axis]), "mask status did not expose plane for %s" % normal)
	var side_target_cell := Vector3i(8, 2, 7)
	var side_neighbor_cell := Vector3i(8, 2, 8)
	var side_target := _index(resource, side_target_cell)
	var side_neighbor := _index(resource, side_neighbor_cell)
	selection.call("set_selection", PackedInt32Array([side_target]), Color(1, 0.45, 0.05, 0.45), Vector3i.RIGHT)
	_select_tool(workspace, Model.TOOL_REMOVE)
	var side_vertices := ((selection.get("_mask_outline") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var side_contour_local := true
	for vertex in side_vertices:
		side_contour_local = side_contour_local and vertex.x < 0.7
	_check(side_contour_local, "side contour jumped through empty space to another surface")
	workspace.call("_prepare_stroke", Model.TOOL_REMOVE)
	workspace.call("_apply_oriented_stroke_segments", _oriented_segment_with_normal(side_target_cell, Vector3i.RIGHT))
	workspace.call("_finish_stroke")
	_check(resource.voxels[side_target] == 0 and resource.voxels[side_neighbor] != 0, "side-facing YZ mask did not clip a real horizontal shape stroke")
	undo.undo()
	_check(resource.voxels[side_target] != 0 and selection.call("mask_normal") == Vector3i.RIGHT, "side stroke Undo lost geometry or mask plane")
	# Reproduce an edge-on authoring pick: the ray reports the neighbouring top
	# face, but the active side mask must own the direction and extend +X.
	_select_tool(workspace, Model.TOOL_ADD)
	var ambiguous_pick := {
		"hit": side_target_cell,
		"adjacent": side_target_cell + Vector3i.UP,
		"normal": Vector3i.UP,
		"view_normal": Vector3.UP,
	}
	var masked_normal: Vector3i = workspace.call(
		"_oriented_brush_normal", ambiguous_pick, Vector3i.UP
	)
	_check(masked_normal == Vector3i.RIGHT, "side mask did not override an ambiguous top-face pick")
	var side_extension := side_target_cell + Vector3i.RIGHT
	workspace.call("_prepare_stroke", Model.TOOL_ADD)
	workspace.call(
		"_apply_oriented_stroke_segments",
		_oriented_segment_with_normal(side_extension, masked_normal),
	)
	workspace.call("_finish_stroke")
	_check(resource.voxels[_index(resource, side_extension)] != 0, "masked Add did not extend the selected side outward")
	_check(resource.voxels[_index(resource, side_extension + Vector3i.BACK)] == 0, "masked side extension escaped its YZ footprint")
	undo.undo()
	_check(resource.voxels[_index(resource, side_extension)] == 0, "Undo did not remove the masked side extension")
	_check(bool(workspace.call("_save")), "save failed")
	var reopened := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(reopened != null and reopened.voxels == resource.voxels and reopened.transparency == resource.transparency, "round trip diverged")
	if "--visual" in OS.get_cmdline_user_args():
		_select_tool(workspace, Model.TOOL_SHELL_RAISE)
		var side := PackedInt32Array()
		for y in range(2, 4):
			for z in range(5, 10):
				side.append(_index(resource, Vector3i(8, y, z)))
		selection.call("set_selection", side, Color(1, 0.45, 0.05, 0.45), Vector3i.RIGHT)
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
	selection.call("clear_selection", true)
	_check(not mask.button_pressed and not selection.call("mask_brushes_enabled") and not overlay.visible and outline.mesh == null, "explicit clear did not remove selection and mask snapshot")
	undo.undo()
	_check(mask.button_pressed and selection.call("mask_brushes_enabled") and selection.call("mask_normal") == Vector3i.RIGHT, "Undo did not restore explicitly cleared mask")
	undo.redo()
	_check(not mask.button_pressed and not selection.call("mask_brushes_enabled"), "Redo did not clear mask again")
	selection.call("set_selection", PackedInt32Array([target]))
	await _settle(selection)
	mask.button_pressed = true
	selection.call("sync", resource, Rect2i(Vector2i.ZERO, Vector2i.ONE), -1, workspace.get("_surface_root") as Node3D)
	_check(not mask.button_pressed and not selection.call("mask_brushes_enabled") and outline.mesh == null, "region change did not clear editor-only mask context")
	workspace.free()
	undo.clear_history()
	undo.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	for error in errors:
		printerr(error)
	if errors.is_empty():
		print("PASS selection mask: oriented persistent snapshots, side extension, contour, Undo/Redo and save")
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
	for y in range(1, 4):
		for z in range(5, 10):
			resource.voxels[Model.index_of(Vector3i(8, y, z), size)] = 1
	resource.transparency.resize(resource.voxels.size())
	return resource


func _index(resource: EmberVoxelModelResource, cell: Vector3i) -> int:
	return Model.index_of(cell, resource.grid_size())


func _centers(cell: Vector3i) -> Array[Vector3i]:
	return [cell]


func _oriented_segment(cell: Vector3i) -> Array[Dictionary]:
	return [{"centers": [cell], "normal": Vector3i.UP}]


func _oriented_segment_with_normal(cell: Vector3i, normal: Vector3i) -> Array[Dictionary]:
	return [{"centers": [cell], "normal": normal}]


func _check(condition: bool, message: String) -> void:
	if not condition and message not in errors:
		errors.append(message)
