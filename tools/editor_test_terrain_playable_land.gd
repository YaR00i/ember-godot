@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const Plan = preload("res://scripts/ember_terrain_plan_resource.gd")
const TerrainMath = preload("res://scripts/prototypes/ember_terrain_generation_math.gd")
func capture(name: String,_panel: Control = null) -> void:
	await frames(5); await RenderingServer.frame_post_draw
	var path := "user://"+name+"-"+str(OS.get_process_id())+".png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
	print("PLAYABLE_LAND_CAPTURE ",ProjectSettings.globalize_path(path))
func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		printerr("Playable land QA requires isolating stale qa_selection experiments."); get_tree().quit(1); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600,900))
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("qa_plains_"+str(OS.get_process_id()),2,2,48),creation.error)
	var path: String = creation.commit(); check(not path.is_empty(),creation.error)
	EditorInterface.get_resource_filesystem().update_file(path); await frames(10); EditorInterface.open_scene_from_path(path)
	deadline = Time.get_ticks_msec()+30000
	while (EditorInterface.get_edited_scene_root() == null or EditorInterface.get_edited_scene_root().scene_file_path != path) and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(15); EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root(); check(scene != null and scene.scene_file_path == path,"fixture open")
	if not errors.is_empty(): get_tree().quit(1); return
	var world: Node = importer._world_editor; var map := scene.get_node("Map") as EmberMapLoader
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection; await ready_tiles(projection)
	world.enabled.button_pressed = true; await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map,scene); var before: Terrain = draft.resource.working_copy()
	var hash := FileAccess.get_sha256(map.compact_terrain.resource_path)
	var plan := Plan.new(); var values := TerrainMath.DEFAULTS.duplicate(); values.profile = "plains"; values.merge(TerrainMath.PLAINS_DEFAULTS)
	values.flat_fraction = 0.95; values.flat_size_m = 24.0; values.micro_m = 0.0; values.land_fraction = 0.9
	plan.regions = [{"id":"game","name":"Игровая суша","bounds":Rect2i(0,0,48,48),"parameters":values}]
	check(world.commit_terrain_plan(map,plan).is_empty(),"plan commit")
	world._open_terrain_plan(); world._terrain_plan_action("generate","game",""); await frames(8)
	var panel: Control = world._generation_panel
	check(panel._plains_grid.is_visible_in_tree() and world.inspector_panel.is_ancestor_of(panel),"profile fields outside dock")
	panel._plains_fields.flat_fraction.value = 80
	panel._plan_save_button.pressed.emit()
	check(is_equal_approx(Plan.read(map).regions[0].parameters.flat_fraction,0.8) and draft.resource.same_terrain_data(before),"recipe Save changed terrain / lost setting")
	world._terrain_plan_action("generate","game",""); panel = world._generation_panel
	check(panel._plains_fields.flat_fraction.value == 80,"saved recipe did not reopen")
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(700,600,850),Vector3(384,65,384)); _camera.far = 8000; _camera.make_current()
	panel._preview_button.pressed.emit(); await ready_dialog(panel)
	var first: Terrain = world._generation_context.candidate
	check(first != null and draft.resource.same_terrain_data(before) and FileAccess.get_sha256(map.compact_terrain.resource_path) == hash,"preview changed source")
	panel._plains_fields.micro_m.value = 0.2
	check(panel.get_apply_button().disabled and world._generation_preview == null,"field retained stale preview")
	panel._plains_fields.micro_m.value = 0.0
	panel._preview_button.pressed.emit(); await ready_dialog(panel)
	check(world._generation_context.candidate.same_terrain_data(first),"repeat preview changed result")
	panel._scroll.scroll_vertical = 10000; await frames(4)
	check(panel.get_global_rect().encloses(panel.get_apply_button().get_global_rect()) and panel.get_global_rect().encloses(panel._preview_button.get_global_rect()),"actions outside footer")
	panel._scroll.scroll_vertical = 0
	var camera_input := InputEventMouseMotion.new(); camera_input.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(importer._forward_3d_gui_input(_camera,camera_input) == EditorPlugin.AFTER_GUI_INPUT_PASS,"camera blocked")
	await capture("playable_land_preview",panel)
	panel._scroll.scroll_vertical = int(panel._plains_grid.position.y)
	await capture("playable_land_controls",panel)
	panel.cancel_requested.emit(); check(world._generation_preview == null and draft.resource.same_terrain_data(before),"Cancel changed terrain")
	world._terrain_plan_action("generate","game",""); panel = world._generation_panel
	panel._preview_button.pressed.emit(); await ready_dialog(panel)
	var candidate: Terrain = world._generation_context.candidate
	var mesh := world._generation_preview.get_node("PreviewTile_6_6").get_child(0,true) as MeshInstance3D
	var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	panel.get_apply_button().pressed.emit(); await ready_tiles(projection)
	check(draft.resource == candidate,"Apply did not use candidate")
	var ground := projection._tiles[Vector2i(6,6)].get_node("Ground") as MeshInstance3D
	check(ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices,"preview != applied geometry")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await ready_tiles(projection); check(draft.resource.same_terrain_data(before),"one terrain Undo")
	history.redo(); await ready_tiles(projection); check(draft.resource.same_terrain_data(candidate),"terrain Redo")
	var result_path := "user://playable-land-"+str(OS.get_process_id())+".json"
	var playback := Node.new(); playback.name = "PlayableLandCheck"; playback.set_script(load("res://tools/test_terrain_playable_land_playback.gd")); playback.result_file = result_path
	scene.add_child(playback); playback.owner = scene
	check(world.sessions.save_all(scene),world.sessions.error)
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_terrain.same_terrain_data(candidate) and is_equal_approx(Plan.read(reopened.get_node("Map")).regions[0].parameters.flat_fraction,0.8),"Save-Reopen terrain/recipe"); reopened.free()
	world._apply_generated_terrain(map,draft,before); world.sessions.discard(scene); await ready_tiles(projection)
	check(draft.resource.same_terrain_data(candidate) and world.sessions.dirty_count(scene) == 0,"Discard after applying different terrain")
	await capture("playable_land_applied"); _camera.queue_free()
	print("PLAYABLE_LAND_NATIVE ","PASS" if errors.is_empty() else "FAIL"," plan/fields/repeat/cancel/preview=Apply/Undo-Redo/Save-Reopen/Discard/camera/layout errors=",errors)
	if not errors.is_empty(): get_tree().quit(1); return
	EditorInterface.play_current_scene(); deadline = Time.get_ticks_msec()+90000
	while not FileAccess.file_exists(result_path) and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(result_path),"F6 result missing")
	if FileAccess.file_exists(result_path):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path)); check(result.get("ok",false),"F6: "+str(result)); print("PLAYABLE_LAND_F6_RESULT ",result)
	EditorInterface.stop_playing_scene(); await frames(8)
	print("PLAYABLE_LAND_F6 ","PASS" if errors.is_empty() else "FAIL"," errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
