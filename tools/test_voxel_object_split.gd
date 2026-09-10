extends SceneTree
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Split = preload("res://addons/ember_import/ember_voxel_object_split.gd")
const Dialog = preload("res://addons/ember_import/ember_voxel_split_dialog.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var folder := "user://ember-tests/split-%d" % Time.get_ticks_usec()
	var source: EmberVoxelModelResource = Shapes.build("block",Vector3i(64,3,64),16,Color.BROWN,"split_fixture","Split").source
	for channel in ["emissive","shine","transparency","transmittance"]:
		var data := PackedByteArray()
		data.resize(source.voxels.size())
		data[33] = 70
		source.set(channel,data)
	source.voxel_groups = [{"id":"a","name":"A","indices":PackedInt32Array([1,33,2048,2081])}]
	var path := folder.path_join("original.tres")
	var prefab := folder.path_join("original.tscn")
	var saved := Store.install_prepared_asset(source,EmberVoxelPrefab.prepare_resource(source),path,prefab)
	assert(saved.ok)
	var scene := Node3D.new()
	root.add_child(scene)
	var parent := StaticBody3D.new()
	scene.add_child(parent)
	parent.owner = scene
	parent.name = "Container"
	parent.transform = Transform3D(Basis(Vector3.UP,0.4).scaled(Vector3(1,2,1)),Vector3(50,6,7))
	var prop := EmberSceneAuthoring.make_model_instance(scene,saved.packed,"split_fixture",Vector3.ZERO)
	parent.add_child(prop)
	prop.name = "Deck"
	prop.owner = scene
	prop.unique_name_in_owner = true
	prop.scene_file_path = prefab
	prop.transform = Transform3D(Basis(Vector3.UP,0.7).scaled(Vector3(1.2,0.8,1.1)),Vector3(3,4,5))
	# Session native lookup is model_id based; use matching fixture path.
	var native := folder.path_join("split_fixture.tres")
	assert(ResourceSaver.save(source,native) == OK)
	var original_hash := FileAccess.get_sha256(native)
	var split := Split.new()
	split.source_directory = folder
	split.prefab_directory = folder.path_join("parts")
	assert(split.prepare(prop,scene,32),split.error)
	assert(split.parts.size() == 4)
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(split.prefab_directory)))
	var mesh_frame: Transform3D = prop.get_node("Mesh").global_transform
	var undo := UndoRedo.new()
	var group := split.commit(undo)
	assert(group != null,split.error)
	assert(group.name == &"Deck" and group.owner == scene and group.get_child_count() == 4)
	assert(scene.get_node("%Deck") == group)
	var groups_count := 0
	var placements := {}
	for index in split.parts.size():
		var child := group.get_child(index) as EmberVoxelProp
		assert(not child.placement_id.is_empty() and not placements.has(child.placement_id))
		placements[child.placement_id] = true
		var part: Dictionary = split.parts[index]
		var model := ResourceLoader.load(folder.path_join(child.model_id+".tres")) as EmberVoxelModelResource
		assert(model != null)
		assert(child.get_node("Collision/Shape").shape != null)
		var size := model.grid_size()
		for channel in ["voxels","emissive","shine","transparency","transmittance"]:
			for y in size.y:
				for z in size.z:
					for x in size.x:
						assert(model.get(channel)[VoxMesher.cell_index(x,y,z,size.x,size.z)] == source.get(channel)[VoxMesher.cell_index(x+part.origin.x,y,z+part.origin.z,64,64)])
		var expected := mesh_frame * ((Vector3(part.origin)+Vector3(0.5,0.5,0.5))/16.0)
		var actual: Vector3 = child.get_node("Mesh").global_transform * (Vector3.ONE*0.5/16.0)
		assert(expected.is_equal_approx(actual))
		for entry in model.voxel_groups:
			groups_count += entry.indices.size()
		var edit := Session.new()
		edit.source_directory = folder
		edit.prefab_directory = split.prefab_directory
		assert(edit.open(child,scene,undo),edit.error)
	assert(groups_count == 4)
	await physics_frame
	await physics_frame
	for x in [31.99,32.0,32.01]:
		var from := mesh_frame * (Vector3(x,8,10)/16.0)
		var to := mesh_frame * (Vector3(x,-2,10)/16.0)
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to))
		assert(not hit.is_empty())
		assert(hit.position.is_equal_approx(mesh_frame * (Vector3(x,3,10)/16.0)))
	undo.undo()
	assert(prop.get_parent() == parent and prop.owner == scene)
	assert(scene.get_node("%Deck") == prop)
	undo.redo()
	assert(group.get_parent() == parent and prop.get_parent() == null)
	assert(FileAccess.get_sha256(native) == original_hash)
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed,folder.path_join("scene.tscn")) == OK)
	var reopened := (ResourceLoader.load(folder.path_join("scene.tscn"),"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	assert(reopened.get_node("Container/Deck").get_child_count() == 4)
	root.add_child(reopened)
	var reopened_group := reopened.get_node("Container/Deck")
	var ids := {}
	for index in 4:
		var restored := reopened_group.get_child(index) as EmberVoxelProp
		var live := group.get_child(index) as EmberVoxelProp
		assert(not ids.has(restored.model_id))
		ids[restored.model_id] = true
		assert(restored.transform.is_equal_approx(live.transform))
		assert(restored.get_node("Mesh").global_transform.is_equal_approx(live.get_node("Mesh").global_transform))
		assert(restored.get_node("Collision/Shape").shape.get_faces() == live.get_node("Collision/Shape").shape.get_faces())
	reopened.free()
	undo.undo()
	assert(split.prepare(prop,scene,32))
	prop.position.x += 1
	assert(split.commit(undo) == null)
	undo.clear_history()
	undo.free()
	scene.free()
	print("test_voxel_object_split: PASS")
	quit()
