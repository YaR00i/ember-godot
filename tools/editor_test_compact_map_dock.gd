@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
## Native map creation routes; only disposable QA scenes and resources.

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Map dock QA requires isolating stale qa_selection experiments."); get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false, "importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete, "preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600, 900))
	EditorInterface.set_main_screen_editor("3D")
	var world: Node = importer._world_editor
	check(not world.active, "fixture must start outside world edit mode")
	var initial_root := EditorInterface.get_edited_scene_root()
	importer._new_compact_map(); await frames(8)
	var panel: Control = importer._compact_map_panel
	check(panel.is_visible_in_tree() and importer._world_editor_dock_added and not world.active, "creation dock unavailable outside edit mode")
	check(not importer._voxel_object_toolbar.visible, "creation retained wide object toolbar")
	check(world.inspector_panel.is_ancestor_of(panel) and not world._workspace_tabs.visible, "creation outside existing dock")
	panel._id_field.text = "invalid/name"; panel._preview_button.pressed.emit()
	check(panel.get_create_button().disabled and not panel._status.text.is_empty(), "invalid ID not reported")
	var id := "map_dock_" + str(OS.get_process_id())
	panel.creation.scene_directory = "res://qa_generation/scenes"; panel.creation.terrain_directory = "res://qa_generation/terrains"
	panel._id_field.text = id; panel._height.value = 48; panel._preview_button.pressed.emit()
	var candidate: Terrain = panel.creation.source
	var path: String = panel.creation.scene_path(); var terrain_path: String = panel.creation.terrain_path()
	check(candidate != null and not FileAccess.file_exists(path) and not FileAccess.file_exists(terrain_path), "preview wrote files")
	importer._new_compact_map()
	check(importer._compact_map_panel == panel and panel.creation.source == candidate, "repeated +Map reset or duplicated panel")
	await frames(8)
	check(EditorInterface.get_base_control().get_global_rect().encloses(panel.get_global_rect()), "creation dock outside editor")
	panel._scroll.scroll_vertical = 10000; await frames(5)
	check(panel.get_global_rect().encloses(panel.get_create_button().get_global_rect()), "Create lost while scrolling")
	await capture("new_map_dock", panel)
	panel.get_create_button().pressed.emit()
	deadline = Time.get_ticks_msec() + 30000
	while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != path) and Time.get_ticks_msec() < deadline: await frames(1)
	check(EditorInterface.get_edited_scene_root() != initial_root and EditorInterface.get_edited_scene_root().scene_file_path == path, "Create did not open new scene")
	check(importer._compact_map_panel == null and not importer._world_editor_dock_added, "Create left temporary dock")
	check(importer._voxel_object_toolbar.visible, "creation did not restore toolbar visibility")
	if not errors.is_empty(): get_tree().quit(1); return
	await frames(12)
	var scene := EditorInterface.get_edited_scene_root()
	var map := scene.get_node("Map") as EmberMapLoader
	check(map.compact_terrain.same_terrain_data(candidate.sectioned_copy()), "created scene differs from preview")
	world.enabled.button_pressed = true
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map, scene)
	var before: Terrain = draft.resource.working_copy()
	var index: int = before.column_index(192, 192)
	world._compact_brush.configure(draft, get_undo_redo(), scene)
	check(world._compact_brush.begin("raise", 1, 4, 2, 0, 32, 2, 371, 0, -99999, "coarse", "square", 4), "brush begin")
	world._compact_brush.stamp(Vector2i(192, 192)); world._compact_brush.end(); await ready_tiles(projection)
	var edited_height: int = draft.resource.column_value("heights", index)
	check(edited_height > before.column_value("heights", index) and world.sessions.dirty_count(scene) > 0, "dirty map fixture not edited")
	var hash := FileAccess.get_sha256(terrain_path)
	world._open_terrain_generation(); world._generation_panel._fields.seed.value = 321
	importer._new_compact_map(); panel = importer._compact_map_panel
	panel.creation.scene_directory = "res://qa_generation/scenes"; panel.creation.terrain_directory = "res://qa_generation/terrains"
	panel._id_field.text = id; panel._prepare()
	check(panel.get_create_button().disabled and FileAccess.get_sha256(terrain_path) == hash, "duplicate overwrote map")
	panel._id_field.text = id + "_cancel"; panel._preset.select(1); panel._preset_changed(1); panel._prepare()
	var cancelled_path: String = panel.creation.scene_path()
	check(panel._texture.texture != null and not panel.get_create_button().disabled, "coast preview failed")
	var orbit := InputEventMouseMotion.new(); orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(importer._forward_3d_gui_input(null, orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS, "creation blocked camera")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	check(importer._forward_3d_gui_input(null, click) == EditorPlugin.AFTER_GUI_INPUT_PASS and not world._compact_brush.active(), "creation painted old map")
	await capture("new_map_coast_dock", panel)
	panel.cancel_requested.emit(); await frames(6)
	check(importer._compact_map_panel == null and world.active and world._generation_panel.is_visible_in_tree(), "cancel did not restore previous page")
	check(world._generation_panel._fields.seed.value == 321 and world._generation_panel.get_apply_button().disabled, "cancel lost settings or restored stale Apply")
	check(draft.resource.column_value("heights", index) == edited_height and world.sessions.dirty_count(scene) > 0 and FileAccess.get_sha256(terrain_path) == hash, "cancel lost or saved dirty terrain")
	check(not FileAccess.file_exists(cancelled_path), "Cancel created file")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await ready_tiles(projection); check(draft.resource.same_terrain_data(before), "brush Undo after map cancel")
	history.redo(); await ready_tiles(projection); check(draft.resource.column_value("heights", index) == edited_height, "brush Redo after map cancel")
	check(world.sessions.save_all(scene), world.sessions.error)
	var reopened := (ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_terrain.column_value("heights", index) == edited_height, "Save/Reopen after map cancel")
	reopened.free(); world.sessions.discard(scene); world._deactivate()
	var empty := Node3D.new(); empty.name = "EmptyDockFixture"
	var packed := PackedScene.new(); packed.pack(empty); empty.free()
	var empty_path := "res://qa_generation/scenes/" + id + "_empty.tscn"
	check(ResourceSaver.save(packed, empty_path) == OK, "empty fixture save")
	EditorInterface.get_resource_filesystem().update_file(empty_path); await frames(8)
	EditorInterface.open_scene_from_path(empty_path)
	deadline = Time.get_ticks_msec() + 30000
	while world.scene == null or world.scene.scene_file_path != empty_path:
		if Time.get_ticks_msec() >= deadline: check(false, "empty fixture open timeout"); break
		await frames(1)
	check(world.map == null and not world.active, "empty fixture contains map")
	importer._new_compact_map(); await frames(6)
	check(importer._compact_map_panel.is_visible_in_tree() and importer._world_editor_dock_added, "creation requires existing map")
	EditorInterface.open_scene_from_path(path)
	await frames(15)
	check(importer._compact_map_panel == null and not world._map_creation_mode and not importer._world_editor_dock_added, "scene switch retained creation")
	print("COMPACT_MAP_DOCK_NATIVE ", "PASS" if errors.is_empty() else "FAIL", " preview/Create/flat/coast/duplicate/cancel/dirty-preservation/Undo-Redo/Save-Reopen/repeat/empty-scene/camera/scene-switch errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
