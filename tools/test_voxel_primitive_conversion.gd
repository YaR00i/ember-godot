extends SceneTree
const Conversion = preload("res://addons/ember_import/ember_voxel_primitive_conversion.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Dialog = preload("res://addons/ember_import/ember_voxel_conversion_dialog.gd")
var errors: Array[String] = []
func _init() -> void:
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)
func _run() -> void:
	for kind in ["block","cylinder","sphere","pier"]:
		for physical in [true,false]:
			var scene := Node3D.new()
			root.add_child(scene)
			scene.rotation.y = 0.6
			scene.position = Vector3(40,7,20)
			var parent: Node3D = StaticBody3D.new() if physical else Node3D.new()
			scene.add_child(parent)
			parent.name = "Container"
			parent.owner = scene
			parent.scale = Vector3(1.2,0.8,1.1)
			var visual := MeshInstance3D.new()
			visual.name = "Visual"
			var collider := CollisionShape3D.new()
			collider.name = "Collision"
			var dimensions := Vector3i(18,3,7)
			if kind in ["block","pier"]:
				var mesh := BoxMesh.new()
				mesh.size = Vector3(17.5,2.4,7.3)
				if kind == "pier":
					dimensions = Vector3i(192,10,256)
					mesh.size = Vector3(dimensions)
				visual.mesh = mesh
				var shape := BoxShape3D.new()
				shape.size = mesh.size
				collider.shape = shape
			elif kind == "cylinder":
				var mesh := CylinderMesh.new()
				mesh.top_radius = 8.5
				mesh.bottom_radius = 8.5
				mesh.height = 5.4
				visual.mesh = mesh
				var shape := CylinderShape3D.new()
				shape.radius = 8.5
				shape.height = 5.4
				collider.shape = shape
				dimensions = Vector3i(17,5,17)
			else:
				var mesh := SphereMesh.new()
				mesh.radius = 8.5
				mesh.height = 17
				visual.mesh = mesh
				var shape := SphereShape3D.new()
				shape.radius = 8.5
				collider.shape = shape
				dimensions = Vector3i.ONE * 17
			parent.add_child(visual)
			visual.owner = scene
			visual.rotation = Vector3(0.1,0.7,0.2)
			visual.position = Vector3(6,4,2)
			if physical:
				parent.add_child(collider)
				collider.owner = scene
				collider.transform = visual.transform
				parent.collision_layer = 4
				parent.collision_mask = 3
				var alignment_undo := UndoRedo.new()
				collider.position += Vector3(0.01,0,0.04)
				var old_collision := collider.transform
				var old_visual := visual.transform
				check(Conversion.inspect(parent,scene).get("alignable",false), "alignment offer absent")
				check(Conversion.align_collision(parent,scene,alignment_undo), "alignment failed")
				check(collider.transform == old_visual and visual.transform == old_visual, "alignment moved visual")
				check(not Conversion.inspect(parent,scene).has("error"), "aligned form rejected")
				alignment_undo.undo()
				check(collider.transform == old_collision, "alignment Undo")
				alignment_undo.redo()
				check(collider.transform == old_visual, "alignment Redo")
				collider.disabled = true
				check(not Conversion.align_collision(parent,scene,alignment_undo), "disabled collision aligned")
				collider.disabled = false
				alignment_undo.free()
			else:
				collider.free()
			var original_world := visual.global_transform
			# Primitive properties describe ideal bounds; SphereMesh tessellation
			# may miss the exact equator by a fraction of a percent.
			var ideal_size: Vector3 = Conversion.inspect(visual,scene).extent
			var original_bounds := visual.global_transform * AABB(-ideal_size * 0.5,ideal_size)
			var converter := Conversion.new()
			var fixture := "user://ember-tests/conversion-%d" % Time.get_ticks_usec()
			converter.source_directory = fixture.path_join("sources")
			converter.prefab_directory = fixture.path_join("prefabs")
			check(converter.prepare(visual,scene,dimensions,16,Color.RED,"Converted"),"prepare " + converter.error)
			check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(fixture)),"preview wrote files")
			var undo := UndoRedo.new()
			var prop := converter.commit(undo)
			check(prop != null,"commit " + converter.error)
			if prop != null:
				var result_mesh := prop.get_node("Mesh") as MeshInstance3D
				var result_bounds := result_mesh.global_transform * result_mesh.get_aabb()
				check(original_bounds.position.is_equal_approx(result_bounds.position) and original_bounds.size.is_equal_approx(result_bounds.size),"bounds changed " + kind)
				check(prop.name == &"Visual" and prop.owner == scene and prop.get_parent() == parent,"owner/name lost")
				check(prop.has_node("Collision/Shape") == physical,"physical flag changed")
				if physical:
					check(collider.get_parent() == null and prop.get_node("Collision").collision_layer == 4,"old collision retained or layer lost")
				var edit := Session.new()
				edit.source_directory = converter.source_directory
				edit.prefab_directory = converter.prefab_directory
				check(edit.open(prop,scene,undo),"Canvas reopen " + edit.error)
				if kind == "pier" and physical:
					edit.draft.voxels[0] = 0
					check(edit.save(edit.draft).ok,"large edited save")
					var reopened_edit := Session.new()
					reopened_edit.source_directory = converter.source_directory
					reopened_edit.prefab_directory = converter.prefab_directory
					check(reopened_edit.open(prop,scene,undo) and reopened_edit.draft.voxels[0] == 0,"large edit reopen " + reopened_edit.error)
					undo.undo()
				undo.undo()
				check(visual.get_parent() == parent and visual.owner == scene and visual.global_transform.is_equal_approx(original_world),"Undo source pose")
				check(not physical or (collider.get_parent() == parent and collider.owner == scene),"Undo collider")
				undo.redo()
				check(prop.get_parent() == parent and visual.get_parent() == null,"Redo")
				var saved := PackedScene.new()
				check(saved.pack(scene) == OK,"pack result")
				check(ResourceSaver.save(saved,fixture.path_join("scene.tscn")) == OK,"save scene")
				var reopened := (ResourceLoader.load(fixture.path_join("scene.tscn"),"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
				check(reopened.get_node("Container/Visual") is EmberVoxelProp,"scene reopen")
				reopened.free()
			undo.clear_history()
			undo.free()
			scene.free()
	var scene := Node3D.new()
	root.add_child(scene)
	var visual := MeshInstance3D.new()
	scene.add_child(visual)
	visual.owner = scene
	visual.mesh = PlaneMesh.new()
	check(Conversion.inspect(visual,scene).has("error"),"arbitrary mesh accepted")
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0
	visual.mesh = cylinder
	check(Conversion.inspect(visual,scene).has("error"),"cone accepted")
	visual.mesh = BoxMesh.new()
	var converter := Conversion.new()
	check(converter.prepare(visual,scene,Vector3i.ONE*16,16,Color.RED,"Stale"),"stale setup")
	visual.position.x += 1
	var undo := UndoRedo.new()
	check(converter.commit(undo) == null,"stale preview applied")
	undo.free()
	scene.free()
	await process_frame
	print("test_voxel_primitive_conversion: ","PASS" if errors.is_empty() else "FAIL"," · ",errors)
	quit(0 if errors.is_empty() else 1)
