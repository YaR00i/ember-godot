@tool
extends "res://tools/editor_test_terrain_plan_river.gd"
func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	Engine.max_fps = 60; await frames(25)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600,900))
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("road_native_"+str(OS.get_process_id()),2,2,96),creation.error)
	creation.source = creation.source.sectioned_copy()
	for key in creation.source.sections:
		if key.y != 0: continue
		var part: Resource = creation.source.sections[key].working_copy()
		for z in 6*16:
			for x in part.width:
				var i: int = x+z*part.width; part.heights[i] = 16; part.cap_depths[i] = 3; part.water_levels[i] = 32; part.water_materials[i] = 5
		creation.source.sections[key] = part
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
	var draft: Dictionary = world.sessions.open_map(map,scene); var original: Resource = draft.resource.working_copy()
	var soil: int = original.palette_surface_roles.find("soil"); var grass: int = original.palette_surface_roles.find("grass")
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(projection.to_global(Vector3(650,700,850)),projection.to_global(Vector3(384,120,384))); _camera.far = 8000; _camera.make_current()
	world._open_terrain_plan(); var panel: Control = world._plan_panel
	panel._buttons.add_mountain.pressed.emit(); select_rect(world,Rect2i(12,12,24,24)); await frames(8)
	panel._buttons.generate.pressed.emit(); var dialog: Control = world._generation_panel
	dialog._mountain_fields.slope_m.value = 10.0; dialog._plan_save_button.pressed.emit(); dialog.return_plan_requested.emit()
	var mountain: Resource = Plan.read(map).working_copy()
	var points := PackedVector2Array([Vector2(8,24),Vector2(18,24),Vector2(30,24),Vector2(40,24)])
	panel._buttons.add_road.pressed.emit(); select_line(world,PackedVector2Array([points[0],points[1]]),false)
	var key := InputEventKey.new(); key.pressed = true; key.keycode = KEY_BACKSPACE; world.forward_input(_camera,key)
	check(world._path_points.size() == 1,"road Backspace")
	var motion := InputEventMouseMotion.new(); motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(world.forward_input(_camera,motion) == EditorPlugin.AFTER_GUI_INPUT_PASS,"road camera blocked")
	key.keycode = KEY_ESCAPE; world.forward_input(_camera,key)
	check(Plan.same(Plan.read(map),mountain) and not world.selecting,"road Esc changed plan")
	panel._buttons.add_road.pressed.emit(); select_line(world,points); await frames(8)
	var plan: Resource = Plan.read(map)
	check(plan.regions.size() == 2 and plan.schema_version == Plan.VERSION and plan.regions[1].kind == "road" and plan.regions[1].points_m == points,"native road selection")
	check(draft.resource.same_terrain_data(original),"line changed terrain")
	if not errors.is_empty(): get_tree().quit(1); return
	panel._buttons.generate.pressed.emit()
	check(dialog._road_grid.is_visible_in_tree() and world.inspector_panel.is_ancestor_of(dialog),"road fields outside common dock")
	dialog._road_fields.edge_m.value = 2.5; dialog._plan_save_button.pressed.emit()
	check(draft.resource.same_terrain_data(original) and Plan.read(map).regions[1].parameters.edge_m == 2.5,"road recipe Save changed source")
	dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	var first: Resource = world._generation_context.candidate; var center: int = original.column_index(384,384)
	check(first != null and first.column_value("heights",center) == 96 and first.column_value("top_materials",center) == soil and draft.resource.same_terrain_data(original),"road preview core/source")
	if first == null: get_tree().quit(1); return
	var ground: MeshInstance3D = world._generation_preview.get_node("PreviewTile_6_6").get_child(0,true)
	var vertices: PackedVector3Array = ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	await capture("road_preview",dialog)
	dialog._road_fields.width_m.value = 5.0; check(dialog.get_apply_button().disabled and world._generation_preview == null,"road stale Apply")
	dialog._road_fields.width_m.value = 4.0; dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	check(world._generation_context.candidate.same_terrain_data(first),"road repeated preview")
	dialog.cancel_requested.emit(); check(draft.resource.same_terrain_data(original) and world._generation_preview == null,"road preview Cancel")
	world._terrain_plan_action("generate",plan.regions[1].id,""); dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	dialog.get_apply_button().pressed.emit(); await ready_tiles(projection)
	check(draft.resource.same_terrain_data(first),"road Apply != preview")
	check(projection._tiles[Vector2i(6,6)].get_node("Ground").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices,"road mesh changed on Apply")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await ready_tiles(projection); check(draft.resource.same_terrain_data(original) and Plan.read(map).patches.is_empty(),"road atomic Undo")
	history.redo(); await ready_tiles(projection)
	world._open_terrain_plan(); panel._buttons.generate.pressed.emit(); await apply_regions(world)
	check(draft.resource.same_terrain_data(first),"native road repeat")
	world._compact_brush.configure(draft,get_undo_redo(),scene)
	check(world._compact_brush.begin("lower",1,4,1,0,16,0,7,1,-99999,"detail","square",4),"manual road brush begin")
	world._compact_brush.stamp(Vector2i(288,384)); world._compact_brush.end(); await ready_tiles(projection)
	var manual: int = draft.resource.column_value("heights",draft.resource.column_index(288,384))
	world._open_terrain_plan(); panel._buttons.bounds.pressed.emit()
	var moved := PackedVector2Array([Vector2(8,36),Vector2(16,38),Vector2(32,34),Vector2(40,36)])
	select_line(world,moved); await frames(8); panel._buttons.generate.pressed.emit(); dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	check(world._generation_context.protected_blocks.size() > 0,"road protection markers")
	dialog.get_apply_button().pressed.emit(); await ready_tiles(projection)
	check(draft.resource.column_value("heights",center) == 192 and draft.resource.column_value("top_materials",center) == grass and draft.resource.column_value("heights",draft.resource.column_index(288,384)) == manual,"road move/manual restoration")
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.compose.pressed.emit(); await apply_regions(world)
	check(draft.resource.column_value("top_materials",draft.resource.column_index(40*16,36*16)) == grass and panel.selected_id() == plan.regions[1].id,"road off/selection")
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.bounds.pressed.emit()
	# The preserved hand-cut pit is hidden behind the restored mountain from
	# the oblique overview. Pick the intended, now visible surface from above.
	var overview_frame := _camera.global_transform
	_camera.look_at_from_position(projection.to_global(Vector3(384,1200,384)),projection.to_global(Vector3(384,120,384)),Vector3.FORWARD)
	select_line(world,points); _camera.global_transform = overview_frame; await frames(8)
	check(Plan.read(map).regions[1].points_m == points,"final visible path points")
	panel._buttons.generate.pressed.emit(); await apply_regions(world)
	check(draft.resource.column_value("heights",center) == 96 and draft.resource.column_value("top_materials",center) == soil,"final road absent")
	var marker := scene.get_node("Map/Regions/PlayerStart") as Node3D; marker.global_position = projection.to_global(Vector3(352,110,384))
	var result_path := "user://road-playback-"+str(OS.get_process_id())+".json"
	var playback := Node.new(); playback.name = "RoadPlaybackCheck"; playback.set_script(load("res://tools/test_terrain_plan_road_playback.gd")); playback.result_file = result_path
	scene.add_child(playback); playback.owner = scene
	check(world.save_all(),world.sessions.error)
	var disk: Resource = ResourceLoader.load(draft.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(disk.same_terrain_data(draft.resource),"road fresh disk differs from draft")
	var saved: Resource = Plan.read(map).working_copy(); var saved_terrain: Resource = draft.resource.working_copy()
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),saved) and reopened.get_node("Map").compact_terrain.same_terrain_data(saved_terrain),"road Save/Reopen"); reopened.free()
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.compose.pressed.emit(); await apply_regions(world)
	world.sessions.discard(scene); await ready_tiles(projection)
	check(Plan.same(Plan.read(map),saved) and draft.resource.same_terrain_data(saved_terrain),"road Discard")
	await capture("road_applied"); _camera.queue_free()
	print("ROAD_NATIVE ","PASS" if errors.is_empty() else "FAIL"," input/params/cancel/preview/mesh/Undo/repeat/brush/move/off/Save/Reopen/Discard errors=",errors)
	if not errors.is_empty(): get_tree().quit(1); return
	EditorInterface.play_current_scene(); deadline = Time.get_ticks_msec()+120000
	while not FileAccess.file_exists(result_path) and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(result_path),"road F6 result missing")
	if FileAccess.file_exists(result_path):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path)); check(result.get("ok",false),str(result)); print("ROAD_F6_RESULT ",result)
	EditorInterface.stop_playing_scene(); await frames(8)
	print("ROAD_F6 ","PASS" if errors.is_empty() else "FAIL"," errors=",errors); get_tree().quit(0 if errors.is_empty() else 1)
