@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"

const ShapeCreation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")

func select_target(target: Node) -> void:
	var selection := EditorInterface.get_selection(); selection.clear(); selection.add_node(target)

func capture(name: String,_panel: Control = null) -> void:
	await frames(5); await RenderingServer.frame_post_draw
	var path := "user://" + name + "-" + str(OS.get_process_id()) + ".png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
	print("DUPLICATE_DOCK_CAPTURE ",ProjectSettings.globalize_path(path))

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Duplicate dock QA requires isolating stale qa_selection experiments."); get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600,900))
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("qa_dup_" + str(OS.get_process_id()),1,1,48),creation.error)
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
	var shape := ShapeCreation.new(); shape.source_directory = "res://content/voxel_models"
	shape.prefab_directory = "user://ember-tests/duplicate-dock-%d/prefabs" % Time.get_ticks_usec()
	check(shape.prepare("block",Vector3i(12,3,5),16,Color("a86f45"),"Plank"),"shape fixture")
	var temporary := UndoRedo.new(); var target := shape.commit(scene,props,temporary,Vector3(160,58,160))
	temporary.clear_history(); temporary.free(); check(target != null,"shape commit")
	if target == null: get_tree().quit(1); return
	target.scale = Vector3(1.2,0.8,1.6); target.rotation_degrees.y = 24
	var initial := target.global_transform; var source_path := shape.source_directory.path_join(target.model_id + ".tres")
	var source_hash := FileAccess.get_sha256(source_path)
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(620,740,720),Vector3(192,48,192)); _camera.far = 8000; _camera.make_current()
	select_target(target); importer._scene_assembly_command(4); await frames(10)
	var panel: Control = world.duplicate_panel
	check(world._duplicate_mode and not world.active and importer._world_editor_dock_added,"duplicate dock did not open")
	var host := EditorInterface.get_base_control().get_global_rect()
	check(host.encloses(panel.get_global_rect()) and host.encloses(panel.parameters_panel.get_global_rect()),"panels outside shell")
	var preview := panel.find_child("CopyPreview",true,false) as Control
	check(preview.is_visible_in_tree() and preview.size.y >= 240,"preview clipped")
	panel._parameter_scroll.scroll_vertical = 10000; await frames(4)
	check(panel.parameters_panel.get_global_rect().encloses(panel.get_create_button().get_global_rect()),"Create outside pinned footer")
	panel._parameter_scroll.scroll_vertical = 0
	var field: LineEdit = panel._axes[0].get_line_edit(); field.grab_focus(); await frames(2); field.text = "23"
	var enter := InputEventKey.new(); enter.keycode = KEY_ENTER; enter.pressed = true; Input.parse_input_event(enter); await frames(4)
	check(is_equal_approx(panel._axes[0].value,23),"numeric Enter")
	field.release_focus(); panel._count.value = 4
	var poses: Array[Transform3D] = panel.operation.positions.duplicate(); var step: Vector3 = panel.world_step()
	check(poses.size() == 4 and props.get_child_count() == 1 and target.global_transform.is_equal_approx(initial),"preview mutated scene / wrong count")
	importer._scene_assembly_command(4); check(panel.operation.positions == poses,"repeat reset pending row")
	select_target(props); importer._new_compact_map(); check(world._duplicate_mode and importer._compact_map_panel == null,"new-map discarded row")
	world.enabled.button_pressed = true; check(not world.active and world._duplicate_mode,"world toggle discarded row")
	var orbit := InputEventMouseMotion.new(); orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(importer._forward_3d_gui_input(_camera,orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS,"camera blocked")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	check(importer._forward_3d_gui_input(_camera,click) == EditorPlugin.AFTER_GUI_INPUT_PASS and not world._compact_brush.active() and not importer._object_brush.active,"viewport brush leaked")
	importer.hide_bottom_panel(); await frames(3); check(panel.operation.positions == poses,"collapse lost row")
	importer.make_bottom_panel_item_visible(panel); await frames(4); await capture("voxel_duplicate_dock",panel)
	panel.get_create_button().pressed.emit(); await frames(5)
	check(not world._duplicate_mode and not importer._duplicate_bottom_button.visible and props.get_child_count() == 5,"row commit / cleanup")
	check(importer._last_duplicate_step.is_equal_approx(step),"last world step not retained")
	for index in 4:
		check(props.get_child(index + 1).global_transform.is_equal_approx(poses[index]),"preview != commit")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); check(props.get_child_count() == 1,"one Undo did not remove whole row")
	history.redo(); check(props.get_child_count() == 5,"Redo")
	select_target(target); importer._scene_assembly_command(5); check(props.get_child_count() == 6,"repeat command did not add one copy")
	check(props.get_child(-1).global_position.is_equal_approx(initial.origin + step),"repeat changed saved world step")
	EditorInterface.save_scene()
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map/Props").get_child_count() == 6,"Save-Reopen copies"); reopened.free()
	select_target(target); importer._scene_assembly_command(4); panel._axes[0].value = 9
	var parent_pose := props.transform; props.position.x += 1; panel.get_create_button().pressed.emit()
	check(world._duplicate_mode and panel.get_create_button().disabled and props.get_child_count() == 6,"stale parent accepted")
	props.transform = parent_pose; panel.cancel_edit()
	importer._scene_assembly_command(4); check(panel._axes[1].value == 0 and panel._count.value == 1,"new context retained old axes/count")
	var escape := InputEventKey.new(); escape.keycode = KEY_ESCAPE; escape.pressed = true
	var focus := EditorInterface.get_base_control().get_viewport().gui_get_focus_owner(); if focus != null: focus.release_focus()
	check(importer._forward_3d_gui_input(_camera,escape) == EditorPlugin.AFTER_GUI_INPUT_STOP and not world._duplicate_mode,"Escape retained row")
	world.enabled.button_pressed = true; await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map,scene); var terrain_before: Terrain = draft.resource.working_copy()
	world.edit_region = Rect2i(0,0,24,24); world._open_terrain_generation(); select_target(target); importer._scene_assembly_command(4)
	panel._axes[0].value = 12; panel.cancel_edit()
	check(world._terrain_workspace.visible and draft.resource.same_terrain_data(terrain_before),"Cancel lost terrain page / data")
	importer._scene_assembly_command(4); importer._on_scene_changed(scene)
	check(not world._duplicate_mode and panel.placement == null and panel.operation == null,"scene change retained row")
	check(FileAccess.get_sha256(source_path) == source_hash and FileAccess.get_sha256(map.compact_terrain.resource_path) == terrain_hash and projection.built_tile_count() == built,"UI wrote source / terrain / remeshed")
	_camera.queue_free()
	print("VOXEL_DUPLICATE_DOCK_NATIVE ","PASS" if errors.is_empty() else "FAIL"," layout/numeric/preview/repeat/guards/camera/collapse/Create/Undo-Redo/Save-Reopen/repeat-step/stale/Esc/Cancel/terrain-return/scene-change/no-remesh errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
