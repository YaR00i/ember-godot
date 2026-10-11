@tool
extends "res://tools/editor_test_terrain_plan_river.gd"
const Grove = preload("res://addons/ember_import/ember_grove_planner.gd")
func ready_grove(dialog: Control) -> void:
	var deadline := Time.get_ticks_msec()+30000
	while dialog.get_apply_button().disabled and Time.get_ticks_msec() < deadline: await frames(1)
	check(not dialog.get_apply_button().disabled,"grove preview timeout: "+dialog._status.text)

func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	Engine.max_fps = 30; await frames(25)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(importer._editor_preparation._complete,"preparation timeout")
	if not errors.is_empty(): get_tree().quit(1); return
	var creation := Creation.new(); creation.scene_directory = "res://qa_generation/scenes"; creation.terrain_directory = "res://qa_generation/terrains"
	check(creation.prepare_sections("grove_native_"+str(OS.get_process_id()),1,1,96),creation.error)
	var path: String = creation.commit(); check(not path.is_empty(),creation.error)
	EditorInterface.get_resource_filesystem().update_file(path); await frames(8); EditorInterface.open_scene_from_path(path)
	await frames(20); EditorInterface.set_main_screen_editor("3D")
	var scene := EditorInterface.get_edited_scene_root(); var map := scene.get_node("Map") as EmberMapLoader
	check(scene != null and scene.scene_file_path == path,"fixture open")
	var projection := map._visual_surface_projection as EmberTerrainPilotProjection; await ready_tiles(projection)
	var world: Node = importer._world_editor; world.enabled.button_pressed = true; await ready_tiles(projection)
	var draft: Dictionary = world.sessions.open_map(map,scene); var original: Resource = draft.resource.working_copy()
	_camera = Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(_camera)
	_camera.look_at_from_position(projection.to_global(Vector3(300,500,500)),projection.to_global(Vector3(192,96,192))); _camera.far = 5000; _camera.make_current()
	world._open_terrain_plan(); var panel: Control = world._plan_panel
	panel._buttons.add_grove.pressed.emit(); select_rect(world,Rect2i(6,6,12,12)); await frames(8)
	check(Plan.read(map).regions.size() == 1 and Plan.read(map).regions[0].kind == "grove","native grove rectangle")
	check(draft.resource.same_terrain_data(original),"plan rectangle changed ground")
	panel._buttons.generate.pressed.emit(); var dialog: Control = world._generation_panel
	check(dialog._grove_grid.is_visible_in_tree() and world.inspector_panel.is_ancestor_of(dialog),"grove outside common dock")
	dialog._grove_fields.density.value = 100.0; dialog._plan_save_button.pressed.emit()
	check(Plan.read(map).regions[0].parameters.density == 1.0 and map.get_node("Props").get_child_count() == 0,"recipe Save changed scene objects")
	dialog._preview_button.pressed.emit(); await ready_grove(dialog)
	var job: RefCounted = world._generation_context.grove_prepared
	var wanted: Array[Dictionary] = job.placements.duplicate(true)
	check(wanted.size() >= 1 and wanted.size() <= 4,"small fixture tree count")
	check(map.get_node("Props").get_child_count() == 0 and draft.resource.same_terrain_data(original),"preview changed canonical data")
	var preview_mesh := world._generation_preview.get_child(0).get_node("Mesh") as MeshInstance3D
	var mesh := preview_mesh.mesh
	await capture("grove_preview",dialog)
	dialog._grove_fields.density.value = 80.0
	check(dialog.get_apply_button().disabled and world._generation_preview == null,"stale grove preview remained")
	dialog._grove_fields.density.value = 100.0; dialog._preview_button.pressed.emit(); await ready_grove(dialog)
	dialog.get_apply_button().pressed.emit(); await frames(8)
	var applied: Resource = Plan.read(map); var members: Array = applied.object_layers[applied.regions[0].id]
	check(members.size() == wanted.size() and map.get_node("Props").get_child_count() == wanted.size(),"Apply != preview count")
	var prop := map.get_node("Props").get_node(NodePath(members[0].id)) as EmberVoxelProp
	check(prop.get_node("Mesh").mesh == mesh and Grove.fingerprint(prop,map,job._frame) == members[0].expected,"preview/applied geometry or transform changed")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); await frames(4)
	check(map.get_node("Props").get_child_count() == 0 and Plan.read(map).object_layers.is_empty(),"atomic grove Undo")
	history.redo(); await frames(4); check(map.get_node("Props").get_child_count() == wanted.size(),"grove Redo")
	world._open_terrain_plan(); panel._buttons.generate.pressed.emit(); dialog._preview_button.pressed.emit(); await ready_grove(dialog)
	dialog.get_apply_button().pressed.emit(); await frames(4)
	check(Plan.same(Plan.read(map),applied) and map.get_node("Props").get_child_count() == wanted.size(),"repeat accumulates trees")
	prop.position.x += 8
	var manual := prop.position
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.groves.pressed.emit()
	dialog._preview_button.pressed.emit(); await ready_grove(dialog); dialog.get_apply_button().pressed.emit(); await frames(4)
	check(prop.get_parent() != null and prop.position == manual and map.get_node("Props").get_child_count() == 1,"off erased edited tree / retained unedited trees")
	world._open_terrain_plan(); panel._buttons.toggle.pressed.emit(); panel._buttons.groves.pressed.emit()
	dialog._preview_button.pressed.emit(); await ready_grove(dialog); dialog.get_apply_button().pressed.emit(); await frames(4)
	check(prop.position == manual and map.get_node("Props").get_child_count() >= 1,"restore lost manual tree")
	check(world.save_all(),world.sessions.error)
	var saved_pose := Grove.pose_version(map); var saved_plan: Resource = Plan.read(map).working_copy()
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	check(Plan.same(Plan.read(reopened.get_node("Map")),saved_plan),"fresh disk plan differs")
	check(reopened.get_node("Map/Props").get_child_count() == map.get_node("Props").get_child_count(),"fresh disk members lost"); reopened.free()
	prop.position.x += 5; world.sessions.discard(scene); await frames(4)
	check(Grove.pose_version(map) == saved_pose,"native Discard lost members/pose")
	check(draft.resource.same_terrain_data(original),"grove changed ground")
	var marker := scene.get_node("Map/Regions/PlayerStart") as Node3D; marker.position = Vector3(48,110,48)
	var playback := Node.new(); playback.name = "GrovePlaybackCheck"; playback.set_script(load("res://tools/test_terrain_plan_grove_playback.gd")); playback.result_file = "user://grove-playback-"+str(OS.get_process_id())+".json"
	scene.add_child(playback); playback.owner = scene; check(EditorInterface.save_scene() == OK,"save playback fixture")
	await capture("grove_applied"); _camera.queue_free()
	print("GROVE_NATIVE ","PASS" if errors.is_empty() else "FAIL"," scene=",path," errors=",errors)
	if not errors.is_empty(): get_tree().quit(1); return
	EditorInterface.play_current_scene(); deadline = Time.get_ticks_msec()+45000
	while not FileAccess.file_exists(playback.result_file) and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(playback.result_file),"F6 result missing")
	if FileAccess.file_exists(playback.result_file):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(playback.result_file)); check(result.get("ok",false),str(result)); print("GROVE_F6_RESULT ",result)
	EditorInterface.stop_playing_scene(); await frames(8)
	print("GROVE_F6 ","PASS" if errors.is_empty() else "FAIL"," errors=",errors); get_tree().quit(0 if errors.is_empty() else 1)
