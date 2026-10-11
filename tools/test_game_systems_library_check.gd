extends SceneTree
## Saved diagnostics must not consume dirty editor cache, mutate files or choose an ID alias.
const Service = preload("res://addons/ember_import/ember_game_systems_check_service.gd")
const Store = preload("res://addons/ember_import/ember_game_systems_store.gd")
const Workspace = preload("res://addons/ember_import/ember_graph_workspace.gd")
const Maps = preload("res://tools/fixtures/ember_exploration_test_fixture.gd")
var _errors: Array[String] = []
var _paths: Array[String] = []
var _route := ""

func _init() -> void:
	var path := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	if path != OS.get_environment("EMBER_GAME_SYSTEMS_TEST_ROOT") or not path.contains("ember-game-systems-") or DirAccess.dir_exists_absolute("res://.git"):
		printerr("FAIL library check gate refused non-disposable project")
		quit.call_deferred(2)
		return
	root.size = Vector2i(1280, 720)
	Maps.prepare(self, "user://library-check-%d" % OS.get_process_id())
	_run.call_deferred()

func _save(resource: Resource, path: String) -> void:
	_paths.append(path)
	_check(ResourceSaver.save(resource, path) == OK, "could not create diagnostic fixture")

func _run() -> void:
	var valid := Store.blank("status", "check_valid", "Сохранённый корректный статус")
	valid.description = "Проверка сохранённой версии."
	var valid_path := Store.path_for("status", "check_valid")
	_save(valid, valid_path)
	var cached := ResourceLoader.load(valid_path)
	cached.default_duration = 0
	var duplicate := Store.clone(valid)
	duplicate.status_id = "wet"
	_save(duplicate, "res://content/combat/statuses/check_duplicate_wet.tres")
	var effect := Store.blank("effect", "check_missing_status", "Потерянный статус")
	effect.description = "Fixture"
	effect.status_id = "absent_check_status"
	_save(effect, Store.path_for("effect", "check_missing_status"))
	var profile := Store.blank("ai", "check_invalid_enum", "Неверный вариант ИИ")
	profile.description = "Fixture"
	profile.target_priority = 99
	_save(profile, Store.path_for("ai", "check_invalid_enum"))
	var item := Store.blank("item", "check_item", "Несовпадающие данные")
	item.definition.id = "different_envelope_id"
	_save(item, Store.path_for("item", "check_item"))
	var wrong := Resource.new()
	_save(wrong, "res://content/combat/effects/check_wrong_type.tres")
	var wrong_step := Store.clone(Store.Catalog.Actions.resource("douse"))
	wrong_step.action_id = "check_wrong_step"
	var wrong_steps: Array[Resource] = [Resource.new()]
	wrong_step.effect_steps = wrong_steps
	_save(wrong_step, Store.path_for("action", "check_wrong_step"))
	var missing_path := "res://content/combat/effects/check_missing_file.tres"
	var file := FileAccess.open(missing_path, FileAccess.WRITE)
	file.store_string('[gd_resource type="Resource" load_steps=2 format=3]\n[ext_resource type="Resource" path="res://content/combat/statuses/absent_file.tres" id="1"]\n[resource]\nresource_name = "missing"\nresource_local_to_scene = false\n')
	file.close()
	_paths.append(missing_path)
	var hashes := {}
	for path in _paths: hashes[path] = FileAccess.get_sha256(path)
	var service := Service.new()
	_check(service.start().get("ok", false), "check process did not start")
	_check(not service.start().get("ok", true), "duplicate check process allowed")
	var report := {}
	for attempt in 300:
		await create_timer(0.1).timeout
		report = service.poll()
		if not report.is_empty(): break
	_check(report.get("ok", false), "report absent/failed: " + str(report))
	if report.get("ok", false):
		_check(_has(report, "duplicate_id", "res://content/combat/statuses/wet.tres") and _has(report, "duplicate_id", "res://content/combat/statuses/check_duplicate_wet.tres"), "duplicate IDs collapsed or wrong file reported")
		_check(_has(report, "missing_id", Store.path_for("effect", "check_missing_status")), "missing ID not reported")
		_check(_has(report, "enum_value", Store.path_for("ai", "check_invalid_enum")), "unsupported native enum not reported")
		_check(_has(report, "envelope_id", Store.path_for("item", "check_item")), "item envelope mismatch not reported")
		_check(_has(report, "wrong_type", "res://content/combat/effects/check_wrong_type.tres"), "wrong Resource type not reported")
		_check(_has(report, "wrong_effect_type", Store.path_for("action", "check_wrong_step")), "wrong nested effect type crashed or disappeared")
		_check(_has(report, "missing_dependency", missing_path), "missing external file not reported before load")
		_check(not _has(report, "validation", valid_path), "unsaved cached status entered saved report")
		_check(cached.default_duration == 0, "checker overwrote live Resource cache")
		for path in hashes: _check(FileAccess.get_sha256(path) == hashes[path], "checker changed file: " + path)
		# The report keeps its findings; remove malformed fixtures before opening
		# the older browser, which is not the saved-data checker under test.
		for path in _paths:
			if path not in [valid_path, "res://content/combat/statuses/check_duplicate_wet.tres"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		await _test_ui(report)
	service.cancel()
	for path in _paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if _errors.is_empty(): print("PASS game systems library check: fresh saved process, raw duplicate identities/exact paths, missing ID/file/type/enums/settings, no cache/file/draft mutation, report search/navigation/dirty guard")
	else: printerr("FAIL library check: ", "; ".join(_errors))
	quit(0 if _errors.is_empty() else 1)

func _test_ui(report: Dictionary) -> void:
	var workspace := Workspace.new()
	workspace.configure(null, null)
	root.add_child(workspace)
	workspace.system_resource_requested.connect(func(path: String) -> void: _route = path)
	workspace.open_resource("systems", "systems_library")
	var hub := workspace.get("_game_systems_workspace") as Control
	hub.call("_open_library_check")
	var panel := hub.get("_check_panel") as ConfirmationDialog
	panel.get("_service").cancel()
	panel.set("_report", report)
	panel.set("_issues", report.issues)
	panel.call("_render")
	var search := panel.find_child("LibraryCheckSearch", true, false) as LineEdit
	search.text = "check_duplicate_wet"
	search.text_changed.emit(search.text)
	var tree := panel.find_child("LibraryCheckIssues", true, false) as Tree
	var row := tree.get_root().get_first_child()
	_check(row != null, "report search lost duplicate source")
	if row != null:
		row.select(0)
		panel.call("_select_issue")
		panel.call("_open_issue")
		_check(_route == "res://content/combat/statuses/check_duplicate_wet.tres", "issue route selected another record with same ID")
	hub.call("select_module", "status", "wet")
	hub.call("begin_edit")
	hub.get("_session").set_value("display_name", "Несохранённый черновик")
	_route = ""
	hub.call("_open_checked_record", {"path": Store.path_for("status", "check_valid")})
	_check(_route.is_empty() and hub.has_unsaved_changes(), "issue navigation discarded draft")
	workspace.free()
	await process_frame

func _has(report: Dictionary, code: String, path: String) -> bool:
	for issue in report.get("issues", []):
		if str(issue.code) == code and str(issue.path) == path: return true
	return false

func _check(condition: bool, message: String) -> void:
	if not condition: _errors.append(message)
