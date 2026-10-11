@tool
extends "res://tools/editor_test_terrain_plan.gd"
func capture(name: String,_panel: Control = null) -> void:
	await frames(5); await RenderingServer.frame_post_draw
	var path := "user://"+name+"-"+str(OS.get_process_id())+".png"
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)
	print("LAKE_CAPTURE ",ProjectSettings.globalize_path(path))
func apply_regions(world: Node) -> void:
	world._generation_panel._preview_button.pressed.emit(); await ready_dialog(world._generation_panel)
	world._generation_panel.get_apply_button().pressed.emit(); await ready_tiles(world.map._visual_surface_projection)
func ready_dialog(dialog: Control) -> void:
	# Native QA may run behind another GPU application. Bound wall time while
	# retaining the real preview-ready gate, rather than treating frame counts
	# or editor background sleep as computation time.
	var deadline := Time.get_ticks_msec()+180000
	while dialog.get_apply_button().disabled and Time.get_ticks_msec() < deadline: await frames(1)
	check(not dialog.get_apply_button().disabled,"preview timeout: "+dialog._status.text)
func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	Engine.max_fps = 60
	if FileAccess.file_exists("res://qa_selection/portable_world.gd") and not FileAccess.file_exists("res://qa_selection/.gdignore"):
		check(false,"isolate stale QA experiments"); get_tree().quit(1); return
	await frames(25)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); DisplayServer.window_set_size(Vector2i(1600,900))
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("lake_native_"+str(OS.get_process_id()),2,2,96),creation.error)
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
	map.compact_water_mesh_step = 8; projection.water_mesh_step = 8
	map.compact_water_volume_sides = true; projection.water_volume_sides = true
	var study := Node.new(); study.name = "PlanarReflection"; study.set_script(load("res://scripts/prototypes/ember_compact_planar_reflection_study.gd")); scene.add_child(study); study.owner = scene
	deadline = Time.get_ticks_msec()+90000
	while not study.get("_prepared") and Time.get_ticks_msec() < deadline: await frames(1)
	check(study.get("_prepared"),"water preparation timeout")
	world.enabled.button_pressed = true; await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map,scene); var original: Resource = draft.resource.working_copy()
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(950,750,1000),Vector3(384,64,384)); _camera.far = 8000; _camera.make_current()
	world._open_terrain_plan(); var panel: Control = world._plan_panel
	panel._buttons.add_lake.pressed.emit(); select_rect(world,Rect2i(12,12,24,24)); await frames(8)
	var plan: Resource = Plan.read(map)
	check(plan != null and plan.schema_version == Plan.VERSION and plan.regions[0].kind == "lake","native lake selection")
	if plan == null: get_tree().quit(1); return
	panel._buttons.generate.pressed.emit(); var dialog: Control = world._generation_panel
	dialog._lake_fields.water_m.value = 5.0; dialog._lake_fields.shore_m.value = 3.0
	dialog._plan_save_button.pressed.emit()
	check(draft.resource.same_terrain_data(original) and Plan.read(map).regions[0].parameters.water_m == 5.0,"recipe Save changed terrain")
	world._terrain_plan_action("generate",plan.regions[0].id,"")
	check(dialog._lake_grid.is_visible_in_tree() and world.inspector_panel.is_ancestor_of(dialog),"lake fields outside dock")
	dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	var first: Resource = world._generation_context.candidate; var center: int = original.column_index(384,384)
	check(first != null and first.column_value("water_levels",center) == 80 and draft.resource.same_terrain_data(original),"preview lake/source")
	if first == null: get_tree().quit(1); return
	dialog._lake_fields.depth_m.value = 2.25
	check(dialog.get_apply_button().disabled and world._generation_preview == null,"lake stale preview")
	dialog._lake_fields.depth_m.value = 2.0; dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	check(world._generation_context.candidate.same_terrain_data(first),"repeat preview")
	var mesh_node: Node = world._generation_preview.get_node("PreviewTile_6_6")
	var water := mesh_node.get_child(1,true) as MeshInstance3D
	check(world._generation_preview._water_fields != null and world._generation_preview._water_fields_ready,"candidate water fields missing")
	if world._generation_preview._water_fields == null:
		print("LAKE_MATERIAL_DEBUG projection=",projection._water_material," shader=",(projection._water_material as ShaderMaterial).shader.resource_path if projection._water_material is ShaderMaterial else "standard"," study=",study.get("_material")," context=",world._generation_context.keys())
		get_tree().quit(1); return
	check(world._generation_preview._water_fields.sample(Vector2i(384,384)).is_empty(),"closed lake classified as sea in preview")
	var vertices: PackedVector3Array = water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var motion := InputEventMouseMotion.new(); motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	check(importer._forward_3d_gui_input(_camera,motion) == EditorPlugin.AFTER_GUI_INPUT_PASS,"lake camera blocked")
	await capture("lake_preview",dialog)
	dialog.cancel_requested.emit(); check(draft.resource.same_terrain_data(original) and world._generation_preview == null,"lake cancel")
	world._terrain_plan_action("generate",plan.regions[0].id,""); dialog._preview_button.pressed.emit()
	deadline = Time.get_ticks_msec()+60000
	while world._generation_preview == null and Time.get_ticks_msec() < deadline: await frames(1)
	await frames(2); var cancel_started := Time.get_ticks_usec(); dialog.cancel_requested.emit()
	print("LAKE_PREVIEW_CANCEL_MS ",(Time.get_ticks_usec()-cancel_started)/1000.0)
	check(world._generation_preview == null and draft.resource.same_terrain_data(original),"cancel pending water worker")
	world._terrain_plan_action("generate",plan.regions[0].id,""); dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	dialog.get_apply_button().pressed.emit(); await ready_tiles(projection)
	check(draft.resource.same_terrain_data(first),"Apply did not use exact candidate")
	var applied_water := projection._tiles[Vector2i(6,6)].get_node("Water") as MeshInstance3D
	check(applied_water != null and applied_water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices,"water preview != applied mesh")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await ready_tiles(projection); check(draft.resource.same_terrain_data(original) and Plan.read(map).patches.is_empty(),"atomic lake Undo")
	history.redo(); await ready_tiles(projection)
	world._open_terrain_plan(); panel._buttons.generate.pressed.emit(); await apply_regions(world)
	check(draft.resource.same_terrain_data(first),"lake repeat accumulated")
	world._compact_brush.configure(draft,get_undo_redo(),scene)
	check(world._compact_brush.begin("raise",1,4,1,0,16,0,7,1,-99999,"detail","square",4),"manual brush begin")
	world._compact_brush.stamp(Vector2i(384,384)); world._compact_brush.end(); await ready_tiles(projection)
	var manual_height: int = draft.resource.column_value("heights",center); check(manual_height > 48,"manual lake brush")
	world._open_terrain_plan(); panel._buttons.bounds.pressed.emit(); select_rect(world,Rect2i(30,30,12,12)); await frames(8)
	panel._buttons.generate.pressed.emit(); dialog._preview_button.pressed.emit(); await ready_dialog(dialog)
	check(world._generation_context.protected_blocks.size() > 0,"lake protected markers")
	await capture("lake_protected",dialog)
	dialog.get_apply_button().pressed.emit(); await ready_tiles(projection)
	check(draft.resource.column_value("heights",center) == manual_height and draft.resource.column_value("water_levels",original.column_index(20*16,24*16)) == 0,"lake move/manual restoration")
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.compose.pressed.emit(); await apply_regions(world)
	check(draft.resource.column_value("water_levels",original.column_index(36*16,36*16)) == 0,"lake disabled water remains")
	# Return to the main lake for Save/Reopen/F6.
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.bounds.pressed.emit(); select_rect(world,Rect2i(12,12,24,24)); await frames(8)
	panel._buttons.generate.pressed.emit(); await apply_regions(world)
	var marker := scene.get_node("Map/Regions/PlayerStart") as Node3D; marker.position = Vector3(112,110,384)
	var result_path := "user://lake-playback-"+str(OS.get_process_id())+".json"
	var playback := Node.new(); playback.name = "LakePlaybackCheck"; playback.set_script(load("res://tools/test_terrain_plan_lake_playback.gd")); playback.result_file = result_path
	scene.add_child(playback); playback.owner = scene
	check(world.sessions.save_all(scene),world.sessions.error)
	var saved: Resource = Plan.read(map).working_copy(); var saved_terrain: Resource = draft.resource.working_copy()
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),saved) and reopened.get_node("Map").compact_terrain.same_terrain_data(saved_terrain),"lake Save/Reopen"); reopened.free()
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.compose.pressed.emit(); await apply_regions(world)
	world.sessions.discard(scene); await ready_tiles(projection)
	check(Plan.same(Plan.read(map),saved) and draft.resource.same_terrain_data(saved_terrain),"lake Discard")
	await capture("lake_applied"); _camera.queue_free()
	print("LAKE_NATIVE ","PASS" if errors.is_empty() else "FAIL"," selection/params/source/cancel/mesh/Undo/repeat/move/brush/off/Save/Reopen/Discard errors=",errors)
	if not errors.is_empty(): get_tree().quit(1); return
	EditorInterface.play_current_scene(); deadline = Time.get_ticks_msec()+120000
	while not FileAccess.file_exists(result_path) and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(result_path),"lake F6 result missing")
	if FileAccess.file_exists(result_path):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(result_path)); check(result.get("ok",false),str(result)); print("LAKE_F6_RESULT ",result)
	EditorInterface.stop_playing_scene(); await frames(8)
	print("LAKE_F6 ","PASS" if errors.is_empty() else "FAIL"," errors=",errors); get_tree().quit(0 if errors.is_empty() else 1)
