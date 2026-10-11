extends SceneTree

const ShapePanel = preload("res://addons/ember_import/ember_voxel_shape_dialog.gd")
var errors: Array[String] = []
var created: EmberVoxelProp

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)

func _run() -> void:
	var scene := Node3D.new(); root.add_child(scene)
	var props := Node3D.new(); scene.add_child(props); props.owner = scene
	var undo := UndoRedo.new()
	var dock := VBoxContainer.new(); dock.size = Vector2(302,600)
	var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme; root.add_child(dock)
	var panel := ShapePanel.new(); panel.use_dock_layout(); root.add_child(panel); dock.add_child(panel.parameters_panel)
	panel.size = Vector2(640,260)
	var directory := "user://ember-tests/shape-dock-%d" % Time.get_ticks_usec()
	panel.source_directory_override = directory.path_join("models"); panel.prefab_directory_override = directory.path_join("prefabs")
	panel.created.connect(func(prop: EmberVoxelProp): created = prop)
	panel.open_for(scene,props,undo,Vector3(8,4,3))
	check(not panel.is_dirty() and panel.get_create_button().disabled,"new context dirty / creatable before preview")
	for kind in 4:
		panel._kind.select(kind); panel._kind_changed()
		panel._sizes[0].value = 12; panel._sizes[1].value = 3; panel._sizes[2].value = 5
		panel._prepare_button.pressed.emit()
		check(not panel.get_create_button().disabled and panel.creation != null,"fixture preview failed")
		check(not FileAccess.file_exists(panel.creation.source_directory.path_join(panel.creation.source.model_id + ".tres")),"preview wrote source")
		check(props.get_child_count() == 0,"preview created scene prop")
		for frame in 5: await process_frame
		check(panel.parameters_panel.get_combined_minimum_size().x <= 302,"narrow shape dock overflow")
		panel._parameter_scroll.scroll_vertical = 10000
		for frame in 3: await process_frame
		check(dock.get_global_rect().encloses(panel.get_create_button().get_global_rect()),"Create outside pinned footer")
		panel.hide(); panel.show(); check(panel.creation != null,"collapse discarded candidate")
		var id: String = panel.creation.source.model_id
		panel._title.text = "Changed " + str(kind); panel._title.text_changed.emit(panel._title.text)
		check(panel.get_create_button().disabled and panel.creation == null and panel._preview == null,"field retained stale candidate")
		panel._commit(); check(props.get_child_count() == 0,"stale direct commit created object")
		panel._prepare(); check(panel.creation.source.model_id != id,"new preview reused invalid candidate ID")
	panel.cancel_edit(); check(panel.creation == null and panel._preview == null and props.get_child_count() == 0,"Cancel mutated scene / retained geometry")
	panel.open_for(scene,props,undo,Vector3(8,4,3)); panel._kind.select(1); panel._kind_changed()
	panel._sizes[0].value = 12; panel._sizes[1].value = 3; panel._sizes[2].value = 5; panel._prepare()
	var model: Resource = panel.creation.source.duplicate(true)
	panel.get_create_button().pressed.emit()
	check(created != null and props.get_child_count() == 1 and created.owner == scene,"Create ownership")
	check(created.position == Vector3(8,4,3) and panel.creation == null,"Create position / candidate cleanup")
	var saved: Resource = load(panel.source_directory_override.path_join(created.model_id + ".tres"))
	check(saved.voxels == model.voxels and saved.palette == model.palette,"prepared != saved source")
	undo.undo(); check(props.get_child_count() == 0,"one Undo")
	undo.redo(); check(props.get_child_count() == 1,"Redo")
	var packed := PackedScene.new(); check(packed.pack(scene) == OK,"scene pack")
	check(ResourceSaver.save(packed,directory.path_join("scene.tscn")) == OK,"scene save")
	var reopened := (load(directory.path_join("scene.tscn")) as PackedScene).instantiate()
	check(reopened.get_child(0).get_child(0).model_id == created.model_id,"Save-Reopen instance")
	reopened.free()
	panel.open_for(scene,props,undo,Vector3.ZERO)
	check(not panel._check_large_budget(Vector3i(192,10,256)),"large budget unguarded")
	panel._large_ack.button_pressed = true
	check(panel._check_large_budget(Vector3i(192,10,256)),"large acknowledgment ignored")
	panel._invalidate(); check(not panel._large_ack.button_pressed,"changed parameters preserved large acknowledgment")
	panel.cancel_edit(); undo.clear_history(); undo.free(); panel.free(); dock.free(); scene.free()
	print("VOXEL_SHAPE_DOCK ","PASS" if errors.is_empty() else "FAIL"," narrow/pinned/kinds/preview/no-write/invalidate/collapse/Cancel/Create/Undo-Redo/Save-Reopen/budget errors=",errors)
	quit(0 if errors.is_empty() else 1)
