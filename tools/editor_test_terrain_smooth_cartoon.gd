@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Pattern=preload("res://scripts/ember_compact_terrain_pattern.gd")
const OUTPUT="C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs"

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"):return
	await frames(20)
	var importer:=get_parent().get_node_or_null("EmberImportPlugin")
	if importer==null:check(false,"importer missing");get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline:await frames(1)
	check(importer._editor_preparation._complete,"editor preparation")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900))
	var packed:=load("res://scenes/compact_cartoon_ground_study.tscn") as PackedScene
	var probe:=packed.instantiate()
	var map:=probe.get_node("Map") as EmberMapLoader
	var terrain:=map.compact_terrain.working_copy()
	var prefix: String="qa_cartoon_"+str(OS.get_process_id())
	var scene_path: String="res://scenes/"+prefix+".tscn"
	var source_path: String="res://content/world_terrains/"+prefix+".res"
	check(ResourceSaver.save(terrain,source_path)==OK,"private source save")
	map.compact_terrain=ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var private_scene:=PackedScene.new();private_scene.pack(probe);ResourceSaver.save(private_scene,scene_path);probe.free()
	EditorInterface.get_resource_filesystem().update_file(source_path);EditorInterface.get_resource_filesystem().update_file(scene_path)
	await frames(8);EditorInterface.open_scene_from_path(scene_path)
	deadline=Time.get_ticks_msec()+60000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=scene_path) and Time.get_ticks_msec()<deadline:await frames(1)
	await frames(12);EditorInterface.set_main_screen_editor("3D")
	var scene:=EditorInterface.get_edited_scene_root()
	check(scene!=null and scene.scene_file_path==scene_path,"native fixture open")
	if scene==null:get_tree().quit(1);return
	map=scene.get_node("Map") as EmberMapLoader
	var world: Node=importer._world_editor
	world.enabled.button_pressed=true;world.category.select(1);world._category_changed(1)
	var projection:=map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection)
	check(projection.ground_style==1,"native smooth mode")
	var entry: Dictionary=world.sessions.open_map(map,scene)
	var baseline: PackedInt32Array=entry.resource.heights.duplicate()
	var brush=world._compact_brush
	brush.configure(entry,get_undo_redo(),scene)
	check(brush.begin("raise",0.0625,8,2,0,1,0,7,0,-99999,"detail","circle",1),"editor brush start")
	brush.stamp(Vector2i(59,59));brush.end();await ready_tiles(projection)
	check(entry.resource.heights!=baseline,"editor brush source")
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();await ready_tiles(projection);check(entry.resource.heights==baseline,"editor brush Undo")
	history.redo();await ready_tiles(projection);check(entry.resource.heights!=baseline,"editor brush Redo")
	var look=world.look_panel
	check(look._choices.has("compact_ground_style"),"existing look panel ground selector")
	look._choices.compact_ground_style.item_selected.emit(0);await ready_tiles(projection)
	check(map.compact_ground_style==0 and projection.ground_style==0,"native ground selector steps")
	history.undo();await ready_tiles(projection);check(map.compact_ground_style==1,"native style Undo")
	history.redo();await ready_tiles(projection);check(map.compact_ground_style==0,"native style Redo")
	history.undo();await ready_tiles(projection)
	check(world.sessions.save_all(scene),world.sessions.error)
	var reopened: Node=(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_ground_style==1,"native saved map mode")
	check(reopened.get_node("Map").compact_terrain.heights==entry.resource.heights,"native saved brush values")
	reopened.free()
	var saved: PackedInt32Array=entry.resource.heights.duplicate()
	brush.begin("raise",0.0625,4,2,0,1,0,7,0);brush.stamp(Vector2i(67,67));brush.end();await ready_tiles(projection)
	world.sessions.discard(scene);await ready_tiles(projection)
	entry=world.sessions.open_map(map,scene);check(entry.resource.heights==saved,"editor Discard")
	var id: String=prefix+"_grass"
	check(ResourceSaver.save(Materials.load_compact_terrain_variant("cartoon_grass").duplicate(true),Materials.variant_path(id))==OK,"private PNG material")
	EditorInterface.get_resource_filesystem().update_file(Materials.variant_path(id));await frames(5)
	check(world.set_compact_surface_material(2,"grass",id),"native PNG variant assignment")
	world.palette.select(1);world._refresh_palette_swatch();world._open_material_pattern();await frames(6)
	var editor: Control=world.material_pattern_dialog
	check(editor._draft.albedo_texture!=null,"PNG visible in material draft")
	check(editor._texture_label.is_visible_in_tree(),"native PNG controls visible")
	var texture: Texture2D=editor._draft.albedo_texture
	editor._remove_texture();editor.undo_edit();check(editor._draft.albedo_texture==texture,"native PNG Undo")
	editor.redo_edit();check(editor._draft.albedo_texture==null,"native PNG Redo")
	editor._change_texture(texture);check(editor._save(),"native PNG Save")
	world._open_material_pattern();check(editor._draft.albedo_texture!=null,"native PNG reopen")
	editor.cancel_edit()
	_camera=Camera3D.new();EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(Vector3(32,16,28),Vector3(12,1.5,8));_camera.far=200;_camera.make_current()
	await frames(15);await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OUTPUT+"/native-cartoon-editor.png")
	world._open_material_pattern();await frames(10);await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OUTPUT+"/native-cartoon-material-editor.png")
	editor.cancel_edit();_camera.queue_free()
	print("SMOOTH_CARTOON_EDITOR ","PASS" if errors.is_empty() else "FAIL"," native brush/Undo/Redo/Save/Reopen/Discard/PNG controls errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
