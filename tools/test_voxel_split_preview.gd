extends SceneTree
const Dialog = preload("res://addons/ember_import/ember_voxel_split_dialog.gd")
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1100,900)
	# Pier is now an authored assembly, not a single splittable prop. Exercise
	# the real split dialog with a stable native source without editing Pier.
	var folder := "user://ember-tests/split-preview-%d" % Time.get_ticks_usec()
	var source: EmberVoxelModelResource = preload("res://addons/ember_import/ember_voxel_shapes.gd").build("block",Vector3i(80,3,80),16,Color.BROWN,"split_preview_fixture","Deck").source
	var saved := preload("res://addons/ember_import/ember_voxel_model_store.gd").install_prepared_asset(source,EmberVoxelPrefab.prepare_resource(source),folder.path_join("split_preview_fixture.tres"),folder.path_join("fixture.tscn"))
	assert(saved.ok)
	var scene := Node3D.new()
	root.add_child(scene)
	var prop := EmberSceneAuthoring.make_model_instance(scene,saved.packed,"split_preview_fixture",Vector3.ZERO)
	scene.add_child(prop)
	prop.owner = scene
	assert(prop != null)
	var initial := source.to_definition().duplicate(true)
	var initial_transform := prop.global_transform
	var undo := UndoRedo.new()
	var dialog := Dialog.new()
	dialog.source_directory = folder
	dialog.prefab_directory = folder.path_join("parts")
	root.add_child(dialog)
	dialog.open_split(prop,scene,undo)
	assert(not dialog.get_ok_button().disabled,dialog._status.text)
	assert(dialog._splitter.parts.size() == 4,"expected four preview sections")
	assert(dialog._splitter.parts.back().size == Vector3i(16,3,16),"edge section dimensions")
	assert(source.to_definition() == initial and prop.global_transform == initial_transform,"preview mutated fixture")
	assert(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dialog.prefab_directory)),"preview wrote split prefabs")
	for frame in 20:
		await process_frame
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(false)
		var path := "user://voxel-split-preview-%d.png" % OS.get_process_id()
		assert(dialog.get_texture().get_image().save_png(path) == OK)
		print("SPLIT_PREVIEW_CAPTURE ",ProjectSettings.globalize_path(path))
	print("SPLIT_PREVIEW PASS")
	dialog.free()
	undo.free()
	scene.free()
	quit()
