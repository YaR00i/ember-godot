extends SceneTree

const MergePanel = preload("res://addons/ember_import/ember_voxel_merge_dialog.gd")
const ShapeCreation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
var errors: Array[String] = []

func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var folder := "user://ember-tests/merge-dock-%d" % Time.get_ticks_usec()
	var scene := Node3D.new(); root.add_child(scene)
	var props := Node3D.new(); scene.add_child(props); props.owner = scene
	var undo := UndoRedo.new(); var nodes: Array = []
	for index in 2:
		var creation := ShapeCreation.new(); creation.source_directory = folder; creation.prefab_directory = folder
		check(creation.prepare("block",Vector3i(12,3,5),16,Color.BROWN,"Board_"+str(index)),"fixture prepare")
		nodes.append(creation.commit(scene,props,undo,Vector3(12.25*index,0,0)))
	undo.clear_history()
	if nodes.any(func(node): return node == null): check(false,"fixture commit"); quit(1); return
	var hashes: Array = nodes.map(func(node): return FileAccess.get_sha256(folder.path_join(node.model_id+".tres")))
	var poses: Array = nodes.map(func(node): return node.transform)
	var dock := VBoxContainer.new(); dock.size = Vector2(302,600)
	var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme; root.add_child(dock)
	var panel := MergePanel.new(); panel.use_dock_layout(); root.add_child(panel); dock.add_child(panel.parameters_panel)
	panel.source_directory = folder; panel.prefab_directory = folder; panel.size = Vector2(640,280)
	panel.open_merge(nodes,scene,undo)
	check(panel._session == null and panel.get_ok_button().disabled and panel.is_dirty(),"dock prepared automatically / lost pending context")
	check(panel.matches_context([nodes[1],nodes[0]],scene,false) and not panel.matches_context(nodes,scene,true),"same selection/mode matching")
	panel._align.button_pressed = true
	check(panel._session == null,"small input rebuilt merge")
	panel._prepare_button.pressed.emit()
	check(not panel.get_ok_button().disabled and panel._session != null,"aligned preview failed: "+panel._status.text)
	if panel.get_ok_button().disabled: quit(1); return
	var candidate: RefCounted = panel._session; var definition: Dictionary = candidate.preview.to_definition()
	panel._scene_orientation.button_pressed = false
	check(panel._session == candidate and panel._session.preview.to_definition() == definition,"view toggle changed prepared operation")
	check(nodes.map(func(node): return node.transform) == poses and props.get_child_count() == 2,"preview moved originals")
	for frame in 5: await process_frame
	check(panel.parameters_panel.get_combined_minimum_size().x <= 302,"narrow merge dock overflow")
	panel._parameter_scroll.scroll_vertical = 10000
	for frame in 3: await process_frame
	check(dock.get_global_rect().encloses(panel._prepare_button.get_global_rect()) and dock.get_global_rect().encloses(panel.get_ok_button().get_global_rect()),"actions outside pinned footer")
	panel.hide(); panel.show(); check(panel._session == candidate,"collapse lost candidate")
	panel._primary.select(1); panel._primary.item_selected.emit(1)
	check(not panel._align.button_pressed and panel._session == null and panel.get_ok_button().disabled,"primary switch retained stale candidate")
	panel._primary.select(0); panel._primary.item_selected.emit(0); panel._align.button_pressed = true; panel._prepare()
	var initial_parent := props.transform; props.position.x += 1
	panel.get_ok_button().pressed.emit()
	check(panel.get_ok_button().disabled and props.get_child_count() == 2,"stale parent accepted")
	props.transform = initial_parent; panel._prepare()
	var permission := {"clean":false}; panel.can_commit = func(): return permission.clean
	panel.get_ok_button().pressed.emit(); check(props.get_child_count() == 2,"dirty Canvas guard accepted commit")
	permission.clean = true; panel._prepare()
	panel.get_ok_button().pressed.emit()
	check(props.get_child_count() == 1 and panel._session == null and panel._selection.is_empty() and not panel.is_queued_for_deletion(),"commit did not release reusable controller")
	var merged := props.get_child(0)
	undo.undo(); check(props.get_child_count() == 2 and nodes.map(func(node): return node.transform) == poses,"one Undo lost exact originals")
	undo.redo(); check(props.get_child_count() == 1 and props.get_child(0) == merged,"Redo failed")
	var packed := PackedScene.new(); check(packed.pack(scene) == OK,"pack merged scene")
	var path := folder.path_join("map.tscn"); check(ResourceSaver.save(packed,path) == OK,"save merged scene")
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_child(0).get_child_count() == 1,"reopen merged scene"); reopened.free()
	var child_count := panel._status.get_parent().get_child_count()
	panel.open_merge([merged],scene,undo,true); panel._prepare_button.pressed.emit()
	check(not panel.get_ok_button().disabled and panel._session.outputs.size() == 2,"unmerge preview failed")
	check(panel._status.get_parent().get_child_count() == child_count,"reopen duplicated controls")
	panel.cancel_edit(); check(panel._session == null and panel._preview == null and props.get_child_count() == 1,"Cancel mutated scene / retained preview")
	panel.open_merge([merged],scene,undo,true); panel._prepare(); panel.get_ok_button().pressed.emit()
	check(props.get_child_count() == 2,"unmerge commit failed")
	undo.undo(); check(props.get_child_count() == 1 and props.get_child(0) == merged,"unmerge Undo failed")
	undo.redo(); check(props.get_child_count() == 2,"unmerge Redo failed")
	check(nodes.map(func(node): return FileAccess.get_sha256(folder.path_join(node.model_id+".tres"))) == hashes,"operation modified original source files")
	undo.clear_history(); undo.free(); panel.free(); dock.free(); scene.free()
	print("VOXEL_MERGE_DOCK ","PASS" if errors.is_empty() else "FAIL"," explicit-preview/invalidate/narrow/pinned/view/context/stale/Canvas-guard/reuse/merge-unmerge/Undo-Redo/Save-Reopen/source errors=",errors)
	quit(0 if errors.is_empty() else 1)
