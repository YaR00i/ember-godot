@tool
extends "res://tools/editor_test_terrain_plan_lake.gd"
func capture(name: String,_panel: Control = null) -> void:
	await frames(5)
	# The editor's camera replaces a test camera each frame. Match the actual
	# viewport immediately before drawing, as in the existing Canvas QA.
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	var previous := camera.global_transform
	camera.global_transform = _camera.global_transform; camera.far = _camera.far
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	RenderingServer.camera_set_transform(camera.get_camera_rid(),camera.get_camera_transform())
	RenderingServer.force_draw(false)
	var path := "user://"+name+"-"+str(OS.get_process_id())+".png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
	viewport.get_texture().get_image().save_png(path.get_basename()+"-viewport.png")
	camera.global_transform = previous
	print("RIVER_CAPTURE ",ProjectSettings.globalize_path(path))
func select_line(world: Node, points: PackedVector2Array, finish := true) -> void:
	var focus := EditorInterface.get_base_control().get_viewport().gui_get_focus_owner()
	if focus != null: focus.release_focus()
	for point in points:
		var cell := Vector2i(point*16); var index: int = world.entry.resource.column_index(cell.x,cell.y)
		var height: int = maxi(world.entry.resource.column_value("heights",index),world.entry.resource.column_value("water_levels",index))+world.entry.resource.origin_y
		var position: Vector3 = world.map._visual_surface_projection.to_global(Vector3(point.x*16,height,point.y*16))
		var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = _camera.unproject_position(position)
		world.forward_input(_camera,click); click.pressed = false; world.forward_input(_camera,click)
	if finish:
		var enter := InputEventKey.new(); enter.pressed = true; enter.keycode = KEY_ENTER; world.forward_input(_camera,enter)
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
	check(creation.prepare_sections("river_native_"+str(OS.get_process_id()),2,2,96),creation.error)
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
	var trial := (load("res://materials/ember_compact_sky_reflection_study.tres") as ShaderMaterial).duplicate() as ShaderMaterial
	map.compact_water_visual_material = trial; projection._water_material = trial.duplicate()
	map.compact_water_mesh_step = 8; projection.water_mesh_step = 8; map.compact_water_volume_sides = true; projection.water_volume_sides = true
	var study := Node.new(); study.name = "PlanarReflection"; study.set_script(load("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")); scene.add_child(study); study.owner = scene
	deadline = Time.get_ticks_msec()+90000
	while not study.get("_prepared") and Time.get_ticks_msec() < deadline: await frames(1)
	check(study.get("_prepared"),"water preparation timeout")
	world.enabled.button_pressed = true; await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map,scene); var original: Resource = draft.resource.working_copy()
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(projection.to_global(Vector3(800,900,-200)),projection.to_global(Vector3(384,64,384))); _camera.far = 8000; _camera.make_current()
	world._open_terrain_plan(); var panel: Control = world._plan_panel
	panel._buttons.add_lake.pressed.emit(); select_rect(world,Rect2i(12,18,20,20)); await frames(8)
	panel._buttons.generate.pressed.emit(); var dialog: Control = world._generation_panel
	dialog._lake_fields.water_m.value = 5.0; dialog._lake_fields.shore_m.value = 3.0; dialog._plan_save_button.pressed.emit(); dialog.return_plan_requested.emit()
	var lake: Resource = Plan.read(map).working_copy()
	var points := PackedVector2Array([Vector2(22,28),Vector2(18,20),Vector2(25,13),Vector2(32,7),Vector2(34,3)])
	panel._buttons.add_river.pressed.emit(); select_line(world,PackedVector2Array([points[0],points[1]]),false)
	var back := InputEventKey.new(); back.pressed = true; back.keycode = KEY_BACKSPACE; world.forward_input(_camera,back)
	check(world._path_points.size() == 1,"Backspace line input")
	var motion := InputEventMouseMotion.new(); motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(world.forward_input(_camera,motion) == EditorPlugin.AFTER_GUI_INPUT_PASS,"river camera blocked")
	back.keycode = KEY_ESCAPE; world.forward_input(_camera,back)
	check(Plan.same(Plan.read(map),lake) and not world.selecting,"Esc changed source plan")
	panel._buttons.add_river.pressed.emit(); select_line(world,points); await frames(8)
	var plan: Resource = Plan.read(map)
	check(plan.regions.size() == 2 and plan.regions[1].kind == "river" and plan.regions[1].points_m == points,"native line selection "+str(plan.data()))
	check(draft.resource.same_terrain_data(original),"line commit changed terrain")
	if not errors.is_empty(): get_tree().quit(1); return
	panel._buttons.generate.pressed.emit()
	check(dialog._river_grid.is_visible_in_tree() and world.inspector_panel.is_ancestor_of(dialog),"river fields outside common dock")
	dialog._river_fields.flow.value = 0.7; dialog._plan_save_button.pressed.emit()
	check(draft.resource.same_terrain_data(original) and Plan.read(map).regions[1].parameters.flow == 0.7,"river recipe Save changed source")
	dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	var first: Resource = world._generation_context.candidate
	check(first != null and first.flow_at_cell(400,208).y < 0 and draft.resource.same_terrain_data(original),"preview direction/source")
	if first == null: get_tree().quit(1); return
	check(world._generation_preview._water_fields_ready,"river preview shader fields missing")
	var water: MeshInstance3D = world._generation_preview.get_node("PreviewTile_6_3").get_child(1,true)
	var vertices: PackedVector3Array = water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	await capture("river_preview",dialog)
	dialog._river_fields.width_m.value = 5.0; check(dialog.get_apply_button().disabled and world._generation_preview == null,"river stale Apply")
	dialog._river_fields.width_m.value = 4.0; dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	check(world._generation_context.candidate.same_terrain_data(first),"river repeat preview")
	dialog.get_apply_button().pressed.emit(); await ready_tiles(projection)
	check(draft.resource.same_terrain_data(first),"river Apply != preview")
	var applied: MeshInstance3D = projection._tiles[Vector2i(6,3)].get_node("Water")
	check(applied.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices,"river water mesh changed on Apply")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await ready_tiles(projection); check(draft.resource.same_terrain_data(original) and Plan.read(map).patches.is_empty(),"atomic river Undo")
	history.redo(); await ready_tiles(projection)
	world._open_terrain_plan(); panel._buttons.generate.pressed.emit(); await apply_regions(world)
	check(draft.resource.same_terrain_data(first),"native repeat river")
	world._open_terrain_plan(); panel._buttons.bounds.pressed.emit()
	var moved := PackedVector2Array([Vector2(22,28),Vector2(28,20),Vector2(37,13),Vector2(39,3)])
	select_line(world,moved); await frames(8); panel._buttons.generate.pressed.emit(); await apply_regions(world)
	check(draft.resource.flow_at_cell(400,208) == Vector2.ZERO and draft.resource.column_value("water_levels",draft.resource.column_index(400,208)) == 0,"native move left channel")
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.compose.pressed.emit(); await apply_regions(world)
	check(draft.resource.flow_at_cell(37*16,13*16) == Vector2.ZERO,"native off left flow")
	check(panel.selected_id() == plan.regions[1].id,"compose lost selected river")
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.bounds.pressed.emit(); select_line(world,points); await frames(8)
	panel._buttons.generate.pressed.emit(); await apply_regions(world)
	check(draft.resource.column_value("water_levels",draft.resource.column_index(352,448)) == 80 and draft.resource.flow_at_cell(400,208).y < 0,"final native river before Save")
	var marker := scene.get_node("Map/Regions/PlayerStart") as Node3D; marker.position = Vector3(112,110,384)
	var result_path := "user://river-playback-"+str(OS.get_process_id())+".json"
	var playback := Node.new(); playback.name = "RiverPlaybackCheck"; playback.set_script(load("res://tools/test_terrain_plan_river_playback.gd")); playback.result_file = result_path
	scene.add_child(playback); playback.owner = scene
	check(world.save_all(),world.sessions.error)
	var disk: Resource = ResourceLoader.load(draft.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	print("RIVER_SAVE_STATE draft=",draft.resource.flow_at_cell(400,208)," baseline=",draft.baseline.flow_at_cell(400,208)," disk=",disk.flow_at_cell(400,208)," path=",draft.path)
	check(disk.same_terrain_data(draft.resource),"fresh disk differs from saved draft")
	var saved: Resource = Plan.read(map).working_copy(); var saved_terrain: Resource = draft.resource.working_copy()
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),saved) and reopened.get_node("Map").compact_terrain.same_terrain_data(saved_terrain),"river Save/Reopen"); reopened.free()
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.compose.pressed.emit(); await apply_regions(world)
	world.sessions.discard(scene); await ready_tiles(projection)
	check(Plan.same(Plan.read(map),saved) and draft.resource.same_terrain_data(saved_terrain),"river Discard")
	await capture("river_applied"); _camera.queue_free()
	print("RIVER_NATIVE ","PASS" if errors.is_empty() else "FAIL"," input/params/preview/mesh/Undo/repeat/move/off/Save/Reopen/Discard errors=",errors)
	if not errors.is_empty(): get_tree().quit(1); return
	EditorInterface.play_current_scene(); deadline = Time.get_ticks_msec()+120000
	while not FileAccess.file_exists(result_path) and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(result_path),"river F6 result missing")
	if FileAccess.file_exists(result_path):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path)); check(result.get("ok",false),str(result)); print("RIVER_F6_RESULT ",result)
	EditorInterface.stop_playing_scene(); await frames(8)
	print("RIVER_F6 ","PASS" if errors.is_empty() else "FAIL"," errors=",errors); get_tree().quit(0 if errors.is_empty() else 1)
