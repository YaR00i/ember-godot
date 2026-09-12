extends SceneTree
## Disposable authoring gate: exercises real workspace controls and fill commit,
## never opens or saves a user's map.

const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const BrushProfiles = preload("res://addons/ember_import/ember_voxel_brush_profiles.gd")
const EditorViewStore = preload("res://addons/ember_import/ember_surface_editor_view_store.gd")
const TEMP_PATH := "user://ember_canvas_workflow_test.tres"
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	if "--wide" in OS.get_cmdline_user_args():
		root.size = Vector2i(1600, 900)
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null, undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var first := _bowl("first")
	var second := _bowl("second")
	workspace.open_surface(first, TEMP_PATH, Rect2i(0, 0, 1, 1))
	for frame in 5:
		await process_frame
	var original := first.voxels.duplicate()
	var migrated_direction := BrushProfiles.normalize_profile({"follow_surface":false})
	_check(bool(migrated_direction.follow_surface), "legacy first-face default was not migrated to surface following")
	var explicit_single_face := BrushProfiles.normalize_profile({
		"follow_surface":false,
		"direction_behavior_version":BrushProfiles.DIRECTION_BEHAVIOR_VERSION,
	})
	_check(not bool(explicit_single_face.follow_surface), "explicit single-face mode was not preserved")
	# Click a real viewport coordinate over the bed. Tint uses the existing
	# palette channel, not a second water material or terrain replacement.
	var tint: OptionButton = workspace.get("_surface_fill_tint")
	tint.select(2)
	var camera: Camera3D = workspace.get("_camera")
	var viewport: SubViewport = workspace.get("_viewport")
	var container: SubViewportContainer = workspace.get("_viewport_container")
	var screen := camera.unproject_position(Vector3(0.53, 1.0 / 16.0, 0.53))
	screen *= container.size / Vector2(viewport.size)
	workspace.call("_apply_surface_fill_click", screen)
	_check(first.surface_fill_materials.count(1) > 0, "viewport fill did not find the basin")
	_check(first.surface_fill_palette.count(2) > 0, "selected tint did not reach fill data")
	_check(first.voxels == original, "water fill modified the authored bed")
	var has_native_water_surface := false
	var water_maximum := Vector2.ZERO
	for visual in (workspace.get("_chunk_meshes") as Dictionary).values():
		var chunk := visual as MeshInstance3D
		if chunk == null or chunk.mesh == null:
			continue
		for surface_index in chunk.mesh.get_surface_count():
			if chunk.mesh.surface_get_name(surface_index) == "water":
				has_native_water_surface = true
				var arrays := chunk.mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					var projected := chunk.transform * vertex
					water_maximum.x = maxf(water_maximum.x, projected.x)
					water_maximum.y = maxf(water_maximum.y, projected.z)
	_check(has_native_water_surface, "native terrain preview omitted the canonical fill-water overlay")
	_check(
		water_maximum.x > 0.5 and water_maximum.y > 0.5,
		"native terrain preview displaced or shrank the fill-water geometry",
	)
	if "--visual-water" in OS.get_cmdline_user_args():
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://ember_canvas_water_test.png")
		print("VISUAL WATER: ", ProjectSettings.globalize_path("user://ember_canvas_water_test.png"))
	var water := first.surface_fill_materials.duplicate()
	var colors := first.surface_fill_palette.duplicate()
	undo.undo()
	_check(first.surface_fill_materials.is_empty(), "Undo did not remove the fill")
	undo.redo()
	_check(first.surface_fill_palette == colors, "Redo lost water tint")
	_check(workspace.has_unsaved_changes(), "fill not marked unsaved")
	workspace.open_surface(first, TEMP_PATH)
	_check(workspace.has_unsaved_changes(), "opening same surface reset saved baseline")
	var guard: ConfirmationDialog = workspace.get("_navigation_guard")
	workspace.open_surface(second, "")
	_check(guard.visible and workspace.get("_resource") == first, "dirty navigation was not intercepted")
	guard.canceled.emit()
	guard.hide()
	_check(first.surface_fill_materials == water, "cancel discarded the draft")
	workspace.open_surface(second, "")
	guard.call("_save_and_continue")
	_check(not guard.visible and workspace.get("_resource") == second, "save-and-open did not navigate")
	var saved := ResourceLoader.load(TEMP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(saved != null and saved.surface_fill_palette == colors, "save/reopen lost tint")
	_check(saved != null and saved.voxels == original, "save/reopen changed bed")
	# A valid draft without a save destination must survive a failed Save.
	second.voxels[0] = 2
	workspace.open_surface(first, TEMP_PATH)
	guard.call("_save_and_continue")
	_check(guard.visible and workspace.get("_resource") == second, "failed save closed the draft")
	_check(second.voxels[0] == 2, "failed save lost the draft")
	guard.call("_custom_action", &"discard")
	_check(second.voxels[0] == 1, "discard did not restore shared Resource in place")
	_check(workspace.get("_resource") == first, "discard-and-open failed")
	_check(not workspace.has_unsaved_changes(), "saved surface reopened dirty")
	workspace.call("_on_view_action", Workspace.ViewAction.GRID_OVERLAY)
	workspace.call("_on_view_action", Workspace.ViewAction.REGION_OVERLAY)
	_check(not (workspace.get("_grid") as MeshInstance3D).visible, "grid toggle did not hide grid")
	var layers: OptionButton = workspace.get("_surface_layer_view")
	layers.select(1)
	workspace.call("_on_surface_layer_view_changed", 1)
	_check(first.surface_fill_materials == water, "bed-only view deleted water")
	_check(not workspace.has_unsaved_changes(), "view settings dirtied resource")
	var remembered_target := Vector3(0.35, 0.22, 0.70)
	workspace.set("_yaw", 0.31)
	workspace.set("_pitch", -0.73)
	workspace.set("_ortho_size", 7.25)
	workspace.set("_camera_fit_margin", 1.35)
	workspace.set("_camera_target", remembered_target)
	workspace.set("_edit_region_blocks", Rect2i(0, 0, 1, 1))
	workspace.call("_on_height_slice_changed", true, 4)
	workspace.open_surface(second, "")
	workspace.open_surface(first, TEMP_PATH)
	_check(is_equal_approx(float(workspace.get("_yaw")), 0.31), "resource switch lost remembered camera yaw")
	_check(is_equal_approx(float(workspace.get("_ortho_size")), 7.25), "resource switch lost remembered camera zoom")
	_check((workspace.get("_camera_target") as Vector3).is_equal_approx(remembered_target), "resource switch lost remembered camera target")
	_check(workspace.get("_edit_region_blocks") == Rect2i(0, 0, 1, 1), "resource switch lost remembered edit region")
	_check(int(workspace.get("_slice_height")) == 4, "resource switch lost remembered height slice")
	_check(not bool(workspace.get("_show_grid")) and not bool(workspace.get("_show_region")), "resource switch lost remembered overlays")
	_check(str(layers.get_item_metadata(layers.selected)) == "floor", "resource switch lost remembered layer view")
	_check(not workspace.has_unsaved_changes(), "restored editor view dirtied resource")
	var exported_views := workspace.export_editor_view_data()
	var restored_store := EditorViewStore.new()
	restored_store.import_data(exported_views)
	var persisted_view := restored_store.recall(TEMP_PATH)
	_check(not persisted_view.is_empty(), "editor layout export lost per-resource view")
	_check(persisted_view.get("edit_region") == Rect2i(0, 0, 1, 1), "editor layout round-trip lost region")
	_check(int(persisted_view.get("slice_height", -1)) == 4, "editor layout round-trip lost slice")
	_check(str(persisted_view.get("layer_view", "")) == "floor", "editor layout round-trip lost layer")
	workspace.call("_activate_tool_id", Model.TOOL_ADD)
	var radius: OptionButton = workspace.get("_radius")
	var depth: SpinBox = workspace.get("_depth")
	var follow: CheckButton = workspace.get("_follow_surface")
	var application: OptionButton = workspace.get("_application_mode")
	var shape: OptionButton = workspace.get("_brush_shape")
	radius.select(1)
	depth.value = 5
	follow.button_pressed = true
	workspace.call("_select_option_metadata", application, "line")
	workspace.call("_select_option_metadata", shape, "square")
	workspace.call("_on_brush_setting_changed")
	workspace.call("_activate_tool_id", Model.TOOL_PAINT)
	radius.select(4)
	depth.value = 3
	follow.button_pressed = false
	workspace.call("_select_option_metadata", application, "point")
	workspace.call("_select_option_metadata", shape, "circle")
	workspace.call("_on_brush_setting_changed")
	workspace.call("_activate_tool_id", Model.TOOL_SMOOTH)
	var smooth_mode: OptionButton = workspace.get("_smooth_mode")
	var smooth_fill_pits: CheckButton = workspace.get("_smooth_fill_pits")
	workspace.call("_select_option_metadata", smooth_mode, BrushProfiles.SMOOTH_COMMON)
	smooth_fill_pits.button_pressed = false
	workspace.call("_on_brush_setting_changed")
	workspace.call("_activate_tool_id", Model.TOOL_RAISE)
	var relief_mode: OptionButton = workspace.get("_relief_mode")
	var relief_style: OptionButton = workspace.get("_relief_generator_style")
	var relief_direction: OptionButton = workspace.get("_relief_generator_direction")
	var relief_scale: OptionButton = workspace.get("_relief_generator_scale")
	var relief_detail: OptionButton = workspace.get("_relief_generator_detail")
	workspace.call("_select_option_metadata", relief_mode, BrushProfiles.RELIEF_GENERATOR)
	workspace.call("_select_option_metadata", relief_style, BrushProfiles.RELIEF_RIDGES)
	workspace.call("_select_option_metadata", relief_direction, -1)
	workspace.call("_select_option_metadata", relief_scale, 32)
	workspace.call("_select_option_metadata", relief_detail, 0)
	workspace.set("_relief_seed_value", 11)
	workspace.call("_on_brush_setting_changed")
	var profile_export := workspace.export_editor_view_data()
	var profile_store := EditorViewStore.new()
	profile_store.import_data(profile_export)
	var profiles := profile_store.recall_brush_profiles()
	var add_profile: Dictionary = profiles.get(Model.TOOL_ADD, {})
	var paint_profile: Dictionary = profiles.get(Model.TOOL_PAINT, {})
	var smooth_profile: Dictionary = profiles.get(Model.TOOL_SMOOTH, {})
	var relief_profile: Dictionary = profiles.get(Model.TOOL_RAISE, {})
	_check(int(add_profile.get("radius", 0)) == 2, "tool profile lost Add radius")
	_check(int(add_profile.get("depth", 0)) == 5, "tool profile lost Add depth")
	_check(bool(add_profile.get("follow_surface", false)), "tool profile lost Add direction mode")
	_check(str(add_profile.get("application", "")) == "line", "tool profile lost Add application mode")
	_check(str(add_profile.get("shape", "")) == "square", "tool profile lost Add footprint shape")
	_check(int(paint_profile.get("radius", 0)) == 8, "tool profile lost Paint radius")
	_check(int(paint_profile.get("depth", 0)) == 3, "tool profile lost Paint depth")
	_check(str(paint_profile.get("application", "")) == "point", "tool profile lost Paint application mode")
	_check(str(smooth_profile.get("smooth_mode", "")) == BrushProfiles.SMOOTH_COMMON, "tool profile lost Common Smooth mode")
	_check(not bool(smooth_profile.get("smooth_fill_pits", true)), "tool profile lost the Smooth pits toggle")
	_check(str(relief_profile.get("relief_mode", "")) == BrushProfiles.RELIEF_GENERATOR, "tool profile lost generative Relief mode")
	_check(str(relief_profile.get("relief_style", "")) == BrushProfiles.RELIEF_RIDGES, "tool profile lost generative Relief style")
	_check(int(relief_profile.get("relief_generator_direction", 0)) == -1, "tool profile lost generative Relief direction")
	_check(int(relief_profile.get("relief_scale", 0)) == 32 and int(relief_profile.get("relief_detail", -1)) == 0, "tool profile lost light generative Relief shape controls")
	_check(int(relief_profile.get("relief_seed", 0)) == 11, "tool profile lost generative Relief variant")
	_check(not workspace.has_unsaved_changes(), "editor-only brush profiles dirtied the voxel Resource")
	workspace.call("_on_height_slice_changed", false, -1)
	workspace.call("_activate_tool_id", Model.TOOL_REMOVE)
	radius.select(0)
	depth.value = 2
	follow.button_pressed = false
	workspace.call("_select_option_metadata", application, "stroke")
	workspace.call("_on_brush_setting_changed")
	var brush_before := first.voxels.duplicate()
	var brush_center := Vector3i(0, 5, 8)
	workspace.call("_prepare_stroke", Model.TOOL_REMOVE)
	var fixed_segment: Array[Dictionary] = [{
		"centers": [brush_center],
		"normal": Vector3i.UP,
	}]
	workspace.call("_apply_oriented_stroke_segments", fixed_segment)
	workspace.call("_apply_oriented_stroke_segments", fixed_segment)
	var brush_size := first.grid_size()
	_check(first.voxels[Model.index_of(brush_center, brush_size)] == 0, "workspace fixed brush did not remove the visible voxel")
	_check(first.voxels[Model.index_of(brush_center - Vector3i.UP, brush_size)] == 0, "workspace fixed brush ignored selected depth")
	_check(first.voxels[Model.index_of(brush_center - Vector3i.UP * 2, brush_size)] != 0, "same-gesture revisit accumulated a hidden third layer")
	workspace.call("_finish_stroke")
	undo.undo()
	_check(first.voxels == brush_before, "one Undo did not restore the complete fixed-depth gesture")
	depth.value = 1
	workspace.call("_select_option_metadata", application, "line")
	workspace.call("_select_option_metadata", shape, "square")
	workspace.call("_on_brush_setting_changed")
	var line_before := first.voxels.duplicate()
	var line_a := Vector3i(0, 5, 6)
	var line_b := Vector3i(0, 5, 10)
	_check(bool(workspace.call("_begin_precision_line", line_a, Vector3i.UP)), "precision line could not set point A")
	var line_b_world := Vector3(
		(float(line_b.x) + 0.5) / 16.0,
		float(line_b.y + 1) / 16.0,
		(float(line_b.z) + 0.5) / 16.0,
	)
	var line_b_screen := camera.unproject_position(line_b_world)
	line_b_screen *= container.size / Vector2(viewport.size)
	_check(workspace.call("_precision_line_target_at", line_b_screen) == line_b, "screen ray did not stay on the first-face line plane")
	_check(bool(workspace.call("_set_precision_line_target", line_b)), "precision line could not set point B")
	_check(first.voxels == line_before, "precision preview mutated voxel data before commit")
	_check((workspace.get("_precision_line_preview_indices") as PackedInt32Array).size() == 5, "precision preview does not match the five-voxel line")
	if "--visual-precision" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		workspace.set("_ortho_size", 1.8)
		workspace.set("_camera_target", Vector3(0.5, 0.18, 0.5))
		workspace.call("_update_camera")
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://ember_precision_line_preview.png")
		print("VISUAL PRECISION LINE: ", ProjectSettings.globalize_path("user://ember_precision_line_preview.png"))
	_check(bool(workspace.call("_commit_precision_line")), "precision line did not commit")
	for z in range(line_a.z, line_b.z + 1):
		_check(first.voxels[Model.index_of(Vector3i(0, 5, z), brush_size)] == 0, "precision line left a gap at Z%d" % z)
	undo.undo()
	_check(first.voxels == line_before, "one Undo did not restore the precision line")
	workspace.call("_select_option_metadata", application, "point")
	workspace.call("_on_brush_setting_changed")
	var point_cell := Vector3i(0, 5, 8)
	var point_world := Vector3(
		(float(point_cell.x) + 0.5) / 16.0,
		float(point_cell.y + 1) / 16.0,
		(float(point_cell.z) + 0.5) / 16.0,
	)
	var point_screen := camera.unproject_position(point_world)
	point_screen *= container.size / Vector2(viewport.size)
	var point_click := InputEventMouseButton.new()
	point_click.button_index = MOUSE_BUTTON_LEFT
	point_click.pressed = true
	point_click.position = point_screen
	workspace.call("_on_viewport_input", point_click)
	_check(first.voxels[Model.index_of(point_cell, brush_size)] == 0, "point mode did not apply one exact click")
	_check(not bool(workspace.get("_stroke_active")), "point mode left a drag gesture active")
	undo.undo()
	_check(first.voxels == line_before, "Undo did not restore the point application")
	workspace.call("_activate_tool_id", Model.TOOL_RAISE)
	var height_limit: OptionButton = workspace.get("_height_limit")
	workspace.call("_select_option_metadata", height_limit, 8)
	var relief_before := first.voxels.duplicate()
	var relief_heights := Model.column_heights(relief_before, brush_size)
	var relief_a := Vector3i(8, int(relief_heights[8 + 8 * brush_size.x]), 8)
	var relief_b := Vector3i(12, int(relief_heights[12 + 8 * brush_size.x]), 8)
	var relief_a_world := Vector3(
		(float(relief_a.x) + 0.5) / 16.0,
		float(relief_a.y + 1) / 16.0,
		(float(relief_a.z) + 0.5) / 16.0,
	)
	var relief_b_world := Vector3(
		(float(relief_b.x) + 0.5) / 16.0,
		float(relief_b.y + 1) / 16.0,
		(float(relief_b.z) + 0.5) / 16.0,
	)
	var relief_a_screen := camera.unproject_position(relief_a_world) * container.size / Vector2(viewport.size)
	var relief_b_screen := camera.unproject_position(relief_b_world) * container.size / Vector2(viewport.size)
	workspace.call("_begin_stroke", relief_a_screen)
	var relief_first_dab := first.voxels.duplicate()
	workspace.call("_extend_stroke", relief_a_screen, true)
	_check(first.voxels == relief_first_dab, "Relief motion inside one voxel jumped past timed buildup")
	workspace.call("_extend_stroke", relief_b_screen, true)
	workspace.call("_extend_stroke", relief_a_screen, true)
	var revisited_center := workspace.get("_relief_hold_center") as Vector3i
	var revisit_top := int(Model.column_heights(first.voxels, brush_size)[revisited_center.x + revisited_center.z * brush_size.x])
	var baseline_revisit_top := int(relief_heights[revisited_center.x + revisited_center.z * brush_size.x])
	_check(revisit_top == baseline_revisit_top + 2, "Relief revisit did not add one predictable buildup dose")
	workspace.call("_finish_stroke")
	undo.undo()
	_check(first.voxels == relief_before, "one Undo did not restore the stable Relief gesture")
	workspace.call("_select_option_metadata", relief_mode, BrushProfiles.RELIEF_GENERATOR)
	workspace.call("_select_option_metadata", relief_style, BrushProfiles.RELIEF_SOIL)
	workspace.call("_select_option_metadata", relief_direction, 0)
	workspace.call("_select_option_metadata", relief_scale, 16)
	workspace.call("_select_option_metadata", relief_detail, 3)
	workspace.set("_relief_seed_value", 7)
	workspace.call("_on_brush_setting_changed")
	var generated_before := first.voxels.duplicate()
	workspace.call("_begin_stroke", relief_a_screen)
	workspace.call("_extend_stroke", relief_b_screen, true)
	workspace.call("_finish_stroke")
	_check(first.voxels != generated_before, "workspace generative Relief produced no changes")
	undo.undo()
	_check(first.voxels == generated_before, "one Undo did not restore generative Relief")
	workspace.set("_pitch", deg_to_rad(-48.0))
	workspace.call("_update_camera")
	var pan_target_before: Vector3 = workspace.get("_camera_target")
	workspace.call("_pan_camera", Vector2(0.0, 40.0))
	var pan_target_after: Vector3 = workspace.get("_camera_target")
	_check(not is_equal_approx(pan_target_after.y, pan_target_before.y), "screen-plane MMB pan still locks vertical movement")
	var zoom_target_before: Vector3 = workspace.get("_camera_target")
	var zoom_before := float(workspace.get("_ortho_size"))
	workspace.call("_zoom_camera_at", Vector2(container.size.x * 0.8, container.size.y * 0.3), 0.8)
	_check(float(workspace.get("_ortho_size")) < zoom_before, "cursor-anchored camera zoom did not change scale")
	_check(not (workspace.get("_camera_target") as Vector3).is_equal_approx(zoom_target_before), "off-center zoom did not preserve the cursor anchor")
	var normalized_view := EditorViewStore.normalize({
		"pitch": INF,
		"ortho_size": 500.0,
		"camera_target": Vector3(INF, 0.0, 0.0),
		"layer_view": "unknown",
	})
	_check(is_finite(float(normalized_view.pitch)), "view validation retained a non-finite camera value")
	_check(is_equal_approx(float(normalized_view.ortho_size), 128.0), "view validation did not clamp camera zoom")
	_check(normalized_view.camera_target == Vector3.ZERO, "view validation retained a non-finite target")
	_check(str(normalized_view.layer_view) == "combined", "view validation retained an unknown layer")
	var below_view := EditorViewStore.normalize({"pitch":deg_to_rad(72.0)})
	_check(is_equal_approx(float(below_view.pitch),deg_to_rad(72.0)), "view validation still prevents inspecting the model from below")
	var bounded_store := EditorViewStore.new()
	for index in EditorViewStore.MAX_ENTRIES + 3:
		bounded_store.remember("res://surface_%d.tres" % index, {})
	_check(bounded_store.recall("res://surface_0.tres").is_empty(), "view store did not evict its oldest resource")
	_check(not bounded_store.recall("res://surface_34.tres").is_empty(), "view store evicted its most recent resource")

	# Leaving the main screen uses the same data owner but close-specific labels
	# and callbacks. Cancel retains the draft, Save and Discard may continue.
	var close_flags := {"continued": 0, "cancelled": 0}
	first.voxels[0] = 2
	workspace.request_close(
		func() -> void: close_flags.continued += 1,
		func() -> void: close_flags.cancelled += 1,
	)
	_check(guard.visible and guard.get_ok_button().text == "Сохранить и закрыть", "close lifecycle did not open its Save/Discard/Cancel guard")
	guard.canceled.emit()
	guard.hide()
	_check(close_flags.cancelled == 1 and close_flags.continued == 0, "close Cancel did not stay in Canvas")
	_check(first.voxels[0] == 2 and workspace.has_unsaved_changes(), "close Cancel lost the draft")
	workspace.request_close(
		func() -> void: close_flags.continued += 1,
		func() -> void: close_flags.cancelled += 1,
	)
	guard.call("_save_and_continue")
	_check(close_flags.continued == 1 and not workspace.has_unsaved_changes(), "close Save did not persist and continue")
	first.voxels[0] = 1
	workspace.request_close(
		func() -> void: close_flags.continued += 1,
		func() -> void: close_flags.cancelled += 1,
	)
	guard.call("_custom_action", &"discard")
	_check(close_flags.continued == 2 and first.voxels[0] == 2, "close Discard did not restore the saved bytes and continue")
	var no_path := _bowl("no_path")
	workspace.open_surface(no_path, "")
	no_path.voxels[0] = 2
	workspace.request_close(
		func() -> void: close_flags.continued += 1,
		func() -> void: close_flags.cancelled += 1,
	)
	guard.call("_save_and_continue")
	_check(guard.visible and close_flags.continued == 2, "failed close Save allowed navigation")
	_check(no_path.voxels[0] == 2 and workspace.has_unsaved_changes(), "failed close Save lost the pathless draft")
	guard.call("_custom_action", &"discard")
	_check(close_flags.continued == 3 and no_path.voxels[0] == 1, "pathless close Discard did not restore baseline")
	workspace.open_surface(first, TEMP_PATH)
	var plugin_source := FileAccess.get_file_as_string("res://addons/ember_surface_canvas/plugin.gd")
	_check("func _get_unsaved_status" in plugin_source and "func _save_external_data" in plugin_source, "main-screen plugin is not wired into Godot external-data lifecycle")
	# Restore the original fixture baseline for the held-stroke visibility gate.
	first.voxels[0] = original[0]
	workspace.call("_save")
	# Leaving Canvas cannot keep a held sculpt brush running while hidden.
	workspace.call("_prepare_stroke", Model.TOOL_ADD)
	first.voxels[0] = 2
	workspace.set("_stroke_changes", {0: 2})
	workspace.hide()
	_check(not bool(workspace.get("_stroke_active")), "hidden workspace retained a live gesture")
	undo.undo()
	_check(first.voxels == original, "hiding workspace did not commit one undoable stroke")
	workspace.show()
	if "--visual" in OS.get_cmdline_user_args():
		var tool: ItemList = workspace.get("_tool")
		for item in tool.item_count:
			if int(tool.get_item_metadata(item)) == Model.TOOL_SURFACE_FILL:
				tool.select(item)
				workspace.call("_on_tool_selected", item)
		layers.select(0)
		workspace.call("_on_surface_layer_view_changed", 0)
		for frame in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://ember_canvas_workflow_test.png")
		print("VISUAL: ", ProjectSettings.globalize_path("user://ember_canvas_workflow_test.png"))
		first.voxels[0] = 2
		workspace.request_close(func() -> void: pass, func() -> void: pass)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://ember_surface_close_lifecycle_test.png")
		print("VISUAL CLOSE: ", ProjectSettings.globalize_path("user://ember_surface_close_lifecycle_test.png"))
		guard.call("_custom_action", &"discard")
	workspace.free()
	undo.clear_history()
	undo.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
	if errors.is_empty():
		print("PASS Surface Canvas: precision point/line, fill tint, Undo/Redo, save/reopen, navigation + close guards, remembered editor view")
	else:
		for error in errors:
			printerr(error)
	quit(0 if errors.is_empty() else 1)


func _bowl(id: String) -> EmberVoxelModelResource:
	var surface := EmberVoxelModelResource.new()
	surface.model_id = "canvas_workflow_" + id
	surface.display_name = "Тестовый пруд · " + id
	surface.voxels_per_block = 16
	surface.size_blocks = Vector3i.ONE
	surface.height_voxels = 8
	surface.palette = PackedColorArray([Color.TRANSPARENT, Color(0.5, 0.65, 0.3), Color(0.15, 0.6, 0.72)])
	var size := surface.grid_size()
	surface.voxels.resize(size.x * size.y * size.z)
	for z in size.z:
		for x in size.x:
			var height := 6 if x < 2 or x > 13 or z < 2 or z > 13 else 1
			for y in height:
				surface.voxels[Model.index_of(Vector3i(x, y, z), size)] = 1
	return surface


func _check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
