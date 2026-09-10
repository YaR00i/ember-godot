extends SceneTree
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Growth = preload("res://addons/ember_import/ember_voxel_canvas_growth.gd")
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
	var creation := Creation.new()
	var fixture := "user://ember-tests/growth-%d" % Time.get_ticks_usec()
	creation.source_directory = fixture.path_join("sources")
	creation.prefab_directory = fixture.path_join("prefabs")
	creation.prepare("block", Vector3i(16,16,16), 16, Color.RED, "Growth")
	for channel in ["emissive", "shine", "transparency", "transmittance"]:
		var values := PackedByteArray()
		values.resize(4096)
		values[0] = 30
		creation.source.set(channel, values)
	creation.packed = EmberVoxelPrefab.prepare_resource(creation.source)
	var undo := UndoRedo.new()
	var prop := creation.commit(scene, scene, undo, Vector3(30,4,7))
	var original_mesh: Mesh = prop.get_node("Mesh").mesh
	var original_aabb := original_mesh.get_aabb()
	var original_offset: Vector3 = prop.get_node("Mesh").position
	var mesh_scale: Vector3 = prop.get_node("Mesh").scale
	var edit := Session.new()
	edit.source_directory = creation.source_directory
	edit.prefab_directory = creation.prefab_directory
	check(edit.open(prop, scene, undo), edit.error)
	var canvas := Workspace.new()
	root.add_child(canvas)
	canvas.setup(null, undo)
	canvas.open_object(edit)
	var before := edit.draft.voxels.duplicate()
	var timer := Time.get_ticks_usec()
	var plan := Growth.plan(edit.draft, Vector3i(32,32,32))
	check(not plan.has("error"), "growth plan")
	check(edit.draft.voxels == before, "preview mutated source")
	canvas._actions.grow_canvas(edit.draft, Vector3i(32,32,32))
	print("CANVAS_GROWTH_16_32_MS ", (Time.get_ticks_usec() - timer) / 1000.0)
	check(edit.draft.validation_errors().is_empty(), "expanded validation")
	check(edit.draft.voxels.count(1) == 4096, "occupancy changed")
	check(edit.draft.emissive[VoxMesher.cell_index(8,0,8,32,32)] == 30, "material remapping")
	check(canvas.has_unsaved_changes(), "growth not dirty")
	undo.undo()
	check(edit.draft.grid_size() == Vector3i(16,16,16) and edit.draft.voxels == before, "growth Undo")
	undo.redo()
	check(edit.draft.grid_size() == Vector3i(32,32,32), "growth Redo")
	canvas.discard_changes()
	check(edit.draft.grid_size() == Vector3i(16,16,16) and edit.draft.validation_errors().is_empty() and not canvas.has_unsaved_changes(), "discard dimensions/channels")
	canvas._actions.grow_canvas(edit.draft, Vector3i(32,32,32))
	check(canvas.save_changes(), "growth Save: " + edit.error)
	check(not canvas.has_unsaved_changes(), "saved dimensions baseline")
	var new_mesh: Mesh = prop.get_node("Mesh").mesh
	var new_offset: Vector3 = prop.get_node("Mesh").position
	check((original_aabb.position * mesh_scale + original_offset).is_equal_approx(new_mesh.get_aabb().position * mesh_scale + new_offset), "world geometry shifted")
	check(original_aabb.size.is_equal_approx(new_mesh.get_aabb().size), "geometry scaled")
	check(prop.get_node("Collision/Shape").shape != null, "collider lost")
	undo.undo()
	check(prop.get_node("Mesh").mesh == original_mesh, "Save Undo geometry")
	undo.redo()
	check((prop.get_node("Mesh").mesh as Mesh).get_aabb() == new_mesh.get_aabb(), "Save Redo geometry")
	var reopened := Session.new()
	reopened.source_directory = creation.source_directory
	reopened.prefab_directory = creation.prefab_directory
	check(reopened.open(prop, scene, undo), "reopen: " + reopened.error)
	check(reopened.draft != null and reopened.draft.grid_size() == Vector3i(32,32,32), "reopen dimensions")
	check(Growth.plan(edit.draft, Vector3i(16,16,16)).has("error"), "shrink allowed")
	check(Growth.plan(edit.draft, Vector3i(33,32,32)).has("error"), "hidden grid rounding")
	check(Growth.plan(edit.draft, Vector3i(256,128,256)).has("error"), "budget bypass")
	for density in [16,32]:
		var source: EmberVoxelModelResource = Shapes.build("block",Vector3i(3,2,3),density,Color.RED,"groups","Groups").source
		source.voxel_groups = [{"id":"part", "name":"Part", "indices":PackedInt32Array([0,1])}]
		var grouped := Growth.plan(source, Vector3i(density * 2,4,density * 2))
		check(not grouped.has("error"), "group plan")
		if not grouped.has("error"):
			check(grouped.properties.voxel_groups[0].indices[0] == VoxMesher.cell_index(density/2,0,density/2,density*2,density*2), "group remapping")
	canvas.queue_free()
	await process_frame
	undo.clear_history()
	undo.free()
	scene.queue_free()
	await process_frame
	print("test_voxel_canvas_growth: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors)
	quit(0 if errors.is_empty() else 1)
