@tool
extends EditorPlugin
## Enable only in the disposable Ember Rock Pilot checkout. Commands, not input.
var failures: Array[String] = []
func _enter_tree() -> void: run.call_deferred()
func frames(count: int) -> void:
	for frame in count: await get_tree().process_frame
func check(value: bool, message: String) -> void:
	if not value: failures.append(message); printerr("FAIL anomaly editor: ",message)

func ready_scene() -> Node:
	var deadline := Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		await frames(1)
		var scene := EditorInterface.get_edited_scene_root()
		if scene == null or scene.scene_file_path != "res://scenes/landscape_compact.tscn": continue
		var sphere := scene.get_node_or_null("Map/WorldAnomaly")
		var projection := scene.get_node_or_null("Map/DerivedCompactWorldTerrain")
		var patch := scene.get_node_or_null("Map/Props/GrassPatch")
		if sphere != null and projection != null and projection.pending_tile_count() == 0 and patch != null and not patch._dirty and not patch._rebuilding: return scene
	check(false,"scene preparation timeout")
	return null

func run() -> void:
	if ProjectSettings.get_setting("application/config/name") != "Ember Rock Pilot" or not ProjectSettings.globalize_path("res://").contains("ember-rock-pilot-"):
		printerr("Anomaly editor QA requires the disposable pilot project."); return
	await frames(20)
	var importer := get_parent().get_node_or_null("EmberImportPlugin")
	if importer == null: check(false,"importer missing"); get_tree().quit(1); return
	var deadline := Time.get_ticks_msec()+90000
	while not importer._editor_preparation._complete and Time.get_ticks_msec()<deadline: await frames(1)
	EditorInterface.open_scene_from_path("res://scenes/landscape_compact.tscn")
	var scene := await ready_scene()
	if scene == null: get_tree().quit(1); return
	var sphere: Node = scene.get_node("Map/WorldAnomaly")
	check(sphere.preparations == 0,"opening editor never prepares anomaly")
	var world: Node = importer._world_editor
	world.enabled.button_pressed = true
	var panel: Node = world.look_panel
	panel.set_target(scene,scene.get_node("Map"),get_undo_redo())
	if OS.get_cmdline_user_args().has("--layout-only"):
		panel._tabs.current_tab = 3
		await frames(3)
		await RenderingServer.frame_post_draw
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("user://anomaly-editing-editor.png")
		for label in ["Предпросмотр аномалии","Вернуться к редактированию земли"]:
			var found := false
			for button in panel.find_children("*","Button",true,false):
				if button.text == label:
					found = true
					check(button.is_visible_in_tree() and button.get_global_rect().intersection(button.get_viewport_rect()).size == button.size,"preview button visible: "+label)
			check(found,"preview button exists: "+label)
		print("WORLD_ANOMALY_LAYOUT ",JSON.stringify({"pass":failures.is_empty(),"failures":failures}))
		get_tree().quit(0 if failures.is_empty() else 1); return
	panel._preview_anomaly()
	var preview_deadline := Time.get_ticks_msec()+180000
	while not sphere._prepared and Time.get_ticks_msec()<preview_deadline: await frames(1)
	check(sphere._prepared,"real panel prepares explicit preview")
	for binding: Dictionary in sphere._bindings:
		check(binding.visual.get_parent() == binding.source and binding.visual.owner == null,"display keeps original editor owner and transform")
		check(binding.visual.global_transform.is_equal_approx(binding.source.global_transform),"display follows original transform")
	panel._stop_anomaly_preview()
	for binding: Dictionary in sphere._bindings: check(not binding.visual.visible,"real panel returns to authoring")
	panel._tabs.current_tab = 3
	await frames(3)
	await RenderingServer.frame_post_draw
	EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png("user://anomaly-editing-editor.png")
	panel._commit("anomaly_x",5.5,6.0,false)
	check(sphere.position.x == 96.0,"real panel moves sphere in metres")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo(); check(sphere.position.x == 88.0,"EditorUndoRedoManager Undo")
	history.redo(); check(sphere.position.x == 96.0,"EditorUndoRedoManager Redo")
	panel._commit("anomaly_radius",4.5,3.25,false)
	panel._commit("anomaly_feather",0.45,0.60,false)
	panel._choices.anomaly_look.item_selected.emit(1)
	check(EditorInterface.save_scene() == OK,"editor saves copy")
	var text := FileAccess.get_file_as_string(scene.scene_file_path)
	check(text.length() < 20000 and not text.contains("DerivedAnomaly") and not text.contains("ember_anomaly_targets"),"editor saves parameters only")
	EditorInterface.reload_scene_from_path(scene.scene_file_path)
	scene = await ready_scene()
	if scene == null: get_tree().quit(1); return
	sphere = scene.get_node("Map/WorldAnomaly")
	check(sphere.preparations == 0 and not sphere._preview_requested,"reopen restores editing mode, not preview state")
	check(sphere.position.x == 96.0 and sphere.radius_m == 3.25 and sphere.feather_m == 0.60 and sphere.inner_look == 2,"native reopen")
	check(sphere.validation_errors().is_empty(),"native validation")
	panel.set_target(scene,scene.get_node("Map"),get_undo_redo())
	panel._commit("anomaly_radius",3.25,9.0,false)
	EditorInterface.reload_scene_from_path(scene.scene_file_path)
	scene = await ready_scene()
	if scene == null: get_tree().quit(1); return
	check(scene.get_node("Map/WorldAnomaly").radius_m == 3.25,"native discard by reload")
	var report := {"pass":failures.is_empty(),"failures":failures,"history":"EditorUndoRedoManager","renderer":RenderingServer.get_current_rendering_method(),"manual":"mouse/hotkeys and feel OPEN"}
	var output := "user://anomaly-editing-editor-checks.json"
	var file := FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t"))
	print("WORLD_ANOMALY_EDITOR ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
