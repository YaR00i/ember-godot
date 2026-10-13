@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
func study_scene_path() -> String:
	return "res://scenes/compact_cartoon_relief_study.tscn"
func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"):return
	await frames(20)
	var importer:=get_parent().get_node_or_null("EmberImportPlugin")
	if importer==null:check(false,"importer missing");get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline:await frames(1)
	check(importer._editor_preparation._complete,"editor preparation")
	var probe=(load(study_scene_path()) as PackedScene).instantiate()
	var map:=probe.get_node("Map") as EmberMapLoader
	var prefix: String="qa_relief_"+str(OS.get_process_id())
	var source_path: String="res://content/world_terrains/"+prefix+".res"
	var scene_path: String="res://scenes/"+prefix+".tscn"
	check(ResourceSaver.save(map.compact_terrain.working_copy(),source_path)==OK,"private source save")
	map.compact_terrain=ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var packed:=PackedScene.new();packed.pack(probe);check(ResourceSaver.save(packed,scene_path)==OK,"private scene save");probe.free()
	EditorInterface.get_resource_filesystem().update_file(source_path);EditorInterface.get_resource_filesystem().update_file(scene_path)
	await frames(8);EditorInterface.open_scene_from_path(scene_path)
	deadline=Time.get_ticks_msec()+60000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=scene_path) and Time.get_ticks_msec()<deadline:await frames(1)
	await frames(12);var scene:=EditorInterface.get_edited_scene_root()
	check(scene!=null and scene.scene_file_path==scene_path,"native fixture open")
	if scene==null:get_tree().quit(1);return
	map=scene.get_node("Map") as EmberMapLoader
	var world: Node=importer._world_editor;world.enabled.button_pressed=true
	world.category.select(1);world._category_changed(1)
	var projection:=map._visual_surface_projection as EmberTerrainPilotProjection
	await ready_tiles(projection);check(projection.smooth_material_blend_enabled,"native blend active")
	var manager:=get_undo_redo()
	manager.create_action("QA material mix",UndoRedo.MERGE_DISABLE,scene)
	manager.add_do_property(map,"compact_smooth_material_blend",false)
	manager.add_undo_property(map,"compact_smooth_material_blend",true)
	manager.commit_action();await ready_tiles(projection)
	check(not projection.smooth_material_blend_enabled,"native blend disabled")
	var history:=manager.get_history_undo_redo(manager.get_object_history_id(scene))
	history.undo();await ready_tiles(projection);check(projection.smooth_material_blend_enabled,"native blend Undo")
	history.redo();await ready_tiles(projection);check(not projection.smooth_material_blend_enabled,"native blend Redo")
	history.undo();await ready_tiles(projection)
	var entry: Dictionary=world.sessions.open_map(map,scene)
	var baseline: PackedByteArray=entry.resource.top_materials.duplicate()
	var brush=world._compact_brush;brush.configure(entry,manager,scene)
	check(brush.begin("paint",0.0625,1,1,0,1,0,7,0),"native paint begin")
	brush.stamp(Vector2i(62,44));brush.end();await ready_tiles(projection)
	check(entry.resource.top_materials!=baseline,"native paint source")
	history.undo();await ready_tiles(projection);check(entry.resource.top_materials==baseline,"native paint Undo")
	history.redo();await ready_tiles(projection);check(entry.resource.top_materials!=baseline,"native paint Redo")
	check(world.sessions.save_all(scene),world.sessions.error)
	var reopened: Node=(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_node("Map").compact_smooth_material_blend,"native blend saved/reopened")
	check(reopened.get_node("Map").compact_terrain.top_materials==entry.resource.top_materials,"native paint saved/reopened")
	reopened.free()
	var saved: PackedByteArray=entry.resource.top_materials.duplicate()
	brush.begin("paint",0.0625,1,1,0,1,0,7,0);brush.stamp(Vector2i(66,46));brush.end();await ready_tiles(projection)
	world.sessions.discard(scene);await ready_tiles(projection)
	entry=world.sessions.open_map(map,scene);check(entry.resource.top_materials==saved,"native Discard")
	print("CARTOON_RELIEF_EDITOR ","PASS" if errors.is_empty() else "FAIL"," native blend/paint/Undo/Redo/Save/Reopen/Discard errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
