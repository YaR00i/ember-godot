@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"

const ShapeCreation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")

func select_target(target: Node) -> void:
	var selection := EditorInterface.get_selection(); selection.clear(); selection.add_node(target)

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Placement dock QA requires isolating stale qa_selection experiments."); get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600,900))
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("qa_place_" + str(OS.get_process_id()),1,1,48),creation.error)
	var path: String = creation.commit(); check(not path.is_empty(),creation.error)
	EditorInterface.get_resource_filesystem().update_file(path); await frames(10); EditorInterface.open_scene_from_path(path)
	deadline = Time.get_ticks_msec() + 30000
	while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != path) and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(15); EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	check(scene != null and scene.scene_file_path == path,"fixture open")
	if not errors.is_empty(): get_tree().quit(1); return
	var world: Node = importer._world_editor
	var map := scene.get_node("Map") as EmberMapLoader; var props := map.get_node("Props") as Node3D
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection; await ready_tiles(projection)
	var built := projection.built_tile_count(); var terrain_hash := FileAccess.get_sha256(map.compact_terrain.resource_path)
	var shape := ShapeCreation.new(); var folder := "user://ember-tests/placement-dock-%d" % Time.get_ticks_usec()
	shape.source_directory = "res://content/voxel_models"; shape.prefab_directory = folder.path_join("prefabs")
	check(shape.prepare("block",Vector3i(12,3,5),16,Color("a86f45"),"Plank"),"shape fixture")
	var temporary_undo := UndoRedo.new(); var target := shape.commit(scene,props,temporary_undo,Vector3(160,58,160))
	temporary_undo.clear_history(); temporary_undo.free()
	check(target != null,"shape commit"); if target == null: get_tree().quit(1); return
	target.scale = Vector3(1.2,0.8,1.6); target.rotation_degrees.y = 24
	var initial := target.global_transform
	var source_path := shape.source_directory.path_join(target.model_id + ".tres"); var source_hash := FileAccess.get_sha256(source_path)
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(620,740,720),Vector3(192,48,192)); _camera.far = 8000; _camera.make_current()
	select_target(target); importer._place_voxel_selection(); await frames(10)
	var panel: Control = world.placement_panel
	check(world._placement_mode and not world.active and importer._world_editor_dock_added,"standalone dock did not open")
	var host := EditorInterface.get_base_control().get_global_rect()
	print("PLACEMENT_NATIVE_LAYOUT parameters=",panel.parameters_panel.get_global_rect()," minimum=",panel.parameters_panel.get_combined_minimum_size()," preview=",panel.get_global_rect()," host=",host)
	check(host.encloses(panel.get_global_rect()) and host.encloses(panel.parameters_panel.get_global_rect()),"panels outside shell")
	var preview := panel.find_child("PlacementPreview",true,false) as Control
	check(preview.is_visible_in_tree() and preview.size.y >= 230 and panel._preview_relatives.size() > 0,"bottom preview clipped / empty")
	panel._parameter_scroll.scroll_vertical = 10000; await frames(4)
	check(panel.parameters_panel.get_global_rect().encloses(panel.get_apply_button().get_global_rect()),"Apply outside pinned footer")
	panel._parameter_scroll.scroll_vertical = 0
	panel._rotations[1].value = 19
	var rotated: Transform3D = panel._planned_world
	panel._pivot.select(1); panel._pivot.item_selected.emit(1)
	check(panel._planned_world.is_equal_approx(rotated),"pivot jump")
	var coordinate_before: float = panel._coordinates[0].value
	var number_field: LineEdit = panel._coordinates[0].get_line_edit(); number_field.grab_focus(); await frames(2)
	number_field.text = str(coordinate_before + 4.43)
	var enter := InputEventKey.new(); enter.keycode = KEY_ENTER; enter.pressed = true; Input.parse_input_event(enter); await frames(4)
	check(is_equal_approx(panel._coordinates[0].value,roundf(coordinate_before + 4.43)),"focused numeric Enter did not update plan")
	var field_escape := InputEventKey.new(); field_escape.keycode = KEY_ESCAPE; field_escape.pressed = true
	check(importer._forward_3d_gui_input(_camera,field_escape) == EditorPlugin.AFTER_GUI_INPUT_PASS and world._placement_mode,"field Escape discarded placement")
	number_field.release_focus()
	var planned: Transform3D = panel._planned_world
	var session: RefCounted = panel.placement
	check(panel.is_dirty() and target.global_transform.is_equal_approx(initial),"preview mutated scene")
	importer._place_voxel_selection(); check(panel.placement == session and panel._planned_world.is_equal_approx(planned),"repeat reset plan")
	select_target(props); importer._place_voxel_selection()
	check(panel.placement == session and panel.is_dirty(),"different selection discarded plan")
	importer._new_compact_map(); check(world._placement_mode and importer._compact_map_panel == null,"new-map command discarded plan")
	world.enabled.button_pressed = true; check(not world.active and world._placement_mode,"world toggle discarded plan")
	var orbit := InputEventMouseMotion.new(); orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(importer._forward_3d_gui_input(_camera,orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS,"camera blocked")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	check(importer._forward_3d_gui_input(_camera,click) == EditorPlugin.AFTER_GUI_INPUT_PASS and not world._compact_brush.active() and not importer._object_brush.active,"viewport activated authoring brush")
	importer.hide_bottom_panel(); await frames(4); check(panel.is_dirty(),"collapse lost plan")
	importer.make_bottom_panel_item_visible(panel); await frames(4)
	await capture("voxel_placement_dock",panel)
	panel.get_apply_button().pressed.emit(); await frames(5)
	check(not world._placement_mode and not importer._placement_bottom_button.visible and target.global_transform.is_equal_approx(planned),"Apply / bound target failed")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); check(target.global_transform.is_equal_approx(initial),"one Undo")
	history.redo(); check(target.global_transform.is_equal_approx(planned),"Redo")
	EditorInterface.save_scene()
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node(scene.get_path_to(target)).transform.is_equal_approx(target.transform),"Save-Reopen transform"); reopened.free()
	select_target(target); importer._place_voxel_selection(); panel._offsets[0].value += 3
	panel.cancel_edit(); check(target.global_transform.is_equal_approx(planned) and panel.placement == null and panel._context.visuals.is_empty(),"Cancel changed scene / retained context")
	importer._place_voxel_selection(); panel._offsets[0].value += 2
	var parent_transform := props.transform; props.position.x += 1
	panel.get_apply_button().pressed.emit(); check(world._placement_mode and panel.get_apply_button().disabled,"stale parent Apply accepted")
	props.transform = parent_transform; panel.cancel_edit()
	importer._place_voxel_selection(); panel._offsets[0].value += 2
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	var focused := EditorInterface.get_base_control().get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus() # Simulate returning focus to 3D before Esc.
	check(importer._forward_3d_gui_input(_camera,escape) == EditorPlugin.AFTER_GUI_INPUT_STOP and not world._placement_mode,"Escape retained preview")
	importer._place_voxel_selection(); importer._new_compact_map()
	check(not world._placement_mode and world._map_creation_mode and panel.placement == null and panel._context.visuals.is_empty(),"clean placement did not yield to new-map parameters")
	importer._cancel_compact_map_creation()
	world.enabled.button_pressed = true; await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map,scene); var terrain_before: Terrain = draft.resource.working_copy()
	world.edit_region = Rect2i(0,0,24,24); world._open_terrain_generation()
	select_target(target); importer._place_voxel_selection(); panel._offsets[2].value += 4; panel.cancel_edit(); await frames(4)
	check(world.active and world._terrain_workspace.visible and draft.resource.same_terrain_data(terrain_before),"Cancel lost terrain page / draft")
	select_target(target); importer._place_voxel_selection(); panel._offsets[0].value += 2
	importer._on_scene_changed(scene)
	check(not world._placement_mode and panel.placement == null and panel._selected_preview.get_child_count() == 0,"scene change retained stale placement")
	check(FileAccess.get_sha256(source_path) == source_hash and FileAccess.get_sha256(map.compact_terrain.resource_path) == terrain_hash and projection.built_tile_count() == built,"UI changed source / terrain / remeshed")
	_camera.queue_free()
	print("VOXEL_PLACEMENT_DOCK_NATIVE ","PASS" if errors.is_empty() else "FAIL"," layout/preview/pivot/repeat/guards/camera/collapse/Apply/Undo-Redo/Save-Reopen/Cancel/stale/Escape/terrain-return/scene-change/source-preservation errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
