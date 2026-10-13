@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const OUTPUT="C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs"
func geometry(projection,preview: Node=null) -> Dictionary:
	var data: Dictionary={}
	for key: Vector2i in projection._tiles:
		var tile: Node=projection._tiles[key] if preview==null else preview.get_node_or_null("PreviewTile_%d_%d"%[key.x,key.y])
		if tile==null:continue
		var mesh: ArrayMesh=tile.get_node("Ground").mesh if preview==null else tile.get_child(0,true).mesh
		data[key]=mesh.surface_get_arrays(0) if mesh.get_surface_count()>0 else []
	return data
func snapshot(name: String) -> void:
	await frames(6);await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OUTPUT+"/generation-split-"+name+".png")
func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"):return
	await frames(20)
	var importer:=get_parent().get_node_or_null("EmberImportPlugin")
	if importer==null:check(false,"importer missing");get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline:await frames(1)
	check(importer._editor_preparation._complete,"preparation")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900))
	var probe=load("res://scenes/compact_smooth_tools_study.tscn").instantiate()
	var prefix: String="qa_split_"+str(OS.get_process_id())
	var source_path: String="res://content/world_terrains/"+prefix+".res"
	var scene_path: String="res://scenes/"+prefix+".tscn"
	check(ResourceSaver.save(probe.baseline_terrain.working_copy(),source_path)==OK,"private painted source")
	probe.get_node("Map").compact_terrain=ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var packed:=PackedScene.new();packed.pack(probe);check(ResourceSaver.save(packed,scene_path)==OK,"private scene");probe.free()
	EditorInterface.get_resource_filesystem().update_file(source_path);EditorInterface.get_resource_filesystem().update_file(scene_path)
	await frames(8);EditorInterface.open_scene_from_path(scene_path)
	deadline=Time.get_ticks_msec()+60000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=scene_path) and Time.get_ticks_msec()<deadline:await frames(1)
	await frames(12);EditorInterface.set_main_screen_editor("3D")
	var scene:=EditorInterface.get_edited_scene_root();check(scene!=null,"scene open")
	if scene==null:get_tree().quit(1);return
	var map:=scene.get_node("Map") as EmberMapLoader
	var world: Node=importer._world_editor;world.enabled.button_pressed=true;world.scene_changed(scene)
	world.category.select(0);world._category_changed(0)
	var projection:=map._visual_surface_projection as EmberTerrainPilotProjection;await ready_tiles(projection)
	_camera=Camera3D.new();EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.fov=40;_camera.look_at_from_position(Vector3(14,10,14),Vector3(4,1.8,4));_camera.make_current()
	var original: Terrain=world.sessions.open_map(map,scene).resource.working_copy()
	var original_hash:=FileAccess.get_sha256(source_path)
	world.edit_region=Rect2i(0,0,8,8);world._open_terrain_generation()
	var dialog: Control=world._generation_panel
	dialog._operation.select(1);dialog._operation.item_selected.emit(1)
	dialog._surface_fields.surface_strength.value=75;dialog._surface_fields.surface_scale.value=1.2;dialog._surface_fields.surface_seed.value=777
	check(not dialog._macro_grid.visible and dialog._surface_box.visible,"native detail-only controls")
	dialog._preview_button.pressed.emit();await ready_dialog(dialog)
	check(FileAccess.get_sha256(source_path)==original_hash,"preview does not write authored source")
	var candidate: Terrain=world._generation_context.candidate
	check(candidate.dense_window(Rect2i(0,0,128,128)).top_materials==original.top_materials,"native detail preserves painted cover")
	var preview_mesh:=geometry(projection,world._generation_preview)
	dialog._surface_fields.surface_seed.value=778
	check(world._generation_preview==null and dialog.get_apply_button().disabled,"detail knob invalidates stale preview")
	dialog._surface_fields.surface_seed.value=777;dialog._preview_button.pressed.emit();await ready_dialog(dialog)
	candidate=world._generation_context.candidate;preview_mesh=geometry(projection,world._generation_preview)
	dialog._scroll.scroll_vertical=0;await snapshot("detail-panel")
	dialog.get_apply_button().pressed.emit();await ready_tiles(projection)
	var entry: Dictionary=world.sessions.open_map(map,scene)
	check(entry.resource==candidate and geometry(projection)==preview_mesh,"native detail preview/Apply exact candidate")
	var detail: Terrain=entry.resource.working_copy()
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();await ready_tiles(projection);check(entry.resource.same_terrain_data(original),"one detail Undo")
	history.redo();await ready_tiles(projection);check(entry.resource.same_terrain_data(detail),"detail Redo")
	var detail_params: Dictionary=dialog.parameters()
	var coverage_params:=detail_params.duplicate(true);coverage_params.merge({"terrain_operation":"coverage","coverage_seed":732,"coverage_scale":2.0,"coverage_sea_m":0.0},true)
	var plan:=Plan.new();plan.regions=[{"id":"detail","name":"Фактура","enabled":true,"kind":"generation","bounds":Rect2i(0,0,8,8),"parameters":detail_params},{"id":"coverage","name":"Покрытия","enabled":true,"kind":"generation","bounds":Rect2i(0,0,8,8),"parameters":coverage_params}]
	plan.schema_version=Plan.VERSION
	check(world.commit_terrain_plan(map,plan).is_empty(),"native operations Plan create")
	world._open_terrain_plan();world._terrain_plan_action("generate","coverage","")
	check(dialog._operation.selected==2 and dialog._coverage_grid.visible and not dialog._surface_box.visible,"native Plan restores separate coverage operation")
	dialog._coverage_fields.coverage_seed.value=765;dialog._plan_save_button.pressed.emit()
	check(Plan.read(map).regions[1].parameters.coverage_seed==765,"coverage settings Save in Plan")
	history.undo();check(Plan.read(map).regions[1].parameters.coverage_seed==732,"coverage Plan Undo")
	history.redo();check(Plan.read(map).regions[1].parameters.coverage_seed==765,"coverage Plan Redo")
	dialog._preview_button.pressed.emit();await ready_dialog(dialog)
	candidate=world._generation_context.candidate
	check(candidate.dense_window(Rect2i(0,0,128,128)).heights==detail.dense_window(Rect2i(0,0,128,128)).heights,"coverage does not reshape terrain")
	check(candidate.dense_window(Rect2i(0,0,128,128)).top_materials!=detail.dense_window(Rect2i(0,0,128,128)).top_materials,"coverage explicitly changes paint")
	preview_mesh=geometry(projection,world._generation_preview)
	dialog._scroll.scroll_vertical=0;await snapshot("coverage-panel")
	dialog.get_apply_button().pressed.emit();await ready_tiles(projection)
	check(geometry(projection)==preview_mesh,"native coverage preview/Apply parity")
	var covered: Terrain=entry.resource.working_copy()
	history.undo();await ready_tiles(projection);check(entry.resource.same_terrain_data(detail),"one coverage Undo")
	history.redo();await ready_tiles(projection);check(entry.resource.same_terrain_data(covered),"coverage Redo")
	world._close_generation_panel();check(world.sessions.save_all(scene),world.sessions.error)
	var reopened=(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_terrain.same_terrain_data(covered),"native terrain Save/Reopen")
	check(Plan.read(reopened.get_node("Map")).regions[0].parameters.terrain_operation=="detail" and Plan.read(reopened.get_node("Map")).regions[1].parameters.coverage_seed==765,"native recipes Save/Reopen")
	reopened.free()
	world._apply_generated_terrain(map,entry,original);world.sessions.discard(scene);await ready_tiles(projection)
	check(entry.resource.same_terrain_data(covered),"native Discard")
	_camera.queue_free();await frames(10)
	print("GENERATION_SPLIT_EDITOR ","PASS" if errors.is_empty() else "FAIL"," detail/coverage/paint/preview/Apply/Undo/Redo/Plan/Save/Reopen/Discard ",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
