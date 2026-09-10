extends SceneTree

const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
var errors: Array[String] = []
var fixture := "user://ember-tests/object-canvas-%d-%d" % [Time.get_unix_time_from_system(), OS.get_process_id()]


func _init() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)


func session(prop: EmberVoxelProp, scene: Node, undo: UndoRedo, shared := false):
	var edit := Session.new()
	edit.source_directory = fixture.path_join("sources")
	edit.prefab_directory = fixture.path_join("prefabs")
	check(edit.open(prop, scene, undo, shared), "session open: " + edit.error)
	return edit


func _run() -> void:
	var source := EmberVoxelModelResource.new()
	source.model_id = "canvas_fixture"
	source.display_name = "Canvas fixture"
	source.voxels_per_block = 16
	source.size_blocks = Vector3i.ONE
	source.height_voxels = 2
	source.physical = true
	source.palette = PackedColorArray([Color.TRANSPARENT, Color("98622d"), Color("438dc4")])
	source.voxels.resize(16 * 2 * 16)
	source.voxels.fill(1)
	var source_path := fixture.path_join("sources/canvas_fixture.tres")
	var prefab_path := fixture.path_join("prefabs/canvas_fixture.tscn")
	var prepared := EmberVoxelPrefab.prepare_resource(source)
	check(prepared != null, "initial prepare failed")
	check(Store.install_prepared_asset(source, prepared, source_path, prefab_path).ok, "fixture save failed")
	var initial_hash := FileAccess.get_sha256(source_path)
	var scene := Node3D.new()
	root.add_child(scene)
	var packed := load(prefab_path) as PackedScene
	var a := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as EmberVoxelProp
	var b := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as EmberVoxelProp
	a.name = "A"
	b.name = "B"
	a.placement_id = "first"
	b.placement_id = "second"
	scene.add_child(a)
	scene.add_child(b)
	a.owner = scene
	b.owner = scene
	scene.set_editable_instance(a, true)
	a.position = Vector3(12, 4, 8)
	a.rotation.y = 0.6
	b.position.x = 30
	var authored := Node3D.new()
	authored.name = "AuthoredSocket"
	authored.position = Vector3(1, 2, 3)
	a.get_node("Mesh").add_child(authored)
	authored.owner = scene
	var pose := a.transform
	var old_mesh = b.get_node("Mesh").mesh
	var old_shape = b.get_node("Collision/Shape").shape
	var old_faces: PackedVector3Array = old_shape.get_faces().duplicate()
	var undo := UndoRedo.new()
	var edit = session(a, scene, undo)
	check(edit.draft != edit._source, "draft aliases canonical source")
	check(edit.save(edit.draft).ok and FileAccess.get_sha256(source_path) == initial_hash, "open/save unchanged wrote source")
	check(DirAccess.get_files_at(fixture.path_join("sources")).size() == 1, "open created independent files")
	edit.draft.voxels[0] = 0
	var result: Dictionary = edit.save(edit.draft)
	check(result.get("ok", false), "selected save failed: %s" % result)
	var unique_id := a.model_id
	check(unique_id != b.model_id, "selected edit did not fork identity")
	check(a.scene_file_path != b.scene_file_path, "selected edit retained old prefab link")
	check(a.get_node("Mesh").mesh != old_mesh and b.get_node("Mesh").mesh == old_mesh, "mesh fork affects sibling")
	check(a.get_node("Collision/Shape").shape != old_shape and b.get_node("Collision/Shape").shape == old_shape, "collider fork affects sibling")
	check(a.transform == pose and a.get_node("Mesh/AuthoredSocket") == authored and authored.owner == scene, "save lost authored placement/children")
	var unique_path: String = result.get("path", "")
	var uid := EmberVoxelPrefab.resource_uid_from_header(unique_path)
	edit.draft.voxels[1] = 0
	check(edit.save(edit.draft).ok and a.model_id == unique_id, "repeated Save changed independent ID")
	check(EmberVoxelPrefab.resource_uid_from_header(unique_path) == uid, "repeated Save changed UID")
	undo.undo()
	undo.undo()
	check(a.model_id == b.model_id and a.get_node("Mesh").mesh == old_mesh and a.get_node("Collision/Shape").shape == old_shape, "Undo failed to restore references/geometry")
	check(FileAccess.file_exists(unique_path), "Undo deleted recoverable asset")
	undo.redo()
	undo.redo()
	var scene_save := PackedScene.new()
	check(scene_save.pack(scene) == OK, "scene pack failed")
	var scene_path := fixture.path_join("scene.tscn")
	check(ResourceSaver.save(scene_save, scene_path) == OK, "scene save failed")
	var reopened := (load(scene_path) as PackedScene).instantiate()
	var reopened_a := reopened.get_node("A") as EmberVoxelProp
	check(reopened_a.model_id == unique_id and reopened_a.scene_file_path == a.scene_file_path, "save/reopen lost independent source/prefab")
	check(reopened_a.get_node_or_null("Mesh/AuthoredSocket") != null, "reopen lost authored child")
	check(reopened_a.transform.is_equal_approx(pose), "reopen lost authored pose")
	check(reopened_a.get_node("Collision/Shape").shape.get_faces() == a.get_node("Collision/Shape").shape.get_faces(), "reopen lost collider")
	reopened.free()
	# Linked/shared edit updates every matching instance in this scene; independent
	# fork keeps a separate mesh and shape even when the old model is edited.
	var linked := EmberSceneAuthoring.make_duplicate(scene, b, Vector3(16, 0, 0))
	EmberSceneAuthoring.attach_duplicate(scene, b, scene, linked)
	var fork_mesh = a.get_node("Mesh").mesh
	var shared_edit = session(b, scene, undo, true)
	shared_edit.draft.voxels[4] = 0
	check(shared_edit.save(shared_edit.draft).ok, "shared save failed")
	var fresh = session(b, scene, undo, true)
	check(fresh.draft.voxels[4] == 0, "new shared session sees stale cached source")
	var cached_prefab := (load(prefab_path) as PackedScene).instantiate()
	check(cached_prefab.get_node("Collision/Shape").shape.get_faces() == b.get_node("Collision/Shape").shape.get_faces(), "cached prefab still has old collision")
	cached_prefab.free()
	check(b.get_node("Mesh").mesh == linked.get_node("Mesh").mesh and b.get_node("Mesh").mesh != old_mesh, "shared linked visuals not refreshed")
	check(b.get_node("Collision/Shape").shape == linked.get_node("Collision/Shape").shape and b.get_node("Collision/Shape").shape != old_shape, "shared linked collision not refreshed")
	check(a.get_node("Mesh").mesh == fork_mesh, "shared edit affected independent fork")
	undo.undo()
	check(b.get_node("Mesh").mesh == old_mesh, "shared Undo lost prior mesh")
	check(b.get_node("Collision/Shape").shape.get_faces() == old_faces, "shared Undo snapshot was mutated by cache replacement")
	var restored := ResourceLoader.load(source_path, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(restored.voxels == source.voxels, "shared Undo lost prior source voxels")
	undo.redo()
	var copy_edit = session(b, scene, undo)
	check(copy_edit.create_independent_copy(), "independent copy failed: " + copy_edit.error)
	var copy := scene.get_child(scene.get_child_count() - 1) as EmberVoxelProp
	check(copy.model_id != b.model_id and copy.scene_file_path != b.scene_file_path and copy.get_node("Mesh").mesh != b.get_node("Mesh").mesh, "independent copy still shares source/mesh")
	check(copy.get_node("Collision/Shape").shape != b.get_node("Collision/Shape").shape, "independent copy shares collider")
	# Workspace guard keeps resource AND target callback in the old session until
	# navigation is accepted; Cancel/Discard must never publish the new draft.
	var canvas := Workspace.new()
	root.add_child(canvas)
	canvas.open_object(session(a, scene, undo))
	var old_session = canvas._object_session
	canvas._resource.voxels[9] = 0
	canvas.open_object(session(b, scene, undo))
	check(canvas._object_session == old_session, "guard rebound target before user decision")
	canvas._navigation_guard._cancel_request()
	check(canvas._object_session == old_session and canvas.has_unsaved_changes(), "Cancel lost old draft")
	canvas.open_object(session(b, scene, undo))
	canvas._navigation_guard._custom_action("discard")
	check(canvas._object_session != old_session and not canvas.has_unsaved_changes(), "Discard navigation failed")
	canvas.open_object(session(b, scene, undo, true))
	canvas._resource.voxels[10] = 0
	canvas.open_object(session(linked, scene, undo))
	canvas._navigation_guard._save_and_continue()
	check(canvas._object_session._target.get_ref() == linked and canvas._resource.voxels[10] == 0, "Save navigation did not refresh incoming shared source/target")
	check(not canvas.has_unsaved_changes(), "incoming object inherited outgoing dirty state")
	var bad = session(b, scene, undo)
	var before_failed_mesh = b.get_node("Mesh").mesh
	var before_failed_shape = b.get_node("Collision/Shape").shape
	var before_failed_hash := FileAccess.get_sha256(source_path)
	bad.draft.voxels[7] = 0
	bad.prefab_directory = source_path
	check(not bad.save(bad.draft).ok, "invalid destination accepted save")
	check(FileAccess.get_sha256(source_path) == before_failed_hash and b.get_node("Mesh").mesh == before_failed_mesh and b.get_node("Collision/Shape").shape == before_failed_shape, "failed destination partially mutated source/instance")
	bad = session(b, scene, undo)
	bad.draft.voxels[8] = 0
	bad._source.palette[1] = Color.RED
	check(not bad.save(bad.draft).ok, "stale external source accepted save")
	bad._source.palette[1] = bad._baseline.palette[1]
	bad = session(b, scene, undo)
	bad.draft.surface_fill_levels = PackedInt32Array([1])
	check(not bad.save(bad.draft).ok, "unsupported water fill published")
	bad = session(b, scene, undo)
	bad.draft.voxels.fill(0)
	check(bad.save(bad.draft).ok, "empty prefab cannot be saved")
	var doomed := EmberSceneAuthoring.make_duplicate(scene, b, Vector3.ZERO)
	EmberSceneAuthoring.attach_duplicate(scene, b, scene, doomed)
	var doomed_edit = session(doomed, scene, undo)
	doomed_edit.draft.voxels[5] = 0
	doomed.free()
	check(not doomed_edit.save(doomed_edit.draft).ok, "freed target accepted save")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for frame in 45:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := fixture.path_join("object-canvas.png")
		root.get_texture().get_image().save_png(capture)
		print("OBJECT_CANVAS_CAPTURE ", ProjectSettings.globalize_path(capture))
	canvas.free()
	var pier := (load("res://scenes/test_pier.tscn") as PackedScene).instantiate()
	var placements := {}
	for prop_name in ["CargoA", "CargoB", "CargoC", "BarrelA", "BarrelB"]:
		var placement: String = pier.get_node("Map/Props/" + prop_name).placement_id
		check(not placement.is_empty() and not placements.has(placement), "pier placement missing/duplicate: " + prop_name)
		placements[placement] = true
	var barrel_session := Session.new()
	check(barrel_session.open(pier.get_node("Map/Props/BarrelA"), pier, undo), "native pier barrel cannot open: " + barrel_session.error)
	var legacy_session := Session.new()
	var legacy_ok := legacy_session.open(pier.get_node("Map/Props/CargoA"), pier, undo)
	print("PIER_CARGO_PREFLIGHT ", "PASS" if legacy_ok else legacy_session.error)
	check(legacy_ok or not legacy_session.error.is_empty(), "legacy refusal has no explanation")
	pier.free()
	undo.clear_history()
	undo.free()
	scene.free()
	for message in errors:
		push_error(message)
	print("test_voxel_object_canvas: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size(), " errors")
	quit(0 if errors.is_empty() else 1)
