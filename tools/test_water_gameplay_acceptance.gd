extends SceneTree
## Headless contract for the W04 water gameplay acceptance gate.

const Launcher := preload("res://tools/water_gameplay_acceptance.gd")
const ShoreSelect := preload("res://tools/water_gameplay_acceptance_shore.gd")
const SurfaceMesher := preload("res://scripts/ember_voxel_surface_mesher.gd")
const REVIEW2_PATH := "res://art/water/presets/water-lab-user-saved-review2-mix-2026-09-15.json"
const REVIEW2_SHA256 := "EB5890D677DA1192D53D540A6DAFD492CD014DCCCAB3E26B6B030B72CEE909B5"
const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"
const PIER_SCENE := "res://scenes/test_pier.tscn"
const SURFACE_PATH := "res://content/world_surfaces/agent_sandbox_surface.tres"

var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)


func _run() -> void:
	_test_modes()
	_test_canonical_sandbox_surface()
	_test_shore_selection()
	_test_authored_fixtures_untouched()
	_test_storage_root()
	_test_review2_hash()
	_test_pier_fixture()
	_test_launcher_source_contract()
	for error in errors:
		push_error(error)
	print(
		"test_water_gameplay_acceptance: ",
		"PASS" if errors.is_empty() else "FAIL",
		" · ",
		errors.size(),
		" errors"
	)
	quit(0 if errors.is_empty() else 1)


func _test_modes() -> void:
	var shore: Dictionary = Launcher.parse_launch(PackedStringArray())
	_check(bool(shore.get("ok", false)) and str(shore.get("mode", "")) == "shore", "empty args should select shore")
	var named: Dictionary = Launcher.parse_launch(PackedStringArray(["shore"]))
	_check(bool(named.get("ok", false)) and str(named.get("mode", "")) == "shore", "shore mode was not recognized")
	var pier: Dictionary = Launcher.parse_launch(PackedStringArray(["pier"]))
	_check(bool(pier.get("ok", false)) and str(pier.get("mode", "")) == "pier", "pier mode was not recognized")
	var mixed: Dictionary = Launcher.parse_launch(PackedStringArray(["pier", "qa-capture"]))
	_check(
		bool(mixed.get("ok", false))
		and str(mixed.get("mode", "")) == "pier"
		and bool(mixed.get("qa_capture", false)),
		"pier + qa-capture should stay pier"
	)
	var unknown: Dictionary = Launcher.parse_launch(PackedStringArray(["lake"]))
	_check(not bool(unknown.get("ok", false)), "unknown mode was accepted")
	_check(str(unknown.get("mode", "")) == "lake", "unknown mode did not report the rejected value")


func _test_canonical_sandbox_surface() -> void:
	_check(
		ShoreSelect.canonical_surface_path() == SURFACE_PATH,
		"helper canonical Surface path drifted"
	)
	var packed := load(SANDBOX_SCENE) as PackedScene
	_check(packed != null, "agent_sandbox.tscn could not be loaded")
	if packed == null:
		return
	var scene := packed.instantiate()
	var map := scene.get_node_or_null("Map") as EmberMapLoader
	_check(map != null, "agent_sandbox lost Map")
	if map != null:
		_check(map.use_visual_surface_physics, "agent_sandbox is not using visual Surface physics")
		var surface := map.visual_surface
		_check(
			surface != null and surface.resource_path == SURFACE_PATH,
			"agent_sandbox does not reference the canonical Surface"
		)
		_check(
			scene.get_node_or_null("Map/Terrain/TimberPier") == null,
			"agent_sandbox unexpectedly contains TimberPier"
		)
	scene.free()


func _test_shore_selection() -> void:
	var surface_path := ProjectSettings.globalize_path(SURFACE_PATH)
	var before := FileAccess.get_sha256(surface_path)
	var surface := load(SURFACE_PATH) as EmberVoxelModelResource
	_check(surface != null, "canonical agent_sandbox Surface is missing")
	if surface == null:
		return
	var first: Dictionary = ShoreSelect.select_shore_spawn(surface)
	var second: Dictionary = ShoreSelect.select_shore_spawn(surface)
	_check(bool(first.get("ok", false)), ShoreSelect.format_failure(first))
	if not bool(first.get("ok", false)):
		return
	_check(
		first.get("wet_cell", Vector2i.ZERO) == second.get("wet_cell", Vector2i.ONE),
		"shore selection is not deterministic"
	)
	_check(
		first.get("inland_cell", Vector2i.ZERO) == second.get("inland_cell", Vector2i.ONE),
		"inland spawn is not deterministic"
	)
	var wet_cell: Vector2i = first.get("wet_cell", Vector2i.ZERO)
	var dry_cell: Vector2i = first.get("dry_cell", Vector2i.ZERO)
	var inland_cell: Vector2i = first.get("inland_cell", Vector2i.ZERO)
	_check(int(first.get("direction_code", 0)) > 0, "selected shoreline has no direction code")
	_check(int(first.get("wet_water_height", -1)) >= 0, "selected shoreline height is not wet")
	_check(SurfaceMesher.water_height_at(surface, wet_cell) >= 0, "selected candidate is not wet")
	_check(SurfaceMesher.water_height_at(surface, dry_cell) < 0, "immediate shoreline neighbor is not dry")
	_check(SurfaceMesher.solid_height_at(surface, inland_cell) >= 0, "inland cell has no solid physical height")
	_check(SurfaceMesher.water_height_at(surface, inland_cell) < 0, "inland spawn is still wet")
	var after := FileAccess.get_sha256(surface_path)
	_check(before == after, "shore helper mutated agent_sandbox_surface.tres")


func _test_authored_fixtures_untouched() -> void:
	var sandbox_before := FileAccess.get_sha256(ProjectSettings.globalize_path(SANDBOX_SCENE))
	var pier_before := FileAccess.get_sha256(ProjectSettings.globalize_path(PIER_SCENE))
	var surface := load(SURFACE_PATH) as EmberVoxelModelResource
	if surface != null:
		ShoreSelect.select_shore_spawn(surface)
	_check(
		sandbox_before == FileAccess.get_sha256(ProjectSettings.globalize_path(SANDBOX_SCENE)),
		"helper changed agent_sandbox.tscn"
	)
	_check(
		pier_before == FileAccess.get_sha256(ProjectSettings.globalize_path(PIER_SCENE)),
		"helper changed test_pier.tscn"
	)


func _test_storage_root() -> void:
	var isolated := Launcher.make_isolated_storage_root(4242, 99)
	_check(
		isolated.begins_with("user://ember-tests/water-gameplay-acceptance-"),
		"isolated storage root escaped user://ember-tests"
	)
	_check(isolated.contains("4242"), "isolated storage root dropped process id")
	var progress := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	_check(progress != null, "EmberExploreProgress autoload is missing")
	if progress == null:
		return
	var original_root := progress.storage_root
	var original_legacy := progress.legacy_storage_root
	var production := _hash_tree(EmberExploreState.DEFAULT_STORAGE_ROOT)
	var production_legacy := _hash_tree(EmberExploreState.DEFAULT_LEGACY_STORAGE_ROOT)
	Launcher.apply_isolated_storage(progress, isolated)
	_check(progress.storage_root == isolated, "Progress storage_root was not redirected")
	_check(
		progress.legacy_storage_root.begins_with(isolated),
		"Progress legacy storage_root was not redirected"
	)
	_check(
		str(progress.get_meta("test_pier_storage_root", "")) == isolated,
		"test_pier_storage_root meta was not set"
	)
	progress.storage_root = original_root
	progress.legacy_storage_root = original_legacy
	_check(
		_hash_tree(EmberExploreState.DEFAULT_STORAGE_ROOT) == production,
		"isolation probe wrote production v2 saves"
	)
	_check(
		_hash_tree(EmberExploreState.DEFAULT_LEGACY_STORAGE_ROOT) == production_legacy,
		"isolation probe wrote production legacy saves"
	)


func _test_review2_hash() -> void:
	var path := ProjectSettings.globalize_path(REVIEW2_PATH)
	_check(FileAccess.file_exists(path), "protected Review2 JSON is missing")
	if not FileAccess.file_exists(path):
		return
	var digest := FileAccess.get_sha256(path).to_upper()
	_check(digest == REVIEW2_SHA256, "protected Review2 JSON hash changed: %s" % digest)


func _test_pier_fixture() -> void:
	var packed := load(PIER_SCENE) as PackedScene
	_check(packed != null, "test_pier.tscn could not be loaded")
	if packed == null:
		return
	var scene := packed.instantiate()
	_check(
		scene.get_node_or_null("Map/Terrain/TimberPier") != null,
		"test_pier lost authored TimberPier"
	)
	_check(
		scene.get_node_or_null("Map/Terrain/BayWater") != null,
		"test_pier lost authored BayWater"
	)
	_check(
		str(scene.scene_file_path) == PIER_SCENE,
		"test_pier instance is not the authored scene"
	)
	scene.free()
	var sandbox := (load(SANDBOX_SCENE) as PackedScene).instantiate()
	_check(
		sandbox.get_node_or_null("Map/Terrain/TimberPier") == null
		and sandbox.get_node_or_null("Map/Terrain/BayWater") == null,
		"TimberPier/BayWater were copied into agent_sandbox"
	)
	sandbox.free()


func _test_launcher_source_contract() -> void:
	var source := FileAccess.get_file_as_string("res://tools/water_gameplay_acceptance.gd")
	_check(source.contains("res://scenes/agent_sandbox.tscn"), "launcher no longer loads agent_sandbox")
	_check(source.contains("res://scenes/test_pier.tscn"), "launcher no longer loads test_pier")
	_check(
		not source.contains("ResourceSaver.save"),
		"launcher contains ResourceSaver.save"
	)
	_check(
		source.contains("user://ember-tests/water-gameplay-acceptance-"),
		"launcher does not isolate saves under user://ember-tests"
	)


func _hash_tree(path: String) -> Dictionary:
	var result := {}
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return result
	for file in DirAccess.get_files_at(absolute):
		result[file] = FileAccess.get_sha256(absolute.path_join(file))
	for directory in DirAccess.get_directories_at(absolute):
		result[directory] = _hash_tree(path.path_join(directory))
	return result
