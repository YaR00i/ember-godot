@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const ShapeCreation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")

func select_nodes(nodes: Array) -> void:
	var selection := EditorInterface.get_selection(); selection.clear()
	for node in nodes: selection.add_node(node)

func capture(name: String,_panel: Control = null) -> void:
	await frames(5); await RenderingServer.frame_post_draw
	var path := "user://"+name+"-"+str(OS.get_process_id())+".png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
	print("MERGE_DOCK_CAPTURE ",ProjectSettings.globalize_path(path))

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Merge dock QA requires isolating stale qa_selection experiments."); get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600,900))
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("qa_merge_"+str(OS.get_process_id()),1,1,48),creation.error)
	var path: String = creation.commit(); check(not path.is_empty(),creation.error)
	EditorInterface.get_resource_filesystem().update_file(path); await frames(10); EditorInterface.open_scene_from_path(path)
	deadline = Time.get_ticks_msec()+30000
	while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != path) and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(15); EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	check(scene != null and scene.scene_file_path == path,"fixture open")
	if not errors.is_empty(): get_tree().quit(1); return
	var world: Node = importer._world_editor
	var map := scene.get_node("Map") as EmberMapLoader; var props := map.get_node("Props") as Node3D
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection; await ready_tiles(projection)
	var built := projection.built_tile_count(); var terrain_hash := FileAccess.get_sha256(map.compact_terrain.resource_path)
	var nodes: Array = []; var source_hashes: Array = []; var source_paths: Array = []; var temporary_undo := UndoRedo.new()
	for index in 2:
		var shape := ShapeCreation.new(); shape.source_directory = "res://content/voxel_models"; shape.prefab_directory = "user://ember-tests/merge-native-%d" % Time.get_ticks_usec()
		check(shape.prepare("block",Vector3i(12,3,5),16,Color("a86f45"),"Board_"+str(index)),"shape fixture")
		var prop := shape.commit(scene,props,temporary_undo,Vector3(160+12.25*index,58,160))
		check(prop != null,"shape commit"); if prop == null: get_tree().quit(1); return
		nodes.append(prop); source_paths.append(shape.source_directory.path_join(prop.model_id+".tres")); source_hashes.append(FileAccess.get_sha256(source_paths.back()))
	temporary_undo.clear_history(); temporary_undo.free()
	var poses: Array = nodes.map(func(node): return node.transform)
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(620,740,720),Vector3(192,48,192)); _camera.far = 8000; _camera.make_current()
	select_nodes(nodes); importer._merge_voxel_selected(false); await frames(10)
	var panel: Control = world.merge_panel
	check(world._panel_host.is_active("merge") and not world.active and importer._world_editor_dock_added,"standalone route missing")
	check(world.inspector_panel.is_ancestor_of(panel.parameters_panel) and panel._legacy_window == null,"modal created / parameters outside dock")
	check(panel._session == null and panel.get_ok_button().disabled,"automatic heavy preparation")
	panel._prepare_button.pressed.emit(); check(panel.get_ok_button().disabled and props.get_child_count() == 2,"fractional alignment accepted implicitly")
	panel._align.button_pressed = true; check(panel._session == null,"option rebuilt geometry")
	panel._prepare_button.pressed.emit(); check(not panel.get_ok_button().disabled,"preview failed: "+panel._status.text)
	if panel.get_ok_button().disabled: get_tree().quit(1); return
	var candidate: RefCounted = panel._session
	var host := EditorInterface.get_base_control().get_global_rect()
	check(host.encloses(panel.parameters_panel.get_global_rect()) and host.encloses(panel.get_global_rect()),"panels outside shell")
	check(panel._preview_container.is_visible_in_tree() and panel._preview_container.size.y >= 230,"bottom preview clipped")
	panel._parameter_scroll.scroll_vertical = 10000; await frames(5)
	check(panel.parameters_panel.get_global_rect().encloses(panel.get_ok_button().get_global_rect()) and panel.parameters_panel.get_global_rect().encloses(panel._prepare_button.get_global_rect()),"pinned actions lost")
	panel._parameter_scroll.scroll_vertical = 0
	select_nodes([nodes[1],nodes[0]]); importer._merge_voxel_selected(false)
	check(panel._session == candidate and panel._align.button_pressed,"repeat reset prepared context")
	select_nodes([nodes[0]]); importer._merge_voxel_selected(true); importer._new_compact_map(); importer._new_voxel_shape()
	check(world._panel_host.is_active("merge") and panel._session == candidate and importer._compact_map_panel == null,"pending guard lost bound selection")
	var orbit := InputEventMouseMotion.new(); orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(importer._forward_3d_gui_input(_camera,orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS,"camera blocked")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	check(importer._forward_3d_gui_input(_camera,click) == EditorPlugin.AFTER_GUI_INPUT_PASS and not importer._object_brush.active,"authoring input leaked")
	panel._scene_orientation.button_pressed = false; check(panel._session == candidate,"view toggle rebuilt operation")
	panel._view_yaw += 0.3; panel._update_camera(); check(panel._session == candidate,"view orbit changed data")
	importer.hide_bottom_panel(); await frames(3); check(panel._session == candidate,"collapse lost candidate")
	importer.make_bottom_panel_item_visible(panel); await frames(4)
	panel._bake_orientation.button_pressed = true; check(panel._session == null,"bake option rebuilt immediately")
	panel._prepare(); check(not panel.get_ok_button().disabled and panel._session.orientation_baked,"bake capability lost")
	panel._bake_orientation.button_pressed = false; panel._prepare(); candidate = panel._session
	await capture("voxel_merge_dock",panel)
	var expected: EmberVoxelModelResource = candidate.preview
	panel.get_ok_button().pressed.emit(); await frames(5)
	check(props.get_child_count() == 1 and not world._panel_host.any_active() and not importer._merge_bottom_button.visible,"merge / lifecycle failed")
	if props.get_child_count() != 1: get_tree().quit(1); return
	var merged := props.get_child(0) as EmberVoxelProp
	check((load("res://content/voxel_models/"+merged.model_id+".tres") as EmberVoxelModelResource).voxels == expected.voxels,"preview != commit")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); check(props.get_child_count() == 2 and nodes.map(func(node): return node.transform) == poses,"one Undo lost exact originals")
	history.redo(); check(props.get_child_count() == 1 and props.get_child(0) == merged,"Redo merge")
	EditorInterface.save_scene()
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map/Props").get_child_count() == 1,"Save-Reopen merge"); reopened.free()
	select_nodes([merged]); importer._merge_voxel_selected(true); panel._prepare()
	check(not panel.get_ok_button().disabled and not panel._align.visible and panel._session.outputs.size() == 2,"unmerge preview")
	importer._voxel_canvas_action(merged,"selected"); await frames(8)
	var canvas := EditorInterface.get_editor_main_screen().get_node("EmberSurfaceCanvasWorkspace")
	canvas._resource.voxel_part_ids[0] = 2
	check(canvas.has_unsaved_changes(),"Canvas dirty fixture")
	panel.get_ok_button().pressed.emit(); check(world._panel_host.is_active("merge") and props.get_child_count() == 1,"dirty Canvas Apply accepted")
	canvas.discard_changes(); check(not canvas.has_unsaved_changes(),"Canvas discard")
	canvas._actions.active_part = 2
	var added: int = canvas._resource.voxels.size()-1
	check(canvas._actions.apply_stroke(canvas._resource,{0:{"after":0},added:{"after":1}}),"Canvas sculpt")
	check(canvas.save_changes(),"Canvas Save"); await frames(5)
	panel.get_ok_button().pressed.emit(); check(panel.get_ok_button().disabled and props.get_child_count() == 1,"stale source accepted")
	EditorInterface.set_main_screen_editor("3D"); panel._prepare()
	check(not panel.get_ok_button().disabled and panel._session.preview.voxels[0] == 0 and panel._session.preview.voxels[added] == 1,"updated unmerge lost sculpt")
	await capture("voxel_unmerge_dock",panel)
	panel.get_ok_button().pressed.emit(); await frames(5); check(props.get_child_count() == 2,"unmerge commit")
	history.undo(); check(props.get_child_count() == 1 and props.get_child(0) == merged,"Undo unmerge")
	history.redo(); check(props.get_child_count() == 2,"Redo unmerge")
	EditorInterface.save_scene(); reopened = (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map/Props").get_child_count() == 2,"Save-Reopen unmerge"); reopened.free()
	select_nodes(props.get_children()); importer._merge_voxel_selected(false); panel._prepare(); panel.cancel_edit()
	check(not world._panel_host.any_active() and panel._session == null and panel._selection.is_empty(),"Cancel retained context")
	world.enabled.button_pressed = true; await ready_tiles(projection)
	world.edit_region = Rect2i(0,0,24,24); world._open_terrain_generation()
	select_nodes(props.get_children()); importer._merge_voxel_selected(false); panel.cancel_edit()
	check(world._terrain_workspace.visible,"Cancel lost return terrain page")
	importer._merge_voxel_selected(false); panel._prepare()
	var focus := EditorInterface.get_base_control().get_viewport().gui_get_focus_owner(); if focus != null: focus.release_focus()
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	check(importer._forward_3d_gui_input(_camera,escape) == EditorPlugin.AFTER_GUI_INPUT_STOP and not world._panel_host.any_active(),"Esc did not cancel")
	importer._merge_voxel_selected(false); importer._on_scene_changed(scene)
	check(not world._panel_host.any_active() and panel._root == null and panel._session == null,"scene change retained stale refs")
	check(source_paths.map(func(source_path): return FileAccess.get_sha256(source_path)) == source_hashes and FileAccess.get_sha256(map.compact_terrain.resource_path) == terrain_hash and projection.built_tile_count() == built,"source / terrain / built tiles changed")
	_camera.queue_free()
	print("VOXEL_MERGE_DOCK_NATIVE ","PASS" if errors.is_empty() else "FAIL"," layout/explicit-preview/options/repeat/guards/view/camera/collapse/merge-unmerge/Canvas-dirty-sculpt/stale/Undo-Redo/Save-Reopen/Cancel/Esc/return/scene/source/no-remesh errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
