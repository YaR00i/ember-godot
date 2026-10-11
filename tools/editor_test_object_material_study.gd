@tool
extends EditorPlugin
var errors: Array[String] = []
func _enter_tree() -> void:
	print("OBJECT_MATERIAL editor driver start")
	_run.call_deferred()
func frames(count: int) -> void:
	for unused in count: await get_tree().process_frame
func check(ok: bool, message: String) -> void:
	if not ok: errors.append(message)
func _run() -> void:
	if "--export-pack" in OS.get_cmdline_args() or not ProjectSettings.globalize_path("res://").contains("ember-river-preview-"): return
	Engine.max_fps = 30; await frames(25)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	var deadline := Time.get_ticks_msec()+90000
	while importer and not importer._editor_preparation._complete and Time.get_ticks_msec() < deadline: await frames(1)
	check(EditorInterface.get_open_scenes().size() == 1,"extra scene open")
	var scene := EditorInterface.get_edited_scene_root()
	check(scene != null and scene.scene_file_path == "res://scenes/object_material_study.tscn","wrong fixture")
	if not errors.is_empty(): get_tree().quit(1); return
	EditorInterface.set_main_screen_editor("3D"); EditorInterface.inspect_object(scene)
	var camera := Camera3D.new(); EditorInterface.get_editor_viewport_3d(0).add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = 16
	camera.global_transform = scene.get_node("Camera").global_transform; camera.make_current()
	var output := "user://ember-tests/object-materials"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for mode in [true,false]:
		scene.surface_response = mode; scene.apply_settings(); await frames(8)
		RenderingServer.force_draw(false)
		check(EditorInterface.get_editor_viewport_3d(0).get_texture().get_image().save_png(output+"/editor_"+("surface" if mode else "legacy")+".png") == OK,"editor capture failed")
	var material := scene.get_node("Sample3/Mesh").get_active_material(0) as ShaderMaterial
	check(material.get_shader_parameter("surface_response_enabled") == false,"toggle did not reach material")
	scene.surface_response = true
	for preset in 3:
		scene.light_preset = preset; scene.apply_settings(); await frames(8)
		RenderingServer.force_draw(false)
		check(EditorInterface.get_editor_viewport_3d(0).get_texture().get_image().save_png(output+"/editor_preset_"+str(preset)+".png") == OK,"preset capture")
	var history := get_undo_redo(); history.create_action("Material study light",UndoRedo.MERGE_DISABLE,scene)
	history.add_do_property(scene,"sun_yaw",-45.0); history.add_undo_property(scene,"sun_yaw",-28.0); history.commit_action()
	await frames(3); check(scene.sun_yaw == -45.0,"light edit failed")
	var undo := history.get_history_undo_redo(history.get_object_history_id(scene)); undo.undo(); await frames(3)
	check(scene.sun_yaw == -28.0,"Undo failed"); undo.redo(); await frames(3); check(scene.sun_yaw == -45.0,"Redo failed")
	history.create_action("Material light preset",UndoRedo.MERGE_DISABLE,scene)
	history.add_do_property(scene,"light_preset",0); history.add_undo_property(scene,"light_preset",2); history.commit_action()
	await frames(3); check(scene.light_preset == 0 and scene.sun_yaw == -45,"preset overwrote manual sun")
	undo.undo(); await frames(3); check(scene.light_preset == 2 and scene.sun_yaw == -45,"preset Undo lost manual sun")
	undo.redo(); await frames(3); check(scene.light_preset == 0,"preset Redo failed")
	undo.undo(); await frames(3)
	var optics_mesh: Mesh = scene.get_node("Sample3/Mesh").mesh
	var optics_source: Dictionary = scene.sample_sources[3].to_definition()
	history.create_action("Optics strength",UndoRedo.MERGE_DISABLE,scene)
	history.add_do_property(scene,"refraction_scale",0.75); history.add_undo_property(scene,"refraction_scale",1.0); history.commit_action()
	await frames(3); check(scene.refraction_scale == 0.75,"optics edit failed")
	undo.undo(); await frames(3); check(scene.refraction_scale == 1.0,"optics Undo failed")
	undo.redo(); await frames(3); check(scene.refraction_scale == 0.75,"optics Redo failed")
	check(scene.get_node("Sample3/Mesh").mesh == optics_mesh and scene.sample_sources[3].to_definition() == optics_source,"optics remeshed or mutated source")
	history.create_action("Cloud strength",UndoRedo.MERGE_DISABLE,scene)
	history.add_do_property(scene,"cloud_strength",0.5); history.add_undo_property(scene,"cloud_strength",1.0); history.commit_action()
	await frames(3); check(scene.cloud_strength == 0.5,"cloud edit failed")
	undo.undo(); await frames(3); check(scene.cloud_strength == 1.0,"cloud Undo failed")
	undo.redo(); await frames(3); check(scene.cloud_strength == 0.5,"cloud Redo failed")
	scene.cloud_scale = 1.6; scene.cloud_seed = 17; scene.crystal_cloud_light = Color("ddbbff")
	await frames(3)
	check(scene.get_node("Sample3/Mesh").mesh == optics_mesh and scene.sample_sources[3].to_definition() == optics_source,"cloud remeshed or wrote source")
	history.create_action("Ice material profile",UndoRedo.MERGE_DISABLE,scene)
	history.add_do_property(scene,"ice_finish",0); history.add_undo_property(scene,"ice_finish",1); history.commit_action()
	await frames(3); check(scene.ice_finish == 0,"finish selection failed")
	undo.undo(); await frames(3); check(scene.ice_finish == 1,"finish Undo failed")
	undo.redo(); await frames(3); check(scene.ice_finish == 0,"finish Redo failed")
	scene.crystal_finish = 0; scene.probe_kind = 1; scene.crack_strength = 0.7; scene.bubble_strength = 0.8
	await frames(3)
	check(scene.get_node("Sample4/Mesh").mesh.surface_get_material(0).get_shader_parameter("optics_surface_roughness") < 0.1,"profile uniforms missing")
	scene.optics_enabled = false; await frames(3)
	check(EditorInterface.save_scene() == OK,"save optics off failed")
	EditorInterface.reload_scene_from_path(scene.scene_file_path); await frames(6)
	scene = EditorInterface.get_edited_scene_root()
	check(not scene.optics_enabled and scene.refraction_scale == 0.75 and scene.cloud_strength == 0.5 and scene.cloud_scale == 1.6 and scene.cloud_seed == 17 and scene.crystal_cloud_light == Color("ddbbff") and scene.ice_finish == 0 and scene.crystal_finish == 0 and scene.probe_kind == 1 and scene.crack_strength == 0.7 and scene.bubble_strength == 0.8,"reopen optics off lost settings")
	scene.optics_enabled = true; scene.apply_settings(); await frames(3)
	check(scene.get_node("Sample3/Mesh").mesh.surface_get_material(0).shader.code.contains("ember_surface_optics"),"reopen enable lost optical material")
	RenderingServer.force_draw(false)
	check(EditorInterface.get_editor_viewport_3d(0).get_texture().get_image().save_png(output+"/editor_optics.png") == OK,"optics capture")
	check(EditorInterface.save_scene() == OK,"save failed")
	var disk := (ResourceLoader.load(scene.scene_file_path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene).instantiate()
	check(disk.sun_yaw == -45.0 and disk.light_preset == 2 and disk.surface_response and disk.sample_sources.size() == 6,"save/reopen lost settings or sources"); disk.free()
	scene.sun_yaw = 30; EditorInterface.reload_scene_from_path(scene.scene_file_path); await frames(8)
	scene = EditorInterface.get_edited_scene_root(); check(scene.sun_yaw == -45.0,"discard/reload failed")
	camera.queue_free()
	if FileAccess.file_exists(output+"/runtime-result.json"): DirAccess.remove_absolute(ProjectSettings.globalize_path(output+"/runtime-result.json"))
	print("OBJECT_MATERIAL launch-F6")
	EditorInterface.play_current_scene(); deadline = Time.get_ticks_msec()+45000
	while not FileAccess.file_exists(output+"/runtime-result.json") and Time.get_ticks_msec() < deadline: await frames(1)
	check(FileAccess.file_exists(output+"/runtime-result.json"),"F6 timeout")
	if FileAccess.file_exists(output+"/runtime-result.json"):
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output+"/runtime-result.json"))
		check(result.ok and result.saved_sun_yaw == -45.0 and result.saved_preset == 2 and result.optics_enabled and result.refraction_scale == 0.75 and result.cloud_strength == 0.5 and result.cloud_scale == 1.6 and result.cloud_seed == 17 and result.cloud_light == "ddbbff" and result.ice_finish == 0 and result.crystal_finish == 0 and result.probe_kind == 1 and result.neutral_light and is_equal_approx(result.effective_yaw,-147.0),"F6 saved settings mismatch")
	EditorInterface.stop_playing_scene(); await frames(6)
	print("OBJECT_MATERIAL completed ok=",errors.is_empty()," errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
