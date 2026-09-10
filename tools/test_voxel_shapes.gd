extends SceneTree
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
var errors: Array[String] = []

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func _run() -> void:
	check(Shapes.build("empty",Vector3i(128,32,128),16,Color.RED,"limit","").ok,"new exact budget rejected")
	check(not Shapes.build("empty",Vector3i(128,33,128),16,Color.RED,"limit","").ok,"new budget exceeded")
	var budget_dialog := preload("res://addons/ember_import/ember_voxel_shape_dialog.gd").new()
	root.add_child(budget_dialog)
	check(not budget_dialog._check_large_budget(Vector3i(192,10,256)),"large preview not gated")
	budget_dialog._large_ack.button_pressed = true
	check(budget_dialog._check_large_budget(Vector3i(192,10,256)),"large preview acknowledgement ignored")
	budget_dialog._invalidate()
	check(not budget_dialog._large_ack.button_pressed,"changed parameters kept acknowledgement")
	budget_dialog.free()
	for dimensions in [Vector3i(32,2,8),Vector3i(64,32,64)]:
		var timer := Time.get_ticks_usec()
		var measured := Creation.new()
		check(measured.prepare("block",dimensions,16,Color.RED,"Measured"), "timing prepare")
		print("SHAPE_PREPARE ",dimensions," ", snappedf((Time.get_ticks_usec()-timer)/1000.0,0.01)," ms")
	for density in [16, 32]:
		for diameter in [1, 2, 3, 7, 16, 17, 32]:
			for kind in ["block", "cylinder", "sphere"]:
				var report := Shapes.build(kind, Vector3i.ONE * diameter, density, Color.RED, "fixture", "fixture")
				check(report.ok, "generator refused valid dimensions")
				var source: EmberVoxelModelResource = report.source
				check(source.validation_errors().is_empty(), "invalid generated source")
				var minimum := Vector3i.ONE * 100000
				var maximum := Vector3i.ONE * -100000
				var grid := source.grid_size()
				for y in grid.y:
					for z in grid.z:
						for x in grid.x:
							if source.voxels[VoxMesher.cell_index(x,y,z,grid.x,grid.z)] > 0:
								minimum = minimum.min(Vector3i(x,y,z))
								maximum = maximum.max(Vector3i(x,y,z))
				check(maximum - minimum + Vector3i.ONE == Vector3i.ONE * diameter, "occupied dimensions drift " + kind + str(diameter))
	check(not Shapes.build("block", Vector3i(16,129,16),16,Color.RED,"bad","").ok, "height clamped")
	check(not Shapes.build("block", Vector3i(256,256,256),32,Color.RED,"bad","").ok, "cell budget bypass")
	var fixture := "user://ember-tests/shapes-%d" % Time.get_ticks_usec()
	var creation := Creation.new()
	creation.source_directory = fixture.path_join("sources")
	creation.prefab_directory = fixture.path_join("prefabs")
	creation.world_size = 24.0
	check(creation.prepare("empty",Vector3i(7,8,5),16,Color.RED,"Empty"), creation.error)
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(fixture)), "preview wrote files")
	var scene := Node3D.new()
	root.add_child(scene)
	scene.rotation.y = 0.4
	scene.position = Vector3(10,0,20)
	var undo := UndoRedo.new()
	var prop: EmberVoxelProp = creation.commit(scene,scene,undo,Vector3(3,4,5))
	check(prop != null and not prop.placement_id.is_empty(), "creation failed")
	check(prop.get_node("Collision/Shape").shape == null, "empty phantom collision")
	check(prop.block_world_size == 24.0 and prop.global_position.is_equal_approx(scene.to_global(Vector3(3,4,5))), "non-default scale/parent transform")
	var placement := prop.placement_id
	undo.undo()
	check(prop.get_parent() == null, "creation Undo")
	undo.redo()
	check(prop.get_parent() == scene and prop.placement_id == placement, "creation Redo")
	var child := Node3D.new()
	scene.set_editable_instance(prop, true)
	child.name = "AuthoredSocket"
	prop.get_node("Collision/Shape").add_child(child)
	child.owner = scene
	var edit := Session.new()
	edit.source_directory = creation.source_directory
	edit.prefab_directory = creation.prefab_directory
	check(edit.open(prop,scene,undo), "empty open " + edit.error)
	var canvas := Workspace.new()
	canvas.setup(null,undo)
	root.add_child(canvas)
	canvas.open_object(edit)
	for frame in 10:
		await process_frame
	var point: Vector2 = canvas._camera.unproject_position(Vector3(0.25,0,0.25)) * canvas._viewport_container.size / Vector2(canvas._viewport.size)
	check(canvas._pick_at(point).get("empty_floor",false), "empty Canvas ray has no floor target")
	canvas._begin_stroke(point)
	canvas._finish_stroke()
	check(edit.draft.voxels.count(1) > 0, "actual Canvas stroke added no voxel")
	check(canvas.save_changes(), "first voxel Canvas save " + edit.error)
	check(prop.get_node("Collision/Shape").shape != null and not prop.get_node("Collision/Shape").disabled, "first voxel collision inactive")
	edit.draft.voxels.fill(0)
	check(edit.save(edit.draft).ok, "erase all save " + edit.error)
	check(prop.get_node("Collision/Shape").shape == null, "empty retained collision")
	check(prop.get_node("Collision/Shape/AuthoredSocket") == child, "authored child lost")
	undo.undo()
	check(prop.get_node("Collision/Shape").shape != null, "empty Undo did not restore solid")
	undo.redo()
	check(prop.get_node("Collision/Shape").shape == null, "empty Redo resurrected collider")
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK, "scene pack")
	var scene_path := fixture.path_join("scene.tscn")
	check(ResourceSaver.save(packed,scene_path) == OK, "scene save")
	var reopened := (ResourceLoader.load(scene_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var restored: EmberVoxelProp = reopened.get_child(0)
	check(restored.get_node("Collision/Shape").shape == null, "reopen collider resurrected")
	check(restored.get_node_or_null("Collision/Shape/AuthoredSocket") != null, "reopen child lost")
	reopened.free()
	canvas.free()
	var linked := EmberSceneAuthoring.make_duplicate(scene,prop,Vector3(20,0,0))
	EmberSceneAuthoring.attach_duplicate(scene,prop,scene,linked)
	var shared := Session.new()
	shared.source_directory = creation.source_directory
	shared.prefab_directory = creation.prefab_directory
	check(shared.open(prop,scene,undo,true), "shared empty open")
	shared.draft.voxels[0] = 1
	check(shared.save(shared.draft).ok, "shared empty to solid")
	check(linked.get_node("Collision/Shape").shape != null, "shared linked collider not created")
	shared.draft.voxels.fill(0)
	check(shared.save(shared.draft).ok, "shared solid to empty")
	check(linked.get_node("Collision/Shape").shape == null, "shared linked collider not cleared")
	var failed := Creation.new()
	failed.source_directory = creation.source_directory
	failed.prefab_directory = creation.source_directory.path_join(creation.source.model_id + ".tres")
	check(failed.prepare("block",Vector3i(2,3,4),16,Color.RED,"Fail"), "failure fixture prepare")
	var failure_source := failed.source_directory.path_join(failed.source.model_id + ".tres")
	check(failed.commit(scene,scene,undo,Vector3.ZERO) == null, "bad destination committed")
	check(not FileAccess.file_exists(failure_source), "failed creation published source")
	undo.clear_history()
	undo.free()
	scene.free()
	for error in errors:
		push_error(error)
	print("test_voxel_shapes: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size(), " errors")
	quit(0 if errors.is_empty() else 1)
