@tool
extends "res://tools/editor_test_terrain_plan_grove.gd"
func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	Engine.max_fps = 30; await frames(25)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	check(EditorInterface.get_open_scenes().size() == 1,"more than one test scene open")
	var path := "res://qa_generation/scenes/placement_native.tscn"
	var scene := EditorInterface.get_edited_scene_root()
	check(scene != null and scene.scene_file_path == path,"prepared fixture not open")
	if not errors.is_empty(): get_tree().quit(1); return
	EditorInterface.set_main_screen_editor("3D")
	var map := scene.get_node("Map") as EmberMapLoader; var projection := map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection)
	var world: Node = importer._world_editor; world.enabled.button_pressed = true; await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map,scene); var original: Resource = draft.resource.working_copy()
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(projection.to_global(Vector3(300,500,500)),projection.to_global(Vector3(192,96,192))); _camera.far = 5000; _camera.make_current()
	world._open_terrain_plan(); var panel: Control = world._plan_panel
	if OS.get_environment("EMBER_PLACEMENT_CAPTURE_ONLY") == "1":
		panel._buttons.generate.pressed.emit(); var current_dialog: Control = world._generation_panel
		current_dialog._preview_button.pressed.emit(); await ready_grove(current_dialog)
		check(current_dialog._source_selection.text.contains("3 / 4"),"selected set summary missing")
		await capture("placement_panel",current_dialog); _camera.queue_free()
		print("PLACEMENT_PANEL ","PASS" if errors.is_empty() else "FAIL"," errors=",errors); get_tree().quit(0 if errors.is_empty() else 1); return
	panel._buttons.add_placement.pressed.emit(); select_rect(world,Rect2i(3,3,18,18)); await frames(8)
	check(Plan.read(map).regions[0].kind == "placement","generic region missing")
	panel._buttons.generate.pressed.emit(); var dialog: Control = world._generation_panel
	check(dialog._placement_mode and world.inspector_panel.is_ancestor_of(dialog),"generic panel outside common dock")
	var ids := PackedStringArray(["vox_tree_120664056","vox_vil_bush","vox_qa_placement_rock"])
	dialog.open_placement(Rect2i(3,3,18,18),Plan.read(map).regions[0].parameters,Grove.choices(true))
	for i in dialog._grove_choice_ids.size():
		if dialog._grove_choice_ids[i] in ids: dialog._grove_choices.select(i,false)
	dialog._grove_fields.density.value = 100; dialog._grove_fields.spacing_m.value = 4
	check(dialog.parameters().model_ids.size() == 3,"mixed catalog selection failed")
	dialog._source_filter.select(3); dialog._filter_sources(); check(dialog.parameters().model_ids.size() == 3,"type filter erased choices")
	dialog._source_filter.select(0); dialog._filter_sources()
	dialog._plan_save_button.pressed.emit(); check(map.get_node("Props").get_child_count() == 0,"recipe Save creates props")
	dialog._preview_button.pressed.emit(); await ready_grove(dialog)
	var job: RefCounted = world._generation_context.grove_prepared; var count: int = job.placements.size(); var models := {}
	for spec in job.placements: models[spec.model_id] = true
	check(count > 3 and count <= 20 and models.size() == 3,"mixed native preview lacks sources")
	var preview_mesh := world._generation_preview.get_child(0).get_node("Mesh").mesh as Mesh
	await capture("placement_preview",dialog)
	dialog._grove_fields.clearance_m.value = 0.6; check(dialog.get_apply_button().disabled and world._generation_preview == null,"clearance did not invalidate preview")
	dialog._grove_fields.clearance_m.value = 0.5; dialog._preview_button.pressed.emit(); await ready_grove(dialog)
	dialog.get_apply_button().pressed.emit(); await frames(6)
	var applied: Resource = Plan.read(map); var members: Array = applied.object_layers[applied.regions[0].id]
	check(members.size() == count and map.get_node("Props").get_child_count() == count,"mixed Apply != preview")
	var prop := map.get_node("Props").get_node(NodePath(members[0].id)) as EmberVoxelProp
	check(prop.get_node("Mesh").mesh == preview_mesh and Grove.fingerprint(prop,map,job._frame) == members[0].expected,"mixed geometry/pose mismatch")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await frames(4); check(map.get_node("Props").get_child_count() == 0 and Plan.read(map).object_layers.is_empty(),"generic Undo not atomic")
	history.redo(); await frames(4); check(map.get_node("Props").get_child_count() == count,"generic Redo failed")
	world._open_terrain_plan(); panel._buttons.generate.pressed.emit(); dialog._preview_button.pressed.emit(); await ready_grove(dialog)
	dialog.get_apply_button().pressed.emit(); await frames(4); check(Plan.same(Plan.read(map),applied),"generic repeat changed state")
	prop.position.x += 8; var manual := prop.position
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.groves.pressed.emit()
	dialog._preview_button.pressed.emit(); await ready_grove(dialog); dialog.get_apply_button().pressed.emit(); await frames(4)
	check(map.get_node("Props").get_child_count() == 1 and prop.position == manual,"generic off erased manual prop")
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.groves.pressed.emit()
	dialog._preview_button.pressed.emit(); await ready_grove(dialog); dialog.get_apply_button().pressed.emit(); await frames(4)
	check(prop.position == manual and draft.resource.same_terrain_data(original),"generic re-enable lost manual prop or changed ground")
	check(world.save_all(),world.sessions.error)
	var saved := Grove.pose_version(map); var saved_plan: Resource = Plan.read(map).working_copy()
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),saved_plan) and reopened.get_node("Map/Props").get_child_count() == map.get_node("Props").get_child_count(),"fresh disk lost generic plan/props"); reopened.free()
	prop.position.x += 5; world.sessions.discard(scene); await frames(4); check(Grove.pose_version(map) == saved,"generic Discard failed")
	scene.get_node("Map/Regions/PlayerStart").position = Vector3(48,110,48)
	var playback := Node.new(); playback.name = "PlacementPlaybackCheck"; playback.set_script(load("res://tools/test_terrain_plan_grove_playback.gd")); playback.result_file = "user://placement-playback-"+str(OS.get_process_id())+".json"
	scene.add_child(playback); playback.owner = scene; check(EditorInterface.save_scene() == OK,"save playback fixture")
	await capture("placement_applied"); _camera.queue_free()
	print("PLACEMENT_NATIVE ","PASS" if errors.is_empty() else "FAIL"," count=",count," models=",models.keys()," errors=",errors)
	if not errors.is_empty(): get_tree().quit(1); return
	EditorInterface.play_current_scene(); deadline = Time.get_ticks_msec()+45000
	while not FileAccess.file_exists(playback.result_file) and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(playback.result_file),"F6 result missing")
	if FileAccess.file_exists(playback.result_file):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(playback.result_file)); check(result.get("ok",false),str(result)); print("PLACEMENT_F6_RESULT ",result)
	EditorInterface.stop_playing_scene(); await frames(8)
	print("PLACEMENT_F6 ","PASS" if errors.is_empty() else "FAIL"," errors=",errors); get_tree().quit(0 if errors.is_empty() else 1)
