@tool
extends EditorPlugin
## Opt-in only in an isolated ember-canvas-smoke-* project with its own user://.
const Queue := preload("res://addons/ember_import/ember_editor_filesystem.gd")
const Store := preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Session := preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Workspace := preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
var errors: Array[String] = []

func _enter_tree() -> void:
	print("EDITOR_FILESYSTEM fixture activated")
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func settle() -> bool:
	var deadline := Time.get_ticks_msec() + 60000
	var fs := EditorInterface.get_resource_filesystem()
	while Time.get_ticks_msec() < deadline:
		if not fs.is_scanning() and not fs.is_importing() and Queue.diagnostics().pending == 0:
			return true
		await get_tree().process_frame
	check(false, "filesystem did not settle within 60 seconds")
	return false

func check_party_scripts() -> void:
	for path in ["res://scripts/ember_party_state.gd", "res://scripts/ember_explore_state.gd", "res://tools/test_party_progression.gd", "res://tools/test_party_save_v2.gd"]:
		var script := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Script
		# Non-tool scripts cannot instantiate in an editor even when valid.
		check(script != null and script.reload(true) == OK, "editor could not parse " + path)

func _run() -> void:
	print("EDITOR_FILESYSTEM startup")
	if not ProjectSettings.globalize_path("res://").contains("ember-canvas-smoke-"):
		push_error("Filesystem fixture is allowed only in a disposable project")
		return
	for frame in 60:
		await get_tree().process_frame
	if not await settle():
		get_tree().quit(1)
		return
	check_party_scripts()
	print("EDITOR_FILESYSTEM party scripts parsed")
	var source := EmberVoxelModelResource.new()
	source.model_id = "filesystem_fixture"
	source.display_name = "Filesystem fixture"
	source.voxels_per_block = 16
	source.size_blocks = Vector3i.ONE
	source.height_voxels = 2
	source.palette = PackedColorArray([Color.TRANSPARENT, Color("98622d")])
	source.voxels.resize(512)
	source.voxels.fill(1)
	var prepared := EmberVoxelPrefab.prepare_resource(source)
	check(Store.install_prepared_asset(source, prepared, "res://content/voxel_models/filesystem_fixture.tres", "res://prefabs/voxels/filesystem_fixture.tscn").ok, "fixture source install failed")
	var initial := Node3D.new()
	initial.name = "FilesystemFixture"
	var published := ResourceLoader.load("res://prefabs/voxels/filesystem_fixture.tscn") as PackedScene
	var prop := published.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as EmberVoxelProp
	initial.add_child(prop)
	prop.name = "Probe"
	prop.owner = initial
	prop.placement_id = "filesystem_probe"
	var packed := PackedScene.new()
	check(packed.pack(initial) == OK, "fixture scene pack")
	var scene_path := "res://scenes/filesystem_fixture_%d.tscn" % OS.get_process_id()
	check(ResourceSaver.save(packed, scene_path) == OK, "fixture scene save")
	initial.free()
	Queue.request()
	await settle()
	EditorInterface.open_scene_from_path(scene_path)
	for frame in 30:
		await get_tree().process_frame
	var scene := EditorInterface.get_edited_scene_root()
	if scene == null or scene.scene_file_path != scene_path:
		push_error("fixture scene did not open")
		get_tree().quit(1)
		return
	prop = scene.get_node("Probe") as EmberVoxelProp
	var old_id := prop.model_id
	var edit := Session.new()
	check(edit.open(prop, scene, get_undo_redo()), "session open " + edit.error)
	var canvas := Workspace.new()
	EditorInterface.get_base_control().add_child(canvas)
	canvas.setup(get_editor_interface(), get_undo_redo())
	canvas.open_object(edit)
	edit.draft.voxels[0] = 0
	var before := int(Queue.diagnostics().scans)
	check(canvas.save_changes(), "Canvas save " + edit.error)
	var new_id := prop.model_id
	for index in 8:
		Queue.request()
	await settle()
	check(int(Queue.diagnostics().scans) == before + 1, "Canvas/burst did not share one scan")
	check(new_id != old_id, "Canvas did not fork source")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	check(prop.model_id == old_id, "Undo source")
	history.redo()
	check(prop.model_id == new_id, "Redo source")
	await settle()
	check_party_scripts()
	check(EditorInterface.save_scene() == OK, "editor scene save")
	var reopened: Node = ResourceLoader.load(scene.scene_file_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	check(reopened.get_node("Probe").model_id == new_id, "saved scene reopen")
	reopened.free()
	var discarded := Session.new()
	check(discarded.open(prop, scene, get_undo_redo()), "reopen session")
	discarded.draft.voxels[1] = 0
	check(discarded._source.voxels[1] == 1, "discard draft mutated source")
	canvas.free()
	for frame in 120:
		await get_tree().process_frame
	await settle()
	for message in errors:
		push_error(message)
	print("editor_test_filesystem: ", "PASS" if errors.is_empty() else "FAIL", " ", Queue.diagnostics())
	if errors.is_empty():
		# Notify only EditorNode, not the whole root: propagating close while
		# its child list is being traversed can tear down plugins mid-iteration.
		EditorInterface.get_base_control().get_parent().notification.call_deferred(NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		get_tree().quit(1)
