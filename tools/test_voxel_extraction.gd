extends SceneTree
const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Extraction = preload("res://addons/ember_import/ember_voxel_extraction_session.gd")
const Split = preload("res://addons/ember_import/ember_voxel_object_split.gd")
const Assembly = preload("res://addons/ember_import/ember_voxel_assembly_session.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
var failures := 0
var folder := "user://extraction_%d" % Time.get_ticks_usec()
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void:
	_run.call_deferred()
func edit_for(prop: EmberVoxelProp, scene: Node, undo: Object) -> RefCounted:
	var edit := Session.new()
	edit.source_directory = folder.path_join("sources")
	edit.prefab_directory = folder.path_join("prefabs")
	check(edit.open(prop,scene,undo),"open " + edit.error)
	return edit
func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var parent := Node3D.new()
	scene.add_child(parent)
	parent.owner = scene
	parent.position = Vector3(8,3,5)
	parent.rotation.y = 0.3
	var undo := UndoRedo.new()
	var creation := Creation.new()
	creation.source_directory = folder.path_join("sources")
	creation.prefab_directory = folder.path_join("prefabs")
	check(creation.prepare("block",Vector3i(32,4,32),16,Color.BROWN,"Доска"),"create")
	creation.source.shine.resize(creation.source.voxels.size())
	creation.source.shine.fill(70)
	creation.source.voxel_groups = [{"id":"wood","name":"Wood","indices":PackedInt32Array([0,1,2]),"locked":false}]
	creation.packed = EmberVoxelPrefab.prepare_resource(creation.source)
	var prop := creation.commit(scene,parent,undo,Vector3(2,0,3))
	prop.rotation.z = 0.1
	prop.scale = Vector3(1.2,0.8,1.1)
	var linked := EmberSceneAuthoring.make_duplicate(scene,prop,Vector3(70,0,0))
	EmberSceneAuthoring.attach_duplicate(scene,prop,parent,linked)
	var initial_id := prop.model_id
	var initial_hash := FileAccess.get_sha256(creation.source_directory.path_join(initial_id+".tres"))
	var edit := edit_for(prop,scene,undo)
	var selected := PackedInt32Array([0,1,2,32,33,34])
	var extract := Extraction.new()
	check(extract.prepare(edit,edit.draft,selected,true),"prepare cut " + extract.error)
	check(not FileAccess.file_exists(extract._source_path) and prop.model_id == initial_id,"prepare no writes")
	var old_frame: Transform3D = edit.context_projection(edit.draft).frame
	var fragment := extract.commit(undo)
	check(fragment != null,"cut commit " + extract.error)
	if fragment == null:
		quit(1)
		return
	check(fragment.get_parent() == parent and fragment.owner == scene,"scene owner")
	var new_frame: Transform3D = fragment.get_node("Mesh").global_transform
	check((new_frame*Vector3(0.5,0.5,0.5)/16.0).is_finite(),"finite")
	check((new_frame*(Vector3.ONE*0.5/16.0)).is_equal_approx(old_frame*(Vector3.ONE*0.5/16.0)),"world position parity")
	check(fragment.get_node("Collision/Shape").shape is ConcavePolygonShape3D,"collision built")
	check(fragment.get_node("Collision/Shape").global_transform.is_equal_approx(new_frame),"collision frame parity")
	var remainder := edit_for(prop,scene,undo)
	check(remainder.draft.voxels[0] == 0 and remainder.draft.voxels[3] == 1,"cut only selected")
	check(extract.piece.shine[0] == 70 and extract.piece.voxel_groups[0].indices.size() == 3,"material and groups")
	check(linked.model_id == initial_id and FileAccess.get_sha256(creation.source_directory.path_join(initial_id+".tres")) == initial_hash,"linked untouched")
	var cut_id := prop.model_id
	undo.undo()
	check(prop.model_id == initial_id and fragment.get_parent() == null,"one undo restores source and removes fragment")
	undo.redo()
	check(prop.model_id == cut_id and fragment.get_parent() == parent,"redo same references")
	check(FileAccess.file_exists(extract._source_path),"files retained")
	var entire := edit_for(linked,scene,undo)
	var all_indices := PackedInt32Array()
	for index in entire.draft.voxels.size():
		all_indices.append(index)
	var all_extract := Extraction.new()
	check(all_extract.prepare(entire,entire.draft,all_indices,true),"whole object extraction prepare " + all_extract.error)
	var all_piece := all_extract.commit(undo)
	check(all_piece != null,"whole object extraction")
	undo.undo()
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK,"scene pack")
	var path := folder.path_join("scene.tscn")
	check(ResourceSaver.save(packed,path) == OK,"scene save")
	var reopened := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(reopened)
	var restored := reopened.get_node(scene.get_path_to(fragment))
	check(restored.model_id == fragment.model_id and restored.get_node("Mesh").global_transform.is_equal_approx(new_frame),"reopen position")
	reopened.free()
	var copied := Extraction.new()
	edit = edit_for(prop,scene,undo)
	check(copied.prepare(edit,edit.draft,PackedInt32Array([2442]),false),"copy prepare")
	var duplicate := copied.commit(undo)
	check(duplicate != null and prop.model_id == cut_id,"copy source unchanged")
	check(duplicate.placement_id != fragment.placement_id,"unique placement id")
	var expected_point: Vector3 = old_frame*((Vector3(10,2,12)+Vector3.ONE*0.5)/16.0)
	check((duplicate.get_node("Mesh").global_transform*(Vector3.ONE*0.5/16.0)).is_equal_approx(expected_point),"nonzero XYZ crop origin")
	check(packed.pack(scene) == OK and ResourceSaver.save(packed,path) == OK,"copy pack")
	reopened = (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(reopened)
	var copy_restored := reopened.get_node(scene.get_path_to(duplicate))
	check((copy_restored.get_node("Mesh").global_transform*(Vector3.ONE*0.5/16.0)).is_equal_approx(expected_point),"copy offset reopen")
	reopened.free()
	var guarded := Extraction.new()
	edit.shared = true
	check(not guarded.prepare(edit,edit.draft,PackedInt32Array([3]),true),"shared refused")
	edit.shared = false
	var dirty := edit.draft.duplicate(true) as EmberVoxelModelResource
	dirty.voxels[3] = 0
	check(not guarded.prepare(edit,dirty,PackedInt32Array([4]),true),"unsaved refused")
	var stale := Extraction.new()
	check(stale.prepare(edit,edit.draft,PackedInt32Array([3]),false),"stale prepare")
	prop.position.x += 1
	check(stale.commit(undo) == null and not FileAccess.file_exists(stale._source_path),"stale position refuses without writes")
	prop.position.x -= 1
	var failed := Extraction.new()
	check(failed.prepare(edit,edit.draft,PackedInt32Array([3]),true),"failure prepare")
	edit.prefab_directory = creation.source_directory.path_join(cut_id+".tres")
	var children := parent.get_child_count()
	check(failed.commit(undo) == null and prop.model_id == cut_id and parent.get_child_count() == children,"late publication failure atomic scene")
	# Separate assembly fixture, extraction across two source sections.
	check(creation.prepare("block",Vector3i(64,4,32),16,Color.BROWN,"Assembly"),"assembly shape")
	var deck := creation.commit(scene,parent,undo,Vector3(100,0,0))
	var split := Split.new()
	split.source_directory = creation.source_directory
	split.prefab_directory = creation.prefab_directory
	check(split.prepare(deck,scene,32),"split")
	var group := split.commit(undo)
	var assembly := Assembly.new()
	assembly.source_directory = creation.source_directory
	assembly.prefab_directory = creation.prefab_directory
	check(assembly.open(group,scene,undo),"assembly open")
	var separate := Extraction.new()
	check(separate.prepare(assembly,assembly.draft,PackedInt32Array([31,32]),true),"assembly extraction prepare " + separate.error)
	var piece := separate.commit(undo)
	check(piece != null and piece.get_parent() == group.get_parent(),"assembly sibling")
	check(assembly.refresh_before_open(),"assembly reopen after cut")
	check(assembly.draft.voxels[31] == 0 and assembly.draft.voxels[32] == 0,"cross section cut")
	undo.undo()
	check(assembly.refresh_before_open() and assembly.draft.voxels[31] == 1 and assembly.draft.voxels[32] == 1,"assembly undo")
	# Native UI confirmation: cancel leaves authoring state unchanged.
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.open_object(edit_for(prop,scene,undo))
	workspace._selection_panel.set_selection(PackedInt32Array([3]))
	for frame in 4:
		await process_frame
	workspace._extract_voxel_selection(false)
	var dialog: ConfirmationDialog
	for child in workspace.get_children():
		if child is ConfirmationDialog and child.title == "Скопировать фрагмент":
			dialog = child
	check(dialog != null,"UI confirm")
	if dialog != null:
		if "--capture" in OS.get_cmdline_user_args():
			root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
			root.content_scale_size = Vector2i.ZERO
			root.size = Vector2i(1280,720)
			workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			dialog.popup_centered()
			for frame in 8:
				await process_frame
			root.get_texture().get_image().save_png("user://voxel_extraction.png")
			print("CAPTURE ",ProjectSettings.globalize_path("user://voxel_extraction.png"))
		dialog.canceled.emit()
		check(prop.model_id == cut_id,"cancel source unchanged")
		await process_frame
		var before_ui := parent.get_child_count()
		workspace._extract_voxel_selection(true)
		for child in workspace.get_children():
			if child is ConfirmationDialog and child.title == "Вырезать фрагмент":
				child.confirmed.emit()
				break
		check(parent.get_child_count() == before_ui+1 and workspace._resource != null and workspace._resource.voxels[3] == 0,"UI stays in updated Canvas by default")
		check(not workspace.has_unsaved_changes(),"refreshed draft clean")
		undo.undo()
		check(workspace._resource.voxels[3] == 1,"staying Canvas follows extraction Undo")
		undo.redo()
		check(workspace._resource.voxels[3] == 0,"staying Canvas follows extraction Redo")
		await process_frame
		workspace._selection_panel.set_selection(PackedInt32Array([4]))
		for frame in 3:
			await process_frame
		workspace._extract_voxel_selection(false)
		for child in workspace.get_children():
			if child is ConfirmationDialog and child.title == "Скопировать фрагмент":
				child.find_child("ExtractionGoTo3D",true,false).button_pressed = true
				child.confirmed.emit()
				break
		check(workspace._resource == null and workspace._extraction_go_to_3d,"explicit 3D option closes Canvas")
	workspace.free()
	if "--benchmark" in OS.get_cmdline_user_args():
		check(creation.prepare("block",Vector3i(128,8,128),16,Color.BROWN,"Large deck"),"large fixture")
		var large := creation.commit(scene,parent,undo,Vector3(400,0,0))
		var large_edit := edit_for(large,scene,undo)
		var large_indices := PackedInt32Array()
		for index in 32768:
			large_indices.append(index)
		var large_extract := Extraction.new()
		var started := Time.get_ticks_usec()
		check(large_extract.prepare(large_edit,large_edit.draft,large_indices,true),"large prepare")
		var prepared_ms := (Time.get_ticks_usec()-started)/1000.0
		started = Time.get_ticks_usec()
		check(large_extract.commit(undo) != null,"large commit")
		print("BENCH 32768 selected / 131072 cells: prepare_ms=",prepared_ms," commit_ms=",(Time.get_ticks_usec()-started)/1000.0)
	undo.clear_history()
	undo.free()
	scene.free()
	print("test_voxel_extraction: ","PASS" if failures == 0 else "FAIL"," · ",failures)
	quit(failures)
