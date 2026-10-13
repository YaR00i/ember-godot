@tool
extends "res://tools/editor_test_compact_terrain_generation.gd"
const Plan=preload("res://scripts/ember_terrain_plan_resource.gd")
const Grove=preload("res://addons/ember_import/ember_grove_planner.gd")
const Placement=preload("res://addons/ember_import/ember_voxel_placement_math.gd")
const OUTPUT="C:/Users/novos/Documents/Codex/2026-10-12/new-chat-2/outputs"
func snapshot(name: String) -> void:
	await frames(5)
	var viewport:=EditorInterface.get_editor_viewport_3d(0)
	var camera:=viewport.get_camera_3d();var previous:=camera.global_transform
	camera.global_transform=_camera.global_transform;camera.far=_camera.far
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	RenderingServer.camera_set_transform(camera.get_camera_rid(),camera.get_camera_transform());RenderingServer.force_draw(false)
	viewport.get_texture().get_image().save_png(OUTPUT+"/smooth-placement-"+name+".png")
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(OUTPUT+"/smooth-placement-"+name+"-panel.png")
	camera.global_transform=previous
func verify_support(map,job,kind := "placement") -> void:
	for spec in job.placements:
		var foot: Dictionary=Placement.footprint(job._template_bounds[spec.model_id],spec.transform)
		if kind=="grove":foot={"point":spec.point,"radius":0.5}
		var support: float=-INF
		for offset in [Vector2.ZERO,Vector2(foot.radius,0),Vector2(-foot.radius,0),Vector2(0,foot.radius),Vector2(0,-foot.radius)]:
			var sample: Dictionary=map.surface_floor_sample(job._frame*Vector3((foot.point.x+offset.x)*16,0,(foot.point.y+offset.y)*16))
			support=maxf(support,(job._frame.affine_inverse()*sample.position).y)
		var bottom: float=spec.transform.origin.y+(job._template_bounds[spec.model_id].position.y if kind=="placement" else 0.0)
		check(absf(bottom-support)<0.0002,"native physical support "+kind)
func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"):return
	Engine.max_fps=30;await frames(20)
	var importer:=get_parent().get_node_or_null("EmberImportPlugin")
	if importer==null:check(false,"importer missing");get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline:await frames(1)
	check(importer._editor_preparation._complete,"preparation")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);DisplayServer.window_set_size(Vector2i(1600,900))
	print("SMOOTH_PLACEMENT_QA preparation ready")
	var probe=load("res://scenes/compact_smooth_tools_study.tscn").instantiate()
	if probe.get_node("Map").get_node_or_null("Props")==null:
		var props:=Node3D.new();props.name="Props";probe.get_node("Map").add_child(props);props.owner=probe
	var prefix: String="qa_smooth_placement_"+str(OS.get_process_id())
	var scene_path: String="res://scenes/"+prefix+".tscn"
	var source_path: String="res://content/world_terrains/"+prefix+".res"
	check(ResourceSaver.save(probe.get_node("Map").compact_terrain.working_copy(),source_path)==OK,"private detail source")
	probe.get_node("Map").compact_terrain=load(source_path)
	var packed:=PackedScene.new();packed.pack(probe);check(ResourceSaver.save(packed,scene_path)==OK,"private scene");probe.free()
	EditorInterface.get_resource_filesystem().update_file(source_path);EditorInterface.get_resource_filesystem().update_file(scene_path)
	await frames(8);EditorInterface.open_scene_from_path(scene_path)
	deadline=Time.get_ticks_msec()+60000
	while (EditorInterface.get_edited_scene_root()==null or EditorInterface.get_edited_scene_root().scene_file_path!=scene_path) and Time.get_ticks_msec()<deadline:await frames(1)
	await frames(12);EditorInterface.set_main_screen_editor("3D")
	print("SMOOTH_PLACEMENT_QA scene open")
	var scene:=EditorInterface.get_edited_scene_root();var map:=scene.get_node("Map") as EmberMapLoader
	var world: Node=importer._world_editor;world.enabled.button_pressed=true;world.scene_changed(scene)
	var projection:=map._visual_surface_projection as EmberTerrainPilotProjection;await ready_tiles(projection)
	print("SMOOTH_PLACEMENT_QA tiles ready")
	_camera=Camera3D.new();EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.fov=50;_camera.far=5000;_camera.look_at_from_position(Vector3(11,8,11),Vector3(4,1.9,4));_camera.make_current()
	var draft: Dictionary=world.sessions.open_map(map,scene);var original: Terrain=draft.resource.working_copy()
	# Exercise the grove branch with a real native tree prefab, independently
	# of the mixed placement UI cycle below. Neither check writes the ground.
	var tree_plan:=Plan.new();tree_plan.schema_version=Plan.VERSION
	var tree_values: Dictionary=Plan.Influence.GROVE_DEFAULTS.duplicate(true)
	tree_values.model_ids=PackedStringArray(["vox_tree_120664056"]);tree_values.density=1.0;tree_values.spacing_m=2.0;tree_values.slope_percent=50.0
	tree_plan.regions=[{"id":"trees","name":"Опора деревьев","kind":"grove","enabled":true,"bounds":Rect2i(1,1,6,6),"parameters":tree_values}]
	var trees:=Grove.new();check(trees.begin(draft.resource,map,scene,tree_plan),trees.error)
	deadline=Time.get_ticks_msec()+30000
	while not trees.finished and Time.get_ticks_msec()<deadline:trees.step(4000);await frames(1)
	check(trees.finished and trees.error.is_empty() and not trees.placements.is_empty(),"native tree planner")
	verify_support(map,trees,"grove")
	print("SMOOTH_PLACEMENT_TREES ","PASS" if errors.is_empty() else "FAIL"," count=",trees.placements.size())
	var plan:=Plan.new();plan.schema_version=Plan.VERSION
	var values: Dictionary=Plan.Influence.PLACEMENT_DEFAULTS.duplicate(true)
	values.model_ids=PackedStringArray(["vox_tree_120664056","vox_qa_placement_rock"]);values.density=1.0;values.spacing_m=2.0;values.slope_percent=50.0;values.clearance_m=0.0
	plan.regions=[{"id":"objects","name":"Опора на гладкой земле","kind":"placement","enabled":true,"bounds":Rect2i(1,1,6,6),"parameters":values}]
	world.sessions.set_plan(draft,plan);world._open_terrain_plan();world._plan_panel._buttons.generate.pressed.emit()
	var dialog: Control=world._generation_panel;dialog._preview_button.pressed.emit();await ready_dialog(dialog)
	print("SMOOTH_PLACEMENT_QA preview ready")
	if not errors.is_empty():get_tree().quit(1);return
	var job: RefCounted=world._generation_context.get("grove_prepared")
	check(job!=null and job.placements.size()>0,"native objects preview")
	if job==null:get_tree().quit(1);return
	verify_support(map,job);var count: int=job.placements.size()
	check(map.get_node("Props").get_child_count()==0 and draft.resource.same_terrain_data(original),"preview preserves source/objects")
	await snapshot("preview")
	# Retaining a preview while changing the style cannot commit old support.
	map.compact_ground_style=0;await ready_tiles(projection)
	check(job.stale() and not world.commit_grove(map,world._generation_context).is_empty(),"native stale style cannot Apply")
	map.compact_ground_style=1;await ready_tiles(projection)
	dialog._preview_button.pressed.emit();await ready_dialog(dialog);job=world._generation_context.grove_prepared
	var wanted: Array[Dictionary]=job.placements.duplicate(true)
	dialog.get_apply_button().pressed.emit();await frames(6)
	check(map.get_node("Props").get_child_count()==count,"native Apply count")
	for spec in wanted:
		var matches:=0
		for prop: EmberVoxelProp in map.get_node("Props").get_children():
			if (job._frame.affine_inverse()*prop.global_transform).is_equal_approx(spec.transform):matches+=1
		check(matches==1,"preview/Apply pose exact")
	var history:=get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo();await frames(4);check(map.get_node("Props").get_child_count()==0,"native Undo")
	history.redo();await frames(4);check(map.get_node("Props").get_child_count()==count,"native Redo")
	var prop:=map.get_node("Props").get_child(0) as EmberVoxelProp;prop.position.x+=0.2;var manual:=prop.transform
	world._open_terrain_plan();world._plan_panel._buttons.generate.pressed.emit();dialog._preview_button.pressed.emit();await ready_dialog(dialog)
	job=world._generation_context.grove_prepared
	check(prop in job.protected_nodes,"native manual protection")
	dialog.get_apply_button().pressed.emit();await frames(4);check(prop.transform==manual,"native manual pose preserved")
	check(world.save_all(),world.sessions.error)
	var saved:=Grove.pose_version(map);var saved_plan: Resource=Plan.read(map).working_copy()
	var reopened=(ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	get_tree().root.add_child(reopened);await frames(2)
	check(Plan.same(Plan.read(reopened.get_node("Map")),saved_plan) and Grove.pose_version(reopened.get_node("Map"))==saved,"native Save/Reopen")
	reopened.free();prop.position.x+=0.2;world.sessions.discard(scene);await frames(4)
	check(Grove.pose_version(map)==saved and draft.resource.same_terrain_data(original),"native Discard/source")
	await snapshot("applied");_camera.queue_free();await frames(10)
	print("SMOOTH_PLACEMENT_EDITOR ","PASS" if errors.is_empty() else "FAIL"," preview/physical support/stale style/Apply/Undo/Redo/manual/Save/Reopen/Discard count=",count," errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
