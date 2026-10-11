extends SceneTree
const SplitPanel = preload("res://addons/ember_import/ember_voxel_split_dialog.gd")
const ConversionPanel = preload("res://addons/ember_import/ember_voxel_conversion_dialog.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
var errors: Array[String] = []
var converted: EmberVoxelProp

func _initialize() -> void: _run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); push_error(message)

func _run() -> void:
	var folder := "user://ember-tests/remaining-docks-%d" % Time.get_ticks_usec()
	var scene := Node3D.new(); root.add_child(scene)
	var source: EmberVoxelModelResource = Shapes.build("block",Vector3i(80,3,80),16,Color.BROWN,"remaining_split","Split").source
	var saved := Store.install_prepared_asset(source,EmberVoxelPrefab.prepare_resource(source),folder.path_join("remaining_split.tres"),folder.path_join("split.tscn"))
	check(saved.ok,"split fixture install")
	var prop := EmberSceneAuthoring.make_model_instance(scene,saved.packed,source.model_id,Vector3(8,4,3)); EmberSceneAuthoring.attach_model_instance(scene,scene,prop)
	var pose := prop.transform; var hash := FileAccess.get_sha256(folder.path_join("remaining_split.tres"))
	var undo := UndoRedo.new()
	var dock := VBoxContainer.new(); dock.size = Vector2(302,650)
	var theme := Theme.new(); theme.default_font_size = 20; dock.theme = theme; root.add_child(dock)
	var split := SplitPanel.new(); split.use_dock_layout(); root.add_child(split); dock.add_child(split.parameters_panel)
	split.size = Vector2(640,280); split.source_directory = folder; split.prefab_directory = folder.path_join("parts")
	split.open_split(prop,scene,undo)
	check(split.is_dirty() and split._splitter == null and split.get_ok_button().disabled,"split prepared automatically")
	split._prepare_button.pressed.emit()
	check(not split.get_ok_button().disabled and split._splitter.parts.size() == 4 and split._splitter.parts.back().size == Vector3i(16,3,16),"split preview edge sections")
	check(split.matches_context(prop,scene) and prop.transform == pose,"split bound target / preview moved source")
	for frame in 5: await process_frame
	check(split.parameters_panel.get_combined_minimum_size().x <= 302,"split narrow overflow")
	split._parameter_scroll.scroll_vertical = 10000
	for frame in 3: await process_frame
	check(dock.get_global_rect().encloses(split._prepare_button.get_global_rect()) and dock.get_global_rect().encloses(split.get_ok_button().get_global_rect()),"split pinned actions")
	split._section.select(0); split._section.item_selected.emit(0)
	check(split._splitter == null and split._preview == null and split.get_ok_button().disabled,"section retained stale preview")
	split._prepare(); check(split._splitter.parts.size() == 9,"section value not used")
	prop.position.x += 1; split.get_ok_button().pressed.emit(); check(scene.get_child(0) == prop and split.get_ok_button().disabled,"split stale accepted")
	prop.transform = pose; split._prepare(); split.cancel_edit()
	check(split._target_ref == null and split._splitter == null and prop.transform == pose,"split Cancel changed source / retained refs")
	split.open_split(prop,scene,undo); split._prepare(); split.get_ok_button().pressed.emit()
	var group := scene.get_child(0)
	check(group != prop and group.get_child_count() == 4 and not split.is_queued_for_deletion() and not split.is_dirty(),"split apply / reusable cleanup")
	undo.undo(); check(scene.get_child(0) == prop and prop.transform == pose,"split one Undo")
	undo.redo(); check(scene.get_child(0) == group,"split Redo")
	var packed := PackedScene.new(); check(packed.pack(scene) == OK,"pack split scene")
	var path := folder.path_join("map.tscn"); check(ResourceSaver.save(packed,path) == OK,"save split scene")
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	check(reopened.get_child(0).get_child_count() == 4,"split Save-Reopen"); reopened.free()
	check(FileAccess.get_sha256(folder.path_join("remaining_split.tres")) == hash,"split changed original file")
	undo.clear_history(); split.free(); scene.free()
	var panel := ConversionPanel.new(); panel.use_dock_layout(); root.add_child(panel); dock.add_child(panel.parameters_panel); panel.size = Vector2(640,280)
	panel.source_directory_override = folder.path_join("converted"); panel.prefab_directory_override = folder.path_join("converted")
	panel.created.connect(func(result: EmberVoxelProp): converted = result)
	for kind in ["block","cylinder","sphere"]:
		scene = Node3D.new(); root.add_child(scene)
		var original := MeshInstance3D.new(); scene.add_child(original); original.owner = scene; original.name = kind
		if kind == "block":
			var mesh := BoxMesh.new(); mesh.size = Vector3(12,4,10); original.mesh = mesh
		elif kind == "cylinder":
			var mesh := CylinderMesh.new(); mesh.top_radius = 3; mesh.bottom_radius = 3; mesh.height = 6; original.mesh = mesh
		else:
			var mesh := SphereMesh.new(); mesh.radius = 3; mesh.height = 6; original.mesh = mesh
		check(panel.open_conversion(original,scene,undo,16),"conversion open")
		check(panel.creation == null and panel.get_ok_button().disabled and panel.matches_context(original,scene),"conversion auto prepared / wrong target")
		panel._prepare_button.pressed.emit()
		check(not panel.get_ok_button().disabled,"conversion preview: "+panel._status.text)
		if panel.get_ok_button().disabled: quit(1); return
		var candidate: RefCounted = panel.creation; var output_path: String = candidate.source_directory.path_join(candidate.source.model_id+".tres")
		check(not FileAccess.file_exists(output_path),"conversion preview published assets")
		panel._show_original.button_pressed = true
		check(panel.creation == candidate and panel._original_preview.visible and not panel._preview.visible,"comparison rebuilt / failed")
		panel._show_original.button_pressed = false
		var size_before := Vector3(panel._sizes[0].value,panel._sizes[1].value,panel._sizes[2].value)
		panel._density.select(1); panel._density.item_selected.emit(1)
		check(panel.creation == null and panel._original_preview == null and Vector3(panel._sizes[0].value,panel._sizes[1].value,panel._sizes[2].value) == size_before*2,"density rescale/invalidate")
		panel._prepare(); check(panel.creation.source.normalized_density() == 32,"density lost")
		for frame in 5: await process_frame
		check(panel.parameters_panel.get_combined_minimum_size().x <= 302,"conversion narrow overflow")
		panel._parameter_scroll.scroll_vertical = 10000
		for frame in 3: await process_frame
		check(dock.get_global_rect().encloses(panel._prepare_button.get_global_rect()) and dock.get_global_rect().encloses(panel.get_ok_button().get_global_rect()),"conversion pinned actions")
		original.position.x += 1; panel.get_ok_button().pressed.emit(); check(original.get_parent() == scene and panel.get_ok_button().disabled,"conversion stale accepted")
		original.position.x -= 1; panel._prepare()
		var permission := {"clean":false}; panel.can_commit = func(): return permission.clean
		panel.get_ok_button().pressed.emit(); check(original.get_parent() == scene,"conversion dirty Canvas applied")
		permission.clean = true; panel._prepare(); converted = null; panel.get_ok_button().pressed.emit()
		check(converted != null and original.get_parent() == null and panel._original == null and panel._original_preview == null and not panel.is_queued_for_deletion(),"conversion apply/cleanup")
		undo.undo(); check(original.get_parent() == scene,"conversion Undo")
		undo.redo(); check(converted.get_parent() == scene,"conversion Redo")
		undo.clear_history(); scene.free()
		panel.can_commit = Callable()
	scene = Node3D.new(); root.add_child(scene)
	var large := MeshInstance3D.new(); scene.add_child(large); large.owner = scene
	var large_mesh := BoxMesh.new(); large_mesh.size = Vector3(192,10,256); large.mesh = large_mesh
	panel.open_conversion(large,scene,undo,16); panel._prepare()
	check(panel._large_ack.visible and panel.creation == null and panel.get_ok_button().disabled,"large preview consent bypassed")
	panel._large_ack.button_pressed = true; panel._sizes[0].value -= 1
	check(not panel._large_ack.button_pressed,"large consent survived parameter change")
	panel.cancel_edit(); check(panel._root == null and panel._original == null and large.get_parent() == scene,"conversion Cancel changed source / retained refs")
	panel.free(); dock.free(); scene.free(); undo.free()
	print("VOXEL_REMAINING_DOCKS ","PASS" if errors.is_empty() else "FAIL"," split/conversion/explicit/narrow/pinned/compare/density/stale/Cancel/Canvas-guard/budget/Undo-Redo/Save-Reopen/source errors=",errors)
	quit(0 if errors.is_empty() else 1)
