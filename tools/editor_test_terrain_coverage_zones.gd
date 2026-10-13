@tool
extends "res://tools/editor_test_terrain_generation_split.gd"
func snapshot(name: String) -> void:
	await frames(5)
	var importer:=get_parent().get_node_or_null("EmberImportPlugin")
	if importer!=null:importer._world_editor._clear_compact_grid_overlay()
	var viewport:=EditorInterface.get_editor_viewport_3d(0);var camera:=viewport.get_camera_3d();var previous:=camera.global_transform
	camera.global_transform=_camera.global_transform;camera.far=_camera.far
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	RenderingServer.camera_set_transform(camera.get_camera_rid(),camera.get_camera_transform());RenderingServer.force_draw(false)
	viewport.get_texture().get_image().save_png(OUTPUT+"/coverage-zones-"+name+".png")
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OUTPUT+"/coverage-zones-"+name+"-panel.png")
	camera.global_transform=previous
func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"):return
	await frames(20);var importer:=get_parent().get_node_or_null("EmberImportPlugin")
	if importer==null:check(false,"importer missing");get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline:await frames(1)
	check(importer._editor_preparation._complete,"preparation")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900))
	var probe=load("res://scenes/compact_cartoon_generated_study.tscn").instantiate()
	var prefix: String="qa_coverage_zones_"+str(OS.get_process_id())
	var source_path: String="res://content/world_terrains/"+prefix+".res";var scene_path: String="res://scenes/"+prefix+".tscn"
	check(ResourceSaver.save(probe.get_node("Map").compact_terrain.working_copy(),source_path)==OK,"private source")
	probe.get_node("Map").compact_terrain=load(source_path)
	var packed:=PackedScene.new();packed.pack(probe);check(ResourceSaver.save(packed,scene_path)==OK,"private scene");probe.free()
	EditorInterface.get_resource_filesystem().update_file(source_path);EditorInterface.get_resource_filesystem().update_file(scene_path)
	await frames(8);EditorInterface.open_scene_from_path(scene_path)
	deadline=Time.get_ticks_msec()+60000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=scene_path) and Time.get_ticks_msec()<deadline:await frames(1)
	await frames(12);EditorInterface.set_main_screen_editor("3D")
	var scene:=EditorInterface.get_edited_scene_root();var map:=scene.get_node("Map") as EmberMapLoader
	var world: Node=importer._world_editor;world.enabled.button_pressed=true;world.scene_changed(scene)
	var projection:=map._visual_surface_projection as EmberTerrainPilotProjection;await ready_tiles(projection)
	_camera=Camera3D.new();EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.fov=45;_camera.far=5000;_camera.look_at_from_position(Vector3(32,24,30),Vector3(12,3,8));_camera.make_current()
	var entry: Dictionary=world.sessions.open_map(map,scene);var original: Terrain=entry.resource.working_copy()
	await snapshot("before")
	# Exercise the real paint input adapter, including atomic protection Undo.
	world.category.select(1);world._category_changed(1)
	var soil_slot: int=original.palette_surface_roles.find("soil")
	for i in world.palette.item_count:
		if world.palette.get_item_metadata(i)==soil_slot:world.palette.select(i)
	world.radius.value=0.75;world.camera=_camera
	var position:=_camera.get_viewport().get_visible_rect().size*0.5;var pick: Dictionary=world._pick_compact(position)
	check(not pick.is_empty(),"paint pick")
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.button_mask=MOUSE_BUTTON_MASK_LEFT;press.position=position
	world._forward_compact(press);check(world._compact_brush.active(),"native paint starts")
	var release:=InputEventMouseButton.new();release.button_index=MOUSE_BUTTON_LEFT;release.position=position
	world._forward_compact(release);await ready_tiles(projection)
	var manual_plan: Resource=Plan.read(map);check(manual_plan!=null and not manual_plan.paint_locks.is_empty(),"native paint creates protection")
	var painted: Terrain=entry.resource.working_copy()
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();await ready_tiles(projection);check(entry.resource.same_terrain_data(original) and Plan.read(map)==null,"native paint/protection one Undo")
	history.redo();await ready_tiles(projection);check(entry.resource.same_terrain_data(painted) and Plan.same(Plan.read(map),manual_plan),"native paint/protection Redo")
	world.edit_region=Rect2i(0,0,24,16);world._open_terrain_generation()
	var dialog: Control=world._generation_panel;dialog._operation.select(2);dialog._operation.item_selected.emit(2)
	check(dialog.parameters().coverage_profile=="large" and dialog._coverage_zone_grid.visible,"native large zones controls")
	dialog._paint_protect.pressed.emit();check(Plan.paint_locked(Plan.read(map).paint_locks,Vector2i(300,200)),"native protect selection")
	history.undo();check(Plan.same(Plan.read(map),manual_plan),"native selection protection Undo")
	dialog._coverage_fields.coverage_zone_m.value=12;dialog._coverage_fields.coverage_soil_amount.value=20;dialog._coverage_fields.coverage_stone_slope.value=35;dialog._coverage_fields.coverage_sand_width_m.value=1.5
	dialog._preview_button.pressed.emit();await ready_dialog(dialog)
	if not errors.is_empty():get_tree().quit(1);return
	var candidate: Terrain=world._generation_context.candidate
	check(candidate.dense_window(Rect2i(0,0,384,256)).heights==painted.dense_window(Rect2i(0,0,384,256)).heights,"native zones preserve detailed geometry")
	for key: Vector2i in manual_plan.paint_locks:
		for bit in 4096:
			if not manual_plan.paint_locks[key][bit/8]&(1<<(bit%8)):continue
			var cell:=key*64+Vector2i(bit%64,bit/64);var i: int=painted.column_index(cell.x,cell.y)
			check(candidate.column_value("top_materials",i)==painted.column_value("top_materials",i),"native protected paint retained")
	var preview_geometry:=geometry(projection,world._generation_preview)
	dialog._coverage_fields.coverage_zone_m.value=16;check(dialog.get_apply_button().disabled and world._generation_preview==null,"zone control invalidates preview")
	dialog._coverage_fields.coverage_zone_m.value=12;dialog._preview_button.pressed.emit();await ready_dialog(dialog)
	candidate=world._generation_context.candidate;preview_geometry=geometry(projection,world._generation_preview)
	var parameters: Dictionary=dialog.parameters()
	# Protection-only change must invalidate a candidate even without geometry edits.
	var changed_plan: Resource=manual_plan.working_copy();changed_plan.protect_paint_area(Rect2i(32,32,8,8),true);map.set_meta(Plan.META,changed_plan)
	check(not world.commit_terrain_generation(map,entry,painted,candidate,manual_plan.data()).is_empty(),"protection stale refusal")
	map.set_meta(Plan.META,manual_plan)
	dialog._scroll.scroll_vertical=0;await snapshot("preview")
	dialog.get_apply_button().pressed.emit();await ready_tiles(projection)
	check(geometry(projection)==preview_geometry and entry.resource==candidate,"native preview/Apply parity")
	var covered: Terrain=entry.resource.working_copy()
	history.undo();await ready_tiles(projection);check(entry.resource.same_terrain_data(painted) and Plan.same(Plan.read(map),manual_plan),"coverage Undo leaves hand paint/locks")
	history.redo();await ready_tiles(projection);check(entry.resource.same_terrain_data(covered),"coverage Redo")
	await snapshot("after")
	# Same source can receive detail separately without changing cover or locks.
	world._open_terrain_generation();dialog._operation.select(1);dialog._operation.item_selected.emit(1)
	dialog._surface_fields.surface_strength.value=75;dialog._preview_button.pressed.emit();await ready_dialog(dialog)
	dialog.get_apply_button().pressed.emit();await ready_tiles(projection)
	check(entry.resource.dense_window(Rect2i(0,0,384,256)).top_materials==covered.dense_window(Rect2i(0,0,384,256)).top_materials and Plan.same(Plan.read(map),manual_plan),"detail retains covers/protection")
	history.undo();await ready_tiles(projection);check(entry.resource.same_terrain_data(covered),"detail Undo exact")
	var saved_plan: Resource=manual_plan.working_copy();saved_plan.regions.assign([{"id":"zones","name":"Крупные зоны","kind":"generation","enabled":true,"bounds":Rect2i(0,0,24,16),"parameters":parameters}])
	check(world.commit_terrain_plan(map,saved_plan).is_empty(),"save zone recipe")
	world._plan_selected_id="zones";world._open_terrain_plan();world._plan_panel._buttons.generate.pressed.emit()
	check(dialog.parameters().coverage_profile=="large" and dialog.parameters().coverage_zone_m==12,"native recipe reopen panel")
	dialog._coverage_fields.coverage_zone_m.value=16;dialog._plan_save_button.pressed.emit();check(Plan.read(map).regions[0].parameters.coverage_zone_m==16,"native recipe Save button")
	history.undo();check(Plan.read(map).regions[0].parameters.coverage_zone_m==12,"recipe Undo");history.redo()
	world._close_generation_panel();check(world.save_all(),world.sessions.error)
	var reopened=(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_terrain.same_terrain_data(covered) and Plan.same(Plan.read(reopened.get_node("Map")),Plan.read(map)),"native Save/Reopen source/recipe/protection")
	reopened.free();world._apply_generated_terrain(map,entry,original);map.remove_meta(Plan.META);world.sessions.discard(scene);await ready_tiles(projection)
	check(entry.resource.same_terrain_data(covered) and not Plan.read(map).paint_locks.is_empty(),"native Discard source/protection")
	_camera.queue_free();await frames(10)
	print("COVERAGE_ZONES_EDITOR ","PASS" if errors.is_empty() else "FAIL"," native paint/locks/selection/stale/preview/Apply/Undo/detail/recipe/Save/Reopen/Discard errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
