@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")

func select_rect(world: Node, bounds: Rect2i) -> void:
	var focus := EditorInterface.get_base_control().get_viewport().gui_get_focus_owner()
	if focus != null: focus.release_focus()
	var press := InputEventMouseButton.new(); press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	var a: Vector3 = world._region_frame() * Vector3(bounds.position.x + 0.5, world._region_height(), bounds.position.y + 0.5)
	var b: Vector3 = world._region_frame() * Vector3(bounds.end.x - 0.5, world._region_height(), bounds.end.y - 0.5)
	press.position = _camera.unproject_position(a); world.forward_input(_camera, press)
	var motion := InputEventMouseMotion.new(); motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = _camera.unproject_position(b); world.forward_input(_camera, motion)
	press.position = motion.position; press.pressed = false; world.forward_input(_camera, press)
	print("PLAN_SELECTION_PROBE selecting=", world.selecting, " rect=", world.edit_region, " category=", world.category.selected, " active=", world.active, " mode=", world._plan_selection)

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args(): return
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	await frames(25)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	check(importer != null, "importer missing")
	if importer == null: get_tree().quit(1); return
	var preparation_deadline := Time.get_ticks_msec() + 90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < preparation_deadline: await frames(1)
	check(importer._editor_preparation._complete, "editor preparation timeout")
	await frames(10)
	var fixture_id := "plan_native_" + str(OS.get_process_id())
	var fixture_scene := SCENE.get_base_dir().path_join(fixture_id + ".tscn")
	var creation := Creation.new(); creation.scene_directory = SCENE.get_base_dir(); creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections(fixture_id, 2, 2, 12), creation.error)
	check(not creation.commit().is_empty(), creation.error)
	EditorInterface.get_resource_filesystem().update_file(fixture_scene)
	await frames(10)
	EditorInterface.open_scene_from_path(fixture_scene)
	var open_deadline := Time.get_ticks_msec() + 30000
	while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != fixture_scene) and Time.get_ticks_msec() < open_deadline:
		await frames(1)
	check(EditorInterface.get_edited_scene_root() != null and EditorInterface.get_edited_scene_root().scene_file_path == fixture_scene, "fixture scene did not open")
	if not errors.is_empty(): get_tree().quit(1); return
	await frames(20); EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root()
	var map := scene.get_node("Map") as EmberMapLoader
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	world.scene_changed(scene)
	world.category.select(0); world._category_changed(0)
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection)
	var initial: Terrain = world.sessions.open_map(map, scene).resource.working_copy()
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(1100, 1150, 1300), Vector3(384, 65, 384)); _camera.far = 8000; _camera.make_current()
	var hash := FileAccess.get_sha256(map.compact_terrain.resource_path)
	world._plan_button.pressed.emit(); await frames(8)
	var panel: Control = world._plan_panel
	check(panel.visible, "plan button did not open")
	panel._buttons.add.pressed.emit(); check(world._plan_selection == "add", "add button routing")
	world.category.select(3) # Plan selection must work even with object tools selected.
	select_rect(world, Rect2i(0, 0, 48, 48)); await frames(8)
	world.category.select(0)
	var plan: Resource = Plan.read(map)
	check(plan != null and plan.regions.size() == 1 and plan.regions[0].bounds == Rect2i(0, 0, 48, 48), "3D region selection")
	panel._name.text = "Главный остров"; panel._buttons.name.pressed.emit()
	check(Plan.read(map).regions[0].name == "Главный остров", "rename")
	panel._buttons.add.pressed.emit(); select_rect(world, Rect2i(3, 4, 9, 10)); await frames(8)
	check(Plan.read(map).regions.size() == 2, "second area")
	panel._buttons.bounds.pressed.emit(); select_rect(world, Rect2i(5, 4, 8, 12)); await frames(8)
	check(Plan.read(map).regions[1].bounds == Rect2i(5, 4, 8, 12), "resize")
	panel._buttons.delete.pressed.emit(); check(Plan.read(map).regions.size() == 1, "delete button routing")
	panel._buttons.add.pressed.emit()
	var esc := InputEventKey.new(); esc.keycode = KEY_ESCAPE; esc.pressed = true; world.forward_input(_camera, esc)
	check(world._plan_selection.is_empty() and panel.visible and Plan.read(map).regions.size() == 1, "selection cancel")
	await frames(8)
	var host := EditorInterface.get_base_control().size
	await check_dock(world, panel)
	await RenderingServer.frame_post_draw
	panel.get_viewport().get_texture().get_image().save_png("res://qa_generation/planner_panel.png")
	panel._buttons.generate.pressed.emit(); await frames(8)
	var dialog: Control = world._generation_panel
	check(dialog._fields.seed.value == 7 and dialog._plan_save_button.visible, "stored recipe not opened")
	dialog._fields.seed.value = 23; dialog._plan_save_button.pressed.emit()
	check(Plan.read(map).regions[0].parameters.seed == 23 and FileAccess.get_sha256(map.compact_terrain.resource_path) == hash, "save parameters changed terrain")
	dialog.hide(); world._open_terrain_plan(); panel._buttons.generate.pressed.emit()
	check(dialog._fields.seed.value == 23, "recipe lost on reopen")
	dialog._back_button.pressed.emit(); check(panel.visible, "return to plan")
	panel._buttons.generate.pressed.emit()
	await frames(8)
	await check_dock(world, dialog)
	await RenderingServer.frame_post_draw
	dialog.get_viewport().get_texture().get_image().save_png("res://qa_generation/planner_parameters.png")
	dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	var candidate: Terrain = world._generation_context.candidate
	check(world.sessions.open_map(map, scene).resource.same_terrain_data(initial), "preview changed terrain")
	dialog.get_apply_button().pressed.emit(); await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map, scene)
	check(draft.resource == candidate, "Apply lost candidate")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await ready_tiles(projection)
	check(draft.resource.same_terrain_data(initial), "terrain Undo")
	history.redo(); await ready_tiles(projection)
	var playback := Node.new(); playback.name = "GenerationPlaybackCheck"
	playback.set_script(load("res://tools/test_compact_terrain_generation_playback.gd")); scene.add_child(playback); playback.owner = scene
	check(world.sessions.save_all(scene), world.sessions.error)
	var saved_plan: Resource = Plan.read(map).working_copy()
	var reopened := (ResourceLoader.load(fixture_scene, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")), saved_plan), "native Save/Reopen plan")
	check(reopened.get_node("Map").compact_terrain.same_terrain_data(candidate), "native Save/Reopen terrain")
	reopened.free()
	world._open_terrain_plan(); panel._name.text = "Discard me"; panel._buttons.name.pressed.emit()
	world.sessions.discard(scene); await ready_tiles(projection)
	check(Plan.same(Plan.read(map), saved_plan) and panel._name.text == "Главный остров", "Discard plan/UI")
	panel.hide(); _camera.queue_free(); await frames(6)
	print("TERRAIN_PLAN_NATIVE ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
	var result_path := "res://qa_generation/play_result.json"
	if FileAccess.file_exists(result_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
	EditorInterface.play_current_scene()
	var deadline := Time.get_ticks_msec() + 60000
	while not FileAccess.file_exists(result_path) and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(result_path), "F6 result missing")
	await frames(3) # The playback creates the file before its writer closes it.
	if FileAccess.file_exists(result_path):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path)); check(result.get("ok", false), "F6: " + str(result))
	EditorInterface.stop_playing_scene(); await frames(5)
	print("TERRAIN_PLAN_F6 ", "PASS" if errors.is_empty() else "FAIL", " errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)
