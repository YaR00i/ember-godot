@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"

func capture(name: String,_panel: Control = null) -> void:
	await frames(5); await RenderingServer.frame_post_draw
	var path := "user://" + name + "-" + str(OS.get_process_id()) + ".png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
	print("SHAPE_DOCK_CAPTURE ",ProjectSettings.globalize_path(path))

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Shape dock QA requires isolating stale qa_selection experiments."); get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600,900))
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("qa_form_" + str(OS.get_process_id()),1,1,48),creation.error)
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
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(620,740,720),Vector3(192,48,192)); _camera.far = 8000; _camera.make_current()
	importer._new_voxel_shape(); await frames(10)
	var panel: Control = world.shape_panel
	check(world._shape_mode and not world.active and panel.get_create_button().disabled,"new form did not open right dock")
	var host := EditorInterface.get_base_control().get_global_rect()
	check(host.encloses(panel.get_global_rect()) and host.encloses(panel.parameters_panel.get_global_rect()),"shape panels outside shell")
	var preview := panel.find_child("ShapePreview",true,false) as Control
	check(preview.is_visible_in_tree() and preview.size.y >= 240,"bottom preview clipped")
	panel._parameter_scroll.scroll_vertical = 10000; await frames(4)
	check(panel.parameters_panel.get_global_rect().encloses(panel.get_create_button().get_global_rect()),"Create outside pinned footer")
	panel._parameter_scroll.scroll_vertical = 0
	panel._kind.select(1); panel._kind_changed(); panel._title.text = "QA board"; panel._title.text_changed.emit(panel._title.text)
	panel._sizes[0].value = 16; panel._sizes[1].value = 2; panel._sizes[2].value = 32
	panel._prepare_button.pressed.emit()
	check(not panel.get_create_button().disabled and panel._preview != null,"board preview missing")
	var candidate: RefCounted = panel.creation; var model: Resource = candidate.source.duplicate(true)
	var source_path: String = candidate.source_directory.path_join(candidate.source.model_id + ".tres")
	check(not FileAccess.file_exists(source_path) and props.get_child_count() == 0,"preview wrote source / scene")
	var field: LineEdit = panel._sizes[1].get_line_edit(); field.grab_focus(); await frames(2); field.text = "3"
	var enter := InputEventKey.new(); enter.keycode = KEY_ENTER; enter.pressed = true; Input.parse_input_event(enter); await frames(4)
	check(panel._sizes[1].value == 3 and panel.creation == null and panel.get_create_button().disabled,"numeric Enter retained stale candidate")
	field.release_focus(); panel._prepare()
	candidate = panel.creation; model = candidate.source.duplicate(true); source_path = candidate.source_directory.path_join(candidate.source.model_id + ".tres")
	importer._new_voxel_shape(); check(panel.creation == candidate,"repeat reset prepared form")
	importer._new_compact_map(); check(world._shape_mode and importer._compact_map_panel == null,"new-map discarded prepared form")
	world.enabled.button_pressed = true; check(not world.active and world._shape_mode,"world toggle discarded prepared form")
	var orbit := InputEventMouseMotion.new(); orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(importer._forward_3d_gui_input(_camera,orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS,"camera blocked")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	check(importer._forward_3d_gui_input(_camera,click) == EditorPlugin.AFTER_GUI_INPUT_PASS and not world._compact_brush.active() and not importer._object_brush.active,"viewport authoring brush leaked")
	importer.hide_bottom_panel(); await frames(3); check(panel.creation == candidate,"collapse lost candidate")
	importer.make_bottom_panel_item_visible(panel); await frames(4)
	await capture("voxel_shape_dock",panel)
	var created := {"prop": null}; panel.created.connect(func(prop: EmberVoxelProp): created.prop = prop)
	panel.get_create_button().pressed.emit(); await frames(12)
	var prop := created.prop as EmberVoxelProp
	check(prop != null and props.get_child_count() == 1 and not world._shape_mode and not importer._shape_bottom_button.visible,"Create / mode cleanup")
	if prop == null: get_tree().quit(1); return
	var saved := load(source_path) as EmberVoxelModelResource
	check(saved.voxels == model.voxels and saved.palette == model.palette,"prepared != installed source")
	var canvas := EditorInterface.get_editor_main_screen().get_node("EmberSurfaceCanvasWorkspace")
	check(canvas.visible and canvas._object_session != null and canvas._object_session._target.get_ref() == prop,"Create did not open existing Canvas")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); check(props.get_child_count() == 0,"creation one Undo")
	history.redo(); check(props.get_child_count() == 1,"creation Redo")
	EditorInterface.set_main_screen_editor("3D"); EditorInterface.save_scene()
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map/Props").get_child(0).model_id == prop.model_id,"Save-Reopen model"); reopened.free()
	importer._new_voxel_shape(); panel._sizes[0].value = 12; panel._prepare()
	var canceled_source: String = panel.creation.source_directory.path_join(panel.creation.source.model_id + ".tres")
	panel.cancel_edit(); check(not world._shape_mode and panel.creation == null and panel._preview == null and not FileAccess.file_exists(canceled_source),"Cancel wrote / retained candidate")
	# Empty shape must still enter the existing first-voxel Canvas workflow.
	importer._new_voxel_shape(); panel._kind.select(0); panel._kind_changed(); panel._sizes[0].value = 16; panel._sizes[1].value = 4; panel._sizes[2].value = 16
	panel._prepare(); panel.get_create_button().pressed.emit(); await frames(12)
	var empty := created.prop as EmberVoxelProp
	check(empty != null and empty.get_node("Collision/Shape").shape == null,"empty creation collider")
	var point: Vector2 = canvas._camera.unproject_position(Vector3(0.25,0,0.25)) * canvas._viewport_container.size / Vector2(canvas._viewport.size)
	check(canvas._pick_at(point).get("empty_floor",false),"empty Canvas ray target")
	canvas._begin_stroke(point); canvas._finish_stroke()
	check(canvas.save_changes() and empty.get_node("Collision/Shape").shape != null,"empty first-voxel Save/collision")
	EditorInterface.set_main_screen_editor("3D"); world.enabled.button_pressed = true; await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map,scene); var terrain_before: Terrain = draft.resource.working_copy()
	world.edit_region = Rect2i(0,0,24,24); world._open_terrain_generation(); importer._new_voxel_shape()
	panel._sizes[0].value = 10; panel._prepare(); panel.cancel_edit()
	check(world._terrain_workspace.visible and draft.resource.same_terrain_data(terrain_before),"Cancel lost terrain page / data")
	importer._new_voxel_shape(); panel._prepare(); importer._on_scene_changed(scene)
	check(not world._shape_mode and panel._root == null and panel.creation == null and panel._preview == null,"scene change retained stale creation")
	check(FileAccess.get_sha256(map.compact_terrain.resource_path) == terrain_hash and projection.built_tile_count() == built,"form UI changed / remeshed terrain")
	_camera.queue_free()
	print("VOXEL_SHAPE_DOCK_NATIVE ","PASS" if errors.is_empty() else "FAIL"," layout/preview/repeat/guards/camera/collapse/Create/Canvas/Undo-Redo/Save-Reopen/Cancel/empty-first-voxel/terrain-return/scene-change/no-remesh errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
