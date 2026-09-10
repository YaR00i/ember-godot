extends SceneTree
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
	var scene := Node3D.new()
	root.add_child(scene)
	scene.transform = Transform3D(Basis.from_euler(Vector3(0.1,0.7,0)).scaled(Vector3(1.2,0.8,1.1)),Vector3(30,3,60))
	var create := Creation.new()
	var fixture := "user://ember-tests/context-%d" % Time.get_ticks_usec()
	create.source_directory = fixture.path_join("sources")
	create.prefab_directory = fixture.path_join("prefabs")
	create.prepare("block",Vector3i(16,16,16),16,Color.RED,"Context")
	var undo := UndoRedo.new()
	var target := create.commit(scene,scene,undo,Vector3(8,2,12))
	target.rotation = Vector3(0.2,1.1,0.1)
	target.scale = Vector3(1.3,0.9,0.7)
	var neighbor := MeshInstance3D.new()
	neighbor.name = "Neighbor"
	neighbor.mesh = BoxMesh.new()
	neighbor.position = Vector3(9,1,13)
	neighbor.rotation.y = -0.5
	neighbor.material_override = StandardMaterial3D.new()
	neighbor.transparency = 0.2
	scene.add_child(neighbor)
	neighbor.owner = scene
	var hidden := MeshInstance3D.new()
	hidden.mesh = BoxMesh.new()
	hidden.visible = false
	scene.add_child(hidden)
	var multim := MultiMeshInstance3D.new()
	multim.multimesh = MultiMesh.new()
	multim.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multim.multimesh.mesh = BoxMesh.new()
	multim.multimesh.instance_count = 1
	scene.add_child(multim)
	var collision := StaticBody3D.new()
	neighbor.add_child(collision)
	var edit := Session.new()
	edit.source_directory = create.source_directory
	edit.prefab_directory = create.prefab_directory
	check(edit.open(target,scene,undo), edit.error)
	var canvas := Workspace.new()
	root.add_child(canvas)
	canvas.setup(null,undo)
	canvas.open_object(edit)
	var source_hash := FileAccess.get_sha256(create.source_directory.path_join(target.model_id + ".tres"))
	var original_mesh: Mesh = target.get_node("Mesh").mesh
	canvas._context_toggle.button_pressed = true
	check(canvas._scene_context.visible, "context not visible")
	check(canvas._scene_context.visuals.size() == 2, "hidden/target/physics cloned")
	var neighbor_copy: MeshInstance3D
	for visual in canvas._scene_context.visuals:
		check(visual.get_script() == null and visual.get_child_count() == 0 and visual.owner == null, "unsafe clone")
		if str(visual.get_meta("context_source")) == "Neighbor":
			neighbor_copy = visual
	check(neighbor_copy != null, "neighbor missing")
	var frame: Transform3D = edit.context_projection(edit.draft).frame
	check((frame * neighbor_copy.transform).is_equal_approx(neighbor.global_transform), "placement/rotation/scale mismatch")
	check(neighbor_copy.mesh == neighbor.mesh and neighbor_copy.material_override == neighbor.material_override, "material/mesh lost")
	canvas._context_opacity.value = 25
	check(is_equal_approx(neighbor_copy.transparency,0.8) and is_equal_approx(neighbor.transparency,0.2), "opacity changed source")
	check(not canvas.has_unsaved_changes(), "context dirtied model")
	var before_neighbor := neighbor.global_transform
	canvas._actions.apply_stroke(edit.draft,{0: {"before":1,"after":0}})
	check(target.get_node("Mesh").mesh == original_mesh and neighbor.global_transform == before_neighbor, "draft leaked into scene")
	undo.undo()
	canvas._actions.grow_canvas(edit.draft,Vector3i(32,32,32))
	frame = edit.context_projection(edit.draft).frame
	check((frame * neighbor_copy.transform).is_equal_approx(neighbor.global_transform), "growth shifted context")
	undo.undo()
	frame = edit.context_projection(edit.draft).frame
	check((frame * neighbor_copy.transform).is_equal_approx(neighbor.global_transform), "Undo shifted context")
	check(FileAccess.get_sha256(create.source_directory.path_join(target.model_id + ".tres")) == source_hash, "toggle/preview wrote file")
	canvas._actions.grow_canvas(edit.draft,Vector3i(32,32,32))
	check(canvas.save_changes(), "save with context: " + edit.error)
	canvas._sync_context_frame()
	frame = edit.context_projection(edit.draft).frame
	check((frame * neighbor_copy.transform).is_equal_approx(neighbor.global_transform), "Save shifted context")
	check(not canvas.has_unsaved_changes(), "context Save dirty")
	var saved_frame := frame
	undo.undo()
	canvas._sync_context_frame()
	frame = edit.context_projection(edit.draft).frame
	check(frame.is_equal_approx(saved_frame), "Save Undo moved the editing anchor")
	check((frame * neighbor_copy.transform).is_equal_approx(neighbor.global_transform), "Save Undo shifted context")
	undo.redo()
	canvas._sync_context_frame()
	frame = edit.context_projection(edit.draft).frame
	neighbor.position.x += 1
	canvas._refresh_scene_context()
	for visual in canvas._scene_context.visuals:
		if str(visual.get_meta("context_source")) == "Neighbor":
			check((frame * visual.transform).is_equal_approx(neighbor.global_transform), "refresh did not update scene")
	canvas._context_toggle.button_pressed = false
	check(canvas._scene_context.visuals.is_empty(), "toggle did not release context")
	canvas._context_toggle.button_pressed = true
	root.remove_child(scene)
	canvas._sync_context_frame()
	check(not canvas._scene_context.visible and not canvas._context_toggle.button_pressed, "closed scene remained visible")
	canvas.queue_free()
	await process_frame
	undo.clear_history()
	undo.free()
	scene.free()
	print("test_voxel_canvas_context: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors)
	quit(0 if errors.is_empty() else 1)
