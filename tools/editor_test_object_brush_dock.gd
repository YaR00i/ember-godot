@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"

const ShapeCreation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Object brush dock QA requires isolating stale qa_selection experiments."); get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false, "importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete, "preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600, 900))
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("qa_brush_" + str(OS.get_process_id()), 1, 1, 48), creation.error)
	var path: String = creation.commit(); check(not path.is_empty(), creation.error)
	EditorInterface.get_resource_filesystem().update_file(path); await frames(10); EditorInterface.open_scene_from_path(path)
	deadline = Time.get_ticks_msec() + 30000
	while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != path) and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(15); EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	check(scene != null and scene.scene_file_path == path, "fixture scene open")
	if not errors.is_empty(): get_tree().quit(1); return
	var world: Node = importer._world_editor
	var map := scene.get_node("Map") as EmberMapLoader
	var props := map.get_node("Props") as Node3D
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection)
	var built := projection.built_tile_count()
	var terrain_hash := FileAccess.get_sha256(map.compact_terrain.resource_path)
	var shape := ShapeCreation.new(); var folder := "user://ember-tests/object-dock-%d" % Time.get_ticks_usec()
	# The editor Inspector resolves canonical IDs. This disposable checkout alone
	# receives a unique canonical fixture; no author asset is replaced.
	shape.source_directory = "res://content/voxel_models"; shape.prefab_directory = folder.path_join("prefabs")
	check(shape.prepare("block", Vector3i(12, 3, 5), 16, Color("a86f45"), "Plank"), "shape fixture")
	var shape_undo := UndoRedo.new(); var original := shape.commit(scene, props, shape_undo, Vector3.ZERO)
	shape_undo.clear_history(); shape_undo.free()
	check(original != null, "shape commit")
	if original == null: get_tree().quit(1); return
	var packed := load(shape.prefab_directory.path_join(original.model_id + ".tscn")) as PackedScene
	var source_path := shape.source_directory.path_join(original.model_id + ".tres")
	var source_hash := FileAccess.get_sha256(source_path)
	var brush: Node = importer._object_brush
	check(brush.activate(scene, props, packed, original.model_id, get_undo_redo(), 16), "standalone activation")
	brush.spacing_blocks = 1.7; brush.yaw_degrees = 31; brush.scale_factor = 1.35; brush.bury_vox = 2
	importer._open_object_brush_settings(); await frames(10)
	check(not world.active and world._object_brush_mode and importer._world_editor_dock_added, "standalone settings did not open dock")
	check(world._object_brush_body.is_ancestor_of(world.object_parameters) and world._object_brush_title.text.contains(original.model_id), "shared controls / asset title")
	check(EditorInterface.get_base_control().get_global_rect().encloses(world.inspector_panel.get_global_rect()), "dock outside native editor shell")
	for property in ["spacing_blocks", "yaw_degrees", "scale_factor", "bury_vox"]:
		check(is_equal_approx(world._object_brush_controls[property].value, brush.get(property)), "stale displayed value: " + property)
		check(world.inspector_panel.get_global_rect().encloses(world._object_brush_controls[property].get_global_rect()), "field outside dock: " + property)
	brush._append(Vector3(64, 48, 64)); world._object_brush_controls.yaw_degrees.value = -27
	check(brush._transforms.is_empty() and is_equal_approx(brush.yaw_degrees, -27), "parameter edit committed / retained stale preview")
	world._object_brush_scroll.scroll_vertical = 10000; await frames(4)
	check(world.inspector_panel.get_global_rect().encloses(world._object_brush_stop.get_global_rect()), "Stop outside pinned footer")
	world._object_brush_scroll.scroll_vertical = 0
	importer._open_object_brush_settings(); await frames(4)
	check(world._object_brush_body.get_child_count() == 3 and is_equal_approx(world._object_brush_controls.yaw_degrees.value, -27), "reopen duplicated / reset fields")
	var pane: Control = world._object_brush_workspace
	var pane_parent := pane.get_parent(); var pane_index := pane.get_index()
	var narrow := VBoxContainer.new(); narrow.size = Vector2(302, 600)
	var theme := Theme.new(); theme.default_font_size = 20; narrow.theme = theme
	EditorInterface.get_base_control().add_child(narrow); pane.reparent(narrow)
	await frames(5)
	check(pane.get_combined_minimum_size().x <= 302 and narrow.get_global_rect().encloses(world._object_brush_stop.get_global_rect()), "302 px fields/footer overflow")
	pane.reparent(pane_parent); pane_parent.move_child(pane, pane_index); narrow.free(); await frames(5)
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(620, 740, 720), Vector3(192, 48, 192)); _camera.far = 8000; _camera.make_current()
	await frames(5); await get_tree().physics_frame
	var orbit := InputEventMouseMotion.new(); orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(importer._forward_3d_gui_input(_camera, orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS, "camera blocked")
	var hit: Dictionary = brush._ray(Vector3(192, 200, 192), Vector3(192, -100, 192))
	check(not hit.is_empty(), "physical terrain hit missing")
	if not hit.is_empty():
		var before := props.get_child_count()
		var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = _camera.unproject_position(hit.position)
		check(importer._forward_3d_gui_input(_camera, click) == EditorPlugin.AFTER_GUI_INPUT_STOP and brush._dragging, "dock input did not reach brush")
		var preview: Transform3D = brush._transforms[0] if not brush._transforms.is_empty() else Transform3D.IDENTITY
		click.pressed = false; importer._forward_3d_gui_input(_camera, click)
		check(props.get_child_count() == before + 1 and brush.active, "real viewport placement failed")
		check(props.get_child(-1).global_transform.is_equal_approx(preview), "preview differs from commit")
		var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
		history.undo(); check(props.get_child_count() == before, "stroke Undo")
		history.redo(); check(props.get_child_count() == before + 1, "stroke Redo")
		EditorInterface.save_scene()
		var reopened := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
		check(reopened.get_node("Map/Props").get_child_count() == props.get_child_count(), "Save-Reopen instances")
		reopened.free()
	await capture("object_brush_dock", world.inspector_panel)
	brush._append(Vector3(64, 48, 64)); var count := props.get_child_count()
	world._object_brush_stop.pressed.emit(); await frames(4)
	check(not brush.active and not world._object_brush_mode and not importer._world_editor_dock_added, "Stop left settings active")
	check(world.object_parameters.get_parent() == world._object_parameters_parent and world.object_parameters.get_index() == world._object_parameters_index, "Stop did not restore shared controls")
	check(props.get_child_count() == count and brush._transforms.is_empty(), "Stop committed unfinished stroke")
	world.enabled.button_pressed = true; await ready_tiles(projection)
	check(brush.activate(scene, props, packed, original.model_id, get_undo_redo(), 16), "world activation")
	world.remember_object(original.model_id); importer._open_object_brush_settings(); await frames(6)
	check(world.active and not world._object_brush_mode and world.category.selected == 3 and world.object_parameters.is_visible_in_tree(), "world brush did not use existing Tools")
	check(is_equal_approx(world._object_brush_controls.yaw_degrees.value, -27), "world controls lost standalone settings")
	world._category_changed(0); check(not brush.active, "terrain switch retained object input")
	world._deactivate(); check(brush.activate(scene, props, packed, original.model_id, get_undo_redo(), 16), "Escape activation")
	importer._open_object_brush_settings()
	var escape := InputEventKey.new(); escape.pressed = true; escape.keycode = KEY_ESCAPE
	check(importer._forward_3d_gui_input(_camera, escape) == EditorPlugin.AFTER_GUI_INPUT_STOP and not brush.active and not world._object_brush_mode, "Escape retained dock")
	check(brush.activate(scene, props, packed, original.model_id, get_undo_redo(), 16), "scene change activation")
	importer._open_object_brush_settings(); importer._new_compact_map(); await frames(5)
	check(not brush.active and not world._object_brush_mode and world._map_creation_mode and not importer._voxel_object_toolbar.visible, "new-map switch restored competing toolbar / kept object input")
	importer._cancel_compact_map_creation(); await frames(3)
	check(importer._voxel_object_toolbar.visible, "new-map Cancel lost original toolbar")
	check(brush.activate(scene, props, packed, original.model_id, get_undo_redo(), 16), "scene change reactivation")
	importer._open_object_brush_settings(); importer._on_scene_changed(scene)
	check(not brush.active and not world._object_brush_mode and world.object_parameters.get_parent() == world._object_parameters_parent, "scene change retained brush / detached controls")
	check(FileAccess.get_sha256(source_path) == source_hash and FileAccess.get_sha256(map.compact_terrain.resource_path) == terrain_hash and projection.built_tile_count() == built, "settings changed source / terrain / mesh")
	_camera.queue_free()
	print("OBJECT_BRUSH_DOCK_NATIVE ", "PASS" if errors.is_empty() else "FAIL", " layout/sync/pinned/camera/placement/preview/Undo-Redo/Save-Reopen/Stop/Escape/world/scene-change/no-remesh errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
