extends SceneTree
## A/B diagnostic, isolated user:// assets. Restores redundant builds only in memory.
const Creation = preload("res://addons/ember_import/ember_voxel_shape_creation.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var old := GDScript.new()
	old.source_code = FileAccess.get_file_as_string("res://addons/ember_import/ember_voxel_object_session.gd")
	old.source_code = old.source_code.replace("prepare_resource(_baseline, _projection_cache)","prepare_resource(_baseline)").replace("prepare_resource(next, _projection_cache)","prepare_resource(next)")
	old.source_code = old.source_code.replace("_projection_errors(prop, _baseline, baseline_packed)","_projection_errors(prop, _baseline)")
	old.source_code = old.source_code.replace("target != prop and not _projection_errors(target, _baseline, baseline_packed)","not _projection_errors(target, _baseline)")
	old.source_code = old.source_code.replace('"packed": baseline_packed, "path": destination','"packed": EmberVoxelPrefab.prepare_resource(_baseline), "path": destination')
	assert(old.reload() == OK)
	for mode in ["before","after"]:
		var scene := Node3D.new()
		root.add_child(scene)
		var undo := UndoRedo.new()
		var creation := Creation.new()
		var folder := "user://ember-tests/save-reuse-%d" % Time.get_ticks_usec()
		creation.source_directory = folder.path_join("sources")
		creation.prefab_directory = folder.path_join("prefabs")
		assert(creation.prepare("block",Vector3i(192,10,256),16,Color.BROWN,"Pier"))
		var prop := creation.commit(scene,scene,undo,Vector3.ZERO)
		assert(prop != null)
		var edit = old.new() if mode == "before" else Session.new()
		edit.source_directory = creation.source_directory
		edit.prefab_directory = creation.prefab_directory
		assert(edit.open(prop,scene,undo))
		for pass_index in 2:
			edit.draft.voxels[pass_index] = 0
			var start := Time.get_ticks_usec()
			assert(edit.save(edit.draft).ok)
			print("SAVE_REUSE ",mode," pass=",pass_index," ms=",(Time.get_ticks_usec()-start)/1000.0)
		undo.clear_history()
		undo.free()
		scene.free()
		await process_frame
	print("SAVE_REUSE PASS")
	quit()
