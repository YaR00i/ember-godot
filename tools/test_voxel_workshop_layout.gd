extends SceneTree

const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")

var failures := 0


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var source: EmberVoxelModelResource = Shapes.build(
		"block", Vector3i(16, 8, 16), 16, Color.SADDLE_BROWN, "workshop_layout", "Причал"
	).source
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null, undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(source, "user://voxel_workshop_layout.tres")
	for frame in 6:
		await process_frame
	var initial_viewport := workspace._viewport_container.size
	check(initial_viewport.x >= 480.0 and initial_viewport.y >= 360.0, "compact Canvas viewport is too small: %s" % initial_viewport)
	check(workspace._tool_rail.visible and workspace._sidebar_panel.visible, "workshop side panels are not visible")
	check(workspace.theme != null and workspace.theme.get_stylebox("normal", "Button") is StyleBoxFlat, "scoped workshop Theme is not applied")
	check(workspace.theme.is_type_variation("WorkshopPrimaryButton", "Button"), "primary button Theme variation is missing")
	check(workspace.theme.is_type_variation("WorkshopSegmentButton", "Button"), "segmented-control Theme variation is missing")
	check(workspace._sidebar_panel.custom_minimum_size.x >= 340.0, "right panel is too narrow for the 125% editor scale")
	check(workspace._sidebar_tabs.get_tab_count() == 3 and workspace._sidebar_tabs.is_tab_hidden(2), "ordinary model hides contextual generator tab")
	check(workspace._sidebar_tabs.get_tab_title(0) == "Части", "parts tab is not first")
	check(workspace._sidebar_tabs.get_tab_title(1) == "Библиотека", "library tab is not second")
	check(workspace._object_name_input != null and not workspace._object_name_input.editable, "surface context must not expose scene-object rename")
	check(workspace._workshop_context_label.text.begins_with("›  Модель Причал"), "model context is not separated from the scene-object field")
	check(workspace._palette_panel.get_parent() == workspace._tool_rail, "palette is not pinned in the left tool rail")
	check(workspace._palette_panel.visible and workspace._palette_panel._swatch_scroll.custom_minimum_size.y <= 80.0, "persistent palette is not compact")
	var first_swatch := workspace._palette_panel._grid.get_child(0) as Button
	check(first_swatch.theme_type_variation == &"WorkshopSwatchButton", "palette swatch is still exposed to editor icon tint")
	for icon_color in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_hover_pressed_color"]:
		check(workspace.theme.get_color(icon_color, &"WorkshopSwatchButton").is_equal_approx(Color.WHITE), "palette swatch tint is not neutral: %s" % icon_color)
	check(workspace._parts_sections.get_tab_count() == 3, "parts panel must be split into selection, groups and view")
	check(workspace._parts_sections.get_tab_title(0) == "Выделение", "selection subsection is not first")
	check(workspace._parts_sections.get_tab_title(1) == "Группы", "groups subsection is missing")
	check(workspace._parts_sections.get_tab_title(2) == "Вид", "view subsection is missing")
	check(workspace.find_child("VoxelWorkshopSelectionTool", true, false) != null, "selection is absent from the primary tool rail")
	check(workspace.find_child("VoxelWorkshopStampTool", true, false) != null, "stamp library is absent from the primary tool rail")
	check(workspace._depth.visible and workspace._depth.value == 1, "fixed brush depth is not visible by default")
	check(workspace._follow_surface.visible and workspace._follow_surface.button_pressed, "surface-following direction is not the default")
	check(workspace._follow_surface.text.contains("по поверхности"), "surface direction label is unclear")
	check(workspace._application_mode.visible and str(workspace._application_mode.get_selected_metadata()) == "stroke", "free stroke is not the default application mode")
	check(workspace._brush_shape.visible and str(workspace._brush_shape.get_selected_metadata()) == "circle", "circle is not the default brush footprint")
	check(workspace._info.text.contains("не наращивает"), "fixed-layer behavior is not explained in the footer")
	workspace._follow_surface.set_pressed_no_signal(false)
	workspace._on_brush_setting_changed()
	check(workspace._follow_surface.text.contains("только одна грань"), "single-face mode is not named honestly")
	check(workspace._info.text.contains("останавливается"), "single-face edge behavior is not explained")
	workspace._follow_surface.set_pressed_no_signal(true)
	workspace._on_brush_setting_changed()
	workspace._select_option_metadata(workspace._application_mode, "line")
	workspace._on_brush_setting_changed()
	check(not workspace._follow_surface.visible, "plane-locked line exposes an incompatible follow-surface switch")
	check(workspace._info.text.contains("кликните A"), "two-point line lifecycle is not explained in the footer")
	workspace._select_option_metadata(workspace._application_mode, "stroke")
	workspace._on_brush_setting_changed()
	workspace._activate_tool_id(Workspace.Model.TOOL_RAISE)
	check(not workspace._depth.visible and not workspace._follow_surface.visible and not workspace._application_mode.visible and not workspace._brush_shape.visible, "relief exposes unrelated precision controls")
	check(workspace._active_tool_label.text.contains("наращивание"), "relief is not explicitly labeled as buildup")
	check(workspace._relief_mode.visible and workspace._buildup_rate.visible and not workspace._relief_generator_style.visible, "buildup Relief controls are not separated from the generator")
	workspace._select_option_metadata(
		workspace._relief_mode, Workspace.BrushProfiles.RELIEF_GENERATOR
	)
	workspace._on_brush_setting_changed()
	check(not workspace._buildup_rate.visible and not workspace._relief_geometry.visible, "generator still exposes buildup-only controls")
	check(workspace._relief_generator_style.visible and workspace._relief_generator_direction.visible and workspace._relief_generator_scale.visible and workspace._relief_generator_detail.visible and workspace._relief_variant_button.visible, "generative Relief controls are incomplete")
	check(workspace._relief_generator_detail.get_item_metadata(0) == 0, "generative Relief is missing the light detail option")
	check(workspace._relief_generator_detail.get_selected_metadata() == 3, "light detail unexpectedly replaced the established default")
	check(workspace._active_tool_label.text.contains("генератор") and workspace._info.text.contains("координатах модели"), "generative Relief behavior is not explained")
	workspace._select_option_metadata(workspace._relief_generator_detail, 0)
	workspace._on_brush_setting_changed()
	check(workspace._info.text.contains("редкие мягкие перепады"), "light generative Relief behavior is not explained")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for frame in 3:
			await process_frame
		var relief_capture := "user://voxel_workshop_relief_generator_1280.png"
		root.get_texture().get_image().save_png(relief_capture)
		print("WORKSHOP_RELIEF_GENERATOR_CAPTURE ", ProjectSettings.globalize_path(relief_capture))
	workspace._activate_tool_id(Workspace.Model.TOOL_SMOOTH)
	check(workspace._smooth_mode.visible and not workspace._smooth_fill_pits.visible, "Smooth mode controls do not start in the compatible Steps mode")
	workspace._select_option_metadata(workspace._smooth_mode, Workspace.BrushProfiles.SMOOTH_COMMON)
	workspace._on_brush_setting_changed()
	check(workspace._smooth_fill_pits.visible and workspace._smooth_fill_pits.button_pressed, "Common Smooth does not expose the enabled pits toggle")
	check(workspace._active_tool_label.text.contains("общий уровень") and workspace._info.text.contains("ямки"), "Common Smooth behavior is not explained in the active tool help")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for frame in 3:
			await process_frame
		var smooth_1280_capture := "user://voxel_workshop_smooth_1280.png"
		root.get_texture().get_image().save_png(smooth_1280_capture)
		print("WORKSHOP_SMOOTH_1280_CAPTURE ", ProjectSettings.globalize_path(smooth_1280_capture))
	workspace._activate_tool_id(Workspace.Model.TOOL_ADD)
	check(workspace._info.get_parent().name == "VoxelWorkshopFooter", "context help still occupies the right panel")
	check(not workspace._stamp_panel._create_panel.visible, "new-stamp form must be collapsed by default")
	workspace._stamp_panel._create_toggle.button_pressed = true
	check(workspace._stamp_panel._create_panel.visible, "new-stamp button does not reveal the creation form")
	workspace._stamp_panel._create_toggle.button_pressed = false
	check(not workspace._stamp_panel._create_panel.visible, "new-stamp form does not collapse")
	check(workspace._stamp_panel._library_actions.get_parent() == workspace._stamp_panel, "library actions must stay outside the scrolling card area")
	workspace._stamp_panel.directory = "user://empty_workshop_library_%d" % Time.get_ticks_usec()
	workspace._stamp_panel.refresh_library()
	check(workspace._stamp_panel._place_button.disabled and workspace._stamp_panel._edit_button.disabled, "empty library actions must be disabled")
	workspace._tool_rail_toggle.button_pressed = false
	for frame in 2:
		await process_frame
	check(not workspace._tool_rail.visible and workspace._viewport_container.size.x > initial_viewport.x + 100.0, "collapsing primary tools does not expand the Canvas")
	workspace._tool_rail_toggle.button_pressed = true
	workspace._sidebar_toggle.button_pressed = false
	for frame in 2:
		await process_frame
	check(not workspace._sidebar_panel.visible and workspace._viewport_container.size.x > initial_viewport.x + 200.0, "collapsing right panels does not expand the Canvas")
	workspace._sidebar_toggle.button_pressed = true
	for frame in 2:
		await process_frame
	var previous_voxel := source.voxels[0]
	source.voxels[0] = 0
	source.emit_changed()
	workspace._set_status("Проверка несохранённого состояния")
	check(workspace._dirty_label.text == "Не сохранено" and workspace._dirty_label.modulate.is_equal_approx(Color(1.0, 0.72, 0.30)), "dirty state is not visibly distinct")
	source.voxels[0] = previous_voxel
	source.emit_changed()
	workspace._set_status("Готово")
	check(workspace._dirty_label.text == "Сохранено", "clean state was not restored")
	workspace._set_status("Проверка ошибки", true)
	check(workspace._status.modulate.is_equal_approx(Color(1.0, 0.45, 0.40)), "error status is not visibly distinct")
	workspace._toggle_voxel_selection()
	for frame in 3:
		await process_frame
	var selection_viewport := workspace._viewport_container.size
	check(workspace._sidebar_tabs.current_tab == 0, "selection does not reveal the parts tab")
	check(workspace._parts_sections.current_tab == 0, "selection tool does not reveal the compact selection subsection")
	check(workspace._selection_panel._mode_buttons.size() == 5 and not workspace._selection_panel._mode.visible, "selection modes still use the long dropdown")
	check(workspace._selection_panel.get_combined_minimum_size().y <= 430.0, "selection controls are still a long vertical canvas")
	check(workspace._select_tool_button.button_pressed and not workspace._stamp_tool_button.button_pressed and workspace._tool.get_selected_items().is_empty(), "selection mode is not the sole primary tool in the rail")
	check(workspace._active_tool_label.text.begins_with("Выделение"), "selection mode has no visible active-tool state")
	check(selection_viewport.distance_to(initial_viewport) <= 2.0, "changing workshop tabs resized the Canvas: %s -> %s" % [initial_viewport, selection_viewport])
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		var parts_capture := "user://voxel_workshop_parts.png"
		root.get_texture().get_image().save_png(parts_capture)
		print("WORKSHOP_PARTS_CAPTURE ", ProjectSettings.globalize_path(parts_capture))
	workspace._parts_sections.current_tab = 1
	workspace._groups_panel.sync([{
		"id":"layout_long_group",
		"name":"Очень длинное имя группы для проверки границы панели",
		"indices":PackedInt32Array([0, 1]),
		"color":Color.CYAN,
		"locked":false,
	}], "layout_long_group")
	workspace._part_selector.clear()
	workspace._part_selector.add_item("Новые воксели → Очень длинное имя части склейки")
	for frame in 3:
		await process_frame
	var groups_scroll := workspace._parts_sections.get_child(1) as ScrollContainer
	var groups_right := groups_scroll.get_global_rect().end.x + 1.0
	var context_right := (workspace.find_child("VoxelWorkshopContextBar", true, false) as Control).get_global_rect().end.x + 1.0
	check(workspace._workshop_context_label.get_global_rect().end.x <= context_right, "model context exceeds the workshop header")
	check(workspace._groups_panel.get_global_rect().end.x <= groups_right, "groups panel exceeds the right sidebar")
	check(workspace._groups_panel._list.get_global_rect().end.x <= groups_right, "long group name pushes its selector outside the sidebar")
	check(workspace._part_selector.get_global_rect().end.x <= groups_right, "long merge-part name pushes its selector outside the sidebar")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		var groups_capture := "user://voxel_workshop_groups.png"
		root.get_texture().get_image().save_png(groups_capture)
		print("WORKSHOP_GROUPS_CAPTURE ", ProjectSettings.globalize_path(groups_capture))
	workspace._open_stamp_library()
	await process_frame
	check(workspace._sidebar_tabs.current_tab == 1, "stamp tool does not reveal the library tab")
	check(workspace._stamp_tool_button.button_pressed and not workspace._select_tool_button.button_pressed, "stamp mode is not reflected in the primary rail")
	check(workspace._active_tool_label.text == "Штамп · библиотека", "stamp library has no visible active-tool state")
	check(workspace._operation_panel.get_parent() == workspace._sidebar_panel, "active operation controls are not pinned above sidebar tabs")
	var compact_geometry := source.duplicate(true) as EmberVoxelModelResource
	compact_geometry.voxels.fill(0)
	compact_geometry.voxels[0] = previous_voxel
	compact_geometry.voxels[1] = previous_voxel
	var preset := Stamp.Preset.new()
	preset.display_name = "Компактный штамп"
	preset.geometry = compact_geometry
	workspace._selection_interaction.begin_stamp(preset)
	for frame in 3:
		await process_frame
	check(workspace._selection_interaction._controls.visible, "compact stamp operation is hidden")
	check(workspace._selection_interaction._stamp_mode_buttons.size() == 3, "stamp mode does not expose add, replace and indent")
	check(workspace._selection_interaction._stamp_mode_buttons[2].text == "Вдавить", "volume indent mode is not explicit")
	check(workspace._selection_interaction._stamp_mirror_buttons.size() == 4, "stamp mirror choices are incomplete")
	check(workspace._selection_interaction._stamp_anchor_buttons.size() == 3, "stamp anchor choices are incomplete")
	workspace._selection_interaction._select_segment(workspace._selection_interaction._stamp_mode, 1)
	await process_frame
	check(workspace._selection_interaction._stamp_mode.selected == 1 and workspace._selection_interaction._stamp_mode_buttons[1].button_pressed, "stamp mode segment does not synchronize operation state")
	check(workspace._sidebar_tabs.size.y >= 150.0, "active operation leaves no useful room for sidebar tabs at 1280x720")
	check(workspace._selection_interaction._apply.get_global_rect().end.y <= workspace._sidebar_panel.get_global_rect().end.y + 1.0, "operation actions are clipped at 1280x720")
	check(workspace._stamp_panel._library_actions.get_global_rect().end.y <= workspace._sidebar_tabs.get_global_rect().end.y + 1.0, "library actions are clipped instead of staying pinned")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		var compact_capture := "user://voxel_workshop_compact.png"
		root.get_texture().get_image().save_png(compact_capture)
		print("WORKSHOP_COMPACT_CAPTURE ", ProjectSettings.globalize_path(compact_capture))
	workspace._selection_interaction.cancel_gesture()
	root.size = Vector2i(1600, 900)
	for frame in 4:
		await process_frame
	check(workspace._viewport_container.size.x >= 850.0 and workspace._viewport_container.size.y >= 520.0, "design-size Canvas viewport is too small: %s" % workspace._viewport_container.size)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		var capture := "user://voxel_workshop_layout.png"
		root.get_texture().get_image().save_png(capture)
		print("WORKSHOP_LAYOUT_CAPTURE ", ProjectSettings.globalize_path(capture))
		workspace._activate_tool_id(Workspace.Model.TOOL_SMOOTH)
		workspace._select_option_metadata(
			workspace._smooth_mode, Workspace.BrushProfiles.SMOOTH_COMMON
		)
		workspace._on_brush_setting_changed()
		for frame in 3:
			await process_frame
		var smooth_capture := "user://voxel_workshop_smooth.png"
		root.get_texture().get_image().save_png(smooth_capture)
		print("WORKSHOP_SMOOTH_CAPTURE ", ProjectSettings.globalize_path(smooth_capture))
	workspace.free()
	undo.clear_history()
	undo.free()
	print("test_voxel_workshop_layout: ", "PASS" if failures == 0 else "FAIL", " · ", failures)
	quit(failures)
