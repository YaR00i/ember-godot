extends SceneTree
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Dialog = preload("res://addons/ember_import/ember_voxel_fragment_dialog.gd")
var errors := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		errors += 1
		push_error(message)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var source: EmberVoxelModelResource = Shapes.build("empty",Vector3i(32,24,16),16,Color.BROWN,"bend_fixture","Board").source
	var indices := PackedInt32Array()
	for channel in Fragment.CHANNELS:
		var data := PackedByteArray()
		data.resize(source.voxels.size())
		source.set(channel, data)
	source.voxel_part_ids.resize(source.voxels.size())
	# Two-voxel thickness, margin around all axes; varying material data.
	for x in range(5, 26):
		for y in range(7, 9):
			for z in range(5, 11):
				var index := Model.index_of(Vector3i(x,y,z),source.grid_size())
				indices.append(index)
				for channel in Fragment.CHANNELS:
					var data: PackedByteArray = source.get(channel)
					data[index] = 1 if channel in ["voxels","collision_voxels"] else 20 + x
					source.set(channel,data)
				source.voxel_part_ids[index] = 1
	indices.sort()
	source.voxel_groups = [{"id":"grain","name":"Grain","indices":indices.duplicate(),"locked":false}]
	source.merge_parts = PackedStringArray(["board"])
	var initial := source.to_definition().duplicate(true)
	check(source.validation_errors().is_empty(),"fixture validation: " + str(source.validation_errors()))
	var plan := Fragment.bend(source,indices,0,1,4)
	check(not plan.has("error"),"bend plan: " + str(plan.get("error","")))
	check(source.to_definition() == initial,"preview must not mutate source")
	if plan.has("error"):
		quit(1)
		return
	check(plan.selected.size() == indices.size(),"preserve volume")
	for index in indices:
		var cell := preload("res://addons/ember_import/ember_voxel_selection.gd").cell_of(index,source.grid_size())
		var t := float(cell.x - 5) / 20.0
		cell.y += roundi(4.0 * 4.0 * t * (1.0 - t))
		var destination := Model.index_of(cell,source.grid_size())
		for channel in Fragment.CHANNELS:
			check(plan.properties[channel][destination] == source.get(channel)[index],"preserve " + channel)
		check(plan.properties.voxel_part_ids[destination] == 1,"preserve part ownership")
	check(plan.properties.voxel_groups[0].indices.size() == indices.size(),"group membership preserved")
	var undo := UndoRedo.new()
	var actions := EmberVoxelSculptActions.new()
	actions.configure(undo)
	check(actions.apply_fragment(source,plan),"one action commits bend")
	var bent := source.to_definition().duplicate(true)
	check(source.validation_errors().is_empty(),"bent source validation")
	undo.undo()
	check(source.to_definition() == initial and not undo.has_undo(),"single undo exact restoration")
	undo.redo()
	check(source.to_definition() == bent,"redo exact restoration")
	check(not actions.apply_fragment(source,plan),"stale preview rejected")
	var path := "user://ember-tests/bend-%d.tres" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ember-tests"))
	check(ResourceSaver.save(source,path) == OK,"save")
	var reopened := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	var reopened_definition := reopened.to_definition() if reopened != null else {}
	reopened_definition.erase("_resourcePath")
	var saved_definition := bent.duplicate(true)
	saved_definition.erase("_resourcePath")
	check(reopened != null and reopened_definition == saved_definition,"save/reopen all channels")
	undo.undo()
	check(Fragment.bend(source,indices,0,0,4).has("error"),"same axes rejected")
	check(Fragment.bend(source,indices,0,1,0).has("error"),"zero bend rejected")
	check(Fragment.bend(source,PackedInt32Array(),0,1,4).has("error"),"empty selection rejected")
	check(Fragment.bend(source,PackedInt32Array([indices[0]]),0,1,4).has("error"),"zero length rejected")
	var excessive := PackedInt32Array()
	excessive.resize(32769)
	check(Fragment.bend(source,excessive,0,1,4).has("error"),"operation limit rejected")
	check(Fragment.bend(source,indices,0,1,32).has("error"),"outside canvas rejected")
	check(Fragment.bend(source,indices,0,1,4,0,Rect2i(),8).has("error"),"slice bound rejected")
	check(Fragment.bend(source,indices,0,1,4,0,Rect2i(0,0,1,1)).has("error"),"working region bound rejected")
	check(not Fragment.bend(source,indices,0,1,-4,1).has("error"),"signed end bend")
	var end_plan := Fragment.bend(source,indices,0,1,-4,1)
	check(end_plan.properties.voxels[Model.index_of(Vector3i(5,7,5),source.grid_size())] == 1,"end bend pins start")
	check(end_plan.properties.voxels[Model.index_of(Vector3i(25,3,5),source.grid_size())] == 1,"end bend displaces far end")
	check(not Fragment.bend(source,indices,2,0,2).has("error"),"alternative axes")
	source.voxel_groups[0].locked = true
	check(Fragment.bend(source,indices,0,1,4).has("error"),"locked source rejected")
	source.voxel_groups[0].locked = false
	var obstacle := Model.index_of(Vector3i(15,11,5),source.grid_size())
	source.voxels[obstacle] = 1
	check(Fragment.bend(source,indices,0,1,4).has("error"),"overlap rejected")
	source.voxels[obstacle] = 0
	source.surface_fill_levels.resize(source.grid_size().x * source.grid_size().z)
	check(Fragment.bend(source,indices,0,1,4).has("error"),"surface water rejected")
	source.surface_fill_levels.clear()
	source.emissive_lights = [{"id":"fixture"}]
	check(Fragment.bend(source,indices,0,1,4).has("error"),"authored lights rejected")
	source.emissive_lights.clear()
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.open_bend(source,PackedInt32Array(),actions,Rect2i(),-1)
	check(dialog.indices.size() == indices.size() and dialog._along.selected == 0,"whole-object scope and longest axis default")
	dialog._amount.value = 4
	dialog._prepare()
	check(not dialog.get_ok_button().disabled,"dialog preview ready")
	check(source.to_definition() == initial,"dialog preview source unchanged")
	dialog._amount.value = 3
	check(dialog.get_ok_button().disabled and dialog.result.is_empty(),"parameter change invalidates preview")
	dialog._amount.value = 4
	dialog._prepare()
	if "--capture" in OS.get_cmdline_user_args():
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(1280,720)
		dialog.hide()
		dialog.popup_centered()
		for frame in 20:
			await process_frame
		RenderingServer.force_draw(false)
		var capture := "user://bend-preview.png"
		check(root.get_texture().get_image().save_png(capture) == OK,"native capture")
		print("CAPTURE ",ProjectSettings.globalize_path(capture))
	dialog.hide()
	check(source.to_definition() == initial,"discard preserves source")
	dialog.open_bend(source,indices,actions,Rect2i(),-1)
	dialog._amount.value = 4
	dialog._prepare()
	dialog._commit()
	check(source.to_definition() == bent,"dialog commit matches preview")
	undo.undo()
	check(source.to_definition() == initial,"dialog undo")
	dialog.free()
	# The visible workshop command uses the same draft and chronological Undo.
	var workspace := preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd").new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(source,"user://ember-tests/bend-workspace.tres")
	for frame in 6:
		await process_frame
	var bend_button := workspace.find_child("VoxelWorkshopBend",true,false) as Button
	check(bend_button != null and bend_button.is_visible_in_tree(),"visible workshop bend command")
	bend_button.pressed.emit()
	var workspace_dialog: ConfirmationDialog
	for child in workspace.get_children():
		if child is Dialog:
			workspace_dialog = child
	check(workspace_dialog != null and workspace_dialog.visible,"button opens bend")
	if workspace_dialog != null:
		workspace_dialog._amount.value = 4
		workspace_dialog._prepare()
		check(not workspace_dialog.get_ok_button().disabled,"workshop preview ready")
		workspace_dialog._commit()
		check(source.to_definition() == bent,"workshop preview/commit parity")
		undo.undo()
		check(source.to_definition() == initial,"workshop undo")
		for frame in 3:
			await process_frame
	workspace._selection_panel.set_selection(PackedInt32Array([indices[0],indices[1]]))
	workspace._bend_voxel_volume()
	for child in workspace.get_children():
		if child is Dialog:
			check(child.indices.size() == 2,"workshop respects selected scope")
			child.hide()
	workspace.free()
	var large: EmberVoxelModelResource = Shapes.build("empty",Vector3i(64,32,64),16,Color.BROWN,"bend_large","Large").source
	var large_indices := PackedInt32Array()
	for y in range(8,16):
		for z in 64:
			for x in 64:
				var index := Model.index_of(Vector3i(x,y,z),large.grid_size())
				large.voxels[index] = 1
				large_indices.append(index)
	var started := Time.get_ticks_usec()
	var large_plan := Fragment.bend(large,large_indices,0,1,4)
	print("Bend 32768 / 131072 cells plan ms: ",(Time.get_ticks_usec() - started) / 1000.0)
	check(not large_plan.has("error") and large_plan.selected.size() == 32768,"maximum supported volume")
	undo.clear_history()
	undo.free()
	print("test_voxel_bend: ","PASS" if errors == 0 else "FAIL"," · ",errors)
	quit(errors)
