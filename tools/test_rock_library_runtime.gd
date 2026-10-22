extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var packed:=EmberVoxelPrefab.ensure_saved("vox_painted_rock_group",16.0,{})
	var prop:=packed.instantiate() as EmberVoxelProp
	root.add_child(prop);prop.configure_voxel_scale(16,1.0)
	assert(prop.get_node("Mesh").mesh.get_faces()==prop.get_node("Collision/Shape").shape.get_faces())
	root.remove_child(prop);prop.free();packed=null;EmberVoxelPrefab.begin_import()
	await process_frame;await process_frame
	Node.print_orphan_nodes()
	print("ROCK_LIBRARY_RUNTIME PASS");quit()
