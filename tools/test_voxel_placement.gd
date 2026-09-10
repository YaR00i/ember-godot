extends SceneTree

const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
const Placement = preload("res://addons/ember_import/ember_voxel_placement_session.gd")
const Math = preload("res://addons/ember_import/ember_voxel_placement_math.gd")
var errors: Array[String] = []
var folder := ""


func _init() -> void:
	_run.call_deferred()


func check(value: bool,message: String) -> void:
	if not value:
		errors.append(message)


func make_prop(scene: Node,parent: Node3D,name: String,position: Vector3) -> EmberVoxelProp:
	var creation := Creation.new()
	creation.source_directory = folder.path_join("sources")
	creation.prefab_directory = folder.path_join("prefabs")
	creation.world_size = 16.0
	check(creation.prepare("block",Vector3i(12,3,5),16,Color("a86f45"),name),"prepare "+name+": "+creation.error)
	var creation_undo := UndoRedo.new()
	var prop := creation.commit(scene,parent,creation_undo,position)
	creation_undo.clear_history()
	creation_undo.free()
	if prop != null:
		prop.name = name
	return prop


func placement_for(target: Node3D,scene: Node,undo: Object) -> RefCounted:
	var edit := Placement.new()
	edit.source_directory = folder.path_join("sources")
	check(edit.open(target,scene,undo),"open "+target.name+": "+edit.error)
	return edit


func _run() -> void:
	folder = "user://ember-tests/placement-%d" % Time.get_ticks_usec()
	var scene := Node3D.new()
	root.add_child(scene)
	var parent := Node3D.new()
	parent.name = "ScaledParent"
	parent.transform = Transform3D(Basis(Vector3.UP,0.42).scaled(Vector3(1.6,0.75,1.25)),Vector3(21,4,-13))
	scene.add_child(parent)
	parent.owner = scene
	var prop := make_prop(scene,parent,"Plank",Vector3(3.2,1.1,-2.4))
	check(prop != null,"single prop creation")
	if prop == null:
		_finish(scene)
		return
	prop.transform.basis = Basis(Vector3(0.3,1,0.2).normalized(),0.31).scaled(Vector3(1.15,0.9,1.35))
	var source_path := folder.path_join("sources").path_join(prop.model_id+".tres")
	var source_hash := FileAccess.get_sha256(source_path)
	var undo := UndoRedo.new()
	var edit := placement_for(prop,scene,undo)
	check(edit.grids.size() >= 2,"actual fitted voxel grid option missing")
	check(edit.grid_steps(0) == Vector3.ONE,"fixed common world grid missing")
	var actual: Vector3 = edit.grid_steps(1)
	var mesh := prop.get_node("Mesh") as MeshInstance3D
	var source := ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	var expected_steps := Vector3(mesh.global_basis.x.length(),mesh.global_basis.y.length(),mesh.global_basis.z.length())/source.normalized_density()
	check(actual.is_equal_approx(expected_steps),"displayed actual voxel lengths are nominal rather than transformed")
	var initial := prop.global_transform
	var collision := prop.get_node("Collision") as Node3D
	var collision_relative := initial.affine_inverse()*collision.global_transform
	var pivot: Vector3 = edit.pivot_local(1,Vector3.ZERO,0)
	var initial_pivot := initial*pivot
	var desired := initial_pivot+Vector3(3.25,-1.5,2.75)
	var desired_coordinates: Vector3 = edit.coordinate_for_world(desired,0)
	var rotation := Vector3(13,27,-8)
	var report: Dictionary = edit.plan(pivot,desired_coordinates,rotation,0)
	check(report.ok,"single preview")
	check(prop.global_transform.is_equal_approx(initial),"preview mutated live object")
	check((report.world*pivot).is_equal_approx(desired),"preview pivot missed numeric coordinate")
	check(report.world.basis.is_equal_approx(Math.rotation_delta(rotation)*initial.basis),"preview decomposed or changed authored basis")
	var original_determinant := absf(initial.basis.determinant())
	check(is_equal_approx(absf(report.world.basis.determinant()),original_determinant),"rotation changed scale determinant")
	check(edit.commit(),edit.error)
	check(prop.global_transform.is_equal_approx(report.world),"commit differs from preview")
	check((prop.global_transform.affine_inverse()*collision.global_transform).is_equal_approx(collision_relative),"collision did not follow selected root")
	check(FileAccess.get_sha256(source_path) == source_hash,"placement wrote voxel source")
	undo.undo()
	check(prop.global_transform.is_equal_approx(initial),"single Undo")
	undo.redo()
	check(prop.global_transform.is_equal_approx(report.world),"single Redo")

	# Changing the pivot after a non-zero rotation must preserve the already
	# previewed transform. The desired coordinate follows the new local pivot.
	var pivot_edit := placement_for(prop,scene,null)
	var center: Vector3 = pivot_edit.pivot_local(0,Vector3.ZERO,0)
	var rotated: Dictionary = pivot_edit.plan(center,pivot_edit.coordinate_for_world(prop.global_transform*center,0),Vector3(0,19,0),0)
	var lower: Vector3 = pivot_edit.pivot_local(1,Vector3.ZERO,0)
	var preserved: Dictionary = pivot_edit.plan(lower,pivot_edit.coordinate_for_world(rotated.world*lower,0),Vector3(0,19,0),0)
	check(preserved.world.is_equal_approx(rotated.world),"pivot switch moved non-zero rotation preview")
	var snapped_coordinates := Math.snap_vox(pivot_edit.coordinate_for_world(rotated.world*lower,0),2.0)
	var snapped: Dictionary = pivot_edit.plan(lower,snapped_coordinates,Vector3(0,19,0),0)
	check(pivot_edit.coordinate_for_world(snapped.world*lower,0).is_equal_approx(snapped_coordinates),"snap did not align agreed world pivot")
	var custom: Vector3 = pivot_edit.pivot_local(2,Vector3(12,3,5),1)
	check(custom.is_equal_approx((prop.get_node("Mesh") as Node3D).transform*Vector3(12.0/16.0,3.0/16.0,5.0/16.0)),"single custom pivot is not source voxel coordinates")
	var discarded_before := prop.transform
	pivot_edit.plan(lower,pivot_edit.coordinate_for_world(snapped.world*lower,0),Vector3(4,5,6),0)
	check(prop.transform.is_equal_approx(discarded_before),"discarded preview changed scene")

	# Existing groups move as one root, including nested containers and all
	# generated collision children. Differing child positions remain authored.
	var group := Node3D.new()
	group.name = "BridgeAssembly"
	parent.add_child(group)
	group.owner = scene
	group.transform = Transform3D(Basis(Vector3.RIGHT,0.08),Vector3(-5,2,9))
	var inner := Node3D.new()
	inner.name = "Parts"
	inner.position = Vector3(0.3,0,-0.2)
	group.add_child(inner)
	inner.owner = scene
	var a := make_prop(scene,inner,"BoardA",Vector3(-7,0,0))
	var b := make_prop(scene,inner,"BoardB",Vector3(7,0.4,1.2))
	b.rotation_degrees = Vector3(2,6,-1)
	var a_local := a.transform
	var b_local := b.transform
	var group_initial := group.global_transform
	var group_undo := UndoRedo.new()
	var group_edit := placement_for(group,scene,group_undo)
	var group_pivot: Vector3 = group_edit.pivot_local(1,Vector3.ZERO,0)
	var group_destination: Vector3 = group_edit.coordinate_for_world(group_initial*group_pivot+Vector3(6,-2,4),0)
	var group_report: Dictionary = group_edit.plan(group_pivot,group_destination,Vector3(0,11,3),0)
	check(group.global_transform.is_equal_approx(group_initial),"group preview mutated scene")
	check(group_edit.commit(),group_edit.error)
	check(group.global_transform.is_equal_approx(group_report.world),"group commit differs from preview")
	check(a.transform.is_equal_approx(a_local) and b.transform.is_equal_approx(b_local),"group move changed member placement")
	group_undo.undo()
	check(group.global_transform.is_equal_approx(group_initial),"group Undo")
	group_undo.redo()
	check(group.global_transform.is_equal_approx(group_report.world),"group Redo")

	# Save/reopen persists only the root transform; sources remain byte-identical.
	var source_hash_a := FileAccess.get_sha256(folder.path_join("sources").path_join(a.model_id+".tres"))
	var source_hash_b := FileAccess.get_sha256(folder.path_join("sources").path_join(b.model_id+".tres"))
	var packed := PackedScene.new()
	check(packed.pack(scene) == OK,"scene pack")
	var scene_path := folder.path_join("placement_scene.tscn")
	check(ResourceSaver.save(packed,scene_path) == OK,"scene save")
	var reopened_packed := ResourceLoader.load(scene_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reopened := reopened_packed.instantiate() as Node3D
	check((reopened.get_node("ScaledParent/BridgeAssembly") as Node3D).transform.is_equal_approx(group.transform),"save/reopen placement")
	check(FileAccess.get_sha256(folder.path_join("sources").path_join(a.model_id+".tres")) == source_hash_a and FileAccess.get_sha256(folder.path_join("sources").path_join(b.model_id+".tres")) == source_hash_b,"group placement wrote sources")
	reopened.free()

	# Preview plans are rejected when a transformed ancestor, intermediate
	# container, source, or subtree composition becomes stale.
	var stale := placement_for(group,scene,null)
	var stale_pivot: Vector3 = stale.pivot_local(0,Vector3.ZERO,0)
	stale.plan(stale_pivot,stale.coordinate_for_world(group.global_transform*stale_pivot+Vector3.ONE,0),Vector3.ZERO,0)
	inner.position.x += 1
	check(not stale.commit(),"stale intermediate transform committed")
	inner.position.x -= 1
	var stale_parent := placement_for(group,scene,null)
	stale_pivot = stale_parent.pivot_local(0,Vector3.ZERO,0)
	stale_parent.plan(stale_pivot,stale_parent.coordinate_for_world(group.global_transform*stale_pivot+Vector3.ONE,0),Vector3.ZERO,0)
	parent.position.y += 1
	check(not stale_parent.commit(),"stale transformed parent committed")
	parent.position.y -= 1
	var top_level := Placement.new()
	top_level.source_directory = folder.path_join("sources")
	inner.set_as_top_level(true)
	check(not top_level.open(group,scene,null),"top-level descendant accepted")
	inner.set_as_top_level(false)
	var invalid := placement_for(group,scene,null)
	var invalid_pivot: Vector3 = invalid.pivot_local(0,Vector3.ZERO,0)
	invalid.plan(invalid_pivot,invalid.coordinate_for_world(group.global_transform*invalid_pivot+Vector3.ONE,0),Vector3.ZERO,0)
	check(not invalid.plan(Vector3.INF,Vector3.ZERO,Vector3.ZERO,0).ok,"non-finite plan accepted")
	check(not invalid.commit(),"previous valid plan remained commit-able after invalid preview")

	undo.clear_history()
	group_undo.clear_history()
	undo.free()
	group_undo.free()
	_finish(scene)


func _finish(scene: Node) -> void:
	for message in errors:
		push_error(message)
	print("test_voxel_placement: ","PASS" if errors.is_empty() else "FAIL"," · ",errors.size()," errors")
	scene.free()
	quit(0 if errors.is_empty() else 1)
