@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const OUTPUT="C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs"
func water_geometry(projection: EmberTerrainPilotProjection, preview: Node=null) -> Dictionary:
	var result: Dictionary={}
	for key: Vector2i in projection._tiles:
		var mesh: ArrayMesh
		if preview!=null:
			var tile:=preview.get_node_or_null("PreviewTile_%d_%d"%[key.x,key.y])
			if tile==null:continue
			mesh=tile.get_child(1,true).mesh
		else:mesh=projection._tiles[key].get_node("Water").mesh
		result[key]=mesh.surface_get_arrays(0) if mesh.get_surface_count()>0 else []
	return result
func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"):return
	await frames(20)
	var importer:=get_parent().get_node_or_null("EmberImportPlugin")
	if importer==null:check(false,"importer missing");get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline:await frames(1)
	check(importer._editor_preparation._complete,"preparation")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900))
	var probe=load("res://scenes/compact_cartoon_generated_study.tscn").instantiate()
	var prefix: String="qa_surface_"+str(OS.get_process_id())
	var source_path: String="res://content/world_terrains/"+prefix+".res"
	var scene_path: String="res://scenes/"+prefix+".tscn"
	check(ResourceSaver.save(probe.get_node("Map").compact_terrain.working_copy(),source_path)==OK,"private source save")
	probe.get_node("Map").compact_terrain=ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var packed:=PackedScene.new();packed.pack(probe);check(ResourceSaver.save(packed,scene_path)==OK,"private scene save");probe.free()
	EditorInterface.get_resource_filesystem().update_file(source_path);EditorInterface.get_resource_filesystem().update_file(scene_path)
	await frames(8);EditorInterface.open_scene_from_path(scene_path)
	deadline=Time.get_ticks_msec()+60000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=scene_path) and Time.get_ticks_msec()<deadline:await frames(1)
	await frames(12);EditorInterface.set_main_screen_editor("3D")
	var scene:=EditorInterface.get_edited_scene_root();check(scene!=null,"native scene open")
	if scene==null:get_tree().quit(1);return
	var map:=scene.get_node("Map") as EmberMapLoader
	var world: Node=importer._world_editor;world.enabled.button_pressed=true;world.scene_changed(scene)
	world.category.select(0);world._category_changed(0)
	var projection:=map._visual_surface_projection as EmberTerrainPilotProjection;await ready_tiles(projection)
	_camera=Camera3D.new();EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(35,18,34),Vector3(12,1.5,8));_camera.far=200;_camera.make_current()
	var original: Terrain=world.sessions.open_map(map,scene).resource.working_copy()
	var original_water:=water_geometry(projection)
	var saved_hash:=FileAccess.get_sha256(source_path)
	world.edit_region=Rect2i(0,0,24,16);world._open_terrain_generation()
	var dialog: Control=world._generation_panel
	for key in {"seed":71,"sea_m":1.25,"land_m":0.9,"relief_m":2.5,"feature_m":11.0,"shore_m":2.4,"land_fraction":0.86}:
		dialog._fields[key].value={"seed":71,"sea_m":1.25,"land_m":0.9,"relief_m":2.5,"feature_m":11.0,"shore_m":2.4,"land_fraction":0.86}[key]
	dialog._surface_fields.surface_strength.value=70;dialog._surface_fields.surface_scale.value=1.0;dialog._surface_fields.surface_seed.value=731
	check(dialog._surface_fields.surface_scale.editable and dialog._surface_fields.surface_seed.editable,"native detail controls active")
	dialog._preview_button.pressed.emit();await ready_dialog(dialog)
	check(FileAccess.get_sha256(source_path)==saved_hash and world.sessions.dirty_count(scene)==0,"preview preserves original file/draft")
	dialog._surface_fields.surface_scale.value=1.5
	check(world._generation_preview==null and dialog.get_apply_button().disabled,"scale change invalidates preview")
	dialog._surface_fields.surface_seed.value=89
	dialog._preview_button.pressed.emit();await ready_dialog(dialog)
	var candidate: Terrain=world._generation_context.candidate
	var preview: Node=world._generation_preview
	var preview_arrays: Array=preview.get_node("PreviewTile_1_1").get_child(0,true).mesh.surface_get_arrays(0)
	var preview_water:=water_geometry(projection,preview)
	dialog._scroll.scroll_vertical=500;await frames(10);await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OUTPUT+"/terrain-surface-generator-panel.png")
	dialog.get_apply_button().pressed.emit();await ready_tiles(projection)
	var entry: Dictionary=world.sessions.open_map(map,scene)
	check(entry.resource==candidate and not dialog.visible,"Apply reuses candidate and closes panel")
	var applied: Array=projection._tiles[Vector2i(1,1)].get_node("Ground").mesh.surface_get_arrays(0)
	check(preview_arrays[Mesh.ARRAY_VERTEX]==applied[Mesh.ARRAY_VERTEX] and preview_arrays[Mesh.ARRAY_COLOR]==applied[Mesh.ARRAY_COLOR],"native smooth preview/Apply geometry/material parity")
	var applied_water:=water_geometry(projection)
	check(not preview_water.is_empty() and preview_water==applied_water,"native smooth shoreline preview/Apply parity")
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();await ready_tiles(projection);check(entry.resource.same_terrain_data(original),"one native Undo restores original terrain")
	check(water_geometry(projection)==original_water,"native shoreline Undo")
	history.redo();await ready_tiles(projection);check(entry.resource.same_terrain_data(candidate),"native terrain Redo")
	check(water_geometry(projection)==applied_water,"native shoreline Redo")
	var plan:=Plan.new();plan.regions=[{"id":"surface","name":"Фактура острова","kind":"generation","enabled":true,"bounds":Rect2i(0,0,24,16),"parameters":dialog.parameters()}]
	plan.schema_version=Plan.VERSION
	check(world.commit_terrain_plan(map,plan).is_empty(),"native plan create")
	world._open_terrain_plan();world._terrain_plan_action("generate","surface","")
	dialog._surface_fields.surface_strength.value=65;dialog._surface_fields.surface_scale.value=1.2;dialog._surface_fields.surface_seed.value=999
	dialog._plan_save_button.pressed.emit()
	check(Plan.read(map).regions[0].parameters.surface_seed==999 and Plan.read(map).regions[0].parameters.surface_scale==1.2,"native plan controls Save")
	history.undo();check(Plan.read(map).regions[0].parameters.surface_seed==89,"native plan settings Undo")
	history.redo();check(Plan.read(map).regions[0].parameters.surface_seed==999,"native plan settings Redo")
	world._close_generation_panel();check(world.sessions.save_all(scene),world.sessions.error)
	var reopened=(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_terrain.same_terrain_data(candidate),"native terrain Save/Reopen")
	check(Plan.read(reopened.get_node("Map")).regions[0].parameters.surface_seed==999,"native plan settings survive scene Reopen")
	reopened.free()
	world._apply_generated_terrain(map,entry,original);world.sessions.discard(scene);await ready_tiles(projection)
	check(entry.resource.same_terrain_data(candidate) and world.sessions.dirty_count(scene)==0,"native Discard")
	await frames(8);await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OUTPUT+"/terrain-surface-generator-applied.png")
	_camera.queue_free()
	print("SURFACE_GENERATOR_EDITOR ","PASS" if errors.is_empty() else "FAIL"," preview/Apply/Undo/Redo/plan/Save/Reopen/Discard errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
