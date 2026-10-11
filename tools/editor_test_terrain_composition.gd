@tool
extends "res://tools/editor_test_terrain_plan.gd"

func apply_plateaus(world: Node) -> void:
	world._generation_panel._preview_button.pressed.emit()
	await ready_dialog(world._generation_panel)
	world._generation_panel.get_apply_button().pressed.emit()
	check(not world._generation_panel.visible, "composition OK did not commit")
	await ready_tiles(world.map._visual_surface_projection)

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	await frames(25)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600, 900))
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false, "importer missing"); get_tree().quit(1); return
	var preparation_deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < preparation_deadline: await frames(1)
	check(importer._editor_preparation._complete, "editor preparation timeout")
	await frames(10)
	var id := "plateau_native_" + str(OS.get_process_id())
	var path := SCENE.get_base_dir().path_join(id + ".tscn")
	var creation := Creation.new(); creation.scene_directory = SCENE.get_base_dir(); creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections(id, 2, 2, 48), creation.error)
	check(not creation.commit().is_empty(), creation.error)
	EditorInterface.get_resource_filesystem().update_file(path); await frames(10)
	EditorInterface.open_scene_from_path(path)
	var deadline := Time.get_ticks_msec() + 30000
	while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != path) and Time.get_ticks_msec() < deadline: await frames(1)
	check(EditorInterface.get_edited_scene_root() != null and EditorInterface.get_edited_scene_root().scene_file_path == path, "fixture did not open")
	if not errors.is_empty(): get_tree().quit(1); return
	await frames(20); EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	var map := scene.get_node("Map") as EmberMapLoader
	check(map.map_id == id and scene.scene_file_path == path, "editor switched away from fixture")
	if not errors.is_empty(): get_tree().quit(1); return
	var world: Node = importer._world_editor; world.enabled.button_pressed = true; world.scene_changed(scene); world.category.select(0)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map, scene)
	var original: Terrain = draft.resource.working_copy()
	var index: int = original.column_index(384, 384)
	var untouched: Node = projection._tiles[Vector2i.ZERO]
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(1100, 1150, 1300), Vector3(384, 65, 384)); _camera.far = 8000; _camera.make_current()
	world._open_terrain_plan(); var panel: Control = world._plan_panel
	print("COMPOSITION_PROBE before map=", map.map_id, " world=", world.map.map_id, " plan=", Plan.read(map))
	panel._buttons.add_plateau.pressed.emit(); print("COMPOSITION_PROBE action=", world._plan_selection)
	select_rect(world, Rect2i(16, 16, 16, 16)); await frames(8)
	print("COMPOSITION_PROBE after=", Plan.read(map).regions)
	check(Plan.read(map).schema_version == 2 and Plan.read(map).regions[0].get("kind", "") == "plateau", "native plateau creation")
	if not errors.is_empty(): get_tree().quit(1); return
	panel._buttons.generate.pressed.emit(); await frames(8)
	var dialog: Control = world._generation_panel
	dialog._plateau_fields.height_m.value = 4; dialog._plateau_fields.transition_m.value = 4
	dialog._plan_save_button.pressed.emit()
	check(draft.resource.same_terrain_data(original), "saving settings changed terrain")
	await frames(8)
	await check_dock(world, dialog)
	var orbit := InputEventMouseMotion.new(); orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(world.forward_input(_camera, orbit) == EditorPlugin.AFTER_GUI_INPUT_PASS, "dock blocked camera")
	var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	click.position = _camera.unproject_position(Vector3(384, 48, 384))
	check(world.forward_input(_camera, click) == EditorPlugin.AFTER_GUI_INPUT_PASS and not world._compact_brush.active(), "recipe viewport click painted terrain")
	if not errors.is_empty(): await capture("dock_layout_failure", dialog); get_tree().quit(1); return
	await RenderingServer.frame_post_draw; dialog.get_viewport().get_texture().get_image().save_png("res://qa_generation/plateau_parameters.png")
	dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	dialog._plateau_fields.height_m.value = 4.25
	check(world._generation_preview == null and world._generation_job == null and dialog.get_apply_button().disabled, "field change left stale candidate")
	dialog.cancel_requested.emit(); await frames(5)
	check(panel.is_visible_in_tree() and not dialog.visible and draft.resource.same_terrain_data(original), "cancel did not return to unchanged plan")
	panel._buttons.generate.pressed.emit(); dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	var first: Terrain = world._generation_context.candidate
	var preview_ground := world._generation_preview.get_node("PreviewTile_6_6").get_child(0, true) as MeshInstance3D
	var vertices: PackedVector3Array = preview_ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(first.column_value("heights", index) == 64 and draft.resource.column_value("heights", index) == 48, "plateau preview")
	await capture("plateau_preview", dialog)
	dialog.get_apply_button().pressed.emit(); await ready_tiles(projection)
	check(draft.resource == first and projection._tiles[Vector2i.ZERO] == untouched, "exact candidate or untouched tile rebuilt")
	var applied_ground := projection._tiles[Vector2i(6, 6)].get_node("Ground") as MeshInstance3D
	check(applied_ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices, "plateau preview/mesh mismatch")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await ready_tiles(projection)
	check(draft.resource.same_terrain_data(original) and Plan.read(map).patches.is_empty(), "atomic native Undo")
	history.redo(); await ready_tiles(projection)
	world._open_terrain_plan(); panel._buttons.generate.pressed.emit(); await apply_plateaus(world)
	check(draft.resource.same_terrain_data(first), "native repeat accumulated")
	world._compact_brush.configure(draft, get_undo_redo(), scene)
	check(world._compact_brush.begin("raise", 1, 4, 1, 0, 16, 0, 7, 1, -99999, "detail", "square", 4), "manual brush begin")
	world._compact_brush.stamp(Vector2i(384, 384)); world._compact_brush.end(); await ready_tiles(projection)
	var manual_height: int = draft.resource.column_value("heights", index)
	check(manual_height > 64, "manual brush no effect")
	world._open_terrain_plan(); panel._buttons.bounds.pressed.emit(); select_rect(world, Rect2i(32, 16, 12, 16)); await frames(8)
	panel._buttons.generate.pressed.emit(); dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	check(world._generation_context.protected_blocks.size() > 0, "manual protection missing")
	await capture("plateau_protected", dialog)
	dialog.get_apply_button().pressed.emit(); await ready_tiles(projection)
	check(draft.resource.column_value("heights", index) == manual_height, "move erased manual edit")
	check(draft.resource.column_value("heights", original.column_index(320, 384)) == 48, "old footprint remained")
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.compose.pressed.emit(); await apply_plateaus(world)
	check(draft.resource.column_value("heights", index) == manual_height and draft.resource.column_value("heights", original.column_index(600, 384)) == 48, "disable/manual protection")
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.bounds.pressed.emit(); select_rect(world, Rect2i(16, 16, 16, 16)); await frames(8)
	panel._buttons.generate.pressed.emit(); await apply_plateaus(world)
	var playback := Node.new(); playback.name = "GenerationPlaybackCheck"; playback.set_script(load("res://tools/test_terrain_composition_playback.gd")); scene.add_child(playback); playback.owner = scene
	check(world.sessions.save_all(scene), world.sessions.error)
	var saved: Resource = Plan.read(map).working_copy()
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := packed.instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")), saved), "native provenance Save/Reopen")
	reopened.free()
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.compose.pressed.emit(); await apply_plateaus(world)
	world.sessions.discard(scene); await ready_tiles(projection)
	check(Plan.same(Plan.read(map), saved) and draft.resource.column_value("heights", index) == manual_height, "native composition Discard")
	panel.hide(); _camera.queue_free(); await frames(6)
	print("TERRAIN_COMPOSITION_NATIVE ", "PASS" if errors.is_empty() else "FAIL", " fixture=", path, " errors=", errors)
	var result_path := "res://qa_generation/play_result.json"
	if FileAccess.file_exists(result_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
	EditorInterface.play_current_scene(); deadline = Time.get_ticks_msec() + 100000
	while not FileAccess.file_exists(result_path) and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(3); check(FileAccess.file_exists(result_path), "F6 result missing")
	if FileAccess.file_exists(result_path):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path)); check(result.get("ok", false), "F6: " + str(result))
	EditorInterface.stop_playing_scene(); await frames(5)
	print("TERRAIN_COMPOSITION_F6 ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
