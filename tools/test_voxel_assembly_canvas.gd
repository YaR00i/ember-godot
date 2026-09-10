extends SceneTree
const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
const Split = preload("res://addons/ember_import/ember_voxel_object_split.gd")
const Assembly = preload("res://addons/ember_import/ember_voxel_assembly_session.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
var folder: String
func _init() -> void:
	_run.call_deferred()
func session(group: Node3D,scene: Node,undo: Object) -> RefCounted:
	var edit := Assembly.new()
	edit.source_directory = folder.path_join("sources")
	edit.prefab_directory = folder.path_join("prefabs")
	assert(edit.open(group,scene,undo),edit.error)
	return edit
func _run() -> void:
	folder = "user://ember-tests/assembly-%d" % Time.get_ticks_usec()
	var scene := Node3D.new()
	root.add_child(scene)
	var undo := UndoRedo.new()
	var creation := Creation.new()
	creation.source_directory = folder.path_join("sources")
	creation.prefab_directory = folder.path_join("prefabs")
	assert(creation.prepare("block",Vector3i(64,4,64),16,Color.BROWN,"Deck"))
	creation.source.voxel_groups = [{"id":"grain","name":"Grain","indices":PackedInt32Array([1,33,2048,2081])}]
	for channel in ["emissive","shine","transparency","transmittance"]:
		var values := PackedByteArray()
		values.resize(creation.source.voxels.size())
		values[33] = 70
		creation.source.set(channel,values)
	creation.packed = EmberVoxelPrefab.prepare_resource(creation.source)
	var prop := creation.commit(scene,scene,undo,Vector3(10,2,30))
	prop.transform.basis = Basis(Vector3.UP,0.4).scaled(Vector3(1.3,0.8,1.1))
	var split := Split.new()
	split.source_directory = creation.source_directory
	split.prefab_directory = creation.prefab_directory
	assert(split.prepare(prop,scene,32),split.error)
	var group := split.commit(undo)
	assert(group != null,split.error)
	var edit := session(group,scene,undo)
	var surface := preload("res://addons/ember_import/ember_walk_surface.gd").make_node(Vector2(64,64))
	group.add_child(surface)
	surface.owner = scene
	surface.get_child(0).owner = scene
	assert(session(group,scene,undo).draft.voxels == edit.draft.voxels)
	assert(edit.draft.grid_size() == Vector3i(64,4,64))
	assert(edit.draft.voxels == creation.source.voxels)
	assert(edit.draft.voxel_groups == creation.source.voxel_groups)
	for channel in ["emissive","shine","transparency","transmittance"]:
		assert(edit.draft.get(channel) == creation.source.get(channel))
	var canvas := Workspace.new()
	root.add_child(canvas)
	canvas.setup(null,undo)
	canvas.open_object(edit)
	assert(not canvas._grow_button.visible)
	var initial_ids: Array = []
	var hashes: Array = []
	for child in group.get_children():
		if child == surface:
			continue
		initial_ids.append(child.model_id)
		hashes.append(FileAccess.get_sha256(creation.source_directory.path_join(child.model_id+".tres")))
	var left := VoxMesher.cell_index(31,3,10,64,64)
	var right := VoxMesher.cell_index(32,3,10,64,64)
	assert(canvas._actions.apply_stroke(edit.draft,{left:{"before":1,"after":0},right:{"before":1,"after":0}}))
	undo.undo()
	assert(edit.draft.voxels[left] == 1 and edit.draft.voxels[right] == 1)
	undo.redo()
	assert(edit.draft.voxels[left] == 0 and edit.draft.voxels[right] == 0)
	assert(canvas.save_changes(),edit.error)
	assert(surface.get_parent() == group and surface.get_child(0).shape.size.x == 64)
	assert(group.get_child(0).model_id != initial_ids[0] and group.get_child(1).model_id != initial_ids[1])
	assert(group.get_child(2).model_id == initial_ids[2] and group.get_child(3).model_id == initial_ids[3])
	for index in 4:
		assert(FileAccess.get_sha256(creation.source_directory.path_join(initial_ids[index]+".tres")) == hashes[index])
	var reopened := session(group,scene,undo)
	assert(reopened.draft.voxels[left] == 0 and reopened.draft.voxels[right] == 0)
	undo.undo()
	for index in 4:
		assert(group.get_child(index).model_id == initial_ids[index])
	undo.redo()
	var ids_after: Array = []
	for child in group.get_children():
		if child == surface:
			continue
		ids_after.append(child.model_id)
	assert(reopened.save(reopened.draft).changed == 0)
	# A failed publication cannot update a subset of scene references.
	var failure := session(group,scene,undo)
	failure.draft.voxels[0] = 0
	failure.draft.voxels[33] = 0
	failure._slots[1].session.prefab_directory = creation.source_directory.path_join(ids_after[0]+".tres")
	assert(not failure.save(failure.draft).ok)
	for index in 4:
		assert(group.get_child(index).model_id == ids_after[index])
	# Existing discard/navigation guard works with the assembly session.
	canvas.open_object(session(group,scene,undo))
	canvas._resource.voxels[5] = 0
	canvas.open_object(session(group,scene,undo))
	canvas._navigation_guard._cancel_request()
	assert(canvas.has_unsaved_changes())
	canvas.open_object(session(group,scene,undo))
	canvas._navigation_guard._custom_action("discard")
	assert(canvas._resource.voxels[5] == 1 and not canvas.has_unsaved_changes())
	var packed := PackedScene.new()
	assert(packed.pack(scene) == OK)
	var path := folder.path_join("scene.tscn")
	assert(ResourceSaver.save(packed,path) == OK)
	var restored := (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	root.add_child(restored)
	var restored_edit := session(restored.get_child(0),restored,undo)
	assert(restored_edit.draft.voxels[left] == 0 and restored_edit.draft.voxels[right] == 0)
	restored.free()
	# A separately edited section may have a different palette ordering.
	var third := group.get_child(2) as EmberVoxelProp
	var third_path := creation.source_directory.path_join(third.model_id+".tres")
	var reordered := (ResourceLoader.load(third_path) as EmberVoxelModelResource).duplicate(true) as EmberVoxelModelResource
	reordered.palette = PackedColorArray([Color.TRANSPARENT,Color.RED,Color.BROWN])
	for index in reordered.voxels.size():
		if reordered.voxels[index] == 1:
			reordered.voxels[index] = 2
	assert(EmberVoxelModelStore.install_prepared_asset(reordered,EmberVoxelPrefab.prepare_resource(reordered),third_path,third.scene_file_path).ok)
	var mixed := session(group,scene,undo)
	assert(mixed.save(mixed.draft).changed == 0)
	var painted := VoxMesher.cell_index(2,3,40,64,64)
	mixed.draft.voxels[painted] = mixed.draft.palette.find(Color.RED)
	assert(mixed.save(mixed.draft).changed == 1)
	var new_color := session(group,scene,undo)
	new_color.draft.palette.append(Color.GREEN)
	new_color.draft.voxels[VoxMesher.cell_index(4,3,42,64,64)] = new_color.draft.palette.size()-1
	assert(new_color.save(new_color.draft).changed == 1)
	group.get_child(0).position.x += 0.2
	var bad := Assembly.new()
	bad.source_directory = creation.source_directory
	assert(not bad.open(group,scene,undo))
	canvas.free()
	undo.clear_history()
	undo.free()
	scene.free()
	print("test_voxel_assembly_canvas: PASS")
	quit()
