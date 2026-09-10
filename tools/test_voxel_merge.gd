extends SceneTree
const Merge = preload("res://addons/ember_import/ember_voxel_merge.gd")
const Session = preload("res://addons/ember_import/ember_voxel_merge_session.gd")
const Dialog = preload("res://addons/ember_import/ember_voxel_merge_dialog.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Growth = preload("res://addons/ember_import/ember_voxel_canvas_growth.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
var errors := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)
func _init() -> void:
	_run.call_deferred()
func shape(id: String, density := 16) -> EmberVoxelModelResource:
	var source: EmberVoxelModelResource = Shapes.build("empty",Vector3i(density,4,density),density,Color.BROWN,id,id).source
	source.voxels[0] = 1
	return source
func _run() -> void:
	var a := shape("a")
	a.shine.resize(a.voxels.size())
	a.shine[0] = 70
	a.voxel_groups = [{"id":"board","name":"Board","indices":PackedInt32Array([0]),"locked":false}]
	var b := shape("b",32)
	b.palette[1] = Color.GREEN
	var inputs: Array[Dictionary] = [{"source":a,"frame":Transform3D.IDENTITY,"name":"A"},{"source":b,"frame":Transform3D.IDENTITY,"name":"B"}]
	var initial := a.to_definition()
	var result := Merge.plan(inputs)
	check(not result.has("error"),"merge plan")
	if result.has("error"):
		print(result)
		quit(1)
		return
	var source: EmberVoxelModelResource = result.source
	check(a.to_definition() == initial,"detached preview")
	check(source.voxels.size()-source.voxels.count(0) == 8,"16 to 32 preserves occupied volume")
	check(result.overlap.size() == 1 and source.palette[source.voxels[0]] == Color.BROWN,"primary wins overlap")
	check(source.validation_errors().is_empty(),"valid merged resource")
	check(source.shine[0] == 70 and source.shine[1] == 70 and source.voxel_groups[0].indices.size() == 8,"promoted channels and groups")
	check(Merge.separate(source).pieces.size() == 1,"fully overlapped part does not resurrect")
	var undo := UndoRedo.new()
	var actions := EmberVoxelSculptActions.new()
	actions.configure(undo)
	var baseline := source.to_definition()
	var before_live := source.voxels.duplicate()
	source.voxels[10] = 1
	check(actions.commit_applied_stroke(source,before_live,source.voxels,PackedInt32Array([10])),"live pointer-up")
	check(source.voxel_part_ids[10] == 0,"live Added assigned")
	undo.undo()
	check(source.to_definition() == baseline,"live Undo exact")
	check(actions.apply_stroke(source,{0:{"before":1,"after":0},10:{"before":0,"after":1}}),"erase and add")
	check(source.voxel_part_ids[0] == 0 and source.voxel_part_ids[10] == 0,"added ownership")
	actions.active_part = 2
	check(actions.apply_stroke(source,{11:{"before":0,"after":1}}),"selected part stroke")
	check(source.voxel_part_ids[11] == 2,"selected part assigned")
	var separated := Merge.separate(source)
	check(not separated.has("error") and separated.pieces.size() == 3,"current shape split with Added")
	var occupied := 0
	for item in separated.pieces:
		occupied += item.source.voxels.size()-item.source.voxels.count(0)
		check(item.source.validation_errors().is_empty() and item.source.merge_parts.is_empty(),"valid ordinary output")
	check(occupied == 9,"removed voxels not resurrected")
	undo.undo()
	undo.undo()
	check(source.to_definition() == baseline,"one stroke undo exact ownership")
	undo.redo()
	undo.redo()
	var moved := Fragment.plan(source,PackedInt32Array([11]),Vector3i(1,0,0),1,0,false)
	check(not moved.has("error") and actions.apply_fragment(source,moved),"move part voxel")
	check(source.voxel_part_ids[12] == 2 and source.voxel_part_ids[11] == 0,"ownership follows move")
	check(actions.grow_canvas(source,Vector3i(64,source.grid_size().y,64)).has("properties"),"grow merged canvas")
	check(source.validation_errors().is_empty(),"growth ownership grid matches")
	var cut := Merge.Extract.plan(source,PackedInt32Array([12+16+16*64]),true)
	check(not cut.has("error") and cut.piece.voxel_part_ids[0] == 2,"crop ownership")
	var cutter := preload("res://addons/ember_import/ember_voxel_object_split.gd").new()
	cutter.source = source
	var section: EmberVoxelModelResource = cutter._extract({"origin":Vector3i.ZERO,"size":Vector3i(32,source.grid_size().y,64)},"ownership_section")
	check(section.validation_errors().is_empty() and section.merge_parts == source.merge_parts and section.voxel_part_ids.count(2) == 1,"section split preserves ownership")
	var path := "user://merge_%d.tres" % Time.get_ticks_usec()
	check(ResourceSaver.save(source,path) == OK,"save parts")
	var reopened := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(reopened.to_definition().model == source.to_definition().model,"reopen preserves all parts")
	inputs[1].frame = Transform3D(Basis(Vector3.UP,PI/2),Vector3(1,0,1))
	check(not Merge.plan(inputs).has("error"),"quarter rotation")
	inputs[1].frame = Transform3D(Basis(Vector3.UP,0.1),Vector3.ZERO)
	check(Merge.plan(inputs).has("error"),"arbitrary rotation refused")
	check(Merge.plan(inputs,true).has("error"),"alignment does not round rotation")
	inputs[1].frame = Transform3D(Basis.IDENTITY,Vector3(0.01,0,0))
	check(Merge.plan(inputs).has("error"),"unaligned position refused")
	var snapped := Merge.plan(inputs,true)
	check(not snapped.has("error") and snapped.adjustments.size() == 1,"mixed density alignment")
	check(snapped.adjustments[0].delta_world.is_equal_approx(Vector3(-0.01,0,0)),"alignment uses high-density grid")
	inputs[1].frame = Transform3D.IDENTITY
	a.palette.resize(256)
	for i in range(1,256):
		a.palette[i] = Color(float(i)/256,0,0)
	check(Merge.plan(inputs).has("error"),"palette overflow refuses without approximation")
	await _scene_test()
	undo.clear_history()
	undo.free()
	if "--benchmark" in OS.get_cmdline_user_args():
		_benchmark()
	print("Voxel merge: ","PASS" if errors == 0 else "FAIL %d" % errors)
	quit(0 if errors == 0 else 1)

func _scene_test() -> void:
	var scene := Node3D.new()
	scene.name = "MergeTest"
	root.add_child(scene)
	var directory := "user://merge_scene_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var nodes: Array = []
	for i in 2:
		var source := shape("part_%d" % i)
		source.palette[1] = Color("b27a47") if i == 0 else Color("88643a")
		for y in 2:
			for z in 4:
				for x in 16:
					source.voxels[VoxMesher.cell_index(x,y,z,16,16)] = 1
		var packed := EmberVoxelPrefab.prepare_resource(source)
		var saved := Session.Store.install_prepared_asset(source,packed,directory.path_join(source.model_id+".tres"),directory.path_join(source.model_id+".tscn"))
		check(saved.ok,"fixture saved")
		var prop := EmberSceneAuthoring.make_model_instance(scene,saved.packed,source.model_id,Vector3.ZERO)
		prop.position.x = i*12
		EmberSceneAuthoring.attach_model_instance(scene,scene,prop)
		nodes.append(prop)
	var session := Session.new()
	session.source_directory = directory
	session.prefab_directory = directory
	check(session.prepare(nodes,scene),"scene merge prepare: " + session.error)
	if not session.error.is_empty():
		scene.free()
		return
	var stale := Session.new()
	stale.source_directory = directory
	stale.prefab_directory = directory
	check(stale.prepare(nodes,scene),"stale fixture")
	nodes[1].position.x += 1
	var failure_undo := UndoRedo.new()
	check(not stale.commit(failure_undo) and scene.get_child_count() == 2,"changed pose refuses atomically")
	nodes[1].position.x -= 1
	var failing := Session.new()
	failing.source_directory = directory
	failing.prefab_directory = directory
	check(failing.prepare(nodes,scene),"failure fixture")
	failing.prefab_directory = directory.path_join("part_0.tres")
	check(not failing.commit(failure_undo) and scene.get_child_count() == 2,"publication failure leaves all scene nodes")
	failure_undo.free()
	await _alignment_test(nodes,scene,directory)
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.source_directory = directory
	dialog.prefab_directory = directory
	var dialog_undo := UndoRedo.new()
	dialog.open_merge(nodes,scene,dialog_undo)
	check(not dialog.get_ok_button().disabled,"native dialog preview")
	await process_frame
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(0.4).timeout
		dialog.get_viewport().get_texture().get_image().save_png("user://voxel_merge.png")
	dialog.free()
	dialog_undo.free()
	var undo := UndoRedo.new()
	check(session.commit(undo),"scene merge commit: " + session.error)
	check(scene.get_child_count() == 1,"many to one")
	var merged: Node = scene.get_child(0)
	var mesh_pose: Transform3D = merged.get_node("Mesh").global_transform
	check(mesh_pose.is_equal_approx(session.frame),"world geometry unchanged")
	undo.undo()
	check(scene.get_child_count() == 2 and scene.get_child(0) == nodes[0],"undo originals restored")
	undo.redo()
	check(scene.get_child_count() == 1,"redo merge")
	var saved_scene := PackedScene.new()
	check(saved_scene.pack(scene) == OK,"pack merged scene")
	var scene_path := directory.path_join("scene.tscn")
	check(ResourceSaver.save(saved_scene,scene_path) == OK,"save merged scene")
	var loaded := load(scene_path).instantiate() as Node3D
	root.add_child(loaded)
	check(loaded.get_child(0).get_node("Mesh").global_transform.is_equal_approx(mesh_pose),"reopen scene keeps geometry frame")
	check(loaded.get_child(0).get_node("Collision/Shape").shape != null,"reopen collision")
	loaded.free()
	var original_path := directory.path_join(merged.model_id+".tres")
	var original_hash := FileAccess.get_sha256(original_path)
	var edit := Session.Edit.new()
	edit.source_directory = directory
	edit.prefab_directory = directory
	check(edit.open(merged,scene,undo),"open merged in Canvas")
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.open_object(edit)
	check(workspace._part_selector.item_count == 3,"Canvas part selector")
	var owners_before: PackedInt32Array = workspace._resource.voxel_part_ids.duplicate()
	workspace._resource.voxel_part_ids[0] = 2
	check(workspace.has_unsaved_changes(),"metadata dirty detection")
	workspace.discard_changes()
	check(not workspace.has_unsaved_changes() and workspace._resource.voxel_part_ids == owners_before,"discard restores membership")
	workspace._actions.active_part = 2
	var added := workspace._resource.voxels.size()-1
	check(workspace._actions.apply_stroke(workspace._resource,{0:{"after":0},added:{"after":1}}),"Canvas merged sculpt")
	check(workspace._save(),"Canvas merged save")
	check(FileAccess.get_sha256(original_path) == original_hash,"instance save leaves shared source unchanged")
	var saved_edit := Session.Edit.new()
	saved_edit.source_directory = directory
	saved_edit.prefab_directory = directory
	check(saved_edit.open(merged,scene,undo),"reopen edited merge")
	check(saved_edit.draft.voxels[0] == 0 and saved_edit.draft.voxel_part_ids[added] == 2,"saved edits and membership")
	workspace.free()
	var split := Session.new()
	split.source_directory = directory
	split.prefab_directory = directory
	check(split.prepare([merged],scene,true),"unmerge prepare: " + split.error)
	check(split.commit(undo),"unmerge commit: " + split.error)
	check(scene.get_child_count() == 2,"unmerge two current pieces")
	undo.undo()
	check(scene.get_child_count() == 1 and scene.get_child(0) == merged,"undo unmerge")
	undo.redo()
	check(scene.get_child_count() == 2,"redo unmerge")
	scene.free()
	undo.clear_history()
	undo.free()

func _alignment_test(nodes: Array, scene: Node3D, directory: String) -> void:
	var previous: Array = nodes.map(func(node): return node.transform)
	nodes[0].position = Vector3(228.79372,0,164)
	nodes[1].position = Vector3(228.53683,9.1354265,165.70525)
	var poses: Array = nodes.map(func(node): return node.transform)
	var undo := UndoRedo.new()
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.source_directory = directory
	dialog.prefab_directory = directory
	dialog.open_merge(nodes,scene,undo)
	check(dialog.get_ok_button().disabled,"fractional placement initially refused")
	dialog._align.button_pressed = true
	check(not dialog.get_ok_button().disabled,"explicit alignment enables merge")
	check(nodes[0].transform == poses[0] and nodes[1].transform == poses[1],"alignment preview leaves scene untouched")
	var aligned: RefCounted = dialog._session
	check(aligned.adjustments.size() == 1,"primary remains fixed")
	var delta: Vector3 = aligned.adjustments[0].delta_world
	check((nodes[1].position+delta).is_equal_approx(Vector3(228.79372,9,166)),"reported user placement snaps to nearest grid")
	check(dialog._preview.has_node("OriginalPosition_1"),"old position ghost")
	dialog._align.button_pressed = false
	check(dialog.get_ok_button().disabled and nodes[1].transform == poses[1],"cancel alignment leaves original pose")
	dialog._align.button_pressed = true
	for i in 3:
		await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(0.4).timeout
		dialog.get_viewport().get_texture().get_image().save_png("user://voxel_merge_alignment.png")
	aligned = dialog._session
	dialog.free()
	check(nodes[1].transform == poses[1],"dismiss dialog keeps fractional positions")
	check(aligned.commit(undo),"aligned merge commit: " + aligned.error)
	var merged: Node3D = scene.get_child(0)
	check(merged.get_node("Mesh").global_transform.is_equal_approx(aligned.frame),"commit uses aligned preview frame")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK,"pack aligned scene")
	var path := directory.path_join("aligned.tscn")
	check(ResourceSaver.save(packed,path) == OK,"save aligned scene")
	var reopened := load(path).instantiate() as Node3D
	root.add_child(reopened)
	check(reopened.get_child(0).get_node("Mesh").global_transform.is_equal_approx(aligned.frame),"reopen aligned geometry")
	reopened.free()
	undo.undo()
	check(scene.get_child_count() == 2 and nodes[0].transform == poses[0] and nodes[1].transform == poses[1],"one Undo restores both fractional positions")
	undo.redo()
	check(scene.get_child_count() == 1,"one Redo restores aligned merge")
	undo.undo()
	undo.clear_history()
	undo.free()
	for i in nodes.size():
		nodes[i].transform = previous[i]

func _benchmark() -> void:
	var a: EmberVoxelModelResource = Shapes.build("block",Vector3i(64,16,64),16,Color.BROWN,"bench_a","A").source
	var inputs: Array[Dictionary] = [{"source":a,"frame":Transform3D.IDENTITY},{"source":a,"frame":Transform3D(Basis.IDENTITY,Vector3(4,0,0))}]
	var started := Time.get_ticks_usec()
	var result := Merge.plan(inputs)
	print("Merge dense 131072 occupied cells ms: ",(Time.get_ticks_usec()-started)/1000.0)
	check(not result.has("error"),"dense benchmark merge")
	started = Time.get_ticks_usec()
	var split := Merge.separate(result.source)
	print("Unmerge dense 131072 occupied cells ms: ",(Time.get_ticks_usec()-started)/1000.0)
	check(not split.has("error") and split.pieces.size() == 2,"dense benchmark unmerge")
	started = Time.get_ticks_usec()
	var packed := EmberVoxelPrefab.prepare_resource(result.source)
	print("Dense merged mesh + collision ms: ",(Time.get_ticks_usec()-started)/1000.0)
	var directory := "user://merge_benchmark_%d" % Time.get_ticks_usec()
	started = Time.get_ticks_usec()
	var saved := Session.Store.install_prepared_asset(result.source,packed,directory.path_join("merge.tres"),directory.path_join("merge.tscn"))
	print("Dense merged asset publish ms: ",(Time.get_ticks_usec()-started)/1000.0)
	check(saved.ok,"dense benchmark publish")
