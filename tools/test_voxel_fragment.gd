extends SceneTree
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
var errors := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var source: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,16,16),16,Color.BROWN,"fragment_test","Fragment").source
	source.voxels[0] = 1
	source.voxels[1] = 1
	source.shine.resize(source.voxels.size())
	source.shine[1] = 70
	source.voxel_groups = [{"id":"board","name":"Board","indices":PackedInt32Array([0,1]),"locked":false}]
	var initial := source.to_definition().duplicate(true)
	var indices := PackedInt32Array([0,1])
	var plan := Fragment.plan(source,indices,Vector3i(2,0,0),1,0,false)
	check(not plan.has("error"),"plan")
	check(source.to_definition() == initial,"preview no mutation")
	var undo := UndoRedo.new()
	var actions := EmberVoxelSculptActions.new()
	actions.configure(undo)
	check(actions.apply_fragment(source,plan),"apply")
	check(source.voxels[0] == 0 and source.voxels[3] == 1 and source.shine[3] == 70,"move channels")
	check(source.voxel_groups[0].indices == PackedInt32Array([2,3]),"move groups")
	undo.undo()
	check(source.to_definition() == initial,"undo exact")
	undo.redo()
	check(source.shine[3] == 70,"redo")
	check(not actions.apply_fragment(source,plan),"stale rejected")
	undo.undo()
	var copy := Fragment.plan(source,indices,Vector3i(4,0,0),1,1,true)
	check(not copy.has("error") and actions.apply_fragment(source,copy),"copy rotate")
	check(source.voxels[0] == 1 and source.voxels[4] == 1 and source.voxels[20] == 1 and source.shine[4] == 70,"rotation coordinates")
	var path := "user://fragment_%d.tres" % Time.get_ticks_usec()
	check(ResourceSaver.save(source,path) == OK,"save")
	var reopened := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(reopened.voxels == source.voxels and reopened.shine == source.shine and reopened.voxel_groups == source.voxel_groups,"reopen")
	check(Fragment.plan(source,indices,Vector3i.ZERO,1,0,true).has("error"),"copy overlap")
	check(Fragment.plan(source,indices,Vector3i(-1,0,0),1,0,false).has("error"),"bounds")
	source.voxel_groups[0].locked = true
	check(Fragment.plan(source,indices,Vector3i(8,0,0),1,0,false).has("error"),"locked")
	source.voxel_groups[0].locked = false
	var box := Selection.new()
	box.start_box(source,Vector3i.ZERO,Vector3i(4,0,1))
	while not box.done:
		box.step(128)
	check(box.error.is_empty() and box.indices.size() == 4,"box occupied only")
	box.start_box(source,Vector3i(0,0,1),Vector3i(4,0,0))
	while not box.done:
		box.step(128)
	check(box.error.is_empty() and box.indices.size() == 4,"box empty corner")
	check(Fragment.plan(source,indices,Vector3i(0,1,0),1,0,false,Rect2i(),0).has("error"),"slice boundary")
	var large: EmberVoxelModelResource = Shapes.build("empty",Vector3i(64,32,64),16,Color.BROWN,"large_fragment","Large").source
	var large_indices := PackedInt32Array()
	for index in 16384:
		large.voxels[index] = 1
		large_indices.append(index)
	var started := Time.get_ticks_usec()
	var large_plan := Fragment.plan(large,large_indices,Vector3i(0,4,0),1,0,false)
	print("Fragment 16384 / 131072 cells plan ms: ", (Time.get_ticks_usec()-started)/1000.0)
	check(not large_plan.has("error"),"large plan")
	check(Selection.combine({0:true},PackedInt32Array([1]),1).size() == 2,"add")
	check(Selection.combine({0:true,1:true},PackedInt32Array([1]),2).size() == 1,"subtract")
	var dialog := preload("res://addons/ember_import/ember_voxel_fragment_dialog.gd").new()
	root.add_child(dialog)
	dialog.open_for(source,indices,actions,Rect2i(),-1)
	dialog._numbers[0].value = 8
	dialog._prepare()
	check(not dialog.get_ok_button().disabled,"dialog preview")
	var before_cancel := source.to_definition().duplicate(true)
	dialog.hide()
	check(source.to_definition() == before_cancel,"cancel")
	if "--capture" in OS.get_cmdline_user_args():
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(1280,720)
		dialog.size = Vector2i(620,650)
		dialog.popup_centered()
		for frame in 12:
			await process_frame
		var capture := "user://fragment-preview.png"
		root.get_texture().get_image().save_png(capture)
		print("CAPTURE ",ProjectSettings.globalize_path(capture))
	dialog.free()
	undo.clear_history()
	print("test_voxel_fragment: ","PASS" if errors == 0 else "FAIL", " · ",errors)
	quit(errors)
