@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const ShapeCreation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")

func select_target(target: Node) -> void:
	var selection := EditorInterface.get_selection(); selection.clear(); selection.add_node(target)

func capture(name: String,_panel: Control = null) -> void:
	await frames(5); await RenderingServer.frame_post_draw
	var path := "user://"+name+"-"+str(OS.get_process_id())+".png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
	print("REMAINING_DOCK_CAPTURE ",ProjectSettings.globalize_path(path))

func check_layout(panel: Control) -> void:
	var host := EditorInterface.get_base_control().get_global_rect()
	check(host.encloses(panel.get_global_rect()) and host.encloses(panel.parameters_panel.get_global_rect()),"panels outside shell")
	check(panel._preview_viewport.get_parent().is_visible_in_tree() and panel._preview_viewport.get_parent().size.y >= 230,"preview clipped")
	panel._parameter_scroll.scroll_vertical = 10000; await frames(4)
	check(panel.parameters_panel.get_global_rect().encloses(panel.get_ok_button().get_global_rect()) and panel.parameters_panel.get_global_rect().encloses(panel._prepare_button.get_global_rect()),"pinned actions lost")
	panel._parameter_scroll.scroll_vertical = 0

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Remaining docks QA requires isolating stale qa_selection experiments."); get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600,900))
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("qa_final_panels_"+str(OS.get_process_id()),1,1,48),creation.error)
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
	var terrain_hash := FileAccess.get_sha256(map.compact_terrain.resource_path); var built := projection.built_tile_count()
	var shape := ShapeCreation.new(); shape.source_directory = "res://content/voxel_models"; shape.prefab_directory = "user://ember-tests/remaining-native-%d" % Time.get_ticks_usec()
	check(shape.prepare("block",Vector3i(80,3,80),16,Color("a86f45"),"Sectioned board"),"shape fixture")
	var temporary_undo := UndoRedo.new(); var original := shape.commit(scene,props,temporary_undo,Vector3(160,58,160)); temporary_undo.clear_history(); temporary_undo.free()
	check(original != null,"shape commit"); if original == null: get_tree().quit(1); return
	var source_path: String = shape.source_directory.path_join(original.model_id+".tres"); var hash := FileAccess.get_sha256(source_path); var pose := original.transform
	var body := StaticBody3D.new(); body.name = "PrimitiveBox"; props.add_child(body); body.owner = scene; body.position = Vector3(90,70,120); body.scale = Vector3(1.2,0.8,1.1)
	var visual := MeshInstance3D.new(); visual.name = "Visual"; body.add_child(visual); visual.owner = scene
	var mesh := BoxMesh.new(); mesh.size = Vector3(12,4,10); visual.mesh = mesh; visual.position = Vector3(2,1,0)
	var collider := CollisionShape3D.new(); collider.name = "Collision"; body.add_child(collider); collider.owner = scene
	var collision := BoxShape3D.new(); collision.size = mesh.size; collider.shape = collision; collider.transform = visual.transform; body.collision_layer = 4
	var original_bounds := visual.global_transform*visual.get_aabb()
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(620,740,720),Vector3(192,48,192)); _camera.far = 8000; _camera.make_current()
	select_target(original); importer._split_voxel_object(); await frames(10)
	var split: Control = world.split_panel
	check(world._panel_host.is_active("split") and split._legacy_window == null and split._splitter == null,"split route/modal/automatic prepare")
	split._prepare_button.pressed.emit(); check(not split.get_ok_button().disabled and split._splitter.parts.size() == 4,"split preview: "+split._status.text)
	if split.get_ok_button().disabled: get_tree().quit(1); return
	await check_layout(split)
	var candidate: RefCounted = split._splitter; importer._split_voxel_object(); check(split._splitter == candidate,"repeat split reset")
	select_target(body); importer._convert_voxel_form(); importer._new_compact_map()
	check(world._panel_host.is_active("split") and split._splitter == candidate and importer._compact_map_panel == null,"split pending guard")
	var orbit := InputEventMouseMotion.new(); orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(importer._forward_3d_gui_input(_camera,orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS,"split camera blocked")
	importer.hide_bottom_panel(); await frames(3); check(split._splitter == candidate,"split collapse lost candidate")
	importer.make_bottom_panel_item_visible(split)
	split._section.select(0); split._section.item_selected.emit(0)
	check(split._splitter == null and split._preview == null,"split field rebuilt / stale preview")
	split._prepare(); check(split._splitter.parts.size() == 9,"32-voxel sections")
	split._section.select(1); split._section.item_selected.emit(1); split._prepare()
	original.position.x += 1; split.get_ok_button().pressed.emit(); check(original.get_parent() == props and split.get_ok_button().disabled,"split stale accepted")
	original.transform = pose; split._prepare()
	importer._voxel_canvas_action(original,"selected"); await frames(8)
	var canvas := EditorInterface.get_editor_main_screen().get_node("EmberSurfaceCanvasWorkspace")
	check(canvas._actions.apply_stroke(canvas._resource,{0:{"after":0}}) and canvas.has_unsaved_changes(),"split Canvas dirty fixture")
	split.get_ok_button().pressed.emit(); check(original.get_parent() == props,"split dirty Canvas applied")
	canvas.discard_changes(); EditorInterface.set_main_screen_editor("3D"); split._prepare()
	await frames(3)
	check(importer._split_bottom_button.visible,"split preview tab lost after Canvas return")
	await capture("voxel_split_dock",split)
	split.get_ok_button().pressed.emit(); await frames(5)
	var group := props.get_child(0)
	check(group != original and group.get_child_count() == 4 and not world._panel_host.any_active() and split._target_ref == null,"split apply/cleanup")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); check(original.get_parent() == props and original.transform == pose,"split one Undo")
	history.redo(); check(group.get_parent() == props,"split Redo")
	EditorInterface.save_scene()
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map/Props").get_child(0).get_child_count() == 4,"split Save-Reopen"); reopened.free()
	select_target(body); importer._convert_voxel_form(); await frames(10)
	var conversion: Control = world.conversion_panel
	check(world._panel_host.is_active("conversion") and conversion._legacy_window == null and conversion.creation == null,"conversion route/modal/automatic prepare")
	conversion._prepare_button.pressed.emit(); check(not conversion.get_ok_button().disabled,"conversion preview: "+conversion._status.text)
	if conversion.get_ok_button().disabled: get_tree().quit(1); return
	await check_layout(conversion)
	candidate = conversion.creation; importer._convert_voxel_form(); check(conversion.creation == candidate,"repeat conversion reset")
	conversion._show_original.button_pressed = true
	check(conversion.creation == candidate and conversion._original_preview.visible and not conversion._preview.visible,"compare mutated candidate")
	conversion._show_original.button_pressed = false
	var number: LineEdit = conversion._sizes[0].get_line_edit(); number.grab_focus(); await frames(2); number.text = "13"
	var enter := InputEventKey.new(); enter.keycode = KEY_ENTER; enter.pressed = true; Input.parse_input_event(enter); await frames(4)
	check(conversion._sizes[0].value == 13 and conversion.creation == null,"numeric Enter did not invalidate")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	check(importer._forward_3d_gui_input(_camera,escape) == EditorPlugin.AFTER_GUI_INPUT_PASS and world._panel_host.is_active("conversion"),"field Esc closed conversion")
	number.release_focus()
	conversion._density.select(1); conversion._density.item_selected.emit(1)
	check(conversion._sizes[0].value == 26 and conversion.creation == null,"density rescale / automatic preparation")
	conversion._prepare(); candidate = conversion.creation
	select_target(group.get_child(0)); importer._split_voxel_object(); importer._new_voxel_shape()
	check(world._panel_host.is_active("conversion") and conversion.creation == candidate,"conversion pending guard lost source")
	check(importer._forward_3d_gui_input(_camera,orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS,"conversion camera blocked")
	visual.position.x += 1; conversion.get_ok_button().pressed.emit(); check(visual.get_parent() == body and conversion.get_ok_button().disabled,"conversion stale accepted")
	visual.position.x -= 1; conversion._prepare()
	importer._voxel_canvas_action(group.get_child(0),"selected"); await frames(8)
	check(canvas._actions.apply_stroke(canvas._resource,{0:{"after":0}}) and canvas.has_unsaved_changes(),"conversion Canvas dirty fixture")
	conversion.get_ok_button().pressed.emit(); check(visual.get_parent() == body,"conversion dirty Canvas applied")
	canvas.discard_changes(); EditorInterface.set_main_screen_editor("3D"); conversion._prepare()
	await frames(3)
	check(importer._conversion_bottom_button.visible,"conversion preview tab lost after Canvas return")
	await capture("voxel_conversion_dock",conversion)
	var result := {"prop":null}; conversion.created.connect(func(prop: EmberVoxelProp): result.prop = prop)
	conversion.get_ok_button().pressed.emit(); await frames(12)
	var converted := result.prop as EmberVoxelProp
	check(converted != null and not world._panel_host.any_active() and conversion._original == null and conversion._original_preview == null,"conversion apply/cleanup")
	if converted == null: get_tree().quit(1); return
	check(canvas.visible and canvas._object_session._target.get_ref() == converted,"conversion did not open Canvas")
	check(collider.get_parent() == null and converted.get_node("Collision").collision_layer == 4,"double collision / layer lost")
	var result_mesh := converted.get_node("Mesh") as MeshInstance3D; var bounds := result_mesh.global_transform*result_mesh.get_aabb()
	check(bounds.position.is_equal_approx(original_bounds.position) and bounds.size.is_equal_approx(original_bounds.size),"conversion changed world bounds")
	history.undo(); check(visual.get_parent() == body and collider.get_parent() == body,"conversion one Undo")
	history.redo(); check(converted.get_parent() == body and collider.get_parent() == null,"conversion Redo")
	EditorInterface.set_main_screen_editor("3D"); EditorInterface.save_scene()
	reopened = (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map/Props/PrimitiveBox/Visual") is EmberVoxelProp,"conversion Save-Reopen"); reopened.free()
	select_target(group.get_child(0)); importer._split_voxel_object(); split._prepare(); split.cancel_edit()
	check(not world._panel_host.any_active() and split._splitter == null,"split Cancel retained refs")
	world.enabled.button_pressed = true; await ready_tiles(projection); world.edit_region = Rect2i(0,0,24,24); world._open_terrain_generation()
	importer._split_voxel_object(); split.cancel_edit(); check(world._terrain_workspace.visible,"split Cancel lost terrain return")
	importer._split_voxel_object(); split._prepare()
	var focus := EditorInterface.get_base_control().get_viewport().gui_get_focus_owner(); if focus != null: focus.release_focus()
	check(importer._forward_3d_gui_input(_camera,escape) == EditorPlugin.AFTER_GUI_INPUT_STOP and not world._panel_host.any_active(),"split viewport Esc")
	# Undo conversion temporarily supplies the original primitive for the remaining lifecycle checks.
	history.undo(); select_target(body); importer._convert_voxel_form(); conversion._prepare(); conversion.cancel_edit()
	check(world._terrain_workspace.visible and conversion.creation == null,"conversion Cancel lost terrain return")
	importer._convert_voxel_form(); conversion._prepare(); importer._on_scene_changed(scene)
	check(not world._panel_host.any_active() and conversion._root == null and conversion._original == null,"conversion scene change retained refs")
	check(FileAccess.get_sha256(source_path) == hash and FileAccess.get_sha256(map.compact_terrain.resource_path) == terrain_hash and projection.built_tile_count() == built,"source/terrain/built tiles changed")
	_camera.queue_free()
	print("VOXEL_REMAINING_DOCKS_NATIVE ","PASS" if errors.is_empty() else "FAIL"," layout/explicit/split-conversion/compare/density/numeric/repeat/guards/stale/Canvas/camera/collapse/Undo-Redo/Save-Reopen/Cancel/Esc/return/scene/source/no-remesh errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
