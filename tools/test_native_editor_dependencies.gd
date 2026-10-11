extends SceneTree
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
const Refresh = preload("res://addons/ember_import/ember_voxel_scene_refresh.gd")
const Selector = preload("res://addons/ember_import/ember_world_surface_selector.gd")
const Store = preload("res://addons/ember_import/ember_voxel_model_store.gd")
const Report = preload("res://addons/ember_import/ember_content_migration_report.gd")
const Dashboard = preload("res://addons/ember_import/ember_content_migration_dashboard.gd")
const Shelf = preload("res://addons/ember_import/ember_voxel_object_library_panel.gd")
const MODEL := "native_editor_fixture"
const RETIRED := "retired_editor_fixture"
var _directory := ""
var _poison := ""
var _errors: Array[String] = []

func _init() -> void:
	var setup := preload("res://tools/fixtures/ember_native_editor_test_fixture.gd").prepare(self)
	_directory = setup.directory
	if setup.refused:
		quit.call_deferred(2)
		return
	_run.call_deferred()

func _check(ok: bool, message: String) -> bool:
	if not ok: _errors.append(message)
	return ok

func _run() -> void:
	var source: EmberVoxelModelResource = Shapes.build("block", Vector3i(16, 16, 16), 16, Color.BROWN, MODEL, "Editor fixture").source
	var ghost := source.duplicate_model()
	ghost.model_id = RETIRED
	var pack := _directory.path_join("poison-legacy")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pack.path_join("voxels/models")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pack.path_join("maps")))
	_poison = pack.path_join("voxels/models/%s.json" % RETIRED)
	var file := FileAccess.open(_poison, FileAccess.WRITE)
	file.store_string(JSON.stringify(ghost.to_definition()))
	file.close()
	var poison_hash := FileAccess.get_sha256(_poison)
	var map_json := pack.path_join("maps/editor_fixture_map.json")
	file = FileAccess.open(map_json, FileAccess.WRITE)
	file.store_string('{"width":375,"height":257,"ground_z":[7]}')
	file.close()
	var map_hash := FileAccess.get_sha256(map_json)
	ProjectSettings.set_setting("ember/pack_path", ProjectSettings.globalize_path(pack))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EmberVoxelCatalog.NATIVE_DIR))
	var source_path := EmberVoxelCatalog.native_path(MODEL)
	_check(ResourceSaver.save(source, source_path) == OK, "native fixture save failed")
	EmberVoxelPrefab.begin_import()
	var packed := EmberVoxelPrefab.prepare_resource(source)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EmberVoxelPrefab.PREFAB_DIR))
	_check(ResourceSaver.save(packed, EmberVoxelPrefab.prefab_path(MODEL)) == OK, "native fixture prefab save failed")
	var scene := Node3D.new()
	var prop := packed.instantiate() as EmberVoxelProp
	scene.add_child(prop)
	var undo := UndoRedo.new()
	var edit := Session.new()
	if _check(edit.open(prop, scene, undo, true), "native object open failed: " + edit.error):
		var before := FileAccess.get_sha256(source_path)
		var cancelled := edit.draft.duplicate_model()
		cancelled.palette[1] = Color.RED
		var reopened := Session.new()
		_check(reopened.open(prop, scene, undo, true) and FileAccess.get_sha256(source_path) == before and reopened.draft.palette[1] == Color.BROWN, "discarded detached draft changed source")
		var changed := edit.draft.duplicate_model()
		changed.palette[1] = Color.CORNFLOWER_BLUE
		var saved: Dictionary = edit.save(changed)
		if _check(saved.get("ok", false), "native save failed: " + str(saved)):
			_check(EmberVoxelCatalog.native_resource(MODEL).palette[1] == Color.CORNFLOWER_BLUE, "native save/reopen lost palette")
			undo.undo()
			_check(EmberVoxelCatalog.native_resource(MODEL).palette[1] == Color.BROWN, "native Undo lost baseline")
			undo.redo()
			_check(EmberVoxelCatalog.native_resource(MODEL).palette[1] == Color.CORNFLOWER_BLUE, "native Redo lost change")
	var missing := EmberVoxelPrefab.prepare_resource(ghost).instantiate() as EmberVoxelProp
	scene.add_child(missing)
	var missing_before := missing.get_node("Mesh") as MeshInstance3D
	var ghost_session := Session.new()
	_check(not ghost_session.open(missing, scene, undo, true), "object editor imported retired JSON implicitly")
	_check(missing.get_node("Mesh") == missing_before and not FileAccess.file_exists(EmberVoxelCatalog.native_path(RETIRED)), "missing native source changed ready object")
	_check(Store.owner(RETIRED).is_empty(), "normal Store owner reads retired JSON")
	var refresh := Refresh.new()
	_check(not refresh.rebuild_catalog_model(RETIRED, scene, undo).get("ok", false), "rebuild imported retired JSON implicitly")
	var map := EmberMapLoader.new()
	map.map_id = "editor_fixture_map"
	map.hydrate_legacy_regions = true
	map.visual_surface = source
	var selector := Selector.new()
	var grid: Dictionary = selector._surface_grid_for_map(map)
	_check(grid.get("width") == 1 and grid.get("depth") == 1, "selection dimensions came from old map JSON")
	map.visual_surface = null
	_check(selector._surface_grid_for_map(map).is_empty(), "missing Surface imported old map geometry")
	map.free()
	selector = null
	var report := Report.build()
	_check(int(report.totals.legacy_remaining) == 0, "native diagnostics enumerate retired JSON")
	for entry in report.domains.voxel.entries:
		_check(str(entry.id) != RETIRED and str(entry.owner) == "native", "diagnostics revived retired model")
	var dashboard := Dashboard.new()
	root.add_child(dashboard)
	dashboard.set_report(report)
	for name in ["PreflightVoxelMigrationBatch", "MigrateVoxelBatch", "ShowSandboxMigrationBatch", "ShowFanTownReadyMigrationBatch"]:
		_check(dashboard.find_child(name, true, false) == null, "dashboard retained legacy control: " + name)
	dashboard.free()
	var shelf := Shelf.new()
	shelf.defer_initial_refresh = true
	root.add_child(shelf)
	var menu := (shelf.find_child("VoxelObjectLibraryMore", true, false) as MenuButton).get_popup()
	_check(menu.get_item_index(1) == -1 and not shelf.has_signal("migrate_requested"), "shelf retained legacy import")
	shelf.free()
	ProjectSettings.set_setting("ember/pack_path", ProjectSettings.globalize_path(_directory.path_join("absent-pack")))
	var detached := Session.new()
	_check(detached.open(prop, scene, undo, true), "native object open requires JOI")
	_check(refresh.rebuild_catalog_model(MODEL, scene, undo).get("ok", false), "native rebuild requires JOI")
	_check(FileAccess.get_sha256(_poison) == poison_hash and FileAccess.get_sha256(map_json) == map_hash, "editor changed frozen JSON")
	undo.clear_history()
	undo.free()
	scene.free()
	if not _errors.is_empty():
		printerr("FAIL native editor dependencies: ", "; ".join(_errors))
		quit(1)
		return
	print("PASS native editor dependencies; open/save/discard/Undo/Redo/rebuild/selection/report/UI with poison and absent JOI")
	quit(0)
