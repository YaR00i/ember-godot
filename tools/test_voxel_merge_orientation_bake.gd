extends SceneTree
const Merge = preload("res://addons/ember_import/ember_voxel_merge.gd")
const Session = preload("res://addons/ember_import/ember_voxel_merge_session.gd")
const Dialog = preload("res://addons/ember_import/ember_voxel_merge_dialog.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
var errors := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)

func _init() -> void:
	_run.call_deferred()

func _key(source: EmberVoxelModelResource, frame: Transform3D, index: int) -> Vector3i:
	var cell := Merge.Selection.cell_of(index,source.grid_size())
	return Vector3i((frame*((Vector3(cell)+Vector3.ONE*0.5)/source.normalized_density())*4096.0).round())

func _cells(source: EmberVoxelModelResource, frame: Transform3D) -> Dictionary:
	var result := {}
	for i in source.voxels.size():
		if source.voxels[i] == 0:
			continue
		var attributes: Array = [source.palette[source.voxels[i]],source.voxel_part_ids[i]]
		for channel in Merge.Fragment.CHANNELS:
			if channel == "voxels":
				continue
			var values: PackedByteArray = source.get(channel)
			attributes.append(values[i] if not values.is_empty() else -1)
		result[_key(source,frame,i)] = attributes
	return result

func _groups(source: EmberVoxelModelResource, frame: Transform3D) -> Array:
	var result: Array = []
	for group in source.voxel_groups:
		var copy: Dictionary = group.duplicate(true)
		var points: Array[String] = []
		for i in group.indices:
			points.append(str(_key(source,frame,i)))
		points.sort()
		copy.erase("indices")
		copy.points = points
		result.append(copy)
	return result

func _overlap(plan: Dictionary) -> Dictionary:
	var result := {}
	for i in plan.overlap:
		result[_key(plan.source,plan.frame,i)] = true
	return result

func _run() -> void:
	var a: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,4,16),16,Color.BROWN,"bake_a","A").source
	a.palette.append(Color.GREEN)
	a.voxels[0] = 1
	a.voxels[17] = 2
	a.voxels[256] = 1
	for channel in Merge.Fragment.CHANNELS:
		if channel == "voxels":
			continue
		var values := PackedByteArray()
		values.resize(a.voxels.size())
		values[0] = 1 if channel == "collision_voxels" else 40
		values[17] = 1 if channel == "collision_voxels" else 70
		values[256] = 1 if channel == "collision_voxels" else 100
		a.set(channel,values)
	a.voxel_groups = [{"id":"paint","name":"Pattern","locked":true,"color":Color.ORANGE,"indices":PackedInt32Array([0,17,256])}]
	var b: EmberVoxelModelResource = Shapes.build("empty",Vector3i(32,4,32),32,Color.BLUE,"bake_b","B").source
	b.voxels[0] = 1
	b.voxels[67] = 1
	var originals := [a.to_definition(),b.to_definition()]
	var axes := [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]
	var count := 0
	for x in axes:
		for y in axes:
			if absf(x.dot(y)) > 0.1:
				continue
			var rotation := Basis(x,y,x.cross(y))
			var base := Transform3D(rotation.scaled(Vector3.ONE*24),Vector3(123,45,-67))
			var inputs: Array[Dictionary] = [{"source":a,"frame":base},{"source":b,"frame":base}]
			var ordinary := Merge.plan(inputs)
			var baked := Merge.plan(inputs,false,true)
			check(not ordinary.has("error") and not baked.has("error"),"orthogonal bake %d" % count)
			if ordinary.has("error") or baked.has("error"):
				continue
			check(baked.source.validation_errors().is_empty(),"valid baked resource")
			check(baked.frame.basis.is_equal_approx(Basis.IDENTITY.scaled(Vector3.ONE*24)),"scene-aligned output frame")
			check(_cells(ordinary.source,ordinary.frame) == _cells(baked.source,baked.frame),"world occupancy/color/six channels/parts unchanged")
			check(_groups(ordinary.source,ordinary.frame) == _groups(baked.source,baked.frame),"group members and metadata unchanged")
			check(_overlap(ordinary) == _overlap(baked),"overlap world positions unchanged")
			check(ordinary.source.merge_parts == baked.source.merge_parts,"part library unchanged")
			inputs[1].frame = base*Transform3D(Basis(Vector3.UP,PI/2.0),Vector3(0.01,0.2,0.05))
			ordinary = Merge.plan(inputs,true)
			baked = Merge.plan(inputs,true,true)
			check(not ordinary.has("error") and not baked.has("error"),"rotated secondary + alignment bake")
			if not ordinary.has("error") and not baked.has("error"):
				check(ordinary.adjustments == baked.adjustments,"alignment reports primary-grid axes and identical world delta")
				check(_cells(ordinary.source,ordinary.frame) == _cells(baked.source,baked.frame),"aligned bake matches ordinary world geometry")
			count += 1
	check(count == 24,"all24 proper orthogonal rotations")
	check(a.to_definition() == originals[0] and b.to_definition() == originals[1],"bake never mutates source drafts")
	var bad_inputs: Array[Dictionary] = [{"source":a,"frame":Transform3D.IDENTITY},{"source":b,"frame":Transform3D.IDENTITY}]
	for basis in [Basis(Vector3.UP,0.1),Basis.IDENTITY.scaled(Vector3(2,3,2)),Basis.IDENTITY.scaled(Vector3(-2,2,2)),Basis(Vector3(1,0,0),Vector3(0.1,1,0),Vector3(0,0,1))]:
		for input in bad_inputs:
			input.frame = Transform3D(basis,Vector3.ZERO)
		check(not Merge.plan(bad_inputs).has("error"),"ordinary merge still supports common frame")
		check(Merge.plan(bad_inputs,false,true).has("error"),"unsupported bake rejected without rounding")
	var tall: EmberVoxelModelResource = Shapes.build("empty",Vector3i(144,4,16),16,Color.BROWN,"tall_bake","Tall").source
	tall.voxels[0] = 1
	var turned := Transform3D(Basis(Vector3.FORWARD,PI/2.0),Vector3.ZERO)
	var large: Array[Dictionary] = [{"source":tall,"frame":turned},{"source":tall,"frame":turned}]
	check(not Merge.plan(large).has("error") and Merge.plan(large,false,true).has("error"),"baked height limits checked before publication")
	await _scene_test()
	print("test_voxel_merge_orientation_bake: ","PASS" if errors == 0 else "FAIL"," · ",errors," · rotations=",count)
	quit(errors)

func _scene_test() -> void:
	root.size = Vector2i(1200,850)
	var scene := Node3D.new()
	scene.name = "BakedBridgeFixture"
	root.add_child(scene)
	scene.transform = Transform3D(Basis(Vector3.UP,PI/2.0).scaled(Vector3.ONE*1.5),Vector3(150,10,-90))
	var directory := "user://merge_bake_%d" % Time.get_ticks_usec()
	var nodes: Array = []
	var hashes: Array[String] = []
	for i in 3:
		var source: EmberVoxelModelResource = Shapes.build("block",Vector3i(8,64,4),16,Color.BROWN,"board_%d" % i,"Board %d" % i).source
		var packed := EmberVoxelPrefab.prepare_resource(source)
		var path := directory.path_join(source.model_id+".tres")
		var installed := Session.Store.install_prepared_asset(source,packed,path,directory.path_join(source.model_id+".tscn"))
		check(installed.ok,"board fixture publication")
		hashes.append(FileAccess.get_sha256(path))
		var prop := EmberSceneAuthoring.make_model_instance(scene,installed.packed,source.model_id,Vector3.ZERO)
		prop.transform = Transform3D(Basis(Vector3.RIGHT,PI/2.0),Vector3(i*8.0+(0.1 if i > 0 else 0.0),0,0))
		EmberSceneAuthoring.attach_model_instance(scene,scene,prop)
		nodes.append(prop)
	var poses: Array = nodes.map(func(node): return node.transform)
	var undo := UndoRedo.new()
	var dialog := Dialog.new()
	root.add_child(dialog)
	dialog.source_directory = directory
	dialog.prefab_directory = directory
	dialog.open_merge(nodes,scene,undo)
	check(not dialog._bake_orientation.button_pressed,"bake opt-in default")
	dialog._align.button_pressed = true
	var ordinary: RefCounted = dialog._session
	var expected := _cells(ordinary.preview,ordinary.frame)
	var scene_pose := scene.transform
	scene.rotate_y(0.1)
	dialog._bake_orientation.button_pressed = true
	check(dialog.get_ok_button().disabled and not undo.has_undo(),"unsupported toggle refuses without Undo")
	check(nodes.map(func(node): return node.transform) == poses,"unsupported toggle leaves originals untouched")
	check(not dialog._session.commit(undo) and scene.get_child_count() == 3 and not undo.has_undo(),"rejected bake cannot commit through API")
	dialog._bake_orientation.button_pressed = false
	check(not dialog.get_ok_button().disabled,"disable bake recovers ordinary merge")
	scene.transform = scene_pose
	dialog._bake_orientation.button_pressed = true
	check(not dialog.get_ok_button().disabled and dialog._session.orientation_baked,"toggle builds baked preview")
	var baked: RefCounted = dialog._session
	check(baked.preview.height_voxels == 16 and baked.preview.grid_size().z == 32,"bridge grid baked flat with preserved padding")
	check(_cells(baked.preview,baked.frame) == expected,"toggle preserves world cells")
	dialog._scene_orientation.button_pressed = false
	check(dialog._preview.get_node("Mesh").global_basis.is_equal_approx(Basis.IDENTITY),"baked local preview is scene aligned")
	dialog._bake_orientation.button_pressed = false
	check(not dialog._session.orientation_baked and _cells(dialog._session.preview,dialog._session.frame) == expected,"toggle off restores ordinary plan")
	dialog._bake_orientation.button_pressed = true
	check(not undo.has_undo() and nodes.map(func(node): return node.transform) == poses,"preview creates no Undo or scene mutation")
	for i in 4: await process_frame
	var scroll := dialog._preview_container.get_parent().get_parent() as ScrollContainer
	check(scroll.get_global_rect().encloses(dialog._preview_container.get_global_rect()),"bake toggle leaves full preview visible")
	baked = dialog._session
	dialog.free()
	check(baked.commit(undo),"commit baked bridge")
	check(scene.get_child_count() == 1,"single merged bridge")
	var merged: EmberVoxelProp = scene.get_child(0)
	var mesh: MeshInstance3D = merged.get_node("Mesh")
	check(mesh.global_transform.is_equal_approx(baked.frame),"baked commit uses exact preview frame")
	var stored := load(directory.path_join(merged.model_id+".tres")) as EmberVoxelModelResource
	check(_cells(stored,mesh.global_transform) == expected,"published bridge unchanged in world")
	var edit := Session.Edit.new()
	edit.source_directory = directory
	edit.prefab_directory = directory
	check(edit.open(merged,scene,undo),"open baked bridge in Canvas")
	var canvas := Workspace.new()
	canvas.setup(null,undo)
	root.add_child(canvas)
	canvas.open_object(edit)
	for i in 6: await process_frame
	check(canvas._resource.height_voxels == 16 and canvas._resource.grid_size().x == 64,"Canvas opens canonical flat bridge")
	var first := stored.voxels.find(1)
	var cell := Merge.Selection.cell_of(first,stored.grid_size())
	var ray_origin := (Vector3(cell)+Vector3(0.5,0.5,0.5))/stored.normalized_density()+Vector3.UP*8
	var pick := Merge.Fragment.Model.pick(canvas._resource,ray_origin,Vector3.DOWN)
	check(not pick.is_empty(),"Canvas top ray hits baked bridge")
	check(not canvas.has_unsaved_changes(),"baked Canvas opens clean")
	var before_stroke: Dictionary = canvas._resource.to_definition()
	check(canvas._actions.apply_stroke(canvas._resource,{first:{"after":0}}),"sculpt baked Canvas")
	undo.undo()
	check(canvas._resource.to_definition() == before_stroke and not canvas.has_unsaved_changes(),"Undo baked Canvas stroke restores all data")
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(0.4).timeout
		root.get_texture().get_image().save_png("user://merge-baked-canvas.png")
	canvas.free()
	for i in nodes.size():
		check(FileAccess.get_sha256(directory.path_join("board_%d.tres" % i)) == hashes[i],"original board file unchanged")
	undo.undo()
	check(scene.get_child_count() == 3 and nodes.map(func(node): return node.transform) == poses,"one Undo restores all original poses")
	undo.redo()
	check(scene.get_child_count() == 1 and scene.get_child(0).get_node("Mesh").global_transform.is_equal_approx(baked.frame),"one Redo restores baked frame")
	var packed_scene := PackedScene.new()
	check(packed_scene.pack(scene) == OK,"pack baked scene")
	var scene_path := directory.path_join("baked_scene.tscn")
	check(ResourceSaver.save(packed_scene,scene_path) == OK,"save baked scene")
	var reopened := load(scene_path).instantiate() as Node3D
	root.add_child(reopened)
	check(_cells(stored,reopened.get_child(0).get_node("Mesh").global_transform) == expected,"save/reopen world geometry")
	var split := Session.new()
	split.source_directory = directory
	split.prefab_directory = directory
	check(split.prepare([merged],scene,true) and split.commit(undo),"unmerge baked bridge")
	check(scene.get_child_count() == 3,"baked part membership separates")
	undo.undo()
	check(scene.get_child_count() == 1,"Undo baked unmerge")
	reopened.free()
	scene.free()
	undo.clear_history()
	undo.free()
