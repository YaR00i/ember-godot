@tool
extends "res://tools/editor_test_compact_section_selection.gd"
## Run only in the disposable QA checkout, never in the author's editor.

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	# Stale local experiments can crash native Godot during filesystem refresh.
	# Keep this fixture independent; never alter or import the author's project.
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Dock QA requires isolating stale qa_selection experiments with a temporary .gdignore.")
		get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false, "importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete, "preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var id := "dock_native_" + str(OS.get_process_id())
	var creation := Creation.new()
	creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections(id, 2, 2, 48), creation.error)
	var paths: Array[String] = [creation.commit()]
	check(not paths[0].is_empty(), creation.error)
	EditorInterface.get_resource_filesystem().update_file(paths[0])
	print("TERRAIN_DOCK_STAGE fixture ", paths[0])
	await frames(10)
	EditorInterface.open_scene_from_path(paths[0])
	deadline = Time.get_ticks_msec() + 30000
	while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != paths[0]) and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(15); EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	check(scene != null and scene.scene_file_path == paths[0], "fixture did not open")
	if not errors.is_empty(): get_tree().quit(1); return
	var map := scene.get_node("Map") as EmberMapLoader
	var world: Node = importer._world_editor
	print("TERRAIN_DOCK_STAGE opened")
	world.enabled.button_pressed = true; print("TERRAIN_DOCK_STAGE enabled")
	world.scene_changed(scene); print("TERRAIN_DOCK_STAGE target")
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection)
	print("TERRAIN_DOCK_STAGE tiles")
	var draft: Dictionary = world.sessions.open_map(map, scene)
	var before: Terrain = draft.resource.working_copy()
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(1700, 1700, 1500), Vector3(650, 35, 380)); _camera.far = 8000; _camera.make_current()
	print("TERRAIN_DOCK_STAGE select")
	world.begin_section_selection(); drag(world, Vector2i(2, 0), Vector2i(2, 0)); key(world, KEY_ENTER)
	await frames(8)
	var panel: Control = world._generation_panel
	check(panel.is_visible_in_tree() and world.inspector_panel.is_ancestor_of(panel), "new sections did not open dock")
	check(not world.sidebar.visible and panel._back_button.visible, "terrain workspace did not free viewport")
	panel._preview_button.pressed.emit(); await ready_dialog(panel)
	print("TERRAIN_DOCK_STAGE preview")
	var candidate: Terrain = world._generation_context.candidate
	check(draft.resource.same_terrain_data(before), "preview changed terrain")
	await capture("dock_new_sections")
	panel.get_apply_button().pressed.emit(); await ready_tiles(projection)
	check(draft.resource == candidate and world.sidebar.visible and not panel.visible, "Apply did not use candidate or return tools")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await ready_tiles(projection); check(draft.resource.same_terrain_data(before), "section Undo")
	history.redo(); await ready_tiles(projection); check(draft.resource == candidate, "section Redo")
	print("TERRAIN_DOCK_STAGE undo-redo")
	check(world.sessions.save_all(scene), world.sessions.error)
	var reopened := (ResourceLoader.load(paths[0], "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_terrain.same_terrain_data(candidate), "section Save/Reopen")
	reopened.free()
	world.begin_section_selection(); drag(world, Vector2i(3, 0), Vector2i(3, 0)); key(world, KEY_ENTER)
	check(panel.visible and world._generation_context.addition, "second addition without leaving edit mode")
	panel.cancel_requested.emit()
	check(not panel.visible and world.sidebar.visible and draft.resource == candidate, "cancel changed source or left dock")
	world._open_terrain_plan(); world._plan_panel._buttons.add.pressed.emit()
	world._workspace_tools_button.pressed.emit()
	check(world._plan_selection.is_empty() and not world.selecting, "tools switch retained rectangle mode")
	world._open_terrain_generation(); panel._preview_button.pressed.emit(); await ready_dialog(panel)
	_camera.queue_free()
	var other := Creation.new(); other.scene_directory = creation.scene_directory; other.terrain_directory = creation.terrain_directory
	check(other.prepare_sections(id + "_other", 1, 1, 48), other.error)
	paths.append(other.commit()); check(not paths[1].is_empty(), other.error)
	EditorInterface.get_resource_filesystem().update_file(paths[1]); await frames(20)
	print("TERRAIN_DOCK_STAGE scene-switch ", paths[1])
	EditorInterface.open_scene_from_path(paths[1])
	deadline = Time.get_ticks_msec() + 30000
	while (world.scene == null or world.scene.scene_file_path != paths[1]) and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(8)
	check(world.scene.scene_file_path == paths[1] and world.map.map_id == id + "_other", "scene target not switched")
	check(not panel.visible and not world._terrain_workspace.visible and world._generation_preview == null and world._generation_job == null, "old preview survived scene switch")
	print("TERRAIN_DOCK_NATIVE ", "PASS" if errors.is_empty() else "FAIL", " sections/repeat/preview/Apply/Undo-Redo/Save-Reopen/cancel/Tools/scene-switch errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)

func capture(name: String) -> void:
	await frames(5)
	await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("res://qa_generation/" + name + ".png")
