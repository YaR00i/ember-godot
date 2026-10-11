@tool
extends EditorPlugin
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
var errors: Array[String]=[]
func _enter_tree() -> void: _run.call_deferred()
func frames(n:int) -> void:
	for i in n: await get_tree().process_frame
func check(ok:bool,msg:String) -> void:
	if not ok: errors.append(msg)
func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	Engine.max_fps=30; await frames(25)
	var importer=get_parent().get_node_or_null("EmberImportPlugin"); var deadline=Time.get_ticks_msec()+90000
	while importer and not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline: await frames(1)
	check(importer != null and importer._editor_preparation._complete,"preparation timeout")
	check(EditorInterface.get_open_scenes().size()==1,"extra scene open")
	var study_path=OS.get_environment("EMBER_GROUND_STUDY_PATH")
	if study_path.is_empty(): study_path="res://scenes/ground_material_study.tscn"
	var scene=EditorInterface.get_edited_scene_root()
	check(scene!=null and scene.scene_file_path==study_path,"wrong fixture")
	if not errors.is_empty(): get_tree().quit(1); return
	EditorInterface.set_main_screen_editor("3D")
	var map: EmberMapLoader=scene.get_node("Map"); var projection=map._visual_surface_projection
	while projection.pending_tile_count()>0 and Time.get_ticks_msec()<deadline: await frames(1)
	var before=map.compact_terrain.working_copy(); var builds=projection.built_tile_count()
	var camera:=Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=12; camera.global_transform=scene.get_node("Camera3D").global_transform; camera.make_current()
	var output="user://ember-tests/surface-layers-20261009" if study_path.contains("finish") else "user://ember-tests/painted-grass-20261009" if study_path.contains("painted") else "user://ember-tests/ground-surfaces-20261009"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	await frames(10); RenderingServer.force_draw(false)
	check(EditorInterface.get_editor_viewport_3d(0).get_texture().get_image().save_png(output+"/editor_3d.png")==OK,"3D capture")
	var world=importer._world_editor
	world.scene_changed(scene); world.enabled.button_pressed=true; world.target_choice.select(0); world._target_changed(0); world.category.select(1); world._category_changed(1)
	check(not world.entry.is_empty(),"map editor entry: "+world.sessions.error)
	if not errors.is_empty(): print("GROUND_MATERIAL completed ok=false errors=",errors); get_tree().quit(1); return
	var fixture="qa_ground_"+str(OS.get_process_id())
	var study_variant:String=world.entry.resource.material_id_for_palette(2)
	var initial_relief:float=Materials.load_compact_terrain_variant(study_variant).micro_relief
	check(ResourceSaver.save(Materials.load_compact_terrain_variant(study_variant).duplicate(true),Materials.variant_path(fixture))==OK,"fixture save")
	EditorInterface.get_resource_filesystem().update_file(Materials.variant_path(fixture)); await frames(5)
	check(world.set_compact_surface_material(2,"grass",fixture),"assign fixture")
	world.palette.select(1); world._refresh_palette_swatch(); world._open_material_pattern(); await frames(6)
	var panel=world.material_pattern_dialog
	check(panel!=null and panel._finish_sliders.has("micro_size_m"),"detail panel missing")
	if study_path.contains("finish"):
		var color_before:PackedByteArray=panel._draft.pixels.duplicate()
		panel._select_channel(1);var height_before:PackedByteArray=panel._draft.relief_pixels.duplicate()
		panel._begin_stroke();var heights:PackedByteArray=panel._grid.tones();heights[0]=(heights[0]+1)%3
		panel._grid.set_tones(heights,panel._channel_colors());panel._on_grid_changed();panel._finish_stroke()
		check(panel._draft.pixels==color_before and panel._draft.relief_pixels!=height_before,"layer mixed color/relief")
		panel.undo_edit();check(panel._draft.relief_pixels==height_before,"relief Undo");panel.redo_edit()
		panel._select_channel(2);panel._select_face(1)
		panel._file_import=false;panel._on_file_selected("user://qa-ground-roughness.png")
		panel._file_import=true;panel._on_file_selected("user://qa-ground-roughness.png")
		check(panel._draft.pixels==color_before,"roughness PNG changed color")
		panel._finish_sliders.pattern_size_m.value=1.7;panel._finish_sliders.roughness_variation.value=0.18
	panel._finish_sliders.micro_relief.value=0.17
	panel.undo_edit(); check(is_equal_approx(panel._draft.micro_relief,initial_relief),"detail Undo")
	panel.redo_edit(); check(is_equal_approx(panel._draft.micro_relief,0.17),"detail Redo")
	panel._finish_sliders.micro_size_m.value=0.14; panel._finish_sliders.micro_roughness.value=0.26
	check(panel.parameters_panel.get_global_rect().encloses(panel._save_button.get_global_rect()),"pinned Save clipped")
	check(panel.parameters_panel.get_combined_minimum_size().x<=340,"sidebar too wide")
	var scroller=panel._parameter_scroll
	scroller.scroll_vertical=roundi(panel._finish_sliders.micro_relief.get_global_rect().position.y-scroller.get_global_rect().position.y-12)
	await frames(4)
	for key in ["micro_relief","micro_size_m","micro_roughness"]:
		check(scroller.get_global_rect().encloses(panel._finish_sliders[key].get_global_rect()),"detail slider clipped: "+key)
	RenderingServer.force_draw(false); await frames(4)
	check(get_viewport().get_texture().get_image().save_png(output+"/editor_panel.png")==OK,"panel capture")
	panel._save_button.pressed.emit(); await frames(5)
	var saved=Materials.load_compact_terrain_variant(fixture)
	if study_path.contains("finish"): check(is_equal_approx(saved.pattern_size_m,1.7) and is_equal_approx(saved.roughness_variation,0.18) and saved.relief_pixels.size()==256,"independent layer Save-Reopen")
	check(is_equal_approx(saved.micro_relief,0.17) and is_equal_approx(saved.micro_size_m,0.14) and is_equal_approx(saved.micro_roughness,0.26),"detail save fresh disk")
	check(world.entry.resource.same_terrain_geometry(before) and projection.built_tile_count()==builds,"detail remesh")
	world._open_material_pattern(); panel._finish_sliders.micro_relief.value=0.3; panel.cancel_edit(); world._open_material_pattern()
	check(is_equal_approx(panel._draft.micro_relief,0.17),"Cancel-Reopen")
	panel.cancel_edit(); world.set_compact_surface_material(2,"grass",study_variant)
	check(world.sessions.save_all(scene),"Save terrain assignment")
	var history=get_undo_redo(); history.create_action("Ground detail",UndoRedo.MERGE_DISABLE,scene)
	history.add_do_property(scene,"detail_enabled",false); history.add_undo_property(scene,"detail_enabled",true); history.commit_action(); await frames(3)
	var undo=history.get_history_undo_redo(history.get_object_history_id(scene)); undo.undo(); await frames(3); check(scene.detail_enabled,"scene detail Undo")
	undo.redo(); await frames(3); check(not scene.detail_enabled,"scene detail Redo"); undo.undo(); await frames(3)
	check(EditorInterface.save_scene()==OK,"scene Save")
	var fresh=(ResourceLoader.load(scene.scene_file_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(fresh.detail_enabled and fresh.get_node("Map").compact_terrain.same_terrain_geometry(before),"fresh scene reopen")
	fresh.free(); camera.queue_free()
	var result_path=output+"/runtime-result.json"
	if FileAccess.file_exists(result_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(result_path))
	print("GROUND_MATERIAL launch-F6")
	EditorInterface.play_current_scene(); deadline=Time.get_ticks_msec()+50000
	while not FileAccess.file_exists(result_path) and Time.get_ticks_msec()<deadline: await frames(1)
	check(FileAccess.file_exists(result_path),"F6 timeout")
	if FileAccess.file_exists(result_path):
		var result:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(result_path)); check(result.ok and result.saved_detail,"F6 mismatch")
	EditorInterface.stop_playing_scene(); await frames(6)
	print("GROUND_MATERIAL completed ok=",errors.is_empty()," errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
