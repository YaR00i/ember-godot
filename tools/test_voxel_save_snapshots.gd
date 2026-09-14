extends SceneTree
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
var errors: Array[String] = []
var directory := "user://ember-tests/save-snapshots-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func hashes(source_path: String, prefab_path: String) -> Array[String]:
	return [FileAccess.get_sha256(source_path), FileAccess.get_sha256(prefab_path)]


func _run() -> void:
	var source: EmberVoxelModelResource = Shapes.build("block", Vector3i(32, 8, 32), 16, Color.CORAL, "snapshot_fixture", "Snapshot").source
	var source_path := directory.path_join("sources/snapshot_fixture.tres")
	var prefab_path := directory.path_join("prefabs/snapshot_fixture.tscn")
	var before := source.to_definition().duplicate(true)
	var notifications: Array[PackedStringArray] = []
	var observe := func(paths: PackedStringArray) -> void:
		notifications.append(paths)
		check((load(source_path) as EmberVoxelModelResource).validation_errors().is_empty(), "notification source unreadable")
		check(load(prefab_path) is PackedScene, "notification prefab unreadable")
	Store.asset_events.assets_published.connect(observe)
	var first := Store.install_prepared_asset(source, EmberVoxelPrefab.prepare_resource(source), source_path, prefab_path, true)
	check(first.ok and not first.snapshot.is_empty(), "publication did not produce snapshot")
	check(source.to_definition() == before, "publication changed input source")
	var original := hashes(source_path, prefab_path)
	var uids := [EmberVoxelPrefab.resource_uid_from_header(source_path), EmberVoxelPrefab.resource_uid_from_header(prefab_path)]
	check(uids[0] != ResourceUID.INVALID_ID and uids[1] != ResourceUID.INVALID_ID, "streamed headers lost UID")
	source.voxels[0] = 0
	var second := Store.install_prepared_asset(source, EmberVoxelPrefab.prepare_resource(source), source_path, prefab_path, true)
	var changed := hashes(source_path, prefab_path)
	check(second.ok and changed != original, "second publication unchanged")
	check(Store.restore_prepared_snapshot(first.snapshot, source_path, prefab_path).ok, "snapshot restore failed")
	check(hashes(source_path, prefab_path) == original, "snapshot did not restore exact source/prefab bytes")
	check(Store.restore_prepared_snapshot(second.snapshot, source_path, prefab_path).ok, "snapshot redo failed")
	check(hashes(source_path, prefab_path) == changed, "snapshot redo changed bytes")
	check([EmberVoxelPrefab.resource_uid_from_header(source_path), EmberVoxelPrefab.resource_uid_from_header(prefab_path)] == uids, "snapshot changed stable UIDs")
	check((load(prefab_path) as PackedScene).get_state().get_path() == prefab_path, "published SceneState retained staging path")
	check(notifications.size() == 4, "successful publications not observable")
	for paths in notifications:
		check(paths == PackedStringArray([source_path, prefab_path]), "notification contained staging paths")
	# Failure on the second rename must restore the already-published source.
	Store.asset_rename_override = func(staged: String, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if destination == prefab_path else DirAccess.rename_absolute(ProjectSettings.globalize_path(staged), ProjectSettings.globalize_path(destination))
	var failed := Store.restore_prepared_snapshot(first.snapshot, source_path, prefab_path)
	Store.asset_rename_override = Callable()
	check(not failed.ok and hashes(source_path, prefab_path) == changed, "failed replay partially published")
	check(notifications.size() == 4, "failed replay emitted publication")
	failed = Store.install_prepared_asset(source, EmberVoxelPrefab.prepare_resource(source), source_path, prefab_path, false)
	check(failed.ok and failed.snapshot.is_empty(), "legacy publication API changed")
	changed = hashes(source_path, prefab_path)
	var corrupt: Dictionary = first.snapshot.duplicate(true)
	corrupt.prefab.hash = "invalid"
	var count := notifications.size()
	failed = Store.restore_prepared_snapshot(corrupt, source_path, prefab_path)
	check(not failed.ok and hashes(source_path, prefab_path) == changed, "corrupt snapshot was published")
	check(notifications.size() == count, "corrupt snapshot notified observers")
	Store.asset_rename_override = func(staged: String, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if destination == prefab_path else DirAccess.rename_absolute(ProjectSettings.globalize_path(staged), ProjectSettings.globalize_path(destination))
	failed = Store.install_prepared_asset(source, EmberVoxelPrefab.prepare_resource(source), source_path, prefab_path, true)
	Store.asset_rename_override = Callable()
	check(not failed.ok and failed.snapshot.is_empty() and hashes(source_path, prefab_path) == changed, "failed prepared publication changed files/snapshot")
	check(notifications.size() == count, "failed prepared publication notified observers")
	Store.asset_events.assets_published.disconnect(observe)
	_test_uid_stream()
	_test_session(source_path, prefab_path)
	for error in errors:
		push_error(error)
	print("test_voxel_save_snapshots: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size())
	quit(0 if errors.is_empty() else 1)


func _test_uid_stream() -> void:
	var path := directory.path_join("large-header.tscn")
	# Cross the stream's 1MiB boundary twice, including UTF-8 after the header.
	var body := "# " + "x".repeat(2100000) + "\n# Берег\n[node name=\"Root\" type=\"Node3D\"]\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("[gd_scene format=3]\n" + body)
	file.close()
	for index in 2:
		var uid := ResourceUID.create_id()
		check(Store._set_staged_uid(path, uid) == OK, "streamed UID write failed")
		var text := FileAccess.get_file_as_string(path)
		check(text.substr(text.find("\n") + 1) == body, "UID update changed streamed body")
		check(text.get_slice("\n", 0).count(" uid=") == 1 and EmberVoxelPrefab.resource_uid_from_header(path) == uid, "UID header duplicated/lost ID")


func _test_session(source_path: String, prefab_path: String) -> void:
	var root_node := Node3D.new()
	root.add_child(root_node)
	var prop := (load(prefab_path) as PackedScene).instantiate() as EmberVoxelProp
	root_node.add_child(prop)
	prop.owner = root_node
	var undo := UndoRedo.new()
	var edit := Session.new()
	edit.source_directory = source_path.get_base_dir()
	edit.prefab_directory = prefab_path.get_base_dir()
	check(edit.open(prop, root_node, undo), "session open failed")
	edit.draft.voxels[1] = 0
	check(edit.save(edit.draft).ok, "first session save failed")
	var saved_source := edit.source_directory.path_join(prop.model_id + ".tres")
	var saved_prefab := prop.scene_file_path
	var first := hashes(saved_source, saved_prefab)
	var first_faces: PackedVector3Array = prop.get_node("Collision/Shape").shape.get_faces()
	edit.draft.voxels[2] = 0
	check(edit.save(edit.draft).ok, "second session save failed")
	var second := hashes(saved_source, saved_prefab)
	var second_faces: PackedVector3Array = prop.get_node("Collision/Shape").shape.get_faces()
	check(edit._last_saved_asset.has("snapshot") and not edit._last_saved_asset.has("packed"), "history asset still retains prepared scene")
	# Reopening and releasing acceleration must not mutate snapshots retained by
	# earlier undo actions through shared Dictionary references.
	check(edit.refresh_before_open(), "session refresh failed")
	edit.release_projection_cache()
	undo.undo()
	check(hashes(saved_source, saved_prefab) == first, "Undo after refresh/cache release changed snapshot bytes")
	check(prop.get_node("Collision/Shape").shape.get_faces() == first_faces, "Undo failed to restore physical geometry")
	undo.redo()
	check(hashes(saved_source, saved_prefab) == second, "Redo after refresh/cache release changed snapshot bytes")
	check(prop.get_node("Collision/Shape").shape.get_faces() == second_faces, "Redo failed to restore physical geometry")
	check(edit.open(prop, root_node, undo), "reopen after redo failed")
	edit.draft.voxels[3] = 0
	check(edit.save(edit.draft).ok, "save after reopening failed")
	var before_bad := hashes(saved_source, saved_prefab)
	var live: ArrayMesh = prop.get_node("Mesh").mesh
	var arrays := live.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	vertices[0].x += 0.25
	arrays[Mesh.ARRAY_VERTEX] = vertices
	live.clear_surfaces()
	live.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	live.surface_set_name(0, "opaque")
	edit.draft.voxels[4] = 0
	check(not edit.save(edit.draft).ok, "snapshot reuse bypassed independent geometry validation")
	check(hashes(saved_source, saved_prefab) == before_bad, "rejected geometry mutation changed disk assets")
	undo.clear_history()
	undo.free()
	root_node.free()
