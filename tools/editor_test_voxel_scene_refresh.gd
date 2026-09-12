@tool
extends EditorPlugin
## Opt-in in a disposable project only. Tests the real toolbar/dock and editor
## history with inline meshes, rather than claiming runtime tests cover them.
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
var errors: Array[String] = []


func _enter_tree() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)


func settle() -> void:
	for frame in 600:
		var fs := EditorInterface.get_resource_filesystem()
		if not fs.is_scanning() and not fs.is_importing(): return
		await get_tree().process_frame
	check(false, "filesystem did not settle")


func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-canvas-smoke-refresh-"):
		push_error("Refresh fixture requires a disposable copy")
		return
	for frame in 60: await get_tree().process_frame
	await settle()
	var source := EmberVoxelModelResource.new()
	source.model_id = "scene_refresh_fixture"
	source.display_name = "Scene refresh fixture"
	source.size_blocks = Vector3i.ONE
	source.height_voxels = 2
	source.physical = true
	source.palette = PackedColorArray([Color.TRANSPARENT, Color("98622d")])
	source.voxels.resize(512)
	source.voxels.fill(1)
	var template := EmberVoxelPrefab.prepare_resource(source).instantiate() as EmberVoxelProp
	var visual := template.get_node("Mesh") as MeshInstance3D
	visual.mesh = Session._legacy_bottom_mesh(visual.mesh)
	template.get_node("Collision/Shape").shape = visual.mesh.create_trimesh_shape()
	var old := PackedScene.new()
	check(old.pack(template) == OK, "old pack")
	template.free()
	var source_path := "res://content/voxel_models/scene_refresh_fixture.tres"
	var prefab_path := "res://prefabs/voxels/scene_refresh_fixture.tscn"
	check(Store.install_prepared_asset(source, old, source_path, prefab_path).ok, "fixture installs")
	check(Store.install_derived_prefab(old, prefab_path, "old-bottom-contract").ok, "old derived installs")
	var scene := Node3D.new()
	scene.name = "RefreshFixture"
	var prop := (load(prefab_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as EmberVoxelProp
	prop.name = "Probe"
	prop.placement_id = "refresh_probe"
	scene.add_child(prop)
	prop.owner = scene
	var saved := PackedScene.new()
	check(saved.pack(scene) == OK, "scene pack")
	check(ResourceSaver.save(saved, "res://scenes/refresh_fixture.tscn") == OK, "fixture scene save")
	scene.free()
	preload("res://addons/ember_import/ember_editor_filesystem.gd").request()
	for frame in 60: await get_tree().process_frame
	await settle()
	EditorInterface.open_scene_from_path("res://scenes/refresh_fixture.tscn")
	for frame in 60: await get_tree().process_frame
	scene = EditorInterface.get_edited_scene_root()
	check(scene != null and scene.scene_file_path == "res://scenes/refresh_fixture.tscn", "fixture scene not active")
	if scene == null: get_tree().quit(1); return
	prop = scene.get_node("Probe") as EmberVoxelProp
	var old_mesh: Mesh = prop.get_node("Mesh").mesh
	var old_shape: Shape3D = prop.get_node("Collision/Shape").shape
	var source_hash := FileAccess.get_sha256(source_path)
	var scene_hash := FileAccess.get_sha256(scene.scene_file_path)
	var pose := prop.transform
	var refresh := EditorInterface.get_base_control().find_child("RefreshSceneVoxels", true, false) as Button
	check(refresh != null, "real refresh button not found")
	if refresh != null: refresh.pressed.emit()
	for frame in 180:
		await get_tree().process_frame
		if prop.get_node("Mesh").mesh != old_mesh: break
	check(prop.get_node("Mesh").mesh != old_mesh and prop.get_node("Collision/Shape").shape != old_shape, "button did not refresh open inline instance")
	check(FileAccess.get_sha256(source_path) == source_hash and FileAccess.get_sha256(scene.scene_file_path) == scene_hash and prop.transform == pose, "button changed source/map/pose")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	check(prop.get_node("Mesh").mesh == old_mesh and prop.get_node("Collision/Shape").shape == old_shape, "editor Undo did not restore geometry")
	history.redo()
	check(prop.get_node("Mesh").mesh != old_mesh and FileAccess.get_sha256(source_path) == source_hash, "editor Redo/source")
	for frame in 120: await get_tree().process_frame
	await settle()
	check(EditorInterface.save_scene() == OK, "updated editor scene save")
	var reopened: Node = ResourceLoader.load(scene.scene_file_path, "", ResourceLoader.CACHE_MODE_IGNORE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	check(reopened.get_node("Probe").get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, "") == prop.get_meta(EmberVoxelPrefab.SOURCE_SIGNATURE_META, ""), "editor save/reopen did not persist revision")
	reopened.free()
	var library_button := EditorInterface.get_base_control().find_child("RebuildVoxelLibrary", true, false) as Button
	# Reproduce the failed publication case: an existing text prefab without UID.
	var no_uid_path := "user://ember-tests/native-refresh-%d/no-uid.tscn" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(no_uid_path.get_base_dir()))
	check(ResourceSaver.save(EmberVoxelPrefab.prepare_resource(source), no_uid_path) == OK, "no-UID fixture save")
	check(Store.install_derived_prefab(EmberVoxelPrefab.prepare_resource(source), no_uid_path, "native-no-uid").ok, "native no-UID publication failed")
	check(EmberVoxelPrefab.resource_uid_from_header(no_uid_path) != ResourceUID.INVALID_ID, "native no-UID publication did not assign UID")
	check(library_button != null, "whole-library button not found")
	var outside := source.duplicate(true) as EmberVoxelModelResource
	outside.model_id = "outside_refresh_fixture"
	check(ResourceSaver.save(outside, "res://content/voxel_models/outside_refresh_fixture.tres") == OK, "outside fixture source save")
	for frame in 60: await get_tree().process_frame
	await settle()
	var library_source_hash := FileAccess.get_sha256(source_path)
	var ids: Array[String] = ["scene_refresh_fixture", "outside_refresh_fixture"]
	var dock := EditorInterface.get_base_control().find_child("EmberMigrationWorkflow", true, false)
	check(dock != null, "real migration dock not found")
	if dock != null and library_button != null:
		var rename_attempts := [0]
		Store.derived_rename_override = func(temporary: String, destination: String):
			rename_attempts[0] += 1
			if rename_attempts[0] <= 2: return FAILED
			return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination))
		var FsQueue = load("res://addons/ember_import/ember_editor_filesystem.gd")
		var scans_before := int(FsQueue.diagnostics().scans)
		dock.library_ids_provider = func(): return ids
		library_button.pressed.emit()
		for frame in 300:
			await get_tree().process_frame
			if not dock._refreshing_voxels: break
		Store.derived_rename_override = Callable()
		check(rename_attempts[0] == 4, "native transient sharing-violation retries not observed")
		check(int(FsQueue.diagnostics().scans) == scans_before, "filesystem scan started during library publication batch")
		check(not dock._refreshing_voxels and "пересобрано 2" in dock._status.text, "real library button/queue: " + dock._status.text)
		dock.library_ids_provider = Callable()
	check(FileAccess.file_exists("res://prefabs/voxels/outside_refresh_fixture.tscn"), "outside-scene asset did not build")
	history.undo()
	history.redo()
	check(FileAccess.get_sha256(source_path) == library_source_hash, "library changed canonical source")
	if dock != null:
		var retry_ids: Array[String] = ["retry_refresh_fixture_%d" % Time.get_ticks_usec()]
		dock.library_ids_provider = func(): return retry_ids
		dock.rebuild_library_voxels()
		while dock._refreshing_voxels: await get_tree().process_frame
		check(dock._library_retry.visible and dock._library_skipped_ids == retry_ids, "failed queue does not offer retry")
		var retry_source := source.duplicate(true) as EmberVoxelModelResource
		retry_source.model_id = retry_ids[0]
		check(ResourceSaver.save(retry_source, EmberVoxelCatalog.native_path(retry_ids[0])) == OK, "retry source fixture save")
		for frame in 60: await get_tree().process_frame
		await settle()
		dock._library_retry.pressed.emit()
		while dock._refreshing_voxels: await get_tree().process_frame
		check(not dock._library_retry.visible and "пересобрано 1" in dock._status.text, "real retry button: " + dock._status.text)
		dock.library_ids_provider = Callable()
	for frame in 90: await get_tree().process_frame
	await settle()
	for message in errors: push_error(message)
	print("editor_test_voxel_scene_refresh: ", "PASS" if errors.is_empty() else "FAIL")
	if errors.is_empty():
		EditorInterface.get_base_control().get_parent().notification.call_deferred(NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		get_tree().quit(1)
