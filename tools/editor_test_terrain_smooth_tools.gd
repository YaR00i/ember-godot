@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const OUTPUT="C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs"
func stroke(world: Node,down_only:=false) -> void:
	world.compact_direction.select(2 if down_only else 0)
	world.camera=_camera
	var position:=_camera.get_viewport().get_visible_rect().size*0.5
	var pick: Dictionary=world._pick_compact(position)
	check(not pick.is_empty(),"native smooth camera pick")
	if pick.is_empty():return
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.button_mask=MOUSE_BUTTON_MASK_LEFT;event.position=position
	world._forward_compact(event)
	check(world._compact_brush.active(),"native existing input begins material brush")
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=false;event.position=position
	world._forward_compact(event)
	await ready_tiles(world.map._visual_surface_projection)
	check(not world._compact_brush.active(),"native input commits one stroke")

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
	var prefix: String="qa_smoothtools_"+str(OS.get_process_id())
	var source_path: String="res://content/world_terrains/"+prefix+".res"
	var scene_path: String="res://scenes/"+prefix+".tscn"
	check(ResourceSaver.save(probe.baseline_terrain.working_copy(),source_path)==OK,"private hand-authored source")
	probe.get_node("Map").compact_terrain=ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var packed:=PackedScene.new();packed.pack(probe);check(ResourceSaver.save(packed,scene_path)==OK,"private scene");probe.free()
	EditorInterface.get_resource_filesystem().update_file(source_path);EditorInterface.get_resource_filesystem().update_file(scene_path)
	await frames(8);EditorInterface.open_scene_from_path(scene_path)
	deadline=Time.get_ticks_msec()+60000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=scene_path) and Time.get_ticks_msec()<deadline:await frames(1)
	await frames(12);EditorInterface.set_main_screen_editor("3D")
	var scene:=EditorInterface.get_edited_scene_root();check(scene!=null,"native scene")
	if scene==null:get_tree().quit(1);return
	var map:=scene.get_node("Map") as EmberMapLoader
	var world: Node=importer._world_editor;world.enabled.button_pressed=true;world.scene_changed(scene)
	world.category.select(0);world._category_changed(0)
	world.tools.select(4);world._tool_changed()
	check(world._mode()=="generator" and world.compact_detail_pattern.selected==0,"old noise remains default")
	world.compact_detail_pattern.select(1);world.compact_detail_pattern.item_selected.emit(1)
	check(world.compact_detail_pattern.is_visible_in_tree() and not world._parameter_group(world.compact_detail).visible,"native shared material-detail controls")
	world.terrain_edit_scale.select(2);world.terrain_edit_scale.item_selected.emit(2)
	world.brush_shape.select(1);world.brush_shape.item_selected.emit(1)
	world.radius.value=0.85;world.depth.value=12;world.compact_feature_scale.value=16;world.compact_seed.value=731
	var projection:=map._visual_surface_projection as EmberTerrainPilotProjection;await ready_tiles(projection)
	var entry: Dictionary=world.sessions.open_map(map,scene)
	var original: Terrain=entry.resource.working_copy()
	_camera=Camera3D.new();EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(14,10,14),Vector3(5.7,2.1,5.25));_camera.far=200;_camera.make_current()
	await frames(10);await stroke(world)
	check(entry.resource.heights!=original.heights,"native material brush changes heights")
	check(entry.resource.top_materials==original.top_materials and entry.resource.base_materials==original.base_materials,"native material brush preserves hand paint")
	var after: Terrain=entry.resource.working_copy()
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();await ready_tiles(projection);check(entry.resource.same_terrain_data(original),"native one stroke Undo")
	history.redo();await ready_tiles(projection);check(entry.resource.same_terrain_data(after),"native one stroke Redo")
	await stroke(world,true)
	var carved:=false
	for i in after.heights.size():
		check(entry.resource.heights[i]<=after.heights[i],"native Only Down does not raise")
		if entry.resource.heights[i]<after.heights[i]:carved=true
	check(carved,"native Only Down actually carves stone")
	history.undo();await ready_tiles(projection);check(entry.resource.same_terrain_data(after),"native down Undo")
	# Scene-owned style changes only projection and retains the authored source.
	world.look_panel._choices.compact_ground_style.item_selected.emit(0);await ready_tiles(projection)
	check(projection.ground_style==0 and entry.resource.same_terrain_data(after),"native voxel display preserves sculpt")
	history.undo();await ready_tiles(projection);check(projection.ground_style==1 and entry.resource.same_terrain_data(after),"native style Undo")
	check(world.sessions.save_all(scene),world.sessions.error)
	var reopened=(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_ground_style==1 and reopened.get_node("Map").compact_terrain.same_terrain_data(after),"native Save/Reopen preserves work/style")
	reopened.free()
	await stroke(world)
	world.sessions.discard(scene);await ready_tiles(projection);entry=world.sessions.open_map(map,scene)
	check(entry.resource.same_terrain_data(after),"native Discard")
	world.compact_direction.select(0);world._tool_changed()
	world.hover.clear();world._update_overlay()
	_camera.look_at_from_position(Vector3(14,10,14),Vector3(4,1.8,4))
	await frames(10);await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OUTPUT+"/smooth-tools-editor.png")
	_camera.queue_free()
	await frames(10)
	var filesystem:=EditorInterface.get_resource_filesystem()
	deadline=Time.get_ticks_msec()+10000
	while filesystem.is_scanning() and Time.get_ticks_msec()<deadline:await frames(1)
	await frames(10)
	print("SMOOTH_TOOLS_EDITOR ","PASS" if errors.is_empty() else "FAIL"," native controls/input/pick/material/Undo/Redo/direction/style/Save/Reopen/Discard ",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
